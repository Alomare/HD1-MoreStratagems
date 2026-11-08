-- The text each machine running the mod shares in a mission: the machine's free pads, the SEAF soldiers it drives and, while
-- it takes over the soldiers of a player who left, that claim. Pure.
--
--   1|<mission seed>|<free pads>|<bot>,<bot>,...|<claim>
--   bot   = <game object id>.<mk>.<perk>.<weapon>.<health>
--           mk 1 to 3; perk t (Displacement Field), h (Heavy Armor) or - (none); weapon the stratagem id of
--           the support weapon in LoadoutSettings, 0 for none; health 0 to 100, the share left
--   claim = <peer who left>:<count>, empty when there is none
--
-- The lobby keeps member data after a mission, so the seed in the text keeps a value from an earlier
-- mission from being read. Game object ids are the same on every machine.
local M = {}

M.VERSION = "1"
M.MAX = 200

local PERK = { t = true, h = true }

-- The text for a state { seed, free, bots = { { id, mk, perk, weapon, hp } }, claim = { peer, count } },
-- or nil and "too_long" past the 200 characters the lobby takes.
function M.encode(state)
	local bots = {}
	for _, b in ipairs(state.bots or {}) do
		local perk = PERK[b.perk] and b.perk or "-"
		local hp = math.max(0, math.min(100, math.floor((tonumber(b.hp) or 100) + 0.5)))
		bots[#bots + 1] = string.format("%d.%d.%s.%d.%d", math.floor(tonumber(b.id) or 0), math.max(1, math.min(3, math.floor(tonumber(b.mk) or 1))),
			perk, math.max(0, math.floor(tonumber(b.weapon) or 0)), hp)
	end
	local claim = ""
	if type(state.claim) == "table" and state.claim.peer ~= nil then
		claim = tostring(state.claim.peer):gsub("[^%w_]", "") .. ":" .. math.max(0, math.floor(tonumber(state.claim.count) or 0))
	end
	local text = table.concat({ M.VERSION, tostring(state.seed or 0), tostring(math.max(0, math.floor(tonumber(state.free) or 0))),
		table.concat(bots, ","), claim }, "|")
	if #text > M.MAX then return nil, "too_long" end
	return text
end

-- The state in a text, or nil for a text of another mission, another version or a bad one.
function M.decode(text, seed)
	if type(text) ~= "string" then return nil end
	local version, their_seed, free, list, claim = text:match("^(%d+)|([^|]*)|(%d+)|([^|]*)|([^|]*)$")
	if version ~= M.VERSION or their_seed ~= tostring(seed or 0) then return nil end
	local state = { seed = seed, free = tonumber(free), bots = {} }
	for entry in list:gmatch("[^,]+") do
		local id, mk, perk, weapon, hp = entry:match("^(%d+)%.([123])%.([th%-])%.(%d+)%.(%d+)$")
		if not id then return nil end
		state.bots[#state.bots + 1] = { id = tonumber(id), mk = tonumber(mk), perk = perk ~= "-" and perk or nil,
			weapon = tonumber(weapon), hp = math.min(100, tonumber(hp)) }
	end
	if claim ~= "" then
		local peer, count = claim:match("^([%w_]+):(%d+)$")
		if not peer then return nil end
		state.claim = { peer = peer, count = tonumber(count) }
	end
	return state
end

return M
