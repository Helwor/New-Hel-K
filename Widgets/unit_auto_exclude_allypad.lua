-- NOTE: pad eclusion cmd is done via an aircraft unit which is not ideal, ideally, pad exclusion (since it is global for every aircraft) should be dealt through a command that doesnt need any aircraft existing
function widget:GetInfo()
	return {
		name      = "Auto Exclude Ally Pads",
		desc      = "Self explanatory",
		author    = "Helwor",
		date      = "August 2024",
		license   = "GNU GPL, v2 or later",
		-- layer     = 2, -- after Unit Start State
		layer     = 0,
		enabled   = false,  --  loaded by default?
		-- api       = true,
		handler   = true,
	}
end
local Echo = Spring.Echo
local DEBUG = false
local isSpec  = false

local function Sleep(bool)
    if widgetHandler.Sleep then
    	if widget.isSleeping ~= bool then
        	return widgetHandler[bool and 'Sleep' or 'Wake'](widgetHandler,widget, {PlayerChanged = true})
        end
    else
        for k,v in pairs(widget) do
            if type(k)=='string' and type(v)=='function' then
                if k ~= 'PlayerChanged' and widgetHandler[k .. 'List'] then
                    widgetHandler[(bool and 'Remove' or 'Update')..'WidgetCallIn'](widgetHandler, k, widget)
                end
            end
        end
    end
end



local CMD_EXCLUDE_PAD = VFS.Include("LuaRules/Configs/customcmds.lua").EXCLUDE_PAD

-- speed up
local tobool = Spring.Utilities.tobool
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitHealth = Spring.GetUnitHealth
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local spGetUnitTeam = Spring.GetUnitTeam
local spValidUnitID = Spring.ValidUnitID
--

local myPlayerID
local myTeam
local myAllyeamID
local myAircraftID

local excludeString

local pad = {}
local padIndex = {}
local landable = {}
local landableIndex = {}
do
	local spugetMovetype = Spring.Utilities.getMovetype
	for defID, def in pairs(UnitDefs) do
		if def.customParams.pad_count then
			pad[defID] = true
			table.insert(padIndex, defID)
		end
		if not tobool(def.customParams.cantuseairpads) then
			local movetype = spugetMovetype(def)
			if (movetype == 1 or movetype == 0) then
				landable[defID] = true
				table.insert(landableIndex, defID)
			end
		end
	end
end

local alliance
local allyTeam
function UpdateAllyTeams()
	alliance = setmetatable({}, {__index = function(self,k) local t = {} rawset(self, k, t) return t end})
	allyTeam = {}
	for i,teamID in pairs(Spring.GetTeamList()) do
		local allyTeamID = Spring.GetTeamAllyTeamID(teamID)
		table.insert(alliance[allyTeamID], teamID)
		allyTeam[teamID] = allyTeamID
	end
end


local function KeyUnpack(t, k)
	k = next(t, k)
	return (k and k..', '..KeyUnpack(t, k) or '')
end

local function IsExcluded(padID)
	return tobool(spGetUnitRulesParam(padID, excludeString))
end

local function IsFinished(unitID)
	return select(5, spGetUnitHealth(unitID)) >= 1
end

local myPads = {}
local allyPads = {}
local pending = {}
local myAirCrafts = {}
local myAircraftID = false
local updateMyAircraft = false

local function UpdatePad(padID, bool, teamID, from)
	if myAircraftID then
		if IsExcluded(padID) ~= bool then
			if DEBUG then
				Echo((from or '')..(IsExcluded(padID) and 'Une' or 'E')..'xcluding '..((teamID and teamID or spGetUnitTeam(padID)) == myTeam and 'Own' or 'Ally')..' Pad '..padID..'.')
			end
			spGiveOrderToUnit(myAircraftID, CMD_EXCLUDE_PAD, padID, 0)
		elseif DEBUG then
			Echo((from or '')..((teamID and teamID or spGetUnitTeam(padID)) == myTeam and 'Own' or 'Ally')..' Pad '..padID.. ' is already ' .. (IsExcluded(padID) and 'Une' or 'E')..'xcluded '..'.')
		end
		pending[padID] = nil
	else
		pending[padID] = bool
		if DEBUG then
			Echo((from or '')..'Put '..((teamID and teamID or spGetUnitTeam(padID)) == myTeam and 'Own' or 'Ally')..' Pad '..padID..' in pending list for '..(bool and 'E' or 'Une')..'xclusion.')
		end
	end
end


function widget:PlayerChanged(playerID) -- updating
	if playerID ~= myPlayerID then
		return
	end
	local isNewSpec = Spring.GetSpectatingState()
	if isSpec ~= isNewSpec then
		isSpec = isNewSpec
		Sleep(isSpec)
		if isSpec then
			myTeam = false
			return
		end
	end

	local newTeamID = Spring.GetMyTeamID()
	local newAllyTeam = Spring.GetMyAllyTeamID()
	if newTeamID ~= myTeam or newAllyTeam ~= myAllyTeam then
		myTeam = newTeamID
		if newAllyTeam ~= myAllyTeam then
			UpdateAllyTeams()
			myAllyTeam = Spring.GetMyAllyTeamID()
		end
		excludeString = "padExcluded" .. myTeam
		allyPads = {}
		myPads = {}
		myAircrafts = {}
		for _, aircraftID in ipairs(spGetTeamUnitsByDefs(myTeam, landableIndex)) do
			myAircrafts[aircraftID] = true
		end
		myAircraftID = next(myAircrafts)
		for _, teamID in ipairs(alliance[myAllyTeam]) do
			local isAllied = teamID ~= myTeam
			for _, padID in ipairs(spGetTeamUnitsByDefs(teamID, padIndex)) do
				if isAllied then
					allyPads[padID] = teamID
				else
					myPads[padID] = teamID
				end
			end
		end
		for padID in pairs(myPads) do
			if IsExcluded(padID) then
				UpdatePad(padID, myTeam, false, 'PlayerChanged: ')
			end

		end
		for padID, teamID in pairs(allyPads) do
			local isExcluded = IsExcluded(padID)
			if next(myPads) then
				if not isExcluded then
					UpdatePad(padID, teamID, true, 'PlayerChanged: ')
				end
			else
				if isExcluded then
					UpdatePad(padID, teamID, false, 'PlayerChanged: ')
				end
			end
		end
	end
end

function widget:UnitCreated(unitID, defID, teamID)
	if landable[defID] then
		myAircrafts[unitID] = true
		if not myAircraftID or updateMyAircraftID then
			myAircraftID = unitID
			updateMyAircraftID = false
			for padID, bool in pairs(pending) do
				if IsExcluded(padID) ~= bool then
					UpdatePad(padID, bool, nil, 'UnitCreated: ')
				end
			end
		end
	elseif pad[defID] then
		if myTeam ~= teamID then
			if not IsExcluded(unitID) then
				UpdatePad(unitID, true, teamID, 'UnitCreated: ')
			end
		end
	end
end

function widget:UnitFinished(unitID, defID, teamID)
	if pad[defID] then
		if teamID == myTeam then
			if not next(myPads) then
				for padID in pairs(allyPads) do
					UpdatePad(padID, true, nil, 'UnitFinished: ')
				end
			end
			myPads[unitID] = true
		else
			if next(myPads) then
				UpdatePad(unitID, true, teamID, 'UnitFinished: ')
			end
		end
	elseif landable[defID] then
		if teamID == myTeam then
			if not myAircraftID then
				widget:UnitCreated(unitID, defID, teamID)
			else
				myAircrafts[unitID] = true
			end
		end
	end
end

function widget:UnitDestroyed(unitID, defID, teamID)
	if pad[defID] then 
		if myPads[unitID] then
			myPads[unitID] = nil
			if not next(myPads) then
				for padID in pairs(allyPads) do
					UpdatePad(padID, false, nil, 'UnitDestroyed: ')
				end
			end
		else
			allyPads[unitID] = nil
		end
		pending[unitID] = nil
	elseif teamID == myTeam and landable[defID] then
		myAircrafts[unitID] = nil
		updateMyAircraftID = 5 -- asking a delayed update to avoid checking spam in case lots of air is destroyed at once
	end
end

function widget:UnitTaken(unitID, defID, fromTeam, toTeam)
	if landable[defID] or pad[defID] then
		if myAllyTeam == allyTeam[fromTeam] then 
			widget:UnitDestroyed(unitID, defID, fromTeam)
		end
		if myAllyTeam == allyTeam[toTeam] then 
			if IsFinished(unitID) then
				widget:UnitFinished(unitID, defID, toTeam)
			else
				widget:UnitCreated(unitID, defID, toTeam)
			end
		end
	end
end

function widget:UnitGiven(unitID, defID, toTeam, fromTeam)
	if myAllyTeam == allyTeam[fromTeam] then
		-- it has already been dealt in UnitTaken
		return
	else
		widget:UnitTaken(unitID, defID, fromTeam, toTeam)
	end
end

function widget:UnitReverseBuilt(unitID, defID, teamID)
	if myAllyTeam == allyTeam[teamID] and (pad[defID] or landable[defID]) then
		widget:UnitDestroyed(unitID, defID, teamID)
	end
end

function widget:Update()
	if updateMyAircraftID then
		updateMyAircraftID = updateMyAircraftID - 1
		if updateMyAircraftID == 0 then
			updateMyAircraftID = false
			myAircraftID = next(myAircrafts)
		end
	end
end

function widget:Initialize()
	myPlayerID = Spring.GetMyPlayerID()
	-- purposefully don't give the teamID and allyTeamdID to make a refresh in PlayerChanged
	widget:PlayerChanged(myPlayerID)
end