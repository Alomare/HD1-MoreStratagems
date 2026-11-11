-- The AD-342 'Hot Dog': the AD-334 'Guard Dog' with the flamer of the FLAM-24 'Pyro' sidearm in place of
-- the submachine gun.
--
-- What lands is the Guard Dog's own backpack, and the drone flies, picks targets, docks and rearms as the
-- Guard Dog does. What changes is the shot:
--
--   * The drone reads drone_info and weapon_info from the settings variant stored for its unit path and
--     upgrade value (drone_component.lua:9-60, firearm_component.lua:16-60). The game stores Guard Dog
--     variants at 1 and 2 only, so this module adds three more at 4, 5 and 6 (Mk1 to Mk3) on every machine,
--     with the pistol's magazine and rate (50 at 10 a second) and the flamer's reach as the drone's
--     targeting radius. On the thrower's machine the hellpod hands the crate the level plus 4; the crate
--     hands it to the pickup (supply_crate_component.lua:41-60), the pickup to the backpack
--     (backpack_pickup_component.lua:191-210, a uint4), the backpack to the drone (#520e79e14b304a44.lua,
--     set_backpack), and the drone replicates it, so every machine picks the same variant. Guard Dogs keep
--     0 to 2. The crate, the pickup and the backpack have no variant there and use their own settings.
--   * On every machine the drone's bullet stream (FirearmComponent.update_slaves) is skipped, and the
--     flamer's slave routine runs in its place, as FlameweaponComponent.update_slaves does for a held
--     pistol (flameweapon_component.lua:310-420): a ray that grows from 1 to 8 metres while firing, cast with
--     the game's own WeaponUtility.shoot_flame_callback, which deals the damage and the burning, and the
--     pistol's flame particles at the drone's muzzle. The drone stays the shooter, as it is for the Guard
--     Dog's bullets, since a hit names the attacker to other machines.
--   * The flame's sound lives in the pistol's flow. Every machine keeps an invisible FLAM-24 linked to the
--     drone and plays fire_start, fire_round and fire_end on it. The drone's own hit events, which would
--     draw bullet impacts, are swallowed during the flame's callback.
--   * On the drone's owner, the patches of burning napalm the pistol leaves are spawned as the pistol's
--     master does (flameweapon_component.lua:255-300): game objects every player sees.
local M = {}

M.NAME = "stratagem_drone_hot_dog"
M.TITLE = "AD-342 'Hot Dog'"
M.BASE = "stratagem_drone_defensive_backpack"
M.TYPE = "supply"
-- Neither a prefix of a vanilla code nor prefixed by one (tests/test_hot_dog.lua checks all 55 and the
-- other stratagems of this mod).
M.CODE = { "down", "up", "left", "up", "right", "right" }
-- The sub-material in the icon material that tools/build_icon.py writes.
M.ICON = "hot_dog_icon"
M.ICON_MATERIAL = "more_stratagems/icons"
-- The Loadout bars, on the game's 1 to 4 scale. The Guard Dog shows ammunition 2, fire rate 2, power 2,
-- range 1 and stability 4; the flamer hits four times as hard and fires a little faster.
M.ATTRIBUTES = { attr_ammo_amount = 2, attr_firerate = 3, attr_power = 4, attr_range = 1, attr_stability = 4,
	attr_spec_backpack = true, attr_spec_incendiary = true }

-- In the game's style: the upgrade texts replace this one in the menus, so each restates it with the
-- change worked in (internal/native-texts.md). The Guard Dog's levels: Mk2 moves while firing, Mk3 adds
-- Mini Stun and AP ammunition.
local function text(change)
	return "The AD-342 'Hot Dog' is a defensive automated drone armed with the compact flamer of the FLAM-24 'Pyro'."
		.. " Enemies caught in the flames start to burn, and the drone leaves patches of fire on the ground."
		.. (change and (" " .. change) or "")
		.. " The flames do NOT spare Helldivers."
		.. " The drone is based from a backpack carried by a Helldiver and lands there to refuel whenever the tank runs dry or when there is a break in the action."
		.. " The AD-342 is part of the Defender equipment kit."
end
M.DESCRIPTION = text()
M.UPGRADES = {
	{ title = M.TITLE .. " Mk2", cost = 2, attributes = { attr_spec_move_and_fire = true },
		description = text("An upgraded stabilizer allows the drone to move and fire at the same time.") },
	{ title = M.TITLE .. " Mk3", cost = 2, attributes = { attr_spec_armorpiercing = true, attr_spec_ministun = true },
		description = text("An upgraded stabilizer allows the drone to move and fire at the same time, and a pre-igniter makes the flames pierce armor and stun targets for a moment.") },
}
-- Descriptions past 200 characters need the define of Obsidian API 1.43.0, which also leaves settings
-- variants above the game's levels alone when an edit rebuilds the game's own.
M.MIN_API = { 1, 43, 0 }

M.DRONE = "equipment/equipment_drone_defensive_01"
M.PISTOL = "equipment/wep_flamepistol_01"
-- Upgrade values 4 to 6. UpgradeableComponent takes 0 to 15 (upgradeable_component.lua:7-30) and plays
-- only the flow events the settings name (none for the drone or the backpack).
M.OFFSET = 4
M.LEVELS = 3
-- The FLAM-24's own numbers (equipment/wep_flamepistol_01.lua), for any the game doesn't answer. The names
-- are resources every mission loads (mission_common holds equipment/* and gameobjects/*).
M.FLAME = {
	effect_hit = "flamethrower",
	flame_effect_name = "effects/generated/wep_flamepistol_fire",
	flame_effect_close_name = "effects/generated/wep_flamethrower_fire_close",
	power = 200, power_crit = 200,
	min_range = 1, max_range = 8, range_increase_per_second = 60,
	rounds_per_second = 10, magazine_capacity = 50,
}
M.AREA = { spawn_object_name = "gameobjects/gameobject_flamepistol_napalm_area", spawn_delay = 0.3, spawn_offset = 6, spawn_max_distance_sqd = 0.25, max_power = 32 }
M.STATUS = { "heavy_burn" }
-- What Mk3 adds, as the Guard Dog Mk3 does (equipment/equipment_drone_defensive_01.lua upgrade_info[2]).
M.MK3_STATUS = "bullet_stun"
-- The drone's flow events and variables a hit plays (weapon_utility.lua shoot_flame_callback): the bullet's
-- impact. Swallowed for a Hot Dog.
M.HIT_EVENTS = { on_raycast = true }
M.HIT_VARIABLES = { hit_position = true, hit = true, hit_normal = true }

-- Whether a version string such as "1.43.0" is at least the list given.
function M.at_least(version, want)
	local got = {}
	for n in tostring(version or ""):gmatch("%d+") do got[#got + 1] = tonumber(n) end
	for i, w in ipairs(want) do
		local v = got[i] or 0
		if v ~= w then return v > w end
	end
	return true
end

function M.def()
	local upgrades = {}
	for i, u in ipairs(M.UPGRADES) do
		upgrades[i] = { title = u.title, description = u.description, cost = u.cost, attributes = u.attributes }
	end
	return {
		name = M.NAME,
		base = M.BASE,
		title = M.TITLE,
		description = M.DESCRIPTION,
		type = M.TYPE,
		code = M.CODE,
		icon = M.ICON,
		icon_material = M.ICON_MATERIAL,
		attributes = M.ATTRIBUTES,
		upgrades = upgrades,
	}
end

-- Tables -------------------------------------------------------------------------------------------

-- A settings table behind the game's protect() wrapper (debug builds wrap the top level only).
local function raw(t)
	return type(t) == "table" and rawget(t, "__protected_table") or t
end
M.raw = raw

local function copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(raw(t)) do out[k] = copy(v) end
	return out
end
M.copy = copy

-- SettingsAux.recursive_override, as the game applies an upgrade to a clone.
local function override(t, o)
	for k, v in pairs(raw(o)) do
		if type(v) == "table" and type(t[k]) == "table" then override(t[k], v) else t[k] = copy(v) end
	end
end

-- dst becomes equal to src, keeping every table dst already has: live drones hold them.
local function assign(dst, src)
	for k, v in pairs(src) do
		local d = rawget(dst, k)
		if type(v) == "table" and type(d) == "table" then
			assign(d, v)
		elseif d ~= v then
			rawset(dst, k, copy(v))
		end
	end
	for k in pairs(dst) do
		if rawget(src, k) == nil then rawset(dst, k, nil) end
	end
end
M.assign = assign

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not same(v, rawget(b, k)) then return false end
	end
	for k in pairs(b) do
		if rawget(a, k) == nil then return false end
	end
	return true
end
M.same = same

local function number_ok(v)
	return type(v) == "number" and v > 0 and v < 100000
end

-- The FLAM-24's weapon_info from the game's table, each field checked, with the fallback for any that isn't.
-- The flamer reads these in the callback (power, power_crit, attributes, hit_status_effects, effect_hit)
-- and in the slave routine (the ranges and the particles).
function M.flame_from(info)
	info = type(info) == "table" and raw(info) or {}
	local out = {}
	for k, fallback in pairs(M.FLAME) do
		local v = info[k]
		if type(fallback) == "number" then
			if not number_ok(v) then v = fallback end
		elseif type(v) ~= "string" or v == "" then
			v = fallback
		end
		out[k] = v
	end
	if out.min_range > out.max_range then out.min_range, out.max_range = M.FLAME.min_range, M.FLAME.max_range end
	local attributes = type(info.attributes) == "table" and raw(info.attributes) or {}
	out.attributes = {
		armorpiercing = attributes.armorpiercing == true,
		ignore_status_effects_if_no_damage = attributes.ignore_status_effects_if_no_damage ~= false,
	}
	local status = {}
	if type(info.hit_status_effects) == "table" then
		for _, s in ipairs(raw(info.hit_status_effects)) do
			if type(s) == "string" then status[#status + 1] = s end
		end
	end
	if #status == 0 then status = copy(M.STATUS) end
	out.hit_status_effects = status
	local area = type(info.area_effect) == "table" and raw(info.area_effect) or {}
	out.area_effect = {}
	for k, fallback in pairs(M.AREA) do
		local v = area[k]
		if type(fallback) == "number" then
			if not number_ok(v) then v = fallback end
		elseif type(v) ~= "string" or v == "" then
			v = fallback
		end
		out.area_effect[k] = v
	end
	return out
end

-- The flamer of a level (0 is Mk1): Mk3 pierces armor and stuns, as the Guard Dog Mk3's rounds do.
function M.flame(pyro, level)
	local f = copy(pyro)
	if level >= 2 then
		f.attributes.armorpiercing = true
		local has = false
		for _, s in ipairs(f.hit_status_effects) do has = has or s == M.MK3_STATUS end
		if not has then f.hit_status_effects[#f.hit_status_effects + 1] = M.MK3_STATUS end
	end
	return f
end

-- The Hot Dog's drone settings for a level (0 is Mk1) from the Guard Dog's drone: the Guard Dog's own level
-- (moving while firing from Mk2), with the pistol's magazine and rate, and a targeting radius no wider than
-- the flame reaches.
function M.variant(drone, level, pyro)
	drone = raw(drone)
	local v = copy(drone)
	local info = type(drone.upgrade_info) == "table" and raw(drone.upgrade_info) or {}
	for i = 1, level do
		if type(info[i]) == "table" then override(v, info[i]) end
	end
	if type(v.weapon_info) ~= "table" then v.weapon_info = {} end
	if type(v.drone_info) ~= "table" then v.drone_info = {} end
	v.weapon_info.firerate = pyro.rounds_per_second * 60
	v.weapon_info.magazine_capacity = pyro.magazine_capacity
	v.drone_info.check_for_target_radius = pyro.max_range
	return v
end

-- The marker: on the thrower's machine, a hellpod set up for the Hot Dog hands the crate the level plus
-- OFFSET. setup is the hellpod's setup info; the stratagem entry in it is the custom one there, the base
-- everywhere else. Values already past the game's levels stay.
function M.mark(setup)
	if type(setup) ~= "table" then return false end
	local info = setup.stratagem_info
	if type(info) ~= "table" or info.name ~= M.NAME then return false end
	local level = setup.upgrade_value or 0
	if type(level) ~= "number" or level < 0 or level >= M.LEVELS or level ~= math.floor(level) then return false end
	setup.upgrade_value = level + M.OFFSET
	return true
end

-- The particle the flame shows for a length, as the pistol picks it: the close one under 2 metres.
-- Answers the effect to start, or nil to keep the one there.
function M.particle(pyro, length, last_length, has)
	local close = pyro.flame_effect_close_name
	if not close then return (not has) and pyro.flame_effect_name or nil end
	if length >= 2 then
		if not has or last_length < 2 then return pyro.flame_effect_name end
	else
		if not has or last_length >= 2 then return close end
	end
	return nil
end

-- Whether a napalm patch at a point is far enough from every one still burning (squared distances).
function M.room_for_patch(at, patches, max_sqd)
	for _, p in ipairs(patches) do
		local dx, dy, dz = at.x - p.x, at.y - p.y, at.z - p.z
		if dx * dx + dy * dy + dz * dz < max_sqd then return false end
	end
	return true
end

-- Runtime ------------------------------------------------------------------------------------------
--
-- env: global(name), log(text), original(settings_path, path) (Obsidian API edits.original, may be nil),
-- unit_path(unit), alive(unit). Every engine call is under pcall.

local CHECK_EVERY = 1

local R = {}
R.__index = R

function M.runtime(env)
	return setmetatable({
		env = env,
		mine = {},       -- level -> our variant table
		ours = setmetatable({}, { __mode = "k" }), -- weapon_info table -> level
		flames = {},     -- level -> the flamer's weapon_info
		wants = nil,     -- level -> what the variant should hold
		installed = false,
		timer = 0,
		hot = setmetatable({}, { __mode = "k" }),   -- unit -> level, or false for a firearm that isn't one
		dogs = setmetatable({}, { __mode = "k" }),  -- unit -> the flamer's slave state and the pistol
		pumps = setmetatable({}, { __mode = "k" }), -- unit -> the napalm timer and patches, on the owner
	}, R)
end

function R:log(text)
	if self.env.log then pcall(self.env.log, "Hot Dog: " .. tostring(text)) end
end

function R:lsm()
	local lsm = self.env.global("LuaSettingsManager")
	if type(lsm) == "table" and type(lsm.unit_path_to_modified_settings) == "table" then return lsm end
	return nil
end

-- The FLAM-24's numbers as the game ships them, before any Obsidian API edit, so every machine builds the
-- same flamer.
function R:pyro(lsm)
	local settings = raw(lsm:get_settings_by_unit_path(M.PISTOL))
	local info = type(settings) == "table" and copy(settings.weapon_info) or {}
	local original = self.env.original
	local sp = original and lsm.get_settings_path_by_unit_path and lsm:get_settings_path_by_unit_path(M.PISTOL)
	if sp and type(info) == "table" then
		for k, fallback in pairs(M.FLAME) do
			local ok, changed, old = pcall(original, sp, "weapon_info." .. k)
			if ok and changed and type(old) == type(fallback) then info[k] = old end
		end
		local ok, changed, old = pcall(original, sp, "weapon_info.attributes.armorpiercing")
		if ok and changed and type(old) == "boolean" and type(info.attributes) == "table" then info.attributes.armorpiercing = old end
	end
	return M.flame_from(info)
end

-- Builds what the variants hold. false when the game's settings aren't there yet.
function R:build(lsm)
	local drone = lsm:get_settings_by_unit_path(M.DRONE)
	if type(drone) ~= "table" or type(raw(drone).drone_info) ~= "table" or type(raw(drone).weapon_info) ~= "table" then return false end
	local pyro = self:pyro(lsm)
	local wants = {}
	for level = 0, M.LEVELS - 1 do
		wants[level] = M.variant(drone, level, pyro)
		self.flames[level] = M.flame(pyro, level)
	end
	self.wants = wants
	return true
end

-- Puts the variants in the game's table, or back as they should be. The same tables every time, so
-- drones in the air keep theirs.
function R:install()
	local lsm = self:lsm()
	if not lsm then return false end
	if not self.wants and not self:build(lsm) then return false end
	local map = lsm.unit_path_to_modified_settings
	for level = 0, M.LEVELS - 1 do
		local key = level + M.OFFSET
		local held = map[M.DRONE] and raw(map[M.DRONE][key])
		local mine = self.mine[level]
		if not mine then
			mine = copy(self.wants[level])
			self.mine[level] = mine
		end
		if held ~= mine then
			lsm:set_modified_settings(M.DRONE, key, mine)
			held = map[M.DRONE] and raw(map[M.DRONE][key])
			if held ~= mine then return false end
		end
		if not same(mine, self.wants[level]) then
			assign(mine, self.wants[level])
			self:log("variant " .. key .. " was changed by something else; put back")
		end
		self.ours[mine.weapon_info] = level
	end
	self.installed = true
	return true
end

-- The lobby stopped being cleared: the game's table goes back to the game's levels, and every flame and
-- hidden pistol goes. A drone still in the air fires as the settings it holds say, as a Guard Dog would.
function R:uninstall(in_mission)
	local lsm = self:lsm()
	local map = lsm and lsm.unit_path_to_modified_settings
	local variants = map and map[M.DRONE]
	if type(variants) == "table" then
		for level = 0, M.LEVELS - 1 do
			local key = level + M.OFFSET
			if self.mine[level] and raw(variants[key]) == self.mine[level] then variants[key] = nil end
		end
	end
	self.installed = false
	if in_mission ~= false then
		for unit in pairs(self.dogs) do self:dismiss(unit) end
	end
	self:clear()
end

-- The hook on HellpodComponent.setup_master, before the original runs.
function R:hellpod(setup)
	local ok, err = pcall(function()
		if type(setup) ~= "table" or type(setup.stratagem_info) ~= "table" or setup.stratagem_info.name ~= M.NAME then return end
		if not self:install() then
			self:log("the variants could not be installed; this one lands as a Guard Dog")
			return
		end
		M.mark(setup)
	end)
	if not ok then self:log(err) end
end

function R:settings_of(unit)
	local ls = self.env.global("LoadoutSettings")
	if type(ls) ~= "table" or type(ls.get_upgraded_settings) ~= "function" then return nil end
	local ok, s = pcall(ls.get_upgraded_settings, unit)
	return ok and type(s) == "table" and s or nil
end

-- The level of a Hot Dog drone, or nil for any other firearm. Other firearms are answered from the cache;
-- a Guard Dog drone is asked again until it settles, in case its upgrade value comes late.
function R:level_of(unit)
	local known = self.hot[unit]
	if known then return known end
	if known == false then return nil end
	local ok, path = pcall(self.env.unit_path, unit)
	if not (ok and path == M.DRONE) then
		self.hot[unit] = false
		return nil
	end
	local s = self:settings_of(unit)
	local level = s and self.ours[s.weapon_info]
	if level then self.hot[unit] = level + 1 end
	return level and level + 1 or nil
end

function R:any(entities)
	if not self.installed or type(entities) ~= "table" then return false end
	for unit in pairs(entities) do
		if self:level_of(unit) then return true end
	end
	return false
end

-- The hook on FirearmComponent.update_slaves: every firearm but the Hot Dogs goes through the game's
-- routine; the Hot Dogs fire the flamer.
function R:slaves(original, component, entities, dt, ...)
	local ok, any = pcall(self.any, self, entities)
	if not (ok and any) then
		if not ok then self:log(any) end
		return original(component, entities, dt, ...)
	end
	local rest, mine = {}, {}
	for unit, ctx in pairs(entities) do
		-- Asked here and not read from the cache: `any` stops at the first Hot Dog, so a second one
		-- (another player's) may not have been asked yet, and would fire bullets.
		if self:level_of(unit) then mine[unit] = ctx else rest[unit] = ctx end
	end
	original(component, rest, dt, ...)
	for unit, ctx in pairs(mine) do
		local fired, err = pcall(self.flame_slave, self, component, unit, ctx, tonumber(dt) or 0)
		if not fired then
			self:log(err)
			self:dismiss(unit)
			self.hot[unit] = false
		end
	end
end

-- The drone's own hit events swallowed for the length of the flame's callback, so no bullet impact shows.
function R:quiet(unit, fn, ...)
	local U = self.env.global("Unit")
	if type(U) ~= "table" then return fn(...) end
	local flow, variable = U.flow_event, U.set_flow_variable
	U.flow_event = function(u, event, ...)
		if u == unit and M.HIT_EVENTS[event] then return end
		return flow(u, event, ...)
	end
	U.set_flow_variable = function(u, name, ...)
		if u == unit and M.HIT_VARIABLES[name] then return end
		return variable(u, name, ...)
	end
	local ok, err = pcall(fn, ...)
	U.flow_event, U.set_flow_variable = flow, variable
	if not ok then error(err, 0) end
end

-- A drone's flamer on this machine: the slave state the game's callback reads, the raycast made with it,
-- and the hidden pistol that carries the sound.
function R:dog(component, unit, level)
	local G = self.env.global
	local W, U, physics, weapons, aux = G("World"), G("Unit"), G("PhysicsWorld"), G("WeaponUtility"), G("EntityAux")
	local world = component.world_proxy:get_world()
	local flame = self.flames[level]
	local s = self:settings_of(unit)
	local offset = s and s.weapon_info and s.weapon_info.ray_source_offset
	offset = type(offset) == "table" and { x = offset.x or 0, y = offset.y or 0, z = offset.z or 0 } or { x = 0, y = 0, z = 0 }
	local state = { last_ray_from = { x = 0, y = 0, z = 0 }, range = flame.min_range, flame_length = flame.min_range, delta_time = 0 }
	local owned = false
	if type(aux) == "table" and aux.owned then
		local ok, v = pcall(aux.owned, unit)
		owned = ok and v and true or false
	end
	local shot = weapons.shoot_flame_callback(unit, { state = state }, component, offset, owned, flame, false)
	local d = { state = state, flame = flame, offset = offset, world = world, count = 0, last_length = flame.min_range, firing = false }
	d.raycast = physics.make_raycast(W.physics_world(world), function(...) self:quiet(unit, shot, ...) end,
		"all", "collision_filter", "damage_ray")
	-- The pistol: never seen, linked to the drone so the sound follows it.
	local ok, err = pcall(function()
		local pistol = W.spawn_unit(world, M.PISTOL, U.world_position(unit, 0), U.world_rotation(unit, 0))
		d.pistol = pistol
		U.set_unit_visibility(pistol, false)
		W.link_unit(world, pistol, 0, unit, 0)
	end)
	if not ok then self:log("no pistol for the sound: " .. tostring(err)) end
	self.dogs[unit] = d
	return d
end

function R:pistol_event(d, event)
	if not d.pistol then return end
	local U = self.env.global("Unit")
	local ok, err = pcall(function()
		if U.alive(d.pistol) then U.flow_event(d.pistol, event) end
	end)
	if not ok then self:log(err) end
end

-- One frame of a Hot Dog's flamer, as FlameweaponComponent.update_slaves runs a held pistol's, with the
-- drone in the wielder's place.
function R:flame_slave(component, unit, ctx, dt)
	local level = self.hot[unit] - 1
	local d = self.dogs[unit] or self:dog(component, unit, level)
	local G = self.env.global
	local W, U, V, Q = G("World"), G("Unit"), G("Vector3"), G("Quaternion")
	local st, fs, flame = ctx.state, d.state, d.flame
	local firing = type(st) == "table" and st.firing_auto == true
	fs.delta_time = dt
	if firing and not d.firing then
		self:pistol_event(d, "fire_start")
		fs.last_beam_check_hit = false
	elseif not firing and d.firing then
		self:pistol_event(d, "fire_end")
	end
	if firing then
		local rotation = U.world_rotation(unit, 0)
		local forward = Q.forward(rotation)
		local from = U.world_position(unit, 0) + Q.rotate(rotation, V(d.offset.x, d.offset.y, d.offset.z))
		fs.range = math.min(fs.range + flame.range_increase_per_second * dt, flame.max_range)
		d.count = d.count + 1
		d.raycast:cast(from, forward, fs.range, d.count)
		self:pistol_event(d, "fire_round")
		fs.last_ray_from.x, fs.last_ray_from.y, fs.last_ray_from.z = from.x, from.y, from.z
		local start = M.particle(flame, fs.flame_length, d.last_length, fs.flame_particle ~= nil)
		if start then
			if fs.flame_particle then W.stop_spawning_particles(d.world, fs.flame_particle) end
			fs.flame_particle = W.create_particles(d.world, start, V.zero())
		end
	elseif d.firing then
		if fs.flame_particle then W.stop_spawning_particles(d.world, fs.flame_particle) end
		fs.flame_particle = nil
		fs.range = flame.min_range
	end
	d.last_length = fs.flame_length
	d.firing = firing
end

-- A drone that is going away: the flame stops and the pistol goes.
function R:dismiss(unit)
	local d = self.dogs[unit]
	if not d then return end
	self.dogs[unit] = nil
	local G = self.env.global
	local ok, err = pcall(function()
		local W, U = G("World"), G("Unit")
		if d.state.flame_particle then W.stop_spawning_particles(d.world, d.state.flame_particle) end
		d.state.flame_particle = nil
		if d.firing then self:pistol_event(d, "fire_end") end
		if d.pistol and U.alive(d.pistol) then
			W.unlink_unit(d.world, d.pistol)
			W.destroy_unit(d.world, d.pistol)
		end
	end)
	if not ok then self:log(err) end
end

-- The hook on FirearmComponent.update_masters, after the original: the owner of a firing Hot Dog leaves
-- patches of napalm where the flame meets the ground, as the pistol's master does.
function R:masters(component, entities, dt)
	if not self.installed or type(entities) ~= "table" then return end
	dt = tonumber(dt) or 0
	for unit, ctx in pairs(entities) do
		if self:level_of(unit) then
			local ok, err = pcall(self.pump, self, component, unit, ctx, dt)
			if not ok then self:log(err) end
		end
	end
end

function R:pump(component, unit, ctx, dt)
	local st = ctx.state
	if type(st) ~= "table" or st.firing_auto ~= true then return end
	local level = self.hot[unit] - 1
	local area = self.flames[level].area_effect
	local p = self.pumps[unit]
	if not p then
		p = { wait = area.spawn_delay, patches = {} }
		self.pumps[unit] = p
	end
	local G = self.env.global
	p.wait = p.wait - dt
	if p.wait >= 0 then return end
	p.wait = area.spawn_delay
	local W, U, physics, Q, aux = G("World"), G("Unit"), G("PhysicsWorld"), G("Quaternion"), G("EntityAux")
	local forward = Q.forward(U.world_rotation(unit, 0))
	local start = U.world_position(unit, 0) + forward
	local world = component.world_proxy:get_world()
	local hit, at = physics.immediate_raycast(W.physics_world(world), start, forward, area.spawn_offset, "closest", "collision_filter", "damage_ray")
	if not hit or not at then return end
	local live = {}
	for _, patch in ipairs(p.patches) do
		if U.alive(patch.unit) then live[#live + 1] = patch end
	end
	p.patches = live
	local point = { x = at.x, y = at.y, z = at.z }
	if not M.room_for_patch(point, live, area.spawn_max_distance_sqd) then return end
	-- The patch burns for the player wearing the pack, or the drone when nobody does.
	local owner = unit
	pcall(function()
		local station = aux.state(unit, "drone").station_unit
		local wielder = station and U.alive(station) and aux.has_component(station, "equipment") and aux.state(station, "equipment").wielder
		if wielder and U.alive(wielder) then owner = wielder end
	end)
	local patch = component.entity_spawner:spawn_entity(area.spawn_object_name, at, nil, nil, { owner_unit = owner, upgrade_value = 0 })
	if patch then
		point.unit = patch
		live[#live + 1] = point
	end
end

-- The hook on FirearmComponent.remove_slave: a firearm leaving the game is forgotten, so a unit handle the
-- engine hands out again starts unknown.
function R:forget(unit)
	self:dismiss(unit)
	self.hot[unit] = nil
	self.pumps[unit] = nil
end

-- Out of a mission the level is gone: every cache is dropped without touching the engine, whose units
-- and particles went with the world.
function R:clear()
	self.dogs = setmetatable({}, { __mode = "k" })
	self.hot = setmetatable({}, { __mode = "k" })
	self.pumps = setmetatable({}, { __mode = "k" })
end

function R:frame(dt, in_mission)
	dt = tonumber(dt) or 0
	if dt ~= dt or dt < 0 then dt = 0 end
	if in_mission == false and (next(self.dogs) or next(self.hot) or next(self.pumps)) then self:clear() end
	self.timer = self.timer - dt
	if self.timer > 0 then return end
	self.timer = CHECK_EVERY
	local ok, err = pcall(self.install, self)
	if not ok then self:log(err) end
	-- A drone removed without the game saying so.
	for unit in pairs(self.dogs) do
		local checked, alive = pcall(self.env.alive, unit)
		if not (checked and alive) then self:dismiss(unit) end
	end
end

return M
