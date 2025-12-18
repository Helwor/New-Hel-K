-- $Id: gui_commandinsert.lua 3171 2008-11-06 09:06:29Z det $
-------------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name = "Strider Hub Alt",
		desc = "Implement a one time build for strider hub on repeat using Alt",
        author = "Helwor",
		date = "Sept 2023",
		license = "GNU GPL, v2",
		layer = 5,
		enabled = true,
		handler = true,
	}
end
local Echo = Spring.Echo
local striderHubDefID 	= UnitDefNames['striderhub'].id
local athenaDefID 		= UnitDefNames['athena'].id

local hubRange = UnitDefs[striderHubDefID].buildDistance

local myTeamID
local myPlayerID = Spring.GetMyPlayerID()

local spGiveOrderToUnit			 = Spring.GiveOrderToUnit
local spGetCommandQueue			 = Spring.GetCommandQueue
local spGetSelectedUnitsSorted	 = Spring.GetSelectedUnitsSorted
local spGetUnitPosition			 = Spring.GetUnitPosition
local spGetUnitCurrentCommand	 = Spring.GetUnitCurrentCommand
local spGetModKeyState			 = Spring.GetModKeyState
local glVertex					 = gl.Vertex


local CMD_REMOVE = CMD.REMOVE
local CMD_RAW_MOVE = Spring.Utilities.CMD.RAW_MOVE
local move_color
do
	local file = VFS.LoadFile('cmdcolors.txt')
	local r, g, b, a = file:match('move'..'[ ]-([^ ]+)[ ]-([^ ]+)[ ]-([^ ]+)[ ]-([^ ]+).-\n')
	move_color = {tonumber(r), tonumber(g), tonumber(b), tonumber(a)}
end

local selectionDefID

local includeAthenaAlt = true

options_order = {'include_athena_alt'}
options_path = 'Hel-K/' .. widget:GetInfo().name
options = {}
options.include_athena_alt = {
	type = 'bool',
	name = 'Include alt mod key for Athena',
	value = includeAthenaAlt,
	OnChange = function(self)
		includeAthenaAlt = self.value
	end,
}



function widget:TextCommand(txt)
	if txt == 'stopproduction' then
		local athenas = selectionDefID[athenaDefID]
		local striderHubs = selectionDefID[striderHubDefID]
		if athenas then
			for i, unitID in ipairs(athenas) do
				local queue = spGetCommandQueue(unitID,-1)
				for i, order in ipairs(queue) do
					if order.id < 0 then
						spGiveOrderToUnit(unitID, CMD_REMOVE, order.tag, 0)
					end
				end
			end
		end
		if striderHubs then
			for i, unitID in ipairs(striderHubs) do
				local queue = spGetCommandQueue(unitID,-1)
				for i, order in ipairs(queue) do
					if order.id < 0 then
						spGiveOrderToUnit(unitID, CMD_REMOVE, order.tag, 0)
					end
				end
			end
		end

	end
end
function widget:UnitCmdDone(unitID,defID,teamID,cmd,params,opts)
	-- Echo("unitID,defID,teamID,cmd,params,opts is ", unitID,defID,teamID,cmd,params,opts)
	if cmd > 0 then 
		return
	end
	if defID ~= striderHubDefID and (not includeAthenaAlt or defID ~= athenaDefID) then
		return
	end
	if not opts.alt then
		return
	end
	local queue = spGetCommandQueue(unitID,-1)
	
	local lastOrder = queue[#queue]
	local remove
	if lastOrder and lastOrder.id == cmd then
		remove = true
		for i, p in ipairs(lastOrder.params) do
			if i~=2 and p ~= params[i] then
				remove =false
				break
			end
		end

	end
	if remove then
		spGiveOrderToUnit(unitID, CMD_REMOVE, lastOrder.tag, 0)
	end


end

local moveOrders = {}
local buildOrders = {}
local pendingCommand = {}
local myHubs = {}
local selectedHubs = {}


local function GetClosestBuildPos(defID, px, py, pz)
	return Spring.ClosestBuildPos(myTeamID, defID, px, 0, pz, hubRange, 0, 0)
end
local function UpdateSelectedHubs()
	selectedHubs = {}
	local units = selectionDefID[striderHubDefID]
	if units then
		for i, unitID in pairs(selectionDefID[striderHubDefID]) do
			selectedHubs[unitID] = true
		end
	end
end
function widget:CommandsChanged()
	selectionDefID = WG.selectionDefID or spGetSelectedUnitsSorted()
	UpdateSelectedHubs()
end

function widget:Update()
	newSequence = true
end

function widget:CommandNotify(cmdID, params, opts) -- need modified gui_chili_integral_menu.lua

	if selectionDefID[striderHubDefID] then
		local capture = false
		local onUI = WG.Chili.Screen0.hoveredControl
		for i, unitID in ipairs(selectionDefID[striderHubDefID]) do
			if cmdID == CMD_RAW_MOVE then

				if not (opts.shift and moveOrders[unitID]) then
					moveOrders[unitID] = {params}
				else
					moveOrders[unitID][#moveOrders[unitID] + 1] = params
				end
				capture = true
			elseif cmdID < 0 and opts.alt then

				if newSequence then
					if onUI then
						local queue = spGetCommandQueue(unitID, -1)
						local build = false
						for i, order in ipairs(queue) do
							if order.id < 0 then
								build = true
								break
							end
						end
						if not build then
							local x, y, z = GetClosestBuildPos(-cmdID, unpack(myHubs[unitID]))
							if x == -1 then
								Echo('['..widget:GetInfo().name..']: '.. UnitDefs[striderHubDefID].humanName .. ' #' .. unitID .. ' couldn\'t find a location to build ' .. UnitDefs[-cmdID].humanName .. '.')
							else
								spGiveOrderToUnit(unitID, cmdID, {x, y, z, 0}, opts)
							end
						end
					end
					newSequence = false
				end
				capture = true
			end
		end
		return capture
	end
end
local function drawLineStrip(start, points)
	glVertex(start[1], start[2], start[3])
	for i, point in ipairs(points) do
		glVertex(point[1], point[2], point[3])
	end
end

function widget:DrawWorld()
	------ draw orders
	if next(moveOrders) then
		local shift = select(4, spGetModKeyState())
		gl.PushAttrib(GL.LINE_BITS)
		gl.LineStipple("springdefault")
		gl.DepthTest(false)
		gl.LineWidth(1)
		gl.Color(move_color)
		for unitID, points in pairs(moveOrders) do
			if shift or selectedHubs[unitID] then
				gl.BeginEnd(GL.LINE_STRIP, drawLineStrip, myHubs[unitID], points)
			end
		end
		gl.Color(1, 1, 1, 1)
		gl.LineStipple(false)
		gl.PopAttrib()
	end
end

function widget:UnitCreated(unitID, defID, teamID, builderID)
	if defID == striderHubDefID then
		myHubs[unitID] = {spGetUnitPosition(unitID)}
	elseif myHubs[builderID] then
		if moveOrders[builderID] then
			local moves = moveOrders[builderID]
			for i, move in ipairs(moveOrders[builderID]) do
				spGiveOrderToUnit(unitID, CMD_RAW_MOVE, move, CMD.OPT_SHIFT + CMD.OPT_ALT)
			end
		end
	end
end

function widget:UnitDestroyed(unitID, defID, teamID)
	if defID == striderHubDefID then
		moveOrders[unitID] = nil
		myHubs[unitID] = nil
	end
end

function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
	end
end
function widget:Initialize()
	if Spring.GetSpectatingState() then
		widgetHandler:RemoveWidget(self)
		return
	end
	selectionDefID = WG.selectionDefID

	widget:PlayerChanged(myPlayerID)
	for i, unitID in ipairs(Spring.GetTeamUnitsByDefs(myTeamID, {striderHubDefID})) do
		myHubs[unitID] = {spGetUnitPosition(unitID)}
	end
	widget:CommandsChanged()
end
