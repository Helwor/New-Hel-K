function widget:GetInfo()
	return {
		name      = "Missile Trajectory",
		desc      = "You've no excuse to miss now.",
		author    = "Helwor, from Stormev's idea",
		date      = "Jan 17 2026",
		license   = "GPL v2 or later",
		layer     = 0,
		enabled   = true,
		handler   = true,
	}
end
local red       = {1,0,0,1}
local green     = {0,1,0,1}
local blue      = {0,0,1,1}
local orange    = {1,1,0,1}
local purple    = {1,0,1,1}
local rose_grey = {0.65, 0.45, 0.45, 1}


local moddedImpact
WG.moddedMissileImpact = setmetatable({}, {__mode = 'v'})
-- valid units for widget
local missileDefs = { -- FIXME values are arbitrary, I didnt find the real ones, but it's accurate enough
	[UnitDefNames["tacnuke"].id]            = { turnStart = 840,  turnRad = 310, cmd = CMD.ATTACK,      color = red,       },
	[UnitDefNames["napalmmissile"].id]      = { turnStart = 840,  turnRad = 310, cmd = CMD.ATTACK,      color = orange,    },
	[UnitDefNames["seismic"].id]            = { turnStart = 840,  turnRad = 310, cmd = CMD.ATTACK,      color = green,     subwater = true},
	[UnitDefNames["empmissile"].id]         = { turnStart = 2260, turnRad = 775, cmd = CMD.ATTACK,      color = blue,      },
	[UnitDefNames["missileslow"].id]        = { turnStart = 1275, turnRad = 368, cmd = CMD.ATTACK,      color = purple,    },
	[UnitDefNames["subtacmissile"].id]      = { turnStart = 1455, turnRad = 415, cmd = CMD.ATTACK,      color = red,       piece = 'aimpoint' },
	[UnitDefNames["shipcarrier"].id]        = { turnStart = 720,  turnRad = 260, cmd = CMD.MANUALFIRE,  color = rose_grey, piece = 'Launcher' },
	[UnitDefNames["staticnuke"].id]         = { turnStart = 8000, turnRad = 450, cmd = CMD.ATTACK,      color = red,       },
}
missileDefs[UnitDefNames["staticmissilesilo"].id]  = {
	meta = {
		[UnitDefNames["tacnuke"].id]        = missileDefs[UnitDefNames["tacnuke"].id],
		[UnitDefNames["empmissile"].id]     = missileDefs[UnitDefNames["empmissile"].id],
		[UnitDefNames["missileslow"].id]    = missileDefs[UnitDefNames["missileslow"].id],
	},
	cmd = CMD.ATTACK,
	colorAlpha = 0.3,
}
local siloDefID = UnitDefNames["staticmissilesilo"].id
local statMissileDefs = {
	[UnitDefNames["tacnuke"].id] = true,
	[UnitDefNames["empmissile"].id] = true,
	[UnitDefNames["missileslow"].id] = true,
	[UnitDefNames["napalmmissile"].id] = true,
	[UnitDefNames["seismic"].id] = true,
}

local selectionChanged = false
local selectionDefID
local selection
local selectedRockets = {}
local multiSelected = false
local currentNodeOrder = false
local allowedCmd = {}
local targetPos = false
local lastPos = {}
-- Speed ups
local spGetActiveCommand       = Spring.GetActiveCommand
local spGetMouseState          = Spring.GetMouseState
local spTraceScreenRay         = Spring.TraceScreenRay
local spGetUnitPosition        = Spring.GetUnitPosition
local spGetGroundHeight        = Spring.GetGroundHeight
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetSelectedUnits = Spring.GetselectedUnits

local glBeginEnd     = gl.BeginEnd
local glLineStipple  = gl.LineStipple
local glColor        = gl.Color
local glVertex       = gl.Vertex
local glShape        = gl.Shape
local glDepthTest    = gl.DepthTest

local GL_LINE_STRIP  = GL.LINE_STRIP

local cos = math.cos
local sin = math.sin
local diag = math.diag
local pi = math.pi
local lines = {
	AddVertex = function(self, x, y, z)
		self.n = self.n + 1
		self[self.n] = {v = {x, y, z}}
	end,
	Clear = function(self)
		if self.n > 0 then
			for k in ipairs(self) do
				self[k] = nil
			end
			self.n = 0
		end
	end,
	ClearAll = function(self)
		for unitID, v in pairs(self) do
			if type(v) == 'table' then
				v:Clear()
			end
		end
	end,
	DestroyAll = function(self)
		for unitID, v in pairs(self) do
			if type(v) == 'table' then
				self[unitID] = nil
			end
		end
	end,

}
setmetatable(
	lines,
	{
		__index = function(self, unitID)
			local t = setmetatable(
				{n = 0, color = false},
				{__index = lines}
			)
			rawset(self, unitID, t)
			return t
		end,
		__move = 'v',
	}
)

local function DrawStraightToGround(line, x, y, z, goalx, goaly, goalz, alreadyFoundGround)
	local dx, dy, dz = goalx - x, goaly - y, goalz - z
	local distance = diag(dx, dy, dz)
	if distance == 0 then return end

	dx, dy, dz = dx/distance, dy/distance, dz/distance
	local div = alreadyFoundGround and 15 or 60
	local numChecks = math.min(div, math.floor(distance / div))
	local step = distance / numChecks
	local stepx, stepy, stepz = step * dx, step * dy, step * dz
	local lastx, lasty, lastz = x, y, z
	for i = 1, numChecks do
		if i == numChecks then
			-- fix precision of the last point, to avoid sometime the calculated point not getting into ground while the goal point is actually is
			-- not doing that can result in crash, as the loop is supposed to find ground at the end during the last recursion when ground has been found
			x, y, z = goalx, goaly, goalz
		else
			x, y, z = x + stepx, y + stepy, z + stepz
		end
		if spGetGroundHeight(x, z) > y-10 then -- arbitrary -10 to consider width of the missile (hax)
			if alreadyFoundGround then
				return x, y, z -- give the final more precise position where the trajectory enter ground
			else
				-- Echo('find ground at ' .. i .. '/' .. numChecks, 'distance from goal', (numChecks - i) * step)
				x, y, z = DrawStraightToGround(line, lastx, lasty, lastz, x, y, z, true)
			end
			line:AddVertex(x, y, z)
			moddedImpact = {x, y, z}
			return
		end
		if distance > 10000 and not alreadyFoundGround and i > 1 and (numChecks - i) * step < 6000 then
			-- refine smaller steps for the last ~6000 elmos (especially useful for long distance nuke)
			return DrawStraightToGround(line, x, y, z, goalx, goaly, goalz)
		end
		lastx, lasty, lastz = x, y, z
	end
	line:AddVertex(goalx, goaly, goalz)
end

local function CreateTrajectory(line, ux, uy, uz, turnStart, turnRad, dirx, diry, dirz, goalx, goaly, goalz)
	local dx, dz = goalx - ux, goalz - uz
	local len2D = diag(dx, dz)
	if len2D == 0 then
		return
	end
	-- draw base to start of turn
	line:AddVertex(ux, uy, uz)
	line:AddVertex(ux, uy + turnStart, uz)
	-- get the center of the circling turn
	local cx, cy, cz = ux + dirx * turnRad, uy + turnStart, uz + dirz * turnRad
	-- draw circle until direction to target is found

	local v1x = -dirx
	local v1z = -dirz
	local bestScore = -math.huge
	local verts = {}
	local bestI = 0
	local div = 40
	for i = 0, div do
		local angle = 2 * pi * i / div
		local cosA = cos(angle)
		local sinA = sin(angle)
		
		local x = cx + turnRad * (cosA * v1x)
		local y = cy + turnRad * (sinA)
		local z = cz + turnRad * (cosA * v1z)
		if spGetGroundHeight(x, z) > y then
			if bestScore < 0.98 then
				for n = 1, #verts do
					line:AddVertex(unpack(verts[n]))
				end
				line:AddVertex(x, y, z)
				moddedImpact = {x, y, z}
				return
			else
				break
			end
		end
		-- normalized tangeant
		local tandirx = -sinA * v1x
		local tandiry = cosA
		local tandirz = -sinA * v1z
		
		-- to target
		local tx = goalx - x
		local ty = goaly - y
		local tz = goalz - z
		local tlen = diag(tx, ty, tz)
		
		if tlen > 0 then
			tx, ty, tz = tx/tlen, ty/tlen, tz/tlen
			local score = (tandirx*tx + tandiry*ty + tandirz*tz)
			if score > bestScore then
				bestScore = score
				lastx, lasty, lastz = x, y, z
				bestI = i
			end
			verts[#verts+1] = {x, y, z}
		end
	end
	for i = 1, bestI do
		line:AddVertex(unpack(verts[i]))
	end
	DrawStraightToGround(line, lastx, lasty, lastz, goalx, goaly, goalz)
end

local GetUnitPieceAbsolutePosition
do
	local currentUID
	local spGetUnitPieceMap      = Spring.GetUnitPieceMap
	local spGetUnitPiecePosition = Spring.GetUnitPiecePosition
	local spGetUnitVectors       = Spring.GetUnitVectors
	local pieceNumMT = {__index = function(self, pieceName)
		local pieceNum = spGetUnitPieceMap(currentUID)[pieceName]
		rawset(self, pieceName, pieceNum)
		return pieceNum
	end}
	local pieceNumCache = setmetatable({}, {__index = function(self, defID)
			local t = setmetatable({}, pieceNumMT);
			rawset(self, defID, t)
			return t end
		}
	)
	function GetUnitPieceAbsolutePosition(unitID, defID, ux, uy, uz, pieceName)
		currentUID = unitID
		local px, py, pz = spGetUnitPiecePosition(unitID, pieceNumCache[defID][pieceName])
		local front, top, right = spGetUnitVectors(unitID)
		return  ux + front[1]*pz + top[1]*py + right[1]*px,
				uy + front[2]*pz + top[2]*py + right[2]*px,
				uz + front[3]*pz + top[3]*py + right[3]*px
	end
end

function widget:SelectionChanged()
	selectionChanged = true
end

function widget:CommandsChanged()
	if selectionChanged then
		selectionChanged = false
		local selDefID = selectionDefID or spGetSelectedUnitsSorted()
		allowedCmd = {}
		selectedRockets = {}
		local count = 0
		local ignoreSilo = false
		if selDefID[siloDefID] then
			for defID in pairs(statMissileDefs) do
				if selDefID[defID] then
					ignoreSilo = true
					break
				end
			end
		end
		for defID, units in pairs(selDefID) do
			local def = missileDefs[defID]
			if def then
				if defID ~= siloDefID or not ignoreSilo then
					allowedCmd[def.cmd] = true
					selectedRockets[defID] = units
					count = count + #units
				end
			end
		end
		multiSelected = count > 1
		currentNodeOrder = false
		lines:DestroyAll()
		lastPos = {}
		draw = false
	end
end

function widget:Update()
	multiPos = false
	targetPos = false
	if not next(selectedRockets) then
		draw = false
		return
	end

	local _, activeCmd = spGetActiveCommand()
	if not allowedCmd[activeCmd] then
		draw = false
		return
	end
	
	local cf2Nodes = WG.TrailHandler and WG.TrailHandler.trails.cf2
	if cf2Nodes and multiSelected and cf2Nodes.interpolated[2] and not cf2Nodes.interpolated[50] then
		local now = os.clock()
		if not currentNodeOrder
			or not currentNodeOrder.final and (
				cf2Nodes.fadeout
				or now > currentNodeOrder.time and cf2Nodes[currentNodeOrder.rawlength + 1]
			)
		then
			currentNodeOrder = {}
			local order = cf2Nodes:MatchUnitsToNodes(selection or spGetSelectedUnits())
			local ok = false
			for unitID, pos in pairs(order) do
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
		else
			multiPos = cf2Nodes.interpolated
		end
		
	else
		currentNodeOrder = false
	end

	local _
	if not multiPos then
		local mx, my = spGetMouseState()
		local _
		_, targetPos = spTraceScreenRay(mx, my, true, true, false, true)
		if not targetPos then
			draw = false
			return
		end
		if lastPos[1] == targetPos[1] and lastPos[2] == targetPos[2]  and lastPos[3] == targetPos[3] then
			return
		end
		lastPos = targetPos
	end
	lines:ClearAll()
	for defID, units in pairs(selectedRockets) do
		local def = missileDefs[defID]
		for _, unitID in ipairs(units) do

			local targetPos = multiPos and currentNodeOrder[unitID] and multiPos[ currentNodeOrder[unitID] ] or targetPos
			moddedImpact = nil
			local ux, uy, uz = spGetUnitPosition(unitID)
			if ux then
				local turnStart = def.turnStart
				if def.piece then
					local by = uy
					ux, uy, uz = GetUnitPieceAbsolutePosition(unitID, defID, ux, uy, uz, def.piece)
					turnStart = turnStart - (uy - by)
				end
				local tx, ty, tz = targetPos[1], targetPos[2], targetPos[3]
				if def.subwater then
					if multiPos then -- work around as customFormation give position at max 0
						ty = spGetGroundHeight(tx, tz)
					end
				else
					ty = math.max(ty, 0)
				end
				local dx, dz = tx - ux, tz - uz
				-- dx, dz = math.max(dx, 1), math.max(dz, 1)
				local len2D = diag(dx, dz)
				local dirx, dirz = dx / len2D, dz / len2D

				if len2D > 0 then
					draw = true
					if def.meta then -- show multiple from silo
						local alpha = def.colorAlpha
						for defID, def in pairs(def.meta) do
							local line = lines[unitID..'-'..defID]
							if not line.color then
								line.color = {def.color[1], def.color[2], def.color[3], alpha}
							end
							CreateTrajectory(line, ux, uy, uz, def.turnStart, def.turnRad, dirx, diry, dirz, tx, ty, tz)
						end
					else
						local line = lines[unitID]
						if not line.color then
							line.color = def.color
						end
						CreateTrajectory(line, ux, uy, uz, turnStart, def.turnRad, dirx, diry, dirz, tx, ty, tz)
					end
				end
			end
			WG.moddedMissileImpact[unitID] = moddedImpact
		end
	end
end


function widget:DrawWorld()
	if not draw then
		return
	end

	-- targetPos[2] = math.max(targetPos[2], 0)
	glLineStipple("")
	glDepthTest(GL.LEQUAL)
	glDepthTest(true)
	for unitID, line in pairs(lines) do
		if type(line) == 'table' then
			if line[2] then
				glColor(line.color)
				glShape(GL_LINE_STRIP, line)
			end
		end
	end
	glDepthTest(false)
	glLineStipple(false)
	glColor(1,1,1,1)
end

function WidgetInitNotify(w, name)
	if name == "API Selection Handler" then
		selectionDefID = WG.selectionDefID
		selection = WG.selection
	end
end

function WidgetRemoveNotify(w, name)
	if name == "API Selection Handler" then
		selectionDefID = nil
		selection = nil
	end
end

function widget:Initialize()
	if not next(missileDefs) then
		Echo('['..widget:GetInfo().name..']: ' .. ' Game doesn\'t have any rocket covered by the widget, shutting down.')
		widgetHandler:RemoveWidget(widget)
		return
	end
	selectionChanged = true
	selectionDefID = WG.selectionDefID
	selection = WG.selection
	widget:CommandsChanged()
end

if f then
	f.DebugWidget(widget)
end