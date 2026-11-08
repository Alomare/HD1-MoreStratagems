-- The SEAF Unit's entry, and the path through Obsidian API's own define when a copy of the API is at
-- hand: the OBSIDIAN_API folder, or ProjectObsidian/Bundled/ObsidianAPI beside the Mods folder. Without
-- one, that test is skipped.
local seaf = obsidian.module("src/seaf_unit")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

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

-- The game's Tesla Tower entry (lua/settings/loadout_settings.lua), the base the SEAF Unit copies.
local function loadout()
	local tesla = {
		name = "stratagem_tesla_tower", activate_sound = "radio_defense_confirm", cooldown_time = 180, description = "stratagem_tesla_tower_d",
		despawn_time = 1.4, flare_type = "normal", icon = "stratagem_tesla_tower", num_uses = 3, spawn_hellpod = true,
		stratagem_type = "defensive", unit = "gameobjects/gameobject_hellpod_tesla_01", validate_position = true, activation_time = 7,
		combo = { "left", "down", "down", "up", "right", "left" }, stratagem_subtypes = { "turret", "defensive" }, patrol_alert_radius = 80,
		attributes = { attr_durability = 3, attr_firerate = 2, attr_power = 4 },
		upgrades = {
			{ cost = 2, upgrade_description = "stratagem_tesla_tower_d_mk2", upgrade_name = "stratagem_tesla_tower_mk2" },
			{ cost = 2, upgrade_description = "stratagem_tesla_tower_d_mk3", upgrade_name = "stratagem_tesla_tower_mk3" },
		},
	}
	local s = { stratagems = { { name = "stratagem_resupply", id = 1, combo = { "down", "down", "up", "right" }, upgrades = {} }, tesla } }
	tesla.id = 2
	return s
end

test("the_def_has_the_numbers_and_names", function()
	local def = seaf.def()
	eq(def.name, "stratagem_seaf_unit")
	eq(def.base, "stratagem_tesla_tower", "copied from the Tesla Tower")
	eq(def.title, "SEAF Unit")
	eq(def.icon, "seaf_unit_icon")
	eq(def.icon_material, "more_stratagems/icons")
	eq(def.stats.cooldown_time, 200, "cooldown")
	eq(def.stats.activation_time, 15, "call-in")
	eq(def.stats.num_uses, 2, "uses")
	eq(type(def.on_activate), "function", "the activation hook")
	eq(def.type, "supply", "a blue supply stratagem")
	eq(def.unlock.rank, 5)
	eq(#def.upgrades, 2, "a Mk2 and Mk3 of the SEAF Unit, not the Tesla Tower levels")
	eq(def.upgrades[1].cost, 2) eq(def.upgrades[2].cost, 3)
	eq(def.upgrades[1].title, "SEAF Unit Mk2")
end)

test("a_landed_beacon_calls_the_soldiers_and_never_drops_the_tower", function()
	local got = nil
	local def = seaf.def(function(pos, upgrade, owner) got = { pos = pos, upgrade = upgrade, owner = owner } end)
	local vector = setmetatable({}, { __index = function(_, k) return ({ x = 1, y = 2, z = 3 })[k] end })
	eq(def.on_activate({ name = seaf.NAME, position = vector, upgrade = 2, owner = "thrower" }), false, "no tower")
	eq(got.pos.x, 1) eq(got.pos.z, 3) eq(rawequal(got.pos, vector), false, "plain numbers, not the vector")
	eq(got.upgrade, 2) eq(got.owner, "thrower")
	-- An error in the call still drops no tower.
	local failing = seaf.def(function() error("broken") end)
	local saved = obsidian.log
	local logged = nil
	obsidian.log = function(t) logged = t end
	eq(failing.on_activate({ position = vector, upgrade = 0 }), false)
	obsidian.log = saved
	yes(logged and logged:find("broken", 1, true), "said in the log")
	-- With an Obsidian API too old for soldiers, the use goes back.
	local refused = nil
	local old = seaf.def(nil, function(owner) refused = owner end)
	eq(old.on_activate({ position = vector, upgrade = 0, owner = "thrower" }), false)
	eq(refused, "thrower")
	yes(seaf.at_least("1.46.0", seaf.BOTS_API), "1.46.0 brings soldiers")
	eq(seaf.at_least("1.45.0", seaf.BOTS_API), false, "1.45.0 has no ammunition recovery")
end)

test("the_api_version_gate", function()
	yes(seaf.at_least("1.46.0", seaf.MIN_API), "1.46.0 is enough")
	yes(seaf.at_least("1.46.3", seaf.MIN_API), "later patch")
	yes(seaf.at_least("2.0.0", seaf.MIN_API), "later major")
	eq(seaf.at_least("1.45.9", seaf.MIN_API), false, "older minor")
	eq(seaf.at_least("1.9.0", seaf.MIN_API), false, "older by number, not text")
	eq(seaf.at_least(nil, seaf.MIN_API), false, "no version")
end)

test("obsidian_api_takes_the_entry", function()
	local path = api_file()
	if not path then return "skip" end
	local stubs = {
		["lib/game"] = { global = function(name) return rawget(_G, name) end },
		["lib/catalog"] = { xp_and_rewards = function() return 0 end, unlocked = function() return false end },
	}
	local saved = { module = obsidian.module, storage = obsidian.storage, caller = obsidian.caller, hook = obsidian.hook, ui = obsidian.ui, log = obsidian.log }
	local saved_ls = rawget(_G, "LoadoutSettings")
	local ls = loadout()
	rawset(_G, "LoadoutSettings", ls)
	obsidian.module = function(name) return stubs[name] or saved.module(name) end
	obsidian.storage = { get = function() return nil end, set = function() end }
	obsidian.caller = function() return "obsidian.api" end
	obsidian.hook = function() end
	obsidian.log = function() end
	-- The deploy has the mod's material, as obsidian.json puts it in the boot bundle.
	obsidian.ui = { art = function(id, opts) return id == seaf.ICON and opts.path == seaf.ICON_MATERIAL end }
	local ok, err = pcall(function()
		local custom = dofile(path)
		local made, why = custom.define(seaf.def())
		yes(made, "defined: " .. tostring(why))
		eq(made.name, seaf.NAME)
		local e = ls.stratagems[made.id]
		eq(e.cooldown_time, 200, "cooldown")
		eq(e.activation_time, 15, "call-in")
		eq(e.num_uses, 2, "uses")
		eq(e.icon, seaf.ICON, "the mod's icon")
		eq(e.unit, "gameobjects/gameobject_hellpod_tesla_01", "the base's unit, which on_activate never lets land")
		eq(e.stratagem_type, "supply")
		-- The same def twice is refused rather than added twice.
		local again, taken = custom.define(seaf.def())
		eq(again, nil) eq(taken, "taken")
	end)
	for k, v in pairs(saved) do obsidian[k] = v end
	rawset(_G, "LoadoutSettings", saved_ls)
	if not ok then error(err, 0) end
end)

-- The icon and material names must be the ones tools/build_icon.py writes into res/icons.material:
-- a gui asked for a sub-material the material lacks stops the game.
test("icon names match the material the build script writes", function()
	local f = assert(io.open("tools/build_icon.py", "r"))
	local text = f:read("*a")
	f:close()
	local seaf = obsidian.module("src/seaf_unit")
	eq(text:match('\nICON = "([^"]+)"'), seaf.ICON, "sub-material name")
	eq(text:match('\nMATERIAL = "([^"]+)"'), seaf.ICON_MATERIAL, "material name")
end)

return T
