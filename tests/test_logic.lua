local levels = obsidian.module("src/repair_levels")
local targets = obsidian.module("src/repair_targets")
local share = obsidian.module("src/repair_share")
local tower = obsidian.module("src/repair_tower")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function c(unit, x, hp, kind, extra)
	local out = { unit = unit, kind = kind or "helldiver", x = x, y = 0, z = 0, hp = hp, max = kind == "machine" and 1000 or 100,
		floor = kind == "machine" and -500 or -100, dead = false }
	for k, v in pairs(extra or {}) do out[k] = v end
	return out
end
local TOWER = { unit = "tower", x = 0, y = 0, z = 0 }

test("each_mk_is_a_step_up_from_the_one_before", function()
	local mk1, mk2, mk3 = levels.LEVELS[0], levels.LEVELS[1], levels.LEVELS[2]
	eq(mk1.mk, 1) eq(mk2.mk, 2) eq(mk3.mk, 3)
	-- Mk2: reach and beams.
	yes(mk2.range > mk1.range, "Mk2 reaches further") yes(mk2.beams > mk1.beams, "Mk2 has more beams")
	eq(mk2.helldiver, mk1.helldiver, "Mk2 heal rate") eq(mk2.revive, false, "Mk2 revive")
	-- Mk3: heal rate and reviving, the rest kept.
	eq(mk3.helldiver, 2 * mk2.helldiver, "Mk3 heals Helldivers twice as fast") eq(mk3.machine, 2 * mk2.machine, "and machines")
	eq(mk3.revive, true, "Mk3 revives") eq(mk3.range, mk2.range) eq(mk3.beams, mk2.beams)
	-- The README and the upgrade texts name these numbers.
	eq(mk1.range, 8) eq(mk2.range, 12) eq(mk1.beams, 1) eq(mk2.beams, 3)
	eq(mk1.helldiver, 10) eq(mk1.machine, 50) eq(mk3.helldiver, 20) eq(mk3.machine, 100)
end)

test("the_level_comes_from_the_upgrade_value_and_stops_at_mk3", function()
	eq(levels.of(0).mk, 1) eq(levels.of(1).mk, 2) eq(levels.of(2).mk, 3)
	eq(levels.of(nil).mk, 1, "no value") eq(levels.of(-3).mk, 1, "below") eq(levels.of(9).mk, 3, "past Mk3")
	eq(select(2, levels.of(15)), 2) eq(select(2, levels.of(0 / 0)), 0, "NaN")
	-- One upgrade level per Mk past the first, as many as the Tesla Tower's unit has (two).
	eq(#tower.UPGRADES, levels.MAX)
end)

test("heals_are_whole_hitpoints_at_the_mk_rate", function()
	eq(levels.TICK, 0.5)
	eq(levels.amount(levels.LEVELS[0], "helldiver"), 5) eq(levels.amount(levels.LEVELS[0], "machine"), 25)
	eq(levels.amount(levels.LEVELS[2], "helldiver"), 10) eq(levels.amount(levels.LEVELS[2], "machine"), 50)
	for n = 0, 2 do
		for _, kind in ipairs({ "helldiver", "machine" }) do
			local a = levels.amount(levels.LEVELS[n], kind)
			eq(a, math.floor(a), "a whole number") yes(a >= 1 and a <= 32767, "fits an int16")
		end
	end
end)

test("conditions_follow_the_health_component", function()
	eq(targets.condition(c("a", 0, 100)), "full")
	eq(targets.condition(c("a", 0, 99)), "hurt")
	eq(targets.condition(c("a", 0, 0)), "downed", "0 is downed")
	eq(targets.condition(c("a", 0, -99)), "downed")
	eq(targets.condition(c("a", 0, -100)), "dead", "at the constitution")
	eq(targets.condition(c("a", 0, 50, nil, { dead = true })), "dead")
end)

test("only_hurt_targets_in_range_get_a_beam", function()
	local mk1 = levels.LEVELS[0]
	local list = { c("full", 2, 100), c("far", 9, 10), c("hurt", 7.9, 60), c("edge", 8, 70) }
	local got = targets.pick(TOWER, list, mk1)
	eq(#got, 1) eq(got[1].unit, "hurt", "most hurt in range")
	local mk2 = levels.LEVELS[1]
	got = targets.pick(TOWER, list, mk2)
	eq(#got, 3, "Mk2: three beams") eq(got[1].unit, "far", "10 hp first") eq(got[2].unit, "hurt") eq(got[3].unit, "edge")
	-- Height counts as distance too.
	got = targets.pick(TOWER, { c("up", 0, 50, nil, { z = 8.5 }) }, mk1)
	eq(#got, 0, "8.5 m up is out of an 8 m range")
end)

test("the_tower_never_heals_itself", function()
	local got = targets.pick(TOWER, { c("tower", 0, 10, "machine"), c("mech", 3, 900, "machine") }, levels.LEVELS[1])
	eq(#got, 1) eq(got[1].unit, "mech")
end)

test("downed_targets_wait_for_mk3_and_then_go_first", function()
	local list = { c("hurt", 3, 20), c("downed", 5, -40), c("burning", 6, -100, "machine"), c("dead", 1, -100) }
	for n = 0, 1 do
		local got = targets.pick(TOWER, list, levels.LEVELS[n])
		eq(#got, 1, "Mk" .. (n + 1) .. " heals only the hurt one") eq(got[1].unit, "hurt")
	end
	local got = targets.pick(TOWER, list, levels.LEVELS[2])
	eq(#got, 3)
	eq(got[1].unit, "downed", "the downed Helldiver first") eq(got[2].unit, "burning", "then the burning vehicle")
	eq(got[3].unit, "hurt")
end)

test("ties_go_to_the_nearest_then_to_the_list_order", function()
	local got = targets.pick(TOWER, { c("b", 6, 50), c("a", 4, 50), c("c", 4, 50) }, levels.LEVELS[1])
	eq(got[1].unit, "a") eq(got[2].unit, "c") eq(got[3].unit, "b")
	-- The share of health decides between a Helldiver and a vehicle.
	got = targets.pick(TOWER, { c("diver", 2, 90), c("mech", 3, 500, "machine") }, levels.LEVELS[0])
	eq(got[1].unit, "mech", "50% before 90%")
end)

test("the_shared_text_reads_back_and_fits_the_lobby", function()
	eq(share.encode({}), "")
	local text = share.encode({ { id = 300, level = 2 }, { id = 12, level = 0 } })
	eq(text, "12:0,300:2", "sorted")
	local back = share.decode(text)
	eq(#back, 2) eq(back[1].id, 12) eq(back[1].level, 0) eq(back[2].id, 300) eq(back[2].level, 2)
	local many = {}
	for i = 1, 60 do many[i] = { id = 60000 + i, level = 1 } end
	text = share.encode(many)
	yes(#text <= share.MAX, "at most 200 characters, got " .. #text)
	eq(#share.decode(text), 25, "whole entries only")
	eq(#share.decode("x,12:,:3,7:1"), 1, "junk skipped") eq(#share.decode(nil), 0)
end)

-- Every arrow code of the game's 55 stratagems (lua/settings/loadout_settings.lua).
local GAME_CODES = {
	"DLDUUR", "RUDRL", "DUDDR", "DRDLLR", "DRDLUD", "RDUULD", "RDUUD", "LRDDR", "DRDLLU", "DLDRR", "RRDL", "LDR", "RRR",
	"DULURD", "DULLRD", "UDRU", "DRULDD", "DRULDL", "DRULDR", "DLDRL", "DLULD", "ULRDUD", "DUUDU", "DLDUL", "DLRUD",
	"DLDUR", "DLDUUL", "LLUURL", "DDRU", "LRDU", "LRUD", "RDDDLD", "DLUDR", "RLRLDDR", "DLULL", "RULR", "RULURL",
	"RULUDR", "DULRLD", "RDUDL", "DLRRL", "UDRLU", "DDLRD", "DDUR", "DLRUU", "DULRLR", "RULD", "RRU", "RRDU", "DRDLUR",
	"LDDURL", "LDURL", "LDURRD", "LDULR", "LUR",
}

test("the_code_clashes_with_no_game_stratagem", function()
	local letters = { left = "L", right = "R", up = "U", down = "D" }
	local mine = ""
	for _, arrow in ipairs(tower.CODE) do mine = mine .. assert(letters[arrow], arrow) end
	eq(#GAME_CODES, 55)
	for _, code in ipairs(GAME_CODES) do
		yes(code ~= mine, "the same code as " .. code)
		-- The game calls the stratagem whose code the arrows match, and reports codes that start another.
		yes(mine:sub(1, #code) ~= code, code .. " starts the Repair Tower's code")
		yes(code:sub(1, #mine) ~= mine, "the Repair Tower's code starts " .. code)
	end
	yes(#tower.CODE >= 1 and #tower.CODE <= 10, "1 to 10 arrows")
end)

-- LoadoutSettings.ATTRIBUTE_SORT_ORDER: an attribute outside it fails an assert in the game.
local ATTRIBUTES = {}
for name in ("attr_power attr_firerate attr_stability attr_ammo_amount attr_duration attr_fuel attr_range attr_durability "
	.. "attr_mobility attr_turnspeed attr_spec_backpack attr_spec_explosive attr_spec_anti_tank attr_spec_overheats attr_spec_melee "
	.. "attr_spec_assistedreload attr_spec_armorpiercing attr_spec_unstoppable attr_spec_burst_fire attr_spec_ministun attr_spec_stun "
	.. "attr_spec_sidearm attr_spec_toxic attr_spec_slowing attr_spec_incendiary attr_spec_chargeup attr_spec_homing attr_spec_lasersight "
	.. "attr_spec_ignore_armor attr_spec_move_and_fire attr_spec_multi_target attr_spec_warning_siren attr_spec_reveal_objectives "
	.. "attr_spec_show_samples attr_spec_remote_detonate attr_spec_arm_swivel"):gmatch("%S+") do ATTRIBUTES[name] = true end

test("the_loadout_bars_use_only_attributes_the_game_has", function()
	local def = tower.def()
	for k in pairs(def.attributes) do yes(ATTRIBUTES[k], k) end
	for i, u in ipairs(def.upgrades) do
		for k in pairs(u.attributes or {}) do yes(ATTRIBUTES[k], "Mk" .. (i + 1) .. " " .. k) end
		for k, v in pairs(u.upgrade_attributes or {}) do
			yes(ATTRIBUTES[k], "Mk" .. (i + 1) .. " " .. k)
			eq(type(v), "number", "an upgrade's bar is a number")
		end
	end
end)

test("the_entry_is_the_tesla_tower_under_a_name_of_its_own", function()
	local def = tower.def()
	eq(def.name, "remixed_repair_tower") eq(def.base, "stratagem_tesla_tower") eq(def.unit, nil, "lands the base's unit")
	eq(def.icon, "stratagem_repairtool") eq(def.type, "defensive") eq(def.unlock.rank, 5)
	eq(def.upgrades[1].cost, 2) eq(def.upgrades[2].cost, 3)
	eq(def.stats, nil, "cooldown, uses, call-in and time on the ground stay the Tesla Tower's")
end)

return T
