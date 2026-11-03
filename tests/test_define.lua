-- The Repair Tower's entry through Obsidian API's own define, when a copy of the API is at hand: the
-- OBSIDIAN_API folder, or ProjectObsidian/Bundled/ObsidianAPI beside the Mods folder. Without one, the
-- test is skipped.
local tower = obsidian.module("src/repair_tower")
local levels = obsidian.module("src/repair_levels")

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

local function clone(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = clone(v) end
	return out
end

local function override(into, from)
	for k, v in pairs(from) do
		if type(v) == "table" and type(into[k]) == "table" then override(into[k], v) else into[k] = clone(v) end
	end
end

-- The game's Tesla Tower entry (lua/settings/loadout_settings.lua), and get_upgraded_stratagem as the
-- game applies levels.
local function loadout()
	local tesla = {
		name = "stratagem_tesla_tower", activate_sound = "radio_defense_confirm", cooldown_time = 180, description = "stratagem_tesla_tower_d",
		despawn_time = 1.4, flare_type = "normal", icon = "stratagem_tesla_tower", num_uses = 3, spawn_hellpod = true,
		stratagem_type = "defensive", unit = "gameobjects/gameobject_hellpod_tesla_01", validate_position = true, activation_time = 7,
		combo = { "left", "down", "down", "up", "right", "left" }, stratagem_subtypes = { "turret", "defensive" }, patrol_alert_radius = 80,
		attributes = { attr_durability = 3, attr_firerate = 2, attr_power = 4 },
		upgrades = {
			{ cost = 2, upgrade_description = "stratagem_tesla_tower_d_mk2", upgrade_name = "stratagem_tesla_tower_mk2", attributes = { attr_spec_multi_target = true } },
			{ cost = 2, upgrade_description = "stratagem_tesla_tower_d_mk3", upgrade_name = "stratagem_tesla_tower_mk3" },
		},
	}
	local s = { stratagems = { { name = "stratagem_resupply", id = 1, combo = { "down", "down", "up", "right" }, upgrades = {} }, tesla } }
	tesla.id = 2
	function s.get_upgraded_stratagem(id, n)
		local e = s.stratagems[id]
		if not n or n == 0 then return e end
		local out = clone(e)
		for i = 1, n do override(out, e.upgrades[i]) end
		return out
	end
	return s
end

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
	obsidian.ui = { art = function(id, opts) return id == tower.ICON and opts.path == tower.ICON_MATERIAL end }
	local ok, err = pcall(function()
		local custom = dofile(path)
		local made, why = custom.define(tower.def("1.22.0"))
		yes(made, "defined: " .. tostring(why))
		eq(made.name, levels.NAME)
		local e = ls.stratagems[made.id]
		eq(e.unit, "gameobjects/gameobject_hellpod_tesla_01", "lands the Tesla Tower")
		eq(e.icon, tower.ICON, "its own icon") eq(table.concat(e.combo, " "), table.concat(tower.CODE, " "))
		eq(#e.upgrades, 2, "Mk2 and Mk3") eq(e.upgrades[1].cost, 2) eq(e.upgrades[2].cost, 3)
		eq(e.upgrades[1].upgrade_attributes.attr_range, 2)
		eq(e.num_uses, 3, "the Tesla Tower's uses") eq(e.cooldown_time, 180, "and cooldown")
		local mk3 = ls.get_upgraded_stratagem(made.id, 2)
		eq(mk3.name, levels.NAME, "the name the hook looks for, at every level")
		eq(mk3.unit, "gameobjects/gameobject_hellpod_tesla_01")
		-- The same def twice is refused rather than added twice.
		local again, taken = custom.define(tower.def("1.22.0"))
		eq(again, nil) eq(taken, "taken")
	end)
	for k, v in pairs(saved) do obsidian[k] = v end
	rawset(_G, "LoadoutSettings", saved_ls)
	if not ok then error(err, 0) end
end)

test("the_own_icon_waits_for_an_api_that_adds_its_material", function()
	eq(tower.own_icon("1.22.0"), true) eq(tower.own_icon("1.22.3"), true) eq(tower.own_icon("2.0.0"), true)
	eq(tower.own_icon("1.21.9"), false) eq(tower.own_icon("1.9.0"), false) eq(tower.own_icon(nil), false, "no obsidian.info")
	local old = tower.def("1.21.0")
	eq(old.icon, tower.OLD_API_ICON) eq(old.icon_material, nil)
	local new = tower.def("1.22.0")
	eq(new.icon, tower.ICON) eq(new.icon_material, tower.ICON_MATERIAL)
end)

-- The names tools/build_icon.py writes and obsidian.json lists.
test("the_icon_names_match_the_build_and_the_manifest", function()
	local f = assert(io.open("tools/build_icon.py", "r"))
	local py = f:read("*a")
	f:close()
	eq(py:match('\nICON = "([^"]+)"'), tower.ICON)
	eq(py:match('\nMATERIAL = "([^"]+)"'), tower.ICON_MATERIAL)
	local texture = py:match('\nTEXTURE = "([^"]+)"')
	f = assert(io.open("obsidian.json", "r"))
	local manifest = f:read("*a")
	f:close()
	yes(manifest:find('"name": "' .. tower.ICON_MATERIAL .. '"', 1, true), "the material in the manifest")
	yes(manifest:find('"name": "' .. texture .. '"', 1, true), "the texture in the manifest")
end)

return T
