-- What a SEAF soldier carries, by Mk. Pure: no game calls, so the tests run it as it is.
--   Mk1: the game's default loadout: the Liberator, the default pistol and the default perk.
--   Mk2: the same, one perk at random (Displacement Field, Heavy Armor, Laser Aim Module, Stun Grenades or
--        Smoke Grenades) and one support weapon at random.
--   Mk3: two soldiers per call, each with a Mk2 kit rolled separately.
-- On a snow mission every soldier also wears the All Terrain Boots perk, at every Mk (M.equip).
local M = {}

-- What the game's default loadout gives (LoadoutSettings.default_loadout), which every soldier lands with.
M.PRIMARY = "equipment/wep_assaultrifle_01"
M.SIDEARM = "equipment/wep_pistol_01"
-- The perks a Mk2 soldier picks from, by the game's names (LoadoutSettings.perks):
--   perk_teleport_shield   Displacement Field: the perk's setup enables the teleport shield (perk_settings.lua).
--   perk_heavy_armor       Heavy Armor: armour and the armour piece.
--   perk_lasersight        Laser Aim Module: the game's default perk, so every soldier already lands with it.
--                          The perk has no master setup: only a beam drawn from the weapon, with no effect on
--                          the soldier's aim. The API refuses to hand it out in a lobby with other players
--                          ("alone_only"), which leaves the default one in place.
--   perk_grenade_stun      Stun Grenades, and
--   perk_grenade_smoke     Smoke Grenades: the perks only change the type of the two grenades every Helldiver
--                          lands with (InventoryComponent "set_grenade_path"). A soldier throws one only when
--                          something calls bot:throw_at.
M.PERKS = { "perk_teleport_shield", "perk_heavy_armor", "perk_lasersight", "perk_grenade_stun", "perk_grenade_smoke" }
M.PERK_CODE = { perk_teleport_shield = "t", perk_heavy_armor = "h", perk_lasersight = "l", perk_grenade_stun = "s", perk_grenade_smoke = "m" }
M.CODE_PERK = { t = "perk_teleport_shield", h = "perk_heavy_armor", l = "perk_lasersight", s = "perk_grenade_stun", m = "perk_grenade_smoke" }
-- The perks that give a soldier grenades of another type.
M.GRENADE_PERKS = { perk_grenade_stun = true, perk_grenade_smoke = true }
-- The perk every soldier gets on snow, on top of the one above (a paid perk: a player without the pack gets none).
M.BOOTS = "perk_all_terrain_boots"
-- Support weapons a bot gets no use from: the REP-80 heals and does nothing to enemies.
M.NOT_FOR_BOTS = { stratagem_repairtool = true }

-- The Mk of a call from the upgrade level the game hands on_activate: 0 for Mk1, 1 for Mk2, 2 for Mk3.
function M.mk(upgrade)
	local n = math.floor(tonumber(upgrade) or 0)
	if n < 0 then n = 0 end
	if n > 2 then n = 2 end
	return n + 1
end

-- Soldiers per call.
function M.count(mk)
	return (tonumber(mk) or 1) >= 3 and 2 or 1
end

-- The perks of M.PERKS the player can use, in that order. usable(name) answers true for one they can.
-- The others stand in for one that is not usable.
function M.perks(usable)
	local out = {}
	for _, name in ipairs(M.PERKS) do
		if usable == nil or usable(name) then out[#out + 1] = name end
	end
	return out
end

-- The support weapons a bot can use, from api.catalog.support_weapons() ({ name, unit_path } each, the
-- weapons that need a backpack or a second player already left out there).
function M.weapons(list)
	local out = {}
	for _, w in ipairs(list or {}) do
		if type(w) == "table" and type(w.name) == "string" and type(w.unit_path) == "string" and not M.NOT_FOR_BOTS[w.name] then
			out[#out + 1] = w
		end
	end
	return out
end

-- Whether a mission is on a snow planet, from the game's state (api.game.state()): the generated level names
-- the planet type. Anything unreadable counts as no.
function M.snow(state)
	local ok, snow = pcall(function()
		local level = type(state) == "table" and state.generated_level
		return type(level) == "table" and level.environment_name == "snow"
	end)
	return ok and snow == true
end

-- The perks a soldier gets on top of the kit: the boots on snow, when the player can use them.
-- usable(name) answers true for a perk the player can use, nil for any.
function M.extras(snow, usable)
	local out = {}
	if snow and (usable == nil or usable(M.BOOTS)) then out[#out + 1] = M.BOOTS end
	return out
end

-- Gives a soldier's body the extra perks (api.gear.add_perk, which runs the perk's setup on the body). Reads the
-- biome and the player's ownership defensively: whatever fails leaves the soldier without them. Answers the
-- perk names added.
function M.equip(api, unit)
	local added = {}
	pcall(function()
		if not (type(api) == "table" and unit and api.gear and api.gear.add_perk) then return end
		local snow = api.game and api.game.state and M.snow(api.game.state())
		local usable = api.catalog and api.catalog.usable
		for _, name in ipairs(M.extras(snow, usable)) do
			if api.gear.add_perk(name, unit) == true then added[#added + 1] = name end
		end
	end)
	return added
end

-- One soldier's kit: { mk, perk, weapon }. perk is a perk name or nil, weapon an entry of `weapons` or nil.
-- rng(n) answers a whole number from 1 to n; the same rng answers give the same kit.
function M.roll(mk, rng, perks, weapons)
	local kit = { mk = mk }
	if mk >= 2 then
		if perks and #perks > 0 then kit.perk = perks[rng(#perks)] end
		if weapons and #weapons > 0 then kit.weapon = weapons[rng(#weapons)] end
	end
	return kit
end

-- The kit a soldier of another machine had, on this machine: the same perk and weapon where this player
-- can use them, else one rolled from what this player can use. weapon_name: a stratagem name or nil.
function M.inherit(mk, perk, weapon_name, rng, perks, weapons)
	local kit = { mk = mk }
	if mk < 2 then return kit end
	for _, p in ipairs(perks or {}) do
		if p == perk then kit.perk = p end
	end
	if not kit.perk and perks and #perks > 0 then kit.perk = perks[rng(#perks)] end
	for _, w in ipairs(weapons or {}) do
		if w.name == weapon_name then kit.weapon = w end
	end
	if not kit.weapon and weapon_name and weapons and #weapons > 0 then kit.weapon = weapons[rng(#weapons)] end
	return kit
end

return M
