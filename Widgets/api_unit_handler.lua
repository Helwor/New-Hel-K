function widget:GetInfo()
	return {
		name      = "Unit Handler",
		desc      = "Manage Centralized Unit Database",
		author    = "Helwor",
		date      = "May 2023",
		license   = "GNU GPL, v2 or later",
		layer     = -10e36,
		enabled   = true,  --  loaded by default?
		api       = true,
		handler   = true,
	}
end
-- requires HasVienChanged

--IMPORTANT NOTE: 
-- !! Update come before PreUnit, unit visible can be detected in update, BUT ICONIZED STATE IS DETECTED FIRST AT PRE UNIT
-- !! PreUnit order is reversed, widget having lower layer will NOT COME FIRST FOR THIS CALLIN
-- so we have to make another with high layer for registering iconized unit
-- !! Unit discovered directly by Los WILL TRIGGER ENTEREDRADAR AFTER
-- !! Unit STRUCTURE discovered By Los ONCE will be seen as static build icon when entering radar again, BUT THE DEFID CANNOT BE RETRIEVED
	-- to work around this when switching view as spec and determine if a unit structure has been discovered by the current ally team, we check the position of the supposed structure and see if its x and z are multiple of 8
	-- TODO DISCERN BETWEEN UNIT BLUEPRINT AND ACTUAL STRUCTURE
-- aswell, if speccing,  it is not possible to know every building that has been discovered but now out of radar by an ally team X if it has not been watched all along (FIX IMPLEMENT ACCESS FROM ENGINE)
-- FIXED Destroyed non ally in radar doesnt trigger anything unless my PR is approven
-- !! the currentFrame from GameFrame can be different from spGetGameFrame(), spGetGameFrame() can be more actual, while GameFrame callin has still not updated, we're not using spGetGameFrame() in here
-- !! enemy terra unit in radar can leave radar without any other sign of existence before (probably as soon as it is created)
-- !! Plop Fac trigger first UnitFinished then UnitCreated !
-- !! In FFA and specfullview it is not possible to know which unit is visible from which allyteam, we only can know that a unit of a teamID has entered the radar/los for a certain allyteam, but no way to know which one without constantly checking for the losState
-- -> FIXED WITH PR, now having fromAllyTeam and defID getting fed -> TODO: FINISH IMPLEMENTATION
-- !! BUG? witnessed during a 1v1 'UnitEnteredLos' for allyTeam 2 which doesnt exist,  but teamID 2 is the gaia team (ally team 16),  (unit entered los being a structure) when nuke destroy a base in Otago.
--    http://zero-k.info/Battles/Detail/1962757
--    I guess it has to do with the crater made by the nuke pulling down the structure under water level before getting destroyed

------------- THIS HAS BEEN TESTED LOCALLY ONLY FOR NOW
-- !! UNIT ENTERING LOS spIsPosInLos start returning true between 2 GameFrames
--    then just after the second GameFrame UnitEnteredLos trigger
--    spIsUnitInLos DOESN'T DETECT IT UNTIL THEN
--    btw height given in isPosInLos doesnt matter
--    unit attribute cannot be retrieved until UnitEnteredLos got triggered
--    sequence:
--		GameFrame -> nothing
--		other callins -> detect pos in los
--		2nd GameFrame -> nothing new
--		UnitEnteredLos gets triggered, can find unit in los and units attributes now
--		UnitEnteredRadar nothing new

-- !! UNIT LEAVING LOS, inversely spIsPosInLos stop returning true between 2 GameFrames
--    BUT THIS TIME IsUnitInLos ALSO STOPS DETECTING IT
--    then UnitLeftLos trigger just after the second GameFrame and units attributes cannot be retrieved anymore
--    sequence:
--		GameFrame -> detect pos in los and unit in los
--		other callins -> stop detecting both, but can still get units attributes and correct pos
--		2nd GameFrame -> nothing new
--		UnitLeftLos gets triggered, nothing new BUT POS BECOME "RADARISED" even with no radar coverage
--		UnitLeftRadar -> cannot retrieve attributes anymore
--		other callins -> nothing new
--------------------------------
local Echo = Spring.Echo
local function Throw(...)
	Echo(...)
	error(debug.traceback())
end
local allyTeamByTeam = {}
local isFFA = Spring.Utilities.Gametype.isFFA()
local manager
local UPDATE_FRAME_HEALTH = 5
local DEBUG_VIS = false
local DEBUG_DETECT = false
local DUMMY_HEALTH = {50,50,0,0,1}
local hasSwitchedSide = false
local INIT, IGNORE_INVALID = false, false

local DESTROYED = {} -- keep track of recently destroyed unit to avoid false positive when detecting entered/left los/radar created/finished etc ...
local CLEANUP_RATE = 60
local cleanUpFrame = Spring.GetGameFrame() + CLEANUP_RATE
local tickSound = LUAUI_DIRNAME .. 'Sounds/buildbar_rem.wav'

local IGNORED = {}
local DEBUGGED = {}
local MEM_UNITS = {}
local WAIT
local destroyedByLosCheck = {}
local CHECK_FOR_RADAR = {}

local Units = {}
local guessed = {}

local myTeamID = Spring.GetMyTeamID()
local myAllyTeamID
local myPlayerID = Spring.GetMyPlayerID()
local force_update = false
local lastDead
local osclock = os.clock
local NOW = osclock()
local currentFrame = Spring.GetGameFrame()

local fullview, isSpec

local GetIconMidY

local fullTraceBackError = true
local DebugWidget
local f = WG.utilFuncs


local spIsUnitVisible = Spring.IsUnitVisible
local spIsUnitInView = Spring.IsUnitInView
local spIsUnitIcon = Spring.IsUnitIcon
local spGetVisibleUnits = Spring.GetVisibleUnits
local spGetCameraPosition = Spring.GetCameraPosition
local spGetCameraVectors = Spring.GetCameraVectors
local spGetCameraFOV = Spring.GetCameraFOV
local spGetGameFrame = Spring.GetGameFrame
local spGetCameraState = Spring.GetCameraState
local spTraceScreenRay = Spring.TraceScreenRay
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGetSpectatingState = Spring.GetSpectatingState
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitLosState = Spring.GetUnitLosState
local spGetGlobalLos = Spring.GetGlobalLos
local spGetLocalAllyTeamID = Spring.GetLocalAllyTeamID
local spGetMyTeamID = Spring.GetMyTeamID
local spAreTeamsAllied = Spring.AreTeamsAllied
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitTeam = Spring.GetUnitTeam
local ALL_UNITS       = Spring.ALL_UNITS
local spGetMyAllyTeamID = Spring.GetMyAllyTeamID
local spGetUnitViewPosition = Spring.GetUnitViewPosition
local spGetUnitIsDead = Spring.GetUnitIsDead
local spValidUnitID = Spring.ValidUnitID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitBuildFacing = Spring.GetUnitBuildFacing
local spIsPosInLos = Spring.IsPosInLos
local spIsUnitInLos = Spring.IsUnitInLos
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam

local formatColumnInfolog = f.formatColumnInfolog



if fullTraceBackError then
	DebugWidget = f.DebugWidget
end

local structureDefID = {}
do
	local spuGetMoveType = Spring.Utilities.getMovetype
	for defID, def in pairs(UnitDefs) do
		if not spuGetMoveType(def) and def.name ~= 'wolverine_mine' and def.name ~= 'terraunit' then
			structureDefID[defID] = true
		end
	end
end
local ignoreHealthDefID = {
  [UnitDefNames['wolverine_mine'].id] = true,
  [UnitDefNames['shieldscout'].id] = true,
  [UnitDefNames['jumpscout'].id] = true,
  -- [UnitDefNames['terraunit'].id] = true,
}
local internalKeys = {
	id = true,
	frame = true,
	isAllied = true,
	isMine = true,
	isEnemy = true,
	teamID = true,
	isInSight = true,
	isInRadar = true,
	health = true,
	defID = true,
	checkHealth = true,
	isKnown = true,
	pos = true,
	GetPos = true,
	isStructure = true,
	facing = true,
	created = true,
	created_from = true,
	isDiscovered = true,
	isDefined = true,
	knownByAlly = true,
	recycled = true,
	guessed = true,
	guessed2 = true,
	guessed3 = true,
	guessed4 = true,
}


local allyTeams = {}
for i,team in pairs(Spring.GetTeamList()) do
	-- Echo("i, team, Spring.GetTeamAllyTeamID(team) is ", i, team, Spring.GetTeamAllyTeamID(team))
	allyTeams[Spring.GetTeamAllyTeamID(team)] = true
end
local FFA = not not allyTeams[2]
--------- Structure Discovered per AllyTeam
local allStructures = WG.allStructures or {} -- add also own made structures?
WG.allStructures = allStructures
local structureDiscovered
WG.structDiscoveredByAllyTeams = WG.structDiscoveredByAllyTeams
	 -- work around to fix unknown allyTeam told by UnitenteredLos, explained at top of the file
	or setmetatable({}, {__index = function(t, k) rawset(t, k, {}) return t[k] end})
local structDiscoveredByAllyTeams = WG.structDiscoveredByAllyTeams
local function RemoveFromAllStructures(id)
	if allStructures[id] then
		for allyTeam, structures in pairs(WG.structDiscoveredByAllyTeams) do
			structures[id] = nil
		end
		allStructures[id] = nil
	end
end
for i,team in pairs(Spring.GetTeamList()) do
	allyTeamByTeam[team] = Spring.GetTeamAllyTeamID(team)
end
for _, allyTeam in pairs(allyTeamByTeam) do
	-- Echo("allyTeam is ", allyTeam)
	if not structDiscoveredByAllyTeams[allyTeam] then
		structDiscoveredByAllyTeams[allyTeam] = {}
	end
end
-- for allyTeam, structures in pairs(WG.structDiscoveredByAllyTeams) do
-- 	for id in pairs(structures) do
-- 		local struct = allStructures[id]
-- 		Echo('discovered structure '.. id, UnitDefs[struct.defID], 'by ally #' .. allyTeam)
-- 	end
-- end


local function UpdateStructureDiscovered()
	-- for id, struct in pairs(allStructures) do
	-- 	-- Echo('check to destroy id ' .. id, UnitDefs[struct.defID].humanName,'pos in los',spIsPosInLos(struct[4], struct[5], struct[6]),'unit in los', spIsUnitInLos(id))
	-- 	if spIsPosInLos(struct[1], struct[2], struct[3], fullview ~= 1 and myAllyTeamID or nil) then
	-- 		-- !! UNIT ENTERING LOS appear ONE FRAME LATER of spIsInLos returing true, (height given in isPosInLos doesnt matter)

	-- 		-- local _,_,_, x, y, z = spGetUnitPosition(id, true)
	-- 		local x, y, z = spGetUnitPosition(id)
	-- 		if x ~= struct[1] and z ~= struct[3] then
	-- 			local unit = Units[id]
	-- 			if unit and unit.defID == struct.defID then
	-- 				widget:UnitDestroyed(id, struct.defID, struct.teamID)
	-- 			else
	-- 				local knownByAlly = struct.knownByAlly
	-- 				knownByAlly[myAllyTeamID] = nil
	-- 				allStructures[id] = nil
	-- 			end
	-- 		end
	-- 	end
	-- end
	-- local oldStructureDiscovered = structureDiscovered
	structureDiscovered = structDiscoveredByAllyTeams[myAllyTeamID]

	for id, unit in pairs(Units) do
		if unit.isStructure then
			if not structureDiscovered[id] then
				local struct = allStructures[id] 
				if not struct or struct.defID == unit.defID then
					local pos = unit.pos
					unit.isDiscovered = false
					if fullview ~= 1 and allyTeamByTeam[unit.teamID] ~= myAllyTeamID then
						for i, p in ipairs(pos) do
							-- Echo('SHUFFLEPOS for ' .. id)
							pos[i] = p + math.random() * 60 * (math.random()>0.5 and 1 or -1)
						end
						unit.shuffledPos = true
						unit.isKnown = nil
					end
				end
			end
		end
	end
	for id, struct in pairs(structureDiscovered) do
		local unit = Units[id]
		if unit and struct.defID == unit.defID then
			unit.isDiscovered = true
			local pos = unit.pos
			pos[1], pos[2], pos[3], pos[4], pos[5], pos[6] = unpack(struct)
			unit.shuffledPos = false
			unit.isKnown = true
			if not unit.isDefined then
				local defID = struct.defID
				unit.defID = defID
				manager:DefineUnit(id, defID, unit)
			end
			unit.facing = struct.facing
			-- Echo('setting structure '.. unit.ud.humanName .. ' as discovered for allyTeam ' .. myAllyTeamID)
		end
	end
end
local function GetIsDiscovered(id, unit, dontVerify)
	local struct = allStructures[id]
	if not struct and unit.isStructure and unit.defID then
		struct = {id = id, unit = unit, teamID = unit.teamID, defID = unit.defID, knownByAlly = unit.knownByAlly,  facing = unit.facing, unpack(unit.pos)}
		allStructures[id] = struct
	end
	if struct then
		if unit.shuffledPos then
			local pos = unit.pos
			pos[1], pos[2], pos[3], pos[4], pos[5], pos[6] = spGetUnitPosition(id, true)
			struct[1], struct[2], struct[3], struct[4], struct[5], struct[6] = unpack(pos)
			unit.shuffledPos = false
		end
		unit.isDiscovered = true
		local knownByAlly = struct.knownByAlly
		knownByAlly[myAllyTeamID] = true
		unit.knownByAlly = knownByAlly
		unit.isKnown = true
		structureDiscovered[id] = struct
		if not unit.defID then
			unit.defID = struct.defID
			manager:DefineUnit(id, unit.defID, unit)
		end
		unit.facing = struct.facing
	elseif not dontVerify then
		unit.knownByAlly = unit.knownByAlly or {}
		guessed[id] = unit -- will be verified
	end
end
----------




local inSight
local Cam


options_path = 'Hel-K/' .. widget:GetInfo().name
options = {}

options.healthCheck = {
	name = 'Health Check Frame Rate',
	desc = "how often in frame we look for known unit's health",
	type = 'number',
	min = 1, max = 30, step = 1,
	value = UPDATE_FRAME_HEALTH,
	OnChange = function(self)
		UPDATE_FRAME_HEALTH = self.value
	end
}
options.debugVis = {
	name = 'Show Units Dots per Visibility',
	type = 'bool',
	desc = '/debugvis',
	value = DEBUG_VIS,
	OnChange = function(self)
		DEBUG_VIS = self.value
	end,
	action = 'debugvis',

}
options.debugDetect = {
	name = 'Show State changes in console',
	type = 'bool',
	desc = '/debugdetect',
	value = DEBUG_DETECT,
	OnChange = function(self)
		DEBUG_DETECT = self.value
	end,
	action = 'debugstate',
	checkForChangeAtLoading = true,
	-- onChangeAtLoading = true,

}


local function dbgStateComment(id, event)
	-- return  ('%-8s %-20s %-10s %s'):format(tostring(id), event, Units[id] and '<unit>' or '', INIT and '(init)' or IGNORE_INVALID and '(changed side)' or '' ) 
	return formatColumnInfolog(
		id, 8,
		event, 17,
		Units[id] and '<unit>' or '', 10,
		INIT and '(init)' or IGNORE_INVALID and '(changed side)' or '' 
	)   
	-- return formatColumn(
	--  id, 45,
	--  event, 90,
	--  Units[id] and '<unit>' or '', 50,
	--  INIT and '(init)' or IGNORE_INVALID and '(changed side)' or '' 
	-- ) 
end



local function GetPos(self, threshold, force) -- method of unit to get its position, to be used by any widget, threshold is the frame delta acceptance
	local pos = self.pos
	if (force or self.isInRadar) and (
		threshold < 0
		or not (self.isStructure and self.isKnown) and (pos.frame or -2) < currentFrame + (threshold or 0)
	) then
		pos.frame = currentFrame
		local p1 = spGetUnitPosition(self.id)
		
		if not p1 then
			if not DEBUGGED[self.id] then
				Spring.PlaySoundFile(tickSound, 0.95, 'ui')
				Echo('UNIT',self.id,self.defID, self.defID and UnitDefs[self.defID].humanName,
				 'POS IS ASKED WHILE NOT HAVING ANY',pos[1],"=>",p1)
				Echo('currentFrame', currentFrame)
				Echo('isValid',spValidUnitID(self.id),'isDead', spGetUnitIsDead(self.id))
				local losState = Spring.GetUnitLosState(self.id, Spring.GetMyAllyTeamID())
				Echo('losState:', losState, losState and table.toline(losState))
				-- Echo('IS IN RADAR?', Spring.IsUnitInRadar(self.id, Spring.GetMyAllyTeamID())) -- IsUnitInRadar is broken
				Echo('Created since', NOW - self.created)
				Echo('DESTROYED IN THE PAST?',DESTROYED[self.id] and currentFrame - DESTROYED[self.id])
				f.Page(self--[[,{all = true, content = true}--]])
				Throw('')
				-- Echo('TRACE BACK')
				-- Echo(debug.traceback())

				DEBUGGED[self.id] = currentFrame
				DEBUG_DETECT = true
				WAIT = currentFrame + 20
			end
			-- error(   )
		else
			pos[1], pos[2], pos[3], pos[4], pos[5], pos[6] = spGetUnitPosition(self.id,true)
		end
	end
	return  pos[1], pos[2], pos[3], pos[4], pos[5], pos[6]

end

-----------------------------------------
local function CreateUnknownUnit(id, teamID)
	local unit = { 
		id = id,
		frame = currentFrame,
		teamID = teamID,
		isMine = false,
		isAllied = false,
		isEnemy = true,
		isInSight = false,
		isInRadar = true,
		defID = false,
		checkHealth = false,
		health = DUMMY_HEALTH,
		isKnown = false,
		pos = {frame = currentFrame,spGetUnitPosition(id, true)},
		GetPos = GetPos,
		isStructure = false,
		created = NOW,
		created_from = 'CreateUnknownUnit',
	}
	if not unit.pos[1] then
		Echo('UNKNOWN UNIT ' .. id .. ' CREATED WITHOUT POS !')
	end
	return unit
end
local debugged = false
local function CreateKnownUnit(id, teamID, defID)
	if not defID then
		defID = spGetUnitDefID(id)
	end
	if not debugged and not tonumber(defID) then
		debugged = true -- never happened
		Echo('KNOWN UNIT CREATION, DONT HAVE DEFID',defID)
		Echo(debug.traceback())
	end
	local health
	local ignore = ignoreHealthDefID[defID]
	if ignore then
		health = DUMMY_HEALTH
	else
		health = {frame = currentFrame,spGetUnitHealth(id)}
	end
	local isMine = teamID == myTeamID
	local isAllied = not isMine and spAreTeamsAllied(teamID, myTeamID)
	local isStructure = structureDefID[defID] or false
	local facing, knownByAlly
	if isStructure then
		facing = spGetUnitBuildFacing(id)
		knownByAlly = {}
	end

	local unit = { 
		id = id,
		frame = currentFrame,
		teamID = teamID,
		isMine = isMine,
		isAllied = isAllied,
		isEnemy = not isAllied and not isMine,
		isInSight = true,
		isInRadar = true,
		defID = defID,
		health = health,
		checkHealth = not ignore,
		isKnown = true,
		pos = {frame = currentFrame, spGetUnitPosition(id, true)},
		GetPos = GetPos,
		isStructure = isStructure,
		knownByAlly = knownByAlly,
		facing = facing,
		created = NOW,
		created_from = 'CreateKnownUnit',
	} 
	return unit
end

local function UpdateAllegiance(unit, id, teamID)

	unit.teamID = teamID
	local isMine = teamID == myTeamID
	local isAllied = not isMine and spAreTeamsAllied(teamID, myTeamID)
	if isMine ~= unit.isMine then
		manager:UnitChangedOwner(unit, id, isMine)
	end
	unit.isMine = isMine
	unit.isAllied = isAllied
	unit.isEnemy = not isAllied and not isMine

end
local debugged = false
local function UpdateUnitDefID(unit, id, defID, teamID, isInSight)
	if unit.defID then
		manager:UnitDestroyed(unit, id, unit.defID, teamID)
	end
	unit.defID = defID
	if not debugged and not tonumber(defID) then
		debugged = true
		Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		Throw('DEFID NOT A NUMBER FOR UNIT',unit.id,unit.name,unit.defID,'defID:',defID)
	end
	local isStructure = structureDefID[defID]
	if isStructure then
		-- local posbefore = unit.pos and unit.pos[1]
		unit:GetPos(-1, true)
		-- if unit.pos[1]%8 ~= 0 or unit.pos[3]%8 ~= 0 then
		-- 	Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		-- 	Echo('WRONG UNIT POS FOR', id, UnitDefs[defID].name, unit.pos[1], 'in radar:', Spring.IsUnitInRadar(id), 'posbefore', posbefore)
		-- 	Echo(debug.traceback())
		-- end
		unit.facing = spGetUnitBuildFacing(id)
		local struct = allStructures[id]
		local knownByAlly
		if struct and struct.defID == defID then
			knownByAlly = struct.knownByAlly
		else
			knownByAlly = {}
		end
		unit.knownByAlly = knownByAlly
		unit.isStructure = true
		unit.shuffledPos = nil
	elseif unit.isStructure then
		-- RemoveFromAllStructures(id)
		allStructures[id] = nil
		unit.isDiscovered = nil
		unit.knownByAlly = nil
		unit.isStructure = false
		local struct = discoveredStructure[id]
		if struct then
			struct.knownByAlly[myAllyTeamID] = nil
			discoveredStructure[id] = nil
		end
		unit.facing = nil
	end
	
	if ignoreHealthDefID[defID] then
		unit.health = DUMMY_HEALTH
	elseif isInSight == false then
		if unit.health == DUMMY_HEALTH then
			unit.health = {frame = currentFrame, unpack(DUMMY_HEALTH)}
		end
	else
		-- local hp, maxHP, paraDamage, capture, build = spGetUnitHealth(id)
		-- if not hp then
		--  hp, maxHP, paraDamage, capture, build = unpack(DUMMY_HEALTH)
		-- end
		-- unit.health = {frame = currentFrame, hp, maxHP, paraDamage, capture, build}
		unit.health = {frame = currentFrame, spGetUnitHealth(id)}
	end
	manager:NewUnit(unit, id, defID, teamID)
end
local function DetectUnitChanges(unit, id, teamID, defID, isInSight)
	if teamID ~= unit.teamID then
		UpdateAllegiance(unit, id, teamID)
	end
	if defID then
		if defID ~= unit.defID or not unit.isKnown then
			if unit.defID then
				-- Echo('unit ', id, 'got recycled !?', UnitDefs[unit.defID].name, UnitDefs[defID].name)
				unit.recycled = defID ~= unit.defID
			end
			UpdateUnitDefID(unit, id, defID, teamID, isInSight)
		end
	end

end

-- local function UpdateUnit(unit, id, teamID, defID, isInSight, isKnown, isKnownByAlly)
-- 	local wasStructure, currentHealth
-- 	if defID then
-- 		if not unit.isDefined then
-- 			manager:DefineUnit(id, defID, unit)
-- 		elseif unit.defID ~= defID then
-- 			if unit.defID then
-- 				widget:UnitDestroyed(id)
				
-- 			end
-- 			manager:DefineUnit(id, defID, unit)
-- 		end
-- 	end
-- end

local function UpdateAll(fullview)
	guessed = {}
	-- Echo("#spGetVisibleUnits(ALL_UNITS,radius,true) is ", #spGetVisibleUnits(ALL_UNITS,radius,true))
	-- Echo('update all')
	-- if Units == Cam.Units then

		-- if changedSide or oldview~=fullview then
			for id, unit in pairs(Units) do
				if id == 888 then
					Echo('discovered:', structureDiscovered[id])
				end
				-- updating our detected units
				if spGetUnitIsDead(id) then -- can happen often
					--Echo('detected just dead unit',id,' while switching side!')
					widget:UnitDestroyed(id)
				else
					local isValid = spValidUnitID(id)
					if not isValid then
						if fullview == 1 then -- can happen often
							-- Echo('detected invalid unit',id,' while switching in fullview!')
							widget:UnitDestroyed(id)
						else
							-- case: undetected, we changed side
							UpdateAllegiance(unit, id, unit.teamID)
							if unit.isInSight then
								widget:UnitLeftLos(id, unit.teamID)
							end
							if unit.isInRadar then
								widget:UnitLeftRadar(id, unit.teamID)
								-- Echo('update all set out of radar',id,UnitDefs[unit.defID].humanName,'isInRadar?', unit.isInRadar)
							end
							-- we can't know for sure in the case of a building, if that unit has been discovered by the new watched ally team 
							-- if we weren't speccing that team when it discovered it
							unit.isKnown = (not not structureDiscovered[id]) or nil
						end
					else -- case: registered unit is valid
						local teamID = spGetUnitTeam(id)
						UpdateAllegiance(unit, id, teamID)
						-- changing Los and health check for already known units

						local isInSight, isInRadar, isKnown = false, false, nil
						if fullview==1 then
							isInSight = true
							isInRadar = true
							isKnown = true
						else
							local losState = spGetUnitLosState(id)
							if losState then
								isInSight = losState.los
								isInRadar = losState.radar
								isKnown =  losState.typed
							end
							if isKnown then
								local defID = spGetUnitDefID(id)
								if unit.defID ~= defID then
									UpdateUnitDefID(unit, id, defID, unit.teamID, not not isInSight)
								end
							end
						end
						if isInRadar then
							if not unit.isInRadar then
								widget:UnitEnteredRadar(id, teamID)
							end
							local x,_,z = unit:GetPos(-1)
							if isInSight then
								if not unit.isInSight then
									widget:UnitEnteredLos(id, teamID)
									-- if not ignoreHealthDefID[unit.defID] and not unit.health[1] then
									-- 	local health = unit.health
									-- 	local hp, maxHP, paraDamage, capture, build = spGetUnitHealth(unit.id)
									-- 	-- if not hp then
									-- 	--  hp, maxHP, paraDamage, capture, build = unpack(DUMMY_HEALTH)
									-- 	-- end
									-- 	unit.frame = currentFrame
									-- 	health[1],health[2],health[3],health[4],health[5] = hp, maxHP, paraDamage, capture, build
									-- end
								end
							else
								-- Work around because we can't know the defID via spGetUnitDefID() nor via Spring.GetUnitLosState()
								-- and therefore can't know if, in the case of a structure, it has been discovered by the new selected ally team in the past
								-- example: in case of speccing FFA, if the spec has never been in full view and the team he was speccing never discovered/made a building X
								--, while it has been discovered by the ally team 3, and this building has been gone out of radar of the ally team 3 then came back
								-- If then, say, the spec decide to spec the ally team 3, the widget CANNOT KNOW what type of building it is (only gadgets can, through spGetUnitLosState()),
								-- even though we can physically watch what it is on the screen
								-- As work around, we can only deduce it is a discovered building by checking its position
								
								if unit.isInSight then
									widget:UnitLeftLos(id, teamID)
								end
								if not isKnown then 
									if not x then
										Echo('no x ??',id,unit.name,unit.teamID,'pos', spGetUnitPosition(id))
										Spring.PlaySoundFile(tickSound, 0.95, 'ui')
									end
									local isStructure = (x%8 == 0) and (z%8 == 0)
									-- if not isStructure it may or may not be a structure, even if it's been already registered as a srtucture, 
									-- until the current allyteam discover it, we can't know if the unit hasnt been recycled
									if isStructure then
										isKnown = true
										unit.isStructure = true
										unit.knownByAlly = {}
										unit.guessed = true
										GetIsDiscovered(id, unit)
									end
								end
							end
						else
							if unit.isInSight then
								widget:UnitLeftLos(id, teamID)
							end
							if unit.isInRadar then
								widget:UnitLeftRadar(id, teamID)
							end
						end
						-- we cannot know for sure if that unit has been discovered by the new watched ally team in the past if we weren't watching that team all the time
						if not isKnown then
							if structureDiscovered[id] then
								GetIsDiscovered(id, unit)
								isKnown = true
							end
						end
						unit.isKnown = isKnown
					end
				end
			end
		-- end
			-- complete by creating new units
			for i, id in ipairs(spGetAllUnits()) do
				local unit = Units[id]
				if DESTROYED[id] then
					-- skip
				elseif spGetUnitIsDead(id) then
					-- Echo('detected just dead unit',id,'is unit?',Units[id], 'while getting All units') -- happens sometime
					widget:UnitDestroyed(id)
				--[[elseif not spValidUnitID(id) then -- never happened
					Echo('detected just invalid unit',id,'is unit?',Units[id], 'while getting All units')
					widget:UnitDestroyed(id,spGetUnitTeam(id))
				--]]
				elseif not unit then
					-- case: new unit that was haven't seen before
					local isInSight, isInRadar, isKnown, defID
					local teamID = spGetUnitTeam(id)
					if fullview == 1 then
						isInSight = true
						isInRadar = true
						isKnown = true
					else
						local losState = spGetUnitLosState(id)
						if losState then
							isInSight = losState.los
							isInRadar = losState.radar -- true anyway?
							-- typed == the unit has just been out of LoS but not out of radar, we can retrieve the defID
							isKnown = losState.typed
							-- if not isInRadar then -- never happened
							--  Echo('UNIT ' .. id .. ' FROM spGetAllUnits not in radar !')
							-- end
						end
					end
					if isInRadar then
						
						local unit
						--
						if isInSight then
							-- case: new unit appear bc of fullview or bc it is in the vision of our current allyTeamID
							-- local allyTeam = spGetUnitAllyTeam(id)
							-- local defID = spGetUnitDefID(id)
							-- unit = CreateKnownUnit(id, teamID, defID)
							-- Units[id] = unit
							-- manager:NewUnit(unit, id, defID, teamID)
							-- inSight[id] = unit
							widget:UnitEnteredLos(id, teamID)
							unit = Units[id]
						else
							-- UPDATE ALLEGIANCE BEFORE ?
							widget:UnitEnteredRadar(id, teamID)
							unit = Units[id]
							if isKnown then 
								local defID = spGetUnitDefID(id)
								if unit.defID ~= defID then
									UpdateUnitDefID(unit, id, defID, teamID, not not isInSight)
								end
								-- Echo('unit.name', unit.name)
								if unit.isStructure then
									local struct = allStructures[id]
									if not struct then
										struct = {id = id, unit = unit, teamID = toTeam, defID = defID, knownByAlly = unit.knownByAlly,  facing = unit.facing, unpack(unit.pos)}
										allStructures[id] = struct
									end

									unit.guessed3 = nil
									GetIsDiscovered(id, unit)
								end
							else
								-- Work around because we can't know the defID via spGetUnitDefID() nor via Spring.GetUnitLosState()
								-- and therefore can't know if, in the case of a structure, it has been discovered by the new selected ally team in the past
								-- example: in case of speccing FFA, if the spec has never been in full view and the team he was speccing never discovered/made a building X
								--, while it has been discovered by the ally team 3, and this building has been gone out of radar of the ally team 3 then came back
								-- If then, say, the spec decide to spec the ally team 3, the widget CANNOT KNOW what type of building it is (only gadgets can know it is defined, through spGetUnitLosState()),
								-- even though we can physically watch what it is on the screen
								-- As work around, we can only deduce it is a discovered building by checking its position
								local x,z = unit.pos[1], unit.pos[3]

								local isStructure = (x%8 == 0) and (z%8 == 0)
								-- if not isStructure it may or may not be a structure, even if it's been already registered as a srtucture, 
								-- until the current allyteam discover it, we can't know if the unit hasnt been recycled
								-- we may also miss it in case of cheating or mod where building can be placed on any position
								if isStructure then
									isKnown = true
									unit.isStructure = true
									unit.guessed2 = true
									unit.knownByAlly = {}
									GetIsDiscovered(id, unit)
								end
							end
							unit.isKnown = isKnown
						end 
						UpdateAllegiance(Units[id], id, teamID)

						---- checking for immediate knowledge
						if fullview == 1 and unit.isStructure and unit.isEnemy then
							local unitAllyTeam = spGetUnitAllyTeam(id)
							local knownByAlly = unit.knownByAlly
							for allyTeam in pairs(allyTeams) do
								if allyTeam ~= unitAllyTeam then
									if knownByAlly[allyTeam] then -- debug
										-- Echo(unit.ud.humanName, id, 'is already noted as known by allyTeam', allyTeam)
									end
									-- if not knownByAlly[allyTeam] then
										local losState = spGetUnitLosState(id, allyTeam)
										local detected = false
										if losState then
											-- if id == 1375 then
											-- if id == 25386 then
												-- Echo('Discovered for allyTeam ' .. allyTeam .. '?', losState.radar, losState.typed, losState.los)

											-- end
											if losState.radar and (losState.typed or losState.los) then
												-- Echo(unit.ud.humanName, id, 'is known by allyTeam', allyTeam)
												detected = true
												knownByAlly[allyTeam] = true
											end
										end
										if not detected then
											-- Echo(unit.ud.humanName, id, 'is not found detected by allyTeam', allyTeam)
										end
									-- end
								end
							end
						end

						-- if unit.health
						-- Echo("unit.name:find('amphcon') is ", unit.name:find('amphcon'), unit.health.frame, unit.checkHealth)
					end
				end

			end
			-- if INIT then
			--  for id, unit in pairs(Units) do
			--      Echo('At init',id,'isInRadar: ',unit.isInRadar,'isInSight',unit.isInSight,'pos',unpack(unit.pos))
			--  end
			-- end
		-- end
	-- end

	-- verify if all is good -- never had problem since
	-- for id,unit in pairs(inSight) do
	--  if spGetUnitIsDead(id) then
	--      Echo('detected just dead unit ', id, ' in inSight while switching !',unit.defID and UnitDefs[unit.defID].name)
	--  elseif not spValidUnitID(id) then
	--      Echo('detected invalid unit', id, ' in inSight while switching !',unit.defID and UnitDefs[unit.defID].name)
	--  end
	-- end
	-- UpdateVisibleUnits()
end
function widget:PlayerChanged(playerID)
	if playerID ~= myPlayerID then
		return
	end
	local newfullview = Cam.fullview
	local oldfullview = fullview
	fullview = newfullview
	isSpec = Cam.isSpec
	local myNewTeamID = spGetMyTeamID()
	local myNewAllyTeamID = allyTeamByTeam[myNewTeamID]
	if not hasSwitchedSide and myAllyTeamID and myAllyTeamID ~= myNewAllyTeamID then
		hasSwitchedSide = true
	end
	local changingSide = myAllyTeamID ~= myNewAllyTeamID
	local changingTeam = myTeamID ~= myNewTeamID
	myAllyTeamID = myNewAllyTeamID
	myTeamID = myNewTeamID

	if changingSide then
		UpdateStructureDiscovered()
	end

	-- local changingSide = not spAreTeamsAllied(myNewTeamID, myTeamID)
	-- Echo(myTeamID,myNewTeamID,'CHANGED SIDE',changedSide)

	if changingSide or (oldfullview ~= newfullview) or force_update then
		force_update = false
		-- Echo('updating all')
		IGNORE_INVALID = true
		UpdateAll(newfullview, changingSide)
		IGNORE_INVALID = false
	elseif changingTeam then
		
		-- local IDUnits = WG.UnitsIDCard.units

		-- Echo('switch ownership')
		for id, unit in pairs(Units) do
			-- local idUnit = IDUnits[id]
			if unit.isMine then
				unit.isAllied = true
				unit.isMine = false
				-- idUnit.isAllied = true
				-- idUnit.isMine = false
			elseif unit.isAllied  then
				if unit.teamID == myTeamID then
					unit.isMine = true
					unit.isAllied = false
					-- idUnit.isMine = true
					-- idUnit.isAllied = false
				end
			end
		end

	end
end




function widget:UnitReverseBuilt(id--[[, unitDefID, unitTeam--]])
	local unit = Units[id]
	if unit then
		unit.checkHealth = not ignoreHealthDefID[defID]
	end
end

function widget:UnitGiven(id, defID, toTeam, fromTeam)
	if DESTROYED[id] then
		return
	end
	local unit = Units[id]


	if spGetUnitIsDead(id) then
		Echo('unit', id, 'got given but is just dead !')
		widget:UnitDestroyed(id,toTeam)
		return
	elseif not spValidUnitID(id) then
		Echo('unit ' .. id .. ' got given but is invalid !')
		Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		widget:UnitDestroyed(id,toTeam)
		return
	end
	if unit then
		-- Echo('unit',id, 'got given from team', fromTeam, 'to team', toTeam, 'was it already registered ?',unit.teamID == toTeam)
		if unit.teamID ~= toTeam then
			UpdateAllegiance(unit, id, toTeam)

			if fullview==1 then
				-- let the checkHealth state and isInSight (true as it should be) as it is
			else
				unit.isInSight = true
				inSight[id] = unit
				unit.checkHealth = not ignoreHealthDefID[defID]
			end
		end
		if unit.defID ~= defID then
			UpdateUnitDefID(unit, id, defID, toTeam, true)
		end		
		if unit.isStructure then
			local knownByAlly = unit.knownByAlly
			local struct = allStructures[id]
			if not struct then
				struct = {id = id, unit = unit, teamID = toTeam, defID = defID, knownByAlly = knownByAlly,  facing = unit.facing, unpack(unit.pos)}
				allStructures[id] = struct
			else
				struct.teamID = toTeam
				knownByAlly = struct.knownByAlly
				unit.knownByAlly = knownByAlly
			end
			local fromAllyTeam = allyTeamByTeam[fromTeam]
			local toAllyTeam = allyTeamByTeam[toTeam]
			knownByAlly[fromAllyTeam] = true
			knownByAlly[toAllyTeam] = nil
			unit.isDiscovered = false
			structDiscoveredByAllyTeams[toAllyTeam][id] = struct
			structDiscoveredByAllyTeams[fromAllyTeam][id] = struct
		end
	else
		-- Echo('unit ' .. id ..  ' created from given')

		local ignore = ignoreHealthDefID[defID]
		local health
		local checkHealth = false
		if ignore then
			health = DUMMY_HEALTH
		else
			local hp, maxHP, paraDamage, capture, build = spGetUnitHealth(id)
			checkHealth = hp ~= maxHP or build~=1 or paraDamage ~= 0 or capture ~= 0
			gettingBuilt = build~=1
			health = {hp, maxHP, paraDamage, capture, build}
			health.frame = currentFrame
		end
		local isMine = toTeam == myTeamID
		local isAllied = not isMine and spAreTeamsAllied(toTeam, myTeamID)

		local isStructure = structureDefID[defID] or false
		local facing, knownByAlly
		if isStructure then
			facing = spGetUnitBuildFacing(id)
			knownByAlly = {}
			local forAllyTeam = spGetUnitAllyTeam(id)
			if forAllyTeam ~= myAllyTeamID then
				knownByAlly[forAllyTeam] = true
			end
		end

		unit = {
			id = id,
			frame = currentFrame,
			isMine = isMine,
			isAllied = isAllied,
			isEnemy = not isAllied and not isMine,
			teamID = toTeam,
			defID = defID,
			health = health,
			isKnown = true,
			isInSight = true,
			isInRadar = true,
			checkHealth = checkHealth,
			pos = {},
			GetPos = GetPos,
			isStructure = isStructure,
			knownByAlly = knownByAlly,
			facing = facing,
			created = NOW,
			created_from = 'UnitGiven',
		}
		Units[id] = unit
		manager:NewUnit(unit, id, defID, toTeam)
		inSight[id] = isInSight and unit or nil

	end

end

function widget:UnitTaken(id, defID, fromTeam, toTeam)
	if spGetUnitIsDead(id) then
		-- Echo('unit', id, 'got taken but is just dead !')
		CHECKDEAD = id
		return
	end

	local unit = Units[id]
	if unit then
		-- Echo('unit',id, 'got took from team', fromTeam, 'to team', toTeam, 'was it already registered ?',unit.teamID == toTeam)
		if unit.teamID ~= toTeam then
			UpdateAllegiance(unit, id, toTeam)

			if fullview==1 then
				-- let the checkHealth state and isInSight (true as it should be) as it is
				-- if not unit.isInSight then
				-- 	Echo('problem in unit taken with unit',id, 'it should be in sight') -- never happened
				-- end
			else
				local ignore = ignoreHealthDefID[defID]

				local isInSight, isInRadar, isKnown   = false, false, false
				local losState = spGetUnitLosState(id)
				if losState then
					isInSight = losState.los
					isInRadar = losState.radar
					isKnown = losState.typed
				end
				if unit.isStructure then
					unit.isKnown = true
					unit.knownByAlly[myAllyTeamID] = true
				else
					unit.isKnown = isKnown
				end

				unit.isInSight = isInSight
				unit.isInRadar = isInRadar
				inSight[id] = isInSight and unit or nil
				unit.checkHealth = not ignore and isInSight
			end
		end
	else
		Echo('unit',id, 'has been taken but wasnt registered !')
		Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		local ignore = ignoreHealthDefID[defID]
		local isInSight, isInRadar, isKnown, isStructure
		local isStructure = structureDefID[defID]
		local isMine = toTeam == myTeamID
		local isAllied = not isMine and spAreTeamsAllied(myTeamID, toTeam)
		if fullview==1 then
			isInSight = true
		else
			local losState = spGetUnitLosState(id)
			if losState then
				isInSight = losState.los
				isInRadar = losState.radar
				isKnown = losState.typed
			end
		end

		local health
		local checkHealth = false
		if ignore then
			health = DUMMY_HEALTH
		else
			local hp, maxHP, paraDamage, capture, build = spGetUnitHealth(id)
			-- if not hp then
			-- 	hp, maxHP, paraDamage, capture, build = unpack(DUMMY_HEALTH)
			-- end
			if fullview==1 or isMine or isAllied then
				checkHealth = hp ~= maxHP or build~=1 or paraDamage ~= 0 or capture ~= 0
			else
				checkHealth = isInSight
			end
			health = {frame = currentFrame, hp, maxHP, paraDamage, capture, build}
		end

		isKnown = isKnown or isStructure
		Echo('unit ' .. id ..  ' created from taken')

		local facing, knownByAlly
		if isStructure then
			facing = spGetUnitBuildFacing(id)
			knownByAlly = {[myAllyTeamID] = true}
		end

		local unit = {
			id = id,
			frame = currentFrame,
			teamID = teamID,
			isAllied = isAllied,
			isMine = isMine,
			isEnemy = not isAllied and not isMine,
			isInSight = isInSight ,
			isInRadar = isInRadar, 
			teamID = toTeam,
			defID = defID,
			health = health,
			checkHealth = checkHealth,
			pos = {},
			GetPos = GetPos,
			isStructure = isStructure,
			knownByAlly = knownByAlly,
			facing = facing,
			isKnown = isKnown,
			created = NOW,
			created_from = 'UnitTaken',
		}
		unit:GetPos(-1)
		Units[id] = unit
		if unit.health[5] < 1 then
			manager:UnitCreated(unit, id, defID, teamID)
		else
			manager:UnitFinished(unit, id, defID, teamID)
		end
		inSight[id] = isInSight  and unit or nil

	end

end

local done = false
function widget:UnitCreated(id, defID, teamID, builderID) 
	-- with cheat globallos UnitCreated when other team is creating unit but instead, UnitEnteredLos is triggered
	if DEBUG_DETECT then
		Echo(dbgStateComment(id,'created'))
	end
	if spGetUnitIsDead(id) then
		-- Echo('unit', id, 'got created but is just dead !')
		-- CHECKDEAD = id
		return
	end

	-- if not fullview and not spAreTeamsAllied(teamID, myTeamID) then
	-- 	Echo('unit ', id, ' enemy created !') -- never happened
	-- end
	local unit = Units[id]
	if not unit then
		local ignoreHealth = ignoreHealthDefID[defID]
		local health
		if ignoreHealth then
			health = DUMMY_HEALTH
		else
			health = {spGetUnitHealth(id)}
			health.frame = currentFrame
		end
		local isMine = teamID == myTeamID
		local isAllied = not isMine and spAreTeamsAllied(teamID, myTeamID)

		local isStructure = structureDefID[defID] or false
		local facing, knownByAlly
		if isStructure then
			facing = spGetUnitBuildFacing(id)
			knownByAlly = {}
		end

		local unit = {
			id = id,
			frame = currentFrame,
			isAllied = isAllied,
			isMine = isMine,
			isEnemy = not isAllied and not isMine,
			teamID = teamID,
			isInSight = true,
			isInRadar = true,
			isKnown = true,
			health = health,
			defID = defID,
			checkHealth = not ignoreHealth and true,
			pos = {},
			GetPos = GetPos,
			isStructure = isStructure,
			knownByAlly = knownByAlly,
			facing = facing,
			created = NOW,
			created_from = 'UnitCreated',
		} 
		-- Echo('unit ' .. id ..  ' created from created')
		unit:GetPos(-1)
		Units[id] = unit
		manager:NewUnit(unit, id, defID, teamID, builderID)
		inSight[id] = unit

	else -- recycled or plop
		DetectUnitChanges(unit, id, teamID, defID, true) 
		-- Spring.PlaySoundFile(tickSound, 0.95, 'ui')
	end
end


-- NOTE: plop fac trigger first UnitFinished then UnitCreated
function widget:UnitFinished(id, defID, teamID)
	-- with cheat globallos UnitCreated when other team is creating unit but instead, UnitEnteredLos is triggered
	-- Echo('unit created',id,defID,teamID)
	local unit = Units[id]
	if not unit then
		local ignore = ignoreHealthDefID[defID]
		local health
		if ignore then
			health = DUMMY_HEALTH
		else
			health = {spGetUnitHealth(id)}
			health.frame = currentFrame
		end
		local isMine = teamID == myTeamID
		local isAllied = not isMine and spAreTeamsAllied(teamID, myTeamID)
		local isInSight, isInRadar = true, true
		-- local isInSight = spGetUnitLosState(id).los
		-- if not isInSight then -- never happened
		-- 	Echo('unit',id,' finished but not in sight !')
		-- end

		-- Echo('unit ' .. id ..  ' created from finished')
		local isStructure = structureDefID[defID] or false
		local facing, knownByAlly
		if isStructure then
			facing = spGetUnitBuildFacing(id)
			knownByAlly = {}
		end

		unit = {
			id = id,
			frame = currentFrame,
			isAllied = isAllied,
			isMine = isMine,
			isEnemy = not isAllied and not isMine,
			teamID = teamID,
			isInSight = isInSight,
			isInRadar = isInRadar,
			health = health,
			defID = defID,
			checkHealth = not ignore and true,
			isKnown = true,
			pos = {},
			GetPos = GetPos,
			isStructure = isStructure,
			knownByAlly = knownByAlly,
			facing = facing,
			created = NOW,
			created_from = 'UnitFinished',
		} 
		unit:GetPos(-1)
		Units[id] = unit
		inSight[id] = isInSight and unit or nil
	end
	manager:UnitFinished(unit, id, defID, teamID)

end

function widget:UnitEnteredLos(id, teamID, forAllyTeam, defID)
	if DEBUG_DETECT then
		Echo(dbgStateComment(id, 'entered los'))
	end
	if DESTROYED[id] then
		return
	elseif spGetUnitIsDead(id) then -- happens often
		-- Echo('unit', id, 'entered LoS but is just dead AND Was registered !')
		widget:UnitDestroyed(id, teamID)
		return
	elseif not spValidUnitID(id) then -- happens often
			-- Echo('unit', id, 'entered LoS but is invalid AND Was registered !')
		widget:UnitDestroyed(id, teamID)
		return
	end

	-----------
	-- Echo(id,'entered los' .. (INIT and ' (init)' or ''))
	if not defID then
		defID = spGetUnitDefID(id)
	end

	local unit = Units[id]
	if unit then
		DetectUnitChanges(unit, id, teamID, defID, true)
		unit.isInSight = true
		unit.isKnown = true
		unit.isInRadar = true
		unit.checkHealth = not ignoreHealthDefID[defID]
	else
		unit = CreateKnownUnit(id, teamID, defID)
		Units[id] = unit
		manager:NewUnit(unit, id, defID, teamID)
	end
	inSight[id] = unit
	-- Echo("unit.isStructure, unit.isEnemy is ", unit.isStructure, unit.isEnemy)
	if unit.isStructure then
		if fullview == 1 and not forAllyTeam then
			return
		end
		if not forAllyTeam then
			forAllyTeam = myAllyTeamID
		end
		if allyTeamByTeam[teamID] == forAllyTeam then
			-- we may use UnitEnteredLos for our own allyTeam to create new units
			return
		end
		local knownByAlly = unit.knownByAlly
		if not knownByAlly[forAllyTeam] then
			local struct = allStructures[id]
			if not struct then
				struct = {id = id, unit = unit, teamID = teamID, defID = defID, knownByAlly = knownByAlly,  facing = unit.facing, unpack(unit.pos)}
				allStructures[id] = struct
			else
				unit.knownByAlly = struct.knownByAlly
			end
			
			knownByAlly[forAllyTeam] = true
			if forAllyTeam == myAllyTeamID then
				structureDiscovered[id] = struct
				unit.isDiscovered = true
			else
				structDiscoveredByAllyTeams[forAllyTeam][id] = struct
			end
		end

	end
	-- if unit.checkHealth and not unit.health.frame then
	-- 	Throw('HERE NOW', f.Page(unit))
	-- end
end
local warns, MAX_WARNS = 0, 10
function widget:UnitLeftLos(id, teamID)
	-- in spec fullview
	-- Echo('a unit of team', teamID, 'left the LoS of ', fromAllyTeam, 'allyteam:',spGetUnitAllyTeam(id),'allied with me?',spAreTeamsAllied(myTeamID,teamID))
	if DEBUG_DETECT then
		Echo(dbgStateComment(id, 'left los'))
	end
	if DESTROYED[id] then
		return
	elseif spGetUnitIsDead(id) then -- happens sometimes
		if Units[id] then
			Echo('unit', id, 'left LoS but is just dead AND Was registered !')
			Spring.PlaySoundFile(tickSound, 0.95, 'ui')
			-- Units[id] = nil
			-- inSight[id] = nil
			-- widget:UnitDestroyed(id, teamID)
		else
			Echo('unit', id, 'left LoS but is just dead AND WASNT registered !')
			Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		end
		widget:UnitDestroyed(id, teamID)
		return
	elseif not IGNORE_INVALID then --
		if not spValidUnitID(id) and warns < MAX_WARNS then
			local unit = Units[id]
			if unit and unit.name:find('drone') then
				return
			end
			warns = warns + 1
			if unit then
				-- FIXME wtf -- seems to happen with drone (at least) systematically now, 
					Spring.PlaySoundFile(tickSound, 0.95, 'ui')
					Echo('unit', id, Units[id].name,  'left LoS but is invalid AND Was registered !')
			else
				Spring.PlaySoundFile(tickSound, 0.95, 'ui')
				Echo('unit', id, 'left LoS but is invalid AND WASNT registered !')
			end
			widget:UnitDestroyed(id, teamID)
			return
		end
	end

	if fullview==1 then
		return
	end
	-- if fullview and spAreTeamsAllied(teamID,myTeamID) then
	-- 	return
	-- 	-- Echo('own allied entered los !',math.round(os.clock()*10)%10)
	-- end
	local unit = Units[id]
	if unit then
		-- local losState = spGetUnitLosState(id)
		-- Echo(id,'left los' .. (INIT and ' (init)' or '') .. (losState and losState.radar and '' or ' (not in radar too)') .. (not spValidUnitID(id) and ' INVALID' or ''))
		-- Echo(id,'left los' .. (INIT and ' (init)' or ''))
		-- if id == 29558 then
		-- 	Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		-- 	CHECK_FOR_RADAR[id] = unit
		-- 	unit.checkFrame = currentFrame
		-- end
		-- if not (unit.isInSight and inSight[id]) then
		-- 	Echo('unit ', id, unit.name,' get out of sight but is not in sight !','.isInSight?', unit.isInSight, 'inSight[id] ?',  inSight[id])
		-- 	Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		-- end
		unit.isInSight = false
		inSight[id] = nil
		unit.checkHealth = false
		unit.lastSeen = currentFrame
		-- if not unit.isStructure then
		-- 	Echo('verif pos out of los', spGetUnitPosition(id))
		-- end
	else -- happens with terra units created by own team out of sight (only those so far)
		-- Echo('unit ', id,MEM_UNITS[id] and MEM_UNITS[id].name or spGetUnitDefID(id) and UnitDefs[spGetUnitDefID(id)].name, ' left LoS but wasnt registered !', 'currentFrame', currentFrame, 'cleaned up and last seen?', MEM_UNITS[id],  MEM_UNITS[id] and MEM_UNITS[id].lastSeen, 'isDead frame?', MEM_UNITS[id] and MEM_UNITS[id].isDead)
		-- Echo("destroyedByLosCheck?", destroyedByLosCheck[id])
		-- if MEM_UNITS[id] then
		-- 	COUNT = (COUNT or 0) + 1
		-- 	if COUNT%5 == 1 then
		-- 		f.Page(MEM_UNITS[id])
		-- 	end
		-- end
		-- TRACK_UNIT = id
		-- Spring.PlaySoundFile(tickSound, 0.95, 'ui')
	end
end


function widget:UnitEnteredRadar(id, teamID, forAllyTeam, defID)
	if DEBUG_DETECT then
		Echo(dbgStateComment(id, 'entered radar'))
	end
	if DESTROYED[id] then
		return
	end
	local unit = Units[id]
	if unit then
		-- TODO IMPLEMENT RECYCLING/STRUCTURE DISCOVERED CHECK
		unit.isInRadar = true
		if unit.teamID ~= teamID then
			UpdateAllegiance(unit, id, teamID)
		end
		if hasSwitchedSide and unit.isStructure and unit.isKnown == nil and unit.defID and unit.isEnemy then
			-- add to discovered building if pos looks like a building
			local x, _, z = spGetUnitPosition(id)
			if x%8 == 0 and z%8 == 0 then
				unit.guessed5 = true
				GetIsDiscovered(id, unit)
			end

		end
	else
		Units[id] = CreateUnknownUnit(id, teamID)

		if --[[not forced and isSpec and--]] fullview~=1 then
			local unit = Units[id]

			-- work around in case the spec switch ally team watch 
			-- to find out if the said ally team has already discovered that (structure) unit
			local x,z = unit.pos[1], unit.pos[3]
			local isStructure = (x%8 == 0) and (z%8 == 0)
			if isStructure then
				-- Echo('guessed structure',x,z)
				unit.isStructure = true
				unit.facing = 0
				unit.knownByAlly = {}
				unit.isKnown = true
				GetIsDiscovered(id, unit)
				unit.guessed3 = true
			end

		end
	end
end


function widget:UnitLeftRadar(id, teamID)
	if DEBUG_DETECT then
		Echo(dbgStateComment(id, 'left radar'))
	end
	
	if lastDead == id then
		return
	elseif DESTROYED[id] then
		return
	end
	if fullview==1 then
		return
	end
	local unit = Units[id]
	if unit then
		if spGetUnitIsDead(id) then
			widget:UnitDestroyed(id, teamID)
			return 
		end
		-- Echo(id, 'left radar' .. (INIT and ' (init)' or ''))
		unit.isInRadar = false
		unit.checkHealth = false
		if not unit.isStructure then
			unit.isKnown = false
		end

	else -- 
		-- happens often but doesnt matter, might be a dead unit that never had the chance to trigger the enter radar
		-- Echo('unregistered unit', id, ' left radar !',spGetUnitDefID(id),'Destroyed ?',DESTROYED[id],'is dead?',spGetUnitIsDead(id),'maybe a terra unit?')
		-- Spring.PlaySoundFile(tickSound, 0.95, 'ui')


		-- Echo('TRACEBACK')
		-- Echo(debug.traceback())
		-- Units[id] = { 
		-- 	id = id,
		-- 	frame = currentFrame,
		-- 	teamID = teamID,
		-- 	isMine = false,
		-- 	isAllied = false,
		-- 	isEnemy = true,
		-- 	isInSight = false,
		-- 	isInRadar = false,
		-- 	defID = false,
		-- 	checkHealth = false,
		-- 	health = DUMMY_HEALTH,
		-- 	isKnown = false,
		-- 	pos = {frame = -1},
		-- 	GetPos = GetPos,
		-- 	isStructure = false,
		-- 	created = NOW,
		-- } 

		-- DEBUGGED[id] = NOW
		-- WAIT = NOW
	end
end

function widget:UnitDamaged(id, defID, teamID)
	-- NOTE: we cannot get enemy unit damaged from there (even those that are in sight), except in SPEC full view (not cheat globallos)
	-- Echo("id is ", id, 'is getting damaged',math.round(os.clock()),Units[id],Units[id] and Units[id].isAllied)
	if id == lastDead then
		return
	elseif DESTROYED[id] then
		return -- so it happens often that UnitDamaged get triggered AFTER UnitDestroyed
	elseif spGetUnitIsDead(id) then -- let's try without it -- in some rarer case it's not the last dead registered 
		-- FIXME: that might be expensive !
		-- seems like it never happened so far
		Echo('id',id, 'get damaged after beeing dead but its not the last dead! Was registered ?',Units[id])
		Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		widget:UnitDestroyed(id, teamID)
		return
	elseif Units[id] then
		if not ignoreHealthDefID[defID] then
			Units[id].checkHealth = true
		end
	else
		-- if not fullview and not spAreTeamsAllied(myTeamID,teamID) then
		-- 	Echo('unit',id, 'is enemy damaged while not in full view !') -- never happened
		-- end
		local health
		local ignore = ignoreHealthDefID[defID]
		if ignore then
			health = DUMMY_HEALTH
		else
			health = {spGetUnitHealth(id)}
		end
		local isInSight, isInRadar = true, true
		-- local isInSight = fullview==1 or spGetUnitLosState(id).los
		-- if not isInSight then -- never happened or missed it
		-- 	Echo('unit',id,'get damaged without beeing in sight !')
		-- end
		health.frame = currentFrame
		local isMine = teamID == myTeamID
		local isAllied = not isMine or fullview and spAreTeamsAllied(teamID, myTeamID) -- without fullview, it will not be an allied in any case

		local isStructure = structureDefID[defID] or false
		local facing, knownByAlly
		if isStructure then
			facing = spGetUnitBuildFacing(id)
			knownByAlly = {}
		end
		local unit = { 
			id = id,
			frame = currentFrame,
			isInSight = isInSight,
			isInRadar = isInRadar,
			defID = defID,
			checkHealth  = not ignore and true,
			health = health,
			teamID = teamID,
			isAllied = isAllied, 
			isMine = isMine,
			isEnemy = not isAllied and not isMine,
			pos = {},
			GetPos = GetPos,
			isStructure = isStructure,
			knownByAlly = knownByAlly,
			facing = facing,
			isKnown = not not defID,
			created = NOW,
			created_from = 'UnitDamaged',
		} 
		unit:GetPos(-1)
		Units[id] = unit
		manager:NewUnit(unit, id, defID, teamID)
		inSight[id] = isInSight and unit or nil
		Echo('Created unit ' .. id ..' '..unit.ud.name..' from UnitDamaged !!!!') -- never happened or missed it
		Spring.PlaySoundFile(tickSound, 0.95, 'ui')


	end
end

function widget:UnitDestroyed(id, defID, teamID)
	-- NOTE: Destroyed can happen and still unit can leave LoS afterward 
	-- if CHECKDEAD == id then
	-- 	Echo('unit ', id, 'got indeed destroyed')
	-- end
	if DEBUG_DETECT then
		Echo(dbgStateComment(id,'destroyed'))
	end
	if DESTROYED[id] then
		if Units[id] then
			Echo('UNIT ' .. id .. ' IS IN DESTROYED BUT UNIT STILL EXISTS')
			Spring.PlaySoundFile(tickSound, 0.95, 'ui')
		end
		return
	end
	DESTROYED[id] = currentFrame
	if lastDead == id then
		return
	end
	local unit = Units[id]
	lastDead = id
	if unit then
		-- Echo(id, 'destroyed' .. (INIT and ' (init)' or ''))
		unit.isDead = currentFrame
		manager:UnitDestroyed(unit, id, defID, teamID)
		local struct = structureDiscovered[id]
		if struct then
			structureDiscovered[id] = nil
			local knownByAlly = struct.knownByAlly
			knownByAlly[myAllyTeamID] = nil
			allStructures[id] = nil
		end
		Units[id] = nil
		inSight[id] = nil
	else
		-- happens sometime, UnitDestroyed can trigger before unit enter radar/los
		-- Echo('unit',id, 'got destroyed but wasnt registered !')
		-- Spring.PlaySoundFile(tickSound, 0.95, 'ui')
	end
end

-------------- Init

-- function widgetRemoveNotify(w,name,preloading)
-- 	if name == 'UnitIDCard' then
-- 		UpdateVisibleUnits = OriUpdateVisibleUnits
-- 	end
-- end
function WidgetInitNotify(w,name,preloading)
	if name == 'UnitsIDCard' then
		-- UIDC = w
		-- Units = WG.UnitsIDCard.units
		-- UpdateVisibleUnits = AltUpdateVisibleUnits
	end
end

function widget:Initialize()
	-- Units = Cam.Units
	if not WG.Cam then
		widget.status = widget:GetInfo().name .. ' requires -HasViewChanged.'
		Echo(widget.status)
		widgetHandler:RemoveWidget(widget)
		return
	end
	if not WG.UnitsIDCard then
		widget.status = widget:GetInfo().name .. ' requires UnitsIDCard.'
		Echo(widget.status)
		widgetHandler:RemoveWidget(widget)
	end		
	Cam = WG.Cam
	Units = Cam.Units
	inSight = Cam.inSight
	manager = WG.UnitsIDCard.manager
	manager:Renew()
	for id in pairs(Units) do
		Units[id] = nil
		inSight[id] = nil
	end
	-- trigger the update from PlayerChanged
	myPlayerID = Spring.GetMyPlayerID()


	force_update = true
	INIT = true
	widget:PlayerChanged(myPlayerID)
	INIT = false
	GetIconMidY = WG.GetIconMidY
end








local structID = nil
local lastGameFrame = currentFrame
local retestPosLos = {}
local function TestPosLos(id, struct, complete) -- remove discovered building that doesnt appear anymore (destroyed without noticing)
	if struct then
		if spIsPosInLos(struct[4], struct[5], struct[6], fullview ~= 1 and myAllyTeamID or nil) then
			if not complete then
				retestPosLos[id] = struct
				-- see explanation pos los vs unit los at top
				return
			end
			local inLos = spIsUnitInLos(id, fullview ~= 1 and myAllyTeamID or nil)
			if not inLos then
				local unit = Units[id]
				if unit and unit.defID == struct.defID then
					widget:UnitDestroyed(id, struct.defID, struct.teamID)
					destroyedByLosCheck[id] = true
					-- Echo('struct discovered ' .. id ..', ' .. unit.name .. ' is gone ('..currentFrame - unit.frame..')', 'valid?', spValidUnitID(id),'dead?', spGetUnitIsDead(id))
				else
					-- got recycled ?
					Echo('struct\'s unit no longer exist', unit, unit and unit.defID )
					local knownByAlly = struct.knownByAlly
					knownByAlly[myAllyTeamID] = nil
					allStructures[id] = nil
					structureDiscovered[id] = nil
					destroyedByLosCheck[id] = true
				end

			end
		end
	end
end


------------- Some updating
function widget:GameFrame(f)
	currentFrame = f
	-- Verify pos being in los for supposedly discovered structure
	-- !! UNIT ENTERING LOS appear ONE FRAME LATER of spIsInLos returing true, (btw height given in isPosInLos doesnt matter)
	for id, struct in pairs(retestPosLos) do
		TestPosLos(id, struct, true)
		retestPosLos[id] = nil
	end
	local struct
	structID, struct = next(structureDiscovered, structureDiscovered[structID] and structID or nil)
	-- if f%100 == 0 then
	-- 	Echo('discovered', table.size(structureDiscovered), structID)
	-- end
	TestPosLos(structID, struct)
	--
	if WAIT then
		if f < WAIT then
			Echo('--- stop waiting ---')
			error()
		end
	end
	for id, unit in pairs(guessed) do
		if unit.isInRadar then
			if not unit.isInSight then
				local x, _, z = unit:GetPos(-1)
				if x%8 ~= 0 or z%8 ~= 0 then
					unit.isKnown = false
					unit.isStructure = false
					unit.facing = 0
					unit.knownByAlly = nil
					unit.guessed, unit.guessed2, unit.guessed3 = nil, nil, nil
				end
			end
			guessed[id] = nil
		end
	end
	if cleanUpFrame < f then
		for id, deadFrame in pairs(DESTROYED) do
			if f - deadFrame > 60 then
				DESTROYED[id] = nil
			end
		end
		cleanUpFrame = f + CLEANUP_RATE
	end
	if fullview ~= 1 and f%200 == 0 then -- clean up unseen mobile unit, undiscovered building or radar dot
		local count = 0
		for id, unit in pairs(Units) do
			if not (unit.isInRadar or unit.isInSight or unit.isStructure) then
				-- if currentFrame - (unit.lastSeen or currentFrame) > 600 then
					count = count + 1
					MEM_UNITS[id] = unit
					-- Echo('forgetting unit', id, unit.name)
					DESTROYED[id] = nil
					lastDead = nil
					widget:UnitDestroyed(id, unit.defID, unit.teamID)
					DESTROYED[id] = nil
					lastDead = nil
					if count == 100 then
				 		break
					end
				-- end
			end
		end
	end
end


local lastView = 0
function widget:DrawWorldPreUnit()
	-- UpdateVisibleUnits()
	-- Cam.isItIcon = spIsUnitIcon(25736)
	local newView = WG.NewView[5] 
	if lastView ~= newView then
		lastView = newView

		
		local frame = currentFrame
		local lagUpdate = WG.lag[1] * UPDATE_FRAME_HEALTH

		-- Echo("lagUpdate is ", lagUpdate)
		-- local count = 0
		local spGetUnitHealth = spGetUnitHealth
		for id, unit in pairs(inSight) do
			if unit.checkHealth then
				-- count = count + 1
				local health = unit.health
				if not health.frame then
					error('UNIT '.. id ..' SHOULDNT CHECK HEALTH !? ' .. UnitDefs[unit.defID].humanName ..'\n' .. f.Page(unit))
					break
				end
				if frame > health.frame + lagUpdate then
					health.frame = frame
					local hp, maxHP, paraDamage, capture, build = spGetUnitHealth(id)
					if  hp then
						-- only in spec fullview we can get informed when enemy unit got damaged, so we can stop checking for nothing
						if fullview==1 or unit.isAllied or unit.isMine then
							if hp == maxHP and paraDamage == 0 and capture == 0  and build==1 then
								unit.checkHealth = false
							end
						end
						health[1], health[2], health[3], health[4], health[5] = hp, maxHP, paraDamage, capture, build
					else -- happen once every blue moon (wtf)
						local defID = spGetUnitDefID(id)

						local name = defID and UnitDefs[defID].name
						local name2 = unit.defID and UnitDefs[unit.defID].name
						Echo('unit',name,name2,id,'dont have health ! is dead?',spGetUnitIsDead(id),'is valid?',spValidUnitID(id),'registered health?',health and health[1],'is allied?',unit.isAllied)
						Spring.PlaySoundFile(tickSound, 0.95, 'ui')
						unit.checkHealth = false
						widget:UnitDestroyed(id, defID, unit.teamID)
					end
				end
			end
				-- too expensive
				-- if newFrame and unit.pos and not unit.isStructure then
				-- -- if fullview or unit.isInRadar then
				-- 	local pos = unit.pos
				-- 	pos[1], pos[2], pos[3] = spGetUnitPosition(id)
				-- 	pos.frame = currentFrame
				-- end
			-- end
		end
		-- if math.round(os.clock()*10)%30 == 0 then
			-- Echo('count for checkhealth',count)
		-- end

	end
end



----------- Some Drawing


if not (gl.Utilities and gl.Utilities.DrawScreenDisc) then
    VFS.Include('LuaUI\\Widgets\\Include\\glAddons.lua')
end

local debugDot = false
local gluDrawScreenDisc = gl.Utilities.DrawScreenDisc
local gluDrawDisc = gl.Utilities.DrawDisc
local spWorldToScreenCoords = Spring.WorldToScreenCoords
local spGetGroundHeight = Spring.GetGroundHeight
local glColor = gl.Color
local color = {
	yellow = {0.7,0.7,0,0.5},
	blue = {0,0,1,0.7},
	red = {1,0,0,0.5},
	black = {0,0,0,1},
	white = {1,1,1,0.7},
	grey = {0.5,0.5,0.5,0.7},
	purple = {1,0,1,0.7}
}
local viscolor = {
	radar = color.yellow,
	insight = color.blue,
	outofradar = color.grey,
	known_outofradar = color.red,
	discovered = color.purple,
	wrong = color.black
}


local WRONGS = {}
function widget:DrawScreen()
	-- if WAIT then
	-- 	if NOW - WAIT > 1 then
	-- 		Echo('-- Stop waiting --')
	-- 		error()
	-- 	end
	-- end
	-- for id,unit in pairs(CHECK_FOR_RADAR) do
	-- 	if unit.checkFrame~= currentFrame then
	-- 		if unit.isInRadar then
	-- 			local losState = spGetUnitLosState(id)
	-- 			if not (losState and losState.radar) then
	-- 				local valid = spValidUnitID(id)
	-- 				local dead = spGetUnitIsDead(id)
	-- 				Echo('UNIT ' .. id .. ' NOT IN RADAR CORRECTED','valid',valid,'dead',dead,'FRAME', currentFrame, UnitDefs[unit.defID].humanName)
	-- 				Spring.PlaySoundFile(tickSound, 0.95, 'ui')

	-- 				if dead then
	-- 					CHECK_FOR_RADAR[id] = nil
	-- 					widget:UnitDestroyed(id, unit.teamID)
	-- 				else
	-- 					CHECK_FOR_RADAR[id] = nil
	-- 					widget:UnitLeftRadar(id, unit.teamID)
	-- 				end
	-- 			end
	-- 		end
	-- 		if id ~= 29558 then
	-- 			CHECK_FOR_RADAR[id] = nil
	-- 		end
	-- 	end
	-- end
	if not DEBUG_VIS then
		return
	end
	local cx, cy, cz = Spring.GetCameraPosition()
	-- local allUnits = Spring.GetAllUnits()
	-- for i = 1, #allUnits do
	-- 	local id = allUnits[i]
	-- 	if not Units[id] and not DESTROYED[id] then
	-- 		WRONGS[id] = currentFrame
	-- 	end
	-- end

	-- for id, frame in pairs(WRONGS) do
	-- 	local _,_,_,x,y,z = Spring.GetUnitPosition(id, true)
	-- 	Echo('missing',id,'frame',frame,x,y,z)
	-- 	if x then
	-- 		local gy = spGetGroundHeight(x,z)
	-- 		local defID = spGetUnitDefID(id) or 0
	-- 		local distFromCam = ( (cx-x)^2 + (cy-y)^2 + (cz-z)^2 ) ^ 0.5
	-- 		y = GetIconMidY(defID, y, gy, distFromCam)
	-- 		x,y = spWorldToScreenCoords(x,y,z)
			
	-- 		glColor(viscolor.wrong)
	-- 		gluDrawScreenDisc(x,y,wrong and 8 or 4)
	-- 		glColor(color.white)
	-- 		gluDrawScreenDisc(x,y,wrong and 6 or 3)
	-- 	end
	-- end
	-- if true then
	-- 	return
	-- end
	for id, unit in pairs(Units) do
		local x,y,z, _
		local wrong = false
		if not unit.isInRadar then
			_,_,_,x,y,z = unpack(unit.pos)
			if not x then
				Spring.PlaySoundFile(tickSound, 0.95, 'ui')
				Echo('unit',id,unit.defID, unit.name or unit.defID and UnitDefs[unit.defID].humanName or 'no_name',"out of radar and doesnt get any pos !",'valid',spValidUnitID(id),'dead', spGetUnitIsDead(id), 'created since',NOW - unit.created)
				f.Page(unit, {all = true, content = true})
				error()
			end
		else
			-- local _x,_y,_z = unpack(unit.pos)

			_,_,_,x,y,z = unit:GetPos(1,true)
			-- if not x then
			-- 	-- Echo('unit',id,unit.defID, unit.name or unit.defID and UnitDefs[unit.defID].humanName or 'no_name',"is marked as inRadar but is not",'valid',spValidUnitID(id),'dead', spGetUnitIsDead(id), 'created since',NOW - unit.created,'pos',unpack(unit.pos))
			-- 	-- local losState = spGetUnitLosState(unit.id, fullview ~= 1 and myAllyTeamID or nil)
			-- 	-- Echo('losState', losState, losState and losState.radar)
			-- 	-- Echo('IsUnitInRadar', Spring.IsUnitInRadar(unit.id))
			-- 	-- f.Page(unit, {all = true, content = true})
			-- 	-- x,y,z = unpack(unit.pos)
			-- 	wrong = true
			-- 	x,y,z = _x,_y,_z
			-- 	WATCH_UNIT = id
			-- 	WATCH_TIME = NOW
			-- end
		end
		local defID = unit.defID or 0
		if x then
			local gy = spGetGroundHeight(x,z)
			local distFromCam = ( (cx-x)^2 + (cy-y)^2 + (cz-z)^2 ) ^ 0.5
			y = WG.GetIconMidY(defID, y, gy, distFromCam)
			x,y = spWorldToScreenCoords(x,y,z)
			if wrong then
				glColor(viscolor.wrong)
			elseif fullview ~= 1 then
				if unit.isInSight then
					glColor(viscolor.insight)
				elseif unit.isInRadar then
					glColor(viscolor.radar)
				elseif structureDiscovered[id] then
					glColor(viscolor.discovered)
				elseif unit.isKnown then
					glColor(viscolor.known_outofradar)
				else
					glColor(viscolor.outofradar)
				end
			else
				local done
				if structureDiscovered[id] then
					glColor(viscolor.discovered)
				elseif unit.isInSight then
					glColor(viscolor.insight)
				elseif unit.isInRadar then
					glColor(viscolor.radar)
				elseif unit.isKnown then
					glColor(viscolor.known_outofradar)
				else
					glColor(viscolor.outofradar)
				end
			end
			gluDrawScreenDisc(x,y,wrong and 8 or 4)
			glColor(color.white)
			gluDrawScreenDisc(x,y,wrong and 6 or 3)
		end
	end
	-- for id, unit in pairs(outOfRadar) do
	-- 	local x,y,z = unpack(unit.pos)
	-- 	glColor(color.outofradar)
	-- 	gluDrawScreenDisc(x,y,z,10)
	-- 	-- glColor(white)
	-- 	-- gluDrawScreenDisc(x,y,z,5)
	-- end
end




if fullTraceBackError then
	f.DebugWidget(widget)
end