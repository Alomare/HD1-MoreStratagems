-- More Stratagems: new stratagems for HELLDIVERS (2015).
local seaf_unit = obsidian.module("src/seaf_unit")
local seaf_squad = obsidian.module("src/seaf_squad")

local api = obsidian.import("obsidian.api")
local api_info = obsidian.info and obsidian.info("obsidian.api")

-- The white and blue armour. The mod runs on without it: soldiers then wear the vanilla mix.
local look_ok, seaf_look = pcall(obsidian.module, "src/seaf_look")
if look_ok and type(seaf_look) == "table" and seaf_look.start then
	local started, why = pcall(seaf_look.start)
	if not started then obsidian.log("SEAF look not started: " .. tostring(why)) end
else
	seaf_look = nil
end

-- Soldiers need Obsidian API 1.42.0. With an older one the stratagem is still defined, so a saved loadout
-- keeps it, and a call gives the use back and says why in the log.
local bots_ready = api_info ~= nil and seaf_unit.at_least(api_info.version, seaf_unit.BOTS_API)
local squad = bots_ready and seaf_squad.new(api, { look = seaf_look }) or nil

local function refused(owner)
	obsidian.log("SEAF Unit: soldiers need Obsidian API " .. table.concat(seaf_unit.BOTS_API, ".") .. " or later; the use is given back")
	pcall(api.stratagems.give, seaf_unit.NAME, owner)
end

local function call_in(pos, upgrade, owner)
	return squad:call_in(pos, upgrade, owner)
end

-- In the main chunk, before the save's loadout is read: a saved loadout naming a stratagem the game
-- doesn't have yet gets the default in the slot. Obsidian API 1.20.0 and later keep it until the game
-- has the stratagem list; an older one answers not_ready, and the mod tries again every frame until
-- it doesn't. true stops the frame calls.
local function define()
	if api_info and not seaf_unit.at_least(api_info.version, seaf_unit.MIN_API) then
		obsidian.log("SEAF Unit not added: needs Obsidian API " .. table.concat(seaf_unit.MIN_API, ".") .. " or later")
		return true
	end
	local made, why = api.stratagems.define(seaf_unit.def(squad and call_in or nil, refused))
	if why == "not_ready" then return false end
	if not made and why ~= "taken" then obsidian.log("SEAF Unit not added: " .. tostring(why)) end
	return true
end
if not define() then obsidian.on_frame(define) end

if squad then
	local wait = 0
	obsidian.on_frame(function()
		local dt = rawget(_G, "ENGINE_DT") or 0.016
		wait = wait - dt
		if wait > 0 then return end
		local step = 0.25 - wait
		wait = 0.25
		local ok, err = pcall(squad.tick, squad, step)
		if not ok then obsidian.log("SEAF Unit: " .. tostring(err)) end
	end)
	-- A lobby that stops being cleared: the soldiers sink away rather than stand frozen.
	obsidian.on_session(function(on)
		if not on then
			local ok, err = pcall(squad.clear, squad)
			if not ok then obsidian.log("SEAF Unit: " .. tostring(err)) end
		end
	end)
else
	obsidian.log("SEAF Unit: Obsidian API " .. tostring(api_info and api_info.version) .. " is older than " .. table.concat(seaf_unit.BOTS_API, ".") .. "; soldiers can't come")
end

obsidian.log("More Stratagems ready")
