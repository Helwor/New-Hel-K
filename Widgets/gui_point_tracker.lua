-- $Id$
local versionNumber = "v2.3"

function widget:GetInfo()
	return {
		name      = "Point Tracker",
		desc      = versionNumber .. " Tracks recently placed map points.",
		author    = "Evil4Zerggin",
		date      = "29 December 2008",
		license   = "GNU LGPL, v2.1 or later",
		layer     = -10e36, -- draw on top of about everything
		enabled   = true  --  loaded by default?
	}
end

local GetMiniMapFlipped = Spring.Utilities.IsMinimapFlipped

----------------------------------------------------------------
--config
----------------------------------------------------------------
--negative to disable blinking
local blinkPeriod = -1
local exp_time = 0.7
local ttl = 13
local mapMarkerSize = 13
local edgeMarkerSize = 32
local lineWidth = 1
local maxAlpha = 1
local fontSize = 16
local maxLabelLength = 16

local minimapMarkerSize = 8

local useFade = true
local animate = false
----------------------------------------------------------------
--speedups
----------------------------------------------------------------
local ArePlayersAllied    = Spring.ArePlayersAllied
local GetPlayerInfo       = Spring.GetPlayerInfo
local GetTeamColor        = Spring.GetTeamColor
local GetSpectatingState  = Spring.GetSpectatingState
local WorldToScreenCoords = Spring.WorldToScreenCoords

local glColor        = gl.Color
local glRect         = gl.Rect
local glLineWidth    = gl.LineWidth
local glShape        = gl.Shape
local glPolygonMode  = gl.PolygonMode
local glText         = gl.Text
local glPushMatrix   = gl.PushMatrix
local glPopMatrix    = gl.PopMatrix
local glTranslate    = gl.Translate
local glScale        = gl.Scale
local glRotate       = gl.Rotate

local abs    = math.abs
local diag   = math.diag

local GL_FRONT_AND_BACK = GL.FRONT_AND_BACK
local GL_LINES          = GL.LINES
local GL_TRIANGLES      = GL.TRIANGLES
local GL_LINE           = GL.LINE
local GL_FILL           = GL.FILL

----------------------------------------------------------------
--vars
----------------------------------------------------------------
--table; i = {r, g, b, a, px, pz, label, expiration}
local mapPoints = {}
local mapPointCount = 0
local MAP_POINT_LIMIT = 15
local myPlayerID
local timeNow, timePart
local on = false
local mapX = Game.mapX * 512
local mapY = Game.mapY * 512
local diagScr
local vsx, vsy, sMidX, sMidY

local mapMarkerVerts = {
	{v = {  0,   -0.75,   0}},
	{v = {  0,   -1.20,   0}},
	{v = {  0,    0.75,   0}},
	{v = {  0,    1.20,   0}},
	{v = {-0.75,    0,    0}},
	{v = {-1.20,    0,    0}},
	{v = { 0.75,    0,    0}},
	{v = { 1.20,    0,    0}},
}


local edgeMarkerVert = {
	{v = {0.5,  0.5, 0}},
	{v = { 0,    0,  0}},
	{v = {0.5, -0.5, 0}},
}


options = {}
options_path = 'Hel-K/'..widget.GetInfo().name
options.animate = {
	name = 'Animate',
	desc = 'Make the point/label more catchy, especially useful if you\'re not using minimap',
	type = 'bool',
	value = animate,
	OnChange = function(self)
		animate = self.value
	end
}

options.debug = {
	name = 'Debugging',
	type = 'bool',
	value = debugging,
	action = 'debugpoint',
	OnChange = function(self)
		debugging = self.value
	end,
	dev = true,
}

----------------------------------------------------------------
--local functions
----------------------------------------------------------------
local function GetPlayerColor(playerID)
	local _, _, isSpec, teamID = GetPlayerInfo(playerID, false)
	if (isSpec) then return GetTeamColor(Spring.GetGaiaTeamID()) end
	if (not teamID) then return nil end
	return GetTeamColor(teamID)
end

local function StartTime()
	local viewSizeX, viewSizeY = widgetHandler:GetViewSizes()
	widget:ViewResize(viewSizeX, viewSizeY)
	timeNow = 0
	timePart = 0
	on = true
end

local function ClearPoints()
	mapPoints = {}
end

local function SetUseFade(bool)
	useFade = bool
end
----------------------------------------------------------------
--callins
----------------------------------------------------------------

function widget:Initialize()
	timeNow = false
	timePart = false
	myPlayerID = Spring.GetMyPlayerID()
	
	WG.PointTracker = {
		ClearPoints = ClearPoints,
		SetUseFade = SetUseFade
	}
end

function widget:Shutdown()
	WG.PointTracker = nil
end

function widget:DrawScreen() -- fix some ui like minimap being on top
	if not on then
		return
	end
	
	glLineWidth(lineWidth)

	local i = 1
	while i <= mapPointCount do
		local curr = mapPoints[i]
		local time_remain = (curr[6] - timeNow)
		local time = ttl - time_remain
		local alpha = (maxAlpha * time_remain / ttl) ^ 2.5
		if debugging then
			Echo('point', i, alpha, curr[6], timeNow, time_remain, (maxAlpha * time_remain / ttl))
		end
		if (alpha <= 0.01 or time_remain < 0) then
			mapPoints[i] = mapPoints[mapPointCount]
			mapPoints[mapPointCount] = nil
			mapPointCount = mapPointCount - 1
		else
			local sx, sy, sz = WorldToScreenCoords(curr[2], curr[3], curr[4])
			local inscreen = (sx >= 0 and sy >= 0 and sx <= vsx and sy <= vsy)
			if inscreen or animate then
				local expand_fact = 0
				if animate then
					expand_fact = exp_time-time
					local slow_t = exp_time * 0.8
					if expand_fact > slow_t then
						local rem = (expand_fact - slow_t)
						expand_fact = expand_fact + rem^3
					end
				end
				local color = curr[1]
				if expand_fact > 0 then
					glColor(color[1], color[2], color[3], math.min(1, alpha) - expand_fact*0.75)
				else
					glColor(color[1], color[2], color[3], math.min(1, alpha))
				end
			
				glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
				glPushMatrix()
				glTranslate(sx , sy , 0)
				local scale = mapMarkerSize
				if expand_fact > 0 then
					-- glLineWidth(lineWidth * (1+expand_fact*2))
					glRotate(-100 * expand_fact, 0, 0, 1)
					local scr_dist = diag(sx - vsx/2, sy - vsy/2)
					glLineWidth(lineWidth + 7 * expand_fact * scr_dist / diagScr)
					-- scale = scale * (1 + expand_fact * scr_dist / (mapMarkerSize/2))
					scale = scale + 2 * expand_fact * scr_dist -- same but simpler
				end
				glScale(scale, scale, 1)
				glRect(-1, -1, 1, 1)
				glShape(GL_LINES, mapMarkerVerts)
				glPopMatrix()
			end
			if not inscreen then
				--out of screen
				glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
				--flip if behind screen
				if (sz > 1) then
					sx = sMidX - sx
					sy = sMidY - sy
				end
				local xRatio = sMidX / abs(sx - sMidX)
				local yRatio = sMidY / abs(sy - sMidY)
				local edgeDist, textX, textY, textOptions
				glPushMatrix()

				if (xRatio < yRatio) then
					edgeDist = (sy - sMidY) * xRatio + sMidY
					textY = edgeDist - fontSize * 0.5
					if (sx > 0) then -- on right
						glTranslate(vsx, edgeDist, 0)
						glRotate(180, 0, 0, 1)
						textX = vsx - edgeMarkerSize/2
						textOptions = "rn"
					else -- on left
						glTranslate(0, edgeDist, 0)
						textX = edgeMarkerSize/2
						textOptions = "n"
					end
				else
					edgeDist = (sx - sMidX) * yRatio + sMidX
					textX = edgeDist
					if (sy > 0) then -- on top
						glTranslate(edgeDist, vsy, 0)
						glRotate(270, 0, 0, 1)
						textY = vsy - edgeMarkerSize/2 - fontSize
						textOptions = "cn"
					else -- on bottom
						glTranslate(edgeDist, 0, 0)
						glRotate(90, 0, 0, 1)
						textY = edgeMarkerSize*3/4
						textOptions = "cn"
					end
				end
				local color = curr[1]
				glColor(color[1], color[2], color[3], alpha)
				glScale(edgeMarkerSize, edgeMarkerSize, 1)
				glShape(GL_TRIANGLES, edgeMarkerVert)
				glPopMatrix()
				glColor(1, 1, 1, alpha)
				glText(curr[5], textX, textY, fontSize, textOptions)
			end
			i = i + 1
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
	diagScr = diag(vsx,vsy)
end

function widget:MapDrawCmd(playerID, cmdType, px, py, pz, label)
	if (not timeNow) then
		StartTime()
	end
	local spectator, fullView = GetSpectatingState()
	local _, _, _, playerTeam = GetPlayerInfo(playerID, false)
	if (label == "Start " .. playerTeam
			or cmdType ~= "point"
			or not (ArePlayersAllied(myPlayerID, playerID) or (spectator and fullView))) then
		return
	end
	
	local r, g, b = GetPlayerColor(playerID)
	local color = {r, g, b}
	local expiration = timeNow + ttl
	
	if mapPointCount < MAP_POINT_LIMIT then
		mapPointCount = mapPointCount + 1
	else
		table.remove(mapPoints, 1)
	end
	mapPoints[mapPointCount] = {color, px, py, pz, label:sub(1, maxLabelLength), expiration}
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

function widget:DrawInMiniMap(sx, sy)
	if (not on) then
		return
	end
	glLineWidth(lineWidth)
	
	local ratioX = sx / mapX
	local ratioY = sy / mapY

	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
	local i = 1
	while i <= mapPointCount do
		local curr = mapPoints[i]
		local x = curr[2] * ratioX
		local y = sy - curr[4] * ratioY

		if GetMiniMapFlipped() then
			x = sx - x
			y = sy - y
		end

		local alpha = maxAlpha * (curr[6] - timeNow) / ttl
		if (alpha <= 0) then
			mapPoints[i] = mapPoints[mapPointCount]
			mapPoints[mapPointCount] = nil
			mapPointCount = mapPointCount - 1
		else
			local color = curr[1]
			glColor(color[1], color[2], color[3], alpha)
			glPushMatrix()
			glTranslate(x, y, 0)
			glScale(minimapMarkerSize, minimapMarkerSize, 1)
			glRect(- 1, - 1, 1, 1)
			glShape(GL_LINES, mapMarkerVerts)
			glPopMatrix()
			i = i + 1
		end
	end
	
	glColor(1, 1, 1)
	glLineWidth(1)
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
end
