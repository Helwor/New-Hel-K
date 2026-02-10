
local ver = 1.0
-- require api_has_view_changed.lua
-- require lib_funcs
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
local currentFrame = Spring.GetGameFrame()
local MIN_RELOAD_TIME_NOTICE = 12 -- dont register reload weapons below this time
local gameSpeed = Game.gameSpeed

------------- EDIT MANUALLY
-- some char cannot be just copy pasted, instead use string.char(num)

-- '*' char 42
-- '«' char 171
-- '°' char 176
-- '›' char 184
-- '»' char 187
-- '×' char 215
-- 'Ø' char 216
-- 'ø' char 248
-- '´' char 180
-- '®' char 174
-- '¤' char 164
-- '·' char 183
-- 

local symbolStatus = {
	str = string.char(42), -- *
	list = false,
	Draw = function() end,
	offX = 2,
	offY = -1,
}

local symbolSelAlly = {
	-- str = string.char(215), -- ×
	str = string.char(42), -- *
	list = false,
	Draw = function() end,
	offX = -1,
	offY = 0,
}
local symbolHealth = {
	str = 'o',
	list = false,
	Draw = function() end,
	offX = 1,
	offY = 0,
}

local symbolPrio = {
	str = string.char(184), -- '›'
	list = false,
	Draw = function() end,
	offX = 3,
	offY = 2,
}

local symbolReload = {
	str = string.char(176), -- '°'
	list = false,
	Draw = function() end,
	offX = 2,
	offY = 1,
}

local objNumbers = {
	Draw = function() end,
	lists = {},
	offX = 3,
	offY = -2,
}

local RADAR_TIMEOUT = 30 * 12


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
	teal           = {   0,    1,    1,    1 },
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

local exponents = {
    ['0'] = string.char(0xE2, 0x81, 0xB0), -- ⁰
    ['1'] = string.char(0xC2, 0xB9),       -- ¹
    ['2'] = string.char(0xC2, 0xB2),       -- ²
    ['3'] = string.char(0xC2, 0xB3),       -- ³
    ['4'] = string.char(0xE2, 0x81, 0xB4), -- ⁴
    ['5'] = string.char(0xE2, 0x81, 0xB5), -- ⁵
    ['6'] = string.char(0xE2, 0x81, 0xB6), -- ⁶
    ['7'] = string.char(0xE2, 0x81, 0xB7), -- ⁷
    ['8'] = string.char(0xE2, 0x81, 0xB8), -- ⁸
    ['9'] = string.char(0xE2, 0x81, 0xB9)  -- ⁹
}
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
	[UnitDefNames['starlight_satellite'].id] = true,
}


local disallowReloadNotice = {
	[UnitDefNames['shipassault'].id] = true,
	[UnitDefNames['turretmissile'].id] = true,
}
local canBuildDefID = {}
local lowCostDefID = {}

local reloadTimes = {}
local weaponNumber = {}
local longReloadCheck
local function InitializeDefs() end
do
	longReloadCheck = {}
	local lrc = longReloadCheck
	local spGetUnitStockpile = Spring.GetUnitStockpile
	local spGetUnitRulesParam = Spring.GetUnitRulesParam
	local spGetUnitWeaponState = Spring.GetUnitWeaponState
	local commDGun = {}
	local confirmedReloadTimes = {}
	local weaponReload = {}
	local checkFuncs = {}
	local WeaponDefs = WeaponDefs


	local function GetComDGun(unitID)
		local weapObj = commDGun[unitID]
		if weapObj == nil then
			weapObj = false
			for weapOrder = 1, 2 do
				local wdef = WeaponDefs[spGetUnitRulesParam(unitID, 'comm_weapon_id_'..weapOrder)]
				if wdef and wdef.customParams.slot == '3' then
					local weapNum = spGetUnitRulesParam(unitID,'comm_weapon_num_'..weapOrder)
					local reloadTime = spGetUnitWeaponState(unitID, weapNum, 'reloadTime')
					weapObj = {weapNum, reloadTime}
					break
				end
			end
			commDGun[unitID] = weapObj
		end
		if weapObj then
			return weapObj[1], weapObj[2]
		end
	end

	checkFuncs.StockpileReload = function(defID, unitID)
		local numStockpiled, numStockpileQued, stockpileBuild = spGetUnitStockpile(unitID)
		return numStockpiled >= 1 and numStockpiled or stockpileBuild, numStockpiled
	end

	checkFuncs.StockpileReloadGadget = function(defID, unitID)
		local numStockpiled, numStockpileQued, stockpileBuild = spGetUnitStockpile(unitID)
		if numStockpiled >= 1 then
			return numStockpiled, numStockpiled
		end
		return spGetUnitRulesParam(unitID, "gadgetStockpile") or 0
	end

	checkFuncs.CaptureReload = function(defID, unitID)
		local reloadFrame = spGetUnitRulesParam(unitID, "captureRechargeFrame")
		if (reloadFrame or 0) == 0 then
			return 1
		elseif (reloadFrame > 0) then
			return 1 - (reloadFrame - currentFrame) / reloadTimes[defID]
		else
			return 0
		end
	end

	checkFuncs.WaterTank = function(defID, unitID)
		local waterTank = spGetUnitRulesParam(unitID, "watertank")
		if (waterTank or 1) >= 1 then
			return 1
		else
			return waterTank / reloadTimes[defID]
		end
	end

	checkFuncs.SpecialReloadUser = function(defID, unitID)
		local specialReloadProp = spGetUnitRulesParam(unitID, "specialReloadRemaining") or 0
		return 1 - specialReloadProp
	end

	checkFuncs.SpecialReload = function(defID, unitID)
		local reloadFrame = spGetUnitRulesParam(unitID, "specialReloadFrame")
		if (reloadFrame or currentFrame) <= currentFrame then
			return 1
		else
			return 1 - (reloadFrame - currentFrame) / reloadTimes[defID]
		end
	end

	checkFuncs.ScriptReload = function(defID, unitID)
		local reloadFrame = spGetUnitRulesParam(unitID, "scriptReloadFrame") or currentFrame
		if reloadFrame <= currentFrame then
			return 1
		else
			return spGetUnitRulesParam(unitID, "scriptReloadPercentage")
				or (1 - ((reloadFrame - currentFrame)/gameSpeed) / reloadTimes[defID])
		end
	end

	checkFuncs.DynaCom = function(defID, unitID)
		local weapNum, reloadTime = GetComDGun(unitID)
		if not weapNum then
			return 0
		end
		local _, reloaded, reloadFrame = spGetUnitWeaponState(unitID, weapNum)
		if reloaded or (reloadFrame or 0) == 0 then
			return 1
		end
		return 1 - ((reloadFrame-currentFrame)/gameSpeed) / reloadTime
	end

	checkFuncs.checkWeaponReload = function(defID, unitID)
		local weapNum = weaponNumber[defID]
		local reloadTime = reloadTimes[defID]
		local _, reloaded, reloadFrame = spGetUnitWeaponState(unitID, weapNum)
		if reloaded or (reloadFrame or 0) == 0 then
			return 1
		end
		return 1 - ((reloadFrame-currentFrame)/gameSpeed) / reloadTime
	end
	for defID, def in pairs(UnitDefs) do

		local cp = def.customParams
		if def.name:match('drone') or cp.dontcount or cp.is_drone or def.cost == 0 then
			ignoreUnitDefID[defID] = true
		end
		if def.cost < 50 then
			lowCostDefID[defID] = true
		end
		if not ignoreUnitDefID[defID] then
			if def.buildSpeed ~= 0 then
				canBuildDefID[defID] = true
			end

			---- Gather various units having long reloading weapon

			local reloadTime, checkFunc, weapNum
			if def.canStockpile then
				if cp.stockpiletime then
					reloadTime = tonumber(cp.stockpiletime)
					checkFunc = checkFuncs.StockpileReloadGadget
				else
					checkFunc = checkFuncs.StockpileReload
				end
			elseif cp.post_capture_reload then
				reloadTime = tonumber(cp.post_capture_reload)
				checkFunc = checkFuncs.CaptureReload
			elseif cp.maxwatertank then
				reloadTime = cp.maxwatertank
				checkFunc = checkFuncs.WaterTank
			elseif cp.specialreloadtime then
				if cp.specialreload_userate then
					reloadTime = tonumber(cp.specialreload_userate)
					checkFunc = checkFuncs.SpecialReloadUser
				else
					reloadTime = cp.specialreloadtime
					checkFunc = checkFuncs.SpecialReload
				end
			elseif cp.script_reload then
				if def.name ~= 'turretaaclose' then -- reload time of 15 probably when it close
					reloadTime = tonumber(cp.script_reload)
					checkFunc = checkFuncs.ScriptReload
				end
			elseif cp.dynamic_comm then
				checkFunc = checkFuncs.DynaCom
			else
				for i, desc in ipairs(def.weapons) do
					local maxReload = 0
					local wdef = WeaponDefs[desc.weaponDef]
					if wdef and (wdef.manualFire or wdef.reload > maxReload) then
						reloadTime = wdef.reload
						maxReload = reloadTime
						checkFunc = checkFuncs.checkWeaponReload
						weapNum = i
						if wdef.manualFire then
							break
						end
					end
				end
			end
			if checkFunc then
				if not reloadTime or reloadTime >= MIN_RELOAD_TIME_NOTICE then
					lrc[defID] = checkFunc
					reloadTimes[defID] = reloadTime
					weaponNumber[defID] = weapNum
					disallowReloadNotice[defID] = disallowReloadNotice[defID] or false
				end
			end
		end
	end

end

local useGlobalList

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
local delayAllyPoses = {}
local numberLists = setmetatable(
	{},
	{
		__index = function(self, str) 
			local list = GetListCentered(str)
			rawset(self, str, list)
			return list
		end
	}
)
local lastView -- save some redundant work
local cx, cy, cz = 0, 0, 0 -- current camera position

-- default options value
local onlyOnIcons = true
local showAllySelected = true
local showHealth = true
local showStatus = true
local showNonManualCons = true
local showCommandStatus = false
local showPrio = true
local showCloaked = false
local showReload = true
local allyOnTop = true
local useFinePos = true
local debugMissingUnits = false
local alphaStatus = 1
local alphaAlly = 1
local alphaHealth = 1
local alphaPrio = 1
local alphaReload = 1

local scale = 1

local debugChoice = 'none'
local debugCustomProps = {
	isInRadar = 'ocre',
	checkHealth = 'red',
}
local tryFont = false
local currentTryFont = 1
--

options_path = 'Hel-K/' .. widget:GetInfo().name
-- local hotkeys_path = 'Hotkeys/Construction'

options_order = {
	-- 'testBool',
	-- 'testTable',
	-- 'testColors',
	-- 'dummy',
	'only_on_icons',
	'fine_pos',
	'scale',

	'show_ally',
	'ally_on_top',
	'alpha_ally',

	'show_health',
	'alpha_health',

	'show_status',
	'show_non_manual_cons',
	'show_command_status',
	'alpha_status',

	'show_prio',
	'alpha_prio',

	'show_reload',
	'alpha_reload',
	'custom_reload',

	'show_cloaked',

	'debugChoice',
	'currentTryFont',
	'setCustomProp',
	'dbgMissingUnits',
}
options = {}

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

options.fine_pos = {
	name = 'Refine Pos',
	type = 'bool',
	desc = "Take the icon size, fov and distance from Cam into consideration for finer position on the icon\nCheck for performance...",
	value = useFinePos,
	OnChange = function(self)
		useFinePos = self.value
	end,
	noHotkey = true,
}

options.scale = {
	name = 'Symbols Scale',
	type = 'number',
	value = scale,
	min             = 1.0,
	max             = 2.5,
	step            = 0.01,
	OnChange = function(self)
		scale = self.value
	end,
	noHotkey = true,
}

options.show_ally = {
	name = 'Draw Selected Allied Units',
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
	name = 'Draw Health Indicator',
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
	desc = 'Mainly useful while using Smart Builder',
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

options.show_prio = {
	name = 'Show Builder High Prio',
	type = 'bool',
	value = showPrio,
	OnChange = function(self)
		showPrio = self.value
	end,
	noHotkey = true,
	children = {'alpha_prio'},
}

options.alpha_prio = {
	name            = '	..transparency',
	type            = 'number',
	value           = alphaPrio,
	min             = 0,
	max             = 1,
	step            = 0.05,
	update_on_the_fly = true,
	OnChange        = function(self)
		alphaPrio = self.value
	end,
	noHotkey = true,
	parents 		= {'show_prio'},
}

options.show_reload = {
	name = 'Show Long Reload/Stockpile',
	desc = 'Indicate when weapon/stockpile that have long reload time is loaded or about to.\nMinimum Reload time: ' .. MIN_RELOAD_TIME_NOTICE,
	type = 'bool',
	value = showReload,
	OnChange = function(self)
		showReload = self.value
	end,
	noHotkey = true,
	children = {'alpha_reload'},
}
options.custom_reload = {
	name = 'Custom Reload Unit Type',
	desc = 'Indicate which unit type you don\'t want to see reload on',
	type = 'table',
	value = disallowReloadNotice,
	preTreatment = function(t) -- receive a copy
		local temp = {}
		local defs = UnitDefs
		for defID, bool in pairs(t) do
			local def = defs[defID]
			if def then
				temp[def.name] = bool
			end
			t[defID] = nil
		end
		for name, bool in pairs(temp) do
			t[name] = bool
		end
	end,
	postTreatment = function(t) -- receive the original
		local temp = {}
		local defNames = UnitDefNames
		for name, bool in pairs(t) do
			local def = UnitDefNames[name]
			if def then
				temp[def.id] = bool
			end
			t[name] = nil
		end
		for defID, bool in pairs(temp) do
			t[defID] = bool
		end
	end,
	noHotkey = true,
	noRemove = true,
	children = {'show_reload'},
}

options.alpha_reload = {
	name            = '	..transparency',
	type            = 'number',
	value           = alphaReload,
	min             = 0,
	max             = 1,
	step            = 0.05,
	update_on_the_fly = true,
	OnChange        = function(self)
		alphaReload = self.value
	end,
	noHotkey = true,
	parents 		= {'show_reload'},
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
		{key = 'all',			name='Show All Symbols'},
		{key = 'try',			name='Try Font', desc = 'Use key PLUS and MINUS (or use the slider below)\nCycle through available characters that will be shown on ally selected units (better do that when speccing),\nConsole debug (F8) will tell the char code to use (not all char codes are available and some will be just empty string)'},
		{key = 'custom', 		name='Custom'},
	},
	OnChange = function(self)
		debugChoice =  self.value
		tryFont = debugChoice == 'try'
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
		if debugChoice ~= 'none' then
			lastStatus = {}
		end
	end,
	noHotkey = true,
}

local setPropWindow
options.setCustomProp = {
	name = 'Debug Custom Property',
	desc = '/setpropicon for rapid access',
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


options.currentTryFont = {
	name = 'Current tried char code',
	type = 'number',
	min = 1, step = 1, max = 255,
	value = currentTryFont,
	update_on_the_fly = true,

	desc = 'If you choose to Try a Font in Debug Choice, select the character here',
	tooltipFunction = function(self)
		local str = string.char(self.value)
		return str .. ' char code: ' .. self.value
	end,
	OnChange = function(self)
		currentTryFont = self.value
		if options.debugChoice.value == 'try' then
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
	desc = "Console debugging for missing units  of api_unit_handler",
	type = 'bool',
	value = debugMissingUnits,
	OnChange = function(self)
		debugMissingUnits = self.value
	end,
	dev = true,
}

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
local diag = math.diag
local floor = math.floor
-- Points Debugging
local spWorldToScreenCoords = Spring.WorldToScreenCoords
-- local GetTextWidth        = fontHandler.GetTextWidth
-- local TextDraw            = fontHandler.Draw
-- local TextDrawRight       = fontHandler.DrawRight
-- local glRect              = gl.Rect
local glColor = gl.Color
local glPushMatrix 	= gl.PushMatrix
local glScale      	= glScale
local glPopMatrix  	= gl.PopMatrix
local glCallList   	= gl.CallList
local glCreateList 	= gl.CreateList
local glDeleteList 	= gl.DeleteList
local glTranslate  	= gl.Translate
local glPushMatrix 	= gl.PushMatrix
local glPopMatrix 	= gl.PopMatrix
local glScale		= gl.Scale


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


function widget:GameFrame(f)
	currentFrame = f
end

local function ApplyColor(id, blink, fov, defID, statusColor, healthColor, prioColor, reloadColor, stockpile, alphaStatus, alphaHealth, alphaPrio, alphaReload)
	local unit = Units[id]
	if not unit then
		return
	end
	if not (healthColor or statusColor or prioColor or reloadColor) then
		return
	end

	local _,gy,_,x,y,z = unit:GetPos(1,true)
	if not x then
		return
	end
	-- Echo("defID is ", defID, id)
	if useFinePos then
		local isIcon = VisibleIcons[id] or not inSight[id]
		if isIcon then
			local distFromCam = diag(cx-x, cy-y, cz-z)
			distFromCam = distFromCam * fov / 45 
			y =	GetIconMidY(defID or 0, y, gy, distFromCam)
		end
	end
	local mx,my = spWorldToScreenCoords(x,y,z)
	if healthColor then
		symbolHealth:Draw(mx, my, healthColor, alphaHealth)
	end
	if statusColor then
		statusColor = blink and blinkcolor[statusColor] or statusColor
		symbolStatus:Draw(mx, my, statusColor, alphaStatus)
	end
	if prioColor then
		symbolPrio:Draw(mx, my, prioColor, alphaPrio)
	end
	if reloadColor then
		if stockpile then
			objNumbers:Draw(mx,my, reloadColor, alphaReload, stockpile)
		else
			symbolReload:Draw(mx, my, reloadColor, alphaReload)
		end
	end

end

local function ProcessUnit(id, defID, allySelUnits, unit, blink, anyDebug, fullview, fov)
	-- if spIsUnitVisible(id) and (not onlyOnIcons or spIsUnitIcon(id)) then
		local statusColor, healthColor, prioColor, reloadColor, stockpile, allySelColor
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
			elseif debugChoice == 'all' then
				healthColor = orange
				statusColor = b_ice
				allySelColor = white
				prioColor = green
				reloadColor = green
			elseif debugChoice == 'try' then
				allySelColor = white
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
				paralyzed = paraDmg > maxhp
				health = hp/(maxhp*bp)
			end
			-- if unit.isKnown then statusColor = violet
			-- end
			-- local builder = bp<1 and Units[unit.builtBy]
			if showPrio and defID and canBuildDefID[defID] then
				prioColor = spGetUnitRulesParam(id, "buildpriority") == 2 and green
			end
			if showStatus then
				statusColor = 
					bp and bp >= 0 and (
							bp < 0.8 and grey
							or bp < 1 and lightgreen
						)
					or (paralyzed or enable4) and b_ice
					or disarmUnits[id] ~= nil and b_whiteviolet
					-- or builder and not builder.isFactory and white
					or showCommandStatus and unit.tracked and (
							unit.movingBack and brown
							  -- unit.assisting and darkenedgreen
							or unit.isIdle and blue
							or unit.autoguard and darkenedgreen
							or unit.manual and (
									unit.building and red
									or unit.actualCmd == 90 and hardviolet
									or orange
								)
							or unit.isFighting and turquoise
							or unit.waitManual and yellow
							-- or unit.actualCmd == 90 and paleviolet
							or unit.cmd and green
						)
					or showNonManualCons and unit.tracked and (
							unit.isCon and not (unit.manual or unit.waitManual) and blue
						)
				if not statusColor then
					if unit.isJumper then
						local jumpReload = unit.isJumper and unit.isMine and spGetUnitRulesParam(id,'jumpReload')
						if jumpReload then
							statusColor = jumpReload >= 1 and darkenedgreen
								  or jumpReload >= 0.8 and lime
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
				healthColor = health and (health < 0.3 and red or health < 0.6 and orange)
			end
			if showAllySelected and allySelUnits[id] then
				allySelColor = white
			end
			if showReload and unit.teamID == myTeamID then
				local checkFunc = longReloadCheck[defID]
				if checkFunc and not disallowReloadNotice[defID] then
					local value, sp = checkFunc(defID, id)
					if value >= 1 then
						reloadColor = value >= 1 and green or lightblue
						stockpile = sp and sp <= 100 and tostring(sp)--:gsub('.', exponents) -- can't display exponent > 3
					end
				end
			end
		end
		
		if healthColor or statusColor or allySelColor or prioColor or reloadColor then
			local _,gy,_,x,y,z = unit:GetPos(1)
			if x then
				if useFinePos then
					local isIcon = onlyOnIcons or VisibleIcons[id]
					if isIcon then
						-- LOOK UnitDrawer.cpp LINE 420
						local distFromCam = diag(cx-x, cy-y, cz-z)
						distFromCam = distFromCam * fov / 45
						y = GetIconMidY(defID or 0, y, gy, distFromCam)
					end
				end

				if not anyDebug and fullview~=1 and (statusColor or healthColor or prioColor or reloadColor) then
					local ls = lastStatus[id]
					if not ls then
						lastStatus[id] = {defID, statusColor, healthColor, prioColor, reloadColor, alphaStatus, alphaHealth, alphaPrio, alphaReload}
					else
						ls[2], ls[3], ls[4], ls[5] = statusColor, healthColor, prioColor, reloadColor
						ls[6], ls[7], ls[8], ls[9] = alphaStatus, alphaHealth, alphaPrio, alphaReload
						ls[10] = stockpile
					end
				end
				local mx,my = spWorldToScreenCoords(x,y,z)
				if reloadColor then
					if stockpile then
						objNumbers:Draw(mx,my, reloadColor, alphaReload, stockpile)
					else
						symbolReload:Draw(mx,my, reloadColor, alphaReload)
					end
					-- end
				end
				if healthColor then
					symbolHealth:Draw(mx, my, healthColor, alphaHealth)
				end
				if statusColor then
					local statusColor = blink and blinkcolor[statusColor] or statusColor
					symbolStatus:Draw(mx,my, statusColor, alphaStatus)
				end
				if prioColor then
					symbolPrio:Draw(mx,my, prioColor, alphaPrio)
				end
				if allySelColor then
					if allyOnTop then
						delayAllyPoses[{mx,my}] = true
					else
						symbolSelAlly:Draw(mx,my, allySelColor, alphaAlly)
					end
				end
			end
		else
			lastStatus[id] = nil
		end
		return 
	-- end
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
	if allyOnTop then
		delayAllyPoses = {}
	end

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
				ProcessUnit(id, defID, allySelUnits, unit, blink, anyDebug, Cam.fullview, Cam.fov)
			end
		end
	end
	if allyOnTop then
		for pos in pairs(delayAllyPoses) do
			symbolSelAlly:Draw(pos[1],pos[2], white, alphaAlly)
		end
	end

	-- Echo("table.size(inRadar) is ", table.size(inRadar))
	-- show last seen unit's symbol and color for a few sec ocne they gone out of view
	if debugChoice ~= "Insight" and Cam.fullview~=1 then
		local fov = Cam.fov
		for id, t in pairs(inRadar) do
			if t.toframe < currentFrame then
				inRadar[id] = nil
				lastStatus[id] = nil
			else
				Echo('apply')
				ApplyColor(id, blink, fov, t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10])
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
	Cam = WG.Cam
	if not Cam then
		Echo(widget:GetInfo().name .. " requires api_has_view_changed.lua")
		widgetHandler:RemoveWidget(widget)
		return
	end
	NewView = WG.NewView
	Visibles = WG.Visibles and WG.Visibles.anyMap
	VisibleIcons = WG.Visibles and WG.Visibles.iconsMap
	GetIconMidY = WG.GetIconMidY
	inSight = Cam.inSight
	disarmUnits = WG.disarmUnits or {}
	myTeamID, myPlayerID = Spring.GetMyTeamID(), Spring.GetMyPlayerID()

	Units = Cam.Units
	widget:ViewResize(Spring.GetViewGeometry())
	-- local font = gl.LoadFont("FreeSansBold.otf", 12, 3, 3)
	if WG.MyFont then
		-- list work with own fontHandler (2 times faster) then 50% even faster using global list if view don't change
		fontHandler = WG.MyFont -- it's a copy of mod_font.lua as widget, a parallel fontHandler that  doesn't reset the cache over time since there's no update
		GetListCentered = glCallList and WG.MyFont.GetListCentered
	end
	UseFont = fontHandler.UseFont
	UseFont(monobold)
	TextDrawCentered = fontHandler.DrawCentered
	useGlobalList = glCallList

	for i = 1, 100 do
		if numberLists[tostring(i)] then -- FIXME: can't make lists during a list creation so I have to do it outside
			-- list created
		end
	end
	for _, obj in ipairs({symbolStatus, symbolSelAlly, symbolReload, symbolHealth, symbolPrio}) do
		if GetListCentered then
			obj.list = GetListCentered(obj.str)
			obj.Draw = function(self, mx,my,color, alpha)
				glColor(color[1], color[2], color[3], alpha or color[4])
				glPushMatrix()
				glTranslate(floor(mx + self.offX + 0.5) , floor(my + self.offY - (useFinePos and 4 or 0) + 0.5) , 0)
				glScale(scale, scale, 0)
				glCallList(self.list)
				glPopMatrix()
			end
		else
			obj.Draw = function(self, mx,my, color, alpha)
				glColor(color[1], color[2], color[3], alpha or color[4])
				glPushMatrix()
				glScale(scale, scale, 0)
				TextDrawCentered(self.str, floor(mx + self.offX + 0.5) , floor(my + self.offY - (useFinePos and 4 or 0) + 0.5))
				glPopMatrix()
			end
		end
	end
	if GetListCentered then
		objNumbers.Draw = function(self, mx,my, color, alpha, numbers)
			glColor(color[1], color[2], color[3], alpha or color[4])
			glPushMatrix()
			glScale(scale, scale, 0)
			glTranslate(floor(mx + self.offX + 0.5) , floor(my - self.offY - (useFinePos and 4 or 0) + 0.5), 0)
			glCallList(numberLists[numbers])
			glPopMatrix()
		end
	else
		objNumbers.Draw = function(self, mx,my, color, alpha, numbers)
			glColor(color[1], color[2], color[3], alpha or color[4])
			glPushMatrix()
			glScale(scale, scale, 0)
			TextDrawCentered(numbers, floor(mx + self.offX + 0.5) , floor(my - self.offY - (useFinePos and 4 or 0) + 0.5))
			glPopMatrix()
		end
	end
	if useGlobalList then
		globalList = glCreateList(GlobalDraw)
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

	for _, obj in ipairs({symbolStatus, symbolSelAlly, symbolHealth, symbolPrio, symbolReload}) do
		if obj.list then
			glDeleteList(obj.list)
			obj.list = nil
		end
	end
	for _, list in pairs(numberLists) do
		glDeleteList(list)
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


if f then
	f.DebugWidget(widget)
end
