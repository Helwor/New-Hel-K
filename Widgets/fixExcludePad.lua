do local skip = VFS.Include("LuaUI/Widgets/Include/helk_core/game_check.lua", nil, VFS.RAW_FIRST).Widget("LuaUI/Widgets/fixExcludePad.lua", getfenv(), "LuaUI/cawidgets.lua", "LuaRules/Configs/customcmds.h.lua", "LuaRules/Configs/customcmds.lua") if skip then return unpack(skip, 1, skip.n) end end -- Hel-K game check
function widget:GetInfo()
	return {
		name      = "FixExcludePad",
		desc      = "Causes only one exclude pad order to be issued in a selection of multiple aircraft. Sending an even number causes the command to do nothing, but sending more than one is redundant.",
		author    = "Helwor",
		date      = "Dec 2023",
		license   = "PD",
		layer     = 1, 
		enabled   = true,  --  loaded by default?
		handler   = true,
	}
end
local Echo						= Spring.Echo
local spGiveOrderToUnit			= Spring.GiveOrderToUnit
local spGetSelectedUnitsSorted	= Spring.GetSelectedUnitsSorted

local airUnitDefID = {}
for defID, def in pairs(UnitDefs) do
	if def.canFly then
		airUnitDefID[defID] = true
	end
end

local CMD_EXCLUDE_PAD
do
	local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")
	CMD_EXCLUDE_PAD = customCmds.EXCLUDE_PAD
end


function widget:CommandNotify(cmd,params,opts)
	if cmd ~= CMD_EXCLUDE_PAD then
		return false
	end
	local selTypes = WG.selectionDefID or spGetSelectedUnitsSorted()
	for defID, units in pairs(selTypes) do
		if airUnitDefID[defID] then
			spGiveOrderToUnit(units[1], cmd, params, opts)
			return true
		end
	end
end
