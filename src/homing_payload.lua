-- Homing Payload: the entry for api.stratagems.define, and the barrage a landed beacon calls down. The
-- missiles are the ones Close Air Support fires, one after another, from high above the beacon. Pure
-- apart from the fire function handed to new(), so the tests run it as it is.
local M = {}

M.NAME = "stratagem_homing_payload"
M.TITLE = "Homing Payload"
-- The game's stratagem the new one is copied from, and what other players see on the wire: the red
-- strike beacon, with a call-in close to this one.
M.BASE = "stratagem_airstrike"
M.TYPE = "offensive"
-- Right, down, down, right, down: no game code starts with it, and it starts with none.
M.CODE = { "right", "down", "down", "right", "down" }
-- The Airstrike comes as a reward of planets of difficulty 3 to 6, which a player reaches around ranks
-- 5 to 10. Rank 7 sits in that range.
M.UNLOCK = { rank = 7 }
-- The name of the sub-material inside the icon material (tools/build_icon.py writes it), not the
-- texture's resource name. A gui asked for a sub-material the material lacks stops the game.
M.ICON = "homing_payload_icon"
M.ICON_MATERIAL = "more_stratagems/icons"
-- Seconds of cooldown, and seconds from call-in to the first missile. No uses field: unlimited.
M.COOLDOWN = 90
M.CALL_IN = 1.5
-- What the Loadout screen shows: the bars and tags, then the power at each Mk.
M.ATTRIBUTES = { attr_power = 3, attr_spec_anti_tank = true, attr_spec_explosive = true, attr_spec_homing = true }

-- The missile, by the name Obsidian API fires it under (api.world.PROJECTILES).
M.MISSILE = "air_support_missile"
-- Metres above the beacon each missile starts, and metres off the line straight up from the beacon. The
-- missile picks targets within 15 metres of itself, so it starts looking on the way down.
M.HEIGHT = 25
M.SPREAD = 2
-- Missiles per call and seconds between two, by Mk.
M.SALVOS = { { count = 5, gap = 0.5 }, { count = 6, gap = 0.4 }, { count = 7, gap = 0.3 } }

-- In the game's style: the upgrade texts replace this one in the menus, so each restates it with the
-- change worked in (internal/native-texts.md).
local function text(count, change)
	return "A fighter in orbit releases " .. count .. " homing missiles, one after another, straight down onto the beacon."
		.. (change and (" " .. change) or "")
		.. " Each missile turns toward the enemies around it as it falls and explodes on impact."
		.. " The missiles do NOT spare Helldivers caught in the blast."
end
M.DESCRIPTION = text("five")
M.UPGRADES = {
	{ title = "Homing Payload Mk2", description = text("six", "An improved release mechanism sends them down in quicker succession."),
		cost = 1, power = 4 },
	{ title = "Homing Payload Mk3", description = text("seven", "A further improved release mechanism sends them down in very quick succession."),
		cost = 2, power = 5 },
}

-- The lowest Obsidian API version the stratagem is defined on, and the lowest one that fires the
-- missiles (api.world.projectile, 1.43.0).
M.MIN_API = { 1, 43, 0 }
M.FIRE_API = { 1, 43, 0 }

-- The Mk of a call from the upgrade value the game hands on_activate: one bit per level bought
-- (LoadoutSettings.get_upgraded_stratagem), so 1 is Mk2, and 2 or 3 is Mk3.
function M.mk(upgrade)
	local n = math.floor(tonumber(upgrade) or 0)
	if n >= 2 then return 3 end
	if n == 1 then return 2 end
	return 1
end

-- How many missiles and how far apart, for a Mk.
function M.salvo(mk)
	local s = M.SALVOS[mk] or M.SALVOS[1]
	return s.count, s.gap
end

-- The seconds after the call-in at which each missile of a Mk goes.
function M.schedule(mk)
	local count, gap = M.salvo(mk)
	local out = {}
	for i = 1, count do out[i] = (i - 1) * gap end
	return out
end

-- Where missile i of count starts and where it flies, as plain numbers. Each starts SPREAD metres off the
-- line above the beacon, at an angle turned by the golden angle from the one before, and flies at the
-- beacon. The tilt is a few degrees: a missile flying exactly straight down has no forward to judge
-- "behind" by, and the game drops the targets behind a missile. Turning the start around the beacon
-- leaves no side out across a call.
local GOLDEN = math.pi * (3 - math.sqrt(5))
function M.shot(i, count, pos)
	local a = (i - 1) * GOLDEN
	local ox, oy = M.SPREAD * math.cos(a), M.SPREAD * math.sin(a)
	local length = math.sqrt(ox * ox + oy * oy + M.HEIGHT * M.HEIGHT)
	local start = { x = pos.x + ox, y = pos.y + oy, z = pos.z + M.HEIGHT }
	local direction = { x = -ox / length, y = -oy / length, z = -M.HEIGHT / length }
	return start, direction
end

-- The barrages in flight. fire(start, direction, owner) sends one missile and answers something, or nil
-- and a reason; log(text) says what went wrong.
local Barrage = {}
Barrage.__index = Barrage

function M.new(fire, log)
	return setmetatable({ fire = fire, log = log or function() end, jobs = {} }, Barrage)
end

-- A landed beacon: pos as plain numbers. The first missile goes at once, the rest by tick().
function Barrage:call(pos, upgrade, owner)
	local count, gap = M.salvo(M.mk(upgrade))
	self.jobs[#self.jobs + 1] = { x = pos.x, y = pos.y, z = pos.z or 0, owner = owner, count = count, gap = gap, fired = 0, wait = 0 }
	self:tick(0)
end

-- dt: seconds since the last tick. A missile that can't be fired ends the barrage: the next would fail
-- the same way.
function Barrage:tick(dt)
	for i = #self.jobs, 1, -1 do
		local job = self.jobs[i]
		job.wait = job.wait - (tonumber(dt) or 0)
		while job.fired < job.count and job.wait <= 0 do
			job.fired = job.fired + 1
			local start, direction = M.shot(job.fired, job.count, job)
			local ok, sent, why = pcall(self.fire, start, direction, job.owner)
			if not (ok and sent) then
				self.log("Homing Payload: missile " .. job.fired .. " of " .. job.count .. " not fired: " .. tostring(ok and why or sent))
				job.fired = job.count
			end
			job.wait = job.wait + job.gap
		end
		if job.fired >= job.count then table.remove(self.jobs, i) end
	end
end

-- Drops every missile still to come: a mission that ends, or a lobby that stops being cleared.
function Barrage:clear()
	self.jobs = {}
end

function Barrage:idle()
	return #self.jobs == 0
end

-- call_in(pos, upgrade, owner): what a landed beacon does, with pos as plain numbers. nil when the
-- missiles can't be fired (an Obsidian API older than FIRE_API): refused(owner) runs instead. Either way,
-- no airstrike.
function M.def(call_in, refused)
	local upgrades = {}
	for i, u in ipairs(M.UPGRADES) do
		upgrades[i] = { title = u.title, description = u.description, cost = u.cost, upgrade_attributes = { attr_power = u.power } }
	end
	local attributes = {}
	for k, v in pairs(M.ATTRIBUTES) do attributes[k] = v end
	return {
		name = M.NAME,
		base = M.BASE,
		title = M.TITLE,
		description = M.DESCRIPTION,
		type = M.TYPE,
		code = { unpack(M.CODE) },
		unlock = M.UNLOCK,
		icon = M.ICON,
		icon_material = M.ICON_MATERIAL,
		attributes = attributes,
		stats = { cooldown_time = M.COOLDOWN, activation_time = M.CALL_IN },
		upgrades = upgrades,
		-- The position is the game's vector, good for this frame only: copied to plain numbers.
		on_activate = function(ctx)
			local p = ctx.position
			local ok, err = pcall(function()
				if call_in then
					call_in({ x = p.x, y = p.y, z = p.z }, ctx.upgrade, ctx.owner)
				elseif refused then
					refused(ctx.owner)
				end
			end)
			if not ok and obsidian and obsidian.log then obsidian.log("Homing Payload: " .. tostring(err)) end
			return false
		end,
	}
end

return M
