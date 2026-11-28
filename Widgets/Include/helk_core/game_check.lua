-- license GNU GPL v2 or later
--
-- Lets a Hel-K file stand down on a game it was not written for.
--
-- Hel-K is installed as loose files, and the engine reads loose files for every
-- game, so other games' widget handlers find Hel-K's widgets too. Many of them
-- load files only Zero-K has, and some have the same path as a file the game
-- ships, which hides the game's own copy. Each file that needs it starts with one
-- line calling Widget or Include below with the game files it needs.
--
-- When every file named is in the game, nothing changes and Hel-K's file runs.
-- When one is missing:
--   if the game has its own file at this path, the game's file runs instead,
--   otherwise a widget returns false, which every widget handler reads as a
--   silent death, and an include carries on.

local function pack(...)
	return { n = select('#', ...), ... }
end

local function missing(...)
	for i = 1, select('#', ...) do
		if not VFS.FileExists((select(i, ...)), VFS.ZIP) then
			return true
		end
	end
	return false
end

local function gameCopy(path, env)
	if VFS.FileExists(path, VFS.ZIP) then
		return pack(VFS.Include(path, env, VFS.ZIP))
	end
end

return {
	-- For a widget in LuaUI/Widgets/. Returns nil to carry on, or the values
	-- the file should return.
	Widget = function(path, env, ...)
		if missing(...) then
			return gameCopy(path, env) or pack(false)
		end
	end,
	-- For a file other files include. Returns nil to carry on, or the values
	-- the file should return.
	Include = function(path, env, ...)
		if missing(...) then
			return gameCopy(path, env)
		end
	end,
}
