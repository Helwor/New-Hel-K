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
-- TODO: add power status and toggleable activated status, change color of button when selected, shift click should add selection
local debugging = false
local Debug -- function written at the end
local myPlayerID = Spring.GetMyPlayerID()
local zenithDefID = WG.zenithDefID or (UnitDefNames['zenith'] or {id = false}).id
local asteroidDefID = (UnitDefNames['asteroid'] or {id = false}).id
local meteorProductionRate = 36 -- one meteor in a bit more than a second in the current version of zerok TODO (I'm too lazy to find where is that number)
local powerTexture = 'Luaui/Images/visible_energy.png'
local imageDir = 'LuaUI/Images/commands/'
local texOn, texOff = imageDir .. 'states/on.png', imageDir .. 'states/off.png'
local CMD_WANT_ONOFF = Spring.Utilities.CMD.WANT_ONOFF

local entries = {}
local blinking = {}
local byid = {}
local currentScale
local r_posx, r_posy = 3/4, 3/4
local size = 50
local vsx, vsy = Spring.Orig.GetViewSizes()
local zenithImage, zenithImageBorder
local asteroidImage, asteroidImageBorder
local powerNeeded

local function GetZenithInfo()
	if zenithImage then
		return
	end
	local zenithDef = UnitDefs[zenithDefID]
	local asteroidDef = UnitDefs[asteroidDefID]
	zenithImage = WG.GetSquareBuildTexture(zenithDef)
	zenithImageBorder = WG.GetBuildIconFrame(zenithDef)
	asteroidImage = WG.GetSquareBuildTexture(asteroidDef)
	asteroidImageBorder = WG.GetBuildIconFrame(asteroidDef)
	powerNeeded = tonumber(zenithDef.customParams.neededlink)
	local weap = zenithDef.weapons[1]
	local weapDef = weap and WeaponDefs[weap.weaponDef]
	if weapDef and weapDef.reload > 1 then
		meteorProductionRate = math.floor(weapDef.reload * 30 + 0.5)
	end
end

local function GetEntry(unitID)
	local index
	for i, entry in pairs(entries) do
		if entry.unitID == unitID then
			return entry
		end
	end
end

local function GetAvailableIndex()
	local size = table.size(entries)
	for i = 1, size do
		if not entries[i] then
			return i
		end
	end
	return size + 1
end

-- local
-- local posX = vsx * 6/7
local function DestroyEntry(unitID)

	if not byid[unitID] then
		return
	end
	local entry = byid[unitID]
	entry.win:Dispose()
	entries[entry.index] = nil
	byid[unitID] = nil
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



local UpdateButtonColor
do	
	-- background
	local s_bgR, s_bgG, s_bgB   = 0.8, 0.5, 0
	local r_bgR, r_bgG, r_bgB   = 0,   0.8, 0
	local g_bgR, g_bgG, g_bgB   = 0.8, 0.8, 0.8
	local o_bgR, o_bgG, o_bgB
	-- focus
	local s_fR, s_fG, s_fB      = 0.9, 0.8, 0
	local r_fR, r_fG, r_fB      = 0,   1,   0
	local g_fR, g_fG, g_fB      = 0.9, 0.9, 0.9
	local o_fR, o_fG, o_fB
	-- press
	local s_pR, s_pG, s_pB      = 1,   0,   0
	local r_pR, r_pG, r_pB      = 0,   1,   0
	local g_pR, g_pG, g_pB      = 1,   1,   1
	local o_pR, o_pG, o_pB
	function UpdateButtonColor(entry)
		local button = entry.button
		local bgCol, focusCol, pressCol = button.backgroundColor, button.focusColor, button.pressBackgroundColor
		if not o_bgR then
			o_bgR, o_bgG, o_bgB = unpack(bgCol)
			o_fR,  o_fG,  o_fB = unpack(focusCol)
			o_pR,  o_pG,  o_pB = unpack(pressCol)
		end
		if entry.stunned then
			bgCol[1], bgCol[2], bgCol[3]          = g_bgR, g_bgG, g_bgB
			focusCol[1], focusCol[2], focusCol[3] = g_fR,  g_fG , g_fB
			pressCol[1], pressCol[2], pressCol[3] = g_pR,  g_pG , g_pB
		elseif entry.working then
			bgCol[1], bgCol[2], bgCol[3]          = r_bgR, r_bgG, r_bgB
			focusCol[1], focusCol[2], focusCol[3] = r_fR,  r_fG , r_fB
			pressCol[1], pressCol[2], pressCol[3] = r_pR,  r_pG , r_pB
		elseif not entry.powered then
			bgCol[1], bgCol[2], bgCol[3]          = s_bgR, s_bgG, s_bgB
			focusCol[1], focusCol[2], focusCol[3] = s_fR,  s_fG , s_fB
			pressCol[1], pressCol[2], pressCol[3] = s_pR,  s_pG , s_pB
		else
			bgCol[1], bgCol[2], bgCol[3]          = o_bgR, o_bgG, o_bgB
			focusCol[1], focusCol[2], focusCol[3] = o_fR,  o_fG , o_fB
			pressCol[1], pressCol[2], pressCol[3] = o_pR,  o_pG , o_pB
		end
		entry.button:Invalidate()
	end
end

local function GetOnOffState(unitID)
	local cmdOnOff = Spring.GetUnitCmdDescs(unitID, CMD_WANT_ONOFF)
	local onoff
	if cmdOnOff and cmdOnOff[1] then
		return tonumber(cmdOnOff[1].params[1]) == 1
	end
	return false
end

local function UpdateButton(entry)
	local lastnum = entry.num
	local unitID = entry.unitID
	entry.num = tonumber(Spring.GetUnitRulesParam(unitID, "meteorsControlled") or 0)
	entry.label:SetCaption(ColoredString(entry))
	local active = GetOnOffState(unitID)
	local colorUpdate = false
	local stunned = Spring.GetUnitIsStunned(unitID)
	local powered = Spring.GetUnitRulesParam(unitID, "lowpower") ~= 1
	local working = active and powered and not stunned
	if entry.powered ~= powered then
		entry.power:SetVisibility(not powered)
		entry.powered = powered
		colorUpdate = true
	end
	if entry.working ~= working then
		entry.working = working
		colorUpdate = true
	end
	if entry.active ~= active then
		entry.active = active
		entry.onoff.file = active and texOn or texOff
		-- Echo('active', active, entry.onoff.file)
		entry.onoff:Invalidate()
		colorUpdate = true
	end
	if stunned ~= entry.stunned then
		entry.stunned = stunned
		colorUpdate = true
	end
	if colorUpdate then
		UpdateButtonColor(entry)
	end
	local blink = not stunned and (entry.num >= entry.max * 0.97)
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
	local index = GetAvailableIndex()
	local entry = {
		index = index,
		unitID = unitID,
		num = -1,
		max = tonumber(Spring.GetUnitRulesParam(unitID, "meteorsControlledMax") or 300),
		win = nil,
		button = nil,
		blinkingPeriod = false,
		powered = nil,
		active = nil,
		stunned = nil,
		working = nil,

		power = nil,-- control
		onoff = nil, -- control
		label = nil, -- control
	}


	local scale = WG.uiScale
	local x, y, w, h = vsx * r_posx, vsy * r_posy, size, size
	local at = 1
	while index > at do
		if x + size * 2.2 > vsx then
			x, y = vsx * r_posx, vsy * r_posy
			y = y - size * 1.2
		else
			x = x + size + size*0.2
		end
		at = at + 1
	end
	entry.win = WG.Chili.Window:New{ -- has to be in window for teakDraggable/tweakResizable to work
		name   = 'zenith_winbutton_' .. index,
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
								Spring.SelectUnit(unitID, select(4, Spring.GetModKeyState()))
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
								x = '1%',
								y = '5%',
								width = "30%",
								height = "30%",
								file = powerTexture,
							},
							WG.Chili.Image:New{
								x = '70%',
								y = '5%',
								width = "30%",
								height = "30%",
								file = texOn,
							},
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

	entry.button = entry.win.children[1]
	entry.power = entry.button.children[1].children[1]
	entry.onoff = entry.button.children[1].children[2]
	entry.label = entry.button.children[1].children[4]
	entries[index] = entry
	byid[unitID] = entry

	UpdateButton(entry)

	if debugging then
		Debug(entry)
	end

end
function widget:GameFrame(f)
	if f%meteorProductionRate == 0 then
		for index, entry in pairs(entries) do
			UpdateButton(entry)
		end
	end
end

local time = 0
local alltime = 0
local pseudoFrame = 0
local blinkTimePeriod = 0.5
function widget:Update(dt)
	alltime = alltime + dt
	time = time + dt
	if time > blinkTimePeriod * 2 then
		time = 0
	end
	if select(3, Spring.GetGameSpeed()) then
		local pframe = math.modf(alltime * 30)
		if pframe ~= pseudoFrame then
			widget:GameFrame(pframe)
			pseudoFrame = pframe
		end
	end
	local blinkingPeriod = time < blinkTimePeriod
	for entry in pairs(blinking) do
		if entry.blinkingPeriod ~= blinkingPeriod then
			entry.blinkingPeriod = blinkingPeriod
			entry.label:SetCaption(ColoredString(entry))
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

function widget:UnitFinished(unitID, defID, teamID)
	if defID == zenithDefID and teamID == myTeamID then
		CreateEntry(unitID)
	end
end

function widget:UnitGiven(unitID, defID, teamID)
	if defID == zenithDefID and teamID == myTeamID then
		local bp = select(5, Spring.GetUnitHealth(unitID))
		if (bp or 0) >= 1 then
			CreateEntry(unitID)
		end
	end
end

function widget:UnitTaken(unitID, defID, teamID)
	if defID == zenithDefID and teamID == myTeamID then
		local bp = select(5, Spring.GetUnitHealth(unitID))
		if (bp or 0) >= 1 then
			DestroyEntry(unitID)
		end
	end
end

function widget:UnitDestroyed(unitID, defID, teamID)
	if defID == zenithDefID and teamID == myTeamID then
		DestroyEntry(unitID)
		return
	end
end
widget.UnitReverseBuilt = widget.UnitDestroyed


function widget:Initialize()
	if not (zenithDefID) then
		widgetHandler:RemoveWidget(widget)
		widget.status = 'Game doesn\t have zenith unit'
		Echo('['..widget.GetInfo().name .. ']: ' .. 'Shutting down, ' .. widget.status)
		return
	end
	GetZenithInfo()
	myTeamID = Spring.GetMyTeamID()
	currentScale = WG.uiScale
	for i, unitID in ipairs(Spring.GetTeamUnitsByDefs(myTeamID, zenithDefID)) do
		local bp = select(5, Spring.GetUnitHealth(unitID))
		if (bp or 0) >= 1 then
			CreateEntry(unitID)
		end
	end
 
end

function widget:ViewResize(x, y) -- adapt to scale but not to change of resolution FIXME? idk
	if currentScale ~= WG.uiScale then
		local scaleChange = currentScale / WG.uiScale
		for index, entry in pairs(entries) do
			local win = entry.win
			win:SetPos(win.x * scaleChange, win.y * scaleChange, win.width * scaleChange, win.height * scaleChange)
		end
		currentScale = WG.uiScale
	end
end

function widget:Shutdown()
	for index, entry in pairs(entries) do
		DestroyEntry(entry.unitID)
	end
end

f.DebugWidget(widget)

-----------------------


function Debug(entry)
	Echo("entry.win.MouseDown:"..tostring(entry.win.MouseDown))
	local realMouseDown = entry.win.MouseDown
	if realMouseDown then
		entry.win.MouseDown = function(self, x, y)
			Echo('Win MD', x, y)
			return realMouseDown(self, x, y)
		end
	end

	Echo("entry.win.NCMouseDown:"..tostring(entry.win.NCMouseDown))
	local realNCMouseDown = entry.win.NCMouseDown
	if realNCMouseDown then
		entry.win.NCMouseDown = function(self, x, y)
			Echo('Win NC MD', x, y)
			return realNCMouseDown(self, x, y)
		end
	end
	Echo("entry.win.NCMouseDownPostChildren:"..tostring(entry.win.NCMouseDownPostChildren))
	local realNCMouseDownPostChildren = entry.win.NCMouseDownPostChildren
	if realNCMouseDownPostChildren then
		entry.win.NCMouseDownPostChildren = function(self, x, y)
			Echo('Win NC MD PC', x, y)
			return realNCMouseDownPostChildren(self, x, y)
		end
	end
	entry.win.OnMouseDown[1] = function(self, x, y) Echo('Win OMD', x, y) end

	--------------------------
	Echo("entry.win.children[1].MouseDown:"..tostring(entry.win.children[1].MouseDown))
	local realMouseDown = entry.win.children[1].MouseDown
	if realMouseDown then
		entry.win.children[1].MouseDown = function(self, x, y)
			Echo('Button MD', x, y)
			return realMouseDown(self, x, y)
		end
	end

	Echo("entry.win.children[1].NCMouseDown:"..tostring(entry.win.children[1].NCMouseDown))
	local realNCMouseDown = entry.win.children[1].NCMouseDown
	if realNCMouseDown then
		entry.win.children[1].NCMouseDown = function(self, x, y)
			Echo('Button NC MD', x, y)
			return realNCMouseDown(self, x, y)
		end
	end
	Echo("entry.win.children[1].NCMouseDownPostChildren:"..tostring(entry.win.children[1].NCMouseDownPostChildren))
	local realNCMouseDownPostChildren = entry.win.children[1].NCMouseDownPostChildren
	if realNCMouseDownPostChildren then
		entry.win.children[1].NCMouseDownPostChildren = function(self, x, y)
			Echo('Button NC MD PC', x, y)
			return realNCMouseDownPostChildren(self, x, y)
		end
	end
	entry.win.children[1].OnMouseDown[1] = function(self, x, y) Echo('Button OMD', x, y) end
end
