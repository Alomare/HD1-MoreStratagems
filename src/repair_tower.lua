-- The A/AC-90 Repair Tower's entry for api.stratagems.define: the Tesla Tower with a code, an icon, words
-- and three Mk levels of its own. The tower's numbers per Mk live in src/repair_levels.lua; the upgrade
-- levels here carry the words, the costs and the Loadout screen's bars.
local levels = obsidian.module("src/repair_levels")

local M = {}

M.TITLE = "A/AC-90 Repair Tower"
-- The Tesla Tower's code with the last two arrows swapped. No game stratagem's code starts with it, and
-- it starts with none of theirs.
M.CODE = { "left", "down", "down", "up", "left", "right" }
-- Its own icon: the Tesla Tower's with the REP-80's heart where the bolts were, in a material this mod
-- puts in the boot bundle (tools/build_icon.py). Obsidian API 1.22.0 adds that material to every gui
-- that draws the game's icons; an older one can't, and a gui asked for a name it doesn't have is
-- assumed fatal, so then the tower shows the REP-80's icon.
M.ICON = "remixed_repair_tower_icon"
M.ICON_MATERIAL = "remixed_stratagems/icons"
M.OLD_API_ICON = "stratagem_repairtool"
M.ICON_API = { 1, 22, 0 }
-- Earned like most of the game's stratagems, in the first missions of a new account. "base" would
-- wait for the Tesla Tower, a reward from difficulty 10 and 11 planets.
M.UNLOCK = { rank = 5 }

M.DESCRIPTION = "A Tesla Tower with REP-80 beams in place of lightning. Heals Helldivers and repairs vehicles and turrets within 8 m, one target at a time."
M.UPGRADES = {
	{ title = "A/AC-90 Repair Tower Mk2", cost = 2,
		description = "Range grows to 12 m, and the tower heals three targets at once.",
		attributes = { attr_spec_multi_target = true }, upgrade_attributes = { attr_range = 2 } },
	{ title = "A/AC-90 Repair Tower Mk3", cost = 3,
		description = "Beams heal twice as fast, get downed Helldivers back up and save burning vehicles before they explode." },
}

-- Whether an Obsidian API of this version ("1.22.0") takes the tower's own icon.
function M.own_icon(version)
	local got = {}
	for n in tostring(version or ""):gmatch("%d+") do got[#got + 1] = tonumber(n) end
	for i, want in ipairs(M.ICON_API) do
		local v = got[i] or 0
		if v ~= want then return v > want end
	end
	return true
end

-- api_version: the running Obsidian API's, from obsidian.info.
function M.def(api_version)
	local own = M.own_icon(api_version)
	local upgrades = {}
	for i, u in ipairs(M.UPGRADES) do
		upgrades[i] = { title = u.title, description = u.description, cost = u.cost, attributes = u.attributes,
			upgrade_attributes = u.upgrade_attributes }
	end
	return {
		name = levels.NAME,
		base = levels.BASE,
		title = M.TITLE,
		description = M.DESCRIPTION,
		code = M.CODE,
		icon = own and M.ICON or M.OLD_API_ICON,
		icon_material = own and M.ICON_MATERIAL or nil,
		type = "defensive",
		-- The bars: no damage or fire rate, a range that grows at Mk2, and the Tesla Tower's toughness.
		attributes = { attr_power = "attr_not_avalible", attr_firerate = "attr_not_avalible", attr_range = 1, attr_durability = 3 },
		upgrades = upgrades,
		unlock = M.UNLOCK,
	}
end

return M
