-- The A/AC-90 Repair Tower in a mission. What lands is the game's own Tesla Tower unit, so every game
-- has it; the thrower's game marks it and switches its attack off, and the tower's owner heals with the
-- game's own heal requests, which reach players without this mod too. Every machine running this mod
-- draws the REP-80 beams.
--
-- Silent: TeslaComponent.update_masters only looks for targets while the master state's `active` is
-- true (tesla_component.lua:199), and only the master decides to shoot, so `active = false` on the
-- owner's machine keeps the tower from firing on every machine. The game's own "stop_attacking"
-- command would do that too, but it also sets time_to_die, which closes the tower (:298, :262).
--
-- Ownership: when the owner leaves, the tower moves to another machine, whose setup_master sets `active`
-- again (base_component.lua:102). The owner shares its towers with the lobby, so a machine running this
-- mod that takes one over switches it off again, on the frame it does, well within the 5.2 seconds the
-- tower takes to start looking for targets.
local levels = obsidian.module("src/repair_levels")
local targets = obsidian.module("src/repair_targets")
local share = obsidian.module("src/repair_share")

local M = {}

M.BEAM = "effects/generated/wep_rep_01_beam"
M.SHARE_NAME = "towers"
M.SHARE_EVERY = 1
-- Units the tower can heal besides Helldivers, by the component they have.
M.MACHINES = { "vehicle", "turret", "launcher_turret", "melee_turret", "tesla" }

local function g(name)
	return rawget(_G, name)
end

local R = {}
R.__index = R

function M.new(api)
	return setmetatable({
		api = api,
		towers = {},      -- tower unit -> { level, beams = { target unit -> particle id }, targets, timer, ttl }
		world = nil,
		vars = nil,       -- the beam effect's variables in this world
		info = setmetatable({}, { __mode = "k" }), -- unit -> health_info from its settings
		share_timer = 0,
		frame_candidates = nil,
	}, R)
end

-- Seconds since the last frame, from the game's own frame time.
local function frame_dt()
	local dt = tonumber(g("REAL_TIME_DT")) or 0
	if dt ~= dt or dt < 0 then return 0 end
	return math.min(dt, 0.25)
end

function R:register(unit, level)
	local t = self.towers[unit]
	if not t then
		t = { beams = {}, targets = {}, timer = 0, world = self:current_world() }
		self.towers[unit] = t
	end
	t.level = level
	return t
end

-- The hook on TeslaComponent.setup_master(component, unit, ctx, spawn), which runs on the machine that
-- owns the tower. spawn is what the hellpod hands the unit (hellpod_component.lua:9-30): the thrower, the
-- stratagem's entry and the upgrade value. The thrower's game has the Repair Tower's own entry there. A
-- takeover sets the unit up again without one.
function R:setup_master(original, component, unit, ctx, spawn, ...)
	original(component, unit, ctx, spawn, ...)
	local state = type(ctx) == "table" and ctx.state
	local info = type(spawn) == "table" and spawn.stratagem_info
	if type(info) == "table" and info.name == levels.NAME then
		if state then state.active = false end
		local _, n = levels.of(spawn.upgrade_value)
		self:register(unit, n)
	elseif self.towers[unit] and state then
		-- A tower this machine takes over from a player who left.
		state.active = false
	end
end

function R:health_info(unit)
	local cached = self.info[unit]
	if cached ~= nil then return cached or nil end
	local lsm = g("LuaSettingsManager")
	local settings = lsm and lsm:get_settings_by_unit(unit)
	local info = type(settings) == "table" and settings.health_info or false
	self.info[unit] = info
	return info or nil
end

-- Everything a tower could heal, once per frame for all towers: Helldivers, then vehicles and turrets.
function R:candidates()
	if self.frame_candidates then return self.frame_candidates end
	local api, Unit, aux = self.api, g("Unit"), g("EntityAux")
	local out, seen = {}, {}
	local function add(unit, kind)
		if not unit or seen[unit] then return end
		seen[unit] = true
		if not (Unit.alive(unit) and aux.has_component(unit, "health")) then return end
		local info = self:health_info(unit)
		if not (info and info.healable) then return end
		local h = aux.state(unit, "health")
		if type(h) ~= "table" then return end
		local p = Unit.world_position(unit, 0)
		out[#out + 1] = {
			unit = unit, kind = kind, x = p.x, y = p.y, z = p.z, node = info.healing_node,
			hp = tonumber(h.hitpoints) or 0, max = tonumber(h.max_hitpoints) or tonumber(info.health) or 0,
			floor = tonumber(h.constitution) or -(tonumber(info.constitution) or 0), dead = h.is_dead == true,
		}
	end
	for _, a in ipairs(api.game.all_avatars()) do add(a.unit, "helldiver") end
	for _, name in ipairs(M.MACHINES) do
		for unit in pairs(api.game.slaves(name)) do add(unit, "machine") end
	end
	self.frame_candidates = out
	return out
end

-- A heal through the target's owner: a command when that's this machine, the game's request otherwise.
function R:heal(st, unit, amount)
	local aux = g("EntityAux")
	if aux.has_component_master(unit, "health") then
		return self.api.game.command(unit, "health", "do_heal", amount)
	end
	local router = type(st) == "table" and st.network_router
	if not router then return false end
	router:transmit_to(aux.owner(unit), "rpc_heal_request", unit, amount)
	return true
end

-- Up, not closing, not destroyed, and done rising out of the hellpod.
local function working(state)
	if type(state) ~= "table" then return false end
	local health = state.health_state
	if type(health) == "table" and health.is_dead then return false end
	if state.time_to_die then return false end
	return (tonumber(state.start_invul_timer) or 0) <= 0
end

-- The tower's own clock: what its time to live lost since the last frame, so a paused game heals
-- nothing. The game's frame time where that isn't there.
function R:clock(unit, t)
	local ctx = self.api.game.slaves("time_to_live")[unit] or self.api.game.masters("time_to_live")[unit]
	local left = type(ctx) == "table" and type(ctx.state) == "table" and tonumber(ctx.state.time_until_dead)
	if not left then return frame_dt() end
	local dt = t.ttl and (t.ttl - left) or 0
	t.ttl = left
	if dt < 0 or dt > 1 then return 0 end
	return dt
end

function R:variables()
	if not self.vars then
		local World = g("World")
		self.vars = {
			start = World.find_particles_variable(self.world, M.BEAM, "start"),
			finish = World.find_particles_variable(self.world, M.BEAM, "end"),
			size = World.find_particles_variable(self.world, M.BEAM, "size"),
		}
	end
	return self.vars
end

-- Where a beam leaves the tower: where its lightning would (tesla_component.lua:131-137).
local function beam_from(unit, state)
	local Unit, V3, V3A = g("Unit"), g("Vector3"), g("Vector3Aux")
	local node = Unit.has_node(unit, "j_muzzle") and Unit.node(unit, "j_muzzle") or 0
	local info = type(state) == "table" and state.tesla_info
	local offset = type(info) == "table" and info.effect_offset and V3A.unbox(info.effect_offset) or V3(0, 0, 2)
	return Unit.world_position(unit, node) + offset
end

-- Where it meets a target: the node the REP-80 aims for, or half a metre over the root.
local function beam_to(c)
	local Unit, V3 = g("Unit"), g("Vector3")
	if c.node and Unit.has_node(c.unit, c.node) then return Unit.world_position(c.unit, Unit.node(c.unit, c.node)) end
	return Unit.world_position(c.unit, 0) + V3(0, 0, 0.5)
end

function R:clear_beams(t)
	local World = g("World")
	for target, id in pairs(t.beams) do
		if self.world then World.destroy_particles(self.world, id) end
		t.beams[target] = nil
	end
end

-- The mission's world, or nil off a mission.
function R:current_world()
	local api = self.api
	if not api.game.in_mission() then return nil end
	local st = api.game.state()
	return type(st) == "table" and st.world_proxy and st.world_proxy:get_world() or nil
end

-- Every beam off, and the towers kept: for a lobby that stops being cleared, which stops the frames.
-- Particles of a world the game already destroyed are only forgotten.
function R:clear_all_beams()
	if self.world and self:current_world() ~= self.world then return self:drop(false) end
	for _, t in pairs(self.towers) do self:clear_beams(t) end
end

-- Everything forgotten. destroy: the world is still there, so its particles go too.
function R:drop(destroy)
	if destroy then self:clear_all_beams() end
	self.towers, self.world, self.vars = {}, nil, nil
	self.info = setmetatable({}, { __mode = "k" })
end

function R:draw(t, unit, state)
	local World, Unit, aux, V3 = g("World"), g("Unit"), g("EntityAux"), g("Vector3")
	local keep = {}
	local from = nil
	for _, c in ipairs(t.targets) do
		local h = Unit.alive(c.unit) and aux.state(c.unit, "health")
		if type(h) == "table" and not h.is_dead then
			keep[c.unit] = true
			from = from or beam_from(unit, state)
			local vars, to = self:variables(), beam_to(c)
			local id = t.beams[c.unit]
			if not id then
				id = World.create_particles(self.world, M.BEAM, from)
				t.beams[c.unit] = id
			end
			World.set_particles_variable(self.world, id, vars.start, from)
			World.set_particles_variable(self.world, id, vars.finish, to)
			World.set_particles_variable(self.world, id, vars.size, V3(1, 0, 0))
			World.move_particles(self.world, id, from)
		end
	end
	for target, id in pairs(t.beams) do
		if not keep[target] then
			World.destroy_particles(self.world, id)
			t.beams[target] = nil
		end
	end
end

-- Towers other machines own, from what they share, and the ones this machine owns, shared.
function R:sync(st, masters)
	local api, Unit, aux = self.api, g("Unit"), g("EntityAux")
	local storage = type(st) == "table" and st.entity_storage
	if not storage then return end
	for _, text in pairs(api.lobby.shared(M.SHARE_NAME)) do
		for _, e in ipairs(share.decode(text)) do
			local unit = storage:unit(e.id)
			if unit and not self.towers[unit] and Unit.alive(unit) and aux.has_component(unit, "tesla") then
				local _, n = levels.of(e.level)
				self:register(unit, n)
			end
		end
	end
	local invalid = g("INVALID_GAME_OBJECT_ID")
	local list = {}
	for unit, t in pairs(self.towers) do
		if masters[unit] then
			local id = storage:go_id(unit)
			if type(id) == "number" and id ~= invalid then list[#list + 1] = { id = id, level = t.level } end
		end
	end
	api.lobby.share(M.SHARE_NAME, share.encode(list))
end

function R:frame()
	local api = self.api
	local world = self:current_world()
	if not world then
		if self.world then self:drop(false) end
		return
	end
	if world ~= self.world then
		-- A new mission: what the last one had went with its world. A tower set up since keeps going.
		local kept = {}
		for unit, t in pairs(self.towers) do
			if t.world == world then kept[unit] = t end
		end
		self:drop(false)
		self.towers, self.world = kept, world
	end
	local st = api.game.state()
	self.frame_candidates = nil
	local masters = api.game.masters("tesla")
	self.share_timer = self.share_timer - frame_dt()
	if self.share_timer <= 0 then
		self.share_timer = M.SHARE_EVERY
		self:sync(st, masters)
	end
	if next(self.towers) == nil then return end

	local Unit = g("Unit")
	local slaves = api.game.slaves("tesla")
	for unit, t in pairs(self.towers) do
		if not Unit.alive(unit) then
			self:clear_beams(t)
			self.towers[unit] = nil
		else
			local m = masters[unit]
			if m and type(m.state) == "table" and m.state.active then m.state.active = false end
			local s = slaves[unit] or m
			local state = s and s.state
			if working(state) then
				t.timer = t.timer - self:clock(unit, t)
				if t.timer <= 0 then
					t.timer = math.max(t.timer + levels.TICK, 0)
					local level = levels.of(t.level)
					local p = Unit.world_position(unit, 0)
					t.targets = targets.pick({ unit = unit, x = p.x, y = p.y, z = p.z }, self:candidates(), level)
					if m then
						for _, c in ipairs(t.targets) do self:heal(st, c.unit, levels.amount(level, c.kind)) end
					end
				end
				self:draw(t, unit, state)
			else
				self:clear_beams(t)
				t.targets = {}
			end
		end
	end
end

return M
