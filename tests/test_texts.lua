-- The words players read: the stratagem's title, the mod's description and the README. Plain and serious,
-- with no first or second person, no "its", no dashes as connectors, and short enough for the game's screens.
local seaf = obsidian.module("src/seaf_unit")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local BANNED = { "its", "you", "your", "yours", "i", "me", "my", "we", "our", "us" }

local function check(text, what)
	local lower = " " .. text:lower():gsub("[^%w'%-]", " ") .. " "
	for _, word in ipairs(BANNED) do
		yes(not lower:find(" " .. word .. " ", 1, true), what .. ' says "' .. word .. '"')
	end
	yes(not text:find("\226\128\148", 1, true) and not text:find("\226\128\147", 1, true), what .. " has a long dash")
	yes(not text:find(" %- ") and not text:find(" %-%- "), what .. " has a dash between words")
	yes(not text:find("\226\128\166", 1, true) and not text:find("...", 1, true), what .. " has an ellipsis")
	yes(not text:find("%w's%f[%W]"), what .. " has a possessive")
end

local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

test("the_stratagem_s_title_keeps_the_writing_rules", function()
	check(seaf.TITLE, "the title")
	check(seaf.DESCRIPTION, "the description")
	for i, u in ipairs(seaf.UPGRADES) do
		check(u.title, "upgrade " .. i .. " title")
		check(u.description, "upgrade " .. i .. " description")
	end
end)

test("the_readme_and_the_mod_description_keep_them_too", function()
	local readme = read("README.md")
	-- Code spans aside, every line.
	for line in readme:gmatch("[^\n]+") do check((line:gsub("`[^`]*`", "")), "README line: " .. line:sub(1, 40)) end
	local manifest = read("obsidian.json")
	local description = manifest:match('"description"%s*:%s*{%s*"en"%s*:%s*"([^"]*)"')
	yes(description, "a description in obsidian.json")
	check(description, "the mod's description")
end)

return T
