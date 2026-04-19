function widget:GetInfo()
	return {
		name      = "Fix Sparrow Fly",
		desc      = "Force sparrows to fly when built",
		author    = "Helwor",
		date      = "Apr 2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true,
	}
end

local sparrowDefID = UnitDefNames['planelightscout'].id

local ignoreBuilderDefID = {
	[UnitDefNames['factoryplane'].id] = true,
	[UnitDefNames['plateplane'].id] = true,
}

local myPlayerID = Spring.GetMyPlayerID()
local myTeamID

------ speed ups

local CMD_MOVE = CMD.MOVE
local CMD_INSERT = CMD.INSERT
local CMD_OPT_RIGHT = CMD.OPT_RIGHT
local CMD_OPT_ALT = CMD.OPT_ALT

local spGetUnitCurrentCommand 	= Spring.GetUnitCurrentCommand
local spGetUnitDefID 			= Spring.GetUnitDefID
local spGetUnitPosition 		= Spring.GetUnitPosition
local spGiveOrderToUnit 		= Spring.GiveOrderToUnit
local spGetMyTeamID 			= Spring.GetMyTeamID

-----------------


function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = spGetMyTeamID()
	end
end

function widget:UnitCreated(unitID, defID, teamID, builderID)
	if defID == sparrowDefID and teamID == myTeamID then
		local builderDefID = builderID and spGetUnitDefID(builderID)
		if not ignoreBuilderDefID[builderDefID] then
			local cmd, opt, tag = spGetUnitCurrentCommand(unitID)
			if not cmd then
				local x, y, z = spGetUnitPosition(unitID)
				if x then
					spGiveOrderToUnit(unitID, CMD_INSERT, {0, CMD_MOVE, CMD_OPT_RIGHT, x, y, z}, CMD_OPT_ALT)
				end
			end
		end
	end
end

function widget:Initialize()
	myTeamID = spGetMyTeamID()
end