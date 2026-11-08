-- More Stratagems: new stratagems for HELLDIVERS (2015).
local seaf_unit = obsidian.module("src/seaf_unit")
local seaf_squad = obsidian.module("src/seaf_squad")
local homing = obsidian.module("src/homing_payload")

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

-- Homing Payload. The missiles need Obsidian API 1.44.0 (a target for api.world.projectile). With an older one the
-- stratagem is still defined, so a saved loadout keeps it, and a call gives the use back and says why.
local fire_ready = api_info ~= nil and seaf_unit.at_least(api_info.version, homing.FIRE_API)
local barrage = fire_ready and homing.new(function(start, direction, owner, target)
	return api.world.projectile(homing.MISSILE, start, { direction = direction, owner = owner or false, target = target })
end, obsidian.log, function(pos)
	return api.enemies.near(homing.REACH, api.game.global("Vector3")(pos.x, pos.y, pos.z))
end) or nil

local function homing_refused(owner)
	obsidian.log("Homing Payload: the missiles need Obsidian API " .. table.concat(homing.FIRE_API, ".") .. " or later; the use is given back")
	pcall(api.stratagems.give, homing.NAME, owner)
end

local function homing_call(pos, upgrade, owner)
	return barrage:call(pos, upgrade, owner)
end

local function define_homing()
	if api_info and not seaf_unit.at_least(api_info.version, homing.MIN_API) then
		obsidian.log("Homing Payload not added: needs Obsidian API " .. table.concat(homing.MIN_API, ".") .. " or later")
		return true
	end
	local made, why = api.stratagems.define(homing.def(barrage and homing_call or nil, homing_refused))
	if why == "not_ready" then return false end
	if not made and why ~= "taken" then obsidian.log("Homing Payload not added: " .. tostring(why)) end
	return true
end
if not define_homing() then obsidian.on_frame(define_homing) end

if barrage then
	-- The missiles still to come, spaced by game time. Outside a mission there is nothing to fire at.
	obsidian.on_frame(function()
		if barrage:idle() then return end
		if not api.game.in_mission() then
			barrage:clear()
			return
		end
		local dt = rawget(_G, "GAME_DT") or rawget(_G, "ENGINE_DT") or 0.016
		local ok, err = pcall(barrage.tick, barrage, dt)
		if not ok then
			obsidian.log("Homing Payload: " .. tostring(err))
			barrage:clear()
		end
	end)
	obsidian.on_session(function(on)
		if not on then barrage:clear() end
	end)
else
	obsidian.log("Homing Payload: Obsidian API " .. tostring(api_info and api_info.version) .. " is older than " .. table.concat(homing.FIRE_API, ".") .. "; the missiles can't come")
end

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

-- The A/MG-15 Perforator Turret: settings variants of the Railcannon Turret on every machine, and the
-- thrower's hellpod handing the turret an upgrade value that picks them (src/perforator_turret).
local perforator = obsidian.module("src/perforator_turret")
local perforator_ready = api_info ~= nil and perforator.at_least(api_info.version, perforator.MIN_API)

local function define_perforator()
	local made, why = api.stratagems.define(perforator.def())
	if why == "not_ready" then return false end
	if not made and why ~= "taken" then obsidian.log("Perforator Turret not added: " .. tostring(why)) end
	return true
end

if perforator_ready then
	if not define_perforator() then obsidian.on_frame(define_perforator) end
	local Unit = function() return rawget(_G, "Unit") end
	local turrets = perforator.runtime({
		global = function(name) return rawget(_G, name) end,
		log = obsidian.log,
		original = api.edits and api.edits.original,
		unit_path = function(unit) return Unit().get_data(unit, "unit_path") end,
		alive = function(unit) return Unit().alive(unit) end,
	})
	obsidian.hook("HellpodComponent", "setup_master", function(original, component, unit, ctx, setup, ...)
		turrets:hellpod(setup)
		return original(component, unit, ctx, setup, ...)
	end)
	obsidian.hook("TurretComponent", "setup_master", function(original, component, unit, ctx, ...)
		original(component, unit, ctx, ...)
		turrets:watch(component, unit, ctx, false)
	end)
	obsidian.hook("TurretComponent", "setup_slave", function(original, component, unit, ctx, ...)
		original(component, unit, ctx, ...)
		turrets:watch(component, unit, ctx, true)
	end)
	obsidian.hook("TurretComponent", "reload_slave", function(original, component, unit, ctx, ...)
		original(component, unit, ctx, ...)
		turrets:reloaded(unit, ctx)
	end)
	obsidian.on_frame(function()
		turrets:frame(rawget(_G, "ENGINE_DT") or 0.016)
	end)
	obsidian.on_session(function(on)
		if not on then
			local ok, err = pcall(turrets.uninstall, turrets)
			if not ok then obsidian.log("Perforator Turret: " .. tostring(err)) end
		end
	end)
else
	obsidian.log("Perforator Turret not added: needs Obsidian API " .. table.concat(perforator.MIN_API, ".") .. " or later")
end

obsidian.log("More Stratagems ready")
