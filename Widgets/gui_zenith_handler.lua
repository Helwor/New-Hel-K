function widget:GetInfo()
	return {
	name      = "Zenith Handler",
	desc      = "Add UI Button to select and show meteors of your Zeniths",
	author    = "Helwor",
	date      = "Nov 2026",
	license   = "GNU GPL, v2 or later",
	layer     = 1005,
	enabled   = true,  --  loaded by default?
	handler   = true,
	}
end
-- TODO: add power status and toggleable activated status
local debugging = false

local myPlayerID = Spring.GetMyPlayerID()
local zenithDefID = WG.zenithDefID or (UnitDefNames['zenith'] or {id = false}).id
local asteroidDefID = (UnitDefNames['asteroid'] or {id = false}).id
local meteorProductionRate = 36 -- one meteor in a bit more than a second in the current version of zerok (I'm too lazy to find where is that number)

local entries = {}
local blinking = {}
local currentScale
local r_posx, r_posy = 3/4, 3/4
local size = 50
local vsx, vsy = Spring.Orig.GetViewSizes()
local zenithImage, zenithImageBorder
local asteroidImage, asteroidImageBorder



local function GetZenithIcon()
	if zenithImage then
		return
	end
	zenithImage = WG.GetSquareBuildTexture(UnitDefs[zenithDefID])
	zenithImageBorder = WG.GetBuildIconFrame(UnitDefs[zenithDefID])
	asteroidImage = WG.GetSquareBuildTexture(UnitDefs[asteroidDefID])
	asteroidImageBorder = WG.GetBuildIconFrame(UnitDefs[zenithDefID])
end
-- local
-- local posX = vsx * 6/7
local function DestroyEntry(unitID)
	local entry = entries[unitID]
	if not entry then
		return
	end
	entry.ui:Dispose()
	entries[unitID] = nil
	blinking[entry] = nil
end

local function GetZenithTooltip(entry) -- is it really needed
	return 
		(WG.Translate("units", "zenith.description") or "Meteor Controller")
		.. '\n[Click to select, click again to attack]'
		.. '\n' .. (entry.num or "0") .. "/" .. (entry.max)
end

local function ColoredString(entry)
	local num = entry.num
	local max = entry.max
	local r, g
	local b = 0
	if entry.blinkingPeriod then
		r, g, b = 1, 1, 1
	else
		r = num / max
		if num > max / 2 then
			g = 1 - r
			r = 1
		else
			g = 1
		end
	end
	local m = math.max
	local f = math.floor
	return string.char(255, m(f(r*255 + 0.5), 1), m(f(g*255 + 0.5), 1), m(f(b*255 + 0.5), 1)) .. num
end

local function Debug(entry)
	Echo("entry.ui.MouseDown:"..tostring(entry.ui.MouseDown))
	local realMouseDown = entry.ui.MouseDown
	if realMouseDown then
		entry.ui.MouseDown = function(self, x, y)
			Echo('Win MD', x, y)
			return realMouseDown(self, x, y)
		end
	end

	Echo("entry.ui.NCMouseDown:"..tostring(entry.ui.NCMouseDown))
	local realNCMouseDown = entry.ui.NCMouseDown
	if realNCMouseDown then
		entry.ui.NCMouseDown = function(self, x, y)
			Echo('Win NC MD', x, y)
			return realNCMouseDown(self, x, y)
		end
	end
	Echo("entry.ui.NCMouseDownPostChildren:"..tostring(entry.ui.NCMouseDownPostChildren))
	local realNCMouseDownPostChildren = entry.ui.NCMouseDownPostChildren
	if realNCMouseDownPostChildren then
		entry.ui.NCMouseDownPostChildren = function(self, x, y)
			Echo('Win NC MD PC', x, y)
			return realNCMouseDownPostChildren(self, x, y)
		end
	end
	entry.ui.OnMouseDown[1] = function(self, x, y) Echo('Win OMD', x, y) end

	--------------------------
	Echo("entry.ui.children[1].MouseDown:"..tostring(entry.ui.children[1].MouseDown))
	local realMouseDown = entry.ui.children[1].MouseDown
	if realMouseDown then
		entry.ui.children[1].MouseDown = function(self, x, y)
			Echo('Button MD', x, y)
			return realMouseDown(self, x, y)
		end
	end

	Echo("entry.ui.children[1].NCMouseDown:"..tostring(entry.ui.children[1].NCMouseDown))
	local realNCMouseDown = entry.ui.children[1].NCMouseDown
	if realNCMouseDown then
		entry.ui.children[1].NCMouseDown = function(self, x, y)
			Echo('Button NC MD', x, y)
			return realNCMouseDown(self, x, y)
		end
	end
	Echo("entry.ui.children[1].NCMouseDownPostChildren:"..tostring(entry.ui.children[1].NCMouseDownPostChildren))
	local realNCMouseDownPostChildren = entry.ui.children[1].NCMouseDownPostChildren
	if realNCMouseDownPostChildren then
		entry.ui.children[1].NCMouseDownPostChildren = function(self, x, y)
			Echo('Button NC MD PC', x, y)
			return realNCMouseDownPostChildren(self, x, y)
		end
	end
	entry.ui.children[1].OnMouseDown[1] = function(self, x, y) Echo('Button OMD', x, y) end

end

local function UpdateButton(entry)
	local lastnum = entry.num
	entry.num = tonumber(Spring.GetUnitRulesParam(entry.unitID, "meteorsControlled") or 0)
	entry.text:SetCaption(ColoredString(entry))
	local blink = (entry.num >= entry.max * 0.97)
	if blink then
		if not blinking[entry] then
			blinking[entry] = true
			entry.blinkingPeriod = false
		end
	else
		blinking[entry] = nil
		entry.blinkingPeriod = false
	end
	if lastnum ~= entry.num and entry.button.state.hovered then
		entry.button.tooltip = GetZenithTooltip(entry)
	end
end

local function CreateEntry(unitID)
	if entries[unitID] then
		return
	end
	local entry = {
		unitID = unitID,
		num = -1,
		max = tonumber(Spring.GetUnitRulesParam(unitID, "meteorsControlledMax") or 300),
		ui = nil,
		button = nil,
		text = nil,
		blinkingPeriod = false,

	}
	local isFirst = not next(entries)
	local count = 1
	for _ in pairs(entries) do
		count = count + 1
	end
	local scale = WG.uiScale
	local x, y, w, h = vsx * r_posx, vsy * r_posy, size, size
	local at = 1
	while count > at do
		if x + size * 2.2 > vsx then
			x, y = vsx * r_posx, vsy * r_posy
			y = y - size * 1.2
		else
			x = x + size + size*0.2
		end
		at = at + 1
	end
	entry.ui = WG.Chili.Window:New{ -- has to be in window for teakDraggable/tweakResizable to work
		name   = 'zenith_winbutton_' .. count,
		x      = x / scale,
		y      = y / scale,
		width  = w / scale,
		height = h / scale,
		padding = { 0, 0, 0, 0 },
		color = {0,0,0,0},
		-- tweakDragUseGrip = true,
		tweakDraggable   = true,
		tweakResizable   = true,
		dockable = true, -- to memorize position actually
		resizable = false,
		draggable = false,
		------- Fix Tweak Drag when window is covered by a entry
		-- SEQUENCE: window MD => window NC MD => window OMD
			-- if not above a entry => window NC MD PC => CAN TWEAK DRAG
			-- if hovering a entry => entry MD => entry OMD => entry will eat the click ANYWAY, CANNOT TWEAK DRAG
		-- FIX: in window OMD => Set disableChildrenHitTest when in Tweak
		--      window OMU => (bug) need to recover children hit test else window will stop triggereing OMD when mouse is over entry
		OnMouseDown = {
			function(self, x, y)
				self.disableChildrenHitTest = widgetHandler.tweakMode
			end
		},
		OnMouseUp = {
			function(self, x, y)
				self.disableChildrenHitTest = false
			end
		},
		------
		parent = WG.Chili.Screen0,
		children = {
			WG.Chili.Button:New{
				x      = '0%',
				y      = '0%',
				width  = debugging and '50%' or '100%',
				height = debugging and '50%' or '100%',
				padding = { 0, 0, 0, 0 },
				backgroundColor = {0.8,0.5,0,1},
				focusColor = {0.9,0.8,0.0,1},
				pressBackgroundColor = {1,0,0,1},
				color = {0,0,0,0},
				tooltip = '',
				OnMouseOver = {
					function(self)
						self.tooltip = GetZenithTooltip(entry)
					end
				},
				OnClick = {
					function(self, x, y)
						if debugging then
							Echo('Button On Click', x, y)
						else
							if Spring.IsUnitSelected(unitID) then
								Spring.SetActiveCommand('Attack')
							else
								Spring.SelectUnit(unitID)
							end
						end
					end
				},
				children = {
					WG.Chili.Image:New{
						x = 0,
						y = 0,
						width = "100%",
						height = "100%",
						file = zenithImage,
						file2 = zenithImageBorder,
						padding = { 0, 0, 0, 0 },
						children = {
							WG.Chili.Image:New{
								x = '0%',
								y = '60%',
								width = "40%",
								height = "40%",
								file = asteroidImage,
								file2 = asteroidImageBorder,
							},
							WG.Chili.Label:New{
								x = '25%',
								y = '75%',
								width = '70%',
								height = '100%',
								align = 'center',
								-- valign = 'top',
								caption = '100',
								font = {
									-- color = {1,0.5,0,1},
									outline = true,
									autoOutlineColor = false,
									outlineWidth = 5,
									shadow = false,
								},
							}
						}
					}
				},
			},
		},
	}

	entry.unitID = unitID
	entry.button = entry.ui.children[1]
	entry.text = entry.button.children[1].children[2]
	entries[unitID] = entry
	UpdateButton(entry)

	if debugging then
		Debug(entry)
	end

end
function widget:GameFrame(f)
	if f%meteorProductionRate == 0 then
		for unitID, entry in pairs(entries) do
			UpdateButton(entry)
		end
	end
end

local time = 0
local blinkTimePeriod = 0.5
function widget:Update(dt)
	time = time + dt
	if time > blinkTimePeriod * 2 then
		time = 0
	end
	local blinkingPeriod = time < blinkTimePeriod
	for entry in pairs(blinking) do
		if entry.blinkingPeriod ~= blinkingPeriod then
			entry.blinkingPeriod = blinkingPeriod
			entry.text:SetCaption(ColoredString(entry))
		end
	end
end

function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		local newTeamID = Spring.GetMyTeamID()
		if newTeamID ~= myTeamID then
			widget:Shutdown()
			widget:Initialize()
		end
	end
end

function widget:UnitCreated(unitID, defID, teamID)
	if defID == zenithDefID and teamID == myTeamID then
		CreateEntry(unitID)
	end
end
widget.UnitGiven = widget.UnitCreated

function widget:UnitDestroyed(unitID, defID, teamID)
	if defID == zenithDefID and teamID == myTeamID then
		DestroyEntry(unitID)
		return
	end
end
widget.UnitTaken = widget.UnitCreated

function widget:Initialize()
	if not (zenithDefID) then
		widgetHandler:RemoveWidget(widget)
		widget.status = 'Game doesn\t have zenith unit'
		Echo('['..widget.GetInfo().name .. ']: ' .. 'Shutting down, ' .. widget.status)
		return
	end
	GetZenithIcon()
	myTeamID = Spring.GetMyTeamID()
	currentScale = WG.uiScale
	for i, unitID in ipairs(Spring.GetTeamUnitsByDefs(myTeamID, zenithDefID)) do
		CreateEntry(unitID)
	end
 
end

function widget:ViewResize(x, y) -- adapt to scale but not to change of resolution FIXME? idk
	if currentScale ~= WG.uiScale then
		local scaleChange = currentScale / WG.uiScale
		for unitID, entry in pairs(entries) do
			local ui = entry.ui
			ui:SetPos(ui.x * scaleChange, ui.y * scaleChange, ui.width * scaleChange, ui.height * scaleChange)
		end
		currentScale = WG.uiScale
	end
end

function widget:Shutdown()
	for unitID, entry in pairs(entries) do
		DestroyEntry(unitID)
	end
end