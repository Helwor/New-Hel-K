

function widget:GetInfo()
	return {
		name      = "UnitsIDCard",
		desc      = "produce extended ID card of units",
		author    = "Helwor",
		date      = "August 2020",
		license   = "GNU GPL, v2 or later",
		layer     = -10e37, -- NOTE: math.huge == 10e38
		enabled   = true,  --  loaded by default?
		handler   = true,
		api		  = true,
	}
end
local Echo = Spring.Echo
local f = WG.utilFuncs
local EMPTY_TABLE = {}
local GetCameraHeight = f.GetCameraHeight
local manager = {}
local debugProps = {'id','isAllied','isMine','isEnemy'}
local filterProps = {}
local function Throw(...)
	Echo(...)
	error(debug.traceback())
end

-- local debugProps = false
local isCommDefID = {}
local isPlaneDefID = {}
local isFactoryDefID = {}
local isDefenseDefID = {}
local isConDefID = {}
for defID, def in pairs(UnitDefs) do
	local name = def.name
	if (name:find('^dyn') or name:find('c%d+_base') or name:find('com%d+$') or name:find('comm') or name:find('^hero')) then 
		isCommDefID[defID] = true
	elseif not def.isImmobile and def.buildOptions[1] then
		isConDefID[defID] = true
	end
	if name:match('bomber') or (name:match('plane') and not def.isFactory ) then
		isPlaneDefID[defID] = true
	end
	if def.isFactory and name~='staticrearm' and name~="striderhub" then
		isFactoryDefID[defID] = true
	end
	if name:find("turret") or name=='staticarty' or name=='staticheavyarty' or name=='staticantiheavy' then
		isDefenseDefID[defID] = true
	end
end
local setPropWindow, setFilterWindow
options_path = 'Hel-K/'..widget:GetInfo().name

options = {}
options_order = {
	'showprop','showAllProps', 'setprop','setpropfilter'
}

local SHOW_UNIT_PROP = false
options.showprop = {
	name = 'Show Debug Prop',
	type = 'bool',
	value = SHOW_UNIT_PROP,
	OnChange = function(self)
		SHOW_UNIT_PROP = self.value
	end,
	action = 'showprop',

}
options.showAllProps = {
	name = 'Show All Properties',
	type = 'bool',
	value = false,

}
options.test = {
	name = 'Test',
	type = 'bool',
	value = false,

}
options.setprop = {
	name = 'Debug Property',
	type = 'button',
	OnChange = function(self)
		if setPropWindow and not setPropWindow.disposed then
			setPropWindow:Dispose()
			setPropWindow = nil
		else
			setPropWindow = f.CreateWindowTableEditer(debugProps, 'debugProps')
		end
	end,
	action = 'setprop',
}
options.setpropfilter = {
	name = 'Filter Out Property',
	type = 'button',
	OnChange = function(self)
		if setPropFilterWindow and not setPropFilterWindow.disposed then
			setPropFilterWindow:Dispose()
			setPropFilterWindow = nil
		else
			setPropFilterWindow = f.CreateWindowTableEditer(filterProps, 'filterProps')
		end
	end,
	action = 'setpropfilter',
}

------------- Partial DEBUG
-- local Debug = { -- default values
--     active=false, -- no debug, no hotkey active without this
--     global=false, -- global is for no key : 'Debug(str)'
--     update = false,
-- }
-- Debug.hotkeys = {
--     active =            {'ctrl','alt','U'} -- this hotkey active the rest
--     ,global =           {'ctrl','alt','G'}

--     ,update = 			{'ctrl','alt','X'}
-- }

-------------

local debuggingUnit = {}


local CheckTime = f.CheckTime
local vunpack   = f.vunpack
local Page = f.Page

local currentFrame = Spring.GetGameFrame()
-- local selByID = {}
-- local selByUnit = {}
local createdByFactory = {}
local CMD = CMD
local DebugUnitCommand = f.DebugUnitCommand
local passiveCommands = {}
for name,id in pairs(CMD) do
	if type(name)=='string' and (name:match('STATE') or name=='REPEAT') then
		passiveCommands[id]=true
	end
end



local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")

local spGetUnitDefID                = Spring.GetUnitDefID
local spGetAllUnits                 = Spring.GetAllUnits
local spGetMyTeamID                 = Spring.GetMyTeamID
local spGetUnitPosition             = Spring.GetUnitPosition
local spAreTeamsAllied              = Spring.AreTeamsAllied
local spGetUnitTeam                 = Spring.GetUnitTeam
local spValidUnitID               	= Spring.ValidUnitID
local spGetGameSeconds				= Spring.GetGameSeconds
local spGetUnitHealth 				= Spring.GetUnitHealth
local spIsReplay                    = Spring.IsReplay
local spGetSpectatingState          = Spring.GetSpectatingState
local spGetCommandQueue             = Spring.GetCommandQueue
local spGetUnitRulesParam           = Spring.GetUnitRulesParam
local spGetGameFrame                = Spring.GetGameFrame
local spGetUnitHealth               = Spring.GetUnitHealth
local spGetUnitIsDead               = Spring.GetUnitIsDead
local spGetUnitCurrentCommand       = Spring.GetUnitCurrentCommand
local spGetSelectedUnits            = Spring.GetSelectedUnits
local spGetGroundHeight             = Spring.GetGroundHeight
local spGetSelectedUnits            = Spring.GetSelectedUnits
local spuGetMoveType                = Spring.Utilities.getMovetype
local spValidFeatureID              = Spring.ValidFeatureID
local spGiveOrderToUnit             = Spring.GiveOrderToUnit
local spGetCameraState				= Spring.GetCameraState
local spGetUnitHealth				= Spring.GetUnitHealth
local spGetUnitLosState 			= Spring.GetUnitLosState

local UnitDefs = UnitDefs


local classByName,familyByName={},{}


do
	local families = {
		['sub'] = 'ship', ['bomber'] = 'plane', ['ship'] = 'ship', -- put ship as key-value pair to check for gunship first, (indexed values are checked first in the iteration)
		'amph', 'strider', 'jump', 'spider', 'cloak', 'tank', 'veh', 'gunship', 'plane', 'shield', 'hover', 'chicken'
	}
	local unitClasses = {
	    raider = {
	        --planefighter = true,

	        shipscout = true,
	        shiptorpraider = true,
	        spiderscout = true,
	        shieldscout = true,
	        cloakraid = true,
	        shieldraid = true,
	        vehraid = true,
	        amphraid = true,
	        vehscout = true,
	        jumpraid = true,
	        hoverraid = true,
	        subraider = true,
	        tankraid = true,
	        gunshipraid = true,
	        gunshipemp = true,      
	        jumpscout = true,
	        tankheavyraid = true,

	        chicken = true,

	    },
	    skirm = {
	        cloakskirm = true,
	        spiderskirm = true,
	        jumpskirm = true,
	        shieldskirm = true,
	        shipskirm = true,
	        amphfloater = true,
	        vehsupport = true,
	        gunshipskirm = true,
	        shieldfelon = true,
	        hoverskirm = true,

	        chickens = true,
	        chicken_spidermonkey = true,
	    },
	    riot = {
	        amphimpulse = true, 
	        cloakriot = true,
	        shieldriot = true,
	        spiderriot = true,
	        spideremp = true,
	        jumpblackhole = true,
	        vehriot = true,
	        tankriot = true,
	        amphriot = true,
	        shiptorpraider = true,
	        hoverriot = true,
	        hoverdepthcharge = true,
	        gunshipassault = true,
	        shipriot = true,
	        striderdante = true,
	    },
	    assault = {
	        jumpsumo = true,
	        cloakassault = true,
	        spiderassault = true,
	        tankheavyassault = true,
	        tankassault = true,
	        shipassault = true,
	        amphassault = true,
	        vehassault = true,
	        shieldassault = true,
	        jumpassault = true,
	        hoverassault = true,
	        hoverheavyraid = true,
	        shipassault = true,
	        --bomberprec = true,
	        --bomberheavy = true,
	        gunshipkrow = true,
	        striderdetriment = true,

	        chickena = true,
	    },
	    arty = {
	        cloakarty = true,
	        amphsupport = true,
	        striderarty = true,
	        shieldarty = true,
	        jumparty = true,
	        veharty = true,
	        tankarty = true,
	        spidercrabe = true,
	        shiparty = true,
	        shipheavyarty = true,
	        shipcarrier = true,
	        hoverarty = true,
	        gunshipheavyskirm = true,
	        tankheavyarty = true,
	        vehheavyarty = true,
	    },
	    special1 = {
	        cloakheavyraid = true,
	        vehcapture = true,    
	        spiderantiheavy = true,   
	        shieldshield = true,
	        cloakjammer = true,
	        --planescout = true,
	    },
	    special2 = {
	        gunshiptrans = true,    
	        shieldbomb = true,
	        cloakbomb = true,
	        gunshipbomb = true,
	        jumpbomb = true,
	        gunshipheavytrans = true,
	        subtacmissile = true,
	        spiderscout = true,
	        amphtele = true,
	        --bomberdisarm = true,
	        striderantiheavy = true,
	        striderscorpion = true,
	    },
	    special3 = {
	        cloaksnipe = true,
	        amphlaunch = true,
	        --planescout = true,
	    },
	    aaunit = {
	        gunshipaa = true,
	        shieldaa = true,
	        cloakaa = true,
	        vehaa = true,
	        hoveraa = true,
	        amphaa = true,
	        spideraa = true,
	        jumpaa = true,
	        tankaa = true,
	        shipaa = true,
	    },
	    conunit = {
	        amphcon = true,
	        planecon = true,
	        cloakcon = true,
	        spidercon = true,
	        jumpcon = true,
	        tankcon = true,
	        hovercon = true,
	        shieldcon = true,
	        vehcon = true,
	        gunshipcon = true,
	        shipcon = true,
	        planecon = true,
	        striderfunnelweb = true,
	    },

	}
	for className,classTable in pairs(unitClasses) do
		for unitName in pairs(classTable) do
			classByName[unitName]=className
		end
	end
	for _,unit in pairs(UnitDefs) do
		for altFamily,family in pairs(families) do
			if not tonumber(altFamily) and unit.name:match(altFamily) or unit.name:match(family) then
				familyByName[unit.name] = family
				break
			end
		end
	end
end
--[[local function FalsifyTable(T)
	for k in pairs(T) do T[k]=false end
end--]]



local Cam
local idlingUnits = {}
local UnitDefs = UnitDefs
local Holder, Units
local name
local UnitsByDefID
local unitModels = {}
local MyUnits
local MyUnitsByDefID
local UnitCallins
local rezedFeatures
local maxUnits = Game.maxUnits
local cache
local myTeamID = Spring.GetMyTeamID()


-- local teams = Spring.GetTeamList()
-- local isChickenGame, chickenTeams = false, {}
-- for _, teamID in pairs(teams) do
-- 	local teamLuaAI = Spring.GetTeamLuaAI(teamID)
-- 	if teamLuaAI and string.find(string.lower(teamLuaAI), "chicken") then
-- 		isChickenGame=true
-- 		chickenTeams[teamID]=true
-- 		--break
-- 	end
-- end

local checkTime=CheckTime("start")

local shift,meta = false,false
local isBomber = {['bomberprec']=true,['bomberdisarm']=true,['bomberriot']=true,['bomberheavy']=true}
local isE = {['energywind']=true,['energysolar']=true,['energyfusion']=true,['energysingu']=true}
local specialWeapons = {['raveparty']=true,['zenith']=true,['mahlazer']=true,['staticnuke']=true,['staticmissilesilo']=true,['staticheavyarty']=true} -- weapons that often need to be ordered manually

local function dumfunc()
	-- a dummy func
end
local copy = function(t,t2)
	for k,v in pairs(t2) do
		t[k] = v
	end
	return t
end
local function clear(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

local function IsImpulseUnit(ud)
	for _, w in pairs(ud.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and (wd.customParams or EMPTY_TABLE).impulse then
			return true
		end
	end
	return false
end
local impulseDefID = {}
for defID,def in ipairs(UnitDefs) do
	if IsImpulseUnit(def) then
		impulseDefID[defID] = true
	end
end
local jumperDefID = {}
for defID,def in ipairs(UnitDefs) do
	if def.customParams.canjump then
	    if not (def.name:match('plate') or def.name:match('factory')) then
            jumperDefID[defID] = true
        end
    end
end
local CMD_RESURRECT = CMD.RESURRECT
local CMD_RECLAIM = CMD.RECLAIM

local UpdateUnitCommand
do
	local cmd, opt, tag
	local ptable = {}
	function UpdateUnitCommand(id,defID,teamID)
		 -- Echo("teamID,myTeamID", teamID, myTeamID)
		if defID and (teamID == myTeamID) then 
			cmd, opt, tag ,ptable[1], ptable[2], ptable[3], ptable[4], ptable[5] = spGetUnitCurrentCommand(id) -- works just fine memory wise

			if cmd and not passiveCommands[cmd] then
				widget:UnitCommand(id,defID,teamID,cmd,ptable,opt,tag)
			else
				-- widget:UnitIdle(id)
			end
		end
	end
end
local function AddToMines(unit, id, defID)
	MyUnits[id]=unit
	if not MyUnitsByDefID[defID] then MyUnitsByDefID[defID]={} end
	MyUnitsByDefID[defID][id]=unit
end

function manager:AddUnit(unit, id)
	local defID = unit.defID
	if not defID then 
		Throw('ASKING TO ADD UNIT WITHOUT DEFID',id,unit)
		
		return unit
	end

	-- if not UnitsByDefID[defID] then UnitsByDefID[defID]={} end
	-- UnitsByDefID[defID][id]=unit
	-- Echo('adding',unit.defID)
	if unit.isMine then
		AddToMines(unit, id, defID)
	end
	return unit
end
local function RemoveFromMines(id, defID)
	MyUnits[id]=nil
	if not defID then 
		-- Throw('Problem! my unit ' .. id .. " didn't have defID !")
		Echo('Problem! my unit ' .. id .. " didn't have defID !")
		Echo(debug.traceback())
		return unit 
	end
	if MyUnitsByDefID[defID] then
		MyUnitsByDefID[defID][id]=nil
		if not next(MyUnitsByDefID[defID],nil) then MyUnitsByDefID[defID]=nil end
	end
end
local function RemoveUnit(unit,id)
	-- unit.GetPos = dumfunc
	if unit.isMine then
		RemoveFromMines(id, unit.defID)
	end
	-- if not UnitsByDefID[defID] then -- FIXME : somehow there's been a crash by nil check, Units[id] has been created without having it in the byDefID table, need to find where, the crash happened on UnitLeftRadar
	-- 	return unit
	-- end
	-- UnitsByDefID[defID][id]=nil
	-- if not next(UnitsByDefID[defID],nil) then UnitsByDefID[defID]=nil end
	return unit
end


function manager:DefineUnit(id, defID, unit)
	-- Echo('produce...',id,os.clock())
	unit.createpos = {unpack(unit.pos)}
	if defID then
		setmetatable(unit, unitModels[defID].mt)
		unit.isDefined = true
	end
	return unit
end


local function CreateUnitModel(defID, ud)
	name = ud.name
	local moveType = spuGetMoveType(ud) or -1
	local isTransportable = not (ud.canFly or ud.cantBeTransported)
	local heavy
	if isTransportable then
		heavy = ud.customParams.requireheavytrans
	end
	local isUnit = moveType>-1

	local proto= {
		name                    = name,
		ud                      = ud,
		maxHP                   = ud.health,
		defID                   = defID,
		cost                    = ud.cost or 0,
	} 
	if isUnit then
		proto.isUnit				= true
		proto.isTransport			= ud.isTransport
		proto.isTransportable		= isTransportable
		proto.heavy					= heavy
		local class					= classByName[name] or isConDefID[defID] and 'conunit' or 'unknown' 
		proto.class                 = class
		proto.family                = familyByName[name] or 'unknown'
		proto.moveType				= moveType
		if isPlaneDefID[defID] then
			proto.isPlane           = true
			if isBomber[name] then
				proto.isBomber = true
			end
		elseif ud.isHoveringAirUnit then
			if name == 'athena' then
				proto.isAthena = true
			else
				proto.isGS = true
			end
		elseif jumperDefID[defID] then
			proto.isJumper = true
		end
		if name:match('scout') then
			proto.isScout = true
		elseif class=="conunit" then
			proto.isCon = true
		elseif name:match('strider') then
			proto.isStrider = true
		elseif isCommDefID[defID] then
			proto.isComm = true
		end
	else
		proto.isStructure             = true
		proto.isMex                   = name == "staticmex" or nil
		proto.isFactory               = isFactoryDefID[defID]
		proto.isFakeFac				 = not proto.isFactory and name:find('^factory') -- for zero wars mod
		proto.isCaretaker             = name == "staticcon" or nil
		proto.isDefense               = isDefenseDefID[defID]
		proto.isSpecialWeapon         = specialWeapons[name]
		proto.isStorage               = name == "staticstorage" or nil
		proto.class					 = 'unknown'
		proto.family                  = familyByName[name] or 'unknown'

		if isE[name] then
			if name=="energysolar" then
				proto.isSolar = true
			elseif name == "energywind" then
				proto.isWind = true
			elseif name == "energyfusion" then
				proto.isFusion = true
			end
		end

	end
	proto.isImpulse				 = impulseDefID[defID]
	proto.moveType				 = moveType
	proto.model = proto
	return proto
end



local function UpdateGuarding(proteged,guard,change)
	local protegedCard,guardCard=Units[proteged],Units[guard]
	if change=="proteged killed" and protegedCard then
		for guard in pairs(protegedCard.isGuarded) do
			if Units[guard] then
				Units[guard].isGuarding=false
			end
		end
	elseif change=="unguarding" and protegedCard and guard then
		if protegedCard then
			protegedCard.escortNum            = protegedCard.escortNum-1

			if guard and protegedCard.isGuarded then protegedCard.isGuarded[guard]     = nil end
			if protegedCard.escortNum==0 then
				protegedCard.isGuarded=nil
			end
		end
		guardCard.isGuarding              = false
		
	elseif change=="new guard" and protegedCard and guard then

		if protegedCard.escortNum==0 then protegedCard.isGuarded={} end
		if guard and protegedCard.isGuarded then protegedCard.isGuarded[guard]     = true end
		protegedCard.escortNum            = protegedCard.escortNum+1
		guardCard.isGuarding=proteged
	 end
end

local spTraceScreenRay = Spring.TraceScreenRay
local spGetMouseState = Spring.GetMouseState




 -- note: cmdTag is not cmdTag, I think it is playerID, to know the tag, I think we must check the next round in widget:Update() in the unitCommandQueue




function manager:UnitCreated(unit, id, defID, teamID,builderID) -- unit created can happen after unit finished ie when factory get plopped
	unit.isGtReclaimed  = false
	unit.isGtBuilt = true --not spGetUnitRulesParam(id, "ploppee") -- don't need anymore
	-- unit.isInSight = true
	if builderID then
		local builder = Units[builderID]
		if builder then
			unit.builtBy = builder.id
		end
	end
	-- if UnitCallins then for callin in pairs(UnitCallins) do callin(id, unit) end end
end
function manager:UnitFinished(unit, id, defID, teamID)
	unit.isGtBuilt = false
	unit.isGtReclaimed = false
	-- unit.isInSight = true
	if not unit.isDefined then
		manager:DefineUnit(id, defID, unit)
	end
	UpdateUnitCommand(id, defID, teamID)
	-- Echo('finished',id,unit.name,'idling?',unit.isIdling)
	-- if UnitCallins then for callin in pairs(UnitCallins) do callin(id, unit) end end
end
function manager:NewUnit(unit, id, defID, teamID, builderID)
	if not defID then
		return
	end
	manager:AddUnit(manager:DefineUnit(id, defID, unit), id)
	-- if not unit.health[5] then
	-- 	Throw('NO HEALTH BUILT FOR '.. id, UnitDefs[defID].humanName,'health?',spGetUnitHealth(id))
	-- end
	if builderID or unit.health[5] < 1 then -- VERIFY IF ALL GOOD
		self:UnitCreated(unit, id, defID, teamID, builderID)
	else
		self:UnitFinished(unit, id, defID, teamID)
	end
end

-- function widget.UnitReverseBuilt = manager.UnitReverseBuilt

function manager:UnitDestroyed(unit, id, defID, teamID)
	RemoveUnit(unit,id)

	-- if unit.isMine then 
	-- 	if unit.isGuarded then UpdateGuarding(id,nil,"proteged killed") end
	-- 	if unit.isGuarding then UpdateGuarding(unit.isGuarding,id,"unguarding") end
	-- end
	-- if UnitCallins then for callin in pairs(UnitCallins) do callin(id, nil,destroyedUnit) end end
end
function manager:Renew()
	for id, unit in pairs(Units) do
		RemoveUnit(unit,id)
	end
	for id in pairs(rezedFeatures) do
		rezedFeatures[id] = nil
	end
end
function manager:UnitChangedOwner(unit, id, isMine)
	if not id then
		Throw('NO ID')
		return
	end
	if isMine == unit.isMine then
		Throw('WONG FUNC CALL unit' .. unit.id ..'IS ALREADY ' .. (not isMine and 'NOT ' or '') .. 'MINE!')
		return
	end
	if isMine then
		AddToMines(unit, id, unit)
	elseif unit.isMine then
		RemoveFromMines(id, unit.defID)
	end
end

----------------------------------------------------------
----------------------------------------------------------
function widget:UnitReverseBuilt(id, defID, teamID)
	local unit = Units[id]
	if unit then 
		unit.isGtReclaimed = true
		unit.isGtBuilt = true
		--if UnitCallins then for callin in pairs(UnitCallins) do callin(id, unit) end end
	end
end


function widget:UnitCommand(id, _, _, cmd, params--[[, opts, playerID,  tag, fromSynced, fromLua--]])
-- Echo("UnitCommand: ", id, defID, teamID, cmd, params, opts, playerID,  tag, fromSynced, fromLua)
	if cmd~=CMD_RESURRECT then
		return
	end
	if params[2] then -- case this is an area resurrect, we can't know right now which feature is getting rezzed
		checkResurrect=checkResurect or {}
		checkResurrect[id]=true
	else
		rezedFeatures[params[1]-maxUnits]=true
	end

end
function widget:UnitCloaked(id, defID, team)
	local unit=Units[id]
	if unit then
		unit.isCloaked=true
	end
end


function widget:UnitDecloaked(id, defID, team)
	local unit=Units[id]
	if unit then
		unit.isCloaked=false
	end
end



function widget:GameFrame(gf)
	currentFrame = gf
	if checkResurrect then
		for id in pairs(checkResurrect) do
			local cmd,_,_,target = spGetUnitCurrentCommand(id)
			if cmd==CMD_RESURRECT then rezedFeatures[target-maxUnits]=true end
		end
		checkResurrect=nil
		return
	end
	if gf%30==0 and next(rezedFeatures) then
		for id in pairs(rezedFeatures) do
			if not spValidFeatureID(id) then rezedFeatures[id]=nil end
		end
	end
end

local busyCmd = {
	[CMD.ATTACK]=true,
	[CMD.REPAIR]=true,
}
function widget:CommandNotify(cmd, params, options)
	if cmd==CMD.RECLAIM and (not params[2] or params[5]) and Units[params[1]] then Units[params[1]].isGtReclaimed=true end
end
function widget:UnitCommandNotify(id, cmd, params, options)
	if cmd==CMD.RECLAIM and (not params[2] or params[5]) then
		local target = params[1]
		if target and target ~= id and Units[target] then
			Units[target].isGtReclaimed=true
	 	end
	end

end

function widget:KeyPress(key,mods)
	shift,meta = mods.shift,mods.meta
    -- if Debug.CheckKeys(key,mods) then
    --     return true
    -- end

	local debug=true
    if key == 267 and mods.alt then -- 267 == KP_/
        local id = spGetSelectedUnits()[1] or WG.PreSelection_GetUnitUnderCursor()
        if id and Units[id] then
        	local obj = debuggingUnit[id]
        	if obj then
        		obj:Delete()
        	end
        	local newobj = f.DebugWinInit2(widget,(Units[id].name and Units[id].name .. ' ' or '') .. 'id '..id,Units[id])
        	newobj.win.OnHide = {
        		function(self)
        			newobj:Delete()
        			debuggingUnit[id] = nil
        		end
        	}
            debuggingUnit[id] = newobj
            
        end
    end

	if debug and mods.ctrl and key==118 then -- Ctrl+V
		-- above 2 units the api_cluster_detection widget is getting crashed by gui_recv_unit_indicator
		-- I don't try to debug it as it is useless
		local mx, my = spGetMouseState()
		local type, id = spTraceScreenRay(mx,my)
		if type == 'unit' then
			local team = spGetUnitTeam(id)
			if team~=myTeamID and spAreTeamsAllied(spGetMyTeamID(), team) or Spring.IsCheatingEnabled() then
				local uid = Spring.GetSelectedUnits()[1]
				if uid then
					-- Echo('unit',uid,'team:',Spring.GetUnitTeam(uid),Spring.GetUnitAllyTeam(uid),Spring.IsUnitAllied(uid))
					Echo('Give ' .. uid, UnitDefs[spGetUnitDefID(uid)].humanName .. ' to team ' .. team)
					Spring.ShareResources(team,"units") -- can only give own stuff, even with cheats active
				end
			end
		end
		return true
	end
end
function widget:KeyRelease(key,mods)
	shift,meta = mods.shift,mods.meta
end


function widget:AfterInit(dt) -- this replace widget:Update() for the first round after Initialize()
	if next(WG.UnitsIDCard.subscribed) then
		for w_name in pairs(WG.UnitsIDCard.subscribed) do
			if widgetHandler.knownWidgets[w_name] then
				Echo('[' .. widget:GetInfo().name .. ']:' .. w_name..' is dependant, reloading it...')
				Spring.SendCommands("luaui enablewidget "..w_name)
				local w = widgetHandler:FindWidget(w_name)
				if not w then
					Echo('[' .. widget:GetInfo().name .. ']: [WARN]: There was a problem reloading' .. w_name)
				elseif w.UnitUpdate then
					if not UnitCallins then Units.UnitCallins={} ; UnitCallins=Units.UnitCallins end
					UnitCallins[w.UnitUpdate]=true
				end
			else
				Echo('[' .. widget:GetInfo().name .. ']: [WARN]: ' .. 'widget' .. w_name .. " is unknown, couldn't reload it")
			end

		end
	end
	widget.Update = widget._Update
	widget._Update = nil
	-- widgetHandler:RemoveWidgetCallIn('Update',self)
end




-- local DisableOnSpec = f.DisableOnSpec(_,widget,'setupSpecsCallIns') -- initialize the call in switcher
function widget:Initialize()
	-- if --[[spIsReplay() or--]] string.upper(Game.modShortName or '') ~= 'ZK' then
	-- 	Echo(widget:GetInfo().name .. ' is only compatible with ZK mod')
	-- 	widgetHandler:RemoveWidget(self)
	-- 	return
	-- end 
	-- if Spring.GetSpectatingState() then
	-- 	widgetHandler:RemoveWidget(self)
	-- 	return
	-- end
	Echo('UnitsIDCard Loading...')
	Cam = WG.Cam
	if not Cam then
		widget.status = widget:GetInfo().name .. ' requires HasViewChanged'
		Echo(widget.status)
		widgetHandler:RemoveWidget(widget)
		return
	end

	-- Debug = f.CreateDebug(Debug,widget,options_path)
	-- DisableOnSpec(widgetHandler,widget)
	-- CheckIfSpectator()

	myTeamID = spGetMyTeamID()  

	Holder = WG.UnitsIDCard
	if not Holder then
		Holder = {
			units = Cam.Units, -- persistent table
			subscribed = {},
			UnitCallins= {},
			-- byDefID= {},
			mine={ byDefID = {} },
			rezedFeatures = {},
		}
		WG.UnitsIDCard = Holder
	end

	Holder.manager = manager
	Holder.active = true
	Holder.creation_time = os.clock()
	Units = Holder.units
	rezedFeatures = Holder.rezedFeatures
	UnitsByDefID = Holder.byDefID
	MyUnits = Holder.mine
	MyUnitsByDefID = MyUnits.byDefID

	for defID, def in pairs(UnitDefs) do
		unitModels[defID] = CreateUnitModel(defID, def)
		unitModels[defID].mt = {__index = unitModels[defID]}
	end
	for id, unit in pairs(Units) do
		if unit.defID then
			manager:NewUnit(unit, unit.id, unit.defID, unit.teamID)
		end
	end
	WG.UnitsIDCard.active = true
end

function widget:Shutdown()
	-- Echo('UnitsIDCard2s shutdown')
	if WG.UnitsIDCard then
		WG.UnitsIDCard.active = false
	end
	Echo(">>>>> ! UnitsIDCard Shutdown ! <<<<<")
end




-- Memorize Debug config over games
function widget:SetConfigData(data)
    -- if data.Debug then
    --     Debug.saved = data.Debug
    -- end
    if data.debugProps then
    	for k,v in pairs(debugProps) do
    		debugProps[k] = nil
    	end
    	for k,v in pairs(data.debugProps) do
    		debugProps[k] = v
    	end
    end
    if data.filterProps then
    	for k,v in pairs(filterProps) do
    		filterProps[k] = nil
    	end
    	for k,v in pairs(data.filterProps) do
    		filterProps[k] = v
    	end
    end
end
function widget:GetConfigData()
	local ret = {debugProps = debugProps, filterProps = filterProps}

	-- if Debug.GetSetting then
	-- 	ret.Debug = Debug.GetSetting()
 --    end
	return ret
end

do -- debugging
	local spValidUnitID                 = Spring.ValidUnitID
	local spGetUnitPosition             = Spring.GetUnitPosition
	local glColor                       = gl.Color
	local glText                        = gl.Text
	local glTranslate                   = gl.Translate
	local glBillboard                   = gl.Billboard
	local glPushMatrix                  = gl.PushMatrix
	local glPopMatrix                   = gl.PopMatrix
	local spIsUnitInView 				= Spring.IsUnitInView
	local spIsSphereInView				= Spring.IsSphereInView
	local green, yellow, red, white, blue, orange
	= {unpack (COLORS.green) }, { unpack (COLORS.yellow) }, {unpack (COLORS.red)}, {unpack (COLORS.white)}, {unpack (COLORS.blue)}, {unpack (COLORS.orange)}
	-- slightly brighter color to read them better
	for i,c in ipairs({green, yellow, red, white, blue, orange}) do
		for i=1,3 do
			if c[i] < 1 then
				c[i] = math.min(c[i] + 1/4, 1)
			end
		end
	end
	local glLists = {}
	local function firstInTable(t)
		local k,v = next(t)
		if k == nil then
			return ' {}'
		else
			return ' {' .. tostring(k)..':'..tostring(v) ..(next(t, k) and ' ...' or '') .. '}'
		end
	end
	function widget:DrawWorld()
		if not (SHOW_UNIT_PROP and (debugProps and debugProps[1]) or options.showAllProps.value) then
			return
		end
		local showAllProps = options.showAllProps.value
		if (Cam and Cam.relDist or GetCameraHeight(spGetCameraState()))>2000 then
			return
		end
		-- gl.DepthTest(false)
		local debugProps = debugProps
		if not showAllProps then
			if next(filterProps) then
				debugProps = copy(debugProps)
				for k,v in pairs(debugProps) do
					if filterProps[k] then
						debugProps[k] = nil
					end
				end
			end
		end
		-- local Units = WG.OutOfRadar
		for id,unit in pairs(Units) do
			local ix,iy,iz = unit:GetPos(1) -- spGetUnitPosition(id)

			if ix --[[and spIsUnitInView(id)--]]and spIsSphereInView(ix,iy,iz) then
				glPushMatrix()
				glTranslate(ix,iy,iz)
				glBillboard()
				glColor(unit.isMine and green or unit.isAllied and blue or unit.isEnemy and orange)
				local off=0
				if showAllProps then
					
					for prop_name, prop in pairs(unit) do
						if not filterProps[prop_name] then
							off=off-6
							if type(prop) == 'table' then
								prop = firstInTable(prop)
							end
							glText(prop_name .. ' = ' .. tostring(prop), 0, off, 5,'nho')
						end
					end

				else
					for _,prop_name in pairs(debugProps) do
						local prop
						if prop_name:find('%.') then
							local t_name, key = prop_name:match('([%w_]+)%.([%w_]+)')
							if t_name and type(unit[t_name]) == 'table' then
								prop = unit[t_name][tonumber(key) or key]
							end
						else
							prop = unit[prop_name]
						end
						if prop then
							off=off-6

							if type(prop) == 'table' then
								prop = firstInTable(prop)
							end
							local str = (prop_name and prop_name ~= 'name' and prop_name..' ' or '') .. (type(prop)=='boolean' and '' or tostring(prop))
							-- if prop_name == 'manualOrder' then
							-- 	prop_name,prop = prop[1],true
							-- end
							glText(str, 0, off, 5,'nho')
						end
					end
				end
				glPopMatrix()
			end

		end
		glColor(white)
		-- gl.DepthTest(true)
	end
end




f.DebugWidget(widget)
