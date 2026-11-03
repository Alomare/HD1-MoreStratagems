-- Remixed Stratagems: custom stratagems made from the game's own units and effects.
local repair_tower = obsidian.module("src/repair_tower")
local repair_runtime = obsidian.module("src/repair_runtime")

local api = obsidian.import("obsidian.api")
local api_info = obsidian.info and obsidian.info("obsidian.api")

-- In the main chunk, before the save's loadout is read: a saved loadout naming a stratagem the game
-- doesn't have yet gets the default in its place. Obsidian API 1.20.0 and later keep it until the game
-- has its stratagem list; an older one answers not_ready, and the mod tries again every frame until
-- it doesn't. true stops the frame calls.
local function define()
	local made, why = api.stratagems.define(repair_tower.def(api_info and api_info.version))
	if why == "not_ready" then return false end
	if not made and why ~= "taken" then obsidian.log("A/AC-90 Repair Tower not added: " .. tostring(why)) end
	return true
end
if not define() then obsidian.on_frame(define) end

local tower = repair_runtime.new(api)
obsidian.hook("TeslaComponent", "setup_master", function(original, ...)
	return tower:setup_master(original, ...)
end)
obsidian.on_frame(function() tower:frame() end)
-- Frames stop while the lobby isn't cleared, so the beams go now; the towers stay quiet and are picked
-- up again when it clears.
obsidian.on_session(function(on)
	if not on then tower:clear_all_beams() end
end)

obsidian.log("Remixed Stratagems ready")
