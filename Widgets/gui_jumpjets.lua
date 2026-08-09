-- $Id: gui_jumpjets.lua 4207 2009-03-29 01:08:09Z quantum $
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Copyright (C) 2008.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "Jumpjet GUI",
		desc      = "Draws jump arc.",
		author    = "quantum",
		date      = "May 30, 2008",
		license   = "GNU GPL, v2 or later",
		layer     = 10000,
		enabled   = true,
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Automatically generated local definitions

local CMD_ATTACK               = CMD.ATTACK
local CMD_FIGHT                = CMD.FIGHT
local CMD_MOVE                 = CMD.MOVE
local CMD_SET_WANTED_MAX_SPEED = CMD.SET_WANTED_MAX_SPEED
local GL_LINE_STRIP            = GL.LINE_STRIP
local glBeginEnd               = gl.BeginEnd
local glColor                  = gl.Color
local glDrawGroundCircle       = gl.DrawGroundCircle
local glLineStipple            = gl.LineStipple
local glVertex                 = gl.Vertex
local spGetActiveCommand       = Spring.GetActiveCommand
local spGetCommandQueue        = Spring.GetCommandQueue
local spGetGameFrame           = Spring.GetGameFrame
local spGetModKeyState         = Spring.GetModKeyState
local spGetMouseState          = Spring.GetMouseState
local spGetSelectedUnits       = Spring.GetSelectedUnits
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetUnitDefID           = Spring.GetUnitDefID
local spGetUnitPosition        = Spring.GetUnitPosition
local spGetFeaturePosition     = Spring.GetFeaturePosition
local spTraceScreenRay         = Spring.TraceScreenRay
local spTestMoveOrder          = Spring.TestMoveOrder
local spTestBuildOrder         = Spring.TestBuildOrder
local spGetGroundHeight        = Spring.GetGroundHeight
local spGetGroundNormal        = Spring.GetGroundNormal
local spIsPosInLos             = Spring.IsPosInLos
local spGetUnitRulesParam	   = Spring.GetUnitRulesParam

local maxUnits = Game.maxUnits
local diag = math.diag
local pairs = pairs
local WG = WG
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
VFS.Include("LuaRules/Configs/customcmds.h.lua")


local myPlayerID = Spring.GetMyPlayerID()
local myTeamID = false
local startChosen = false
local startDefID = false
local preGameJumper = false

local glVertex = glVertex
local green      = {0.5,   1, 0.5,   1}
local greenred   = {  0.8, 0.5, 0.5,   1}
local yellow     = {  1,   1, 0.5,   1}
local orange     = { 0.9, 0.5,   0,   1}
local red        = {  1,   0,   0,   1}
local purple     = {  1,   0,   0.5,   1}


-- Types of passibility.
local V_PASS = 0
local V_STRUCTURE = 1
local V_FOG = 2
local V_SINK = 3

-- First in range, then out of range
local viabilityColours = {
	[V_PASS] = {green, greenred},
	[V_STRUCTURE] = {yellow, orange},
	[V_FOG] = {greenred, greenred},
	[V_SINK] = {purple, purple},
}
-- local faintedColors = {}
-- faintedColors[red] = {}
-- for i,col in ipairs(red) do
-- 	faintedColors[red][i] = math.max(col/2,0)
-- end
-- for i,plainColors in pairs(viabilityColours) do
-- 	for j,colTable in ipairs(plainColors) do
-- 		if not faintedColors[colTable] then
-- 			local fainted = {}
-- 			for k,col in ipairs(colTable) do
-- 				fainted[k] = math.max(col/2,0)
-- 			end
-- 			faintedColors[colTable] = fainted
-- 		end
-- 	end
-- end



local jumpDefs  = VFS.Include"LuaRules/Configs/jump_defs.lua"
for defID, def in pairs(jumpDefs) do
	local ud = UnitDefs[defID]
	def.maxWaterDepth = ud.maxWaterDepth
	def.midy = ud.model.midy
	def.id = defID
end
local function spTestMoveOrderX(unitDefID, x, y, z)
	return spTestMoveOrder(unitDefID, x, y, z, 0, 0, 0, true, true, true)
end

local function CheckTerrainBlock(bx, by, bz, finish, height)
	local vx, vy, vz = finish[1] - bx, finish[2] - by, finish[3] - bz
	local wallStep = 0.015
	
	-- check if there is no wall in between
	local x,z = bx, bz
	--Spring.Echo("Widget", x, by, z, "vec", vx, vy, vz, "step", wallStep)
	for i = 0, 1, wallStep do
		x = x + vx*wallStep
		z = z + vz*wallStep
		if ((spGetGroundHeight(x,z) - 30) > (by + vy*i + (1 - (2*i - 1)^2)*height)) then
			return i
		end
	end
	return false
end

local function GetJumpViabilityLevel(unitDefID, start, finish, height, maxWaterDepth)
	local bx, by, bz = start[1], start[2], start[3]
	local x, y, z = finish[1], finish[2], finish[3]

	if spTestMoveOrderX(unitDefID, x, y, z) then
		local blockStep = CheckTerrainBlock(bx, by, bz, finish, height)
		return V_PASS, blockStep
	else
		local normal = select(2, spGetGroundNormal(x, z))
		if normal < 0.6 then
			 -- Ground is too steep for bots to walk on.
			return false
		end
		
		local blockStep = CheckTerrainBlock(bx, by, bz, finish, height)
		if spGetGroundHeight(x, z) < -maxWaterDepth then
			-- Water too deep for the unit to walk on
			return V_SINK
		end
		
		-- Ground is fine, must contain a blocking structure or
		-- be out of LOS. Spring.TestMoveOrder returns false in
		-- widgets for all out of LOS locations.
		
		if spIsPosInLos(x, y, z) or WG.InitialQueue then
			return V_STRUCTURE, blockStep
		else
			return V_FOG, blockStep
		end
	end
end

local function ListToSet(t)
	local new = {}
	for i=1,#t do
		new[ t[i] ] = true
	end
	return new
end

local ignoreOrder = {
	[CMD_SET_WANTED_MAX_SPEED or 70] = true,
	[CMD.STOP] = true,
}

local accurate = ListToSet({CMD_MOVE, CMD_RAW_MOVE, CMD_JUMP, CMD_FIGHT})


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function GetDist3(a, b)
	return ((a[1] - b[1])^2 + (a[2] - b[2])^2 + (a[3] - b[3])^2)^0.5
end

local function GetDist2(a, b)
	return ((a[1] - b[1])^2 + (a[3] - b[3])^2)^0.5
end

local function DrawLoop(start, vector, color, progress, step, height, secondColorStep, secondColor)
	glColor(color[1], color[2], color[3], color[4])
	for i = progress, 1, step do
		if secondColorStep and secondColorStep < i then
			glColor(secondColor[1], secondColor[2], secondColor[3], secondColor[4])
			secondColorStep = false
		end
		local x = start[1] + vector[1]*i
		local y = start[2] + vector[2]*i + (1-(2*i-1)^2)*height
		local z = start[3] + vector[3]*i

		glVertex(x, y, z)
	end

	local x = start[1] + vector[1]
	local y = start[2] + vector[2]
	local z = start[3] + vector[3]

	glVertex(x, y, z)
end

local function DrawLineSeaLine(point, color)
	glVertex(point[1], point[2], point[3])
	glVertex(point[1], 0, point[3])
end
local function FaintColor(colTable,strength)
	local mult = 0.5 + 0.5*strength

	local newcolTable = {}
	for i=1,3 do
		local col = colTable[i]
		newcolTable[i] = col*mult
	end
	return newcolTable
end
local function GetArcColor(viability, inRange, jumpReload)
	local col
	if viability then
		col =  inRange and viabilityColours[viability][1] or viabilityColours[viability][2]
	else
		col = red
	end
	if jumpReload<1 then
		col = FaintColor(col, jumpReload)
	end
	return col
end

local function FindInsertPosInPreGame(X, Z, startPos)
	local pos
	local insertPos = 0
	local start = 1
	local pos = WG.preGameBuildQueue
	local diag = math.diag

	if startPos then
		pos[0] = {false, unpack(startPos)}
		start = 0
		-- Echo('unit #'.. (conRef or unitID) ..' pos ref:',unitPosX, unitPosZ)
	end
	local bestDist = math.huge
	-- getting insert point that add the least distance
	--  NOTE sqrt is mandatory 
	local new_next -- we don't need to recalculate 'this_new' as it is the previous 'new_next'
	for i = start, #pos do 
		-- Echo('iter',i, pos.n)
		local this, next = pos[i], pos[i+1]
		local thisX, thisZ = this[2], this[4]
		if not next or thisX ~= next[2] or thisZ ~= next[4] then -- to gain some cpu we don't consider order that have same poses than its next (happening mostly when terraforming)
			local this_new = new_next or diag(thisX - X, thisZ - Z)
			local this_next
			if next then
				local nextX, nextZ = next[2], next[4]
				this_next = diag(nextX - thisX, nextZ - thisZ)
				new_next = diag(X - nextX, Z - nextZ)
			else
				this_next, new_next = 0, 0
			end
			-- Echo(i,this[1],next and next[1] or 0,this[2])
			
			local newDist = this_new + new_next - this_next
			-- Echo('i', i,'=', this_new, new_next, this_next, 'dist', newDist)
			if newDist <= bestDist then 
				bestDist = newDist
				insertPos = i
			end
		end
	end
	pos[0] = nil
	return insertPos
end


local function GetOrderPos(cmdID, params)
	local len = #params
	local x, y, z
	if len == 3 then
		x, y, z = unpack(params)
	elseif len == 5 or len == 1 then
		local id = params[1]
		if id > maxUnits then
			x, y, z = spGetFeaturePosition(id - maxUnits)
		else
			x, y, z = spGetUnitPosition(id)
		end
	elseif len == 4 then
		local id = params[1]
		if id > maxUnits then
			x, y, z = spGetFeaturePosition(id - maxUnits)
		else
			x, y, z = spGetUnitPosition(id)
		end
		if not x then
			x, y, z = params[1], params[2], params[3]
		end
	end
	return x, y, z
end

local function FindInsertPosInUnitQueue(X, Z, unitID, queue)
	local pos
	local insertPos = 0
	local start = 0
	local diag = diag
	local pos = {
		[0] = {i = 0, spGetUnitPosition(unitID)}
	}
	for i, order in ipairs(queue) do
		if not ignoreOrder[order.id] then
			local x, y, z = GetOrderPos(order.id, order.params)
			if x then
				pos[#pos + 1] = {i = i, x, y, z}
				-- Echo('good', i, unpack(order.params))
			else
				-- Echo('noop', i, unpack(order.params))
			end
		end
	end


		-- Echo('unit #'.. (conRef or unitID) ..' pos ref:',unitPosX, unitPosZ)
	local bestDist = math.huge
	-- getting insert point that add the least distance
	local insertPos = 0
	local new_next -- we don't need to recalculate 'this_new' as it is the previous 'new_next'
	for i = start, #pos do 
		-- Echo('iter',i, pos.n)
		local this, next = pos[i], pos[i+1]
		local thisX, thisZ = this[1], this[3]
		if not next or thisX ~= next[1] or thisZ ~= next[3] then -- to gain some cpu we don't consider order that have same poses than its next (happening mostly when terraforming)
			local this_new = new_next or diag(thisX - X, thisZ - Z)
			local this_next
			if next then
				local nextX, nextZ = next[1], next[3]
				this_next = diag(nextX - thisX, nextZ - thisZ)
				new_next = diag(X - nextX, Z - nextZ)
			else
				this_next, new_next = 0, 0
			end
			-- Echo(i,this[1],next and next[1] or 0,this[2])
			
			local newDist = this_new + new_next - this_next
			-- Echo('i', i,'=', this_new, new_next, this_next, 'dist', newDist)
			if newDist <= bestDist then 
				bestDist = newDist
				insertPos = i
			end
		end
	end
	local p = pos[insertPos]
	return p, queue[p.i]
end


local function DrawArc(def, start, finish, dist, range, isEstimate, quality, jumpReload, drawRange)
	-- todo: display lists
	local height = def.height
	local viability, blockStep = GetJumpViabilityLevel(def.id, start, finish, height, def.maxWaterDepth)
	local color = GetArcColor(viability, dist < range, jumpReload)

	quality = quality or 1
	
	local vector = {}
	for i = 1, 3 do
		vector[i] = finish[i] - start[i]
	end

	if drawRange then
		local col = isEstimate and orange or yellow
		glColor(col[1], col[2], col[3], col[4])
		glDrawGroundCircle(start[1], start[2], start[3], range, 100*quality)
	end


	local progress = 0
	local step = 0.01/quality

	glLineStipple('')
	glBeginEnd(GL_LINE_STRIP, DrawLoop, start, vector, color, progress, step, height, blockStep, red)
	glLineStipple(false)
	
	if finish[2] < 0 then
		glLineStipple(1, 255)
		glBeginEnd(GL_LINE_STRIP, DrawLineSeaLine, finish, color)
		glLineStipple(false)
	end
end

local function DrawMouseArc(unitID, def, finish, shift, meta, quality)
	local range = def.range * (spGetUnitRulesParam(unitID, "jumpRangeMult") or 1)
	local queueCount = spGetCommandQueue(unitID, 0) or 0
	local queue, order
	if shift and queueCount > 0 then
		queue = spGetCommandQueue(unitID, -1)
		local i = queueCount
		while i > 0 and queue[i] and ignoreOrder[queue[i].id] do
			queue[i] = nil
			i = i - 1
		end
		order = queue[i]
	end
	if order then -- shifted
		-- Echo("order, #queue is ", order, #queue)
		local from
		if meta then
			from, order = FindInsertPosInUnitQueue(finish[1], finish[3], unitID, queue)
		else
			local x, y, z = GetOrderPos(order.id, order.params)
			if x then
				from = {x, y, z}
			end
		end
		if from then
			local isEstimate = order and not accurate[order.id]
			from[2] = from[2] + def.midy
			local dist  = diag(finish[1] - from[1], finish[3] - from[3])
			DrawArc(def, from, finish, dist, range, isEstimate, quality, 1, true)
		end
	else
		local jumpReload = spGetUnitRulesParam(unitID, "jumpReload") or 1
		local from = {select(4,spGetUnitPosition(unitID, true))}
		local dist = diag(finish[1] - from[1], finish[3] - from[3])
		DrawArc(def, from, finish, dist, range, false, quality, jumpReload, true)
	end
end

function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
		startChosen = false
		startDefID = false
	end
end

function widget:GameFrame()
	preGame = WG.InitialQueue
end

function widget:Initialize()
	widget:PlayerChanged(myPlayerID)
	for i, comm in pairs(WG.ModularCommAPI and WG.ModularCommAPI.GetPlayerCommProfiles(myPlayerID, true) or {}) do
		if not comm.notStarter then
			local defID = comm.baseUnitDefID
			if jumpDefs[defID] then
				preGameJumper = jumpDefs[defID]
			end
		end
	end
end
local currentNodeOrder
local function GetMultiPos(x, z, shift, meta)
	if meta and shift and not x then
		return false
	end
	local multiPos = false
	local cf2Nodes = WG.TrailHandler and WG.TrailHandler.trails.cf2
	if cf2Nodes and cf2Nodes.interpolated[2] and not cf2Nodes.interpolated[50] then
		local now = os.clock()
		if not currentNodeOrder
			or not currentNodeOrder.final and (
				cf2Nodes.fadeout
				or now > currentNodeOrder.time and cf2Nodes[currentNodeOrder.rawlength + 1]
			)
		then
			currentNodeOrder = {}
			cf2Nodes:MatchCF2UnitsToNodes(x, z, shift, meta)
			local ok = false
			for unitID, pos in pairs(cf2Nodes.order) do
				for i, p in ipairs(cf2Nodes.interpolated) do
					if p == pos then
						ok = true
						currentNodeOrder[unitID] = i
						break
					end
				end
			end
			currentNodeOrder.time = now + 0.3
			currentNodeOrder.rawlength = #cf2Nodes
			currentNodeOrder.final = cf2Nodes.fadeout
			if ok then
				multiPos = cf2Nodes.interpolated
			end
			-- DIFFERS VOLUNTARILY FROM THE MISSILE TRAJECTORY WIDGET:
			if currentNodeOrder.final then
				currentNodeOrder = false
				multiPos = false
			end			
		else
			multiPos = cf2Nodes.interpolated
		end
		
	else
		currentNodeOrder = false
	end

	return multiPos
end



function widget:DrawWorld()
	local _, activeCommand = spGetActiveCommand()
	if WG.InitialQueue then
		local preGameQueue = WG.preGameBuildQueue
		if preGameQueue  and preGameJumper then
			local def = preGameJumper
			local range = def.range
			local sx, sy, sz
			if not startChosen then
				sx, sy, sz = Spring.GetTeamStartPosition(myTeamID) -- Returns -100, -100, -100 when none chosen
				if sx > 0 then
					sy = spGetGroundHeight(sx, sz)
					startChosen = {sx, sy, sz}
				end
			else
				sx, sy, sz = unpack(startChosen)
			end
			local lastOrder
			-- Draw queued jumps in preGame
			for i, order in ipairs(preGameQueue) do
				if order[1] == CMD_JUMP then
					if i == 1 then
						if startChosen then
							local to = {order[2], order[3], order[4]}
							local dist = diag(to[1] - startChosen[1], to[3] - startChosen[3])
							local jumpReload = 0.65
							local quality = 1
							DrawArc(def, startChosen, to, dist, range, true, quality, jumpReload, false)

						end
					else
						local to = {order[2], order[3], order[4]}
						local from = {lastOrder[2], lastOrder[3], lastOrder[4]}
						local dist = diag(to[1] - from[1], to[3] - from[3])
						local jumpReload = 0.65
						local quality = 1
						DrawArc(def, from, to, dist, range, true, quality, jumpReload, false)
					end
				end
				lastOrder = order
				
			end
			-- Draw user jump in preGame
			if WG.preGamePseudoCommand == CMD_JUMP then
				local mouseX, mouseY   = spGetMouseState()
				local category, to    = spTraceScreenRay(mouseX, mouseY, true)
				if category == 'ground' then
					local from
					local _, _, meta, shift   = spGetModKeyState()
					if shift and lastOrder then
						if meta then
							local insertPos = FindInsertPosInPreGame(to[1], to[3], startChosen)
							local order = preGameQueue[insertPos]
							from = order and {order[2], order[3], order[4]} or startChosen
						else
							from = {lastOrder[2], lastOrder[3], lastOrder[4]}
						end
					else
						from = startChosen
					end
					if from then
						local dist = diag(to[1] - from[1], to[3] - from[3])
						local range = jumpDefs[preGameJumperDefID].range
						local jumpReload = 1
						local quality = 1
						DrawArc(def, from, to, dist, range, true, quality, jumpReload, true)
					end
				end
			end
		end
	elseif activeCommand == CMD_JUMP or select(2, Spring.GetDefaultCommand()) == CMD_JUMP then
		local to
		local _, _, meta, shift   = spGetModKeyState()
		local mouseX, mouseY   = spGetMouseState()
		if WG.ClampScreenPosToWorld then
			local _mx, _my
			local _mx, _my, pos = WG.ClampScreenPosToWorld(mouseX, mouseY, false, true)
			if pos then
				to = pos
			end
		end
		if not to then
			local category, pos    = spTraceScreenRay(mouseX, mouseY, true, false ,false, true)
			if category == 'ground' then
				to = pos
			end
		end

		local multiPos = GetMultiPos(to and to[1], to and to[3], meta, shift)
		if (multiPos or to) then
			for defID, units in pairs(WG.selectionDefID or spGetSelectedUnitsSorted()) do
				if jumpDefs[defID] then
					for _, unitID in ipairs(units) do
						local to = multiPos and currentNodeOrder[unitID] and multiPos[ currentNodeOrder[unitID] ] or to
						if to then
							DrawMouseArc(unitID, jumpDefs[defID], to, shift, meta, math.max(1-#units/50, 0.3))
						end
					end
				end
			end
		end
	end
end

f.DebugWidget(widget)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
