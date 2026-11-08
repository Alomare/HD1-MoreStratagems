-- The pure parts of the SEAF Unit: kits, the shared registry, the heir and the rules.
local kit = obsidian.module("src/seaf_kit")
local registry = obsidian.module("src/seaf_registry")
local heir = obsidian.module("src/seaf_heir")
local rules = obsidian.module("src/seaf_rules")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local WEAPONS = { { name = "stratagem_machinegun", unit_path = "equipment/wep_mg" }, { name = "stratagem_flamethrower", unit_path = "equipment/wep_flame" } }

local function seq(...)
	local list, i = { ... }, 0
	return function(n)
		i = i + 1
		local v = list[(i - 1) % #list + 1]
		assert(v >= 1 and v <= n, "rng answer in range")
		return v
	end
end

test("kit_counts_and_mk_from_the_upgrade_level", function()
	eq(kit.mk(0), 1) eq(kit.mk(1), 2) eq(kit.mk(2), 3) eq(kit.mk(7), 3, "no Mk4") eq(kit.mk(nil), 1) eq(kit.mk(-1), 1)
	eq(kit.count(1), 1) eq(kit.count(2), 1) eq(kit.count(3), 2)
end)

test("kit_roll_is_a_function_of_the_rng", function()
	local perks = kit.perks()
	eq(#perks, 5)
	local a = kit.roll(2, seq(2, 1), perks, WEAPONS)
	local b = kit.roll(2, seq(2, 1), perks, WEAPONS)
	eq(a.perk, "perk_heavy_armor") eq(a.weapon.name, "stratagem_machinegun")
	eq(b.perk, a.perk) eq(b.weapon, a.weapon, "the same answers, the same kit")
	local one = kit.roll(1, seq(1), perks, WEAPONS)
	eq(one.perk, nil, "Mk1 carries no perk") eq(one.weapon, nil, "and no support weapon")
	eq(kit.roll(3, seq(1, 2), perks, WEAPONS).weapon.name, "stratagem_flamethrower", "Mk3 rolls a Mk2 kit")
end)

test("a_perk_the_player_cant_use_falls_back_to_the_others", function()
	local perks = kit.perks(function(name) return name ~= "perk_teleport_shield" end)
	eq(#perks, 4) eq(perks[1], "perk_heavy_armor")
	eq(kit.roll(2, seq(1), perks, WEAPONS).perk, "perk_heavy_armor")
	local only = kit.perks(function(name) return name == "perk_heavy_armor" end)
	eq(#only, 1) eq(kit.roll(2, seq(1), only, WEAPONS).perk, "perk_heavy_armor")
	eq(#kit.perks(function() return false end), 0)
	eq(kit.roll(2, seq(1), {}, WEAPONS).perk, nil, "none usable, none carried")
end)

test("bots_get_no_repair_tool_and_an_inherited_kit_keeps_what_it_can", function()
	local list = kit.weapons({ WEAPONS[1], { name = "stratagem_repairtool", unit_path = "equipment/wep_repairtool_01" }, { name = 5 } })
	eq(#list, 1) eq(list[1].name, "stratagem_machinegun")
	local k = kit.inherit(2, "perk_teleport_shield", "stratagem_flamethrower", seq(1), kit.perks(), WEAPONS)
	eq(k.perk, "perk_teleport_shield") eq(k.weapon.name, "stratagem_flamethrower")
	local swapped = kit.inherit(2, "perk_teleport_shield", "stratagem_dlc_gun", seq(1, 2), { "perk_heavy_armor" }, WEAPONS)
	eq(swapped.perk, "perk_heavy_armor", "a perk this player can't use is swapped")
	eq(swapped.weapon.name, "stratagem_flamethrower", "and so is a weapon this player doesn't own")
	eq(kit.inherit(2, nil, nil, seq(1), kit.perks(), WEAPONS).weapon, nil, "no weapon stays none")
	eq(kit.inherit(1, "perk_heavy_armor", "stratagem_machinegun", seq(1), kit.perks(), WEAPONS).perk, nil, "Mk1 keeps nothing")
end)

test("the_mk2_pool_holds_the_five_perks_by_their_game_names_and_each_has_a_registry_code", function()
	local want = { "perk_teleport_shield", "perk_heavy_armor", "perk_lasersight", "perk_grenade_stun", "perk_grenade_smoke" }
	eq(#kit.PERKS, #want)
	for i, name in ipairs(want) do
		eq(kit.PERKS[i], name)
		eq(kit.CODE_PERK[kit.PERK_CODE[name]], name, "a code and back")
		eq(kit.perks()[i], name)
	end
	for i = 1, 5 do eq(kit.roll(2, seq(i, 1), kit.perks(), WEAPONS).perk, want[i], "each one can be rolled") end
	eq(kit.roll(1, seq(3), kit.perks(), WEAPONS).perk, nil, "Mk1 rolls none")
	yes(kit.GRENADE_PERKS.perk_grenade_stun and kit.GRENADE_PERKS.perk_grenade_smoke and not kit.GRENADE_PERKS.perk_lasersight)
	for _, name in ipairs(want) do
		local text = registry.encode({ seed = 5, free = 1, bots = { { id = 7, mk = 2, perk = kit.PERK_CODE[name], weapon = 0, hp = 100 } } })
		eq(registry.decode(text, 5).bots[1].perk, kit.PERK_CODE[name], name .. " survives the shared text")
		eq(kit.inherit(2, name, nil, seq(1), kit.perks(), WEAPONS).perk, name, name .. " is inherited")
	end
end)

test("snow_is_read_from_the_generated_level_and_never_throws", function()
	yes(kit.snow({ generated_level = { environment_name = "snow" } }))
	for _, level in ipairs({ "desert", "forest", "lava", "city", "provinggrounds" }) do
		yes(not kit.snow({ generated_level = { environment_name = level } }), level)
	end
	yes(not kit.snow(nil)) yes(not kit.snow({})) yes(not kit.snow("snow")) yes(not kit.snow({ generated_level = "snow" }))
	local bad = setmetatable({}, { __index = function() error("no level yet") end })
	yes(not kit.snow(bad), "an unreadable state counts as no snow")
end)

test("the_boots_are_an_extra_perk_on_snow_only_and_only_when_usable", function()
	eq(#kit.extras(false), 0) eq(#kit.extras(nil), 0)
	local on = kit.extras(true)
	eq(#on, 1) eq(on[1], "perk_all_terrain_boots")
	eq(#kit.extras(true, function() return true end), 1)
	eq(#kit.extras(true, function(name) return name ~= "perk_all_terrain_boots" end), 0, "a paid perk the player lacks")
	yes(not kit.PERK_CODE.perk_all_terrain_boots, "the boots are not a kit perk")
	local given = {}
	local api = { game = { state = function() return { generated_level = { environment_name = "snow" } } end },
		catalog = { usable = function() return true end },
		gear = { add_perk = function(name, unit) given[#given + 1] = { name, unit } return true end } }
	eq(#kit.equip(api, "body"), 1) eq(given[1][1], "perk_all_terrain_boots") eq(given[1][2], "body")
	eq(#kit.equip(api, nil), 0, "no body, no call")
	eq(#kit.equip(nil, "body"), 0)
end)

test("registry_round_trip", function()
	local text = registry.encode({ seed = 77, free = 2, bots = { { id = 301, mk = 2, perk = "t", weapon = 14, hp = 80.4 }, { id = 302, mk = 1, hp = 100 } } })
	eq(text, "1|77|2|301.2.t.14.80,302.1.-.0.100|")
	local s = registry.decode(text, 77)
	eq(s.free, 2) eq(#s.bots, 2)
	eq(s.bots[1].id, 301) eq(s.bots[1].mk, 2) eq(s.bots[1].perk, "t") eq(s.bots[1].weapon, 14) eq(s.bots[1].hp, 80)
	eq(s.bots[2].perk, nil) eq(s.bots[2].weapon, 0)
	eq(s.claim, nil)
	local claimed = registry.decode(registry.encode({ seed = 77, free = 0, bots = {}, claim = { peer = "abc123", count = 3 } }), 77)
	eq(claimed.claim.peer, "abc123") eq(claimed.claim.count, 3) eq(#claimed.bots, 0)
end)

test("a_registry_of_another_mission_or_bad_text_is_not_read", function()
	local text = registry.encode({ seed = 77, free = 1, bots = { { id = 1, mk = 1, hp = 50 } } })
	eq(registry.decode(text, 78), nil, "another seed")
	for _, bad in ipairs({ "", "junk", "2|77|1||", "1|77|1|1.4.-.0.50|", "1|77|1|x|", "1|77|1||peer", nil, 5 }) do
		eq(registry.decode(bad, 77), nil, "bad text " .. tostring(bad))
	end
end)

test("eight_bots_and_a_claim_fit_the_lobby_limit", function()
	local bots = {}
	for i = 1, 8 do bots[i] = { id = 65000 + i, mk = 3, perk = "h", weapon = 999, hp = 100 } end
	local text = registry.encode({ seed = 4294967295, free = 4, bots = bots, claim = { peer = "76561198000000000", count = 8 } })
	yes(text, "encoded")
	yes(#text <= 200, "under 200: " .. #text)
	local many = {}
	for i = 1, 20 do many[i] = { id = 65000 + i, mk = 3, perk = "h", weapon = 999, hp = 100 } end
	local none, why = registry.encode({ seed = 1, free = 1, bots = many })
	eq(none, nil) eq(why, "too_long")
end)

test("every_machine_picks_the_same_heir_from_shuffled_lists", function()
	local list = { { peer = "p3", free = 4 }, { peer = "p1", free = 4 }, { peer = "p2", free = 4 } }
	local shuffled = { list[2], list[3], list[1] }
	for seed = 1, 30 do
		eq(heir.pick("leaver", list, 1, seed), heir.pick("leaver", shuffled, 1, seed), "seed " .. seed)
	end
	local seen = {}
	for seed = 1, 60 do seen[heir.pick("leaver", list, 1, seed)] = true end
	yes(seen.p1 and seen.p2 and seen.p3, "spread over the machines")
	eq(heir.hash("abc"), heir.hash("abc"))
end)

test("the_heir_prefers_free_pads_and_never_is_the_leaver", function()
	local list = { { peer = "a", free = 0 }, { peer = "b", free = 3 }, { peer = "c", free = 1 } }
	for seed = 1, 20 do eq(heir.pick("x", list, 2, seed), "b", "only b has room for two") end
	local none = { { peer = "a", free = 0 }, { peer = "c", free = 1 } }
	for seed = 1, 20 do yes(heir.pick("x", none, 2, seed), "with no room anywhere, all count") end
	eq(heir.pick("x", {}, 1, 1), nil, "no candidates")
	eq(heir.pick("x", { { peer = "x", free = 4 } }, 1, 1), nil, "the leaver is no heir")
end)

test("a_claim_conflict_goes_to_the_lower_peer", function()
	eq(heir.keeps({ "b", "a" }, "a"), true)
	eq(heir.keeps({ "b", "a" }, "b"), false)
	eq(heir.keeps({ "a" }, "a"), true)
end)

test("fit_keeps_to_the_pads_and_the_squad_cap", function()
	eq(rules.fit(2, 4, 0, 8), 2)
	eq(rules.fit(2, 1, 0, 8), 1, "one pad")
	eq(rules.fit(2, 0, 0, 8), 0, "no pad")
	eq(rules.fit(2, 4, 7, 8), 1, "one place left in the squad")
	eq(rules.fit(1, 4, 8, 8), 0, "squad full")
	eq(rules.fit(1, 4, 9, 8), 0, "never below 0")
end)

test("a_soldier_follows_the_owner_else_the_nearest_player", function()
	local owner = { unit = "me" }
	local humans = { { unit = "far", x = 30, y = 0 }, { unit = "near", x = 3, y = 0 } }
	eq(rules.follow_target(owner, humans, { x = 0, y = 0 }), "me")
	eq(rules.follow_target(nil, humans, { x = 0, y = 0 }), "near")
	eq(rules.follow_target(nil, {}, { x = 0, y = 0 }), nil)
end)

test("what_a_soldier_picks_up", function()
	local sample, ammo, gun = { kind = "research_sample_pickup" }, { kind = "ammo_pickup" }, { kind = "weapon_pickup" }
	eq(rules.wants_pickup(sample, {}, 1), true, "samples always, a player near or not")
	eq(rules.wants_pickup(ammo, { ammo_low = true }, 1), true)
	eq(rules.wants_pickup(ammo, { ammo_low = false }, nil), false, "the game gives no box to full magazines")
	eq(rules.wants_pickup(gun, { support_empty = true }, 10), true)
	eq(rules.wants_pickup(gun, { support_empty = true }, 6), false, "a player within 6 metres")
	eq(rules.wants_pickup(gun, { support_empty = true }, nil), true, "no player at all")
	eq(rules.wants_pickup(gun, { support_empty = false }, 20), false, "a weapon in hand is never dropped for one")
	eq(rules.wants_pickup({ kind = "objective_carry_object" }, {}, nil), false)
	eq(rules.wants_pickup({ kind = "backpack_pickup" }, { support_empty = true }, nil), false)
end)

test("landing_spots_dont_overlap", function()
	eq(#rules.offsets(0), 0)
	local one = rules.offsets(1)
	eq(one[1].x, 0) eq(one[1].y, 0)
	for n = 2, 4 do
		local spots = rules.offsets(n)
		eq(#spots, n)
		for i = 1, n do
			for j = i + 1, n do
				local dx, dy = spots[i].x - spots[j].x, spots[i].y - spots[j].y
				yes(math.sqrt(dx * dx + dy * dy) >= 2.99, n .. " spots apart")
			end
		end
	end
end)

return T
