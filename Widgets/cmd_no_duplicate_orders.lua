-- $Id: cmd_no_duplicate_orders.lua 3171 2008-11-06 09:06:29Z det $
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    cmd_no_duplicate_orders.lua
--  brief:   Blocks duplicate Attack and Repair/Build orders
--  author:  Owen Martindell
--
--  Copyright (C) 2008.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "NoDuplicateOrders",
		desc      = "Blocks duplicate Attack and Repair/Build orders 1.1",
		author    = "TheFatController",
		date      = "16 April, 2008",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true  --  loaded by default?
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local GetSelectedUnits = Spring.GetSelectedUnits
local GetCommandQueue  = Spring.GetCommandQueue
local GetUnitPosition  = Spring.GetUnitPosition
local GiveOrderToUnit  = Spring.GiveOrderToUnit
local GetUnitHealth    = Spring.GetUnitHealth

local CMD_OPT_INTERNAL = CMD.OPT_INTERNAL
local CMD_RAW_BUILD = Spring.Utilities.CMD.RAW_BUILD

local buildList = {}

function widget:Initialize()
	if (Spring.GetSpectatingState() or Spring.IsReplay()) and (not Spring.IsCheatingEnabled()) then
		widgetHandler:RemoveWidget()
	end
	local myTeam = Spring.GetMyTeamID()
	local units = Spring.GetTeamUnits(myTeam)
	for i=1,#units do
		local unitID = units[i]
		local buildProgress = select(5, GetUnitHealth(unitID))
		if (buildProgress < 1) then widget:UnitCreated(unitID) end
	end
end

local function toLocString(posX,posY,posZ)
	return (posX .. "_" .. posZ)
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
	local locString = toLocString(GetUnitPosition(unitID))
	buildList[locString] = unitID
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	local locString = toLocString(GetUnitPosition(unitID))
	buildList[locString] = nil
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	local locString = toLocString(GetUnitPosition(unitID))
	buildList[locString] = nil
end
local optFixMixedOrders = false -- when only a part of selected units have the same current order  than the newly issued,
	--  we don't want to cancel it but rather issue it to those who doesnt have it already
local optNeverCancelOrder = false -- never cancel identical orders, override the opt above
function widget:CommandNotify(cmd, params, options)
	if params[2] then -- This widget only handles unit-target commands
		return false
	end
	if ((options.coded == 16) or (options.coded == 48)) and (cmd == CMD.REPAIR) then -- Right Click or Shift+Right Click
		-- Echo('process')
		local selUnits = GetSelectedUnits()
		local blockUnits = {}
		local keepSecond = {}
		local shiftMode = (options.coded == 48)
		-- 'nomix' fix is overriden if optNeverCancelOrder
		local optFixMixedOrders = not optNeverCancelOrder and optFixMixedOrders
		local tags = optFixMixedOrders and {}
		for i = 1, #selUnits do
			local unitID = selUnits[i]
			local cmdID, _, cmdTag, cmdParam1, _, cmdParam3 = Spring.GetUnitCurrentCommand(unitID)
			if cmdID then
				if (cmdID == CMD.REPAIR) and (params[1] == cmdParam1) and (not shiftMode or optNeverCancelOrder or optFixMixedOrders) then
					-- Do not block Shift+Right Click as it is used to cancel an order.
					-- Echo('block 1')
					blockUnits[unitID] = true
				else
					-- Echo('case 2 RAW_BUILD')
					local cmdID_2, _, cmdTag_2, cmdParam1_2, _, cmdParam3_2
					if cmdID == CMD_RAW_BUILD then
						cmdID_2, _, cmdTag_2, cmdParam1_2, _, cmdParam3_2 = Spring.GetUnitCurrentCommand(unitID, 2)
					end
					local structureMatch = ((cmdID < 0) and cmdParam3 and (params[1] == buildList[toLocString(cmdParam1, 0, cmdParam3)])) or
							   (cmdID_2 and (cmdID_2 < 0) and cmdParam3_2 and (params[1] == buildList[toLocString(cmdParam1_2, 0, cmdParam3_2)]))
					-- Echo("structureMatch is ", structureMatch)
					if structureMatch then
						if shiftMode and not optNeverCancelOrder then
							-- Shift+Right Click on a construction command should remove the command.
							Spring.GiveOrderToUnit(unitID, CMD.REMOVE, {cmdTag}, 0)
							if cmdTag_2 then
								Spring.GiveOrderToUnit(unitID, CMD.REMOVE, {cmdTag_2}, 0)
							end
						end
						blockUnits[unitID] = true
						if cmdID_2 then
							keepSecond[unitID] = true
						end
					end
				end
				-- Echo("blockUnits[unitID] is ", blockUnits[unitID])
			end

		end
		if next(blockUnits) then
			for i = 1, #selUnits do
				local unitID = selUnits[i]
				if not blockUnits[unitID] then
					-- Echo('give issued order')
					GiveOrderToUnit(unitID, cmd, params, options)
				elseif not shiftMode then
					local cQueue = GetCommandQueue(unitID, -1)
					-- Echo('recheck all orders')
					for j = 2, #cQueue do
						local v = cQueue[j]
						if not keepSecond[unitID] or j > 2 then
							-- orders will negate themselves
							GiveOrderToUnit(unitID, v.id, v.params, CMD.OPT_SHIFT)
						end
					end
				end
			end
			return true
		else
			return false
		end
	else
		-- Echo('not process')
	end
	if (options.coded == 16) and (id == CMD.ATTACK) then -- Right Click only
		local selUnits = GetSelectedUnits()
		local blockUnits = {}
		for i = 1, #selUnits do
			local unitID = selUnits[i]
			local cmdID, cmdOpts, _, cmdParam = Spring.GetUnitCurrentCommand(unitID)
			-- Override internal commands to override idle behaviour.
			if cmdID and (params[1] == cmdParam) and (cmdOpts ~= CMD_OPT_INTERNAL) then
				blockUnits[unitID] = true
			end
		end -- for
		if next(blockUnits) then
			for i = 1, #selUnits do
				local unitID = selUnits[i]
				if not blockUnits[unitID] then
					GiveOrderToUnit(unitID, id, params, options)
				else
					local cQueue = GetCommandQueue(unitID, -1)
					for j = 2, #cQueue do
						local v = cQueue[j]
						GiveOrderToUnit(unitID,v.id,v.params, CMD.OPT_SHIFT)
					end -- for
				end -- if ... else
			end -- for
			return true
		else -- if
			return false
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
