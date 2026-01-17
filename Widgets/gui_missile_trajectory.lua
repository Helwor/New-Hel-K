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
WG.moddedMissileImpact = {}
-- valid units for widget
local missileDefs = { -- FIXME values are arbitrary, I didnt find the real ones, but it's accurate enough
	[UnitDefNames["tacnuke"].id]            = { turnStart = 840,  turnRad = 310, cmd = CMD.ATTACK,      color = red,       },
	[UnitDefNames["napalmmissile"].id]      = { turnStart = 840,  turnRad = 310, cmd = CMD.ATTACK,      color = orange,    },
	[UnitDefNames["seismic"].id]            = { turnStart = 840,  turnRad = 310, cmd = CMD.ATTACK,      color = green,     },
	[UnitDefNames["empmissile"].id]         = { turnStart = 2260, turnRad = 775, cmd = CMD.ATTACK,      color = blue,      },
	[UnitDefNames["missileslow"].id]        = { turnStart = 1275, turnRad = 368, cmd = CMD.ATTACK,      color = purple,    },
	[UnitDefNames["subtacmissile"].id]      = { turnStart = 1455, turnRad = 415, cmd = CMD.ATTACK,      color = red,       piece = 'aimpoint' },
	[UnitDefNames["shipcarrier"].id]        = { turnStart = 720,  turnRad = 260, cmd = CMD.MANUALFIRE,  color = rose_grey, piece = 'Launcher' },
	[UnitDefNames["staticnuke"].id]         = { turnStart = 8000, turnRad = 450, cmd = CMD.ATTACK,      color = red,       },
}
missileDefs["staticmissilesilo"]  = {
	meta = {
		[UnitDefNames["tacnuke"].id]        = missileDefs[UnitDefNames["tacnuke"].id],
		[UnitDefNames["empmissile"].id]     = missileDefs[UnitDefNames["empmissile"].id],
		[UnitDefNames["missileslow"].id]    = missileDefs[UnitDefNames["missileslow"].id],
	},
	cmd = CMD.ATTACK,
	colorAlpha = 0.3,
}

local selectionChanged = false
local selectedRockets = {}
local allowedCmd = {}

-- Speed ups
local spGetActiveCommand       = Spring.GetActiveCommand
local spGetMouseState          = Spring.GetMouseState
local spTraceScreenRay         = Spring.TraceScreenRay
local spGetUnitPosition        = Spring.GetUnitPosition
local spGetGroundHeight        = Spring.GetGroundHeight
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted

local glBeginEnd     = gl.BeginEnd
local glLineStipple  = gl.LineStipple
local glColor        = gl.Color
local glVertex       = gl.Vertex
local glDepthTest    = gl.DepthTest

local GL_LINE_STRIP  = GL.LINE_STRIP

local cos = math.cos
local sin = math.sin
local diag = math.diag
local pi = math.pi

local function DrawStraightToGround(x, y, z, goalx, goaly, goalz)
	-- Vecteur vers la cible
	local dx, dy, dz = goalx - x, goaly - y, goalz - z
	local distance = diag(dx, dy, dz)
	if distance == 0 then return end
	
	dx, dy, dz = dx/distance, dy/distance, dz/distance
	local numChecks = math.min(50, math.floor(distance / 50))
	local step = distance / numChecks
	
	local stepx, stepy, stepz = step * dx, step * dy, step * dz

	for i = 1, numChecks do
		x, y, z = x + stepx, y + stepy, z + stepz
		if spGetGroundHeight(x, z) > y then
			glVertex(x, y, z)
			moddedImpact = {x, y, z}
			return
		end
	end
	glVertex(goalx, goaly, goalz)
end

local function DrawTrajectory(ux, uy, uz, turnStart, turnRad, dirx, diry, dirz, goalx, goaly, goalz)
	local dx, dz = goalx - ux, goalz - uz
	local len2D = diag(dx, dz)
	if len2D == 0 then
		return
	end
	-- draw base to start of turn
	glVertex(ux, uy, uz)
	glVertex(ux, uy + turnStart, uz)
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
					glVertex(unpack(verts[n]))
				end
				glVertex(x, y, z)
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
		glVertex(unpack(verts[i]))
	end
	DrawStraightToGround(lastx, lasty, lastz, goalx, goaly, goalz)
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
		allowedCmd = {}
		selectedRockets = spGetSelectedUnitsSorted()
		for defID, units in pairs(selectedRockets) do
			local def = missileDefs[defID]
			if not def then
				selectedRockets[defID] = nil
			else
				allowedCmd[def.cmd] = true
			end
		end
	end
end

function widget:DrawWorld()
	if not next(selectedRockets) then
		return
	end
	-- while attacking
	local _, activeCmd = spGetActiveCommand()
	if not allowedCmd[activeCmd] then
		return
	end

	local mx, my = spGetMouseState()
	local desc, targetPos = spTraceScreenRay(mx, my, true)
	if not targetPos then
		return
	end
	glLineStipple("")
	glDepthTest(GL.LEQUAL)
	glDepthTest(true)
	for defID, units in pairs(selectedRockets) do
		local def = missileDefs[defID]
		for _, unitID in ipairs(units) do
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
				local dx, dz = tx - ux, tz - uz
				local len2D = diag(dx, dz)
				if len2D > 0 then
					local dirx, dirz = dx / len2D, dz / len2D
					if def.meta then -- show multiple from silo
						local alpha = def.colorAlpha
						for defID, def in pairs(def.meta) do
							glColor(def.color[1], def.color[2], def.color[3], alpha)
							glBeginEnd(GL_LINE_STRIP, DrawTrajectory, ux, uy, uz, def.turnStart, def.turnRad, dirx, diry, dirz, targetPos[1], targetPos[2], targetPos[3])
						end
					else
						glColor(def.color)
						glBeginEnd(GL_LINE_STRIP, DrawTrajectory, ux, uy, uz, turnStart, def.turnRad, dirx, diry, dirz, targetPos[1], targetPos[2], targetPos[3])
					end
				end
			end
			WG.moddedMissileImpact[unitID] = moddedImpact
		end
	end
	glDepthTest(false)
	glLineStipple(false)
	glColor(1,1,1,1)
end

function widget:Initialize()
	if not next(missileDefs) then
		Echo('['..widget:GetInfo().name..']: ' .. ' Game doesn\'t have any rocket covered by the widget, shutting down.')
		widgetHandler:RemoveWidget(widget)
		return
	end
	selectionChanged = true
	widget:CommandsChanged()
end

if f then
	f.DebugWidget(widget)
end