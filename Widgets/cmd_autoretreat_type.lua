function widget:GetInfo()
	return {
		name      = "AutoRetreat Type",
		desc      = "Switch Auto Retreat State for current selected unit type and those to be produced later",
		author    = "Helwor",
		date      = "Dec 2023",
		license   = "GNU GPL, v2 or later",
		layer     = 2, -- after Unit Start State
		enabled   = true,  --  loaded by default?
		handler   = true,
	}
end

local Echo = Spring.Echo

-- if you're not having Hel-K EPIC MENU then you can edit the table directly here
--  1 = Retreat 30%, 2 = 'Retreat 65%, 3 = Retreat 99%, excluded = false
-- human name of game name of units are both accepted
-- on load it will complete the table by unit health >= 350 and < 500 for 65% retreat, and > 500 with 30% retreat, excluding arty except for sling
-- both 

local uniqueStateByType = {
	-- example
	Ronin = 2, -- human name
	Glaive = 3, 
	-- spideremp = false, -- game name of Venom 

}
local candidateDefID = {}
for defID, def in pairs(UnitDefs) do
	if def.canMove and not def.isFactory then
		local name, humanName = def.name, def.humanName
		-- ignore comms, drone, chicken, ...
		if not (
            -- name:find('dyn')
            -- or name:find('c%d+_base')
            -- or name:find('com%d+$')
            -- or name:find('comm')
            (def.customParams.dynamic_comm or def.customParams.level) -- is comm
            or name:find('drone')
            or name:find('chicken')
            or name:find('starlight_satellite'))
        then 
			candidateDefID[defID] = humanName
			local health = def.health
			if health >= 150 then
				-- ignore valid but unwanted bomb, arty except for Sling 
				if not (name:find('bomb') or name:find('arty') and name ~= 'cloakarty') then
					if uniqueStateByType[name] == nil and uniqueStateByType[humanName] == nil then
						uniqueStateByType[name] =  health < 7000 and 2 or 1
					end
				end
			end
		end
	end
end

local situationalRetreatType = { -- apply only on selected instead of by type

}
for defID, def in pairs(UnitDefs) do
	if candidateDefID[defID] then
		local name = def.name
		if name:find('raid') or name:find('scout')
			or name == 'spideremp'
		then
			situationalRetreatType[name] = true
		else
			situationalRetreatType[name] = false
		end
	end
end


local uniqueStateByDefID = {
	Update = function(self)
		for k in pairs(self) do
			if k ~= 'Update' then
				self[k] = nil
			end
		end
		local UnitDefs, UnitDefNames = UnitDefs, UnitDefNames
		for name, value in pairs(uniqueStateByType) do
			local lowname = name:lower()
			local correctdef = UnitDefNames[name]

			if not correctdef then
				uniqueStateByType[name] = nil
				if lowname ~= name then
					correctdef = UnitDefNames[lowname]
				end
				if not correctdef then
					for defID, def in pairs(UnitDefs) do
						if def.humanName:lower() == lowname then
							uniqueStateByType[def.name] = value
							correctdef = def
							break
						end
					end
				end
			end
			if correctdef and candidateDefID[correctdef.id] then
				self[correctdef.id] = value
			end
		end
	end
}
uniqueStateByDefID:Update()

local situationalRetreatDefID = {
	Update = function(self)
		for k in pairs(self) do
			if k ~= 'Update' then
				self[k] = nil
			end
		end
		local UnitDefs, UnitDefNames = UnitDefs, UnitDefNames
		for name, value in pairs(situationalRetreatType) do
			local lowname = name:lower()
			local correctdef = UnitDefNames[name]

			if not correctdef then
				situationalRetreatType[name] = nil
				if lowname ~= name then
					correctdef = UnitDefNames[lowname]
				end
				if not correctdef then
					for defID, def in pairs(UnitDefs) do
						if def.humanName:lower() == lowname then
							situationalRetreatType[def.name] = value
							correctdef = def
							break
						end
					end
				end
			end
			if correctdef and candidateDefID[correctdef.id] then
				self[correctdef.id] = value
			end
		end
	end
}
situationalRetreatDefID:Update()





local spGetTeamUnitsByDefs      = Spring.GetTeamUnitsByDefs
-- local spGiveOrder            = Spring.GiveOrder
local spGiveOrderToUnit			= Spring.GiveOrderToUnit
local spGetUnitRulesParam       = Spring.GetUnitRulesParam
local spGetTeamRulesParam		= Spring.GetTeamRulesParam
local spGetActiveCommand		= Spring.GetActiveCommand
local spSetActiveCommand		= Spring.SetActiveCommand
local CMD_OPT_RIGHT             = CMD.OPT_RIGHT
local CMD_RETREAT
do
	local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")
	CMD_RETREAT = customCmds.RETREAT
end



local states, wantedStates, maxState
do
	states = { 'Retreat Off', 'Retreat Off', 'Retreat 30%', 'Retreat 65%', 'Retreat 99%' } -- from cmd_retreat
	-- TODO: how to get the command desc without unit? for future change?
	-- (OPT_RIGHT option (right click) or maxState-1 which is then translated to 0 by modulo, giving directly 0 will not work) 
	-- the #1 being the place holder for default state

	maxState = #states
	table.remove(states, 1)
	-- states[maxState] = nil
	maxState = maxState - 1
	states[0] = states[1]
	wantedState = {} 
	local j = 0
	for i = 3, maxState-2 do
		j = j + 1
		wantedState[j] = true
	end
end
--

local hotkey = 'Alt+r' -- default hotkey
local myTeamID = Spring.GetMyTeamID()
local playerID = Spring.GetMyPlayerID()
local byType = {}
local selTypes = false
local typeArray = false
local situationalUnits = false
local EMPTY_TABLE = {}
local PARAM_STATE = {}
local TYPE_TABLE = {}


local function SetUnitAutoRetreat(id, state, checkCurState)
	if checkCurState and state == spGetUnitRulesParam(id, 'retreatState') then
		return false
	end
	-- if state == 0 then -- it can also work by giving maxState param instead
	-- 	spGiveOrderToUnit(id, CMD_RETREAT, EMPTY_TABLE, CMD_OPT_RIGHT)
	-- else
		spGiveOrderToUnit(id, CMD_RETREAT, PARAM_STATE, 0)
	-- end
	return true
end

local function SwitchAutoRetreat(state, curStateByID) -- set to the next allowed state
	while wantedState[state] == false do -- check if user wanna skip that state
		state = state + 1
	end
	PARAM_STATE[1] = state
	if state == maxState then
		-- we stop tracking new units and will set the current to 'Retreat Off'
		state = 0
		for i, defID in pairs(typeArray) do
			byType[defID] = nil
		end
	else
		for i, defID in pairs(typeArray) do
			byType[defID] = state
		end
	end	
	local changed = false	
	if typeArray[1] then
		for i, id in pairs(spGetTeamUnitsByDefs(myTeamID, typeArray) or EMPTY_TABLE) do
			changed = SetUnitAutoRetreat(id, state, true) or changed
		end
	end
	for defID, units in pairs(situationalUnits) do
		for i, id in ipairs(units) do
			if state ~= curStateByID[id] then
				changed = SetUnitAutoRetreat(id, state) or changed
			end
		end
	end
	return state, changed
end
local function SwitchOnOffAutoRetreat(on, curStateByID) -- toggle on/off retreat state if option unique state by type enabled
	local changed = false
	for _, defID in pairs(typeArray) do
		TYPE_TABLE[1] = defID
		local state = on and uniqueStateByDefID[defID] or 0
		PARAM_STATE[1] = on and state or maxState
		for i, id in pairs(spGetTeamUnitsByDefs(myTeamID, TYPE_TABLE) or EMPTY_TABLE) do
			changed = SetUnitAutoRetreat(id, state, true) or changed
		end
		byType[defID] = on and state or nil
	end
	for defID, units in pairs(situationalUnits) do
		local state = on and uniqueStateByDefID[defID] or 0
		PARAM_STATE[1] = on and state or maxState
		for i, id in ipairs(units) do
			if state ~= curStateByID[id] then
				changed = SetUnitAutoRetreat(id, state) or changed
			end
		end
	end
	return on, changed
end


local function GetMostPresentState()
	if not (typeArray[2] or next(situationalUnits)) then
		return byType[ typeArray[1] ] or 0
	end
	local counts, curStateByID = {}, {}
	for i, defID in pairs(typeArray) do
		local units = selTypes[defID]
		local state = byType[defID] or 0
		counts[state] = (counts[state] or 0) + (units.count or #units)
	end
	for defID, units in pairs(situationalUnits) do
		local units = selTypes[defID]
		for i = 1, #units do
			local id = units[i]
			local state = spGetUnitRulesParam(id, 'retreatState') or 0
			if state == maxState then
				state = 0
			end
			curStateByID[id] = state
			counts[state] = (counts[state] or 0) + 1
		end
	end
	local mostCount = 0
	local mostPresentState = 0
	for state = 1, maxState do
		local count = counts[state]
		if count and count > mostCount then
			mostCount = count
			mostPresentState = state
		end
	end
	return mostPresentState, curStateByID
end

function GetMostRetreating()
	if not (typeArray[2] or next(situationalUnits)) then
		return not not byType[ typeArray[1] ]
	end
	local counts, curStateByID = {}, {}

	for i, defID in pairs(typeArray) do
		local units = selTypes[defID]
		local state = not not byType[defID]
		counts[state] = (counts[state] or 0) + (units.count or #units)
	end
	for defID, units in pairs(situationalUnits) do
		for i, id in ipairs(units) do
			local state = spGetUnitRulesParam(id, 'retreatState') or 0
			if state == maxState then -- never happening ?
				state = 0
			end
			curStateByID[id] = state
			if state == 0 then
				state = false
			else
				state = not not state
			end
			counts[state] = (counts[state] or 0) + 1
		end
	end
	return (counts[true] or 0) > (counts[false] or 0), curStateByID
end

local function GetArrays(filterUnique)
	if not typeArray then
		selTypes = WG.selectionDefID or spGetSelectedUnitsSorted() or EMPTY_TABLE
		typeArray = {}
		situationalUnits = {}
		local n = 0
		for defID, units in pairs(selTypes) do
			if candidateDefID[defID] then
				if not filterUnique or uniqueStateByDefID[defID] then
					if situationalRetreatDefID[defID] then
						situationalUnits[defID] = units
					else
						n = n + 1
						typeArray[n] = defID
					end
				end
			end
		end
	end
end

local function Comment(state)
	if options.comment.value then
		local named, n = {}, 0
		for _, defID in pairs(typeArray) do
			n = n + 1
			named[n] = candidateDefID[defID] -- .. ' [' .. defID .. ']'
		end
		for _, defID in pairs(situationalUnits) do
			n = n + 1
			named[n] = candidateDefID[defID] -- .. ' [' .. defID .. ']'
		end
		if type(state) == 'boolean' then
			Echo('Auto-Retreat set to ' .. (on_off and 'ON' or 'OFF') .. ' for: ' .. table.concat(named,', ') )
		else
			Echo('Auto-Retreat set to ' .. states[state] .. ' for: ' .. table.concat(named,', ') )
		end
		if typeArray[1] and state == 0 or not state then
			Echo("Newly made units aren't bound anymore to widget " .. widget.GetInfo().name .. ".")
		end
	end
end


local function Process()
	-- if spGetActiveCommand() ~= 0 then
	-- 	return
	-- end
	local onlyUnique = options.uniqueByType.value
	GetArrays(onlyUnique)
	if not (typeArray[1] or next(situationalUnits)) then
		return
	end
	local state, changed, playSound
	local wantedState, curStateByID
	if onlyUnique then
		state, curStateByID = GetMostRetreating()
		wantedState = not state
	else
		state, curStateByID = GetMostPresentState()
		wantedState = state + 1
	end
	if onlyUnique then
		state, changed = SwitchOnOffAutoRetreat( wantedState, curStateByID )
	else
		state, changed = SwitchAutoRetreat( wantedState, curStateByID )
	end


	if (state and state ~= 0) and options.newHaven.value then
		local havenCount = spGetTeamRulesParam(myTeamID, "haven_count")
		if not havenCount or havenCount == 0 then
			spSetActiveCommand('sethaven')
			playSound = true
		end
	end
	if changed then
		playSound = true
		Comment(state)
	end
	if playSound then
		WG.noises.PlayResponse(false, typeArray[1] or next(situationalUnits))
	end
	
end
---------- Options
options_path = 'Hel-K/' .. widget.GetInfo().name
options_order = {}
options = {}
options.command = {
	name = widget.GetInfo().name,
	type = 'button',
	slim = true,
	desc = widget.GetInfo().desc,
	hotkey = hotkey,
	OnChange = Process,
	action = 'autoretreat_type',
}
options_order[#options_order + 1]  = 'command'

for i = 1, maxState-1 do
	options['wantedState' .. i] = {
		name = "Use '" .. states[i+1] .. "'",
		type = 'bool',
		desc = '',
		noHotkey = true,
		value = true,
		slim = true,
		OnChange = function(self)
			wantedState[i] = self.value
		end,
	}
	options_order[#options_order + 1]  = 'wantedState' .. i
end

options.newHaven = {
	name = 'New Retreat Zone if needed',
	desc = "Activate the command to set up a new Retreat Zone if there's none.",
	type = 'bool',
	value = false,
	-- noHotkey = true,
	slim = true,
}
options_order[#options_order + 1]  = 'newHaven'

options.uniqueByType = {
	name = 'Custom and unique retreat % by type',
	type = 'bool',
	value = false,
	desc = (function()
		local t = {}
		t[1] = 'Only set predefined units with unique retreat % On and off'
		t[2] = 'Values:'
		for i = 1, maxState - 1 do
			t[#t+1] = '\t\t' .. states[i] .. ' => ' .. i
		end
		t[#t+1] = '(Regular unit name like "Ronin" are accepted)'
		if not WG.EpicMenuFromHelK then
			t[#t+1] = ('NOTE: without EPIC MENU from Hel-K you need to edit the table "uniqueStateByType" directly in the widget')
		end
		return table.concat(t,'\n')
	end)(),
	OnChange = function(self)
		widget:CommandsChanged()
	end,
	noHotkey = true,
	slim = true,
	children = {'editUniqueByType'},
}
options_order[#options_order + 1]  = 'uniqueByType'

options.editUniqueByType = {
	name = 'Edit Custom Retreat %',
	type = 'table',
	desc = options.uniqueByType.desc,
	slim = true,
	value = uniqueStateByType,
    OnChange = function(self)
        uniqueStateByDefID:Update()
        widget:CommandsChanged()
    end,
    parents = {'uniqueByType'},
    noRemove = true,
}
options_order[#options_order + 1]  = 'editUniqueByType'

options.editSituational = {
	name = 'Situational Retreat',
	type = 'table',
	desc = 'Which type of units you want to be processed individually via selection, rather than by type',
	slim = true,
	value = situationalRetreatType,
    OnChange = function(self)
        situationalRetreatDefID:Update()
        widget:CommandsChanged()
    end,
	noRemove = true,
	isCheckboxList = true,
}
options_order[#options_order + 1]  = 'editSituational'

options.comment = {
	name = 'Comment on console',
	desc = 'Get aware of what happen after the given order until I implement some visual :P',
	type = 'bool',
	value = false,
	slim = true,
	noHotkey = true,
}
options_order[#options_order + 1]  = 'comment'

--------------------
function widget:PlayerChanged(playerID)
    if playerID == myPlayerID then
	   myTeamID = Spring.GetMyTeamID()
    end
end
function widget:CommandsChanged()
	typeArray = false
	selTypes = false
	situationalUnits = false
end


function widget:Initialize()
	if Spring.GetSpectatingState() then
		widget.status = 'Useless as spectator.'
		widgetHandler:RemoveWidget(widget)
		return
	end
	myPlayerID = Spring.GetMyPlayerID()
	myTeamID = Spring.GetMyTeamID()
end

function widget:UnitCreated(id, defID)
	if byType[defID] then
		SetUnitAutoRetreat(id, byType[defID])
	end
end
widget.UnitGiven = widget.UnitCreated

f.DebugWidget(widget)