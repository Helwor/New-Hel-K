

function widget:GetInfo()
	return {
		name      = "Persistent Build Height 2",
		desc      = "Advanced Teraform Build UI, work in tandem with draw_placement.lua",
		author    = "Helwor",
		version   = "v1",
		date      = "7th June, 2016",
		license   = "GNU GPL, v2 or later",
		layer     = -10000, -- before mex placement handler
		enabled   = true,
		handler   = true,
--      api = true,
		requiring = { -- IMPLEMENT SYSTEM TO TRACK DEPENDENCIES
			['EPIC Menu'] = 'modVanilla',
		},
	}
end
-- SEE ud.customParams.pylonrange for grid range
widget.requiring = widget.GetInfo().requiring
local Echo = Spring.Echo


SPECIFIED_MEMORY = false --  we don't need it anymore, but this enable specific memory holed heights after placing and specific persistent heights over game




local buildHeight = {}



include("keysym.lua")
VFS.Include(LUAUI_DIRNAME ..'/Widgets/Include/weap_ranges.lua')
local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua", nil, VFS.GAME)
local _, ToKeysyms = include("Configs/integral_menu_special_keys.lua")

--------------------------------------------------------------------------------
-- Speedups
--------------------------------------------------------------------------------

-- local GetDef					= f.GetDef
--local CheckReach				= f.CheckReach
-- local CheckCanSub			= f.CheckCanSub
local UniTraceScreenRay			= f.UniTraceScreenRay
local SpiralSquare				= f.SpiralSquare
local TestBuild					= f.TestBuild
--local GetDirection			= f.GetDirection
--local plusMin					= f.plusMin
--local table					= f.table
-- local l						= f.l
-- local GetInsertPosOrder		= f.GetInsertPosOrder
-- local GetPosOrder			= f.GetPosOrder
-- local IsEqual				= f.IsEqual
-- local GetTeamUnits			= f.GetTeamUnits
-- local QueueChanged			= f.QueueChanged
-- local Page					= f.Page
local GetCameraHeight			= f.GetCameraHeight
local getconTable				= f.getconTable
-- local IdentifyPlacement		= f.IdentifyPlacement
local getcons					= f.getcons
local MultiInsert				= f.MultiInsert
-- local Overlapping			= f.Overlapping
local GetCommandPos				= f.GetCommandPos
-- local deepcopy				= f.deepcopy
-- local CheckTime				= f.CheckTime
local MakeOptions				= f.MakeOptions
local ClampMousToMinimap		= f.ClampMousToMinimap

local spGetActiveCommand		= Spring.GetActiveCommand
local spSetActiveCommand		= Spring.SetActiveCommand
local spGetMouseState			= Spring.GetMouseState
-- local spTraceScreenRay          = Spring.TraceScreenRay
local spGetGroundHeight			= Spring.GetGroundHeight
local spGetGroundOrigHeight		= Spring.GetGroundOrigHeight
local spGetSelectedUnits		= Spring.GetSelectedUnits
local spGetModKeyState			= Spring.GetModKeyState
-- local spGetUnitTeam             = Spring.GetUnitTeam

local spGetAllUnits				= Spring.GetAllUnits
local spGetCommandQueue			= Spring.GetCommandQueue
local spGiveOrderToUnit			= Spring.GiveOrderToUnit
local spGiveOrderToUnitArray	= Spring.GiveOrderToUnitArray
local spSendCommands			= Spring.SendCommands
local spTestBuildOrder			= Spring.TestBuildOrder
local spGetBuildFacing			= Spring.GetBuildFacing
-- local spGetGroundBlocked		= Spring.GetGroundBlocked
local spGetTimer				= Spring.GetTimer
local spDiffTimers				= Spring.DiffTimers
local spClosestBuildPos			= Spring.ClosestBuildPos
-- local spGetCameraState		= Spring.GetCameraState
local spValidUnitID				= Spring.ValidUnitID
local spGetUnitDefID			= Spring.GetUnitDefID
-- local spPos2BuildPos			= Spring.Pos2BuildPos
local spGetBuildSpacing			= Spring.GetBuildSpacing
-- local spGetGameSeconds		= Spring.GetGameSeconds
local spFindUnitCmdDesc			= Spring.FindUnitCmdDesc
local spGetUnitIsDead			= Spring.GetUnitIsDead
local spGetUnitPosition			= Spring.GetUnitPosition

-- local spuAndBit				= Spring.Utilities.AndBit
local spuCheckBit				= Spring.Utilities.CheckBit
--local spuGetUnitCanBuild		= Spring.Utilities.GetUnitCanBuild -- (id, defID to build)
local spGetUnitCurrentCommand	= Spring.GetUnitCurrentCommand
local spIsAboveMiniMap			= Spring.IsAboveMiniMap


local UnitDefs = UnitDefs

local function IdentifyPlacement(pid, facing)
	return WG.PlacementModule:Measure(pid, facing)
end

-- for k,v in pairs(Game) do
--     if k:lower():match('map') or k:lower():match('form') then
--         Echo(k,v)
--     end
-- end
local widgets = { -- stored handles of some external widgets
	building_starter = false,
	guard_remove = false,
	ctrl_morph = false,
	fix_autoguard = false,
	mex_placement = false,
	command_insert = false,
	drawing_placement = false,
}

local floor = math.floor
local ceil = math.ceil
local min, max = math.min, math.max
local abs = math.abs
local round = function(x,n) return tonumber(math.round(x,n)) end
local nround = f.nround
local mol = function(a,b,tol) return abs(a-b)<=tol end -- More Or Less function
local toggleHeight   --= KEYSYMS.B
local heightIncrease --= KEYSYMS.C
local heightDecrease --= KEYSYMS.V

local SEND_DELAY = 0.8 -- the max time it would take between order given and order received in synced
local CMD_INSERT    = CMD.INSERT
local CMD_OPT_ALT   = CMD.OPT_ALT
local CMD_OPT_SHIFT = CMD.OPT_SHIFT
local CMD_OPT_INTERNAL = CMD.OPT_INTERNAL -- using OPT_INTERNAL prevent from Repeat state to operate
local CMD_REPAIR = CMD.REPAIR
-- f.Page(Spring.GetModOptions())
local EMPTY_TABLE = {}
local XYZ_TABLE = {}
local XYZP_TABLE = {}
local CTRL_TABLE = {ctrl = true}
local INSERT_TABLE = {[3]=--[[CMD_OPT_INTERNAL+--]]CMD_OPT_SHIFT}

local elevRangeDraw = {
	color = {0.75, 0.75, 0.2, 0.9},
	defID = false,
	wDef = false,
	radius = false,
	verts = false,
	update = false,
}

local useMinimap = false

-- previously local INSERT_TABLE = {[3]=CMD_OPT_SHIFT}



local myTeamID = Spring.GetMyTeamID()
-- local sDefID = Spring.GetTeamRulesParam(myTeamID, "commChoice") or UnitDefNames.dyntrainer_strike_base.id-- Starting unit def ID



local opt = {
	findPlatform = true,
	force_wind_no_terra = true,
	auto_fix_mex = true,
}

local dbg_options_path = 'Hel-K/' .. widget:GetInfo().name
------------- DEBUG CONFIG
local Debug = { -- default values
	active = false, -- no debug, no other hotkey active without this
	global = true, -- global is for no key : 'Debug(str)'
	reload = true,
	elevChange = false,
	platform = false,
	ownPlat = false,
	modPH = false,
	PH = false,
	fixMex = false,
}
-- Debug.hotkeys = {
--     active =            {'ctrl','alt','S'} -- this hotkey active the rest
--     ,global =           {'ctrl','alt','G'}

--     ,elevChange =       {'ctrl','alt','L'}
--     ,ownPlat =          {'ctrl','alt','H'}
--     ,reload =           {'ctrl','KP6'}
-- }
-------------

local weapRanges = WG.weapRanges

-- local CI_Disabled

local dumfunc = function() end

-- local HOOKS = {}
local function HotkeyChangeNotification()
	local key = WG.crude.GetHotkeyRaw("epic_persistent_build_height_hotkey_toggle")
	toggleHeight = ToKeysyms(key and key[1])
	key = WG.crude.GetHotkeyRaw("epic_persistent_build_height_hotkey_raise")
	heightIncrease = ToKeysyms(key and key[1])
	key = WG.crude.GetHotkeyRaw("epic_persistent_build_height_hotkey_lower")
	heightDecrease = ToKeysyms(key and key[1])
end
-- f.Page(Game,{all=true})
---------------------------------
-- Epic Menu
---------------------------------
--local commandPanelPath = 'Hotkeys/Command Panel'
--local customGridPath = 'Hotkeys/Command Panel/Custom'
local helkpath = 'Hel-K/' .. widget:GetInfo().name
local hotkeyPath = "Hotkeys/Construction"
options_path = 'Settings/Interface/Building Placement'
options_order = {   
	'enterSetHeightWithB', 'altMouseToSetHeight', 'label_structure', 'hotkey_toggle', 'hotkey_raise', 'hotkey_lower',
	'auto_fix_mex', 'force_wind_no_terra',
}
if SPECIFIED_MEMORY then
	table.insert(options_order, 'rmbHeightOverGame')
	table.insert(options_order, 'forgetHeightAfterPlacing')
end
-- Working but no need anymore
-- Heights to retain over games
local heightsNamesToRmbOverGames = {
	staticradar = true,
	turrettorp = true,
	staticheavyradar = true,
}
-- Height we forget immediately after placing
local heightsNamesToForgetAfterPlacing = {
	turretlaser = true,
}
local toForgetOnShiftRelease = false
local heightsToRmbOverGames = {}
local heightsToForgetAfterPlacing = {}

function heightsToRmbOverGames:Update(names)
	for k,v in pairs(self) do
		if k ~= 'Update' then
			self[k] = nil
		end
	end
	for name, bool in pairs(names) do
		local validName = UnitDefNames[name] and name
		if not validName then
			for defID, def in pairs(UnitDefs) do
				local humanName = def.humanName
				if humanName and humanName:lower():match(name:lower()) then
					validName = def.name
					names[validName] = true
				end
			end
			names[name] = nil
		end
		if validName and bool then
			self[UnitDefNames[validName].id] = true
		end
	end
end
heightsToForgetAfterPlacing.Update = heightsToRmbOverGames.Update

heightsToRmbOverGames:Update(heightsNamesToRmbOverGames)
heightsToForgetAfterPlacing:Update(heightsNamesToForgetAfterPlacing)
--
options_path_alphabetical = { ['Hel-K'] = true }
options = {
	enterSetHeightWithB = {
		name = "Toggle set height",
		type = "bool",
		value = true,
		noHotkey = true,
		desc = "Press a hotkey (default B) while placing a structure to set the height of the structure. Keys C and V increase or decrease height."
	},
	altMouseToSetHeight = {
		name = "Alt mouse wheel to set height",
		type = "bool",
		value = true,
		noHotkey = true,
		desc = "Hold Alt and mouse wheel to set height."
	},
	label_structure = {
		type = 'label',
		name = 'Terraform Structure Placement',
		path = hotkeyPath
	},
	hotkey_toggle = {
		name = 'Toggle Structure Terraform',
		desc = 'Press during structure placement to make a strucutre on a spire or a hold. Alt + MMB also toggles this mode.',
		type = 'button',
		hotkey = "B",
		bindWithAny = true,
		dontRegisterAction = true,
		OnHotkeyChange = HotkeyChangeNotification,
		path = hotkeyPath,
	},
	hotkey_raise = {
		name = 'Raise Structure Teraform',
		desc = 'Increase the height of structure terraform. Also possible with Alt + Scrollwheel.',
		type = 'button',
		hotkey = "C",
		bindWithAny = true,
		dontRegisterAction = true,
		OnHotkeyChange = HotkeyChangeNotification,
		path = hotkeyPath,
	},
	hotkey_lower = {
		name = 'Lower Structure Terraform',
		desc = 'Decrease the height of structure terraform. Also possible with Alt + Scrollwheel.',
		type = 'button',
		hotkey = "V",
		bindWithAny = true,
		dontRegisterAction = true,
		OnHotkeyChange = HotkeyChangeNotification,
		path = hotkeyPath,
	},
	--------------------
	auto_fix_mex = {
		name = "Auto Fix Mex",
		type = "bool",
		value = opt.auto_fix_mex,
		noHotkey = true,
		desc = 'Level ground if mex spot is found to be unfit after being ordered',
		OnChange = function(self)
			opt[self.key] = self.value
		end,
		path = helkpath,
	},
	force_wind_no_terra = {
		name = 'Force no terra on wind',
		desc = 'When placing first wind on a too steep slope, look around to find a better place',
		type = 'bool',
		value = opt.force_wind_no_terra,
		OnChange = function(self)
			opt[self.key] = self.value
		end,
		path = helkpath,
	},
	
}
--global
if SPECIFIED_MEMORY then
	options.rmbHeightOverGame = {
		name = 'Persistent heights',
		desc = 'Set Particular type of build for which widget should remember their heights',
		type = 'table',
		value = heightsNamesToRmbOverGames,
		preTreatment = function(t)
			-- local toNames = {}
			-- Echo('before')
			-- for k,v in pairs(t) do
			--     Echo(k,v)
			--     if UnitDefs[k] then
			--         toNames[UnitDefs[k].name] = true
			--     end
			--     t[k] = nil
			-- end
			-- for name in pairs(toNames) do
			--     table.insert(t, name)
			-- end
		end,
		postTreatment = function(t)

			-- local toDefID = {}
			-- for k, name in pairs(t) do
			--     if UnitDefNames[name] then
			--         toDefID[UnitDefNames[name].id] = true
			--     end
			--     t[k] = nil
			-- end
			-- for defID in pairs(toDefID) do
			--     t[defID] = true
			-- end
			
		end,
		OnChange = function(self)
			heightsToRmbOverGames:Update(self.value)
		end,
		path = helkpath,
	}
	options.forgetHeightAfterPlacing = {
		name = 'Memory Holed height',
		desc = 'Set Particular type of build for which widget forget after placing',
		type = 'table',
		value = heightsNamesToForgetAfterPlacing,
		postTreatment = function(t)

			-- local toDefID = {}
			-- for k, name in pairs(t) do
			--     if UnitDefNames[name] then
			--         toDefID[UnitDefNames[name].id] = true
			--     end
			--     t[k] = nil
			-- end
			-- for defID in pairs(toDefID) do
			--     t[defID] = true
			-- end
			
		end,
		OnChange = function(self)
			heightsToForgetAfterPlacing:Update(self.value)
		end,
		path = helkpath,
	}

end

-- local oldSpringSetActiveCommand
-- do--- DEBUG FAST lotus place after release of another PID, check where the PID got cancelled

--     local lotusDefID = UnitDefNames['turretlaser'].id
--     local oldSpringSetActiveCommand = Spring.SetActiveCommand
--     Spring.SetActiveCommand = function(n, ...)
--         if (n == 0 or n == -1 or n == nil) and
--             select(2, Spring.GetActiveCommand()) == -lotusDefID then
--                 Echo('=====> SET',n,'PID',PID, table.toline(Spring.GetPressedKeys()))
--                 Echo(debug.traceback():sub(1,700))
--         end
--         return oldSpringSetActiveCommand(n, ...)
--     end
--     spSetActiveCommand = Spring.SetActiveCommand
-- end




--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
VFS.Include("LuaRules/Configs/customcmds.h.lua")

local mexDefID = UnitDefNames["staticmex"].id
local geoDefID = UnitDefNames["energygeo"].id
local windDefID = UnitDefNames['energywind'].id
local lotusDefID = UnitDefNames['turretlaser'].id


local FACTORY_RANGE_SQ = VFS.Include("gamedata/unitdefs_pre.lua", nil, VFS.GAME).FACTORY_PLATE_RANGE^2
local plateDefID = {}
for defID, def in pairs(UnitDefs) do
	if def.name:match('^plate') then
	   plateDefID[defID] = UnitDefNames[def.customParams.child_of_factory].id
	end
end
specialAboveWaterDefID = {
	[UnitDefNames['turrettorp'].id] = true,
}

local INCREMENT_SIZE = 20
local MAX_SEND = 20 -- maximum orders to send per update round

local timeBlockDuplicate -- work around to prevent user spamming mex to get cancelled

--------------------------------------------------------------------------------
-- Local Vars
--------------------------------------------------------------------------------
-- local ghosts = WG.ghosts
local Points={} -- debugging
local PID
local g = {
	lava = (Game.waterDamage or 0) > 3,
	noterra = not Game.mapDamage or string.find((Game.modName or ''):lower(), 'arena mod'),
	modArena = string.find((Game.modName or ''):lower(), 'arena mod'),
	timeOutNoTerra = 0,
	NEW_PID = true,
	BRIEF_SNAP = false,
}

local OFF_WATER = g.lava and 4 or 0.1



local Cam
--local g.preGame=true
g.preGame=Spring.GetGameFrame() <= 1 -- FIXME: it should be <3 or check the Initial Queue Widget WG

local spotsPos

local maxx,maxz = Game.mapSizeX, Game.mapSizeZ


local myPlatforms = {} -- platform manager
local groundModule = {offsetPH = nil} -- !! offsetPH == nil means it is available for modification, offsetPH == false means it has been used and is locked for that position



-- registering the originalHeight, work-around for randomly generated map where Spring.GetGroundOrigHeight cannot be used
local origHeightMap

local placementHeight = 0

-- local origHeight = 0
local height=0
local level = 0


local mustTerraform = false
local needTerra, sloppedTerrain = false, false
local blockingStruct = false


WG.movedPlacement=WG.movedPlacement or {-1}

local movedPlacement = WG.movedPlacement
local CheckTerra

-- local onOwnPlatform

local ignoreFirst = false


 -- project to better the snapping and elevation management
local delayedOrders = {}

local surround = false
local offmap = false
--local eSpec = {398,400,401} -- special treatment for solar, windgen and energy pylon
--local special = false
local specs = {}
local specCount = 1
local inRadiusPlacement = false
local mexes = {}

local forceResetAcom = false
local workOnRelease = false

local water = false

local floater = false
local hold = false
local snapTime = spGetTimer()
local ordered = false

local currentCommand


local prevMx, prevMy
local p = {
	facing=false
	,footX=false
	,footZ=false
	,oddX=false
	,oddZ=false
	,sizeX=false
	,sizeZ=false
	,terraSizeX=false
	,terraSizeZ=false
	,spacing=false
	,floater=false
}

local prev = {
	x = -1,
	z = -1,
}




local duplicate = {}



local alt,ctrl,shift,meta=false,false,false

local spacing = false

local insertBuild = false
local leftClick = false
local rightClick = false

local cons = getcons()
local conTable = getconTable()

local drawWater = false

g.toggleEnabled = false

local pointX = false
local pointY = 0
local pointZ = 0

-- local check=CheckTime('start')

local geos = WG.geos or {map={}}
function geos:Map() -- to be run after widgets loaded
	local spGetFeatureDefID = Spring.GetFeatureDefID
	local spGetFeaturePosition = Spring.GetFeaturePosition
	for i,fID in ipairs(Spring.GetAllFeatures()) do
		if FeatureDefs[spGetFeatureDefID(fID)].geoThermal then
			local fx, fy, fz = spGetFeaturePosition(fID)
			fx,fz = (floor(fx/16)+0.5) * 16,(floor(fz/16)+0.5) * 16
			if fx>maxx-40 then fx = maxx - 40 elseif fx < 40 then fx = 40 end
			if fz>maxz-40 then fz = maxz - 40 elseif fz < 40 then fz = 40 end

			-- Points[#Points+1]={fx,fy,fz}
			local thisgeo = {x = fx, z = fz}
			geos[#geos+1] = thisgeo
			local map = geos.map
			for x=fx-32,fx+32,16 do
				if x>=40 or x<=maxx-40 then
					if not map[x] then map[x]={} end
					for z=fz-32,fz+32,16 do
						if z>=40 or z<=maxz-40 then
							map[x][z]=thisgeo
						end
					end
				end
			end
		end
	end
	return map
end

function geos:GetClosest(x,z,dist)
	if not dist then dist=math.huge end
	local spot
	for i,thisspot in ipairs(self) do
		local thisdist = ((thisspot.x-x)^2+(thisspot.z-z)^2)^0.5
		if thisdist<dist then
			spot,dist=thisspot,thisdist
		end
	end
	return spot,dist
end

local function CheckPlateReach(lot, PID)
	local parentDefID = plateDefID[PID]
	local len = #lot
	local remaining = len
	if WG.queuedFactories then
		if os.clock() - WG.queuedFactoriesUpdateTime < 4 then
			for id, data in pairs(WG.queuedFactories) do
				if data.unitDefID == parentDefID then
					for i, p in ipairs(lot) do
						if not p.inreach then
							if ((p[1] - data.x)^2 + (p[2] - data.z)^2) < FACTORY_RANGE_SQ then
								p.inreach = true
								remaining = remaining - 1
								if remaining == 0 then
									return true
								end
							end
						end
					end
				end
			end
		end
	end
	for i, team in ipairs(Spring.GetTeamList()) do
		if Spring.AreTeamsAllied(team, myTeamID) then
			for i,fid in ipairs(Spring.GetTeamUnitsByDefs(team,parentDefID)) do
				local fx,fy,fz = spGetUnitPosition(fid)
				for i, p in ipairs(lot) do
					if not p.inreach then
						if ((p[1] - fx)^2 + (p[2] - fz)^2) < FACTORY_RANGE_SQ then
							p.inreach = true
							remaining = remaining - 1
							if remaining == 0 then
								return true
							end
						end
					end
				end
			end
		end
	end
	return remaining ~= len -- has any plate pos in reach of factory
end

local GetWindAt
do 

	local spGetGameRulesParam = Spring.GetGameRulesParam
	local max = math.max
	local windMin = spGetGameRulesParam("WindMin")
	local windMax = spGetGameRulesParam("WindMax")
	local windGroundMin = spGetGameRulesParam("WindGroundMin")
	local windGroundSlope = spGetGameRulesParam("WindSlope")
	local windMinBound = spGetGameRulesParam("WindMinBound")
	local tidalHeight = spGetGameRulesParam("tidalHeight")
	local econMultEnabled = (spGetGameRulesParam("econ_mult_enabled") and true) or false
	local mult = econMultEnabled and (spGetGameRulesParam("econ_mult_" .. (Spring.GetMyAllyTeamID() or ""))) or 1
	local tidalInc = round(UnitDefNames['energywind'].customParams.income_energy * mult,1)
	GetWindAt = function(y)
		if y <= tidalHeight then
			return false,tidalInc
		else
			local minWindIncome = (windMin + (windMax - windMin)*max(0, min(windMinBound, windGroundSlope*(y - windGroundMin))))
			local curIncome = minWindIncome+(windMax-minWindIncome)*spGetGameRulesParam('WindStrength')
			return   round(minWindIncome * mult, 1)
					,round(curIncome * mult,2)
					,round(windMax * mult,1)
					,round( (minWindIncome+(windMax-minWindIncome)/2) * mult, 1 )
					,mult
		end
	end

end


local function CheckGeos(px,pz)
	local _px, _pz = px,pz
	local spot
	if spTestBuildOrder(geoDefID, px, 0, pz, 0)==0 then
		local geoX,_,geoZ = spClosestBuildPos(0,geoDefID, px, 0, pz, 600 ,0 ,0)
		if geoX>-1 then
			px,pz = geoX,geoZ
			spot = geos.map[geoX] and geos.map[geoX][geoZ]
		else
			spot = geos:GetClosest(px,pz,600)
			if spot then
				px,pz = spot.x,spot.z
			end
		end
	else
		spot = geos.map[px] and geos.map[px][pz]
	end
	return px,pz,spot
end

local function FindPlacementAround(px,pz,placed,pid,_p,lookingForFlat,customElev,dontRegister)
	local p = _p or pid and IdentifyPlacement(pid) or p
	local customPID = pid
	pid = pid or PID
	local movedPlacement = movedPlacement
	if dontRegister then
		movedPlacement = {}
	end
	movedPlacement[1] = -1
	-- Echo("lookingForFlat is ", lookingForFlat)
	-- this part work faster if we just wanna avoid bumbps to place a build without elevation
	if lookingForFlat then
		local movx, movy, movz = spClosestBuildPos(0,pid, px, 0, pz, 16*7 ,0 ,p.facing)
		if movx and movx > -1 then
			if not plateDefID[PID] or CheckPlateReach({{movx, movz}}, PID) then
				needTerra = CheckTerra(movx, movz, customPID and pid, placed, _p, customElev)
				if not dontRegister then
					pointX, pointY, pointZ = movx, movy, movz
				end
				movedPlacement[1], movedPlacement[2], movedPlacement[3] = pointX, pointY, pointZ
				return movedPlacement[1], movedPlacement[3]
			end
		end
		return
	end

	-- NEW METHOD with disregarding steepness 
	-- LOOP iterating squares clockwise from center to exterior, starting at bottom left corner
	local found = {}
	local minDist = math.huge
	local thisNeedTerra
	-- just simulating
	local dismiss = {}
	local sizeX, sizeZ = p.sizeX, p.sizeZ
	local find = function(layer,offx,offz)
		local movx, movz, offmap = groundModule:clamp(px+offx, pz+offz, sizeX, sizeZ)
		if offmap then
			return
		end
		-- Echo('passed')
		local fDist=(movx-px)^2 + (movz-pz)^2
		if found.layer and layer>found.layer+2 then
			return true
		end
		for block in pairs(dismiss) do
			local blX, blZ, blSX, blSZ = block[1], block[2], block[3], block[4]
			local dx,dz = (movx-blX)^2, (movz-blZ)^2
			--check for overlap on found blocking struct so we don't redo all the job
			if dx < (sizeX+blSX)^2 and dz < (sizeZ+blSZ)^2 then
				return
			end
		end
		-- Points[#Points+1]={movx,pointY,movz} -- for debugging
		if fDist < minDist then 
			if not plateDefID[PID] or CheckPlateReach({{movx, movz}}, PID) then
				local _needTerra = CheckTerra(movx, movz, customPID and pid, placed, _p, customElev)
				-- Echo("#Points,blockingStruct is ", #Points,blockingStruct)
				if blockingStruct then
					dismiss[blockingStruct] = true
				else
					if not lookingForFlat or not sloppedTerrain then
						thisNeedTerra = _needTerra
						minDist, found.layer = fDist, layer
						found[1], found[2], found[3] = movx, pointY, movz
					end
				end
			end
		end
	end
	local layers = pid == geoDefID and 2 or wantNoTerra and 12 or 7
	SpiralSquare(layers,16,find)

	if found[1] then
		-- needTerra = CheckTerra(found[1],found[3],customPID and pid,placed)
		if not dontRegister then
			needTerra = thisNeedTerra
			pointX,pointY,pointZ = found[1],found[2],found[3]
		end
		movedPlacement[1], movedPlacement[2], movedPlacement[3] = pointX, pointY, pointZ

	end
	return found[1], found[3]
end
WG.FindPlacementAround = FindPlacementAround


--
function groundModule:ValidPlacement(x,z,pid,_p)
	local p = _p or pid and IdentifyPlacement(pid) or p
	x,z,offmap = self:clamp(x,z,p.sizeX,p.sizeZ)
	return floor((x + 8 - p.oddX)/16)*16 + p.oddX, floor((z + 8 - p.oddZ)/16)*16 + p.oddZ
end
function groundModule:clamp(x,z,sizeX,sizeZ)
	local offx = x-sizeX<0 and sizeX or x>maxx-sizeX and maxx-sizeX
	local offz = z-sizeX<0 and sizeZ or z>maxz-sizeZ and maxz-sizeZ
	return offx or x,
		   offz or z,
		   offx or offz
end
function groundModule:Init()
	self.snapTolerance = INCREMENT_SIZE*0.5
	self.sortFunc = function(a,b) return a<b end
end
function groundModule:Update(x,z,_p)
	local height = spGetGroundHeight(x,z) 
	local origHeight = (origHeightMap and origHeightMap[x][z] or spGetGroundOrigHeight(x,z)) or height 
	local modHeight     = height~=origHeight and height - origHeight --origHeight and height-origHeight -- diff more or less by 10 which is the max before having to terraform

	self.height = height
	self.origHeight = origHeight
	self.modHeight      = modHeight
	self.elevated       = modHeight and modHeight >= 7
	self.subelevated    = modHeight and modHeight <= -7
	self:UpdateRefHeights(_p or p)
end
function groundModule:UpdateRefHeights(p)
	-- defining reference height that will be used to apply placementHeight on
	-- defining max height that will tell us if a building should be leveled
	local minGround = min(self.origHeight, self.height)
	if not p.underSea then
		minGround = max(OFF_WATER, minGround)
	end
	local maxGround = max(self.origHeight, self.height)
	if not p.underSea then
		maxGround = max(OFF_WATER, maxGround)
	end



	self.minGround, self.maxGround = minGround, maxGround

end

function groundModule:GetSnapOrder(target)
	Debug.elevChange('GetSnapOrder for target', target)
	-- Making a table that will tell us the next snap level if there's one and correct the offset to go
	local tol = self.snapTolerance
	local debug = Debug.elevChange()
	local rHeight, rOrigHeight, rTarget = round(self.height), round(self.origHeight), round(target)

	if rTarget == 0 then
		rTarget = OFF_WATER
	end
	local water = mol(rTarget,0,tol) and not (p.floater) and rTarget or OFF_WATER
	-- if rTarget == 0 then
	--     rTarget = OFF_WATER
	-- end
	-- local water = OFF_WATER
	if rHeight <= tol and (p.floater) then
		rHeight = water
	end
	if rOrigHeight<=tol and (p.floater) then
		rOrigHeight = water
	end
	-- Echo("rHeight,rOrigHeight,rTarget is ", rHeight,rOrigHeight,rTarget,mol(rHeight,rOrigHeight,7),mol(rHeight,rOrigHeight,7) and rOrigHeight or rHeight,mol(rHeight,rOrigHeight,7) and rHeight or rOrigHeight)

	local uniqueVals = {
		[mol(rHeight,rOrigHeight,tol) and rHeight or rOrigHeight]='origHeight', -- rOrigHeight will exist only if it differ from height by at least 7 (tol) elmos
		[rHeight]='height', 
		[water]='water',
		[rTarget]='target'
	}
	if specialAboveWaterDefID[p.PID] then
		uniqueVals[4] = 'specAboveWater'
	end

	-- if true then
	--     uniqueVals[5] = 'arbitrary'
	-- end
	local heights={}
	for k,v in pairs(uniqueVals) do table.insert(heights,k) end
	table.sort(heights,self.sortFunc)

	local current=1

	-- NOTE: make sure to have rTarget as key to avoid endless loop
	while heights[current] ~= rTarget do
		current = current+1
	end
	local closest
	local neigh1, neigh2 = heights[current-1], heights[current+1] 
	if neigh1 and neigh2 then
		closest = neigh2 - rTarget < rTarget - neigh1 and neigh2 or neigh1
	else
		closest = neigh1 or neigh2
	end

	if debug then
		local str = ''
		for i,h in ipairs(heights) do
			str = str..', #'..i..': '..uniqueVals[h]..' = '..h
		end
		str = str:sub(2,str:len())
		Echo('all values => '..str)
		Echo("current is #", current..': '..uniqueVals[ heights[current] ]..' = '..heights[current])
		Echo(closest and ('closest is ' .. uniqueVals[closest] .. ': ' .. closest) or 'there is no other height to snap to' )
	end
	self.snap = false
	return heights, current, uniqueVals, closest
end
function groundModule:UpdateSnap(level, apply, change, _p) -- used to update the snap when moving cursor around or to apply a change when user want to modify height
	Debug.elevChange('update snap ', apply and 'apply' or 'not apply', change and 'change' or 'not change')
	local p = _p or p
	-- if round(level) < 0 and (not p.underSea) then
	--     Debug.elevChange("level is below water, for this floating build, returning min'ed height mod from water level", OFF_WATER + math.max(placementHeight, 0))
	--     -- return OFF_WATER + math.max(placementHeight, 0)
	--     Echo("placementHeight is ", placementHeight)
	--     return OFF_WATER + placementHeight
	--     -- Debug.elevChange('level is below water, for this floating build, returning water level')
	--     -- return OFF_WATER
	-- end
	-- if level < OFF_WATER and (not p.underSea) then
	--     level = OFF_WATER
	-- end
	-- if self.height < 0 and level < 0 and (not p.underSea) then
	--     level = - self.height + OFF_WATER
	-- end

	-- if level < 0 and (not p.underSea) then
	--     Debug.elevChange("level is below water, for this floating build, returning water level")
	--     placementHeight = - self.height
	--     return 0
	-- end
	local minAtWater = p.floater
	if not change then
		local ret
		if specialAboveWaterDefID[p.PID] and level > 0 and level < 7 then
			ret = level
		elseif minAtWater and mol(level, 0, 7) then
			ret = mol(level, self.height, 7) and max(OFF_WATER, self.height) or OFF_WATER
		elseif mol(level, self.height, 7) then
			ret = self.height
		end
		if ret then
			Debug.elevChange('no change, returning ' .. ret)
			self.snap = ret
			return self.snap
		end
	end

	local heights, current, uniqueVals, closest = self:GetSnapOrder(level)
	local snap
	if closest then
		if abs(closest-level) <= self.snapTolerance 
			or level<0 and round(closest) == 0 and minAtWater
			-- or closest == 4 and level <= INCREMENT_SIZE and specialAboveWaterDefID[p.PID] 
		then
			if apply then
				snapTime=spGetTimer()
			end
			-- Echo("closest,level is ", closest,level)
			if round(closest)==round(level) then
				Debug.elevChange('level '.. round(level) .. ' is same as the snap: '.. uniqueVals[closest])
			else
				Debug.elevChange('closest snap from ' .. round(level) .. ' is ' .. uniqueVals[closest] .. ': ' .. closest)
			end
			snap = closest
		else
			Debug.elevChange('closest snap ' .. uniqueVals[closest] .. ', ' .. closest .. ' is too far from level ' .. round(level))
		end
	else
		-- happens when level is at ~=0, highest ground is water and the build cannot sub
		Debug.elevChange('there is no other values than the level ' .. level )
	end
	self.snap = snap and uniqueVals[closest]

	return snap or level
end

function groundModule:DefineMaxOffset(up, value) -- Define if it should lock the elevation for a few time and return the corrected offset that will modify placementHeight
	local debug = Debug.elevChange()
	if debug then
		Echo('----- Define Offset -----', up, value)
	end

	local minAtWater = p.floater
	local placementHeight, pointY = placementHeight, pointY
	local offset = (INCREMENT_SIZE)*value 
	if self.offsetPH then
		placementHeight = placementHeight + self.offsetPH
		self.offsetPH = false
	end
	local placementHeightOffset --= offset
	-- Echo('offset should be ',(INCREMENT_SIZE)*value + pointY-(placementHeight+height),'but it is ',offset)
	local heights,current, uniqueVals, closest = groundModule:GetSnapOrder(pointY,false,true)


	-- correct the placementHeight, if the placementHeight+height doesnt correspond to the capped pointY, when pointY has been capped to not go under water with build that cannot
	-- this is normal behaviour when user set a negative placement height to build structure underneath higher terrain, and we keep it until 
	-- user want to change height placement on lower terrain

	-- local refHeight = min(self.height,self.origHeight)
	local refHeight = self.height

	-- Echo("height,origHeight is ", height,origHeight)

	-- if 
	-- if specialAboveWaterDefID[p.PID] then
	--     if placementHeight == 0 and up then

	if minAtWater then
		-- if specialAboveWaterDefID[p.PID]
		if (placementHeight+self.minGround)<0 and refHeight>10 and mol(round(pointY),0,7) then
			local oldPH = placementHeight
			placementHeight = -abs(math.max(refHeight,0))
			-- Echo('correcting placement height '..placementHeight..' to '..-abs(math.max(refHeight,0)))
			placementHeight = round(placementHeight/INCREMENT_SIZE) * INCREMENT_SIZE
			if debug then
				-- Echo('correcting placement height '..placementHeight..' to '.. round(refHeight/INCREMENT_SIZE) * INCREMENT_SIZE)
				Echo('correcting placement height '.. oldPH ..' to '.. placementHeight, 'refHeight : ' .. refHeight)
			end
			-- placementHeight = -abs(math.max(refHeight,0))
			-- placementHeight = floor(min(height,origHeight)/INCREMENT_SIZE) * INCREMENT_SIZE
		end
	end
	--





	local sign = up and 1 or -1
	local nextValue = heights[current+sign]
	if debug then
		Echo("current is", heights[current], "nextValue is ", nextValue, 'closest', closest, 'pointY', pointY, 'goalOffset', nextValue and nextValue-pointY or 'none')
	end

	if nextValue then
		local goalOffset = round(nextValue-pointY)
		-- Echo('nextStop is:',uniqueVals[ nextValue ]..':'..nextValue,'pointY is '..pointY,'offset:'..(offset)..' vs '..'max:'..goalOffset--[[..' ('..(cnt or 'no count')..')'--]],'ph:'..placementHeight)
		-- if the normal offset is beyond the next snap level, snap is active and we reduce the offset
		if abs(goalOffset) <= abs(offset) + self.snapTolerance then -- abs offset vs abs goalOffset
			snapTime = spGetTimer()
			self.snap = nextValue
			local _offset = offset
			offset = goalOffset 
			-- if abs(goalOffset) < self.snapTolerance then
			--     placementHeightOffset = 0
			-- else
				-- placementHeightOffset = round(goalOffset/INCREMENT_SIZE) * INCREMENT_SIZE
			-- end

			-- placementHeightOffset = math.max(abs(round(goalOffset/INCREMENT_SIZE)),1) * INCREMENT_SIZE * sign
			placementHeightOffset = goalOffset
			-- Echo('snap', 'offset is ', goalOffset, 'placementHeight Offset => ', placementHeightOffset)
			if debug then
				Echo('snapping to '.. heights[current+sign], 'pointY is ',pointY, 'because abs goalOffset: '.. abs(goalOffset) .. ' <= '.. ' abs (offset: ' .. abs(_offset) .. ') + self.snapTolerance ' .. self.snapTolerance
				..', placementHeightOffset is '..placementHeightOffset )
			end
		else
			-- Echo('not snapping')
		end
	end
	if placementHeightOffset then
		if debug then
			Echo('PLACEMENT HEIGHT =>', placementHeight .. ' + ' .. placementHeightOffset .. ' = ' .. (placementHeight + placementHeightOffset) )
		end
		placementHeight = placementHeight + placementHeightOffset
	else
		local oldPH, oldOffset = placementHeight, offset
		placementHeight = (round(placementHeight/INCREMENT_SIZE) * INCREMENT_SIZE) + offset
		offset = placementHeight - oldPH
		if debug then
			Echo('PLACEMENT HEIGHT ROUNDED: '.. oldPH ..' => '..(round(oldPH/INCREMENT_SIZE) * INCREMENT_SIZE), 'OFFSET: '.. oldOffset..' => '..offset..', NEW PH: '..placementHeight )
		end
	end

	self.lastOffset = placementHeightOffset or offset
	-- resetting mode of placementHeight Adjuster, now keep the current placementHeight definitively
	local wasAltDig = self.altDig~=nil
	local wasAltElev = self.altElev~=nil
	if wasAltDig or wasAltElev then
		Debug.modPH('reset'.. (wasAltDig and ' altDig, ' or '') .. (wasAltElev and ' altElev, ' or '') .. ' user changed the PH')
	end
	self.altDig = nil
	self.altElev = nil
	self.altPH = nil
	--
	pointY = pointY+offset
	if debug then
		Echo('PH => ' .. placementHeight,'pointY ==> '..pointY)
	end

	return placementHeight, pointY
end

function groundModule:AdjustPH(X,Z,p)
	local debug = Debug.modPH


	-- Adjust the placemenHeight for transitionning between normal ground to elevated/subelevated ground and vice versa
	local PH = placementHeight
	if round(PH) == 0 and not self.altPH then
		-- nothing to do
		return
	end
	groundModule:Update(X,Z,p)
	local height = self.height
	local origHeight = self.origHeight


	---- set the pointY

	-- local waterline = p.floatOnWater and 0 or OFF_WATER
	-- local snap          = min(abs(height),INCREMENT_SIZE*0.5)
	local snap          = INCREMENT_SIZE*0.5
	--if abs(origHeight-height)<snap then Echo('==') origHeight=height  else Echo('~=',abs(origHeight-height)) end

	-- water               = round(height)<=0
	local modHeight     = origHeight~=height and height-origHeight -- diff more or less by 10 which is the max before having to terraform
	local elevated      = modHeight and height>origHeight
	local subelevated   = modHeight and height<origHeight
	floater             = p.floater
	canSub              = p.canSub


	local newPH
	if not self.altPH then -- we're not in mode
		if PH>0 then
			self.altDig = nil
			debug("the mode altDig is reset ")
			if self.altElev == nil then
				if elevated then
					self.altElev = false -- we don't allow altElev if we're starting already on elevated ground
					debug('the mode altElev is disabled')
				else
					self.altElev = true
					debug('the mode altElev is ready')
				end
			elseif self.altElev and elevated then
				self.altPH = PH
				newPH = math.max(PH - modHeight, 0)
				debug('enter '.. (PH == 0 and 'elevShallow' or 'limitElev'), 'PH '..PH..' => '..newPH,'modHeight',modHeight)
			end

		elseif PH<0 then
			self.altElev = nil
			debug('the mode altElev is reset')

			if self.altDig == nil then -- initialize mode altDig
				if subelevated then
					debug('the mode altDig is disabled') -- we don't allow altDig if we're starting already on subelevated ground
					self.altDig = false
				else-- the user wanna dig on unmodified/elevated ground, mode is ready to trigger
					self.altDig = true
					debug('the mode altDig is ready')
				end
			elseif self.altDig and subelevated then
				-- we enter the mode
				self.altPH = PH
				newPH = math.min(PH - modHeight, 0)
				debug('enter '.. (PH == 0 and 'digShallow' or 'limitDig'), 'PH '..PH..' => '..newPH,'modHeight',modHeight)
			end
		-- elseif PH == 0 and myPlatforms.x and self.height < 0 and (p.floater) then
		--     Echo('OK')
		end
	elseif self.altDig then
		local digOnDug = subelevated and self.altPH<0
		if not digOnDug then
			newPH = self.altPH
			newPH = round(newPH/INCREMENT_SIZE) * INCREMENT_SIZE
			self.altPH = false
			debug('leaving altDig and transfering the backup PH ' .. newPH)
		else
			newPH = math.min(self.altPH - modHeight, 0)
			debug('..in altDig, updating PH => '.. newPH,'altPH',self.altPH,'modHeight',modHeight)
		end
	elseif self.altElev then
		local elevOnElevated = elevated and self.altPH>0
		if not elevOnElevated then

			newPH = self.altPH
			newPH = round(newPH/INCREMENT_SIZE) * INCREMENT_SIZE
			self.altPH = false
			debug('leaving altElev and transfering the backup PH ' .. newPH)
		else
			newPH = math.max(self.altPH - modHeight, 0)
			debug('..in altElev, updating PH => '.. newPH,'altPH',self.altPH,'modHeight',modHeight)
		end

	end
	if newPH then
		placementHeight = newPH
		WG.placementHeight = placementHeight
		-- placementHeight = round(placementHeight/INCREMENT_SIZE) * INCREMENT_SIZE
		-- debug('... PH => '..placementHeight,'altPH',self.altPH,'modHeight',modHeight)
	end

end

------- running test for wind income
	-- local test = {
	--     windInc = 0,
	--     count = 0,
	--     avg = 0,
	--     UpdateWind = function(self,f)
	--         local winc = self.GetTeamRulesParam(myTeamID,'WindIncome')
	--         self.windInc = self.windInc + winc
	--         self.count = self.count + 1
	--         self.avg =  self.windInc / self.count
	--         if f%6000==0 then
	--             Echo('wind income: ' .. tostring(winc),'avg: ' .. self.avg)
	--         end
	--     end,
	--     GetTeamRulesParam = Spring.GetTeamRulesParam,
	-- }

	-- function widget:GameFrame(f)
	--     if f%200 and test[1]==false then
	--         test[1]=nil
	--     end


	--     if f%10 == 0 then
	--         if test[1]==nil then
	--             local units = Spring.GetTeamUnitsByDefs(myTeamID,{windDefID})
	--             if units[1] then
	--                 test[1] = units[1]
	--                 Echo('wind found')
	--             else
	--                 test[1] = false
	--             end
	--         end
	--         if test[1] then
	--             test:UpdateWind(f)
	--         end
	--     end

	-- end
-------------------
function groundModule:SetTerraforming(units, team, x,height,z,terraSizeX, terraSizeZ)

	local commandTag = WG.Terraform_GetNextTag()
	local ulen = #units

	local params = {}
	params[1]  = 1            -- terraform type = level
	params[2]  = team
	params[3]  = x
	params[4]  = z
	params[5]  = commandTag
	params[6]  = 1            -- Loop parameter
	params[7]  = height       -- Height parameter of terraform
	params[8]  = 5            -- Five points in the terraform 
	params[9]  = ulen         -- Number of cons with the command
	params[10] = 0            -- Ordinary volume selection
	-- Rectangle of terraform
	-- top right
	params[11] = x + terraSizeX
	params[12] = z + terraSizeZ
	-- bottom right
	params[13] = x + terraSizeX
	params[14] = z - terraSizeZ
	-- bottom left
	params[15] = x - terraSizeX
	params[16] = z - terraSizeZ
	-- top left
	params[17] = x - terraSizeX
	params[18] = z + terraSizeZ
	-- top right
	params[19] = params[11]
	params[20] = params[12]
	-- Set cons

	local i = 21
	for j = 1, ulen do
		params[i] = units[j]
		i = i + 1
	end
	spGiveOrderToUnit(units[1], CMD_TERRAFORM_INTERNAL, params, 0)
	return commandTag
end


-- tool to store/verify and get platform of elevated building created by user
function myPlatforms:Process(px, pz)
	-- Echo('plat',self.x, math.round(os.clock()))
	local out =  not self.x
	local platX, platZ
	if --[[ round(placementHeight)~=0 and--]] not surround --[[and PID~=mexDefID--]] then
		-- local camHeight = GetCameraHeight(spGetCameraState())
		local radius = round(Cam.relDist/1000) * 3
		platX, platZ = myPlatforms:LookFor(p.sizeX, px, pz, (radius * 8)^2)
	end
	-- Echo("out, self.x is ", out, self.x)
	if out and self.x then
		self.oriPH = placementHeight
		groundModule:Update(self.x, self.z)
		-- placementHeight = round((groundModule.height - groundModule.minGround) /INCREMENT_SIZE) * INCREMENT_SIZE
		placementHeight = 0
	elseif not self.x and self.oriPH then
		placementHeight = self.oriPH
		WG.placementHeight = placementHeight
		self.oriPH = false
	elseif self.x then
		platX, platZ = self.x, self.z
	end
	return platX, platZ
end
function myPlatforms:New(sx, x, z, defID)
	if not self[sx] then
		self[sx] = {}
	end
	if not self[sx][x] then
		self[sx][x] = {}
	end
	self[sx][x][z] = {defID = defID, time = os.clock()}
	Debug.platform('new platform of ' .. defID .. ' x' .. sx .. ' created !','['..x..']['..z..']')
end
function myPlatforms:Remove(sx, x, z)
	self[sx][x][z] = nil
	if not next(self[sx][x]) then
		self[sx][x] = nil
	end
	if not next(self[sx]) then
		self[sx] = nil
	end
	self.x, self.z = nil, nil
	Debug.platform('platform ', sx, x, z,'successfully removed')
end
function myPlatforms:Verify(X, Z, sx, sz, acceptance)
	-- first step : register the modded height points on foot print
	-- 
	Debug.platform('Verifying platform', X, Z, sx)

	local thre = 7 -- threshold
	local debugOwnPlat = Debug.platform()
	local bad = 0
	local heights = {}
	local n_points = (( sx/4 + 1 )*( sz/4 + 1 ))
	local n_goal = round(n_points * acceptance)
	for x = X - sx, X + sx, 8 do
		for z = Z - sz, Z + sz, 8 do
			local ht = spGetGroundHeight(x, z)
			local oht = (origHeightMap and origHeightMap[x][z] or spGetGroundOrigHeight(x,z))
			-- Echo("origHeight",origHeight,"placementHeight",placementHeight,"height ", height)
			if oht and not mol(ht,oht,thre) then -- might be out off map so we check if oht exist
				-- setting or upping a score to that height rounded by thre
				local rh = nround(ht, thre)
				local ref = heights[rh - thre] and rh - thre
					or heights[rh] and rh
					or heights[rh + thre] and rh + thre
				if not ref then
					ref = rh
					heights[ref] = 0
				end
				heights[ref] = heights[ref] + 1
			else
				-- Points[#Points+1]={x,ht,z,txt=ref}
				bad = bad + 1
				if bad > (n_points - n_goal) then
					-- majority of points have same height than original, we don't look further
					if debugOwnPlat then
						Echo('but too many points have same height than original: ' .. bad .. '/' .. n_points )
					end
					return false
				end
			end
		end
	end
	-- we check the highest score
	local platH, platScore = next(heights)
	local n_heights=0
	for h,score in pairs(heights,platH) do
		if score > platScore then
			platH, platScore = h, score
		end
	end
	if debugOwnPlat then
		Echo('modded height  '.. platH .. ' has the highest score: ' .. platScore )
	end

	if platScore < n_goal then
		if debugOwnPlat then
			Echo("No platform detected.")
		end
		return false
	end
	-- case: majority of ground point at blueprint has same height
	-- we're on a complete (or almost) platform, we look around if the platform extends
	if debugOwnPlat then
		Echo("the build is on a platform, checking now if it's our own")
	end
	-- if the terrain has been elevated we guess if it has been elevated for multiple structure by checking around, in this case we reconsider the mod height
	local good=0
	local startingLayer = sx/8 + 1 -- TODO:I didnt make a spiral rectangle function yet
	local layers=sx~=sz and 4 or 3
	local n_around = ( (sx)/4 + 1 + layers*2 )^2 - n_points
	local found 
	local function check(layer,offx,offz)
		local ht = spGetGroundHeight(X + offx, Z + offz)
		-- Points[#Points+1]={X+offx,ht, Z+offz}

		if not mol(ht, platH, thre) then
			good = good + 1
			if good >= round(n_around * 0.85) then 
				return true
			end
		end
	end
	local found = SpiralSquare(layers + startingLayer, 8, check, startingLayer)

	if debugOwnPlat then
		if found then
			Echo("the platform doesn't extend much outside of the build, at least " ..good .. '+/' .. n_around .. 'have different heights, this platform is our own')
		else
			Echo("the platform extend outside by at least " .. (n_around-good) .. ' squars, this platform is NOT our own')
		end
	end

	return found
end
function myPlatforms:LookFor(sx, cx, cz, distance, sz, pid)
-- Echo("table.size(self) is ", table.size(self))
	local bestDist = math.huge
	local foundX, foundY, foundZ
	pid = pid or PID
	if self[sx] then
		local time = os.clock()
		for x, tx in pairs(self[sx]) do
			local dx = abs(x-cx)
			if dx <= distance then
				for z, t in pairs(tx) do
					if pid and t.defID == pid then
						local dz = abs(z - cz)
						if dz <= distance then

							local dist = (dx^2 + dz^2)--^0.5
							-- Echo("dist, distance is ", dist, distance)
							if dist < distance and dist < bestDist then
								if self:Verify(x, z, sx, sz or sx, 0.6) then
									bestDist = dist
									foundX,foundZ = x, z
								elseif time - t.time > 30 then
									self:Remove(sx, x, z)
								end
							end
						end
					end
				end
			end
		end
	end
	-- experimental part -- not good, we need to check around manually for it to be useful
	-- if not foundX then
	--     -- local X, Z = FindPlacementAround(cx,cz,placed,false,false,true, true)

	--     local foundX, foundY,  foundZ = spClosestBuildPos(0,PID, cx, 0, cz, distance ,0 ,p.facing)
	--     if foundX and foundX > -1 and (foundY > 0 or not p.floatOnWater or p.underSea)
	--     and abs(foundY -  (origHeightMap and origHeightMap[foundX][foundZ] or spGetGroundOrigHeight(foundX,foundZ))) > 7
	--     then
	--         myPlatforms:New(p.sizeX, foundX, foundZ, PID)
	--         Echo("found unregistered plat ", foundX, foundY, foundZ)
	--     else
	--         foundX, foundZ = nil, nil
	--     end
	-- end
	--
	self.x, self.z = foundX, foundZ
	return foundX,foundZ
end






--
--Echo("----------------------------------------------------------------")
--------------------------------------------------------------------------------
-- Height Handling
--------------------------------------------------------------------------------
--include("Map/MapInfo")
--VFS.Include("Map/MapInfo.h")
do
	local GetPos = Spring.GetUnitPosition
	local struct = {defID = 0, 0, 0, 0}
	local SpiralSquare= f.SpiralSquare
	local nround = f.nround
	local shipFactoryDefID = UnitDefNames.factoryship.id

	WG.CheckTerra = function(X,Z,pid,placed,_p,customElev)-- fixed canFloat and sub placement, also adding some comfort and readiness
		--pointX = floor((pointX + 8 - oddX)/16)*16 + oddX
		--pointZ = floor((pointZ + 8 - oddZ)/16)*16 + oddZ
		-- local debugOwnPlat = Debug.platform()

		local PH = placementHeight
		local customPid = pid
		if customPid then
			PH = customElev or 0
		end
		pid = pid or PID
		if X then
			if type(X) == 'table' then
				X,Z = X[1],X[2]
			end
		else 
			X,Z = pointX,pointZ
		end

		local p = _p or customPid and IdentifyPlacement(pid) or p
		groundModule:Update(X, Z, p)
		local height = groundModule.height
		local origHeight = groundModule.origHeight


		---- set the pointY

		-- local waterline = p.floatOnWater and not g.lava and 0 or OFF_WATER
		-- local snap          = min(abs(height),INCREMENT_SIZE*0.5)
		local snap          = INCREMENT_SIZE * 0.5
		--if abs(origHeight-height)<snap then Echo('==') origHeight=height  else Echo('~=',abs(origHeight-height)) end

		water               = round(height) <= 0
		-- local modHeight     = groundModule.modHeight --origHeight and height-origHeight -- diff more or less by 10 which is the max before having to terraform
		-- local elevated      = groundModule.elevated -- modHeight and height>origHeight
		-- local subelevated   = groundModule.subelevated -- modHeight and height<origHeight
		floater             = p.floater
		canSub              = p.canSub


		-- snap system for helping the user adjusting elevation to different level
		-- dismiss the PH modification in some case, apply it compared to originalHeight in other cases
		-- level               = PH +
		--                         (
		--                             water and (p.underSea and height or PH<OFF_WATER and -PH or OFF_WATER )
		--                          -- onOwnPlatform is if the PH correspond to the origHeight + terraformed height, meaning we already built a platform there at the same height
		--                          -- or onOwnPlatform and origHeight
		--                          or height<=OFF_WATER and not p.underSea and OFF_WATER
		--                          -- if elevated ground PH will apply to origHeight, on dug ground it will apply to origHeight if the PH is roughly equal
		--                          -- or (elevated or modHeight and mol(modHeight,PH,5)) and origHeight
		--                          or min(height,origHeight or height)
		--                         )
		-- local refHeight = groundModule.minGround
		-- local offsetPH = groundModule.offsetPH

		
	   -- if offsetPH then
		--     PH = PH + offsetPH
		-- end
		-- Echo("offsetPH is ", offsetPH, 'PH',PH,'digShallow',digShallow)
		-- level = --[[round(PH) == 0 and groundModule.maxGround or--]]  PH + (modHeight and groundModule.minGround or height)
		-- level = --[[round(PH) == 0 and groundModule.maxGround or--]]  PH + (elevated and height or origHeight)
		level = PH + height
		if (p.floater) and height < 0 then
			level = level - height
		end
		-- level = PH + (p.floatOnWater and not p.underSea and 0 or height)
		-- level = --[[round(PH) == 0 and groundModule.maxGround or--]]  PH + groundModule.minGround
		-- level = --[[round(PH) == 0 and groundModule.maxGround or--]]  PH + refHeight
		-- if elevated then
		--     level = height + PH
		-- elseif subelevated then
		--     Echo('modHeight',modHeight,'PH',PH)
		--     if modHeight < PH and PH<0 then

		--         level = origHeight + PH
		--     end
		-- end
		-- if level < OFF_WATER and (not p.underSea) then
		--     level = OFF_WATER
		-- end
		local oldlvl = level
		level = groundModule:UpdateSnap(level,false,false,p)

		if level == 0 then
			level = OFF_WATER
		end
		if Debug.elevChange() then
			Echo("PH, height is ", PH, height, spGetGroundHeight(X, Z), '=>', PH + height)
		end
		-- Echo("level is ", level)
		--Echo("modHeight,PH is ", modHeight,PH)
		local snapGround    = level < height + snap + OFF_WATER and level > height - snap + OFF_WATER

		groundModule.snapFloat           = not snapGround 
											and (level ~= 4 or not specialAboveWaterDefID[p.PID] )
											and (level < snap + OFF_WATER and level > -snap + OFF_WATER or not p.underSea and level <= OFF_WATER)


		-- local digToWater    = not water and (snapFloat or level<0 and height>1)

		-- local snapSub       = p.underSea and level+10>origHeight and level-10<origHeight

		-- local snapOriGround = not snapFloat and (not modHeight and snapGround or elevated and level<origHeight+snap+OFF_WATER and level>origHeight-snap+OFF_WATER)
		-- local snapOriGround = not snapFloat and (not modHeight and snapGround or --[[elevated and--]] level<origHeight+snap+OFF_WATER and level>origHeight-snap+OFF_WATER)

		-- pointY = groundModule.snap
		--          or   ( (not p.underSea and level<=OFF_WATER) or snapFloat )
		--                 and    OFF_WATER 
		--          or snapGround
		--                 and height
		--          or (snapSub or snapOriGround) 
		--                 and origHeight
		--          or level

		-- Echo("modHeight is ", modHeight,'placementHeight',placementHeight)
		pointY = level
		
		-- Echo("PH,pointY is ",PH, pointY,snapOriGround)
		if g.lava then
			if pointY < OFF_WATER and PID ~= shipFactoryDefID then
				pointY = OFF_WATER
			end
		else
			if pid == winDefID and pointY == 0.1 then
				pointY = 0
			end
		end

		-----
		if Debug.elevChange() then
			Echo(
				'pointY updated: ' .. pointY,'level ' .. level,'PH' .. PH,
				groundModule.snap and 'snap module:'.. groundModule.snap
				or
				'('..PH
				 .. ' + '
				 ..  (
						groundModule.snap
						or water and (p.underSea and height or PH<OFF_WATER and -PH or OFF_WATER )
						or height <= OFF_WATER and not p.underSea and OFF_WATER
						or min(height, origHeight)
					  )
				 ..')'
			)
		end
		groundModule.snap = false
		drawWater = --[[(pointY == OFF_WATER) or--]] (level < 80)

		---- Find out if the build pass

		-- local onOwnPlatform = height~=origHeight and mol(height,PH+origHeight,10)
		-- spPos2BuildPos is giving same y as the engine grid (~= than origHeight)
		--_,origHeight = spPos2BuildPos(pid,pointX,height,pointZ,p.facing)  


		-- Echo("Spring.TestBuildOrder(p.pid, px, 0, pz, p.facing) is ", Spring.TestBuildOrder(p.pid, X, 0, Z, p.facing))
		-- this next line tells us if the ground is blocked for a normal placement
		local _, offset
		local cantPlace, onPlaced
		local offset = 0
		local finalElev = abs(pointY - height)
		------ EXPERIMENTAL:  augment the footprint by the difference between wanted elevation and current ground height, this is not ideal, it's only useful if the terrain is same height as the footprint
		------ offset the build automatically when zoomed out, if needed due to other builds in vicinity (this doesnt check for ground height and assume neighbour build are on flat surface, TODO: might be hard and costly but maybe implement the height ground checking for neighbours)
		if (Cam.relDist - finalElev) > 2000 then
			local extra = pointY < height and 28 or 0 -- when digging the space taken is a bit wider
			offset = math.floor((finalElev + extra)/28) * 8-- for 28 height diff the pyramid half size enlarge by 8 on a flat surface, we follow this and assume the terrain would be flat
			-- Echo('elev',finalElev,math.floor(finalElev/28),'offset',offset)
			offset = math.max(offset,0)
		end
		------
		cantPlace, _, blockingStruct, _, onPlaced = TestBuild(X, Z, p, true, placed, nil, nil, nil, nil, offset)

		-- end
		-- Echo("X,Z,pid,placed and #placed,blockingStruct is ", X,Z,pid,placed and #placed,blockingStruct)
		-- Echo("PH,height,origHeight is ",PH, height,origHeight)
		-- Points={}
		-- Echo("solarDefID is ", UnitDefNames['energysolar'].id, pid)
		sloppedTerrain = cantPlace and not blockingStruct --and not onPlaced --?? need to organize better the parameters in the whole process, add the placed in the regular check, not only on the click ?
		mustTerraform = sloppedTerrain


		if not mustTerraform and not blockingStruct then 
			-- mustTerraform = not mol(pointY,groundModule.maxGround,7)
			mustTerraform = specialAboveWaterDefID[p.PID] and level == 4 or g.lava and pointY == OFF_WATER or not mol(pointY, (p.floater) and max(height,0) or height, 7)
			-- if round(PH)~=0 then
			--     mustTerraform = p.underSea and pointY>origHeight or digToWater or snapOriGround and not snapGround or not (snapSub or snapFloat or PH==0 or PH==OFF_WATER or snapGround or snapOriGround)
			-- end
			-- if mustTerraform and PH<0 and water and p.floatOnWater and not digForWater then mustTerraform = false end
		end
		if mustTerraform and PID == shipFactoryDefID and pointY == OFF_WATER and not g.lava then
			pointY = -20
		end

		--if snapOriGround  and (isMex or not mustTerraform) or pointY==OFF_WATER and not digToWater and floater or (snapSub and not mustTerraform) then -- fixed water canFloat and digging
	-- fixed water canFloat and 
		if pid == geoDefID then
			local gx,gy,spot = CheckGeos(X,Z)
			if not spot then 
				sloppedTerrain, mustTerraform = false, false
			end
		end
		-- Echo("pointY is ", pointY)
		return not g.noterra and mustTerraform, pointY, blockingStruct, sloppedTerrain
	end
	CheckTerra = WG.CheckTerra
end

local function CheckEnabled()
	-- if options.enterSetHeightWithB.value then
	--     return g.toggleEnabled
	-- end
	return true
end

local function reset(shift,keepAcom,force)
		pointX = false
		--cons = {}
		mexes = {}
		if not keepAcom then
			groundModule.altPH = nil
			groundModule.altDig = nil
			groundModule.altElev = nil
		end
		-- WG.commandLot={}
		if widgets.command_insert and widgets.command_insert._CommandNotify then
			widgets.command_insert.CommandNotify = widgets.command_insert._CommandNotify
			widgets.command_insert._CommandNotify = nil
		end
		ignoreFirst=false
		-- if not (shift or meta) then
		if --[[force or--]] not (shift --[[or meta--]]) then
			if (
				force and (not WG.drawingPlacement)
				or not keepAcom and not widgets.drawing_placement
			) and (select(2,spGetActiveCommand()) or 0)<0 then
				spSetActiveCommand(0)
			end
			PID = false
			myPlatforms.x = false
			myPlatforms.oriPH = false
			-- if CI_Disabled then
			--     local widgets.command_insert = widgetHandler:FindWidget('CommandInsert')
			--     if widgets.command_insert then
			--         widgetHandler:UpdateWidgetCallIn("CommandNotify", widgets.command_insert)
			--     end
			--     CI_Disabled = false
			--     -- Echo('widgets.command_insert reenabled')
			-- end
			ordered = false
		end
		if force and not shift then
			forceResetAcom = false
		end
		movedPlacement[1] = -1
		update=true
		g.timeOutNoTerra = 0
		if WG.DrawTerra then WG.DrawTerra.finish=true end
end
-- testing speed
--local T ={ln=0}
	--[[for i=1,1000000 do
		T.ln=T.ln+1 T[T.ln]=true
	end--]]
	--setmetatable(T,{__index=function(t,k)return 3 end})
	--T[1000000]=true
	--T[1]=true
	--for i=1,999999 do T[i]=nil end
	--for i=1,1000000 do T[i]=true end
	--T[555555]=nil
	--for i=1,10 do T[i]=true end

	--local T2 = pack2(a,1,b,2,c,3,d,4)
	--Echo('-2')
	--for k,v in pairs(T2) do Echo(k,v) end

	--local T2 = f.pack('a',1,'b',2)
	--for k,v in pairs(T2) do Echo(k,v) end

local clock = os.clock

function widget:KeyRelease(key,mods)
	-- Echo("ordered, meta, shift, mods.shift is ", ordered, meta, shift, mods.shift)

	local newalt,newctrl,newmeta,newshift = mods.alt,mods.ctrl,mods.meta,mods.shift
	if  shift and not newshift and PID then
		if toForgetOnShiftRelease then
			buildHeight[toForgetOnShiftRelease] = 0
			toForgetOnShiftRelease = false
		end

		if ordered then
			if PID and (not widgets.drawing_placement or forceResetAcom) and select(2,spSetActiveCommand()) == -PID then
				spSetActiveCommand(-1)
			end
			for k in pairs(WG.commandLot) do
				WG.commandLot[k] = nil
			end
			reset(false)
		elseif not widgets.drawing_placement and PID and not select(2, spGetActiveCommand()) then -- if DrawPlacement has cancelled/don't have PID
			reset(false)
		end
	end
	alt, ctrl, meta, shift = newalt, newctrl, newmeta, newshift
	if not ordered then
		return
	end
	-- if ordered and meta and not shift then
	-- -- if meta and not shift and not (mods.meta or mods.shift) then
	--     spSetActiveCommand(0)
	--     PID = false
	--     myPlatforms.oriPH = false
	--     ordered = false
	--     reset(false)
	--     -- Echo('reset in PBH')
	-- end

end
function widget:KeyPress(key, mods, isRepeat)
	-- if not DONE and key == 268 then
	--     opt.CreateWindowTableEditer(options.rmbHeightOverGame.value, 'TEST', options.rmbHeightOverGame.preTreatment, options.rmbHeightOverGame.postTreatment, options.rmbHeightOverGame.callback)
	--     DONE = true
	-- end
	if isRepeat then
		return
	end
	alt, ctrl, meta, shift = mods.alt, mods.ctrl, mods.meta, mods.shift
--Page(Spring,'map')
	-- Debug.CheckKeys(key,mods)
	-- if mods.ctrl and key==262 then -- Ctrl + KP6 to reload
	--     Spring.Echo('Reloading ' .. widget:GetInfo().name)
	--     Spring.SendCommands('luaui disablewidget ' .. widget:GetInfo().name)
	--     Spring.SendCommands('luaui enablewidget ' .. widget:GetInfo().name)
	-- end
	if not PID then return end
	if options.enterSetHeightWithB.value then
		if key == toggleHeight then
			g.toggleEnabled = not g.toggleEnabled
			return true
		end
	end
	if not g.toggleEnabled then return false end
	local value = key == heightIncrease and 1 or key == heightDecrease and -1
	if not value then 
		return
	end
	if groundModule.snapFloat and not p.underSea and value < 0 then
		return true
	end
	if g.noterra then
		g.timeOutNoTerra = os.clock() + 3
		return true
	end
	if g.NEW_PID then
		g.NEW_PID = false
		placementHeight = not g.noterra and buildHeight[PID] or 0
		if placementHeight ~= 0 then
			snapTime=spGetTimer()
			-- g.BRIEF_SNAP = true
			update = true
			groundModule:DefineMaxOffset(key == heightIncrease,value,true)
		end
		WG.placementHeight = placementHeight
		return true
	end
	if snapTime and spDiffTimers(spGetTimer(),snapTime) < 0.25 - (g.BRIEF_SNAP and 0.15 or 0) then
		return true
	else 
		snapTime=false
		g.BRIEF_SNAP = false
	end

	-- block height change for 0.25 second when reaching float point or zero ground point for the ease of the user wanting to get back quickly to zero elevation
	placementHeight, pointY = groundModule:DefineMaxOffset(key == heightIncrease,value,true)
	WG.placementHeight = placementHeight
	buildHeight[PID] = myPlatforms.oriPH or placementHeight
	-- pointY = pointY + offset
	update = true
	return true
end


function widget:MouseWheel(up, value)
	if not PID then return end
	if not alt then return end
	if not options.altMouseToSetHeight.value then return end
	if g.noterra then
		g.timeOutNoTerra = os.clock() + 3
		return true
	end
	if groundModule.snapFloat and p.floater and value < 0 then
		return true
	end
	if snapTime and spDiffTimers(spGetTimer(),snapTime) < 0.25 - (g.BRIEF_SNAP and 0.15 or 0) then
		return true
	else 
		snapTime=false
		g.BRIEF_SNAP = false
	end
-- block height change for 0.25 second when reaching float point or zero ground point for the ease of the user wanting to get back quickly to zero elevation
	if g.NEW_PID then
		g.NEW_PID = false
		placementHeight = not g.noterra and buildHeight[PID] or 0
		if placementHeight ~= 0 then
			snapTime = spGetTimer()
			-- g.BRIEF_SNAP = true
			update = true
			groundModule:DefineMaxOffset(up,0)
		end
		WG.placementHeight = placementHeight
		return true
	end
-- block height change for 0.25 second when reaching float point or zero ground point for the ease of the user wanting to get back quickly to zero elevation
	placementHeight, pointY = groundModule:DefineMaxOffset(up,value)

	-- Echo("now placementHeight,offset is ", placementHeight,offset)

	buildHeight[PID] = myPlatforms.oriPH or placementHeight
	WG.placementHeight = placementHeight
	-- pointY = pointY + offset
	update = true
	return true
end





local function ApplyHeight(lot,useBuildHeight, exceptPlatform) -- defining height and duplicating coords that will need terraformation
	local i,n=1,0
	local items = #lot
	while i<=items do
		local X,Z,facing = lot[i+n][1],lot[i+n][2],lot[i+n][4]
		if facing then -- in case of surrounding, we get the facing from CommandNotify then we have to reupdate for our own facing afterward
			if facing ~= p.facing then
				p = IdentifyPlacement(PID,facing)
			end
			update = true
		end
		--Echo("X,Z is ", X,Z)
		local isMex = lot[i+n].mex
		local pid = isMex and mexDefID or lot[i+n].pid
		local customElev
		local platX, platZ
		if exceptPlatform and not isMex then
			platX, platZ = myPlatforms:LookFor(p.sizeX, X, Z, p.radiusSq, nil, pid)
			if platX then
				X, Z = platX, platZ
				customElev = 0
			end
		end

		if not customElev then
			if isMex or g.noterra then
				customElev = 0
			elseif pid == PID then
				customElev = g.NEW_PID and 0 or placementHeight
			elseif useBuildHeight then
				customElev = g.NEW_PID and 0 or buildHeight[pid]
			end
		end
		local outMap =  X-p.sizeX < 0
			or X + p.sizeX > maxx
			or Z - p.sizeZ < 0
			or Z + p.sizeZ > maxz
		if outMap then 
			table.remove(lot,i + n)
			i = i - 1
			items = items - 1
		elseif CheckTerra(X, Z, pid, nil, nil, customElev) then
			-- replace the table with our y added
			local newEntry = {X, pointY, Z, facing, pid = pid, mex = isMex, terra=true}

			if not g.preGame then
				table.insert(lot,i + n, newEntry)
				n = n + 1
			end
			lot[i + n] = {X, pointY, Z, facing, pid = pid, mex = isMex}
			-- duplicate for sorting terra -- SHOULD JUST ADD .terra instead
			if ghosts then
				ghosts.ln = ghosts.ln + 1
				ghosts[ghosts.ln] = newEntry
				ghosts[X..pointY..Z] = ln
			end
		else
			--local height = spGetGroundHeight(X,Z)
			if pid ~= mexDefID and surround and (blockingStruct) then --remove the surrounding buildings made by ctrl+shift if they are stepping on existing buildings
				table.remove(lot, i+n)
				i = i - 1
				items = items - 1
			else
				lot[i + n]={X, pointY, Z, facing, mex = isMex, pid = pid}
			end
		end
		i = i + 1
	end
end
local function CreateTerra(cl, unitID)
	local p = p
	local pid
	if cl and cl.pid then
		pid = cl.pid
		p = IdentifyPlacement(pid, cl.facing)
	end
	if not pid then
		pid = PID
	end
	if pid == mexDefID and  spotsPos and WG.GetClosestMetalSpot then
		local pos = WG.GetClosestMetalSpot(pointX, pointZ)
		if pos then
			pointX, pointZ = pos.x, pos.z
		end
	end
	-- Setup parameters for terraform command

	-- local team = cons[1] and spGetUnitTeam(cons[1]) or spGetMyTeamID()
	local team = myTeamID

	-- addTerraUnit = true
	-- local terraSizeX,terraSizeZ=p.terraSizeX,p.terraSizeZ
	-- if cl and cl.facing and cl.facing~=p.facing and mod(p.facing,2)~=mod(cl.facing,2) then terraSizeX,terraSizeZ = p.terraSizeZ,p.terraSizeX end
	return groundModule:SetTerraforming(cons, myTeamID, pointX, pointY, pointZ, p.terraSizeX, p.terraSizeZ)

end
do
	local widgetNames = {
		['Draw Placement'] = 'drawing_placement',
		['Mex Placement Handler'] = 'mex_placement',
		['FixAutoGuard'] = 'fix_autoguard',
		['Building Starter'] = 'building_starter',
		['Guard Remove'] = 'guard_remove',
		['Hold Ctrl during placement to morph'] = 'ctrl_morph',
		['Factory Preorder'] = 'fac_preorder',
	}
	function WidgetInitNotify(w, name, preloading)
		local key = widgetNames[name]
		if key then
			widgets[key] = w
		end
	end
	function WidgetRemoveNotify(w, name, preloading)
		local key = widgetNames[name]
		if key then
			widgets[key] = nil
		end
	end
end

local function DistributeOrders(lot, PID, meta, shift)
	if not PID then
		return
	end
	shift = shift and not g.modArena
	-- conTable = getconTable()
	if not next(conTable.cons) then 
		return
	end
	local time = os.clock()
	local cheating = Spring.IsCheatingEnabled() -- in case the con is invisible
	for id,con in pairs(conTable.cons) do
		con.canBuild = cheating or spFindUnitCmdDesc(id,-PID)
	end

	local includeConPos = true
	if not (shift or meta) then
		conTable.inserted_time = false
		conTable.waitOrder = false
		for id,con in pairs(conTable.cons) do
			con.commands = {}
			con.queueSize = 0
		end
	elseif not conTable.inserted_time or time - conTable.inserted_time > SEND_DELAY then
		-- Echo(FormatTime(os.clock()))
		conTable.inserted_time = false
		conTable.waitOrder = false
		for id, con in pairs(conTable.cons) do
			local queue = spGetCommandQueue(id,-1) or EMPTY_TABLE
			local commands = {}
			local first = 1
			-- for i, order in ipairs(queue) do
			-- 	Echo('QUEUE: ' .. i, 'cmd ' .. order.id, 'p: ', unpack(order.params))
			-- end
			for i, order in ipairs(queue) do
				if i == 1 and order.id == 0 then -- 
					first = 2
				end
				-- if includeConPos == true and i == first then
					
				--     Echo(order.id,'unpack(order.params)', unpack(order.params))
				-- end
				-- if includeConPos == true and i == first and order.id == CMD_REPAIR and not order.params[5] then
				-- if includeConPos == true and i == first and order.id < 0 and not order.params[5] then -- TODO: UPDATE THIS WITH BUILD RADIUS CHECK
				-- 	-- Echo(('cancel includeCon params'):upper())
				-- 	-- (!this behaviour is outdated)
				-- 	-- the con is currently building, we don't include the con position in the insertion calculation, to avoid inserting before the current build
				-- 	-- it appears there are param 4 as PID in the command when the build is not yet started, params 5 is facing
				-- 	-- when the build has been started, the PID disappear and the facing remains so we can assume the build has started with 4 params
				-- 	includeConPos = false
				-- end
				local posx, _, posz = GetCommandPos(order)
				if i == first and includeConPos == true and  posx then
					local targetDefID
					if order.id == CMD_REPAIR then
						if not order.params[2] then
							targetDefID = spGetUnitDefID(order.params[1])
						end
					elseif order.id < 0 then
						targetDefID = -order.id
					end
					if targetDefID then
						local radius = WG.PlacementModule:Measure(targetDefID).radius
						local x, _, z = spGetUnitPosition(id)
						if math.diag(x - posx, z - posz) < (con.buildDistance + radius) then
							includeConPos = false
						end
					end
				end
				commands[i] = not posx and EMPTY_TABLE or {posx,posz, cmd = order.id, facing = order.id < 0 and order[4] or 0}
				-- Echo('add',i,posx,posz,  order.id, order.id<0 and order.params[4])
			end
			con.commands = commands
			con.queueSize = #queue
		end
	end

	conTable.multiInsert = false
	if shift and meta then 
		-- workaround to have a virtually updated command queue until it is actually updated
		local conRef
		-- has2ndOrder => don't insert before the first order if there is only one order to send (terraform included)
		-- hasSecondOrder = lot[2] and lot[2]~=lot[1] or lot[3] or false
		-- use cons[1] as reference for position for every cons
		conRef = cons[1]
		-- includeConPos = false
		MultiInsert(lot, conTable, true, includeConPos, conRef) 
	end
	-- Echo('RESULT')
	-- for id, con in pairs(conTable.cons) do
	-- 	for i, order in ipairs(con.commands) do
	-- 		local ins = con.insPoses[i]
	-- 		Echo(i,"insert at", ins, "p", order[1], order[2])
	-- 	end
	-- end
	local tryCI = shift and meta and (not cons[2] or Spring.GetConfigInt('tryCI') == 1) 
	-- Echo('tryCI', tryCI, Spring.GetConfigInt('tryCI'))

	local ownFacing = p.facing
	local before = meta and not shift
	local after = not meta and shift
	local direct = not meta and not shift
	local hasTerra
	local commandTag = false
	local nDelayed = #delayedOrders
	local batch
	local order_count=0
	local opts = f.MakeOptions()
	INSERT_TABLE[3] = opts.coded
	local GBC = WG.GlobalBuildCommand
	for i = 1, #lot do
		local elem = lot[i]
		local facing
		pointX, pointY, pointZ, facing = unpack(elem)
		facing = facing or ownFacing
		local cmdID
		XYZP_TABLE[1], XYZP_TABLE[2], XYZP_TABLE[3] = pointX, pointY, pointZ
		INSERT_TABLE[4], INSERT_TABLE[5], INSERT_TABLE[6] = pointX, pointY, pointZ
		-- INSERT_TABLE[3] = (shift and CMD_OPT_SHIFT or 0) + (alt and CMD_OPT_ALT or 0)
		-- case Level order
		if GBC and GBC.CommandNotifyRaiseAndBuild(cons, -PID, pointX, pointY, pointZ, facing, s) then
			--skip
		else
			if elem.terra then
				commandTag = CreateTerra(elem)
				hasTerra = false
				cmdID = CMD_LEVEL
				elem.commandTag = commandTag
				XYZP_TABLE[4] = commandTag
				
				INSERT_TABLE[2], INSERT_TABLE[7] = cmdID, commandTag
				
				--Echo("commandTag",commandTag)
				-- I never tested the global build command and never been implemented to my widget yet
			elseif commandTag then
				commandTag, hasTerra = false, true
			end
			if not commandTag then
				cmdID = elem.mex and -mexDefID or elem.pid and -elem.pid or -PID
				XYZP_TABLE[4] = facing
				INSERT_TABLE[2], INSERT_TABLE[7] = cmdID, facing
			end
			local firstcon = true
			local spGetUnitPosition = Spring.GetUnitPosition
			for id,con in pairs(conTable.cons) do
				if con.canBuild then
					local inreach = true or not con.isImmobile or g.modArena
					if not inreach then
						local cx, cy, cz = spGetUnitPosition(id)
						if cx then -- in case of cheat
							local dist = ((pointX - cx)^2 + (pointZ-cz)^2)^0.5
							if dist < con.buildDistance then -- TODO: need to add the radius of PID since some game update
								inreach = true
							end
						end
					end
					if inreach then
						local queue = con.commands


						if order_count == MAX_SEND then
							order_count = 0
						end
						if order_count == 0 then
							nDelayed = nDelayed + 1
							batch = {}
							delayedOrders[nDelayed] = batch
						end
						order_count = order_count + 1
						if not batch[id] then batch[id] = {} end

						-- table.insert(conArray,id)
						local noAct
						-- if noAct==nil then
							local cmds = queue
							local cmds_n = cmds and #cmds or 0 -- NOTE: when cheats are active and player is controllig unit's AI, we don't have the unit's queue
							noAct = direct or cmds_n == 0 or cmds_n == 1 and (cmds[1].id == 0 or cmds[1].id == 5)
							-- noAct=con.noAct
						-- end
						local order
						local posCommand
						if noAct and (i == 1 or g.modArena) then -- XYZP_TABLE : 4th param is commandTag for leveling or facing for building
							-- order = {cmdID,{unpack(XYZP_TABLE)},--[[CMD_OPT_INTERNAL +--]] (shift and CMD_OPT_SHIFT or 0) + (alt and CMD_OPT_ALT or 0)}
							order = {cmdID, {unpack(XYZP_TABLE)}, --[[CMD_OPT_INTERNAL +--]] opts.coded}
							posCommand = -1
						else
							posCommand = before and i - 1
								or (after or noAct) and -1
								or (con.insPoses[i] or 0) + (hasTerra and 1 or 0)
							-- Echo("insert " .. INSERT_TABLE[2] .. ' at ' .. posCommand)
							-- note: the engine refuse a build order on unfit terrain, hopefully INSERT order circumvent this problem
							-- Echo('=>> id ', id, 'x', pointX, 'z', pointZ,  'con.insPoses[i]', con.insPoses[i], 'posCommand', posCommand)
							INSERT_TABLE[1]  = posCommand

							--Echo("hasTerra is ", hasTerra,con.insPoses[i])
							--INSERT_TABLE breakdown : insertion point,level or building id,CMD_OPT_INTERNAL, pointX,pointY,pointZ,commandTag or facing
							-- spGiveOrderToUnit(id,CMD_INSERT,INSERT_TABLE,CMD_OPT_ALT+CMD_OPT_INTERNAL)
							-- if thisround then table.insert(thisround,{id,CMD_INSERT,{unpack(INSERT_TABLE)},CMD_OPT_ALT+CMD_OPT_INTERNAL}) end
							-- table.insert(orderArray,{CMD_INSERT,{unpack(INSERT_TABLE)},CMD_OPT_ALT+CMD_OPT_INTERNAL})
							-- table.insert(batch[id],{CMD_INSERT,{unpack(INSERT_TABLE)},CMD_OPT_ALT+(--[[shift and CMD_OPT_SHIFT or--]] 0)+CMD_OPT_INTERNAL})
							order = {CMD_INSERT, {unpack(INSERT_TABLE)}, CMD_OPT_ALT + (--[[shift and CMD_OPT_SHIFT or--]] 0)--[[+CMD_OPT_INTERNAL--]]}
							-- NOTE: CMD_OPT_SHIFT will bug the order if insertion is at 0, order will appear but will not be done
						end
						local cancelled
						if firstcon then

							-- simulate a command notify for guard remove check
								-- Echo("i==1, widgets.guard_remove, posCommand == con.queueSize, shift is ", i==1, widgets.guard_remove, posCommand, con.queueSize, shift)
							if i == 1 then
								if firstcon and WG.sounds_gaveOrderToUnit then
									-- Spring.PlaySoundFile(LUAUI_DIRNAME .. 'Sounds/buildbar_add.wav', 0.95, 'ui')
									 WG.sounds_gaveOrderToUnit(id, true)
								end
								if widgets.fix_autoguard and shift then
									widgets.fix_autoguard:CommandNotify(cmdID, {pointX, pointY, pointZ}, {shift = true})
								end
								if widgets.guard_remove and (posCommand == -1 or posCommand >= con.queueSize) and shift then
									widgets.guard_remove:CommandNotify(cmdID, {pointX, pointY, pointZ}, {shift = true})
								end
							end

							if hasTerra and round(placementHeight) ~= 0 then
								Debug.platform('register a platform for ' .. p.sizeX .. ' at ' .. pointX, pointZ)
								-- Echo('here 1')
								myPlatforms:New(p.sizeX, pointX, pointZ, PID)
							end
							conTable.inserted_time = time
							if conTable.inserted_time then

								-- cancelled = widgetHandler:CommandNotify(order[1],order[2],{coded=order[3]})
								-- Echo("'firstcon', id,cancelled is ", 'firstcon', id,cancelled)
								conTable.waitOrder = {order[1], order[2]}
								firstcon = false
							end
							if widgets.fac_preorder then
								widgets.fac_preorder:CommandNotify(cmdID, {pointX, pointY, pointZ, facing}, {shift = true})
							end

						end
						if not conTable.multiInsert then -- completing the virtual queue ourselves if MultiInsert wasn't called
							if posCommand == -1 then
								posCommand = con.queueSize
							end
							local coords = {pointX, pointZ, cmd = cmdID, facing = facing}
							table.insert(con.commands, posCommand + 1, coords)
							con.queueSize = con.queueSize + 1
						end
						if not inreach and posCommand == 0 then
							-- we guess there will be another order given to move the con, we duplicate to simulate it
							table.insert(con.commands, 1, con.commands[1])
							con.queueSize = con.queueSize + 1
						end
						if not cancelled then
							table.insert(batch[id], order)
						end
						if not commandTag then
							if widgets.building_starter then
								-- XYZ_TABLE[1],XYZ_TABLE[2],XYZ_TABLE[3]=pointX,pointY,pointZ
								widgets.building_starter:CommandNotify(cmdID, XYZP_TABLE, EMPTY_TABLE,true)
							end
							-- if widgets.ctrl_morph and ctrl then
							--     -- Echo('send ctrl', os.clock())
							--     -- widgets.ctrl_morph:UnitCommand(id, 0, myTeamID, cmdID, XYZP_TABLE, CTRL_TABLE)
							-- end
						end
					else
						conTable[id] = nil
					end
				end
			end
		end
	end
	if tryCI then
		------ Trying new CommandInsert
		local lot = WG.commandLot
		local cmd, p4
		for i, order in ipairs(lot) do
			local cmd
			-- if lot[i+1] and lot[i+1] == order then
			if lot[i].commandTag then
				cmd = CMD_LEVEL
				-- p4 = CreateTerra(order)
				p4 = lot[i].commandTag
			else
				cmd = order.pid and -order.pid or order.mex and -mexDefID or -PID
				p4 = p.facing
			end
			-- Echo(i,'sent',cmd,'params',order[1],order[2],order[3], p4)
			if cmd then
				WG.CommandInsert(cmd, {order[1], order[2], order[3], p4}, opts)
			end
		end
		for k,v in pairs(lot) do
			lot[k] = nil
		end
		for i, v in pairs(delayedOrders) do
			delayedOrders[i] = nil
		end
		return
		-------------
	end

	if delayedOrders[1] then
		local batch = table.remove(delayedOrders,1)
		local ID_TABLE = {}
		-- local sum = 0
		for id,orders in pairs(batch) do
			-- sum=sum+#orders
			ID_TABLE[1] = id
			for i, order in ipairs(orders) do
				-- Echo('order given',order[1],unpack(order[2]))
				-- if shift and meta and i==1 then
				--     if order[6] then
				--         local 
				--         WG.CommandInsert(order[1],{select(4,unpack(order[2]))},f.Decode(order[2][3]))
				--     -- else
				--     --     WG.CommandInsert(order[1],{select(4,order)},f.Decode(order[3]))
				--     end
				-- else
					spGiveOrderToUnit(id, unpack(order))
				-- end
			end
			-- Spring.GiveOrderArrayToUnitArray(ID_TABLE,orders) -- seems it is now choppy compared to simple give order
		end
		-- Echo("batch is ", sum)
	end
	-- orderF = Spring.GetGameFrame()
	-- Echo('ordered at ',Spring.GetGameFrame())

end




local function ProcessPreGameQueue(preGameQueue,tasker)
	local needTerra,commandTag
	for i=1,#preGameQueue do
		PID, pointX, pointY, pointZ, facing, needTerra = unpack(preGameQueue[i])
		-- Echo("PID,pointX,pointY,pointZ,facing,needTerra is ", PID,pointX,pointY,pointZ,facing,needTerra)
		if needTerra then
			if p.PID ~= PID or p.facing ~= facing then
				p = IdentifyPlacement(PID,facing)
			end

			commandTag = CreateTerra()
			-- spGiveOrderToUnit(tasker,CMD_INSERT,{-1,CMD_LEVEL,CMD_OPT_SHIFT, pointX, pointY, pointZ, commandTag},CMD_OPT_ALT)
			spGiveOrderToUnit(tasker, CMD_INSERT, {-1, CMD_LEVEL, CMD_OPT_SHIFT, pointX, pointY, pointZ, commandTag}, CMD_OPT_ALT + CMD_OPT_SHIFT)
		end
		spGiveOrderToUnit(tasker, CMD_INSERT, {-1, -PID, CMD_OPT_SHIFT, pointX, pointY, pointZ, facing}, CMD_OPT_ALT + CMD_OPT_SHIFT)
	end

end

-- local getCI = function ()     return widgetHandler:FindWidget("CommandInsert") and  true or false end
-- local stopCI = function ()  return  spSendCommands("luaui disablewidget CommandInsert") end
-- local enableCI = function ()    return  spSendCommands("luaui enablewidget CommandInsert") end

--if check("resume")>0.01 then check("reset") end
-- local cnt = 0
local function CheckForDuplicateMex(x, z)
	if timeBlockDuplicate then 
		-- this is for preventing mex to be cancelled because user would spam a mex
		-- few time after, Drawing Placement will fill up cantMex[spot] and then it won't matter
		-- but this wouldnt fix the problem if DrawingPlacement wasnt there
		-- and it doesnt fix the overalapping mex on area mex
		-- TODO need to centralize and unify the placement handling completely (big work)
		local time = os.clock()
		local changed = false
		for btime, toblock in pairs(timeBlockDuplicate) do
			if time - btime > SEND_DELAY then
				changed = true
				timeBlockDuplicate[btime] = nil
				-- Echo('delete duplicate', time - btime, toblock[1], toblock[2])
			else
				
				if toblock[1] == x and toblock[2] == z then
					-- Echo('blocked duplicate', time - btime, x, z)
					return true
				end
			end
		end
		if changed and not next(timeBlockDuplicate) then
			timeBlockDuplicate = nil
		end
	end
end
local function AddToBlockDuplicateMex(x, z)
	local time = os.clock()
	if not timeBlockDuplicate then
		timeBlockDuplicate = {}
	end
	if timeBlockDuplicate[time] then
		time = time + 0.01
		while timeBlockDuplicate[time] do
			time = time + 0.01
		end
	end
	-- Echo('add duplicate to block', time, x, z, 'already existing?', timeBlockDuplicate[time])
	timeBlockDuplicate[time] = {x, z}
end
local IsOccupied
do	
	local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
	function IsOccupied(x,z)
		return spGetUnitsInRectangle(x,z,x,z)[1]
	end
end
local IsMexable
do
	local spIsUnitAllied = Spring.IsUnitAllied
	local spGetUnitHealth = Spring.GetUnitHealth
	function IsMexable(x, z, ignoreEnemy)
		local mexID = IsOccupied(x, z)
		if not mexID then
			return true
		end

		if not spIsUnitAllied(mexID) then
			return ignoreEnemy or false
		end

			-- or select(5,Spring.GetUnitHealth(mexID))<1 and Spring.AreTeamsAllied(Spring.GetMyTeamID(), Spring.GetUnitTeam(mexID))
		return (select(5,spGetUnitHealth(mexID)) or 0) < 1
	end
end
do
	local solarDefID = UnitDefNames['energysolar'].id
	local solarp
	local windp
	local lotusp
	local count = 0
	function widget:CommandNotify(cmd, params, opts)
		count = count + 1
		-- NOTE: when using Alt and Draw Placement, it happens the active command get reset by some widget at CommandNotify stage
		-- replacing Mex Placement Handler behaviour 
		-- Echo('CN',cmd,unpack(params))
		-- for k,v in pairs(opts) do
		--     if v then
		--         Echo(k,v)
		--     end
		-- end
		-- if true then
		--     return
		-- end
		if delayedOrders[1] then 
			-- Echo('delayed order',#delayedOrders)
			-- return
		end
		-- local _alt, _ctrl, _meta, _shift = spGetModKeyState()
		alt, ctrl, meta, shift = opts.alt, opts.ctrl, opts.meta, opts.shift
		-- if not shift and _shift and cmd~=1 then
		--     Echo('got shift !') -- I guess that will happens if the key is released after sending // never happened so far
		--     Echo("debug.traceback() is ", debug.traceback())
		-- end
		local doMex 

		if cmd == -mexDefID then
			doMex=true
		elseif cmd == CMD_AREA_MEX then
			doMex = true
		end
		if doMex then


			local addLotus = ctrl and alt and shift
			if not addLotus and (ctrl or alt or shift or g.autoMex) then -- cancelled because not implemented with featured mexing (variant with solars added)
				if shift and not (ctrl or alt) then
					-- let PBH do the leveling if needed
					return
				else
					-- let the mex placement handler add 1 or 2 solar
					local watchForDuplicate = params[4] and params[4] <= 1 -- TODO this cover single mex but we should fix the removing of area mex 
					if watchForDuplicate and CheckForDuplicateMex(params[1], params[3]) then
						return true
					end

					local ret = widgets.mex_placement and widgets.mex_placement:CommandNotify(cmd, params, opts)
					if ret then
						WG.sounds_gaveOrderToUnit(cons[1], true)
						if watchForDuplicate then
							AddToBlockDuplicateMex(params[1], params[3])
						end
					end
					return ret
				end
			end
			local cx, cy, cz, cr = params[1], params[2], params[3], params[4]--math.max((params[4] or 60),60)
			local spot
			if cr <= 1  then
				spot = WG.GetClosestMetalSpot and WG.GetClosestMetalSpot(cx,cz)
				if not spot then
					return true
				end
				cx, cz = spot.x, spot.z
			end
			PID = mexDefID
			p = IdentifyPlacement(mexDefID)
			if not solarp then
				solarp = IdentifyPlacement(solarDefID)
				windp = IdentifyPlacement(windDefID)
				lotusp = IdentifyPlacement(lotusDefID) 
			end
			placementHeight=0

			local tmp={}
			local n = 0
			local centerX, centerZ = maxx/2, maxz/2
			local function GetDirsToCenter(x,z)
				local dirx,dirz = centerX-x, centerZ-z
				local biggest = math.max(abs(dirx),abs(dirz))
				return dirx/biggest, dirz/biggest
			end
			local function ApplyMex(mex)
				local mx,mz = mex.x,mex.z
				
				--if (mex.x > xmin) and (mex.x < xmax) and (mex.z > zmin) and (mex.z < zmax) then -- square area, should be faster
				if  ( (cx-mx)^2 + (cz-mz)^2 ) <= cr^2  then -- circle area, slower
					 if IsMexable(mx, mz, true) then 
						n = n+1
						-- Echo("mx,mz,p.sizeX,p.sizeZ,mexDefID,pid=mexDefID is ", mx,mz,p.sizeX,p.sizeZ,mexDefID)
						tmp[n] = {mx,mz,p.sizeX,p.sizeZ,mexDefID,pid=mexDefID}
					end

					--commands[#commands+1] = {x = mex.x, z = mex.z, d = Distance(aveX,aveZ,mex.x,mex.z)}
					-- CheckTerra(mx,mz,mexDefID)

					-- table.insert(tmp,{mx,mz,true})

					if addLotus then
						local dirx,dirz = GetDirsToCenter(mx,mz)
						-- local x,z = groundModule:clamp(mx+40,mz,lotusp.sizeX,lotusp.sizeZ)
						local offset = p.sizeX + lotusp.sizeX
						local x,z = groundModule:ValidPlacement(mx+dirx*offset,mz+dirz*offset,nil,lotusp)
						CheckTerra(x,z,lotusDefID,tmp,lotusp)
						if blockingStruct then
							-- Echo('lotus got blocking')
							if blockingStruct.defID == lotusDefID then
								x = false
							else
								x,z = FindPlacementAround(x,z,tmp,lotusDefID,lotusp)
							end
						end
						if x then
							n = n + 1
							tmp[n] = {x,z,lotusp.sizeX,lotusp.sizeZ,lotusDefID,pid=lotusDefID}
						end
						-- x,z = groundModule:clamp(mx+72+24,mz,solarp.sizeX,solarp.sizeZ)
						offset = offset + lotusp.sizeX + solarp.sizeX
						local ep,eDefID = solarp, solarDefID
						x,z = groundModule:ValidPlacement(mx+dirx*(offset),mz+dirz*(offset),nil,solarp)
						CheckTerra(x,z,eDefID,tmp,ep)
						if blockingStruct then
							if blockingStruct.defID == solarDefID or blockingStruct.defID == windDefID then
								x = false
							else
								x,z = FindPlacementAround(x,z,tmp,eDefID,ep)
								CheckTerra(x,z,eDefID,tmp,ep)
							end
						end
						if not blockingStruct then
							local isWater = spGetGroundHeight(x,z) < 0.1
							if isWater or mustTerraform then
								offset = offset - solarp.sizeX + windp.sizeX
								ep,eDefID = windp, windDefID
								x,z = groundModule:ValidPlacement(mx+dirx*(offset),mz+dirz*(offset),nil,windp)
								CheckTerra(x,z,eDefID,tmp,ep)
							end
						end
						if x then
							n = n + 1
							tmp[n] = {x,z,ep.sizeX,ep.sizeZ,eDefID,pid=eDefID}
						end
					end

					-- table.insert(tmp,{mx+32,mz,true})
				end

			end
			if spot then -- meaning there is only a single mex to deal with
				ApplyMex(spot)
			elseif spotsPos then
				local spots = WG.metalSpots
				for i = 1, #spots do
					ApplyMex(spots[i])
				end
			else
				n = n + 1
				tmp[n] = {cx, cz ,p.sizeX, p.sizeZ, mexDefID, pid = mexDefID}
			end
			---------------------------------------------
			-- sort the mexes placements by proximity of the last move/placement
			local con = cons[1]
			local queue = g.preGame and WG.preGameBuildQueue or spGetCommandQueue(con,-1)
			if not queue then  
				return
			end
			local lastorder = queue[#queue]
			local lastpos
			-- local lastpos = lastorder and (shift or meta) and lastorder.params and Spring.Utilities.IsValidPosition(lastorder.params[1],lastorder.params[3]) and {lastorder.params[1],lastorder.params[3]} 
			if con then
				lastpos = {spGetUnitPosition(con)}
				table.remove(lastpos,2)
			else
				lastpos = tmp[1]
			end

			local i,finish=1,#tmp
			if finish > 0 then
				if finish > 1 then
					local minDist = (lastpos[1]-tmp[1][1])^2 + (lastpos[2]-tmp[1][2])^2
					local best = 1
					while i<finish do

						local isMex = tmp[i][3]
						i=i+1
						local newDist = (lastpos[1]-tmp[i][1])^2 + (lastpos[2]-tmp[i][2])^2
						if newDist < (minDist --[[+ (isMex and 1000 or 0)--]]) then
							minDist=newDist
							best=i
						end
						if i == finish then
							lastpos = tmp[best]
							table.insert(WG.commandLot,(table.remove(tmp,best)))
							minDist = (lastpos[1]-tmp[1][1])^2 + (lastpos[2]-tmp[1][2])^2
							i=1
							finish=finish-1
							best=1
						end
					end
				end
				table.insert(WG.commandLot,(table.remove(tmp,1)))
			end
			if addLotus then -- put the mex at first to build for each cluster
				local lot = WG.commandLot
				local clusterStart = 1
				local mex
				local prev
				for i,v in ipairs(lot) do
					local nex = lot[i]
					mex = v.pid == mexDefID and i
					if prev then
						local dist = ( (prev[1]-v[1])^2 + (prev[2]-v[2])^2 ) ^0.5
						if dist > 100 then
							clusterStart = i
						end
					end
					if mex and clusterStart ~= mex then
						lot[clusterStart],lot[mex] =  lot[mex], lot[clusterStart]
						mex = false
					end
					prev = v
				end
			end
			-- PID = false
			-- Spring.PlaySoundFile(sound_queue_add, 0.95, 'ui')

			-- if shift then
			--     WG.OtherWidgetPlacedMex()
			-- end
			return true
		end
		------------------------------------------------------
		--

		if shift and PID and cmd==0 and not params[1]  then
			-- spGiveOrderToUnitArray(cons,CMD.STOP, {},{})
			-- spSetActiveCommand(-1) -- cancel with S while placing multiple
			-- reset(shift)
		end
		if pointX then
			if cmd<0 and PID --[[and PID~=mexDefID--]] and params[3] then
				if ignoreFirst then 
					ignoreFirst=false
				else

					pointX = params[1]
					pointZ = params[3]
					table.insert(WG.commandLot, {params[1],params[3],nil,p.facing~=params[4] and params[4]})
				end

				if mustTerraform then
					return true
				end
			end
		end
	end
end
--Page(CMD,'45')
local terraDefID = UnitDefNames['terraunit'].id
local cmdTags = {}
local tagHolder = {}
local terraUnits = {}
local attachTerraUnits = {}

function widget:UnitDestroyed(unitID, defID, team)
	if team ~= myTeamID then
		return
	end
	if defID == terraDefID and terraUnits[unitID] and opt.auto_fix_mex then
		local xz = terraUnits[unitID]
		local x,z
		if xz then
			x, z = xz:match(('^([^%-]+)%-([^%-]+)')) 
			if x then
				x, z = tonumber(x), tonumber(z)
			end
			Debug.fixMex('x, z is',x, z, '=>',cmdTags[x] and cmdTags[x][z])
		end
		local commandTag = z and cmdTags[x] and cmdTags[x][z]
		if commandTag then
			cmdTags[x][z] = nil
			if not next(cmdTags[x]) then
				cmdTags[x] = nil
			end
			tagHolder[commandTag] = nil
			Debug.fixMex('successfully destroyed commandTag',commandTag)
		end

	end
end
local IsCmdReallyDone = function(unitID,defID, team, cmdDone, params)
	local cmd,_,_,p1,_,p3 = spGetUnitCurrentCommand(unitID)
	if not cmd then
		Debug.fixMex('no cmd, '.. cmdDone ..' done')
		return true
	end
	if (cmd == cmdDone and p1 == params[1] and p3 == params[3]) then
		Debug.fixMex('cmdDone is same as current '.. cmdDone .. ', not done')
		return false
	end

	local hasThisOrder -- this is costly
	local queue = spGetCommandQueue(unitID,-1)
	for i, order in ipairs(queue) do
		if order.id == cmdDone and order.params[1] == params[1] and order.params[3] == params[3] then
			hasThisOrder = true
			break
		end
	end
	if hasThisOrder then
		-- Echo('unit',unitID,'has already this order','cur cmd',cmd,'p',p1,p3)
		Debug.fixMex('got this order in the queue '.. cmdDone .. ', not done')
		return false
	end
	Debug.fixMex('dont got the order ' .. cmdDone .. ', done')
	return true
end

function widget:UnitCmdDone(unitID, defID, team, cmdDone, params)
	if team ~= myTeamID then
		return
	end

	--[[if cmdDone == CMD_LEVEL and opt.auto_fix_mex and IsCmdReallyDone(unitID,defID, team, cmdDone, params) then
		local commandTag = params[4]
		local xz = params[1]..'-'..params[3]
		local found = tagHolder[commandTag]
		-- Echo(os.clock(),'CMD_LEVEL done, commandTag:', commandTag,'x-z',xz,'found?',found)

	else--]]
	if cmdDone == -mexDefID and spotsPos and opt.auto_fix_mex and  params[3] and not params[5] then

		if IsCmdReallyDone(unitID,defID, team, cmdDone, params) then
			local x,y,z = unpack(params)
			local commandTag = cmdTags[x] and cmdTags[x][z]
			if not commandTag then    
				if not Spring.GetUnitsInRectangle(x,z,x,z)[1] then
					-- Echo("spGetGroundBlocked(mexDefID,x,y,z) is ", Spring.GetGroundBlocked(x-24,z-24,x+24,z+24))
					if Spring.TestBuildOrder(mexDefID, x, 0, z, 1) == 0 then
						if CheckTerra(x, z, mexDefID, nil, nil, 0) then
							commandTag = groundModule:SetTerraforming( {unitID}, myTeamID, x, y, z, 23.9, 23.9)
							cmdTags[x] = cmdTags[x] or {}
							cmdTags[x][z] = commandTag
							tagHolder[commandTag] = false
							attachTerraUnits[unitID] = commandTag
							Debug.fixMex(os.clock(),unitID, 'create terra tag', commandTag, 'at '..x,z)
						end
					end
				end
			else
				Debug.fixMex(os.clock(), unitID, 'reuse terra tag', commandTag)
			end
			if commandTag then
				spGiveOrderToUnit(unitID,CMD_INSERT, {0, CMD_LEVEL,CMD_OPT_SHIFT, x, y, z, commandTag}, CMD_OPT_ALT + CMD_OPT_SHIFT)
				spGiveOrderToUnit(unitID,CMD_INSERT, {1, -mexDefID,CMD_OPT_SHIFT, x, y, z, 1}, CMD_OPT_ALT + CMD_OPT_SHIFT)
			end
		end
	end
end



function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	if cmdID == CMD_INSERT and opt.auto_fix_mex then
		local commandTag = attachTerraUnits[unitID]
		if commandTag then
			if tagHolder[commandTag] then
				return
			end
			if cmdParams[2] == CMD_LEVEL then
				-- skip
			elseif cmdParams[1] == 0 and cmdParams[2] == CMD_REPAIR then
				local debugMe = Debug.fixMex()
				local terraID = cmdParams[4]
				local defID = terraID and spGetUnitDefID(terraID)
				if debugMe then
					Echo(terraID, 'terraDefID ?', terraDefID, defID)
				end
				if defID == terraDefID then
					-- local order = spGetCommandQueue(unitID,1)[1]
					local cmd, _, _, p1, p2, p3, p4 = spGetUnitCurrentCommand(unitID)
					if debugMe then
						Echo('cmd ?', cmd, p4,'==', commandTag)
					end
					if cmd == CMD_LEVEL then
						if p4 == commandTag  then
							local xz = p1 .. '-' .. p3
							terraUnits[terraID] = xz
							tagHolder[commandTag] = terraID
							if debugMe then
								Echo('created attachment of terra unit ',terraID, 'to xz', p1, p3,' verif?', cmdTags[p1] and cmdTags[p1][p3])
							end
						end
					end
					attachTerraUnits[unitID] = nil
				end
				
			end

		end
	end

	if conTable.waitOrder and conTable.cons[unitID] then
		local waitOrder = conTable.waitOrder
		if waitOrder[1] == cmdID and table.compare(waitOrder[2], cmdParams) then -- until the last (but first of a batch) user order has not been received here, we keep the virtual queue made by multiinsert
			conTable.inserted_time = false
			conTable.waitOrder = false
			-- Echo('UC at ',Spring.GetGameFrame(),Spring.GetGameFrame()-orderF,spGetCommandQueue(unitID,0))
		end
		-- conTable.inserted_time = false
	end
	-- cnt = cnt + 1
	-- Echo('#'..cnt,'unit: ' .. unitID, 'cmd: ' .. cmdID, 'params:','opts: '.. cmdOpts.coded,unpack(cmdParams))
--[[            local comment, cmdName
			if cmdID==1 then 
				for k,v in pairs(CMD) do if k==cmdParams[2] then cmdName=k end end
				if not cmdName then for k,v in pairs(customCmds) do if v==cmdParams[2] then cmdName=k end end end
				if cmdName then comment = 'inserting '..cmdName..' at '..cmdParams[1]
				else comment = 'cmdName not found'
				end
			else
				for k,v in pairs(CMD) do if k==cmdID then cmdName=v end end
				if not cmdName then for k,v in pairs(customCmds) do if v==cmdID then cmdName=k end end end
				if cmdName then comment = cmdName
				else
					comment = 'cmdName is not found'
				end

			end
			Echo(comment)
		Echo("cmdID:"..cmdID,'Params: ',unpack(cmdParams))
		Echo("cmdOpts.coded is ", cmdOpts.coded)--]]
--Echo("UnitDefs[unetDefID].canLoopbackAttack is ", UnitDefs[unitDefID].canLoopbackAttack)
	--if unitID==24703 then Echo("PBH UC unit:"..unitID,cmdID,unpack(cmdParams)) end
	--if g.preGame then Echo("order stop") spGiveOrderToUnitArray({unitID},CMD.STOP, {},{}) end
end
function widget:SelectionChanged(newsel,less)
	-- local identical = #cons == #newsel
	-- if identical then
	--     local common = {}
	--     for i,id in ipairs(cons) do
	--         common[id] = true
	--     end
	--     for i,id in ipairs(newsel) do
	--         if not common[id] then
	--             identical = false
	--             break
	--         end
	--     end
	--     if identical then
	--         Echo(' in selection changed: the selection is actually identical !',os.clock())
	--     end
	-- end
end

function widget:CommandsChanged()
	-- if not ordered then cons=getcons() end
	local newsel = getcons()
	myPlatforms.x, myPlatforms.z = false,false
	-- local identical = #cons == #newsel
	-- if identical then
	--     local common = {}
	--     for i,id in ipairs(cons) do
	--         common[id] = true
	--     end
	--     for i,id in ipairs(newsel) do
	--         if not common[id] then
	--             identical = false
	--             break
	--         end
	--     end
	--     if identical then
	--         Echo(' in Commands changed: the selection is actually identical !',os.clock())
	--     end
	-- end

	cons = newsel

	conTable = getconTable()
end


-- local function TransferDrawData(needTerra)
--     -- Echo("needTerra is ", needTerra)
--     if WG.DrawTerra.ready then
--         local DT = WG.DrawTerra
--         DT.new=true
--         DT.finish=false
--           DT[1],  DT[2], DT[3], DT[4],  DT[5],                DT[6],             DT[7],  DT[8],    DT[9],   DT[10]
--         = pointX,pointY,pointZ,p.sizeX,p.sizeZ, (p.floatOnWater and pointY<=OFF_WATER), PID, p.facing, needTerra,drawWater

--         return true
--     end
-- end

local TransferDrawData
do
	local WG = WG
	-- local DT = WG.DrawTerra
	local draw
	TransferDrawData = function(needTerra)
		-- WG.DrawTerra={}
		-- if not DT then DT = WG.DrawTerra end
		-- Echo("WG.DrawTerra is ", WG.DrawTerra,DT.ready,not (DT or DT.ready) )
		-- if not (DT and DT.ready) then return end
		if WG.DrawTerra.ready then
			if not PID then
				Echo('NO PID WHEN SENDING DRAW TERRA DATA!')
				Echo(debug.traceback())
				return
			end
			local DT = WG.DrawTerra
			-- if needTerra then
				DT.new=true
				DT.finish=false
				  DT[1],   DT[2],  DT[3],  DT[4],   DT[5],                DT[6],             DT[7],  DT[8],    DT[9],     DT[10]
				= pointX, pointY, pointZ, p.sizeX, p.sizeZ, (p.floatOnWater and pointY<=0.1), PID,  p.facing, needTerra, drawWater

				-- WG.DrawTerra = draw
				-- Echo("needTerra is ", needTerra)
				return true
			-- elseif DT.working then
				-- Echo("DT.finish is ", DT.finish)
				-- DT.finish=true
			-- end
		end
	end
end
-- TransferDrawData = function(needTerra) end

-- local function FindClosestPlace(x,z)
-- end



function TreatLot(lot,PID, useBuildHeight, exceptPlatform)
	if plateDefID[PID] and CheckPlateReach(lot, PID) then
		-- if not CheckPlateReach(lot, PID) then
		--     conTable.fromPBH = true
		--     return conTable
		-- end
		-- remove plate placements that are out of range
		local s, i = lot[1], 1
		while s do
			if not s.inreach then
				table.remove(lot,i)
			else
				i = i + 1
			end
			s = lot[i]
		end
	end
	ApplyHeight(lot, useBuildHeight, exceptPlatform)
	if SPECIFIED_MEMORY then
		if heightsToForgetAfterPlacing[PID] then
			if select(4, spGetModKeyState()) then
				toForgetOnShiftRelease = PID
			else
				buildHeight[PID] = 0
			end
		end
	end
	if g.preGame then
		local IQ = widgetHandler:FindWidget("Initial Queue ZK")
		if IQ then
			local prevb
			for i,b in ipairs(lot) do
				if not prevb or (prevb[1]~=b[1] or prevb[3]~=b[3]) then -- ignore duplicate
					IQ:CommandNotify(b.mex and -mexDefID or -PID,{b[1],b[2],b[3],b.facing,b.terra},{alt=alt,ctrl=ctrl,shift=shift,meta=meta})
				end
				prevb=b
			end
		end
	else
		DistributeOrders(lot, PID, meta, shift or lot.shift)
	end
	for k in pairs(lot) do lot[k]=nil end
	reset(shift)
	conTable.fromPBH = true

	-- for i,order in ipairs(conTable.cons[ cons[1] ].commands) do
	--     Echo('in conTable.commands',i,order.cmd,order.facing)
	-- end
	return conTable
end
--local interval=0

-- Update process
local lastCamDist = 0

local function Process(mx, my, update)
	-- Should not ignore water if the structure can float. See https://springrts.com/mantis/view.php?id=5390
	local px, _, pz
	if not mx then
		mx,my = spGetMouseState()
	end
	if not leftClick then
		useMinimap = spIsAboveMiniMap(mx, my)
	elseif useMinimap then
		mx, my = ClampMouseToMinimap(mx, my)
	end

	-- if useMinimap then
	-- 	mx, my = ClampMouseToMinimap(mx, my)
	-- end

	px, _, pz, offmap = UniTraceScreenRay(mx, my, useMinimap, p.underSea, p.sizeX, p.sizeZ)
	if not px then
		return
	end

	--special = shift and table.has(eSpec,PID)
	if update or p.facing ~= spGetBuildFacing() then
		p = IdentifyPlacement(PID)
		p.facing = spGetBuildFacing()
		update = true
	end
	p.spacing = spGetBuildSpacing()

	-- Echo("upx,upy,upz is ", upx,upy,upz)

	-- local   _, pos = spTraceScreenRay(mx, my, true, false, false, not p.floater)



	local mex
	if PID == mexDefID then 
		mex =  spotsPos and WG.GetClosestMetalSpot(px,pz)
		if mex then px,pz = mex.x, mex.z end
		update = true
	end

	if not (mex) then
	--Echo("mouseCount", mouseCount)
		px,pz = floor((px + 8 - p.oddX)/16)*16 + p.oddX, floor((pz + 8 - p.oddZ)/16)*16 + p.oddZ
	--Echo(spPos2BuildPos(PID,px,0,pz,p.facing))
		-- local sx,sz = p.sizeX,p.sizeZ
		-- if px-sx<0 then px=sx elseif px+sx>maxx then px=maxx-sx end
		-- if pz-sz<0 then pz=sz elseif pz+sz>maxz then pz=maxz-sz end
	end
	local geoSpot
	if PID == geoDefID then
		px, pz, geoSpot = CheckGeos(px, pz)
		update = true

	end
	local moved = px~=prev.x or pz~=prev.z
	update = update or moved or Cam.dist ~= lastCamDist
	if update then
		elevRangeDraw.update = update
	end

	lastCamDist = Cam.dist
	-- updating Drawing datas if something new
	--if prevX==px and prevZ==pz and not newheight then --[[Echo('not updating')--]] return  end
	if not update then --[[Echo('not updating')--]] return end

	-- Points={} -- debugging
	prev.x,prev.z = px, pz

	pointX,pointZ = px,pz
	p.spacing = spGetBuildSpacing()

	local platX, platZ
	if opt.findPlatform then
		platX, platZ = myPlatforms:Process(px,pz)
		-- Echo('look for plat',os.clock(),'=>',platX, platZ)
	end
	if platX then
		needTerra = CheckTerra(platX, platZ)
		if not blockingStruct then
			pointX, pointZ = platX, platZ
			needTerra = CheckTerra()
		end
	else
		if not platX then
			if moved then
				if movedPlacement[1] == -1 then
					groundModule:AdjustPH(pointX,pointZ,p)
					groundModule.offsetPH = nil
					groundModule.lastOffset = nil
				end
			end
			needTerra = CheckTerra()
			
		end
	end

	--[[Echo('updating')--]]
	drawWater = pointY < 80 and pointY > -80 -- showing water level when approaching of it
			-- Callin may have been removed
	movedPlacement[1]=-1
	-- Echo("sloppedTerrain is ", sloppedTerrain)
	-- Echo("surround is ", surround)
	if not platX --[[and (surround or 0) < 2500--]] and PID~=mexDefID then --
		local noterra = g.noterra
		if noterra or PID~=geoDefID or geoSpot then
			local lookingForFlat = noterra or not blockingStruct and sloppedTerrain and mol(placementHeight,0,7)
				and (PID == windDefID and opt.force_wind_no_terra or Cam.relDist>2000)
			local findAround = lookingForFlat or blockingStruct
			-- Echo("wantNoTerra is ", wantNoTerra, findAround)
			-- Echo('=>',math.round(os.clock()))
			-- Echo("lookingForFlat, blockingStruct is ", lookingForFlat, blockingStruct)
			if findAround then
				FindPlacementAround(pointX, pointZ, nil, nil, nil, lookingForFlat)
			end
		end
	end 
	if not TransferDrawData(needTerra) then
		widgetHandler:UpdateWidgetCallIn("DrawWorld", widget)
	end
	update = false
end
widget.Process = Process


function widget:Update(dt)
	-- time = time + dt
	-- if g.testGround==nil then
	--     g.testGround = spGetGroundHeight(100,100)
	-- elseif g.testGround and  g.testGround~=spGetGroundHeight(100,100) then
	--     Echo('TEST GROUND HAS BEEN MODIFIED','time',time,'frame',Spring.GetGameFrame())
	--     g.testGround = false
	-- end
--[[    interval = interval+dt --- CHECK THE LAG
	delta = dt
	if interval>1 then Echo(dt) interval=0 end--]]
	if delayedOrders[1] then
		-- Echo("#delayedOrders is ", #delayedOrders)
		local batch = table.remove(delayedOrders,1)
		local ID_TABLE={}
		-- local sum=0
		for id,orders in pairs(batch) do
			-- sum=sum+#orders
			ID_TABLE[1]=id
			for i,order in ipairs(orders) do
				spGiveOrderToUnit(id,unpack(order))
			end
			-- Spring.GiveOrderArrayToUnitArray(ID_TABLE,orders) -- seems it is now choppy compared to simple give order
		-- if orderArray[1] then
		--     Spring.GiveOrderArrayToUnitArray(conArray,orderArray)
		end
		-- Echo("batch is ", sum)

	end
	WG.placementX, WG.placementZ = pointX, pointZ
	local wasLeftClick, wasRightClick = leftClick, rightClick
	alt,ctrl,meta,shift = spGetModKeyState()

	_,_,leftClick,_,rightClick = spGetMouseState()

	if mexToAreaMex == 'back' and wasLeftClick and not leftClick then
			spSetActiveCommand('buildunit_staticmex')
			-- if widgets.drawing_placement then

			-- mexToAreaMex = 'alt'
	end
	if g.autoMex and not rightClick then
		-- PID = false
		-- ordered = true
		if WG.commandLot[1] then
			TreatLot(WG.commandLot, mexDefID)
			for k in pairs(WG.commandLot) do
				WG.commandLot[k] = nil
			end
		end
		g.autoMex = false
		if not widgets.drawing_placement then
			spSetActiveCommand(-1)
		end
	end
	-- if PID and (wasLeftClick and not leftClick or wasRightClick and not rightClick) then
	--     ordered = true
	--     -- if not shift then
	--     --     Echo('=> reset',os.clock())
	--     --     reset(shift)
	--     -- end
	-- end
-- Echo("WG.PreSelection_GetUnitUnderCursor(true) is ", WG.PreSelection_GetUnitUnderCursor(true))
	update = update or surround ~= (ctrl and shift and Cam.relDist)
	if update then
		elevRangeDraw.update = update
	end
	surround = (ctrl and shift) and Cam.relDist

--Echo("WG.Chili.Grid.MouseMove() is ", WG.Chili.Grid.OnClick)
	if PID and
		(
			leftClick and rightClick 
			or rightClick and ordered
			or wasRightClick and not rightClick and not WG.drawEnabled
		)
	then
		-- resetting while placing if rightclick
		local aCom = select(2,spGetActiveCommand())
		if not widgets.drawing_placement and -(aCom or 0) == PID then
			spSetActiveCommand(-1)
		end
		for k in pairs(WG.commandLot) do
			WG.commandLot[k] = nil
		end
		--Echo("stopped with rightClick")
		reset(shift,nil,forceResetAcom)
	end

--Echo("g.preGame",g.preGame)

	-- commandLot = #WG.commandLot>0 and WG.commandLot or commandLot -- getting global commandLot from draw placement widget, or own commandLot
	-- shift = shift or WG.commandLot.shift
	if (not shift or not leftClick)--[[(not leftClick or meta)--]] and WG.commandLot[1] and PID then
		TreatLot(WG.commandLot,PID) -- it can happen the PID got reset just after
		if meta and not shift then
			-- get back activecommand when inserting single ?
			-- spSetActiveCommand(currentCommand)
		end
		reset(shift,nil,forceResetAcom)
		for k in pairs(WG.commandLot) do
			WG.commandLot[k] = nil
		end
	end


	local Com, activeCommand = spGetActiveCommand()
	if (not activeCommand) or (activeCommand >= 0) then
		if PID then
			if widgets.drawing_placement then
				reset()
			elseif not (shift or meta) then
				reset()
			end
		end
		return
	end
	-- Echo("PID ~= -activeCommand is ", PID ~= -activeCommand)
	if PID ~= -activeCommand then
		PID = -activeCommand
		-- Echo('set PID',PID,os.clock())
		myPlatforms.oriPH = false
		placementHeight= not g.noterra and buildHeight[PID] or 0
		local engaged = widgets.drawing_placement and widgets.drawing_placement.dstatus == 'engaged'
		if not engaged then
			g.NEW_PID = true
		end
		if g.NEW_PID then
			placementHeight = 0
		end
		WG.placementHeight = placementHeight
		-- if not CI_Disabled then
		--     -- local widgets.command_insert = widgetHandler:FindWidget('CommandInsert')
		--     -- if widgets.command_insert then
		--     --     widgetHandler:RemoveWidgetCallIn("CommandNotify", widgets.command_insert)
		--     --     CI_Disabled = true
		--     -- end
		-- end
		currentCommand=Com -- backup to recover PID on use of meta -- not used anymore
		update = true
	end
	if not PID then
		return
	end

	Process(mx, my, update)
	update = false
end
local EraseOverlap
do

	local GetQueue,GiveOrder,CMD_REMOVE,pcall = spGetCommandQueue,spGiveOrderToUnit,CMD.REMOVE,pcall
	EraseOverlap = function(x,z)
		x,z = x or pointX, z or pointZ
		local sx,sz = p.terraSizeX, p.terraSizeZ
		local erased
		if g.preGame then -- this is not implemented as rigth hold click
			local IQ = widgetHandler:FindWidget("Initial Queue ZK")
			if not IQ then return end
			local queue =  WG.preGameBuildQueue
			local j, n = 1, #queue

			while j<=n do 
				local order = queue[j]
				local id,ix,iy,iz,facing,terra = unpack(order)
				local ud=UnitDefs[id] 
				local isx,isz=ud.xsize*4,ud.zsize*4
				local off=facing==1 or facing==3
				if off then isx,isz=isz,isx end
				if (x-ix)^2 < (sx+isx)^2 and (z-iz)^2 < (sz+isz)^2 then
					IQ:CommandNotify(-id,{ix,iy,iz,facing},{shift=true})
					local newn = #queue
					if newn~=n then 
						n=newn
						erased = true
						j=j-1
					end
				end
				j=j+1
			end
			return erased
		end
		local plopped = {}
		for i=1, #cons do
			local con=cons[i]
			if spValidUnitID(con) and not spGetUnitIsDead(con) then
				local queue=GetQueue(con,-1)
				if queue then
					local levelx,levelz,leveltag
					for j=2,#queue do -- not checking the first command, as the build may have been nanoframed if it is at first order
						local command = queue[j]
						local cmdid = command.id
						if cmdid < 0 or cmdid == CMD_LEVEL then
							local params=queue[j].params
							local ud = cmdid < 0 and UnitDefs[-cmdid]
							if ud then
								local tag,ix,iz,facing = command.tag,params[1],params[3],params[4]
								local isx,isz=ud.xsize*4,ud.zsize*4
								local off=facing==1 or facing==3
								if off then isx,isz=isz,isx end
								-- overlap check
								if (x-ix)^2 < (sx+isx)^2 and (z-iz)^2 < (sz+isz)^2 then
									local authorized = true
									if j==1 then
										local ixiz = ix .. iz
										if plopped[ixiz]==nil then 
											plopped[ixiz] = sp.GetUnitsInRectangle(ix,iz,ix,iz)[1] or false
										end
										authorized = plopped[ixiz] == false
									end
									if authorized then
										if levelx==ix and levelz==iz then 
											pcall(GiveOrder(con,CMD_REMOVE, leveltag, 0))
										end
										GiveOrder(con,CMD_REMOVE, tag, 0)
										erased=true
									end
								end
							elseif cmdid== CMD_LEVEL then
								levelx,levelz = params[1], params[3]
								leveltag = command.tag
							else
								levelx=false
							end
						else
							----- not erasing other command
							-- local ix, iy, iz = GetCommandPos(command)
							-- if ix and (x-ix)^2 < (sx)^2 and (z-iz)^2 < (sz)^2 then
							--     GiveOrder(con,CMD_REMOVE, command.tag, 0)
							--     erased=true
							-- end
							------
						end
					end
				end
			end
		end
		return erased
	end
end



local count = 0
local spGetDefaultCommand = Spring.GetDefaultCommand

function widget:MousePress(mx, my, button)
	-- Echo("meta and PID is ", meta and PID, meta and PID and ordered)
	alt, ctrl, meta, shift = spGetModKeyState()
	-- Echo("spGetActiveCommand() is ", spGetActiveCommand())
	if button == 1 then
		leftClick = true
		forceResetAcom = false
	elseif button == 3 then
		rightClick = true
		if PID and not ordered and not widgets.drawing_placement then
			return true
		end
	end

	if button == 3 and not PID and select(2, spGetDefaultCommand()) == -mexDefID then
		g.autoMex = true -- Mex Placement Handler has set the default command to mex because user mouse is hovering a mex placement
		-- spSetActiveCommand(-mexDefID)
		return
	end

	-- spSetActiveCommand('staticmex')
	-- Echo(os.clock(),mexDefID,"select(2,spGetActiveCommand()) is ", select(2,spGetActiveCommand()))
	if not PID then
		return
	end
	if button == 1 then
		if PID ~= -(select(2, spGetActiveCommand()) or 0) then
			reset()
			return
		end
		if not (cons[1] or g.preGame) or WG.Chili.Screen0:IsAbove(mx,my) then
			return
		end
		useMinimap = spIsAboveMiniMap(mx, my)

		-- update pointX, pointY, pointZ as something might have happened between the last update and the click
		Process(mx, my, true)
	end
	if not (PID and pointX and pointZ) then

		return
	end
	if WG.drawingPlacement and shift and not ctrl then
		-- let Drawing Placement widget taking over
		-- pointX,pointZ = floor((px + 8 - p.oddX)/16)*16 + p.oddX, floor((pz + 8 - p.oddZ)/16)*16 + p.oddZ
		local canBuild = spTestBuildOrder(PID, pointX, 0, pointZ, p.facing) ~= 0
		if canBuild and not myPlatforms.x and (groundModule.elevated or groundModule.subelevated) then
			-- Echo('here 2')
			myPlatforms:New(p.sizeX,pointX,pointZ,PID)
		end
		return
	end

	if button == 3 then
		-- Echo("spGetActiveCommand() is ", spGetActiveCommand())
		-- spSetActiveCommand(0)
		if workOnRelease then
			workOnRelease = false
			widgetHandler.mouseOwner = nil
		end
		if not shift then
			-- reset(shift,true) 
			reset() 
		end
		return --true
	end
	-- if button == 1 and widgets.command_insert and meta and not shift and pointX then -- 
	--     widgetHandler:RemoveWidgetCallIn("CommandNotify", widgets.command_insert)
	--     CI_Disabled=true
	--     Echo('remove widgets.command_insert')
	-- end
	local surroundCancelled = false
	if button == 1 and shift and ctrl then
		-- prevent from ordering surrounding buildings by the engine around a flying air unit
		local under = WG.PreSelection_GetUnitUnderCursor()
		-- this to prevent an accidental surrournding because a flying unit just gone under the cursor at this moment in time
		-- also prevent surround when cam dist too far
		if under then
			surroundCancelled = Cam.relDist > 2500
			if not surroundCancelled then
				local ux, uy, uz = spGetUnitPosition(under)
				local gy = spGetGroundHeight(ux,uz)
				if uy > gy + 30 then
					surroundCancelled = true
				end
			end 
			if surroundCancelled then
				if movedPlacement[1] == -1 then
					return true
				end
			end
		end
		if not (needTerra or movedPlacement[1]==-1) and not surroundCancelled then 
			return
		end
	end
	if button == 1 and pointX then
		--rmbMouse={mx,my}
		--spSetActiveCommand(-1)
		--Echo("MP:Active Command Removed")
		-- if g.preGame and not shift then
		--     local IQ = widgetHandler:FindWidget("Initial Queue ZK")
		--     if IQ and mustTerraform then 
		--         -- hijacking CommandNotify of widget Initial Queue ZK, for it to take into consideration pre Game placement on unbuildable terrain
		--         IQ:CommandNotify(-PID,{pointX,pointY,pointZ,p.facing,true},{alt=alt,ctrl=ctrl,shift=shift,meta=meta})
		--     end
		--     return true
		-- end
		if (shift) and not surround and EraseOverlap() then
			return true
		end
		if meta and shift and widgets.command_insert then
			widgets.command_insert._CommandNotify = widgets.command_insert.CommandNotify
			widgets.command_insert.CommandNotify = dumfunc
		elseif meta and not shift then
			forceResetAcom = true
		end

		--cons = getcons()
		--if not shift and PID==mexDefID then spSetActiveCommand(-1) end -- this prevent MexPlacement Handler to trigger
		if --[[not meta and--]] mustTerraform or movedPlacement[1]>-1 or offmap or myPlatforms.x then-- temporary fix for placement above existing structure, not ideal
			-- override the engine behaviour
			-- local x = myPlatforms.x or movedPlacement[1]>-1 and movedPlacement[1] or pointX
			-- local z = myPlatforms.z or movedPlacement[1]>-1 and movedPlacement[2] or pointZ
			local x,z = pointX, pointZ
			-- Echo("movedPlacement[1] is ", movedPlacement[1])
			local canBuild = spTestBuildOrder(PID, x, 0, z, p.facing) ~= 0
			if canBuild and not myPlatforms.x and (groundModule.elevated or groundModule.subelevated) then
				-- Echo('here 3')
				myPlatforms:New(p.sizeX,x,z,PID)
			end
			ignoreFirst = canBuild
			-- ignoreFirst=not offmap and not mustTerraform
			
			-- local order = movedPlacement[1]>-1 and {movedPlacement[1],movedPlacement[3]} or {pointX,pointZ}


			local order = {x,z, pid = PID}
			WG.commandLot.shift = shift
			workOnRelease = order
			if not shift or surroundCancelled then
				return true
			end


			---
			table.insert(WG.commandLot, order)
			ordered=true
			if mexDefID==PID then
				return true-- bypassing Mex Placement Handler widget
			end 
			if not shift and meta then
				--
				return true
			end
		elseif PID==geoDefID then
			local geoX,geoZ = CheckGeos(pointX,pointZ)
			if geoX then 
				ordered = true
				workOnRelease = {geoX, geoZ, pid = PID}
				return true
			end
		else
			local canBuild = spTestBuildOrder(PID, pointX, 0, pointZ, p.facing) ~= 0
			if canBuild and not myPlatforms.x and (groundModule.elevated or groundModule.subelevated) then
				-- Echo('here 4')
				myPlatforms:New(p.sizeX,pointX,pointZ,PID)
			end
			-- forcing command on wrong test build order that should allow building
			ordered = true
			if not canBuild and not mustTerraform then
				-- TODO: I don't find any workaround, the engine need to be fixed, units like halberd that report wrongly unbuildable
				-- on water when terrain is too steep undersea
			 -- correcting the placement X and Z that engine should have done for units that float like Hover made by Athena
			 -- or forcing the placement with  (CMD_INSERT?)
			elseif (canBuild and not p.floatOnWater and not p.underSea and pointY<=0.1 
					or not canBuild and mustTerraform and meta)
			then
				-- ignoreFirst=true
				widgetHandler:CommandNotify(-PID,{pointX,pointY,pointZ,p.facing},MakeOptions())
				-- table.insert(WG.commandLot, {pointX,pointZ})

				return true
			elseif meta and not shift then
				if g.preGame then
					ignoreFirst = true
					widgetHandler:CommandNotify(-PID, {pointX,pointY,pointZ,p.facing}, MakeOptions())
				else
					widget:CommandNotify(-PID, {pointX,pointY,pointZ,p.facing}, MakeOptions())
				end
				if g.preGame then
					spSetActiveCommand(0)
				end
				return true
			elseif canBuild and not mustTerraform then

				--[[if PID == mexDefID and not shift and WG.metalSpots then
					-- let mex_placement_handler do the job
					Echo('ok here')
				else--]]if widgets.drawing_placement and not shift then
					workOnRelease = {pointX,pointZ,pid = PID}

					-- widgetHandler:CommandNotify(-PID,{pointX,pointY,pointZ,p.facing},MakeOptions())

					return true
				else
					ignoreFirst = true
				end
				-- 
			end
		end
		-- if not hold and mustTerraform then return true,widget:Update(Spring.GetLastUpdateSeconds()) end

		return --[[true--]]
	end
end
FormatTime = function(n)
	local h = math.floor(n/3600)
	h = h>0 and h
	local m = math.floor( (n%3600) / 60 )
	m = (h or m>0) and m
	local s = ('%.3f'):format(n%60)
	return (h and h .. ':' or '') .. (m and m .. ':' or '') .. s
end
function widget:MouseRelease(mx,my,button)
		-- work around to have the shift working on very fast ordering (shift might come after the mouseclick)
		if pointX and PID and workOnRelease then
			table.insert(WG.commandLot, workOnRelease)

			workOnRelease = false

			if not (shift or WG.commandLot.shift) then
				TreatLot(WG.commandLot,PID)
				reset(false,false,true) 
			else
				 ordered=true
				 forceResetAcom = true
			end
			-- forceResetAcom = not (WG.commandLot.shift or shift) 
			-- -- if forceResetAcom then
			-- --     Echo('Force',FormatTime(Spring.GetGameSeconds()))
			-- -- end
			-- -- Echo('here',os.clock(),'shift?',select(4,spGetModKeyState()),'pid?',PID,spGetActiveCommand())
			-- ordered=true

			-- if not select(4,spGetModKeyState()) then
			--     spSetActiveCommand(0)
			-- end
		end
		workOnRelease = false
		return -1
	-- Echo('release','shift?',select(4,spGetModKeyState()))
	-- if CI_Disabled then
	--     -- CI_Disabled=false
	--     -- widgetHandler:UpdateWidgetCallIn("CommandNotify", widgets.command_insert)
	-- end

end
--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
do
	local color = {
		fade_blue = {0, 0.7,  0.7, 0.6},
		strong_blue = {0, 0.9, 0.9, 0.9},
		white = {1,1,1,1},
		purple = {1,0,1,1},
		ocre = {1,1,0.3,1},
		tainted_blue = {0.5,1,1,1},
		teal = {0.3,0.7,1,1},
		custColor = {1,1,0.4,1},
	}
	-- Points Debugging
	local ToScreen = Spring.WorldToScreenCoords
	local glText=gl.Text

	local GL_LINE_STRIP     = GL.LINE_STRIP
	local GL_LINES          = GL.LINES
	local glVertex          = gl.Vertex
	local glLineWidth       = gl.LineWidth
	local glColor           = gl.Color
	local glBeginEnd        = gl.BeginEnd

	local GetTextWidth        = fontHandler.GetTextWidth
	local UseFont             = fontHandler.UseFont
	-- local TextDraw            = fontHandler.Draw
	local TextDrawCentered    = fontHandler.DrawCentered
	-- local TextDrawRight       = fontHandler.DrawRight
	local glRect              = gl.Rect
	local font            = "LuaUI/Fonts/FreeSansBold_14"
	local fontWOutline    = "LuaUI/Fonts/FreeSansBoldWOutline_14"     -- White outline for font (special font set)
	local formatnum           = function(n) return tostring(n):sub(1,3) end
	local function DrawRectangle(x,y,z,w,h)
		glVertex(x + w, y, z + h)
		glVertex(x + w, y, z - h)
		glVertex(x - w, y, z - h)
		glVertex(x - w, y, z + h)
		glVertex(x + w, y, z + h)
	end
	local function DrawVerticals(x,y,z,w,h,ey)
		glVertex(x + w, y, z + h)
		glVertex(x + w, ey, z + h)

		glVertex(x + w, y, z - h)
		glVertex(x + w, ey, z - h)

		glVertex(x - w, y, z - h)
		glVertex(x - w, ey, z - h)

		glVertex(x - w, y, z + h)
		glVertex(x - w, ey, z + h)

		glVertex(x + w, y, z + h)
		glVertex(x + w, ey, z + h)
	end
	local function Vertices(t)
		for i,v in ipairs(t) do
			glVertex(unpack(v))
		end
	end
	
	function widget:DrawScreen()
		if PID and pointX then
			if PID==windDefID then
				local minW,incW,maxW,avgW,mult = GetWindAt(pointY==0.1 and spGetGroundHeight(pointX,pointZ) or pointY)
				local c
				local mx,my = ToScreen(pointX,pointY,pointZ-24)
				local str
				if minW then
					str =  (minW and ('%.1f'):format(minW)..' < ' or '')..('%.2f'):format(incW)..(avgW and ' ( avg:'..('%.1f'):format(avgW)..')' or '')
					c = color.custColor
					local malus = 1-minW/mult -- how much left from a maxed min
					local bonus = (incW/maxW)*0.4 -- ratio income vs max income, 0.4 beeing the max possible bonus
					red = 0.5+malus -- to make strong yellow we need red at 1
					green = 1-malus+bonus
					c[1] = red
					c[2] = green
					c[4] = 0.6
					-- color[3] = red*0.5 -- need to compensate the reddish colors for visibility
				else 
					c = color.teal
					str = ('%.2f'):format(incW)

				end
				glColor(c)
				UseFont(font)
				TextDrawCentered(str, mx, my+40)
				-- glText(str, mx-(min and 30 or 5), my+10, 11)    -- not enough visible without outline
				glColor(color.white)
			end
			local toNoTerra = g.timeOutNoTerra
			if toNoTerra > 0 then
				if os.clock() < toNoTerra then
					glColor(color.white)
					UseFont(font)
					local mx,my = ToScreen(pointX, pointY, pointZ-12)
					TextDrawCentered("This Map doesn't allow Terraformation !", mx, my+20)
				else
					toNoTerra = 0
				end
			end
		end
		-- if true then return end
		for i,p in ipairs(Points) do
				 
			local mx,my = ToScreen(unpack(p))                   
			--glColor(waterColor)
			glText(p.txt or i, mx-5, my, 10)                   
			--glPointSize(10.0)
			--glBeginEnd(GL.POINTS, pointfunc,x,y,z)
		end
		if pointX and Debug.PH() then
			-- local mx,my = ToScreen(pointX, pointY, pointZ)    
			local mx,my = spGetMouseState() 
			local str = 'ph:'..formatnum(placementHeight)
					  ..', lvl:'..formatnum(level)
					  ..', h:'..formatnum(groundModule.height)
					  ..'/'..formatnum(groundModule.origHeight)
			glText(str, mx+30, my-27, 10)
		end
	end
	local glDrawGroundCircle = gl.DrawGroundCircle
	local CalcBallisticCircle 		= VFS.Include("LuaUI/Utilities/engine_range_circles.lua")
	local presetTable = setmetatable(
		{},
		{
			__index = function(self, num) 
				local ret = {}
				for i = 1, num do
					ret[i] = {}
				end
				rawset(self, num, ret)
				return ret
			end
		}
	)
	local function MakeVertices(t)
		local len = #t
		local verts = presetTable[len]
		for i = 1, len do
			verts[i].v = t[i]
		end
		return verts
	end

	function widget:DrawWorld()
		-- Echo('DW run',math.round(os.clock()), 'PID',PID,'working',WG.DrawTerra and WG.DrawTerra.working)
		if not PID then
			return
		end
		if pointX and PID then
			local conf = weapRanges[PID]
			if conf then
				if elevRangeDraw.update then
					if elevRangeDraw.defID ~= PID then
						-- if elevRangeDraw.list then
						-- 	gl.DeleteList(elevRangeDraw.list)
						-- 	elevRangeDraw.list = nil
						-- end
						elevRangeDraw.defID = PID
						local index = 1

						-- elevRangeDraw.wNum = conf['weaponNum' .. index]
						elevRangeDraw.wDef = conf['weaponDef' .. index]
						elevRangeDraw.radius = conf[index]
						elevRangeDraw.offY = conf['offY' .. index]
						local wDef = elevRangeDraw.wDef
						-- Echo("wType, modHeight", wDef.type, wDef.heightMod)
						-- Echo('Defined aimy for ' .. UnitDefs[PID].humanName .. ' at ' ..elevRangeDraw.offY )
						remake = true
					end
					local x, y, z = unpack(elevRangeDraw)

					if pointX ~= x or pointY ~= y or pointZ ~= z then
						remake = true
						elevRangeDraw[1], elevRangeDraw[2], elevRangeDraw[3] = pointX, pointY, pointZ
					end



					if remake then
						local coords
						if WANT_ALL_RANGES then
							-- more expensive in every way even with one single range to do and could barely be useful when placing a strider
							coords = WG.CalcBallisticCircleOfModel(pointX, pointY, pointZ, PID)
							elevRangeDraw.verts = coords
						else
							-- pre work for weapon #1 is already done
							coords = (WG.CalcBallisticCircle or CalcBallisticCircle)(pointX, pointY + elevRangeDraw.offY, pointZ, elevRangeDraw.radius, elevRangeDraw.wDef)
							elevRangeDraw.verts = MakeVertices(coords)
						end
						-- Echo("coords is ", coords)
					end
					elevRangeDraw.update = false
				end
				glLineWidth(1.3)
				glColor(elevRangeDraw.color)
				-- gl.PolygonMode(GL.FRONT, GL.LINE)
				-- Echo(" is ", unpack(elevRangeDraw.verts[1].v))
				if WANT_ALL_RANGES then
					for i, v in ipairs(elevRangeDraw.verts) do
						glBeginEnd(GL.LINE_LOOP, Vertices, v)
					end
				else
					gl.Shape(GL.LINE_LOOP, elevRangeDraw.verts)
				end
				
				glColor(1,1,1,1)
				glLineWidth(1)
				-- gl.PolygonMode(GL.FRONT, GL.FILL)
			end


			local drawingP = WG.drawingPlacement
			local DrawTerra = WG.DrawTerra
			if drawingP then
				if DrawTerra and DrawTerra.working and not DrawTerra.finish--[[ or special--]] then
					-- widgetHandler:RemoveWidgetCallIn("DrawWorld", self)
					local firstP = drawingP[1]
					-- Echo('=>',drawingTerra.finish)
					if firstP then
						if (pointX~=firstP[1] or pointZ~=firstP[2]) then
							pointX, pointZ = firstP[1],firstP[2]
							CheckTerra()
							if needTerra then
								TransferDrawData(needTerra)
							end
						end
					end
					if not needTerra then
						DrawTerra.finish=true
					end
				end
				return
			elseif DrawTerra and DrawTerra.working then
				return
			end
			if opt.findPlatform and round(placementHeight)~=0 and not myPlatforms.x then
				local camHeight = Cam.relDist
				-- if camHeight>1750 then

				-- Echo("camHeight is ", camHeight)
				-- number in square to look around the cursor pos
					glColor(1,1,1,0.3)
					local radius = round(camHeight/1000) * 3
					glDrawGroundCircle(pointX, pointY, pointZ, radius*8, 40)
					glColor(1,1,1,1)
				-- end
			end

			local bx,by,bz,bw,bh,float = pointX,pointY,pointZ,p.sizeX,p.sizeZ,water and not p.underSea --,not(snapFloat and water)
			if movedPlacement[1]>-1 then
				bx, bz = movedPlacement[1], movedPlacement[3]
			end
			local gy = spGetGroundHeight(bx,bz)
			if p.floatOnWater and gy < 0 and placementHeight <= 0 then gy = 0 end
			--glColor(0,1,0,0.4)
			glLineWidth(1.0)

			--// draw the lines

			if drawWater then
				
				if pointY == 0.1 or snapFloat and level <= 0.1 then

					glColor(color.tainted_blue)  
					--glColor(waterColor)
				else 
					glColor(color.strong_blue)
				end
			end
			glLineWidth(snapTime and 2.5 or 2)
			glColor(pointY == 0.1 and color.strong_blue or color.fade_blue)
			glBeginEnd(GL_LINE_STRIP, DrawRectangle, bx,by,bz,bw,bh)


			glLineWidth(1.0)
			if gy>0 then
				glColor(color.ocre)
			end
			glBeginEnd(GL_LINE_STRIP, DrawRectangle, bx,by,bz,bw,bh)
			glBeginEnd(GL.LINES, DrawVerticals, bx,gy,bz,bw,bh,by)
			glBeginEnd(GL_LINE_STRIP, DrawRectangle, bx,gy,bz,bw,bh)
			glColor(1, 1, 1, 1)
		end
	end
end


function PBHCallin(self) -- unused homemade callin
	Echo("TRIGGERED",self.value)
end
do -- work around to get origHeight on auto generated maps where Spring.GetGroundOrigHeight is broken
	local ProgressiveMapRegistration
	local screenFrame = 0
	local count = 0
	local time = 0
	local spGetTimer = Spring.GetTimer
	local spDiffTimers = Spring.DiffTimers
	function widget:DrawGenesis()
		if screenFrame == 2 then
			local timer = spGetTimer()
		-- just need an overtime callin for the first rounds to fill up our map of heights progressively
			if not (ProgressiveMapRegistration and ProgressiveMapRegistration()) then
				-- Echo('registering done')
				if count > 0 then
					time = time + spDiffTimers(spGetTimer(), timer)
					Echo('['..widget:GetInfo().name..']: sampled ' .. count .. ' map points in '.. time .. ' seconds')
				end
				widgetHandler:RemoveWidgetCallIn('DrawGenesis', widget)
				return
			end
			time = time + spDiffTimers(spGetTimer(), timer)
		end
	end
	function AfterInit(_,dt)
		if screenFrame>=1 then
			geos:Map()
			WG.geoMap = geos
			if not origHeightMap and Spring.GetGameRulesParam("mapgen_enabled") then
				local cyield = coroutine.yield
				ProgressiveMapRegistration = coroutine.wrap(function()
					origHeightMap = setmetatable({},{__index=function(self,k) local t = {} self[k] = t return t end})
					WG.origHeightMap = origHeightMap
					for x = 0, maxx, 8 do
						count = count + 1
						local oriX = origHeightMap[x]
						for z = 0, maxz, 8 do
							count = count + 1
							oriX[z] = spGetGroundHeight(x,z)
						end
						if x % 32 == 0 then
							cyield(true)
						end
					end
					cyield(false)
				end)
			end
			widget.DrawScreen = widget._DrawScreen
			widgets.command_insert = widgetHandler:FindWidget("CommandInsert") -- Get command insert widget
			widgets.fac_preorder = widgetHandler:FindWidget("Factory Preorder")
			widgetHandler:UpdateWidgetCallIn('Update', widget)
			widgetHandler:UpdateWidgetCallIn('MousePress', widget)
		end
		screenFrame = screenFrame + 1
	end
end
--------------------------------------------------------------------------------
-- Persistent Config
--------------------------------------------------------------------------------

function widget:GetConfigData() -- NOTE shutting down on player changed when resigning don't save the buildHeight even though this is triggered
	-- Echo('PBH GET CONFIG')
	local heightByName = {}
	for unitDefID, bHeight in pairs(buildHeight) do
		local name = UnitDefs[unitDefID] and UnitDefs[unitDefID].name
		if name then
			-- if name=='turretriot' then
			--     Echo('ShuttingDown turretriot,'..unitDefID..',bHeight is '..bHeight)
			-- end
			heightByName[name] = bHeight
		end
	end
	local ret = {}
	ret.buildHeight = heightByName
	if Debug.GetSetting then
		ret.Debug = Debug.GetSetting()
	end
	return ret
end
function widget:SetConfigData(data)
	-- Echo('SET CONFIG')
	local heightByName = data.buildHeight or {}
	local UnitDefNames = UnitDefNames
	for name, bHeight in pairs(heightByName) do
		local unitDefID = UnitDefNames[name] and UnitDefNames[name].id
		if unitDefID then
			buildHeight[unitDefID] = bHeight
		end
	end
	if data.Debug then
		Debug.saved = data.Debug
	end
end

function widget:GameFrame(f)

	if g.preGame then
		if f < 2 then 
			return
		end
		local End
		local preGameQueue = WG.preGameBuildQueue
		if not ( preGameQueue and preGameQueue[1]) then
			End = true
		elseif not preGameQueue.tasker then
			if f > 4 then -- InitialQueue finalize at frame #2 or #3, but we may get the tasker at start of frame 4 if our widget layer is lower
				End = true
			end
		else
			cons[1] = preGameQueue.tasker
			ProcessPreGameQueue(preGameQueue, preGameQueue.tasker)
			End = true
		end
		if End then
			g.preGame = false
			widgetHandler:RemoveWidgetCallIn('GameFrame',widget)
		end
	end
end
function widget:Initialize()
	-- Echo('PBH INITIALIZE')
	-- take spSetActiveCommand again from Spring, for debugging
	spSetActiveCommand = Spring.SetActiveCommand
	Cam = WG.Cam
	if not Cam then
		Echo(widget:GetInfo().name .. ' requires api_has_view_changed')
		widgetHandler:RemoveWidget(self)
		return
	end
	-- REAL_WATER_LEVEL = Spring.GetWaterPlaneLevel() -- TODO: implement some day

	-- TODO use Spring.GetGameRulesParam("mapgen_enabled") to know if we need to register the original map heights to save some mem
	if Spring.GetSpectatingState() then
		-- widgetHandler:RemoveWidget(self)
		-- return
		widgetHandler:RemoveWidgetCallIn('UnitCommand',widget)
	end
	if not g.preGame then
		widgetHandler:RemoveWidgetCallIn('GameFrame',widget)
	end


	widgets.building_starter    = widgetHandler:FindWidget('Building Starter')
	widgets.fix_autoguard       = widgetHandler:FindWidget('FixAutoGuard')
	widgets.guard_remove        = widgetHandler:FindWidget('Guard Remove')
	widgets.ctrl_morph          = widgetHandler:FindWidget('Hold Ctrl during placement to morph')
	widgets.mex_placement       = widgetHandler:FindWidget('Mex Placement Handler')
	widgets.drawing_placement   = widgetHandler:FindWidget('Draw Placement')
	widgets.command_insert      = widgetHandler:FindWidget("CommandInsert")
	

	-----------------
	if SPECIFIED_MEMORY then
		widget._Update = widget.Update
		widget.Update = function()
			-- wait the first update round to update the buildHeight content from the updated optionized table
			for defID in pairs(buildHeight) do
				if not heightsToRmbOverGames[defID] then
					buildHeight[defID] = nil
				end
			end
			widget.Update = widget._Update
			widget._Update = nil
		end
	end
	-----------------
	if WG.myPlatforms then
		for sx, t in pairs(WG.myPlatforms) do
			if type(sx) == 'number' then
				myPlatforms[sx] = t
			end
		end
	end
	WG.myPlatforms = myPlatforms
	-----------------


	groundModule:Init()
	spotsPos = WG.metalSpotsByPos
	WG.commandLot= WG.commandLot or {}
	for k,v in pairs(WG.commandLot) do WG.commandLot[k]=nil end

	-----------------
	origHeightMap = WG.origHeightMap
	if not WG.geos then -- first time widget initialized
		widget._DrawScreen = widget.DrawScreen
		widget.DrawScreen = widget.AfterInit -- after init will get called after all widgets got loaded
		widgetHandler:RemoveWidgetCallIn('Update', widget)
		widgetHandler:RemoveWidgetCallIn('MousePress', widget)
	end
	-----------------
	Debug = f.CreateDebug(Debug,widget,dbg_options_path)
	local PBHCallin = widget.PBHCallin
	if WG.HOOKS then
		WG.HOOKS:HookOption(self,'Draw Terra2','draw_s_contour',PBHCallin)
	end

	if WG.cacheHandler then
		local oriIsMexable = IsMexable
		local cacheHandler = WG.CacheHandler
		IsMexable = function(spot, ignoreEnemy) -- improve perf a lot
			return cacheHandler:GetCache().funcResults:Get(oriIsMexable, 2, spot, ignoreEnemy)
		end
		local oriIsOccupied = IsOccupied
		IsOccupied = function(...)
			return cacheHandler:GetCache().funcResults:Get(oriIsOccupied, 2, ...)
		end
	end

--[[    if Spring.GetSpectatingState() or Spring.IsReplay() or not Game.mapDamage then
		Spring.Echo("widget Persistent Build Height 2 disabled")
		widgetHandler:RemoveWidget()
	end--]]
--[[        spSendCommands("luaui disablewidget Mex Placement Handler")
	spSendCommands("luaui enablewidget Mex Placement Handler")--]]
--[[    if widgetHandler:FindWidget("CommandInsert") and widgetHandler:FindWidget("MultiInsert") then
		CI_back=true
		spSendCommands("luaui disablewidget CommandInsert")
	end
	if widgetHandler:FindWidget("CommandInsert") then
		CI_back=true
		spSendCommands("luaui disablewidget CommandInsert")
	end--]]
	ghosts = WG.ghosts
	WG.PBHisListening = self
	HotkeyChangeNotification()
end

local playerID = Spring.GetMyPlayerID()
function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
	end
end
function widget:Shutdown()
	if elevRangeDraw.list then
		gl.DeleteList(elevRangeDraw.list)
		elevRangeDraw.list = nil
	end
	WG.placementX, WG.placementZ = nil, nil
	WG.placementHeight = nil
	if oldSpringSetActiveCommand then
		Spring.SetActiveCommand = oldSpringSetActiveCommand
	end
	-- save platforms in case widget is reloaded
	--
	-- Echo('PBH SHUTDOWN')
	WG.PBHisListening = false
	-- WG.CheckTerra = nil
	-- WG.FindPlacementAround = nil
	-- for k,v in pairs(WG.commandLot) do WG.commandLot[k]=nil end
	-- if MPH then 
	--     spSendCommands("luaui disablewidget Mex Placement Handler")
	--     spSendCommands("luaui enablewidget Mex Placement Handler")
	-- end
	-- if CI_back then 
	--     spSendCommands("luaui enablewidget CommandInsert")
	-- end
	if WG.DrawTerra and WG.DrawTerra.ready then
		WG.DrawTerra.finish = true
	end
	movedPlacement[1]=-1
	if Debug.Shutdown then
		Debug.Shutdown()
	end

	if widgets.command_insert and widgets.command_insert._CommandNotify then
		widgets.command_insert.CommandNotify = widgets.command_insert._CommandNotify
		widgets.command_insert._CommandNotify = nil
	end

end
f.DebugWidget(widget)
