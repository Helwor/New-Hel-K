--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "Transport Load Double Tap",
    desc      = "Matches selected transports and units when load is double pressed.",
    author    = "GoogleFrog, rewrite and improved by Helwor",
    date      = "8 May 2015",
    license   = "GNU GPL, v2 or later",
    layer     = -math.huge,
    handler   = true,
    enabled   = true,
  }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local Echo = Spring.Echo


-- default value before user start touching options
local shortWalkDist     = 300
local letAutoWait       = true
local noSelectNeeded    = true

--


VFS.Include("LuaRules/Configs/customcmds.h.lua")


local CMD_MOVE                  = CMD.MOVE
local CMD_SET_WANTED_MAX_SPEED  = CMD.SET_WANTED_MAX_SPEED
local CMD_LOAD_UNITS            = CMD.LOAD_UNITS
local CMD_UNLOAD_UNIT           = CMD.UNLOAD_UNIT
local CMD_RECLAIM               = CMD.RECLAIM
local CMD_REPAIR                = CMD.REPAIR
local CMD_RESURRECT             = CMD.RESURRECT
local CMD_WAIT                  = CMD.WAIT
local CMD_REMOVE                = CMD.REMOVE
local CMD_MANUALFIRE            = CMD.MANUALFIRE

local CMD_OPT_SHIFT             = CMD.OPT_SHIFT
local CMD_OPT_RIGHT             = CMD.OPT_RIGHT

local CMD_ONECLICK_WEAPON       = CMD_ONECLICK_WEAPON



local UseHungarian, SpiralSquare

local indexedLightTrans     = {}
local indexedHeavyTrans     = {}
local transDefID 	  	    = {}
local lightTransDefID 	    = {}
local heavyDefID 		    = {}
local untransportableDefID  = {}
local waitForLoad 		    = {}
local OPT_RIGHT_TABLE       = {alt=false, ctrl=false, meta=false, shift=false, right=true, internal=false, coded=CMD_OPT_RIGHT}

for defID, def in pairs(UnitDefs) do
	if (def.canFly or def.cantBeTransported) then
		if def.isTransport then
			transDefID[defID] = true
			if def.customParams.islighttransport then
                table.insert(indexedLightTrans, defID)
				lightTransDefID[defID] = true
            else
                table.insert(indexedHeavyTrans, defID)
			end
        else
            untransportableDefID[defID] = true
		end
	else
        if def.customParams.requireheavytrans then
		  heavyDefID[defID] = true
        end

	end
end




options_path = 'Settings/Interface/Commands/Transport Load Double Tap'
options_order = {'nocopyshortwalk','noselneeded','letautowait'}
options = {}

options.nocopyshortwalk = {
    name = "Don't retain Unit Move on Short Walk",
    desc = "If the Unit to load has a short travel distance (min set below), don't copy unit's orders.",
    type = 'number',
    value = shortWalkDist,
    min = 0,
    max = 1500,
    step = 20,
    OnChange = function(self)
        shortWalkDist = self.value
    end,
}

options.noselneeded = {
    name = "Default to available transports",
    desc = 'Use any available transport if none selected',
    type = 'bool',
    value = noSelectNeeded,
    OnChange = function(self)
        noSelectNeeded = self.value
    end,
}


options.letautowait = {
    name = "Use 'Load AI'",
    desc = "If you have the widget Load AI, let it manage the waiting",
    type = 'bool',
    value = letAutoWait,
    OnChange = function(self)
        if self.value and widgetHandler:FindWidget('Load AI') then
            letAutoWait = true
        else
            letAutoWait = false
        end
    end,
}


local spGiveOrderToUnit             = Spring.GiveOrderToUnit
local spGetUnitPosition             = Spring.GetUnitPosition
local spGetFeaturePosition          = Spring.GetFeaturePosition
local spRequestPath                 = Spring.RequestPath
local spGetUnitIsTransporting       = Spring.GetUnitIsTransporting
local spGetUnitDefID                = Spring.GetUnitDefID
local spGiveOrderArrayToUnitArray   = Spring.GiveOrderArrayToUnitArray
local spGetCommandQueue             = Spring.GetCommandQueue
local spGetUnitRadius               = Spring.GetUnitRadius
local spGetSelectedUnitsSorted      = Spring.GetSelectedUnitsSorted
local spGetMyTeamID                 = Spring.GetMyTeamID
local spGetCommandQueue             = Spring.GetCommandQueue
local spGetUnitCurrentCommand       = Spring.GetUnitCurrentCommand
local spGetGroundHeight             = Spring.GetGroundHeight
local spGetUnitVelocity             = Spring.GetUnitVelocity
local spGetTeamUnitsByDefs          = Spring.GetTeamUnitsByDefs
local spGetUnitEffectiveBuildRange  = Spring.GetUnitEffectiveBuildRange

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- From transport AI

local EMPTY_TABLE = {}
local MAX_UNITS = Game.maxUnits
local areaTarget -- used to match area command targets
local myTeamId = spGetMyTeamID()

local goodCommand = {
	[CMD_MOVE] = true,
	[CMD_RAW_MOVE] = true,
	[CMD_RAW_BUILD] = true,
	[CMD_SET_WANTED_MAX_SPEED or 70] = true,
	[CMD.GUARD] = true,
	[CMD_RECLAIM] = true,
	[CMD_REPAIR] = true,
	[CMD_RESURRECT] = true,
	[CMD_JUMP] = true,
}

local function AdjustForBuildDistance(unitID, params, lastMove)
    local range = spGetUnitEffectiveBuildRange(unitID)
    -- Echo("lastMove is ", lastMove)
    if not lastMove then
        lastMove = {spGetUnitPosition(unitID)}
    end
    local dirx,dirz = params[1]-lastMove[1], params[3]-lastMove[3]
    local dist = (dirx^2 + dirz^2)^0.5
    if dist < range then
        Echo('dist too close')
        return false
    end
    dirx, dirz = dirx / dist, dirz / dist
    params[1] = params[1] + range * -dirx
    params[3] = params[3] + range * -dirz
    params[2] = spGetGroundHeight(params[1], params[3])
    return true
end

local function ProcessCommand(unitID, cmdID, params, lastMove)
	if not (goodCommand[cmdID] or cmdID < 0) then
		return false
	end
	local halting = not (cmdID == CMD_MOVE or cmdID == CMD_RAW_MOVE or  cmdID == CMD_SET_WANTED_MAX_SPEED)
	if cmdID == CMD_SET_WANTED_MAX_SPEED then
		return true, halting
	end
    if cmdID == CMD_RAW_BUILD or cmdID < 0 then
        if not AdjustForBuildDistance(unitID,params,lastMove) then
            return false
        end
    end
	local targetOverride

	if params[5] and not params[6] and (cmdID == CMD_RESURRECT or cmdID == CMD_RECLAIM or cmdID == CMD_REPAIR) then
		areaTarget = {
			x = params[2],
			z = params[4],
			objectID = params[1]
		}
	elseif areaTarget and params[4] and not params[5] then
		if params[1] == areaTarget.x and params[3] == areaTarget.z then
			targetOverride = areaTarget.objectID
		end
		areaTarget = nil
	elseif areaTarget then
		areaTarget = nil
	end
	if not targetOverride then
        if cmdID == CMD_RAW_BUILD and params[3] then
            return true, halting, params
        elseif params[3] and not params[5] then
			return true, halting, params
		elseif not params[1] then
			return true, halting
		end
	end
	
	local moveParams = {1, 2, 3}
	if cmdID == CMD_RESURRECT or cmdID == CMD_RECLAIM then
		moveParams[1], moveParams[2], moveParams[3] = spGetFeaturePosition((targetOverride or params[1] or 0) - MAX_UNITS)
	else
		moveParams[1], moveParams[2], moveParams[3] = spGetUnitPosition(targetOverride or params[1])
	end
	return true, halting, moveParams[1] and moveParams
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local spGetGroundBlocked = Spring.GetGroundBlocked
local spClosestBuildPos = Spring.ClosestBuildPos
local spTestBuildOrder = Spring.TestBuildOrder
local solarDefID = UnitDefNames['energysolar'].id
local stardustDefID = UnitDefNames['turretriot'].id
local starlightDefID = UnitDefNames['mahlazer'].id



local draw = {}
local drawfunc = function(t)
	for i, point in ipairs(t) do
		if t[i+1] then
			gl.Vertex(unpack(t[i]))
			gl.Vertex(unpack(t[i+1]))
		end
	end
end
local function IsTargetReachable (moveID, ox,oy,oz,tx,ty,tz,radius)
	local result,lastcoordinate, waypoints
	local path = spRequestPath( moveID,ox,oy,oz,tx,ty,tz, 0)
	if path then
		local waypoint = path:GetPathWayPoints() --get crude waypoint (low chance to hit a 10x10 box). NOTE; if waypoint don't hit the 'dot' is make reachable build queue look like really far away to the GetWorkFor() function.
		local finalCoord = waypoint[#waypoint]
		if finalCoord then --unknown why sometimes NIL
			draw = waypoint
			table.insert(draw,1,{ox,oy,oz})
			local dx, dy, dz = finalCoord[1]-tx, finalCoord[2]-ty, finalCoord[3]-tz
			local dist = math.sqrt(dx*dx + dy*dy, dz*dz)
			if dist <= radius+20 then --is within radius?
				result = "reach"
				lastcoordinate = finalCoord
				waypoints = waypoint
			else
				result = "outofreach"
				lastcoordinate = finalCoord
				waypoints = waypoint
			end
		end
	else
		result = "noreturn"
		lastcoordinate = nil
		waypoints = nil
	end
	return result, lastcoordinate, waypoints
end

function widget:DrawWorld()
	if draw[1] then
		gl.BeginEnd(GL.LINES, drawfunc, draw)
	end
end



-- local bigger = {}
-- local bySize = {}
-- for defID, def in pairs(UnitDefs) do
--     local size = def.xsize
--     bySize[size] = defID
-- end
-- for defID, def in pairs(UnitDefs) do
--     local biggerSize, biggerDefID
--     local size = def.xsize
--     for i=1, 6 do
--         biggerSize = size+i
--         if bySize[biggerSize] then
--             biggerDefID = bySize[biggerSize]
--         end
--     end
--     if biggerDefID then
--         -- Echo(UnitDefs[defID].name,'defID',defID,'size',size,' is set to ',UnitDefs[biggerDefID].name,'defID', defID,'with size',biggerSize)
--         bigger[defID] = biggerDefID
--     else
--         -- Echo(UnitDefs[defID].name,'size',size,' no bigger size ')
--         bigger[defID] = defID
--     end
-- end

-- function taiEmbark(unitID, teamID, embark, shift, internal)
--     Echo("taiEmbark is ", unitID, teamID, embark, shift, internal)
-- end
local function AdjustForBlockedGround(location, unitID)
	local x, y, z = location[1], location[2], location[3]
	
	-- local function CheckBlocked(layer, offx, offz)
	-- local blocking = Spring.TestBuildOrder(solarDefID, x, y, z, 1)
	local radius = spGetUnitRadius(unitID)
	-- Echo("spGetGroundBlocked(x - 100, z - 100, x + 100, z + 100)  is ", spGetGroundBlocked(x - radius, z - radius, x + radius, z + radius) )
	-- local testMove = Spring.TestMoveOrder()
    local gblock = spGetGroundBlocked(x - 100, z - 100, x + 100, z + 100)
    
    if gblock == 'feature' then

    end
    -- Echo("gblock is ", gblock)
	-- if gblock then
	-- 	x, y, z = spClosestBuildPos(0,solarDefID, x, 0, z, 200 ,0 ,0)
	-- 	if x then
	-- 		location[1], location[2], location[3] = x, y, z
	-- 		-- Echo('=>',x,y,z)
	-- 	end
	-- end
    -- if not gblock then
        local defID = spGetUnitDefID(unitID)
        x, y, z = spClosestBuildPos(0,defID, x, 0, z, 200 ,0 ,0)
        if x then
            location[1], location[2], location[3] = x, y, z
            -- Echo('=>',x,y,z)
        end
    -- end
	-- end
end


local function CopyMoveThenUnload(transID, unitID, isWaiting)
	local cmdQueue = spGetCommandQueue(unitID, -1)
	if not cmdQueue then
		return
	end
	local commandLocations, c = {}, 0
	local queueToRemove, r = {}, 0
	
	areaTarget = nil
    local lastMove
	for i = (isWaiting and 2 or 1), #cmdQueue do -- ignore the first waitcommand executed

		local cmd = cmdQueue[i]
		local keepGoing, haltAtCommand, moveParams = ProcessCommand(unitID, cmd.id, cmd.params, lastMove)
		if not keepGoing then
			break
		end
		
		if moveParams then
            c = c + 1
			commandLocations[c] = moveParams
            lastMove = moveParams
		end
		
		if haltAtCommand then
			break
		else
            r = r + 1
			queueToRemove[r] = cmd.tag
		end
	end
	
	if c == 0 then
		return
	end
    local ux,uy,uz = spGetUnitPosition(unitID)
    local dist = 0
    for i=1, c do
        local move = commandLocations[i]
        local mx, my, mz = unpack(move)
        local dist3D = ((mx-ux)^2 + (my-uy)^2 + (mz-uz)^2)^0.5
        dist = dist + dist3D
    end

    if dist < shortWalkDist then
        spGiveOrderToUnit(unitID, CMD_REMOVE, queueToRemove, 0)
        return
    end

	local commands = {}
	for i = 1, c - 1 do
		commands[i] = {CMD_RAW_MOVE, commandLocations[i], CMD_OPT_SHIFT}
	end
	AdjustForBlockedGround(commandLocations[c], unitID)
	-- commandLocations[#commandLocations][4] = 100
	commandLocations[c][4] = unitID
	commands[c] = {CMD_UNLOAD_UNIT, commandLocations[c], CMD_OPT_SHIFT}
	-- CMD_UNLOAD_UNIT works much better, fix unresponding unload command (the transport woudldn't try to find another spot or sometime just don't move execute order at all)
	
	spGiveOrderArrayToUnitArray({transID}, commands)
	spGiveOrderToUnit(unitID, CMD_REMOVE, queueToRemove, 0)
end

local function DoSelectionLoadOLD()
	-- Find the units which can transport and the units which are transports
	local selectedUnits = Spring.GetSelectedUnits()
	local lightTrans = {}
	local heavyTrans = {}
	local light = {}
	local heavy = {}
	
	for i = 1, #selectedUnits do
		local unitID = selectedUnits[i]
		local unitDefID = spGetUnitDefID(unitID)
		local ud = unitDefID and UnitDefs[unitDefID]
		if ud then
			if (ud.canFly or ud.cantBeTransported) then
				if ud.isTransport then
					local transportUnits = spGetUnitIsTransporting(unitID)
					if transportUnits and #transportUnits == 0 then
						if ud.customParams.islighttransport then
							lightTrans[#lightTrans + 1] = unitID
						else
							heavyTrans[#heavyTrans + 1] = unitID
						end
					end
				end
			elseif ud.customParams.requireheavytrans then
				heavy[#heavy + 1] = unitID
			else
				light[#light + 1] = unitID
			end
		end
	end
	
	-- Assign transports to units
	local lightEnd = math.min(#light, #lightTrans)
	for i = 1, lightEnd do
		spGiveOrderToUnit(lightTrans[i], CMD_LOAD_UNITS, {light[i]}, CMD_OPT_RIGHT)
		spGiveOrderToUnit(light[i], CMD_WAIT, EMPTY_TABLE, CMD_OPT_RIGHT)
		CopyMoveThenUnload(lightTrans[i], light[i])
	end
	
	local heavyEnd = math.min(#heavy, #heavyTrans)
	for i = 1, heavyEnd do
		spGiveOrderToUnit(heavyTrans[i], CMD_LOAD_UNITS, {heavy[i]}, CMD_OPT_RIGHT)
		spGiveOrderToUnit(heavy[i], CMD_WAIT, EMPTY_TABLE, CMD_OPT_RIGHT)
		CopyMoveThenUnload(heavyTrans[i], heavy[i])
	end
	
	--Spring.Echo("light", #light)
	--Spring.Echo("heavy", #heavy)
	--Spring.Echo("lightTrans", #lightTrans)
	--Spring.Echo("heavyTrans", #heavyTrans)
	if #light > #lightTrans then
		local offset = #heavy - #lightTrans
		heavyEnd = math.min(#light, #heavyTrans + #lightTrans - #heavy)
		--Spring.Echo("offset", offset)
		for i = #lightTrans + 1, heavyEnd do
			spGiveOrderToUnit(heavyTrans[offset + i], CMD_LOAD_UNITS, {light[i]}, CMD_OPT_RIGHT)
			spGiveOrderToUnit(light[i], CMD_WAIT, EMPTY_TABLE, CMD_OPT_RIGHT)
			CopyMoveThenUnload(heavyTrans[offset + i], light[i])
		end
	end
	Spring.SetActiveCommand(nil)
end

local function IsBusy(transID)
    return waitForLoad[transID] or spGetUnitCurrentCommand(transID) == CMD_LOAD_UNITS
end

local function DoSelectionLoad()
	-- Find the units which can transport and the units which are transports
	local lightTrans, lT = {}, 0
	local heavyTrans, hT = {}, 0
	local light, l = {}, 0
	local heavy, h = {}, 0
    -- local unitDefs = {}
    local selTypes = WG.selectionDefID or spGetSelectedUnitsSorted()
    ----------- Pick all team units if needed 

    local transSelected
    for defID in pairs(transDefID) do
        if selTypes[defID] then
            transSelected = true
            break
        end
    end
    if not transSelected and noSelectNeeded then
        local units = spGetTeamUnitsByDefs(myTeamID, indexedLightTrans)
        for i, unitID in ipairs(units) do
            if not IsBusy(unitID) then
                local transportUnits = spGetUnitIsTransporting(unitID)
                if transportUnits and not transportUnits[1] then
                    lT = lT + 1
                    lightTrans[lT] = unitID
                end
            end
        end
        units = spGetTeamUnitsByDefs(myTeamID, indexedHeavyTrans)
        for i, unitID in ipairs(units) do
            if not IsBusy(unitID) then
                local transportUnits = spGetUnitIsTransporting(unitID)
                if transportUnits and not transportUnits[1] then
                    hT = hT + 1
                    heavyTrans[hT] = unitID
                end
            end
        end
    end
    -----------------------

	for defID, units in pairs(selTypes) do
        if transDefID[defID] then
            local isLightT = lightTransDefID[defID]
            for i, unitID in ipairs(units) do
                if not IsBusy(unitID) then
    				local transportUnits = spGetUnitIsTransporting(unitID)
    				if transportUnits and not transportUnits[1] then
                        if isLightT then
    						lT = lT + 1
    						lightTrans[lT] = unitID
                        else
       						hT = hT + 1
       						heavyTrans[hT] = unitID
        				end
                    end
                end
            end
		elseif heavyDefID[defID] then
			for i, unitID in ipairs(units) do
                h = h + 1
			    heavy[h] = unitID
            end
		elseif not untransportableDefID[defID] then
            for i, unitID in ipairs(units) do
                l = l + 1
                light[l] = unitID
            end
		end
	end

    local new
	-- first we deal with the heavy units
	local poses = {}
	local extraHeavy = hT > h
	if h > 0 and hT > 0 then
		local res = UseHungarian(heavy, heavyTrans, poses) -- this version of Hungarian support asymetric tables (that will be completed with dummy distances)
		for i = 1, h do 
			local unitID = heavy[i]
			local j = res[i]
			local transID = heavyTrans[j]
			if transID then
				heavyTrans[j] = nil

				spGiveOrderToUnit(transID, CMD_LOAD_UNITS, {unitID}, CMD_OPT_RIGHT)
                if letAutoWait then
                    widgetHandler:UnitCommandNotify(transID, CMD_LOAD_UNITS, {unitID}, OPT_RIGHT_TABLE)
                else
				    spGiveOrderToUnit(unitID, CMD_WAIT, EMPTY_TABLE, CMD_OPT_RIGHT)
                end
				-- CopyMoveThenUnload(transID, unitID)
				waitForLoad[transID] = unitID -- fix to get the last commands given to the unit if the CMD_LOAD_UNITS has been triggered in a same span of time, the orders need some time to get replied by the server
                new = true
			end
		end
	end
	if l > 0 and (lT > 0 or extraHeavy) then
		-- then the light
		local needHeavy = l > lT
		local res = UseHungarian(light, lightTrans, poses) -- this version of Hungarian support asymetric tables (that will be completed with dummy distances)
		if lightTrans[1] then
			for i = 1, l do 
				local unitID = light[i]
				local j = res[i]
				local transID = lightTrans[j]
				if transID then
					light[i] = nil
					spGiveOrderToUnit(transID, CMD_LOAD_UNITS, {unitID}, CMD_OPT_RIGHT)
                    if letAutoWait then
                        widgetHandler:UnitCommandNotify(transID, CMD_LOAD_UNITS, {unitID}, OPT_RIGHT_TABLE)
                    else
                        spGiveOrderToUnit(unitID, CMD_WAIT, EMPTY_TABLE, CMD_OPT_RIGHT)
                    end
					waitForLoad[transID] = unitID
                    new = true
					-- CopyMoveThenUnload(transID, unitID)
				end
			end
		end
		if needHeavy and extraHeavy then
			local lightRem, lr = {}, 0
			for k, unitID in pairs(light) do
				lr = lr + 1
				lightRem[lr] = unitID
			end
			local heavyTransRem, hTr = {}, 0
			for k, transID in pairs(heavyTrans) do
				hTr = hTr + 1
				heavyTransRem[hTr] = transID
			end
			local res = UseHungarian(lightRem, heavyTransRem, poses) -- this version of Hungarian support asymetric tables (that will be completed with dummy distances)
			for i = 1, lr do 
				local unitID = lightRem[i]
				local j = res[i]
				local transID = heavyTransRem[j]
				if transID then
					spGiveOrderToUnit(transID, CMD_LOAD_UNITS, {unitID}, CMD_OPT_RIGHT)
                    if letAutoWait then
                        widgetHandler:UnitCommandNotify(transID, CMD_LOAD_UNITS, {unitID}, OPT_RIGHT_TABLE)
                    else
                        spGiveOrderToUnit(unitID, CMD_WAIT, EMPTY_TABLE, CMD_OPT_RIGHT)
                    end
					waitForLoad[transID] = unitID
                    new = true
				end
			end
		end
	end
	Spring.SetActiveCommand(nil)
    return new
end

-------------- Drop close ground feature

-----------------------

function widget:CommandNotify(cmdId, params, opts)
    -- Echo("unpack(params) is ", params and unpack(params))
	if cmdId == CMD_LOADUNITS_SELECTED then
		return DoSelectionLoad()
	end
end


local waitForWait = {}
local IsWaiting
do
    local CMD_OPT_ALT = CMD.OPT_ALT
    function IsWaiting(id)
        local cmd, opt = spGetUnitCurrentCommand(id)
        return cmd == CMD_WAIT and (opt % (2*CMD_OPT_ALT) < CMD_OPT_ALT)
    end
end

function widget:UnitCommand(unitID, defID, teamID, cmdID, params, opts)
    -- if unitID == 28777 then
	   -- Echo("UC ", unitID, 'cmd', cmdID,'#params', #params,':',unpack(params))
    --     for k,v in pairs(opts) do Echo(k,v) end
    -- end
    -- if os.clock() - (lasttime or 0) > 2 then
    --     Echo('---------')
    --     lasttime = os.clock()
    -- end
    if cmdID == 1 then cmdID = params[2] end

    -- Echo(UnitDefs[Spring.GetUnitDefID(unitID)].humanName,'cmd',cmdID,allCmds[cmdID],'wait for wait', waitForWait[unitID])
    if cmdID == CMD_WAIT and waitForWait[unitID] then
        local transID = waitForWait[unitID]
        CopyMoveThenUnload(transID, unitID)
        waitForWait[unitID] = nil
	elseif cmdID == CMD_LOAD_UNITS and waitForLoad[unitID] then
		local transporteeID = waitForLoad[unitID]
        local isWaiting = IsWaiting(transporteeID)
        if letAutoWait and not isWaiting then
            waitForWait[transporteeID] = unitID
        else
            -- Echo('copy',spGetCommandQueue(transporteeID, 0),'orders')
		    CopyMoveThenUnload(unitID, transporteeID, isWaiting)
        end
		waitForLoad[unitID] = nil
	end
end
local myPlayerID = Spring.GetMyPlayerID()
function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
    	myTeamID = spGetMyTeamID()
    end
end
function widget:Initialize()
    if Spring.GetSpectatingState() or Spring.IsReplay() then
        widgetHandler:RemoveWidget(widget)
        return
    end    
    widget:PlayerChanged(myPlayerID)
    -- widgetHandler:RegisterGlobal(widget, 'taiEmbark', taiEmbark)
end
function widget:Shutdown()
    -- widgetHandler:DeregisterGlobal(widget, 'taiEmbark')
end


