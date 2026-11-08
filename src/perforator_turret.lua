-- The A/MG-15 Perforator Turret: the Railcannon Turret with an AR-20L 'Justice' mounted on the barrel,
-- firing a stream of Justice rounds (internal/perforator-research.md).
--
-- The shot's look and sound live in the flow of whichever unit fires, so the turret's own events would
-- play the rail shot. Every machine mounts a real Justice on the turret and hands the rifle the events
-- of each shot: the rifle plays the muzzle flash, the tracer and the sound. The turret stays the shooter
-- as far as damage goes, since a hit names the attacker to other machines and the rifle exists on one
-- machine only.
--
-- How: the turret reads weapon_info and turret_info from the settings variant stored for the unit path
-- and upgrade value (LoadoutSettings.get_upgraded_settings, turret_component.lua:14-21, 49, 173). The
-- game stores variants for the Railcannon Turret at upgrade values 1 and 2 only, so this module adds
-- three more at 4, 5 and 6 (Mk1 to Mk3) on every machine. The thrower's machine adds 4 to the upgrade
-- value the hellpod hands the turret (hellpod_component.lua:13, 19-23); the turret replicates the value
-- (a uint4 game object field), so every machine picks the same variant. Railcannon Turrets keep 0 to 2.
local M = {}

M.NAME = "stratagem_turret_perforator"
M.TITLE = "A/MG-15 Perforator Turret"
M.BASE = "stratagem_turret_railcannon"
M.TYPE = "defensive"
-- Neither a prefix of a vanilla code nor prefixed by one (tests/test_perforator.lua checks all 55).
M.CODE = { "left", "down", "up", "up", "right" }
-- The sub-material in the icon material that tools/build_icon.py writes.
M.ICON = "perforator_turret_icon"
M.ICON_MATERIAL = "more_stratagems/icons"
-- The Loadout bars, on the game's 1 to 4 scale: the Minigun Turret (75 power, 1300 a minute) shows 3 power
-- and 4 fire rate, the Railcannon Turret 1 fire rate. upgrade_attributes are the new values, not steps.
M.ATTRIBUTES = { attr_durability = 3, attr_firerate = 3, attr_power = 3, attr_stability = 4, attr_turnspeed = 2 }

local BASE_TEXT = "Call in an automatic turret that fires a rapid stream of AR-20L 'Justice' rounds with a tighter spread than the rifle."
	.. " The turret is capable of distinguishing friend from foe, but stay out of the line of fire. The rounds do not pierce heavy armor."
M.DESCRIPTION = BASE_TEXT
-- The Railcannon Turret's levels and costs: Mk2 doubles the fire rate, Mk3 adds faster turning and a
-- 120 second cooldown. The upgrade texts replace the base one in the menus, so each restates it.
M.UPGRADES = {
	{ title = M.TITLE .. " Mk2", cost = 2, upgrade_attributes = { attr_firerate = 4 },
		description = BASE_TEXT .. " An improved feed mechanism allows for a higher rate of fire." },
	{ title = M.TITLE .. " Mk3", cost = 2, stats = { cooldown_time = 120 }, upgrade_attributes = { attr_turnspeed = 4 },
		description = BASE_TEXT .. " An improved feed mechanism allows for a higher rate of fire and upgraded motors allow for faster rotation towards targets." },
}
-- Descriptions past 200 characters need the define of Obsidian API 1.43.0, which also leaves settings
-- variants above the game's levels alone when an edit rebuilds the game's own.
M.MIN_API = { 1, 43, 0 }

-- The turret unit the Railcannon Turret calls down, and the Justice.
M.UNIT = "gameobjects/gameobject_hellpod_railcannon_turret"
M.RIFLE = "equipment/wep_assaultrifle_02"
-- Upgrade values 4 to 6: UpgradeableComponent takes 0 to 15 (upgradeable_component.lua:11-12) and plays
-- no flow event for a level the turret has no upgrade_info for (:40-48).
M.OFFSET = 4
M.LEVELS = 3
-- The Justice's own numbers (equipment/wep_assaultrifle_02.lua:7), used for any the game doesn't answer.
M.JUSTICE = { firerate = 400, power = 120, power_crit = 150, range = 30, effect_hit = "projectile_heavy", armorpiercing = false }
-- 15 percent faster than the Justice at Mk1; Mk2 and Mk3 double that, as the Railcannon Turret Mk2 does.
M.RATE_GAIN = 1.15
-- Degrees off the barrel for every round (turret_component.lua:464 passes no fraction flag, so
-- get_random_spread uses the full angle). The Justice opens from 0 to 15 degrees as it fires and holds
-- about 2.5 in sustained fire; 1.5 is well inside both.
M.SPREAD = 1.5
-- turret_info for a stream rather than a rail shot:
--   rounds 3000: with infinite_ammo the count resets when it runs out, a jump each machine sees late. At
--     920 a minute the turret's 120 seconds use 1840, so no reset comes in a turret's life.
--   fire_cooldown 0.5: keeps firing that long after the barrel drifts off the target, as the Minigun.
--   angle_to_target_diff_before_shooting 0.07: as the Minigun; the Railcannon's 0.001 cuts the stream on
--     every small correction.
--   targeting_mode "angle": what the barrel already faces first, as the Minigun; "size" chases the
--     biggest target, which suits a rail and not rounds that don't pierce armor.
M.TURRET = { rounds = 3000, fire_cooldown = 0.5, angle_to_target_diff_before_shooting = 0.07, targeting_mode = "angle" }

-- The rifle on the barrel: the turret's turning node, and metres from it in that node's frame (y along the
-- barrel, z up). Where it sits is a matter of looks: change these to move it.
M.MOUNT_NODE = "j_rotate_side"
M.MOUNT = { x = 0, y = 0.25, z = 0.3 }
-- What a shot says to the unit firing it (turret_component.lua, weapon_utility.lua): these go to the rifle.
M.SHOT_EVENTS = { fire_start = true, fire_round = true, fire_end = true, on_raycast = true }
M.SHOT_VARIABLES = { hit_position = true, hit = true, hit_normal = true }

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
		upgrades[i] = { title = u.title, description = u.description, cost = u.cost, upgrade_attributes = u.upgrade_attributes, stats = u.stats }
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

-- dst becomes equal to src, keeping every table dst already has: live turrets hold them.
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

-- Rounds a minute at a level (0 is Mk1).
function M.rate(justice_rate, level)
	local mk1 = math.floor(justice_rate * M.RATE_GAIN + 0.5)
	return level >= 1 and mk1 * 2 or mk1
end

-- The weapon_info of a level from the Justice's numbers ({ firerate, power, power_crit, range,
-- effect_hit, armorpiercing }). unstoppable is set false outright, rather than left out, so nothing of the
-- rail's is kept.
function M.weapon(justice, level)
	return {
		automatic = true,
		firerate = M.rate(justice.firerate, level),
		power = justice.power,
		power_crit = justice.power_crit,
		range = justice.range,
		effect_hit = justice.effect_hit,
		spread = M.SPREAD,
		attributes = { armorpiercing = justice.armorpiercing == true, unstoppable = false },
	}
end

-- The Perforator's settings for a level (0 is Mk1) from the Railcannon Turret's base settings: the
-- Railcannon's own level (health, life, map icon, turn speed), with the Justice's weapon and the stream's
-- turret_info.
function M.variant(rail, level, justice)
	rail = raw(rail)
	local v = copy(rail)
	local info = type(rail.upgrade_info) == "table" and raw(rail.upgrade_info) or {}
	for i = 1, level do
		if type(info[i]) == "table" then override(v, info[i]) end
	end
	v.weapon_info = M.weapon(justice, level)
	if type(v.turret_info) ~= "table" then v.turret_info = {} end
	for k, value in pairs(M.TURRET) do v.turret_info[k] = value end
	return v
end

-- The Justice's numbers from a weapon_info table, each checked, with the fallback for any that isn't.
function M.justice_from(info)
	local out = {}
	for k, fallback in pairs(M.JUSTICE) do
		local v
		if type(info) == "table" then
			if k == "armorpiercing" then
				local a = info.attributes
				v = type(a) == "table" and a.armorpiercing or nil
			else
				v = info[k]
			end
		end
		if type(v) ~= type(fallback) or (type(v) == "number" and not (v > 0 and v < 100000)) then v = fallback end
		out[k] = v
	end
	return out
end

-- The marker: on the thrower's machine, a hellpod set up for the Perforator hands the turret the level
-- plus OFFSET. setup is the hellpod's setup info; the game's stratagem entry in it is the custom one there
-- (custom.lua:1303-1305), the base everywhere else. Values already past the game's levels stay.
function M.mark(setup)
	if type(setup) ~= "table" then return false end
	local info = setup.stratagem_info
	if type(info) ~= "table" or info.name ~= M.NAME then return false end
	local level = setup.upgrade_value or 0
	if type(level) ~= "number" or level < 0 or level >= M.LEVELS or level ~= math.floor(level) then return false end
	setup.upgrade_value = level + M.OFFSET
	return true
end

-- Runtime ------------------------------------------------------------------------------------------
--
-- env: global(name), log(text), original(settings_path, path) (Obsidian API edits.original, may be nil),
-- unit_path(unit), alive(unit). Every engine call is under pcall.

local CHECK_EVERY = 1
-- How long a newly set up turret is watched for the upgrade value reaching it late (seconds). The turret
-- doesn't fire in the first 4 to 5.5 seconds (start_invul_time, start_idle_time).
local WATCH_FOR = 10

local R = {}
R.__index = R

function M.runtime(env)
	return setmetatable({
		env = env,
		mine = {},       -- level -> our variant table
		ours = setmetatable({}, { __mode = "k" }), -- weapon_info table -> level
		wants = nil,     -- level -> what the variant should hold
		installed = false,
		timer = 0,
		masters = setmetatable({}, { __mode = "k" }), -- unit -> { component, ctx, left }
		slaves = setmetatable({}, { __mode = "k" }),
		built = setmetatable({}, { __mode = "k" }), -- slave state -> weapon_info the raycast was made with
		rifles = setmetatable({}, { __mode = "k" }), -- turret unit -> { unit, world }
		redirecting = false,
	}, R)
end

function R:log(text)
	if self.env.log then pcall(self.env.log, "Perforator Turret: " .. tostring(text)) end
end

function R:lsm()
	local lsm = self.env.global("LuaSettingsManager")
	if type(lsm) == "table" and type(lsm.unit_path_to_modified_settings) == "table" then return lsm end
	return nil
end

function R:justice(lsm)
	local settings = raw(lsm:get_settings_by_unit_path(M.RIFLE))
	local info = type(settings) == "table" and raw(settings.weapon_info) or nil
	local out = M.justice_from(info)
	-- The values before any Obsidian API edit, so every machine builds the same weapon.
	local original = self.env.original
	local sp = original and lsm.get_settings_path_by_unit_path and lsm:get_settings_path_by_unit_path(M.RIFLE)
	if sp then
		for k, fallback in pairs(M.JUSTICE) do
			local path = k == "armorpiercing" and "weapon_info.attributes.armorpiercing" or ("weapon_info." .. k)
			local ok, changed, old = pcall(original, sp, path)
			if ok and changed and type(old) == type(fallback) then out[k] = old end
		end
	end
	return out
end

-- Builds what the variants hold. false when the game's settings aren't there yet.
function R:build(lsm)
	local rail = lsm:get_settings_by_unit_path(M.UNIT)
	if type(rail) ~= "table" or type(raw(rail).turret_info) ~= "table" then return false end
	local justice = self:justice(lsm)
	local wants = {}
	for level = 0, M.LEVELS - 1 do wants[level] = M.variant(rail, level, justice) end
	self.wants = wants
	return true
end

-- Puts the variants in the game's table, or back as they should be. The same tables every time, so
-- turrets standing keep theirs.
function R:install()
	local lsm = self:lsm()
	if not lsm then return false end
	if not self.wants and not self:build(lsm) then return false end
	local map = lsm.unit_path_to_modified_settings
	for level = 0, M.LEVELS - 1 do
		local key = level + M.OFFSET
		local held = map[M.UNIT] and raw(map[M.UNIT][key])
		local mine = self.mine[level]
		if not mine then
			mine = copy(self.wants[level])
			self.mine[level] = mine
		end
		if held ~= mine then
			lsm:set_modified_settings(M.UNIT, key, mine)
			held = map[M.UNIT] and raw(map[M.UNIT][key])
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

-- The lobby stopped being cleared: the game's table goes back to the game's levels. Turrets standing
-- keep the tables they hold and fire as before; one set up later is a plain Railcannon Turret.
function R:uninstall()
	local lsm = self:lsm()
	local map = lsm and lsm.unit_path_to_modified_settings
	local variants = map and map[M.UNIT]
	if type(variants) == "table" then
		for level = 0, M.LEVELS - 1 do
			local key = level + M.OFFSET
			if self.mine[level] and raw(variants[key]) == self.mine[level] then variants[key] = nil end
		end
	end
	self.installed = false
	self.masters = setmetatable({}, { __mode = "k" })
	self.slaves = setmetatable({}, { __mode = "k" })
	for unit in pairs(self.rifles) do self:dismount(unit) end
end

-- Runs fn(...) with the shot events and hit variables of a turret carrying a rifle sent to the rifle
-- instead. Only for the length of the call, so the game's calls cost nothing the rest of the time.
function R:through_rifles(fn, ...)
	local U = self.env.global("Unit")
	if self.redirecting or next(self.rifles) == nil or type(U) ~= "table" then return fn(...) end
	local rifles = self.rifles
	local flow, variable, alive = U.flow_event, U.set_flow_variable, U.alive
	local function rifle_of(unit, known, name)
		local r = known[name] and rifles[unit]
		return r and alive(r.unit) and r.unit or nil
	end
	U.flow_event = function(unit, event, ...)
		return flow(rifle_of(unit, M.SHOT_EVENTS, event) or unit, event, ...)
	end
	U.set_flow_variable = function(unit, name, value)
		return variable(rifle_of(unit, M.SHOT_VARIABLES, name) or unit, name, value)
	end
	self.redirecting = true
	local ok, err = pcall(fn, ...)
	self.redirecting = false
	U.flow_event, U.set_flow_variable = flow, variable
	if not ok then error(err, 0) end
end

-- Puts a Justice on a turret running on the Perforator's settings, and makes the slave raycast again with
-- the shot's effects sent to the rifle. As reload_slave makes it (turret_component.lua:179), with the
-- turret as the shooter. A rifle that can't be mounted leaves the turret firing as it was.
function R:mount(component, unit, ctx, settings)
	local G = self.env.global
	local W, U, physics, weapons = G("World"), G("Unit"), G("PhysicsWorld"), G("WeaponUtility")
	local world = component.world_proxy:get_world()
	if not self.rifles[unit] then
		local node = U.node(unit, M.MOUNT_NODE)
		local rifle = W.spawn_unit(world, M.RIFLE, U.world_position(unit, node), U.world_rotation(unit, node))
		U.set_unit_visibility(rifle, true)
		W.link_unit(world, rifle, 0, unit, node)
		U.set_local_position(rifle, 0, G("Vector3")(M.MOUNT.x, M.MOUNT.y, M.MOUNT.z))
		U.set_local_rotation(rifle, 0, G("Quaternion").identity())
		self.rifles[unit] = { unit = rifle, world = world }
	end
	local st = ctx.state
	local shot = weapons.shoot_ray_callback(unit, ctx, component, { x = 0, y = 0, z = 0 }, false, settings.weapon_info, settings.explosive_info, st.owner_unit)
	st.raycast_slave = physics.make_raycast(W.physics_world(world), function(...) self:through_rifles(shot, ...) end,
		"all", "collision_filter", "damage_ray")
end

-- Takes the rifle off a turret that is going away.
function R:dismount(unit)
	local rifle = self.rifles[unit]
	if not rifle then return end
	self.rifles[unit] = nil
	local G = self.env.global
	local ok, err = pcall(function()
		if G("Unit").alive(rifle.unit) then
			G("World").unlink_unit(rifle.world, rifle.unit)
			G("World").destroy_unit(rifle.world, rifle.unit)
		end
	end)
	if not ok then self:log(err) end
end

-- The hook on HellpodComponent.setup_master, before the original runs.
function R:hellpod(setup)
	local ok, err = pcall(function()
		if type(setup) ~= "table" or type(setup.stratagem_info) ~= "table" or setup.stratagem_info.name ~= M.NAME then return end
		if not self:install() then
			self:log("the variants could not be installed; this one lands as a Railcannon Turret")
			return
		end
		M.mark(setup)
	end)
	if not ok then self:log(err) end
end

function R:is_turret(unit)
	local ok, path = pcall(self.env.unit_path, unit)
	return ok and path == M.UNIT
end

-- After TurretComponent.setup_master or setup_slave: watched for a while in case the upgrade value
-- reaches the unit late, or (on an owner taking over from a player who left) not at all at setup.
function R:watch(component, unit, ctx, slave)
	local ok, err = pcall(function()
		if not (type(ctx) == "table" and type(ctx.state) == "table" and self:is_turret(unit)) then return end
		local list = slave and self.slaves or self.masters
		list[unit] = { component = component, ctx = ctx, left = WATCH_FOR }
	end)
	if not ok then self:log(err) end
end

function R:settings_of(unit)
	local ls = self.env.global("LoadoutSettings")
	if type(ls) ~= "table" or type(ls.get_upgraded_settings) ~= "function" then return nil end
	local ok, s = pcall(ls.get_upgraded_settings, unit)
	return ok and type(s) == "table" and s or nil
end

-- After TurretComponent.reload_slave: the settings the slave raycast was just made with (the same call
-- reload_slave makes, turret_component.lua:173).
function R:reloaded(unit, ctx, component)
	local ok, err = pcall(function()
		if not (type(ctx) == "table" and type(ctx.state) == "table" and self:is_turret(unit)) then return end
		local s = self:settings_of(unit)
		self.built[ctx.state] = s and s.weapon_info or false
		if component and s and self.ours[s.weapon_info] then self:mount(component, unit, ctx, s) end
	end)
	if not ok then self:log(err) end
end

-- One watched turret. true once it runs on the Perforator's settings, nil while it isn't one (yet).
function R:sync(unit, w, slave)
	local s = self:settings_of(unit)
	local weapon = s and s.weapon_info
	if not (weapon and self.ours[weapon]) then return nil end
	local st = w.ctx.state
	if slave then
		if st.weapon_info ~= weapon or self.built[st] ~= weapon then
			-- The raycast keeps the settings it was made with: made again, keeping the turret's rotation.
			local start, rotation = st.start_rotation, st.rotation
			w.component:reload_slave(unit, w.ctx)
			if start ~= nil then st.start_rotation = start end
			if rotation ~= nil then st.rotation = rotation end
			st.turret_info, st.weapon_info = s.turret_info, weapon
			self.built[st] = weapon
			self:log("a slave turret picked up the Perforator settings late")
		end
	elseif st.weapon_info ~= weapon then
		st.turret_info, st.weapon_info = s.turret_info, weapon
		st.round_delay = 60 / weapon.firerate
		self:log("a turret taken over runs on the Perforator settings again")
	end
	return true
end

function R:tend(list, dt, slave)
	for unit, w in pairs(list) do
		w.left = w.left - dt
		local alive_ok, alive = pcall(self.env.alive, unit)
		if not (alive_ok and alive) or w.left <= 0 then
			list[unit] = nil
		else
			local ok, done = pcall(self.sync, self, unit, w, slave)
			if not ok then
				self:log(done)
				list[unit] = nil
			elseif done then
				list[unit] = nil
			end
		end
	end
end

function R:frame(dt)
	dt = tonumber(dt) or 0
	if dt ~= dt or dt < 0 then dt = 0 end
	self.timer = self.timer - dt
	if self.timer <= 0 then
		self.timer = CHECK_EVERY
		local ok, err = pcall(self.install, self)
		if not ok then self:log(err) end
		-- A turret removed without the game saying so.
		for unit in pairs(self.rifles) do
			local checked, alive = pcall(self.env.alive, unit)
			if not (checked and alive) then self:dismount(unit) end
		end
	end
	if not self.installed then return end
	if next(self.masters) then self:tend(self.masters, dt, false) end
	if next(self.slaves) then self:tend(self.slaves, dt, true) end
end

return M
