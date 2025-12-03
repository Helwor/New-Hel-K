
function widget:GetInfo()
	return {
		name      = "Fix Wait",
		desc      = "Only unwait waiting units if any",
		author    = "Helwor",
		date      = "Oct 2023",
		license   = "GNU GPL, v2 or v3",
		layer     = -10, -- Before NoDuplicateOrders
		enabled   = true
	}
end


local spGetSelectedUnits 		= Spring.GetSelectedUnits
local spGiveOrderToUnit			= Spring.GiveOrderToUnit
local spGiveOrderToUnitArray    = Spring.GiveOrderToUnitArray
local spGetUnitCurrentCommand 	= Spring.GetUnitCurrentCommand
local spGetCommandQueue			= Spring.GetCommandQueue
local spGetFactoryCommands		= Spring.GetFactoryCommands
local spGetUnitdefID			= Spring.GetUnitDefID
local spGetSelectedUnitsSorted	= Spring.GetSelectedUnitsSorted
local spGetSelectedUnitsCount	= Spring.GetSelectedUnitsCount
local CMD_WAIT 					= CMD.WAIT
local CMD_OPT_ALT 				= CMD.OPT_ALT
local CMD_OPT_SHIFT				= CMD.OPT_SHIFT
local EMPTY_TABLE				= {}

local factoryDefs = {}
for defID, def in ipairs(UnitDefs) do
	if def.isFactory then
		factoryDefs[defID] = true
	end
end

function IsWaiting(unitID, isFac, shift)
	local cmdID, opt
	if isFac then
		local order = (spGetFactoryCommands(unitID, 1) or EMPTY_TABLE)[1]
		if order then
			cmdID, opt = order.id, order.options.coded
		end
	elseif shift then
		local queue = (spGetCommandQueue(unitID,-1) or EMPTY_TABLE)
		local lastOrder = queue[#queue]
		if lastOrder then
			cmdID, opt = lastOrder.id, lastOrder.options.coded
		end
	else
		cmdID, opt = spGetUnitCurrentCommand(unitID)
	end
    return cmdID == CMD_WAIT and (opt % (2*CMD_OPT_ALT) < CMD_OPT_ALT)
end

function widget:CommandNotify(cmdID, params, opts)
	if cmdID ~= CMD_WAIT then
		return
	end
	local selDefID = (spGetSelectedUnitsSorted() or EMPTY_TABLE)
	if not next(selDefID) then
		return
	end

	local len = spGetSelectedUnitsCount()
	if len < 2 then
		return
	end
	local waiting, w = {}, 0
	local shift = opts.shift
	for defID, units in pairs(selDefID) do
		local isFac = factoryDefs[defID]
		for i, unitID in ipairs(units) do
			if IsWaiting(unitID, isFac, shift) then
				w = w + 1
				waiting[w] = unitID
			end
		end
	end

	if w > 0 and w < len then
		-- giving order one by one is smooth and doesn't take more time or very barely on big number (1000+)
		local opt = shift and not isFac and CMD_OPT_SHIFT or 0
		for i, unitID in ipairs(waiting) do
			spGiveOrderToUnit(unitID, CMD_WAIT, EMPTY_TABLE, opt)
		end
		-- provoke freeze on big number
		-- spGiveOrderToUnitArray(waiting, CMD_WAIT, EMPTY_TABLE, shift and CMD_OPT_SHIFT or 0)
		return true
	end
end

function widget:Initialize()
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		widgetHandler:RemoveWidget(self)
	end
end