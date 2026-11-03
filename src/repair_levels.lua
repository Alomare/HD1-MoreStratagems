-- The A/AC-90 Repair Tower at each Mk, by the stratagem's upgrade level: 0 is Mk1. The level travels
-- to the tower as its unit's upgrade_value, which every machine reads to set the unit up from the Tesla
-- Tower's settings. That unit has two upgrades, so a level past 2 would find no settings on any machine:
-- the tower stops at Mk3.
local M = {}

M.NAME = "remixed_repair_tower"
M.BASE = "stratagem_tesla_tower"

-- Seconds between heals. The REP-80 heals once a second; half a second keeps the beams' work steady.
M.TICK = 0.5

-- range: metres from the tower's root. beams: targets healed at once. helldiver, machine: hitpoints a
-- second for a Helldiver, and for a vehicle or turret. revive: downed targets count too (a Helldiver
-- bleeding out, a vehicle burning before it blows up).
M.LEVELS = {
	[0] = { mk = 1, range = 8, beams = 1, helldiver = 10, machine = 50, revive = false },
	[1] = { mk = 2, range = 12, beams = 3, helldiver = 10, machine = 50, revive = false },
	[2] = { mk = 3, range = 12, beams = 3, helldiver = 20, machine = 100, revive = true },
}
M.MAX = 2

-- The level for an upgrade value, clamped, and the clamped value.
function M.of(upgrade)
	local n = math.floor(tonumber(upgrade) or 0)
	if n ~= n or n < 0 then n = 0 elseif n > M.MAX then n = M.MAX end
	return M.LEVELS[n], n
end

-- Hitpoints in one heal. The game's heal request carries an int16, so a whole number.
function M.amount(level, kind)
	local rate = kind == "helldiver" and level.helldiver or level.machine
	return math.max(1, math.floor(rate * M.TICK + 0.5))
end

return M
