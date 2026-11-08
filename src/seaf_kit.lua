-- What a SEAF soldier carries, by Mk. Pure: no game calls, so the tests run it as it is.
--   Mk1: the Liberator and the default pistol, no perk.
--   Mk2: the same, one perk at random (Displacement Field or Heavy Armor) and one support weapon at random.
--   Mk3: two soldiers per call, each with a Mk2 kit rolled separately.
local M = {}

M.PRIMARY = "equipment/wep_assaultrifle_01"
M.SIDEARM = "equipment/wep_pistol_01"
-- perk_teleport_shield is the perk the game calls Displacement Field: the perk's setup enables the teleport
-- shield (perk_settings.lua).
M.PERKS = { "perk_teleport_shield", "perk_heavy_armor" }
M.PERK_CODE = { perk_teleport_shield = "t", perk_heavy_armor = "h" }
M.CODE_PERK = { t = "perk_teleport_shield", h = "perk_heavy_armor" }
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
-- Each one stands in for the other when only one is usable.
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
