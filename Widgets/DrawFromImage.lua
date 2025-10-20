function widget:GetInfo()
	return {
		name      = "Draw Marker From Image",
		desc      = "Place marker drawn from images, put images png/jpg/tif in the LuaUI/Widgets/Drawings dir, they get updated live during widget run"
					.."\nUse shift to place multiple, right click to cancel."
					.."\nRight click on marker object to customize each one of them"
					.."\nClick on map and drag: left to mirror horizontally, down to mirror vertically."
					.."\nImages are stored as json file for faster loading"
					.."\nRename files ('category_filename.jpg') to implement jumpable categories "
					.."\nUI can be hidden and shown when Ctrl + Alt is pushed",
		author    = "Helwor",
		date      = "Dec 2023",
		license   = "GNU GPL, v2 or later",
		layer     = - 10e35,
		enabled   = true,  --  loaded by default?
		-- api       = true,
		handler   = true,
	}
end
if not _G then 
	_G = getfenv(loadstring(''))
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
local glReadPixels = gl.ReadPixels

local vsx, vsy = widgetHandler:GetViewSizes()

local drawingsDir = "LuaUI\\Widgets\\Drawings\\"

local MarkerMaker = {} -- class
MarkerMaker.mt = {__index = MarkerMaker}
local customPanel

local categories = {byKey = {}, scrollPoses = {}, controls = {}, head = nil}
local updateCategories = false

local DEBUG_CONTOUR = false

-- options
local mode = 'contour'
local pix_detect = 0.5 -- any rgb color below this value will accept a pixel as valid, any alpha value below (1-pix_detect) will deny it
local analyse_size = 330 -- the diagonal of the image is extended to this in order to improve the contour making
local onscreen_size = 150 -- the final result on screen as marker is reshrinked by this multiplicator
local angle_tolerance = 0.05
local always_up = true
local placing_frame = false
--

local showMultFrame = false
local showFrame = false
local buttonWidth = 75
local COUNT_FOR_ANGLE = 3
local PRECISION = 0.5
local MAX_WIN_HEIGHT = 300 -- adaptative win height to fit the last thumbnail size

local drawing
local currentMarkerLine, markerLines = 0, 0
local markerTime = 0
local markerDelay = 0.04
local toDraw = {}
local pendingLists = {}

-- hax to customize selected button appearance
local oriBGColor
local oriFocusColor
local oriPressedColor
local selectedColor
local buttonPadding = {5,10,5,10}
local function MakeSelectedColor(r,g,b,a)
	-- return {1, g * 0.8, b * 0.8, a * 1.5}
	return {r * 0.5, g * 2, b * 0.5, a * 1.5}
end
function hyp_to_side(hyp) -- from hypothenus to side (assuming a square ofc)
	return (hyp^2 / 2)^0.5
end
--
local holder = {}
local tasks = {}
local selector, win, scroll
local deselectOnRelease = false
local selected = false
local customize = false
local initialized = false
local Init, UpdateScreenRatio
local curScrollPosY = false
local updateTime = 0
local updateDelay = 3
local taskTime = 0
local taskDelay = 1
local vsx, vsy = Spring.GetViewGeometry()

options_path = 'Hel-K/'..widget:GetInfo().name
options_order = {'always_up','placing_frame', 'note', 'mode', 'pix_detect', 'analyse_size', 'onscreen_size', 'angle_tolerance'}
options = {}


options.always_up = {
	name = 'Always Up',
	desc = 'Always show the UI without key pressed Ctrl + Alt',
	type = 'bool',
	value = always_up,
	OnChange = function(self)
		always_up = self.value
		if win then
			if not always_up then
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

options.placing_frame = {
	name = 'Show Placing Frame',
	desc = 'Useful when you plan have to mirror the image and you\'re unsure where it will land',
	type = 'bool',
	value = placing_frame,
	OnChange = function(self)
		placing_frame = self.value
	end,

}

options.note = {
	name = 'NOTE:',
	type = 'text',
	value = 'Options below are globals.\nEach marker object can be customized separately by Right Click.\n',
}

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
	end,
}


options.pix_detect = {
	name = 'Pixel Detection',
	type = 'number',
	min = 0.01,	max = 0.99,	step = 0.01,
	value = pix_detect,
	desc = 'Sensibility to detect pixels that will be drawn, one of the pixel\'s color must be under this value to be detected, if it is semi transparent, the alpha channel must also be superior to (1-value)',
	OnChange = function(self)
		pix_detect = self.value
		initialized = false
	end,
}

options.analyse_size = {
	name = 'Analyse Size',
	type = 'number',
	min = 50, max = 800, step = 10,
	value = analyse_size,
	desc = 'Definition of the image we work on, can help especially when using Contour mode, avoid upping it using Spaghetti as it will make too many lines',
	OnChange = function(self)
		analyse_size = self.value
		initialized = false
	end,
}

options.onscreen_size = {
	name = 'Onscreen Size',
	type = 'number',
	min = 50, max = 600, step = 10,
	value = onscreen_size,
	desc = 'Final size on screen',
	OnChange = function(self)
		showFrame = false
		if self.value ~= onscreen_size then
			onscreen_size = self.value
			for i, obj in ipairs(holder) do
				if self.use_default then
					obj:SetScreenRatio()
				end
			end
		end
	end,

	tooltipFunction = function(self)
		if initialized then
			showFrame = self.value
		end
		return self.value
	end,
}

options.angle_tolerance = {
	name = 'Simplify Angle Tolerance',
	type = 'number',
	min = 0.000, max = 0.1, step = 0.005,
	value = angle_tolerance,
	desc = 'How much difference of angle we tolerate before creating a new segment, works only for Contour and Spaghetti mode',
	OnChange = function(self)
		angle_tolerance = self.value
		initialized = false
	end,
}


local function ReturnSelf(self)
	return self
end

local SortByLength = function(a, b)
	return #a > #b
end
--- making Rotator clockwise usage: rotateClock[x][z] = rotatedCoords
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

local rotateClock = setmetatable(
	{},
	{
		__index = function(self, k) 
			local t = {}
			rawset(self, k, t)
			return t
		end
	}
)
local clockCoords, r = {}, 0
local add = function(_, x, z)
	r = r + 1
	clockCoords[r] = {z,x}
end
SpiralSquare(1, 1, add)
for i, r in ipairs(clockCoords) do
	rotateClock[ r[1] ][ r[2] ] = clockCoords[i + 1] or clockCoords[1]
end
setmetatable(rotateClock, nil)

local rotateAntiClock = setmetatable(
	{},
	{
		__index = function(self, k) 
			local t = {}
			rawset(self, k, t)
			return t
		end
	}
)
local antiClockCoords, r = {}, 0
local add = function(_, x, z)
	r = r + 1
	antiClockCoords[r] = {z,x}
end
SpiralSquare(1, 1, add, nil, true)
for i, r in ipairs(antiClockCoords) do
	rotateAntiClock[ r[1] ][ r[2] ] = antiClockCoords[i + 1] or antiClockCoords[1]
end
-- setmetatable(rotateAntiClock, nil)
--[[ verif
local function verif(_, x, z)
	local coords = rotateClock[z][x]
	Echo(x, z .. ' =>> ' .. coords[2], coords[1])
end
SpiralSquare(1, 1, verif)
--]]

-- local deg = math.deg(math.atan2(x,z))



-------
local DrawPendingMarker = function(start, End, screen_ratio)
	for i = start, End do
		local line = toDraw[i]
		local c1, c2 = line[1], line[2]
		glVertex(c1[1], c1[2], c1[3])
		glVertex(c2[1], c2[2], c2[3])
	end
end

local function HighlightCategoryHead(catHead)
	if catHead then
		local bgColor, focusColor, pressedColor = catHead.backgroundColor, catHead.focusColor, catHead.pressBackgroundColor
		bgColor[1], bgColor[2], bgColor[3] = 1, 1, 0
		focusColor[1], focusColor[2], focusColor[3] = 1, 1, 0
		pressedColor[1], pressedColor[2], pressedColor[3] = 1, 1, 0 
		catHead:Invalidate()
	end
	if categories.head then
		local oldHead = categories.head
		local oldHeadColor, oldHeadFocus, oldHeadPressed = oldHead.backgroundColor, oldHead.focusColor, oldHead.pressBackgroundColor
		oldHeadColor[1], oldHeadColor[2], oldHeadColor[3] = unpack(oriBGColor)
		oldHeadFocus[1], oldHeadFocus[2], oldHeadFocus[3] = unpack(oriFocusColor)
		oldHeadPressed[1], oldHeadPressed[2], oldHeadPressed[3] = unpack(oriPressedColor)
		oldHead:Invalidate()
	end
	categories.head = catHead
end

local function MakeCategories()
	local files = VFS.DirList(drawingsDir, '{*.png,*.jpg,*.jpeg,*.tif,*.tiff}')
	local byKey = {}
	local newCats = {}
	local lastCat
	local c = 0
	for i, file in ipairs(files) do
		if not holder[file] then -- wait for it to be added
			return
		end
		local filename = file:gsub(drawingsDir, '')
		local cat = filename:match('^([%a]+)_')
		if cat and cat ~= lastCat then
			byKey[cat] = file
			c = c + 1
			newCats[c] = cat
			lastCat = cat
		end

	end
	local beNew = false

	for cat, file in pairs(byKey) do
		if categories.byKey[cat] ~= file then
			beNew = true
			break
		end
	end
	for cat, file in pairs(categories.byKey) do
		if byKey[cat] ~= file then
			beNew = true
			break
		end
	end
	if not beNew and categories[1] and not newCats[1] then
		beNew = true
	end
	local y = win.height - win.padding[2] - win.padding[4] - scroll.clientArea[4] - scroll.bottom
	local bheight = (scroll.clientArea[4] - 1) / c + 1
	if beNew then
		local scrollPoses = {}
		local controls = {}	
		for i = #categories, 1, -1 do
			win:RemoveChild(categories.controls[i])
			categories[i] = nil
		end
		for i, cat in ipairs(newCats) do
			local obj = holder[ byKey[cat] ]
			if obj then
				local ctrl = obj.control
				scrollPoses[i] = select(2, ctrl:ClientToParent(ctrl.x, ctrl.y)) / 2
				local control = WG.Chili.Button:New{
					caption = cat:sub(1,2),
					tooltip = cat,
					x = 1,
					y = y,
					width = 13,
					height = bheight,
					OnClick = {
						function(self)
							scroll:SetScrollPos(nil, scrollPoses[i], nil, true)
						end
					}
				}
				win:AddChild(control)
				controls[i] = control
				y = y + bheight - 1
			end
		end
		newCats.byKey = byKey
		newCats.scrollPoses = scrollPoses
		newCats.controls = controls

		categories = newCats
	else
		local scrollPoses = categories.scrollPoses
		local byKey = categories.byKey
		for i, cat in ipairs(categories) do
			local obj = holder[ byKey[cat] ]
			if obj then
				local ctrl = obj.control
				scrollPoses[i] = select(2, ctrl:ClientToParent(ctrl.x, ctrl.y)) / 2
			end
		end
		local controls = categories.controls
		if controls[1] and controls[1].height ~= bheight then
			for i, control in ipairs(controls) do 
				control:SetPosRelative(nil, y, nil, bheight, clientArea, dontUpdateRelative)
				y = y + bheight - 1
			end
		end
	end
end

local totalHeight -- keep track of the total height because we don't update the client area after each change but at the end
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
		x = 15,
		y = 14,
		width = buttonWidth,
		bottom = 10,
		padding = {0,0,0,0},
		itemPadding = {0,0,0,0},
		itemMargin = {0,0,0,0},
		horizontalScrollbar = false,
		orientation   = "vertical",
		Update = function(self, ...)
			if curScrollPosY then -- fix update of window marker controls getting moved
				scroll:SetScrollPos(nil, curScrollPosY, nil, true)
				curScrollPosY = false
				return WG.Chili.ScrollPanel.Update(self, ...)
			end
			local currentScrollPosY = self.scrollPosY
			-- find the category button before the current pos and highlight it
			local catHead
			if self.contentArea and currentScrollPosY == self.contentArea[4] - self.clientArea[4] then
				catHead = categories.controls[#categories.controls]
			else
				for i, scrollPosY in ipairs(categories.scrollPoses) do
					if scrollPosY <= (currentScrollPosY + 5) then
						catHead = categories.controls[i]
					else
						break
					end
				end
			end
			if catHead then
				if categories.head ~= catHead then
					HighlightCategoryHead(catHead)
				end
			elseif categories.head then
				HighlightCategoryHead(nil)
			end
			return WG.Chili.ScrollPanel.Update(self, ...)
		end,

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
		padding = {0,7,5,5},
		resizable = false,
		maxHeight = 200,
		width = buttonWidth + 23,
		OnResize = {
			function(self)
				updateCategories = 0
				curScrollPosY = scroll.scrollPosY
			end
		},
		OnClick = {
			function()
				if select(3, Spring.GetModKeyState()) then
					WG.crude.OpenPath(widget.options_path)
					return true
				end
			end
		},
		children = {
			scroll
		}
	}
	if not always_up then
		local alt, ctrl, meta, shift = Spring.GetModKeyState()
		if not (ctrl and alt) then
			win:Hide()
		end
	end
end

local function MakeCustomizationPanel()

	local cp = {}
	local win_width = 600
	local win_height = 350

	local panel_bottom = 30
	local panel_top = 15
	local panel_right = 5
	local panel_left = 5
    local button_height = 20

    local color_text = {1,1,1,1}
    local color_header = {1,1,0,1}


    local panel_col_width = (win_width - panel_left - panel_right) / 2
    local left = 10


    local y = 0

    cp.useDefault = WG.Chili.Checkbox:New{
		x = left,
		y = y,
		width = "48%",
		left = left,
		-- right = panel_col_width,
		defaultHeight = 22,
		caption = 'Use Default',
		checked = true,
		OnChange = {
			function(self)
				cp.SwitchCustom(self.checked)
				if customize then
					customize.useDefault = not self.checked
					if not customize:IsConform() then
						customize:FastUpdate()
					else
						-- saving the change in json, since there will be no new obj created
						customize:Save()
					end
				end
			end
		},
        tooltip = 'Ignore customization, but keep it memorized'
        		  ..'\nDefault values are:'
        		  ..'\nMode: ' .. mode
        		  ..'\nPixel Detection: ' .. pix_detect
        		  ..'\nAnalyse Size: ' .. analyse_size
        		  ..'\nOnScreen Size: ' .. onscreen_size
        		  ..'\nAngle Tolerance: ' .. angle_tolerance,
        HitTest = ReturnSelf,

	}


	y = y + 25
    cp.header_mode = WG.Chili.Label:New{
    	y = y,
		x = left,
		width = "48%",
        caption = 'Modes',
        textColor = color_header,
        -- align='leftr',
    }

	local modes = {}
	cp.modes = modes
	local ignoreOnChange = false
	for i, m in ipairs{'Contour', 'Spaghetti', 'Plain'} do
		y = y + 15
		local cb = WG.Chili.Checkbox:New{
			x = left,
			-- right = panel_col_width,
			y = y,
			width = "48%",
			caption = '   ' .. m,
			textColor = color_text,
			checked = m:lower() == mode,
			OnChange = {function(self)
				if ignoreOnChange then
					ignoreOnChange = false
					return
				end
				if self.checked then -- nothing to do
					self.checked = false -- makes it rechecked actually
					return 
				end
				for j, cb in ipairs(modes) do
					if i ~= j  and cb.checked then
						ignoreOnChange = true
						cb:Toggle()
					end
				end
				if customize then
					customize.mode = m:lower()
					-- Echo('mode set to', m:lower())
					if not customize.useDefault then
						customize:FastUpdate()
					else
						customize:Save()
					end
				end
			end},
			tooltip = "",
			round = true,
		}
		modes[i] = cb
	end


	y = y + 25
	cp.header_pix_detect = WG.Chili.Label:New{
		y = y,
		x = left,
		width = "48%",
        caption = 'Pixel Detection',
        tooltip = 'Sensibility to detect pixels that will be drawn, one of the pixel\'s color must be under this value to be detected, if it is semi transparent, the alpha channel must also be superior to (1-value)',
        HitTest = ReturnSelf,

        textColor = color_header,
    }

	y = y + 15
	cp.pix_detect = WG.Chili.Trackbar:New{
		x = left,
		y = y,
		width = "48%",
		-- right = panel_col_width,
		value = pix_detect,
		trackColor = color_text, -- trackColor has not been implemented yet
		min = 0.01,
		max = 0.99,
		step = 0.01,
		OnMouseUp = {
			function(self)
				if customize then
					-- Echo('mouse up', self.value, 'customize', customize, customize.pix_detect, customize.spix_detect)
				end
				if customize then
					if customize.pix_detect ~= self.value then
						customize.pix_detect = self.value
						if not customize.useDefault then
							customize:FastUpdate()
						else
							customize:Save()
						end
					end
				end
			end
		},
	}


	y = y + 25
	cp.header_analyse_size = WG.Chili.Label:New{
		y = y,
		x = left,
		width = "48%",
        caption = 'Analyse Size',
        textColor = color_header,
        tooltip = 'Definition of the image we work on, can help especially when using Contour mode, avoid upping it using Spaghetti as it will make too many lines',
        HitTest = ReturnSelf,
    }

	y = y + 15

	cp.analyse_size = WG.Chili.Trackbar:New{
		x = left,
		y = y,
		width = "48%",
		-- right = panel_col_width,
		value = analyse_size,
		trackColor = color_text,
		min = 50, max = 800, step = 10,
		OnMouseUp = {
			function(self)
				if customize then
					if customize.analyse_size ~= self.value then
						customize.analyse_size = self.value
						if not customize.useDefault then
							customize:FastUpdate()
						else
							customize:Save()
						end
					end
				end
			end
		},
		-- useValueTooltip = not option.tooltipFunction,
		-- tooltipFunction = option.tooltipFunction,
		-- tooltip_format = option.tooltip_format,
	}

	y = y + 25
	cp.header_onscreen_size = WG.Chili.Label:New{
		x = left,
		y = y,
		width = "48%",
        caption = 'Onscreen Size',
        textColor = color_header,
        tooltip = 'Final size on screen',
        HitTest = ReturnSelf,

        -- align='leftr',
    }

	y = y + 15
	cp.onscreen_size = WG.Chili.Trackbar:New{
		x = left,
		y = y,
		width = "48%",
		-- right = panel_col_width,
		value = onscreen_size,
		trackColor = color_text,
		min = 50, max = 600, step = 10,
		OnMouseUp = {
			function(self)
				if customize then
					if customize.onscreen_size ~= self.value then
						customize.onscreen_size = self.value
						if not customize.use_default then
							customize:SetScreenRatio()
							customize:Save()
							showMultFrame = 1
						end
					end
				end
			end
		},
		tooltipFunction = function(self)
			if customize then
				showMultFrame = self.value / customize.onscreen_size
			end
			return self.value
		end,
		OnMouseOver = {function(self)
			if customize then
				showMultFrame = self.value / customize.onscreen_size
			end
		end},
		OnMouseOut = {function()
			showMultFrame = false end
		}
	}

	y = y + 25
	cp.header_angle_tolerance = WG.Chili.Label:New{
		x = left,
		y = y,
        caption = 'Angle Tolerance',
        width = "48%",
        textColor = color_header,
        tooltip = 'How much difference of angle we tolerate before creating a new segment, works only for Contour and Spaghetti mode',
        HitTest = ReturnSelf,
    }

	y = y + 15
	cp.angle_tolerance = WG.Chili.Trackbar:New{
		x = left,
		y = y,
		width = "48%",
		-- right = panel_col_width,
		min = 0.000, max = 0.1, step = 0.005,
		value = angle_tolerance,
		trackColor = color_text,
		OnMouseUp = {
			function(self)
				if customize then
					if customize.angle_tolerance ~= self.value then
						customize.angle_tolerance = self.value
						if not customize.useDefault and customize.mode ~= 'plain' then
							customize:FastUpdate()
						else
							customize:Save()
						end
					end
				end
			end
		},
	}

	y = y + 25
	cp.reset_defaults = WG.Chili.Button:New{
		x = left,
		y = y,
		width = 150,
		-- right = panel_col_width,
		caption = 'Reset Customization',
		tooltip = 'return to default values:'
        		  ..'\nMode: ' .. mode
        		  ..'\nPixel Detection: ' .. pix_detect
        		  ..'\nAnalyse Size: ' .. analyse_size
        		  ..'\nOnScreen Size: ' .. onscreen_size
        		  ..'\nAngle Tolerance: ' .. angle_tolerance,
		trackColor = color_text,
		OnClick = {
			function(self)
				if customize then
					for i, m in ipairs({'contour', 'spaghetti', 'plain'}) do
						if mode == m then
							if not cp.modes[i].checked then
								cp.modes[i]:Toggle()
							end
							break
						end
					end
					local defaults = {pix_detect, analyse_size, onscreen_size, angle_tolerance}
					for i, opt in ipairs({'pix_detect', 'analyse_size', 'onscreen_size', 'angle_tolerance'}) do
						if math.abs(cp[opt].value - defaults[i]) > 1e-6 then -- value of angle_tolerance can differ a tiny bit when getting digested by the trackbar control
							cp[opt]:SetValue(defaults[i])
							cp[opt].OnMouseUp[1](cp[opt])
						end
					end
					showMultFrame = false
				end
			end
		},
	}

--
	local function CreateMarkerImage()
	    cp.marker_image = WG.Chili.Image:New{
			file = '',
			DrawControl = function(self)
				-- Echo('draw control', os.clock())
				local obj = customize
				if obj and obj.list then
					-- FIXME NOT PERFECT
					-- Echo("obj.win.contentArea is ", unpack(cp.win.clientArea))
					-- Echo("cp.scroll_panel.contentArea is ", unpack(cp.scroll_panel.clientArea))
					local ca = cp.scroll_panel.clientArea
					-- local col_width = ca[3]/2 -- - panel_left - panel_right
					local col_width = cp.win.width/2 - panel_left - panel_right
					local image_size = (col_width - 50)
					local colx = col_width + 20
					-- local wratio = obj.midx / obj.midy
					-- local hratio = obj.midy / obj.midx
					-- local width = image_size * (wratio > 1 and 1 or wratio)
					-- local height = image_size * (hratio < 1 and 1 or hratio)
					-- Echo("whratio is ", whratio,'midx, midy', obj.midx, obj.midy)
					-- Echo('width', width,'height', height)
					-- Echo("width / obj.midx, -height / obj.midy is ", width / obj.midx, -height / obj.midy)
					-- local x = col_width + (obj.midx+1)
					local y = (obj.midy+1)
					-- local ratio = width / (obj.midx*2)
					local ratio
					if obj.midx > obj.midy then
						ratio = image_size / (obj.midx*2)
					else
						ratio = image_size / (obj.midy*2)
					end
					gl.PushMatrix()
					gl.Color(1,1,1,0.5)
					-- gl.Translate(x, y*ratio, 0)
					-- gl.Scale(width / obj.midx, -height / obj.midy, 1)
					gl.Translate(colx , 0, 0)
					gl.Scale(ratio, -ratio, 1)
					gl.Translate(obj.midx , -y, 0)

					gl.CallList(obj.list)
					gl.PopMatrix()
				end
				-- local ratio = self.width / ((obj.midx+1) * 2)
				-- gl.PushMatrix()
				-- gl.Color(1,1,1,0.5)
				-- gl.Scale(ratio * reduce, ratio * reduce, 1)
				-- gl.Translate((obj.midx+1) / reduce, (obj.midy+1), 0)
				-- gl.Scale(1,-1,1)
				-- gl.CallList(obj.list)
				-- gl.PopMatrix()
			end,

	    }
	end
	CreateMarkerImage()



--

    cp.scroll_panel = WG.Chili.ScrollPanel:New{
    	name = 'marker_custom_panel',
        x = panel_left,
        y = panel_top,
        right = panel_right,
        bottom = panel_bottom,
		orientation   = "vertical",
    }
    cp.scroll_panel:AddChild(cp.useDefault)

    cp.scroll_panel:AddChild(cp.header_mode)
    for i, ctrl in ipairs(cp.modes) do
    	cp.scroll_panel:AddChild(ctrl)
    end

    cp.scroll_panel:AddChild(cp.header_pix_detect)
    cp.scroll_panel:AddChild(cp.pix_detect)

    cp.scroll_panel:AddChild(cp.header_analyse_size)
    cp.scroll_panel:AddChild(cp.analyse_size)

    cp.scroll_panel:AddChild(cp.header_onscreen_size)
    cp.scroll_panel:AddChild(cp.onscreen_size)

	cp.scroll_panel:AddChild(cp.header_angle_tolerance)
    cp.scroll_panel:AddChild(cp.angle_tolerance)

	cp.scroll_panel:AddChild(cp.reset_defaults)
    
    cp.scroll_panel:AddChild(cp.marker_image)


    cp.closeButton = WG.Chili.Button:New{
        caption = 'Close',
        OnClick = {
        	function(self)
        		cp.win:Hide()
        		customize = false
        	end
        },
        --backgroundColor=color.sub_close_bg,
        --textColor=color.sub_close_fg,
        --classname = "navigation_button",
        
        right = 10,
        bottom = 6,
        width = 60,
        height = button_height,
    }

    cp.win = {
        x = (vsx - win_width) / 2,
        y = 200,
        name = 'marker_custom_win',
        width  = win_width,
        height = win_height,
        classname = "main_window_small_tall",
        parent = WG.Chili.Screen0,
        -- backgroundColor = color.sub_bg,
        -- resizable = false,
        caption = 'filename' .. '\'s param',
        -- minWidth = win_width,
        -- minHeight = win_height,
        children = {
            cp.scroll_panel,
            cp.closeButton,

        },
    }

    cp.RemakeImage = function()
    	cp.scroll_panel:RemoveChild(cp.marker_image)
    	CreateMarkerImage()
    	cp.scroll_panel:AddChild(cp.marker_image)
    end

    cp.SwitchCustom = function(isCustom)
    	if isCustom then
	    	for i = 1, 3 do
	    		color_text[i] = 1
	    		if i == 3 then
	    			color_header[i] = 0
	    		else
	    			color_header[i] = 1
	    		end

	    	end
	    else
	    	for i = 1, 3 do
	    		color_text[i] = 0.5
	    		color_header[i] = 0.5
	    	end
	    end
	    cp.scroll_panel:CallChildren("Invalidate")
	    cp.scroll_panel:Invalidate()
   	end

    WG.Chili.Window:New(cp.win)
    if WG.MakeMinizable then
        WG.MakeMinizable(cp.win)
    end
   	cp.SwitchCustom(false)
   	customPanel = cp 
end




function Init()
	if not selector then
		MakeSelector()
		MakeCustomizationPanel()
		customPanel.win:Hide()
	end
	tasks = {}
	taskTime = 0

	for file, obj in pairs(holder) do
		obj:Remove()
	end
	initialized = true
end


function MarkerMaker:New(file, index, params)
	-- Echo('new obj', file, index, params, params and params.mode, params and params.useDefault)
	local obj = {
		file = file,
		filename = nil,
		index = nil,
		list = nil, -- drawing list
		control = nil,
		size = nil, -- the size is used as a signature, to recognize the file

		useDefault = true,
		mode = mode,							smode = nil,
		pix_detect = pix_detect, 				spix_detect = nil,
		analyse_size = analyse_size, 			sanalyse_size = nil,
		angle_tolerance = angle_tolerance, 		sangle_tolerance = nil,
		onscreen_size = onscreen_size,

		screen_ratio = nil,

		pressed = false,
		mx = false, my = false,
		onMapDirX = 1, onMapDirY = 1,

		lines = {},
		left = nil, top = nil, right = nil, bottom = nil,
		midx = nil, midy = nil,
	}
	if params then
		obj.useDefault = params.useDefault
		obj.mode = params.mode							
		obj.angle_tolerance = params.angle_tolerance 	
		obj.analyse_size = params.analyse_size 			
		obj.onscreen_size = params.onscreen_size 		
		obj.pix_detect = params.pix_detect
		if params == customize then
			customize = obj
		end
	end
	setmetatable(obj, MarkerMaker.mt)
	local lines

	if obj.useDefault and mode == "plain" or not obj.useDefault and obj.mode == "plain" then
		lines = obj:ImageToLineObj()
	else
		lines = obj:AddNewContouredImage()
	end
	if not lines then
		return
	end
	obj.lines = lines
	
	obj:AddLineObj(index)
	if customize == obj then
		obj:SetupCustomPanel()
	end
end

function MarkerMaker:AddNewContouredImage()
	local raster = self:GetRaster()
	if not raster then
		Echo('[' .. widget:GetInfo().name .. '] file ' .. self.file .. ' couldn\'t get loaded')
	else
		local contours = self:AcquireContours(raster)
		if not contours then
			Echo('[' .. widget:GetInfo().name .. '] file ' .. self.file .. ' couldn\'t make any contour')
			self.left = 1 self.top = 50 self.right = 50 self.bottom = 1 self.midx = 25 self.midy = 25
			return {}
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
			self:SimplifyContours(contours)
			if DEBUG_CONTOUR then
				for i, line in ipairs(raster) do
					local txt = ''
					for i, color in ipairs(line) do
						txt = txt .. string.color(color) .. (color.txt or 'XX')
					end
					Echo(i..txt)
				end
			end
			local lines = self:ContourToLineObj(contours)
			return lines
		end
	end
end

function MarkerMaker:AcquireContours(raster)
	local mode = self.useDefault and mode or self.mode
	local pix_detect = self.useDefault and pix_detect or self.pix_detect
	local left, top, right, bottom = math.huge, -math.huge, -math.huge, math.huge
	local contours, c = {}, 0
	local inShape = false
	local spaghetti_mode = mode == "spaghetti"
	local modf = math.modf
	local wasContour = false
	for y, t in pairs(raster) do
		for x, pixel in pairs(t) do
			local something = pixel[4] > (1 - pix_detect) and (pixel[1] < pix_detect or pixel[2] < pix_detect or pixel[3] < pix_detect)

			if something then
				if x < left then left = x end
				if y < bottom then bottom = y end
				if x > right then right = x end
				if y > top then top = y end
				if not inShape then
					if not pixel.contour then
						c = c + 1
						-- Echo('****CONTOUR ' .. c)
						contours[c] = self:AcquireContour(pixel, y, x, 0, 1, raster, spaghetti_mode, pix_detect, c)
						if wasContour then
							contours[c].filling = true

						end
					end
				end
				inShape = not spaghetti_mode and pixel
			elseif inShape then
				if not inShape.contour then
					c = c + 1
					-- Echo('****CONTOUR AFTER ' .. c)
					contours[c] = self:AcquireContour(inShape, y, x-1, 0, -1, raster, spaghetti_mode, pix_detect, c)
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

function MarkerMaker:GetRaster()
	local file = self.file
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
	gl.Texture(0, file)
	local info = gl.TextureInfo(file)
	if not info or info.xsize == -1 then
		Echo("CAN'T LOAD FILE " .. file)
		gl.Texture(0, false)
		gl.DeleteTexture(file)
		return
	end
	-- f.Page(info)

	local analyse_size = self.useDefault and analyse_size or self.analyse_size


	local sizeX = info.xsize
	local sizeY = info.ysize
	local diag = math.diag(sizeX, sizeY)
	local mul = analyse_size / diag
	sizeX = sizeX * mul
	sizeY = sizeY * mul

	gl.TexRect(0, 0, sizeX, sizeY)
	-- FIXME gl.ReadPixels is bugged when asking a map (w > 1 and h > 1), giving values at the wrong place
	-- so we ask line by line...


	for y = sizeY-1, 0, -1 do -- y0 is at bottom
		t[y+1] = gl.ReadPixels(0, y, sizeX, 1)
	end

	gl.Texture(0, false)
	gl.DeleteTexture(file)
	return t
end

function MarkerMaker:AcquireContour(point, _y, _x, diry, dirx, raster, spaghetti_mode, pix_detect, c)
	local y, x = _y, _x
	point[1], point[2], point[3], point[4] = 0, 1, 1, 1
	-- point.txt = '0'..1
	-- point.contourStart = c
	-- Echo('START', x, y)
	local inv = false -- dirx == -1

	local join = {}
	local phase1 = true
	local lastY, lastX
	for iter = 1, 2 do
		if not phase1 then
			if lastY == y and lastX == x then
				break
			end
			inv = not inv
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
			y, x, diry, dirx, point = self:FindContourPoint(y, x, diry, dirx, raster, spaghetti_mode, pix_detect, c, i, inv)
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
	return long
end

--- Contours
function MarkerMaker:FindContourPoint(y, x, diry, dirx, raster, spaghetti_mode, pix_detect, c, index, inv)
	-- check clockwise, starting just next to the point we come from
	diry, dirx = diry * -1, dirx * -1
	local loopy, loopx
	local End = inDeadEnd and 7 or 8

	for i = 1, End do
		local dirs = inv and rotateAntiClock[diry][dirx] or rotateClock[diry][dirx]
		diry, dirx = dirs[1], dirs[2]
		local _y, _x = y + diry, x + dirx
		local point = raster[_y][_x]
		if point then
			local something = point[4] > (1 - pix_detect) and (point[1] < pix_detect or point[2] < pix_detect or point[3] < pix_detect)
			if something then
				if not point.contour or not spaghetti_mode then
					return _y, _x, diry, dirx, point
				end
			end
		end
	end
end

function MarkerMaker:SimplifyContours(contours)
	-- for debugging only
	-- local float = function(n, dec)
	-- 	return tostring(n):ftrim(dec or 2)
	-- end
	local angle_tolerance = self.useDefault and angle_tolerance or self.angle_tolerance
	local abs, diag = math.abs, math.diag
	local atan2 = math.atan2
	local remove = table.remove
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
					local devied = devAngle and devAngle > angle_tolerance -- deviation from origin of segment
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

function MarkerMaker:SetScreenRatio()
	local onscreen_size = self.use_default and onscreen_size or self.onscreen_size
	self.screen_ratio = onscreen_size / math.diag((self.midx + self.midy) * 2)
	-- self.screen_ratio = 0.2
	return
end

function MarkerMaker:ContourToLineObj(contours)
	local onscreen_size = self.useDefault and onscreen_size or self.onscreen_size
	local analyse_size = self.useDefault and analyse_size or self.analyse_size
	table.sort(contours, SortByLength)
	local lines, l = {}, 0
	local bottom, top = math.huge, -math.huge
	local left, right = math.huge, -math.huge
	for i, contour in ipairs(contours) do
		for i, coord in ipairs(contour) do 
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
			Echo(self.filename .. ' !no line at contour ' .. i)
		end
	end
	self.l = l
	local midx, midy = ((right or left) - left) / 2, (top - bottom) / 2
	self.midx, self.midy = midx, midy
	local offx, offy = -left - midx, -top + midy
	for i, line in ipairs(lines) do
		line[1], line[2], line[3], line[4] = line[1] + offx, line[2] + offy, line[3] + offx, line[4] + offy
	end

	self.lines = lines
	-- Echo('LINES', l)
	-- Echo("lines.left, lines.top, lines.right, lines.bottom is ", lines.left, lines.top, lines.right, lines.bottom)
	return lines
end


------ simple and complete process to create lines for plain mode
function MarkerMaker:ImageToLineObj()
	local file = self.file
	gl.Texture(0, file)
	local info = gl.TextureInfo(file)
	if not info or info.xsize == -1 then
		Echo("CAN'T LOAD FILE " .. file)
		gl.Texture(0, false)
		gl.DeleteTexture(file)
		return
	end
	local analyse_size, onscreen_size, pix_detect = analyse_size, onscreen_size, pix_detect
	if self.useDefault then
		analyse_size = analyse_size
		onscreen_size = onscreen_size
		pix_detect = pix_detect
	else
		analyse_size = self.analyse_size
		onscreen_size = self.onscreen_size
		pix_detect = self.pix_detect
	end
	local sizeX = info.xsize
	local sizeY = info.ysize
	local diag = math.diag(sizeX, sizeY)
	local mul = analyse_size / diag
	sizeX = sizeX * mul
	sizeY = sizeY * mul

	gl.TexRect(0, 0, sizeX, sizeY)
	local temp_screen_ratio = onscreen_size / analyse_size -- FIXME the real screen_ratio will be defined by getting the top, left, right, bottom later :(
	-- FIXME gl.ReadPixels is bugged when asking a map (w > 1 and h > 1), giving values at the wrong place
	-- so we ask line by line...
	local lines, l = {}, 0
	local left, right = math.huge, -math.huge
	local modf = math.modf
	local skip = modf(1/temp_screen_ratio) -- reduce the number of line
	if skip == 1 then
		skip = false
	end
	for y = sizeY-1, 0, -1 do -- y0 is at bottom
		if not skip or modf(y)%skip == 0 then
			local pixels = gl.ReadPixels(0, y, sizeX, 1)
			local started = false
			local line, lastX, lastY
			for x, color in ipairs(pixels) do
				local something = color[4] > (1 - pix_detect) and (color[1] < pix_detect or color[2] < pix_detect or color[3] < pix_detect)
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
	end
	gl.Texture(0, false)
	gl.DeleteTexture(file)
	if l == 0 then
		Echo('!No lines created from', file)
		self.midx = 25 self.midy = 25
		return {}
	end

	bottom, top = lines[l][2], lines[1][2]

	self.l = l

	local midx, midy = ((right or left) - left) / 2, (top - bottom) / 2
	local offx, offy = -left - midx, -top + midy
	for i, line in ipairs(lines) do
		line[1], line[2], line[3], line[4] =
			(line[1]) + offx,
			(line[2]) + offy,
			(line[3]) + offx,
			(line[4]) + offy
	end
	self.midx, self.midy = midx, midy
	return lines
end

function MarkerMaker:AddLineObj(index, isLoaded)
	self:SetScreenRatio()
	if not isLoaded then
		self.filename = self.file:gsub(drawingsDir, '')
		local size = 0
		local read = io.open(self.file, 'r')
		if read then
			size = read:seek('end')
			read:close()
		end
		self.size = size
		self:Save()
	end
	local len = #holder + 1
	if index and index < len then
		table.insert(holder, index, self)
		for i = index+1, len do
			holder[i].index = i
		end
	else
		index = len
		holder[len] = self
	end
	self.index = index
	self.list = gl.CreateList(
		gl.BeginEnd,
		GL.LINES,
		function()
			for _, line in ipairs(self.lines) do
				glVertex(line[1], line[2], 0)
				glVertex(line[3], line[4], 0)
			end
		end
	)
	
	holder[self.file] = self

	self:AddControl(index)
end




function MarkerMaker:AddControl(index)
	local obj = self
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
		tooltip = '#' .. index .. ' ' .. obj.filename,
		y = y,
		width = w,
		height = h,
		-- width = '100%',
		-- height = '100%',
		backgroundColor = backgroundColor,
		padding = buttonPadding,
		OnMouseDown = {
			function(self)
				local mx, my, lButton, _, rightButton = spGetMouseState()
				if rightButton then
					obj:SetupCustomPanel()
					customPanel.win:Show()
				else
					obj:Select()
				end
			end
		},
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
	updateCategories = 0
	scroll:UpdateLayout()
	if customize == obj then
		customPanel.RemakeImage()
	end

end

function MarkerMaker:SetupCustomPanel()
	-- Echo("self.useDefault is ", self.useDefault)
	customize = nil

	customPanel.win.caption = self.filename
	customPanel.win:Invalidate()
	if customPanel.useDefault.checked ~= self.useDefault then
		customPanel.useDefault:Toggle()
	end

	for i, m in ipairs{'Contour', 'Spaghetti', 'Plain'} do
		if self.mode == m:lower() then
			local control = customPanel.modes[i]
			if not control.checked then
				-- Echo('check mode', m)
				control:Toggle()
			end
		end
	end

	if customPanel.pix_detect.value ~= self.pix_detect then
		customPanel.pix_detect:SetValue(self.pix_detect)
	end

	if customPanel.analyse_size.value ~= self.analyse_size then
		customPanel.analyse_size:SetValue(self.analyse_size)
	end

	if customPanel.onscreen_size.value ~= self.onscreen_size then
		customPanel.onscreen_size:SetValue(self.onscreen_size)
	end

	if customPanel.angle_tolerance.value ~= self.angle_tolerance then
		customPanel.angle_tolerance:SetValue(self.angle_tolerance)
	end

	customize = self
	customPanel:RemakeImage()
end


function MarkerMaker:Select()
	if selected then
		selected:Deselect()
	end
	selected = self
	local control = self.control
	local r,g,b,a = unpack(selectedColor)
	for _, t in pairs({control.backgroundColor, control.focusColor, control.pressBackgroundColor}) do
		t[1], t[2], t[3], t[4] = r, g, b, a
	end
	control:Invalidate()
	return true
end

function MarkerMaker:Deselect()
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

	selected.pressed = false
	selected.onMapDirX, selected.onMapDirY = 1, 1

	selected = false

	return true
end

function MarkerMaker:PrepareMarker()
	if selected ~= self then
		Echo('Drawing Marker Obj Selection Mismatch !')
		return
	end
	-- create list to be drawn as preview on map when supplementary marker are pendings
	-- list is keyed in pendingList as the mark line index it will supposed to be deleted, as the correspondent marker will start to be drawn
	local pending = false
	if markerLines > 0 then
		pending = markerLines + 1
	end
	markerLines = selected:SetupCoords(markerLines, selected.screen_ratio)
	if pending then
		pendingLists[pending] = gl.CreateList(gl.BeginEnd, GL.LINES, DrawPendingMarker, pending, markerLines, selected.screen_ratio)
	end

	drawing = true
end

function MarkerMaker:SetupCoords(l, screen_ratio)
	local lines = self.lines
	local midx, midy = self.midx, self.midy
	local mx, my = self.mx, self.my
	local dirx, diry = self.onMapDirX, self.onMapDirY

	for i, line in ipairs(lines) do
		local x1, y1, x2, y2 = line[1] * (dirx or 1), line[2] * (diry or 1), line[3] * (dirx or 1), line[4] * (diry or 1)
		-- local x1, y1, x2, y2 = line[1] + mx, line[2] + my, line[3] + mx, line[4] + my
		-- onlyCoords, useMinimap, includeSky, ignoreWater
		local _, c1 = spTraceScreenRay(x1 * screen_ratio + mx, y1 * screen_ratio + my, true, false, false, false) --onlyCoords, useMinimap, includeSky, ignoreWater
		local _, c2 = spTraceScreenRay(x2 * screen_ratio + mx, y2 * screen_ratio + my, true, false, false, false)
		if c1 and c2 then
			l = l + 1
			toDraw[l] = {c1, c2}
		end
	end
	return l
end

function MarkerMaker:IsConform()
	local wrong
	if self.useDefault then
		wrong = self.smode ~= mode
			or self.sangle_tolerance ~= angle_tolerance
			or self.sPixDetect ~= pix_detect
			or self.sanalyseSize ~= analyse_size
	else
		wrong = self.smode ~= self.mode
			or self.sangle_tolerance ~= self.angle_tolerance
			or self.sPixDetect ~= self.pix_detect
			or self.sanalyseSize ~= self.analyse_size
	end
	if not wrong then
		local file = self.file
		local size = 0
		local read = io.open(file)
		if read then
			size = read:seek('end')
			read:close()
		end
		wrong = size ~= self.size
	end
	return not wrong
end

function MarkerMaker:Save()
	if self.useDefault then
		self.smode = mode
		self.sangle_tolerance = angle_tolerance
		self.sPixDetect = pix_detect
		self.sanalyseSize = analyse_size
		self.sonscreen_size = onscreen_size
	else
		self.smode = self.mode
		self.sangle_tolerance = self.angle_tolerance
		self.sPixDetect = self.pix_detect
		self.sanalyseSize = self.analyse_size
		self.sonscreen_size = self.onscreen_size
	end
	local jsonstring = json.encode(self)
	if jsonstring then
		-- local jsonfile = file:sub(1, (file:find('%.[^%.]+$') or 0) - 1)  .. '.json'
		local jsonfile = self.file  .. '.json'
		local f = io.open(jsonfile, "w")
		f:write(jsonstring)
		f:close()
	end
end

function MarkerMaker:LoadObj(file)
	-- local jsonfile = file:sub(1, (file:find('%.[^%.]+$') or 0) - 1)  .. '.json'
	local jsonfile = file  .. '.json'
	local code = io.open(jsonfile, "r")
	if code then
		local success, obj = pcall(json.decode, code:read('*a'))
		if not success then
			Echo('couldn\'t load the json file ' .. jsonfile, obj)
			code:close()
			return
		else
			local add = {}
			local lines = obj.lines
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
		code:close()
		setmetatable(obj, MarkerMaker.mt)
		return obj
	end
end

function MarkerMaker:FastUpdate()
	if holder[self.file] then -- when resetting customization, several FastUpdate will likely happen
		local newTask = {self.file, self.index, self}
		table.insert(tasks, 1, newTask)
		tasks[self.file] = newTask
		self:Remove(true)
		taskTime = taskDelay
		updateTime = 0
	end
end


function MarkerMaker:UpdateFile(file, alphaIndex)
	local obj = holder[file]
	local loaded
	local toAdd
	local customParams
	local conform
	if not obj then
		toAdd = true
		loaded = self:LoadObj(file)
		if loaded then
			conform = loaded:IsConform()
			-- Echo('loaded check', conform, "loaded.useDefault", loaded.useDefault, 'loaded.mode', loaded.mode, 'loaded.smode', loaded.smode)
			if not conform then
				customParams = loaded

				loaded = nil
			end
		end
	else
		conform = obj:IsConform()
		-- Echo('obj check', conform, "obj.useDefault", obj.useDefault, 'obj.mode', obj.mode, 'obj.smode', obj.smode, 'index', obj.index)
		if not conform then
			obj:Remove()
			customParams = obj
			toAdd = obj.index
		end
	end
	if toAdd then
		local index = tonumber(toAdd)
		if loaded then
			loaded:AddLineObj(alphaIndex or index, true)
		else
			local newTask = {file, alphaIndex or index, customParams}
			tasks[#tasks + 1] = newTask
			tasks[file] = newTask
		end
	end
	return toAdd
end


function MarkerMaker:UpdateFiles()
	local files = VFS.DirList(drawingsDir, '{*.png,*.jpg,*.jpeg,*.tif,*.tiff}')
	local count = 0
	for i, file in ipairs(files) do
		count = count + 1
		files[file] = true
		self:UpdateFile(file, i)
	end
	if holder[count + 1] then -- some file got deleted
		for file, obj in pairs(holder) do
			if type(file) ~= 'number' then
				if not files[file] then
					obj:Remove()
				end
			end
		end
	end
	-- if hasNew then
	-- 	updateCategories = 0
	-- end
end

function MarkerMaker:Remove(fastUpdate)
	if selected == self then
		selected:Deselect()
	end
	if customize == self and not fastUpdate then
		customPanel.closeButton.OnClick[1](customPanel.closeButton)
	end
	if not holder[self.file] then
		error('trying to remove object already removed')
	end
	local index = self.index
	local rem = table.remove(holder, index)
	if self ~= rem then
		Echo('removed the wrong obj, '..self.filename..', file didnt have the correct index ' .. self.index .. ', instead '..rem.filename..' got removed')
	end
	holder[self.file] = nil

	for i = index, #holder do
		if not holder[i] then
			Echo('Indexing problem! Trying to reindex image from #'.. i .. ' to', #holder)
			Echo('debug:')
			for i = index, #holder do
				Echo(i .. ':', holder[i])
			end
			break
		end
		holder[i].index = i
	end
	-- verif
	local err
	for i = 1, #holder do
		if not holder[i] then
			Echo('object missing at index', i, 'after removing', self.filename, 'at index', self.index)
			err = true
		end
	end
	if err then
		error()
	end

	-- local y = obj.control.y
	selector:RemoveChild(self.control)
	scroll:UpdateLayout()
	updateCategories = 0
	if self.list then
		gl.DeleteList(self.list)
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
	elseif not (always_up or win and win.hidden) then
		win:Hide()
	end
end
function widget:KeyRelease(key, mods)
	if deselectOnRelease and not mods.shift then
		deselectOnRelease = false
		if selected then
			selected:Deselect()
		end
	end
	if not (mods.ctrl and mods.alt) then
		if not (always_up or win and win.hidden) then
			win:Hide()
		end
	end
end








function widget:MousePress(mx, my, button)
	if button == 3 then
		if selected then
			if selected.pressed then -- fix the widget keeping wrongly ownership of the mouse
				if widgetHandler.mouseOwner == widget then
					widgetHandler.mouseOwner = nil
				end
				selected.onMapDirX, selected.onMapDirY = 1, 1
				selected.pressed = false
			else
				selected:Deselect()
			end
			return true
		end
	elseif button == 1 then
		if selected then
			if selected.pressed then
				return
			end
			if not WG.Chili.Screen0:IsAbove(mx, my) then
				selected.pressed = 0
				selected.mx, selected.my = mx, my
				return true
			end
		end
	end
end

function widget:Update(dt)
	if selected and selected.pressed then
		local mx, my, lb = spGetMouseState()
		if lb then
			selected.onMapDirX = mx - selected.mx < -10 and -1 or 1
			selected.onMapDirY = my - selected.my < -10 and -1 or 1
		else
			selected:PrepareMarker(selected.onMapDirX, selected.onMapDirY)
			if not select(4, spGetModKeyState()) then -- not shift, don't keep it selected
				MarkerMaker:Deselect()
			else
				selected.pressed = false
				deselectOnRelease = true
			end	
		end
	end
	updateTime = updateTime + dt
	taskTime = taskTime + dt

	if drawing then
		markerTime = markerTime + dt
		if markerTime > markerDelay then
			markerTime = 0
			currentMarkerLine = currentMarkerLine + 1
			if pendingLists[currentMarkerLine] then
				gl.DeleteList(pendingLists[currentMarkerLine])
				pendingLists[currentMarkerLine] = nil
			end
			local line = toDraw[currentMarkerLine]
			if line then
				-- Echo(line)
				local c1, c2 = unpack(line)
				spMarkerAddLine(c1[1], 0, c1[3], c2[1], 0, c2[3])
				toDraw[currentMarkerLine] = nil
			else
				currentMarkerLine = 0
				markerLines = 0
				drawing = false
				-- Echo('done')
			end
		end
	end
	if updateCategories then
		if not tasks[1] then
			updateCategories = updateCategories + 1
			if updateCategories == 10 then
				updateCategories = false
				MakeCategories()
			end
		end
	end
end


local dirCornerOffset = 0.05
local frame = gl.CreateList(
	function()
		gl.Shape(GL.LINES, {
			{v={-1,0.5,0}}, {v={-1,1,0}},
			{v={-1,1,0}}, {v={-0.5,1,0}},

			{v={1,0.5,0}}, {v={1,1,0}},
			{v={1,1,0}}, {v={0.5,1,0}},

			{v={1 + dirCornerOffset,0.5 + dirCornerOffset,0}}, {v={1 + dirCornerOffset,1 + dirCornerOffset,0}},
			{v={1 + dirCornerOffset,1 + dirCornerOffset,0}}, {v={0.5 + dirCornerOffset,1 + dirCornerOffset,0}},

			{v={-1,-0.5,0}}, {v={-1,-1,0}},
			{v={-1,-1,0}}, {v={-0.5,-1,0}},

			{v={1,-0.5,0}}, {v={1,-1,0}},
			{v={1,-1,0}}, {v={0.5,-1,0}},
			 
		})
	end
)
function widget:DrawWorld()
	for _, list in pairs(pendingLists) do
		gl.CallList(list)
	end
end
function widget:DrawScreen()
	if not initialized then
		Init()
		MarkerMaker:UpdateFiles()
		updateTime = updateDelay
	end
	if updateTime >= updateDelay then
		MarkerMaker:UpdateFiles()
		updateTime = 0
	end
	if taskTime >= taskDelay then
		local t = table.remove(tasks, 1)
		while t do
			local file, index, customParams = t[1], t[2], t[3]
			if tasks[file] ~= t then
				t = table.remove(tasks, 1)
			else
				if tasks[file] == t then
					if VFS.FileExists(file) then
						-- Echo('tasking', file, 'index:', index, 'cp', customParams)
						MarkerMaker:New(file, index, customParams)
					end
					tasks[file] = nil
				end
				break
			end
		end
		taskTime = 0
	end

	if selected then
		local mx, my  = spGetMouseState()
		gl.PushMatrix()
		if selected.pressed then
			gl.Translate(selected.mx, selected.my, 0)
		else
			gl.Translate(mx, my, 0)
		end
		gl.Scale(selected.onMapDirX * selected.screen_ratio, selected.onMapDirY * selected.screen_ratio, 1)
		gl.CallList(selected.list)
		if placing_frame then
			gl.Scale(selected.midx, selected.midy, 1)
			gl.CallList(frame)
		end
		gl.PopMatrix()
	end
	if customize and showMultFrame then
		gl.PushMatrix()
		gl.Translate(vsx/2, vsy/2, 0)
		gl.Scale(showMultFrame * customize.midx * customize.screen_ratio, showMultFrame * customize.midy * customize.screen_ratio, 1)
		gl.CallList(frame)
		gl.PopMatrix()
	end
	if showFrame then
		gl.PushMatrix()
		gl.Translate(vsx/2, vsy/2, 0)
		local side = hyp_to_side(showFrame)
		gl.Scale(side/2, side/2, 1)
		gl.CallList(frame)
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
	for _, list in pairs(pendingLists) do
		gl.DeleteList(list)
	end
	gl.DeleteList(frame)
end
if f then
	f.DebugWidget(widget)
end


function widget:ViewResize(viewSizeX, viewSizeY)
  vsx = viewSizeX
  vsy = viewSizeY
end
