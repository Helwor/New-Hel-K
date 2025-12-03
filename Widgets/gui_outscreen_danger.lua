function widget:GetInfo()
  return {
	name      = "Outscreen Danger",
	desc      = "Warn when an enemy enter LoS while you're looking away",
	author    = "Helwor",
	date      = "Dec 2024",
	license   = "GNU LGPL, v2 or later",
	layer     = 0,
	enabled   = true,  --  loaded by default?
	handler   = true,
  }
end


----------------------------------------------------------------
--config
----------------------------------------------------------------
local arrowSize = 40
local maxAlpha = 0.9
local blinkPeriod = -1 --blinking time, negative to disable blinking
local ttl = 30
local forgetTime = 6 -- amount of time we're forgetting a unit after he vanished (either by going out of los or completely)
local highlightSize = 32
local highlightLineMin = 24
local highlightLineMax = 40
local arrowWidth = arrowSize / 1.2
local cropCircle = arrowWidth / 2
local texSize = arrowSize
local lineWidth = 1
local fontSize = 16
local maxLabelLength = 16

local minimapHighlightSize = 8
local minimapHighlightLineMin = 6
local minimapHighlightLineMax = 10

local useFade = true
----------------------------------------------------------------
--speedups
----------------------------------------------------------------
-- local spGetPlayerInfo       = Spring.spGetPlayerInfo
local spGetTeamColor        = Spring.GetTeamColor
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetSpectatingState  = Spring.GetSpectatingState
local spWorldToScreenCoords = Spring.WorldToScreenCoords
local spGetUnitDefID        = Spring.GetUnitDefID
local spIsUnitInView        = Spring.IsUnitInView
local spIsUnitInLos         = Spring.IsUnitInLos

local glTranslate           = gl.Translate
local glRotate              = gl.Rotate
local glColor               = gl.Color
local glRect                = gl.Rect
local glLineWidth           = gl.LineWidth
local glShape               = gl.Shape
local glPolygonMode         = gl.PolygonMode
local glText                = gl.Text
local glCallList            = gl.CallList
local glPushMatrix          = gl.PushMatrix
local glPopMatrix           = gl.PopMatrix
local glScale               = gl.Scale

local max                   = math.max
local abs                   = math.abs
local pi                    = math.pi
local atan2                 = math.atan2
local strSub                = string.sub
 
local GL_LINES              = GL.LINES
local GL_TRIANGLES          = GL.TRIANGLES
local GL_LINE               = GL.LINE
local GL_FRONT_AND_BACK     = GL.FRONT_AND_BACK
local GL_FILL               = GL.FILL

local lists = {}
local forget = {}
----------------------------------------------------------------
--vars
----------------------------------------------------------------
--table; i = {r, g, b, a, px, pz, label, expiration}
local enemies = {}
local count = 0
local MAX = 50
local myPlayerID
local myTeamID
local myAllyTeamID 
local teamColors = {}
local timeNow, timePart
local on = false
local mapX = Game.mapX * 512
local mapY = Game.mapY * 512
local vsx, vsy, sMidX, sMidY
local allyTeamByTeam = {}

for i,teamID in pairs(Spring.GetTeamList()) do
	allyTeamByTeam[teamID] = Spring.GetTeamAllyTeamID(teamID)
end

local isSpec, isFullRead = false

local canAttack = {}
for defID, def in pairs(UnitDefs) do
	if def.canAttack then
		canAttack[defID] = true
	end
end

local yellow = {1,1,0,1}
local red = {1,0,0,1}

-- local arrow = { -- arrow toward the right
-- 	{     0       ,       0      },
-- 	{-arrowSize   ,  arrowWidth/2},
-- 	{-arrowSize/2 ,       0      },

-- 	{     0       ,       0      },
-- 	{-arrowSize   , -arrowWidth/2},
-- 	{-arrowSize/2 ,       0      },
-- }
local arrow = { -- arrow toward the top -- makes the rotation calc a bit simpler
	-- leftwing
	{     0       ,       0       },
	{     0       ,  -arrowSize/2 },
	{-arrowWidth/2,  -arrowSize   },
	--rightwing
	{     0       ,       0       },
	{ arrowWidth/2,  -arrowSize   },
	{     0       ,  -arrowSize/2 },
 }
local arrowNew = { -- arrow toward the top -- makes the rotation calc a bit simpler
	-- leftwing
	{     0       ,       0       },
	{     0       ,  -arrowSize/2 },
	{-arrowWidth/2,  -arrowSize   },
	--rightwing
	{     0       ,       0       },
	{ arrowWidth/2,  -arrowSize   },
	{     0       ,  -arrowSize/2 },
	-- center
	{     0       ,       0       },
	{ arrowWidth/4, -arrowSize*3/4},
	{-arrowWidth/4, -arrowSize*3/4},

}
----------------------------------------------------------------
--local functions
----------------------------------------------------------------
local function DrawArrow(array)
	local vertices = {}
	for i, t in pairs(array) do
		local x, y, z = t[1], t[2], 0
		vertices[i] = {v = {x, y, z}}
	end
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
	glShape(GL.TRIANGLES, vertices)

end
local function DrawScreenDisc(x, y, r)
	gl.PushMatrix()
	gl.Translate(x, y, 0)
	gl.Scale(r, r, y)
	gl.BeginEnd(GL.TRIANGLE_FAN, function() 
		local divs = 24
		for i = 0, divs - 1 do
			local r = 2.0 * math.pi * (i / divs)
			local cosv = math.cos(r)
			local sinv = math.sin(r)
			-- gl.TexCoord(cosv, sinv)
			gl.Vertex(cosv, sinv, 0)
		end
	end)
	gl.PopMatrix()
end

local function CreateArrow(array)
	-- ban a disc area

	-- gl.DepthMask(false)
	-- gl.ColorMask(false, false, false, false)
	gl.StencilTest(true)
	gl.DepthTest(GL.NEVER)
	gl.StencilOp(GL.KEEP, GL.INCR, GL.KEEP)
	gl.StencilMask(1)
	gl.StencilFunc(GL.ALWAYS, 0, 1)
	gl.PushMatrix()
		gl.Translate(0, -arrowSize, 0)
		gl.Scale(0.95, 1.3, 1)
		DrawScreenDisc(0, 0, arrowWidth*3.05/7)
	gl.PopMatrix()
	gl.DepthTest(false)
	-- gl.ColorMask(true, true, true, true)
	gl.StencilOp(GL.KEEP, GL.INCR, GL.INCR)
	gl.StencilMask(1)
	gl.StencilFunc(GL.EQUAL, 0, 1)

	-- draw arrow
	DrawArrow(array)

	gl.StencilTest(false)

	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
end
local function TextureCircleCrop(tex, w, h, r)
	gl.DepthMask(false)
	gl.StencilTest(true)
	gl.DepthTest(GL.NEVER)
	gl.ColorMask(false, false, false, false)
	gl.StencilOp(GL.KEEP, GL.INCR, GL.KEEP)
	gl.StencilMask(1)
	gl.StencilFunc(GL.ALWAYS, 0, 1)

	DrawScreenDisc(0, 0, r)

	gl.DepthTest(false)
	gl.ColorMask(true, true, true, true)
	gl.StencilOp(GL.KEEP, GL.INCR, GL.INCR)
	gl.StencilMask(1)
	gl.StencilFunc(GL.NOTEQUAL, 0, 1)


	gl.Scale(1,-1,1)
	gl.Texture(tex)
	gl.TexRect(w/2, h/2, -w/2, -h/2)
	gl.Texture(false)
	gl.Scale(1,-1,1)

	gl.StencilTest(false)

	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
end	
setmetatable(
	lists,
	{	__index = function(self, defID)
			local list = gl.CreateList(TextureCircleCrop, '#'..defID, texSize, texSize, cropCircle)
			rawset(self, defID, list)
			return list
		end
	}
)
-- local function GetPlayerColor(playerID)
-- 	local _, _, isSpec, teamID = spGetPlayerInfo(playerID, false)
-- 	if (isSpec) then return spGetTeamColor(Spring.GetGaiaTeamID()) end
-- 	if (not teamID) then return nil end
-- 	return spGetTeamColor(teamID)
-- end

local function StartTime()
	local viewSizeX, viewSizeY = widgetHandler:GetViewSizes()
	widget:ViewResize(viewSizeX, viewSizeY)
	timeNow = 0
	timePart = 0
	on = true
end

local function SetUseFade(bool)
	useFade = bool
end

local function GetTeamColors(playerID, oldTeamID, newTeamID)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local color = {spGetTeamColor(teamID)}
		teamColors[teamID] = {strong = color, faded = {color[1]/2, color[2]/2, color[3]/2, color[4]}}
	end
end

local function GetRotation(sx, sy)
	local rx, ry = (sx - sMidX), (sy - sMidY)
	local d = (rx^2 + ry^2) ^0.5
	local dx, dy = rx / d, ry / d
	local byPI = atan2(dx, dy)
	if byPI < 0 then
		byPI = -byPI
	else
		byPI = pi + (pi - byPI)
	end
	return (byPI / (pi*2) * 360), dx, dy, d
end

local function Pulse(time, speed, reduce)
	time = (time or os.clock()) * speed
	local pulse = time % reduce -- one way too brutal 
	local pulse = time % reduce * 2 - time % (reduce*2) -- two way smooth
	-- when pulse is negative the arrow grow back up, we harden the growing back to original size
	if pulse < 0 then
		-- reapply its ratio to come closer to zero
		pulse = pulse * -(pulse / reduce )
	end
	glRotate(pulse, 0, 0, 0) 
end

----------------------------------------------------------------
--callins
----------------------------------------------------------------

function widget:UnitEnteredLos(id, teamID, forAllyTeam, defID)
	if allyTeamByTeam[teamID] ~= myAllyTeamID then
		if enemies[id] then
			enemies[id].gone = false
			return
		end
		if count >= MAX then
			return
		end
		if spIsUnitInView(id) then
			return
		end
		defID = defID or spGetUnitDefID(id)
		local x, y, z = spGetUnitPosition(id)
		local color, pulse, reduce
		if defID and canAttack[defID] then
			color = teamColors[teamID].strong
			pulse = true
			reduce = false
		else
			color = teamColors[teamID].faded
			pulse = false
			reduce = 40
		end
		if (not timeNow) then
			StartTime()
		end
		count = count + 1
		enemies[id] = {x, y, z, color, sometext, timeNow, defID, pulse, reduce}
	end
end

function widget:UnitLeftLos(id)
	if enemies[id] then
		enemies[id].gone = true
	end
end


function widget:Update(dt)
	if (not timeNow) then
		StartTime()
	else
		if useFade then
			timeNow = timeNow + dt
		end
		timePart = timePart + dt
		if (timePart > blinkPeriod and blinkPeriod > 0) then
			timePart = timePart - blinkPeriod
			on = not on
		end
	end
end


function widget:UnitDestroyed(id, teamID)
	if teamID == myTeamID then
		return
	end
	local obj = enemies[id]
	if obj and not obj.fadeAway then
		obj.fadeAway = timeNow
	end
end
lists.oldArrow = gl.CreateList(DrawArrow, arrow)

function widget:DrawScreen()
	-- Echo('in outscreen danger', f2())

	if (not on) then
		return
	end
	glLineWidth(lineWidth)

	for id, obj in pairs(enemies) do
		local x, y, z, color, text, time, defID, pulse, reduce = obj[1], obj[2], obj[3], obj[4], obj[5], obj[6], obj[7], obj[8], obj[9]
		local live = timeNow - time
		if live > ttl then
			if live > ttl + forgetTime then
				count = count - 1
				enemies[id] = nil
			end
			return
		end
		local alpha = maxAlpha * 1 - (live / ttl)
		if obj.fadeAway then
			alpha = alpha - 0.75 * (timeNow - obj.fadeAway)
			-- Echo('fading away', alpha)
			pulse = false
		end

		local _x, _y, _z = spGetUnitPosition(id)
		if _x then
			x, y, z = _x, _y, _z
			obj[1], obj[2], obj[3] = x, y, z
		else
			obj.gone = true
			alpha = alpha *0.66
		end
			-- Echo("alpha is ", alpha)
		if (alpha <= 0.1) then
			return
		else
			local sx, sy, sz = spWorldToScreenCoords(x, y, z)

			
			glPushMatrix()
			glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
			local onScreen
			if (sx >= 0 and sy >= 0	and sx <= vsx and sy <= vsy) then
				glTranslate(sx, sy, 0)
				-- on screen
				pulse = false
				if not obj.fadeAway then
					obj.fadeAway = timeNow
				end
			else
				--out of screen
				--flip if behind screen
				if (sz > 1) then
					sx = sMidX - sx
					sy = sMidY - sy
				end
				local xRatio = sMidX / abs(sx - sMidX)
				local yRatio = sMidY / abs(sy - sMidY)
				local edgeDist, textX, textY, textOptions

				if (xRatio < yRatio) then
					edgeDist = (sy - sMidY) * xRatio + sMidY
					if (sx > 0) then
						-- RIGHT
						glTranslate(vsx, edgeDist, 0)
						-- glRotate(270, 0, 0, 270)
						textX = vsx - arrowSize
						textY = edgeDist - fontSize * 0.5
						textOptions = "rn"
					else
						-- LEFT
						glTranslate(0, edgeDist, 0)
						-- glRotate(90, 0, 0, 90)
						textX = arrowSize
						textY = edgeDist - fontSize * 0.5
						textOptions = "n"
					end
				else
					edgeDist = (sx - sMidX) * yRatio + sMidX
					if (sy > 0) then
						glTranslate(edgeDist, vsy, 0)
						-- TOP
						textX = edgeDist
						textY = vsy - arrowSize - fontSize
					else
						-- BOTTOM
						glTranslate(edgeDist, 0, 0)
						-- glRotate(180, 0, 0, 180)
						textX = edgeDist
						textY = arrowSize
					end
					textOptions = "cn"
				end

					
			end
			local rot, dx, dy, d = GetRotation(sx, sy)

			local startedSince = timeNow - time
			if startedSince < 1 then -- bump at first second
				local scale = 1 + 0.5 *(1-startedSince)
				glScale(scale, scale, 0 )
			end
			if reduce then -- reduce for secondary unit
				glRotate(reduce, 0, 0, 0)
			end
			if pulse then
				Pulse(timeNow, 70 * alpha, 50 * alpha) -- time speed, reduce
			end
			

			if defID then
				glColor(1, 1, 1, alpha+(alpha/3))
				glPushMatrix()
				glTranslate(-dx * arrowSize*1.2, -dy * arrowSize*1.2, 0)
				glCallList(lists[defID])
				glPopMatrix()
			end

			glColor(color[1], color[2], color[3], alpha)

			glRotate(rot, 0, 0, rot)

			glCallList(lists.arrowDraw)
			glPopMatrix()
			-- debug line from mid to arrow
			-- gl.BeginEnd(GL.LINES, function() gl.Vertex(sx, sy, 0) gl.Vertex(sMidX, sMidY, 0) end)
			glColor(1, 1, 1, alpha)
			if text then
				glText(text, textX, textY, fontSize, textOptions)
			end
		end
	end
	
	glColor(1, 1, 1)
	glLineWidth(1)
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
end

function widget:ViewResize(viewSizeX, viewSizeY)
	vsx = viewSizeX
	vsy = viewSizeY
	sMidX = viewSizeX * 0.5
	sMidY = viewSizeY * 0.5
end


function widget:PlayerChanged(playerID)
	-- Echo('player', playerID, 'Changed', Spring.GetMyPlayerID())
	if playerID == myPlayerID then
		local oldTeamID = myTeamID
		myTeamID = Spring.GetMyTeamID()
		local wasSpec, wasFullRead = isSpec, isFullRead
		isSpec, isFullRead = spGetSpectatingState()
		if oldTeamID ~= myTeamID then
			if not isSpec or not teamColors[1] then
				GetTeamColors()
			end
			for id in pairs(enemies) do
				enemies[id] = nil
			end
			count = 0

		end
		myAllyTeamID = Spring.GetMyAllyTeamID()
		-- Echo("wasSpec, isSpec is ", wasSpec, isSpec, 'widget is sleeping', widget.isSleeping)

		if not wasFullRead and isFullRead then
			widgetHandler:Sleep(widget)
		elseif wasFullRead and not isFullRead then
			widgetHandler:Wake(widget)
		end
	end
end


function widget:Initialize()
	timeNow = false
	timePart = false
	myPlayerID = Spring.GetMyPlayerID()
	myAllyTeamID = Spring.GetMyAllyTeamID()
	lists.arrowDraw = gl.CreateList(CreateArrow, arrowNew)
	widget:PlayerChanged(myPlayerID)
	for i, id in ipairs(Spring.GetAllUnits()) do
		local teamID = Spring.GetUnitTeam(id)
		if allyTeamByTeam[teamID] ~= myAllyTeamID then
			if not spIsUnitInView(id) and spIsUnitInLos(id) then
				widget:UnitEnteredLos(id ,teamID)
			end
		end
	end
end

function widget:Shutdown()
	for _, list in pairs(lists) do
		gl.DeleteList(list)
	end
end
