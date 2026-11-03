-- The runtime against a fake game: one fake per machine (tests/fake.lua).
local F = dofile("tests/fake.lua")
local runtime = obsidian.module("src/repair_runtime")
local levels = obsidian.module("src/repair_levels")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

F.globals()

-- A machine, its runtime, and a setup that goes through the hook the way the loader runs it.
local function machine(peer)
	local m = F.new(peer)
	local rt = runtime.new(m.api)
	m.rt = rt
	m.hooked = function(comp, u, ctx, spawn) return rt:setup_master(F.tesla.setup_master, comp, u, ctx, spawn) end
	m.frame = function() rt:frame() end
	return m
end

local function spawn(level, name)
	return { owner_unit = "thrower", upgrade_value = level, stratagem_info = { name = name or levels.NAME } }
end

local function healed(m, unit)
	local total, n = 0, 0
	for _, h in ipairs(m.heals) do
		if h.unit == unit then total, n = total + h.amount, n + 1 end
	end
	return total, n
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

test("the_repair_tower_never_fires_and_a_tesla_tower_still_does", function()
	local m = machine()
	local diver = m:helldiver({ x = 3, y = 0, z = 0 }, 60)
	m:enemy({ x = -3, y = 0, z = 0 })
	local repair = m:tower({ x = 0, y = 0, z = 0 }, spawn(2), nil, m.hooked)
	eq(m.masters.tesla[repair].state.active, false, "switched off in setup_master")
	m:run(30, m.frame)
	eq(#m.shots, 0, "no shot from the Repair Tower in 30 seconds")
	yes(diver.health.hitpoints > 60, "and it healed")
	-- The control: the game's own Tesla Tower, through the same hook, fires once it's up.
	local control = machine()
	control:enemy({ x = 3, y = 0, z = 0 })
	local tesla = control:tower({ x = 0, y = 0, z = 0 }, spawn(0, "stratagem_tesla_tower"), nil, control.hooked)
	eq(control.masters.tesla[tesla].state.active, true, "a Tesla Tower stays on")
	control:run(10, control.frame)
	yes(#control.shots > 0, "the Tesla Tower fired")
	eq(count(control.rt.towers), 0, "and isn't taken for a Repair Tower")
end)

test("the_tower_is_quiet_without_the_closing_command", function()
	local m = machine()
	m:helldiver({ x = 2, y = 0, z = 0 }, 50)
	local repair = m:tower({ x = 0, y = 0, z = 0 }, spawn(0), nil, m.hooked)
	m:run(20, m.frame)
	for _, cmd in ipairs(m.commands) do
		yes(cmd.comp ~= "tesla", "a tesla command: " .. tostring(cmd.cmd))
		eq(cmd.cmd, "do_heal", "only heals are sent")
	end
	local state = m.masters.tesla[repair].state
	eq(state.time_to_die, nil, "not closing")
end)

test("a_tower_switched_on_again_is_off_by_the_next_frame", function()
	local m = machine()
	m:enemy({ x = 2, y = 0, z = 0 })
	local repair = m:tower({ x = 0, y = 0, z = 0 }, spawn(1), nil, m.hooked)
	m:run(8, m.frame)
	-- As a takeover does: setup_master again, with nothing from the hellpod.
	local ctx = m.masters.tesla[repair]
	m.hooked(F.tesla, repair, ctx, nil)
	eq(ctx.state.active, false, "the hook knows the tower")
	-- And if something sets it outside the hook, the frame puts it back before the tower can look around.
	ctx.state.active = true
	m:step(0.05, m.frame)
	eq(ctx.state.active, false, "off again after one frame")
	m:run(10, m.frame)
	eq(#m.shots, 0)
end)

test("heals_wait_for_the_tower_to_rise_then_tick_at_the_mk_rate", function()
	local m = machine()
	local diver = m:helldiver({ x = 4, y = 0, z = 0 }, 10)
	m:tower({ x = 0, y = 0, z = 0 }, spawn(0), nil, m.hooked)
	m:run(5, m.frame)
	eq(#m.heals, 0, "nothing while the tower rises out of the hellpod")
	m:run(5, m.frame)
	local total, n = healed(m, diver)
	yes(n >= 9 and n <= 11, "a heal every half second, got " .. n)
	for _, h in ipairs(m.heals) do eq(h.amount, 5, "Mk1: 10 a second") eq(h.how, "command", "this machine's Helldiver") end
	yes(total >= 45 and total <= 55, "about 50 in 5 seconds, got " .. total)
	m:run(10, m.frame)
	eq(diver.health.hitpoints, 100, "up to full")
	local _, after = healed(m, diver)
	m:run(5, m.frame)
	eq(select(2, healed(m, diver)), after, "nothing more once full")
end)

test("other_players_and_vehicles_get_the_game_s_heal_request", function()
	local m = machine()
	local mate = m:helldiver({ x = 3, y = 0, z = 0 }, 40, "peer2")
	local mech = m:vehicle({ x = -5, y = 0, z = 0 }, 300, "peer3")
	m:tower({ x = 0, y = 0, z = 0 }, spawn(1), nil, m.hooked)
	m:run(7, m.frame)
	local to_mate, to_mech = 0, 0
	for _, r in ipairs(m.rpcs) do
		eq(r.name, "rpc_heal_request")
		if r.unit == mate then to_mate = to_mate + 1 eq(r.peer, "peer2") eq(r.amount, 5) end
		if r.unit == mech then to_mech = to_mech + 1 eq(r.peer, "peer3") eq(r.amount, 25) end
	end
	yes(to_mate > 0, "the teammate") yes(to_mech > 0, "the mech")
end)

test("beams_follow_the_mk_count_and_go_when_they_have_no_target", function()
	local m = machine()
	local a = m:helldiver({ x = 2, y = 0, z = 0 }, 30)
	local b = m:helldiver({ x = 3, y = 0, z = 0 }, 50)
	local c = m:helldiver({ x = 0, y = 4, z = 0 }, 70)
	m:helldiver({ x = 0, y = 5, z = 0 }, 100)
	local repair = m:tower({ x = 0, y = 0, z = 0 }, spawn(1), nil, m.hooked)
	m:run(5.5, m.frame)
	eq(F.live(m.world), 3, "Mk2: three beams, none to the healthy one")
	local beams = m.rt.towers[repair].beams
	yes(beams[a] and beams[b] and beams[c], "one to each hurt Helldiver")
	-- Each beam runs from the coil to the target's spine.
	local p = m.world.particles[beams[a]]
	local from, to = p.vars["effects/generated/wep_rep_01_beam#start"], p.vars["effects/generated/wep_rep_01_beam#end"]
	eq(from.z, 3, "the muzzle (1 m) and the lightning's offset (2 m)") eq(to.x, 2) eq(to.z, 1.2, "the healing node")
	eq(p.vars["effects/generated/wep_rep_01_beam#size"].x, 1)
	m:kill(a)
	m:step(0.05, m.frame)
	eq(F.live(m.world), 2, "a dead target's beam goes at once")
	m:run(20, m.frame)
	eq(F.live(m.world), 0, "all full: no beams")
	eq(m.world.created, m.world.destroyed, "every beam made was destroyed")
end)

test("mk1_has_one_beam_and_a_short_reach", function()
	local m = machine()
	m:helldiver({ x = 2, y = 0, z = 0 }, 30)
	m:helldiver({ x = 3, y = 0, z = 0 }, 50)
	local far = m:helldiver({ x = 10, y = 0, z = 0 }, 20)
	m:tower({ x = 0, y = 0, z = 0 }, spawn(0), nil, m.hooked)
	m:run(6, m.frame)
	eq(F.live(m.world), 1, "one beam")
	eq(select(2, healed(m, far)), 0, "10 m is out of Mk1's reach")
	local m2 = machine()
	local far2 = m2:helldiver({ x = 10, y = 0, z = 0 }, 20)
	m2:tower({ x = 0, y = 0, z = 0 }, spawn(1), nil, m2.hooked)
	m2:run(6, m2.frame)
	yes(select(2, healed(m2, far2)) > 0, "Mk2 reaches 10 m")
end)

test("only_mk3_gets_a_downed_helldiver_back_up", function()
	for level = 0, 2 do
		local m = machine()
		local downed = m:helldiver({ x = 3, y = 0, z = 0 }, -30)
		m:tower({ x = 0, y = 0, z = 0 }, spawn(level), nil, m.hooked)
		m:run(8, m.frame)
		if level < 2 then
			eq(#m.heals, 0, "Mk" .. (level + 1) .. " leaves a downed Helldiver")
			eq(F.live(m.world), 0, "with no beam")
		else
			yes(downed.health.hitpoints > 0, "Mk3 got the Helldiver up, at " .. downed.health.hitpoints)
			eq(m.heals[1].amount, 10, "Mk3: 20 a second")
		end
	end
end)

test("machines_heal_at_their_own_rate_and_enemies_never", function()
	local m = machine()
	local mech = m:vehicle({ x = 5, y = 0, z = 0 }, 500)
	local enemy = m:enemy({ x = 2, y = 0, z = 0 })
	enemy.health.hitpoints = 10
	m:tower({ x = 0, y = 0, z = 0 }, spawn(2), nil, m.hooked)
	m:run(7.2, m.frame)
	local total, n = healed(m, mech)
	yes(n > 0, "the mech") eq(total, n * 50, "Mk3: 100 a second for a vehicle")
	eq(select(2, healed(m, enemy)), 0, "no enemy")
end)

test("a_paused_game_heals_nothing", function()
	local m = machine()
	m:helldiver({ x = 3, y = 0, z = 0 }, 10)
	m:tower({ x = 0, y = 0, z = 0 }, spawn(0), nil, m.hooked)
	m:run(6, m.frame)
	local before = #m.heals
	m.paused = true
	m:run(10, m.frame)
	eq(#m.heals, before, "the tower's clock stood still")
	m.paused = false
	m:run(2, m.frame)
	yes(#m.heals > before, "and runs again")
end)

test("other_machines_learn_the_tower_draw_its_beams_and_leave_the_heals_to_the_owner", function()
	local owner, other = machine("me"), machine("peer2")
	local repair = owner:tower({ x = 0, y = 0, z = 0 }, spawn(1), nil, owner.hooked)
	owner:helldiver({ x = 3, y = 0, z = 0 }, 50)
	owner:run(1.5, owner.frame)
	local text = owner.shared_out.towers
	eq(text, owner.goids[repair] .. ":1", "the owner shares the tower and its level")
	-- The same tower and Helldiver as the other machine sees them.
	local copy = other:tower({ x = 0, y = 0, z = 0 }, nil, "me", other.hooked)
	other.goids[copy] = owner.goids[repair]
	other:helldiver({ x = 3, y = 0, z = 0 }, 50, "me")
	other:run(1.5, other.frame)
	eq(count(other.rt.towers), 0, "nothing shared yet: a plain Tesla Tower")
	other.shared_in.towers = { me = text }
	other:run(6, other.frame)
	eq(other.rt.towers[copy].level, 1, "learned with its level")
	eq(F.live(other.world), 1, "draws the beam")
	eq(#other.heals + #other.rpcs, 0, "and heals nothing: the owner does")
	eq(other.shared_out.towers, "", "and shares no tower of its own")
end)

test("a_machine_that_takes_a_known_tower_over_keeps_it_quiet_and_healing", function()
	local m = machine("peer2")
	local diver = m:helldiver({ x = 3, y = 0, z = 0 }, 40)
	-- The tower another machine threw, learned from its share.
	local repair = m:tower({ x = 0, y = 0, z = 0 }, nil, "me", m.hooked)
	m.shared_in.towers = { me = m.goids[repair] .. ":2" }
	m:run(1.5, m.frame)
	yes(m.rt.towers[repair], "learned")
	-- That machine leaves; this one takes the tower over and sets it up afresh, with no hellpod data.
	m.shared_in.towers = {}
	repair.owner = "peer2"
	local ctx = { state = {} }
	m.masters.tesla[repair] = ctx
	m.masters.time_to_live[repair] = { state = { time_until_dead = 100 } }
	m.hooked(F.tesla, repair, ctx, nil)
	eq(ctx.state.active, false)
	m:run(12, m.frame)
	eq(#m.shots, 0, "no shot after the takeover")
	yes(diver.health.hitpoints > 40, "healing again")
	eq(m.shared_out.towers, m.goids[repair] .. ":2", "and shares it now")
end)

test("towers_and_beams_go_with_the_mission", function()
	local m = machine()
	m:helldiver({ x = 3, y = 0, z = 0 }, 40)
	local repair = m:tower({ x = 0, y = 0, z = 0 }, spawn(0), nil, m.hooked)
	m:run(6, m.frame)
	eq(F.live(m.world), 1)
	m:kill(repair)
	m:step(0.05, m.frame)
	eq(F.live(m.world), 0, "a destroyed tower takes its beams")
	eq(count(m.rt.towers), 0)
	-- A lobby that stops being cleared: beams off, the tower kept.
	local repair2 = m:tower({ x = 0, y = 0, z = 0 }, spawn(0), nil, m.hooked)
	m:run(6, m.frame)
	eq(F.live(m.world), 1)
	m.rt:clear_all_beams()
	eq(F.live(m.world), 0, "beams off")
	yes(m.rt.towers[repair2], "the tower kept")
	-- Leaving the mission: the world is gone, so nothing is destroyed in it.
	m:step(0.05, m.frame)
	m.in_mission = false
	local destroyed = m.world.destroyed
	m.rt:clear_all_beams()
	m:step(0.05, m.frame)
	eq(m.world.destroyed, destroyed, "no call into a gone world")
	eq(count(m.rt.towers), 0, "forgotten")
end)

test("a_closing_or_destroyed_tower_stops", function()
	local m = machine()
	local diver = m:helldiver({ x = 3, y = 0, z = 0 }, 10)
	local repair = m:tower({ x = 0, y = 0, z = 0 }, spawn(0), nil, m.hooked)
	m:run(6, m.frame)
	m.slaves.tesla[repair].state.time_to_die = true
	m:step(0.05, m.frame)
	eq(F.live(m.world), 0, "closing: no beam")
	local hp = diver.health.hitpoints
	m:run(5, m.frame)
	eq(diver.health.hitpoints, hp, "and no heal")
	m.slaves.tesla[repair].state.time_to_die = nil
	repair.health.is_dead = true
	m:run(5, m.frame)
	eq(diver.health.hitpoints, hp, "destroyed: no heal")
end)

return T
