function widget:GetInfo()
	return {
		name      = "Draw Marker From Image",
		desc      = "Place marker drawn from images, use Ctrl + Alt to show the UI, put images png/jpg/tif in the LuaUI/Widgets/Drawings dir, they get updated live during widget run"
					.."\nUse shift to place multiple, right click to cancel."
					.."\nClick on map and drag: left to mirror horizontally, down to mirror vertically."
					.."\nImages are stored as json file for faster loading",
		author    = "Helwor",
		date      = "Dec 2023",
		license   = "GNU GPL, v2 or later",
		layer     = - 10e35,
		enabled   = true,  --  loaded by default?
		-- api       = true,
		handler   = true,
	}
end

local json = VFS.Include("LuaRules/Utilities/json.lua",nil, VFS.ZIP)

local Echo = Spring.Echo

local spGetGroundHeight 	= Spring.GetGroundHeight
local spWorldToScreenCoords = Spring.WorldToScreenCoords
local spTraceScreenRay 		= Spring.TraceScreenRay
local spGetMouseState 		= Spring.GetMouseState
local spGetModKeyState 		= Spring.GetModKeyState
local spGetSelectedUnits 	= Spring.GetSelectedUnits
local spMarkerAddLine 		= Spring.MarkerAddLine

local glVertex = gl.Vertex


local drawingsDir = "LuaUI\\Widgets\\Drawings\\"

local tasks = {}
local DEBUG_CONTOUR = false
local mode = 'contour'
local alwaysUp = false
local angleSmoothness = 0.05
local COUNT_FOR_ANGLE = 3
local PRECISION = 0.5
local analyse_size = 300 -- the diagonal of the image is extended to this in order to improve the contour making
local screen_ratio = 1/2 -- the final result on screen as marker is reshrinked by this multiplicator
-- local listFile = "LuaUI\\Widgets\\Drawings\\Draw_19.txt"
local buttonWidth = 75
local MAX_WIN_HEIGHT = 300 -- adaptative win height to fit the last thumbnail size
local buttonPadding = {5,10,5,10}
local pixDetect = 0.6 -- any rgb color below this value will accept a point of line, any alpha value below (1-pixDetect) will deny it

local LBPressed, LBx, LBy = false
local mirrorH, mirrorV = 1, 1

-- hax to customize selected button appearance
local oriBGColor
local oriFocusColor
local oriPressedColor
local selectedColor
local function MakeSelectedColor(r,g,b,a)
	-- return {1, g * 0.8, b * 0.8, a * 1.5}
	return {r * 0.5, g * 2, b * 0.5, a * 1.5}
end
--
local holder = {}
local selector, win, scroll
local deselectOnRelease = false
local selected = false
local initialized = false
local Init
local updateTime = 0
local updateDelay = 3
local taskTime = 0
local taskDelay = 1
local vsx, vsy = Spring.GetViewGeometry()

options_path = 'Hel-k/'..widget:GetInfo().name
options_order = {'alwaysUp', 'mode', 'simplifyAngle'}
options = {}

options.mode = {
	name = 'Mode',
	type = 'radioButton',
	value = mode,
	items = {
		{name = 'Contour', key = 'contour'},
		{name = 'Spaghetti', key = 'spaghetti'},
		{name = 'Plain', key = 'plain'},
	},
	OnChange = function(self)
		mode = self.value
		initialized = false
	end
}

options.simplifyAngle = {
	name = 'Simplify Angle Tolerance',
	type = 'number',
	min = 0.000, max = 0.1, step = 0.005,
	value = angleSmoothness,
	desc = '',
	OnChange = function(self)
		angleSmoothness = self.value
		initialized = false
	end,
}

options.alwaysUp = {
	name = 'Always Up',
	desc = 'Always show the UI without key pressed Ctrl + Alt',
	type = 'bool',
	value = alwaysUp,
	OnChange = function(self)
		alwaysUp = self.value
		if win then
			if not alwaysUp then
				local alt, ctrl = Spring.GetModKeyState()
				if not (alt and ctrl) then
					win:Hide()
				end
			elseif win.hidden then
				win:Show()
			end
		end
	end,
}

-- Making Contour
--- making Rotator clockwise usage: rasterRot[x][z] = rotatedCoords


local function SpiralSquare(layers, step, callback, offset, reverse, ortho)
	-- LOOP iterating squares clockwise from center to exterior, starting at bottom left corner
	-- reverse is anticlockwise, from exterior to center, starting at top right
	-- first point is always at center if offset is explicit 0
	local brokeloop = false
	offset = offset and offset / step
	local startlayer = offset or 1
	-- Echo("layers,startlayer,step is ", layers,startlayer,step)
	-- reverse mode will start from top right and go anticlockwise
	local ret
	if startlayer == 0 then
		ret = callback(0,0,0)
		if ret then 
			return ret
		end
		startlayer=1
	end
	local inc = 1
	-- reverse: from exterior to interior
	if reverse then
		inc  = -inc
		step = -step
		startlayer, layers = layers - (layers + startlayer) % 1, startlayer
	end
	local edge
	--
	for layer = startlayer, layers, inc do 
		local offz = -layer * step
		for s = step, -step, -2*step do -- browse half of perimeter per iteration (positive x and z then negative x and z)
			for offx = -layer*s, (layer-1)*s, s do -- start at first x, end at one step before last x // start at last x end at one step before first x
				for b = offz, layer * s, s do
					offz = b -- memorize b until last iteration -- loop will iterate only once at each second iteration of offx, so z will be stuck while x will change
					ret = callback(
						layer,
						reverse and offz or offx,
						reverse and offx or offz
					)
					if ret ~= nil then
						return ret
					end
				end
			end
		end
	end
end

local rasterRot = setmetatable(
	{},
	{
		__index = function(self, k) 
			local t = {}
			rawset(self, k, t)
			return t
		end
	}
)
local rotateRight, r = {}, 0
local add = function(_, x, z)
	r = r + 1
	rotateRight[r] = {z,x}
end
f.SpiralSquare(1, 1, add)
for i, r in ipairs(rotateRight) do
	rasterRot[ r[1] ][ r[2] ] = rotateRight[i + 1] or rotateRight[1]
end
setmetatable(rasterRot, nil)

local rasterRotInv = setmetatable(
	{},
	{
		__index = function(self, k) 
			local t = {}
			rawset(self, k, t)
			return t
		end
	}
)
local rotateLeft, r = {}, 0
local add = function(_, x, z)
	r = r + 1
	rotateLeft[r] = {z,x}
end

for i, r in ipairs(rotateLeft) do
	rasterRotInv[ r[1] ][ r[2] ] = rotateLeft[i + 1] or rotateLeft[1]
end

--[[ verif
local function verif(_, x, z)
	local coords = rasterRot[z][x]
	Echo(x, z .. ' =>> ' .. coords[2], coords[1])
end
f.SpiralSquare(1, 1, verif)
--]]

-- local deg = math.deg(math.atan2(x,z))
local glReadPixels = gl.ReadPixels
local function GetRaster(imageFile)
	local t = setmetatable(
		{},
		{
			__index = function(self, k) 
				local t = {}
				rawset(self, k, t)
				return t
			end
		}
	)
	gl.Texture(0, imageFile)
	local info = gl.TextureInfo(imageFile)
	if not info or info.xsize == -1 then
		Echo("CAN'T LOAD FILE " .. imageFile)
		return
	end
	-- f.Page(info)
	local sizeX = info.xsize
	local sizeY = info.ysize
	local diag = math.diag(sizeX, sizeY)
	local mul = analyse_size / diag
	sizeX = sizeX * mul
	sizeY = sizeY * mul

	gl.TexRect(0, 0, sizeX, sizeY)
	-- FIXME gl.ReadPixels is bugged when asking a map (w > 1 and h > 1), giving values at the wrong place
	-- so we ask line by line...
	local lines, l = {}, 0
	local left, right = math.huge, -math.huge
	for y = sizeY-1, 0, -1 do -- y0 is at bottom
		t[y+1] = gl.ReadPixels(0, y, sizeX, 1)
	end

	gl.Texture(0, false)
	gl.DeleteTexture(imageFile)
	return t
end

--- Contours
local function SearchAround(y, x, diry, dirx, raster, index, c, inv, inDeadEnd)
	-- check clockwise, starting just next to the point we come from
	diry, dirx = diry * -1, dirx * -1
	local dbg
	local loopy, loopx
	local spaghetti_mode = mode == 'spaghetti'
	local End = inDeadEnd and 7 or 8
	for i = 1, End do
		local dirs = inv and rasterRotInv[diry][dirx] or rasterRot[diry][dirx]
		-- dbg = table.concat({x, y, dirx, diry, '=>', dirs[2], dirs[1], '=>', x + dirs[2], y + dirs[1]}, ',')
		diry, dirx = dirs[1], dirs[2]
		local _y, _x = y + diry, x + dirx
		local point = raster[_y][_x]
		if point then
			local something = point[4] > (1 - pixDetect) and (point[1] < pixDetect or point[2] < pixDetect or point[3] < pixDetect)
			if something then
				if point.contour then
					if not spaghetti_mode then
						return _y, _x, diry, dirx, point
					end
				else
					return _y, _x, diry, dirx, point
				end
			end
		end
	end
	return

end

local function AcquireContour(point, _y, _x, raster, diry, dirx, c)
	local y, x = _y, _x
	point[1], point[2], point[3], point[4] = 0, 1, 1, 1
	-- point.txt = '0'..1
	-- point.contourStart = c
	-- Echo('START', x, y)
	local inv = false
	local join = {}
	local phase1 = true
	local lastY, lastX
	for iter = 1, 2 do
		if not phase1 then
			if lastY == y and lastX == x then
				break
			end
			inv = true
		end
		local contour, i = {}, 0 
		local tries = 0
		local diry, dirx, point = diry, dirx, point
		local y, x = y, x
		point.contour = false
		while point do
			tries = tries + 1
			if tries > 15000 then
				Echo('TOO MANY TRIES CONTOUR')
				break
			end
			i = i + 1
			contour[i] = {x, y} -- final result given in x,y not y,x
			lastY, lastX = y, x
			-- Echo('inv ' .. tostring(inv) .. ': #' .. i .. ': ' ..  x, y.. ' cont:'.. tostring(point.contour) )
			if point.contour then
				-- end the loop of the contour
				break
			end
			point.contour = c
			y, x, diry, dirx, point = SearchAround(y, x, diry, dirx, raster, i, c, inv)
		end
		phase1 = false
		join[#join+1] = contour
	end
	local part1 = join[1]
	local part2 = join[2]
	if not part2 then
		-- Echo("cont".. c.." only one part ", #part1, 'attack dir', dirx)
		return part1
	end
	-- Echo("cont".. c.." #part1, #part2 is ", #part1, #part2, 'attack dir', dirx)
	local long = #part1 > #part2 and part1 or part2
	local short = long == part1 and part2 or part1
	-- Echo('long, short', #long, #short)
	local insert = table.insert
	for i = 2, #short do
		local s = short[i]
		if s then
			insert(long, 1, s)
		end
	end
	-- Echo("#long is ", #long)
	local start, End = raster[long[1][2]][long[1][1]], raster[long[#long][2]][long[#long][1]]
	start.contourStart = c
	End.contourEnd = c


	-- Echo('return contour', #long)
	return long
end
local function AcquireContours(raster)
	local left, top, right, bottom = math.huge, -math.huge, -math.huge, math.huge
	local contours, c = {}, 0
	local inShape = false
	local simple = mode ~= 'spaghetti'
	local wasContour = false
	for y, t in pairs(raster) do
		for x, pixel in pairs(t) do
			local something = pixel[4] > (1 - pixDetect) and (pixel[1] < pixDetect or pixel[2] < pixDetect or pixel[3] < pixDetect)

			if something then
				if x < left then left = x end
				if y < bottom then bottom = y end
				if x > right then right = x end
				if y > top then top = y end
				if not inShape then
					if not pixel.contour then
						c = c + 1
						-- Echo('****CONTOUR ' .. c)
						contours[c] = AcquireContour(pixel, y, x, raster, 0, 1, c)
						if wasContour then
							contours[c].filling = true
						end
					end
				end
				inShape = simple and pixel
			elseif inShape then
				if not inShape.contour then
					c = c + 1
					-- Echo('****CONTOUR AFTER ' .. c)
					contours[c] = AcquireContour(inShape, y, x-1, raster, 0, -1, c)
				end
				inShape = false
			end
			wasContour = pixel.contour
		end
	end
	if c > 0 then
		contours.left, contours. top, contours.right, contours.bottom = left, top, right, bottom
		return contours
	end
end
local function SimplifyContours(contours)
	-- if true then return end
	local abs, diag = math.abs, math.diag
	local atan2 = math.atan2
	local remove = table.remove
	local f = function(n, dec)
		return tostring(n):ftrim(dec or 2)
	end
	local sizeX, sizeY = contours.right - contours.left, contours.top - contours.bottom
	local step = math.max(3, diag(sizeX, sizeY) / 30)
	-- Echo('*--------------------------------------------------')
	-- Echo('--------------------------------------------------')
	-- Echo('STEP', step)
	for c, contour in ipairs(contours) do
		local len = #contour
		local DBG = false and c == 1
		if DBG then
			Echo('**** CONTOUR '.. c ..'#'..len..' ****')
		end
		if len > 2 then
			-- local sensitivity = 1.04
			local i = 1
			local start = contour[1]
			local last = start
			local cur
			local travel
			local deviationx, deviationy = 0, 0
			local segI  = 1
			local makeAngle
			local angleX, angleY = 0, 0
			local angle
			local lastAngle
			while i < len do
				i = i + 1 
				cur = contour[i]
				local devX, devY = (cur[1] - last[1]), (cur[2] - last[2])
				local dist = diag(devX, devY)
				-- local straight = diag(cur[1] - start[1], cur[2] - start[2])
				if last == start then
					-- Echo(string.color({0,1,0,1}) .. '***start new segment', 'x'..start[1], 'y'..start[2])
					travel = 0
					segI = i - 1
					makeAngle = COUNT_FOR_ANGLE
					angleX, angleY = 0, 0
					deviationx, deviationy = 0, 0
					angle = false
					lastAngle = false
				end
				travel = travel + dist
				deviationx, deviationy = deviationx + devX, deviationy + devY

				if makeAngle then
					makeAngle = makeAngle - dist
					angleX, angleY = angleX + devX, angleY + devY
					if makeAngle <= 0 then
						makeAngle = false
						angle = atan2(angleX, angleY)
						lastAngle = angle
					end
				else
					lastAngle = lastAngle * (COUNT_FOR_ANGLE-1)/COUNT_FOR_ANGLE + atan2(devX, devY)/COUNT_FOR_ANGLE
				end
				deviationx = deviationx + devX
				deviationy = deviationy + devY
				local devAngle = angle and abs(angle - atan2(deviationx, deviationy)) 
				local devLastAngle = lastAngle and abs(lastAngle - angle)
				-- Echo(i,'x'..last[1]..'-'..cur[1],'y'..last[2]..'-'..cur[2], 'dist:'..f(dist),'straight:'..f(straight),'travel:'..f(travel), 'ratio:'..f(travel/straight))
				-- Echo("angle is ", angle)
				-- Echo('travel'..f(travel),'deviation',devX, devY, 'angle', angle, 'devAngle', devAngle )
				if travel > step or i == len then
					-- local ratio = travel/straight
					-- local ratioed = ratio > sensitivity
					local devied = devAngle and devAngle > angleSmoothness -- deviation from origin of segment
					local devied2 = devLastAngle and devLastAngle > 1/(COUNT_FOR_ANGLE * PRECISION) -- deviation from a little distance
					-- Echo(i,devied,devied2,'x'..last[1]..'-'..cur[1],'y'..last[2]..'-'..cur[2], "lastAngle is ", lastAngle)
					-- Echo(i,devied,devied2,'x'..last[1]..'-'..cur[1],'y'..last[2]..'-'..cur[2], lastAngle and "lastAngle:"..f(lastAngle), devLastAngle and 'devLastAngle:'..f(devLastAngle))
					if --[[ratioed or]] devied or devied2 or i == len then
						-- Echo(string.color({1,1,0,1})..'x'..last[1]..'-'..cur[1],'y'..last[2]..'-'..cur[2] .. ' => ', ratioed and 'ratio:' .. f(ratio), devied and 'devied:'..f(devAngle), devied2 and 'devied2:'..f(devLastAngle), (i == len) and 'end')
						if segI < i-2 then
							-- Echo(i, string.color({1,0,0,1}) .. '<<<<< remove from', segI+1, 'to', i-2)
							for i = i - 2, segI + 1, -1  do
								remove(contour, i)
								len = len - 1
							end
						end

						i = segI + 1
						start = last
					else
						last = cur
					end
				else
					last = cur
				end
			end
		end
		-- Echo("COUNT is ", COUNT, 'segments', #contour)
		-- Echo('contour', c, 'segments', #contour)
		-- Echo("step is ", step)
	end
	-- Echo('simplified')
	-- for i, contour in ipairs(contours) do
	-- 	Echo('contour',i,'#'..#contour)
	-- 	if i >= 4 then
	-- 		for i,v in pairs(contour) do
	-- 			Echo(i,unpack(v))
	-- 		end
	-- 	end
	-- end
	-- Echo("contours", #contours, 'COUNT',COUNT)
end
local SortContoursBySize = function(a, b)
	return #a > #b
end

local function ContourToLineObj(contours)
	table.sort(contours, SortContoursBySize)
	local lines, l = {}, 0
	local bottom, top = math.huge, -math.huge
	local left, right = math.huge, -math.huge
	for i, contour in ipairs(contours) do
		for i, coord in ipairs(contour) do 
			coord[1] = coord[1] * screen_ratio
			coord[2] = coord[2] * screen_ratio
			local x, y = coord[1], coord[2]
			if x < left then
				left = x
			elseif x > right then
				right = x
			end
			if y > top then
				top = y
			elseif y < bottom then
				bottom = y
			end
		end
		local i = 2
		local line = contour[1]
		local nex = contour[2]
		if line then
			if not nex then
				line[3], line[4] = line[1]+1, line[2]+1
				l = l + 1
				lines[l] = line
			else
				while nex do 
					line[3], line[4] = nex[1], nex[2]
					l = l + 1
					lines[l] = line
					line = nex
					i = i + 1
					nex = contour[i]
				end
			end
		else
			Echo('no line at contour ' .. i)
		end
	end
	lines.l = l
	lines.left, lines.top, lines.right, lines.bottom = left, top, right or left, bottom or top
	local midx, midy = (right - left) / 2, (top - bottom) / 2
	lines.midx, lines.midy = midx, midy
	local offx, offy = -left - midx, -top + midy
	for i, line in ipairs(lines) do
		line[1], line[2], line[3], line[4] = line[1] + offx, line[2] + offy, line[3] + offx, line[4] + offy
	end
	-- Echo('LINES', l)
	-- Echo("lines.left, lines.top, lines.right, lines.bottom is ", lines.left, lines.top, lines.right, lines.bottom)
	return lines
end




-------
local function ImageToLineObj(imageFile)
	gl.Texture(0, imageFile)
	local info = gl.TextureInfo(imageFile)
	if not info or info.xsize == -1 then
		Echo("CAN'T LOAD FILE " .. imageFile)
		return
	end
	-- f.Page(info)

	-- local sizeX = info.xsize
	-- local sizeY = info.ysize
	-- if sizeX > 150 or sizeY > 150 then
	-- 	sizeX, sizeY = sizeX * 150/sizeX, sizeY * 150/sizeY
	-- elseif sizeX < 50 or sizeY < 50 then
	-- 	sizeX, sizeY = sizeX * 1.5, sizeY * 1.5
	-- end

	local sizeX = info.xsize
	local sizeY = info.ysize
	local diag = math.diag(sizeX, sizeY)
	local mul = analyse_size / diag
	sizeX = sizeX * mul
	sizeY = sizeY * mul

	gl.TexRect(0, 0, sizeX, sizeY)
	-- FIXME gl.ReadPixels is bugged when asking a map (w > 1 and h > 1), giving values at the wrong place
	-- so we ask line by line...
	local lines, l = {}, 0
	local left, right = math.huge, -math.huge
	for y = sizeY-1, 0, -1 do -- y0 is at bottom
		local pixels = gl.ReadPixels(0, y, sizeX, 1)
		local started = false
		local line, lastX, lastY
		local oldcount = l
		for x, color in ipairs(pixels) do
			local something = color[4] > (1 - pixDetect) and (color[1] < pixDetect or color[2] < pixDetect or color[3] < pixDetect)
			if line then
				if not something then
					if line[1] == lastX then
						lastX = lastX + 1
						if lastX > right then
							right = lastX
						end
					end
					line[3], line[4] = lastX, lastY
					line = false
				else
					lastX, lastY = x, y
					if lastX > right then
						right = lastX
					end
				end
			elseif something then
				lastX, lastY = x, y
				line = {lastX, lastY}
				if x < left then
					left = x
				end
				l = l + 1
				lines[l] = line
			end
		end
		if line then
			if line[1] == lastX then
				lastX = lastX + 1
				if lastX > right then
					right = lastX
				end
			end
			line[3], line[4] = lastX, lastY
		end
	end
	gl.Texture(0, false)
	gl.DeleteTexture(imageFile)
	if l == 0 then
		return
	end

	bottom, top = lines[l][2], lines[1][2]

	lines.l = l
	lines.left, lines.top, lines.right, lines.bottom = left, top, right or left, bottom
	local midx, midy = (right - left) / 2, (top - bottom) / 2
	lines.midx, lines.midy = midx, midy
	local offx, offy = -left - midx, -top + midy
	for i, line in ipairs(lines) do
		line[1], line[2], line[3], line[4] = line[1] + offx, line[2] + offy, line[3] + offx, line[4] + offy
	end

	return lines
end


local function SetupCoords(mx, my, lines, ret, l, mirrorH, mirrorV)
	local midx, midy = lines.midx, lines.midy
	for i, line in ipairs(lines) do
		local x1, y1, x2, y2 = line[1] * (mirrorH or 1), line[2] * (mirrorV or 1), line[3] * (mirrorH or 1), line[4] * (mirrorV or 1)
		-- local x1, y1, x2, y2 = line[1] + mx, line[2] + my, line[3] + mx, line[4] + my
		-- onlyCoords, useMinimap, includeSky, ignoreWater
		local _, c1 = spTraceScreenRay(x1 + mx, y1 + my, true, false, false, false) --onlyCoords, useMinimap, includeSky, ignoreWater
		local _, c2 = spTraceScreenRay(x2 + mx, y2 + my, true, false, false, false)
		if c1 and c2 then
			l = l + 1
			ret[l] = {c1, c2}
		end
	end
	return l
end

local function Deselect()
	-- hax to make the button appear "selected" with special color when mouse in or out
	if not selected then 
		return
	end
	local control = selected.control
	local bgColor, focusColor, pressedColor = control.backgroundColor, control.focusColor, control.pressBackgroundColor
	bgColor[1], bgColor[2], bgColor[3], bgColor[4] = unpack(oriBGColor)
	focusColor[1], focusColor[2], focusColor[3], focusColor[4] = unpack(oriFocusColor)
	pressedColor[1], pressedColor[2], pressedColor[3], pressedColor[4] = unpack(oriPressedColor)
	control:Invalidate()
	selected = false
	LBPressed = false
	mirrorH, mirrorV = 1, 1

	return true
end

local function Select(obj)
	Deselect()
	selected = obj
	local control = obj.control
	local bgColor, focusColor, pressedColor = control.backgroundColor, control.focusColor, control.pressBackgroundColor
	local r,g,b,a = unpack(selectedColor)
	bgColor[1], bgColor[2], bgColor[3], bgColor[4] = r, g, b, a
	focusColor[1], focusColor[2], focusColor[3], focusColor[4] = r, g, b, a
	pressedColor[1], pressedColor[2], pressedColor[3], pressedColor[4] = r, g, b, a
	control:Invalidate()
	return true
end


local totalHeight -- keep track of the total height because we don't update the client area after each change but at the end
local function AddControl(obj, index)
	local backgroundColor = {0.3,0.3,0.3,1}
	local w = buttonWidth 
	local wmargin = buttonPadding[1] + buttonPadding[3]-- FIXME count the button's item margin correctly
	local hmargin = buttonPadding[2] + buttonPadding[4]-- FIXME count the button's item margin correctly
	local hratio =  (obj.midy+1) / (obj.midx+1)
	-- for reducing image when height ratio is too big and repositionning at the middle of the button
	local reduce = 1
	if hratio > 2 then
		reduce = 2 / hratio
		hratio = 2
	end
	local h = (w - wmargin) * (hratio) + hmargin
	h = math.floor(h + 0.5)
	local y
	local off = 0
	local control = WG.Chili.Button:New{
		caption = '',
		tooltip = obj.filename,
		y = y,
		width = w,
		height = h,
		-- width = '100%',
		-- height = '100%',
		backgroundColor = backgroundColor,
		padding = buttonPadding,
		OnMouseDown = {	function(self) Select(obj) end },
		children = {
			WG.Chili.Image:New{
				width = '100%',
				height = '100%',
				file = '',
				DrawControl = function(self)
					-- Echo('self.width', self.width, obj.midx * 2, obj.midx * 2 / self.width)
					-- Echo("self.clientArea[4] is ", unpack(self.clientArea))
					local ratio = self.width / ((obj.midx+1) * 2)
					gl.PushMatrix()
					gl.Color(1,1,1,0.5)
					gl.Scale(ratio * reduce, ratio * reduce, 1)
					gl.Translate((obj.midx+1) / reduce, (obj.midy+1), 0)
					gl.Scale(1,-1,1)
					gl.CallList(obj.list)
					gl.PopMatrix()
				end,
			}
		}
	}
	-- control:AddChild(image)
	selector:AddChild(control, false, index)
	if not oriBGColor then
		oriBGColor = {unpack(control.backgroundColor)}
		oriFocusColor = {unpack(control.focusColor)}
		oriPressedColor = {unpack(control.pressBackgroundColor)}
		local r,g,b,a = unpack(control.focusColor)
		selectedColor = MakeSelectedColor(r,g,b,a)
	end
	obj.control = control
	-- local lastChild = selector.children[#selector.children]
	-- win:SetPos(nil, nil, nil, lastChild.y + lastChild.height + 45)
	-- selector:SetPos(nil, nil, nil, lastChild.y + lastChild.height + 12)
	taskTime = 0
end

local lastTimeY
local lastHeight
local paddingBot = -2

local function MakeSelector()
	local lastHeight
	selector = WG.Chili.StackPanel:New{
		y = 0,
		width = "100%",
		bottom = 0,
		padding = {0,0,0,0},
		itemMargin = {0, 0, 0, paddingBot},
  		itemPadding   = {0, 0, 0, 0},
		resizeItems = false,
		centerItems = false,
		autosize = true,
		-- autoArrangeV = true,
		orientation   = "vertical",
		preserveChildrenOrder = true,
		OnResize = {
			function(self)
				if lastHeight == self.height  or self.height <= 10 then
					return -- avoid spam
				end
				local now = os.clock()
				lastHeight = self.height
				local off = scroll.y + win.padding[2] + scroll.bottom + win.padding[4]
				local newWinHeight = self.height + off
				local totalHeight = newWinHeight
				local children = self.children
				local clen = #children
				if clen >= 2 then -- avoid working during spam of useless resize
					local lastChildY = children[clen].y
					if lastChildY == 0 or newWinHeight < lastChildY then
						return -- avoid spam
					end
				end
				local children = selector.children
				local lastY, lastObj, lastI, opt
				local scrollbar = false
				for i = clen, 1, -1 do
					local child = children[i]
					if child.y  + (off - paddingBot) > MAX_WIN_HEIGHT then
						lastY = child.y
						scrollbar = true
					else
						if not lastY then
							lastY = child.y + child.height
						end
						break
					end
				end
				if lastY then
					if lastY == lastTimeY then
						-- avoid spam
						return
					end
					newWinHeight = lastY - paddingBot + off

					if win.maxHeight == newWinHeight then
						lastTimeY = lastY
						return
					end
				end
				if newWinHeight > MAX_WIN_HEIGHT then
					win.maxHeight = newWinHeight
				else
					win.maxHeight = MAX_WIN_HEIGHT
				end
				lastTimeY = lastY
				if newWinHeight and win.height ~= math.min(newWinHeight, win.maxHeight) then
					local selWidth = buttonWidth + (scrollbar and scroll.scrollbarSize or 0)
					local winWidth = selWidth + 23
					if winWidth == win.width then
						winWidth = nil
						selWidth = nil
					end
					win:SetPos(nil, nil, winWidth, math.min(newWinHeight, win.maxHeight))
					if selWidth then
						scroll:SetPos(nil,nil,selWidth)
					end
				end
			end
		},
		children = {},
	}
	scroll = WG.Chili.ScrollPanel:New{
		y = 14,
		width = buttonWidth,
		bottom = 10,
		padding = {0,0,0,0},
		itemPadding = {0,0,0,0},
		itemMargin = {0,0,0,0},
		horizontalScrollbar = false,
		orientation   = "vertical",
		children = {
			selector
		},
	}


	


	win = WG.Chili.Window:New{
		parent = WG.Chili.Screen0,
		caption = 'Marker Selector',
		x = vsx - (buttonWidth + 23 + 4),
		y = 200,
		height = 0,
		padding = {12,7,5,5},
		resizable = false,
		maxHeight = 200,
		width = buttonWidth + 23,
		children = {
			scroll
		}
	}
	if not alwaysUp then
		local alt, ctrl, meta, shift = Spring.GetModKeyState()
		if not (ctrl and alt) then
			win:Hide()
		end
	end
end

local function SaveLines(lines, file)
	local jsonstring = json.encode(lines)
	if jsonstring then
		-- local jsonfile = file:sub(1, (file:find('%.[^%.]+$') or 0) - 1)  .. '.json'
		local jsonfile = file  .. '.json'
		local f = io.open(jsonfile, "w")
		f:write(jsonstring)
		f:close()
	end
end

local function LoadLines(file)
	-- local jsonfile = file:sub(1, (file:find('%.[^%.]+$') or 0) - 1)  .. '.json'
	local jsonfile = file  .. '.json'
	local obj = io.open(jsonfile, "r")
	if obj then

		local success, lines = pcall(json.decode, obj:read('*a'))
		if not success then
			Echo('couldn\'t load the json file ' .. jsonfile)
		else
			local add = {}
			for k,v in pairs(lines) do
				if type(k) == 'string' and tonumber(k) then
					lines[k] = nil
					-- lines[tonumber(k)] = v
					add[k] = v
				end
			end
			for k,v in pairs(add) do
				lines[tonumber(k)] = v
			end
		end
		obj:close()
		return lines
	end
end


local function AddLineObj(lines, file, index, isLoaded)
	if not isLoaded then
		lines.file = file
		lines.filename = file:gsub(drawingsDir, '')
		local size = 0
		local read = io.open(file, 'r')
		if read then
			size = read:seek('end')
			read:close()
		end
		lines.size = size
		SaveLines(lines, file)
	end

	index = index or #holder+1
	lines.index = index
	lines.list = gl.CreateList(
		gl.BeginEnd,
		GL.LINES,
		function()
			for _, line in ipairs(lines) do
				glVertex(line[1], line[2], 0)
				glVertex(line[3], line[4], 0)
			end
		end
	)
	holder[index] = lines
	holder[file] = lines

	AddControl(lines, index)
end

local function AddNewContouredImage(file, index)
	local raster = GetRaster(file)
	if not raster then
		Echo('[' .. widget:GetInfo().name .. '] file ' .. file .. ' couldn\'t get loaded')
	else
		local contours = AcquireContours(raster)
		if not contours then
			Echo('[' .. widget:GetInfo().name .. '] file ' .. file .. ' couldn\'t make any contour')
		else
			local f
			for i, contour in ipairs(contours) do
				if contour.filling then
					if not f then
						f = i
					end
				else
					if f then
						contours[i], contours[f] = contours[f], contours[i]
						if contours[f+1].filling then
							f = f + 1
						end
					end
				end

			end
			SimplifyContours(contours)
			if DEBUG_CONTOUR then
				for i, line in ipairs(raster) do
					local txt = ''
					for i, color in ipairs(line) do
						txt = txt .. string.color(color) .. (color.txt or 'XX')
					end
					Echo(i..txt)
				end
			end
			local lines = ContourToLineObj(contours)
			lines.mode = mode
			lines.smooth = angleSmoothness
			AddLineObj(lines, file, index)
		end
	end
end

local function AddNewImage(file, index)
	local lines = ImageToLineObj(file)
	lines.mode = mode
	lines.smooth = angleSmoothness
	-- l = FuseMiniLines(lines, l, 9)
	-- FillGaps(lines, l, 12)
	AddLineObj(lines, file, index)
end

local function RemoveLineObj(obj, file)
	holder[file] = nil
	-- local y = obj.control.y
	selector:RemoveChild(obj.control)
	if obj.list then
		gl.DeleteList(obj.list)
	end
end

function Init()
	if not selector then
		MakeSelector()
	end
	tasks = {}
	taskTime = 0

	for file, obj in pairs(holder) do
		RemoveLineObj(obj, file)
	end
	initialized = true
end

local function ObjectMatch(obj)
	local wrong = obj.mode ~= mode or obj.smooth ~= angleSmoothness
	if not wrong then
		local file = obj.file
		local size = 0
		local read = io.open(file)
		if read then
			size = read:seek('end')
			read:close()
		end
		wrong = size ~= obj.size
	end
	return not wrong
end

local function UpdateFiles()
	local files = VFS.DirList(drawingsDir, '{*.png,*.jpg,*.jpeg,*.tif,*.tiff}')

	local count = 0
	for i, file in ipairs(files) do
		count = count + 1
		files[file] = true
		local obj = holder[file]
		local loaded
		local toAdd
		if not obj then
			toAdd = true
			loaded = LoadLines(file)
			if loaded and not ObjectMatch(loaded) then
				loaded = nil
			end
		else
			if not ObjectMatch(obj) then
				RemoveLineObj(obj, file)
				toAdd = obj.index
			end
		end
		if toAdd then
			local index = tonumber(toAdd)
			if loaded then
				AddLineObj(loaded, file, index, true)
			elseif mode == 'contour' or mode == 'spaghetti' then
				tasks[file] = {AddNewContouredImage, index}
				-- AddNewContouredImage(file, index)
			else
				tasks[file] = {AddNewImage, index}
				-- AddNewImage(file, index)
			end
		end
	end
	if holder[count + 1] then -- some file got deleted
		for file, obj in pairs(holder) do
			if type(file) ~= 'number' then
				if not files[file] then
					RemoveLineObj(obj, file)
				end
			end
		end
	end
end

--- Callins


function widget:KeyPress(key, mods, isRepeat)
	if isRepeat then
		return
	end
	if mods.ctrl and mods.alt then
		if win and win.hidden then
			win:Show()
		end
	elseif not (alwaysUp or win and win.hidden) then
		win:Hide()
	end
end
function widget:KeyRelease(key, mods)
	if deselectOnRelease and not mods.shift then
		deselectOnRelease = false
		Deselect()
	end
	if not (mods.ctrl and mods.alt) then
		if not (alwaysUp or win and win.hidden) then
			win:Hide()
		end
	end
end
local l, len = 0, 0
local t = 0
local toDraw = {}
local PENDING = {}
local glVertex = gl.Vertex


local toCome = function(start, End)
	for i = start, End do
		local line = toDraw[i]
		local c1, c2 = line[1], line[2]
		glVertex(c1[1], c1[2], c1[3])
		glVertex(c2[1], c2[2], c2[3])
	end
end
local drawing

local function OrderDraw(mx, my, mirrorH, mirrorV)
	local pending = false
	if len > 0 then
		pending = len + 1
	end
	len = SetupCoords(mx, my, selected, toDraw, len, mirrorH, mirrorV)
	if pending then
		PENDING[pending] = gl.CreateList(gl.BeginEnd, GL.LINES, toCome, pending, len)
	end
	drawing = true
	-- Echo('lines ready', len)

	if not select(4, spGetModKeyState()) then -- not shift, don't keep it selected
		Deselect()
	else
		deselectOnRelease = true
	end	
end


function widget:MousePress(mx, my, button)
	if button == 3 then
		if selected then
			if LBPressed then -- fix the widget keeping wrongly ownership of the mouse
				if widgetHandler.mouseOwner == widget then
					widgetHandler.mouseOwner = nil
				end
			end
			Deselect(selected)
			return true
		end
	elseif button == 1 then
		if LBPressed then
			return
		end
		if selected and not WG.Chili.Screen0:IsAbove(mx, my) then
			LBPressed = 0
			LBx, LBy = mx, my
			return true
		end
	end
end

function widget:Update(dt)
	if LBPressed then
		local mx, my, lb = Spring.GetMouseState()
		if lb then
			mirrorH = mx - LBx < -10 and -1 or 1
			mirrorV = my - LBy < -10 and -1 or 1
		else
			OrderDraw(LBx, LBy, mirrorH, mirrorV)

			LBPressed = false
			mirrorH, mirrorV = 1, 1
		end
	end
	updateTime = updateTime + dt
	taskTime = taskTime + dt

	if drawing then
		t = t + dt
		if t > 0.04 then
			t = 0
			l = l + 1
			if PENDING[l] then
				gl.DeleteList(PENDING[l])
				PENDING[l] = nil
			end
			local line = toDraw[l]
			if line then
				-- Echo(line)
				local c1, c2 = unpack(line)
				spMarkerAddLine(c1[1], 0, c1[3], c2[1], 0, c2[3])
				toDraw[l] = nil
			else
				l = 0
				len = 0
				drawing = false
				-- Echo('done')
			end
		end
	end
end



local frame = gl.CreateList( -- unused
	function()
		gl.Shape(GL.LINES, {
			{v={-1,0.5,0}}, {v={-1,1,0}},
			{v={-1,1,0}}, {v={-0.5,1,0}},

			{v={1,0.5,0}}, {v={1,1,0}},
			{v={1,1,0}}, {v={0.5,1,0}},

			{v={-1,-0.5,0}}, {v={-1,-1,0}},
			{v={-1,-1,0}}, {v={-0.5,-1,0}},

			{v={1,-0.5,0}}, {v={1,-1,0}},
			{v={1,-1,0}}, {v={0.5,-1,0}},
			 
		})
	end
)
function widget:DrawWorld()
	for _, list in pairs(PENDING) do
		gl.CallList(list)
	end
end
function widget:DrawScreen()
	if not initialized then
		Init()
		UpdateFiles()
		updateTime = updateDelay
	end
	if updateTime >= updateDelay then
		UpdateFiles()
		updateTime = 0
	end
	if taskTime >= taskDelay then
		local file, t = next(tasks)
		if file then
			local func, index = unpack(t)
			func(file, index)
			tasks[file] = nil
		end
		taskTime = 0
	end

	if selected then
		local mx, my  = spGetMouseState()
		gl.PushMatrix()
		if LBPressed then
			gl.Translate(LBx,LBy,0)
		else
			gl.Translate(mx,my,0)
		end
		gl.Scale(mirrorH, mirrorV, 1)
		gl.CallList(selected.list)
		-- show a frame
			-- gl.Scale(selected.midx, selected.midy, 1)
			-- gl.CallList(frame)
		--
		gl.PopMatrix()
	end
	-- gl.Texture(0, imageFile)
	-- local info = gl.TextureInfo(imageFile)
	-- gl.TexRect(0, 0, info.xsize, info.ysize)
	-- gl.Texture(0, false)


	-- if holder[1] then
	-- 	local lines = holder[1]
	-- 	gl.PushMatrix()
	-- 	-- gl.Translate(vsx - lines.midx-1, lines.midy, 0)
	-- 	gl.Translate(500, 500, 0)
	-- 	gl.LineStipple(false)
	-- 	gl.CallList(lines.list)
	-- 	gl.PopMatrix()
	-- end
	
end

function widget:Shutdown()
	for _, obj in ipairs(holder) do
		if obj.list then
			gl.DeleteList(obj.list)
		end
	end
	for _, list in pairs(PENDING) do
		gl.DeleteList(list)
	end
	gl.DeleteList(frame)
end
if f then
	f.DebugWidget(widget)
end

