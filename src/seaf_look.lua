-- The SEAF Unit's look: a blue set of armour (helmet, body, cape) that the game's customization
-- component can spawn like any other. The pieces are copies of the default Helldiver outfit under new unit
-- names (res/armor, built by tools/build_armor.py), so other players' armour is untouched.
--
-- The look is three indexes into CustomizationSettings.helmet, .body and .cape, which go over the network as
-- one byte each. Every machine that runs this mod adds the same three entries at the end of the lists, so the
-- indexes mean the same everywhere. A machine without them has no such entry, and the game errors reading
-- the missing one: use pick(members), which answers the fallback unless every player in the lobby has them.
--
-- Entries are never offered to the player. The armory menu drops every entry whose name no rank unlocks, no
-- DLC owns and the save does not list as unlocked, and these names are none of those. The menu is also
-- cleaned after it builds, for the debug "unlock all" command that lists every name.
local M = {}

M.OPTION = "custom_armor"
M.PREFIX = "more_stratagems/armor/"

-- Each entry copies the game's default piece, named by `base`, and changes the name and the unit path.
M.PIECES = {
	helmet = { base = "cus_helmet_tactical", name = "cus_helmet_seaf", unit_path = M.PREFIX .. "seaf_helmet" },
	body = { base = "cus_body_default", name = "cus_body_seaf",
		male = M.PREFIX .. "seaf_body_male", female = M.PREFIX .. "seaf_body_female" },
	cape = { base = "cus_cape_default", name = "cus_cape_seaf", unit_path = M.PREFIX .. "seaf_cape" },
}
-- The order the pieces are added and reported in.
M.KINDS = { "helmet", "body", "cape" }

-- The snow helmet and body and the Ceremonial cape, which every game has.
local FALLBACK = { helmet = 4, body = 4, cape = 12 }

local unpack = unpack or table.unpack

local function settings()
	return rawget(_G, "CustomizationSettings")
end

local function log(text)
	if obsidian and obsidian.log then pcall(obsidian.log, text) end
end

local function clone(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = clone(v) end
	return out
end

local function find(list, name)
	for i, entry in ipairs(list) do
		if type(entry) == "table" and entry.name == name then return i end
	end
	return nil
end

-- The new entry for a piece, copied from the base entry of the game's list.
local function made(piece, base)
	local entry = clone(base)
	entry.name = piece.name
	if piece.unit_path then
		entry.unit_path = piece.unit_path
	else
		-- A body has a unit for each gender.
		entry.male = clone(entry.male or {})
		entry.female = clone(entry.female or {})
		entry.male.unit_path = piece.male
		entry.female.unit_path = piece.female
	end
	return entry
end

local state = { indexes = nil }

-- Whether the option is on. An unreadable option counts as off.
function M.enabled()
	if not (obsidian and obsidian.settings and obsidian.settings.get) then return false end
	local ok, value = pcall(obsidian.settings.get, M.OPTION)
	return ok and value == true
end

-- Adds the three entries when the option is on, and returns { helmet, body, cape }. Called again, it adds
-- nothing and returns the same indexes. Returns nil, and changes nothing, when the option is off or the game's
-- lists are not there.
function M.install()
	local ok, result = pcall(function()
		if not M.enabled() then return nil end
		local cs = settings()
		if type(cs) ~= "table" then return nil end
		local found, fresh = {}, {}
		for _, kind in ipairs(M.KINDS) do
			local list, piece = cs[kind], M.PIECES[kind]
			if type(list) ~= "table" then return nil end
			local at = find(list, piece.name)
			if not at then
				local base = find(list, piece.base)
				if not base then return nil end
				fresh[kind] = made(piece, list[base])
			end
			found[kind] = at
		end
		local indexes = {}
		for _, kind in ipairs(M.KINDS) do
			local list = cs[kind]
			if fresh[kind] then
				-- The next free slot of the array, so the game's own indexes stay where they are.
				found[kind] = #list + 1
				list[found[kind]] = fresh[kind]
			end
			indexes[kind] = found[kind]
		end
		state.indexes = indexes
		return indexes
	end)
	if not ok then
		log("SEAF look not installed: " .. tostring(result))
		return nil
	end
	return result and { helmet = result.helmet, body = result.body, cape = result.cape } or nil
end

-- Takes the entries out. An entry at the end of a list is removed. One with another mod's entry after it is
-- put back to a copy of the default piece, so no later index moves. Do not call this while a bot wears the
-- look: a piece whose entry is gone errors in the game's customization update.
function M.uninstall()
	local ok, err = pcall(function()
		local cs = settings()
		if type(cs) == "table" then
			for _, kind in ipairs(M.KINDS) do
				local list, piece = cs[kind], M.PIECES[kind]
				local at = type(list) == "table" and find(list, piece.name)
				if at then
					if at == #list then
						table.remove(list, at)
					else
						local base = find(list, piece.base)
						list[at] = base and clone(list[base]) or list[at]
					end
				end
			end
		end
		state.indexes = nil
	end)
	if not ok then log("SEAF look not removed: " .. tostring(err)) end
end

-- { helmet, body, cape } while the entries are in the game's lists, nil when the option is off or the
-- install failed.
function M.indexes()
	local have = state.indexes
	local cs = settings()
	if not (have and type(cs) == "table" and M.enabled()) then return nil end
	for _, kind in ipairs(M.KINDS) do
		local list, entry = cs[kind], nil
		entry = type(list) == "table" and list[have[kind]]
		if not (type(entry) == "table" and entry.name == M.PIECES[kind].name) then return nil end
	end
	return { helmet = have.helmet, body = have.body, cape = have.cape }
end

-- The look every game has: the snow helmet and body, and the Ceremonial cape.
function M.fallback()
	return { helmet = FALLBACK.helmet, body = FALLBACK.body, cape = FALLBACK.cape }
end

-- Whether every other player in the lobby runs Obsidian with the same mod set as each other. members is
-- obsidian.session.members(). The mod set carries this mod's version and option values, so the same set as
-- ours has the entries. Nobody else in the lobby counts as shared. A player the list does not show as
-- having Obsidian has no entries.
function M.shared(members)
	local mine
	for _, m in ipairs(members or {}) do
		if not (type(m) == "table" and m.obsidian and m.modset) then return false end
		mine = mine or m.modset
		if m.modset ~= mine then return false end
	end
	return true
end

-- The indexes for a lobby: the blue set when it is installed and every player has it, the
-- fallback otherwise.
function M.pick(members)
	local own = M.indexes()
	if own and M.shared(members) then return own end
	return M.fallback()
end

-- Removes the entries from the armory menu's lists. menu is the screen after on_enter built them.
function M.strip_menu(menu)
	local ours = {}
	for _, piece in pairs(M.PIECES) do ours[piece.name] = true end
	for _, group in ipairs(menu and menu.options or {}) do
		local list = group.options
		if group.type ~= "gender" and type(list) == "table" then
			for i = #list, 1, -1 do
				if type(list[i]) == "table" and ours[list[i].name] then table.remove(list, i) end
			end
			if type(group.selected_option) == "number" and group.selected_option > #list then
				group.selected_option = math.max(#list, 1)
			end
		end
	end
end

local wrapped = false

-- Wraps on_enter of the armory menu, so the entries are gone from the menu's lists whatever unlocked them.
function M.guard_menu()
	if wrapped or not (obsidian and obsidian.wrap and obsidian.capabilities and obsidian.capabilities.wrap) then return end
	wrapped = true
	pcall(obsidian.wrap, "MenuScreenArmoryProfile", "on_enter", function(original, self, ...)
		local out = { original(self, ...) }
		pcall(M.strip_menu, self)
		return unpack(out)
	end)
end

-- For main.lua: installs now if the game's settings are there already, and again when the game loads them.
function M.start()
	M.install()
	pcall(M.guard_menu)
	if obsidian and obsidian.on_require then
		pcall(obsidian.on_require, "lua/settings/customization_settings", function() M.install() end)
	end
end

return M
