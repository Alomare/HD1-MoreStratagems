-- Which units a Repair Tower heals: plain data in, a list out, so every machine that draws the beams
-- picks the same targets from the same replicated health, and the tower's owner heals those.
--
-- A candidate: { unit, kind = "helldiver" | "machine", x, y, z, hp, max, floor, dead }. hp is the
-- replicated hitpoints, max the maximum, floor the health component's constitution (negative: a unit at
-- or under it is dead, one between it and 0 is downed).
local M = {}

-- "dead", "downed", "hurt" or "full".
function M.condition(c)
	if c.dead or c.hp <= c.floor then return "dead" end
	if c.hp <= 0 then return "downed" end
	if c.hp < c.max then return "hurt" end
	return "full"
end

-- Whether a tower at this level heals the candidate at all.
function M.wants(c, level)
	local cond = M.condition(c)
	return cond == "hurt" or (cond == "downed" and level.revive)
end

local function distance2(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return dx * dx + dy * dy + dz * dz
end

-- The candidates the tower heals now, at most level.beams of them: downed first, then the lowest share of
-- health, then the nearest. tower: { unit, x, y, z }. The tower never heals itself.
function M.pick(tower, candidates, level)
	local range2 = level.range * level.range
	local chosen = {}
	for i, c in ipairs(candidates) do
		if c.unit ~= tower.unit and c.max > 0 and M.wants(c, level) then
			local d2 = distance2(tower, c)
			if d2 <= range2 then
				chosen[#chosen + 1] = { c = c, d2 = d2, i = i, downed = c.hp <= 0, share = c.hp / c.max }
			end
		end
	end
	table.sort(chosen, function(a, b)
		if a.downed ~= b.downed then return a.downed end
		if a.share ~= b.share then return a.share < b.share end
		if a.d2 ~= b.d2 then return a.d2 < b.d2 end
		return a.i < b.i
	end)
	local out = {}
	for i = 1, math.min(level.beams, #chosen) do out[i] = chosen[i].c end
	return out
end

return M
