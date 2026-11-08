-- The SEAF Unit's entry for api.stratagems.define. A beacon calls down SEAF soldiers who fight beside the
-- squad (seaf_squad); the Tesla Tower it is copied from never lands.
local M = {}

M.NAME = "stratagem_seaf_unit"
M.TITLE = "SEAF Unit"
-- In the game's style: the upgrade texts replace this one in the menus, so each restates it with the
-- change worked in (tools: internal/native-texts.md).
local KIT = " Improved field kits equip each soldier with a support weapon and a random perk."
local function text(count, soldier, follows, helps, collects, leaves)
	return "Call down " .. count .. " of the Super Earth Armed Forces to fight beside the squad. The " .. soldier
		.. " " .. follows .. " the Helldivers, " .. helps .. " up the fallen and " .. collects
		.. " samples, but " .. leaves .. " the objectives to them. SEAF soldiers are NOT reinforced when they fall."
end
M.DESCRIPTION = text("a soldier", "soldier", "follows", "helps", "collects", "leaves")
-- The game's stratagem the new one is copied from. Other players see this one on the wire.
M.BASE = "stratagem_tesla_tower"
M.TYPE = "supply"
-- Offered from rank 5 on, as the game offers the other stratagems by rank.
M.UNLOCK = { rank = 5 }
-- The icon is the name of the sub-material inside the icon material (tools/build_icon.py writes it),
-- not the texture's resource name. A gui asked for a sub-material the material lacks stops the game.
M.ICON = "seaf_unit_icon"
M.ICON_MATERIAL = "more_stratagems/icons"
-- Seconds of cooldown, seconds from call-in to the stratagem landing, and uses per mission.
M.COOLDOWN = 200
M.CALL_IN = 15
M.USES = 2
M.UPGRADES = {
	{ title = "SEAF Unit Mk2", description = M.DESCRIPTION .. KIT, cost = 2 },
	{ title = "SEAF Unit Mk3", description = text("two soldiers", "soldiers", "follow", "help", "collect", "leave") .. KIT, cost = 3 },
}
-- The lowest Obsidian API version the stratagem is defined on, and the lowest one soldiers come with
-- (guest bots on any machine, looks, deaths, pickups and the lobby calls of 1.41.0; the default loadout,
-- fight's best weapon and the weapon's range of 1.42.0; routes, movement, the "threat" weapon choice and
-- grenades of 1.45.0; ammunition recovery of 1.46.0).
M.MIN_API = { 1, 46, 0 }
M.BOTS_API = { 1, 46, 0 }

-- Whether a version string such as "1.22.0" is at least the list given.
function M.at_least(version, want)
	local got = {}
	for n in tostring(version or ""):gmatch("%d+") do got[#got + 1] = tonumber(n) end
	for i, w in ipairs(want) do
		local v = got[i] or 0
		if v ~= w then return v > w end
	end
	return true
end

-- call_in(pos, upgrade, owner): what a landed beacon does, with pos as plain numbers. nil when soldiers
-- can't come (an Obsidian API older than BOTS_API): refused(owner) runs instead. Either way, no tower.
function M.def(call_in, refused)
	local upgrades = {}
	for i, u in ipairs(M.UPGRADES) do upgrades[i] = { title = u.title, description = u.description, cost = u.cost } end
	return {
		name = M.NAME,
		base = M.BASE,
		title = M.TITLE,
		description = M.DESCRIPTION,
		type = M.TYPE,
		unlock = M.UNLOCK,
		icon = M.ICON,
		icon_material = M.ICON_MATERIAL,
		stats = { cooldown_time = M.COOLDOWN, activation_time = M.CALL_IN, num_uses = M.USES },
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
			if not ok and obsidian and obsidian.log then obsidian.log("SEAF Unit: " .. tostring(err)) end
			return false
		end,
	}
end

return M
