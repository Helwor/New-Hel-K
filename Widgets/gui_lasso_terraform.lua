-- Hel-k Improvement
	-- work on edge of map, (better with -ClampedMouseMove.lua)
	-- ignore UI when needed
	-- better text visibility
	-- tell angle of ramp
	-- fix lasso wrong behaviour, mouse now trace the tip of the wall instead of the footprint
	-- lasso better understandable with double line (CAN BE IMPROVED)
	-- lasso-ramp (WIP enable TRY_LASSORAMP, mouse movement need to be VERY FAST, push ALT once after the lasso is done)
	-- optimizations/code readability
	-- minRampWidth can be small as 24

function widget:GetInfo()
	return {
		name      = "Lasso Terraform GUI",
		desc      = "Interface for lasso terraform.",
		author    = "Google Frog",
		version   = "v1",
		date      = "Nov, 2009",
		license   = "GNU GPL, v2 or later",
		layer     = 999, -- Before Chili
		enabled   = true,
		handler   = true,
	}
end
local Echo = Spring.Echo
include("keysym.lua")

--------------------------------------------------------------------------------
-- Speedups
--------------------------------------------------------------------------------

local osclock           = os.clock

local GL_LINE_STRIP      = GL.LINE_STRIP
local GL_LINES           = GL.LINES
local glVertex           = gl.Vertex
local glLineStipple      = gl.LineStipple
local glLineWidth        = gl.LineWidth
local glColor            = gl.Color
local glBeginEnd         = gl.BeginEnd
local glPushMatrix       = gl.PushMatrix
local glPopMatrix        = gl.PopMatrix
local glScale            = gl.Scale
local glTranslate        = gl.Translate
local glLoadIdentity     = gl.LoadIdentity
local glCallList         = gl.CallList
local glCreateList       = gl.CreateList
local glDepthTest        = gl.DepthTest
local glBillboard        = gl.Billboard
local glText             = gl.Text

local spGetActiveCommand = Spring.GetActiveCommand
local spSetActiveCommand = Spring.SetActiveCommand
local spGetMouseState    = Spring.GetMouseState

local spIsAboveMiniMap        = Spring.IsAboveMiniMap --
--local spGetMiniMapGeometry  = (Spring.GetMiniMapGeometry or Spring.GetMouseMiniMapState)

local spGetSelectedUnits    = Spring.GetSelectedUnits

local spGiveOrder           = Spring.GiveOrder
local spGetUnitDefID        = Spring.GetUnitDefID
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetModKeyState      = Spring.GetModKeyState
local spGetUnitBuildFacing  = Spring.GetUnitBuildFacing
local spGetGameFrame        = Spring.GetGameFrame

local spTraceScreenRay      = Spring.TraceScreenRay
local spGetGroundHeight     = Spring.GetGroundHeight
local spGetCurrentTooltip   = Spring.GetCurrentTooltip

local spSendCommands        = Spring.SendCommands

local mapWidth, mapHeight   = Game.mapSizeX, Game.mapSizeZ
local maxUnits = Game.maxUnits

local st_find = string.find

local sqrt  = math.sqrt
local floor = math.floor
local ceil  = math.ceil
local abs   = math.abs
local modf  = math.modf
local string_format = string.format

-- command IDs
VFS.Include("LuaRules/Configs/customcmds.h.lua")

local Grid = 16 -- grid size, do not change without other changes.

---------------------------------
-- Epic Menu
---------------------------------
local HOTKEY_PATH = 'Hotkeys/Construction'

options_path = 'Settings/Interface/Building Placement'
options_order = {'catlabel', 'structure_holdMouse', 'structure_altSelect', 'staticMouseTime', 'staticMouseThreshold', 'label_preset', 'text_hotkey_level', 'text_hotkey_raise'}
options = {
	catlabel = {
		name = 'Build Height',
		type = 'label',
	},
	structure_holdMouse = {
		name = "Terraform by holding mouse click",
		type = "bool",
		value = false, --[[ disabled by default because it is easy to accidentally enable this UI;
							having your mouse anchored to a spot on your screen because you click
							and hold for too long (likely to happen if you want to line build, or
							are considering options) is really bad if you don't know what is coming ]]
		desc = "When enabled, holding down the left mouse button while placing a structure will enter height selection mode.",
	},
	structure_altSelect = {
		name = "Terraform by selecting with Alt",
		type = "bool",
		value = false,
		desc = "When enabled, holding Alt while selecting a build option (either on the command card or with a hotkey) will cause height selection mode when the structure is placed.",
	},
	staticMouseTime = {
		name = "Structure Terraform Press Time",
		type = "number",
		value = 1, min = 0, max = 10, step = 0.05,
	},
	staticMouseThreshold = {
		name = "Mouse drag threshold",
		type = "number",
		value = 20, min = 0, max = 400, step = 1,
		desc = "Dragging the mouse more than this many pixels to start registering as a mouse movement.",
	},
	label_preset = {
		type = 'label',
		name = 'Terraform Preset Hotkeys',
		path = HOTKEY_PATH
	},
	text_hotkey_level = {
		name = 'Level Presets',
		type = 'text',
		value = "These buttons can be bound to issue Level commands without the height selection step. Each preset is associated to a sliderbar which determines the height. The first four defaults (0, -8, -20, -24) block ships, let all units pass, block some units, and block land units.",
		path = HOTKEY_PATH .. "/Level",
	},
	text_hotkey_raise = {
		name = 'Raise Presets',
		type = 'text',
		value = "These buttons can be bound to issue Raise commands without the height adjustment step. Each preset is associated to a sliderbar which determines the amount raised or lowered. The first four values block vehicles (12, -12) and bots (24, -30).",
		path = HOTKEY_PATH .. "/Raise",
	},
}

---------------------------------
---------------------------------
-- Terraform hotkey presets

local hotkeyDefaults = {
	levelPresets = {0, -8, -20, -24},
	levelTypePreset = {0, 0, 0, 0},
	raisePresets = {12, 24, 54, 240, -120, 96},
	raiseTypePreset = {1, 1, 1, 0, 0, 1},
	levelCursorHotkey = {"alt+g"},
	raiseHotkey = {"alt+v", "alt+b", "alt+n", "alt+h", "alt+j", "alt+m"},
}

---------------------------------
-- Config
---------------------------------

-- for command canceling when the command has been given and shift is de-pressed
local originalCommandGiven = false

-- max difference of height around terraforming, Makes Shraka Pyramids. Not used
local maxHeightDifference = 30

-- elmos of height that correspond to a 1 veritcal pixel of mouse movement during height choosing
local mouseSensitivity = 2

-- snap to Y grid for raise
local heightSnap = 12

-- max sizes of non-ramp command, reduces slowdown MUST AGREE WITH GADGET VALUES
local maxAreaSize = 2000 -- max width or length
local maxWallPoints = 700 -- max points that makeup a wall

-- bounding ramp dimensions, reduces slowdown MUST AGREE WITH GADGET VALUES
local maxRampLength = 3000
local maxRampWidth = 800
local minRampLength = 64
local minRampWidth = 24 -- (ori 48) 24 is actually acceptable

local startRampWidth = 60

-- max slope of certain units, changes ramp colour
local botPathingGrad = 1.375
local vehPathingGrad = 0.498

-- Colours used during height choosing for level and raise
local negVolume   = {1, 0, 0, 0.1} -- negative volume
local posVolume   = {0, 1, 0, 0.1} -- posisive volume
local groundGridColor  = {0.3, 0.2, 1, 0.8} -- grid representing new ground height

-- colour of lasso during drawing
local lassoColorGood = {0.2, 1.0, 0.2, 1.0}
local lassoColorBad  = {1.0, 0.2, 0.2, 1.0}
local lassoColorCurrent = lassoColorGood

-- colour of ramp
local vehPathingColor = {0.2, 1.0, 0.2, 1.0}
local botPathingColor = {0.78, .78, 0.39, 1.0}
local noPathingColor = {1.0, 0.2, 0.2, 1.0}

-- cost mult of terra
local costMult = 1
local modOptions = Spring.GetModOptions()
if modOptions.terracostmult then
	costMult = modOptions.terracostmult
end

----------------------------------
-- Global Vars
local TRY_NEWLASSO = true -- working well
local TRY_LASSORAMP = true -- WIP space each points enough
local placingRectangle = false
local drawingLasso = false
local drawingRectangle = false
local drawingRamp = false
local simpleDrawingRamp = false
local setHeight = false
local setLassoHeight = false
local terraform_type = 0 -- 1 = level, 2 = raise, 3 = smooth, 4 = ramp, 5 = restore, 6 = bump

local commandMap = {
	CMD_LEVEL,
	CMD_RAISE,
	CMD_SMOOTH,
	CMD_RAMP,
	CMD_RESTORE
}

local terraTag=-1

local volumeSelection = 0
local totalMouseMove = 0

local currentlyActiveCommand = false
local presetTerraHeight = false
local presetTerraLevelToCursor = false
local mouseBuilding = false

local buildToGive = false
local buildingPress = false

local terraformHeight = 0
local orHeight = 0 -- store ground height
local storedHeight = 0 -- for snap to height
local loop = 0

local point = {}
local points = 0

local drawPoint = {}
local drawPoints = 0
--draw list--
local volumeDraw
local groundGridDraw
local mouseGridDraw
----
local mouseUnit = {id = false}

local mouseX, mouseY

local mexDefID = UnitDefNames.staticmex.id

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Hotkeys

for i = 1, 3 do
	options["level_cursor_radio_" .. i]  = {
		name = 'Level to Cursor Hotkey ' .. i,
		type = 'radioButton',
		path = HOTKEY_PATH .. "/Level",
		value = i - 1,
		items = {
			{key = 0, name = 'Add and Subtract', desc = 'Terraform the entire area to the selected height.'},
			{key = 1, name = 'Only Add', desc = 'Raise lower parts of the terrain up to the selected height.'},
			{key = 2, name = 'Only Subtract', desc = 'Lower high parts of the terrain up to the selected height.'},
		},
		noHotkey = true,
	}
	options_order[#options_order + 1] = "level_cursor_radio_" .. i

	options["level_cursor_button_" .. i] = {
		type = 'button',
		name = 'Level to Cursor Hotkey ' .. i,
		desc = 'Set this hotkey to Level to the height of the terrain at the start of the lasson drawing.',
		path = HOTKEY_PATH .. "/Level",
		hotkey = hotkeyDefaults.levelCursorHotkey[i],
		OnChange = function ()
			local cmdDesc = Spring.GetCmdDescIndex(CMD_LEVEL)
			if cmdDesc then
				Spring.SetActiveCommand(cmdDesc)
				volumeSelection = options["level_cursor_radio_" .. i].value
				presetTerraHeight = 0
				presetTerraLevelToCursor = true
			end
		end,
	}
	options_order[#options_order + 1] = "level_cursor_button_" .. i
end

for i = 1, 10 do
	options["level_type_" .. i]  = {
		name = 'Level Hotkey ' .. i,
		type = 'radioButton',
		path = HOTKEY_PATH .. "/Level",
		value = hotkeyDefaults.levelTypePreset[i] or 0,
		items = {
			{key = 0, name = 'Add and Subtract', desc = 'Terraform the entire area to the selected height.'},
			{key = 1, name = 'Only Add', desc = 'Raise lower parts of the terrain up to the selected height.'},
			{key = 2, name = 'Only Subtract', desc = 'Lower high parts of the terrain up to the selected height.'},
		},
		noHotkey = true,
	}
	options_order[#options_order + 1] = "level_type_" .. i
	
	options["level_value_" .. i] = {
		name = "Level height " .. i,
		type = "number",
		path = HOTKEY_PATH .. "/Level",
		value = hotkeyDefaults.levelPresets[i] or 0,
		min = -400, max = 400, step = 2,
	}
	options_order[#options_order + 1] = "level_value_" .. i
	
	options["level_hotkey_" .. i] = {
		type = 'button',
		name = 'Level Hotkey ' .. i,
		desc = 'Set this hotkey to issue a Level command with the above parameters.',
		path = HOTKEY_PATH .. "/Level",
		OnChange = function ()
			local cmdDesc = Spring.GetCmdDescIndex(CMD_LEVEL)
			if cmdDesc then
				Spring.SetActiveCommand(cmdDesc)
				volumeSelection = options["level_type_" .. i].value
				presetTerraHeight = options["level_value_" .. i].value
			end
		end,
	}
	options_order[#options_order + 1] = "level_hotkey_" .. i
	
	options["raise_type_" .. i]  = {
		name = 'Raise Hotkey ' .. i,
		type = 'radioButton',
		path = HOTKEY_PATH .. "/Raise",
		value = hotkeyDefaults.raiseTypePreset[i] or 0,
		items = {
			{key = 0, name = 'Full', desc = 'Raise or lower the entire area.'},
			{key = 1, name = 'Cull Cliffs', desc = 'Avoid raising sections of the terrain over the edge of cliffs.'},
			{key = 2, name = 'Cull Ridges', desc = 'Avoid lowering sections of the terrain into steep ridges or walls.'},
		},
		noHotkey = true,
	}
	options_order[#options_order + 1] = "raise_type_" .. i
	
	options["raise_value_" .. i] = {
		name = "Raise amount " .. i,
		type = "number",
		path = HOTKEY_PATH .. "/Raise",
		value = hotkeyDefaults.raisePresets[i] or 0,
		min = -400, max = 400, step = 2,
	}
	options_order[#options_order + 1] = "raise_value_" .. i
	
	options["raise_hotkey_" .. i] = {
		type = 'button',
		name = 'Raise Hotkey ' .. i,
		desc = 'Set this hotkey to issue a Raise command with these parameters.',
		path = HOTKEY_PATH .. "/Raise",
		hotkey = hotkeyDefaults.raiseHotkey[i],
		OnChange = function ()
			local cmdDesc = Spring.GetCmdDescIndex(CMD_RAISE)
			if cmdDesc then
				Spring.SetActiveCommand(cmdDesc)
				volumeSelection = options["raise_type_" .. i].value
				presetTerraHeight = options["raise_value_" .. i].value
			end
		end,
	}
	options_order[#options_order + 1] = "raise_hotkey_" .. i
end

--------------------------------------------------------------------------------
-- Command handling and issuing.
--------------------------------------------------------------------------------
local Dist = function(p1, p2)
	return ((p1.x - p2.x)^2 + (p1.z - p2.z)^2) ^0.5
end

local function stopCommand(shiftHeld)
	if not shiftHeld then
		presetTerraHeight = false
		presetTerraLevelToCursor = false
	end
	if not presetTerraHeight then
		volumeSelection = 0
	end
	
	currentlyActiveCommand = false
	drawingLasso = false
	setLassoHeight = false
	lassoRamp = false
	drawingRectangle = false
	setHeight = false
	if (volumeDraw) then
		gl.DeleteList(volumeDraw)
		gl.DeleteList(mouseGridDraw)
	end
	if (groundGridDraw) then
		gl.DeleteList(groundGridDraw)
	end
	volumeDraw = false
	groundGridDraw = false
	mouseGridDraw = false
	placingRectangle = false
	drawingRamp = false
	simpleDrawingRamp = false
	points = 0
	terraform_type = 0
end

local function completelyStopCommand()
	presetTerraHeight = false
	presetTerraLevelToCursor = false
	volumeSelection = 0
	
	currentlyActiveCommand = false
	spSetActiveCommand(nil)
	originalCommandGiven = false
	drawingLasso = false
	setLassoHeight = false
	lassoRamp = false
	drawingRectangle = false
	setHeight = false
	if (volumeDraw) then
		gl.DeleteList(volumeDraw)
		gl.DeleteList(mouseGridDraw)
	end
	if (groundGridDraw) then
		gl.DeleteList(groundGridDraw)
	end
	volumeDraw = false
	groundGridDraw = false
	mouseGridDraw = false
	placingRectangle = false
	drawingRamp = false
	simpleDrawingRamp = false
	points = 0
	terraform_type = 0
end
local function ElevAngle(elev, dis)
	return math.atan2(elev, dis) / math.pi * 180
end



local function SendCommand(constructor)
	local dis, angle
	if lassoRamp then
		-- Echo('new send','points', points)
		if point[2] then
			dis = ((point[2].x - point[1].x)^2 + (point[2].z - point[1].z)^2)^0.5
			angle = ElevAngle(point[1].mouse[2] - point[2].mouse[2], dis)
		end
		while points > 2 do
			-- Echo('CHECK LENGTH',point[1].x, point[1].mouse[2], point[1].z,'-', point[2].x, point[2].mouse[2], point[2].z, '->', dis, 'angle', angle)
			if dis < minRampLength then
				table.remove(point, 2)
				points = points - 1
				dis = ((point[2].x - point[1].x)^2 + (point[2].z - point[1].z)^2)^0.5
				Echo('point #2 dismissed, remaining ' .. points)
			else
				break
			end
		end
		if points == 3 then
			local disNext = ((point[3].x - point[2].x)^2 + (point[3].z - point[2].z)^2)^0.5
			if disNext < minRampLength then
				table.remove(point, 2)
				points = points - 1
				dis = ((point[2].x - point[1].x)^2 + (point[2].z - point[1].z)^2)^0.5
				Echo('remove before last point bc too short')
			end
		end
		if points == 2 and dis < minRampLength then
			Echo('last segment is normal lasso', point[1].x, point[1].z,'-', point[2].x, point[2].z, '->', dis, 'angle', ElevAngle(point[1].mouse[2] - point[2].mouse[2], dis))
			terraform_type = 1
			terraformHeight = point[1].mouse[2]
			END_LASSO_RAMP = true
			lassoRamp = false
		end
		if points < 2 then
			Echo('SINGLE POINT WTF?', points)
			return
		end

		if lassoRamp and terraform_type == 1 then
			terraform_type = 4
			terraformHeight = minRampWidth
		end

	end
	constructor = constructor or spGetSelectedUnits()

	if (#constructor == 0) or (points == 0) then
		return
	end
	
	local commandTag = WG.Terraform_GetNextTag()
	local pointAveX = 0
	local pointAveZ = 0
	
	local a,c,m,s = spGetModKeyState()

	for i = 1, points do
		pointAveX = pointAveX + point[i].x
		pointAveZ = pointAveZ + point[i].z
	end
	pointAveX = pointAveX/points
	pointAveZ = pointAveZ/points
	
	local team = Spring.GetUnitTeam(constructor[1]) or Spring.GetMyTeamID()
	if terraform_type == 4 then
		local params = {}
		params[1] = terraform_type -- 1 = level, 2 = raise, 3 = smooth, 4 = ramp, 5 = restore
		params[2] = team -- teamID of the team doing the terraform
		params[3] = pointAveX
		params[4] = pointAveZ
		params[5] = commandTag
		params[6] = loop -- true or false
		params[7] = terraformHeight -- width of the ramp
		params[8] = points -- how many points there are in the lasso (2 for ramp)
		params[9] = #constructor -- how many constructors are working on it
		params[10] = volumeSelection -- 0 = none, 1 = only raise, 2 = only lower
		local i = 11
		for j = 1, points do
			params[i] = point[j].x
			-- params[i + 1] = point[j].y + (points * 15) + (j == 1 and 5 or 0)
			params[i + 1] = lassoRamp and point[j].mouse[2] or point[j].y
			-- Echo(j, point[j].y, params[i + 1])
			params[i + 2] = point[j].z
			i = i + 3
			if j == 2 and lassoRamp then
				local dis = ((params[i-6] - params[i-3])^2 + (params[i-4] - params[i-1])^2)^0.5
				SEG = SEG + 1
				points = points - 1
				table.remove(point, 1)
				Echo('make ramp seg #' .. SEG, params[i-6], params[i-5], params[i-4], '--', params[i-3], params[i-2], params[i-1],
				 'length', dis, 'angle', ElevAngle(params[i-2] - params[i-5], dis),
				  'verif next height',points>1 and point[j] and point[j].mouse[2],
				  'points remaining', points,
				  'verif length', points, #point)
				break
			end

		end
				
		for j = 1, #constructor do
			params[i] = constructor[j]
			i = i + 1
		end
		
		Spring.GiveOrderToUnit(constructor[1], CMD_TERRAFORM_INTERNAL, params, CMD.OPT_SHIFT)
		if lassoRamp and points > 1 then
			return SendCommand(constructor)
		end
		if s then
			originalCommandGiven = true
		else
			spSetActiveCommand(nil)
			originalCommandGiven = false
		end
	else
		local params = {}
		params[1] = terraform_type
		params[2] = team
		params[3] = pointAveX
		params[4] = pointAveZ
		params[5] = commandTag
		params[6] = loop
		params[7] = terraformHeight
		params[8] = points
		params[9] = #constructor
		params[10] = volumeSelection
		local i = 11
		for j = 1, points do
			params[i] = point[j].x
			params[i + 1] = point[j].z
			if END_LASSO_RAMP then
				-- Echo('make lasso point', params[i], params[i + 1],'height', terraformHeight)
			end
			i = i + 2
		end
		for j = 1, #constructor do
			params[i] = constructor[j]
			i = i + 1
		end
		Spring.GiveOrderToUnit(constructor[1], CMD_TERRAFORM_INTERNAL, params, 0)
		if lassoRamp then
			return SendCommand(constructor)
		elseif END_LASSO_RAMP then
			END_LASSO_RAMP = false
		end
		if s then
			originalCommandGiven = true
		else
			spSetActiveCommand(nil)
			originalCommandGiven = false
		end
	end
	
	-- check whether global build command wants to handle the commands before giving any orders to units.
	local handledExternally = false
	if WG.GlobalBuildCommand and buildToGive then
		handledExternally = WG.GlobalBuildCommand.CommandNotifyRaiseAndBuild(constructor, buildToGive.cmdID, buildToGive.x, terraformHeight, buildToGive.z, buildToGive.facing, s)
	elseif WG.GlobalBuildCommand then
		handledExternally = WG.GlobalBuildCommand.CommandNotifyTF(constructor, s)
	end
	
	if not handledExternally then
		local cmdOpts = {
			alt = a,
			shift = s,
			ctrl = c,
			meta = m,
			coded = (a and CMD.OPT_ALT   or 0)
				  + (m and CMD.OPT_META  or 0)
				  + (s and CMD.OPT_SHIFT or 0)
				  + (c and CMD.OPT_CTRL  or 0)
		}

		local height = Spring.GetGroundHeight(pointAveX, pointAveZ)
		WG.CommandInsert(commandMap[terraform_type], {pointAveX, height, pointAveZ, commandTag}, cmdOpts, 0)

		if buildToGive and currentlyActiveCommand == CMD_LEVEL then
			for i = 1, #constructor do
				WG.CommandInsert(buildToGive.cmdID, {buildToGive.x, 0, buildToGive.z, buildToGive.facing}, cmdOpts, 1)
			end
		end
	end
	buildToGive = false
	points = 0
end

--------------------------------------------------------------------------------
-- Drawing and placement utility function
--------------------------------------------------------------------------------
local clampPos
do
	local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ
	function clampPos(pos)
		if pos then
			local x, z = pos[1], pos[3]
			local changed = false
			if x < 0 then
				x = 0
				changed = true
			elseif x > mapSizeX then
				x = mapSizeX
				changed = true
			end
			if z < 0 then
				z = 0
				changed = true
			elseif z > mapSizeZ then
				z = mapSizeZ
				changed = true
			end
			if changed then
				pos[1], pos[3] = x, z
				pos[2] = spGetGroundHeight(x, z)
			end

		end
		-- Spring.Echo('pos',pos[1], pos[3], math.round(os.clock()))
		return pos
	end
end
local function legalPos(pos)
	return pos and clampPos(pos)
	-- return pos and pos[1] > 0 and pos[3] > 0 and pos[1] < Game.mapSizeX and pos[3] < Game.mapSizeZ
end

local function safeTrace(mx, my, useMinimap, onlyCoords, includeSky, throughWater, offsetHeight, clamp)
	local pos, _
	if clamp then
		if WG.ClampScreenPosToWorld then
			_, _, pos = WG.ClampScreenPosToWorld(mx, my, useMinimap, throughWater, 5, nil, offsetHeight)
			if pos then
				return pos
			end
		end
	end
	local what
	what, pos = spTraceScreenRay(mx, my, useMinimap, onlyCoords, includeSky, throughWater, offsetHeight)
	if pos then
		if what == 'sky' then
			pos[1], pos[2], pos[3] = pos[4], pos[5], pos[6]
		end
		return pos
	end
end
local function GetLassoPos(mx, my, clamp)
	local pos = safeTrace(mx, my, true, false, true, true, TRY_NEWLASSO and orHeight or nil, clamp)
	local mouse
	pos = legalPos(pos)
	if pos then
		if TRY_NEWLASSO then
			mouse = legalPos{pos[4], orHeight, pos[6]}
			mouse[2] = orHeight
			pos = legalPos{pos[4], pos[2], pos[6]}
			-- Echo("mouse[1], Game.mapSizeX is ", mouse[1], Game.mapSizeX)
		end
		local y = pos[2] -- don't know why it looks different but end result is the same (?)
		local y = spGetGroundHeight(pos[1],pos[3])
		pos[2] = y
	end
	return pos, mouse
end
local function AddLassoPos(mx, my, clamp)
	local pos, mouse = GetLassoPos(mx, my, clamp)
	if pos then
		local diffX = abs(point[points].x - pos[1])
		local diffZ = abs(point[points].z - pos[3])
			
		if diffX >= 10 or diffZ >= 10 then
			points = points + 1
			point[points] = {x = pos[1], y = pos[2], z = pos[3], mouse = mouse}
		end
	end
end
local function lineVolumeLevel()
	for i = 1, drawPoints do
		repeat -- emulating continue
			if (terraformHeight < drawPoint[i].ytl) then
				if (volumeSelection == 1) then
					break -- continue
				end
				glColor(negVolume)
			else
				if (volumeSelection == 2) then
					break -- continue
				end
				glColor(posVolume)
			end
			
			for lx = 0,12,4 do
				for lz = 0,12,4 do
					glVertex(drawPoint[i].x+lx ,drawPoint[i].ytl,drawPoint[i].z+lz)
					glVertex(drawPoint[i].x+lx ,terraformHeight,drawPoint[i].z+lz)
				end
			end
		until true --do not repeat
	end
end

local function lineVolumeRaise()

	for i = 1, drawPoints do
		if (terraformHeight < 0) then
			glColor(negVolume)
		else
			glColor(posVolume)
		end
		
		for lx = 2,14,4 do
			for lz = 2,14,4 do
				glVertex(drawPoint[i].x+lx ,drawPoint[i].ytl,drawPoint[i].z+lz)
				glVertex(drawPoint[i].x+lx ,drawPoint[i].ytl + terraformHeight,drawPoint[i].z+lz)
			end
		end
		
	end

end

local function groundGrid()

	for i = 1, drawPoints do
	
		glColor(groundGridColor)
		local x, z = drawPoint[i].x, drawPoint[i].z
		
		glVertex(x, drawPoint[i].ytl, z)
		glVertex(x+Grid, drawPoint[i].ytr, z)

		glVertex(x, drawPoint[i].ytl, z)
		glVertex(x, drawPoint[i].ybl, z+Grid)
		
		if drawPoint[i].Right then
			glVertex(x+16, drawPoint[i].ytr, z)
			glVertex(x+16, drawPoint[i].ybr, z+Grid)
		end
		
		if drawPoint[i].Bottom then
			glVertex(x, drawPoint[i].ybl, z+16)
			glVertex(x+Grid, drawPoint[i].ybr, z+16)
		end
		
	end

end

local function mouseGridLevel()
	for i = 1, drawPoints do
	
		glColor(groundGridColor)
		
		local x, z = drawPoint[i].x, drawPoint[i].z

		glVertex(x, terraformHeight, z)
		glVertex(x+Grid, terraformHeight, z)

		glVertex(x, terraformHeight, z)
		glVertex(x, terraformHeight, z+Grid)
		
		if drawPoint[i].Right then
			glVertex(x+16, terraformHeight, z)
			glVertex(x+16, terraformHeight, z+Grid)
		end
		
		if drawPoint[i].Bottom then
			glVertex(x, terraformHeight, z+16)
			glVertex(x+Grid, terraformHeight, z+16)
		end
		
	end

end

local function mouseGridRaise()
	for i = 1, drawPoints do
	
		glColor(groundGridColor)
		
		local x, z = drawPoint[i].x, drawPoint[i].z

		glVertex(x, drawPoint[i].ytl+terraformHeight, z)
		glVertex(x+Grid, drawPoint[i].ytr+terraformHeight, z)

		glVertex(x, drawPoint[i].ytl+terraformHeight, z)
		glVertex(x, drawPoint[i].ybl+terraformHeight, z+Grid)
		
		if drawPoint[i].Right then
			glVertex(x+16, drawPoint[i].ytr+terraformHeight, z)
			glVertex(x+16, drawPoint[i].ybr+terraformHeight, z+Grid)
		end
		
		if drawPoint[i].Bottom then
			glVertex(x, drawPoint[i].ybl+terraformHeight, z+16)
			glVertex(x+Grid, drawPoint[i].ybr+terraformHeight, z+16)
		end
		
	end

end
local SetBorder
do
	local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
	function SetBorder(gPoint)
		local minx, minz, maxx, maxz = mapX, mapZ, 0, 0
		for _, p in ipairs(gPoint) do
			local x, z = p.x, p.z
			if x < minx then
				minx = x
			end
			if x > maxx then
				maxx = x
			end
			if z < minz then
				minz = z
			end
			if z > maxz then
				maxz = z
			end
		end
		return minx, maxx, minz, maxz
	end
end

local function calculateLinePoints(mPoint, mPoints)
	
	
	local gPoint = {}
	local gPoints = 1
	
	mPoint[1].x = floor((mPoint[1].x+8)/16)*16
	mPoint[1].z = floor((mPoint[1].z+8)/16)*16
	
	local x, z = floor((mPoint[1].x+8)/16)*16, floor((mPoint[1].z+8)/16)*16
	gPoint[1] = {x = x, z = z}

	for i = 2, mPoints, 1 do
		mPoint[i].x = floor((mPoint[i].x+8)/16)*16
		mPoint[i].z = floor((mPoint[i].z+8)/16)*16
		
		local diffX = mPoint[i].x - mPoint[i-1].x
		local diffZ = mPoint[i].z - mPoint[i-1].z
		local a_diffX = abs(diffX)
		local a_diffZ = abs(diffZ)
		
		if a_diffX <= 16 and a_diffZ <= 16 then
			local x, z = mPoint[i].x, mPoint[i].z
			gPoints = gPoints + 1
			gPoint[gPoints] = {x = x, z = z}
		else
			-- prevent holes inbetween points
			if a_diffX > a_diffZ then
				local m = diffZ/diffX
				local sign = diffX/a_diffX
				for j = 0, a_diffX, 16 do
					local x, z = mPoint[i-1].x + j*sign, floor((mPoint[i-1].z + j*m*sign)/16)*16
					gPoints = gPoints + 1
					gPoint[gPoints] = {x = x, z = z}
				end
			else
				local m = diffX/diffZ
				local sign = diffZ/a_diffZ
				for j = 0, a_diffZ, 16 do
					local x, z = floor((mPoint[i-1].x + j*m*sign)/16)*16, mPoint[i-1].z + j*sign
					gPoints = gPoints + 1
					gPoint[gPoints] = {x = x, z = z}
				end
			end
			
		end
	end
	
	if gPoints > maxWallPoints then
		Spring.Echo("Terraform Command Too Large")
		stopCommand()
		return
	end
	local left, right, top, bottom = SetBorder(gPoint)
	local area = {}
	for i = left - 32, right + 32, 16 do
		area[i] = {}

	end

	drawPoint = {}
	drawPoints = 0
	
	for i = 1, gPoints do
		for lx = -16,0,16 do
			for lz = -16,0,16 do
				local x, z = gPoint[i].x, gPoint[i].z
				if not area[x+lx][z+lz] then
					drawPoints = drawPoints + 1
					drawPoint[drawPoints] = {
						x = x+lx,
						z = z+lz,
						ytl = spGetGroundHeight(x+lx,    z+lz),
						ytr = spGetGroundHeight(x+lx+16, z+lz),
						ybl = spGetGroundHeight(x+lx,    z+lz+16),
						ybr = spGetGroundHeight(x+lx+16, z+lz+16),
					}
					area[gPoint[i].x+lx][gPoint[i].z+lz]  = true
				end
			end
		end
	
	end
	
	for i = 1, drawPoints do
		local x, z = drawPoint[i].x, drawPoint[i].z 
		if not area[x+16][z] then
			drawPoint[i].Right = true
		end
		if not area[x][z+16] then
			drawPoint[i].Bottom = true
		end
	end
end

local function calculateAreaPoints(mPoint, mPoints)
	
	local gPoint = {}
	local gPoints = 1
	
	mPoints = mPoints + 1
	mPoint[mPoints] = mPoint[1]
	
	local x, z = floor((mPoint[1].x)/16)*16, floor((mPoint[1].z)/16)*16
	mPoint[1].x = x
	mPoint[1].z = z
	
	gPoint[1] = {x = x,	z = z}
	local lastMx, lastMz = x, z
	for i = 2, mPoints do
		local mx, mz = floor((mPoint[i].x)/16)*16, floor((mPoint[i].z)/16)*16
		mPoint[i].x = mx
		mPoint[i].z = mz
		local diffX = mx - lastMx
		local diffZ = mz - lastMz
		local a_diffX = abs(diffX)
		local a_diffZ = abs(diffZ)
		
		if a_diffX <= 16 and a_diffZ <= 16 then
			gPoints = gPoints + 1
			gPoint[gPoints] = {x = mx, z = mz}
		else
			-- prevent holes inbetween points
			if a_diffX > a_diffZ then
				local m = diffZ/diffX
				local sign = diffX/a_diffX
				for j = 0, a_diffX, 16 do
					gPoints = gPoints + 1
					gPoint[gPoints] = {x = lastMx + j*sign, z = floor((lastMz + j*m*sign)/16)*16}
				end
			else
				local m = diffX/diffZ
				local sign = diffZ/a_diffZ
				for j = 0, a_diffZ, 16 do
					gPoints = gPoints + 1
					gPoint[gPoints] = {x = floor((lastMx + j*m*sign)/16)*16, z = lastMz + j*sign}
				end
			end
		end
		lastMx, lastMz = mx, mz
	end
	local left, right, top, bottom = SetBorder(gPoint)

	if right-left > maxAreaSize or bottom-top > maxAreaSize then
		Spring.Echo("Terraform Command Too Large")
		stopCommand()
		return
	end
	
	local area = {}
	
	for i = left - 32, right + 32, 16 do
		area[i] = {}
	end
	
	for i = 1, gPoints do
		local p = gPoint[i]
		area[p.x][p.z] = 2
	end
	
	for i = left,right,16 do
		local col = area[i]
		for j = top,bottom,16 do
			if col[j] ~= 2 then
				col[j] = 1
			end
		end
	end
	
	for i = left,right,16 do
		local col = area[i]
		if col[top] ~= 2 then
			col[top] = -1
		end
		if col[bottom] ~= 2 then
			col[bottom] = -1
		end
	end
	for i = top,bottom,16 do
		if area[left][i] ~= 2 then
			area[left][i] = -1
		end
		if area[right][i] ~= 2 then
			area[right][i] = -1
		end
	end
	
	local continue = true

	while continue do
		continue = false
		local lastCol = area[left-16]
		local col = area[left]
		local nextCol = area[left+16]
		for i = left,right,16 do
			for j = top,bottom,16 do
				if col[j] == -1 then
					if nextCol[j] == 1 then
						nextCol[j] = -1
						continue = true
					end
					if lastCol[j]  == 1 then
						lastCol[j]  = -1
						continue = true
					end
					if col[j+16] == 1 then
						col[j+16] = -1
						continue = true
					end
					if col[j-16] == 1 then
						col[j-16] = -1
						continue = true
					end
					col[j] = false
				end
			end
			lastCol = col
			col = nextCol
			nextCol = area[i+32]
		end
		
	end

	drawPoint = {}
	drawPoints = 0
	
	for i = left, right, 16 do
		for j = top, bottom, 16 do
			if area[i][j] then
				drawPoints = drawPoints + 1
				drawPoint[drawPoints] = {x = i,z = j,
					ytl = spGetGroundHeight(i,j),
					ytr = spGetGroundHeight(i+16,j),
					ybl = spGetGroundHeight(i,j+16),
					ybr = spGetGroundHeight(i+16,j+16),
				}
			end
		end
	end
	
	for i = 1, drawPoints do
		if not area[drawPoint[i].x+16][drawPoint[i].z] then
			drawPoint[i].Right = true
		end
		if not area[drawPoint[i].x][drawPoint[i].z+16] then
			drawPoint[i].Bottom = true
		end
	end
end

local function SetFixedRectanglePoints(pos)
	if legalPos(pos) then
		local x = floor((pos[1] + 8 - placingRectangle.oddX)/16)*16 + placingRectangle.oddX
		local z = floor((pos[3] + 8 - placingRectangle.oddZ)/16)*16 + placingRectangle.oddZ
		
		point[1].y = spGetGroundHeight(x, z)
		if placingRectangle.floatOnWater and point[1].y < 2 then
			point[1].y = 2
		end
		point[2].x = x - placingRectangle.halfX
		point[2].z = z - placingRectangle.halfZ
		point[3].x = x + placingRectangle.halfX
		point[3].z = z + placingRectangle.halfZ
		
		placingRectangle.legalPos = true
	else
		placingRectangle.legalPos = false
	end
end


--------------------------------------------------------------------------------
-- Mouse/keyboard Callins
--------------------------------------------------------------------------------

local function ResetMouse()
	Spring.WarpMouse(mouseX, mouseY)
end

local function snapToHeight(heightArray, snapHeight, arrayCount)
	local smallest = abs(heightArray[1] - snapHeight)
	local smallestIndex = 1
	for i=2, arrayCount do
		local diff = abs(heightArray[i] - snapHeight)
		if diff < smallest then
			smallest = diff
			smallestIndex = i
		end
	end
	return smallestIndex
end

function widget:MousePress(mx, my, button)
	local screen0 = WG.Chili.Screen0

	if screen0 and screen0.hoveredControl and not setHeight then
		local classname = screen0.hoveredControl.classname
		if not (classname == "control" or classname == "object" or classname == "panel" or classname == "window") then
			return
		end
	end
	if button == 1 and placingRectangle and placingRectangle.legalPos then
		local activeCmdIndex, activeid = spGetActiveCommand()
		local index = Spring.GetCmdDescIndex(CMD_LEVEL)
		if not index then
			return
		end
		spSetActiveCommand(index)
		currentlyActiveCommand = CMD_LEVEL
		
		setHeight = true
		drawingRectangle = false
		placingRectangle = false
		
		mouseX = mx
		mouseY = my
		
		local x1, z1 = point[2].x, point[2].z
		local x2, z2 = point[3].x-1, point[3].z-1
		
		buildToGive = {
			facing = Spring.GetBuildFacing(),
			cmdID = activeid,
			x = (x1 + x2)/2,
			z = (z1 + z2)/2,
		}

		terraformHeight = point[1].y
		storedHeight = point[1].y
		
		points = 5
		point[1] = {x = x1, z = z1}
		point[2] = {x = x1, z = z2}
		point[3] = {x = x2, z = z2}
		point[4] = {x = x2, z = z1}
		point[5] = {x = x1, z = z1}

		loop = 1
		calculateAreaPoints(point,points)
		
		if (groundGridDraw) then
			gl.DeleteList(groundGridDraw);
			groundGridDraw = nil
		end
		groundGridDraw = glCreateList(glBeginEnd, GL_LINES, groundGrid)
	
		if (volumeDraw) then
			gl.DeleteList(volumeDraw); volumeDraw=nil
			gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
		end
		volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeLevel)
		mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridLevel)
		return true
	end
	
	local toolTip = Spring.GetCurrentTooltip()
	if not (toolTip == "" or st_find(toolTip, "Terrain type") or st_find(toolTip, "Metal:")) then
		return false
	end
	
	local activeCmdIndex, activeid = spGetActiveCommand()
	if ((activeid == CMD_LEVEL) or (activeid == CMD_RAISE) or (activeid == CMD_SMOOTH) or (activeid == CMD_RESTORE) or (activeid == CMD_BUMPY))
			and not (setHeight or drawingRectangle or drawingLasso or drawingRamp or simpleDrawingRamp or placingRectangle) then

		if button == 1 then
			if not spIsAboveMiniMap(mx, my) then
		
				
				-- local pos = safeTrace(mx, my, true, false, true, true, nil, true) -- UNCOMMENT WIP WORK WHEN STARTING OUT OF MAP
				local pos = safeTrace(mx, my, true, false, true, true)
				if legalPos(pos) then
					widgetHandler:UpdateWidgetCallIn("DrawWorld", self)
					orHeight = spGetGroundHeight(pos[1],pos[3])
					
					local a,c,m,s = spGetModKeyState()
					local ty, id = spTraceScreenRay(mx, my, false, false, false, true)
					if c and ty == "unit" and c then
						local ud = UnitDefs[spGetUnitDefID(id)]
						--if ud.isImmobile then
						mouseUnit = {id = id, ud = ud}
						drawingRectangle = true
						point[1] = {x = floor((pos[1])/16)*16, y = spGetGroundHeight(pos[1],pos[3]), z = floor((pos[3])/16)*16}
						point[2] = {x = floor((pos[1])/16)*16, y = spGetGroundHeight(pos[1],pos[3]), z = floor((pos[3])/16)*16}
						point[3] = {x = floor((pos[1])/16)*16, y = spGetGroundHeight(pos[1],pos[3]), z = floor((pos[3])/16)*16}
						--end
					elseif a then
						drawingRectangle = true
						point[1] = {x = floor((pos[1])/16)*16, y = spGetGroundHeight(pos[1],pos[3]), z = floor((pos[3])/16)*16}
						point[2] = {x = floor((pos[1])/16)*16, y = spGetGroundHeight(pos[1],pos[3]), z = floor((pos[3])/16)*16}
						point[3] = {x = floor((pos[1])/16)*16, y = spGetGroundHeight(pos[1],pos[3]), z = floor((pos[3])/16)*16}
					else
						drawingLasso = true
						points = 1
						point[1] = {x = pos[1], y = orHeight, z = pos[3], mouse = {pos[1], pos[2], pos[3]}}
					end
					
					if (activeid == CMD_LEVEL) then
						terraform_type = 1
						terraformHeight = point[1].y
						storedHeight = orHeight
					elseif (activeid == CMD_RAISE) then
						terraform_type = 2
						terraformHeight = 0
						storedHeight = 0
					elseif (activeid == CMD_SMOOTH) then
						terraform_type = 3
					elseif (activeid == CMD_RESTORE) then
						terraform_type = 5
					elseif (activeid == CMD_BUMPY) then
						terraform_type = 6
					end
					
					currentlyActiveCommand = activeid
					
					return true
				end
			end
		else
			spSetActiveCommand(nil)
			originalCommandGiven = false
			return true
		end
		
	elseif (activeid == CMD_RAMP) and not (setHeight or drawingRectangle or drawingLasso or drawingRamp or simpleDrawingRamp or placingRectangle) then
		if button == 1 then
			if not spIsAboveMiniMap(mx, my) then
				-- local _, pos = spTraceScreenRay(mx, my, true, false, false, true)
				local pos = safeTrace(mx, my, true, false, true, true)
				if legalPos(pos) then
					local a,c,m,s = spGetModKeyState()
					widgetHandler:UpdateWidgetCallIn("DrawWorld", self)
					orHeight = spGetGroundHeight(pos[1],pos[3])
					
					point[1] = {x = pos[1], y = orHeight, z = pos[3], ground = orHeight}
					point[2] = {x = pos[1], y = point[1].y, z = pos[3], ground = point[1]}
					storedHeight = orHeight
					points = 2
					if c or a then
						drawingRamp = 1
					else
						simpleDrawingRamp = 1
					end
					terraform_type = 4
					terraformHeight = startRampWidth -- width
					mouseX = mx
					mouseY = my
					return true
				end
			end
		end
		
	end
	
	if setHeight and button == 1 then
		SendCommand()
		local a,c,m,s = spGetModKeyState()
		stopCommand(s)
		return true
	end
	
	if drawingRamp == 2 and button == 1 then
		mouseX = mx
		mouseY = my
		drawingRamp = 3
		return true
	end

	if drawingLasso or setHeight or drawingRamp or simpleDrawingRamp or drawingRectangle or placingRectangle then
		if button == 3 then
			completelyStopCommand()
			return true
		end
	end
	
	return false
end

function widget:MouseMove(mx, my, dx, dy, button)
	--local _, pos = spTraceScreenRay(mx, my, true, false, false, true)
	--local normal = select(2, Spring.GetGroundNormal(pos[1], pos[3]))
	--Spring.Echo("normal", normal)
	totalMouseMove = totalMouseMove + math.abs(dx or 0) + math.abs(dy or 0)
	if totalMouseMove < options.staticMouseThreshold.value then
		return
	end

	if drawingLasso then
		if button == 1 then
			local a,c,m,s = spGetModKeyState()
			if not c then
				AddLassoPos(mx, my)
			end
		end
		
		return true
		
	elseif drawingRectangle then

		if button == 1 then
			-- local _, pos = spTraceScreenRay(mx, my, true, false, false, true)
			local pos = safeTrace(mx, my, true, false, true, true)
		
			if legalPos(pos) then
			
				local x = floor((pos[1])/16)*16
				local z = floor((pos[3])/16)*16
				
				if x > point[1].x then
					point[2].x = x+16
					point[3].x = point[1].x
				else
					if x - point[1].x == 0 then
						x = x - 16
					end
					point[2].x = x
					point[3].x = point[1].x+16
				end
				
				if z > point[1].z then
					point[2].z = z+16
					point[3].z = point[1].z
				else
					if z - point[1].z == 0 then
						z = z - 16
					end
					point[2].z = z
					point[3].z = point[1].z+16
				end

				if abs(point[2].x - point[3].x) > maxAreaSize
				or abs(point[2].z - point[3].z) > maxAreaSize then
					lassoColorCurrent = lassoColorBad
				else
					lassoColorCurrent = lassoColorGood
				end
			end
		end
		
		return true
		
	elseif drawingRamp == 1 then
		
		local a,c,m,s = spGetModKeyState()
		if a then
			ResetMouse()
			storedHeight = storedHeight + (my-mouseY)*mouseSensitivity
			local heightArray = {
				-12,
				orHeight,
			}
			point[1].y = heightArray[snapToHeight(heightArray,storedHeight,2)]
		else
			if my ~= mouseY then
				ResetMouse()
				point[1].y = point[1].y + (my-mouseY)*mouseSensitivity
				storedHeight = point[1].y
			end
		end
		
		return true
		
	elseif drawingRamp == 3 then

		local a,c,m,s = spGetModKeyState()
		if a then
			ResetMouse()

			local dis = sqrt((point[1].x-point[2].x)^2 + (point[1].z-point[2].z)^2)
			storedHeight = storedHeight + (my-mouseY)/50*dis*mouseSensitivity
			local heightArray = {
				botPathingGrad*dis+point[1].y,
				vehPathingGrad*dis+point[1].y,
				point[1].y,
				-botPathingGrad*dis+point[1].y,
				-vehPathingGrad*dis+point[1].y,
				-5,
				orHeight,
			}
			point[2].y = heightArray[snapToHeight(heightArray,storedHeight,7)]
		else
			if my ~= mouseY then
				ResetMouse()
				point[2].y = point[2].y + (my-mouseY)*mouseSensitivity
				storedHeight = point[2].y
			end
		end
			
		return true
	
	end
	
	return false
end

local function CheckPlacingRectangle(self)
	if placingRectangle and not placingRectangle.drawing then
		widgetHandler:UpdateWidgetCallIn("DrawWorld", self)
		placingRectangle.drawing = true
	end
	
	if buildToGive and buildToGive.needGameFrame then
		widgetHandler:UpdateWidgetCallIn("GameFrame", self)
		buildToGive.needGameFrame = false
	end
end

function widget:Update(dt)
	if buildingPress and buildingPress.frame then
		buildingPress.frame = buildingPress.frame - dt
	end
	CheckPlacingRectangle(self)
	
	local activeCmdIndex, activeid = spGetActiveCommand()
	if currentlyActiveCommand then
		if activeid ~= currentlyActiveCommand then
			stopCommand()
		end
	end
	
	if setHeight then
		local mx,my = spGetMouseState()
		
		if terraform_type == 1 then
			local a,c,m,s = spGetModKeyState()
			if c then
				-- local _, pos = spTraceScreenRay(mx, my, true, false, false, true)
				local pos = safeTrace(mx, my, true, false, true, true)
				if legalPos(pos) then
					terraformHeight = spGetGroundHeight(pos[1],pos[3])
					storedHeight = terraformHeight
					mouseX = mx
					mouseY = my
				end
			elseif a then
				ResetMouse()
				storedHeight = storedHeight + (my-mouseY)*mouseSensitivity
				local heightArray = {
					-2,
					orHeight,
					-23,
				}
				terraformHeight = heightArray[snapToHeight(heightArray,storedHeight,3)]
			else
				ResetMouse()
				terraformHeight = terraformHeight + (my-mouseY)*mouseSensitivity
				storedHeight = terraformHeight
			end
			if (volumeDraw) then
				gl.DeleteList(volumeDraw); volumeDraw=nil
				gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
			end
			volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeLevel)
			mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridLevel)
		elseif terraform_type == 2 then
			ResetMouse()
			local a,c,m,s = spGetModKeyState()
			if c then
				terraformHeight = 0
				storedHeight = 0
			elseif a then
				storedHeight = storedHeight + (my-mouseY)*mouseSensitivity
				terraformHeight = floor((storedHeight+heightSnap/2)/heightSnap)*heightSnap
			else
				terraformHeight = terraformHeight + (my-mouseY)*mouseSensitivity
				storedHeight = terraformHeight
			end
			if (volumeDraw) then
				gl.DeleteList(volumeDraw); volumeDraw=nil
				gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
			end
			volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeRaise)
			mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridRaise)
		elseif terraform_type == 4 then
			ResetMouse()
			terraformHeight = terraformHeight + (my-mouseY)*mouseSensitivity
			if terraformHeight < minRampWidth then
				terraformHeight = minRampWidth
			end
			if terraformHeight > maxRampWidth then
				terraformHeight = maxRampWidth
			end
		end
	
	elseif drawingRamp == 2 or simpleDrawingRamp == 1 then
		local mx,my = spGetMouseState()
		-- local _, pos = spTraceScreenRay(mx, my, true, false, false, true)
		local pos = safeTrace(mx, my, true, false, true, true)
		if legalPos(pos) then
			local dis = sqrt((point[1].x-pos[1])^2 + (point[1].z-pos[3])^2)
			if dis ~= 0 then
				orHeight = spGetGroundHeight(pos[1],pos[3])
				storedHeight = orHeight
				if dis < minRampLength then
					-- Do not draw really short ramps.
					if dis > minRampLength*0.3 or (point[2].x ~= point[1].x) then
						point[2] = {
							x = point[1].x+minRampLength*(pos[1]-point[1].x)/dis,
							y = orHeight,
							z = point[1].z+minRampLength*(pos[3]-point[1].z)/dis,
							ground = orHeight
						}
					end
				elseif dis > maxRampLength then
					point[2] = {
						x = point[1].x+maxRampLength*(pos[1]-point[1].x)/dis,
						y = orHeight,
						z = point[1].z+maxRampLength*(pos[3]-point[1].z)/dis,
						ground = orHeight
					}
				else
					point[2] = {x = pos[1], y = orHeight, z = pos[3], ground = orHeight}
				end
			end
		end
	elseif placingRectangle then
		local pos
		if (activeid == -mexDefID) and WG.mouseoverMex then
			pos = {WG.mouseoverMex.x, WG.mouseoverMex.y, WG.mouseoverMex.z}
		else
			local mx,my = spGetMouseState()
			-- pos = select(2, spTraceScreenRay(mx, my, true, false, false, not placingRectangle.floatOnWater))
			pos = safeTrace(mx, my, true, false, true, not placingRectangle.floatOnWater)
		end
		
		local facing = Spring.GetBuildFacing()
		local offFacing = (facing == 1 or facing == 3)
		if offFacing ~= placingRectangle.offFacing then
			placingRectangle.halfX, placingRectangle.halfZ = placingRectangle.halfZ, placingRectangle.halfX
			placingRectangle.oddX, placingRectangle.oddZ = placingRectangle.oddZ, placingRectangle.oddX
			placingRectangle.offFacing = offFacing
		end
		
		SetFixedRectanglePoints(pos)
		
		return true
	end
	
	local mx, my, lmb, mmb, rmb = spGetMouseState()
	
	if lmb and activeid and activeid < 0 then
		local pos
		if (activeid == -mexDefID) and WG.mouseoverMex then
			pos = {WG.mouseoverMex.x, WG.mouseoverMex.y, WG.mouseoverMex.z}
		else
			-- pos = select(2, spTraceScreenRay(mx, my, true, false, false, true))
			pos = safeTrace(mx, my, true, false, true, true)
		end
		if pos and legalPos(pos) and options.structure_holdMouse.value then
			if buildingPress then
				if math.abs(pos[1] - buildingPress.pos[1]) >= 4 or math.abs(pos[3] - buildingPress.pos[3]) >= 4 then
					local a,c,m,s = spGetModKeyState()
					if s then
						buildingPress.frame = false
					else
						buildingPress.frame = options.staticMouseTime.value
						buildingPress.pos[1] = pos[1]
						buildingPress.pos[3] = pos[3]
					end
				end
			else
				buildingPress = {pos = pos, frame = options.staticMouseTime.value, unitDefID = -activeid}
			end
		end
	else
		buildingPress = false
	end
	
	if buildingPress and buildingPress.frame and buildingPress.frame < 0 then
		if buildingPress.unitDefID == -activeid then
			WG.Terraform_SetPlacingRectangle(buildingPress.unitDefID)
			CheckPlacingRectangle(self)
			widget:MousePress(mx, my, 1)
		end
	end
end

function widget:MouseRelease(mx, my, button)
	if drawingLasso then
		if button == 1 then
			
			-- local _, pos = spTraceScreenRay(mx, my, true, false, false, true)

			AddLassoPos(mx, my)
	
			if (not presetTerraHeight) and (terraform_type == 1 or terraform_type == 2) then
				setHeight = true
				if drawingLasso then
					drawingLasso = false
					setLassoHeight = true
				end
				mouseX = mx
				mouseY = my
				
				local disSQ = (point[1].x-point[points].x)^2 + (point[1].z-point[points].z)^2
			
				if disSQ < 6400 and points > 10 then
					loop = 1
					calculateAreaPoints(point,points)
					if (groundGridDraw) then gl.DeleteList(groundGridDraw); groundGridDraw=nil end
					groundGridDraw = glCreateList(glBeginEnd, GL_LINES, groundGrid)
				else
					loop = 0
					calculateLinePoints(point,points)
					if (groundGridDraw) then gl.DeleteList(groundGridDraw); groundGridDraw=nil end
					groundGridDraw = glCreateList(glBeginEnd, GL_LINES, groundGrid)
				end
				
				if terraform_type == 1 then
					if (volumeDraw) then
						gl.DeleteList(volumeDraw); volumeDraw=nil
						gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
					end
					volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeLevel)
					mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridLevel)
				elseif terraform_type == 2 then
					if (volumeDraw) then
						gl.DeleteList(volumeDraw); volumeDraw=nil
						gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
					end
					volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeRaise)
					mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridRaise)
				end
			elseif terraform_type == 3 or terraform_type == 5 or terraform_type == 6 or (presetTerraHeight and (terraform_type == 1 or terraform_type == 2)) then
			
				local disSQ = (point[1].x-point[points].x)^2 + (point[1].z-point[points].z)^2
			
				if disSQ < 6400 and points > 10 then
					loop = 1
					calculateAreaPoints(point,points)
					if (groundGridDraw) then gl.DeleteList(groundGridDraw); groundGridDraw=nil end
					groundGridDraw = glCreateList(glBeginEnd, GL_LINES, groundGrid)
				else
					loop = 0
					calculateLinePoints(point,points)
					if (groundGridDraw) then gl.DeleteList(groundGridDraw); groundGridDraw=nil end
					groundGridDraw = glCreateList(glBeginEnd, GL_LINES, groundGrid)
				end
				if points ~= 0 then
					if presetTerraHeight and not presetTerraLevelToCursor then
						terraformHeight = presetTerraHeight
					end
					SendCommand()
				end
				local a,c,m,s = spGetModKeyState()
				stopCommand(s)
			end
			
			return true
		elseif button == 4 or button == 5 then
			stopCommand()
		else
			return true
		end
	elseif drawingRectangle then
	
		if button == 1 then
			--spSetActiveCommand(nil)
			
			if (not presetTerraHeight) and (terraform_type == 1 or terraform_type == 2) then
				setHeight = true
				drawingRectangle = false
				mouseX = mx
				mouseY = my
				
				local x,z
				
				-- local _, pos = spTraceScreenRay(mx, my, true, false, false, true)
				local pos = safeTrace(mx, my, true, false, true, true)
				if legalPos(pos) then
					if mouseUnit.id then
						local ty, id = spTraceScreenRay(mx, my, false, false, false, true)
						if ty == "unit" and id == mouseUnit.id then
							local x,_,z = spGetUnitPosition(mouseUnit.id)
							local face = spGetUnitBuildFacing(mouseUnit.id)
							
							local xsize,ysize
							if (face == 0) or (face == 2) then
								xsize = mouseUnit.ud.xsize*4
								ysize = (mouseUnit.ud.zsize or mouseUnit.ud.ysize)*4
							else
								xsize = (mouseUnit.ud.zsize or mouseUnit.ud.ysize)*4
								ysize = mouseUnit.ud.xsize*4
							end
							
							
							if mouseUnit.ud.isImmobile then
								points = 5
								point[1] = {x = x - xsize - 32, z = z - ysize - 32}
								point[2] = {x = x + xsize + 16, z = point[1].z}
								point[3] = {x = point[2].x, z = z + ysize + 16}
								point[4] = {x = point[1].x, z = point[3].z}
								point[5] = {x =point[1].x, z = point[1].z}
								loop = 1
								calculateAreaPoints(point,points)
							else
								points = 5
								point[1] = {x = x - xsize - 16, z = z - ysize - 16}
								point[2] = {x = x + xsize + 16, z = point[1].z}
								point[3] = {x = point[2].x, z = z + ysize + 16}
								point[4] = {x = point[1].x, z = point[3].z}
								point[5] = {x = point[1].x, z = point[1].z}
								loop = 0
								calculateLinePoints(point,points)
							end
							
							if (groundGridDraw) then
								gl.DeleteList(groundGridDraw);
								groundGridDraw=nil
							end
							groundGridDraw = glCreateList(glBeginEnd, GL_LINES, groundGrid)
							
							if terraform_type == 1 then
								if (volumeDraw) then
									gl.DeleteList(volumeDraw); volumeDraw=nil
									gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
								end
								volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeLevel)
								mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridLevel)
							elseif terraform_type == 2 then
								if (volumeDraw) then
									gl.DeleteList(volumeDraw); volumeDraw=nil
									gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
								end
								volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeRaise)
								mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridRaise)
							end
							
							mouseUnit.id = false
							return true
						end
						
					end
					
					x = floor((pos[1])/16)*16
					z = floor((pos[3])/16)*16
					
					if x - point[1].x == 0 then
						x = x - 16
					end
					if z - point[1].z == 0 then
						z = z - 16
					end
				else
					x = point[2].x
					z = point[2].z
				end
				
				local left, right = math.min(x, point[1].x), math.max(x, point[1].x)
				local top, bottom = math.min(z, point[1].z), math.max(z, point[1].z)
				
				local a,c,m,s = spGetModKeyState()
				points = 5
				point[1] = {x = left + (c and 16 or 0), z = top + (c and 16 or 0)}
				point[2] = {x = point[1].x, z = bottom}
				point[3] = {x = right, z = point[2].z}
				point[4] = {x = point[3].x, z = point[1].z}
				point[5] = {x = point[1].x, z = point[1].z}
				
				if c then
					loop = 0
					calculateLinePoints(point,points)
				else
					loop = 1
					calculateAreaPoints(point,points)
				end
				if (groundGridDraw) then gl.DeleteList(groundGridDraw); groundGridDraw=nil end
				groundGridDraw = glCreateList(glBeginEnd, GL_LINES, groundGrid)
				
				if terraform_type == 1 then
					if (volumeDraw) then
						gl.DeleteList(volumeDraw); volumeDraw=nil
						gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
					end
					volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeLevel)
					mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridLevel)
				elseif terraform_type == 2 then
					if (volumeDraw) then
						gl.DeleteList(volumeDraw); volumeDraw=nil
						gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
					end
					volumeDraw = glCreateList(glBeginEnd, GL_LINES, lineVolumeRaise)
					mouseGridDraw = glCreateList(glBeginEnd, GL_LINES, mouseGridRaise)
				end
				
			elseif terraform_type == 3 or terraform_type == 5 or terraform_type == 6 or (presetTerraHeight and (terraform_type == 1 or terraform_type == 2)) then
			
				-- local _, pos = spTraceScreenRay(mx, my, true, false, false, true)
				local pos = safeTrace(mx, my, true, false, true, true)
				local x,z
				if legalPos(pos) then
					if mouseUnit.id and point[1].x == point[2].x and point[1].z == point[2].z then
						local ty, id = spTraceScreenRay(mx, my, false, false, false, true)
						if ty == "unit" and id == mouseUnit.id then
							local x,_,z = spGetUnitPosition(mouseUnit.id)
							local face = spGetUnitBuildFacing(mouseUnit.id)
							
							local xsize,ysize
							if (face == 0) or (face == 2) then
								xsize = mouseUnit.ud.xsize*4
								ysize = (mouseUnit.ud.zsize or mouseUnit.ud.ysize)*4
							else
								xsize = (mouseUnit.ud.zsize or mouseUnit.ud.ysize)*4
								ysize = mouseUnit.ud.xsize*4
							end
							
							if mouseUnit.ud.isImmobile then
								points = 5
								point[1] = {x = x - xsize - 32, z = z - ysize - 32}
								point[2] = {x = x + xsize + 16, z = point[1].z}
								point[3] = {x = point[2].x, z = z + ysize + 16}
								point[4] = {x = point[1].x, z = point[3].z}
								point[5] = {x = point[1].x, z = point[1].z}
								loop = 1
							else
								points = 5
								point[1] = {x = x - xsize - 16, z = z - ysize - 16}
								point[2] = {x = x + xsize + 16, z = point[1].z}
								point[3] = {x = point[2].x, z = z + ysize + 16}
								point[4] = {x = point[1].x, z = point[3].z}
								point[5] = {x = point[1].x, z = point[1].z}
								loop = 0
							end
							
							if presetTerraHeight and not presetTerraLevelToCursor then
								terraformHeight = presetTerraHeight
							end
							SendCommand()
							local a,c,m,s = spGetModKeyState()
							stopCommand(s)
							return true
						end
					end
				
					x = floor((pos[1])/16)*16
					z = floor((pos[3])/16)*16
					
					if x - point[1].x == 0 then
						x = x - 16
					end
					if z - point[1].z == 0 then
						z = z - 16
					end
				else
					x = point[2].x
					z = point[2].z
				end
				
				local left, right = math.min(x, point[1].x), math.max(x, point[1].x)
				local top, bottom = math.min(z, point[1].z), math.max(z, point[1].z)
				
				local a,c,m,s = spGetModKeyState()
				points = 5
				point[1] = {x = left + (c and 16 or 0), z = top + (c and 16 or 0)}
				point[2] = {x = point[1].x, z = bottom}
				point[3] = {x = right, z = point[2].z}
				point[4] = {x = point[3].x, z = point[1].z}
				point[5] = {x = point[1].x, z = point[1].z}
				
				if c then
					loop = 0
					calculateLinePoints(point,points)
				else
					loop = 1
					calculateAreaPoints(point,points)
				end

				if points ~= 0 then
					if presetTerraHeight and not presetTerraLevelToCursor then
						terraformHeight = presetTerraHeight
					end
					SendCommand()
				end
				local a,c,m,s = spGetModKeyState()
				stopCommand(s)
				
			end
			
			return true
		elseif button == 4 or button == 5 then
			stopCommand()
		else
			return true
		end
	
	elseif drawingRamp == 1 then
	
		if button == 1 then
			mouseX = mx
			mouseY = my
			--spSetActiveCommand(nil)
			drawingRamp = 2
			return true
		elseif button == 4 or button == 5 then
			drawingRamp = false
			points = 0
		else
			return true
		end
	
	elseif drawingRamp == 3 then
	
		if button == 1 then
			mouseX = mx
			mouseY = my
			setHeight = true
			drawingRamp = false
			return true
		elseif button == 4 or button == 5 then
			drawingRamp = false
			points = 0
		else
			return true
		end
	
	elseif simpleDrawingRamp == 1 and button == 1 then
		if math.abs(point[1].x - point[2].x) + math.abs(point[1].z - point[2].z) < 10 then
			mouseX = mx
			mouseY = my
			drawingRamp = 2
			simpleDrawingRamp = false
		else
			mouseX = mx
			mouseY = my
			setHeight = true
			drawingRamp = false
			simpleDrawingRamp = false
		end
		return true
	end
	if button == 3 then
		-- fix mouse locked by left click handling then cancellation with right click while left click is still held
		widgetHandler.mouseOwner = nil
		return true
	end
	return false
end

function widget:KeyRelease(key)
	if originalCommandGiven and (key == KEYSYMS.LSHIFT or key == KEYSYMS.RSHIFT) then
		completelyStopCommand()
	end
	
	if drawingLasso and ((key == KEYSYMS.LCTRL) or (key == KEYSYMS.RCTRL)) then
		local mx, my = spGetMouseState()
		AddLassoPos(mx, my)
		return true
	end
end

function widget:KeyPress(key, mods)
	
	if key == KEYSYMS.ESCAPE then
		if drawingLasso or setHeight or drawingRamp or simpleDrawingRamp or drawingRectangle or placingRectangle then
			completelyStopCommand()
			return true
		end
	end
	
	if key == KEYSYMS.SPACE and (
		(terraform_type == 1 and (setHeight or drawingLasso or placingRectangle or drawingRectangle)) or
		(terraform_type == 2 and (setHeight or drawingLasso or placingRectangle or drawingRectangle)) or
		(terraform_type == 3 and (drawingLasso or drawingRectangle)) or
		(terraform_type == 4 and (setHeight or drawingRamp or simpleDrawingRamp or drawingRectangle)) or
		(terraform_type == 5 and (drawingLasso or drawingRectangle))
	) then
		volumeSelection = volumeSelection+1
		if volumeSelection > 2 then
			volumeSelection = 0
		end
		return true
	end
	
	if key == KEYSYMS.SPACE and terraform_type == 6 then
		volumeSelection = volumeSelection+1
		if volumeSelection > 1 then
			volumeSelection = 0
		end
		return true
	end
	if setLassoHeight and loop == 0 and TRY_LASSORAMP and (key == KEYSYMS.LALT or key == KEYSYMS.RALT) and not (mods.ctrl or mods.meta) then
		if points > 1 and (math.abs(point[1].y - point[points].y) / points > 7) then
			local first = point[1]
			local last = point[points]
			local len = Dist(first, last)
			if len < minRampLength then
				return
			end
			R = (R or 0) + 1
			SEG = 0
			Echo('---------------------------------------')
			Echo('--------- MAKE RAMP '..R..' ---------')
			lassoRamp = true
			-- Echo(point[points].y, point[1].y, 'diff', point[points].y - point[1].y,'off', off)
			-- remove point before last until segment length is big enough
			local i = points - 1
			local p
			while i > 0 do
				p = point[i]
				local dis = Dist(p, last)
				-- Echo('last dis', dis, 'vs', minRampLength)
				if dis < minRampLength then
					points = points - 1
					table.remove(point, i)
					Echo('dis too short',dis,'Remove From Last, remaining', points)
				else
					-- Echo('last dis correct', dis)
					break
				end
				i = i - 1
			end
			Echo('points', points)
			-- do the same from the start, all along to have long enough segments, also count the real total length
			local i = 2
			local start = point[1]
			local totalLen = 0
			while i <= points do
				p = point[i]
				local dis = Dist(start, p)
				if dis < minRampLength then
					points = points - 1
					table.remove(point, i)
					i = i - 1
					Echo('remove next after seg start #' .. i, 'dist', dis, 'remain', points)
				else
					-- Echo('dis correct for', i, 'd'.. dis)
					totalLen = totalLen + dis
					start = p
				end
				i = i + 1
				p = point[i]
			end
			---
			-- Echo('points', points)
			local off = (last.y - first.y) / (points - 1)
			for i = 2, points-1 do
				local m = point[i].mouse
				-- Echo(i," is ", m[2], '=>', m[2] + off * (i-1))
				m[2] = m[2] + off * (i-1)
				-- if m then

			end
			local lastm = last.mouse
			lastm[2] = last.y
			for i = 1, points do
				Echo('point', point[i].x, point[i].mouse[2], point[i].z, 'dist', point[i+1] and Dist(point[i], point[i+1]))
			end
			Echo('Set ramp from', point[1].x, point[1].mouse[2], point[1].z, 'to', last.x, last.mouse[2], last.z, 'points', points)

		end
	end
end

--------------------------------------------------------------------------------
-- Rectangle placement interaction
--------------------------------------------------------------------------------

local function Terraform_SetPlacingRectangle(unitDefID)
	-- Do no terraform with pregame placement.
	if Spring.GetGameFrame() < 1 then
		return false
	end
	
	if not unitDefID or not UnitDefs[unitDefID] then
		return false
	end
	
	local ud = UnitDefs[unitDefID]
		
	local facing = Spring.GetBuildFacing()
	local offFacing = (facing == 1 or facing == 3)
	
	local footX = ud.xsize/2
	local footZ = ud.zsize/2
	
	if offFacing then
		footX, footZ = footZ, footX
	end
	
	placingRectangle = {
		floatOnWater = ud.floatOnWater,
		oddX = (footX%2)*8,
		oddZ = (footZ%2)*8,
		halfX = footX/2*16,
		halfZ = footZ/2*16,
		offFacing = offFacing
	}
	
	currentlyActiveCommand = -unitDefID
	terraform_type = 1
	point[1] = {x = 0, y = 0, z = 0}
	point[2] = {x = 0, y = 0, z = 0}
	point[3] = {x = 0, y = 0, z = 0}
	
	local pos
	if (unitDefID == mexDefID) and WG.mouseoverMex then
		pos = {WG.mouseoverMex.x, WG.mouseoverMex.y, WG.mouseoverMex.z}
	else
		local mx,my = spGetMouseState()
		-- pos = select(2, spTraceScreenRay(mx, my, true, false, false, not placingRectangle.floatOnWater))
		pos = safeTrace(mx, my, true, false, true, not placingRectangle.floatOnWater)
	end
	
	SetFixedRectanglePoints(pos)
	
	return true
end

local function Terraform_SetPlacingRectangleCheck()
	return options.structure_altSelect.value
end

function WG.Terraform_GetNextTag()
	terraTag = terraTag + 1
	return terraTag
end

function WG.Terraform_GetIsPlacingStructure()
	return (placingRectangle or buildToGive) and true
end

function widget:Initialize()
	--set WG content at initialize rather than during file read to avoid conflict with local copy (for dev/experimentation)
	WG.Terraform_SetPlacingRectangle = Terraform_SetPlacingRectangle
	WG.Terraform_SetPlacingRectangleCheck = Terraform_SetPlacingRectangleCheck
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function DrawLine(pos)
	for i = 1, points do
		glVertex(point[i].x,point[i].y,point[i].z)
	end
	if pos then
		glVertex(pos[1],pos[2],pos[3])
	end
end
local function DrawMouseLine(mousePos)
	for i = 1, points do
		local m = point[i].mouse
		if m then
			glVertex(m[1], m[2], m[3])
		end
	end
	if mousePos then
		glVertex(mousePos[1], mousePos[2], mousePos[3])
	end
end
local function DrawRectangleLine(buffer)
	buffer = buffer or 0
	local p1Y, p2, p3 = point[1].y, point[2], point[3]
	glVertex(p3.x + buffer, p1Y, p3.z + buffer)
	glVertex(p3.x + buffer, p1Y, p2.z - buffer)
	glVertex(p2.x - buffer, p1Y, p2.z - buffer)
	glVertex(p2.x - buffer, p1Y, p3.z + buffer)
	glVertex(p3.x + buffer, p1Y, p3.z + buffer)
end

local function DrawRampFirstSetHeight(dis)
	glVertex(point[1].x, point[1].y,      point[1].z)
	glVertex(point[1].x, point[1].ground, point[1].z)
end

local function DrawRampStart(dis)
	-- perpendicular
	local px, pz = terraformHeight*(point[1].z-point[2].z)/dis, -terraformHeight*(point[1].x-point[2].x)/dis
	local p1 = point[1]
	local x, y, ground, z = p1.x, p1.y, p1.ground, p1.z
	glVertex(x + px, y,      z + pz)
	glVertex(x + px, ground, z + pz)
	glVertex(x - px, ground, z - pz)
	glVertex(x - px, y,      z - pz)
	
end

local function DrawRampMiddleEnd(dis)
	-- perpendicular
	local px, pz = terraformHeight*(point[1].z-point[2].z)/dis, -terraformHeight*(point[1].x-point[2].x)/dis
	local p1, p2 = point[1], point[2]
	glVertex(p2.x - px, p2.y,      p2.z - pz)
	glVertex(p1.x - px, p1.y,      p1.z - pz)
	glVertex(p1.x + px, p1.y,      p1.z + pz)
	glVertex(p2.x + px, p2.y,      p2.z + pz)
	glVertex(p2.x - px, p2.y,      p2.z - pz)
	glVertex(p2.x - px, p2.ground, p2.z - pz)
	glVertex(p2.x + px, p2.ground, p2.z + pz)
	glVertex(p2.x + px, p2.y,      p2.z + pz)
	
end
local function ElevAngle(elev, dis)
	return math.atan2(elev, dis) / math.pi * 180
end

local function drawMouseText(y,text)
	local mx,my = spGetMouseState()
	glText(text, mx+40, my+y, 18,"no")
end

local dis
function widget:DrawWorld()
	if not (drawingLasso or setHeight or drawingRectangle or drawingRamp or simpleDrawingRamp or placingRectangle) then
		widgetHandler:RemoveWidgetCallIn("DrawWorld", self)
		return
	end
	
	--// draw the lines
	--glLineStipple(2, 4095)
	glLineWidth(3.0)
	
	if terraform_type == 4 then
		dis = sqrt((point[1].x-point[2].x)^2 + (point[1].z-point[2].z)^2)
		
		if dis == 0 then
			glColor(vehPathingColor)
			glBeginEnd(GL_LINES, DrawRampFirstSetHeight)
		else
			local grad = abs(point[1].y-point[2].y)/dis
			if grad <= vehPathingGrad then
				glColor(vehPathingColor)
			elseif grad <= botPathingGrad then
				glColor(botPathingColor)
			else
			   glColor(noPathingColor)
			end
			glBeginEnd(GL_LINE_STRIP, DrawRampStart, dis)
			glBeginEnd(GL_LINE_STRIP, DrawRampMiddleEnd, dis)
		end
	else
		if setHeight then
			--glDepthTest(true)
			glCallList(groundGridDraw)
			glCallList(volumeDraw)
			glCallList(mouseGridDraw)
			
			--glDepthTest(false)
		elseif drawingLasso then
			glColor(lassoColorGood)
			local mx, my = spGetMouseState()
			local pos, mouse = GetLassoPos(mx, my)
			glBeginEnd(GL_LINE_STRIP, DrawLine, pos)

			glColor(1,1,0,1)
			glBeginEnd(GL_LINE_STRIP, DrawMouseLine, mouse)

		elseif drawingRectangle or (placingRectangle and placingRectangle.legalPos) then
			glColor(lassoColorCurrent)
			glBeginEnd(GL_LINE_STRIP, DrawRectangleLine)
			local a,c,m,s = spGetModKeyState()
			if c then
				glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, 32)
			end
		end
		
	end

	glColor(1, 1, 1, 1)
	glLineWidth(1.0)
	--glLineStipple(false)
end
local function ElevAngle(elev, dis)
	return math.atan2(elev, dis) / math.pi * 180
end
function widget:DrawScreen()
	if terraform_type == 1 or terraform_type == 2 then
		if setHeight then
			drawMouseText(10,floor(terraformHeight))
		end
	elseif terraform_type == 4 then
		drawMouseText(27, ('%.2f°'):format(ElevAngle(point[2].y - point[1].y, dis)))
		if drawingRamp == 1 then
			drawMouseText(10,floor(point[1].y))
		elseif drawingRamp == 3 then
			if point[2].y == 0 then
				drawMouseText(10,point[2].y .. " Water Level")
			elseif point[2].y == point[1].y then
				drawMouseText(10,floor(point[2].y) .. " Flat")
			else
				drawMouseText(10,floor(point[2].y))
			end
		end
	end
	
	if (setHeight or drawingLasso or placingRectangle or drawingRectangle or drawingRamp or simpleDrawingRamp) then
		if terraform_type ~= 6 then
			if volumeSelection == 1 then
				if terraform_type == 2 then
					drawMouseText(-10,"Cull Cliffs")
				else
					drawMouseText(-10,"Only Raise")
				end
			elseif volumeSelection == 2 then
				if terraform_type == 2 then
					drawMouseText(-10,"Cull Ridges")
				else
					drawMouseText(-10,"Only Lower")
				end
			end
		else
			if volumeSelection == 0 then
				drawMouseText(-10,"Blocks Vehicles")
			elseif volumeSelection == 1 then
				drawMouseText(-10,"Blocks Bots")
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function widget:Shutdown()
	if (volumeDraw) then
		gl.DeleteList(volumeDraw); volumeDraw=nil
		gl.DeleteList(mouseGridDraw); mouseGridDraw=nil
	end
	if (groundGridDraw) then
		gl.DeleteList(groundGridDraw); groundGridDraw=nil
	end
end