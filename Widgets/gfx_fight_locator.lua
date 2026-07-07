function widget:GetInfo()
	return {
		name = "Fight Locator",
		desc = "Show where fight occur when user is zoomed out",
		author = "Helwor",
		date = "July 2026",
		license = "GNU GPL, v2 or later",
		layer = -100,
		enabled = false,
	}
end
local Spring = Spring
local os = os
local GL = GL
local gl = gl
local WG = WG
local math = math

local dynamic = false
local TIMEOUT = 5
local CELL = 1000
local BLINK = 0.4
local frame_size = 25
local now = Spring.GetGameSeconds()
local events = {}
local function NewEvent(x, z)

	local event = {
		timeout = 0,
		weight = 0,
		x = 0, z = 0,
	}
	events[x..'-'..z] = event
	return event
end



----- arrow heads graphics
local space = 0.2 -- space left at middle (out of 0.5)
local wide = 0.4 -- wide, right angle head at 0.5
local thick = 0.15 -- thickness max 0.5 - space for right angle tail
local arrow_heads_vert = { --  anti clockwise triangles, can be culled front
	---- bottom left
	-- leftmost
	{v = {-space, -space, 0}}, -- head
	{v = {-0.5, -(0.5+space-wide), 0}}, -- ext
	{v = {-(space+thick), -(space+thick), 0}}, -- in
	-- rightmost
	{v = {-space, -space, 0}}, -- head
	{v = {-(space+thick), -(space+thick), 0}}, -- in
	{v = {-(0.5+space-wide), -0.5, 0}}, -- ext

	---- top right
	-- leftmost
	{v = {(space), (space), 0}}, -- head
	{v = {(space+thick), (space+thick), 0}}, -- in
	{v = {(0.5+space-wide), 0.5, 0}}, -- ext
	-- rightmost
	{v = {space, space, 0}}, -- head
	{v = {0.5, (0.5+space-wide), 0}}, -- ext
	{v = {(space+thick), (space+thick), 0}}, -- in

	---- top left
	-- leftmost
	{v = {-space, space, 0}}, -- head
	{v = {-(space+thick), (space+thick), 0}}, -- in
	{v = {-0.5, (0.5+space-wide), 0}}, -- ext
	-- rightmost
	{v = {-space, space, 0}}, -- head
	{v = {-(0.5+space-wide), 0.5, 0}}, -- ext
	{v = {-(space+thick), (space+thick), 0}}, -- in

	---- bottom right
	-- leftmost
	{v = {space, -space, 0}}, -- head
	{v = {(0.5+space-wide), -0.5, 0}}, -- ext
	{v = {(space+thick), -(space+thick), 0}}, -- in
	-- rightmost
	{v = {space, -space, 0}}, -- head
	{v = {(space+thick), -(space+thick), 0}}, -- in
	{v = {0.5, -(0.5+space-wide), 0}}, -- ext
}

function widget:Update()
	now = os.clock()
	for cell_coord, event in pairs(events) do
		if now >= event.timeout then
			events[cell_coord] = nil
		else
			if event.weight > 50 then 
				local fact = (event.timeout - now) / TIMEOUT
				if fact > 0.001 then
					event.weight, event.x, event.z = event.weight * fact, event.x * fact, event.z * fact
				end
			end
		end
	end
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer)
	local x, y, z = Spring.GetUnitPosition(unitID)
	local cellX, cellZ  = math.floor(x/CELL), math.floor(z/CELL)
	local event
	for offx = -2, 2 do
		for offz = -2, 2 do
			if offx ~= 0 or offz ~= 0 then 
				local ev = events[(cellX+offx)..'-'..(cellZ+offz)]
				if ev then
					if math.diag(x - ev.x/ev.weight, z - ev.z/ev.weight) < CELL then
						event = ev
						break
					end
				end
			end
		end
	end
	local isNew = false
	if not event then
		event = events[(cellX)..'-'..(cellZ)]
		if not event then
			event = NewEvent(cellX, cellZ)
			isNew = true
		end
	end
	if dynamic or isNew then
		event.timeout = now + TIMEOUT
		event.x, event.z = event.x + x * damage, event.z + z * damage
		event.weight = event.weight + damage
	end
end

function widget:DrawScreenEffects()
	if WG.Cam.relDist < 5000 then
		return
	end
	-- local list = ''
	-- for k,v in pairs(events) do
	-- 	list = list..v.weight..','
	-- end
	-- list = list:sub(1, -2)
	-- gl.Text("#events ".. table.size(events) .. ', weights ' .. list, 600, 25)
	gl.Culling(GL.BACK)
	local blink = (now%BLINK < BLINK/2)
	local r, g, b = 0.8, 0.1 + (blink and 0.8 or 0), 0.5
	for cell_coord, event in pairs(events) do
		if event.weight > 0 then
			local x, z = event.x / event.weight, event.z / event.weight
			local y = Spring.GetGroundHeight(x, z)
			if Spring.IsSphereInView(x, y, z, 300) then
				local a = (event.timeout - now) / TIMEOUT
				gl.Color(r, g, b, a)
				x, y = Spring.WorldToScreenCoords(x, y, z)
				gl.PushMatrix()
					gl.Translate(x, y, 0)
					gl.Scale(frame_size * (blink and 1.2 or 1), frame_size * (blink and 1.2 or 1), 0)
					gl.Shape(GL.TRIANGLES, arrow_heads_vert)
				gl.PopMatrix()
			end
		end
	end
	gl.Culling(false)
	gl.Color(1,1,1,1)
end