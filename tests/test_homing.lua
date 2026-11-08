-- Homing Payload: the entry, the code, the barrage by Mk, where each missile starts and flies, the words,
-- and the path through Obsidian API's own define when a copy of the API is at hand (the OBSIDIAN_API
-- folder, or ProjectObsidian/Bundled/ObsidianAPI beside the Mods folder). Without one, that test is skipped.
local homing = obsidian.module("src/homing_payload")
local seaf = obsidian.module("src/seaf_unit")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function near(got, want, what)
	if math.abs(got - want) > 1e-6 then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

-- Every code of the game's own stratagems (lua/settings/loadout_settings.lua), U D L R.
local VANILLA = {
	"UDRLU", "ULRDUD", "DDRU", "UDRU", "DDUR", "DLDUR", "DLDUUL", "DLDUL", "DLDUUR", "DLULD", "DLULL", "DLDRL", "DLDRR",
	"DLRRL", "DLRUD", "DLUDR", "DULURD", "DULLRD", "DUDDR", "DUUDU", "DULRLD", "DULRLR", "DDLRD", "DLRUU", "DRULDD",
	"DRULDL", "DRULDR", "DRDLLU", "DRDLUR", "DRDLLR", "DRDLUD", "LUR", "LDR", "LLUURL", "LDURL", "LDULR", "LDURRD",
	"LDDURL", "LRDU", "RDUUD", "LRDDR", "LRUD", "RULD", "RUDRL", "RRR", "RRU", "RULR", "RRDU", "RRDL", "RDDDLD",
	"RDUULD", "RULUDR", "RULURL", "RLRLDDR", "RDUDL",
}
local LETTER = { up = "U", down = "D", left = "L", right = "R" }

test("the_def_has_the_numbers_and_names", function()
	local def = homing.def()
	eq(def.name, "stratagem_homing_payload")
	eq(def.base, "stratagem_airstrike", "copied from the Airstrike")
	eq(def.title, "Homing Payload")
	eq(def.type, "offensive", "a red offensive stratagem")
	eq(def.icon, "homing_payload_icon")
	eq(def.icon_material, "more_stratagems/icons")
	eq(def.stats.cooldown_time, 90, "cooldown")
	eq(def.stats.activation_time, 1.5, "call-in")
	eq(def.stats.num_uses, nil, "unlimited uses")
	eq(def.unlock.rank, 7)
	eq(table.concat(def.code, " "), "right down down right down")
	eq(#def.upgrades, 2, "a Mk2 and Mk3 made for it, not the Airstrike levels")
	eq(def.upgrades[1].title, "Homing Payload Mk2") eq(def.upgrades[2].title, "Homing Payload Mk3")
	eq(def.upgrades[1].cost, 1) eq(def.upgrades[2].cost, 2)
	eq(def.upgrades[1].stats.cooldown_time, 75, "Mk2 cooldown") eq(def.upgrades[2].stats.cooldown_time, 75, "Mk3 keeps it")
	eq(def.attributes.attr_spec_homing, true)
	eq(def.upgrades[2].upgrade_attributes.attr_power, 5)
	eq(type(def.on_activate), "function")
end)

test("the_code_collides_with_no_game_code_either_way", function()
	local mine = ""
	for _, arrow in ipairs(homing.CODE) do mine = mine .. LETTER[arrow] end
	eq(#VANILLA, 55, "every game code")
	for _, code in ipairs(VANILLA) do
		yes(code ~= mine, "the same as " .. code)
		yes(mine:sub(1, #code) ~= code, code .. " is a start of it, and fires first")
		yes(code:sub(1, #mine) ~= mine, "it is a start of " .. code .. ", which could never be entered")
	end
end)

test("mk1_and_mk2_fire_the_same_barrage_and_mk3_a_bigger_one", function()
	eq(homing.mk(0), 1) eq(homing.mk(nil), 1) eq(homing.mk(1), 2) eq(homing.mk(2), 3) eq(homing.mk(3), 3, "both levels bought")
	local want = { { 5, 0.5 }, { 5, 0.5 }, { 7, 0.4 } }
	for mk, w in ipairs(want) do
		local count, gap = homing.salvo(mk)
		eq(count, w[1], "Mk" .. mk .. " missiles") near(gap, w[2], "Mk" .. mk .. " gap")
		local times = homing.schedule(mk)
		eq(#times, w[1])
		eq(times[1], 0, "the first at the call-in")
		near(times[#times], (w[1] - 1) * w[2], "the last")
	end
end)

test("every_missile_starts_high_above_the_beacon_and_flies_at_it", function()
	local beacon = { x = 10, y = -4, z = 2 }
	local angles = {}
	for i = 1, 7 do
		local start, dir = homing.shot(i, 7, beacon)
		near(start.z, beacon.z + homing.HEIGHT, "height")
		near(math.sqrt((start.x - beacon.x) ^ 2 + (start.y - beacon.y) ^ 2), homing.SPREAD, "off the line above the beacon")
		near(math.sqrt(dir.x ^ 2 + dir.y ^ 2 + dir.z ^ 2), 1, "a direction a unit long")
		yes(dir.z < -0.99, "near straight down")
		yes(math.abs(dir.x) + math.abs(dir.y) > 0.01, "a little tilt, so the missile has a forward")
		-- Followed down to the beacon's height, the line meets the beacon.
		local t = (beacon.z - start.z) / dir.z
		near(start.x + dir.x * t, beacon.x, "lands on x") near(start.y + dir.y * t, beacon.y, "lands on y")
		angles[#angles + 1] = math.atan2(start.y - beacon.y, start.x - beacon.x) % (2 * math.pi)
	end
	-- The five of a Mk1 call come from every side: no gap between two starts wider than a third of a turn.
	local five = { unpack(angles, 1, 5) }
	table.sort(five)
	local widest = five[1] + 2 * math.pi - five[#five]
	for i = 2, #five do widest = math.max(widest, five[i] - five[i - 1]) end
	yes(widest < 2 * math.pi / 3, "a side left out: " .. widest)
end)

test("a_barrage_fires_on_time_with_plain_numbers_and_the_thrower_as_owner", function()
	local shots, clock = {}, 0
	local b = homing.new(function(start, dir, owner)
		shots[#shots + 1] = { at = clock, start = start, dir = dir, owner = owner }
		return "missile"
	end)
	b:call({ x = 1, y = 2, z = 3 }, 1, "thrower")
	eq(#shots, 1, "the first at once")
	for _ = 1, 60 do
		clock = clock + 0.05
		b:tick(0.05)
	end
	eq(#shots, 5, "Mk2: five")
	for i, s in ipairs(shots) do
		-- On the first frame that reaches the time, so within one frame of it.
		local late = s.at - (i - 1) * 0.5
		yes(late > -1e-6 and late < 0.05 + 1e-6, "missile " .. i .. " on time, " .. late .. " late")
		eq(s.owner, "thrower")
		eq(getmetatable(s.start), nil, "plain numbers")
	end
	yes(b:idle(), "done")
	-- Two at once run side by side; a long frame fires what it owes.
	b:call({ x = 0, y = 0, z = 0 }, 0, "a")
	b:call({ x = 50, y = 0, z = 0 }, 3, "b")
	b:tick(10)
	eq(#shots, 5 + 5 + 7)
	yes(b:idle())
end)

test("each_missile_is_handed_an_enemy_and_every_enemy_gets_one_first", function()
	eq(homing.target(1, {}), nil, "none around") eq(homing.target(1, nil), nil)
	eq(homing.target(1, { "a", "b" }), "a") eq(homing.target(2, { "a", "b" }), "b") eq(homing.target(3, { "a", "b" }), "a", "round again")
	local targets = {}
	local b = homing.new(function(_, _, _, target) targets[#targets + 1] = target or "none" return true end, nil, function(job)
		eq(job.x, 4, "asked about the beacon")
		return { "near", "far" }
	end)
	b:call({ x = 4, y = 0, z = 0 }, 0)
	b:tick(10)
	eq(table.concat(targets, " "), "near far near far near")
	-- A list that fails leaves the missile to look for one itself.
	local got = {}
	local c = homing.new(function(_, _, _, target) got[#got + 1] = target == nil return true end, nil, function() error("no list") end)
	c:call({ x = 0, y = 0, z = 0 }, 0)
	eq(got[1], true)
end)

test("a_missile_that_fails_ends_the_barrage_and_says_why", function()
	local said = {}
	local tries = 0
	local b = homing.new(function()
		tries = tries + 1
		if tries == 2 then return nil, "not_cleared" end
		return "missile"
	end, function(t) said[#said + 1] = t end)
	b:call({ x = 0, y = 0, z = 0 }, 0)
	b:tick(0.5)
	b:tick(0.5)
	eq(tries, 2, "nothing after the failure")
	yes(b:idle())
	yes(said[1] and said[1]:find("not_cleared", 1, true), "said in the log")
	-- An error in fire is caught too.
	local broken = homing.new(function() error("engine") end, function(t) said[#said + 1] = t end)
	broken:call({ x = 0, y = 0, z = 0 }, 0)
	yes(broken:idle())
	yes(said[2]:find("engine", 1, true))
	-- clear drops the rest.
	local count = 0
	local c = homing.new(function() count = count + 1 return true end)
	c:call({ x = 0, y = 0, z = 0 }, 2)
	c:clear()
	c:tick(5)
	eq(count, 1, "only the first went")
end)

test("a_landed_beacon_calls_the_barrage_and_never_drops_the_airstrike", function()
	local got = nil
	local def = homing.def(function(pos, upgrade, owner) got = { pos = pos, upgrade = upgrade, owner = owner } end)
	local vector = setmetatable({}, { __index = function(_, k) return ({ x = 1, y = 2, z = 3 })[k] end })
	eq(def.on_activate({ name = homing.NAME, position = vector, upgrade = 3, owner = "thrower" }), false, "no airstrike")
	eq(got.pos.x, 1) eq(got.pos.z, 3) eq(rawequal(got.pos, vector), false, "plain numbers, not the vector")
	eq(got.upgrade, 3) eq(got.owner, "thrower")
	local saved = obsidian.log
	local logged = nil
	obsidian.log = function(t) logged = t end
	eq(homing.def(function() error("broken") end).on_activate({ position = vector, upgrade = 0 }), false)
	obsidian.log = saved
	yes(logged and logged:find("broken", 1, true), "said in the log")
	-- With an Obsidian API that can't fire the missiles, the use goes back.
	local refused = nil
	eq(homing.def(nil, function(owner) refused = owner end).on_activate({ position = vector, upgrade = 0, owner = "thrower" }), false)
	eq(refused, "thrower")
	yes(seaf.at_least("1.44.0", homing.FIRE_API), "1.44.0 fires them")
	eq(seaf.at_least("1.43.0", homing.FIRE_API), false, "1.43.0 can't hand a missile a target")
end)

-- The words players read, by the rules of tests/test_texts.lua, and in the game's style: each upgrade
-- text replaces the one before in the menus, so it restates the whole.
local BANNED = { "its", "you", "your", "yours", "i", "me", "my", "we", "our", "us" }
local function check(text, what, digits)
	local lower = " " .. text:lower():gsub("[^%w'%-]", " ") .. " "
	for _, word in ipairs(BANNED) do
		yes(not lower:find(" " .. word .. " ", 1, true), what .. ' says "' .. word .. '"')
	end
	yes(not text:lower():find("it\39s", 1, true), what .. " has the short form of it is")
	yes(not text:find("\226\128\148", 1, true) and not text:find("\226\128\147", 1, true), what .. " has a long dash")
	yes(not text:find(" %- "), what .. " has a dash between words")
	yes(not text:find("%w's%f[%W]"), what .. " has a possessive")
	yes(digits or not text:find("%d"), what .. " has a digit: counts are words")
	yes(not text:find("%%") and not text:lower():find("second", 1, true), what .. " has a time or a percentage")
end

test("the_words_keep_the_rules_and_each_level_restates_the_one_before", function()
	check(homing.TITLE, "the title")
	check(homing.DESCRIPTION, "the description")
	for i, u in ipairs(homing.UPGRADES) do
		check(u.title, "upgrade " .. i .. " title", true)
		check(u.description, "upgrade " .. i .. " description")
	end
	yes(homing.DESCRIPTION:find("five homing missiles", 1, true), "the count")
	yes(homing.DESCRIPTION:find("NOT spare Helldivers", 1, true), "the caveat")
	local mk2, mk3 = homing.UPGRADES[1].description, homing.UPGRADES[2].description
	yes(mk2:find("five homing missiles", 1, true) and mk3:find("seven homing missiles", 1, true), "the counts")
	yes(mk2:find("NOT spare Helldivers", 1, true) and mk3:find("NOT spare Helldivers", 1, true), "the caveat stays")
	yes(mk2:find("called more often", 1, true), "the Mk2 change")
	yes(mk3:find("called more often", 1, true) and mk3:find("quicker succession", 1, true), "Mk3 restates Mk2 and adds the release")
	-- Every sentence of the base is there, in the same order.
	local last = 0
	for sentence in homing.DESCRIPTION:gmatch("[^%.]+%.") do
		local at = mk2:find(sentence, 1, true)
		yes(at and at > last, "Mk2 restates: " .. sentence)
		last = at
	end
end)

-- The icon and material names must be ones tools/build_icon.py writes into res/icons.material: a gui
-- asked for a sub-material the material lacks stops the game.
test("the_icon_is_one_the_build_script_writes", function()
	local f = assert(io.open("tools/build_icon.py", "r"))
	local text = f:read("*a")
	f:close()
	yes(text:find('("' .. homing.ICON .. '", "more_stratagems/' .. homing.ICON .. '"', 1, true), "sub-material in PNG_ICONS")
	eq(text:match('\nMATERIAL = "([^"]+)"'), homing.ICON_MATERIAL, "material name")
end)

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

-- The game's Airstrike entry (lua/settings/loadout_settings.lua), and the game's way to read a level:
-- the entry with every bought level laid over it, one bit per level (BitAux.is_bit_set).
local function loadout()
	local airstrike = {
		name = "stratagem_airstrike", id = 2, activate_sound = "radio_offense_confirm", activation_time = 2, cooldown_time = 90,
		description = "stratagem_airstrike_d", despawn_time = 1, flare_type = "danger", icon = "stratagem_airstrike",
		stratagem_type = "offensive", unit = "gameobjects/airstrike_01", combo = { "right", "up", "down", "right", "left" },
		stratagem_subtypes = { "strike" }, attributes = { attr_power = 3, attr_spec_explosive = true },
		upgrades = {
			{ cost = 2, upgrade_description = "stratagem_airstrike_d_mk2", upgrade_name = "stratagem_airstrike_mk2", upgrade_attributes = { attr_power = 4 } },
			{ cost = 2, upgrade_description = "stratagem_airstrike_d_mk3", upgrade_name = "stratagem_airstrike_mk3", upgrade_attributes = { attr_power = 5 } },
		},
	}
	local s = { stratagems = { { name = "stratagem_resupply", id = 1, combo = { "down", "down", "up", "right" }, upgrades = {} }, airstrike } }
	function s.get_upgraded_stratagem(id, value)
		local e = s.stratagems[id]
		local out = {}
		for k, v in pairs(e) do out[k] = v end
		for level, u in ipairs(e.upgrades or {}) do
			if math.floor((value or 0) / 2 ^ (level - 1)) % 2 == 1 then
				for k, v in pairs(u) do out[k] = v end
			end
		end
		return out
	end
	return s
end

-- The flare's countdown (lua/components/stratagem_component.lua:72), with Precision Call-In's -1
-- (perk_settings.lua: set_stratagem_extra_activation_time).
local PRECISION = -1
local function countdown(ls, id, value, extra)
	return math.max(0.1, ls.get_upgraded_stratagem(id, value).activation_time + extra)
end

test("obsidian_api_takes_the_entry_and_precision_call_in_shortens_it", function()
	local path = api_file()
	if not path then return "skip" end
	local stubs = {
		["lib/game"] = { global = function(name) return rawget(_G, name) end },
		["lib/catalog"] = { xp_and_rewards = function() return 0 end, unlocked = function() return false end },
	}
	local saved = { module = obsidian.module, storage = obsidian.storage, caller = obsidian.caller, hook = obsidian.hook, ui = obsidian.ui,
		log = obsidian.log, session = obsidian.session }
	local saved_ls = rawget(_G, "LoadoutSettings")
	local ls = loadout()
	rawset(_G, "LoadoutSettings", ls)
	obsidian.module = function(name) return stubs[name] or saved.module(name) end
	obsidian.storage = { get = function() return nil end, set = function() end }
	obsidian.caller = function() return "obsidian.api" end
	obsidian.hook = function() end
	obsidian.log = function() end
	obsidian.ui = { art = function(id, opts) return id == homing.ICON and opts.path == homing.ICON_MATERIAL end }
	local cleared = true
	obsidian.session = { cleared = function() return cleared end }
	local ok, err = pcall(function()
		local custom = dofile(path)
		local made, why = custom.define(homing.def())
		yes(made, "defined: " .. tostring(why))
		local e = ls.stratagems[made.id]
		eq(e.cooldown_time, 90, "cooldown")
		eq(e.activation_time, 1.5, "call-in")
		eq(e.num_uses, nil, "unlimited")
		eq(e.icon, homing.ICON)
		eq(e.flare_type, "danger", "the Airstrike's red beacon")
		eq(table.concat(e.combo, " "), "right down down right down")
		eq(e.stratagem_type, "offensive")
		eq(e.upgrades[1].upgrade_name, "stratagem_homing_payload_mk2")
		eq(e.upgrades[2].cost, 2)
		-- The thrower's flare reads the real entry at the level bought: 1.5 seconds, 0.5 with the perk.
		for _, value in ipairs({ 0, 1, 2, 3 }) do
			near(countdown(ls, made.id, value, 0), 1.5, "call-in at upgrade value " .. value)
			near(countdown(ls, made.id, value, PRECISION), 0.5, "with Precision Call-In at upgrade value " .. value)
		end
		-- In a lobby that isn't cleared the stratagem is the Airstrike: 2 seconds, 1 with the perk, as
		-- other players count it.
		cleared = false
		near(countdown(ls, made.id, 0, PRECISION), 1, "the base's time")
		cleared = true
		-- The same def twice is refused rather than added twice.
		local again, taken = custom.define(homing.def())
		eq(again, nil) eq(taken, "taken")
	end)
	for k, v in pairs(saved) do obsidian[k] = v end
	rawset(_G, "LoadoutSettings", saved_ls)
	if not ok then error(err, 0) end
end)

return T
