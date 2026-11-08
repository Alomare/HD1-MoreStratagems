-- The A/MG-15 Perforator Turret: the entry, the code, the texts, the settings variants built from the
-- Railcannon Turret and the Justice, the hellpod marker, and the runtime against a small stand-in for
-- LuaSettingsManager and the turret component.
local pt = obsidian.module("src/perforator_turret")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- The game's numbers, as lifted (gameobjects/gameobject_hellpod_railcannon_turret.lua,
-- equipment/wep_assaultrifle_02.lua).
local function railcannon()
	return {
		unit_radius = 1,
		turret_info = { angle_to_target_diff_before_shooting = 0.001, check_for_enemies_interval = 1, check_for_enemies_radius = 16, fire_cooldown = 0,
			infinite_ammo = true, rounds = 50, start_idle_time = 5.5, start_invul_time = 4, switch_target_angle = 40, switch_target_interval = 1,
			targeting_mode = "size", turn_speed_idle = 0, turn_speed_target = 0.23 },
		weapon_info = { automatic = false, effect_hit = "projectile_heavy", firerate = 15, power = 1500, range = 50, spread = 0,
			attributes = { armorpiercing = true, unstoppable = true } },
		health_info = { armor_max = 150, armor_min = 0, authoritative = true, constitution = 0, constitution_decay = 0, healable = true, health = 400, health_decay = 0 },
		ttl_info = { time_until_dead = 120, time_until_despawn = 4 },
		show_on_map_info = {},
		upgrade_info = { { weapon_info = { firerate = 30 } }, { turret_info = { turn_speed_target = 0.3 } } },
	}
end

local function justice()
	return { weapon_info = { effect_hit = "projectile_heavy", firerate = 400, magazine_capacity = 20, power = 120, power_crit = 150, range = 30,
		spread_max = 15, spread_min = 0, attributes = { armorpiercing = false, chambered = true, fully_automatic = true } } }
end

-- The game's levels for a settings table, as create_upgrade_settings_permutations makes them.
local function level(base, n)
	local v = pt.copy(base)
	for i = 1, n do
		local function over(t, o)
			for k, x in pairs(o) do
				if type(x) == "table" and type(t[k]) == "table" then over(t[k], x) else t[k] = pt.copy(x) end
			end
		end
		over(v, base.upgrade_info[i])
	end
	return v
end

local function protect(t)
	return setmetatable({ __protected_table = t }, { __index = t, __newindex = function() error("constant") end })
end

-- A stand-in game: LuaSettingsManager with the Railcannon Turret's levels 1 and 2, LoadoutSettings reading
-- each unit's upgrade value, and turret units.
local function game()
	local rail, rifle = railcannon(), justice()
	local by_path = { [pt.UNIT] = protect(rail), [pt.RIFLE] = protect(rifle), ["gameobjects/gameobject_hellpod_minigun_turret"] = protect({ weapon_info = { firerate = 1300 } }) }
	local g = { rail = rail, rifle = rifle, logs = {}, reloads = 0 }
	g.vanilla = { [1] = protect(level(rail, 1)), [2] = protect(level(rail, 2)) }
	local lsm = { unit_path_to_modified_settings = { [pt.UNIT] = { [1] = g.vanilla[1], [2] = g.vanilla[2] } } }
	function lsm:get_settings_by_unit_path(p) return by_path[p] end
	function lsm:get_settings_path_by_unit_path(p) return p end
	function lsm:set_modified_settings(p, k, t)
		self.unit_path_to_modified_settings[p] = self.unit_path_to_modified_settings[p] or {}
		self.unit_path_to_modified_settings[p][k] = protect(t)
	end
	function lsm:get_modified_settings(unit, v)
		local m = self.unit_path_to_modified_settings[unit.path]
		return m and m[v] or by_path[unit.path]
	end
	g.lsm = lsm
	local ls = { get_upgraded_settings = function(unit, v) return lsm:get_modified_settings(unit, v or unit.upgrade) end }
	local globals = { LuaSettingsManager = lsm, LoadoutSettings = ls }
	g.env = {
		global = function(name) return globals[name] end,
		log = function(text) g.logs[#g.logs + 1] = text end,
		unit_path = function(u) return u.path end,
		alive = function(u) return u.alive end,
	}
	g.component = { reload_slave = function(_, unit, ctx)
		g.reloads = g.reloads + 1
		local s = ls.get_upgraded_settings(unit)
		ctx.state.rotation = { "identity" }
		ctx.state.start_rotation = "node now"
		ctx.state.round_delay = 60 / s.weapon_info.firerate
		ctx.state.raycast_slave = { weapon_info = s.weapon_info }
	end }
	function g.turret(upgrade, path)
		return { path = path or pt.UNIT, upgrade = upgrade, alive = true }
	end
	return g
end

local function near(got, want, what)
	if math.abs(got - want) > 1e-9 then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

test("the_entry_has_the_railcannon_turret_numbers_and_new_words", function()
	local def = pt.def()
	eq(def.name, "stratagem_turret_perforator")
	eq(def.base, "stratagem_turret_railcannon")
	eq(def.title, "A/MG-15 Perforator Turret")
	eq(def.type, "defensive")
	eq(def.icon, "perforator_turret_icon")
	eq(def.icon_material, "more_stratagems/icons")
	eq(table.concat(def.code, " "), "left down up up right")
	eq(def.stats, nil, "uses, cooldown and call-in are the base's")
	eq(def.unlock, nil, "unlocked with the Railcannon Turret")
	eq(def.on_activate, nil, "the turret lands")
	eq(#def.upgrades, 2)
	eq(def.upgrades[1].cost, 2) eq(def.upgrades[2].cost, 2)
	eq(def.upgrades[1].title, "A/MG-15 Perforator Turret Mk2")
	eq(def.upgrades[2].title, "A/MG-15 Perforator Turret Mk3")
	eq(def.upgrades[1].stats, nil, "Mk2 keeps the cooldown")
	eq(def.upgrades[2].stats.cooldown_time, 120, "Mk3 cooldown, as the Railcannon Turret Mk3")
	eq(def.upgrades[1].upgrade_attributes.attr_firerate, 4)
	eq(def.upgrades[2].upgrade_attributes.attr_turnspeed, 4)
end)

-- Every vanilla code (lua/settings/loadout_settings.lua), and the other stratagems of this mod.
local VANILLA = {
	"up down right left up", "up left right down up down", "down down right up", "up down right up", "down down up right",
	"down left down up right", "down left down up up left", "down left down up left", "down left down up up right", "down left up left down",
	"down left up left left", "down left down right left", "down left down right right", "down left right right left", "down left right up down",
	"down left up down right", "down up left up right down", "down up left left right down", "down up down down right", "down up up down up",
	"down up left right left down", "down up left right left right", "down down left right down", "down left right up up", "down right up left down down",
	"down right up left down left", "down right up left down right", "down right down left left up", "down right down left up right", "down right down left left right",
	"down right down left up down", "left up right", "left down right", "left left up up right left", "left down up right left",
	"left down up left right", "left down up right right down", "left down down up right left", "left right down up", "right down up up down",
	"left right down down right", "left right up down", "right up left down", "right up down right left", "right right right",
	"right right up", "right up left right", "right right down up", "right right down left", "right down down down left down",
	"right down up up left down", "right up left up down right", "right up left up right left", "right left right left down down right", "right down up down left",
}

test("the_code_is_neither_a_vanilla_code_nor_a_prefix_of_one", function()
	eq(#VANILLA, 55, "all vanilla codes")
	local mine = table.concat(pt.CODE, " ")
	local others = {}
	for _, c in ipairs(VANILLA) do others[#others + 1] = c end
	for _, path in ipairs({ "src/homing_payload.lua" }) do
		local ok, mod = pcall(dofile, path)
		if ok and type(mod) == "table" and type(mod.CODE) == "table" then others[#others + 1] = table.concat(mod.CODE, " ") end
	end
	for _, c in ipairs(others) do
		yes(c ~= mine, "same as " .. c)
		yes((c .. " "):sub(1, #mine + 1) ~= mine .. " ", "a prefix of " .. c)
		yes((mine .. " "):sub(1, #c + 1) ~= c .. " ", "starts with " .. c)
	end
end)

local BANNED = { "its", "it's", "you", "your", "i", "me", "my", "we", "our", "us" }
local function check(text, what)
	local lower = " " .. text:lower():gsub("[^%w'%-]", " ") .. " "
	for _, word in ipairs(BANNED) do yes(not lower:find(" " .. word .. " ", 1, true), what .. ' says "' .. word .. '"') end
	yes(not text:find("\226\128\148", 1, true) and not text:find("\226\128\147", 1, true), what .. " has a long dash")
	yes(not text:find(" %- "), what .. " has a dash between words")
	yes(not text:find("%w's%f[%W]"), what .. " has a possessive")
	yes(#text <= 600, what .. " is longer than define takes")
end

test("the_texts_restate_the_base_and_keep_the_writing_rules", function()
	check(pt.TITLE, "the title")
	check(pt.DESCRIPTION, "the description")
	local mk2, mk3 = pt.UPGRADES[1].description, pt.UPGRADES[2].description
	for i, u in ipairs(pt.UPGRADES) do
		check(u.title, "upgrade " .. i .. " title")
		check(u.description, "upgrade " .. i .. " description")
		eq(u.description:sub(1, #pt.DESCRIPTION), pt.DESCRIPTION, "upgrade " .. i .. " restates the base")
	end
	yes(mk2:find("higher rate of fire", 1, true), "Mk2 says the change")
	yes(mk3:find("higher rate of fire", 1, true) and mk3:find("faster rotation", 1, true), "Mk3 restates Mk2 and adds the turn speed")
end)

test("the_variants_fire_justice_rounds_with_the_railcannon_levels", function()
	local g = game()
	local before = pt.copy(g.rail)
	local j = pt.justice_from(g.rifle.weapon_info)
	local mk = {}
	for l = 0, 2 do mk[l] = pt.variant(protect(g.rail), l, j) end
	eq(mk[0].weapon_info.firerate, 460, "Justice 400, 15 percent faster")
	eq(mk[1].weapon_info.firerate, 920, "Mk2 doubles")
	eq(mk[2].weapon_info.firerate, 920, "Mk3 keeps Mk2")
	near(mk[0].turret_info.turn_speed_target, 0.23) near(mk[1].turret_info.turn_speed_target, 0.23)
	near(mk[2].turret_info.turn_speed_target, 0.3, "Mk3 turns as the Railcannon Turret Mk3")
	for l = 0, 2 do
		local w, t = mk[l].weapon_info, mk[l].turret_info
		eq(w.automatic, true) eq(w.power, 120) eq(w.power_crit, 150) eq(w.range, 30) eq(w.effect_hit, "projectile_heavy")
		yes(w.spread < 2.5 and w.spread > 0, "a tighter spread than the Justice")
		eq(w.attributes.armorpiercing, false) eq(w.attributes.unstoppable, false)
		eq(t.rounds, 3000) near(t.fire_cooldown, 0.2) near(t.angle_to_target_diff_before_shooting, 0.01) eq(t.targeting_mode, "angle")
		eq(t.infinite_ammo, true) eq(t.check_for_enemies_radius, 16) eq(t.start_invul_time, 4)
		eq(mk[l].health_info.health, 400, "the turret's health") eq(mk[l].ttl_info.time_until_dead, 120)
		yes(mk[l].weapon_info ~= g.rail.weapon_info and mk[l].health_info ~= g.rail.health_info, "own tables")
		yes(#mk[l].upgrade_info == 2, "the upgrade info, as the game's levels keep it")
	end
	-- 2000 rounds a minute is the most the stream could use in a turret's 120 seconds.
	yes(mk[1].turret_info.rounds > mk[1].weapon_info.firerate * 2, "no ammunition reset in a turret's life")
	yes(pt.same(g.rail, before), "the Railcannon Turret's settings stay as they were")
end)

test("the_justice_numbers_fall_back_one_by_one", function()
	local j = pt.justice_from({ power = 0 / 0, firerate = "fast", range = 25, attributes = { armorpiercing = true } })
	eq(j.power, 120, "not a number") eq(j.firerate, 400, "wrong type") eq(j.range, 25, "the game's")
	eq(j.armorpiercing, true) eq(j.effect_hit, "projectile_heavy", "missing")
	eq(pt.justice_from(nil).power_crit, 150)
end)

test("the_marker_moves_only_the_perforator_past_the_game_levels", function()
	for l = 0, 2 do
		local s = { stratagem_info = { name = pt.NAME }, upgrade_value = l }
		eq(pt.mark(s), true) eq(s.upgrade_value, l + 4)
		eq(pt.mark(s), false, "once") eq(s.upgrade_value, l + 4)
	end
	local s = { stratagem_info = { name = pt.NAME } }
	eq(pt.mark(s), true) eq(s.upgrade_value, 4, "no value is Mk1")
	local rail = { stratagem_info = { name = "stratagem_turret_railcannon" }, upgrade_value = 2 }
	eq(pt.mark(rail), false) eq(rail.upgrade_value, 2, "the Railcannon Turret keeps the value")
	eq(pt.mark(nil), false) eq(pt.mark({}), false)
	eq(pt.mark({ stratagem_info = { name = pt.NAME }, upgrade_value = 1.5 }), false)
end)

test("the_variants_go_in_beside_the_game_levels_and_come_out_again", function()
	local g = game()
	local r = pt.runtime(g.env)
	eq(r:install(), true)
	local map = g.lsm.unit_path_to_modified_settings[pt.UNIT]
	eq(map[1], g.vanilla[1], "Mk2 Railcannon untouched") eq(map[2], g.vanilla[2])
	eq(g.vanilla[1].weapon_info.firerate, 30) eq(g.vanilla[1].weapon_info.power, 1500)
	local held = {}
	for l = 0, 2 do
		held[l] = pt.raw(map[4 + l])
		eq(held[l].weapon_info.firerate, l == 0 and 460 or 920)
	end
	-- Again: the same tables.
	eq(r:install(), true)
	for l = 0, 2 do eq(pt.raw(map[4 + l]), held[l]) end
	-- An edit rebuilding every variant from the base (an Obsidian API older than 1.43.0) is put back in
	-- place on the next check, keeping the tables live turrets hold.
	local weapon = held[1].weapon_info
	pt.assign(held[1], level(g.rail, 2))
	eq(weapon.automatic, false)
	r:frame(1)
	eq(held[1].weapon_info, weapon, "the same table") eq(weapon.automatic, true) eq(weapon.firerate, 920)
	-- A script reload empties the map: back with the same tables.
	g.lsm.unit_path_to_modified_settings = {}
	r:frame(1)
	eq(pt.raw(g.lsm.unit_path_to_modified_settings[pt.UNIT][5]), held[1])
	-- An uncleared lobby: the game's levels only.
	map = g.lsm.unit_path_to_modified_settings[pt.UNIT]
	map[1], map[2] = g.vanilla[1], g.vanilla[2]
	r:uninstall()
	eq(map[4], nil) eq(map[5], nil) eq(map[6], nil)
	eq(map[1], g.vanilla[1]) eq(map[2], g.vanilla[2])
	eq(held[0].weapon_info.firerate, 460, "a turret standing keeps a working table")
end)

test("the_hellpod_of_a_perforator_hands_the_turret_its_level", function()
	local g = game()
	local r = pt.runtime(g.env)
	local s = { stratagem_info = { name = pt.NAME, unit = pt.UNIT }, upgrade_value = 2 }
	r:hellpod(s)
	eq(s.upgrade_value, 6)
	local turret = g.turret(s.upgrade_value)
	local got = g.env.global("LoadoutSettings").get_upgraded_settings(turret)
	eq(got.weapon_info.firerate, 920) near(got.turret_info.turn_speed_target, 0.3)
	local rail = { stratagem_info = { name = "stratagem_turret_railcannon" }, upgrade_value = 1 }
	r:hellpod(rail)
	eq(rail.upgrade_value, 1)
	eq(g.env.global("LoadoutSettings").get_upgraded_settings(g.turret(1)).weapon_info.power, 1500, "a Railcannon Turret stays one")
	-- No settings yet: lands as a Railcannon Turret, and says so.
	local bare = game()
	bare.lsm.get_settings_by_unit_path = function() return nil end
	local r2 = pt.runtime(bare.env)
	local s2 = { stratagem_info = { name = pt.NAME }, upgrade_value = 0 }
	r2:hellpod(s2)
	eq(s2.upgrade_value, 0)
	yes(bare.logs[1] and bare.logs[1]:find("Railcannon", 1, true), "logged")
end)

test("a_slave_that_sees_the_upgrade_value_late_remakes_the_raycast", function()
	local g = game()
	local r = pt.runtime(g.env)
	r:install()
	local turret = g.turret(0)
	-- setup_slave read the value before it arrived: the Railcannon's base settings.
	local ctx = { state = {} }
	g.component.reload_slave(g.component, turret, ctx)
	r:reloaded(turret, ctx)
	local base = g.env.global("LoadoutSettings").get_upgraded_settings(turret)
	ctx.state.weapon_info, ctx.state.turret_info = base.weapon_info, base.turret_info
	ctx.state.start_rotation, ctx.state.rotation = 0.25, { "landed" }
	r:watch(g.component, turret, ctx, true)
	r:frame(0.1)
	eq(ctx.state.weapon_info.power, 1500, "still the base while the value is 0")
	turret.upgrade = 5
	r:frame(0.1)
	eq(ctx.state.weapon_info.firerate, 920) eq(ctx.state.raycast_slave.weapon_info.firerate, 920, "the raycast too")
	near(ctx.state.round_delay, 60 / 920)
	eq(ctx.state.start_rotation, 0.25, "rotation kept") eq(ctx.state.rotation[1], "landed")
	local reloads = g.reloads
	r:frame(0.1)
	eq(g.reloads, reloads, "done once")
	-- A slave set up right: no remake.
	local good = g.turret(4)
	local c2 = { state = {} }
	g.component.reload_slave(g.component, good, c2)
	r:reloaded(good, c2)
	local s = g.env.global("LoadoutSettings").get_upgraded_settings(good)
	c2.state.weapon_info = s.weapon_info
	r:watch(g.component, good, c2, true)
	reloads = g.reloads
	r:frame(0.1)
	eq(g.reloads, reloads, "nothing to do")
end)

test("railcannon_and_other_turrets_are_never_touched", function()
	local g = game()
	local r = pt.runtime(g.env)
	r:install()
	local rail = g.turret(2)
	local ctx = { state = {} }
	local s = g.env.global("LoadoutSettings").get_upgraded_settings(rail)
	ctx.state.weapon_info = s.weapon_info
	r:watch(g.component, rail, ctx, true)
	r:watch(g.component, rail, ctx, false)
	local minigun = g.turret(0, "gameobjects/gameobject_hellpod_minigun_turret")
	local mctx = { state = { weapon_info = "minigun" } }
	r:watch(g.component, minigun, mctx, true)
	eq(r.slaves[minigun], nil, "not the Railcannon Turret unit")
	for _ = 1, 120 do r:frame(0.1) end
	eq(ctx.state.weapon_info, s.weapon_info) eq(g.reloads, 0)
	eq(next(r.slaves), nil, "the watch ends") eq(next(r.masters), nil)
end)

test("an_owner_taking_over_a_perforator_runs_it_on_the_perforator_settings", function()
	local g = game()
	local r = pt.runtime(g.env)
	r:install()
	local turret = g.turret(0)
	-- migrated_to_me: setup_master with no setup info, before the upgrade value is copied over.
	local base = g.env.global("LoadoutSettings").get_upgraded_settings(turret)
	local ctx = { state = { weapon_info = base.weapon_info, turret_info = base.turret_info, round_delay = 4 } }
	r:watch(g.component, turret, ctx, false)
	r:frame(0.1)
	eq(ctx.state.round_delay, 4)
	turret.upgrade = 5
	r:frame(0.1)
	eq(ctx.state.weapon_info.firerate, 920) eq(ctx.state.turret_info.rounds, 3000)
	near(ctx.state.round_delay, 60 / 920)
	eq(r.masters[turret], nil, "done")
	-- A turret that dies is dropped.
	local gone = g.turret(4)
	r:watch(g.component, gone, { state = {} }, false)
	gone.alive = false
	r:frame(0.1)
	eq(r.masters[gone], nil)
end)

test("an_edited_justice_still_gives_the_justice_numbers", function()
	local g = game()
	g.rifle.weapon_info.power = 999
	g.env.original = function(_, path)
		if path == "weapon_info.power" then return true, 120 end
		return false, nil
	end
	local r = pt.runtime(g.env)
	r:install()
	eq(pt.raw(g.lsm.unit_path_to_modified_settings[pt.UNIT][4]).weapon_info.power, 120)
end)

-- Through Obsidian API's own define, when a copy of the API is at hand (as tests/test_define.lua).
local function api_file()
	for _, dir in ipairs({ os.getenv("OBSIDIAN_API") or "", "../../ProjectObsidian/Bundled/ObsidianAPI" }) do
		if dir ~= "" then
			local path = dir .. "/lib/custom.lua"
			local f = io.open(path, "r")
			if f then f:close() return path end
		end
	end
	return nil
end

test("obsidian_api_takes_the_entry", function()
	local path = api_file()
	if not path then return "skip" end
	local rail = {
		name = "stratagem_turret_railcannon", id = 2, activate_sound = "radio_defense_confirm", cooldown_time = 180, description = "stratagem_turret_railcannon_d",
		despawn_time = 1.4, flare_type = "normal", icon = "stratagem_turret_railcannon", num_uses = 3, spawn_hellpod = true, stratagem_type = "defensive",
		unit = pt.UNIT, validate_position = true, activation_time = 7, combo = { "left", "down", "up", "left", "right" },
		stratagem_subtypes = { "turret", "defensive" }, patrol_alert_radius = 80, attributes = { attr_durability = 3, attr_firerate = 1, attr_power = 3, attr_turnspeed = 2 },
		upgrades = {
			{ cost = 2, upgrade_description = "stratagem_turret_railcannon_d_mk2", upgrade_name = "stratagem_turret_railcannon_mk2", upgrade_attributes = { attr_firerate = 2 } },
			{ cooldown_time = 120, cost = 2, upgrade_description = "stratagem_turret_railcannon_d_mk3", upgrade_name = "stratagem_turret_railcannon_mk3", upgrade_attributes = { attr_turnspeed = 4 } },
		},
	}
	local ls = { stratagems = { { name = "stratagem_resupply", id = 1, combo = { "down", "down", "up", "right" }, upgrades = {} }, rail } }
	local stubs = {
		["lib/game"] = { global = function(name) return rawget(_G, name) end },
		["lib/catalog"] = { xp_and_rewards = function() return 0 end, unlocked = function() return false end },
	}
	local saved = { module = obsidian.module, storage = obsidian.storage, caller = obsidian.caller, hook = obsidian.hook, ui = obsidian.ui, log = obsidian.log }
	local saved_ls = rawget(_G, "LoadoutSettings")
	rawset(_G, "LoadoutSettings", ls)
	obsidian.module = function(name) return stubs[name] or saved.module(name) end
	obsidian.storage = { get = function() return nil end, set = function() end }
	obsidian.caller = function() return "obsidian.api" end
	obsidian.hook = function() end
	obsidian.log = function() end
	obsidian.ui = { art = function(id, opts) return id == pt.ICON and opts.path == pt.ICON_MATERIAL end }
	local ok, err = pcall(function()
		local custom = dofile(path)
		local made, why = custom.define(pt.def())
		yes(made, "defined: " .. tostring(why))
		local e = ls.stratagems[made.id]
		eq(e.num_uses, 3) eq(e.cooldown_time, 180) eq(e.activation_time, 7)
		eq(e.unit, pt.UNIT, "the Railcannon Turret lands")
		eq(table.concat(e.combo, " "), "left down up up right")
		eq(e.icon, pt.ICON)
		eq(e.upgrades[1].cost, 2) eq(e.upgrades[2].cost, 2)
		eq(e.upgrades[1].cooldown_time, nil) eq(e.upgrades[2].cooldown_time, 120)
		eq(e.upgrades[1].upgrade_attributes.attr_firerate, 4)
		eq(e.attributes.attr_firerate, 3)
	end)
	for k, v in pairs(saved) do obsidian[k] = v end
	rawset(_G, "LoadoutSettings", saved_ls)
	if not ok then error(err, 0) end
end)

return T
