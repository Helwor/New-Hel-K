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
local displaySymbol = true
local displayBar = true
local GAME_SPEED = Game.gameSpeed
-- run speed notification
local triangle = string.char(226, 150, 186) -- ►
local runningSince = false -- only available via Hel-Chobby
local askedRunningSince = false
local timeCounter = 0
local gameTimePerSecond = 1
local lastGameTime = 0
local offy = -75
local runString = false
local runningSince
local runFontSize = 12
local runWidth, runHeight
local maxRunLength = 10
local baseRunWidth
local lastmx, lastmxy = -1, -1
local tooltip = false
--- catching up bar 
local width
local height = 5
local currentFrame = Spring.GetGameFrame()
local gameProg = currentFrame
---
local gl = gl
local Spring = Spring
local math = math
local vsx, vsy
local Screen0

WG.catchingUp = false
local time = os.clock()
local done = false

local frame = {
	{v = {-0.5, -0.5, 0}},
	{v = {-0.5, 0.5, 0}},
	{v = {0.5, 0.5, 0}},
	{v = {0.5, -0.5, 0}},
	{v = {-0.5, -0.5, 0}},
}

local function TimeFormat(sec)
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

function widget:GameProgress(f) -- first game progress can take a while to get
	gameProg = f
end

function widget:GameFrame(f)
	currentFrame = f
end

function widget:IsAbove(mx, my)
	if not runString then -- end of service
		if tooltip then
			if Screen0.currentTooltip == tooltip then
				Screen0.currentTooltip = 'NONE'
			end
			tooltip = false
			lastmx, lastmy = -1, -1
		end
		return
	elseif mx == lastmx and my == lastmy and strGameTimePerSecond == tooltip then
		-- nothing to do
		return
	end
	if mx > vsx - runWidth and my > vsy + offy and my < vsy + offy + runHeight
	then -- in the zone
		if tooltip ~= strGameTimePerSecond then
			tooltip = strGameTimePerSecond
			Screen0.currentTooltip = tooltip
		end
	else -- out of the zone
		if Screen0.currentTooltip == tooltip then
			Screen0.currentTooltip = 'NONE'
			tooltip = false
		end
	end
	lastmx, lastmy = mx, my
end
function widget:Update(dt)
	timeCounter = timeCounter + dt
	if timeCounter >= 1 then
		local gameTime = Spring.GetGameSeconds()
		local gameTimePassed = gameTime - lastGameTime
		lastGameTime = gameTime
		gameTimePerSecond = gameTimePassed / timeCounter
		if gameTimePerSecond > 1.05 then
			if gameProg <= currentFrame then -- approx time from game starting time stamp from lobby, only available with Hel-Chobby
				if not askedRunningSince then
					askedRunningSince = true
					Spring.SendCommands('getrunningsince')
				elseif runningSince then
					gameProg = math.max(1, (runningSince - 45) * GAME_SPEED) -- remove 45 sec for discounting aprox placing time
					runningSince = false
				end
			end
			local eta = gameProg > currentFrame and  (gameProg - currentFrame) / (gameTimePerSecond * GAME_SPEED)
			if eta then
				eta = eta + eta / gameTimePerSecond
			else
				eta = 'unknown'
			end
			strGameTimePerSecond = ('x%.1f ETA:%s'):format(gameTimePerSecond, tonumber(eta) and TimeFormat(eta) or eta)
			local int = math.min(maxRunLength, math.floor(gameTimePerSecond + 0.5))
			runString = triangle:rep(int) 
			runWidth = baseRunWidth * int
			WG.catchingUp = gameTimePerSecond
			WG.catchingUpETA = eta
		elseif runString then
			runString = false
			WG.catchingUp = false
			WG.catchingUpETA = false
		end
		timeCounter = 0
	end
end

function widget:DrawScreen()
	if runString and displaySymbol then
		-- draw speed run triangles
		gl.Color(0,0.8,0,1)
		-- FIXME can't find how to display special character this way:
		-- UseFont(runFont)
		-- fhDraw(runString, math.floor(vsx - runWidth - 2 + 0.5), math.floor(vsy + offy + 0.5))
		------
		gl.Text(runString, math.floor(vsx - runWidth - 2 + 0.5), math.floor(vsy + offy + 0.5), runFontSize, '')
	end
	if displayBar and gameProg - currentFrame > GAME_SPEED then
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
		if runString then
			gl.Text(TimeFormat(gameProg / GAME_SPEED) ..' '.. strGameTimePerSecond, vsx/2, vsy-height/2, 10.5, 'cvno')
		else
			gl.Text(TimeFormat(gameProg / GAME_SPEED), vsx/2, vsy-height/2, 11, 'cvno')
		end
		-- draw run triangles
	end
	gl.Color(1,1,1,1)
end

function widget:RecvLuaMsg(msg, playerID)
	if msg:find('^gamerunningsince') then
		local delta = msg:sub(('gamerunningsince'):len()+2)
		runningSince = tonumber(delta)
		Echo("runningSince1 is ", runningSince)
	end
end

function widget:GetViewSizes(x, y)
	vsx, vsy = Spring.Orig.GetViewSizes()
	width = vsx
end


function widget:Initialize()
	Screen0 = WG.Chili.Screen0
	widget:GetViewSizes(Spring.GetViewSizes())
    local testFont = WG.Chili.Font:New({name = font, size = runFontSize})
    local testString= ("%s"):format(triangle)
    baseRunWidth, runHeight = testFont:GetTextWidth(testString), testFont:GetTextHeight(testString)
    testFont:Dispose()

    testFont = nil
    WG.catchingUp = false
    WG.catchingUpETA = false
end

function widget:Shutdown()
	WG.catchingUp = nil
	WG.catchingUpETA = nil
end
