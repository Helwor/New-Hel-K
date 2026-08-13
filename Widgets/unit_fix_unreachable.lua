function widget:GetInfo()
	return {
	name      = "Fix Unreachable Target",
	desc      = "Make cons abandon unreachable reclaim or repair targets",
	author    = "Helwor",
	date      = "Aug 2026",
	license   = "GNU GPL, v2 or later",
	layer     = 10e36,
	enabled   = false,  --  loaded by default?
	handler   = true,
	}
end

local Spring = Spring
local UnitDefs = UnitDefs
local FeatureDefs = FeatureDefs
local table = table
local CMD = CMD
local CMD_RAW_BUILD = Spring.Utilities.CMD.RAW_BUILD
-- local newSequence = true
-- local checkForCommand = false
-- Situation AREA RECLAIM ISSUED OR AREA REPAIR ISSUED
-- Flying Units doesn't have RAW_BUILD command when ordered to work, so we can discriminate them effortlessly
-- CASE unit don't need to move to start reclaiming
	-- UnitCommand receive only CMD.RECLAIM with 4 args x, y, z, r params
	-- nothing else appear neither in the command queue nor in GetUnitCurrentCommand
	-- but a silent order is inserted which is CMD.RECLAIM with 5 params, the first being the featureID, the four other being the normal x, y, z, r params
	-- so if we need we have to check one update later which feature the unit it actually reclaiming
	-- in the next Update() Spring.GetUnitCurrentCommand() or Spring.GetUnitCommands() will reveal it
-- CASE unit has to move
	-- UnitCommand receive CMD.RECLAIM with 4 args x, y, z, r params
	-- a non silent RAW_BUILD is inserted at 0 containing 5 params, feature pos, timeout I believe (2), an id related to the unit defID reclaiming
	-- NOTE: weirdly enough when area command is queued and next to be executed, the unit start walking toward the feature but the RAW_BUILD is not immediately inserted, but some frame later
	-- at this point in time, the CMD.RECLAIM with 5 params containing the featureID can be detected via Spring.GetUnitCurrentCommand() or Spring.GetUnitCommands()
	-- but also in UnitCmdDone, due to a bug, the CMD.RECLAIM with 5 params will also appears to be "done".
	-- It's a bug that happen when then current order is pushed by an insertion
	-- but we CAN be still in the same sequence, no new Update() or GameFram() happened yet

local debugging = false
local GAME_SPEED = Game.gameSpeed
local MAX_UNITS = Game.maxUnits
local NOISE_DIST = 16
local watching = table.new(50, 50)
local abandoned = table.new(200, 200)
local updateRate = (debugging and 1 or 3) * GAME_SPEED
local timeoutStuck = (debugging and 1 or 3) * updateRate
local timeoutCache = 2 * GAME_SPEED
local updateAbandoned = 15 * GAME_SPEED
local timeoutAbandoned = 150 * GAME_SPEED
local currentFrame = -1
local UnitDefs = UnitDefs
local myTeamID
local myPlayerID = Spring.GetMyPlayerID()
local selectedWatching = {}
local pending = {}
local handledCmd = {
	[CMD.RECLAIM] = true,
	[CMD.REPAIR] = true,
	-- [CMD.RESURRECT] = true, -- NOT IMPLEMENTED YET, BEHAVIOUR IS DIFFERENT, DOESN'T RECEIVE A RAW_BUILD ORDER
}


local function copy(t)
	local new = {}
	for k, v in pairs(t) do
		new[k] = v
	end
	return new
end
local cache = setmetatable({}, {__mode = 'v'})
local function clear(t)
	for k,v in pairs(t) do
		t[k] = nil
	end
end

local function FeatureIsResurrectable(featureID)
	local fDefID = Spring.GetFeatureDefID(featureID)
	if fDefID then
		return FeatureDefs[fDefID].resurrectable == 1
	end
end

local function GetFeaturesInCylinder(cmdID, ctrl, x, z, r)
	local strID = 'F'.. x..'-'..z..'-'..r
	local cached = cache[strID]
	if not cached then -- want metal only
		local features = Spring.GetFeaturesInCylinder(x, z, r)
		if cmdID == CMD.RECLAIM then
			cached = {}
			local i = 0
			for _, featureID in ipairs(features) do
				local fm, _, fe = Spring.GetFeatureResources(featureID)
				if ctrl and (fe > 0.001 or fm > 0.001) or not ctrl and fm > 0.001 then
					if Spring.GetFeatureResources(featureID) > 0.001 then
						i = i + 1
						cached[i] = {id = featureID + MAX_UNITS, Spring.GetFeaturePosition(featureID)}
					end
				end
			end
		elseif cmdID == CMD.RESURRECT then
			cached = {}
			local i = 0
			for _, featureID in ipairs(features) do
				if FeatureIsResurrectable(featureID) then
					i = i + 1
					cached[i] = {id = featureID + MAX_UNITS, Spring.GetFeaturePosition(featureID)}
				end
			end
		else
			cached = table.new(#features)
			for i, featureID in ipairs(features) do
				cached[i] = {id = featureID + MAX_UNITS, Spring.GetFeaturePosition(featureID)}
			end
		end
		cached.timeout = currentFrame + timeoutCache
		cache[strID] = cached
	elseif currentFrame > cached.timeout then
		local features = Spring.GetFeaturesInCylinder(x, z, r)
		clear(cached)
		if cmdID == CMD.RECLAIM then
			local i = 0
			for _, featureID in ipairs(features) do
				local fm, _, fe = Spring.GetFeatureResources(featureID)
				if ctrl and (fe > 0.001 or fm > 0.001) or not ctrl and fm > 0.001 then
					if Spring.GetFeatureResources(featureID) > 0.001 then
						i = i + 1
						cached[i] = {id = featureID + MAX_UNITS, Spring.GetFeaturePosition(featureID)}
					end
				end
			end
		elseif cmdID == CMD.RESURRECT then
			local i = 0
			for _, featureID in ipairs(features) do
				if FeatureIsResurrectable(featureID) then
					i = i + 1
					cached[i] = {id = featureID + MAX_UNITS, Spring.GetFeaturePosition(featureID)}
				end
			end
		else
			for i, featureID in ipairs(features) do
				cached[i] = {id = featureID + MAX_UNITS, Spring.GetFeaturePosition(featureID)}
			end
		end
		cached.timeout = currentFrame + timeoutCache
	else
		return cached, true
	end
	return cached
end

local function GetFriendlyUnitsInCylinder(cmdID, x, z, r)
	local strID = 'U'.. x..'-'..z..'-'..r
	local cached = cache[strID]
	if not cached then 
		local units = Spring.GetUnitsInCylinder(x, z, r, Spring.ALLY_UNITS)
		if cmdID == CMD.REPAIR then
			cached = {}
			local i = 0
			for _, unitID in ipairs(units) do
				local hp, maxhp = Spring.GetUnitHealth(unitID)
				if hp < maxhp then
					i = i + 1
					cached[i] = {id = unitID, Spring.GetUnitPosition(unitID)}
				end
			end
		else
			cached = table.new(#units)
			for i, unitID in ipairs(units) do
				cached[i] = {id = unitID, Spring.GetUnitPosition(unitID)}
			end
		end
		cached.timeout = currentFrame + timeoutCache
		cache[strID] = cached
	elseif currentFrame > cached.timeout then
		local units = Spring.GetUnitsInCylinder(x, z, r, Spring.ALLY_UNITS)
		clear(cached)
		if cmdID == CMD.REPAIR then
			local i = 0
			for _, unitID in ipairs(units) do
				local hp, maxhp = Spring.GetUnitHealth(unitID)
				if hp < maxhp then
					i = i + 1
					cached[i] = {id = unitID, Spring.GetUnitPosition(unitID)}
				end
			end
		else
			for i, unitID in ipairs(units) do
				cached[i] = {id = unitID, Spring.GetUnitPosition(unitID)}
			end
		end
		cached.timeout = currentFrame + timeoutCache
	else
		return cached, true
	end
	return cached
end

local function FindClosestAvailable(unitID, cmdID, ctrl, x, y, z, r)
	local ux, _, uz= Spring.GetUnitPosition(unitID)
	local things, wasCached
	if (cmdID == CMD.RECLAIM or cmdID == CMD.RESURRECT) then
		things, wasCached = GetFeaturesInCylinder(cmdID, ctrl, x, z, r)
	else
		things, wasCached = GetFriendlyUnitsInCylinder(cmdID, x, z, r)
	end
	if --[[not wasCached and]] things[2] then
		local diag = math.diag
		table.sort(things, function(a, b) return  diag(a[1] - ux, a[3] - uz) < diag(b[1] - ux, b[3] - uz) end)
	end
	local abandoned = abandoned
	local avoidSelf = cmdID == CMD.REPAIR
	for i, thing in ipairs(things) do
		if not (abandoned[thing.id..'-'..unitID] or avoidSelf and unitID == thing.id) then
			return thing.id
		end
	end
end


local function Retarget(unitID, debug)
	local queue = Spring.GetUnitCommands(unitID, 3)
	if debug then
		for i, order in ipairs(queue) do
			Echo('unit', unitID, 'order', i, 'cmd', f.cmdNames[order.id], #order.params)
		end
	end
	if not queue[1] or queue[1].id ~= CMD_RAW_BUILD then
		return -- something wrong
	end
	local second = queue[2]
	local cmdID = second and second.id
	if not cmdID then
		return -- another thing wrong
	end
	if not second.params[5] then -- case not an area command, just remove the order
		if debugging then
			Echo('remove simple order for', f.cmdNames[second.id], 'tag', second.tag, 'targetID', second.params[1])
		end
		Spring.GiveOrderToUnit(unitID, CMD.REMOVE, second.tag, 0)
		return
	end
	local third = queue[3]
	if third and third.id == cmdID and #third.params == 4 then
		-- case area order
		Spring.GiveOrderToUnit(unitID, CMD.REMOVE, second.tag, 0)
		local targetID = FindClosestAvailable(unitID, cmdID, third.options.ctrl, unpack(third.params))
		if targetID then
			-- Spring.GiveOrderToUnit(unitID, CMD.INSERT, {0, Spring.Utilities.CMD.RAW_MOVE, 0, 500, 500, 500}, CMD.OPT_ALT)
			Spring.GiveOrderToUnit(unitID, CMD.INSERT, {0, cmdID, 0, targetID, unpack(third.params)}, CMD.OPT_ALT)
		else
			Spring.GiveOrderToUnit(unitID, CMD.REMOVE, third.tag, 0)
		end
		if debugging then
			Echo('Remove target', second.params[1], targetID and 'Retarget to '..targetID or 'Remove Area Order' )
		end

	else
		return -- definitely wrong
	end
end


function widget:UnitCommand(unitID, defID, teamID, cmdID, params, options, ...)
	-- GetUpdate()
	if cmdID == CMD.REMOVE then
		return
	end
	if debugging then
		f.DebugUnitCommand(unitID, defID, teamID, cmdID, params, options, ...)
	end
	local inserting = cmdID == CMD.INSERT
	local insertPos
	if inserting then
		insertPos = params[1]
		if insertPos == 0 and params[2] == CMD_RAW_BUILD then
			local cmd, opt, tag, p1, p2, p3, p4, p5 = Spring.GetUnitCurrentCommand(unitID)
			if (p5 or not p4) and handledCmd[cmd] then
				if abandoned[p1..'-'..unitID] then
					if debugging then
						Echo('GOT Abandoned', p1, ' from RAW_BUILD')
					end
					pending[unitID] = true
				else
					watching[unitID] = {
						stuck = 0,
						targetID = p1,
						speed = UnitDefs[defID].speed,
					}
					if debugging then
						Echo('GOT Feature ', watching[unitID].targetID, ' from RAW_BUILD', 'start watching', watching[unitID].targetID)
					end
				end

				-- engine behaviour inserting a CMD_RAW_BUILD when order is out of reach
			end
			return
		end
		-- if insertPos == 0 then
		--  cmdID = params[2]
		--  params = {select(4, unpack(params))}
		-- end
	end
	--[[if cmdID == CMD.RECLAIM and params[4] then
		if params[5] then
			-- watching[unitID] = params[1]
			-- Echo('watching[unitID]', watching[unitID], 'from UnitCommand', inserting and 'inserting' or '')
		else
			-- checkForCommand = unitID
		end
	else]]if not options.shift or insertPos == 0 then
		if watching[unitID] then
			if debugging then
				Echo('stop watching ', watching[unitID].targetID, 'order with no shift')
			end
			watching[unitID] = nil
		end
	end
end

function widget:UnitCmdDone(unitID, defID, teamID, cmdDone, paramsDone, optionsDone, tagDone)
	-- GetUpdate()
	if not watching[unitID] then
		return
	end
	if debugging then
		f.DebugUnitCmdDone(unitID, defID, teamID, cmdDone, paramsDone, optionsDone, tagDone)
	end
	local cmd, opt, tag, p1, p2, p3, p4, p5 = Spring.GetUnitCurrentCommand(unitID)

	if tag == tagDone then
		-- an insertion has just pushed the "done" order (bug of UnitCmdDone)
		return
	end
	if cmdDone == CMD.STOP then
		if watching[unitID] then
			if debugging then
				Echo('stop watching', watching[unitID].targetID, 'STOP done')
			end
			watching[unitID] = nil
		end
	--[[elseif cmdDone == CMD.RECLAIM then
		if #paramsDone == 5 then
			-- Echo('stop watching', paramsDone[1], 'from unitCmdDone')
			-- watching[unitID] = nil
		elseif #paramsDone == 4 then
			Echo('Area Reclaim done')
		end
	]]elseif cmdDone == CMD_RAW_BUILD then
		if watching[unitID] then
			if debugging then
				Echo('stop watching', watching[unitID].targetID, 'RAW_BUILD done')
			end
			watching[unitID] = nil
		end
	end
	-- if cmdDone == CMD.RECLAIM then
	-- 	if p5 then 
	-- 		watching[unitID] = p1
	-- 		Echo('nextFeature to watch', watching[unitID], 'from unitCmdDone')
	-- 	elseif p4 then
	-- 		Echo('next order is reclaim area, get command...')
	-- 		checkForCommand = unitID
	-- 	end
	-- end
end


function widget:CommandsChanged()
	selectedWatched = {}
	local selMap = WG.selectionMap
	if not selMap then
		local sel = spGetSelectedUnits()
		selMap = table.new(0, #sel)
		for i, unitID in ipairs(sel) do
			selMap[unitID] = true
		end
	end
	for unitID in pairs(selMap) do
		local obj = watching[unitID]
		if obj then
			selectedWatched[unitID] = obj
		end
	end
end

function widget:CommandNotify(cmd, params, options)
	if next(selectedWatching) then
		if not options.shift or cmd == CMD.INSERT and params[1] == 0 then
			for unitID in pairs(selectedWatching) do
				selectedWatching[unitID] = nil
				watching[unitID] = nil
				if debugging then
					Echo('stopped watching', watching[unitID].targetID, 'from Command Notify')
				end
			end
		end
	end
end

function widget:GameFrame(frame)
	-- local unitID = Spring.GetSelectedUnits()[1]
	-- if unitID then
	--  local queue = Spring.GetUnitCommands(unitID, -1)
	--  for i, order in ipairs(queue) do
	--      Echo(i, f.cmdNames[order.id], '#'..#order.params)
	--  end
	-- end
	currentFrame = frame
	for unitID in pairs(pending) do
		Retarget(unitID)
		pending[unitID] = nil
	end
	if frame % updateRate == 0 then
		local posCache = {}
		for unitID, obj in pairs(watching) do
			local targetID = obj.targetID
			
			local pos = posCache[targetID]
			if not pos then
				if targetID >= MAX_UNITS then
					pos = {Spring.GetFeaturePosition(targetID - MAX_UNITS)}
				else
					pos = {Spring.GetUnitPosition(targetID)}
				end
				posCache[targetID] = pos
			end
			local tx, ty, tz = pos[1], pos[2], pos[3]

			if not tx then
				if debugging then
					Echo('stop watching', targetID, 'invalid')
				end
				watching[unitID] = nil
			else
				local ux, uy, uz = Spring.GetUnitPosition(unitID)
				local dist = math.diag(ux - tx, uz - tz)

				if not obj.bestDist or dist < obj.bestDist - NOISE_DIST then
					obj.bestDist = dist
					obj.stuck = 0
				else
					obj.stuck = obj.stuck + updateRate
					if debugging then
						Echo('unit stuck', obj.stuck, '/', timeoutStuck, obj.stuck >= timeoutStuck)
					end
					if obj.stuck >= timeoutStuck then
						abandoned[targetID..'-'..unitID] = currentFrame + timeoutAbandoned
						Retarget(unitID)
						watching[unitID] = nil
					end
				end
			end
		end
	end

	if frame % updateAbandoned == 0 then
		for id, timeout in pairs(abandoned) do
			if currentFrame > timeout then
				abandoned[id] = nil
			end
		end
	end
end

function widget:UnitDestroyed(unitID)
	watching[unitID] = nil
end

function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
	end
end

function widget:Initialize()
	widget:PlayerChanged(myPlayerID)
end

f.DebugWidget(widget)