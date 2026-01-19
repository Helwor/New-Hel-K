-- new requirement : glAddons.lua in Include folder
-- features:
	-- so many
	-- cancel surrounding (override) when cam relDist > 2500
function widget:GetInfo()
	return {
		name      = "Draw Placement",
		desc      = "Place builds following cursor, respecting radius for eBuilds and much more",
		author    = "Helwor",
		version   = "v1",
		date      = "30th May, 2020",
		license   = "GNU GPL, v2 or later",
		layer     = -10001, -- before PBH
		enabled   = true,
		handler   = true,
	}
end
local requirements = {
	exists = {
		-- handle terraform build and much more
		[WIDGET_DIRNAME ..'persistent_build_heigth2.lua'] = {VFS.RAW},
		-- enhance option system
		[WIDGET_DIRNAME ..'gui_epicmenu.lua'] = {VFS.RAW},
	},
	value = {
		-- tracking game units and maintain their database
		['WG.UnitsIDCard and WG.UnitsIDCard.active'] = {'Requires api_unit_data.lua and running'},
		-- track view and visible units
		['WG.Visibles and WG.Cam'] = {'Requires api_view_changed.lua and api_visible_units.lua'},
		-- track specific units order for widgets
		['WG.commandTrackerActive'] = {'Requires API Command Tracker widget to be active'},
	}
}


local Echo = Spring.Echo
include("keysym.lua")
-- VFS.Include("LuaRules/Configs/customcmds.h.lua")


----
--CONFIG
----
local MAX_REACH = 500 -- set radius of unit scan around the cursor, to detect connections of grid, 500 for pylon, 150 for singu/fusion

local SEND_DELAY = 0.8
----- default value of options before user touch them
local opt = {
	showRail = false,


	-- dev options, need to be reverified, best settings is already set
	autoNeat = true,
	neatFarm = false,
	useExtra = true, -- use extra search around to choose between 2 best methods that return the same number of poses
	useReverse = true,
	tryEdges = false,
	------

	connectWithAllied = true, -- not fully implemented, always true
	update_rail_MM  = false,


	enableEraser = true, 
	uniformEraserSize = true,
	eraserMult = 2.5,
	eraseAnyCmd = false, 

	checkOnlyMex = false,
	cheapRail = false, -- Improve perf but doesn't get around blocking structure
	alwaysMex = true, -- cap mex nearby without connection mode -- not implemented with farm, might be expensive
	-- experimental
	mexToAreaMex = false, -- single mex click do area mex, not ideally implemented
	ctrlBehaviour = 'no_spacing', -- switch temporary to spacing 0 with ctrl held

	grabMexes = false, -- grab mexes around depending on cam height
	grabMexesMultRadius = 1,
	grabMexesCap = 500, -- maximum

	remote = false, -- remote connection
	magnetMex = false, -- abandoned (for now) feature
	remoteMultRadius = 2,
	remoteCap = 300, -- maximum

	disallowSurround = false, -- 



}
-----

local myTeamID = Spring.GetMyTeamID()
local myPlayerID = Spring.GetMyPlayerID()
--------------------------------------------------------------------------------
-- Speedups
--------------------------------------------------------------------------------

-- local Page 							= f.Page
-- local GetDirection 					= f.GetDirection
local s									= f.s
-- local GetDef 						= f.GetDef
local l									= f.l
-- local inTable						= f.inTable
local UniTraceScreenRay					= f.UniTraceScreenRay
local ClampMouseToMinimap				= f.ClampMouseToMinimap
local TestBuild                   		= f.TestBuild
local CheckCanSub 						= f.CheckCanSub
local PushOut							= f.PushOut
local getconTable						= f.getconTable
local GetDist 							= f.GetDist
local GetPosOrder 						= f.GetPosOrder
-- local roughequal 					= f.roughequal
-- local sbiggest 						= f.sbiggest
-- local contiguous 					= f.contiguous
-- local MergeRects 					= f.MergeRects
-- local minMaxCoord 					= f.minMaxCoord
-- local MapRect 						= f.MapRect
local IsOverlap							= f.IsOverlap
-- local StateToPos 					= f.StateToPos
local GetCons 							= f.GetCons
local GetCommandPos						= f.GetCommandPos
-- local IsEqual 						= f.IsEqual
local MultiInsert 						= f.MultiInsert
local getcons 							= f.getcons
local deepcopy 							= f.deepcopy
-- local bet 							= f.bet
local toMouse 							= f.toMouse
-- local togrid 						= f.pointToGrid
local GetCameraHeight					= f.GetCameraHeight
-- local newTable 						= f.newTable


local toValidPlacement 					= f.toValidPlacement

-- local Overlapping 					= f.Overlapping
-- local Overlappings 					= f.Overlappings

-- local Turn90 						= f.Turn90

-- local vunpack 						= f.vunpack
local CheckTime 						= f.CheckTime

-- local nround							= f.nround

--local ListCallins 					= f.ListCallins

local color = COLORS

local UnitDefs = UnitDefs

local Points = {} -- debugging
local Cam, NewView



local sp = {

	GetActiveCommand 		= Spring.GetActiveCommand,
	SetActiveCommand 		= Spring.SetActiveCommand,

	GetModKeyState			= Spring.GetModKeyState,
	GetUnitsInCylinder		= Spring.GetUnitsInCylinder,
	GetUnitsInRectangle		= Spring.GetUnitsInRectangle,
	GetUnitDefID	 		= Spring.GetUnitDefID,
	GetSelectedUnits 		= Spring.GetSelectedUnits,
	GetMyTeamID 			= Spring.GetMyTeamID,
	GetAllUnits 	 		= Spring.GetAllUnits,


	GetCommandQueue  		= Spring.GetCommandQueue,
	GiveOrderToUnit  		= Spring.GiveOrderToUnit,
	GiveOrderToUnitArray  	= Spring.GiveOrderToUnitArray,

	WarpMouse 		 		= Spring.WarpMouse,
	WorldToScreenCoords 	= Spring.WorldToScreenCoords,
	GetMouseState    		= Spring.GetMouseState,
	TraceScreenRay  	 	= Spring.TraceScreenRay,
	GetGroundHeight  		= Spring.GetGroundHeight,

	SendCommands			= Spring.SendCommands,

	ValidUnitID				= Spring.ValidUnitID,
	ValidFeatureID			= Spring.ValidFeatureID,
	GetUnitPosition 	    = Spring.GetUnitPosition,
	GetFeaturePosition		= Spring.GetFeaturePosition,


	GetBuildFacing			= Spring.GetBuildFacing,
	GetBuildSpacing			= Spring.GetBuildSpacing,
	SetBuildSpacing			= Spring.SetBuildSpacing,
	GetUnitBuildFacing		= Spring.GetUnitBuildFacing,

	GetCameraState			= Spring.GetCameraState,
	GetCameraPosition		= Spring.GetCameraPosition,
	SetCameraTarget			= Spring.SetCameraTarget,

	GetTimer				= Spring.GetTimer,
	DiffTimers 				= Spring.DiffTimers,

	Pos2BuildPos 			= Spring.Pos2BuildPos,
	ClosestBuildPos 		= Spring.ClosestBuildPos,

	FindUnitCmdDesc  		= Spring.FindUnitCmdDesc,
	GetMyTeamID     		= Spring.GetMyTeamID,
	GetUnitTeam 			= Spring.GetUnitTeam,
	SetMouseCursor 			= Spring.SetMouseCursor,
	GetUnitsInRectangle		= Spring.GetUnitsInRectangle,

	IsUnitAllied			= Spring.IsUnitAllied,
	GetCmdDescIndex			= Spring.GetCmdDescIndex,

	GetModKeyState			= Spring.GetModKeyState,
	IsAboveMiniMap			= Spring.IsAboveMiniMap,
	WorldToScreenCoords	= Spring.WorldToScreenCoords,

}

local IsOccupied
do	
	local spGetUnitsInRectangle = sp.GetUnitsInRectangle
	function IsOccupied(x,z)
		return spGetUnitsInRectangle(x,z,x,z)[1]
	end
end

local g = {
	noterra = not Game.mapDamage or (Game.modName or ''):lower():find('arena mod'),
	preGame = Spring.GetGameSeconds() < 1,
	cantMex = {},
	previMex = {},
	closeMex = {},
	visitedOnce = {},
	remoteRadius = false,
	magnetScreen = false,

}
local initialized = false
local useMinimap = false
local ToggleDraw



-- --
-- local oriSetActiveCommand = sp.SetActiveCommand
-- local tm, history = os.clock(), {}
-- function sp.SetActiveCommand(cmd)
-- 	local now = os.clock()
-- 	local spam = now - tm  < 0.1
-- 	if spam then
-- 		table.insert(history,now .. ' cmd: ' .. cmd)
-- 	else
-- 		if history[4] then
-- 			Echo('SetActiveCommand got spammed !', table.concat(history, '\n'))
-- 		end
-- 		history = {}
-- 	end
-- 	return oriSetActiveCommand(cmd)
-- end
-- ---

local function CalcGrabRadius()
	local r = math.min(opt.grabMexesCap, (Cam.relDist / 18) * opt.grabMexesMultRadius)
	g.grabRadius = r
	return r
end
local function CalcRemoteRadius()
	local r = math.min(opt.remoteCap, (Cam.relDist / 25) * opt.remoteMultRadius)
	local r2 = math.min(opt.remoteCap, 1000^0.5)
	g.remoteRadius = r
	g.magnetScreen = r2 -- abandoned feature
	return r, r2
end
local CalcEraserRadius
do
	local unisx, unisz = 32, 32
	CalcEraserRadius = function(p)
		local sx,sz = p.terraSizeX, p.terraSizeZ
		local viewHeight = Cam.relDist
		local factor = 1
		local rad = false
		if viewHeight > 2500 then
			local mult = opt.eraserMult
			if opt.uniformEraserSize then
				sx, sz = unisx, unisz
			end
			factor = 1 + ( (viewHeight * mult - 2500)/2500 )
			sx, sz = sx * factor, sz * factor
			-- radSq = ((sx + sz) /2)^2
			rad = (sx^2 + sz^2) ^0.5
		end
		g.erase_factor = factor
		g.erase_round = rad
		return rad, factor
	end
end
------ OPTIONS
local function GetPanel(path) -- Find out the option panel if it's visible
	for _,win in pairs(WG.Chili.Screen0.children) do
		if  type(win)     == 'table'
		and win.classname == "main_window_tall"
		and win.caption   == path
		then
			for panel in pairs(win.children) do
				if type(panel)=='table' and panel.name:match('scrollpanel') then
					return panel
				end
			end
		end
	end
end
options_path = 'Hel-K/' .. widget:GetInfo().name

options = {}

options.showrail = {
	name = 'Show Rail',
	type = 'bool',
	value = opt.showRail,
	OnChange = function(self)
		opt.showRail = self.value
	end,
}

options.toggledraw = {
	name = 'Toggle Draw',
	desc = 'Define Hotkey to be used when you want to toggle Draw Mode for the current build option.',
	type = 'button',
	hotkey = 'Shift+Alt+D',
	OnChange = function(self)
		ToggleDraw()
	end
}


------ Paint Farm

options.neatfarm = {
	name = 'Paint Farm: neat squares only',
	desc = 'use only one method to place neat squares or use all available methods to find placable builds asap',
	type = 'bool',
	value = opt.neatFarm,
	OnChange = function(self)
		opt.neatFarm = self.value
		options.useextra.hidden = opt.neatFarm
		options.autoneat.hidden = opt.neatFarm
		options.usereverse.hidden = opt.neatFarm
		options.tryedges.hidden = opt.neatFarm
		local panel = GetPanel(options_path)
		if panel then
			WG.crude.OpenPath(options_path)
			local newpanel = GetPanel(options_path)
			if newpanel then
				newpanel.scrollPosY = panel.scrollPosY
			end
		end

	end,
	category = 'paint',
	dev = true,
}
options.autoneat = {
	name = 'Paint Farm: Auto Neat',
	desc = 'Choose automatically wether to use neat farm or not',
	type = 'bool',
	value = opt.autoNeat,
	OnChange = function(self)
		opt.autoNeat = self.value
	end,
	category = 'paint',
	dev = true,
}

options.useextra = {
	name = 'Paint Farm: Use extra search',
	desc = 'Use extra search around to get the most desirable positions for our current poses',
	type = 'bool',
	value = opt.useExtra,
	OnChange = function(self)
		opt.useExtra = self.value
	end,
	category = 'paint',
	dev = true,
}
options.usereverse = {
	name = 'Paint Farm: Use reverse search',
	desc = 'Use a third method going reverse to get better results',
	type = 'bool',
	value = opt.useReverse,
	OnChange = function(self)
		opt.useReverse = self.value
	end,
	category = 'paint',
	dev = true,
}
options.tryedges = {
	name = 'Paint Farm: Try edges method',
	desc = 'Priviledgize pose location that touch the most edge points of posed builds',
	type = 'bool',
	value = opt.tryEdges,
	OnChange = function(self)
		opt.tryEdges = self.value
	end,
	category = 'paint',
	dev = true,
}
----------



options.late_shift = {
	name = 'Detect late shift',
	desc = ([[
		When pressing shift almost simultaneously with mouse press,
		if there is some lag, it may miss the shift first and detect a mouse press first
		then act as you were not starting to draw, this fixes it.
	]]):gsub('\t', ''),
	type = 'bool',
	value = opt.late_shift,
	OnChange = function(self)
		opt.late_shift = self.value
	end
}
options.enableEraser = {
	name = 'Build eraser (Shift+Right Click)',
	type = 'bool',
	desc = 'Use it like an eraser on any queued build',
	value = opt.enableEraser,
	OnChange = function(self)
		opt.enableEraser = self.value
	end,
	category = 'eraser',
	children = {'eraseAnyCmd', 'eraserMult'},

}
options.uniformEraserSize = {
	name = 'Uniform Eraser Size',
	type = 'bool',
	desc = "When eraser become a round brush (zoomed out), don't scale it by its placement build size",
	value = opt.enableEraser,
	OnChange = function(self)
		opt[self.key] = self.value
	end,
	category = 'eraser',
	children = {'eraseAnyCmd', 'eraserMult'},

}
options.eraseAnyCmd = {
	name = 'Eraser can erase any command',
	type = 'bool',
	value = opt.eraseAnyCmd,
	OnChange = function(self)
		opt.eraseAnyCmd = self.value
	end,
	category = 'eraser',
	parents = {'enableEraser'},
}
options.eraserMult = {
	name = 'Eraser Mult Radius',

	type = 'number', 
	value = opt.eraserMult,
	min = 1, max = 4, step = 0.1,
	update_on_the_fly = true,
	OnChange = function(self)
		opt[self.key] = self.value
		if initialized then
			SHOW_ERASER_RADIUS = os.clock()
		end
	end,
	category = 'eraser',
	parents = {'enableEraser'},
}
options.update_rail_MM = {
	type = 'bool',
	name = 'Update Rail by Mouse Move',
	desc = 'Choose either to update the rail by the MouseMove, more reactive visually,\n or by Update, allow finer rapid mouse movements',
	value = opt.update_rail_MM,
	OnChange = function(self)
		opt.update_rail_MM = self.value
	end,
}

options.mexToAreaMex = {
	name = 'Mex w/o Shift transform to AreaMex',
	type = 'bool',
	value = opt.mexToAreaMex,
	OnChange = function(self)
		opt[self.key] = self.value
	end,
}
options.checkOnlyMex = {
	name = 'Connect only to new mex',
	desc = 'Ignore other grid but mex, improve performance.',
	type = 'bool',
	value = opt.checkOnlyMex,
	OnChange = function(self)
		opt[self.key] = self.value
	end,
}
options.cheapRail = {
	name = 'Cheap rail',
	desc = 'Improve perf but doesn\'t fix rail unplaceable points.',
	type = 'bool',
	value = opt.cheapRail,
	OnChange = function(self)
		opt[self.key] = self.value
	end,
}

------ grab more mexes

options.grabMexes = {
	name = 'Grab Mex Around',
	desc = 'EXPERIMENTAL\nWhen using Mex build, catch more mex around in the same go (depends on Camera view distance).',
	type = 'bool',
	value = opt.grabMexes,
	OnChange = function(self)
		opt[self.key] = self.value
	end,
	category = 'grabMexes',
	children = {'grabMexesMultRadius', 'grabMexesCap'},
}
options.grabMexesCap = {
	name = 'Grab Mex Radius Cap',

	type = 'number', 
	value = opt.grabMexesCap,
	min = 300, max = 3000, step = 100,
	update_on_the_fly = true,
	OnChange = function(self)
		opt[self.key] = self.value
		if initialized then
			SHOW_GRAB_RADIUS = os.clock()
		end
	end,
	category = 'grabMexes',
	parents = {'grabMexes'},
}

options.grabMexesMultRadius = {
	name = 'Grab Mex Radius Mult',

	type = 'number', 
	value = opt.grabMexesMultRadius,
	min = 0, max = 2, step = 0.01,
	update_on_the_fly = true,
	OnChange = function(self)
		opt[self.key] = self.value
		if initialized then
			SHOW_GRAB_RADIUS = os.clock()
		end
	end,
	category = 'grabMexes',
	parents = {'grabMexes'},
}
---------------------------

------ Remote Connect

options.remote = {
	name = 'Remote Connection',
	desc = 'Extend rail to remote mexes and connect them.',
	type = 'bool',
	value = opt.remote,
	OnChange = function(self)
		opt[self.key] = self.value
	end,
	category = 'remote',
	children = {'remoteMultRadius', 'remoteCap'},
}
-- abandoned (for now) feature
-- options.magnetMex = { 
-- 	name = 'Mex magnet',
-- 	desc = 'EXPERIMENTAL\nWhen in connect mode, move cursor toward near mex'
-- 		..'\nUse same base radius as the remote radius', -- roughly
-- 	type = 'bool',
-- 	value = opt.magnetMex,
-- 	OnChange = function(self)
-- 		opt[self.key] = self.value
-- 	end,
-- 	category = 'remote',
-- 	children = {'remoteMultRadius', 'remoteCap'},
-- }

options.remoteMultRadius = {
	name = 'Remote Radius',

	type = 'number', 
	value = opt.remoteMultRadius,
	min = 1, max = 3, step = 0.1,
	update_on_the_fly = true,
	OnChange = function(self)
		opt[self.key] = self.value
		if initialized then
			SHOW_REMOTE_RADIUS = os.clock()
		end
	end,
	category = 'remote',
	parents = {'remote', 'magnetMex'},
}
options.remoteCap = {
	name = 'Remote Radius Cap',

	type = 'number', 
	value = opt.remoteCap,
	min = 100, max = 1000, step = 50,
	update_on_the_fly = true,
	OnChange = function(self)
		opt[self.key] = self.value
		if initialized then
			SHOW_REMOTE_RADIUS = os.clock()
		end
	end,
	category = 'remote',
	parents = {'remote', 'magnetMex'},
}
---------------------------




options.ctrlBehaviour = {
	name = 'Behaviour while holding Ctrl',
	type = 'radioButton',
	-- desc = 'Switch temporary to spacing 0 with ctrl held when you\'re set for connection mode',
	value = opt.ctrlBehaviour,
	items = {
		{key = 'engine', name = 'Engine behaviour'},
		{key = 'no_spacing', name = 'No Spacing'},
	},
	OnChange = function(self)
		opt[self.key] = self.value
	end,
}
options.alwaysMex = {
	name = 'always Mex',
	desc = 'Even when not in connect mode, add mex nearby',
	value = opt.alwaysMex,
	OnChange = function(self)
		opt[self.key] = self.value
	end,	
}

options.disallowSurround = {
	name = 'Disallow Surround',
	desc = 'While Drawing, don\'t let the engine place builds around a target, continue as usual',
	value = opt.disallowSurround,
	OnChange = function(self)
		opt[self.key] = self.value
	end,	
}


------------- DEBUG OPTIONS

local Debug = { -- default values, modifiable in options
	active = false, -- no debug, no other hotkey active without this
	global = true, -- global is for no key : 'Debug(str)'
	reload = true,

	paint = false,
	judge = false,
	connect = false,
	mexing = false,
	edges = false,
	paintMethods = false,
	ordering = false,
	grids = false,
}



-- local GetWidgetOption = WG.GetWidgetOption




local GetCloseMex



local max 		= math.max
local min		= math.min
local round 	= math.round
local abs 		= math.abs
local sqrt		= math.sqrt
local floor 	= math.floor
local ceil 		= math.ceil

local format 	= string.format
local clock 	= os.clock


-- local SM = widgetHandler:FindWidget('Selection Modkeys')
-- if SM then
-- 	SM_Enabled = SM.options.enable
-- end



local PBH, PBS, plate_placer

local EMPTY_TABLE = {}
--[[
local toggleHeight   = KEYSYMS.B
local heightIncrease = KEYSYMS.C
local heightDecrease = KEYSYMS.V
--]]


local spacingIncrease = KEYSYMS.Z
local spacingDecrease = KEYSYMS.X

---------------------------------
-- Epic Menu
---------------------------------


--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------

VFS.Include("LuaRules/Configs/customcmds.h.lua")



--test()
--------------------------------------------------------------------------------
-- Local Vars
--------------------------------------------------------------------------------

--local time
--local tick={}
--local coroute={}

local DP = {}
local pos = false

local eraser_color = { 0.6, 0.7, 0.5, 0.2}
eraser_color = {0.8, 0.2, 0.3, 0.2}
local mexDefID = UnitDefNames["staticmex"].id
local pylonDefID = UnitDefNames['energypylon'].id

local noDraw = {
	[UnitDefNames["staticcon"].id]=true,
	[UnitDefNames["staticstorage"].id]=true,
	[UnitDefNames["staticrearm"].id]=true
}


local E_SPEC = {
	[UnitDefNames["energysolar"].id] = true,
	[UnitDefNames["energywind"].id] = true,
	[UnitDefNames["energypylon"].id] = true,
	[UnitDefNames['energyfusion'].id]=true,
	[UnitDefNames['energysingu'].id]=true,


}
local E_RADIUS={
	[UnitDefNames['staticmex'].id]=49,
	[UnitDefNames['energysolar'].id]=99,
	[UnitDefNames['energywind'].id]=60,
	[UnitDefNames['energyfusion'].id]=150,
	[UnitDefNames['energysingu'].id]=150,
	[UnitDefNames['energypylon'].id]=499,
	--[UnitDefNames['energypylon'].id]=3877,
}

-- for paint farm
local Paint -- paint farm function

local farm_spread = false
local FARM_SPREAD = { -- how far in half-sizes from the cursor a placement can occur
					  -- 1 is default, if 1 then there will be no placement on cursor, but an attempt to put 4 placements with common corner at cursor (offsetted by oddx)
					  -- if >1 then there will be an attempt to put 1 at center + all around,
					  -- if nothing on the way, 2 will bring 9 placement, 4 will bring 25 and so on
	[UnitDefNames['spiderscout'].id]=3, 
	[UnitDefNames['energywind'].id]=2,
}
local farm_scale = false
local FARM_SCALE = { -- separation of build in farm per defID
	[UnitDefNames['energywind'].id]=1,

}
local MAX_SCALE = {
	[UnitDefNames['energywind'].id]=3,
	[UnitDefNames['energysolar'].id]=7,
}
--------
local factoryDefID = {}
for defID, def in pairs(UnitDefs) do
	local cp = def.customParams
	if cp.parent_of_plate then
		factoryDefID[defID] = true
	end
end
local plateDefID = {}
for defID, def in pairs(UnitDefs) do
	local cp = def.customParams
	if (cp.child_of_factory) then
		plateDefID[defID] = true
	end
end
local special = false


local VERIF_SHIFT = false
local UPDATE_RAIL = false
local overlapped = {}



local GetClosestAvailableMex

do

	function GetClosestAvailableMex(x,z, distRange, once)
		local spots = WG.metalSpots
		if not spots then
			return
		end
		local t
		local bestSpot
		local bestDist = math.huge
		for i = 1, #spots do
			local spot = spots[i]
			local dx, dz = x - spot.x, z - spot.z
			local dist = dx*dx + dz*dz
			if distRange then
				if dist < distRange then
					if not (once and g.visitedOnce[spot]) then
						if not g.cantMex[spot] then
							if not t then
								t = {}
							end
							t[#t + 1] = {spot.x, spot.y, spot.z, spot = spot, dist = dist}
						end
						if once then 
							g.visitedOnce[spot] = true
						end
					end
				end
			end
			if dist < bestDist and not g.cantMex[spot] then
				bestSpot = spot
				bestDist = dist
			end
		end
		return bestSpot, math.sqrt(bestDist), t
	end
end
local switchSM, SM_enable_opt






local forgetMex = {}
local spacing = false

local newmove



local CURSOR_ERASE_NAME, CURSOR_ERASE = 'map_erase','eraser'

local mx, my = false, false

--local places

--local blockIndexes -- not used anymore, time consuming

local rail = {n=0}
local specs = {
	n = 0,
	mexes = {},
	clear = function(self)
		for i = 1, #self do
			self[i] = nil
		end
		for k in pairs(self.mexes) do
			self.mexes[k] = nil
		end
		self.n = 0
	end,
}
local mexes = specs.mexes

local connectedTo={}
local allGrids = {}


local placed={}



local primRail={n=0}
local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ

-- local pushRail= false
-- local pushedRails={n=0}
-- local AVG = {n=0}


local Drawing = false

WG.drawEnabled = false


-- local rmbAct=false

dstatus ='none'
local waitReleaseShift=false


-- those are used with Backwarding and Warping functions which are currently not used anymore
	-- local backward = false
	-- local invisible = false
	-- local freeze = false
	-- local warpBack = false
	-- local oldCamPos = false
	-- local camPosChange = false
	-- local camGoal = false
	-- local panning = false
	-- local hold = false
	-- local washold = false
	local mousePos = {}
	-- local hold = false
--
local p = {}
local prev = {
	lasP_To_Cur=0,
	llasP_To_Cur=0,
	dist_drawn = 0,
	press_time = os.clock(),
	pos = false,
	pid = false,
	mexDist = 0,
	x = false,
	y = false,
	mx = false,
	my = false,
	firstmx = false,
	firstmy = false,
}



local PID = false



local leftClick = false
local rightClick = false
local shift = false
local meta = false


local cons



local pointX = false
local pointY = false
local pointZ = false


local function getclosest(from,tbl)
	local closest,changed,bestDist=1
	local same={}
	local tbl_n = #tbl
	for i=1,tbl_n do
		local t=tbl[i]
		local dist = (from[1]-t[1])^2+(from[2]-t[2])^2
		if not bestDist then 
			bestDist=dist
		elseif bestDist==dist then
			same[i]=dist
		elseif dist<bestDist then
			bestDist=dist closest=i changed=true
		end

	end
	for i,dist in pairs(same) do
		if bestDist~=dist then same[i]=nil end
	end
	return changed,tbl[closest],closest,next(same) and same
end



local function ReorderClosest(total,first_i,last_i,con, startpoint)
	local startpoint=startpoint or total[first_i-1]
	if not startpoint then
		if not con then
			startpoint=total[first_i]
		else
			local x,_,z = Spring.GetUnitPosition(con)
			startpoint={x,z}
		end
	end
	local veryfirst = startpoint
	-- local last_startpoint
	local t,i = {},0
	for a=first_i,last_i do
		i=i+1
		-- Echo('add one item at ',a)
		t[i]=total[a]
	end
	for a=first_i,last_i do
		local _,_,i,same = getclosest(startpoint,t)
		if same and veryfirst~=startpoint then
			_,_,i = getclosest(veryfirst,t)
		end
		-- Echo("closest =>",i)
		-- startpoint=table.remove(t,i)
		-- total[a]=startpoint
		total[a] = table.remove(t,i)
	end
end
local IsMexable
do
	local spIsUnitAllied = Spring.IsUnitAllied
	local spGetUnitHealth = Spring.GetUnitHealth
	function IsMexable(spot, ignoreEnemy)
		local mexID = IsOccupied(spot.x,spot.z)
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

------------------ geos object

local geos = {
	map = {},
	defID = UnitDefNames["energygeo"].id,
	cant = {},
}
function geos:Get()
	for i, fID in ipairs(Spring.GetAllFeatures()) do
		if FeatureDefs[Spring.GetFeatureDefID(fID)].geoThermal then
			local fx, fy, fz = Spring.GetFeaturePosition(fID)
			fx,fz = (floor(fx/16)+0.5) * 16,(floor(fz/16)+0.5) * 16
			-- Points[#Points+1]={fx,fy,fz}
			local thisgeo = {x = fx, z = fz}
			self[#self+1] = thisgeo
			local map = self.map
			for x = fx - 32, fx+ 32, 16 do
				if not map[x] then map[x]={} end
				for z = fz - 32, fz + 32, 16 do
					map[x][z] = thisgeo
				end
			end
		end
	end
end
function geos:GetClosest(x,z,dist)
	if not dist then dist=math.huge end
	local maxDist = dist
	local spot
	for i,thisspot in ipairs(self) do
		local thisdist = ((thisspot.x-x)^2+(thisspot.z-z)^2)^0.5
		if thisdist<dist then spot,dist=thisspot,thisdist end
	end
	return spot,dist
end

function geos:BarOccupied()
	for i,spot in ipairs(self) do
		local geoX,geoZ = spot.x,spot.z
		local cantPlace,blockingStruct= TestBuild(geoX,geoZ,p,true,placed)
		if blockingStruct then
			for i,b in ipairs(blockingStruct) do
				if b.defID==self.defID then
					geos.cant[spot]=true
					break
				end
			end
		end
	end
end
function geos:Update(newx,newz)
	local geoX,_,geoZ = sp.ClosestBuildPos(0,PID, newx, 0, newz, 600 ,0 ,0)
	local spot
	local ClosestBuildPosFailed = geoX==-1
	if geoX==-1 then -- ClosestBuildPos can return -1 if it need terraformation first
		spot = self:GetClosest(newx,newz,500)
		if not spot then return end
		geoX,geoZ = spot.x,spot.z
	else 
		spot = self.map[geoX] and self.map[geoX][geoZ]
	end
	if not spot then return end
	if self.cant[spot] then return end
	self.cant[spot]=true
	if ClosestBuildPosFailed then
		-- if WG.movedPlacement[1] then
		-- 	geoX,_,geoZ = unpack(WG.movedPlacement)
		-- Echo("WG.movedPlacement[1] is ", WG.movedPlacement[1])
		-- else
		-- 	return
		-- end
		if WG.FindPlacementAround then
			WG.FindPlacementAround(geoX,geoZ)
			-- local needterra,_,blockingStruct = WG.CheckTerra(geoX,geoZ)
			if WG.movedPlacement[1]>-1 then
				geoX,_,geoZ = unpack(WG.movedPlacement)
			else
				return
			end
		else 
			-- local cantPlace = TestBuild(geoX,geoZ,p,true,placed,overlapped)
			-- if cantPlace then return end
			return
		end
	end
	return geoX,geoZ
end

----------------------





local SendCommand
do
	local TABLE_BUILD = {0, 0, CMD.OPT_SHIFT, 0, 0, 0, 0}
	local GiveOrder,			GetGround,			GetOrders,			HasCommand,		 		GetDelta
	 = sp.GiveOrderToUnit, sp.GetGroundHeight, sp.GetCommandQueue, sp.FindUnitCmdDesc, Spring.GetLastUpdateSeconds

	SendCommand =  function(PID, mods)
		--local cons = sp.GetSelectedUnits()
		if not g.preGame and cons.n == 0 then	return end
		local nspecs = #specs
		if nspecs == 0 then return end

		local alt, ctrl, meta, shift = alt, ctrl, meta, shift
		if mods then
			alt, ctrl, meta, shift = unpack(mods)
		end
		shift = true -- force it anyway?

		-- if global build command is active, check if it wants to handle the orders before giving units any commands.

		-- Didnt touch GlobalBuildCommand...won't probably work like that(Helwor)
		if nspecs == 0 then
			return
		end
		-- putting every placements in one go, adding mexes if needed
		local facing = p.facing
		local total, n = {}, 0
		for i = 1,nspecs do
			local spec = specs[i]
			spec.pid = PID
			n = n + 1; total[n] = spec
			local nspec = n
			if mexes[i] then
				local inmexes = mexes[i]
				for i = 1, #inmexes do -- it can happen we have to put several mexes after one single building placement, (when placing pylon mostly)
					local inmex = inmexes[i]
					inmex.mex = true
					n = n + 1
					total[n] = inmex
				end
				-- reorder mexes and the e Build to get closest of each others first
				ReorderClosest(total, nspec, n, i == 1 and cons[1]--[[,i>1 and specs[i-1]--]])
			end
		end
		if mexes[nspecs+1] then -- in case we don't have one more specs but one more group of mexes?
			-- Echo('we have last mexes without spec')
			local inmexes = mexes[nspecs+1]
			local nspec = n
			for i = 1, #inmexes do
				inmexes[i].mex = true
				n = n + 1; total[n] = inmexes[i]
			end
			ReorderClosest(total,nspec,n,cons[1])
		end
		local opts = f.MakeOptions(nil, true, mods)
		if dstatus == 'paint_farm' then
			local spread = FARM_SPREAD[PID]
			local toReorder = (not spread and 4) or (spread - spread%2 + 1)^2
			ReorderClosest(total, 1, nspecs > toReorder and toReorder or nspecs, cons[1])
		else

			if factoryDefID[PID] or plateDefID[PID] then
				if plate_placer and plate_placer.CommandNotify then
					for i = 1, n do
						local p = total[i]
						plate_placer:CommandNotify(-PID,  {p[1], GetGround(p[1],p[2]), p[2],1}, opts)
					end
				end
			end
		end
		if PBH then -- Let PersistentBuildHeight do the job
			if PID == mexDefID then
				local done
				for i,p in ipairs(total) do
					if PBH:CommandNotify(-mexDefID, {p[1], GetGround(p[1], p[2]), p[2], 1}, opts) then
						done = true
					end
				end
				if done then
					return
				end
			end
			WG.commandLot = WG.commandLot or {}
			local lot = WG.commandLot
			for k,v in ipairs(lot) do lot[k]=nil end
			for k,v in ipairs(total) do lot[k]=v end
			lot.shift = true
			conTable = PBH.TreatLot(lot, PID, true, true) -- let some special feature of PBH to handle the placement height if only one build
			return
		end
		if g.preGame then
			local IQ = widgetHandler:FindWidget("Initial Queue ZK")
			if IQ then 
				-- hijacking CommandNotify of widget Initial Queue ZK, for it to take into consideration pre Game placement on unbuildable terrain
				for i,b in ipairs(total) do
					IQ:CommandNotify(b.mex and -mexDefID or -PID,{b[1], GetGround(b[1], b[2]), b[2]}, opts)
				end
			end
			return
		end


		local time = os.clock()
		for id,con in pairs(conTable.cons) do
			con.canBuild = HasCommand(id,-PID)
		end

		if not (shift or meta) then
			conTable.inserted_time = false
			conTable.waitOrder = false
			for id,con in pairs(conTable.cons) do
				con.commands = {}
				con.queueSize = 0
			end
		elseif not conTable.inserted_time or conTable.inserted_time and time - conTable.inserted_time > SEND_DELAY then
			conTable.inserted_time = false
			conTable.waitOrder = false
			for id,con in pairs(conTable.cons) do
				local queue = GetOrders(id,-1)
				local commands = {}
				for i,order in ipairs(queue) do
					local posx,_,posz = GetCommandPos(order)
					commands[i] = not posx and EMPTY_TABLE or {posx,posz}
				end
				con.commands = commands
				con.queueSize = #queue
			end
		end
		conTable.multiInsert = false
		if shift and meta then 
			-- workaround to have a virtually updated command queue until it is actually updated
			local has2ndOrder, conRef
			-- has2ndOrder => don't insert before the first order if there is only one order to send (terraform included)
			-- hasSecondOrder = lot[2] and lot[2]~=lot[1] or lot[3] or false
			-- use cons[1] as reference for position for every cons
			conRef = cons[1]
			MultiInsert(total,conTable,true,has2ndOrder,conRef) 
		end
		-- local conTable =  MultiInsert(total)
		local codedOpt = {coded=CMD.OPT_ALT}
		local firstCon = true
		for i=1, #total do
			local x,z = unpack(total[i])
			for id,con in pairs(conTable.cons) do
				if con.canBuild then
					if (shift or meta) then
						local cmds = GetOrders(id, 2)
						noAct = not cmds[1] or not cmds[2] and (cmds[1].id==0 or cmds[1].id==5)
					else
						noAct = true
					end
					local buildPID = total[i].mex and -mexDefID or -PID
					if WG.GlobalBuildCommand and WG.GlobalBuildCommand.CommandNotifyRaiseAndBuild(cons, buildPID, x, GetGround(x,z), z, facing, s) then
					else
						local pos = (noAct or not meta) and -1 or (con.insPoses[i] or 0)
						TABLE_BUILD[1]=pos
						TABLE_BUILD[2]=buildPID
						TABLE_BUILD[4]=x
						TABLE_BUILD[5]=GetGround(x,z)
						TABLE_BUILD[6]=z
						TABLE_BUILD[7]=facing

						if not widgetHandler:CommandNotify(CMD.INSERT, TABLE_BUILD, codedOpt) then
							GiveOrder(id, CMD.INSERT, TABLE_BUILD, CMD.OPT_ALT)
							if firstCon and conTable.inserted_time then
								conTable.waitOrder = {CMD.INSERT,TABLE_BUILD}
							end 
							firstCon = false
						end
						-- GiveOrder(id,CMD.INSERT,{pos,buildPID,CMD.OPT_SHIFT, x, GetGround(x,z), z, facing},CMD.OPT_ALT)
					end
				end
			end
		end
		
	end
end

-- for k,v in pairs(widget) do
--     if tonumber(k) and tonumber(k) > 39000 then
--         Echo(k,v)
--     end
-- end




local EraseOverlap
do
	local mem = setmetatable({},{__mode='v'})
	-- local mem = {}
	local CMD_OPT_ALT = CMD.OPT_ALT
	local CMD_RAW_BUILD
	local CMD_RAW_MOVE
	local CMD_STOP = CMD.STOP
	do
		local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")
		CMD_RAW_BUILD = customCmds.RAW_BUILD
		CMD_RAW_MOVE = customCmds.RAW_MOVE
	end
	local function overlap(rad, x, z, sx, sz, ix, iz, isx, isz, checkSurround)
		if checkSurround then -- for surround to apply, the placement center must be inside the other placement
			return (x-ix)^2 < isx^2 and (z-iz)^2 < isz^2
		elseif rad then
			return (x-ix)^2 + (z-iz)^2 < (((rad^2)/2)^0.5 + isx)^2 + (((rad^2)/2)^0.5 + isz)^2 
			-- return (x-ix)^2 + (z-iz)^2 < (sx + isx)^2 + (sz + isz)^2 -- distance check
			-- (only work because the radius used is (sx^2 + sz^2)^0.5, else it requires the commented line above)
			-- would be same but more expensive to execute
			-- and (x-ix)^2 < (rad + isx)^2 and (z-iz)^2 < (rad + isz)^2 -- width and height check
		else
			return (x-ix)^2 < (sx+isx)^2 and (z-iz)^2 < (sz+isz)^2
		end
	end
	EraseOverlap = function(x,z, checkOnlyOverlap, checkSurround) 
		local GetQueue, GiveOrder, CMD_REMOVE, pcall = sp.GetCommandQueue, sp.GiveOrderToUnit,CMD.REMOVE, pcall
		if not checkOnlyOverlap then
			sp.SetMouseCursor(CURSOR_ERASE_NAME)
		end
		if not x then
			x,z = pos[1],pos[3]
			-- x = floor((x + 8 - p.oddX)/16)*16 + p.oddX
			-- z = floor((z + 8 - p.oddZ)/16)*16 + p.oddZ
		end
		local rad, factor = CalcEraserRadius(p)
		local sx, sz = p.terraSizeX, p.terraSizeZ
		local erased
		if g.preGame then
			local IQ = widgetHandler:FindWidget("Initial Queue ZK")
			if not IQ then return end
			local queue =  WG.preGameBuildQueue
			local j,n = 1, #queue
			local optShift = {shift=true}
			while j<=n do 
				local order = queue[j]
				local defid, ix, iy, iz, facing = unpack(order)
				local info = p:Measure(defid, facing)
				if overlap(rad, x, z, sx, sz, ix, iz, info.sizeX, info.sizeZ, checkSurround) then
					if checkOnlyOverlap then
						return true
					end
					IQ:CommandNotify(-defid, {ix,iy,iz}, optShift)

					local newn = #queue
					if newn ~= n then 
						n = newn
						erased = true
						j = j - 1
					end
				end
				j = j + 1
			end
			return erased
		end
		-- f.Page(Spring.GetUnitRulesParams(cons[1]))
		local plopped = {}
		local known_command = {}
		local temp_key = {}

		for i,id in ipairs(cons) do
			mem[id] = mem[id] or setmetatable({},{__mode='v'})
			-- mem[id] = mem[id] or {}
			local mem_done = mem[id]
			-- Echo("mem done is ", table.toline(mem_done))
			local queue = GetQueue(id,-1)
			if queue then
				local orderStop = false
				local queueLen = #queue

				local levelx, levelz, leveltag, loneleveltag, wantEraseLevel
				for j = 1, queueLen do 

					local command = queue[j]
					local tag = command.tag

					if mem_done[tag] then
						queueLen = queueLen - 1
					else
						local cmd = command.id
						-- Echo('current command',Spring.GetUnitCurrentCommand(id))
						if cmd < 0 or cmd == CMD_LEVEL then
							if cmd < 0 then
								local ix, _, iz, facing = unpack(command.params)
								local info = p:Measure(-cmd, facing)
								local levelOfBuild = levelx == ix and levelz == iz
								if not levelOfBuild then
									loneleveltag = leveltag
								end
								if overlap(rad, x, z, sx, sz, ix, iz, info.sizeX, info.sizeZ, checkSurround) then
									-- we verify the cons hasnt plopped the nanoframe yet
									if checkOnlyOverlap then
										return true
									end
									local authorized = true
									if j==1 then
										local ixiz = ix .. iz
										if plopped[ixiz] == nil then 
											plopped[ixiz] = IsOccupied(ix,iz) or false
										end
										authorized = plopped[ixiz] == false
									end
									if authorized then
										if levelOfBuild then 
											pcall(GiveOrder,id,CMD_REMOVE, leveltag, 0)
											mem_done[leveltag] = temp_key
											levelx = false
										end
										GiveOrder(id,CMD_REMOVE, tag, 0)
										-- Echo('remove ', tag, 'cmd', cmd)
										mem_done[tag] = temp_key
										lastRemove = cmd
										erased=true
									end
								end
							elseif cmd == CMD_LEVEL and not checkOnlyOverlap then
								-- we found
								levelx,levelz = command.params[1], command.params[3]
								leveltag = command.tag
								if opt.eraseAnyCmd and (x-levelx)^2 < (sx)^2 and (z-levelz)^2 < (sz)^2 then
									wantEraseLevel = leveltag
									-- Echo('SET',x,z,'=>',levelx,levelz,'next',queue[j+1])
								end
							end

						elseif opt.eraseAnyCmd and not checkOnlyOverlap then
							if leveltag then -- we are past any build cmd after the level cmd, meaning it's alone
								-- Echo('set lone')
								loneleveltag = leveltag
							end

							local ix, iy, iz = GetCommandPos(command)
							-- if ix then
							-- 	Echo("#"..command.tag,"cmd", cmd, math.modf(x)..' vs '..math.modf(ix),math.modf(z) .. ' vs ' .. math.modf(iz))
							-- else
							-- 	Echo('no ix',x,z)
							-- end
							if ix and (x-ix)^2 < (sx)^2 and (z-iz)^2 < (sz)^2 then
								local tag = command.tag
								if cmd ~= CMD_RAW_BUILD then -- it will be removed by itself if needed, plus, if we remove it before the attached build it will get reinserted just immediately
									GiveOrder(id,CMD_REMOVE, tag, 0)
									-- Echo('remove ', tag, 'cmd', command.id)
									erased=true
									lastRemove = cmd
								else
									-- mem_done[command.tag] = temp_key
								end
								mem_done[tag] = temp_key
								queueLen = queueLen - 1
							elseif cmd == CMD_STOP then
								-- queueLen = queueLen - 1
							end
						end
						if wantEraseLevel and (wantEraseLevel == loneleveltag or not queue[j+1]) then
							queueLen = queueLen - 1
							lastRemove = CMD_LEVEL
							pcall(GiveOrder,id,CMD_REMOVE, wantEraseLevel, 0)
							mem_done[wantEraseLevel] = temp_key
							loneleveltag = false
							wantEraseLevel = false
							erased=true
						end
					end
				end
				if queueLen == 0 and erased --[[and lastRemove == CMD_RAW_MOVE--]] then
					GiveOrder(id,CMD_STOP, 0, 0) -- fix unit keeping walking
				end
			end
		end
		return erased
	end
end

local function GetPlacements() -- for now, only placements from current cons are considered
	
	if not (  g.preGame and  WG.preGameBuildQueue and WG.preGameBuildQueue[1]	or cons[1] and sp.ValidUnitID(cons[1])  ) then
		return EMPTY_TABLE
	end
	-- local lookForEbuild = PID and E_RADIUS[PID] and dstatus ~= 'paint_farm' and sp.GetBuildSpacing() >= 7
	local lookForEbuild = special and not opt.checkOnlyMex

	local time = Spring.GetTimer()
	local T,length={},0
	local eBuilds,copy = {},{}
	local buffered = conTable and conTable.inserted_time and os.clock() - conTable.inserted_time < SEND_DELAY
	local queue = g.preGame and WG.preGameBuildQueue or buffered and conTable.cons[ cons[1] ].commands or sp.GetCommandQueue(cons[1],-1) or EMPTY_TABLE
	for i,order in ipairs(queue) do
		local pid,x,y,z,facing
		if buffered then
			if order.cmd and order.cmd < 0 then
				x, z = order[1], order[2]
				pid, facing = -order.cmd, order.facing
			end
		elseif g.preGame then
			pid, x, y, z, facing = unpack(order)
		elseif order.id < 0 then 
			pid, x, y, z, facing = -order.id, unpack(order.params)
		end
		if pid then
			local s = p:Measure(pid, facing)
			local sx,sz = s.sizeX,s.sizeZ

			local eradius = s.eradius
			if pid == mexDefID and GetCloseMex --[[and not g.preGame--]] then
				local spot = GetCloseMex(x,z)
				if spot then
					-- g.cantMex[spot]=not IsMexable(spot)
					g.cantMex[spot]=true
				end
			end
			length = length + 1
			local build = {x, z, sx, sz, eradius = eradius, defID = pid, facing = facing}
			T[length]=build
			if lookForEbuild and eradius and eradius < 500 then
				eBuilds[build] = true
				-- Points[#Points+1] = {x,sp.GetGroundHeight(x,z),z,txt = x..'-'..z}
			end
			--Echo("UnitDefs[-order.id].name is ", UnitDefs[-order.id].name,sx,sz)
		end
	end
	--connect placements together

	--if special then

		local function LinkTogether(eBuild,link) -- this might need a limitation, if hundreds of solars are ordered
			local x,z = eBuild[1],eBuild[2]
			local radius = eBuild.eradius
			local linked={}
			eBuild.grid=link
			eBuilds[eBuild]=nil
			
			for eBuild2 in pairs(eBuilds) do
				
				local ix,iz,iradius = eBuild2[1],eBuild2[2],eBuild2.eradius
				if (x-ix)^2 + (z-iz)^2 < (radius+iradius)^2 then

					linked[eBuild2]=true
					eBuild2.grid=link
				end
			end
			-- Echo('-- link '..link)
			for eBuild in pairs(linked) do

				LinkTogether(eBuild,link)
			end
			-- Echo('--')
			
		end

		local link=0
		local eBuild = next(eBuilds)
		while eBuild do
			link=link+1
			LinkTogether(eBuild,'p'..link)
			eBuild=next(eBuilds)
		end
	--end

	return T
end

function widget:CommandsChanged()
--[[		for _, myCmd in pairs(buildQueue) do
			local cmd = myCmd.id
			if cmd < 0 then -- check visibility for building jobs
				local x, y, z, h = myCmd.x, myCmd.y, myCmd.z, myCmd.h
				if spIsAABBInView(x-1,y-1,z-1,x+1,y+1,z+1) then
					buildList[#buildList+1] = myCmd
				end--]]
	cons=getcons()
	conTable = getconTable()
	--if cons[1] then placed = GetPlacements() end -- FOR TESTING ONLY
end

local NormalizeRail
local GoStraight

do
	local start,start_r,last_good_spec_n,locked
	local cur_dirx, cur_dirz
	local color = COLORS
	local function GetOrthoDir(x1,x2,z1,z2) -- fix name, it's 8 directional
		local rawx,rawz = ( x2 - x1 ), ( z2 - z1 )
		local abx, abz = abs(rawx), abs(rawz)
		local biggest =  max( abx, abz )
		local dirx, dirz = rawx / biggest, rawz / biggest
		local straight_dirx,straight_dirz = round(dirx), round(dirz)
		return straight_dirx,straight_dirz
	end
	GoStraight = function(on,x,z,railLen)
		start = rail[start_r] and rail[start_r].straight and rail[start_r] 
		if not on then
			if start then 
				g.unStraightened,locked = clock(),clock()
			end
			start, cur_dir, start_r = nil, nil,nil --[[Echo('return normal')--]]
			return false,locked,x,z,railLen
		else
			g.unStraightened = false
		end

		if not start then 
			start_r = rail.n
			start = rail[start_r]
			last_good_spec_n = specs.n
			if start then 
				start.straight=true
				start.color=color.blue
				locked=clock()
			end
		end
		if not start then --[[Echo('no start')--]] return false,locked,x,z,railLen end
		if not x then return end
		local rawx,rawz = ( x - start[1] ), ( z - start[3] )
		local abx, abz = abs(rawx), abs(rawz)
		local biggest =  max( abx, abz )
		local dirx, dirz = rawx / biggest, rawz / biggest
		local straight_dirx, straight_dirz = round(dirx), round(dirz)

		if cur_dirx ~= straight_dirx or cur_dirz ~= straight_dirz then
			cur_dirx, cur_dirz = straight_dirx, straight_dirz
			rail.processed = start_r
			for i = start_r+1, rail.n do
				rail[i]=nil
			end
			rail.n = start_r
			for i = last_good_spec_n+1,specs.n do
				specs[i]=nil
			end
			specs.n = last_good_spec_n

			NormalizeRail()
			if dstatus == 'paint_farm' then
				rail.processed=0
				specs:clear()
				Paint('reset') 
				TestBuild('reset memory')
				Paint()
			end
		end
		-- Echo("straight_dirx,straight_dirz is ", straight_dirx,straight_dirz)
		x,z = start[1] + straight_dirx * biggest, start[3] + straight_dirz * biggest
		-- local verx,verz = ( x - start[1] ), ( z - start[3] )
		-- Echo(rail.n,start[1],start[3],abx,abz,'correct',x,z,'verif',verx,verz)
		-- Points[1] = {x,sp.GetGroundHeight(x,z),z}
		-- Echo("start.straight is ", start.straight,start[1],start[3])
		return true,locked,x,z, rail.n
	end
end





local function reset(complete)
	--ControlFunc(1,"Def","break",DefineBlocks)
	if PID and select(4,sp.GetModKeyState()) and specs[1] then  waitReleaseShift=true end
	-- Echo('complete', complete, os.clock())
	-- if complete then
	-- 	Echo(debug.traceback())
	-- end

	--Echo(debug.getinfo(2).currentline)
	WG.drawEnabled=false
	if complete then
		if WG.old_showeco ~= nil then
			WG.showeco = WG.old_showeco
			WG.old_showeco = nil
		end
		WG.force_show_queue_grid = false
	end
	-- paint farm stuff
	Paint('reset') 
	farm_spread=false
	farm_scale = false
	REMOTE = false
	g.visitedOnce = {}
	TestBuild('reset memory')
	--
	-- TestBuild('reset invalid')
	--
	GoStraight(false)
	g.unStraightened = false
	--
	pointX = false
	--cons = {}
	Drawing = false
	specs:clear()
	WG.drawingPlacement = false


	rail = {n=0}
	linked = {}
	-- pushedRails = {n=0}
	-- AVG={n=0}
	primRail={n=0}
	geos.cant={}
	g.cantMex={}
	g.previMex = {}
	knownUnits={}
	prev.pos = false
	prev.lasP_To_Cur = 0
	prev.llasP_To_Cur = 0
	prev.start_mx, prev.start_my = false, false
	overlapped={}
	connectedTo={}
	allGrids = {}

	local metalSpots = WG.metalSpots or EMPTY_TABLE
	for i=1,#metalSpots do metalSpots[i].grids=nil end


	spacing = false
	special = false

	forgetMex = {}


	mousePos = {} -- belong to warping/backwarding


end
--[[function widget:TextCommand(command)
Echo("command is ", command)
end--]]

--[[local function CheckWarping() -- not used anymore
	-- if PID and dstatus == 'engaged' and shift or warpBack=="hold" then
	if PID and dstatus == 'engaged' and shift then


		local vsx, vsy = widgetHandler:GetViewSizes()
		local ud = UnitDefs[PID]
		local	_, pos = sp.TraceScreenRay(mx, my, true, false, false, not ud.floatOnWater)
		pos = pos or false
		if pos then
			local cam = sp.GetCameraState()


			local px,py,pz = cam.px, cam.py, cam.pz
			local diffpx = pos and px and px-pos[1]
			local diffpz = pos and pz and pz-pos[3]

		local maximum = mx<130 or mx>vsx-130 or my<160 or my>vsy-150		



			local camPos = {sp.GetCameraPosition()}

			camPosChange = oldCamPos and not roughequal({oldCamPos[1],oldCamPos[3]}, {camPos[1],camPos[3]}, 0)

			oldCamPos = {sp.GetCameraPosition()}	
			if maximum and not camPosChange then


				sp.SetCameraTarget(px - (diffpx)*0.85,py,pz-(diffpz)*1.3,0.50)
				warpBack = "ready"
				return true
			end

			-- if camPosChange and camGoal then
			if camPosChange then
			
				if prev.mx then
					mouseDir = GetDirection(prev.mx,prev.my,mx,my)
					--speed = math.sqrt(abs(mx-prev.mx)^2+abs(my-prev.my)^2)
					sp.WarpMouse(mx-(mx-vsx/2)/4,my-(my-vsy/2)/4)
					sp.SetActiveCommand(0)
				end
				--prev.mx=mx
				--prev.my=my

				--sp.SendCommands("Mouse1")
				return true
			elseif not camPosChange and freeze  then
				--defining a warpback position, either on last placement or on last mouse position, depending if the last placement is out of screen or not
				-- for now freeze got the recorded world pos of the mouse
				futX,futY = toMouse(specs[#specs])
				local maximum = futX<130 or futX>vsx-130 or futY<160 or futY>vsy-150		
				if not maximum then 
					freeze = specs[#specs] -- if placement is not out of screen, freeze become placement
				end
				warpBack = true
			end
		else
			Echo("hors limite")
			warpBack = false
			freeze=false
			
			return false
		end

	------------------------------------------------
		if warpBack=="ready" and not freeze then
			--recording mouse position in world pos as soon as we gonna pan view
			Echo("Getting freeze")

			local	_, pos = sp.TraceScreenRay(mx, my, true, false, false, not ud.floatOnWater)
			pos = pos or false
			if pos and not freeze then
				freeze = {pos[1],pos[2],pos[3]}
			end
			return true
		end



		if freeze and warpBack==true then

			sp.WarpMouse(toMouse(freeze)) 

			p:RecoverPID()
			if IsEqual(freeze,specs[#specs]) then
				sp.SendCommands("Mouse1") -- clicking mouse on placement for graphical coherance
			end
			warpBack = false
			freeze=false
			return true
		elseif not freeze  and warpBack==true then
			freeze=false
			warpBack = false

		end
		if camPosChange then -- waiting for view panning to be over
			return true
		end

	else

		warpBack = false
		freeze=false

		warpBack = false

	end

end--]]


--[[local function CheckBackward2() -- not used anymore
	backward = false
	local last = #specs-1>0 and #specs-1
	if last then

		local lastX, lastY = toMouse(specs[last]) -- getting a valid mouse position according to the new placement
		local curX,curY = toMouse(specs[#specs])

	--local oriDist = GetDist(mousePos[last][1],mousePos[last][2],mousePos[#specs][1],mousePos[#specs][2])
	--local newDist = GetDist(mousePos[last][1],mousePos[last][2],mx,my)
		local oriDist = GetDist(lastX,lastY,curX,curY)
		local newDist = GetDist(lastX,lastY,mx,my)
		local j = "current is last"
		for i=#specs-2, 1,-1 do -- if we are zoomed out and previous ones are close, we help the backwarding
			local iX,iY = toMouse(specs[i])

			--local prevOriDist = GetDist(mousePos[i][1],mousePos[i][2],mousePos[#specs][1],mousePos[#specs][2])
			local prevOriDist = GetDist(iX,iY,curX,curY)

			if prevOriDist<1500  then
			-- if prevOriDist<1500 and prevOriDist>oriDist  then
				j = "current is "..#specs-1-i.." before last"
				--local prevNewDist = GetDist(mousePos[i][1],mousePos[i][2],mx,my)
				local prevNewDist = GetDist(iX,iY,mx,my)
				if prevNewDist<=prevOriDist then 
					newDist = prevNewDist
					oriDist = prevOriDist
					backward = true
					break
				end
			else
				break
			end
		end
		--Echo(j, "backward=", backward)
		--Echo(speed)

		if (newDist<=oriDist ) and not invisible then 
		-- if (newDist<=oriDist or last2 and newDist2<oriDist2) and not invisible then 
		local last2 = #specs-2>0 and #specs-2
			if special and last2 then
				local oriDist2 = GetDist(mousePos[last2][1],mousePos[last2][2],mousePos[#specs][1],mousePos[#specs][2])
				local newDist2 = GetDist(mousePos[last2][1],mousePos[last2][2],mx,my)
				backward = newDist2<oriDist2
			else
				backward=true
			end
		
			backward = true
			--Echo(" backward")
			--Echo("--")
		end


		if backward and (newDist<oriDist*2/3) then
		-- if backward and (newDist<oriDist*2/3) or (last2 and newDist2<oriDist2) then
			--Echo("oriDist<1500 is ", oriDist<1500)
			if mexes[#specs] then
				
				local num = inTable(forgetMex, mexes[#specs])
				forgetMex[num]=nil
				mexes[#specs]=nil
			end

			specs[#specs]=nil




			--widgetHandler:UpdateWidgetCallIn("DrawWorld", self)

			--- little trick to place correctly placement grid from engine
			local curMouse = {mx,my}

			local mX, mY = toMouse(specs[#specs]) -- getting a valid mouse position according to the new placement
			sp.WarpMouse(mX,mY)

			sp.SendCommands("Mouse1")
			local impede = false
			if #specs>3 then-- in case we're crossing another placement we have to fully jump or we will get stuck
				for i=1, #specs-1 do
						
					impede=	pointX>specs[i][1]-p.footX*16 and pointX<=specs[i][1]+p.footX*16 and
							pointZ>specs[i][2]-p.footZ*16 and pointZ<=specs[i][2]+p.footZ*16
					if impede then

						break
					end
				end
			end
			if impede then
			-- if impede  or oriDist<1500 then
				--Echo("total warp")
				--sp.WarpMouse(unpack(mousePos[#specs]))
				sp.WarpMouse(mX,mY)
			else
				--local midX = curMouse[1]-(curMouse[1]-mousePos[#specs][1])/3
				--local midY = curMouse[2]-(curMouse[2]-mousePos[#specs][2])/3

				local midX = curMouse[1]-(curMouse[1]-mX)/3
				local midY = curMouse[2]-(curMouse[2]-mY)/3
				--Echo("little warp")
				sp.WarpMouse(midX,midY)
			end

			--sp.SetActiveCommand(activeCom) --renewing placement starting for graphical coherence

			--------
		end
		if backward then
			return true
		end
	end
	return false
end
--]]
local function CheckBackward() -- not used and older
	local specsLen = #specs
	backward = false
	local last = specsLen>1 and specs[specsLen-1]
	if last then
		local toScreen,GetGround = sp.WorldToScreenCoords,sp.GetGroundHeight

		local current = specs[specsLen]
		local toScreen = sp.WorldToScreenCoords
		local lastX, lastY = toScreen(last[1],last[2],last[3]) -- getting a valid mouse position according to the new placement
		local curX,curY = toScreen(current[1],current[2],current[3])

	--local oriDist = GetDist(mousePos[last][1],mousePos[last][2],mousePos[#specs][1],mousePos[#specs][2])
	--local newDist = GetDist(mousePos[last][1],mousePos[last][2],mx,my)
		local oriDist = (lastX-curX)^2 + (lastZ-curZ)^2
		local newDist = (lastX-mx)^2 + (lastZ-mz)^2
		local j = "current is last"
		for i=#specs-2, 1,-1 do -- if we are zoomed out and previous ones are close, we help the backwarding
			local spec=specs[i]
			local iX,iY = toScreen(spec[1],GetGround(spec[1],spec[2]),spec[2])

			--local prevOriDist = GetDist(mousePos[i][1],mousePos[i][2],mousePos[#specs][1],mousePos[#specs][2])
			local prevOriDist = GetDist(iX,iY,curX,curY)

			if prevOriDist<1500 --[[and prevOriDist>oriDist--]]  then
				j = "current is "..#specs-1-i.." before last"
				--local prevNewDist = GetDist(mousePos[i][1],mousePos[i][2],mx,my)
				local prevNewDist = GetDist(iX,iY,mx,my)
				if prevNewDist<=prevOriDist then 
					newDist = prevNewDist
					oriDist = prevOriDist
					backward = true
					break
				end
			else
				break
			end
		end
		--Echo(j, "backward=", backward)
		--Echo(speed)

		if (newDist<=oriDist --[[or last2 and newDist2<oriDist2--]]) and not invisible then 
			--[[local last2 = #specs-2>0 and #specs-2
			if special and last2 then
				local oriDist2 = GetDist(mousePos[last2][1],mousePos[last2][2],mousePos[#specs][1],mousePos[#specs][2])
				local newDist2 = GetDist(mousePos[last2][1],mousePos[last2][2],mx,my)
				backward = newDist2<oriDist2
			else
				backward=true
			end--]]
				backward = true
			--Echo(" backward")
			--Echo("--")
		end


		if backward and (newDist<oriDist*2/3)--[[ or (last2 and newDist2<oriDist2)--]] then
			--Echo("oriDist<1500 is ", oriDist<1500)
			if mexes[specsLen] then
				
				local num = inTable(forgetMex, mexes[specsLen])
				forgetMex[num]=nil
				mexes[specsLen]=nil

			end

			specs[specsLen]=nil
			specsLen=specsLen-1
			--widgetHandler:UpdateWidgetCallIn("DrawWorld", self)
			--- little trick to place correctly placement grid from engine
			local pmx, pmy = toMouse(specs[specsLen]) -- getting a valid mouse position according to the new placement
			sp.WarpMouse(pmx,pmy)

			sp.SendCommands("Mouse1")
			local impede = false
			if #specs>3 then-- in case we're crossing another placement we have to fully jump or we will get stuck
				for i=1, #specs-1 do
						
					impede=	pointX>specs[i][1]-p.footX*16 and pointX<=specs[i][1]+p.footX*16 and
							pointZ>specs[i][2]-p.footZ*16 and pointZ<=specs[i][2]+p.footZ*16
					if impede then

						break
					end
				end
			end
			if impede  --[[or oriDist<1500--]] then
				--Echo("total warp")
				--sp.WarpMouse(unpack(mousePos[#specs]))
				sp.WarpMouse(pmx,pmy)
			else
				--local midX = curMouse[1]-(curMouse[1]-mousePos[#specs][1])/3
				--local midY = curMouse[2]-(curMouse[2]-mousePos[#specs][2])/3

				local midX = mx-(mx-pmx)/3
				local midY = my-(my-pmy)/3
				--Echo("little warp")
				sp.WarpMouse(midX,midY)
			end

			--sp.SetActiveCommand(activeCom) --renewing placement starting for graphical coherence

			--------
		end
		if backward then
			return true
		end
	end
	return false
end
-------------
--------
--------
--------
---


--------
--------
--------
--------
--[[local function pushAway(pos,tgt,dir)
	local x,z = unpack(pos)	

	local ix,iz
	if t(tgt[1])=="table" then --then this is a block of rectangles
		--ix,iz = table.sumxz(tgt,1,2) -- make an average center of the block, to define the direction of push away
		--ix,iz = ix/#tgt,iz/#tgt
		--table.insert(AVG,{ix,iz}) -- just to check the drawing on map
		local minMax=minMaxCoord(tgt)
		ix,iz = table.sumxz(minMax,1,2) -- make an average center of the block, to define the direction of push away
		ix,iz = ix/2,iz/2
		table.insert(AVG,{ix,iz}) -- just to check the drawing on map
	else
		ix,iz = tgt[1],tgt[2]
	end

	local iDir = GetDirection(ix,iz,x,z)
	if iDir.x==0 and iDir.z==0 then iDir.x=math.random() iDir.z=math.random() end
	local pointRect = {x,z,p.sizeX*2,p.sizeZ*2}
	local tries=0
	while Overlapping(pointRect,tgt) do
		tries=tries+1
		x = x+8*(iDir.x)
		z = z+8*(iDir.z)
		pointRect = {x,z,p.sizeX*2,p.sizeZ*2}
		if tries==100 then Echo("tried too much") break end
	end
	return x,z, tries>0
end--]]

-- Check if is it in radius of a specific building or the last in the list of placements or all placements (all=true), 
local function IsInRadius(x,z,radius,all,target)
	-- local radius=(E_RADIUS[PID]*2)^2
	-- local radius = (p.eradius * 2) ^2
	if target then return radius>(x-target[1])^2 + (z-target[2])^2 end

	local start = #specs
	local End = all and 1 or start
	for i=start,End, -1 do --reverse loop to save some CPU, mostly used for checking previous placement,
							-- it can become useful to check others in case of drawing placements backward
		target=specs[i]
		--Echo("(x-target[1])^2 + (z-target[2])^2, radius is ", (x-target[1])^2 + (z-target[2])^2, radius)
		if radius>(x-target[1])^2 + (z-target[2])^2 then return true end
	end
	return false
end



--judge.connectedGrids = function(self) Echo('TEST',self) end


local function AdaptForMex(name) 
	ATTRACTED = false
	if not GetCloseMex then
		return
	end
	if name == 'energypylon' then
		return
	end
	if not (opt.remote or g.unStraightened) then
		return
	end

	local min, max = math.min, math.max
	-- local spot, mDist = g.closeMex[1],g.closeMex[2]
	-- local spot, mDist = GetCloseMex(pointX, pointZ)

	local spot, mDist, t = GetClosestAvailableMex(pointX, pointZ, (CalcRemoteRadius() + E_RADIUS[mexDefID])^2, true)
	if opt.remote then
		if REMOTE and REMOTE[1] then
			if t then
				for _, p in pairs(t) do
					for i, pg in pairs(REMOTE) do
						if pg[1] ~= p[1] or pg[3] ~= p[3] then
							REMOTE[#REMOTE + 1] = p
							break
						-- else
						-- 	Echo('same point',p[1],p[3])
						end
					end
				end
			end
		else
			REMOTE = t
		end
		
		-- if REMOTE then
		-- 	table.sort(REMOTE, function(a, b) return a.dist < b.dist end) 
		-- end
	end
	if not spot then
		return
	end
	-- magnetMex is abandoned feature for now
	if not (g.unStraightened and opt.magnetMex) then -- don't use magnet when in straight mode
		return
	end
	--- magnetMex abandoned feature for now
	local mPosx, mPosy, mPosz = spot.x, spot.y, spot.z

	local scMexPosX,scMexPosY = sp.WorldToScreenCoords(mPosx,mPosy,mPosz)
	local scMexDist = (scMexPosX-mx)^2 + (scMexPosY-my)^2
	local mexDist =  ((pointX - mPosx) / 16) ^ 2 + ((pointZ - mPosz) / 16) ^ 2
	approaching = prev.mexDist==mexDist and approaching or mexDist<prev.mexDist

	prev.mexDist = mexDist
	local mDirx,mDirz = scMexPosX-mx, scMexPosY-my
	local biggest =  max( abs(mDirx), abs(mDirz) )
	mDirx,mDirz = mDirx/biggest, mDirz/biggest

	-- if name~="energypylon" then
	-- if PID ~= pylonDefID then

		-- help mouse to navigate through mex
		-- if  mexDist<15 and not inTable(forgetMex, {mPosx, mPosz}) then -- forgetting mex once we reached it
		-- 	table.insert(forgetMex, {mPosx, mPosz})
		-- end
		if  mexDist<15  then -- forgetting mex once we reached it
			forgetMex[spot] = true
		end
		------- REFINE IT OR MAYBE NOT USE IT AT ALL
		-- Echo("scMexDist is ", scMexDist, scMexDist^0.5)



		if --[[approaching and--]] not forgetMex[spot] and scMexDist < g.magnetScreen^2 then
			local factor = min(1000 / scMexDist, 10, scMexDist )
			local gox, goy = mx + factor *(mDirx), my + factor * (mDirz)
			sp.WarpMouse(gox, goy)
			ATTRACTED = spot
			-- Echo('attracting', gox, goy)
			return gox, goy
		elseif --[[not approaching and--]] scMexDist<5 then
			-- Echo('repulsing')
			sp.WarpMouse( mx + 3 *(-mDirx) * scMexDist/1000, my + 3 * (-mDirz)*scMexDist/1000)
		end
		---------
	-- end

	-- push pointX away from mex
	-- local sx,sz = p.sizeX*2,p.sizeZ*2
	-- while IsOverlap(mPosx,mPosz,24,24,pointX,pointZ,sx,sz) do
	--	pointX = pointX+16*(mDirx--[[+ampX--]])
	--	pointZ = pointZ+16*(mDirz--[[+ampZ--]])
	-- end	-------------------------------------------------------------------------
end
	--local ampX = (1-abs(mexDirection[1])/2)*plusMin(mexDirection[1])
	--local ampZ = (1-abs(mexDirection[2])/2)*plusMin(mexDirection[2])
	--local impede = curX<p.footX and curZ<p.footZ
-- local centerpoint,outpoint


local function AvoidMex(x,z)
	if not GetCloseMex then
		return
	end
	local mPos,mDist = g.closeMex[1], g.closeMex[2]
	local mPosx, mPosy, mPosz = mPos.x, mPos.y, mPos.z
	--Echo(" mex ", mPos.x,mPos.z)
	--Echo("cursor", x,z)
	local sx, sz = p.sizeX, p.sizeZ
	local mDirx, mDirz = mPosx-x, mPosz-z
	local biggest =  math.max( abs(mDirx), abs(mDirz) )
	mDirx, mDirz = mDirx / biggest, mDirz / biggest
	x = floor((x + 8 - p.oddX)/16) * 16 + p.oddX
	z = floor((z + 8 - p.oddZ)/16) * 16 + p.oddZ

	--while IsOverlap(mPosx,mPosz,24,24,x,z,sx,sz) do
	while ((x - mPosx)^2 < (sx + 24)^2 and (z - mPosz)^2 < (sz + 24)^2) do
		x = x + 16 * -mDirx
		z = z + 16 * -mDirz
		x = floor((x + 8 - p.oddX)/16) * 16 + p.oddX
		z = floor((z + 8 - p.oddZ)/16) * 16 + p.oddZ
	end
	sp.WarpMouse(Spring.WorldToScreenCoords(x, sp.GetGroundHeight(x,z), z))
	return x,z
end

local function FixBetween(x,z,connected)
	local fixed
	local unitx,unitz = connected[1], connected[2]
	local ud = UnitDefs[ connected[3] ]
	local laspx,laspz = unpack(specs[specs.n])
	local w,h = p.sizeX*2, p.sizeZ*2
	local unitw,unith = ud.xsize*8, ud.zsize*8

	x = floor((x + 8 - p.oddX)/16)*16 + p.oddX
	z = floor((z + 8 - p.oddZ)/16)*16 + p.oddZ
	--local distance = sqrt( (laspx-unitx)^2 + (laspz-unitz)^2 )
	 -- arranging the placement on connection, between last spec and spotted econ building
--Echo(abs(connected[1]-laspec[1]),abs(connected[2]-laspec[2]))
	--pointX = pointX + (connected[1]-laspec[1])/32--*ratio
	--pointX = floor((pointX + 8 - p.oddX)/16)*16 + p.oddX

	--Echo(Overlapping( {x1,z1,w1,h1}, {x2,z2,w1,h1} ), Overlapping( {x1,z1,w1,h1}, {x3,z3,w3,h3} ))
	if
		IsOverlap( x, z, w, h, laspx, laspz, w, h )
	or
		IsOverlap( x, z, w, h, unitx, unitz, unitw, unith )
	then
		--local ratio = (UnitDefs[PID].name=='energysolar' and 1.5 or 1) / (UnitDefs[connected[3]].name=='energysolar' and 1.5 or 1)
--[[	local tX = pointX + (connected[1]-laspec[1])
		local tZ = pointX + (connected[2]-laspec[2])--]]
		x = abs(unitx + laspx)/2
		z = abs(unitz + laspz)/2
--[[				Echo("pointX,tX is ", pointX,tX)
		Echo("pointZ,tZ is ", pointZ,tZ)--]]
		x = floor((pointX + 8 - p.oddX)/16) * 16 + p.oddX
		z = floor((pointZ + 8 - p.oddZ)/16) * 16 + p.oddZ
		fixed = {x, z}
	end

	--pointZ = pointZ + (connected[2]-laspec[2])/32--*ratio
	--pointZ = floor((pointZ + 8 - p.oddZ)/16)*16 + p.oddZ

--[[				pointX = distance<(p.eradius*2) and pointX + (connected[1]-laspec[1])/32 or
								   pointX + (connected[1]-laspec[1])/48
	pointZ = distance<(radius*2) and pointZ + (connected[2]-laspec[2])/32 or
								   pointZ + (connected[2]-laspec[2])/48--]]
	return fixed
end

local function UpdateMexes(px, pz, remove, at, virtual, irail)
	local spotsPos = WG.metalSpotsByPos or EMPTY_TABLE
	local spots = WG.metalSpots or EMPTY_TABLE
	if remove then
		if mexes[at] --[[and not g.preGame--]]  then
			local imexes = mexes[at]
			for i = 1, #imexes do
				local x, z = imexes[i][1], imexes[i][2]
				local n = spotsPos[x][z]
				g.cantMex[spots[n]] = nil
				allGrids['m'..n] = nil
			end
			mexes[at] = nil
		end
		return
	end
	if virtual then
		g.previMex = {}
	end
	-- local IsOccupied = sp.GetUnitsInRectangle
	local rad = E_RADIUS[PID]
	local sqMaxDist = (rad+49)^2
	local reorder
	for n = 1, #spots do
		local spot = spots[n]
		local dist = (px-spot.x)^2 + (pz-spot.z)^2
		-- if dist<(rad+49)^2  and not IsOccupied(x,z,x,z)[1] then -- check if the virtual mex is in my range then
		if dist < sqMaxDist and (virtual or not g.cantMex[spot]) then
			if IsMexable(spot) then -- check if the virtual mex is in my range then
				-- adding mex to place by the way
				if virtual then
					g.previMex[#g.previMex+1]={spot.x,spot.z}
				elseif not g.cantMex[spot] then
					local imexes = mexes[at]
					if not imexes then
						-- Echo('new',at, 1)
						imexes = {{spot.x,spot.z, dist = dist}}
						mexes[at]=imexes
					else 
						-- reorder = imexes
						imexes[#imexes+1]={spot.x,spot.z}
						-- Echo('plus',at, #imexes)

					end
					if irail then
						irail.mex = true
						irail.color = color.yellow
					end
					allGrids['m'..n]=true
					g.cantMex[spot]=true
				end
				--
			end
		end
	end
	if reorder then
		-- Echo('reorder', #reorder)
		table.sort(reorder, function(a, b) return a.dist < b.dist end)
	end

end
local CheckConnections
do
	local known = {time = os.clock()}
	local knownGrid = {time = os.clock()}-- TODO: short time cache for grid
	local function GetInfo(id) 

	end
	CheckConnections = function(px, pz, previousCo, checkOnlyMex)  -- TODO: OPTIMIZE !
		--determine the grids of empty mexes in range if those mexes were built
		--see if different grids would actually be the same if the mex were built
		-- then decide accordingly to pose or not, comparing to previous connections
		-- localize globals to repeat call faster
		-- check also home made grid of ordered building and grid of existing unit, linking those who should be considered the same
		local GetUnitsInRange,			GetPos,				GetDefID,			GetParam,              GetTeam
		 = sp.GetUnitsInCylinder, Spring.GetUnitPosition, sp.GetUnitDefID, Spring.GetUnitRulesParam, sp.GetUnitTeam
		-- local cachedData = WG.CacheHandler:GetCache().data
		local time = os.clock()
		if time - known.time > 30 then
			known = {time = time}
		end
		if time - knownGrid.time > 4 then
			knownGrid = {time = time}
		end

		local spots = WG.metalSpots or EMPTY_TABLE
		local allegianceTarget = opt.connectWithAllied and Spring.ALLY_UNITS or Spring.MY_UNITS
		--
		local E_RADIUS = E_RADIUS
		local rad, mexrad = E_RADIUS[PID], E_RADIUS[mexDefID] -- ranges of our own econ building and mex for connection check
		-- if true then
		-- 	return 0,{},{},{}
		-- end
		--
		local connected
		local grids={} -- the current connections we gonna find
		local cm,cu,cp
		local huge = math.huge
		-- local cmdist,cudist,cpdist = huge, huge, huge
		--we add the units around cursor and detect if any real new grid is found or if it's linked to a virtualmex
		if checkOnlyMex then
			local curToMex = (rad+49)^2
			for n = 1, #spots do
				local spot = spots[n]
				local dist = ((px-spot.x)^2 + (pz-spot.z)^2)
				if dist < curToMex then -- check if the virtual mex is in my range then
					grids['m'..n] = {}
				end
			end
		else
			-- UNITS IN RADIUS OF PLACEMENT CURSOR
			local newunits = GetUnitsInRange(px, pz, MAX_REACH + rad, allegianceTarget)-- the maximum reach (singu or fusion:150, pylon:500) + own rad 

			local irad, ix, iy, iz
			for i=1,#newunits do

				ix = false
				local id = newunits[i]
				local knownU = known[id]
				
				if knownU then
					irad, ix, iz = knownU[1], knownU[2], knownU[3]
				elseif knownU == false then
					-- skip
				else
					irad = E_RADIUS[GetDefID(id)]
					if not irad then
						known[id] = false
					else
						ix,iy,iz = GetPos(id)
						known[id] = {irad, ix, iz}
					end
				end
				if ix then
					-- distance cursor->econ building and get it's grid
					local dist = (px-ix)^2 + (pz-iz)^2
					-- Echo("dist is ", dist)
					if dist < (irad+rad)^2 then
						--overlapped[#overlapped+1]={ix,iz,idefid}
						-- if dist<cudist then cu,cudist={ix,iz,isx,isz,dist},dist end
						local ugrid = GetParam(id, 'gridNumber')
						--if idefid==mexDefID and grid==1 then grid = 'm'..spotsPos[ix][iz]  --[[Echo('-> grid', grid)--]] end

						if ugrid then
							grids[ugrid]=grids[ugrid] or {}
							-- EMPTY MEX IN RADIUS OF UNIT
						-- 	for n = 1, #spots do
						-- 		local spot = spots[n]
						-- 		if (ix-spot.x)^2 + (iz-spot.z)^2 < (irad+49)^2  and not IsOccupied(spot.x, spot.z) then -- check if the virtual mex is in my range then
						-- 			local mgrid = 'm'..n
						-- 			grids[mgrid]=grids[mgrid] or {}
						-- 			grids[ugrid][mgrid]=true
						-- 			grids[mgrid][ugrid]=true
						-- 		end
						-- 	end
						end
					end
				end
			end

			-- associate different grids linked by empty mex
		--[[	for grid, links in pairs(grids) do
				if tostring(grid):match('m') then -- it's a unit grid
					for link1 in pairs(links) do
						for link2 in pairs(links) do if link2~=link1 then grids[link1][link2]=true end end
					end
				end
			end--]]
			--
			-- EMPTY MEX IN CURSOR RADIUS
			for n = 1, #spots do
				local spot = spots[n]
				local dist = ((px-spot.x)^2 + (pz-spot.z)^2)
				-- Echo("dist is ", dist)
				if dist<(rad+49)^2  and not IsOccupied(spot.x,spot.z) then -- check if the virtual mex is in my range then
					local x, z = spot.x, spot.z
					local mgrid = 'm'..n
					-- Echo('GOT ',n,dist)
					grids[mgrid]=grids[mgrid] or {}
						local newunits=GetUnitsInRange(x, z, 150 + mexrad, allegianceTarget)-- the maximum reach (singu or fusion) + mex rad
						-- UNITS THAT WOULD BE CONNECTED TO EMPTY MEX
						for i=1,#newunits do
							local id = newunits[i]

							local irad = E_RADIUS[GetDefID(id)]
							if irad then
								local ix,iy,iz = GetPos(id)
								if ( (x-ix)^2 + (z-iz)^2 ) < (irad+mexrad)^2 then-- distance mex->econ and get it's grid
									local ugrid = GetParam(id,'gridNumber')
									if ugrid then
										grids[ugrid]=grids[ugrid] or {}
										grids[ugrid][mgrid]=true
										grids[mgrid][ugrid]=true
									end
								end
							end

						end
					-- end
				end
			end
			-- if not checkOnlyMex then
				-- consider grid of placed buildings
				for i=1,#placed do
					local place=placed[i]
					local ix,iz = place[1],place[2]
					local irad = place.eradius
					if irad then
						local dist = (px-ix)^2 + (pz-iz)^2
						if dist < (irad+rad)^2 then
							-- if dist<cpdist then cp,cpdist={ix,iz,place[3],place[4],dist},dist end
							local pgrid = place.grid or -1
							grids[pgrid]=grids[pgrid] or {}
							connected=true
							-- PLACEMENT TO REAL UNIT
							local newunits=GetUnitsInRange(ix,iz,MAX_REACH+irad, allegianceTarget)
							for i=1,#newunits do
								local id = newunits[i]
								local urad = E_RADIUS[GetDefID(id)]
								if urad then
									local ux,uy,uz = GetPos(id)
									if ( (ix-ux)^2 + (iz-uz)^2 ) < (irad+urad)^2 then-- distance placement->real eBuild and get it's grid
										local ugrid = GetParam(id,'gridNumber')
										if ugrid then 
											grids[ugrid]=grids[ugrid] or {}
											grids[ugrid][pgrid]=true
											grids[pgrid][ugrid]=true
										end
									end
								end
							end
							--
							-- check if there's a close empty mex near the placement
							local range = (irad+mexrad)^2
							for n = 1, #spots do
								local spot = spots[n]
								if (ix-spot.x)^2 + (iz-spot.z)^2 < range  and not IsOccupied(spot.x,spot.z) then -- check if the virtual mex is in my range then
									local mgrid = 'm'..n
									grids[mgrid]=grids[mgrid] or {}
									grids[pgrid][mgrid]=true
									grids[mgrid][pgrid]=true
								end
							end
							--
						end
					end
				end
				-- consider drawn projected current placements as grid, discarding the 3 last placements behind cursor
				-- TODO CHANGE RULE
				local last = #specs-3
				if last>0 then
					--local irad=p.eradius
					local irad = E_RADIUS[PID]
					local sx,sz = p.sizeX,p.sizeZ
					for i=1,last do 
						local place=specs[i]
						local ix,iz = place[1],place[2]
						local dist = (px-ix)^2 + (pz-iz)^2
						if dist < (irad+rad)^2 then
							-- if dist<cpdist then cp,cpdist={ix,iz,sx,sz,dist},dist end
							local pgrid = 's'
							grids[pgrid]=grids[pgrid] or {}
							connected=true
							break
						end
					end
				end
			-- end
		end

		for grid, links in pairs(grids) do
			for link1, g1 in pairs(links) do
				for link2 in pairs(links) do
					if link2~=link1 then
						grids[link1][link2]=true 
					end 
				end
			end
		end

		-- we associate grids connected to each others -- FIXME: this doesnt detect a placement that is connected but not under the cursor radius, but we still can do our job
		local n=0
		local connect={}


		-- we discernate the real separate grids, register the newly connected grids
		local connectedTo = previousCo  or connectedTo
		for grid,links in pairs(grids) do

			if not links.done then
				n=n+1
				
				local isNew = not connectedTo[grid]
				for link in pairs(links) do
					if isNew then isNew=not connectedTo[link] end
					grids[link].done=true
				end
				if isNew then 
					connect[grid]=true
				end
				links.done=true
			end
			links.done=nil
		end
		for grid,links in pairs(grids) do links.done=nil end
		-- register if we get out of a grid

		local out={}
		for grid,links in pairs(connectedTo) do
			if not grids[grid] and not connectedTo[grid].done then
				out[grid]=true
				for link in pairs(links) do
					--Echo('link:', link)
					connectedTo[link].done=true
				end
			end
			links.done = true
		end
		for grid,links in pairs(connectedTo) do links.done=nil end

	--if cu then overlapped[#overlapped+1]=cu end
		-- local function keysunpack(t,k)
		-- 	local k = next(t,k)
		-- 	if k then return k,keysunpack(t,k) end
		-- end

	--[[	for grid,linkedTo in pairs(grids) do
			Echo('grid: '..grid..' |', keysunpack(linkedTo))
			--for link in pairs(linkedTo) do Echo('('..link..')') end
		end--]]
		-- finally we find out if there is any new grid to connect


	--Echo("n is ", n,connect)
	--[[	if n>0 then
			for grid in pairs(grids) do linked[grid]=true end
			--CompareGrids(connectedTo,grids,linked,px,pz)
			--connectedTo=grids
		else
			linked={}
		end--]]
		--Echo("connect,out is ", connect,out)

		return n,connect,out,grids
	end
end
local function keysunpack(t,k)
	local k = next(t,k)
	if k then return k,keysunpack(t,k) end
end

local function copy(t)
	local T={}
	for k,v in pairs(t) do
		T[k]=v
	end
	return T
end

local function Link(grids)
	local T={}
	for g1,links in pairs(grids) do
		T[g1]={}
		for g2 in pairs(grids) do
			if g1~=g2 then T[g1][g2]=true end
		end
	end
	return T
end
local function readgrids(grids)
	local str = ''
	for k,v in pairs(grids) do
		str = str .. k .. '-'
	end
	return str:sub(1,-2)
end
local function Judge(rx, rz, sx, sz, lasp, llasp, PBH, irail, lastRail)
	-- FIXME: the grid system need to be bettered: make it so that we can know all grids we're connected to
	-- IMPROVE AND SIMPLIFY
--Page(connectedTo)
	--local isPylon = PID == UnitDefNames["energypylon"].id
	local debug = Debug.judge()

	local spots = WG.metalSpots
	local radius = (p.eradius * 2) ^2
	local n, newgrids, outgrids, grids = CheckConnections(rx, rz, nil, PID ~= pylonDefID and opt.checkOnlyMex)

	--newgrids and outgrids register the connections and disconnections to current point from last point
	local n_new = l(newgrids)
	local connectToSelf
	if n_new == 1 and newgrids.s then
		connectToSelf = true
	end
	

	-- Echo("overlapLasp is ", overlapLasp,abs(lasp[1]-rx),sx,'|',abs(lasp[2]-rz),sz)
	local cantPlace, blockingStruct, _, overlapSpec = TestBuild(rx, rz, p, true, placed, overlapped, specs, true)
	-- local overlapLasp = lasp and (lasp[1]-rx)^2 < (sx*2)^2 and (lasp[2]-rz)^2 < (sz*2)^2
	local overlapLasp = false
	if lasp and overlapSpec then
		for i, v in ipairs(overlapSpec) do
			if lasp[1] == v[1] and lasp[2] == v[2] and sx == v[3] and sz == v[4] then
				overlapLasp = true
				break
			end
		end
	end
	local tooSteep = cantPlace and not blockingStruct
	local hasRealOverlap = cantPlace and blockingStruct
	-- Echo("overlapSpec is ", overlapSpec and (overlapSpec[2] and '1+' or overlapSpec[1] and '1' or '??') or '0')
	local overlapOnlyLasp = not hasRealOverlap and overlapLasp and overlapSpec and not overlapSpec[2]

	local steppingOnSpecQueue = not overlapOnlyLasp and overlapSpec

	irail.tooSteep = tooSteep
	irail.overlapSpec = not not overlapSpec -- transform into bool
	irail.steppingOnSpecQueue = not not steppingOnSpecQueue
	irail.hasRealOverlap = not not hasRealOverlap

	local inRadius = steppingOnSpecQueue or lastRail and lastRail.steppingOnSpecQueue or lasp and IsInRadius(rx,rz,radius,true)
	local inRadiusOfLasp = lasp and IsInRadius(rx,rz,radius,nil,lasp)
	-- local inRadiusOfConnected = lasp and IsInRadius(rx,rz,radius,nil,lasp)
	local inRadiusOfLlasp = llasp and IsInRadius(rx,rz,radius,nil,llasp)
	--local canReplaceLasp = llasp and IsInRadius(rx,rz,radius*2,nil,llasp)
	local status = lasp and lasp.status or 'out'
	-- Can we move the lasp (last placement) on that new rail point
	local canPose = not (overlapSpec or hasRealOverlap or tooSteep and (g.noterra or not PBH)) 
	irail.canPose = canPose
	-- local canPoseBefore = lastRail and not (lastRail.steppingOnSpecQueue or lastRail.hasRealOverlap)
	local canPoseBefore = lastRail and lastRail.canPose
	local canReplace = lasp and (canPose or overlapOnlyLasp)
	local canMoveConnection = inRadiusOfLlasp and (not tooSteep or lasp.tooSteep or PID == pylonDefID and not g.noterra)
	-- Echo("canMoveConnection is ", canMoveConnection, 'lasp too steep', lasp.tooSteep,'inRadiusOfLlasp',inRadiusOfLlasp)
	-- check if we loose a connection if we replace the lasp by the current
	-- if canPose or canPoseBefore or canReplace then
	-- 	Echo( 
	-- 		(
	-- 			(canPose and 'canPose, ' or '')
	-- 			.. (canPoseBefore and 'canPoseBefore, ' or '')
	-- 			.. (canReplace and 'canReplace, ' or '')
	-- 		):sub(1, -3)
	-- 	)
	-- end
	if canMoveConnection then
		for k in pairs(lasp.newgrids) do
			if not grids[k]  then
				if k ~= 's' then
					canMoveConnection=false
					if debug then
						Echo('loosing', k, 'if move connection',os.clock())
					end
				end
			end
		end
	end
	-- check the real new connections we can make
	local realnewgrids, n_realnew = {},0
	for k in pairs(newgrids) do
		if not allGrids[k] --[[and k~='s'--]] then
			realnewgrids[k]=true
			n_realnew = n_realnew+1
		end
	end

	if status == 'out' then
		-- if n_realnew>0 then status = 'connect' end
		if n_new>0 then status = 'connect' end
	elseif status == 'connect' then
		if n==0 then status = 'disconnect'
		elseif n_new==0 then status = 'onGrid'
		end
	elseif status == 'disconnect' then 
		if n==0 then status = 'out'
		elseif n_new>0 then status = 'connect'
		end
	elseif status == 'onGrid' then
		if n==0 then status = 'disconnect'
		elseif n_new>0 then status = 'connect'
		end
	end

	local pose
	local reason
	if debug or Debug.connect() then
		Echo(
			(
				'status: '.. status .. ', '
				.. (
					next(allGrids) and (
						'grids:['	
						.. (n_new > 0  and 'new:' ..  readgrids(newgrids) .. ', ' or '')
						.. (n_realnew > 0 and 'real new: ' .. readgrids(realnewgrids) .. ', '  or '')
						.. 'all: ' .. readgrids(allGrids) .. ', ' or ''
					):sub(1, -3) .. '], '
					or ''
				)
				.. (
					(overlapLasp or hasRealOverlap or steppingOnSpecQueue) and (
						'overlap:['
						..	(overlapLasp and 'self, ' or '')
						.. (hasRealOverlap and 'real, ' or '')
						.. (steppingOnSpecQueue and 'queue, ' or '')
					):sub(1, -3) .. '], '
					or ''
				) 
			):sub(1, -3)
			-- ''
			--  ..(connectToSelf and 'connectToSelf, ' or '')
			--  .. (tooSteep and 'tooSteep, ' or '')
			--  ..(canMoveConnection and 'Can Move, ' or '')
		)
	end

	local pushBackR
	if status == 'onGrid' then
		for grid, v in pairs(grids) do
			if string.find(grid, 'm') then
				local n = tonumber(string.match(grid,'%d+'))
				local at = specs.n
				if not g.cantMex[spots[n]] then
					UpdateMexes(rx, rz, nil, at)
				end
			end
		end
		--
		-- move the placement further away as long as the loosing connections of current are hold by the last placement
		if canMoveConnection and canReplace then
			pose = 'replace'
			reason = 'can move up connection1'
		-- elseif tooSteep then
		-- 	if lastRail and PID ~= pylonDefID and canPoseBefore then
		-- 		pose = 'before'
		-- 		reason = 'before because too steep'
		-- 	end
		-- elseif canPose then

		-- 	pose = true
		end
	elseif status == 'connect' then

		-- case of reaching a connection but this step make us loose the previous connection
		if (not lasp --[[or not lasp.status == 'onGrid'--]] or lasp.status == 'disconnect') and not inRadius then
			if canPoseBefore then
				pose = 'before'
				reason = 'before to not get out of own radius'
			elseif canPose then
				pose = true
				reason = 'pose now, couldn\'t pose before to maintain connection'
			end
		elseif connectToSelf and overlapSpec then
			pose='before'
			reason = 'connecting to self queue before stepping on placement'
		elseif overlapOnlyLasp then
			if canMoveConnection then
				reason = 'can move up connection2'
				pose ='replace'
			elseif PID ~= pylonDefID then
				local r = lasp and lasp.r - 1
				local pushable = r and rail[r] and rail[r].posable and rail[r]
				while pushable do
					local stillOverlap = (rx - pushable[1])^2 < (sx*2)^2 and (pushable[3]-rz)^2 < (sz*2)^2
					if not stillOverlap then
						-- pushed back enough
						break
					end
					r = r - 1
					pushable = r and rail[r] and rail[r].posable and rail[r]
				end
				if pushable then
					pose = 'pushback'
					pushBackR = r
					reason = 'pushing back last placement to pose self in order to connect'
				end
			end
		elseif not overlapSpec then
			if canMoveConnection and canReplace then
				reason = 'moving current connection to add more'
				pose ='replace'
			else--[[if not (overlapLast or hasRealOverlap) then--]]
				if inRadius then
					if canPose then
						reason = 'pose now to connect'
						pose = true
					end
				elseif canPoseBefore then
					reason = 'pose before to not lose self connection'
					pose = 'before'
				end
			end
		end
	elseif status == 'out' then -- we're not constrained by losing grid
		if not steppingOnSpecQueue  then
			if --[[not hasRealOverlap and--]] not inRadiusOfLasp and canPoseBefore then 
				-- keep our connection with our last spec
				reason = 'need to pose before losing connection with lasp'
				pose = 'before'

			elseif tooSteep --[[and (PID~=pylonDefID or g.noterra)--]] then
				-- avoid steepness if we can
				if canPoseBefore then
					if lastRail and (PID~=pylonDefID or g.noterra) and not (lastRail.overlapSpec or lastRail.tooSteep) then
						reason = 'pose before to avoid steepness1'
						pose = 'before'
					end
				end
			elseif not hasRealOverlap then
				-- pose on last cursor pos even if not connecting/disconnecting
				if inRadiusOfLlasp and (not overlapSpec or overlapOnlyLasp) then -- switched statement => VERIFY IF ALL GOOD
					reason = 'can move up placement'
					pose = 'replace'
				elseif not overlapSpec then -- switched statement => VERIFY IF ALL GOOD
					reason = 'free and can pose now'
					pose= true
				end
			end
		end
		
	elseif status == 'disconnect' then
		if not inRadius and canPoseBefore then
			reason = 'not in radius anymore, pose before'
			pose = 'before'
		else
			if tooSteep and canPoseBefore then
				if lastRail and not (lastRail.overlapSpec or lastRail.tooSteep) then
					reason = 'pose before to avoid steepness2'
					pose = 'before'
				end
			elseif canPose then
			-- pose on last cursor pos even if not connecting/disconnecting
				-- if not overlapSpec then
					reason = 'can pose now'
					pose= true
				-- elseif inRadiusOfLlasp then
				-- 	pose = 'replace'
				-- end
			end
		end
	end
	if pose == 'replace' then
		-- status=lasp.status
		for k,v in pairs(lasp.newgrids) do newgrids[k]=true end
	end
	-- Echo("steppingOnSpecQueue is ", steppingOnSpecQueue)
	if pose then
		if debug then
			-- Echo(pose and "pose:"..(pose==true and "normal" or pose) or "",lasp and lasp.status,'=>'..status,'canMoveConnection:'..(canMoveConnection and 'yes' or 'no'),os.clock())
			Echo(lasp and table.concat({keysunpack(lasp.newgrids)},'-') or 'no lasp??',
				'POSE ' .. (lasp and tostring(lasp.status) or 'no lasp??')..' => '..status,reason
			)
		end
	end
	-- Echo(tostring(lasp.status)..'=>'..status,reason)
	-- Echo(pose and "pose:"..(pose==true and "normal" or pose) or "",lasp and lasp.status,'=>'..status,'canMoveConnection:'..(canMoveConnection and 'yes' or 'no'),reason,os.clock())
	-- Echo(table.concat({keysunpack(lasp.grids)},'-'),'|',table.concat({keysunpack(lasp.newgrids)},'-'))
	return pose, grids, status, newgrids, pushBackR
end




local function PoseSpecialOnRail()
	--Echo("specs.n,#specs is ", specs.n,#specs)
	-- local mingap = math.min(p.footX, p.footZ) -- TODO: BETTER
	local n = #specs
	local lasp = specs[n]
	if lasp and lasp.grids then
		connectedTo = lasp.grids
	end
	local a = rail.processed
	local railLen = rail.n
	if a >= railLen then
		return
	end

	
	local llasp = specs[n-1]
	local oddx, oddz = p.oddX, p.oddZ
	local sx, sz = p.sizeX, p.sizeZ
	local rx, rz

	local r = lasp and lasp.r or 1


	rx, rz = rail[a].rx, rail[a].rz
	-- Echo('Pose Special On Rail', 'from', a, 'r', r)
	--Echo('complete from=>> :'..a..' gap: '..a-r..'('..mingap..')')

	--laspx,_,laspz = sp.ClosestBuildPos(0,PID, laspx, 0, laspz, 1000,0,p.facing)

	local pose, grids, status, newgrids
	local lastRail = rail[a]
	-- Echo('run Special Posing at', (a+1) .. '/' .. railLen, '(real: ' ..#rail ..')')
	while a < railLen do
		a = a + 1
		local gap = a-r
		local irail = rail[a]
		rx,rz = irail.rx, irail.rz
		-- irail.specOverlap = lasp and (lasp[1]-rx)^2 < (sx*2)^2 and (lasp[2]-rz)^2 < (sz*2)^2
		irail.done = true
		local pushBackR
		if not pose then 
			pose, grids, status, newgrids, pushBackR = Judge(rx, rz, sx, sz, lasp, llasp, PBH, irail, lastRail)
			if status == 'connect' then
				irail.color = color.teal
				irail.connect = true
				for k in pairs(newgrids) do
					if type(k) == 'string' and k:match('m') then
						irail.conectMex = true
						-- irail.color = color.white
						break
					end
				end
			elseif status == 'disconnect' then
				irail.color = color.purple
			elseif status == 'onGrid' then
				irail.color = color.blue
				irail.onGrid = true
			end
		end

		if pose then
			if pose == 'pushback' and pushBackR then
				Debug.judge('can push back to R', pushBackR)
				-- push back the last posed until we can place
				local pushed = rail[pushBackR]
				lasp[1], lasp[2] = pushed[1], pushed[3]
				lasp.r = pushBackR
				pose = true
			end
			r = a
			if pose ~= 'replace' then
				n = n + 1
			end

			if pose == 'before' then
				if lastRail
				and not lastRail.steppingOnSpecQueue
				and not (lasp and (lasp[1] - lastRail.rx)^2 < (sx * 2)^2 and (lasp[2] - lastRail.rz)^2 < (sz * 2)^2)
				then
					irail = lastRail
					rx = lastRail.rx
					rz = lastRail.rz
					r = r - 1
					irail.overlapPlacement = true

					-- irail.color = color.purple
					_, grids, status, newgrids, canMex = Judge(rx, rz, sx, sz, lasp, llasp, PBH, irail)
				else
					pose = false
					n = n - 1
					Debug.judge('placement refused at ',lastRail.rx, lastRail.rz)
				end
			end

				--Echo('pose',r-1)

--[[				if pose=='push back and pose' and a>3 then
					Echo('check')
					local tries=0
					while lasp and (lasp[1]-rx)^2 < (sx*2)^2 and (lasp[2]-rz)^2 < (sz*2)^2 and lasp.r > 3 and tries<10 do
						tries = tries+1
						local backr = lasp.r-1
						lasp[1],lasp[2],lasp.r = rail[backr][1], rail[backr][3], backr
						Echo('pushed back to ', backr)
						if tries==10 then Echo('too many tries') end
					end
				end--]]
			if pose then
				-- Echo('new pose',n,pose)
				if pose == 'replace' then
					UpdateMexes(lasp[1], lasp[2], 'remove', n)
				end
				irail.posable = true
				irail.color = irail.color or color.orange
				local grids = Link(grids)
				specs[n]={ rx, rz, r = r, n = n, status = status, grids = grids, newgrids = newgrids, tooSteep = irail.tooSteep}
				connectedTo = grids
				-- allGrids = {}
				UpdateMexes(rx, rz, nil, n, false, irail)
				for g in pairs(grids) do
					allGrids[g] = true
				end
				-- for i=1,n do
				-- 	for k in pairs(specs[i].grids) do
				-- 		allGrids[k]=true 
				-- 	end
				-- end

					--Echo('pose',r)

				llasp = pose == 'replace' and llasp or lasp
				lasp = specs[n]

				---connectedTo = Link(grids)
				pose = false

			end

		end
		lastRail=irail
	end
	rail.processed = railLen
	specs.n = n
	return
end


local function PoseOnRail()
	--Echo("specs.n
	local mingap = math.min(p.footX,p.footZ)+p.spacing -- TODO: BETTER

	local n = #specs
	local laspec = specs[n]
	local railLen = rail.n


	local r = laspec and laspec.r or 0
	local a = rail.processed
	-- Echo('PoseOnRail', 'from', a,'r', r,'specs len',#specs, 'real', f.l(specs))

	--laspx,_,laspz = sp.ClosestBuildPos(0,PID, laspx, 0, laspz, 1000,0,p.facing)
	local sx, sz, oddx, oddz,facing = p.sizeX, p.sizeZ, p.oddX, p.oddZ, p.facing
	local rx,rz
	local alwaysMex = opt.alwaysMex and E_RADIUS[PID]
	while a < railLen do
		a = a + 1
		local gap = a - r
		local posable = gap >= mingap -- the minimum before caring to verify
		if posable then
			rx, _, rz = unpack(rail[a])
			rx = floor((rx + 8 - oddx)/16)*16 + oddx
			rz = floor((rz + 8 - oddz)/16)*16 + oddz

			local overlap, _, _, overlapPlacement = TestBuild(rx, rz, p, (not PBH or g.noTerra), placed, overlapped, specs, true)
			if not (overlap or overlapPlacement) then
				r = a
				n = n + 1
				specs[n] = {rx, rz, r = r, n = n}
				if alwaysMex then
					UpdateMexes(rx, rz, nil, n, false, rail[a])
				end
				-- laspx,laspz = rx,rz
			end
		end
	end
	rail.processed = rail.n
	specs.n = n
	return
end

-- Paint Function
do
	local min, max, abs, huge = math.min, math.max, math.abs, math.huge
	local GetGround = Spring.GetGroundHeight
	local coordsMemory = {}
	local SpiralSquare = f.SpiralSquare
	local poses,currentBarred, extraBarred,blockingStruct
	local method
	local rx,ry,rz,sx,sz, oddx,oddz
	local facing
	local scale
	local layers
	local max_possible

	----
	local edges = {}
	local debugEdges = false
	local fx,fz
	----
	local debug = false
	local debugMethods = false
	local solarDefID = UnitDefNames['energysolar'].id
	local windDefID = UnitDefNames['energywind'].id
	local firstTime = true
	local firstPose = false
	local useNeat
	local MarkEdge = function(layer,offx,offz)
		local x, z = fx + offx, fz + offz
		edges[x] = edges[x] or {}
		edges[x][z] = true
		if debugEdges then
			Points[#Points+1] = {x, sp.GetGroundHeight(x,z), z, color = color.red, txt = 'o'}
		end
	end
	local cnt, colcnt = 0, 0
	local function Bar(x,z,sx,sz,offx,offz,permanent,extra)
		local score = 0
		if permanent then -- permanent is barring existing or placed structures
			for x = x - sx + offx, x + sx, 16 do
				coordsMemory[x] = coordsMemory[x] or {}
				for z = z - sz + offz, z + sz, 16 do
					coordsMemory[x][z] = true
				end
			end
			return score
		end

		----- WIP: do circle instead of square ?
			local maxx, maxz = x + sx, z + sz
			local minx, minz = x - sx, z - sz
			-- local midx, midz = minx + (maxx-minx)/2, minz + (maxz-minz)/2
			-- local maxlen = (maxx-minx)/2 -- since we use only square for now -- TODO: implement rectangle
		-----
		------ WIP
		local edge
		------
		for x = x - sx, x + sx, 16 do -- temporary barring our current projected placements
			for z = z - sz, z + sz, 16 do
				if debug or debugEdges then
					edge = x == minx or x == maxx or z == minz or z == maxz
				end
				----- WIP
					--- circle?
					-- local fromEdge = ((x-midx)^2 + (z-midz)^2)^0.5 - maxlen
					-- local out = fromEdge >=16
					-- local edge = fromEdge >= 0 and not out
					---
				-----
				if opt.tryEdges and not opt.neatFarm then
					score = score + (edges[x] and edges[x][z] and 1 or 0)
				end
				if not (coordsMemory[x] and coordsMemory[x][z])
				and not (currentBarred[x] and currentBarred[x][z])
				then
					---- WIP
					-- if not out then
					----
						if not extra then
							currentBarred[x] = currentBarred[x] or {}
							currentBarred[x][z] = edge and 'e' or true
							if edge and (debug or debugEdges)--[[ and (x-minx)%(sx/4) == 0 and (z-minz)%(sz/4) == 0--]] then
								local num = #Points + 1
								local txt = num -- round(num/10)
								Points[num] = {x, sp.GetGroundHeight(x,z), z, color = color.yellow, txt = 'x'}
							end
						elseif not (extraBarred[x] and extraBarred[x][z]) then
							extraBarred[x] = extraBarred[x] or {}
							extraBarred[x][z] = edge and 'e' or true
							-- if edge and (debug or debugEdges) and (x%160==0 or z%160==0) then
							-- 	Points[#Points+1] = {x, sp.GetGroundHeight(x,z), z, color = color.yellow}
							-- end

							-- Points[#Points+1] = {x, sp.GetGroundHeight(x,z), z, color = color.white}

						end
					---- WIP
					-- end
					----
				end
				-- edge = x==minx or x==maxx or z==maxz
			end
		end
		return score
	end
	local function UpdateMem(barred) -- we put the temporarily blocked into permanent
		for x,col in pairs(barred) do
			if not coordsMemory[x] then -- directly take the currentBarred column
				coordsMemory[x] = col
				-- if debug or debugEdges then
				-- 	for z, v in pairs(col) do
				-- 		if v=='e'then
				-- 			Points[#Points+1] = {x,sp.GetGroundHeight(x,z),z,color = v=='e' and color.red or color.yellow,txt='x'}
				-- 		end
				-- 		-- Points[#Points+1] = {x,sp.GetGroundHeight(x,z),z,color = v=='e' and color.red or color.yellow,txt='x'}
				-- 	end
				-- end
			else
				for z, v in pairs(col) do
					-- if debug or debugEdges then
					-- 	for z, v in pairs(col) do
					-- 		if v=='e'then
					-- 			Points[#Points+1] = {x,sp.GetGroundHeight(x,z),z,color = v=='e' and color.red or color.yellow,txt='x'}
					-- 		end
					-- 		-- Points[#Points+1] = {x,sp.GetGroundHeight(x,z),z,color = v=='e' and color.red or color.yellow,txt='x'}
					-- 	end
					-- end
					coordsMemory[x][z] = v
				end
			end
		end

		-- for x,col in pairs(barred) do
		-- 	for z in pairs(col) do
				
		-- 	end
		-- end
	end
	local function GetSeparation(t) -- add every separations between each poses of t
		local sep = 0
		local p = t[1]
		local lastx, lastz = p[1], p[2]
		for i = 2, t.n do
			p = t[i]
			if not p.extra then
				local x, z = p[1], p[2]
				sep = sep + ( (lastx-x)^2 + (lastz-z)^2 )^0.5
				lastx, lastz = x, z
			end
		end
		return sep
	end
	local function SepOnExisting(t,ex)
		local sep = 0
		local n_ex = #ex
		for i = 1, t.n do
			local tx, tz = t[i][1], t[i][2]
			for j = 1, n_ex do
				sep = sep + ( (tx - ex[j][1])^2 + (tz-ex[j][2])^2 )^0.5
			end
		end
		return sep
	end
	local BarPlaced = function()
		for i, b in ipairs(placed) do
			local bx, bz = b[1], b[2]

			local bsx, bsz = b[3], b[4]
			local oddBx, oddBz = bsx%16, bsz%16
			local offx, offz = oddBx == oddx and 0 or oddx - oddBx, oddBz == oddz and 0 or oddz - oddBz
			-- Echo(UnitDefs[b.defID].name,'master',oddx,"oddBx", oddBx,'=>',offx)
			Bar(
				 bx
				,bz
				,bsx + sx - 16
				,bsz + sz - 16
				,0,0
				,'permanent'
			)
		end

	end

	local spTestBuildOrder = Spring.TestBuildOrder
	local FindPose = function(layer,offx,offz)
		local x = rx + offx
		local z = rz + offz
		-- Points[#Points+1] = {x,sp.GetGroundHeight(x,z),z,color = v=='e' and color.red or color.blue,txt='-'}
		local extra = layer > layers
		-- Echo("layer,layers is ", layer,layers)
		local onEdge
		if not (coordsMemory[x] and coordsMemory[x][z])
		and not (currentBarred[x] and currentBarred[x][z])
		and not (extra and extraBarred[x] and extraBarred[x][z])
		-- and InMapBounding(x,z)
		then 
			if (debug or debugEdges) and not extra and ceil(layer) == layers then
				if method ~= 3 then
					Points[#Points+1] = {x, sp.GetGroundHeight(x,z), z, color = color.yellow}
				end
			end
			-- Points[#Points+1]={x,GetGround(x,z),z,txt=extra and 'ex' or 'm'..poses.method}
			-- 'remember' will tell TestBuild to memorize coords that resulted in overlapping and return the sets of overlapped rects
			local cantPlace = spTestBuildOrder(PID, x, 0, z, facing) == 0
			if cantPlace then
				-- we bar just that position permanently
				-- Bar(x,z,0,0,0,0,'permanent')
				coordsMemory[x] = coordsMemory[x] or {}
				coordsMemory[x][z] = true
			else -- we found a good spot, we bar it and all around, temporarily
				local add = {x, z, r = a, extra = extra}
				add.score = Bar(x, z, ( sx + scale*8 )*2 - 16,( sz + scale*8 )*2 - 16, false, false, false, extra) -- extra is extra check farther than normal, in case we got more there
				local dist = ( (x - rx)^2 + (z - rz)^2 )^0.5
				poses.n = poses.n + 1
				poses[poses.n] = add
				poses.dist = poses.dist + dist
				-- if poses.method==2 then
				-- 	Echo("poses.n is ", poses.n)
				-- end
			end
		end
	end

	local function ExecuteMethod(method,layers,step,offset,reversed,findings,bestAtMax)
		poses = {n = 0, dist = 0, barred = {}, reversed = reversed, method = method, sep = 0, score = 0}
	
		currentBarred = poses.barred
		extraBarred = {}
		SpiralSquare(layers, step, FindPose, offset, reversed)
		local real_n = 0
		for i = 1, poses.n do
			local p = poses[i]
			if not p.extra then
				real_n = real_n + 1
				poses.score = poses.score + p.score
				-- if reversed then
				-- 	Points[#Points+1] = {p[1],sp.GetGroundHeight(p[1],p[2]), p[2]}
				-- end
			end
		end
		poses.real_n = real_n
		if real_n == 0 then
			-- if debugMethods then
			-- 	Echo('Method #'..method.. ' found 0 poses')
			-- end
			return
		end

		table.insert(findings,poses)
		local isBest = bestAtMax and real_n == max_possible 
		if isBest then
			if debugMethods then
				Echo('Method #'..method.. ' found ideal poses: '..real_n..'.')
			end
		elseif real_n > 1 then
			poses.sep = GetSeparation(poses)
			-- if blockingStruct then
			-- 	poses.sep = poses.sep + SepOnExisting(poses,blockingStruct)
			-- end
			if debugMethods then
				Echo('Method #'..method.. ' found '.. poses.n .. ' (real: '..real_n..')' .. ' poses, dist: '..poses.dist..(poses.n>1 and ', sep: '..poses.sep or '').. '.')
			end
		end
		return poses, isBest
	end


	Paint = function(reset)
		--Echo("specs.n,#specs is ", specs.n,#specs)
		if reset then 
			for k,v in pairs(coordsMemory) do 
				coordsMemory[k]=nil
			end
			for k in pairs(edges) do
				edges[k]=nil
			end
			firstTime = true
			useNeat = false
			return
		end
		sx, sz, oddx, oddz, facing = p.sizeX, p.sizeZ, p.oddX, p.oddZ, p.facing
		scale = farm_scale -- it should be better called 'spread' but ...
		if firstTime then
			BarPlaced()
			firstTime = false
			firstPose = false
			useNeat = opt.neatFarm 
				or PID == solarDefID and scale >1 
				or PID == windDefID and scale > 1 
				or sx ~= sz 
				or max(sx,sz) > 40 and scale > 1
		end
		debugMethods = Debug.paintMethods()
		if opt.tryEdges and not useNeat then
			debugEdges = Debug.edges()
			debug = false
		else
			debugEdges = false
			debug = Debug.paint()
		end



		local mingap = useNeat and max( sx + scale*8, sz + scale*8) or min( sx + scale*8, sz + scale*8) 
		local flexible = scale> 4


		local n = #specs
		local laspec = specs[n]
		local railLen = rail.n


		local r = laspec and laspec.r
		local lasR = rail[r]
		local a = rail.processed
		--laspx,_,laspz = sp.ClosestBuildPos(0,PID, laspx, 0, laspz, 1000,0,p.facing)
		local lasRx, lasRy, lasRz
		local offposeX, offposeZ
		if lasR and lasR.rpose then 
			lasRx, lasRy, lasRz = unpack(lasR.rpose)
			if useNeat then
				local Prx = floor( (lasRx + mingap ) / (mingap*2) ) * (mingap*2) -- - offposeX
				local Prz = floor( (lasRz + mingap ) / (mingap*2) ) * (mingap*2)  -- - offposeZ
				offposeX = lasRx - Prx
				offposeZ = lasRz - Prz
				-- Points[#Points+1]={Prx,ry,Prz,color = color.yellow}
			end
		end

		max_possible = (farm_spread+1)^2

		----- measuring half size
		local numBuildsWide = farm_spread + 1
		local totalSep = farm_spread * scale  
		local halfSizeX = numBuildsWide*sx + totalSep * 8
		local halfSizeZ = numBuildsWide*sz + totalSep * 8

		------

		while a<railLen do
			a=a+1

			------------- Adjusting starting position
			rx,ry,rz=unpack(rail[a])
			rx = floor( (rx + 8 - oddx)/16 )*16 + oddx
			rz = floor( (rz + 8 - oddz)/16 )*16 + oddz
			if farm_spread%2 == 1 then
				rx = rx - oddx + (scale%2)*8
				rz = rz - oddz + (scale%2)*8
			end
			--------- clamp farm
			local onMapEdge

			if rx <= halfSizeX then
				rx = halfSizeX
				onMapEdge = true
			elseif rx >= mapSizeX-halfSizeX then
				rx = mapSizeX-halfSizeX
				onMapEdge = true
			end
			if rz <= halfSizeZ then
				rz = halfSizeZ
				onMapEdge = true
			elseif rz >= mapSizeZ-halfSizeZ then
				rz = mapSizeZ-halfSizeZ
				onMapEdge = true
			end

			-------------

			local dist

			if lasRx then
				dist = max( abs(lasRx-rx), abs(lasRz-rz) )
			end
			local posable = not lasRx or dist >=mingap/2
			-- local posable = true
			-- Echo((dist and 'dist '..dist..' ' or '') .. (posable and 'posable' or ''))

			if useNeat and lasRx then
				rx = floor( (rx - offposeX + mingap ) / (mingap*2) ) * (mingap*2) + offposeX
				rz = floor( (rz - offposeZ + mingap ) / (mingap*2) ) * (mingap*2) + offposeZ
				-- Echo("offposeX, offposeZ is ", offposeX, offposeZ)
				posable = lasRx~=rx or lasRz~=rz
				-- Points[#Points+1]={rx,ry,rz,color = color.red}
			end

			-- posable = true
			-- Echo("#allspecs is ", #allspecs)
			-- posable = true
			if posable then
			-- 	if lasR then
					-- Points[#Points+1]={lasRx,lasRy,lasRz}
				-- end
				-- Points[#Points+1]={rx,ry,rz,color = color.red, txt  = (dist or 'no')..'/'..(mingap-16)}
				--debug
				currentBarred = {}
				extraBarred = {}
				method = 0
				----- Define how far we check -----
				local offset,step
				-- farm_spread 1 by default will make a quad
				layers = floor( (farm_spread+1)/2 )

				offset = (farm_spread%2) * mingap -- we start at 0 on uneven farm_spread value (which is an even number of build)
				-----
				-- Echo("rx%16 is ", rx%16,sx,sz, farmW%16, farmH%16,oddz,oddx,mapSizeX%16,mapSizeZ%16 )

				---
				---- debug middle pos when on map edge
				-- if onMapEdge then
				-- 	Points[#Points+1] = {rx, sp.GetGroundHeight(rx,rz),rz,txt = 'o',size = 13}
				-- end
				----
				-- SpiralSquare(layers,16,FindPose,offset)
				method = 1
				local findings = {}
				local reversed = false
				local extra = opt.useExtra and not useNeat and 1 or 0 -- checking extra layers to see what would fit the best with the environment, without actually posing them
				-- this is costly as none of the extra layer will be remembered
				-- method #1, looking for the neat square of placements

				repeat -- this is not a real loop, only used to break code execution

					local found, isBest = ExecuteMethod( method, layers + extra, mingap * 2, offset, reversed, findings, 'bestAtMax')
					if (isBest or useNeat) then
						break
					end
					-- method #2, looking for possible placements starting from center (or oddx), in spiral, clockwise and starting at 10 o'clock
					method = method+1
					if farm_spread == 1 and not onMapEdge then
						offset = math.max(oddx, oddz) + scale*8
						layers = math.ceil( (mingap*2 - 16)/16 )
						-- layers=layers*1.33
					else
						if flexible then
							-- offset = offset - 16
							-- mingap = mingap - 16
						end
						layers = (mingap/16) * farm_spread
					end

					ExecuteMethod(method, layers + extra, 16, offset, reversed, findings) 
					-- method #3, same as method #2 but counter clockwise and starting from exterior
					if opt.useReverse then
						method = method+1
						reversed = true
						ExecuteMethod(method, layers + extra, 16, offset, reversed, findings)
					end

				until true

				local best = findings[1]
				if best and debugMethods then
					Echo('method #'..best.method,'found: ' ..best.real_n..'/'..best.n,'sep: '..best.sep, 'dist: '..best.dist,'score: '..best.score, ' => current best: '..best.method)
				end

				local strScore
				for i=2,#findings do
					local found=findings[i]
					-- strScore = strScore ..' | m'..found.method..': '.. found.score
					if found.real_n < best.real_n then
						-- skipping 
					elseif found.real_n == best.real_n then
						if found.n < best.n then
							-- skip, 'best' has more 'extra' than found
						elseif found.n      >   best.n 
							or found.score  >   best.score
							or found.sep    <   best.sep
							or found.sep   ==   best.sep and found.dist < best.dist
						then
							best = found
						end
					else
						-- if found.method == 3 and best.method == 2 or i==3 then
						-- 	Echo('METHOD 3 ACTUALLY FOUND MORE THAN METHOD 2 !')
						-- 	Echo('method #'..best.method,'found: ' ..best.real_n..'/'..best.n,'sep: '..best.sep,'dist: '..best.dist,'score: '..best.score, ' => current best: '..best.method)
						-- 	Echo('method #'..found.method,'found: ' ..found.real_n..'/'..found.n,'sep: '..found.sep,'dist: '..found.dist,'score: '..found.score, ' => current best: '..best.method)
						-- end
						best = found
					end
					if debugMethods then
						Echo('method #'..found.method,'found: ' ..found.real_n..'/'..found.n,'sep: '..found.sep,'dist: '..found.dist,'score: '..found.score, ' => current best: '..best.method)
					end
				end
				if strScore and debugEdges then
					Echo(strScore)
				end



				if best then
					if debugMethods then
						Echo('=> BEST METHOD '..best.method..' ('..#findings..' findings)', 'found '..best.n..'/'..best.n,'sep '..best.sep,'dist '..best.dist,'score: '..best.score)
					end


					UpdateMem(best.barred) -- put the currentBarred into coordsMemory
					r=a
					lasRx,lasRz = rx,rz
					if useNeat and not offposeX then
						local Prx = floor( (lasRx + mingap ) / (mingap*2) ) * (mingap*2) -- - offposeX
						local Prz = floor( (lasRz + mingap ) / (mingap*2) ) * (mingap*2)  -- - offposeZ
						offposeX = lasRx - Prx
						offposeZ = lasRz - Prz
						-- Points[#Points+1]={Prx,ry,Prz,color = color.yellow}
					end
					-- Points[#Points+1] = {rx,ry,rz,color = color.blue,txt='P'}
					rail[a].specs=best
					local rpose = {rx, sp.GetGroundHeight(rx,rz), rz}
					rail[a].rpose = rpose
					for i,v in ipairs(best) do
						if not v.extra then
							if not firstPose then
								firstPose = v
							end
							n=n+1
							v.r = r
							v.n = n
							specs[n] = v
							rail[r].color = color.green
							if opt.tryEdges and not useNeat then
								fx,fz = v[1], v[2]
								local limit = (sx + oddx + scale*8) - (scale%2) * 8
								SpiralSquare(limit/16, 16, MarkEdge, limit)
							end

							if debug then
								local x, z = v[1],v[2]
								Points[#Points+1] = {x, sp.GetGroundHeight(x,z), z, color = color.blue, txt = 'P'}
							end
						end
					end

					----- show the placements found per method as 'P' .. method in blue
					if debug or debugEdges then
						for _,found in ipairs(findings) do
							for _, p in ipairs(found) do
								local x,z =  p[1], p[2]
								Points[#Points+1] = {x,sp.GetGroundHeight(x,z),z,color = color.blue,txt='P'..found.method,size = 15}
							end
						end
					end
				end

				currentBarred={}
				extraBarred = {}
				

			end
		end
		rail.processed = rail.n
		-- Echo("rail.processed is ", rail.processed)
		specs.n = n
		return
	end
end
do
	NormalizeRail = function(expensive) -- complete rail from received mouse points
		-- Echo('#specs', )
		-- Echo("(next(specs)) is ", (next(specs)),specs[1],specs[2],f.l(specs))
		-- Echo("(next(rail)) is ", (next(rail)),rail[1],rail[2],f.l(rail))
		if not rail[2] then  return end
		local railn = rail.n
		if REMOTE then
			-- if specs[1] then
				if REMOTE[1] then
					local newprocessed = rail.processed
					for i = 1, #REMOTE do
						local add = REMOTE[i]
						local i = f.InsertWithLeastDistance(rail, add)
						add.inserted = true
						table.insert(rail, i, add)
						railn = railn + 1
						-- Echo('insert rail at',i, 'specs', #specs, os.clock(),'processed', rail.processed)

						if i == 1 then 
							i = 2 -- don't replace the very first rail
						end
						if i - 1 < newprocessed then
							newprocessed = i - 1
						end
						-- Echo('inserted at i', i, newprocessed,'.processed is', rail.processed)
					end

					if newprocessed ~= rail.processed then
						-- Echo('newprocessed', newprocessed, 'rail.processed', rail.processed)
						for i = #specs, 1, -1 do
							local s = specs[i]
							if s.r > newprocessed then
								specs[i] = nil
							else
								break
							end
						end
						rail.processed = math.max(newprocessed, 1)

						-- Echo('new processed', rail.processed)
					end
				end
				REMOTE = false
			-- end
		end

		-- Echo("rail.processed, #rail is ", rail.processed, #rail)

		local update
		local insert, remove, max, GetGround = table.insert, table.remove, math.max, sp.GetGroundHeight
		-------------------
		--local x,y,z = unpack(rail[1])
	--[[	local p = rail.processed==1 and 2 or rail.processed
		local x,y,z = unpack(rail[p-1])
		rail.processed = p-1
		local lasR = rail[p-1]
		local tries=0
		local j=p--]]
		--Echo('--->norm at ',p-1--[[, 'processed:',rail.processed--]])
		local tries=0
		local pr = rail.processed
		-- Echo('normalize from', pr + 1, 'to', railn)
		local lasR = rail[pr]

		if not lasR then
			Echo('WRONG .processed !','processed:',rail.processed,'#rail',#rail)
			local count = 0
			for i, v in pairs(rail) do
				if tonumber(i) then
					count = count + 1
					if count ~= i then
						Echo('WRONG RAIL ARRAY')
						Echo(i, count, v)
					end
				end
			end
			count = 0
			for i, s in pairs(specs) do
				if tonumber(i) then
					count = count + 1
					if count ~= i then
						Echo('WRONG SPEC ARRAY')
						Echo(i, s, count)
					end
					Echo('spec', i, "s.r is ", s.r)
				end
			end
		end
		local j = pr+1
		--Echo('normalize:', p-1,railn)
		--Echo('normalize:', rail.processed,railn)
		local oddx, oddz = p.oddX, p.oddZ
		local sx, sz = p.sizeX, p.sizeZ
		local cheapRail = opt.cheapRail
		while j <= railn do
			tries = tries+1
			local x,y,z = lasR[1], lasR[2], lasR[3]
			local railJ = rail[j]
			local jx, jy, jz =  railJ[1], railJ[2], railJ[3]
			local dirx, dirz = jx - x, jz - z
			local biggest =  max( abs(dirx), abs(dirz) )
			dirx, dirz = dirx / biggest, dirz / biggest
			local floater = p.floater
			-- insert as many points as needed between two distanced points until distance is below/equal 16 for each coord
			while (abs(x - jx) > 16 or abs(z - jz) > 16)--[[ and tries1<2--]] do
				
				tries = tries + 1
				x = x + dirx * 16
				z = z + dirz * 16
				local rx = floor((x + 8 - oddx) / 16) * 16 + oddx
				local rz = floor((z + 8 - oddz) / 16) * 16 + oddz
				local cantPlace, _, closest
				if not cheapRail then -- I think this is not needed and use up a lot of time
					cantPlace, _, closest = TestBuild(rx, rz, p, (not PBH or g.noTerra), placed, overlapped, nil, true)
					if cantPlace and closest then 
						rx, rz = PushOut(rx, rz, sx, sz, x, z, closest, p)
					end
				end
				----------------------------
				local y = GetGround(x,z)
				if  y < 0 and floater then y = 0 end
				insert(rail, j, { x, y, z, pushed = pushed, rx = rx, rz = rz, overlap = closest })
				railn = railn + 1
				j = j + 1
				if tries == 2000 then
					Echo('too many tries',j , railn, 'WRONG LOOP')
					break
				end
			end
			railJ = rail[j]
			--Echo("total tries",tries1)
			-- remove the next point if it is now too close
			if (abs( x - jx ) < 16 and abs( z - jz) < 16) then
				-- Echo('remove', j, pr, rail[j].done)
				-- if rail[j].inserted then
				-- 	Echo('insert removed at',j)
				-- end
				remove(rail,j)
				railn = railn - 1
				j = j - 1
				railJ = rail[j]
			-- the next point is at perfect distance but hasnt been updated, adding the missing keys
			elseif not railJ.rx then
				-- if rail[j].inserted then
				-- 	Echo('adding rx to inserted at ', j)
				-- end
				local rx, rz = railJ[1],railJ[3]
				local cantPlace,_,closest
				if not cheapRail then
					cantPlace, _, closest = TestBuild(rx, rz, p, (not PBH or g.noTerra), placed, overlapped, nil, true)
					if cantPlace and closest then 
						rx,rz = PushOut(rx, rz, sx, sz, x, z, closest, p)
					end
				end
				railJ.rx, railJ.rz, railJ.pushed, railJ.overlap = rx, rz, pushed, closest

			end

			lasR = railJ
			j = j + 1
			
			--Echo(lasR or 'NOT')
		end
			--Echo('normalized '..rail.n..' to '..railn)
		if prev.rail[1] ~= rail[railn][1] or prev.rail[3] ~= rail[railn][3] then
			update=true
			--Echo('update')
		end
		prev.rail = rail[railn]
		if rail.processed > railn then 
			rail.processed = railn
		end
		rail.n = railn
		-- Echo('<-- processed:', rail.processed, 'railn', rail.n)


		return update
		
	end
end
local function Init()
	if not rail[1] then return end
	local x,z = rail[1][1], rail[1][3]
	rail.processed=1
	specs:clear()
	for _, r in ipairs(rail) do r.color = nil r.done = false end
	TestBuild('forget extra')
	g.cantMex = {}
	WG.drawingPlacement = specs
	local hasOverlap = TestBuild(x,z,p,(not PBH or g.noTerra),placed,overlapped,nil,true)

	if hasOverlap and not special then
		if WG.FindPlacementAround then -- if zoomed out and PBH is active, we look for a placement around
			WG.FindPlacementAround(pointX,pointZ,placed)
			if WG.movedPlacement[1]>-1 then
				x,z = WG.movedPlacement[1],WG.movedPlacement[3]
				hasOverlap = false
			end
		end
	end
	if not hasOverlap and dstatus~='paint_farm' then
		specs[1]={x,z,r=1}
		specs.n=1

	end
	if E_SPEC[PID] then
		WG.old_showeco = WG.showeco or false
		WG.showeco = true
		WG.force_show_queue_grid = PID
	end
	if special then
		local n,newgrids,_,grids = CheckConnections(x, z, nil, PID ~= pylonDefID and opt.checkOnlyMex)
		connectedTo=Link(grids)
		allGrids={}
		for k in pairs(grids) do allGrids[k]=true end
		local status = n==0 and 'out' or 'onGrid'
		if not hasOverlap then
			specs[1].status = status
			specs[1].grids = connectedTo
			specs[1].newgrids = newgrids
			UpdateMexes(x,z,nil,1)
		else 
			rail[1].status=status
			rail[1].grids=connectedTo
		end
		NormalizeRail()
		PoseSpecialOnRail()
	else
		NormalizeRail()
		if dstatus == 'paint_farm' then 
			rail.processed=0
			Paint()
		else
			if opt.alwaysMex  and E_RADIUS[PID] then
				UpdateMexes(x,z,nil,1)
			end
			PoseOnRail()
		end
	end
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	-- Echo("cmd == CMD_FACTORY_GUARD is ", cmdID == CMD_FACTORY_GUARD, CMD_FACTORY_GUARD,cmdID)
	-- do
	-- 	local id = unitID
	-- 	local len = sp.GetCommandQueue(id, 0)
	-- 	if cmdID == 1 then
	-- 		cmdID = cmdParams[2]
	-- 		for i = 1, 3 do table.remove(cmdParams, 1) end
	-- 	end
	-- 	Echo('UC', 'cmd rec: '..cmdID, 'param: ' .. tostring(cmdParams[1]),'orders: '..len,  len > 0 and ('last order: ' .. sp.GetCommandQueue(id, -1)[len].id) or 'no order left')
	-- end
	if conTable.waitOrder and conTable.cons[unitID] then
		local waitOrder = conTable.waitOrder
		if waitOrder[1] == cmdID and table.compare(waitOrder[2], cmdParams) then -- until the last user order has not been received here, we keep the virtual queue made by multiinsert
			conTable.inserted_time = false
			conTable.waitOrder = false
		end
		-- conTable.inserted_time = false
	end
end

function widget:CommandNotify(cmd, params, options)

	-- NOTE: when using Alt, it happens the active command get reset by some widget at CommandNotify stage
	-- if shift and PID and cmd==0 and #params==0  then
	-- 	if leftClick and #specs>0 then 
	-- 		local cmd
	-- 		rmbAct, cmd = sp.GetActiveCommand()
	-- 		-- if not cmd or cmd
	-- 		dstatus = 'held'
	-- 	else 
	-- 		Spring.GiveOrderToUnitArray(getcons(),CMD.STOP, EMPTY_TABLE,EMPTY_TABLE)
	-- 	end
	-- 	sp.SetActiveCommand(0) -- cancel with S while placing multiple
	-- 	--[[Echo('stop command')--]] reset()
	-- end
end

--
-- local time=0
-- local PBS


local prevpx,prevpz=0,0

WG.PlacementModule = {PID = false} -- future global placement handler
local PlacementModule = WG.PlacementModule

do

	local cache = {}
	local offed = {}
	local methods = {}
	local mt_methods = {__index = methods}
	local mt_cache = {} -- defined when placementModule switch PID
	do
		local lastMx, lastMy
		local lastMx, lastMy, curPID
		local curx, cury, curz
		local floor = math.floor
		local mousepos = Spring.GetMouseState
		local ground = Spring.GetGroundHeight
		local UniTraceScreenRay = f.UniTraceScreenRay
		local UnitDefs = UnitDefs
		local function ToValidPosition(self, mx, my)
			if not mx then
				mx, my = mousepos()
			end
			local changed = false
			if self.PID ~= curPID then
				curPID = self.PID
				changed = true
			end
			if lastMx ~= mx or lastMy ~= my then
				lastMx, lastMy = mx, my
				changed = true
			end
			if changed then
				local x, y, z = UniTraceScreenRay(mx, my, useMinimap, self.underSea, self.sizeX, self.sizeZ)
				if not x then
					return
				end
				local oddX, oddZ = self.oddX, self.oddZ
				curx = floor((x + 8 - oddX)/16)*16 + oddX
				curz = floor((z + 8 - oddZ)/16)*16 + oddZ
				cury = ground(curx, curz)
			end

			return curx, cury, curz

		end
		methods.ToValidPosition = ToValidPosition

	end
	local spuGetMoveType = Spring.Utilities.getMovetype
	local function newcache(PID)
		local t = {}
		local def = UnitDefs[PID]
		local footX, footZ = def.xsize/2, def.zsize/2
		local offfacing = false
		local sizeX, sizeZ = footX * 8, footZ * 8 
		local oddX,oddZ = (footX%2)*8, (footZ%2)*8
		local canSub = CheckCanSub(def.name)
		--[[
			Note:
			-floatOnWater is only correct for buildings (at the notable exception of turretgauss) and flying units
			-canMove and isBuilding are unreliable:
			   staticjammer, staticshield, staticradar, factories... have 'canMove'
			   staticcon, striderhub doesn't have... 'isBuilding'
			-isGroundUnit is reliable
			-spuGetMoveType is better as it discern also between flying (1) and building (false)
			-def.maxWaterDepth is only correct for telling us if a non floating building can be a valid build undersea
			-def.moveDef.depth is always correct about units except for hover
			-def.moveDef.depthMod is 100% reliable for telling if non flying unit can be built under sea, on float or only on shallow water:
			   no depthMod = flying or building,
			   0 = walking unit undersea,
			   0.1 = sub, ship or hover,
			   0.02 = walking unit only on shallow water
		--]]
		local isUnit = spuGetMoveType(def) -- 1 == flying, 2 == on ground/water false = building
		local depthMod = isUnit and def.moveDef.depthMod
		local floatOnWater = def.floatOnWater
		local gridAboveWater = floatOnWater or isUnit -- that's what the engine relate to, with a position based on trace screen ray that has floatOnWater only, which offset the grid for units
		local underSea = depthMod == 0 or not (isUnit or floatOnWater or def.maxWaterDepth == 0)
		local reallyFloat = isUnit == 2 and depthMod == 0.1 or floatOnWater and def.name ~= 'turretgauss'
		local cantPlaceOnWater = not (underSea or reallyFloat)
		t.footX				= footX
		t.footZ				= footZ
		t.oddX				= oddX
		t.oddZ				= oddZ
		t.sizeX				= sizeX
		t.sizeZ				= sizeZ
		t.terraSizeX		= sizeX-0.1
		t.terraSizeZ		= sizeZ-0.1
		t.offfacing			= false
		t.canSub			= canSub
		t.floater			= def.floatOnWater or not canSub
		t.needTerraOnWater	= not canSub and not def.name:match('hover')
		t.underSea			= underSea
		t.reallyFloat		= reallyFloat
		t.cantPlaceOnWater	= cantPlaceOnWater
		t.gridAboveWater	= gridAboveWater -- following the wrong engine grid 
		t.floatOnWater		= floatOnWater
		f.facing 			= 0
		t.height			= def.height
		t.name				= def.name
		t.PID				= PID
		t.eradius			= E_RADIUS[PID]
		t.radiusSq			= def.name == "energypylon" and 3877 or (def.radius^2)
		t.radius			= def.radius

		if footX ~= footZ then
			local off = {}
			offed[PID] = off

			off.footX, 		off.footZ		= footZ,		footX
			off.oddX,  		off.oddZ		= oddZ,  		oddX
			off.sizeX, 		off.sizeZ		= sizeZ, 		sizeX
			off.terraSizeX, off.terraSizeZ	= sizeZ-0.1,	sizeX-0.1
			off.offfacing 	= true
			off.facing 		= 1
			setmetatable(off, {__index = t})
		end
		cache[PID] = setmetatable(t, mt_methods)
		return t
	end
	function PlacementModule:Measure(PID, facing)
		local isSelf = false
		if not PID then 
			isSelf = true
			PID, facing = self.PID, self.facing
			if not PID then
				return
			end
		end
		facing = facing or sp.GetBuildFacing()
		local cached = cache[PID] or newcache(PID)

		if facing == 1 or facing == 3 then
			cached = offed[PID] or cached
		end
		-- Echo("measure", 'isSelf', isSelf, " facing is ", facing,'is Off:', cached == offed[PID],'sx, sz', cached.sizeX, cached.sizeZ, cached.terraSizeX, cached.terraSizeZ)
		if isSelf then
			mt_cache.__index = cached
			setmetatable(self, mt_cache)
			-- Echo("self:ToValidPosition() is ", self:ToValidPosition())

			return self
		end
		cached.facing = facing
		return cached
	end
end
function PlacementModule:Update()

	local _, PID = sp.GetActiveCommand()
	if PID then
		if PID > -1 then
			PID = false
		else
			PID = -PID
			if factoryDefID[PID] and plate_placer then
				plate_placer:Update()
				_, PID = sp.GetActiveCommand()
				if PID then PID = -PID end
			end
		end
	end

	if not Drawing or PID then
		local reMeasure
		if PID then
			if self.PID ~= PID then
				-- Echo('PID changed', math.round(os.clock()))
				if Drawing then
					return
				end
				reMeasure = true
				self:UpdateSpacing()
				-- self.PID,self.lastPID = PID,self.PID or PID
				self.PID, self.lastPID = PID, PID
				-- WG.force_show_queue_grid = not not E_SPEC[PID]
				WG.force_show_queue_grid = PID
			end
			local facing = sp.GetBuildFacing()
			if facing and facing ~= self.facing then
				reMeasure, self.facing = true, facing
			end
		else
			PID = false
		end
		self.PID = PID
		if reMeasure then 
			-- Echo('remeasure', os.clock())
			self:Measure()
		end
	end
end
do
	local spGetCmdDescIndex = Spring.GetCmdDescIndex
	function PlacementModule:RecoverPID()
		local lastPID = self.lastPID
		if not lastPID then
			return
		end
		if E_SPEC[lastPID] then
			WG.force_show_queue_grid = lastPID
		end
		local _,com,_,comname = sp.GetActiveCommand()
		-- local com = select(2, sp.GetActiveCommand())
		if select(2, sp.GetActiveCommand()) ~= -lastPID then
			if com then
				Echo('!!comname is ',comname,com, 'last pid is', lastPID )
			end
			local cmdIndex = lastPID and spGetCmdDescIndex(-lastPID)
			return cmdIndex and sp.SetActiveCommand(cmdIndex)
		end
	end
end
function PlacementModule:UpdateSpacing(value)
	local spacing = sp.GetBuildSpacing()
	if ctrl and opt.ctrlBehaviour == 'no_spacing' then
		spacing = 0
		special = false
	else
		spacing = math.max(spacing + (value or 0), 0)
		special = E_SPEC[PID] and spacing >= 7 and dstatus ~= 'paint_farm'
		if special then
			spacing = 7
		end
		if value and dstatus ~= 'paint_farm' then
			Spring.SetBuildSpacing(spacing)
			if PID then
				WG.buildSpacing[PID] = spacing
			else
				Echo('NO PID ???', debug.traceback())
			end
		end
	end
	if self.spacing ~= spacing then 
		self.spacing = spacing
		return true
	end
end
function PlacementModule:GetRealSurround(x, z)
	if Cam.relDist > 2500 then
		return false
	end
	-- if we really want the real surround it would need to check every order of every units, we only check selected cons order
	local overlap = EraseOverlap(x, z, true, true)
	if overlap then
		return true
	end
	local under = WG.PreSelection_GetUnitUnderCursor()
	if under then
		local ux, uy, uz = sp.GetUnitPosition(under)
		local gy = sp.GetGroundHeight(ux,uz)
		if uy > gy + 30 then
			return false
		end
		return true
		----- not needed
		-- local defID = sp.GetUnitDefID(under)
		-- if not defID then
		-- 	return false
		-- end
		-- local def = UnitDefs[defID]
		-- local facing = def.isImmobile and Spring.GetUnitBuildFacing(under) or 0
		-- local usx, usz = def.xsize * 4, def.zsize * 4
		-- if facing%2 == 1 then
		-- 	usx, usz = usz, usx
		-- end
		-- if (x-ux)^2 < usx^2 and (z-uz)^2 < usz^2 then
		-- 	return true
		-- end
	end
	return false
end



local Controls ={}


p = PlacementModule
WG.PlacementModule = PlacementModule

local function FinishDrawing(fixedMex, mods)
	alt, ctrl, meta, shift = sp.GetModKeyState()

	if dstatus == 'paint_farm' then
		if specs[1] then
			SendCommand(PID, mods)
		end
		reset()
		Drawing = false
		WG.drawingPlacement = false
		p:RecoverPID()
		dstatus = 'engaged'
		return
	elseif dstatus == 'engaged' then
		-- finish correctly, ordering
		-- Echo("#specs is ", #specs, os.clock())
		if shift then
			p:RecoverPID()
		else
			dstatus ='none'
		end
		-- if Debug and WG.PBHisListening then Echo('DP release and catch PBH') end
		if specs[1] then
			SendCommand(PID, mods)
			-- NOTE: when using Alt, it happens the active command get reset by some widget at CommandNotify stage
			-- so we redo it
			if alt  and shift then
				p:RecoverPID()
			end
		elseif (not prev.pos or prev.pos[1] == pointX and prev.pos[3] == pointZ) then
			if not opt.enableEraser and (Cam.relDist or  GetCameraHeight(sp.GetCameraState())) < 1000 then -- zoomed in enough, we allow erasing placement
				EraseOverlap(pointX,pointZ)
			elseif WG.FindPlacementAround then -- if zoomed out and PBH is active, we look for a placement around
				if not pointX then
					Echo('Error in Draw Placement Finish Drawing, no pointX !')
				elseif not fixedMex and PID ~= geos.defID then
					WG.FindPlacementAround(pointX, pointZ, placed)
					if WG.movedPlacement[1] >- 1 then
						specs[1] = {WG.movedPlacement[1], WG.movedPlacement[3]}
						specs.n = 1
						SendCommand(PID, mods)
					end
				end
			end
		end
		reset(true)
		Drawing = false
		WG.drawingPlacement = false
		-- Echo("prev.pos[1],pos[1] is ", prev.pos[1],pointX)
		-- if specs[1] then EraseOverlap(specs[1][1],specs[1][3]) end
		-- if (PID~=mexDefID) then dstatus = 'none' end
		return
	end
end

local UpdateRail = function()
	if rail[2] then
		g.previMex={}
		local update = NormalizeRail() -- this will complete and normalize the rail by separating/creating each point by 16, no matter the speed of the mouse
		if update then
			NormalizeRail()
			if special then
				PoseSpecialOnRail()
			elseif dstatus == 'paint_farm' then
				Paint()
			else
				PoseOnRail()
			end
		end
	end
end

function ToggleDraw()
	if PID then 
		noDraw[PID] = not noDraw[PID]
	end
	Drawing = not noDraw[PID]
	-- WG.drawingPlacement=Drawing

	reset()
	drawEnabled = false
	if leftClick then 
		sp.SetActiveCommand(-1)
		dstatus = 'held'
	end
end


function widget:Update()
	if dstatus == 'erasing' then
		-- EraseOverlap()
		sp.SetMouseCursor(CURSOR_ERASE_NAME)
		return
	end

end
function widget:IsAbove(x, y)	-- previously Update
	local dt = 0

	-- if cons[1] then
	-- 	local id = cons[1]
	-- 	local len = sp.GetCommandQueue(id, 0)
	-- 	Echo( len > 0 and sp.GetCommandQueue(id, -1)[len].id or 'no order left')
	-- end
	local wasLeftClick, wasRightClick = leftClick, rightClick

	mx, my, leftClick, _, rightClick = sp.GetMouseState()
	alt, ctrl, meta, shift = sp.GetModKeyState()
	if dstatus == 'verif_!R_or_place' then
		dstatus = 'engaged'
		FinishDrawing(PID == mexDefID and GetCloseMex, MODS)
		MODS = false
	end

	-- old
	-- if dstatus == 'engaged' and not (leftClick or rightClick) then
	-- 	reset(true)
	-- end
	--
	-- new -- fix the repeatition
	if dstatus == 'engaged' and (not leftClick and wasLeftClick or not rightClick and wasRightClick) then
		reset(true)
	end
	--

	-- Echo("WG.myPlatforms.x is ", WG.myPlatforms.x)
	if UPDATE_RAIL then
		UPDATE_RAIL = false
		UpdateRail()
	end
	-- time = time+dt
	if mexToAreaMex == 'back' and wasLeftClick and not leftClick then
		-- sp.SetActiveCommand('buildunit_staticmex')
		mexToAreaMex = 'alt'
	end
	p:Update()
--Page(p)
	PID = p.PID
	drawEnabled = PID and not noDraw[PID]
	WG.drawEnabled = drawEnabled
	special = drawEnabled and E_SPEC[PID] and dstatus ~= 'paint_farm' and p.spacing >= 7
	if g.preGame then
		if Spring.GetGameFrame() > 0 and not WG.InitialQueue then
			g.preGame = false
			g.transition = true
		end
	end

	if PID and dstatus == 'none' then
		dstatus = 'ready'
	end

	if VERIF_SHIFT then
		VERIF_SHIFT.page = VERIF_SHIFT.page + 1
		local time = Spring.DiffTimers(Spring.GetTimer(), VERIF_SHIFT.timer)
		if time > 0.1 and VERIF_SHIFT.page > 2 or not leftClick then
			-- Echo('too late',time > 0.1, VERIF_SHIFT.page > 2, not select(3,sp.GetMouseState()))
			VERIF_SHIFT = false
		elseif shift then
			if not widgetHandler.mouseOwner or widgetHandler.mouseOwner.GetInfo().name == 'Persistent Build Height 2' then
				local _mx, _my = VERIF_SHIFT[1], VERIF_SHIFT[2]
				VERIF_SHIFT = false
				widgetHandler.mouseOwner = nil
				Spring.WarpMouse(_mx,_my)
				Spring.SendCommands('mouse1')
				Spring.WarpMouse(mx + (mx - _mx) * 1, my + (my - _my) * 1)
				-- Spring.WarpMouse(mx,my)
				return widget:IsAbove(dt)
				-- Echo('ok')
			else
				-- Echo('cancel')
				VERIF_SHIFT = false

			end
			return			
		end
	end

	-- if dstatus:match'held' then
	-- 	if dstatus:match'!R' and not rightClick then Echo('CHECK')  dstatus = 'rollback' end -- meanwhile Drawing, rightClick press cancelled the Drawing, PID is recovered after rightClick is released
	-- end
	-- if dstatus == 'rollback' and not leftClick then
	-- end
	--if  and not leftClick and not shift then reset()  end
	if dstatus == 'held_!R' and not rightClick then
		dstatus = 'rollbackL'
	end
	if dstatus == 'rollbackL' then -- waiting to roll back the PID 
		if not leftClick then
			-- Echo("2 widgetHandler.mouseOwner is ", widgetHandler.mouseOwner)
			p:RecoverPID()
			dstatus = 'engaged'
			reset()
			return widget:IsAbove(dt)
		end
		return
	end
	if dstatus == 'rollbackR' then -- waiting to roll back the PID 
		if not rightClick then
			-- Echo("2 widgetHandler.mouseOwner is ", widgetHandler.mouseOwner)
			p:RecoverPID()
			dstatus = 'engaged'
			reset()
			return widget:IsAbove(dt)
		end
		return
	end

	if dstatus == 'engaged' then
		if rightClick  then
			dstatus = 'held_!R'
			local aCom = select(2, sp.GetActiveCommand())
			if -(aCom or 0) == p.PID then
				sp.SetActiveCommand(0)
			end
			WG.force_show_queue_grid = true
			reset()
			return
		end
	end

	if not PID and dstatus~='erasing' then
		if dstatus == 'ready' or dstatus == 'engaged' then
			dstatus = 'none'
		else
			return
		end
	end
	if dstatus == 'engaged' and not (shift or leftClick) then
		if not Drawing and PID==mexDefID then
				dstatus = 'none'
		--if PID==mexDefID and not shift then sp.SetActiveCommand(-1) end
		elseif not (ctrl or specs[1]) then
			dstatus = 'none'
		end
	end

	if dstatus == 'none' then
		local aCom = select(2,sp.GetActiveCommand())
		if -(aCom or 0) == p.PID then
			if not widgetHandler.mouseOwner then
				sp.SetActiveCommand(-1)
				reset(true)
				return
			end
		end
		reset(true)
		return
	end


	if not leftClick then
		useMinimap = sp.IsAboveMiniMap(mx, my)
	elseif useMinimap then
		mx, my = ClampMouseToMinimap(mx, my)
	end
	local _x, _y, _z, _offMap = UniTraceScreenRay(mx, my, useMinimap, p.underSea, p.sizeX, p.sizeZ)
	if not _x then
		return
	end
	pos = {_x, _y ,_z, offMap}
	if PID == mexDefID and opt.grabMexes and GetCloseMex then
		CalcGrabRadius()
	end


	if Drawing then --

		 -- don't use/show the engine build command, handle it ourself
		if sp.GetActiveCommand()>0 then 
			sp.SetActiveCommand(0)
		end
	end



	if dstatus == 'erasing' then
		-- EraseOverlap()
		-- sp.SetMouseCursor(CURSOR_ERASE_NAME)
		return
	end

	-- if Drawing and rightClick and dstatus~='paint_farm' then dstatus = 'held_!R' sp.SetActiveCommand(0) reset() end -- reset but will recover PID on rightClick release


--[[	warpBack = warpBack  or drawEnabled and not shift and "ready" -- getting back to position if shift got released then rehold

	washold = washold or hold--]]


--[[	if hold then
		widgetHandler:RemoveWidgetCallIn("DrawWorld", self)
		return
	end--]]


	if PID==geos.defID then
		local geoX,geoY,geoZ = sp.ClosestBuildPos(0,PID, pos[1], 0, pos[3], 500 ,0 ,0)
		if geoX >- 1 then
			local thisgeo = geos.map[geoX] and geos.map[geoX][geoZ]
			if not geos.cant[thisgeo] then
				pos = {geoX,geoY,geoZ}
			end
		end
	end
	if Drawing then
		if g.transition then -- transition while drawing and the game start, we do not have yet the 
			if cons[1] then
				g.transition = false
			else
				return
			end
		elseif not ( g.preGame or (cons[1] and sp.ValidUnitID(cons[1])) ) then
			reset()
			drawEnabled=false
			return
		end

		if special then
			UpdateMexes(pos[1], pos[3], nil, nil, 'virtual') 
		elseif g.previMex[1] then
			g.previMex = {}
		end
	end

--[[if not leftClick and PID then
tick[1],a,b,c,d,e = allow(tick[1],1,Continue, DefineBlocks, "Define")

else End("Define")
end
--]]

	------------------------------
	if not Drawing then return end
	------------------------------
	if dstatus == 'paint_farm' then return end
	----------------------
	-- if leftClick then  sp.SetActiveCommand(-1) end
	if p:UpdateSpacing() then
		Init()
	end
end

function widget:KeyRelease(key, mods)
	local newalt, newctrl, newmeta, newshift = mods.alt, mods.ctrl, mods.meta, mods.shift
	local shiftRelease = shift and not newshift
	local ctrlRelease = ctrl and not newctrl
	alt, ctrl, meta, shift = newalt, newctrl, newmeta, newshift
	-- local _alt, _ctrl, _meta, _shift = sp.GetModKeyState()
	-- if shift ~= _shift then
	-- 	Echo('in PBH2 modkey differs from key release !',shift, _shift)
	-- end
	-- if waitReleaseShift and not shift then sp.SetActiveCommand(0) waitReleaseShift=false end
	if Drawing and shift and PID then
		GoStraight(alt)
	end

	if (dstatus == 'engaged' or dstatus == 'erasing')
		and not (shift or ctrl)
		and (shiftRelease or ctrlRelease)
		and not specs[1] then
		dstatus = 'none'

		-- happens when laggy, another PID got get by the user but controls didnt got time to update
		-- restricting more the leave of the command
		-- if PID and -PID == select(2, sp.GetActiveCommand()) then
			sp.SetActiveCommand(-1)
		-- end
		reset(true)
		PID = false
		return
	end

	if specs[1] and shift and alt and not special and dstatus ~= 'paint_farm' then PoseOnRail() end --  also key 308=LALT
end

local function ChangeSpacing(value)
	if Drawing then
		if p:UpdateSpacing(value) then
			Init()
		end
		return true
	end
	return false
end


function widget:MouseWheel(up,value) -- verify behaviour of keypress on spacing change
	if ctrl then
		if PID --[[and p.sizeX==p.sizeZ--]] then
			local isPainting = dstatus == 'paint_farm'
			local modifyPainting = shift
			if modifyPainting then
				if not (PID == mexDefID and GetCloseMex) then
					local changed
					local modifySpread = alt
					if modifySpread then
						local spread = FARM_SPREAD[PID] or 1
						spread = up and min(spread + 1,5) or max(spread - 1,1)
						changed = spread ~= (FARM_SPREAD[PID] or 1)
						FARM_SPREAD[PID] = spread ~= 1 and spread or nil
						farm_spread = spread
					else
						local scale = FARM_SCALE[PID] or 0
						scale = up and min(scale + 1, MAX_SCALE[PID] or 5) or max(scale - 1,0)
						changed = scale ~= (FARM_SCALE[PID] or 0)
						FARM_SCALE[PID] = scale ~= 0 and scale or nil
						farm_scale=scale
					end
					if isPainting and changed then
						Paint('reset')
						Init()
					end
				end
				return true
			end
		end
	elseif shift and Drawing and PID then
		if (PBS and PBS.options.wheel_spacing and PBS.options.wheel_spacing.value) then
			return ChangeSpacing(value)
		end
	end
end

-- function Spring.GetUnitsInCircle(r,mx,my)
-- 	if not mx then
-- 		mx, my = Spring.GetMouseState()
-- 	end
-- 	local corners = {}
-- 	for i = -1, 1, 2 do
-- 		local where, pos = Spring.TraceScreenRay(mx + i * r, my + i * r,true,true,true,false)
-- 		if where == 'sky' then
-- 			pos[1], pos[2], pos[3] = pos[4], pos[5], pos[6]
-- 		end
-- 		Points[#Points+1] = {pos[1], pos[2], pos[3],size = 50}
-- 		corners[i] = pos
-- 	end
-- 	if corners[-1][1] > corners[1][1] then
-- 		corners[1][1], corners[-1][1] = corners[-1][1], corners[1][1]
-- 	end
-- 	if corners[-1][3] > corners[1][3] then
-- 		corners[1][3], corners[-1][3] = corners[-1][3], corners[1][3]
-- 	end

-- 	local left, 		  bottom,			right, 			  top 
-- 		= corners[-1][1], corners[-1][3], corners[1][1], corners[1][3] 
-- 		-- Echo("left,bottom,right,top is ", left,bottom,right,top)
-- 		Echo(" is ", #Spring.GetUnitsInRectangle(left,bottom,right,top))
-- 	for i, id in ipairs(Spring.GetUnitsInRectangle(left,bottom,right,top)) do
-- 		local ux,uy,uz = Spring.GetUnitPosition(id)
-- 		Points[#Points+1] = {ux,uy,uz,txt = 'o',size = 15}
-- 	end

-- end



function widget:KeyPress(key, mods,isRepeat)
	local wasCtrl = ctrl
	alt, ctrl, meta, shift = mods.alt, mods.ctrl, mods.meta, mods.shift
	-- Echo("special, ctrl, opt.ctrlBehaviour is ", special, ctrl, opt.ctrlBehaviour)
	local inc, dec = key == spacingIncrease, key == spacingDecrease
	if (inc or dec) then
		if ChangeSpacing(inc and 1 or -1) then
			return true
		end
		-- if Drawing then
		-- 	return true
		-- else
			return
		-- end
	end
	-- toggling special treatment for solar/wind/pylons or back to normal 



	-- if Drawing and shift and key==308 then
		--pushRail=not pushRail
		--rail=deepcopy(primRail)
	-- end
	if Drawing and PID and shift then
		GoStraight(alt)
	end
	-- if Drawing then 
	-- 	return true
	-- end

end

-- function widget:IsAbove(x, y)
-- 	if y > 740 then
-- 		Echo('got it', WG.Chili.Screen0.hoveredControl)
-- 	elseif WG.Chili.Screen0.hoveredControl then
-- 		Echo('detected', WG.Chili.Screen0.hoveredControl,y)
-- 	end
-- 	-- Echo("WG.Chili.Screen0.hoveredControl is ", WG.Chili.Screen0.hoveredControl)
-- end
function widget:MousePress(mx, my, button)
	alt, ctrl, meta, shift = sp.GetModKeyState()
	--
	if button == 2 then return end
	--
	if dstatus == 'verif_!R_or_place' then
		if button == 3 then 
			reset(true)
			dstatus = 'rollbackR'
			return true
		elseif button == 1 then
			-- in case of big lag, the Update didnt occur, we provoke it
			widget:IsAbove(0)
		end
		MODS = false
	end
	if dstatus == 'ready' then
		if PID == mexDefID and button == 1 and not shift and opt.mexToAreaMex then
			if not WG.Chili.Screen0.hoveredControl then
				reset(true)
				sp.SetActiveCommand('areamex')
				mexToAreaMex = 'back'
				-- ordered = true
			end
			return
		end

	elseif dstatus == 'rollbackL' and button == 3
	or dstatus == 'rollbackR' and button == 1 then
		return true -- block the mouse until the rollback occur

	elseif (dstatus =='paint_farm' or dstatus == 'erasing') then
		if button == 1 then
			dstatus ='held_!L'
			sp.SetActiveCommand(0)
			WG.force_show_queue_grid = true
			reset() 
			return true
		end
	elseif dstatus == 'engaged' then
		if button == 3 and Drawing then
			dstatus = 'held_!R'
			local aCom = select(2,sp.GetActiveCommand())
			if -(aCom or 0) == p.PID then
				sp.SetActiveCommand(0)
			end
			WG.force_show_queue_grid = true
			reset()
			return true
		end
	end

	if shift and not PID and (select(2,sp.GetActiveCommand()) or 0) < 0 then
		widget:IsAbove(0)
		Echo('didnt have PID, now ?',PID,os.clock())
		Spring.PlaySoundFile(LUAUI_DIRNAME .. 'Sounds/buildbar_add.wav', 0.95, 'ui')
		if not PID then
			return
		end
	end
	-- if button==1 and WG.Chili.Screen0.hoveredControl then
	-- 	return
	-- end
	if button == 1 and PID then
		if ctrl and shift and (PID ~= mexDefID or not CloseMex) then -- surround
			-- use the normal engine building system when ctrl and shift are pressed and some conditions are met
			if not opt.disallowSurround	then
				if WG.PlacementModule:GetRealSurround(pos[1], pos[3]) then
					dstatus = 'engaged'
					return
				end
			end
			if opt.ctrlBehaviour == 'engine' then
				dstatus = 'engaged'
				return
			end				
		elseif not shift then
			-- dstatus = 'wait1'
			dstatus = 'engaged'
			VERIF_SHIFT = opt.late_shift and {mx,my, page = 0, timer=Spring.GetTimer()}
			return
		end
	end
	-- if button==1 and meta and not (shift or ctrl) and PID then dstatus = 'engaged' return end
	local x, y, z
	if shift and PID then
		if dstatus == "ready" and PBH then
			PBH.Process(mx,my) -- if user moved the cursor fast, PBH didnt scan for moved placement (etc...) at the current position
		end
		if button == 3 and not Drawing then
			if ctrl then
				if p.sx == p.sz  then -- paint_farm has not rectangular build implemented yet
					if PID == mexDefID and GetCloseMex then
						-- skip
					else
						dstatus = "paint_farm"
						if WG.DrawTerra and WG.DrawTerra.working then
							WG.DrawTerra.finish = true
						end
						farm_spread = FARM_SPREAD[PID] or 1
						farm_scale = FARM_SCALE[PID] or 0
						Points={}
					end
				end
			elseif dstatus == 'ready' or dstatus == 'engaged' and opt.enableEraser then
				dstatus = 'erasing'
				sp.SetActiveCommand(0)
				WG.force_show_queue_grid = true
				EraseOverlap()
				return true
			end
		end
		useMinimap = sp.IsAboveMiniMap(mx, my)
		x, y, z = UniTraceScreenRay(mx, my, useMinimap, p.underSea, p.sizeX, p.sizeZ)
		if not x then
			return
		end
		prev.firstmx, prev.firstmy = mx, my
		-- x,y,z = unpack(pos)
		x = floor((x + 8 - p.oddX)/16)*16 + p.oddX
		z = floor((z + 8 - p.oddZ)/16)*16 + p.oddZ
		local myPlatforms = WG.myPlatforms
		-- Echo("myPlatforms is ", myPlatforms and myPlatforms.x)
		pointX, pointZ = x, z
		if myPlatforms and  myPlatforms.x then
			x = myPlatforms.x
			z = myPlatforms.z
		end
		if button == 3 and not Drawing then
			if dstatus == "paint_farm" then
				special = false
				Drawing = true
				WG.drawingPlacement=specs
				placed = GetPlacements()
				local r = {x,y,z,rx=x,rz=z}
				rail={r,n=1,processed=1}
				Init()
				prev.rail = rail[1]
				prev.mx = mx
				prev.my = my
				return true, widget:IsAbove(--[[Spring.GetLastUpdateSeconds()--]])
			elseif dstatus == 'erasing' then
				EraseOverlap(x,z)
				-- Spring.SetMouseCursor(CURSOR_ERASE_NAME)
			end
			return true
		elseif drawEnabled and button == 1 then
			-- Echo('there',os.clock())
			if GetCloseMex then
				g.closeMex[1],g.closeMex[2] = GetCloseMex(x,z)
			end
			--x,z = AvoidMex(x,z)

			--local x,y,z = pointToGrid(16,x,z)
	--		cons = GetCons()
			p:UpdateSpacing()
			--places,blockIndexes=DefineBlocks()

	--[[		if getaround then
				map,Rects,places = WG.DefineBlocksNew(PID)
			end--]]

		--places,blockIndexes=DefineBlocks()
			Drawing = true
			WG.drawingPlacement = specs
			dstatus = 'engaged'
			placed = GetPlacements()
			--x,y,z=sp.ClosestBuildPos(0,PID, x, y, z, 1000,0,p.facing)
	--[[		if GetCameraHeight(sp.GetCameraState())<5500 and EraseOverlap(x,z) then -- allow erasing only if not zoommed out too far
				local acom = sp.GetActiveCommand()
				reset() return true
			else--]]
				if WG.movedPlacement and WG.movedPlacement[1]>-1 then
					x,y,z = unpack(WG.movedPlacement)
				end
				local r = {x, y, z, rx = x, rz = z}
				rail = {r, n = 1, processed = 1}
				primRail = {r, n = 1}	
				prev.dist_drawn = 0
				prev.press_time = os.clock()
				if PID == mexDefID and GetCloseMex --[[and not g.preGame--]] then
					local spot = GetCloseMex(x,z)
					if spot and not g.cantMex[spot] then
						g.cantMex[spot] = true
						if (alt or ctrl) or IsMexable(spot, true) then -- finally allow already mexed spot to be completed
							specs[1] = {spot.x, spot.z, r = 1}
							specs.n = 1
						end
					end
				elseif PID == geos.defID then
					geos:BarOccupied()
					local geoX,geoZ = geos:Update(x,z)
					if geoX then 
						specs[1] = {geoX,geoZ,r=1}
						specs.n = 1
					end
				else
					Init()
				end
			--end
			prev.rail = rail[1]
			prev.mx = mx
			prev.my = my

			return true, widget:IsAbove(Spring.GetLastUpdateSeconds())
		end
	end
end
function WidgetInitNotify (w, name, preloading)
	if name == 'Persistent Build Height 2' then
		PBH = w
	elseif name == 'Factory Plate Placer' or name == 'Factory Plate Placer2' then
		plate_placer = w
	elseif name == 'Selection Modkeys' then
		SM_enable_opt = w.options.enable
		do
			local isEnabled
			switchSM = function(backup) 
				if backup then 
					if isEnabled then
						SM_enable_opt.value = true
					end
				else
					isEnabled = SM_enable_opt.value
					if isEnabled then
						SM_enable_opt.value = false
					end

				end
			end
		end
	elseif name == 'Persistent Build Spacing' then
		PBS = w
	end

end
function WidgetRemoveNotify(w, name, preloading)
	if name == 'Persistent Build Height 2' then
		PBH = false
	elseif name == 'Factory Plate Placer' or name == 'Factory Plate Placer2' then
		plate_placer = nil
	elseif name == 'Selection Modkeys' then
		switchSM = function() end
	elseif name == 'Persistent Build Spacing' then
		PBS = nil
	end
end



function widget:MouseRelease(mx,my,button)
	-- Echo('Total tries', TRIED)
	TRIED = 0
	MODS = false
	alt, ctrl, meta, shift = sp.GetModKeyState()
	-- Echo("alt, ctrl, shift is ", alt, ctrl, shift)
	if shift  then -- prevent from selecting unit when releasing left button above unit while shift is held
		switchSM()
	end
	local _,_,lb,_,rb = sp.GetMouseState()
	if dstatus == 'held_!R' then
		if button == 3 then 
			dstatus = 'rollbackL'
			-- Echo("widgetHandler.mouseOwner is ", widgetHandler.mouseOwner)
		elseif button == 1 then
			if shift then
				dstatus = 'engaged'
				p:RecoverPID()
			else
				dstatus = 'none'
				reset(true)
			end
		end
		widgetHandler.mouseOwner = nil -- disown the mouse after a leftClick + rightClick then release rightClick
	elseif dstatus == 'held_!L' then
		if button == 1 then 
			dstatus = 'rollbackR'
			-- Echo("widgetHandler.mouseOwner is ", widgetHandler.mouseOwner)
		elseif button == 3 then
			dstatus = 'none'
			reset(true)
		end
		widgetHandler.mouseOwner = nil -- disown the mouse after a leftClick + rightClick then release rightClick
		return true
	elseif dstatus == 'erasing' and button == 3 then
		if shift then
			dstatus = 'engaged'
			p:RecoverPID()
		else
			dstatus = 'none'
			reset(true)
		end
		return true
	elseif Drawing then
		local fixedMetalSpot = PID == mexDefID and WG.metalSpots
		local dist_drawn = prev.dist_drawn
		if prev.pos and prev.mx ~= mx and prev.my ~= my then
			dist_drawn = dist_drawn + ((prev.mx - mx)^2 + (prev.my - my)^2) ^ 0.5
		end
		if dstatus ~= 'paint_farm' and not (fixedMetalSpot or PID == geos.defID) and (prev.dist_drawn<=8 or os.clock()-prev.press_time<0.08) then
			while specs[2] do
				table.remove(specs)
			end
			specs.n = 1
		elseif not fixedMetalSpot then
			widget:MouseMove(mx, my, 0, 0, button) -- try to complete the rail before finishing
			if not opt.update_rail_MM then
				UpdateRail()
			end
		end
		dstatus = 'verif_!R_or_place' -- due to lag it can happen the user simulatneously right click and release left click to cancel the build, release left click would then comes first wrongly
		MODS = {alt, ctrl, meta, shift}
		-- FinishDrawing(fixedMetalSpot)
	end
	return true, switchSM(true)
end
local function UpdateBasicRail(pos,rail) -- unused -- not working
	if not pos then return end
	local newx,newz = pos[1], pos[3]
	local railLen = #rail
	local lasR = rail[railLen]
	local gapx,gapz
	if lasR then
--			gapx = abs( pointX - newx ) or 10000
--			gapz = abs( pointZ - newz ) or 10000
		gapx = abs( lasR[1] - newx ) or 10000
		gapz = abs( lasR[3] - newz ) or 10000
		if gapx<16 and gapz<16 then
			return
		end
	end
	pointX, pointZ = newx, newz
	local px,py,pz = pos[1], pos[2], pos[3]
	railLen = railLen+1
	rail[railLen]={px,py,pz} -- depending on mouse speed points will not be evenly positionned, but we will use them to fill the blanks and normalize their distance
	rail.n = railLen

	return true
end
local OrderPointsByProximity2 = function(points,startPoint) -- reorder table to get each one next to each other
	local i, n = 0, #points
	local current, nextp = startPoint
	-- each points is compared to all the others, then we move forward, maybe it could be handled better to avoid that many iterations (hungarian method?)
	while i < n do
		local j = i + 1
		 -- we assume the closest is the next point, and update the index c if we find a closest one
		nextp = points[j]
		closest, c = nextp, j
		local x, z = current[1], current[2]
		local dist = ((x - closest[1])^2 + (z - closest[2])^2) -- this is not the real distance to avoid doing one more operation, but the end goal is achieved, real dist would need to be the square root of this

		-- Echo('for i', i+1,'current closest',j, 'at', x,z)
		while j < n do
			j = j + 1
			local compared = points[j]
			local newdist = ((x - compared[1])^2 + (z - compared[2])^2)
			if newdist < dist then
				-- Echo('for i', i+1,'new closest',j,'at', x,z)
				closest, dist, c = compared, newdist, j
			end
		end
		-- we switch elements of the table: next i become the closest, index of closest receive the element that was in next i
		i = i + 1
		if i ~= c then
			-- Echo('point['..c..'] => point['..i..']')
			points[i], points[c] = closest, nextp 
		end
		current = closest
	end
end
local OrderPointsByLeastDistance = function(points,startPoint) -- reorder table to get each one next to each other
	local i, n = 0, #points
	local current, nextp = startPoint
	-- each points is compared to all the others, then we move forward, maybe it could be handled better to avoid that many iterations (hungarian method?)
	while i < n do
		local j = i + 1
		 -- we assume the closest is the next point, and update the index c if we find a closest one
		nextp = points[j]
		closest, c = nextp, j
		local x, z = current[1], current[2]
		local dist = ((x - closest[1])^2 + (z - closest[2])^2) -- this is not the real distance to avoid doing one more operation, but the end goal is achieved, real dist would need to be the square root of this
		while j < n do
			j = j + 1
			local compared = points[j]
			local newdist = ((x - compared[1])^2 + (z - compared[2])^2)
			if newdist < dist then
				closest, dist, c = compared, newdist, j
			end
		end
		-- we switch elements of the table: next i become the closest, index of closest receive the element that was in next i
		i = i + 1
		if i ~= c then
			points[i], points[c] = closest, nextp 
		end
		current = closest
	end
end
function widget:MouseMove(x, y, _, _, button, recursion)
	-- if not Drawing --[[and not (warpBack=="ready")--]] then	return	end
	if useMinimap then
		x, y = ClampMouseToMinimap(x, y)
	end

	if not recursion then
		if prev.firstmx and (PID ~= mexDefID) then
			if not special and clock() - prev.press_time < 0.09 then -- mouse click leeway
				-- Echo("clock() - prev.press_time is ", clock() - prev.press_time)
				return
			end

			if  ((prev.firstmx - x)^2 + (prev.firstmy - y)^2) ^0.5 < 15 * (1500 / Cam.relDist) then -- mouse move leeway
				return
			end
		end
		prev.firstmx = false
		if dstatus == 'erasing' then
			local x, y, z = UniTraceScreenRay(x, y, useMinimap, p.underSea, p.sizeX, p.sizeZ)
			if not x then
				return
			end
			EraseOverlap(x, z)
			return
		end
		if not Drawing then return	end

		if g.unStraightened then
			if clock() - g.unStraightened < 0.3 then 
				return
			else
				g.unStraightened=false
			end
		end
		if not pos then
			return
		end
	end
	if special --[[and not attracted--]] --[[and opt.magnetMex--]] then 
		AdaptForMex(p.name)
	end
	mx = x
	my = y
----------------------Warping Back (old) ----------------------
--[[	if CheckWarping() then -- panningview, warping back when panning view or reholding shift
		widgetHandler:UpdateWidgetCallIn("DrawWorld", self)
		--if camPosChange then widgetHandler:UpdateWidgetCallIn("DrawWorld", self) end
	end--]]
---------------------------------------------------------

	local _x, _y, _z, _offMap = UniTraceScreenRay(mx, my, useMinimap, p.underSea, p.sizeX, p.sizeZ)
	if not _x then
		return
	end
	pos = {_x, _y ,_z, _offMap}

	if not recursion then

		if (PID == mexDefID or special and opt.remote) and prev.pos and button == 1 then -- help to catch mex between mouse move point when going fast
			local threshold = 200
			local totalTries = 1000
			local ppos = prev.pos
			local px, pz, ppx, ppz = pos[1], pos[3], ppos[1], ppos[3]
			local d = ((px - ppx)^2 + (pz - ppz)^2) ^ 0.5

			if d > threshold then
				local endpos = pos
				local endmx, endmy = mx, my
				local dirx, dirz = px - ppx, pz - ppz
				local biggest =  max( abs(dirx), abs(dirz) )
				dirx, dirz = dirx / biggest, dirz / biggest
				local x, y
				local GetGround, ToScreen = sp.GetGroundHeight, sp.WorldToScreenCoords
				while d > threshold do
					-- insert as many points as needed between two distanced points until distance is below/equal 16 for each coord
					-- local time = Spring.GetTimer()
					local tx, ty
					ppx = ppx + dirx * threshold
					ppz = ppz + dirz * threshold
					d = d - threshold
					local ppy = GetGround(ppx, ppz)
					x, y = ToScreen(ppx, ppy, ppz)
					-- Points[#Points + 1] = {ppx, ppy, ppz}

					widget:MouseMove(x, y, 0, 0, 1, true)
				end
				pos = endpos
				mx, my = endmx, endmy

				-- Echo('recur end', prev.mx, '=>', endmx, '=', prev.dist_drawn, '+' ,((prev.mx - mx)^2 + (prev.my - my)^2) ^ 0.5)
				-- RECUREND = true
			end
			-- widget:MouseMove(endmx,endmy, 0, 0, 1, true)
		end
	end


	-- Points[np] = {txt = (recursion and 'R' or '') .. np, color = recursion and Colors.red or nil,  unpack(pos)}
	-- if RECUREND then
	-- 	Echo('RECUREND', prev.mx, '=>', mx, '=', prev.dist_drawn, '+' ,((prev.mx - mx)^2 + (prev.my - my)^2) ^ 0.5)
	-- end
	prev.dist_drawn = prev.dist_drawn + ((prev.mx - mx)^2 + (prev.my - my)^2) ^ 0.5
	--- WIP Debug
	-- local np = #Points + 1
	-- local txt = (recursion and 'R' or '') .. np .. ' d:' .. ('%.1f'):format(prev.dist_drawn)
	-- local col = recursion and Colors.red or RECUREND and Colors.blue or nil
	-- Points[np] = {size = 100, txt = txt, color = col, unpack(pos)}
	--------
	prev.mx, prev.my = mx,my
	prev.pos = pos


	-- CATCH MEXES around the cursor depending on cam height
	if PID == mexDefID and GetCloseMex then
		local x, y, z = pos[1],pos[2],pos[3]
		local spots = WG.metalSpots
		local sqrt = math.sqrt
		if opt.grabMexes then
			-- grab mexes around
			local threshold = (g.grabRadius + p.eradius) ^2
			-- CATCH_MEX_RADIUS = threshold
			local addmex, a = {}, 0
			local bestDist, closest = math.huge
			local mexrad
			for i = 1, #spots do
				local spot = spots[i]
				local dx, dz = x - spot.x, z - spot.z
				local dist = dx*dx + dz*dz

				if dist < threshold  and not g.cantMex[spot] then
					if (alt or ctrl) or IsMexable(spot, true) then -- finally allow already mexed spot to be completed
						a = a + 1
						local new = {spot.x,spot.z,r=1, dist = dist, index = a}
						addmex[a] = new
						if dist < bestDist then
							bestDist = dist
							closest = new
						end
						
					end
					g.cantMex[spot]=true
				end

			end
			-- for i, p in ipairs(add) do
			-- 	f.InsertWithLeastDistanceBI(specs, p, math.max(#specs-1, 1))
			-- end
			if a > 0 then
				local s = #specs
				local inserted
				if s == 1  then
					-- put the first automated mex into the calculation, start from our position
					table.insert(addmex, 1, table.remove(specs))
					s = 0
					a = a + 1
					inserted = true
				end
				if a > 1 then
					-- table.sort(addmex, function(a, b) return a.dist < b.dist end)
					-- addmex[closest.index], addmex[1] = addmex[1], addmex[closest.index]
					if a > 2 then
						if specs[s - 1] then
							-- Echo('order from last spec')
							OrderPointsByProximity2(addmex,specs[s - 1])
						else
							-- Echo('order from player')
							local ux, uz
							if cons[1] then
								ux, _, uz = sp.GetUnitPosition(cons[1])
							end
							if ux then
								OrderPointsByProximity2(addmex, {ux, uz})
							else
								OrderPointsByProximity2(addmex, addmex[1])
							end
						end
					else
						-- Echo('single')
						addmex[closest.index], addmex[1] = addmex[1], addmex[closest.index]

					end
				end
				for i = 1, #addmex do
					s = s + 1
					specs[s] = addmex[i]
				end
			end
		else
			local spot = GetCloseMex(x,z)
			if spot and not g.cantMex[spot] then 
				-- specs[#specs+1]={spot.x,spot.z,r=1}
				-- if not sp.GetUnitsInRectangle(spot.x,spot.z,spot.x,spot.z)[1] then
				if IsMexable(spot) then
					specs[#specs+1] = {spot.x, spot.z, r = 1}
				end
				g.cantMex[spot]=true
			end
		end
		return -- dont need to make a rail for this
	end

	local newx, newy, newz = pos[1], pos[2], pos[3]
	-- local railLen = #rail
	-- if #rail ~= rail.n then
	-- 	error('can\'t rely on rail.n')
	-- end
	local railLen = rail.n

	local lasR = rail[railLen]
	local gapx,gapz
	if lasR then
--			gapx = abs( pointX - newx ) or 10000
--			gapz = abs( pointZ - newz ) or 10000
		gapx = abs( newx - lasR[1] )
		gapz = abs( newz - lasR[3] )
		if gapx < 16 and gapz < 16 then
			return
		end
-- 
		straight, locked, pos[1], pos[3], railLen = GoStraight(alt, newx, newz, railLen) -- transform to 8-directional if asked

		newx,newz = pos[1],pos[3]
		lasR = rail[railLen]

	end
	if PID == geos.defID then
		newx = floor((newx + 8 - p.oddX)/16)*16 + p.oddX
		newz = floor((newz + 8 - p.oddZ)/16)*16 + p.oddZ
		local geoX,geoZ = geos:Update(newx,newz)
		if geoX then 
			pointX, pointZ = geoX,geoZ
			specs.n = specs.n + 1
			specs[specs.n] = {geoX, geoZ, r = 1}
		end
		return
	end
	pointX, pointZ = newx, newz
	local px,py,pz = newx,newy,newz


	local specsLen = #specs



	---------- Remove rail on Backward TODO IMPROVE -----------------------
	-- comparing distance of 
	-- i-rail/cursor, i-rail/last placement, i-rail/last rail and last rail/cursor
	-- in order to erase the rail when cursor going backward
	-- note: rail.processed can differ from railLen if we used recursion and not using updateRailMM
	local processed
	if dstatus ~='paint_farm' and rail.processed == railLen and (not locked or clock() - locked > 0.3) then
		local x,y,z = unpack(rail[railLen])
		local factor = Cam.relDist
		local llasP = specs[specsLen-1]
		local llasPx,llasPz, llasP_To_Cur
		if llasP then
			llasPx,llasPz = llasP[1],llasP[2]
			llasP_To_Cur = (llasPx-px)^2 + (llasPz-pz)^2 
		end

		local lasP = specs[specsLen]
		local lasPx, lasPz, lasP_To_Cur
		if lasP then
			lasPx, lasPz = lasP[1], lasP[2]
			lasP_To_Cur = (lasPx - px)^2 + (lasPz - pz)^2 
		end

		if llasP and llasP_To_Cur < prev.llasP_To_Cur and prev.llasP_To_Cur < factor then
			-- if the mouse is getting closer from the second last placement and the last distance checked is < cam dist threshold
			local cancelled = false
			for i = railLen, llasP.r + 1, -1 do
				-- remove railpoints after last placement until current rail point 
				if special then
					local ri = rail[i]
					if ri and (ri.mex or ri.connect) then
						cancelled = i
						break
					end
				end
				rail[i]=nil
			end
			-- if cancelled then
			-- 	Echo('CANCELLED', math.round(os.clock()))
			-- end
			-- Echo(
			-- 	'cancelled', cancelled,
			-- 	'lasP.r', lasP.r,
			-- 	 cancelled and (rail[cancelled].mex and 'mex' or rail[cancelled].connect and 'connect') or ''
			-- )
			railLen = cancelled or llasP.r
			processed = llasP.r
			if not cancelled or cancelled < lasP.r then
			-- delete the last placement, second last become last
				if cancelled then
					Points = {}
					Points[#Points + 1] = {color = color.white, size = 30, unpack(rail[processed])}	
				end
				lasP = llasP
				if special then
					UpdateMexes(lasPx, lasPz, 'remove', specsLen)
				end
				
				specs[specsLen] = nil
				specsLen = specsLen - 1
				TestBuild('forget extra')
				if cancelled and cancelled < lasP.r then

					processed = llasP.r -- case it can beconnected, let the last rail point be reprocessed
				end
				if special then 
					allGrids = {} 
					for i = 1, specsLen do
						for k in pairs(specs[i].grids) do
							allGrids[k] = true 
						end
					end
				end
			end

			--Echo('removed rails to previous of last spec')
		elseif lasP and lasP_To_Cur < prev.lasP_To_Cur and prev.lasP_To_Cur < factor then
			-- else if mouse is getting closer of the last placement within the cam dist threshold
			for i = lasP.r + 1, railLen do
				-- delete rails after the last placement
				rail[i] = nil
			end
			railLen = lasP.r
			processed = railLen
			-- Echo('delete 2')
		else			
			-- removing rail by distance of the cursor from a variable number of last rail points (depending on zoom)
			local lasRx, lasRy, lasRz = unpack(rail[railLen])

			local fact = Cam.relDist / 1000 --* sp.GetBuildSpacing() / 3
			-- Echo('---st')
			-- if not (lasR.mex or lasR.connect) then
				for i = railLen - 1, railLen - (7 + fact) + (lasR.straight and 5 or 0) + (lasR.mex and 10 or 0), -1 do
					local ri = rail[i]
					if ri then
						if ri.mex or ri.connect then
							-- Echo('break ', i)
							break
						end
						-- Echo('i',i,"lasP, lasP.r is ", lasP, lasP.r, 'lasP is connecting', lasP.status == 'connect')

						local rix, riy, riz = ri[1], ri[2], ri[3]
						local lasR_To_Cur = (lasRx - px)^2 + (lasRz - pz)^2 --
						local ri_To_Cur  = (rix-px)^2    + (riz-pz)^2 -- distance ri to cursor
						local ri_To_LasR = (rix-lasRx)^2 + (riz-lasRz)^2 -- distance ri to last rail point
						local ri_To_LasP = lasP and (rix-lasPx)^2 + (riz-lasPz)^2 -- distance ri to last placement

						if  ri_To_Cur < ri_To_LasR or specsLen == 1 and railLen < 8 and lasP_To_Cur < ri_To_LasP then
							rail[railLen] = nil
							railLen = railLen - 1
							if not processed or railLen < processed then
								processed = railLen
							end
							lasRx, lasRy, lasRz = unpack(rail[railLen])

							if lasP and lasP.r > railLen then
								if special then 
									UpdateMexes(lasPx, lasPz, 'remove', specsLen)
								end
								specs[specsLen] = nil
								specsLen = specsLen - 1
								TestBuild('forget extra')
								lasP = specs[specsLen]
								if lasP and lasP.r > 1 then
									processed = llasP.r - 1
								else
									processed = 1
								end
								-- Echo('delete spec #'..(specsLen+1).. ', at rail #'..lasP.r..', rails: ' ..railLen, 'to process: '..tostring(processed))

								if special then 
									allGrids={}
									for i = 1, specsLen do
										for k in pairs(specs[i].grids) do
											allGrids[k] = true 
										end
									end
								end
							end
						end
						--Echo('rail reduced, now: '..railLen, 'processed: '..rail.processed )
					end
				end
			-- end
		end
		prev.lasP_To_Cur = lasP_To_Cur or 0
		prev.llasP_To_Cur = llasP_To_Cur or 0
	end
	-- Echo("rail.processed is ", rail.processed)
	-- Echo('will be first val:'
	-- 	,processed 
	-- 	,(UPDATE_RAIL or recursion or RECUREND) and rail.processed
	-- 	,specs.n~=specsLen and (lasP and lasP.r)
	-- 	, railLen
	-- )

	rail.processed = processed 
						or UPDATE_RAIL and rail.processed
						or specs.n ~= specsLen and (lasP and lasP.r)
					--[[(   specs.n==specsLen+1 and (lasP and lasP.r)
						 or specs.n==specsLen+2 and (llasP and llasP.r)	 )--]]
						or railLen
	-- Echo("rail.processed is ", rail.processed, specs.n, specsLen, specs.n~=specsLen,'UPDATE_RAIL', UPDATE_RAIL)

	specs.n = specsLen

	-- it's not useful outside of debugging or maybe showing raw rail points for user
	-- primRail.n = primRail.n + 1
	-- primRail[primRail.n]={px,py,pz}
	-------
	railLen = railLen+1
	rail[railLen]={px, py, pz--[[, n = railLen--]]} -- depending on mouse speed points will not be evenly positionned, but we will use them to fill the blanks and normalize their distance

	rail.n = railLen
	-- Echo('=> ', rail.n, #rail)
	-- if recursion then
	-- 	Echo('recursion '..#Points..' :', rail.processed)
	-- end
	-- if RECUREND then
	-- 	Echo('end recur processed:', rail.processed)
	-- 	RECUREND = false
	-- end

	if opt.update_rail_MM then
		UpdateRail()
	else
		UPDATE_RAIL = true
	end
	-- Echo('end of mm', mx,my)
end

--------------------------------------------------------------------------------
-- Graphics
--------------------------------------------------------------------------------
local drawValue = true
local glLists = {}
do
	local GL_LINE_STRIP			= GL.LINE_STRIP
	local GL_LINES				= GL.LINES
	local GL_POINTS				= GL.POINTS
	local GL_ALWAYS				= GL.ALWAYS


	local glVertex				= gl.Vertex
	local glLineWidth   		= gl.LineWidth
	local glColor       		= gl.Color
	local glBeginEnd    		= gl.BeginEnd
	local glPushMatrix 			= gl.PushMatrix
	local glPopMatrix			= gl.PopMatrix
	local glText 				= gl.Text
	local glDrawGroundCircle	= gl.DrawGroundCircle
	local glPointSize 			= gl.PointSize
	local glNormal 				= gl.Normal
	local glDepthTest			= gl.DepthTest
	local glTranslate 			= gl.Translate
	local glBillboard       	= gl.Billboard
	local GL_POINTS				= GL.POINTS
	local glCallList			= gl.CallList

	local ToScreen = Spring.WorldToScreenCoords
	local gluDrawScreenDisc
	local gluDrawGroundDisc
	local gluDrawDisc
	local gluDrawGroundRectangle
	local gluDrawGroundHollowCircle
	local gluDrawFlatCircle
	local lastView

	function InitDraw()
		gluDrawScreenDisc 			= gl.Utilities.DrawScreenDisc
		gluDrawGroundDisc 			= gl.Utilities.DrawGroundDisc
		gluDrawGroundRectangle 		= gl.Utilities.DrawGroundRectangle
		gluDrawDisc			 		= gl.Utilities.DrawDisc
		gluDrawGroundHollowCircle  	= gl.Utilities.DrawGroundHollowCircle
		gluDrawFlatCircle 			= gl.Utilities.DrawFlatCircle
		lastView = NewView[2]
	end
	local white 			= {1,1,1,1}
	local yellow			= {1,1,0,1}
	-- local pointList
	-- local listSize = 0

	local font            		= "LuaUI/Fonts/FreeMonoBold_12"
	local UseFont 				= fontHandler.UseFont
	local TextDrawCentered 		= fontHandler.DrawCentered


	glLists.point = gl.CreateList(
		glBeginEnd,GL.POINTS,
			function()
				glNormal(1, 0, 1)
				glVertex(1, 0, 1)
			end
	)


	local function DrawPoint(p, i)
		glPushMatrix()	
		-- local mx,my = ToScreen(unpack(p))                   

		glTranslate(unpack(p))
		glBillboard()
		glColor(p.color or white)
		-- if p.txt then my=my-10 end
		-- glText(i..(p.txt or ' '), mx-5, my, 10) 
		-- TextDrawCentered((p.txt or i), mx-3, my)
		glText( (p.txt or i or ''), -3, -3, p.size or 10)
		glPopMatrix()

	end

	local function drawPoints()
		-- UseFont(font)
		if not Points[1] then
			return
		end
		if Points[4000] then
			Points = {}

			if table.size(glLists) > 500 then
				local simplepoint = glLists.point
				glLists.point = nil
				for k, l in pairs(glLists) do
					gl.DeleteList(l)
					glLists[k] = nil
				end
				glLists.point = simplepoint

			end
		end

		for i, p in ipairs(Points) do
			glPushMatrix()	
			-- local mx,my = ToScreen(unpack(p))                   

			glTranslate(unpack(p))
			glBillboard()
			glColor(p.color or white)
			-- if p.txt then my=my-10 end
			-- glText(i..(p.txt or ' '), mx-5, my, 10) 
			-- TextDrawCentered((p.txt or i), mx-3, my)
			local strID = 'point'..(p.txt or i)..'-'..(p.size or 10)
			local list  = glLists[strID]
			if not list then
				list = gl.CreateList(glText, (p.txt or i), -3, -3, p.size or 10)
				glLists[strID] = list
			end
			glCallList(list)
			-- glText((p.txt or i), -3, -3, p.size or 10) 

			glPopMatrix()
			--glPointSize(10.0)
			--glBeginEnd(GL.POINTS, pointfunc,x,y,z)
		end
	end
	local vsx, vsy
	function widget:ViewResize(x,y)
		vsx, vsy = x, y
		g.vsx, g.vsy = x, y
	end
	function widget:DrawScreen()
		glColor(1,1,1,1)

		-- gl.PushMatrix()
		-- gl.BeginText()
		-- glColor(1,1,1,1)
		-- glColor(1,0.5,1,1)
		-------------------------
	 -- 	if Points[1] then
		-- 	drawPoints()
		-- end

		-------------------------
		glColor(0.7,0.7,0.7,1)
		if dstatus ~= 'none' then
			glText(format(dstatus), 0,vsy-110, 25)
		end
		if drawEnabled then
			glText(format("Drawing"), 0,vsy-68, 25)

			-- if pushRail then
			-- 		glPushMatrix()	
		 --       		glText(format("pushing"), 0,vsy-150, 25)
		 --            glPopMatrix()
			-- end
			if special then
				glColor(0.7,0.7,0,1)
				glText("eBuild", 0,vsy-89, 25)
			end
			if true then
				glColor(0.7,0.7,0,1)
				local spacing = sp.GetBuildSpacing()
				if p.spacing ~= spacing then
					glText(p.spacing .. ' ('..spacing..')', 0,vsy-152, 25)
				else
					glText(p.spacing, 0,vsy-152, 25)
				end
			end

		end

		-----------------
		-- SHOW FARM SETTING
		if PID and ctrl and (alt or shift) then
			if not (PID == mexDefID and WG.metalSpotsByPos) then
				-- local sx,sz = p.sizeX,p.sizeZ
				UseFont(font)
				-- if sx==sz then
					local x,y,z = unpack(pos)
					local mx,my = ToScreen(x,y,z)
					-- glPushMatrix()
					-- glTranslate(x,y,z)
					-- glBillboard()
					
					glColor(yellow)

					TextDrawCentered('f:'..((FARM_SPREAD[PID] or 1) + 1)..'|'..(FARM_SCALE[PID] or 0), mx + 15,my + 15)
					-- glPopMatrix()
				-- end
			end
		end
		-- if PID then
		-- 	local x,y,z = unpack(pos)
		-- 	local mx,my = ToScreen(x,y,z)
	 --        -- glPushMatrix()
	 --        -- glTranslate(x,y,z)
	 --        -- glBillboard()
	 --        UseFont(font)
	 --        glColor(COLORS.yellow)
	 --        local name = p.lastPID and UnitDefs[p.lastPID].name
	 --        TextDrawCentered(tostring(name), mx + 15,my + 40)
	 --        -- glPopMatrix()

		-- end
		-- debugging


		if special and PID ~= pylonDefID and Debug.mexing() then
			if opt.magnetMex then
				glColor(0,1,0,0.3)
				local mx, my = sp.GetMouseState()
				gluDrawScreenDisc(mx,my,1000^0.5)
			end
			if REMOTE and specs[1] then
				glColor(COLORS.purple)
				for i, v in pairs(REMOTE) do
					local x,y,z = unpack(v)
					local mx,my = ToScreen(x,y,z)

					TextDrawCentered(tostring(i), mx ,my )
				end
				glColor(1, 1, 1, 1)
			end
		end


		---- Debug Order of specs
		if Debug.ordering() then
			if not copyrail or PID and primRail[1] then
				copyrail = copy(primRail)
			end

			local railLen = #copyrail

			if railLen > 0 then
				
				local floater = p and p.floater
				local GetGround = sp.GetGroundHeight
				glColor(0.2, 1, 0.2, 1)
				for i=1, railLen do
					--Draw the placements
					local r = copyrail[i]
					local x, z = r[1], r[3]
					local y = GetGround(x,z)
					local mx, my = ToScreen(x,y,z)
					TextDrawCentered(tostring(i), mx ,my )					
					--[[
					local mexes = mexes[i]
					if mexes then
						glColor(1,0.7,0,1)
						for j=1,#mexes do
							-- glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, mexes[i],nil,true)
							local mex = mexes[j]
							local x, z = mex[1], mex[2]
							local y = GetGround(x,z)
							local mx, my = ToScreen(x,y,z)
							TextDrawCentered(i .. '-' .. j, mx ,my )
						end
						glColor(0.2, 1, 0.2, 1)
					end
					--]]
				end
				--[[
				local lasmexes = mexes[specLength+1]
				if lasmexes then
					glColor(1,0.7,0,1)
					for j=1,#lasmexes do
						-- glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, mexes[i],nil,true)
						local mex = lasmexes[j]
						local x, z = mex[1], mex[2]
						local y = GetGround(x,z)
						local mx, my = ToScreen(x,y,z)
						TextDrawCentered('+' .. '-' .. j, mx ,my )
					end
					glColor(0.2, 1, 0.2, 1)
				end
				--]]
			end
		end
		glColor(1, 1, 1, 1)

	end





	local function rectverts(x, y, z, sx, sz)
		glVertex(x - sx, y, z - sz)
		glVertex(x + sx, y, z - sz)
		glVertex(x + sx, y, z + sz)
		glVertex(x - sx, y, z + sz)
	end

	local function DrawRect(x,z,sx,sz, floater, plain)
		local strID = sx..'-'..sz..'-'..(plain and 'plain' or '')
		local list = glLists[strID]
		if not list then
			list = gl.CreateList(
				glBeginEnd, plain and GL.QUADS or GL_LINE_STRIP,
				function()
					glVertex( sx, 0,  sz)
					glVertex( sx, 0, -sz)
					glVertex(-sx, 0, -sz)
					glVertex(-sx, 0,  sz)
					glVertex( sx, 0,  sz)
				end
			)
			glLists[strID] = list
		end
		local y = sp.GetGroundHeight(x,z)
		glPushMatrix()
		glTranslate(x, floater and y<0 and 0 or y , z)
		glCallList(list)
		glPopMatrix()

	end
	local function DrawRectangleLine(t,pl,mex)
		--[[h = h+3--]]
		 --h = pointY == 0.1 and  h+3 or h
		 local h = sp.GetGroundHeight(t[1], t[2])
		 if h<0 and (mex or p.floater) then
			h=0
		 end
		 local x, z, sx, sz = t[1], t[2]
		 if pl then
			if t[4] then
				sx, sz = t[3], t[4]
			else
				local info = p:Measure(t[3], t[4]) -- defID and facing
				sx, sz = info.sizeX, info.sizeZ
			end
		 elseif mex then
			sx, sz = 24,24
		 else
			sx, sz = p.sizeX, p.sizeZ
		 end
		 
		glVertex(x + sx, h, z + sz)
		glVertex(x + sx, h, z - sz)
		glVertex(x - sx, h, z - sz)
		glVertex(x - sx, h, z + sz)
		glVertex(x + sx, h, z + sz)
	end

	local normalColor = {0.2, 1.0, 0.2, 0.8}
	local connectColor = {0.7, 1.0, 0.2, 0.8}

	local specColor



----------------------------------------
	

	function widget:DrawWorld()
		local x, y, z
		if PID then
			if special then
				specColor = connectColor
			else
				specColor = normalColor
			end
		end

		if special and specs[1] and Debug.grids() then
			Points = {}
			for i = 1, #specs do
				local spec = specs[i]
				local grids = spec.grids
				local list = '#' .. i .. ':'
				for k,v in pairs(grids) do
					list = list .. k .. ','
				end
				list = list:gsub(',$', '')
				local r = rail[spec.r]

				Points[#Points + 1] = {txt = 'x' .. i, color = color.yellow, unpack(r)}
				Points[#Points + 1] = {txt =  list, spec[1], sp.GetGroundHeight(spec[1], spec[2]), spec[2]}
			end
		end

		drawPoints()

	--Echo("not (warpBack==hold) is ", not (warpBack=="hold"))
		--if #rail==0 then return end
	--[[	if not drawEnabled and not (warpBack=="hold" and #specs>0) then
			widgetHandler:RemoveWidgetCallIn("DrawWorld", self)

			return
		end--]]

		-- DRAW M GRIDS
	--[[	local spotsPos=WG.metalSpotsByPos
		for x,t in pairs(spotsPos) do
			for z,n in pairs(t) do
				glPushMatrix()
				glTranslate(x,sp.GetGroundHeight(x,z),z)
				glBillboard()
				glColor(1, 1, 0, 0.6)
				glText('m'..n, 0,0,30,'h')
				glPopMatrix()
				glColor(1, 1, 1, 1)
			end
		end--]]
		--
		-- DRAW GROUND CIRCLE OF RADIUS
	--[[	if pos and PID and E_SPEC[PID] then 
			local mx,my = sp.GetMouseState()
			local	_, pos = sp.TraceScreenRay(mx, my, true, false, false, not p.floater)
			if pos then
				local ud = UnitDefs[PID]
				glColor(specColor)
				glDrawGroundCircle(pos[1],pos[2],pos[3], E_RADIUS[PID], 32)
			end
		end--]]
		-------

		--- SHOW RAIL
		if opt.showRail and PID ~= mexDefID then
			if primRail[1] then
				glColor(0.5, 0.5, 0.5, 0.4)
				glPointSize(2.0)
				for i=1, #primRail do
					local pr = primRail[i]
					glPushMatrix()
					glTranslate(pr[1], pr[2], pr[3])
					glCallList(glLists.point)
					glPopMatrix()
				end
				glColor(1, 1, 1, 1)
				glPointSize(1)
			end



			local railn=rail.n
			if railn > 0 then
				glPointSize(2.5)
				local point = glLists.point
				for i=1, railn do
					local r = rail[i]
					local x,y,z = r[1], r[2], r[3]
					if y<0 and p.floater then y=0 end
					glColor(1,1,1,1)
					if r.color then glColor(r.color) 
					elseif r.done then glColor(1,0.2,0.2,1) 
					elseif r.pushed then glColor(0.8,1,1,1) 
					end
					glPushMatrix()
					glTranslate(x,y,z)
					glCallList(point)
					glPopMatrix()
				end
				glPointSize(1.0)
				glColor(1, 1, 1, 1)
			end
		end
		-- DRAW ERASER
		if dstatus == 'erasing' 
			or SHOW_ERASER_RADIUS
			or PID and opt.enableEraser
		then
			local p = p
			local x,z
			local stipple = false
			if not PID then
				p = p:Measure(p.lastPID or UnitDefNames['energysolar'].id, 0)
			end
			if dstatus ~= 'erasing' then
				CalcEraserRadius(p)
			end
			if SHOW_ERASER_RADIUS then
				if os.clock() - SHOW_ERASER_RADIUS > 1 then
					SHOW_ERASER_RADIUS = false
				end
				local _
				x, _, z = UniTraceScreenRay(vsx/2, vsy/2, useMinimap, p.underSea, p.sizeX, p.sizeZ)
				if not x then
					return
				end
			else
				x, z = pos[1], pos[3]
				stipple = dstatus ~= 'erasing'
			end
			local rad = g.erase_round
			local factor = g.erase_factor
			local sx,sz = p.terraSizeX * factor, p.terraSizeZ * factor


			local flatOnWater = false
			if p and p.floater then
				local gy =  sp.GetGroundHeight(x,z) 
				if gy < 0 then
					flatOnWater = -gy
				end
			end
			if stipple then
				gl.LineStipple('')
				glColor(eraser_color[1], eraser_color[2], eraser_color[3], math.min(eraser_color[4] * 4, 1))
			else
				glColor(eraser_color)
			end
			if rad then
				if flatOnWater then
					if stipple then
						gluDrawFlatCircle(x, 0, z, rad)
					else
						gluDrawDisc(x, 0, z, rad)
					end
				else
					if stipple then
						gluDrawGroundHollowCircle(x, z, rad)
					else
						gluDrawGroundDisc(x,z, rad)
					end
					
				end
			elseif stipple then
				-- nothing to do
			elseif flatOnWater then
				DrawRect(x,z,sx,sz, true, true)
			else
				gluDrawGroundRectangle(x - sx, z - sz,x + sx,z + sz)
			end
			if stipple then
				gl.LineStipple(false)
			end
			glColor(1,1,1,1)
		end

		-- SHOW FARM SETTING
		-- draw farm rectangle in diagonal
		if PID and ctrl and (shift or alt) and pos then
			if not (PID == mexDefID and WG.metalSpots) then
				local sx,sz = p.sizeX,p.sizeZ
				gl.DepthTest(GL.ALWAYS)
				-- if sx==sz then
					glColor(yellow)
					-- local x,y,z = unpack(pos)
					local spread = FARM_SPREAD[PID] or 1
					local scale = FARM_SCALE[PID] or 0
					if not x then
						x, y, z = UniTraceScreenRay(mx, my, useMinimap, p.underSea, sx, sz)
						if not x then
							return
						end
					end
					-- x,y,z = unpack(pos)
					x = floor((x + 8 - p.oddX)/16)*16 + p.oddX
					z = floor((z + 8 - p.oddZ)/16)*16 + p.oddZ
					-- local limit = (sx+oddx+scale*8)-(scale%2)*8
					if spread%2 == 1 then
						x = x - p.oddX + (scale%2)*8
						z = z - p.oddZ + (scale%2)*8
					end
					for i = -spread, spread, 2 do
						local sx,sz = sx,sz
						if i == 0 and dstatus ~= 'paint_farm' then -- for the middle square to be visible despite the build drawn
							sx,sz = sx+3, sz+3
						end
						DrawRect(x + i*(sx + scale*8), z + i*(sz + scale*8), sx, sz)
						-- glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, {x+i*(sx+scale*8), z+i*(sz+scale*8), sx, sz}, true)
					end
				-- end
				gl.DepthTest(GL.LEQUAL)
				gl.DepthTest(false)
			end
		end
		-- OVERLAP DRAW
		local overlapped_ln = #overlapped
		if overlapped_ln > 0 then
			glColor(1,0.3,0,1)
			for i=1, overlapped_ln do
				--Draw the placements
				local ol = overlapped[i]
				--if ol.tf then glColor(1,0.3,0,1) end
				local width = 3 - (overlapped_ln - i)
				glLineWidth(width>1 and width or 1)
				glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, ol, true)
			end
			glLineWidth(1.0)
			glColor(1, 1, 1, 1)
		end
		-- GRAB RADIUS
		if SHOW_GRAB_RADIUS 
			or PID == mexDefID and opt.grabMexes and GetCloseMex
		then
			local x, y, z = x, y, z
			local r
			if SHOW_GRAB_RADIUS then
				r = CalcGrabRadius()
				if os.clock() - SHOW_GRAB_RADIUS > 1 then
					SHOW_GRAB_RADIUS = false
				end
				x, y, z = unpack(Cam.trace)
			else
				r = g.grabRadius or CalcGrabRadius()
			end
			-- CATCH_MEX_RADIUS
			if not x then
				x, y, z = UniTraceScreenRay(mx, my, useMinimap, true, 24, 24)
				if not x then
					return
				end
			end

			glColor(0.8,0.7,0.2,0.2)
			gluDrawGroundDisc(x, z, r)
		elseif SHOW_REMOTE_RADIUS
			or special and PID ~= pylonDefID and opt.remote
		then
			local x, y, z = x, y, z
			local r
			if SHOW_REMOTE_RADIUS then
				r = CalcRemoteRadius()
				if os.clock() - SHOW_REMOTE_RADIUS > 1 then
					SHOW_REMOTE_RADIUS = false
				end
				x, y, z = unpack(Cam.trace)
			else--if lastView ~= NewView[2] then
				r = CalcRemoteRadius()
				if r < E_RADIUS[PID] then
					r = 0
				end
			end

			if not x then
				x, y, z = UniTraceScreenRay(mx,my, useMinimap, true, 24, 24)
				if not x then
					return
				end
			end
			if r > 0 then
				glColor(0.2,0.7,0.2,0.2)
				gluDrawGroundDisc(x, z, r)
			end
		end





		if PID and (special or PID == mexDefID) and Debug.mexing() then
			glColor(1,0,1,1)
			glLineWidth(3)
			for spot in pairs(g.cantMex) do
				DrawRect(spot.x,spot.z,28,28)
			end
			local mx, my = sp.GetMouseState()
			if not x then
				x, y, z = UniTraceScreenRay(mx, my, useMinimap, p.underSea, p.sizeX, p.sizeZ)
				if not x then
					return
				end
			end
			local avspot = GetClosestAvailableMex(x, z)
			
			if avspot then
				glColor(1,0.75,1,1)
				DrawRect(avspot.x,avspot.z,28,28)
			end
			
			-- Echo("REMOTE_RADIUS is ", REMOTE_RADIUS)
			if special and PID ~= pylonDefID and opt.remote and Drawing then
				glColor(1,1,0,1)
				glLineWidth(1)
				gl.LineStipple('spring default')
				gl.LineStipple(true)
				gluDrawGroundHollowCircle(x, z, g.remoteRadius)
				gl.LineStipple(false)
			end
			if ATTRACTED then
				glColor(0,1,0,0.3)
				gluDrawGroundHollowCircle(ATTRACTED.x,ATTRACTED.z,80) 
			end

			glColor(1,0,0,0.3)
			for spot in pairs(forgetMex) do
				gluDrawGroundHollowCircle(spot.x,spot.z,80) 
			end
			glLineWidth(1.0)
		end

		if g.previMex[1] then
			glColor(1,0.7,0,1)
			for i=1,#g.previMex do
				local mex = g.previMex[i]
				DrawRect(mex[1],mex[2],24,24)
				-- glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, g.previMex[i],nil,true)
			end
			glColor(specColor)
		end
		local specLength = #specs

		if specLength > 0 then
			glColor(specColor)
			
			local sx,sz = p.sizeX, p.sizeZ
			local floater = p and p.floater
			for i = 1, specLength do
				--Draw the placements
				local spec = specs[i]
				if spec.tf then
					glColor(1,0.3,0,1)
				end
				local width = (6.5 - (specLength - i)) / 2

				glLineWidth(width>1 and width or 1)

				DrawRect(spec[1],spec[2],sx,sz, floater)
				-- glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, spec)

				local mexes = mexes[i]
				if mexes then
					glColor(1,0.7,0,1)
					for i = 1, #mexes do
						-- glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, mexes[i],nil,true)
						local mex = mexes[i]
						DrawRect(mex[1],mex[2],24,24, true)
					end
					glColor(specColor)
				end
				
			end
			local lasmexes = mexes[specLength+1]
			if lasmexes then
				glColor(1,0.7,0,1)
				for i = 1, #lasmexes do
					local mex = lasmexes[i]
					DrawRect(mex[1],mex[2],24,24, true)
					-- glBeginEnd(GL_LINE_STRIP, DrawRectangleLine, lasmexes[i],nil,true)
				end
				glColor(specColor)
			end
			glLineWidth(1.0)
		end
		glColor(1, 1, 1, 1)
	end
end


function DPCallin(self) -- homemade callin -- not used anymore
	Echo("TRIGGERED2", self.value)
end

function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = sp.GetMyTeamID()
	end
end

function widget:AfterInit()
	geos:Get()
	GetCloseMex = WG.metalSpots and WG.GetClosestMetalSpot
	widget.Update = widget._Update
	widget._Update = nil
	initialized = true
end

function widget:Initialize()
	--widget._UpdateSelection = widgetHandler.UpdateSelection
	--widgetHandler.UpdateSelection = widget.UpdateSelection
	-- Spring.SetBuildSpacing = function(...)
	-- 	-- Echo("SET", os.clock(), ...)
	-- 	-- Echo(debug.traceback())
	-- 	return sp.SetBuildSpacing(...)
	-- end
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		-- Spring.Echo("DrawPlacement disabled")
		-- widgetHandler:RemoveWidget(self)
		-- return
		widgetHandler:RemoveWidgetCallIn('UnitCommand',widget)
	end
	
	Cam = WG.Cam
	NewView = WG.NewView
	local sig = '[' ..widget:GetInfo().name .. ']:'
	local status
	if not Cam then
		status = 'Requires api_view_changed.lua in Include\\helk_core\\widgets\\ folder.'
		widgetHandler:RemoveWidget(widget)
	elseif not gl.Utilities.DrawGroundDisc then
		status = 'Requires addon_gl.lua in Include\\helk_core\\ folder.'
	end
	if status then
		widget.status = status
		widgetHandler:RemoveWidget(widget)
		Echo(sig .. status)
		return
	end
	InitDraw()
	widget:ViewResize(Spring.GetViewGeometry())
	widget:PlayerChanged(myPlayerID)
	plate_placer = widgetHandler:FindWidget('Factory Plate Placer2') or widgetHandler:FindWidget('Factory Plate Placer')

	local w = widgetHandler:FindWidget('Selection Modkeys')
	if w then
		SM_enable_opt = w.options.enable
		do
			local isEnabled
			switchSM = function(backup) 
				isEnabled = SM_enable_opt.value
				if backup then 
					if isEnabled then
						SM_enable_opt.value = true
					end
				else
					isEnabled = SM_enable_opt.value
					if isEnabled then
						SM_enable_opt.value = false
					end

				end
			end
		end
	else
		switchSM = function() end
	end
	PBH = widgetHandler:FindWidget('Persistent Build Height 2')
	PBS = widgetHandler:FindWidget('Persistent Build Spacing')
	widget._Update = widget.Update
	widget.Update = widget.AfterInit
	widgetHandler:UpdateWidgetCallIn('GameFrame',widget)
	Spring.AssignMouseCursor(CURSOR_ERASE_NAME, CURSOR_ERASE, true, false)

	WG.drawingPlacement = false
	Debug = f.CreateDebug(Debug, widget, options_path)
	-- if WG.HOOKS then
	-- 	WG.HOOKS:HookOption(widget,'Lasso Terraform GUI','structure_holdMouse',DPCallin)
	-- end
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

	-- if Spring.GetGameFrame()>0 then widget:GameFrame() end
	widget:CommandsChanged()

end

function widget:SetConfigData(data)
	if data.DP then
		noDraw = data.DP.noDraw
		-- pushRail = data.DP.pushRail
		FARM_SPREAD = data.DP.spreads or FARM_SPREAD
		FARM_SCALE = data.DP.scales or FARM_SCALE
	end
	if data.Debug then
		Debug.saved = data.Debug
	end
end
function widget:GetConfigData()
	--Echo("noDraw is "
	local ret = {
		DP = {
			noDraw = noDraw,
			pushRail = pushRail,
			spreads = FARM_SPREAD,
			scales=FARM_SCALE
		}
	}
	if Debug and Debug.GetSetting then
		ret.Debug = Debug.GetSetting()
	end
	return ret
end



function widget:Shutdown()
	--widgetHandler.UpdateSelection = widget._UpdateSelection
	--widget.UpdateSelection = widget._UpdateSelection
	reset(true)
	WG.drawEnabled=false
	WG.drawingPlacement = false
	for k, list in pairs(glLists) do
		gl.DeleteList(list)
		glLists[k] = nil
	end
	-- Spring.SetBuildSpacing = sp.SetBuildSpacing
end

if f then
	f.DebugWidget(widget)
end


