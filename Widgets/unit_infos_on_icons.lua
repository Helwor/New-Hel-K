
local ver = 0.1
-- require -HasViewChanged.lua
-- require UtilsFunc.lua
-- can use command_tracker.lua
-- can use modified vanilla gui_epic_penu.lua
function widget:GetInfo()
	return {
		name      = "Infos On Icons",
		desc      = "Draw some valuables info on top of icon when zoomed out, ver " .. ver,
		author    = "Helwor",
		date      = "Jan 2023",
		license   = "GNU GPL, v2",
		layer     = 4000, 
		enabled   = true,  --  loaded by default?
		handler   = true,
	}
end
local Echo = Spring.Echo
local myTeamID, myPlayerID
------------- EDIT MANUALLY
-- some char cannot be just copy pasted, instead use string.char(num)

-- '×' char 215
-- '°' char 176
-- '›' char 184
-- '»' char 187
-- '«' char 171
-- 'Ø' char 216
-- 'ø' char 248
-- '´' char 180
-- '®' char 174
-- '¤' char 164
-- '·' char 183


local symbolStatus = {
	str = '*',
	list = false,
	Draw = function() end,
	-- since the new GetMidY
	offX = 2,
	-- offY = -2,
	offY = -1,
}

local symbolSelAlly = {
	-- str = string.char(176), -- '°'
	str = '*', -- '*' need -4 y to be centered
	list = false,
	Draw = function() end,
	-- since the new GetMidY
	offX = 0,
	offY = -1,
}
local symbolHealth = {
	str = 'o',
	list = false,
	Draw = function() end,
	-- since the new GetMidY
	offX = 1,
	offY = 0,
}

local RADAR_TIMEOUT = 30 * 12 -- 


----------------------

local colors = {
	 white          = {   1,    1,    1,    1 },
	 black          = {   0,    0,    0,    1 },
	 grey           = { 0.5,  0.5,  0.5,    1 },
	 lightgrey      = { 0.75,0.75, 0.75,    1 },
	 red            = {   1, 0.25, 0.25,    1 },
	 darkred        = { 0.8,    0,    0,    1 },
	 lightred       = {   1,  0.6,  0.6,    1 },
	 magenta        = {   1, 0.25,  0.3,    1 },
	 rose           = {   1,  0.6,  0.6,    1 },
	 bloodyorange   = {   1, 0.45,    0,    1 },
	 orange         = {   1,  0.7,    0,    1 },
	 copper         = {   1,  0.6,  0.4,    1 },
	 darkgreen      = {   0,  0.6,    0,    1 },
	 green          = {   0,    1,    0,    1 },
	 lightgreen     = { 0.7,    1,  0.7,    1 },
	 teal			= {   0,    1,    1,    1 },
	 darkenedgreen  = { 0.4,    0.8,  0.4,  1 },
	 blue           = { 0.3, 0.35,    1,    1 },
	 fade_blue      = {   0,  0.7,  0.7,  0.6 },
	 paleblue       = { 0.6,  0.6,    1,    1 },
	 tainted_blue   = { 0.5,    1,    1,    1 },
	 turquoise      = { 0.3,  0.7,    1,    1 },
	 lightblue      = { 0.7,  0.7,    1,    1 },
	 cyan           = { 0.3,    1,    1,    1 },
	 ice            = {0.55,    1,    1,    1 },
	 lime           = { 0.5,    1,    0,    1 },
	 yellow         = {   1,    1,  0.3,    1 },
	 ocre           = { 0.7,  0.5,  0.3,    1 },
	 brown          = { 0.9, 0.75,  0.3,    1 },
	 purple         = { 0.9,    0,  0.7,    1 },
	 hardviolet     = {   1, 0.25,    1,    1 },
	 violet         = {   1,  0.4,    1,    1 },
	 paleviolet     = {   1,  0.7,    1,    1 },
	 whiteviolet    = {   1, 0.85,    1,    1 },
	 nocolor        = {   0,    0,    0,    0 },
}
-- local colorsByStr = {
-- 	[strHealth] = {
-- 		[colors.red] = true,
-- 		[colors.orange] = true,
-- 		[colors.white] = true,
-- 	},
-- 	[strSelAlly] = {
-- 		[colors.white] = true
-- 	}

-- }




local CreateWindowTableEditer
do
	local f = WG.utilFuncs
	CreateWindowTableEditer = f.CreateWindowTableEditer
end

local airpadDefID = {}
do
    local airpadDefs = VFS.Include("LuaRules/Configs/airpad_defs.lua", nil, VFS.GAME)
    for defID in pairs(airpadDefs) do
        airpadDefID[defID] = true
    end
end
local ignoreUnitDefID = {
	[UnitDefNames['terraunit'].id ] = true,
	[UnitDefNames['wolverine_mine'].id] = true,
	[UnitDefNames['shieldscout'].id] = true,
}
for defID, def in pairs(UnitDefs) do
	if def.name:match('drone') then
		ignoreUnitDefID[defID] = true
	end
end

local lowCostDefID = {}
for defID, def in pairs(UnitDefs) do
	if def.cost < 50 then
		lowCostDefID[defID] = true
	end
end


local useList
local currentFrame = Spring.GetGameFrame()
-- local normalScale = 1366*768
-- local scale = 1
-- local scale,vsy,vsy

local UseFont
local TextDrawCentered, GetListCentered

local font            = "LuaUI/Fonts/FreeSansBold_14"
local fontWOutline    = "LuaUI/Fonts/FreeSansBoldWOutline_14"     -- White outline for font (special font set)
local monobold        = "LuaUI/Fonts/FreeMonoBold_12"


-- datas from HasViewChanged
local Cam
local Units
local inSight
local NewView, Visibles, VisibleIcons
--
local disarmUnits
local lastStatus = WG.lastStatus or {}
WG.lastStatus = lastStatus
local inRadar = WG.inRadar or {}
WG.inRadar = inRadar
local problems = {}

local lastView -- save some redundant work
local cx, cy, cz = 0, 0, 0 -- current camera position

-- default options value
local onlyOnIcons = false
local showAllySelected = true
local showHealth = true
local showStatus = true
local showNonManualCons = true
local showCommandStatus = false
local showCloaked = true
local alphaStatus = 1
local alphaAlly = 1
local alphaHealth = 1
local allyOnTop = true
local debugMissingUnits = false

local debugChoice = 'none'
local debugCustomProps = {
	isInRadar = 'ocre',
	checkHealth = 'red',
}
local tryFont = false
local currentTryFont = 1
--



-- local colorsByStr = {
-- 	[strHealth] = {
-- 		[colors.red] = true,
-- 		[colors.orange] = true,
-- 		[colors.white] = true,
-- 	},
-- 	[strSelAlly] = {
-- 		[colors.white] = true
-- 	}

-- }




options_path = 'Hel-K/' .. widget:GetInfo().name
-- local hotkeys_path = 'Hotkeys/Construction'

options_order = {
	-- 'testBool',
	-- 'testTable',
	-- 'testColors',
	-- 'dummy',
	'only_on_icons',

	'show_ally',
	'ally_on_top',
	'alpha_ally',

	'show_health',
	'alpha_health',

	'show_status',
	'show_non_manual_cons',
	'show_command_status',
	'alpha_status',

	'show_cloaked',
	-- 'lbl_alpha',

	'debugChoice',
	'setCustomProp',
	'tryFont',
	'currentTryFont',
	'dbgMissingUnits',
}
options = {}

-- options.testBool = {
-- 	name = 'Test Bool',
-- 	type = 'bool',
-- 	value = false,
-- 	OnChange = function(self)
-- 		-- Echo("self.checked,self.value is ", self.checked,self.value)
-- 	end,
-- 	path = 'TOTO',
-- }

-- options.testColors = {
-- 	name = 'Test Colorize',
-- 	type = 'colors',
-- 	value = {0.5,0.5,0.5,1},
-- 	colorizeName = true,
-- 	path = 'TOTO',
-- }

-- local thisTable = {'myvalue'}
-- options.testTable = {
-- 	type = 'table',
-- 	name = 'Dummy Table',
-- 	value = thisTable,
-- 	-- alwaysOnChange = true,
-- 	callback = function(self)
-- 		Echo('MY CALL BACK',self, self and self.value, self and self[1])
-- 	end,
-- 	OnChange = function(self)
-- 		Echo('ON CHANGE',os.clock(),'type',type(self.value))
-- 		Echo("self.value == thisTable is ", self.value == thisTable)
-- 		if type(self.value) == 'table' then
-- 			for k,v in pairs(self.value) do
-- 				Echo('=>',k,v)
-- 			end
-- 		end
-- 	end,
-- 	path = 'TOTO',
-- }



-- options.dummy = {
-- 	type = 'bool',
-- 	name = 'Dummy',
-- 	value = {'HI'},
-- 	alwaysOnChange = true,
-- 	OnChange = function(self)
-- 		-- Echo('ON CHANGE',os.clock())
-- 		-- Echo("self.value is ", self.value)
-- 		-- if type(self.value) == 'table' then
-- 		-- 	Echo('IS TABLE !',self.value[1])
-- 		-- 	self.value[1] = 'HELLO'
-- 		-- else
-- 		-- 	self.value = {'OK'}
-- 		-- end
-- 	end,
-- 	path = 'TOTO',
-- }
options.only_on_icons = {
	name = 'Draw only on unit icons',
	type = 'bool',
	desc = "draw only when unit is an icon",
	value = false,
	OnChange = function(self)
		onlyOnIcons = self.value
	end,
	noHotkey = true,
}


options.show_ally = {
	name = 'Draw Selected Allied units',
	type = 'bool',
	value = showAllySelected,
	OnChange = function(self)
		showAllySelected = self.value
	end,
	noHotkey = true,
	children = {'ally_on_top', 'alpha_ally'},
}
options.ally_on_top = {
	name = '	..on top',
	desc = "Ally selected unit's symbol appear on top of the others",
	type = 'bool',
	value = allyOnTop,
	OnChange = function(self)
		allyOnTop = self.value
	end,
	noHotkey = true,
	parents = {'show_ally', 'debugFont'},
}
options.alpha_ally = {
	name            = '	..transparency',
	type            = 'number',
	value           = alphaAlly,
	min             = 0,
	max             = 1,
	step            = 0.05,
	update_on_the_fly = true,
	OnChange        = function(self)
						alphaAlly = self.value
					end,
	noHotkey = true,
	parents = {'show_ally', 'tryFont'},
}


options.show_health = {
	name = 'Draw Health indicator',
	type = 'bool',
	value = showHealth,
	OnChange = function(self)
		showHealth = self.value
	end,
	noHotkey = true,
	children = {'alpha_health'},
}

options.alpha_health = {
	name            = '	..transparency',
	type            = 'number',
	value           = alphaHealth,
	min             = 0,
	max             = 1,
	step            = 0.05,
	tooltipFunction = function(self)
						return self.value
					  end,
	OnChange        = function(self)
						alphaHealth = self.value
					end,
	noHotkey = true,
	parents 		= {'show_health'},
}





-- options.lbl_alpha = {
-- 	name = 'Transparency',
-- 	type ='Label'
-- }

options.show_status = {
	name = "Draw Unit's Status",
	type = 'bool',
	value = showStatus,
	OnChange = function(self)
		showStatus = self.value
	end,
	noHotkey = true,
	children = {'alpha_status', 'show_command_status', 'show_non_manual_cons'},
}

options.show_non_manual_cons = {
	name = 'Show Tracked non manual Cons',
	desc = 'Mainly while using Smart Builder',
	type = 'bool',
	value = showNonManualCons,
	OnChange = function(self)
		showNonManualCons = self.value
	end,
	noHotkey = true,
	parents 		= {'show_status'},
}
options.show_command_status = {
	name = "Extra command status",
	desc = "Add status command of tracked units by widgets",
	type = 'bool',
	value = showCommandStatus,
	OnChange = function(self)
		showCommandStatus = self.value
	end,
	noHotkey = true,
	parents 		= {'show_status'},
}


options.alpha_status = {
	name            = '	..transparency',
	type            = 'number',
	value           = alphaStatus,
	min             = 0,
	max             = 1,
	step            = 0.05,
	update_on_the_fly = true,
	OnChange        = function(self)
						alphaStatus = self.value
					end,
	noHotkey = true,
	parents 		= {'show_status'},
}

options.show_cloaked = {
	name = 'Draw Cloaked indicator',
	type = 'bool',
	value = showCloaked,
	OnChange = function(self)
		showCloaked = self.value
	end,
	noHotkey = true,
}


-- options.lbl_debug = {
-- 	type = 'label',
-- 	name = 'Debug',
-- }
-- debuginsight = {
-- 	name ='Debug Units in Sight',
-- 	value = debugInSight,
-- 	type = 'bool',
-- 	OnChange = function(self)
-- 		debugInSight = self.value
-- 		if debugInSight then
-- 			lastStatus = {}
-- 		end
-- 	end,
-- },
-- debugAlledgiance = {
-- 	name ='Debug Unit Alledgiances',
-- 	value = debugAlledgiance,
-- 	type = 'bool',
-- 	OnChange = function(self)
-- 		debugAlledgiance = self.value
-- 		if debugAlledgiance then
-- 			lastStatus = {}
-- 		end
-- 	end,
-- },

options.debugChoice = {
	name = 'Debug Choice',
	type = 'radioButton',
	value = debugChoice,
	items = {
		{key = 'none', 			name='None'},
		{key = 'inSight',		name='inSight'},
		{key = 'alledgiance',	name='Alledgiance'},
		{key = 'custom', 		name='Custom'},
	},
	OnChange = function(self)
		debugChoice =  self.value
		if debugChoice ~= 'none' then
			lastStatus = {}
		end
	end,
	noHotkey = true,
}

local setPropWindow
options.setCustomProp = {
	name = 'Debug Custom Property',
	type = 'button',
	value = false,
	OnChange = function(self)
		if setPropWindow and not setPropWindow.disposed then
			setPropWindow:Dispose()
			setPropWindow = nil
		else
			setPropWindow = CreateWindowTableEditer(debugCustomProps, 'debugCustomProps')
		end
	end,
	action = 'setpropicon',
}


options.tryFont = {
	name = 'Try Font',
	desc = 'Use key PLUS and MINUS (or use the slider below)\nCycle through available characters that will be shown on ally selected units (better do that when speccing),\nConsole debug (F8) will tell the char code to use (not all char codes are available and some will be just empty string)',
	type = 'bool',
	value = tryFont,
	children = {'currentTryFont', 'alpha_ally'},
	OnChange = function(self)
		tryFont = self.value
		if tryFont then
			widgetHandler:UpdateWidgetCallIn('KeyPress',widget)
			if symbolSelAlly.list then
				gl.DeleteList(symbolSelAlly.list)
				symbolSelAlly.list = GetListCentered(string.char(currentTryFont))
			else
				symbolSelAlly.backupStr = symbolSelAlly.str
				symbolSelAlly.str = string.char(currentTryFont)
			end


		else
			if symbolSelAlly.backupStr then
				symbolSelAlly.str = symbolSelAlly.backupStr
			end
			if symbolSelAlly.list then
				gl.DeleteList(symbolSelAlly.list)
				symbolSelAlly.list = GetListCentered(symbolSelAlly.str)
			end
			widgetHandler:RemoveWidgetCallIn('KeyPress',widget)
		end
	end,
	noHotkey = true,
}
options.currentTryFont = {
	name = '	..current tried char code',
	type = 'number',
	min = 1, step = 1, max = 255,
	value = currentTryFont,
	parents = {'tryFont'},
	update_on_the_fly = true,
	tooltipFunction = function(self)
		local str = string.char(self.value)
		return str .. ' char code: ' .. self.value
	end,
	OnChange = function(self)
		currentTryFont = self.value
		if options.tryFont.value then
			if symbolSelAlly.list then
				gl.DeleteList(symbolSelAlly.list)
				symbolSelAlly.list = GetListCentered(string.char(currentTryFont))
			else
				if not symbolSelAlly.backupStr then
					symbolSelAlly.backupStr = symbolSelAlly.str
				end
				symbolSelAlly.str = string.char(currentTryFont)
			end
		end
	end,
}
options.dbgMissingUnits = {
	name = 'Debug Missing Units',
	type = 'bool',
	value = debugMissingUnits,
	OnChange = function(self)
		debugMissingUnits = self.value
	end
}
-- for k,opt in pairs(options) do
-- 	opt:OnChange()
-- end
local options = options
local debugging = true -- need UtilsFunc.lua
local f = debugging and WG.utilFuncs



local spGetUnitDefID                = Spring.GetUnitDefID
local spGetAllUnits                 = Spring.GetAllUnits
local spGetMyTeamID                 = Spring.GetMyTeamID
local spGetUnitPosition             = Spring.GetUnitPosition
-- local spAreTeamsAllied              = Spring.AreTeamsAllied
local spGetUnitTeam                 = Spring.GetUnitTeam
local spValidUnitID                 = Spring.ValidUnitID
local spGetUnitHealth               = Spring.GetUnitHealth
local spGetSpectatingState          = Spring.GetSpectatingState
local spGetUnitRulesParam           = Spring.GetUnitRulesParam
local spGetUnitIsDead               = Spring.GetUnitIsDead
local spGetGroundHeight 			= Spring.GetGroundHeight
-- local spGetUnitTeam                 = Spring.GetUnitTeam
local spIsUnitIcon                  = Spring.IsUnitIcon
local spIsUnitVisible               = Spring.IsUnitVisible
local spGetGameFrame                = Spring.GetGameFrame
local spGetUnitRulesParam           = Spring.GetUnitRulesParam


local max,min = math.max,math.min
local floor = math.floor
-- Points Debugging
local spWorldToScreenCoords = Spring.WorldToScreenCoords
-- local GetTextWidth        = fontHandler.GetTextWidth
-- local TextDraw            = fontHandler.Draw
-- local TextDrawRight       = fontHandler.DrawRight
-- local glRect              = gl.Rect
local glColor = gl.Color
local glPushMatrix 	= gl.PushMatrix
local glScale      	= gl.Scale
local glPopMatrix  	= gl.PopMatrix
local glCallList   	= gl.CallList
local glCreateList 	= gl.CreateList
local glDeleteList 	= gl.DeleteList
local glTranslate  	= gl.Translate
local glPushMatrix 	= gl.PushMatrix
local glPopMatrix 	= gl.PopMatrix


local spGetUnitViewPosition = Spring.GetUnitViewPosition
-- local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitHealth = Spring.GetUnitHealth
-- local spGetVisibleUnits = Spring.GetVisibleUnits
-- local spGetSpectatingState = Spring.GetSpectatingState
local spIsUnitVisible = Spring.IsUnitVisible
local spGetAllUnits  = Spring.GetAllUnits
local spGetUnitIsDead = Spring.GetUnitIsDead


local GetIconMidY



local remove = table.remove
local round = math.round

local myTeamID = Spring.GetMyTeamID()


-- for i,color in pairs(colors) do
-- 	color[4] = alphaStatus
-- end
local    green,           yellow,           red,                white,              blue,               paleblue
	= colors.green,    colors.yellow,    colors.red,        colors.white,      colors.blue,         colors.paleblue
local    orange ,        turquoise,         paleviolet,         violet,             hardviolet
	= colors.orange,  colors.turquoise,  colors.paleviolet, colors.violet,     colors.hardviolet
local     copper,         white,            grey,               lightgreen,         darkenedgreen,       lime
	= colors.copper,  colors.white,      colors.grey,       colors.lightgreen, colors.darkenedgreen,   colors.lime
local    whiteviolet, 		lightblue, 		   lightgrey,		ocre
	= colors.whiteviolet, colors.lightblue, colors.lightgrey, colors.ocre

local cyan, ice, teal = colors.cyan, colors.ice, colors.teal
local nocolor = colors.nocolor

local b_ice, b_grey, b_grey2, b_whiteviolet = {unpack(ice)}, {unpack(grey)}, {unpack(grey)}, {unpack(whiteviolet)}
local blinkcolor = {
	[b_ice] = b_grey,
	[b_whiteviolet] = b_grey2,
	[b_grey] = b_ice,
	[b_grey2] = b_whiteviolet,
}
-- local font = {
--   classname     = 'font',

--   font          = "FreeSansBold.otf",
--   size          = 12,
--   outlineWidth  = 3,
--   outlineWeight = 3,

--   shadow        = false,
--   outline       = false,
--   color         = {1,1,1,1},
--   outlineColor  = {0,0,0,1},
--   autoOutlineColor = true,
-- }
-- local myFont = FontHandler.LoadFont(font, 20, 20, 3)
--     Echo("myFont is ", myFont)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- local lists = {}
-- for _,color in pairs(colors) do
--   lists[color] = {}
-- end
-- for color1,color2 in pairs(blinkcolor) do
--   lists[color1] = {}
--   lists[color2] = {}
-- end



local GetUnitPos = function(id, threshold)
    local unit = Units[id]
    if not unit then
    	return
    end
    local pos = unit.pos
    local _
    if not unit.isStructure and currentFrame > pos.frame + threshold then
        _, _, _, pos[1], pos[2], pos[3] = spGetUnitPosition(id,true)
        pos.frame = currentFrame
    end
    return  pos[1], pos[2], pos[3]
end
function widget:GameFrame(f)
	currentFrame = f
end
local function ApplyColor(id, statusColor, healthColor, alphaStatus, alphaHealth, defID, blink)
	local unit = Units[id]
	if not unit then
		return
	end
	if not (healthColor or statusColor) then
		return
	end
	local _,_,_,x,y,z = unit:GetPos(1,true)
	if not x then
		return
	end
	-- Echo("defID is ", defID, id)
	local isIcon = VisibleIcons[id] or not inSight[id]
	if isIcon then
		local distFromCam = ( (cx-x)^2 + (cy-y)^2 + (cz-z)^2 ) ^ 0.5
		local gy = spGetGroundHeight(x,z)
		y =	GetIconMidY(defID or 0, y, gy, distFromCam)
	end
	local mx,my = spWorldToScreenCoords(x,y,z)
	if healthColor then
		symbolHealth:Draw(mx, my, healthColor, alphaHealth)
	end
	if statusColor then
		local statusColor = blink and blinkcolor[statusColor] or statusColor
		symbolStatus:Draw(mx, my, statusColor, alphaStatus)
	end

end

local enable3 = false -- debugging to see 3 different state at a time on any unit

local function Treat(id,defID,allySelUnits,unit, blink, anyDebug)
	-- if spIsUnitVisible(id) and (not onlyOnIcons or spIsUnitIcon(id)) then
		local statusColor, healthColor, allySelColor, allyDelayDraw
		local alphaStatus = alphaStatus
		
		-- local x,y,z = unit:GetPos(0, true)

		if anyDebug then
			if debugChoice == 'custom' then
				for k,v in pairs(debugCustomProps) do
					local orik = k
					local AND = k:explode('&')
					local pass
					for _,key in ipairs(AND) do
						local NOT, key = key:match('^(!?)(.*)')
						if NOT == '!' then
							pass = not unit[key]
						else
							pass = unit[key]
						end
						if not pass then
							break
						end
					end
					-- done = true
					if pass then
						local color = colors[v]
						if color then
							if not statusColor then
								statusColor = color
							-- elseif not allySelColor then
							-- 	allySelColor = color
							elseif not healthColor then
								healthColor = color
							end
						end
					end
				end
			elseif debugChoice == 'alledgiance' then
				healthColor = unit.isMine and lightblue or unit.isAllied and blue or unit.isEnemy and orange
			elseif debugChoice == 'inSight' then
				healthColor = white
			end
		else
			local health = unit.health
			if not health[1] then
				health = false
			end
			local paralyzed
			local hp,maxhp,paraDmg,bp
			if health then
				hp,maxhp, paraDmg,bp = health[1], health[2], health[3], health[5]
				-- if not maxhp then
				-- 	Echo('no max hp for unit ',unit.defID and UnitDefs[unit.defID].name,unpack(health))
				-- 	return
				-- end
				paralyzed = paraDmg > maxhp
				-- health.frame = currentFrame
				health = hp/(maxhp*bp)

			end
			-- if unit.isKnown then statusColor = violet
			-- end
			-- local builder = bp<1 and Units[unit.builtBy]
			if showStatus then
				statusColor = 
					bp and bp>=0 and (
							bp<0.8 and grey
							or bp<1 and lightgreen
						)
					or (paralyzed or enable3) and b_ice
					or disarmUnits[id]~=nil and b_whiteviolet
					-- or builder and not builder.isFactory and white
					or showCommandStatus and unit.tracked and (
							unit.movingBack and brown
							  -- unit.assisting and darkenedgreen
							or unit.isIdle and blue
							or unit.autoguard and darkenedgreen
							or unit.manual and (
									unit.building and red
									or unit.actualCmd==90 and hardviolet
									or orange
								)
							or unit.isFighting and turquoise
							or unit.waitManual and yellow
							-- or unit.actualCmd == 90 and paleviolet
							or unit.cmd and green
						)
					or showNonManualCons and unit.tracked and (
							unit.isCon and not (unit.manual or unit.waitManual or unit.isFighting) and blue
						)

				if not statusColor then
					if unit.isJumper then
						local jumpReload = unit.isJumper and unit.isMine and spGetUnitRulesParam(id,'jumpReload')
						if jumpReload then
							statusColor = jumpReload>=1 and darkenedgreen
								  or jumpReload>=0.8 and lime
						end
					elseif showCloaked and unit.isCloaked then
					  alphaStatus = 0.7
					  statusColor = paleblue
					elseif defID then
						if airpadDefID[defID] and not unit.isEnemy then
							if spGetUnitRulesParam(id, "padExcluded" .. myTeamID) == 1 then
								statusColor = copper
							end
						elseif unit.isBomber then
							local noammo = spGetUnitRulesParam(id, "noammo")
							if (noammo or 0) > 0 then
								statusColor = ocre
							end
						end
					end
				end
			end
			if showHealth then
				healthColor = health and (health<0.3 and red or (enable3 or health<0.6) and orange)
			end
			if showAllySelected or tryFont then
				if allyOnTop then
					allyDelayDraw = enable3 or allySelUnits[id]
				else
					allySelColor = (enable3 or allySelUnits[id]) and white
				end
			end

		end

		if healthColor or statusColor or allySelColor or allyDelayDraw then
			local _,_,_,x,y,z = unit:GetPos(1)
			if x then
				local isIcon = onlyOnIcons or VisibleIcons[id]
				if isIcon then
					-- LOOK UnitDrawer.cpp LINE 420
					local gy = spGetGroundHeight(x,z)
					local distFromCam = ( (cx-x)^2 + (cy-y)^2 + (cz-z)^2 ) ^ 0.5
					GetIconMidY(defID or 0, y, gy, distFromCam)
				end

				if not anyDebug and (statusColor or healthColor) then
					local ls = lastStatus[id]
					if not ls then
						lastStatus[id] = {statusColor, healthColor, alphaStatus, alphaHealth, defID}
					else
						ls[1], ls[2] = statusColor, healthColor
						ls[3], ls[4] = alphaStatus, alphaHealth
					end
				end
				local mx,my = spWorldToScreenCoords(x,y,z)
				if healthColor then

					symbolHealth:Draw(mx, my, healthColor, alphaHealth)
				end
				if statusColor then
					local statusColor = blink and blinkcolor[statusColor] or statusColor
					symbolStatus:Draw(mx,my, statusColor, alphaStatus)
					-- local x2,y2,z2 = Spring.GetUnitPosition(id)
					-- local mx2, my2 = spWorldToScreenCoords(x2,y2,z2)
					-- symbolStatus:Draw(mx2,my2, colors.orange, alphaStatus)
				end
				if allySelColor then
					symbolSelAlly:Draw(mx,my, allySelColor, alphaAlly)
				elseif allyDelayDraw then
					return {mx,my}
				end
			end
		else
			lastStatus[id] = nil
		end

		return 

	-- end

end

function widget:GameOver()
	-- widgetHandler:RemoveWidget(widget)
end
function widget:UnitEnteredLos(unitID)
	if lastStatus[unitID] then
		inRadar[unitID] = nil
		lastStatus[unitID] = nil
	end
end
function widget:UnitLeftLos(unitID)
	if lastStatus[unitID] then
		inRadar[unitID] = lastStatus[unitID]
		inRadar[unitID].toframe = currentFrame + RADAR_TIMEOUT
	end
end
function widget:UnitLeftRadar(unitID)
	if inRadar[unitID] then
		inRadar[unitID] = nil
		lastStatus[unitID] = nil
	end
end
function widget:UnitDestroyed(unitID)
	if inRadar[unitID] then
		inRadar[unitID] = nil
		lastStatus[unitID] = nil
	end
end
local globalList
local problems = {}
local lastMessage = ''
local clockMessage = os.clock()
local GlobalDraw = function()
	UseFont(monobold)
	local allySelUnits = WG.allySelUnits
	local subjects =
		(debugChoice == 'custom' or debugChoice == 'alledgiance') and Cam.Units
		or debugChoice == 'inSight' and inSight
		or onlyOnIcons and VisibleIcons
		or Visibles

	for id in pairs(problems) do
		if Units[id] then
			problems[id] = nil
		end
	end
	local blink = os.clock()%0.5 < 0.25
	local size = table.size(subjects)
	local avoidLowCost = size > 300
	cx, cy, cz = unpack(Cam.pos)
	local delayAllyPoses = {}

	local anyDebug = debugChoice ~= 'none'
	for id in pairs(subjects) do
		local unit = Units[id]
		if not unit then
			if debugMissingUnits then
				problems[id] = true
			end
		else
			local defID = unit.defID
			local valid = anyDebug or not (avoidLowCost and lowCostDefID[defID] or ignoreUnitDefID[defID])
			if valid then
				local allyPos = Treat(id,defID,allySelUnits, unit, blink, anyDebug)
				if allyPos then
					delayAllyPoses[allyPos] = true
				end
			end
		end
	end
	for pos in pairs(delayAllyPoses) do
		symbolSelAlly:Draw(pos[1],pos[2], white, alphaAlly)
	end


	-- Echo("table.size(inRadar) is ", table.size(inRadar))
	-- show last seen unit's symbol and color for a few sec ocne they gone out of view
	if not debugInSight and Cam.fullview~=1 then
		for id, t in pairs(inRadar) do
			if t.toframe < currentFrame then
				inRadar[id] = nil
				lastStatus[id] = nil
			else
				ApplyColor(id, t[1], t[2], t[3], t[4], t[5], blink)
			end
		end
	end
	-- for id in pairs(radar) do
	-- 	if 
	-- end
	if debugMissingUnits then
		local msg
		if next(problems) then
			local rendered, dead = 0, 0
			for id in pairs(problems) do
				if spGetUnitIsDead(id) then
					dead = dead + 1
					problems[id] = nil
				else
					local _,_,_, x,y,z = spGetUnitPosition(id, true)

					if x and spIsUnitVisible(id) then
						local mx,my = spWorldToScreenCoords(x,y,z)
						symbolStatus:Draw(mx,my, red, 0.5)
						rendered = rendered + 1
					end
				end
			end
			msg = 'problems:'..table.size(problems) .. ', ' .. (next(problems) or '') .. ' ... rendered: ' .. rendered ..' dead:'..dead
		else
			msg = 'no missing units'
		end
		local now = os.clock()
		if lastMessage ~= msg or now - clockMessage > 5 then
			clockMessage = now
			Echo(msg)
			lastMessage = msg
		end
	end
	-- if math.round(os.clock()*10)%30 == 0 then
	-- 	Echo('count in Infos on icons',count)
	-- end
	glColor(white)
end

local minus, plus = 269, 270

function widget:KeyPress(key, mods)
	if not tryFont then
		return
	end
	if key == plus then
		if currentTryFont < 255 then
			local currentTryFont = currentTryFont + 1
			local str = string.char(currentTryFont)
			-- options.currentTryFont.value = currentTryFont
			-- options.currentTryFont:OnChange()
			WG.SetWidgetOption(widget:GetInfo().name,options_path,'currentTryFont',currentTryFont)
			Echo('char used',currentTryFont,type(str),str)
		end
		return true
	elseif key == minus then
		if currentTryFont > 0 then
			local currentTryFont = currentTryFont - 1
			local str = string.char(currentTryFont)
			-- options.currentTryFont.value = currentTryFont
			-- options.currentTryFont:OnChange()
			WG.SetWidgetOption(widget:GetInfo().name,options_path,'currentTryFont',currentTryFont)
			Echo('char used',currentTryFont,type(str),str)
		end
		return true
	end
end
local test = function() end
function widget:DrawScreenEffects()
	-- gl.Billboard()
	-- gl.DepthTest(false)
	-- Echo("gl.DrawListAtUnit(id,symbolHealth.list) is ", gl.DrawListAtUnit(id,symbolHealth.list,true,4,4,4))
	-- gl.DepthTest(true)
	--***************************
	local thisFrame = spGetGameFrame()
	lastFrame = thisFrame
	if globalList then
		if lastView ~= NewView[5] then -- 50% faster
			glDeleteList(globalList)
			globalList = glCreateList(GlobalDraw)
			-- globalList = glCreateList(function() end)
		end
		glCallList(globalList)		
	else
		GlobalDraw()
	end
	--***************************
	-- UseFont(monobold)
	--***************************
	-- local test = glCreateList(GlobalDraw)
	-- glDeleteList(test)
	lastView = NewView[5]
	-- local isSpectating = spGetSpectatingState()
end

function widget:ViewResize(vsx, vsy)
	-- vsx,vsy = vsx + 500, vsy + 500
	-- scale = (vsx*vsy) / normalScale
	-- Echo("scale is ", scale)
end

function WidgetRemoveNotify(w,name,preloading)
	if preloading then
		return
	end
	if name == 'HasViewChanged' then
		widgetHandler:Sleep(widget)
	end
end
function WidgetInitNotify(w,name,preloading)
	if preloading then
		return
	end

	if name == 'HasViewChanged' then
		-- Units = WG.UnitsIDCard.units
		widgetHandler:Wake(widget)
	end
end

function widget:Initialize()
	NewView = WG.NewView
	Visibles = WG.Visibles and WG.Visibles.anyMap
	VisibleIcons = WG.Visibles and WG.Visibles.iconsMap
	GetIconMidY = WG.GetIconMidY
	Cam = WG.Cam
	inSight = Cam.inSight
	disarmUnits = WG.disarmUnits or {}
	myTeamID, myPlayerID = Spring.GetMyTeamID(), Spring.GetMyPlayerID()
	if not Cam then
		Echo(widget:GetInfo().name .. " requires HasViewChanged.")
		widgetHandler:RemoveWidget(widget)
		return
	end

	-- if WG.UnitsIDCard then
	-- 	Units = WG.UnitsIDCard.units
	-- 	Echo(widget:GetInfo().name .. ' use UnitsIDCard.')
	-- elseif Cam and Cam.Units then
	-- 	Units = Cam.Units
	-- 	Echo(widget:GetInfo().name .. ' use Cam.Units.')
	-- end
	Units = Cam.Units
	widget:ViewResize(Spring.GetViewGeometry())
	-- local font = gl.LoadFont("FreeSansBold.otf", 12, 3, 3)
	if WG.MyFont then
		fontHandler = WG.MyFont -- it's a copy of mod_font.lua as widget, a parallel fontHandler that  doesn't reset the cache over time since there's no update
		useList = true -- list work with own fontHandler (2 times faster) then 50% even faster using global list if view don't change move
	end
	UseFont = fontHandler.UseFont
	UseFont(monobold)
	TextDrawCentered = fontHandler.DrawCentered
	useList = true
	if useList and glCallList then

		GetListCentered = WG.MyFont.GetListCentered

		symbolStatus.list = GetListCentered(symbolStatus.str)
		symbolStatus.Draw = function(self, mx,my,color)
			glColor(color[1], color[2], color[3], alphaStatus or color[4])
			glPushMatrix()
			glTranslate(floor(mx + self.offX + 0.5) , floor(my + self.offY + 0.5) , 0)
			glCallList(self.list)
			glPopMatrix()
		end

		symbolSelAlly.list = GetListCentered(symbolSelAlly.str)
		symbolSelAlly.Draw = function(self, mx,my,color, alphaStatus)

			glColor(color[1], color[2], color[3], alphaStatus or color[4])
			glPushMatrix()
			glTranslate(floor(mx + self.offX + 0.5) , floor(my + self.offY + 0.5) , 0)
			glCallList(self.list)
			glPopMatrix()
		end

		symbolHealth.list = GetListCentered(symbolHealth.str)
		symbolHealth.Draw = function(self, mx,my,color, alphaStatus)
			glColor(color[1], color[2], color[3], alphaStatus or color[4])
			glPushMatrix()
			glTranslate(floor(mx + self.offX + 0.5) , floor(my + self.offY + 0.5) , 0)
			glCallList(self.list)
			glPopMatrix()
		end


		globalList = glCreateList(GlobalDraw)

		-- for color,t in pairs(lists) do
		-- 	-- t[strSel] = glCreateList(
		-- 	-- 	function()
		-- 	-- 		glColor(color)
		-- 	-- 		TextDrawCentered(strSel, 0, 0)
		-- 	-- 	end
		-- 	-- )
		-- 	-- t[strHealth] = glCreateList(
		-- 	-- 	function()
		-- 	-- 		glColor(color)
		-- 	-- 		TextDrawCentered(strHealth, 0, 0)
		-- 	-- 	end
		-- 	-- )
		-- 	t[strSel] = strSelList
		-- 	if colorsByStr[strHealth][color] then
		-- 		t[strHealth] = strHealthList
		-- 	end
		-- 	if colorsByStr[strSelAlly][color] then
		-- 		t[strSelAlly] = strSelAllyList
		-- 	end
		-- end
	else
		symbolStatus.Draw = function(self, mx,my, color, alphaStatus)
			glColor(color[1], color[2], color[3], alphaStatus or color[4])
			TextDrawCentered(self.str, mx, my)
		end
		symbolSelAlly.Draw = function(self, mx,my, color, alphaStatus)
			glColor(color[1], color[2], color[3], alphaStatus or color[4])
			TextDrawCentered(self.str, mx, my)
		end
		symbolHealth.Draw = function(self, mx,my, color, alphaStatus)
			glColor(color[1], color[2], color[3], alphaStatus or color[4])
			TextDrawCentered(self.str, mx, my)
		end

	end
	widgetHandler.actionHandler:AddAction( -- we cannot set the action through epic menu option or it won't switch as desired
		widget,'showpropicon',
		function()
			if options.debugChoice.value == 'custom' then
				options.debugChoice.value = 'none'
			else
				options.debugChoice.value = 'custom'
			end
			options.debugChoice:OnChange()
		end,
		nil,
		't'
	)


end


function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
	end
end

function widget:Shutdown()
	if globalList then
		glDeleteList(globalList)
	end
	widgetHandler.actionHandler:RemoveAction(widget,'showpropicon')
  -- 	for color, t in pairs(lists) do
		-- for str, list in pairs(t) do
	 --  		glDeleteList(list)
		-- end
  -- 	end
  	if symbolStatus.list then
  		glDeleteList(symbolStatus.list)
  	end
  	if symbolSelAlly.list then
  		glDeleteList(symbolSelAlly.list)
  	end
  	if symbolHealth.list then
  		glDeleteList(symbolHealth.list)
  	end
end

function widget:SetConfigData(data)
    if data.debugCustomProps then
    	for k,v in pairs(debugCustomProps) do
    		debugCustomProps[k] = nil
    	end
    	for k,v in pairs(data.debugCustomProps) do
    		debugCustomProps[k] = v
    	end
    end
end
function widget:GetConfigData()
	return {debugCustomProps = debugCustomProps}
end


if debugging then
	f.DebugWidget(widget)
end
