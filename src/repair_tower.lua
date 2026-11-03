-- The A/AC-90 Repair Tower's entry for api.stratagems.define: the Tesla Tower with a code, an icon, words
-- and three Mk levels of its own. The tower's numbers per Mk live in src/repair_levels.lua; the upgrade
-- levels here carry the words, the costs and the Loadout screen's bars.
local levels = obsidian.module("src/repair_levels")

local M = {}

M.TITLE = "A/AC-90 Repair Tower"
-- The Tesla Tower's code with the last two arrows swapped. No game stratagem's code starts with it, and
-- it starts with none of theirs.
M.CODE = { "left", "down", "down", "up", "left", "right" }
-- The REP-80's icon: the HUD has no repair tower of its own, and the tower's work is the REP-80's.
M.ICON = "stratagem_repairtool"
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

function M.def()
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
		icon = M.ICON,
		type = "defensive",
		-- The bars: no damage or fire rate, a range that grows at Mk2, and the Tesla Tower's toughness.
		attributes = { attr_power = "attr_not_avalible", attr_firerate = "attr_not_avalible", attr_range = 1, attr_durability = 3 },
		upgrades = upgrades,
		unlock = M.UNLOCK,
	}
end

return M
