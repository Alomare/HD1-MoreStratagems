-- Who takes over the SEAF soldiers of a player who left. Every machine works it out from the same shared
-- values, so they agree with no message between them. Pure.
local M = {}

-- A small string hash, the same on every machine.
function M.hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
	return h
end

-- The heir of `leaver`: candidates are { peer, free } for every machine still in the lobby that runs the
-- mod in this mission, this one included. Machines whose free pads cover `need` come first; with none, all
-- of them. Sorted by peer, then one picked by a hash of the leaver and the seed. nil with no candidate.
function M.pick(leaver, candidates, need, seed)
	local fits, all = {}, {}
	for _, c in ipairs(candidates or {}) do
		if c.peer ~= nil and c.peer ~= leaver then
			all[#all + 1] = c
			if (tonumber(c.free) or 0) >= (tonumber(need) or 0) then fits[#fits + 1] = c end
		end
	end
	local list = #fits > 0 and fits or all
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return tostring(a.peer) < tostring(b.peer) end)
	local i = M.hash(tostring(leaver) .. ":" .. tostring(seed or 0)) % #list + 1
	return list[i].peer
end

-- With several machines claiming the soldiers of one leaver (their lists disagreed), the lowest peer keeps
-- them. claimants: the peers claiming, this one among them. Answers true when `me` keeps the soldiers it has.
function M.keeps(claimants, me)
	for _, peer in ipairs(claimants or {}) do
		if tostring(peer) < tostring(me) then return false end
	end
	return true
end

return M
