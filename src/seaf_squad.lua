-- SEAF soldiers in a mission: the call-in, their gear and orders, deaths, the shared registry, and the
-- handover when a player leaves. The machine that throws the beacon spawns and drives the soldiers, as
-- guest bots of Obsidian API (bare Helldivers with no player record and no HUD slot).
--
-- A body can't change machines: the game kills a Helldiver that moves to another machine
-- (CharacterComponent.migrated_to_me). So when a player leaves, the machine every other machine picks as
-- heir (seaf_heir) spawns new soldiers with the same Mk, perk, weapon and health near where the old ones
-- stood. A lost soldier is better than a doubled one: a soldier the leaver hadn't shared yet is lost, and
-- of two machines that both took one over, the higher peer gives theirs up.
local kit = obsidian.module("src/seaf_kit")
local rules = obsidian.module("src/seaf_rules")
local registry = obsidian.module("src/seaf_registry")
local heir = obsidian.module("src/seaf_heir")

local M = {}

M.NAME = "stratagem_seaf_unit"
M.SHARE = "seaf"
M.DECAY = 5             -- seconds a corpse stays before it sinks away
M.SHARE_EVERY = 1       -- seconds between looks at the registry
M.HANDOVER_WAIT = 2     -- seconds after a player leaves before the heir acts, for the lobby to settle
M.CLAIM_TIME = 4        -- seconds a claim stays in the shared value after the soldiers are spawned
M.FOLLOW = 6            -- metres a soldier keeps to the one it follows
M.FIGHT = 25            -- metres a soldier fights in
M.REVIVE = 15           -- metres a soldier goes to help someone up
M.PICKUP = 12           -- metres a soldier goes for something lying about
M.FALLBACK_LOOK = { helmet = 4, body = 4 }
M.PICKUP_KINDS = { "research_sample_pickup", "ammo_pickup", "weapon_pickup" }
M.CORPSE_WATCH = 2      -- seconds a dead soldier's body is watched for the weapon it drops
M.CORPSE_REACH = 4      -- metres from the body a dropped weapon can come to rest in

local S = {}
S.__index = S

local function g(name)
	return rawget(_G, name)
end

-- What the squad reads from the game, apart from the API: game object ids, positions and health. A test
-- hands in the machine's own.
local function default_env(api)
	local env = {}
	function env.goid(unit)
		local st = api.game.state()
		local storage = type(st) == "table" and st.entity_storage
		if not storage then return nil end
		local ok, id = pcall(storage.go_id, storage, unit)
		return ok and type(id) == "number" and id or nil
	end
	function env.unit_of(id)
		local st = api.game.state()
		local storage = type(st) == "table" and st.entity_storage
		if not storage then return nil end
		local ok, unit = pcall(storage.unit, storage, id)
		return ok and unit or nil
	end
	function env.position(unit)
		local units = g("Unit")
		if not (unit and units and units.alive(unit)) then return nil end
		local p = units.world_position(unit, 0)
		return { x = p.x, y = p.y, z = p.z }
	end
	function env.health(unit)
		local aux = g("EntityAux")
		local ok, h = pcall(aux.state, unit, "health")
		if not (ok and type(h) == "table") then return nil end
		local most = tonumber(h.max_hitpoints)
		if not (most and most > 0) then return nil end
		return math.max(0, math.min(1, (tonumber(h.hitpoints) or most) / most))
	end
	function env.members()
		local session = obsidian.session
		if not (session and session.members) then return nil end
		local ok, list = pcall(session.members)
		return ok and list or nil
	end
	function env.rng(n) return math.random(n) end
	function env.log(text) obsidian.log(text) end
	return env
end

-- api: Obsidian API. env, all optional: look (the seaf_look module), members(), rng(n), log(text),
-- goid(unit), unit_of(id), position(unit), health(unit), kit_state(bot).
function M.new(api, env)
	local base = default_env(api)
	for k, v in pairs(env or {}) do base[k] = v end
	local s = setmetatable({ api = api, env = base, bots = {}, peers = {}, positions = {}, pending = {}, present = {},
		wait = 0, clock = 0, counter = 0, mission = nil, seed = nil, claim = nil, claim_until = nil, inherited = {},
		corpses = {}, seen_pickups = {} }, S)
	if api.lobby and api.lobby.on_leave then
		api.lobby.on_leave(function(peer) s:on_leave(peer) end)
	end
	return s
end

function S:log(text)
	pcall(self.env.log, text)
end

-- A new mission starts empty: the API drops every bot with the game state that had them.
function S:sync_mission()
	local st = self.api.game.state()
	if st ~= self.mission then
		self.mission = st
		self.seed = type(st) == "table" and st.mission_seed or nil
		self.bots, self.peers, self.positions, self.pending, self.inherited = {}, {}, {}, {}, {}
		self.claim, self.claim_until, self.counter = nil, nil, 0
		self.corpses, self.seen_pickups = {}, {}
	end
end

-- This machine's peer id, from the lobby list.
function S:me()
	for _, p in ipairs(self.api.lobby.players() or {}) do
		if p.me then return p.peer end
	end
	return nil
end

-- Soldiers alive in the squad: this machine's and those every other machine still here shares.
function S:squad_alive()
	local n = 0
	for _, rec in ipairs(self.bots) do
		if not rec.dead then n = n + 1 end
	end
	for peer, state in pairs(self.peers) do
		if self.present[peer] then n = n + #state.bots end
	end
	return n
end

-- The perks and support weapons this player can hand out.
function S:choices()
	local catalog = self.api.catalog
	local perks = kit.perks(catalog and catalog.usable)
	local weapons = kit.weapons(catalog and catalog.support_weapons and catalog.support_weapons() or {})
	return perks, weapons
end

-- The stratagem id of a support weapon, and back, from the game's list: the same on every machine.
function S:weapon_id(name)
	local ls = self.api.game.global("LoadoutSettings")
	for _, s in ipairs(ls and ls.stratagems or {}) do
		if s.name == name then return s.id end
	end
	return 0
end

function S:weapon_name(id)
	if not id or id == 0 then return nil end
	local ls = self.api.game.global("LoadoutSettings")
	for _, s in ipairs(ls and ls.stratagems or {}) do
		if s.id == id then return s.name end
	end
	return nil
end

-- The look of a soldier, worked out at each call and each handover: the white and blue set when it is
-- installed and every player in the lobby has it (seaf_look.pick), else the vanilla mix; gender 1 and the
-- blue outline either way. A player without the set would fail on pieces the game doesn't list for them.
function S:look()
	local idx = nil
	local look = self.env.look
	if look then
		local ok, got = pcall(function()
			if look.pick then return look.pick(self.env.members()) end
			return look.indexes() or look.fallback()
		end)
		if ok and type(got) == "table" then idx = got end
	end
	idx = idx or M.FALLBACK_LOOK
	local out = { helmet = idx.helmet, body = idx.body, cape = idx.cape, gender = 1 }
	local settings = self.api.game.global("GameSettings")
	local colors = type(settings) == "table" and settings.player_colors
	if type(colors) == "table" and type(colors[2]) == "table" then out.color = colors[2] end
	return out
end

-- One soldier: a guest bot at pos. rec.kit, rec.hp (0 to 1). Answers the record, or nil when the API
-- refused (no free pad, for one).
function S:spawn(k, pos, hp)
	self.counter = self.counter + 1
	local rec = { kit = k, hp = hp or 1, name = "SEAF " .. self.counter, seed = self.counter }
	local opts = { bare = true, guest = true, require_pad = true, loadout = "default", name = rec.name, position = pos, look = self:look(),
		on_death = function() self:died(rec) end }
	local b, why = self.api.bots.add(opts)
	if not b and why == "bad_value" then
		opts.look = nil
		b, why = self.api.bots.add(opts)
	end
	if not b then
		self:log("SEAF soldier not added: " .. tostring(why))
		return nil
	end
	rec.bot = b
	self.bots[#self.bots + 1] = rec
	self:prepare(rec)
	return rec
end

-- Gear and orders, once the body is there: the spawn is queued, so this waits for it. The body comes with
-- the game's default loadout (add's loadout = "default"): the Liberator, the pistol and the default perk,
-- which is the Mk1 kit. Mk2 adds a perk and a support weapon. The game takes out each weapon it is given
-- (InventoryComponent "set_weapon"), so fight's "threat" brings the right one back out: the Liberator for most
-- targets, the support weapon for what deserves it, the pistol once the Liberator has no ammunition. Orders run on
-- this machine, the one that owns the soldier, as the input they drive is read here only. Routes (navigate),
-- soldierly movement and grenades (auto_grenades) come with the API's 1.45.0.
function S:prepare(rec)
	if rec.ready or rec.dead then return end
	local b = rec.bot
	if not b:unit() then return end
	rec.ready = true
	if rec.kit.perk then b:give_perk(rec.kit.perk) end
	kit.equip(self.api, b:unit())
	if rec.kit.weapon then b:give_weapon("support_weapon", rec.kit.weapon.unit_path) end
	if rec.hp and rec.hp < 1 and rec.hp > 0 then b:set_health(rec.hp) end
	b:fight(M.FIGHT, { weapon = "threat" })
	b:follow(function(bot) return self:follow_target(bot) end, M.FOLLOW)
	b:navigate(true)
	b:movement({ seed = rec.seed })
	b:auto_grenades(true)
	b:ride_along(true)
	b:auto_revive(M.REVIVE)
	b:auto_get_up(true)
	b:avoid_shots(true, { melee = true })
	b:auto_pickup({ kinds = M.PICKUP_KINDS, radius = M.PICKUP, want = function(item, bot) return self:wants(item, bot) end })
end

-- The player of this machine while alive, else the nearest living player.
function S:follow_target(bot)
	local humans = {}
	local me = self.api.game.my_unit()
	local owner = nil
	for _, unit in ipairs(self.api.bots.humans()) do
		local p = self.env.position(unit)
		if p then
			humans[#humans + 1] = { unit = unit, x = p.x, y = p.y }
			if unit == me then owner = { unit = unit } end
		end
	end
	return rules.follow_target(owner, humans, bot:position())
end

function S:kit_state(bot)
	if self.env.kit_state then return self.env.kit_state(bot) end
	local low, support = false, false
	for _, w in ipairs(bot:weapons() or {}) do
		if w.slot == "support_weapon" then support = true end
		local master = self.api.game.masters(w.component)[w.unit]
		local state = master and master.state
		local mags = state and tonumber(state.num_mags)
		local start = type(w.info) == "table" and tonumber(w.info.magazines)
		if mags and start and start > 0 and mags < start / 2 then low = true end
	end
	return { ammo_low = low, support_empty = not support }
end

-- Ammunition comes back by itself while a soldier holds less than the kit started with (rules.ammo_step). A weapon
-- with magazines gets those back; one with none to spare, as a single-shot launcher, gets the round back; a laser
-- the radiators. Through the API's add_ammo, on this machine, which owns the soldier.
function S:recover_ammo(rec, dt)
	if not (rec.ready and not rec.dead and rec.bot.add_ammo) or dt <= 0 then return end
	rec.ammo = rec.ammo or {}
	for _, w in ipairs(rec.bot:weapons() or {}) do
		local master = self.api.game.masters(w.component)[w.unit]
		local state = master and master.state
		if state then
			local mags, rounds = tonumber(state.num_mags), tonumber(state.rounds)
			local a = rec.ammo[w.unit]
			if not a then
				a = { timer = 0, start_mags = math.max(mags or 0, type(w.info) == "table" and tonumber(w.info.magazines) or 0), start_rounds = rounds or 0 }
				rec.ammo[w.unit] = a
			end
			local add
			if a.start_mags > 0 then
				a.timer, add = rules.ammo_step(w.slot, a.timer, dt, mags, a.start_mags)
				if add > 0 then rec.bot:add_ammo(w.slot, add) end
			elseif rounds and type(state.heat) ~= "number" then
				a.timer, add = rules.ammo_step(w.slot, a.timer, dt, rounds, a.start_rounds)
				if add > 0 then rec.bot:add_ammo(w.slot, nil, add) end
			end
		end
	end
end

function S:wants(item, bot)
	local near = nil
	local at = item.position
	if at then
		for _, unit in ipairs(self.api.bots.humans()) do
			local p = self.env.position(unit)
			if p then
				local dx, dy = p.x - at.x, p.y - at.y
				local d = math.sqrt(dx * dx + dy * dy)
				if not near or d < near then near = d end
			end
		end
	end
	return rules.wants_pickup(item, self:kit_state(bot), near)
end

-- A soldier died: forgotten, and the corpse sinks away after a few seconds. The game drops the support weapon
-- (CharacterStateDead), a moment after this call; this machine owns the soldier and so what falls, and
-- takes it away for every machine (the new pickups near the body in the next ticks) before anyone can use it.
function S:died(rec)
	if rec.dead then return end
	rec.dead = true
	local pos = rec.bot:position()
	self:forget(rec)
	rec.bot:remove({ decay = M.DECAY })
	if pos and self.api.world and self.api.world.pickups then
		self.corpses[#self.corpses + 1] = { x = pos.x, y = pos.y, z = pos.z, til = self.clock + M.CORPSE_WATCH, before = self.seen_pickups }
	end
end

-- What this machine sees lying about now, to tell a corpse's weapon from those that were there before.
function S:note_pickups()
	local world = self.api.world
	if not (world and world.pickups) then return end
	local seen = {}
	for _, p in ipairs(world.pickups(nil, nil, { "weapon_pickup" }) or {}) do seen[p.unit] = true end
	self.seen_pickups = seen
end

function S:clear_corpses()
	local world = self.api.world
	if #self.corpses == 0 or not (world and world.pickups and world.remove_pickup) then return end
	for i = #self.corpses, 1, -1 do
		local c = self.corpses[i]
		for _, p in ipairs(world.pickups(c, M.CORPSE_REACH, { "weapon_pickup" }) or {}) do
			if p.owned and not c.before[p.unit] then
				c.before[p.unit] = true
				local ok, why = world.remove_pickup(p.unit)
				if not ok then self:log("SEAF soldier's weapon not removed: " .. tostring(why)) end
			end
		end
		if self.clock >= c.til then table.remove(self.corpses, i) end
	end
end

function S:forget(rec)
	for i, r in ipairs(self.bots) do
		if r == rec then
			table.remove(self.bots, i)
			return
		end
	end
end

-- The use back to the thrower when no soldier could come. The cooldown keeps running.
function S:give_back(owner)
	local ok, why = self.api.stratagems.give(M.NAME, owner)
	if not ok then self:log("SEAF Unit: use not given back: " .. tostring(why)) end
end

-- From on_activate on the thrower's machine. pos: plain numbers { x, y, z }. Answers how many soldiers came.
function S:call_in(pos, upgrade, owner)
	if not self.api.game.in_mission() then return 0 end
	self:sync_mission()
	local mk = kit.mk(upgrade)
	local n = rules.fit(kit.count(mk), self.api.bots.free_pads(), self:squad_alive(), rules.SQUAD_CAP)
	local made = 0
	if n > 0 then
		local offsets = rules.offsets(n)
		local perks, weapons = self:choices()
		for i = 1, n do
			local k = kit.roll(mk, self.env.rng, perks, weapons)
			local at = { x = pos.x + offsets[i].x, y = pos.y + offsets[i].y, z = pos.z or 0 }
			if self:spawn(k, at, 1) then made = made + 1 end
		end
	end
	if made == 0 then
		self:log("SEAF Unit: no soldier could come (free pads " .. tostring(self.api.bots.free_pads()) .. ", squad " .. self:squad_alive() .. ")")
		self:give_back(owner)
	end
	return made
end

-- What this machine shares: the free pads, the soldiers alive, and a claim while it takes some over.
function S:state()
	local out = { seed = self.seed, free = self.api.bots.free_pads(), bots = {}, claim = self.claim }
	for _, rec in ipairs(self.bots) do
		local unit = not rec.dead and rec.bot:unit()
		local id = unit and self.env.goid(unit)
		if id then
			local hp = self.env.health(unit) or rec.hp or 1
			out.bots[#out.bots + 1] = { id = id, mk = rec.kit.mk, perk = kit.PERK_CODE[rec.kit.perk],
				weapon = rec.kit.weapon and self:weapon_id(rec.kit.weapon.name) or 0, hp = hp * 100 }
		end
	end
	return out
end

function S:share()
	local text, why = registry.encode(self:state())
	if not text then
		self:log("SEAF Unit: registry not shared: " .. tostring(why))
		return
	end
	self.api.lobby.share(M.SHARE, text)
end

-- The other machines' values, once a second, with where their soldiers stand.
function S:read()
	self.present = {}
	for _, p in ipairs(self.api.lobby.players() or {}) do self.present[p.peer] = true end
	local values = self.api.lobby.shared(M.SHARE) or {}
	for peer in pairs(self.peers) do
		if self.present[peer] and not values[peer] then self.peers[peer] = nil end
	end
	local me = self:me()
	for peer, text in pairs(values) do
		local state = registry.decode(text, self.seed)
		-- A value of another mission or a bad one counts as none.
		if not state then self.peers[peer] = nil end
		if state then
			self.peers[peer] = state
			local spots = self.positions[peer] or {}
			self.positions[peer] = spots
			for _, b in ipairs(state.bots) do
				local unit = self.env.unit_of(b.id)
				local p = unit and self.env.position(unit)
				if p then spots[b.id] = p end
			end
			-- Two machines took over the same soldiers: the lower peer keeps them.
			local c = state.claim
			if c and self.claim and c.peer == self.claim.peer and me and not heir.keeps({ peer, me }, me) then
				self:give_up(c.peer)
			end
		end
	end
end

function S:give_up(leaver)
	for _, rec in ipairs(self.inherited[leaver] or {}) do
		if not rec.dead then
			rec.dead = true
			self:forget(rec)
			rec.bot:remove()
		end
	end
	self.inherited[leaver] = nil
	if self.claim and self.claim.peer == leaver then self.claim, self.claim_until = nil, nil end
end

-- A player left: what they shared last, kept for the heir.
function S:on_leave(peer)
	if not self.api.game.in_mission() then return end
	self:sync_mission()
	local state = self.peers[peer]
	if not state then
		local text = self.api.lobby.last_shared and self.api.lobby.last_shared(M.SHARE, peer)
		state = text and registry.decode(text, self.seed)
	end
	self.peers[peer], self.present[peer] = nil, nil
	if state and #state.bots > 0 then
		self.pending[#self.pending + 1] = { leaver = peer, bots = state.bots, positions = self.positions[peer] or {},
			at = self.clock + M.HANDOVER_WAIT }
	end
	self.positions[peer] = nil
end

function S:take_over(p)
	local me = self:me()
	if not me then return end
	local candidates = { { peer = me, free = self.api.bots.free_pads() } }
	for peer, state in pairs(self.peers) do
		if self.present[peer] and peer ~= p.leaver then candidates[#candidates + 1] = { peer = peer, free = state.free } end
	end
	if heir.pick(p.leaver, candidates, #p.bots, self.seed) ~= me then return end
	self.claim = { peer = p.leaver, count = #p.bots }
	self:share()
	local perks, weapons = self:choices()
	local mine = self.inherited[p.leaver] or {}
	self.inherited[p.leaver] = mine
	local here = self.env.position(self.api.game.my_unit())
	for i, b in ipairs(p.bots) do
		local at = p.positions[b.id] or (here and { x = here.x + i * 2, y = here.y, z = here.z })
		if at and rules.fit(1, self.api.bots.free_pads(), self:squad_alive(), rules.SQUAD_CAP) > 0 then
			local k = kit.inherit(b.mk, kit.CODE_PERK[b.perk], self:weapon_name(b.weapon), self.env.rng, perks, weapons)
			local rec = self:spawn(k, at, math.max(0.01, (b.hp or 100) / 100))
			if rec then mine[#mine + 1] = rec end
		end
	end
	self.claim_until = self.clock + M.CLAIM_TIME
	self:log("SEAF Unit: took over " .. #mine .. " of " .. #p.bots .. " soldiers from a player who left")
end

-- About four times a second from main.lua's frame function.
function S:tick(dt)
	if not self.api.game.in_mission() then
		if #self.bots > 0 or self.mission then self.bots, self.mission, self.pending = {}, nil, {} end
		return
	end
	self:sync_mission()
	self.clock = self.clock + (tonumber(dt) or 0)
	self:clear_corpses()
	self:note_pickups()
	for i = #self.bots, 1, -1 do
		local rec = self.bots[i]
		-- The API drops a bot by itself: aboard the shuttle, or at the mission's end.
		if rec.bot.removed then
			table.remove(self.bots, i)
		else
			self:prepare(rec)
			kit.hide_cape(self.api, rec.bot:unit())
			self:recover_ammo(rec, tonumber(dt) or 0)
		end
	end
	self.wait = self.wait - (tonumber(dt) or 0)
	if self.wait <= 0 then
		self.wait = M.SHARE_EVERY
		self:read()
		if self.claim_until and self.clock >= self.claim_until then self.claim, self.claim_until = nil, nil end
		self:share()
		self:board()
	end
	for i = #self.pending, 1, -1 do
		local p = self.pending[i]
		if self.clock >= p.at then
			table.remove(self.pending, i)
			self:take_over(p)
		end
	end
end

-- Once a player is aboard the shuttle, every soldier boards too.
function S:board()
	if not self.api.bots.player_aboard() then return end
	for _, rec in ipairs(self.bots) do
		if rec.ready and not rec.boarding and not rec.dead then
			local ok = rec.bot:board(function(done) if not done then rec.boarding = false end end)
			if ok then rec.boarding = true end
		end
	end
end

-- The session stopped being cleared: every soldier sinks away, and the shared value empties.
function S:clear()
	for _, rec in ipairs(self.bots) do
		if not rec.dead then
			rec.dead = true
			pcall(rec.bot.remove, rec.bot, { decay = M.DECAY })
		end
	end
	self.bots, self.pending, self.inherited = {}, {}, {}
	self.claim, self.claim_until = nil, nil
	pcall(self.api.lobby.share, M.SHARE, nil)
end

return M
