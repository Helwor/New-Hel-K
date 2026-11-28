do local skip = VFS.Include("LuaUI/Widgets/Include/helk_core/game_check.lua", nil, VFS.RAW_FIRST).Widget("LuaUI/Widgets/api_font_cache.lua", getfenv(), "LuaUI/cawidgets.lua", "LuaRules/Configs/customcmds.h.lua") if skip then return unpack(skip, 1, skip.n) end end -- Hel-K game check
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "Font Cache",
		desc      = "Cache for Chili fonts.",
		author    = "GoogleFrog",
		date      = "8 June 2021",
		license   = "GNU GPL, v2 or later",
		layer     = math.huge,
		alwaysStart = true,
		enabled   = true,
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local DISABLE = false

local font = {}
local specialFont = {}

function WG.GetFont(size)
	size = size or 13
	if (not font[size]) or DISABLE then
		font[size] = WG.Chili.Font:New {
			font          = "FreeSansBold.otf",
			size          = size,
			shadow        = true,
			outline       = false,
			outlineWidth  = 3,
			outlineWeight = 3,
			color         = {1, 1, 1, 1},
			outlineColor  = {0, 0, 0, 1},
			autoOutlineColor = false,
			useRTT = false,
		}
	end
	return font[size]
end

function WG.GetSpecialFont(size, name, data)
	size = size or 13
	if not specialFont[size] then
		specialFont[size] = {}
	end
	if DISABLE or (not specialFont[size][name]) then
		local shadows, outline, autoOutlineColor = true, false, false
		if data.shadows ~= nil then
			shadows = data.shadows
		end
		if data.outline ~= nil then
			outline = data.outline
		end
		if data.autoOutlineColor ~= nil then
			autoOutlineColor = data.autoOutlineColor
		end
		specialFont[size][name] = WG.Chili.Font:New {
			font          = data.font or "FreeSansBold.otf",
			size          = data.size or size,
			shadow        = shadows,
			outline       = outline,
			outlineWidth  = data.outlineWidth or 3,
			outlineWeight = data.outlineWeight or 3,
			color         = data.color or {1, 1, 1, 1},
			outlineColor  = data.outlineColor or {0, 0, 0, 1},
			autoOutlineColor = autoOutlineColor,
		}
	end
	return specialFont[size][name]
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
