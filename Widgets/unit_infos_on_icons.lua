local ver = 2.0
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
local sig = '['..widget.GetInfo().name .. '] '
local Echo = Spring.Echo
local myTeamID, myPlayerID
local currentFrame = Spring.GetGameFrame()
local MIN_RELOAD_TIME_NOTICE = 12 -- dont register reload weapons below this time
local NEW_METHOD = true
local FONT_NAME = "FreeSansBold.otf"
local baseFontSize = 12
local font
local fontSize = 12
local fonts = {}
local gameSpeed = Game.gameSpeed
local updateRate = 10
local hasAmmoDefID = WG.hasAmmoDefID
local globalList
local atlasses = {}
local lastView -- save some redundant work
local cx, cy, cz = 0, 0, 0 -- current camera position

local glTexture = gl.Texture
local glTexRect = gl.TexRect
local glAddAtlasTexture = gl.AddAtlasTexture
local glGetAtlasTexture = gl.GetAtlasTexture
local glDeleteTextureAtlas = gl.DeleteTextureAtlas
local glTextureInfo = gl.TextureInfo
local pcall = pcall
local clock = os.clock
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
	offX = 1,
	offY = 0,
	-- str = string.char(226, 153, 165), -- ♥
	-- str = "\225\131\166", -- ღ
	-- str = string.char(226, 153, 161), -- ♡
	-- str = string.char(226, 157, 164), -- ❤ 
	-- fontSize = 9,
	-- offX = 3,
	-- offY = 1,
	list = false,
	Draw = function() end,
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

local symbolAmmo = {
	-- str = string.char(183), -- '·'
	-- str = '.',
	-- str = '\226\154\171',
	-- str = '¤',
	-- str = '•',
	-- str = '＊',
	-- str = '✱',
	-- str = '✳',
	-- str = string.char(226, 129, 141),   -- ⁍ U+204D (E2 81 8D) black rightwards bullet
	-- str = string.char(194, 161),           -- ¡ U+00A1 (C2 A1) point d'exclamation inversé
	-- str = string.char(240, 159, 167, 168), -- 🧨 U+1F9E8 (F0 9F A7 A8)
	str = string.char(226, 129, 131),   -- ⁃ U+2043 (E2 81 83) hyphen bullet

	list = false,
	Draw = function() end,
	offX = 2,
	offY = 1,
}

local symbolObjects = {symbolStatus, symbolSelAlly, symbolReload, symbolAmmo, symbolHealth, symbolPrio}


local objNumbers = {
	Draw = function() end,
	offX = 3,
	offY = -2,
}
local digits = {}
for i = 0, 9 do
	digits[48 + i] = {str = tostring(i)}   -- char code of digit as key
end
objNumbers.digits = digits
objNumbers.adv = 7                         -- move distance to place next char when displaying more digits

local glyphObjects = {unpack(symbolObjects)}
for _, d in pairs(digits) do
	glyphObjects[#glyphObjects + 1] = d
end
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

local airpadDefID = WG.airpadDefID

local fakeIDTable = {id = -1}
local ignoreUnitDefID = {
	[WG.terraunitDefID] = true,
	[(UnitDefNames['wolverine_mine'] or fakeIDTable).id] = true,
	[(UnitDefNames['shieldscout'] or fakeIDTable).id] = true,
	[(UnitDefNames['starlight_satellite'] or fakeIDTable).id] = true,
}


local disallowReloadNotice = {
	[(UnitDefNames['shipassault'] or fakeIDTable).id] = true,
	[(UnitDefNames['turretmissile'] or fakeIDTable).id] = true,
}
local canBuildDefID = {}
local lowCostDefID = {
	[(UnitDefNames['energysolar'] or fakeIDTable).id] = true,
	[(UnitDefNames['energywind'] or fakeIDTable).id] = true,
}

local reloadTimes = {}
local weaponNumber = {}
local longReloadCheck
local morphing = {}
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
				if not reloadTime or tonumber(reloadTime) >= MIN_RELOAD_TIME_NOTICE then -- string format compatible (Future Wars)
					lrc[defID] = checkFunc
					reloadTimes[defID] = tonumber(reloadTime)
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

local font1            = "LuaUI/Fonts/FreeSansBold_14"
local font1WOutline    = "LuaUI/Fonts/FreeSansBoldWOutline_14"     -- White outline for font (special font set)
local monobold        = "LuaUI/Fonts/FreeMonoBold_12"
-- local monobold        = "FreeSansBold.otf"


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
			local list
			if GetListCentered then
				list = GetListCentered(str)
				rawset(self, str, list)
				return list
			else
				return 0
			end
		end
	}
)

-- default options value
local onlyOnIcons = true
local autoFix = true
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
local initialized = false

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
	'new_method',
	'only_on_icons',
	'auto_fix',
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

options.new_method = {
	name = 'New Method',
	type = 'bool',
	desc = "Draw unicodes and using atlas",
	value = NEW_METHOD,
	OnChange = function(self)
		NEW_METHOD = self.value
		initialized = false
	end,
	hidden = true,
	noHotkey = true,
}

options.only_on_icons = {
	name = 'Draw only on unit icons',
	type = 'bool',
	desc = "draw only when unit is an icon",
	value = onlyOnIcons,
	OnChange = function(self)
		onlyOnIcons = self.value
	end,
	noHotkey = true,
}
options.auto_fix = {
	name = 'Automatic Fix for InconsAsUI Mode',
	type = 'bool',
	desc = "Automatically draw on every units instead of just icons when the mode IconsAsUI is enabled. This is due to engine bug wrongly missing iconized state of units that are under ~95% build progress",
	value = autoFix,
	OnChange = function(self)
		autoFix = self.value
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

	desc = 'If you choose to Try a Font in Debug Choice, select the character here or push +/-, also commented in console (F8)',
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

local b_ice, b_whiteviolet, b_violet_blue = {unpack(ice)}, {unpack(whiteviolet)}, {unpack(violet)}
local blinkcolor = {
	[b_ice] = grey,
	[b_whiteviolet] = grey,
	[b_violet_blue] = paleblue,
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
--   autoOutlineColor = false,
-- }
-- local myFont = FontHandler.LoadFont(font, 20, 20, 3)
--     Echo("myFont is ", myFont)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function ApplyColor(id, defID, blink, fovRatio, statusColor, healthColor, IconsAsUI)
	local unit = Units[id]
	if not unit then
		return
	end
	if not (healthColor or statusColor) then
		return
	end

	local _,gy,_,x,y,z = unit:GetPos(1,true)
	if not x then
		return
	end
	-- Echo("defID is ", defID, id)
	if useFinePos then
		-- local isIcon = VisibleIcons[id] or not inSight[id]
		-- if isIcon then
			local distFromCam = diag(cx-x, cy-y, cz-z)
			distFromCam = distFromCam * fovRatio
			y =	GetIconMidY(defID or 0, y, gy, distFromCam)

		-- end
	end
	local mx,my = spWorldToScreenCoords(x,y,z)
	if IconsAsUI then
		my = my - 3
	end
	if healthColor then
		symbolHealth:Draw(mx, my, healthColor, alphaHealth)
	end
	if statusColor then
		statusColor = blink and blinkcolor[statusColor] or statusColor
		symbolStatus:Draw(mx, my, statusColor, alphaStatus)
	end
end

local function DrawUnit(id, unit, blink, fovRatio, IconsAsUI)
	local _,gy,_,x,y,z = unit:GetPos(1)
	if x then
		local info = unit.info
		local statusColor, healthColor, prioColor, reloadColor, ammoColor, stockpile, alphaStatus, allySelColor
		 = info[1], info[2], info[3], info[4], info[5], info[6], info[7], info[8]
		local isIcon
		if useFinePos then
			isIcon = onlyOnIcons or VisibleIcons[id]
			if isIcon then
				-- LOOK UnitDrawer.cpp LINE 420
				local distFromCam = diag(cx-x, cy-y, cz-z)
				distFromCam = distFromCam * fovRatio
				y = GetIconMidY(unit.defID or 0, y, gy, distFromCam)

			end
		end

		local mx,my = spWorldToScreenCoords(x,y,z)
		if IconsAsUI and isIcon then -- work around
			my = my - 3
		end
		if reloadColor then
			if stockpile then
				objNumbers:Draw(mx,my, reloadColor, alphaReload, stockpile)
			else
				symbolReload:Draw(mx,my, reloadColor, alphaReload)
			end
			-- end
		end

		if ammoColor then
			symbolAmmo:Draw(mx,my, ammoColor, alphaReload)
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
	else
		lastStatus[id] = nil
	end
end

local function ProcessUnit(id, defID, allySelUnits, unit, blink, anyDebug, fullview)
	local statusColor, healthColor, prioColor, reloadColor, ammoColor, stockpile, allySelColor
	local alphaStatus = alphaStatus
	local gotAny
	local info = unit.info
	unit.lastInfo = currentFrame
	if not info then
		info = {}
		unit.info = info
	end
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
			ammoColor = yellow
		elseif debugChoice == 'try' then
			allySelColor = white
		end
	else
		local health = unit.health
		local hp = health and health[1]
		local paralyzed
		local maxhp,paraDmg,bp
		if hp then
			maxhp, paraDmg, bp = health[2], health[3], health[5]
			paralyzed = paraDmg > maxhp
			health = hp / (maxhp * bp)
		end
		-- if unit.isKnown then statusColor = violet
		-- end
		-- local builder = bp<1 and Units[unit.builtBy]
		if showPrio and canBuildDefID[defID] then
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
				or morphing[id] and b_violet_blue
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
				else
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
		if showReload --[[and unit.teamID == myTeamID]] then
			local checkFunc = longReloadCheck[defID]
			if checkFunc and not disallowReloadNotice[defID] then
				local value, sp = checkFunc(defID, id)
				if value >= 0.8 then
					reloadColor = value >= 1 and green or white
					stockpile = sp and tostring(sp <= 100 and sp or 100)--:gsub('.', exponents) -- can't display exponent > 3
				end
			end
			if hasAmmoDefID[defID] then
				local value = spGetUnitRulesParam(id, 'ammoFraction') or 1
				if value < 0.6 then
					ammoColor = value < 0.3 and red or orange
				end
			end
		end
	end
	if not anyDebug and fullview~=1 and unit.isEnemy and (statusColor or healthColor) then
		lastStatus[id] = unit
	end
	gotAny = healthColor or statusColor or allySelColor or prioColor or reloadColor or ammoColor
	info.gotAny = gotAny
	if gotAny then
		info[1], info[2], info[3], info[4], info[5], info[6], info[7], info[8]
			= statusColor, healthColor, prioColor, reloadColor, ammoColor, stockpile, alphaStatus, allySelColor
	end
	return gotAny
end



local problems = {}
local lastMessage = ''
local clockMessage = os.clock()
local currentAtlas = false

local lastColor, lastA
local GlobalDraw = function()
	lastColor, lastA = nil, nil
	UseFont(monobold)
	if NEW_METHOD then
		gl.Blending(GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
		currentAtlas = atlasses[1] and atlasses[1].tex
		if currentAtlas then
			glTexture(0, currentAtlas)
		end
	end
	local IconsAsUI = Spring.GetConfigInt("UnitIconsAsUI", 0) == 1

	local subjects =
		(debugChoice == 'custom' or debugChoice == 'alledgiance') and Cam.Units
		or debugChoice == 'inSight' and inSight
		or onlyOnIcons and (
				not (autoFix and IconsAsUI)
				or (Cam.relDist < 5000 and IconsAsUI)
			) and VisibleIcons -- IconsAsUI mode doesnt register correctly the icons
		or Visibles
	-- Echo("Cam.relDist is ", Cam.relDist)
	for id in pairs(problems) do
		if Units[id] then
			problems[id] = nil
		end
	end
	local blink = clock()%0.5 < 0.25
	local size = table.size(subjects)
	local avoidLowCost = false and size > 300
	cx, cy, cz = unpack(Cam.pos)
	if allyOnTop then
		delayAllyPoses = {}
	end
	local Units, allySelUnits, updateRate, currentFrame = Units, WG.allySelUnits, updateRate, currentFrame
	local fullview, fov, lowCost, ignore, anyDebug = Cam.fullview, Cam.fov, lowCostDefID, ignoreUnitDefID, debugChoice ~= 'none'
	local fovRatio = fov / 45
	local updateFrame = currentFrame - updateRate
	-- Echo("currentFrame, currentFrame is ", currentFrame, currentFrame)
	for id in pairs(subjects) do
		local unit = Units[id]
		if not unit then
			if debugMissingUnits then
				problems[id] = true
			end
		else
			local defID = unit.defID
			if anyDebug or not (avoidLowCost and lowCost[defID] or ignore[defID]) then
				if anyDebug or (unit.lastInfo or -1000) < updateFrame then
					if ProcessUnit(id, unit.defID, allySelUnits, unit, blink, anyDebug, fullview) then
						DrawUnit(id, unit, blink, fovRatio, IconsAsUI)
					end
				elseif unit.info.gotAny then
					DrawUnit(id, unit, blink, fovRatio, IconsAsUI)
				end
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
		for id, unit in pairs(inRadar) do
			if unit.toframe < currentFrame then
				inRadar[id] = nil
				lastStatus[id] = nil
			else
				local info = unit.info
				ApplyColor(id, unit.defID, blink, fovRatio, info[1], info[2], IconsAsUI)
			end
		end
	end
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
end

local function SafeGlobalDraw()

	local ok, err = pcall(GlobalDraw)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	glColor(1, 1, 1, 1)
	glTexture(0, false)
	currentAtlas = false
	if not ok then
		Echo(sig .. 'GlobalDraw error: ' .. tostring(err))
	end
end

local function MakeGlyphTex(str, fontSize)
	local texSize = fontSize * 2
	local tex = gl.CreateTexture(texSize, texSize, {
		target = GL.TEXTURE_2D,
		format = GL.RGBA8,
		min_filter = GL.NEAREST,
		mag_filter = GL.NEAREST,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true,
	})
	gl.RenderToTexture(tex, function()
		gl.Clear(GL.COLOR_BUFFER_BIT, 0,0,0,0)

		gl.BlendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
		gl.PushMatrix()
		if str:byte(2) then
			local font = fonts[fontSize or baseFontSize]
			glScale(2/(texSize+1), -2/(texSize+1), 1)          -- 1 unité = 1 pixel de la texture
			font:Begin(true)
			font:SetTextColor(1,1,1,1)
			font:Print(str, 0, 0, texSize*0.5, "cvno")   -- sans "B", inutile ici
			font:End()
		else
			-- gl.Blending(GL.ONE, GL.ZERO)
			gl.Scale(2/(texSize), -2/(texSize), 1)
			TextDrawCentered(str, 0,0)
		end
		gl.PopMatrix()
		gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	end)
	gl.DeleteTextureFBO(tex)
	return tex
end

local function CreateTextures()
	for _, obj in ipairs(glyphObjects) do
		obj.tex = MakeGlyphTex(obj.str, obj.fontSize or baseFontSize)
	end
end

local function CreateAtlas()
	local n_tex = 0
	local textures = {}
	local area = 0
	for _, obj in ipairs(glyphObjects) do
		if obj.tex then
			local info = glTextureInfo(obj.tex)
			if info.xsize <= 0 then
				Echo('['..widget.GetInfo().name .. '] Error with texture for ', obj.str)
			else
				area = area + info.xsize * info.ysize
				obj.xsize, obj.ysize = info.xsize, info.ysize
				n_tex = n_tex + 1
				textures[n_tex] = obj
			end
		end
	end

	if n_tex == 0 then
		Echo(sig .. 'No atlas to make (no valid textures)')
		return
	end

	local atlasMaxX = Spring.GetConfigInt("MaxTextureAtlasSizeX", 4096)
	local atlasMaxY = Spring.GetConfigInt("MaxTextureAtlasSizeY", 4096)

	local areaNeeded = math.ceil(area * 1.43) -- estimate it will be filled at 70%
	local tries = 0

	while n_tex > 0 do
		tries = tries + 1
		if tries > 40 then
			Echo('['..widget.GetInfo().name .. '] ' .. 'TOO MANY TRIES TO MAKE ATLASSES')
			useAtlas = false
			return false
		end
		local atlas_xsize, atlas_ysize = math.min(atlasMaxX, 2048), math.min(atlasMaxY, 2048)
		while atlas_xsize * atlas_ysize > areaNeeded do
			if (atlas_xsize/2) * atlas_ysize >= areaNeeded and atlas_xsize >= atlas_ysize and atlas_xsize > 512 then
				atlas_xsize = atlas_xsize/2
			elseif atlas_xsize * (atlas_ysize/2) >= areaNeeded and atlas_ysize >= atlas_xsize and atlas_ysize > 512 then
				atlas_ysize  = atlas_ysize/2
			else
				break
			end
		end

		local atlas = gl.CreateTextureAtlas(atlas_xsize, atlas_ysize, 2) --  0 (Legacy), 1 (Quadtree), 2 (Row)
		local n_atlas = #atlasses + 1
		local in_tex = 0
		local toFill = atlas_xsize * atlas_ysize
		local filled = 0
		local atlas_textures = {}

		for i = n_tex, 1, -1 do
			local texObj = textures[i]
			local texName = texObj.tex
			local xsize, ysize = texObj.xsize, texObj.ysize
			-- if (xsize > atlas_xsize and xsize > atlas_ysize) or (ysize > atlas_xsize and ysize > atlas_ysize) then -- if they can be rotated ?
			if (xsize > atlas_xsize or ysize > atlas_ysize) then
				Echo('['..widget.GetInfo().name .. '] ' .. 'Texture ' .. texName, 'size', xsize, ysize, 'cannot fit in atlas of size', atlas_xsize, atlas_ysize)
				useAtlas = false
				return false
			end
			local area = (xsize * ysize) * 1.43
			if filled + area > toFill then
				break
			end
			atlas_textures[texObj.tex] = texObj
			filled = filled + area
			in_tex = in_tex + 1
			glAddAtlasTexture(atlas, texName)
		end
		local floor = math.floor
		if in_tex > 0 and gl.FinalizeTextureAtlas(atlas) then
			local atlasInfo = glTextureInfo(atlas)
			local aw, ah = atlasInfo.xsize, atlasInfo.ysize -- real size of atlas is optimized and can take less space
			areaNeeded = areaNeeded - filled
			atlasses[n_atlas] = {tex = atlas, num = in_tex, id = atlasInfo.id, target = atlasInfo.target, textures = atlas_textures, xsize = aw, ysize = ah}
			for i = n_tex, n_tex - in_tex + 1, -1 do
				local obj = textures[i]
				local u1, u2, v1, v2 = glGetAtlasTexture(atlas, obj.tex)
				u1 = floor(u1 * aw) / aw -- u1, u2... is given at middle of texel
				v1 = floor(v1 * ah) / ah
				u2 = floor(u2 * aw) / aw
				v2 = floor(v2 * ah) / ah
				-- textures are mirrored on y in atlas
				v1, v2 = v2, v1
				obj.u1, obj.u2, obj.v1, obj.v2 = u1, u2, v1, v2
				obj.hw, obj.hh = obj.xsize/2, obj.ysize/2
				obj.atlas = atlas
			end
			n_tex = n_tex - in_tex
			Echo(sig..'Atlas ' .. atlas .. ' successfully created ' .. aw .. 'x' ..  ah, 'id ' .. atlasInfo.id, in_tex .. ' textures.')
			-- Echo('created atlas', n_atlas, 'size', atlas_xsize, atlas_ysize, 'textures in', in_tex)
		else
			Echo(sig .. 'Atlas Creation failed')
			glDeleteTextureAtlas(atlas)
			areaNeeded = areaNeeded * 1.20
		end
	end
	return true
end



local function DestroyGL() -- need modified gl.DeleteTextureAtlas due to engine bug (engine assign id according to number of atlas instead of unique ones)
	for i, atlasObj in pairs(atlasses) do
		if atlasObj.tex then
			local atlasInfo = glTextureInfo(atlasObj.tex)
			if not atlasInfo or atlasInfo.id ~= atlasObj.id or atlasInfo.xsize ~= atlasObj.xsize or atlasInfo.ysize ~= atlasObj.ysize then
				-- should never happen now with the workaround
				Echo(sig .. 'Not deleting atlas ' .. atlasObj.tex, 'id '..tostring(atlasInfo and atlasInfo.id), 'it\' s not our own')
			else
				glDeleteTextureAtlas(atlasObj.tex)
			end
			atlasObj.tex = nil
		end
		atlasses[i] = nil
	end
	if globalList then
		glDeleteList(globalList)
	end
	globalList = nil
	-- if font then
	-- 	gl.DeleteFont(font)
	-- 	font = nil
	-- end

	currentAtlas = false

	for _, obj in ipairs(glyphObjects) do
		if obj.tex then
			gl.DeleteTexture(obj.tex)
			obj.tex = nil
		end
		if obj.list then
			glDeleteList(obj.list)
			obj.list = nil
		end
		obj.atlas = nil
	end
	for k, list in pairs(numberLists) do
		glDeleteList(list)
		numberLists[k] = nil
	end
	lastView = nil
end

local function InitGL()
	DestroyGL()

	for _, obj in ipairs(symbolObjects) do
		if obj.str:byte(2) then
			local fontSize = obj.fontSize or baseFontSize
			local font = fonts[fontSize]
			if not font then
				font = gl.LoadFont(FONT_NAME, fontSize, 2 * fontSize / baseFontSize, 20 * fontSize / baseFontSize)
				font:SetOutlineColor({0,0,0,1})
				font:SetAutoOutlineColor(false)
				fonts[fontSize] = font
			end
		end
	end
	if WG.MyFont then
		-- list work with own fontHandler (2 times faster) then 50% even faster using global list if view doesn't change
		fontHandler = WG.MyFont -- it's a copy of mod_font.lua as widget, a parallel fontHandler that  doesn't reset the cache over time since there's no update
		GetListCentered = WG.MyFont.GetListCentered
	end
	UseFont = fontHandler.UseFont
	UseFont(monobold)
	objNumbers.adv = fontHandler.GetTextWidth('0')
	objNumbers.adv = floor(objNumbers.adv + 0.5)
	TextDrawCentered = fontHandler.DrawCentered
	-- preloading
	for _, obj in ipairs(glyphObjects) do
		if not obj.str:byte(2) then
			TextDrawCentered(obj.str, 0,0) -- preload the font
		end
	end
	--
	useGlobalList = true

	for i = 1, 100 do
		if numberLists[tostring(i)] then -- FIXME: can't make lists during a list creation so I have to do it outside
			-- list created
		end
	end

	if NEW_METHOD then
		CreateTextures()
		CreateAtlas()
	end

	for _, obj in ipairs(symbolObjects) do
		if NEW_METHOD then
			obj.Draw = function(self, mx,my, color, alpha)
				if currentAtlas ~= self.atlas then
					currentAtlas = self.atlas
					glTexture(0, currentAtlas)
				end
				local a = alpha or color[4]
				if color ~= lastColor or a ~= lastA then
					lastColor, lastA = color, a
					glColor(color[1]*a, color[2]*a, color[3]*a, a)
				end
				local x, y = floor(mx + self.offX + 0.5) , floor(my - self.offY - (useFinePos and 4 or 0) + 0.5)
				local w, h = self.hw, self.hh
				w, h = w * scale, h * scale
				glTexRect(x - w, y - h, x + w, y + h, self.u1, self.v1, self.u2, self.v2)
				-- TODO Delete individual textures once tests are not needed
				-- glTexture(0, self.tex)
				-- glTexRect(x - w, y - h, x + w, y + h)
			end
		elseif GetListCentered then
			obj.list = GetListCentered(obj.str)
			obj.Draw = function(self, mx,my,color, alpha)
				glColor(color[1], color[2], color[3], alpha or color[4])
				glPushMatrix()
				glTranslate(floor(mx + self.offX + 0.5) , floor(my - self.offY - (useFinePos and 4 or 0) + 0.5) , 0)
				glScale(scale, scale, 0)
				glCallList(self.list)
				glPopMatrix()
			end
		else
			obj.Draw = function(self, mx,my,color, alpha)
				glColor(color[1], color[2], color[3], alpha or color[4])
				glPushMatrix()
				glScale(scale, scale, 0)
				TextDrawCentered(self.str, floor(mx + self.offX + 0.5) , floor(my - self.offY - (useFinePos and 4 or 0) + 0.5))
				glPopMatrix()
			end
		end
	end
	if NEW_METHOD then
		objNumbers.Draw = function(self, mx,my, color, alpha, numbers)
			local a = alpha or color[4]
			local a = alpha or color[4]
			if color ~= lastColor or a ~= lastA then
				lastColor, lastA = color, a
				glColor(color[1]*a, color[2]*a, color[3]*a, a)
			end
			local n, w = #numbers, self.adv
			local y = floor(my - self.offY - (useFinePos and 4 or 0) + 0.5)
			local half = floor(w * 0.5)
			local x0 = floor(mx + self.offX + 0.5) - floor(n * w * 0.5)
			local digits = self.digits
			for k = 1, n do
				local d = digits[numbers:byte(k)]
				if d then
					if currentAtlas ~= d.atlas then
						currentAtlas = d.atlas
						glTexture(0, currentAtlas)
					end
					local x = x0 + (k - 1) * w + half
					glTexRect(x - d.hw, y - d.hh, x + d.hw, y + d.hh, d.u1, d.v1, d.u2, d.v2)
				end
			end
		end
	elseif GetListCentered then
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
		globalList = 0
	end
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


local minus, plus = 269, 270

function widget:KeyPress(key, mods)
	if not initialized then
		return
	end
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

function widget:GameFrame(f)
	currentFrame = f
end

function widget:DrawScreenEffects()
	if not initialized then
		InitGL()
		initialized = true
	end

	if globalList then
		if lastView ~= NewView[5] then -- 50% faster
			glDeleteList(globalList)
			globalList = glCreateList(SafeGlobalDraw)
		end
		glCallList(globalList)		
	else
		SafeGlobalDraw()
	end
	lastView = NewView[5]
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

function MorphStart(unitID)-- BUG the first ever Morph Start of the game is never registered, so we use MorphUpdate to cope
	morphing[unitID] = true
end
local done = false
function MorphUpdate(morphTable) 
	if not done then
		for unitID in pairs(morphTable) do
			MorphStart(unitID)
		end
		done = true
	end
end
function MorphStop(unitID)
	morphing[unitID] = nil
end
function MorphFinished(unitID)
	morphing[unitID] = nil
end

local verifTime = 0
function widget:Update(dt)
	verifTime = verifTime + dt
	if verifTime >= 1 then
		verifTime = 0
		local a = atlasses[1]
		if a then
			local info = glTextureInfo(a.tex)
			if not info or info.xsize ~= a.xsize or info.ysize ~= a.ysize then
				Echo(sig .. 'Invalid atlas ! Something gone wrong', 'assumed size', a.xsize .. 'x' .. a.ysize, 'size of atlas ' .. a.tex, tostring(info and info.xsize) .. 'x' .. tostring(info and info.ysize) , 'rebuilding')
				initialized = false
				return
			end
		end
	end
end

function widget:Initialize()
	currentFrame = spGetGameFrame()
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

	widgetHandler:RegisterGlobal(widget, 'MorphStart', MorphStart)
	widgetHandler:RegisterGlobal(widget, 'MorphUpdate', MorphUpdate)
	widgetHandler:RegisterGlobal(widget, 'MorphStop', MorphStop)
	widgetHandler:RegisterGlobal(widget, 'MorphFinished', MorphFinished)

end


function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
	end
end

function widget:Shutdown()


	DestroyGL()
	for fontSize, font in pairs(fonts) do
		gl.DeleteFont(font)
		fonts[fontSize] = nil
	end
	widgetHandler.actionHandler:RemoveAction(widget,'showpropicon')
	widgetHandler:DeregisterGlobal(widget, 'MorphStart', MorphStart)
	widgetHandler:DeregisterGlobal(widget, 'MorphUpdate', MorphUpdate)
	widgetHandler:DeregisterGlobal(widget, 'MorphStop', MorphStop)
	widgetHandler:DeregisterGlobal(widget, 'MorphFinished', MorphFinished)	
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
