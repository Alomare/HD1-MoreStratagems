-- The SEAF look against a fake CustomizationSettings with the game's list sizes (24 helmets, 22 bodies, 41
-- capes) and the game's entry shapes. Each test loads a fresh copy of the module.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function fresh() return dofile("src/seaf_look.lua") end

-- The game's lists: entries named as in lua/settings/customization_settings.lua, the defaults first and the
-- snow variants at 4. Bodies carry a unit for each gender.
local function game_settings()
	local helmet = { icon = "icon_customization_helmet", icon_unlock = "icon_unlock_custom_helmet" }
	local body = { icon = "icon_customization_armor", icon_unlock = "icon_unlock_custom_armor" }
	local cape = { icon = "icon_customization_cape", icon_unlock = "icon_unlock_custom_cape" }
	local helmets = { "cus_helmet_tactical", "cus_helmet_tacticaldesert", "cus_helmet_tacticalforest", "cus_helmet_tacticalsnow" }
	local bodies = { "cus_body_default", "cus_body_defaultdesert", "cus_body_defaultforest", "cus_body_defaultsnow" }
	for i = 1, 24 do
		helmet[i] = { name = helmets[i] or ("cus_helmet_" .. i), unit_path = "characters/helmet_" .. i }
	end
	for i = 1, 22 do
		local n = bodies[i] or ("cus_body_" .. i)
		body[i] = { name = n, male = { unit_path = "characters/" .. n .. "_male" }, female = { unit_path = "characters/" .. n .. "_female" } }
	end
	for i = 1, 41 do
		cape[i] = { name = i == 1 and "cus_cape_default" or i == 12 and "cus_cape_ceremonial" or ("cus_cape_" .. i), unit_path = "characters/cape_" .. i }
	end
	return { helmet = helmet, body = body, cape = cape, gender = { { name = "male" }, { name = "female" } } }
end

-- Runs fn(look, settings, env) with the game's globals and the loader's calls faked, and puts everything back.
local function with_game(opts, fn)
	opts = opts or {}
	local saved = { obsidian = obsidian, cs = rawget(_G, "CustomizationSettings") }
	local env = { logged = {}, wraps = {}, requires = {}, option = opts.option == nil and true or opts.option }
	obsidian = {
		module = saved.obsidian.module,
		capabilities = { wrap = true },
		settings = { get = function(id)
			if opts.broken_settings then error("settings are not ready") end
			if id == "custom_armor" then return env.option end
		end },
		log = function(text) env.logged[#env.logged + 1] = text end,
		wrap = function(target, method, f) env.wraps[#env.wraps + 1] = { target, method, f } end,
		on_require = function(name, f) env.requires[#env.requires + 1] = { name, f } end,
	}
	local cs = not opts.no_settings and game_settings() or nil
	if opts.edit then opts.edit(cs) end
	rawset(_G, "CustomizationSettings", cs)
	local ok, err = pcall(fn, fresh(), cs, env)
	obsidian = saved.obsidian
	rawset(_G, "CustomizationSettings", saved.cs)
	if not ok then error(err, 0) end
end

test("option_off_changes_nothing", function()
	with_game({ option = false }, function(look, cs)
		eq(look.install(), nil, "install with the option off")
		eq(#cs.helmet, 24, "helmets") eq(#cs.body, 22, "bodies") eq(#cs.cape, 41, "capes")
		eq(look.indexes(), nil, "indexes with the option off")
	end)
end)

test("install_adds_three_entries_at_the_end_and_returns_their_indexes", function()
	with_game(nil, function(look, cs)
		local got = look.install()
		yes(got, "indexes")
		eq(got.helmet, 25, "helmet index") eq(got.body, 23, "body index") eq(got.cape, 42, "cape index")
		eq(cs.helmet[25].name, "cus_helmet_seaf")
		eq(cs.helmet[25].unit_path, "more_stratagems/armor/seaf_helmet")
		eq(cs.body[23].name, "cus_body_seaf")
		eq(cs.body[23].male.unit_path, "more_stratagems/armor/seaf_body_male")
		eq(cs.body[23].female.unit_path, "more_stratagems/armor/seaf_body_female")
		eq(cs.cape[42].name, "cus_cape_seaf")
		eq(cs.cape[42].unit_path, "more_stratagems/armor/seaf_cape")
		eq(#cs.helmet, 25) eq(#cs.body, 23) eq(#cs.cape, 42)
		yes(got.helmet < 256 and got.body < 256 and got.cape < 256, "one byte on the wire")
		-- The group's own fields stay.
		eq(cs.helmet.icon, "icon_customization_helmet")
	end)
end)

test("the_games_own_entries_are_not_changed_or_shared", function()
	with_game(nil, function(look, cs)
		look.install()
		eq(cs.helmet[1].name, "cus_helmet_tactical") eq(cs.helmet[1].unit_path, "characters/helmet_1")
		eq(cs.body[1].name, "cus_body_default") eq(cs.body[1].male.unit_path, "characters/cus_body_default_male")
		eq(cs.cape[1].name, "cus_cape_default") eq(cs.cape[1].unit_path, "characters/cape_1")
		yes(cs.body[23].male ~= cs.body[1].male, "the male table is a copy")
		yes(cs.body[23].female ~= cs.body[1].female, "the female table is a copy")
	end)
end)

test("install_is_idempotent", function()
	with_game(nil, function(look, cs)
		local a = look.install()
		local b = look.install()
		eq(b.helmet, a.helmet) eq(b.body, a.body) eq(b.cape, a.cape)
		eq(#cs.helmet, 25) eq(#cs.body, 23) eq(#cs.cape, 42)
		-- Another copy of the module in the same game finds the entries and adds none.
		local c = fresh().install()
		eq(c.helmet, 25) eq(#cs.helmet, 25)
	end)
end)

test("indexes_follows_the_option_and_the_lists", function()
	with_game(nil, function(look, cs, env)
		eq(look.indexes(), nil, "before install")
		look.install()
		local got = look.indexes()
		eq(got.helmet, 25) eq(got.body, 23) eq(got.cape, 42)
		got.helmet = 1
		eq(look.indexes().helmet, 25, "the answer is a copy")
		env.option = false
		eq(look.indexes(), nil, "option off")
		env.option = true
		cs.cape[42] = { name = "other", unit_path = "x" }
		eq(look.indexes(), nil, "an entry that is not ours")
	end)
end)

test("uninstall_removes_the_entries_and_is_safe_twice", function()
	with_game(nil, function(look, cs)
		look.install()
		look.uninstall()
		eq(#cs.helmet, 24) eq(#cs.body, 22) eq(#cs.cape, 41)
		eq(look.indexes(), nil)
		look.uninstall()
		eq(#cs.helmet, 24, "second uninstall")
		eq(look.install().helmet, 25, "installs again at the same place")
	end)
end)

test("uninstall_keeps_every_other_index_in_place", function()
	with_game(nil, function(look, cs)
		look.install()
		cs.helmet[26] = { name = "another_mods_helmet", unit_path = "y" }
		look.uninstall()
		eq(#cs.helmet, 26, "no hole and no shift")
		eq(cs.helmet[26].name, "another_mods_helmet")
		eq(cs.helmet[25].name, "cus_helmet_tactical", "the slot holds the default piece")
		eq(#cs.body, 22) eq(#cs.cape, 41)
	end)
end)

test("fallback_is_the_snow_helmet_and_body_and_the_ceremonial_cape", function()
	with_game(nil, function(look, cs)
		local f = look.fallback()
		eq(f.helmet, 4) eq(f.body, 4) eq(f.cape, 12)
		eq(cs.helmet[f.helmet].name, "cus_helmet_tacticalsnow")
		eq(cs.body[f.body].name, "cus_body_defaultsnow")
		eq(cs.cape[f.cape].name, "cus_cape_ceremonial")
		f.helmet = 99
		eq(look.fallback().helmet, 4, "a fresh table each time")
	end)
	with_game({ option = false }, function(look)
		eq(look.fallback().body, 4)
	end)
end)

test("install_fails_closed", function()
	with_game({ no_settings = true }, function(look)
		eq(look.install(), nil, "no settings table")
		eq(look.indexes(), nil)
	end)
	with_game({ edit = function(cs) cs.cape[1].name = "renamed" end }, function(look, cs)
		eq(look.install(), nil, "no default cape")
		eq(#cs.helmet, 24, "nothing added to the helmets either")
		eq(#cs.body, 22)
	end)
	with_game({ edit = function(cs) cs.body = nil end }, function(look, cs)
		eq(look.install(), nil, "no body list")
		eq(#cs.helmet, 24)
	end)
	with_game({ broken_settings = true }, function(look, cs, env)
		eq(look.install(), nil, "the option cannot be read")
		eq(#cs.helmet, 24)
	end)
end)

test("shared_needs_everyone_on_one_mod_set", function()
	local look = fresh()
	yes(look.shared({}), "alone")
	yes(look.shared(nil), "no list")
	yes(look.shared({ { peer = 1, obsidian = true, modset = "a" }, { peer = 2, obsidian = true, modset = "a" } }), "same set")
	eq(look.shared({ { peer = 1, obsidian = true, modset = "a" }, { peer = 2, obsidian = true, modset = "b" } }), false, "different sets")
	eq(look.shared({ { peer = 1, obsidian = false } }), false, "a player without Obsidian")
	eq(look.shared({ { peer = 1, obsidian = true, modset = "a" }, { peer = 2, obsidian = false } }), false, "one of two without")
end)

test("pick_gives_the_set_only_when_it_is_safe", function()
	with_game(nil, function(look)
		eq(look.pick({}).helmet, 4, "not installed yet")
		look.install()
		eq(look.pick({}).helmet, 25, "alone")
		eq(look.pick({ { peer = 1, obsidian = true, modset = "a" } }).body, 23, "with a player on one set")
		eq(look.pick({ { peer = 1, obsidian = false } }).cape, 12, "with a vanilla player")
	end)
end)

test("strip_menu_drops_our_entries_from_every_list_but_gender", function()
	with_game(nil, function(look, cs)
		look.install()
		local function opts(kind) local c = {} for i, e in ipairs(cs[kind]) do c[i] = e end return c end
		local menu = { options = {
			{ type = "helmet", selected_option = 25, options = opts("helmet") },
			{ type = "body", selected_option = 3, options = opts("body") },
			{ type = "cape", selected_option = 1, options = opts("cape") },
			{ type = "gender", selected_option = 1, options = { { name = "male" }, { name = "female" } } },
		} }
		look.strip_menu(menu)
		eq(#menu.options[1].options, 24) eq(#menu.options[2].options, 22) eq(#menu.options[3].options, 41)
		eq(#menu.options[4].options, 2)
		eq(menu.options[1].selected_option, 24, "a selection past the end is brought back")
		eq(menu.options[2].selected_option, 3)
		look.strip_menu(nil)
		look.strip_menu({})
	end)
end)

test("guard_menu_wraps_on_enter_and_cleans_after_it", function()
	with_game(nil, function(look, cs, env)
		look.install()
		look.guard_menu()
		look.guard_menu()
		eq(#env.wraps, 1, "wrapped once")
		eq(env.wraps[1][1], "MenuScreenArmoryProfile") eq(env.wraps[1][2], "on_enter")
		local menu = { options = { { type = "helmet", selected_option = 1, options = { cs.helmet[1], cs.helmet[25] } } } }
		local calls = {}
		local function original(self, a, b) calls[#calls + 1] = { self, a, b } return "r1", "r2" end
		local r1, r2 = env.wraps[1][3](original, menu, "x", "y")
		eq(r1, "r1") eq(r2, "r2")
		eq(calls[1][1], menu) eq(calls[1][2], "x") eq(calls[1][3], "y")
		eq(#menu.options[1].options, 1, "the entry is gone after the original ran")
		-- A menu the cleaner cannot read does not stop the original's results.
		local r = env.wraps[1][3](function() return "ok" end, nil)
		eq(r, "ok")
	end)
end)

test("start_installs_now_and_when_the_game_loads_the_settings", function()
	with_game(nil, function(look, cs, env)
		look.start()
		eq(#cs.helmet, 25, "installed at once")
		eq(#env.requires, 1) eq(env.requires[1][1], "lua/settings/customization_settings")
		eq(#env.wraps, 1, "menu guard")
		-- The game builds new lists later: the callback installs into them.
		local later = game_settings()
		rawset(_G, "CustomizationSettings", later)
		env.requires[1][2](later)
		eq(#later.helmet, 25, "installed into the lists the game built")
		eq(look.indexes().body, 23)
	end)
	with_game({ option = false }, function(look, cs, env)
		look.start()
		eq(#cs.helmet, 24, "option off")
	end)
	-- With none of the loader's calls at all, start does nothing and does not error.
	local saved = obsidian
	obsidian = { module = saved.module }
	local ok = pcall(function() fresh().start() end)
	obsidian = saved
	yes(ok, "start without the loader's calls")
end)

test("no_comment_or_text_uses_the_banned_words", function()
	local f = io.open("src/seaf_look.lua", "r")
	local text = f:read("*a")
	f:close()
	for word in text:lower():gmatch("%a+'?%a*") do
		if word == "i" .. "ts" or word == "it'" .. "s" then error("a banned word is in src/seaf_look.lua: " .. word) end
	end
	yes(not text:find("\226\128\148") and not text:find("\226\128\147"), "an em or en dash")
end)

return T
