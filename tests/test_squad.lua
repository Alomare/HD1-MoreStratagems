-- The SEAF squad on fake machines that share a lobby (tests/fake.lua).
local F = dofile("tests/fake.lua")
local squad_mod = obsidian.module("src/seaf_squad")
local registry = obsidian.module("src/seaf_registry")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function squad_on(m, env)
	local e = {}
	for k, v in pairs(m.env) do e[k] = v end
	for k, v in pairs(env or {}) do e[k] = v end
	return squad_mod.new(m.api, e)
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

test("a_mk3_call_brings_two_soldiers_with_a_mk2_kit_and_their_orders", function()
	local net = F.net()
	local m = F.machine(net, "a")
	local s = squad_on(m)
	eq(s:call_in({ x = 10, y = 10, z = 1 }, 2, m.avatar), 2)
	eq(#m.bots, 2)
	local a, b = m.bots[1], m.bots[2]
	for _, bot in ipairs(m.bots) do
		eq(bot.opts.guest, true, "a guest") eq(bot.opts.bare, true) eq(bot.opts.require_pad, true)
		eq(bot.opts.loadout, "default", "the Liberator and the pistol of the game's default loadout")
		eq(bot.gear.primary_weapon, nil, "nothing given over them, so nothing dropped")
		eq(bot.gear.sidearm_weapon, nil)
		yes(bot.gear.perk == "perk_teleport_shield" or bot.gear.perk == "perk_heavy_armor", "a perk")
		yes(bot.gear.support_weapon == "equipment/wep_mg" or bot.gear.support_weapon == "equipment/wep_flame", "a support weapon, never the REP-80")
		eq(bot.orders.fight[1], 25) eq(bot.orders.fight[2].weapon, "best", "the weapon for each target")
		eq(type(bot.orders.follow[1]), "function") eq(bot.orders.follow[2], 6)
		eq(bot.orders.ride_along[1], true) eq(bot.orders.auto_revive[1], 15)
		eq(bot.orders.avoid_shots[2].melee, true, "close attacks too")
		eq(bot.orders.auto_pickup[1].radius, 12)
		eq(bot.look.helmet, 4) eq(bot.look.body, 4) eq(bot.look.cape, 12) eq(bot.look.gender, 1)
		eq(bot.look.color.x, 2, "the blue outline")
	end
	local dx = a.body.pos.x - b.body.pos.x
	yes(math.abs(dx) >= 2.9, "apart")
	eq(a.body.pos.z, 1)
	eq(m.given, 0)
	F.run(net, { a = s }, 1)
	local st = registry.decode(net.shared.a.seaf, net.seed)
	eq(#st.bots, 2) eq(st.bots[1].mk, 3) eq(st.free, 2)
end)

test("a_mk1_soldier_has_the_default_kit_and_follows_the_owner_else_the_nearest_player", function()
	local net = F.net()
	local m = F.machine(net, "a", { pos = { x = 0, y = 0 } })
	local other = F.machine(net, "b", { pos = { x = 50, y = 0 } })
	local s = squad_on(m)
	eq(s:call_in({ x = 40, y = 0, z = 0 }, 0, m.avatar), 1)
	local bot = m.bots[1]
	eq(bot.gear.perk, nil, "the default perk kept") eq(bot.gear.support_weapon, nil, "no support weapon")
	local follow = bot.orders.follow[1]
	eq(follow(bot), m.avatar, "the owner, even with another player nearer")
	m.avatar.dead = true
	eq(follow(bot), other.avatar, "the owner dead: the nearest player")
	other.avatar.dead = true
	eq(follow(bot), nil, "nobody left")
end)

test("the_custom_look_is_used_only_when_the_look_module_picks_it", function()
	local net = F.net()
	local m = F.machine(net, "a")
	local asked = nil
	local look = { pick = function(members) asked = members return { helmet = 25, body = 23, cape = 42 } end }
	local s = squad_on(m, { look = look, members = function() return { "everyone" } end })
	s:call_in({ x = 0, y = 0, z = 0 }, 0, m.avatar)
	eq(m.bots[1].look.helmet, 25) eq(m.bots[1].look.cape, 42)
	eq(asked[1], "everyone", "asked with the lobby members")
	local broken = squad_on(F.machine(F.net(), "z"), { look = { pick = function() error("no") end } })
	broken:call_in({ x = 0, y = 0, z = 0 }, 0, nil)
	eq(broken.api.bots.free_pads(), 3, "a look that fails still brings the soldier")
	-- A look the game refuses: the soldier comes in the default armour.
	local m2 = F.machine(F.net(), "c")
	m2.refuse_look = true
	eq(squad_on(m2):call_in({ x = 0, y = 0, z = 0 }, 0, m2.avatar), 1)
	eq(m2.bots[1].look, nil)
end)

test("a_call_with_no_room_gives_the_use_back", function()
	local net = F.net()
	local m = F.machine(net, "a", { pads = 1 })
	local s = squad_on(m)
	eq(s:call_in({ x = 0, y = 0, z = 0 }, 2, m.avatar), 1, "Mk3 with one pad: one soldier")
	eq(m.given, 0)
	eq(s:call_in({ x = 0, y = 0, z = 0 }, 2, m.avatar), 0, "no pad left")
	eq(m.given, 1, "the use back")
	eq(m.given_to[1], "stratagem_seaf_unit") eq(m.given_to[2], m.avatar)
	-- The squad cap counts every machine's soldiers.
	local net2 = F.net()
	local mine = F.machine(net2, "a")
	local full = F.machine(net2, "b")
	local bots = {}
	for i = 1, 8 do bots[i] = { id = 900 + i, mk = 1, hp = 100 } end
	net2.shared.b.seaf = registry.encode({ seed = net2.seed, free = 0, bots = bots })
	local s2 = squad_on(mine)
	F.run(net2, { a = s2 }, 1)
	eq(s2:call_in({ x = 0, y = 0, z = 0 }, 0, mine.avatar), 0, "eight alive already")
	eq(mine.given, 1)
	-- A value from another mission isn't counted.
	net2.shared.b.seaf = registry.encode({ seed = 1, free = 0, bots = bots })
	F.run(net2, { a = s2 }, 1)
	eq(s2:call_in({ x = 0, y = 0, z = 0 }, 0, mine.avatar), 1)
	eq(full.peer, "b")
end)

test("a_dead_soldier_is_forgotten_and_its_corpse_decays", function()
	local net = F.net()
	local m = F.machine(net, "a")
	local s = squad_on(m)
	s:call_in({ x = 0, y = 0, z = 0 }, 2, m.avatar)
	local first, second = m.bots[1], m.bots[2]
	first.body.dead = true
	F.run(net, { a = s }, 1.5)
	eq(first.removed, true) eq(first.decay, 5, "the corpse stays 5 seconds")
	eq(second.removed, nil)
	eq(#s.bots, 1)
	eq(#registry.decode(net.shared.a.seaf, net.seed).bots, 1, "the registry lists the living one")
	eq(m.given, 0, "a death gives nothing back")
end)

test("soldiers_board_only_after_a_player_and_leave_with_the_session", function()
	local net = F.net()
	local m = F.machine(net, "a")
	local s = squad_on(m)
	s:call_in({ x = 0, y = 0, z = 0 }, 2, m.avatar)
	F.run(net, { a = s }, 2)
	eq(m.bots[1].boarding, nil, "nobody aboard yet")
	net.aboard = true
	F.run(net, { a = s }, 1.5)
	yes(m.bots[1].boarding and m.bots[2].boarding, "both board")
	local kept = { m.bots[1], m.bots[2] }
	s:clear()
	eq(kept[1].removed, true) eq(kept[1].decay, 5) eq(kept[2].decay, 5)
	eq(net.shared.a.seaf, nil, "the shared value empties")
	eq(#s.bots, 0)
end)

-- Three machines: a calls soldiers and leaves; b and c pick the same heir.
local function three(seed, a_pos)
	local net = F.net(seed)
	local a = F.machine(net, "a")
	local b = F.machine(net, "b")
	local c = F.machine(net, "c")
	local squads = { a = squad_on(a), b = squad_on(b), c = squad_on(c) }
	squads.a:call_in(a_pos or { x = 30, y = 5, z = 0 }, 1, a.avatar)
	F.run(net, squads, 2)
	return net, squads, a, b, c
end

test("a_leavers_soldiers_come_back_once_on_exactly_one_machine", function()
	for seed = 1, 12 do
		local net, squads, a = three(seed)
		local old = a.bots[1]
		local mk, perk, weapon = 2, old.gear.perk, old.gear.support_weapon
		old.body.pos = { x = 33, y = 7, z = 0 }
		F.run(net, squads, 1)
		F.leave(net, "a")
		squads.a = nil
		F.run(net, squads, 1)
		eq(#net.machines.b.bots + #net.machines.c.bots, 0, "the heir waits for the lobby to settle")
		F.run(net, squads, 3)
		local nb, nc = #net.machines.b.bots, #net.machines.c.bots
		eq(nb + nc, 1, "seed " .. seed .. ": once, on one machine")
		local new = (nb == 1 and net.machines.b or net.machines.c).bots[1]
		eq(new.gear.perk, perk, "the same perk")
		eq(new.gear.support_weapon, weapon, "the same weapon")
		eq(new.body.pos.x, 33, "where the old one stood") eq(new.body.pos.y, 7)
		F.run(net, squads, 6)
		eq(#net.machines.b.bots + #net.machines.c.bots, 1, "and no more later")
		local heir_peer = nb == 1 and "b" or "c"
		local st = registry.decode(net.shared[heir_peer].seaf, net.seed)
		eq(#st.bots, 1) eq(st.bots[1].mk, mk) eq(st.claim, nil, "the claim cleared")
	end
end)

test("health_carries_over_and_a_leaver_with_no_soldiers_changes_nothing", function()
	local net, squads, a, b, c = three(3)
	a.bots[1].body.hp = 0.4
	F.run(net, squads, 1.5)
	F.leave(net, "a")
	squads.a = nil
	F.run(net, squads, 4)
	local new = (#b.bots == 1 and b or c).bots[1]
	eq(new.body.hp, 0.4)
	-- c leaves: b ends with the one soldier, whether c had it or not, and never two.
	F.leave(net, "c")
	squads.c = nil
	F.run(net, squads, 4)
	eq(#b.bots, 1)
end)

test("the_heir_needs_a_free_pad_and_loses_what_doesnt_fit", function()
	local net = F.net(5)
	local a = F.machine(net, "a")
	local b = F.machine(net, "b", { pads = 0 })
	local squads = { a = squad_on(a), b = squad_on(b) }
	squads.a:call_in({ x = 0, y = 0, z = 0 }, 2, a.avatar)
	F.run(net, squads, 2)
	F.leave(net, "a")
	squads.a = nil
	F.run(net, squads, 4)
	eq(#b.bots, 0, "lost rather than standing still")
	yes(b.logs[#b.logs]:find("took over 0 of 2", 1, true), "said in the log")
end)

test("two_machines_that_both_took_over_end_with_one_set", function()
	-- c can't read b's value, so both b and c may see themselves as heir: find a seed where both do.
	for seed = 1, 40 do
		local net = F.net(seed)
		local a = F.machine(net, "a")
		local b = F.machine(net, "b")
		local c = F.machine(net, "c")
		c.blind.b = true
		local squads = { a = squad_on(a), b = squad_on(b), c = squad_on(c) }
		squads.a:call_in({ x = 0, y = 0, z = 0 }, 1, a.avatar)
		F.run(net, squads, 2)
		F.leave(net, "a")
		squads.a = nil
		F.run(net, squads, 2.25)
		if #b.bots == 1 and #c.bots == 1 then
			c.blind.b = nil
			F.run(net, squads, 3)
			eq(#b.bots, 1, "b, the lower peer, keeps them")
			eq(#c.bots, 0, "c gives them up")
			return
		end
	end
	error("no seed gave a conflict")
end)

test("a_registry_counts_only_the_peers_still_here", function()
	local net = F.net()
	local a = F.machine(net, "a")
	F.machine(net, "b")
	local s = squad_on(a)
	net.shared.b.seaf = registry.encode({ seed = net.seed, free = 2, bots = { { id = 5, mk = 1, hp = 100 } } })
	F.run(net, { a = s }, 1)
	eq(s:squad_alive(), 1)
	F.leave(net, "b")
	eq(s:squad_alive(), 0)
	eq(count(s.pending), 1, "the soldier of b waits for the heir")
end)

return T
