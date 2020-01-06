-- Automated test for [unitdata.lua] library.

local helper = wesnoth.require "lua/helper.lua"

-- Returns a new unit (WML table) for further testing.
local function newunit()
	local unit = wesnoth.create_unit { type = "Efraim_god", random_traits = "no" }

	-- Unit must be on the map for tests, otherwise wesnoth.get_unit() won't find it by ID.
	unit:to_map(1, 1)

	return unit.__cfg
end

-- Throw an exception if expected_wml isn't equal to actual_wml.
local function assert_wml_equals(expected_wml, actual_wml)
	local expected = wml.tostring(expected_wml)
	local actual = wml.tostring(actual_wml)

	assert(expected == actual, "WML table is different from expected:\n" ..
		"Expected: " .. expected .. "\n" .. "Actual:   " .. actual)
end

-- Call iterator-returning function (e.g. "advancements") on unit (either WML table or ID)
-- and compare the results with a known correct result (provided as array).
local function test_iterator(unit, api_function_name, expected_array)
	-- When error happens, this string will be shown to tell which function failed.
	local where = "loti.unit." .. api_function_name .. "()"

	-- Obtain the iterator and check it.
	local iterator = loti.unit[api_function_name](unit)
	assert(type(iterator) == "function", where .. " returned non-iterator")

	-- Retrieve all results.
	local obtained_array = {}
	for _, elem in iterator do
		table.insert(obtained_array, elem)
	end

	if api_function_name == "effects" or api_function_name == "effect_containers" then
		-- API of effects() doesn't guarantee the order of results,
		-- and this order is different in WML and Lua implementations (which is OK).
		-- Therefore the testsuite shouldn't check the order of effects(), only their presence.
		table.sort(obtained_array, function(a, b)
			if(type(a) == 'table') then a = wml.tostring(a) end
			if(type(b) == 'table') then b = wml.tostring(b) end

			return a < b
		end)
	end

	assert(#expected_array == #obtained_array,
		where .. " returned " .. #obtained_array .. " elements (expected: " .. #expected_array .. ")")

	for idx in ipairs(expected_array) do
		local expected = expected_array[idx]
		local obtained = obtained_array[idx]

		if type(expected) == "function" then
			-- Callback to check the results
			expected(obtained)
		else
			-- Exact value of the result, compare directly.
			assert_wml_equals(expected, obtained)
		end
	end
end

-- Check the add/list sequence of functions like add_advancement().
-- Parameters:
-- unit - main test unit (first parameter to API functions), can be either WML table or unit ID.
-- iter_fn - name of iterator (e.g. "advancements"),
-- add_fn - name of add function (e.g. "add_advancement"),
-- array_of_things_to_add - array of arguments of add_fn() function (e.g. advancement names, or item number/sort).
-- expected_results - expected contents of iterator after all add_fn() calls. This is passed to test_iterator().
local function test_add_list(unit, iter_fn, add_fn, array_of_things_to_add, expected_results)
	-- Test the empty iterator. Should be valid and should provide an empty list.
	test_iterator(unit, iter_fn, {})

	-- Add the test objects (whatever they are - item WML tables, advancement IDs, doesn't matter).
	for _, add_arguments in ipairs(array_of_things_to_add) do
		loti.unit[add_fn](unit, table.unpack(add_arguments))
	end

	-- Compare current state of unit (e.g. items on unit) with array of what we just added.
	test_iterator(unit, iter_fn, expected_results)
end

-- Utility function to add trait to unit (NOT provided by unitdata API),
-- where unit can be WML table or ID. Used in the test of effects().
-- Returns new version of unit (either WML table or ID, will be the same format as input parameter)
local function add_trait(unit, trait)
	local id = unit
	local form = "id"

	if type(unit) == "table" then
		id = unit.id
		form = "wml"
	end

	local lua_unit = wesnoth.get_unit(id)
	lua_unit:add_modification("trait", trait)

	if form == "wml" then
		return lua_unit.__cfg
	end

	return lua_unit.id
end

-- Prepare array of tests.
local tests = {}

-- Functions should equally accept both WML table and ID (string) of the unit.
for unit_form, get_unit in pairs({
	['WML table'] = newunit,
	['unit ID'] = function() return newunit().id end
}) do
	local subtest_name = ' (on ' .. unit_form .. ')'

	tests['add/list advancements' .. subtest_name] = function()
		test_add_list(get_unit(), "advancements", "add_advancement",
			-- Note: all these advancements must be valid for the test unit
			-- (in this case, Efraim_god),
			-- because add_advancement() won't add unknown advancements.
			{ { "fireball1_incineration" }, { "LotF1" }, { "resist_fire1" } },

			-- Check each returned value with an evaluation callback.
			{
				function(result)
					assert(result.id == "fireball1_incineration")
					assert(result.strict_amla)
					assert(result.require_amla == "fireball")
				end,
				function(result) assert(result.id == "LotF1") end,
				function(result) assert(result.id == "resist_fire1") end,
			}
		)
	end

	tests['remove/list advancements' .. subtest_name] = function()
		local unit

		-- Prepare a unit who already has some advancements
		-- (so that we can test remove_advancement() on this unit)
		local function prepare_unit()
			unit = get_unit()

			loti.unit.add_advancement(unit, "fireball1_incineration")
			loti.unit.add_advancement(unit, "LotF1")
			loti.unit.add_advancement(unit, "resist_fire1")
		end

		-- Try deleting the first advancement.
		prepare_unit()
		loti.unit.remove_advancement(unit, "fireball1_incineration")
		test_iterator(unit, "advancements", {
			function(result) assert(result.id == "LotF1") end,
			function(result) assert(result.id == "resist_fire1") end,
		})

		-- Try deleting advancement in the middle.
		prepare_unit()
		loti.unit.remove_advancement(unit, "LotF1")
		test_iterator(unit, "advancements", {
			function(result) assert(result.id == "fireball1_incineration") end,
			function(result) assert(result.id == "resist_fire1") end,
		})

		-- Try deleting the last advancement.
		prepare_unit()
		loti.unit.remove_advancement(unit, "resist_fire1")
		test_iterator(unit, "advancements", {
			function(result) assert(result.id == "fireball1_incineration") end,
			function(result) assert(result.id == "LotF1") end,
		})

		-- Try deleting the non-existent advancement.
		prepare_unit()
		loti.unit.remove_advancement(unit, "fireball")
		test_iterator(unit, "advancements", {
			function(result) assert(result.id == "fireball1_incineration") end,
			function(result) assert(result.id == "LotF1") end,
			function(result) assert(result.id == "resist_fire1") end,
		})
	end

	tests['add/list items' .. subtest_name] = function()
		test_add_list(get_unit(), "items", "add_item",
			{ { 100, "sword" }, { 327 }, { 562, "spear" }, { 535, "armour" }, { 535, "gauntlets" } },
			{
				loti.item.type[100],
				loti.item.type[327],
				function(result)
					-- Crafted weapon.
					-- Its item sort (in this case, spear) must be different from default.
					assert(result.sort == "spear")

					-- All other fields should be the same as in loti.item.type.
					result.sort = "weaponword"
					assert_wml_equals(loti.item.type[562], result)
				end,

				function(result)
					-- Crafted armour (chest).
					assert(result.sort == "armour")

					-- All other fields should be the same as in loti.item.type.
					result.sort = "armourword"
					assert_wml_equals(loti.item.type[535], result)
				end,

				function(result)
					-- Crafted non-chest armour (in this case, gauntlets).
					assert(result.sort == "gauntlets")

					-- Note: correct result should have its defence multiplied by 1/3
					-- (only chest armours get the full defence)
					result.defence = result.defence * 3
					result.sort = "armourword"
					assert_wml_equals(loti.item.type[535], result)
				end,
			}
		)
	end

	tests['list_unit_item_numbers()' .. subtest_name] = function()
		local unit = get_unit()

		loti.unit.add_item(unit, 100, "sword")
		loti.unit.add_item(unit, 327)
		loti.unit.add_item(unit, 535, "armour")
		loti.unit.add_item(unit, 535, "gauntlets")
		loti.unit.add_item(unit, 562, "spear")

		local actual = table.concat(loti.unit.list_unit_item_numbers(unit), ",")
		local expected = table.concat({ 100, 327, 535, 535, 562 }, ",")

		assert(expected == actual,
			"Result of list_unit_item_numbers (" .. actual .. ") " ..
			"is different from expected (" .. expected ..").")
	end

	tests['remove/list items' .. subtest_name] = function()
		local unit

		-- Prepare a unit who already has some items
		-- (so that we can test remove_item() on this unit)
		local function prepare_unit()
			unit = get_unit()

			loti.unit.add_item(unit, 100, "sword") -- Cunctator's sword
			loti.unit.add_item(unit, 327) -- Eidolon's Coat
			loti.unit.add_item(unit, 535, "armour")
			loti.unit.add_item(unit, 535, "gauntlets")
			loti.unit.add_item(unit, 562, "spear")
		end

		-- Correct value that should pass test_iterator() check before making any remove_item() calls.
		local original_array = {
			function(result) assert(result.number == 100 and result.sort == "sword") end,
			function(result) assert(result.number == 327 and result.sort == "cloak") end,
			function(result) assert(result.number == 535 and result.sort == "armour") end,
			function(result) assert(result.number == 535 and result.sort == "gauntlets") end,
			function(result) assert(result.number == 562 and result.sort == "spear") end,
		}

		-- Double-check that certain item (from "original_array" list, see above)
		-- is not present on the unit, and that all other items from "original_array" are present,
		-- Throw exception if this statement is incorrect.
		-- Parameter: index - index of the item in "original_array" that should have been deleted.
		-- Note: if index is false/nil, then NONE of the items are expected to be deleted.
		local function assert_item_was_deleted(index)
			local expected_array = table.pack(table.unpack(original_array)) -- Clone the original array
			if index then
				table.remove(expected_array, index)
			end

			test_iterator(unit, "items", expected_array)
		end

		-- Before we start testing remove_item(),
		-- let's double-check that "original_array" is correct.
		prepare_unit()
		test_iterator(unit, "items", original_array)

		-- Try deleting non-crafted item. Don't provide item_sort parameter (which is optional).
		prepare_unit()
		loti.unit.remove_item(unit, 100)
		assert_item_was_deleted(1)

		-- Try deleting non-crafted item, but provide item_sort parameter (which is optional).
		prepare_unit()
		loti.unit.remove_item(unit, 100, "sword")
		assert_item_was_deleted(1)

		-- Try deleting non-crafted item, but provide incorrect item_sort parameter.
		-- This shouldn't delete anything (because item with this item_sort doesn't exist).
		prepare_unit()
		loti.unit.remove_item(unit, 100, "mace")
		assert_item_was_deleted(false)

		-- Try deleting item which is not present on the unit (without item_sort).
		-- This shouldn't delete anything.
		prepare_unit()
		loti.unit.remove_item(unit, 123)
		assert_item_was_deleted(false)

		-- Try deleting item which is not present on the unit
		-- (but specify item_sort, which is the same as item_sort of one of the present items).
		-- This shouldn't delete anything.
		prepare_unit()
		loti.unit.remove_item(unit, 123, "sword")
		assert_item_was_deleted(false)

		-- Try deleting non-first item in the list (with optional item_sort)
		prepare_unit()
		loti.unit.remove_item(unit, 327, "cloak")
		assert_item_was_deleted(2)

		-- Try deleting non-first item in the list (without optional item_sort)
		prepare_unit()
		loti.unit.remove_item(unit, 327)
		assert_item_was_deleted(2)

		-- Try deleting crafted item without item_sort parameter.
		prepare_unit()
		loti.unit.remove_item(unit, 562)
		assert_item_was_deleted(5)

		-- Try deleting crafted item with item_sort parameter.
		prepare_unit()
		loti.unit.remove_item(unit, 562, "spear")
		assert_item_was_deleted(5)

		-- Try deleting crafted item, but provide incorrect item_sort parameter.
		-- This shouldn't delete anything.
		prepare_unit()
		loti.unit.remove_item(unit, 562, "thunderstick")
		assert_item_was_deleted(false)

		-- Try deleting crafted item without item_sort parameter,
		-- when there are TWO items with this item_number.
		-- Only one (the first one) should be deleted.
		prepare_unit()
		loti.unit.remove_item(unit, 535)
		assert_item_was_deleted(3)

		-- Try deleting crafted item with item_sort parameter,
		-- when there are TWO items with this item_number.
		-- Only one (the one with correct item_sort) should be deleted.
		prepare_unit()
		loti.unit.remove_item(unit, 535, "armour")
		assert_item_was_deleted(3)

		prepare_unit()
		loti.unit.remove_item(unit, 535, "gauntlets")
		assert_item_was_deleted(4)

		-- Try remove_all_items(unit) without callback
		prepare_unit()
		loti.unit.remove_all_items(unit)
		test_iterator(unit, "items", {})

		-- Try remove_all_items(unit) with callback: remove only cloaks and spears.
		prepare_unit()
		loti.unit.remove_all_items(unit, function(result)
			return result.sort == "cloak" or result.sort == "spear"
		end)
		test_iterator(unit, "items", {
			original_array[1],
			original_array[3],
			original_array[4]
		})

		-- Try remove_all_items(unit) with callback: remove only swords and items with #535.
		prepare_unit()
		loti.unit.remove_all_items(unit, function(result)
			return result.sort == "sword" or result.number == 535
		end)

		test_iterator(unit, "items", {
			original_array[2],
			original_array[5]
		})
	end

	tests['list effects' .. subtest_name] = function()
		local unit = get_unit()

		-- Empty (newly created) unit doesn't have any effects.
		-- (assuming random_traits="no" when creating the unit).
		test_iterator(unit, "effects", {})

		-- Effects (things like "absorbs(1)" or "+16 regeneration") are added to unit indirectly.
		-- This happens when unit has some items/advancements that provide effects.
		-- Furthermore, additional effects can be caused by combination of items ("item set bonus").
		-- Let's add some effect-granting traits/items/advancements to unit and then check the results.

		unit = add_trait(unit, { -- "strong" trait: +1 melee damage, +1 hp
			name = "strong",
			{ "effect", {
				apply_to = "attack",
				increase_damage = 1,
				range = "melee"
			} },
			{ "effect", {
				apply_to = "hitpoints",
				increase_total = 1
			} }
		})

		loti.unit.add_advancement(unit, "sword1") -- "Better with the sword" advancement
		loti.unit.add_item(unit, 100) -- Cunctator's sword
		loti.unit.add_item(unit, 209) -- Cunctator's Helmet
		loti.unit.add_item(unit, 249) -- Redshirt Armour
		loti.unit.add_advancement(unit, "dodge") -- "Harder to hit" advancement
		loti.unit.add_item(unit, 327) -- Eidolon's Coat
		loti.unit.add_item(unit, 535, "armour")
		loti.unit.add_item(unit, 535, "gauntlets")
		loti.unit.add_item(unit, 562, "spear")

		-- Throw an exception if "effect" (WML table) doesn't add exactly N abilities,
		-- where N is the number of elements in check_functions[] array.
		-- Otherwise call check_functions[idx] callback for each added ability,
		-- where idx is 1, 2, 3, etc.,
		-- Each callback receives two parameters:
		-- 1) name of ability tag (e.g. "leadership" or "heals"),
		-- 2) contents of ability tag (WML table)
		local function assert_added_abilities(effect, check_functions)
			assert(effect.apply_to == "new_ability",
				"Effect doesn't add any abilities: " .. wml.tostring(effect))

			local added_abilities = effect[1][2]
			assert(#added_abilities == #check_functions,
				"Effect adds " .. #added_abilities ..
				" abilities (should be " .. #check_functions .."): " .. wml.tostring(effect))

			for idx, ability_tag in ipairs(added_abilities) do
				check_functions[idx](ability_tag[1], ability_tag[2])
			end
		end

		-- Same as assert_adds_abilities(), but expects only 1 ability.
		local function assert_adds_ability(effect, check_function)
			assert_added_abilities(effect, { check_function })
		end

		-- Throw an exception if effect doesn't add the ability
		-- frail tide (15): -15% physical resistance to adjacent enemies.
		local function assert_adds_frail_tide_15(effect)
			assert_adds_ability(effect, function(tag, ability)
				assert(tag == "resistance")
				assert(ability.id == "frail tide")
				assert(ability.sub == 15)
				assert(ability.max_value == 80)
				assert(ability.cumulative)
				assert(ability.apply_to == "blade,impact,pierce")
				assert(ability.affect_enemies)
				assert(not ability.affect_allies)
				assert(not ability.affect_self)

				local filter = helper.child_array(ability, "affect_adjacent")[1]
				assert(filter.adjacent == "n,ne,se,s,sw,nw")
			end)
		end

		-- Now check values returned by loti.unit.effects(unit) here.
		-- NOTE: test_iterator() sorts the effects (alphabetically by their wml.tostring(effect)).
		test_iterator(unit, "effects", {
			-- Advancement "Better with the sword": +1 damage to "sword" attack.
			function(effect)
				assert(effect.apply_to == "attack")
				assert(effect.name == "sword")
				assert(effect.increase_damage == 1)
			end,

			-- Trait "strong": +1 to melee damage.
			function(effect)
				assert(effect.apply_to == "attack")
				assert(effect.increase_damage == 1)
				assert(effect.range == "melee")
			end,

			-- Advancement "Harder to hit": +1-2 defense on different terrains.
			function(effect)
				assert(effect.apply_to == "defense")
				assert(not effect.replace)

				local bonus = helper.child_array(effect, "defense")[1]
				assert(bonus.frozen == -2)
				assert(bonus.shallow_water == -2)
				assert(bonus.deep_water == -2)
				assert(bonus.reef == -2)
				assert(bonus.flat == -2)
				assert(bonus.castle == -1)
				assert(bonus.frozen == -2)
				assert(bonus.village == -1)
				assert(bonus.forest == -1)
				assert(bonus.cave == -2)
				assert(bonus.hills == -1)
				assert(bonus.mountains == -1)
				assert(bonus.fungus == -2)
				assert(bonus.swamp_water == -2)
				assert(bonus.sand == -2)
			end,

			-- Level-up (receiving the advancement "Better with the sword")
			-- caused unit to completely heal and get +3 max hp.
			function(effect)
				assert(effect.apply_to == "hitpoints")
				assert(effect.increase_total == 3)
				assert(effect.heal_full)
			end,

			-- Level-up (receiving the advancement "Harder to hit")
			-- caused unit to completely heal and get +3 max hp.
			function(effect)
				assert(effect.apply_to == "hitpoints")
				assert(effect.increase_total == 3)
				assert(effect.heal_full)
			end,

			-- Trait "strong": +1 to hitpoints.
			function(effect)
				assert(effect.apply_to == "hitpoints")
				assert(effect.increase_total == 1)
			end,

			-- Level-up (receiving the advancement "Better with the sword")
			-- caused Efraim (Demigod unit) to need 9% more xp for next advancement,
			-- as defined by IMPROVED_AMLA_DEFAULT_BONUSES.
			function(effect)
				assert(effect.apply_to == "max_experience")
				assert(effect.increase == '9%')
			end,

			-- Level-up (receiving the advancement "Harder to hit")
			-- caused Efraim (Demigod unit) to need 9% more xp for next advancement,
			-- as defined by IMPROVED_AMLA_DEFAULT_BONUSES.
			function(effect)
				assert(effect.apply_to == "max_experience")
				assert(effect.increase == '9%')
			end,

			-- Level-up (receiving the advancement "Better with the sword")
			-- caused Efraim (Demigod unit) to need 35 more xp for next advancement,
			-- as defined by IMPROVED_AMLA_DEFAULT_BONUSES.
			function(effect)
				assert(effect.apply_to == "max_experience")
				assert(effect.increase == 35)
			end,

			-- Level-up (receiving the advancement "Harder to hit")
			-- caused Efraim (Demigod unit) to need 35 more xp for next advancement,
			-- as defined by IMPROVED_AMLA_DEFAULT_BONUSES.
			function(effect)
				assert(effect.apply_to == "max_experience")
				assert(effect.increase == 35)
			end,

			function(effect)
				-- Redshirt Armour (item #249).
				-- Movement +1
				assert(effect.apply_to == "movement")
				assert(effect.increase == 1)
			end,

			function(effect)
				-- Cunctator's Helmet (item #209):
				-- set bonus from requires Cunctator's sword (item #100) also being present.
				-- Resistance +10 (up to a maximum of 80) when defending
				assert_adds_ability(effect, function(tag, ability)
					assert(tag == "resistance")
					assert(ability.id == "careful")
					assert(ability.add == 10)
					assert(ability.max_value == 80)
					assert(ability.affect_self)
					assert(ability.active_on == "defense")

					local filter = helper.child_array(ability, "filter_base_value")[1]
					assert(filter.less_than == 80)
				end)
			end,

			function(effect)
				-- Redshirt Armour (item #249).
				-- absorbs (1)
				assert_adds_ability(effect, function(tag, ability)
					assert(tag == "dummy")
					assert(ability.id == "absorb")
					assert(ability.value == 1)
				end)
			end,

			function(effect)
				-- Eidolon's Coat (item #327).
				-- Two abilities are added by the same [effect]: cures and heals +8.
				assert_added_abilities(effect, {
					function(tag, ability)
						-- Cures poison
						assert(tag == "heals")
						assert(ability.id == "curing")
						assert(ability.affect_allies)
						assert(not ability.affect_self)
						assert(ability.poison == "cured")
						assert(helper.child_array(ability, "affect_adjacent")[1]) -- Empty but present
					end,
					function(tag, ability)
						-- Heals +8
						assert(tag == "heals")
						assert(ability.id == "healing")
						assert(ability.affect_allies)
						assert(not ability.affect_self)
						assert(ability.poison == "slowed")
						assert(ability.value == 8)
						assert(helper.child_array(ability, "affect_adjacent")[1]) -- Empty but present
					end
				})
			end,

			function(effect)
				-- Cunctator's Helmet (item #209).
				-- Despair 15 (affects adjacent enemies)
				assert_adds_ability(effect, function(tag, ability)
					assert(tag == "leadership")
					assert(ability.id == "despair")
					assert(ability.value == -15)
					assert(ability.affect_enemies)
					assert(not ability.affect_allies)
					assert(not ability.affect_self)
					assert(not ability.cumulative)

					local filter = helper.child_array(ability, "affect_adjacent")[1]
					assert(filter.adjacent == "n,ne,se,s,sw,nw")
				end)
			end,

			function(effect)
				-- Unimpalability (item #562).
				-- frail tide (15): -15% physical resistance to adjacent enemies
				assert_adds_frail_tide_15(effect)
			end,

			function(effect)
				-- Second Unimpalability (item #562).
				-- The duplicate is caused by two Unimpalability items
				-- (each of them grants this effect).
				-- frail tide (15): -15% physical resistance to adjacent enemies
				assert_adds_frail_tide_15(effect)
			end,

			function(effect)
				-- Cunctator's sword (item #100):
				-- set bonus from requires Cunctator's Helmet (item #209) also being present.
				-- Plus 5% resistance to arcane, cold and fire.
				assert(effect.apply_to == "resistance")
				assert(effect.number_required == 209)
				assert(not effect.replace)

				local bonus = helper.child_array(effect, "resistance")[1]
				assert(bonus.arcane == -5)
				assert(bonus.cold == -5)
				assert(bonus.fire == -5)
			end,
		})
	end

	tests['list effect_containers' .. subtest_name] = function()
		local unit = get_unit()

		-- Empty (newly created) unit doesn't have any modifications.
		-- (assuming random_traits="no" when creating the unit).
		test_iterator(unit, "effect_containers", {})

		unit = add_trait(unit, {
			name = "strong",
			{ "effect", {
				apply_to = "attack",
				increase_damage = 1,
				range = "melee"
			} },
			{ "effect", {
				apply_to = "hitpoints",
				increase_total = 1
			} }
		})

		loti.unit.add_advancement(unit, "sword1") -- "Better with the sword" advancement
		loti.unit.add_item(unit, 100) -- Cunctator's sword
		loti.unit.add_item(unit, 209) -- Cunctator's Helmet
		loti.unit.add_item(unit, 249) -- Redshirt Armour
		loti.unit.add_advancement(unit, "dodge") -- "Harder to hit" advancement
		loti.unit.add_item(unit, 327) -- Eidolon's Coat
		loti.unit.add_item(unit, 535, "armour")
		loti.unit.add_item(unit, 535, "gauntlets")
		loti.unit.add_item(unit, 562, "spear")

		-- Now check values returned by loti.unit.effect_containers(unit) here.
		-- NOTE: test_iterator() sorts these containers alphabetically.
		test_iterator(unit, "effect_containers", {
			function(obj)
				assert(obj.id == "dodge")
			end,

			function(obj)
				assert(obj.id == "sword1")
			end,

			function(obj)
				assert(obj.number == 562)
				assert(obj.sort == "spear")
			end,

			function(obj)
				assert(obj.number == 535)
				assert(obj.sort == "armour")
			end,

			function(obj)
				assert(obj.number == 535)
				assert(obj.sort == "gauntlets")
			end,

			function(obj)
				assert(obj.number == 249)
				assert(obj.sort == "armour")
			end,

			function(obj)
				assert(obj.number == 209)
				assert(obj.sort == "helm")
			end,

			function(obj)
				assert(obj.number == 100)
				assert(obj.sort == "sword")
			end,

			function(obj)
				assert(obj.number == 327)
				assert(obj.sort == "cloak")
			end,

			function(obj)
				assert(obj.name == "strong")
			end
		})
	end
end

-- To simplify debugging, uncomment the following line to run only ONE test named below:
--tests = { tests['add/list items (on WML table)'] }
--tests = { tests['add/list advancements (on WML table)'],  tests['add/list advancements (on unit ID)'] }
--tests = { tests['list effects (on unit ID)'] }
--tests = { tests['list effects (on WML table)'] }

-- Provide the list of tests, will be used by loti.testsuite().
return tests
