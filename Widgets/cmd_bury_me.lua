function widget:GetInfo()
	return {
	name      = "Bury Me",
	desc      = "Bury/Unbury selected Con/Commander with Alt + D (default) or command /buryme",
	author    = "Helwor",
	date      = "Mai 2026",
	license   = "GNU GPL, v2 or later",
	layer     = -99999990,
	enabled   = true, 
	}
end

------ options
local hotkey = 'Alt+d'
local depth = 150
local stop_queue = false
local max_prio = true
local unbury = true
-----------

local BuryMe
local slow_update = 800
local buried = {}
local toDelete = {}
local potentialValidSel = true

options = {}
options_path = 'Hel-K/' .. widget.GetInfo().name
options_order = {'buryme', 'depth', 'stop_queue', 'max_prio', 'unbury'}
options.buryme = {
	name = 'Bury Me',
	type = 'button',
	action = 'buryme';
	OnChange = function(self)
		BuryMe()
	end,
	hotkey = hotkey,
} 

options.depth = {
	type = 'number',
	name = 'Depth',
	min = 75, max = 300, step = 1,
	value = depth,
	OnChange = function(self)
		depth = self.value
	end
}

options.stop_queue = {
	type = 'bool',
	name = 'Stop Queue',
	desc = 'Don\'t keep unit\'s queue',
	value = stop_queue,
	OnChange = function(self)
		stop_queue = self.value
	end
}

options.max_prio = {
	type = 'bool',
	name = 'Max Prio',
	desc = 'Switch the unit to max priority upon action',
	value = max_prio,
	OnChange = function(self)
		max_prio = self.value
	end
}

options.unbury = {
	type = 'bool',
	name = 'Unbury',
	desc = 'Keep track of buried units and unbury them when action is called again',
	value = unbury,
	OnChange = function(self)
		unbury = self.value
	end
}

local UnitDefs = UnitDefs

local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spFindUnitCmdDesc = Spring.FindUnitCmdDesc
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetCommandQueue = Spring.GetCommandQueue
local spValidUnitID = Spring.ValidUnitID
local spGetUnitDefID = Spring.GetUnitDefID

local CMD_TERRAFORM_INTERNAL = Spring.Utilities.CMD.TERRAFORM_INTERNAL
local CMD_LEVEL = Spring.Utilities.CMD.LEVEL
local CMD_RESTORE = Spring.Utilities.CMD.RESTORE
local CMD_PRIORITY = Spring.Utilities.CMD.PRIORITY
local CMD_REPAIR = CMD.REPAIR
local CMD_INSERT = CMD.INSERT
local CMD_SELFD = CMD.SELFD
local CMD_OPT_SHIFT = CMD.OPT_SHIFT
local CMD_OPT_ALT = CMD.OPT_ALT



function widget:SelectionChanged()
	potentialValidSel = true
end
local terraunitDefID = UnitDefNames['terraunit'].id

function BuryMe()
	if not potentialValidSel then
		return
	end
	potentialValidSel = false
	for defID, units in pairs(WG.selectionDefID or spGetSelectedUnitsSorted()) do
		if not UnitDefs[defID].isImmobile and spFindUnitCmdDesc(units[1], CMD_LEVEL) then
			potentialValidSel = true
			for i, id in ipairs(units) do
				local cmdID
				local x, y, z = spGetUnitPosition(id)
				local size
				local depth = depth
				local terra_type
				local elev_type
				local loop
				if unbury and buried[id] then
					cmdID = CMD_RESTORE
					terra_type = 5 -- restore
					size = 8 + ((depth/28)*8)
					depth = 0
					elev_type = 0 -- none
					local queue = spGetCommandQueue(id, 2)
					if queue[2] and queue[1].id == CMD_REPAIR and queue[2].id == CMD_LEVEL then
						if math.abs(x - queue[2].params[1]) < 16 and math.abs(z - queue[2].params[3]) < 16 then
							local terra_id = queue[1].params[1]
							spGiveOrderToUnit(id, CMD.REMOVE, queue[2].tag, 0)
							if spGetUnitDefID(terra_id) == terraunitDefID then
								-- self destruct to make sure in case user don't use terra unit handler or a con is assiting
								toDelete[terra_id] = 30
							end
						end
					end
				else
					cmdID = CMD_LEVEL
					size = 8
					terra_type = 1 -- level
					elev_type = 2 -- lower
					depth = depth
				end
				local team = spGetUnitTeam(units[1])
				if x and team then
					local commandTag = WG.Terraform_GetNextTag()
					local params = {}
					params[1] = terra_type -- terraform type = level
					params[2] = team
					params[3] = x
					params[4] = z
					params[5] = commandTag
					params[6] = 1 -- Loop parameter (rectangle filled?)
					params[7] = y - depth -- Height parameter of terraform
					params[8] = 5 -- Five points in the terraform
					params[9] = 1 -- Number of constructors with the command
					params[10] = elev_type
					
					-- Rectangle of terraform
					params[11] = x + size
					params[12] = z + size
					params[13] = x + size
					params[14] = z - size
					params[15] = x - size
					params[16] = z - size
					params[17] = x - size
					params[18] = z + size
					params[19] = x + size
					params[20] = z + size
					params[21] = id
					if max_prio then
						spGiveOrderToUnit(id, CMD_PRIORITY, 2, 0)
					end
					spGiveOrderToUnit(id, CMD_TERRAFORM_INTERNAL, params, 0)
					if stop_queue then
						spGiveOrderToUnit(id, cmdID, {x, y, z, commandTag}, 0)
					else
						spGiveOrderToUnit(id, CMD_INSERT, {0, cmdID, CMD_OPT_SHIFT, x, y, z, commandTag}, CMD_OPT_ALT)
					end
					buried[id] = not unbury or not buried[id]
				end
			end
		end
	end
end


function widget:GameFrame(f)
	if f%slow_update == 0 then
		for id in pairs(buried) do
			if not spValidUnitID(id) then
				buried[id] = nil
			end
		end
	end
	if next(toDelete) then
		for terra_id, timeOut in pairs(toDelete) do
			timeOut = timeOut - 1
			if timeOut <= 0 then
				if spValidUnitID(terra_id) then
					spGiveOrderToUnit(terra_id, CMD_SELFD, 0, 0)
				end
				toDelete[terra_id] = nil
			else
				toDelete[terra_id] = timeOut
			end
		end
	end
end