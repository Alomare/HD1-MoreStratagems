-- The towers a machine owns, as the text it shares with the lobby: "<game object id>:<level>", comma
-- separated. Game object ids are the same on every machine, so the others can find each tower's unit and
-- draw its beams, and whoever takes a tower over when its owner leaves knows to keep it quiet. The lobby
-- takes up to 200 characters.
local M = {}

M.MAX = 200

-- list: { { id = n, level = n }, ... }. Sorted, so the same towers give the same text.
function M.encode(list)
	local sorted = {}
	for i, e in ipairs(list) do sorted[i] = e end
	table.sort(sorted, function(a, b) return a.id < b.id end)
	local parts, size = {}, 0
	for _, e in ipairs(sorted) do
		local part = string.format("%d:%d", e.id, e.level)
		local add = #part + (#parts > 0 and 1 or 0)
		if size + add > M.MAX then break end
		parts[#parts + 1] = part
		size = size + add
	end
	return table.concat(parts, ",")
end

-- Whatever another machine shared: entries that don't read as an id and a level are skipped.
function M.decode(text)
	local out = {}
	if type(text) ~= "string" then return out end
	for id, level in text:gmatch("(%d+):(%d+)") do
		out[#out + 1] = { id = tonumber(id), level = tonumber(level) }
	end
	return out
end

return M
