-- A small stand-in for what the SEAF squad touches: Obsidian API's bots, lobby, catalog and stratagems, on
-- one or more machines that share a lobby. A net holds what every machine sees: the members, the shared
-- texts and the units by game object id. Each machine has separate pads, bots and a player.
local F = {}

-- The net: seed (the mission seed), members (peers in the lobby, in order).
function F.net(seed)
	return { seed = seed or 4242, members = {}, shared = {}, units = {}, next_id = 100, aboard = false, machines = {} }
end

local function unit(net, pos, owner)
	local u = { alive = true, dead = false, pos = { x = pos.x, y = pos.y, z = pos.z or 0 }, hp = 1, owner = owner }
	net.next_id = net.next_id + 1
	u.id = net.next_id
	net.units[u.id] = u
	return u
end

local Bot = {}
Bot.__index = Bot

function Bot:unit() return self.body and self.body.alive and self.body or nil end
function Bot:position() local u = self:unit() return u and { x = u.pos.x, y = u.pos.y, z = u.pos.z } or nil end
function Bot:give_weapon(slot, path) self.gear[slot] = path return true end
function Bot:give_perk(name) self.gear.perk = name return true end
function Bot:remove_perk() self.gear.perk = false return true end
function Bot:set_health(share) self.body.hp = share return true end
function Bot:weapons() return {} end
local function order(name)
	return function(self, ...) self.orders[name] = { ... } return self end
end
for _, name in ipairs({ "fight", "follow", "ride_along", "auto_revive", "auto_get_up", "avoid_shots", "auto_pickup", "navigate", "movement", "auto_grenades" }) do Bot[name] = order(name) end
function Bot:board(on_done)
	self.boarding = on_done or true
	return true
end
function Bot:remove(opts)
	self.removed = true
	self.decay = type(opts) == "table" and opts.decay or nil
	if not self.decay and self.body then self.body.alive = false end
	local m = self.machine
	for i, b in ipairs(m.bots) do
		if b == self then table.remove(m.bots, i) break end
	end
	return true
end

-- A machine in the net: peer, pads (free game pads with no bot), avatar (the player's unit).
function F.machine(net, peer, opts)
	opts = opts or {}
	local m = { net = net, peer = peer, pads = opts.pads or 4, bots = {}, given = 0, logs = {}, leave_fns = {}, last = {},
		usable = opts.usable or {}, blind = {}, in_mission = true, state = { mission_seed = net.seed } }
	m.avatar = unit(net, opts.pos or { x = 0, y = 0, z = 0 }, peer)
	net.members[#net.members + 1] = peer
	net.machines[peer] = m
	net.shared[peer] = {}

	local function free() return math.max(0, m.pads - #m.bots) end

	m.api = {
		game = {
			in_mission = function() return m.in_mission end,
			state = function() return m.in_mission and m.state or nil end,
			my_unit = function() return m.avatar.alive and not m.avatar.dead and m.avatar or nil end,
			global = function(name)
				if name == "LoadoutSettings" then
					return { stratagems = { { id = 1, name = "stratagem_resupply" }, { id = 14, name = "stratagem_machinegun" },
						{ id = 15, name = "stratagem_flamethrower" }, { id = 16, name = "stratagem_repairtool" } } }
				elseif name == "GameSettings" then
					return { player_colors = { { x = 1 }, { x = 2, y = 20, z = 200, w = 255 } } }
				end
			end,
			masters = function() return {} end,
		},
		bots = {
			free_pads = function() return m.in_mission and free() or 0 end,
			add = function(o)
				if o.require_pad and free() == 0 then return nil, "no_pad" end
				if m.refuse_look and o.look then return nil, "bad_value" end
				local b = setmetatable({ machine = m, opts = o, name = o.name, gear = {}, orders = {}, look = o.look, guest = o.guest }, Bot)
				b.body = unit(net, o.position, peer)
				m.bots[#m.bots + 1] = b
				return b
			end,
			humans = function()
				local out = {}
				for _, p in ipairs(net.members) do
					local a = net.machines[p] and net.machines[p].avatar
					if a and a.alive and not a.dead then out[#out + 1] = a end
				end
				return out
			end,
			player_aboard = function() return net.aboard end,
		},
		lobby = {
			players = function()
				local out = {}
				for _, p in ipairs(net.members) do out[#out + 1] = { peer = p, me = p == peer } end
				return out
			end,
			share = function(name, value)
				net.shared[peer][name] = (value ~= nil and value ~= "") and value or nil
				return true
			end,
			shared = function(name)
				local out = {}
				for _, p in ipairs(net.members) do
					local v = p ~= peer and not m.blind[p] and net.shared[p] and net.shared[p][name]
					if v then
						out[p] = v
						m.last[p] = v
					end
				end
				return out
			end,
			last_shared = function(_, p) return m.last[p] end,
			on_leave = function(fn) m.leave_fns[#m.leave_fns + 1] = fn return true end,
		},
		catalog = {
			usable = function(name) return m.usable[name] ~= false end,
			support_weapons = function()
				return { { name = "stratagem_machinegun", unit_path = "equipment/wep_mg" }, { name = "stratagem_flamethrower", unit_path = "equipment/wep_flame" },
					{ name = "stratagem_repairtool", unit_path = "equipment/wep_repairtool_01" } }
			end,
		},
		-- api.gear.add_perk: the perks added on top of a body's main one are listed on the body. Refuses a perk
		-- the player cannot use, as the real one does ("not_available").
		gear = {
			add_perk = function(name, unit)
				if m.usable[name] == false then return false, "not_available" end
				if m.add_perk_error then error("add_perk failed") end
				unit.extra_perks = unit.extra_perks or {}
				unit.extra_perks[#unit.extra_perks + 1] = name
				return true
			end,
		},
		stratagems = { give = function(name, owner) m.given = m.given + 1 m.given_to = { name, owner } return true end },
	}

	local rolls = 0
	m.env = {
		goid = function(u) return u.id end,
		unit_of = function(id) local u = net.units[id] return u and u.alive and u or nil end,
		position = function(u) return u and u.alive and { x = u.pos.x, y = u.pos.y, z = u.pos.z } or nil end,
		health = function(u) return u.hp end,
		-- A fixed run of answers, so a kit is the same each run.
		rng = function(n) rolls = rolls + 1 return (rolls % n) + 1 end,
		log = function(text) m.logs[#m.logs + 1] = text end,
		members = function() return nil end,
	}

	-- The API's own frame for these bots: a body that died tells on_death once.
	function m:frame()
		for _, b in ipairs(self.bots) do
			if b.body and b.body.dead and not b.told then
				b.told = true
				if b.opts.on_death then b.opts.on_death(b) end
			end
		end
	end
	return m
end

-- Every machine's API frame and squad tick, `seconds` long in steps of dt.
function F.run(net, squads, seconds, dt)
	dt = dt or 0.25
	for _ = 1, math.floor(seconds / dt + 0.5) do
		for peer, s in pairs(squads) do
			local m = net.machines[peer]
			if m then
				m:frame()
				s:tick(dt)
			end
		end
	end
end

-- A peer leaves: the game kills the bodies that machine owned, and every machine still here hears of it.
function F.leave(net, peer)
	for i, p in ipairs(net.members) do
		if p == peer then table.remove(net.members, i) break end
	end
	for _, u in pairs(net.units) do
		if u.owner == peer then u.alive = false end
	end
	net.machines[peer] = nil
	for _, p in ipairs(net.members) do
		for _, fn in ipairs(net.machines[p].leave_fns) do fn(peer) end
	end
end

return F
