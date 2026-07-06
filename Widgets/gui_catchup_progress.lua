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

local height = 5
local currentFrame = Spring.GetGameFrame()
local gameProg = currentFrame
local gl = gl
local vsx, vsy
local width

function widget:GameProgress(f)
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
function widget:DrawScreen()
	if gameProg - currentFrame > 100 then
		gl.LineWidth(1)
		gl.PushMatrix()
		gl.Translate(vsx/2, vsy-height/2, 0)
		gl.Scale(width, height, 1)
		gl.Rect(-0.5, -0.5, -0.5 + (currentFrame / gameProg), 0.5)
		gl.Color(0.8,0.5,0,1)
		gl.Shape(GL.LINE_STRIP, frame)
		gl.LineWidth(1)
		-- gl.Text(TimeFormat(currentFrame)..'/'..TimeFormat(gameProg), (vsx + width)/2, vsy-height/2, 10, 'vno')
		gl.PopMatrix()
		gl.Text(TimeFormat(gameProg), vsx/2, vsy-height/2, 10, 'cvno')
		gl.Color(1,1,1,1)
	end
end

function widget:GetViewSizes(x, y)
	vsx, vsy = Spring.Orig.GetViewSizes()
	width = vsx
end

function widget:Initialize()
	widget:GetViewSizes(Spring.GetViewSizes())
end