-- The AD-342 'Hot Dog': the entry, the code, the texts, the flamer and the drone variants built from the
-- FLAM-24 and the Guard Dog, the hellpod marker, and the runtime against a small stand-in for the engine,
-- LuaSettingsManager and the firearm component.
local hd = obsidian.module("src/hot_dog")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function near(got, want, what)
	if math.abs(got - want) > 1e-9 then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

-- The game's numbers, as lifted (equipment/equipment_drone_defensive_01.lua, equipment/wep_flamepistol_01.lua).
local function guard_dog()
	return {
		drone_info = { check_for_target_interval = 1, check_for_target_radius = 10, max_inactivity_time = 20, max_speed = 10, min_speed = 1,
			turn_speed = 0.2, turn_speed_firing = 0.1, turn_speed_patrol = 0.4 },
		weapon_info = { effect_hit = "projectile", firerate = 500, magazine_capacity = 50, magazines = 1, magazines_max = 1, power = 50, range = 18, spread = 8,
			attributes = { armorpiercing = false, fixed_spread = true, fully_automatic = true }, ray_source_offset = { x = 0, y = 0, z = 0.75 } },
		upgrade_info = {
			{ drone_info = { move_while_firing = true } },
			{ weapon_info = { attributes = { armorpiercing = true, ignore_status_effects_if_no_damage = true }, hit_status_effects = { "bullet_stun" } } },
		},
	}
end

local function pyro()
	return { weapon_info = { effect_hit = "flamethrower", effect_scale = 0.75, flame_effect_close_name = "effects/generated/wep_flamethrower_fire_close",
		flame_effect_name = "effects/generated/wep_flamepistol_fire", low_ammo_warning = 10, magazine_capacity = 50, magazines = 3, magazines_max = 6,
		max_range = 8, min_range = 1, move_speed_aim = 1, move_speed_reload = 1, power = 200, power_crit = 200, range_increase_per_second = 60,
		reload_duration = 2, reload_duration_fast = 2, rounds_per_second = 10, spread = 0, turn_speed_aim = 1, turn_speed_fire = 0.6,
		attributes = { armorpiercing = false, chambered = false, fully_automatic = true, ignore_status_effects_if_no_damage = true, semi_automatic = true, sidearm = true },
		ray_source_offset = { x = 0.22, y = 0, z = 1.5 }, hit_status_effects = { "heavy_burn" },
		area_effect = { max_power = 32, spawn_delay = 0.3, spawn_object_name = "gameobjects/gameobject_flamepistol_napalm_area", spawn_offset = 6, spawn_max_distance_sqd = 0.25 } } }
end

local function protect(t)
	return setmetatable({ __protected_table = t }, { __index = t, __newindex = function() error("constant") end })
end

-- The game's level of a settings table, as create_upgrade_settings_permutations makes it.
local function level(base, n)
	local v = hd.copy(base)
	local function over(t, o)
		for k, x in pairs(o) do
			if type(x) == "table" and type(t[k]) == "table" then over(t[k], x) else t[k] = hd.copy(x) end
		end
	end
	for i = 1, n do over(v, base.upgrade_info[i]) end
	return v
end

test("the_entry_is_the_guard_dog_with_new_words_and_icon", function()
	local def = hd.def()
	eq(def.name, "stratagem_drone_hot_dog")
	eq(def.base, "stratagem_drone_defensive_backpack")
	eq(def.title, "AD-342 'Hot Dog'")
	eq(def.type, "supply", "blue")
	eq(def.icon, "hot_dog_icon")
	eq(def.icon_material, "more_stratagems/icons")
	eq(table.concat(def.code, " "), "down up left up right right")
	eq(def.stats, nil, "uses, cooldown and call-in are the Guard Dog's")
	eq(def.unit, nil, "the Guard Dog's crate lands")
	eq(def.unlock, nil, "unlocked with the Guard Dog")
	eq(def.on_activate, nil)
	eq(def.attributes.attr_spec_incendiary, true) eq(def.attributes.attr_spec_backpack, true)
	eq(#def.upgrades, 2)
	eq(def.upgrades[1].cost, 2) eq(def.upgrades[2].cost, 2)
	eq(def.upgrades[1].title, "AD-342 'Hot Dog' Mk2")
	eq(def.upgrades[2].title, "AD-342 'Hot Dog' Mk3")
	eq(def.upgrades[1].attributes.attr_spec_move_and_fire, true, "Mk2 tag, as the Guard Dog Mk2")
	eq(def.upgrades[2].attributes.attr_spec_armorpiercing, true) eq(def.upgrades[2].attributes.attr_spec_ministun, true)
end)

-- Every vanilla code (lua/settings/loadout_settings.lua).
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

test("the_code_is_neither_a_code_of_the_game_or_the_mod_nor_a_prefix_of_one", function()
	eq(#VANILLA, 55, "all vanilla codes")
	local mine = table.concat(hd.CODE, " ")
	local others = {}
	for _, c in ipairs(VANILLA) do others[#others + 1] = c end
	for _, path in ipairs({ "src/homing_payload.lua", "src/perforator_turret.lua" }) do
		local mod = dofile(path)
		others[#others + 1] = table.concat(mod.CODE, " ")
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
	check(hd.TITLE, "the title")
	check(hd.DESCRIPTION, "the description")
	local opening = "The AD-342 'Hot Dog' is a defensive automated drone armed with the compact flamer of the FLAM-24 'Pyro'."
	for i, u in ipairs(hd.UPGRADES) do
		check(u.title, "upgrade " .. i .. " title")
		check(u.description, "upgrade " .. i .. " description")
		eq(u.description:sub(1, #opening), opening, "upgrade " .. i .. " restates the base")
		yes(u.description:find("NOT spare Helldivers", 1, true), "upgrade " .. i .. " keeps the warning")
	end
	yes(hd.UPGRADES[1].description:find("move and fire", 1, true), "Mk2 says the change")
	yes(hd.UPGRADES[2].description:find("move and fire", 1, true) and hd.UPGRADES[2].description:find("pierce armor", 1, true), "Mk3 restates Mk2 and adds AP and stun")
end)

test("the_flamer_is_the_pyro_and_mk3_adds_ap_and_the_stun", function()
	local game = pyro().weapon_info
	local before = hd.copy(game)
	local p = hd.flame_from(protect(game))
	eq(p.power, 200) eq(p.power_crit, 200) eq(p.effect_hit, "flamethrower")
	eq(p.min_range, 1) eq(p.max_range, 8) eq(p.range_increase_per_second, 60) eq(p.rounds_per_second, 10) eq(p.magazine_capacity, 50)
	eq(p.flame_effect_name, "effects/generated/wep_flamepistol_fire")
	eq(p.flame_effect_close_name, "effects/generated/wep_flamethrower_fire_close")
	eq(p.attributes.armorpiercing, false) eq(p.attributes.ignore_status_effects_if_no_damage, true)
	eq(#p.hit_status_effects, 1) eq(p.hit_status_effects[1], "heavy_burn")
	eq(p.area_effect.spawn_object_name, "gameobjects/gameobject_flamepistol_napalm_area")
	near(p.area_effect.spawn_delay, 0.3) eq(p.area_effect.spawn_offset, 6) near(p.area_effect.spawn_max_distance_sqd, 0.25)
	local mk = {}
	for l = 0, 2 do mk[l] = hd.flame(p, l) end
	eq(mk[0].attributes.armorpiercing, false) eq(mk[1].attributes.armorpiercing, false)
	eq(mk[2].attributes.armorpiercing, true, "Mk3 pierces armor")
	eq(#mk[1].hit_status_effects, 1)
	eq(table.concat(mk[2].hit_status_effects, " "), "heavy_burn bullet_stun", "Mk3 burns and stuns")
	yes(mk[0] ~= p and mk[2].hit_status_effects ~= p.hit_status_effects, "own tables")
	eq(#p.hit_status_effects, 1, "the base flamer stays")
	yes(hd.same(game, before), "the FLAM-24's settings stay as they were")
end)

test("the_flamer_numbers_fall_back_one_by_one", function()
	local p = hd.flame_from({ power = 0 / 0, max_range = "far", min_range = 30, flame_effect_name = "", rounds_per_second = 20, hit_status_effects = { 5 } })
	eq(p.power, 200, "not a number") eq(p.max_range, 8, "wrong type") eq(p.rounds_per_second, 20, "the game's")
	eq(p.min_range, 1, "a minimum past the maximum") eq(p.flame_effect_name, "effects/generated/wep_flamepistol_fire", "empty name")
	eq(p.hit_status_effects[1], "heavy_burn", "no status names")
	local none = hd.flame_from(nil)
	eq(none.power, 200) eq(none.area_effect.spawn_offset, 6) eq(none.attributes.armorpiercing, false)
end)

test("the_drone_variants_carry_the_pyro_magazine_and_the_guard_dog_levels", function()
	local dog = guard_dog()
	local before = hd.copy(dog)
	local p = hd.flame_from(pyro().weapon_info)
	local mk = {}
	for l = 0, 2 do mk[l] = hd.variant(protect(dog), l, p) end
	for l = 0, 2 do
		local w, d = mk[l].weapon_info, mk[l].drone_info
		eq(w.firerate, 600, "10 a second, as the Pyro")
		eq(w.magazine_capacity, 50, "the Pyro's magazine")
		eq(d.check_for_target_radius, 8, "targets within the flame's reach")
		eq(w.attributes.fully_automatic, true, "the firearm still counts the rounds")
		eq(w.ray_source_offset.z, 0.75, "the drone's muzzle")
		eq(d.max_speed, 10) eq(d.max_inactivity_time, 20)
		yes(w ~= dog.weapon_info and d ~= dog.drone_info, "own tables")
	end
	eq(mk[0].drone_info.move_while_firing, nil, "Mk1 stops to fire")
	eq(mk[1].drone_info.move_while_firing, true, "Mk2 moves while firing")
	eq(mk[2].drone_info.move_while_firing, true, "Mk3 keeps Mk2")
	yes(hd.same(dog, before), "the Guard Dog's settings stay as they were")
end)

test("the_marker_moves_only_a_hot_dog_drop_past_the_game_levels", function()
	for l = 0, 2 do
		local setup = { stratagem_info = { name = hd.NAME }, upgrade_value = l }
		yes(hd.mark(setup), "level " .. l)
		eq(setup.upgrade_value, l + 4)
	end
	local nothing = { stratagem_info = { name = hd.NAME } }
	yes(hd.mark(nothing)) eq(nothing.upgrade_value, 4, "no upgrade value is Mk1")
	local guard = { stratagem_info = { name = hd.BASE }, upgrade_value = 2 }
	yes(not hd.mark(guard)) eq(guard.upgrade_value, 2, "a Guard Dog keeps the game's")
	local twice = { stratagem_info = { name = hd.NAME }, upgrade_value = 5 }
	yes(not hd.mark(twice)) eq(twice.upgrade_value, 5, "already marked")
	yes(not hd.mark(nil)) yes(not hd.mark({ upgrade_value = 1 }))
end)

test("the_particle_is_the_pistol_choice_by_flame_length", function()
	local p = hd.flame_from(pyro().weapon_info)
	eq(hd.particle(p, 1, 1, false), p.flame_effect_close_name, "starts close")
	eq(hd.particle(p, 1.5, 1, true), nil, "keeps the close one")
	eq(hd.particle(p, 3, 1.5, true), p.flame_effect_name, "grows past 2 metres")
	eq(hd.particle(p, 4, 3, true), nil, "keeps the long one")
	eq(hd.particle(p, 1, 4, true), p.flame_effect_close_name, "shrinks against a wall")
	eq(hd.particle(p, 5, 5, false), p.flame_effect_name, "none yet, long")
end)

test("a_patch_needs_room_from_every_burning_one", function()
	local patches = { { x = 0, y = 0, z = 0 }, { x = 3, y = 0, z = 0 } }
	yes(not hd.room_for_patch({ x = 0.3, y = 0, z = 0 }, patches, 0.25), "within half a metre")
	yes(hd.room_for_patch({ x = 1, y = 0, z = 0 }, patches, 0.25), "a metre off")
	yes(hd.room_for_patch({ x = 0, y = 0, z = 0 }, {}, 0.25), "none burning")
end)

-- A stand-in game: vectors, units, LuaSettingsManager with the Guard Dog's levels, LoadoutSettings reading
-- each unit's upgrade value, a physics world that records casts, and the game's flame callback recording
-- what it was made with.
local function vec(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end })
end

local function game()
	local dog, gun = guard_dog(), pyro()
	local by_path = { [hd.DRONE] = protect(dog), [hd.PISTOL] = protect(gun), ["equipment/wep_assaultrifle_01"] = protect({ weapon_info = { firerate = 600 } }) }
	local g = { logs = {}, casts = {}, flows = {}, particles = {}, stopped = {}, spawned = {}, destroyed = {}, callbacks = {}, ground = vec(5, 5, 0) }
	g.vanilla = { [1] = protect(level(dog, 1)), [2] = protect(level(dog, 2)) }
	local lsm = { unit_path_to_modified_settings = { [hd.DRONE] = { [1] = g.vanilla[1], [2] = g.vanilla[2] } } }
	function lsm:get_settings_by_unit_path(p) return by_path[p] end
	function lsm:get_settings_path_by_unit_path(p) return p end
	function lsm:set_modified_settings(p, k, t)
		self.unit_path_to_modified_settings[p] = self.unit_path_to_modified_settings[p] or {}
		self.unit_path_to_modified_settings[p][k] = protect(t)
	end
	g.lsm = lsm
	local ls = { get_upgraded_settings = function(unit, v)
		v = v or unit.upgrade
		local m = lsm.unit_path_to_modified_settings[unit.path]
		return m and m[v] or by_path[unit.path]
	end }
	local particle_id = 0
	local W = {
		physics_world = function(world) return { world = world } end,
		spawn_unit = function(world, path) local u = { path = path, alive = true, visible = true } g.pistol = u return u end,
		link_unit = function(world, child, _, parent) child.parent = parent end,
		unlink_unit = function(world, child) child.parent = nil end,
		destroy_unit = function(world, u) u.alive = false g.destroyed[#g.destroyed + 1] = u end,
		create_particles = function(world, name) particle_id = particle_id + 1 g.particles[#g.particles + 1] = name return particle_id end,
		stop_spawning_particles = function(world, id) g.stopped[#g.stopped + 1] = id end,
	}
	local U = {
		world_position = function(u) return vec(u.x or 0, u.y or 0, u.z or 3) end,
		world_rotation = function(u) return "rotation" end,
		set_unit_visibility = function(u, on) u.visible = on end,
		alive = function(u) return u.alive end,
		flow_event = function(u, event) g.flows[#g.flows + 1] = (u.path == hd.PISTOL and "pistol " or "drone ") .. event end,
		set_flow_variable = function(u, name) g.flows[#g.flows + 1] = (u.path == hd.PISTOL and "pistol var " or "drone var ") .. name end,
	}
	local Q = { forward = function() return vec(1, 0, 0) end, rotate = function(_, v) return vec(v.x, v.y, v.z) end }
	local V = setmetatable({ zero = function() return vec(0, 0, 0) end }, { __call = function(_, x, y, z) return vec(x, y, z) end })
	local P = {
		-- The engine answers a cast later, in the physics step: here, at the next cast.
		make_raycast = function(pw, callback) return { cast = function(_, from, dir, range, id)
			if g.pending then g.pending() end
			g.casts[#g.casts + 1] = { from = from, range = range, id = id }
			g.pending = function() g.pending = nil callback({}, id) end
		end } end,
		immediate_raycast = function(pw, from, dir, length)
			g.ray = { from = from, length = length }
			if g.ground then return true, g.ground end
			return false
		end,
	}
	local WU = { shoot_flame_callback = function(unit, ctx, component, offset, owned, flame, marksman)
		g.callbacks[#g.callbacks + 1] = { unit = unit, ctx = ctx, component = component, offset = offset, owned = owned, flame = flame }
		return function()
			-- What the game's callback does to the drone and the state: a hit's events on the shooter.
			U.set_flow_variable(unit, "hit_position", vec(0, 0, 0))
			U.flow_event(unit, "on_raycast")
			ctx.state.flame_length = ctx.state.range
		end
	end }
	local aux = {
		owned = function(u) return u.owned end,
		state = function(u, name)
			if name == "drone" then return { station_unit = u.station } end
			if name == "equipment" then return { wielder = u.wielder } end
		end,
		has_component = function(u, name) return name == "equipment" and u.wielder ~= nil end,
	}
	local globals = { LuaSettingsManager = lsm, LoadoutSettings = ls, World = W, Unit = U, Quaternion = Q, Vector3 = V,
		PhysicsWorld = P, WeaponUtility = WU, EntityAux = aux }
	g.globals = globals
	g.env = {
		global = function(name) return globals[name] end,
		log = function(text) g.logs[#g.logs + 1] = text end,
		unit_path = function(u) return u.path end,
		alive = function(u) return u.alive end,
	}
	g.component = {
		world_proxy = { get_world = function() return "world" end },
		entity_spawner = { spawn_entity = function(_, path, at, rot, nothing, setup)
			local u = { path = path, alive = true, at = at, setup = setup }
			g.spawned[#g.spawned + 1] = u
			return u
		end },
	}
	function g.unit(path, upgrade, extra)
		local u = { path = path, upgrade = upgrade, alive = true }
		for k, v in pairs(extra or {}) do u[k] = v end
		return u
	end
	return g
end

test("install_puts_three_variants_past_the_guard_dog_levels_and_keeps_them", function()
	local g = game()
	local r = hd.runtime(g.env)
	yes(r:install(), "installed")
	local map = g.lsm.unit_path_to_modified_settings[hd.DRONE]
	yes(map[1] == g.vanilla[1] and map[2] == g.vanilla[2], "the game's levels stay")
	for key = 4, 6 do
		local v = map[key]
		eq(v.weapon_info.firerate, 600, "variant " .. key)
		eq(r.ours[v.weapon_info], key - 4)
	end
	eq(map[5].drone_info.move_while_firing, true)
	eq(r.flames[2].attributes.armorpiercing, true) eq(r.flames[0].attributes.armorpiercing, false)
	-- An edit that rebuilds the table, and one that changes our numbers: put back, same tables.
	local held = hd.raw(map[4])
	map[4] = nil
	held.weapon_info.firerate = 1
	yes(r:install())
	yes(hd.raw(map[4]) == held, "the same table back")
	eq(held.weapon_info.firerate, 600, "numbers put back")
	r:uninstall(true)
	eq(map[4], nil) eq(map[5], nil) eq(map[6], nil)
	yes(map[1] == g.vanilla[1], "the game's levels stay after")
end)

test("the_pyro_is_read_before_any_api_edit", function()
	local g = game()
	g.globals.LuaSettingsManager:get_settings_by_unit_path(hd.PISTOL).__protected_table.weapon_info.power = 9000
	g.env.original = function(sp, path)
		if sp == hd.PISTOL and path == "weapon_info.power" then return true, 200 end
		return false
	end
	local r = hd.runtime(g.env)
	yes(r:install())
	eq(r.flames[0].power, 200, "the shipped power, as every machine has it")
end)

test("the_hellpod_marks_a_hot_dog_after_installing", function()
	local g = game()
	local r = hd.runtime(g.env)
	local setup = { stratagem_info = { name = hd.NAME }, upgrade_value = 1 }
	r:hellpod(setup)
	eq(setup.upgrade_value, 5)
	yes(r.installed)
	local guard = { stratagem_info = { name = hd.BASE }, upgrade_value = 1 }
	r:hellpod(guard)
	eq(guard.upgrade_value, 1)
	-- Settings not there: the drop goes out as a Guard Dog.
	local g2 = game()
	g2.globals.LuaSettingsManager = nil
	local r2 = hd.runtime(g2.env)
	local early = { stratagem_info = { name = hd.NAME }, upgrade_value = 0 }
	r2:hellpod(early)
	eq(early.upgrade_value, 0)
	yes(#g2.logs == 1 and g2.logs[1]:find("lands as a Guard Dog", 1, true), "says so")
end)

test("only_hot_dog_drones_leave_the_bullet_routine", function()
	local g = game()
	local r = hd.runtime(g.env)
	yes(r:install())
	local hot = g.unit(hd.DRONE, 5, { owned = true })
	local guard = g.unit(hd.DRONE, 2)
	local rifle = g.unit("equipment/wep_assaultrifle_01", 0)
	local entities = { [hot] = { state = { firing_auto = false } }, [guard] = { state = {} }, [rifle] = { state = {} } }
	local seen
	local function original(component, list, dt) seen = list end
	r:slaves(original, g.component, entities, 0.1)
	yes(seen ~= entities, "a list without the Hot Dog")
	yes(seen[guard] and seen[rifle] and not seen[hot], "the Guard Dog and the rifle fire bullets")
	eq(r.hot[hot], 2, "Mk2, cached") eq(r.hot[rifle], false) eq(r.hot[guard], nil, "a Guard Dog is asked again")
	-- No Hot Dog: the game's own table, untouched.
	r:slaves(original, g.component, { [guard] = entities[guard], [rifle] = entities[rifle] }, 0.1)
	yes(seen[guard] and seen[rifle])
	-- Not installed (a lobby that isn't cleared): everything goes through.
	r:uninstall(true)
	r:slaves(original, g.component, entities, 0.1)
	yes(seen == entities, "the game's table as given")
end)

test("a_firing_hot_dog_casts_a_growing_flame_with_the_pistol_sound", function()
	local g = game()
	local r = hd.runtime(g.env)
	yes(r:install())
	local hot = g.unit(hd.DRONE, 6, { owned = true, z = 3 })
	local state = { firing_auto = false }
	local entities = { [hot] = { state = state } }
	local function original() end
	r:slaves(original, g.component, entities, 0.05)
	eq(#g.casts, 0, "idle")
	local made = g.callbacks[1]
	yes(made, "the game's flame callback")
	yes(made.unit == hot, "the drone is the shooter")
	yes(made.component == g.component, "with the firearm component")
	eq(made.owned, true) eq(made.offset.z, 0.75, "the drone's muzzle offset")
	yes(made.flame == r.flames[2], "the Mk3 flamer")
	yes(g.pistol and g.pistol.path == hd.PISTOL and g.pistol.visible == false and g.pistol.parent == hot, "a hidden pistol on the drone")

	state.firing_auto = true
	r:slaves(original, g.component, entities, 0.05)
	r:slaves(original, g.component, entities, 0.05)
	eq(#g.casts, 2)
	near(g.casts[1].range, 4, "1 metre plus 60 a second") near(g.casts[2].range, 7)
	eq(g.casts[1].from.z, 3.75, "from the muzzle offset")
	yes(g.casts[2].id > g.casts[1].id, "a new shot id each frame")
	for _ = 1, 10 do r:slaves(original, g.component, entities, 0.05) end
	near(g.casts[#g.casts].range, 8, "no further than the FLAM-24")
	local flows = table.concat(g.flows, ",")
	yes(flows:find("pistol fire_start", 1, true) and flows:find("pistol fire_round", 1, true), "the sound on the pistol")
	yes(not flows:find("drone on_raycast", 1, true) and not flows:find("drone var hit_position", 1, true), "no bullet impact from the drone")
	eq(g.particles[1], r.flames[2].flame_effect_close_name, "starts with the close flame")
	eq(g.particles[2], r.flames[2].flame_effect_name, "then the long one")
	eq(#g.stopped, 1, "the close one stopped")
	-- The callback reads the flame's state: the last start and the frame time.
	local st = made.ctx.state
	eq(st.last_ray_from.z, 3.75) near(st.delta_time, 0.05)

	state.firing_auto = false
	r:slaves(original, g.component, entities, 0.05)
	yes(table.concat(g.flows, ","):find("pistol fire_end", 1, true), "the sound stops")
	eq(#g.stopped, 2, "the flame stops")
	eq(st.flame_particle, nil) eq(st.range, 1, "back to the start")
	-- The game's Unit functions are the game's again.
	yes(g.globals.Unit.flow_event ~= nil)
	g.globals.Unit.flow_event(hot, "on_raycast")
	yes(table.concat(g.flows, ","):find("drone on_raycast", 1, true), "untouched outside the callback")
end)

test("a_drone_that_goes_takes_the_flame_and_the_pistol", function()
	local g = game()
	local r = hd.runtime(g.env)
	yes(r:install())
	local hot = g.unit(hd.DRONE, 4)
	local entities = { [hot] = { state = { firing_auto = true } } }
	r:slaves(function() end, g.component, entities, 0.05)
	local pistol = g.pistol
	r:forget(hot)
	yes(not pistol.alive, "pistol destroyed")
	eq(#g.stopped, 1, "flame stopped")
	eq(r.hot[hot], nil) eq(r.dogs[hot], nil)
	-- Out of a mission, nothing of the engine is touched.
	r:slaves(function() end, g.component, entities, 0.05)
	local second = g.pistol
	r:frame(0.1, false)
	eq(r.dogs[hot], nil, "dropped")
	yes(second.alive, "a dead world's unit isn't touched")
	-- A drone gone without the game saying so.
	r:slaves(function() end, g.component, entities, 0.05)
	hot.alive = false
	r.timer = 0
	r:frame(0.1, true)
	yes(not g.pistol.alive, "removed on the next check")
end)

test("the_owner_leaves_napalm_patches_where_the_flame_meets_the_ground", function()
	local g = game()
	local r = hd.runtime(g.env)
	yes(r:install())
	local player = g.unit("characters/helldiver", 0)
	local station = g.unit("equipment/equipment_drone_defensive_backpack_01", 4, { wielder = player })
	local hot = g.unit(hd.DRONE, 4, { station = station })
	local guard = g.unit(hd.DRONE, 0)
	local state = { firing_auto = true }
	local entities = { [hot] = { state = state }, [guard] = { state = { firing_auto = true } } }
	r:masters(g.component, entities, 0.2)
	eq(#g.spawned, 0, "not before the pistol's delay")
	r:masters(g.component, entities, 0.2)
	eq(#g.spawned, 1)
	local patch = g.spawned[1]
	eq(patch.path, "gameobjects/gameobject_flamepistol_napalm_area")
	yes(patch.setup.owner_unit == player, "burns for the player wearing the pack")
	eq(patch.setup.upgrade_value, 0)
	eq(g.ray.length, 6, "the pistol's reach for patches") eq(g.ray.from.x, 1, "a metre ahead of the drone")
	-- The same spot: no second patch while the first burns.
	r:masters(g.component, entities, 0.4)
	eq(#g.spawned, 1)
	patch.alive = false
	r:masters(g.component, entities, 0.4)
	eq(#g.spawned, 2, "a new one once it's out")
	-- Not firing, or nothing hit within reach: none.
	g.spawned[2].alive = false
	state.firing_auto = false
	r:masters(g.component, entities, 1)
	eq(#g.spawned, 2)
	state.firing_auto = true
	g.ground = nil
	r:masters(g.component, entities, 1)
	eq(#g.spawned, 2)
	-- No pack wearer: the drone itself.
	g.ground = vec(9, 9, 0)
	station.wielder = nil
	r:masters(g.component, entities, 1)
	yes(g.spawned[3] and g.spawned[3].setup.owner_unit == hot, "the drone owns it")
end)

-- The icon and material names must be ones tools/build_icon.py writes into res/icons.material, and the
-- texture one obsidian.json ships: a gui asked for a sub-material the material lacks stops the game.
test("the_icon_is_one_the_build_script_writes_and_the_manifest_ships", function()
	local f = assert(io.open("tools/build_icon.py", "r"))
	local text = f:read("*a")
	f:close()
	yes(text:find('("' .. hd.ICON .. '", "more_stratagems/' .. hd.ICON .. '"', 1, true), "sub-material in PNG_ICONS")
	eq(text:match('\nMATERIAL = "([^"]+)"'), hd.ICON_MATERIAL, "material name")
	local m = assert(io.open("obsidian.json", "r"))
	local manifest = m:read("*a")
	m:close()
	yes(manifest:find('"name": "more_stratagems/' .. hd.ICON .. '"', 1, true), "texture resource")
	yes(manifest:find('"data": "res/' .. hd.ICON .. '.texture"', 1, true), "texture file")
	yes(manifest:find('"src/hot_dog.lua"', 1, true), "module listed")
	local tex = io.open("res/" .. hd.ICON .. ".texture", "rb")
	yes(tex, "texture built") if tex then tex:close() end
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

-- The game's Guard Dog entry (lua/settings/loadout_settings.lua:490-500).
local function loadout()
	local guard = {
		name = "stratagem_drone_defensive_backpack", id = 2, activate_sound = "radio_supplies_confirm", cooldown_time = 0,
		description = "stratagem_drone_defensive_backpack_d", despawn_time = 1.4, flare_type = "normal", icon = "stratagem_drone_defensive",
		num_uses = 1, spawn_hellpod = true, stratagem_type = "supply", unit = "gameobjects/supplycrate_drone_defensive_backpack",
		validate_position = true, activation_time = 3, combo = { "down", "up", "left", "up", "right", "down" },
		stratagem_subtypes = { "support" }, patrol_alert_radius = 80,
		attributes = { attr_ammo_amount = 2, attr_firerate = 2, attr_power = 2, attr_range = 1, attr_spec_backpack = true, attr_stability = 4 },
		upgrades = {
			{ cost = 2, upgrade_description = "stratagem_drone_defensive_backpack_d_mk2", upgrade_name = "stratagem_drone_defensive_backpack_mk2",
				attributes = { attr_spec_move_and_fire = true } },
			{ cost = 2, upgrade_description = "stratagem_drone_defensive_backpack_d_mk3", upgrade_name = "stratagem_drone_defensive_backpack_mk3",
				attributes = { attr_spec_armorpiercing = true, attr_spec_ministun = true } },
		},
	}
	return { stratagems = { { name = "stratagem_resupply", id = 1, combo = { "down", "down", "up", "right" }, upgrades = {} }, guard } }
end

test("obsidian_api_takes_the_entry_as_a_guard_dog_drop", function()
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
	obsidian.ui = { art = function(id, opts) return id == hd.ICON and opts.path == hd.ICON_MATERIAL end }
	obsidian.session = { cleared = function() return true end }
	local ok, err = pcall(function()
		local custom = dofile(path)
		local made, why = custom.define(hd.def())
		yes(made, "defined: " .. tostring(why))
		local e = ls.stratagems[made.id]
		eq(e.unit, "gameobjects/supplycrate_drone_defensive_backpack", "the Guard Dog's crate")
		eq(e.spawn_hellpod, true, "through a hellpod, which the marker hooks")
		eq(e.num_uses, 1) eq(e.activation_time, 3) eq(e.cooldown_time, 0)
		eq(e.icon, hd.ICON)
		eq(e.stratagem_type, "supply")
		eq(table.concat(e.combo, " "), "down up left up right right")
		eq(e.attributes.attr_spec_incendiary, true)
		eq(e.upgrades[1].upgrade_name, "stratagem_drone_hot_dog_mk2")
		eq(e.upgrades[1].attributes.attr_spec_move_and_fire, true)
		eq(e.upgrades[2].cost, 2)
		eq(e.upgrades[2].attributes.attr_spec_ministun, true)
	end)
	for k, v in pairs(saved) do obsidian[k] = v end
	rawset(_G, "LoadoutSettings", saved_ls)
	if not ok then error(err, 0) end
end)

return T
