--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    unit_smart_nanos.lua
--  brief:   Enables auto reclaim & repair for idle turrets
--  author:  Owen Martindell
--
--  Copyright (C) 2008.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
		return {
	name      = "API Clamp Mouse To World",
	desc      = "Tool to Clamp the mouse click inside the world map",
	author    = "Helwor",
	date      = "8 Sept 2022",
	license   = "GNU GPL, v2 or later",
	layer     = 1000001, -- after CF2
	enabled   = true,  --  loaded by default?
	handler   = true,
		}
end
-- speeds up
local Echo = Spring.Echo

local Screen0
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount
local spIsAboveMiniMap = Spring.IsAboveMiniMap
local selected = spGetSelectedUnitsCount()
local spGetMouseState = Spring.GetMouseState
local spGetWaterLevel = Spring.GetWaterLevel

local ClampScreenPosToWorld
WG.ClampScreenPosToWorld = false
local floor, round, huge, abs, max = math.floor, math.round, math.huge, math.abs, math.max
local round = function(x)
	return tonumber(round(x))
end

local defaultMargin = 20

----
local debugMe = {
	state = false,

	draw = function(self,pos, pos2, pos3)
		gl.PushMatrix()
		if pos2 then
			gl.BeginEnd(GL.LINE_STRIP, function()
				gl.Vertex(pos[1], pos[2], pos[3])
				gl.Vertex(pos2[1], pos2[2], pos2[3])
				if pos3 then
					gl.Vertex(pos3[1], pos3[2], pos3[3])
				end
			end)
		end
		gl.Translate(pos[1], pos[2], pos[3])
		gl.CallList(self.list)
		gl.Billboard()
		gl.Text(string.format('%d',pos[2]), 0,0,15 * WG.Cam.relDist / 1000, 'no')
		gl.PopMatrix()
	end
	,
	list = gl.CreateList(
		function()
			gl.PointSize(5)
			gl.BeginEnd(GL.POINTS, gl.Vertex, 0,0,0 )
			gl.PointSize(1)
			gl.Color(1,1,1,1)
		end
	)

}
options_path = 'Hel-K/' .. widget:GetInfo().name
options = {}
options_order = {'margin','debugMe'}
options.debugMe = {
	name = 'debug draw',
	type = 'bool',
	value = debugMe.state,
	OnChange = function(self)
		debugMe.state = self.value
	end,
	dev = true,
}
options.margin = {
	name = 'margin',
	type = 'number',
	min = 0, max = 50, step = 1,
	value = defaultMargin,
	OnChange = function(self)
		defaultMargin = self.value
	end,
	dev = true,
}

----

local f = WG.utilFuncs

function widget:CommandsChanged()
	selected = spGetSelectedUnitsCount()
end

local vsx, vsy
do
	local spWorldToScreenCoords = Spring.WorldToScreenCoords
	local mapSizeX, mapSizeZ = Game.mapSizeX,Game.mapSizeZ
	local spTraceScreenRay = Spring.TraceScreenRay
	local spGetGroundHeight = Spring.GetGroundHeight

	-- OLD dirty work around
	local clamp = function(x,z,off)
		local off = off or 1
		if x > mapSizeX - off then
			x = mapSizeX - off
		elseif x < off then
			x = off
		end

		if z > mapSizeZ - off then
			z = mapSizeZ - off
		elseif z < off then
			z = off
		end
		return x,z
	end
	local clampscreen = function(x,y)
		if x > vsx - 1 then
			x = vsx - 1
		elseif x < 1 then
			x = 1
		end

		if y > vsy - 1 then
			y = vsy - 1
		elseif y < 1 then
			y = 1
		end
		return x, y
	end
	local function process(center, height, margin, offsetHeight)
		-- local newY = math.max(center[5] - height, 0)
		local newY = center[5] - height
		local mx, my = spWorldToScreenCoords(center[4], newY, center[6])
		local center2 = {center[4], newY, center[6]}
		local _, test = spTraceScreenRay(mx, my, true, false, true, false, offsetHeight)
		if not test then
			return
		end
		local x2, y2, z2 = test[4], test[5], test[6]
		if not OUTHEIGHT and debugMe.state then
			OUTHEIGHT = {x2, y2, z2}
			local clx, clz = math.clamp(x2, 0, Game.mapSizeX), math.clamp(y2, 0, Game.mapSizeZ)
			OUTHEIGHT_CLAMPED = {clx, spGetGroundHeight(clx, clz), clz}

		end
		for i = 1, 3 do
			table.remove(test,1)
		end

		test[1], test[3] = clamp(test[1], test[3], margin or defaultMargin) -- margin < may fall too often out of map when traced
		test[2] = spGetGroundHeight(test[1], test[3])
		if offsetHeight then
			-- test[4], test[5], test[6] = x2, offsetHeight, z2
			test[4], test[5], test[6] = test[1], offsetHeight, test[3]
		end
		return mx, my, test, center2
	end

	local function OldMethod(mx, my, throughWater, margin, offsetHeight) -- not perfect but best so far
		local center2, center3, center4
		local nature, center
		 -- center[4-6] intersection of plane 0 (or offsetHeight)
		nature, center = spTraceScreenRay(mx, my, true, false, true, throughWater ~= false, offsetHeight)
		if not center then
			-- trace error (should not happen anymore since some recent engine update iirc)
			return mx, my, false
			end
		local center2 = {center[4],center[5],center[6]}
		-- when mouse fall into the sky
		-- we use the coord from the sky, but the world trace goes to plane 0 (or offsetHeight)
		-- which will offset when clamping back to map bounds and map height
		-- to avoid this we reask mouse pos from that sky position but lowered by the groundheight of this position
		-- then we reask the world sky version from this new screen pos that will give us a negative offset of the world pos that will be reoffsetted when clamped
		-- debugging
		-- local cx,cy,cz,c2x,c2y,c2z = unpack(center)
		-- local height = spGetGroundHeight(center[4],center[6])
		-- Echo(nature .. ' : ' .. round(cx),round(cy),round(cz) .. '   |   ' .. round(c2x),round(c2y),round(c2z) .. '| height: '.. round(height))
		--
		if nature == 'sky' then
			local test
			local height, newY
			if debugMe.state then
				local clx, clz = math.clamp(center[4], 0, Game.mapSizeX), math.clamp(center[6], 0, Game.mapSizeZ)
				CLAMPED = {clx, spGetGroundHeight(clx, clz), clz}
			end
			height = spGetGroundHeight(center[4],center[6])
			local _mx, _my
			_mx, _my, test = process(center, height, margin, offsetHeight)

			if not test then
				local height = height / 2
				_mx, _my, test = process(center, height, margin, offsetHeight)
				if not test then
					-- Echo('not clamped C')    
					return mx, my, false
				else
					-- Echo('corrected 1x')
				end
			else
				-- Echo('no correction')
			end
			mx, my = _mx, _my
			local correct-- = abs(height - test[2]) > abs(height/2)
				-- Echo("math.abs(height - test[2]) is ", math.abs(height - test[2]))
			-- Echo("newY,'vs',test[2] is ", height,'vs',test[2],'correct',correct,(height + test[2]) / 2)
			correct = true
			if correct then
				height = (height + test[2]) / 2
				_mx,_my,test = process(center, height, margin, offsetHeight)

				if not test then
					-- Echo('not clamped D')
					return mx, my, false
				end
			end
			center[1], center[2], center[3], center[4], center[5], center[6] = test[1], test[2], test[3], test[4], test[5], test[6]
			mx, my = spWorldToScreenCoords(center[1], center[2], center[3]) 
			-- nature,center = spTraceScreenRay(mx,my,true,true,false,false)
			-- if not center then
			--     return
			-- end

			mx, my = clampscreen(mx, my)
		end
		-- Echo("h,h2 is ", h,h2)
		-- Echo('clamped')
		-- Echo("mx,my, center, center2", mx,my, center, center2)
		return mx, my, center, center2
	end


	local function NewMethod(mx, my, throughWater) -- Not good/incomplete
		-- local nature, pos = spTraceScreenRay(mx, my, true, false, true, true)
		local nature, pos = spTraceScreenRay(mx, my, true, false, true, true, spGetWaterLevel(0,0)) -- assume the water level is uniform, but some map can have different water level over time
		local clamped = false
		if pos == nil then
			return mx, my
		end
		if nature == "sky" then
			local _,_, edgeX, edgeZ = clamp(pos[1], pos[3], 8) -- test if we are on edge
			local x, y, z = pos[4], pos[5], pos[6] -- get the mouse pos at plane of water level
			x, z, edgeX, edgeZ = clamp(x, z, 8) -- clamp at the edge of map
			mx, my = spWorldToScreenCoords(x, y, z) -- pick up the new screen position after clamping
				-- trace pos this time at ground height
			nature, pos = spTraceScreenRay(mx, my, true, false, true, true)
			-- nature can be sky if ground is underwater, in such case we stay at water level
			if nature == 'ground' or throughWater then
					-- in case we fall on ground, translate to the edge of map
				x, z = edgeX or pos[1], edgeZ or pos[3] 
				y = spGetGroundHeight(x, z) -- update the ground height after translation
				mx, my = spWorldToScreenCoords(x, y, z)
			end
			clamped = true
		end
		return mx, my, pos, clamped
	end

	local function AnotherMethod(mx, my)
		local nature, coords = Spring.TraceScreenRay(mx, my, true, false, true)

		if not coords then
			return mx, my, false
		end

		if nature == "ground" then
			return mx, my, {coords[1], coords[2], coords[3]}
		end

		-- sky : on a planePos (coords[4-6])
		local x, z = coords[4], coords[6]
		local y = Spring.GetGroundHeight(x, z)

		-- second trace à la hauteur du sol
		local nature2, coords2 = Spring.TraceScreenRay(mx, my, true, false, true, false, y)

		if coords2 then
			x, z = coords2[4], coords2[6]
			y = Spring.GetGroundHeight(x, z)
		end

		-- clamp
		x = math.max(0, math.min(Game.mapSizeX, x))
		z = math.max(0, math.min(Game.mapSizeZ, z))

		local mx2, my2 = Spring.WorldToScreenCoords(x, y, z)
		return mx2, my2, {x, y, z}		
	end

	ClampScreenPosToWorld = function (mx,my, useMinimap, throughWater, margin, ignoreUI, offsetHeight)

		
		if not Screen0 then
			Screen0 = WG.Chili.Screen0
			if not Screen0 then
				return mx, my, false
			end
		end
		local lmb
		if not mx then
			mx, my, lmb = spGetMouseState()
		end
		if useMinimap ~= false and spIsAboveMiniMap(mx, my) or ignoreUI~=false and (Screen0.hoveredControl and lmb) then
			-- Echo('not clamped A')
			return mx, my, false
		end
		local center, center2
		CLAMPED = false
		OUTHEIGHT = false
		OUTHEIGHT_CLAMPED = false
		mx, my, center, center2 = OldMethod(mx,my, throughWater, margin, offsetHeight)
		-- local clamped
		-- mx, my, center, clamped = NewMethod(mx, my, throughWater)
		-- mx, my, center = AnotherMethod(mx, my)
		return mx,my, center, center2--, center3, center4



	end
	WG.ClampScreenPosToWorld = ClampScreenPosToWorld
end


local CF2
function widget:Initialize()
	widget:ViewResize()
	-- if Spring.GetSpectatingState() then
	--     widgetHandler:RemoveWidget(self)
	--     return
	-- end
	WG.ClampScreenPosToWorld = ClampScreenPosToWorld
	widget:CommandsChanged()
end
function widget:ViewResize(x,y)
	vsx, vsy = Spring.Orig.GetViewSizes()
end

function widget:DrawWorld()
	if debugMe.state then
		local _,_,pos, pos2 = WG.ClampScreenPosToWorld()
		if pos then
			gl.Color(1,1,0,1)
			debugMe:draw(pos)
		end
		if pos2 then
			gl.Color(1,1,1,1)
			debugMe:draw(pos2)
		end
		if OUTHEIGHT then
			gl.Color(1,0,0,1)
			debugMe:draw(OUTHEIGHT)
		end
		if OUTHEIGHT_CLAMPED then
			gl.Color(1,0.5,0,1)
			debugMe:draw(OUTHEIGHT_CLAMPED, {OUTHEIGHT_CLAMPED[1], 0, OUTHEIGHT_CLAMPED[3]},OUTHEIGHT)
		end
		if CLAMPED then
			gl.Color(0,1,0,1)
			debugMe:draw(CLAMPED)
		end
		--- draw exterior
		if not list then
			list = gl.CreateList(function()
				local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
				local step = 32
				local margin = 320
				local spGetGroundHeight = Spring.GetGroundHeight
				local spWorldToScreenCoords = Spring.WorldToScreenCoords
				-- columns
				for x = -margin, mapX + margin, step do
					local line1, i1, line2, i2 = {}, 0, {}, 0
					local line, i = line1, i1
					for z = -margin, mapZ + margin, step do
						if (x <= 0) or (x >= mapX) or (z <= 0) or (z >= mapZ) then
							i = i + 1
							line[i] = {x, spGetGroundHeight(x,z), z}
						else
							line, i = line2, i2
						end
					end
					if line1[2] then
						gl.BeginEnd(GL.LINE_STRIP, function()
							for _, c in ipairs(line1) do
								gl.Vertex(unpack(c))
							end
						end)
					end
					if line2[2] then
						gl.BeginEnd(GL.LINE_STRIP, function()
							for _, c in ipairs(line2) do
								gl.Vertex(unpack(c))
							end
						end)
					end
				end
				-- rows
				for z = -margin, mapZ + margin, step do
					local line1, i1, line2, i2 = {}, 0, {}, 0
					local line, i = line1, i1
					for x = -margin, mapX + margin, step do
						if (x <= 0) or (x >= mapX) or (z <= 0) or (z >= mapZ) then
							i = i + 1
							line[i] = {x, spGetGroundHeight(x,z), z}
						else
							line, i = line2, i2
						end
					end
					if line1[2] then
						gl.BeginEnd(GL.LINE_STRIP, function()
							for _, c in ipairs(line1) do
								gl.Vertex(unpack(c))
							end
						end)
					end
					if line2[2] then
						gl.BeginEnd(GL.LINE_STRIP, function()
							for _, c in ipairs(line2) do
								gl.Vertex(unpack(c))
							end
						end)
					end
				end

			end)
		end
		if list then
			gl.CallList(list)
		end
	end
end

function widget:Shutdown()
	if list then
		gl.DeleteList(list)
	end
end

f.DebugWidget(widget)