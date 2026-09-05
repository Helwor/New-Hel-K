function widget:GetInfo()
	return {
	name      = "Catching Up Progress",
	desc      = "",
	author    = "Helwor",
	date      = "July 2026",
	license   = "GNU GPL, v2 or later",
	layer     = 100,
	enabled   = true,
	handler   = true,
	}
end
 -- FIXME can't find how to display some special characters with this
-- local fhDraw = fontHandler.Draw
-- local font = "LuaUI/Fonts/FreeSansBold_14"
-- local runFont = "LuaUI/Fonts/FreeMonoBold_12"
-- local runFont = "LuaUI/Fonts/FreeSansBold_14" 
-- local UseFont = fontHandler.UseFont
------
local triangle = string.char(226, 150, 186) -- ►

local timeCounter = 0
local gameTimePerSecond = 1
local lastGameTime = 0
local offy = -75
local runString = false
local runFontSize = 12
local runWidth, runHeight
local maxRunLength = 10
local baseRunWidth
local height = 5
local currentFrame = Spring.GetGameFrame()
local gameProg = currentFrame
local gl = gl
local Spring = Spring
local math = math
local vsx, vsy
local width

function widget:GameProgress(f) -- knowing we're catching up via GameProgress is not ideal
	gameProg = f
end

function widget:GameFrame(f)
	currentFrame = f
end

local frame = {
	{v = {-0.5, -0.5, 0}},
	{v = {-0.5, 0.5, 0}},
	{v = {0.5, 0.5, 0}},
	{v = {0.5, -0.5, 0}},
	{v = {-0.5, -0.5, 0}},
}
local function TimeFormat(t)
	local sec = t / 30
	local h, m = '', ''
	if sec >= 3600 then
		h = math.floor(sec/3600)..'h'
		sec = sec%3600
	end
	if sec >= 60 then
		m = math.floor(sec/60)..'m'
		sec = sec%60
	end
	if sec == 0 then
		sec = ''
	else
		sec = math.floor(sec)..'s'
	end
	return h..m..sec
end

function widget:Update(dt)
	timeCounter = timeCounter + dt
	if timeCounter >= 1 then
		local gameTime = Spring.GetGameSeconds()
		local gameTimePassed = gameTime - lastGameTime
		lastGameTime = gameTime
		gameTimePerSecond = gameTimePassed / timeCounter
		if gameTimePerSecond > 1.1 then
			local int = math.min(maxRunLength, math.floor(gameTimePerSecond + 0.5))
			runString = triangle:rep(int) 
			runWidth = baseRunWidth * int
		else
			runString = false
		end
		timeCounter = 0
	end
end

function widget:DrawScreen()
	if runString then
		-- draw speed run triangles
		gl.Color(0,0.8,0,1)
		-- FIXME can't find how to display special character this way
		-- UseFont(runFont)
		-- fhDraw(runString, math.floor(vsx - runWidth - 2 + 0.5), math.floor(vsy + offy + 0.5))
		------
		gl.Text(runString, math.floor(vsx - runWidth - 2 + 0.5), math.floor(vsy + offy + 0.5), runFontSize, '')
	end
	if gameProg - currentFrame > 30 then
		gl.Color(1,1,1,1)
		-- draw bar
		gl.LineWidth(1)
		gl.PushMatrix()
		gl.Translate(vsx/2, vsy-height/2, 0)
		gl.Scale(width, height, 1)
		gl.Rect(-0.5, -0.5, -0.5 + (currentFrame / gameProg), 0.5)
		gl.Color(0.8,0.5,0,1)
		gl.Shape(GL.LINE_STRIP, frame)
		gl.LineWidth(1)
		gl.PopMatrix()
		gl.Text(TimeFormat(gameProg), vsx/2, vsy-height/2, 10, 'cvno')
		-- draw run triangles
	end
	gl.Color(1,1,1,1)
end

function widget:GetViewSizes(x, y)
	vsx, vsy = Spring.Orig.GetViewSizes()
	width = vsx
end


function widget:Initialize()
	widget:GetViewSizes(Spring.GetViewSizes())
    local testFont = WG.Chili.Font:New({name = font, size = runFontSize})
    local testString= ("%s"):format(triangle)
    baseRunWidth, runHeight = testFont:GetTextWidth(testString), testFont:GetTextHeight(testString)
    testFont:Dispose()
    testFont = nil
end

