-- A small stand-in for the parts of the game the Repair Tower touches: units with health, the tesla and
-- time-to-live components, the particle world, the heal requests and the lobby's shared texts. One fake
-- is one machine. Its Tesla Tower master behaves as the game's does where it matters here: it fires at
-- anything in range once its start timer runs out, as long as `active` is true.
local F = {}

local V = {}
V.__index = V
V.__add = function(a, b) return F.v(a.x + b.x, a.y + b.y, a.z + b.z) end
function F.v(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end

local function copy_v(p) return F.v(p.x, p.y, p.z) end

function F.new(peer)
	local m = {
		peer = peer or "me", units = {}, goids = {}, next_goid = 100, in_mission = true,
		world = { particles = {}, created = 0, destroyed = 0, moved = 0, next_id = 1 },
		heals = {}, rpcs = {}, commands = {}, shots = {}, shared_out = {}, shared_in = {},
		masters = { tesla = {}, time_to_live = {} }, slaves = { tesla = {}, time_to_live = {}, vehicle = {}, turret = {} },
		paused = false,
	}

	-- def: pos {x,y,z}, owner (peer, this machine's by default), health { hitpoints, max_hitpoints,
	-- constitution }, info (health_info), comps (list of extra component names), nodes (names).
	function m:unit(def)
		local u = { alive = true, pos = def.pos or { x = 0, y = 0, z = 0 }, owner = def.owner or self.peer, comps = { health = true },
			nodes = {}, info = def.info, name = def.name }
		for _, c in ipairs(def.comps or {}) do u.comps[c] = true end
		for i, n in ipairs(def.nodes or {}) do u.nodes[n] = i end
		local h = def.health or { hitpoints = 100, max_hitpoints = 100, constitution = -100 }
		u.health = { hitpoints = h.hitpoints, max_hitpoints = h.max_hitpoints, constitution = h.constitution, is_dead = false }
		self.units[#self.units + 1] = u
		self.goids[u] = self.next_goid
		self.next_goid = self.next_goid + 1
		for _, c in ipairs({ "vehicle", "turret" }) do
			if u.comps[c] then self.slaves[c][u] = { state = {} } end
		end
		return u
	end

	function m:helldiver(pos, hp, owner)
		local u = self:unit({ pos = pos, owner = owner, health = { hitpoints = hp, max_hitpoints = 100, constitution = -100 },
			info = { healable = true, health = 100, constitution = 100, healing_node = "spine2" }, nodes = { "spine2" }, name = "helldiver" })
		u.avatar = true
		return u
	end

	function m:vehicle(pos, hp, owner)
		return self:unit({ pos = pos, owner = owner, comps = { "vehicle" }, health = { hitpoints = hp, max_hitpoints = 1000, constitution = -500 },
			info = { healable = true, health = 1000, constitution = 500, healing_node = "j_hut" }, nodes = { "j_hut" }, name = "mech" })
	end

	function m:enemy(pos)
		return self:unit({ pos = pos, owner = "host", health = { hitpoints = 300, max_hitpoints = 300, constitution = -50 },
			info = { healable = false, health = 300 }, name = "enemy" })
	end

	-- A Tesla Tower unit, set up through `setup` (the hooked setup_master, or the game's own) when this
	-- machine owns it. spawn as the hellpod hands it over.
	function m:tower(pos, spawn, owner, setup)
		F.current = self
		local u = self:unit({ pos = pos, owner = owner, comps = { "tesla", "time_to_live" }, nodes = { "j_muzzle" },
			health = { hitpoints = 800, max_hitpoints = 800, constitution = 0 }, info = { healable = true, health = 800 }, name = "tower" })
		u.muzzle = { x = pos.x, y = pos.y, z = pos.z + 1 }
		local info = { range = 8, num_bolts = 1, effect_offset = { x = 0, y = 0, z = 2 } }
		self.slaves.tesla[u] = { state = { start_invul_timer = 5.2, health_state = u.health, tesla_info = info } }
		self.slaves.time_to_live[u] = { state = { time_until_dead = 150 } }
		if u.owner == self.peer then
			local ctx = { state = {} }
			self.masters.tesla[u] = ctx
			self.masters.time_to_live[u] = { state = { time_until_dead = 150 } }
			setup(F.tesla, u, ctx, spawn)
		end
		return u
	end

	function m:kill(u) u.alive = false end

	-- The game's update for the parts faked here, then the frame callback, as the loader runs them.
	function m:step(dt, frame)
		rawset(_G, "REAL_TIME_DT", dt)
		F.current = self
		if not self.paused then
			for u, ctx in pairs(self.masters.tesla) do F.tesla.update_master(self, u, ctx, dt) end
			for _, ctx in pairs(self.slaves.tesla) do
				if ctx.state.start_invul_timer > 0 then ctx.state.start_invul_timer = ctx.state.start_invul_timer - dt end
			end
			for _, map in ipairs({ self.slaves.time_to_live, self.masters.time_to_live }) do
				for _, ctx in pairs(map) do ctx.state.time_until_dead = ctx.state.time_until_dead - dt end
			end
		end
		if frame then frame() end
	end

	function m:run(seconds, frame, dt)
		dt = dt or 0.05
		local steps = math.floor(seconds / dt + 0.5)
		for _ = 1, steps do self:step(dt, frame) end
	end

	local function apply_heal(u, amount)
		if u.health.hitpoints > u.health.constitution then
			u.health.hitpoints = math.min(u.health.hitpoints + amount, u.health.max_hitpoints)
		end
	end

	-- The API, as far as the runtime calls it.
	m.api = {
		game = {
			in_mission = function() return m.in_mission end,
			state = function()
				return {
					world_proxy = { get_world = function() return m.in_mission and m.world or nil end },
					entity_storage = {
						go_id = function(_, u) return m.goids[u] or -1 end,
						unit = function(_, id) for u, g in pairs(m.goids) do if g == id then return u end end end,
					},
					network_router = { transmit_to = function(_, peer, name, u, amount)
						m.rpcs[#m.rpcs + 1] = { peer = peer, name = name, unit = u, amount = amount }
						if name == "rpc_heal_request" then
							m.heals[#m.heals + 1] = { unit = u, amount = amount, how = "rpc" }
							apply_heal(u, amount)
						end
					end },
				}
			end,
			masters = function(name) return m.masters[name] or {} end,
			slaves = function(name) return m.slaves[name] or {} end,
			all_avatars = function()
				local out = {}
				for _, u in ipairs(m.units) do
					if u.avatar and u.alive then out[#out + 1] = { unit = u, owned = u.owner == m.peer } end
				end
				return out
			end,
			command = function(u, comp, cmd, data)
				m.commands[#m.commands + 1] = { unit = u, comp = comp, cmd = cmd, data = data }
				if comp == "health" and cmd == "do_heal" and u.owner == m.peer then
					m.heals[#m.heals + 1] = { unit = u, amount = data, how = "command" }
					apply_heal(u, data)
					return true
				end
				return false
			end,
		},
		lobby = {
			share = function(name, value) m.shared_out[name] = value return true end,
			shared = function(name) return m.shared_in[name] or {} end,
		},
	}
	return m
end

-- The game's Tesla Tower as far as these tests need it. setup_master sets `active` as the game does, and
-- update_master shoots when it's on, the timer has run out and something with health is in range.
F.tesla = {}
function F.tesla.setup_master(_, u, ctx, spawn)
	local state = ctx.state
	state.active = true
	state.start_invul_timer = 5.2
	state.health_state = u.health
	state.tesla_info = { range = 8, num_bolts = 1 }
	state.owner_unit = spawn and spawn.owner_unit
end
setmetatable(F.tesla, { __call = function(_, ...) return F.tesla.setup_master(...) end })

function F.tesla.update_master(machine, u, ctx, dt)
	local state = ctx.state
	if state.start_invul_timer > 0 then
		state.start_invul_timer = state.start_invul_timer - dt
		return
	end
	if not state.active then return end
	for _, other in ipairs(machine.units) do
		if other ~= u and other.alive and not other.health.is_dead then
			local dx, dy, dz = other.pos.x - u.pos.x, other.pos.y - u.pos.y, other.pos.z - u.pos.z
			if dx * dx + dy * dy + dz * dz <= 64 then machine.shots[#machine.shots + 1] = { from = u, at = other } end
		end
	end
end

-- The engine's globals, reading whichever machine is stepping.
function F.globals()
	local function cur() return F.current end
	rawset(_G, "INVALID_GAME_OBJECT_ID", 65535)
	rawset(_G, "Vector3", function(x, y, z) return F.v(x, y, z) end)
	rawset(_G, "Vector3Aux", { unbox = function(t) return F.v(t.x, t.y, t.z) end })
	rawset(_G, "Unit", {
		alive = function(u) return type(u) == "table" and u.alive == true end,
		has_node = function(u, name) return u.nodes[name] ~= nil end,
		node = function(u, name)
			local i = u.nodes[name]
			if not i then error("no node " .. tostring(name)) end
			return i
		end,
		world_position = function(u, node)
			if node == u.nodes.j_muzzle and u.muzzle then return copy_v(u.muzzle) end
			if node ~= 0 then return F.v(u.pos.x, u.pos.y, u.pos.z + 1.2) end
			return copy_v(u.pos)
		end,
	})
	rawset(_G, "EntityAux", {
		has_component = function(u, c) return u.comps[c] == true end,
		has_component_master = function(u, c) return u.comps[c] == true and u.owner == cur().peer end,
		state = function(u, c) if c == "health" then return u.health end end,
		owner = function(u) return u.owner end,
	})
	rawset(_G, "LuaSettingsManager", { get_settings_by_unit = function(_, u) return { health_info = u.info } end })
	rawset(_G, "World", {
		find_particles_variable = function(_, name, var) return name .. "#" .. var end,
		create_particles = function(w, name, pos)
			assert(name == "effects/generated/wep_rep_01_beam", "beam effect")
			local id = w.next_id
			w.next_id = id + 1
			w.particles[id] = { vars = {}, pos = pos }
			w.created = w.created + 1
			return id
		end,
		set_particles_variable = function(w, id, var, value)
			assert(w.particles[id], "particle " .. tostring(id) .. " exists")
			w.particles[id].vars[var] = value
		end,
		move_particles = function(w, id, pos)
			assert(w.particles[id], "particle exists")
			w.particles[id].pos = pos
			w.moved = w.moved + 1
		end,
		destroy_particles = function(w, id)
			assert(w.particles[id], "particle " .. tostring(id) .. " destroyed once")
			w.particles[id] = nil
			w.destroyed = w.destroyed + 1
		end,
	})
end

function F.live(w)
	local n = 0
	for _ in pairs(w.particles) do n = n + 1 end
	return n
end

return F
