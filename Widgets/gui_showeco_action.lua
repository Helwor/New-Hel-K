-- if VFS.FileExists(filename, VFS.ZIP_ONLY) then


local version = "v1.003"
function widget:GetInfo()
  return {
    name      = "Showeco and Grid Drawer",
    desc      = "Register an action called Showeco & draw overdrive overlay.", --"acts like F4",
    author    = "xponen, ashdnazg",
    date      = "July 19 2013",
    license   = "GNU GPL, v2 or later",
    layer     = 0, --only layer > -4 works because it seems to be blocked by something.
    enabled   = true,  --  loaded by default?
    handler   = true,
  }
end


local Echo = Spring.Echo

local spGetMapDrawMode = Spring.GetMapDrawMode
local spSendCommands   = Spring.SendCommands
function widget:DrawScreen()
end
local function ToggleShoweco()
	WG.showeco = not WG.showeco

	if (not WG.metalSpots and (spGetMapDrawMode() == "metal") ~= WG.showeco) then
		spSendCommands("showmetalmap")
	end
end

WG.ToggleShoweco = ToggleShoweco
WG.force_show_queue_grid = false
--------------------------------------------------------------------------------------
--Grid drawing. Copied and trimmed from unit_mex_overdrive.lua gadget (by licho & googlefrog)
VFS.Include("LuaRules/Configs/constants.lua", nil, VFS.ZIP_FIRST)
VFS.Include("LuaRules/Utilities/glVolumes.lua") --have to import this incase it fail to load before this widget

local spGetUnitDefID       = Spring.GetUnitDefID
local spGetUnitPosition    = Spring.GetUnitPosition
local spGetActiveCommand   = Spring.GetActiveCommand
local spTraceScreenRay     = Spring.TraceScreenRay
local spGetMouseState      = Spring.GetMouseState
local spAreTeamsAllied     = Spring.AreTeamsAllied
local spGetMyTeamID        = Spring.GetMyTeamID
local spGetUnitPosition    = Spring.GetUnitPosition
local spValidUnitID        = Spring.ValidUnitID
local spGetUnitRulesParam  = Spring.GetUnitRulesParam
local spGetSpectatingState = Spring.GetSpectatingState
local spGetBuildFacing     = Spring.GetBuildFacing
local spPos2BuildPos       = Spring.Pos2BuildPos

local glVertex        = gl.Vertex
local glCallList      = gl.CallList
local glColor         = gl.Color
local glCreateList    = gl.CreateList

--// gl const

local pylons = {count = 0, data = {}, byColor = {}}
local pylonByID = {}
local currentSelection = false

local eBuildDefs = {}
local isBuilder = {}
local floatOnWater = {}

for i=1,#UnitDefs do
	local udef = UnitDefs[i]
	local range = tonumber(udef.customParams.pylonrange)
	if (range and range > 0) then
		eBuildDefs[i] = range
	end
	if udef.isBuilder then
		isBuilder[i] = true
	end
	if udef.floatOnWater then
		floatOnWater[i] = true
	end
end

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Utilities

local drawList = 0
local disabledDrawList = 0
local lastDrawnFrame = 0
local lastFrame = 2
local highlightQueue = false
local prevCmdID
local lastCommandsCount

local function ForceRedraw()
	lastDrawnFrame = 0
end

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Menu Options
local helk_path = 'Hel-K/' .. widget:GetInfo().name
local drawAlpha = 0.2
local noEffColor = {1, 0.25, 1, drawAlpha}
local new_method = true
local HighlightEBuilds

WG.showeco_always_mexes = true -- No OnChange when not changed from the default.

options_path = 'Settings/Interface/Economy Overlay'
options_order = {'start_with_showeco', 'always_show_mexes', 'mergeCircles', 'new_method', 'drawQueued', 'no_eff_color'}
options = {
	new_method = {
		name = 'New Merging method',
		type = 'bool',
		value = new_method,
		OnChange = function(self)
			new_method = self.value
			HighlightEBuilds = new_method and HighlightEBuildsNEW or HighlightEBuildsOLD
		end,
	},
	start_with_showeco = {
		name = "Start with economy overlay",
		desc = "Game starts with Economy Overlay enabled",
		type = 'bool',
		value = false,
		noHotkey = true,
		OnChange = function(self)
			if (self.value) then
				WG.showeco = self.value
			end
		end,
	},
	always_show_mexes = {
		name = "Always show Mexes",
		desc = "Show metal extractors even when the full economy overlay is not enabled.",
		type = 'bool',
		value = true,
		OnChange = function(self)
			WG.showeco_always_mexes = self.value
		end,
	},
	mergeCircles = {
		name = "Draw merged grid circles",
		desc = "Merge overlapping grid circle visualisation. Does not work on older hardware and should automatically disable.",
		type = 'bool',
		value = true,
		OnChange = ForceRedraw,
	},
	drawQueued = {
		name = "Draw grid in queue",
		desc = "Shows the grid of not-yet constructed buildings in the queue of a selected constructor. Activates only when placing grid structures.",
		type = 'bool',
		value = true,
		OnChange = ForceRedraw,
	},
	no_eff_color = {
		name = 'Unconnected Power Color',
		type = 'colors',
		value = noEffColor,
		OnChange = function(self)
			noEffColor[1], noEffColor[2], noEffColor[3], noEffColor[4] = unpack(self.value)
			ForceRedraw()
		end,
		path = helk_path,
	}
}

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- local functions

local disabledColor = { 0.6,0.7,0.5, drawAlpha}
local placementColor = { 0.6, 0.7, 0.5, drawAlpha} -- drawAlpha on purpose!

local GetGridColor = VFS.Include("LuaUI/Headers/overdrive.lua")

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Unit Handling

local function addUnit(unitID, unitDefID, unitTeam)
	if eBuildDefs[unitDefID] and not pylonByID[unitID] then
		local spec, fullview = spGetSpectatingState()
		spec = spec or fullview
		if spec or spAreTeamsAllied(unitTeam, spGetMyTeamID()) then
			local x,y,z = spGetUnitPosition(unitID)
			pylons.count = pylons.count + 1
			pylons.data[pylons.count] = {unitID = unitID, x = x, y = y, z = z, radius = eBuildDefs[unitDefID]}
			pylonByID[unitID] = pylons.count
		end
	end
end

local function removeUnit(unitID, unitDefID, unitTeam)
	pylons.data[pylonByID[unitID]] = pylons.data[pylons.count]
	pylonByID[pylons.data[pylons.count].unitID] = pylonByID[unitID]
	pylons.data[pylons.count] = nil
	pylons.count = pylons.count - 1
	pylonByID[unitID] = nil
end

function widget:UnitStructureMoved(unitID, unitDefID, newX, newZ)
	if pylonByID[unitID] then
		local unitTeam = Spring.GetUnitTeam(unitID)
		removeUnit(unitID, unitDefID, unitTeam)
		addUnit(unitID, unitDefID, unitTeam)
	end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
	addUnit(unitID, unitDefID, unitTeam)
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if pylonByID[unitID] then
		removeUnit(unitID, unitDefID, unitTeam)
	end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
	addUnit(unitID, unitDefID, unitTeam)
end

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------

local function InitializeUnits()
	pylons = {count = 0, data = {}}
	pylonByID = {}
	local allUnits = Spring.GetAllUnits()
	for i=1, #allUnits do
		local unitID = allUnits[i]
		local unitDefID = spGetUnitDefID(unitID)
		local unitTeam = Spring.GetUnitTeam(unitID)
		widget:UnitCreated(unitID, unitDefID, unitTeam)
	end
end

local prevFullView = false
local prevTeamID = -1

function widget:Update(dt)
	local teamID = Spring.GetMyTeamID()
	local _, fullView = Spring.GetSpectatingState()
	if (fullView ~= prevFullView) or (teamID ~= prevTeamID) then
		InitializeUnits()
	end
	prevFullView = fullView
	prevTeamID = teamID
end

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Drawing

function widget:Initialize()
	options.new_method:OnChange()
	InitializeUnits()
	widget:SelectionChanged(Spring.GetSelectedUnits())
end

function widget:Shutdown()
	gl.DeleteList(drawList or 0)
	gl.DeleteList(disabledDrawList or 0)
end

function widget:GameFrame(f)
	if f%32 == 2 then
		lastFrame = f
	end
end

local function makePylonListVolume(onlyActive, onlyDisabled)
	local drawGroundCircle = options.mergeCircles.value and gl.Utilities.DrawMergedGroundCircle or gl.Utilities.DrawGroundCircle
	local i = 1
	while i <= pylons.count do
		local data = pylons.data[i]
		local unitID = data.unitID
		if spValidUnitID(unitID) then
			local efficiency = spGetUnitRulesParam(unitID, "gridefficiency") or -1
			if efficiency == -1 and not onlyActive then
				glColor(disabledColor)
				drawGroundCircle(data.x, data.z, data.radius)
			elseif efficiency ~= -1 and not onlyDisabled then
				if efficiency == 0 then
					glColor(noEffColor[1], noEffColor[2], noEffColor[3], drawAlpha)
				else
					glColor(GetGridColor(efficiency, drawAlpha))
				end
				
				drawGroundCircle(data.x, data.z, data.radius)
			end
			i = i + 1
		else
			pylons.data[i] = pylons.data[pylons.count]
			pylonByID[pylons.data[i].unitID] = i
			pylons.data[pylons.count] = nil
			pylons.count = pylons.count - 1
		end
	end
	if highlightQueue and not onlyActive and currentSelection then
		for i = 1, #currentSelection do
			local unitID = currentSelection[i]
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and isBuilder[unitDefID] then
				local cmdQueue = Spring.GetCommandQueue(unitID, -1)
				if cmdQueue then
					for i = 1, #cmdQueue do
						local cmd = cmdQueue[i]
						local radius = eBuildDefs[-cmd.id]
						if radius then
							glColor(disabledColor)
							drawGroundCircle(cmd.params[1], cmd.params[3], radius)
						end
					end
				end
				break
			end
		end
	end
	-- Keep clean for everyone after us
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	glColor(1,1,1,1)
end

local colors = setmetatable(
	{},
	{
		__index = function(self, efficiency)
			local color = efficiency == '0.00' and {noEffColor[1], noEffColor[2], noEffColor[3], drawAlpha}
				or efficiency == '-1.00' and disabledColor
				or {unpack(GetGridColor(tonumber(efficiency), drawAlpha))}
			rawset(self, efficiency, color)
			return color
		end
	}

)

local function UpdateStatus()
	local i = 1
	pylons.byColor = {}
	local byColor = pylons.byColor
	local datas = pylons.data
	local len = pylons.count
	local strformat = string.format
	while i <= len do
		local data = datas[i]
		local unitID = data.unitID
		if spValidUnitID(unitID) then
			local efficiency = spGetUnitRulesParam(unitID, "gridefficiency") or -1
			local color = colors[strformat('%.2f',efficiency)]
			local items = byColor[color]
			if not items then
				items = {}
				byColor[color] = items
			end
			items[unitID] = data
			i = i + 1
		else
			datas[i] = datas[len]
			pylonByID[datas[i].unitID] = i
			datas[len] = nil
			len = len - 1
		end
	end
	pylons.count = len
end

local function makePylonListVolumeNEW()
	-- fix map edge extension 2 leaving wrong states
	gl.Culling(false)
	gl.DepthTest(GL.LEQUAL)
	gl.DepthTest(false)
	--
	local drawGroundCircle = gl.Utilities.DrawMergedGroundCircle
	local drawGroundCircles = gl.Utilities.DrawMergedGroundCircles
	local tsize = table.size
	for color, items in pairs(pylons.byColor) do
		gl.Color(color)
		if tsize(items) >= 10 then
			drawGroundCircles(items)
		else
			for i, data in pairs(items) do
				drawGroundCircle(data.x, data.z, data.radius)
			end
		end
	end
	if highlightQueue and currentSelection then
		local spGetCommandQueue = Spring.GetCommandQueue
		for i = 1, #currentSelection do
			local unitID = currentSelection[i]
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and isBuilder[unitDefID] then
				local cmdQueue = spGetCommandQueue(unitID, -1)
				if cmdQueue then
					for i = 1, #cmdQueue do
						local cmd = cmdQueue[i]
						local radius = eBuildDefs[-cmd.id]
						if radius then
							glColor(disabledColor)
							drawGroundCircle(cmd.params[1], cmd.params[3], radius)
						end
					end
				end
				break
			end
		end
	end
	-- Keep clean for everyone after us
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	glColor(1,1,1,1)
end



function HighlightEBuildsOLD()
	-- fix map edge extension 2 leaving wrong states
	gl.Culling(false)
	gl.DepthTest(GL.LEQUAL)
	gl.DepthTest(false)
	--
	if lastDrawnFrame < lastFrame then
		lastDrawnFrame = lastFrame
		if options.mergeCircles.value then
			gl.DeleteList(disabledDrawList or 0)
			disabledDrawList = gl.CreateList(makePylonListVolume, false, true)
			gl.DeleteList(drawList or 0)
			drawList = gl.CreateList(makePylonListVolume, true, false)
		else
			gl.DeleteList(drawList or 0)
			drawList = gl.CreateList(makePylonListVolume)
		end
	end
	gl.CallList(drawList)
	if options.mergeCircles.value then
		gl.CallList(disabledDrawList)
	end
end

function HighlightEBuildsNEW()
	-- fix map edge extension 2 leaving wrong states
	if not (options.mergeCircles.value and gl.Utilities.DrawMergedGroundCircles) then
		return HighlightEBuildsOLD()
	end
	gl.Culling(false)
	gl.DepthTest(GL.LEQUAL)
	gl.DepthTest(false)
	--
	if lastDrawnFrame < lastFrame then
		lastDrawnFrame = lastFrame
		UpdateStatus()
		gl.DeleteList(drawList or 0)
		drawList = gl.CreateList(makePylonListVolumeNEW, options.mergeCircles.value)
	end
	gl.CallList(drawList)
end


local function HighlightPlacement(unitDefID)
	local mx, my = spGetMouseState()
	local _, coords = spTraceScreenRay(mx, my, true, true, false, not floatOnWater[unitDefID])
	if coords then
		local radius = eBuildDefs[unitDefID]
		if (radius ~= 0) then
			local x, _, z = spPos2BuildPos(unitDefID, coords[1], 0, coords[3], spGetBuildFacing())
			glColor(placementColor)
			gl.Utilities.DrawGroundCircle(x,z, radius)
		end
	end
end

function widget:SelectionChanged(selectedUnits)
	-- force regenerating the lists if we've selected a different unit
	currentSelection = selectedUnits
	lastDrawnFrame = 0
end


function widget:DrawWorldPreUnit()
	if Spring.IsGUIHidden() then return end

	local _, cmdID = spGetActiveCommand()  -- show eBuild if it is about to be placed
	if cmdID ~= prevCmdID then
		-- force regenerating the lists if just picked a building to place
		prevCmdID = cmdID
		if cmdID and cmdID < 0 then
			lastDrawnFrame = 0
		end
	end

	local drawQueue, defID
	if cmdID and cmdID<0 and eBuildDefs[-cmdID] then
		defID = -cmdID
		drawQueue = true
	else
		local forceDrawQueue = WG.force_show_queue_grid
		if forceDrawQueue then
			drawQueue = true
			if type(forceDrawQueue) == 'number' then
				defID = eBuildDefs[forceDrawQueue] and forceDrawQueue
			end
		end
	end

	if drawQueue then
		if lastDrawnFrame ~= 0 then
			local commandsCount = 0
			if currentSelection then
				local spGetCommandQueue = Spring.GetCommandQueue
				for i = 1,#currentSelection do
					local unitID = currentSelection[i]
					local unitDefID = spGetUnitDefID(unitID)
					if unitDefID and isBuilder[unitDefID] then
						commandsCount = spGetCommandQueue(unitID, 0)
						break
					end
				end
			end
			if commandsCount ~= lastCommandsCount then
				-- force regenerating the lists if a building was placed/removed
				lastCommandsCount = commandsCount
				lastDrawnFrame = 0
			end
		end
		highlightQueue = options.drawQueued.value
		HighlightEBuilds()
		highlightQueue = false
		if defID then
			HighlightPlacement(defID)
		end
		glColor(1,1,1,1)
		return
	end

	if currentSelection then
		for i = 1, #currentSelection do
			local ud = spGetUnitDefID(currentSelection[i])
			if (eBuildDefs[ud]) then
				HighlightEBuilds()
				glColor(1,1,1,1)
				return
			end
		end
	end

	local showecoMode = WG.showeco
	if showecoMode then
		HighlightEBuilds()
		glColor(1,1,1,1)
		return
	end
end