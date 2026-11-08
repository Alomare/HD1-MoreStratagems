-- The rules SEAF soldiers follow, as plain decisions. Pure.
local M = {}

-- SEAF soldiers alive in the squad at most, all machines together.
M.SQUAD_CAP = 8
-- Metres a player has to keep from a weapon on the ground for a soldier to take it.
M.PLAYER_CLEAR = 6

-- How many soldiers a call can bring: what it asks for, no more than the free pads of this machine and the
-- room left under the squad cap.
function M.fit(want, free_pads, squad_alive, cap)
	local room = (tonumber(cap) or M.SQUAD_CAP) - (tonumber(squad_alive) or 0)
	local n = math.min(tonumber(want) or 0, tonumber(free_pads) or 0, room)
	return math.max(0, math.floor(n))
end

local function flat_distance(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Whom a soldier follows: the player of the machine that owns it while that player lives, else the
-- nearest living player, else nobody. owner: { unit, x, y } or nil; humans: a list of { unit, x, y };
-- here: { x, y }, where the soldier stands. Answers a unit or nil.
function M.follow_target(owner, humans, here)
	if owner and owner.unit ~= nil then return owner.unit end
	local best, best_d = nil, math.huge
	for _, h in ipairs(humans or {}) do
		local d = here and flat_distance(h, here) or 0
		if d < best_d then best, best_d = h.unit, d end
	end
	return best
end

-- Whether a soldier takes a thing lying about. item.kind: the kind api.bots.usables gives. state: what the
-- soldier has, { ammo_low, support_empty, support_one_use }. player_near: metres from the item to the
-- nearest living player, nil with none.
--   Research samples: always; they count for the whole squad.
--   Ammo boxes: when a weapon runs under half of the magazines it holds, as the game hands out a box only then.
--   Weapons (one-use launchers among them): only with no player within 6 metres of the item, and only
--   into an empty support slot or one holding a spent one-use launcher, so nothing a player walks to
--   is taken and no weapon is dropped for it.
function M.wants_pickup(item, state, player_near)
	local kind = type(item) == "table" and item.kind
	state = state or {}
	if kind == "research_sample_pickup" then return true end
	if kind == "ammo_pickup" then return state.ammo_low == true end
	if kind == "weapon_pickup" then
		if player_near ~= nil and player_near <= M.PLAYER_CLEAR then return false end
		return state.support_empty == true or state.support_one_use == true
	end
	return false
end

-- Where n soldiers land around the beacon, as offsets { x, y } 3 metres apart, so their hellpods don't
-- come down on one spot.
function M.offsets(n)
	local out = {}
	n = math.max(0, math.floor(tonumber(n) or 0))
	if n == 1 then return { { x = 0, y = 0 } } end
	local radius = n > 1 and 1.5 / math.sin(math.pi / n) or 0
	for i = 1, n do
		local a = (i - 1) * 2 * math.pi / n
		out[i] = { x = radius * math.cos(a), y = radius * math.sin(a) }
	end
	return out
end

return M
