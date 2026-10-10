function widget:GetInfo()
	return {
		name      = "Draw Marker From Image",
		desc      = "Place marker drawn from images, put images png/jpg/tif in the LuaUI/Widgets/Drawings dir, they get updated live during widget run"
					.."\nUse shift to place multiple, right click to cancel."
					.."\nRight click on marker object to customize each one of them"
					.."\nClick on map and drag: left to mirror horizontally, down to mirror vertically."
					.."\nImages are stored as json file for faster loading"
					.."\nRename files ('category_filename.jpg') to implement jumpable categories "
					.."\nUI can be hidden and shown when Ctrl + Alt is pushed or always visible",
		author    = "Helwor",
		date      = "Dec 2023",
		license   = "GNU GPL, v2 or later",
		layer     = - 10e35,
		enabled   = true,  --  loaded by default?
		-- api       = true,
		handler   = true,
	}
end
local ALLOWED_FORMATS = '{*.png,*.jpg,*.jpeg,*.jpe,*.tif,*.tiff}'
local LINE_COLOR = {1,1,1,0.5} -- color of lines
local forceResetDate = 1791294080
local sig = '['..widget.GetInfo().name..']: '
local MIN_ANGLE_GAP, BASE_ANGLE_GAP = 2.2, 7.7

----- per-item default param
local mode = 'contour'
local pix_detect         = 0.5
local analyze_size       = 400
local onscreen_size      = 250
local angle_tolerance    = 1
local noise_reduction    = 2
local refine_curve       = 1
-- devMode only
local angle_gap          = 7.7
local window_len         = 2.2
local arrow_limit        = 1
local max_seg_angle      = math.pi/2
local radius_ref         = 150
-- fixed param for curve detection
local minRatioR, maxRatioR = 0.15, 0.5
local downRatioR = minRatioR * 0.8
-------


local json = VFS.Include("LuaRules/Utilities/json.lua",nil, VFS.ZIP)

----- Localizations

local spGetGroundHeight     = Spring.GetGroundHeight
local spWorldToScreenCoords = Spring.WorldToScreenCoords
local spTraceScreenRay      = Spring.TraceScreenRay
local spGetMouseState       = Spring.GetMouseState
local spGetModKeyState      = Spring.GetModKeyState
local spGetSelectedUnits    = Spring.GetSelectedUnits
local spMarkerAddLine       = Spring.MarkerAddLine

local glPushMatrix          = gl.PushMatrix
local glTranslate           = gl.Translate
local glScale               = gl.Scale
local glCallList            = gl.CallList
local glPopMatrix           = gl.PopMatrix
local glDeleteList          = gl.DeleteList
local glTexture             = gl.Texture
local glTextureInfo         = gl.TextureInfo
local glTexRect             = gl.TexRect
local glDeleteTexture       = gl.DeleteTexture
local glDeleteTextureFBO    = gl.DeleteTextureFBO
local glColor               = gl.Color
local glVertex              = gl.Vertex
local glReadPixels          = gl.ReadPixels

local huge                  = math.huge

local FileExists            = VFS.FileExists

----------------------
--- for devMode debug
local DBG_SHARP_ANGLE = 1
local DBG_CURVE = 2
local DBG_EXTREMITY = 3
local KIND_COLORS = {
	[DBG_SHARP_ANGLE] = {1,1,0,1},
	[DBG_CURVE] = {0.2,0.9,1,1},
	[DBG_EXTREMITY] = {1,0.2,0.2,1},
}
--------
local CUSTOM_PARAMS_ORDER = {
	'useDefault',
	'mode',
	'pix_detect',
	'analyze_size',
	'onscreen_size',
	'angle_tolerance',
	'noise_reduction',
	'refine_curve',
	'angle_gap',
	'window_len',
	'arrow_limit',
	'max_seg_angle',
	'radius_ref',
}
local PARAMS = {
	---
	onMapDirX = {
		value = 1,
		type = 'number',
		initial = true,
	},
	onMapDirY = {
		value = 1,
		type = 'number',
		initial = true,
	},
	---
	-- mandatory
	file      = { type = 'string', mandatory = true},
	filename  = { type = 'string', mandatory = true},
	sizeX     = { type = 'number', mandatory = true},
	sizeY     = { type = 'number', mandatory = true},
	mul       = { type = 'number', mandatory = true},
	size      = { type = 'number', mandatory = true}, -- the size is used as a signature to recognize the file
	lines     = { type = 'table' , mandatory = true},
	midx      = { type = 'number', mandatory = true},
	midy      = { type = 'number', mandatory = true},
	-- non generic
	useDefault = {
		title = 'Use Default',
		type = 'boolean',
		default = true,
		no_s = true,
	},
	mode = {
		title = 'Mode',
		type = 'string',
		format = '%s',
		default = mode,
		need_remake = true,
	},
	-- generic number type
	pix_detect = {
		title = 'Pixel Detection',
		type = 'number',
		desc = 'Sensibility to detect pixels that will be drawn, one of the pixel\'s color must be under this value to be detected, if it is semi transparent, the alpha channel must also be superior to (1-value)',
		format = '%.3f',
		min = 0, max = 1, step = 0.005,
		default = pix_detect,
		generic = true,
		need_remake = true,
	},
	analyze_size = {
		title = 'Analyze size',
		type = 'number',
		desc = 'Definition of the image we work on, can help especially when using Contour mode, avoid upping it using Spaghetti as it will make too many lines',
		format = '%d',
		min = 50, max = 800, step = 10,
		default = analyze_size,
		generic = true,
		need_remake = true,
	}, 
	onscreen_size = {
		title = 'On Screen Size',
		type = 'number',
		desc = 'The final result on screen as marker is reshrinked by this multiplicator',
		format = '%d',
		min = 50, max = 500, step = 10,
		default = onscreen_size,
		generic = true,
		always_custom = true,
	},
	angle_tolerance = {
		title = 'Angle Tolerance',
		type = 'number',
		desc = 'How much difference of angle we tolerate before creating a new segment, works only for Contour and Spaghetti mode',
		format = '%.3f',
		min = 0, max = 3, step = 0.005,
		default = angle_tolerance,
		noPlain = true,
		generic = true,
		need_remake = true,
	},
	noise_reduction = {
		title = 'Noise Reduction',
		type = 'number',
		desc = 'Suppress little lines under this length (% of the image diagonal size), not for plain mode',
		format = '%.1f',
		min = 0, max = 20, step = 0.1,
		default = noise_reduction,
		noPlain = true,
		generic = true,
		need_remake = true,
	},
	refine_curve = {
		title = 'Refine Curves',
		type = 'number',
		desc = '<1 smoothen the big curves, >1 smoothen the small curves (blue), not for plain mode',
		format = '%.2f',
		min = 0.01, max = 3, step = 0.01,
		default = refine_curve,
		noPlain = true,
		generic = true,
		need_remake = true,
	}, 
	----- Dev only
	angle_gap = {
		title = 'Angle Gap',
		desc = 'Distance before and after the point, from which we measure the point angle in order to avoid false positive, not for plain mode',
		type = 'number',
		format = '%.2f',
		min = 2.2, max = 15, step = 0.01,
		default = 7.7,
		devMode = true,
		noPlain = true,
		generic = true,
		need_remake = true,
	},
	window_len = {
		title = 'Window Len',
		desc = 'Distance before and after the point in which we pick a strong angular point (yellow), not for plain mode',
		type = 'number',
		format = '%.2f',
		min = 2.2, max = 15, step = 0.01,
		default = 2.2,
		devMode = true,
		noPlain = true,
		generic = true,
		need_remake = true,
	},
	arrow_limit = {
		title = 'Arrow Limit',
		desc = 'Threshold limit of arrow of arc of the current point angle, deciding to place a curve point (blue), not for plain mode',
		type = 'number',
		format = '%.2f',
		min = 0.01, max = 2, step = 0.01,
		default = 1,
		devMode = true,
		noPlain = true,
		generic = true,
		need_remake = true,
	},
	max_seg_angle = {
		title = 'Max Seg Angle',
		desc = 'Maximum angle at point allowed deciding to place a curve point (blue), not for plain mode',
		type = 'number',
		format = '%.2f',
		min = 0.01, max = math.pi, step = 0.01,
		default = max_seg_angle,
		devMode = true,
		noPlain = true,
		generic = true,
		need_remake = true,
	},
	radius_ref = {
		title = 'Radius Ref',
		desc = 'Size of reference to dissociate small curve from big curve, for "Refine Curve" to work, not for plain mode',
		type = 'number',
		format = '%d',
		min = 1, max = 300, step = 1,
		default = radius_ref,
		devMode = true,
		noPlain = true,
		generic = true,
		need_remake = true,
	},
	--
}

local p = PARAMS


local vsx, vsy = widgetHandler:GetViewSizes()

local DRAWINGS_DIR = "LuaUI/Widgets/Drawings/"

local MarkerMaker = {} -- class
MarkerMaker.mt = {__index = MarkerMaker}

local customPanel

local categories = {byKey = {}, scrollPoses = {}, controls = {}, head = nil}
local updateCategories = false

local debugContour = false

-- options

local always_up = true
local placing_frame = false
local devMode = false
local console_debugging = false
local updateTime = 0
local update_delay = 3
local max_update_time = 0.05

--

local showMultFrame = false
local showFrame = false

---- old
local COUNT_FOR_ANGLE = 3
local PRECISION = 0.5
----

------ selector
local MAX_SELECTOR_HEIGHT = 300 -- adaptative win height to fit the last thumbnail size
local SELECTOR_BUTTON_W = 75
local SELECTOR_BTN_PADDING = {1,2,1,2}
-- hax to customize selected button appearance
local oriBGColor
local oriFocusColor
local oriPressedColor
local selectedColor
--
local selector, win, scroll
--------

local drawing
local currentMarkerLine, markerLines = 0, 0
local markerTime = 0
local MARKER_DELAY = 0.044 -- the minimal time period between drawing, else it would be ignored
local toDraw = {}
local pendingLists = {}


local function MakeSelectedColor(r,g,b,a)
	return {r * 0.5, g * 2, b * 0.5, a * 1.5}
end
function hyp_to_side(hyp) -- from hypothenus to side (assuming a square ofc)
	return (hyp^2 / 2)^0.5
end
--

local holder = {}
local tasks = {}
local curScrollPosY = false
local deselectOnRelease = false
local selected = false
local customize = false
local initialized = false
local Init, UpdateScreenRatio, RemakeCustomizationPanel
-- local maxPerUpdate = 10
local current = 1
local taskTime = 0
local taskDelay = 1
local vsx, vsy = Spring.Orig.GetViewGeometry()
local scaled_vsx, scaled_vsy = Spring.GetViewGeometry()

options_path = 'Hel-K/'..widget:GetInfo().name
options_order = {
	'always_up',
	'placing_frame',
	'update_delay',
	'max_update_time',
	'note',

	'mode',

	'pix_detect',
	'analyze_size',
	'onscreen_size',
	'angle_tolerance',
	'noise_reduction',
	'refine_curve',

	'devMode',
	'console_debugging',
}
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
options.update_delay = {
	name = 'Live Update Delay',
	desc = 'Period between file checks in sec',
	type = 'number',
	min = 1, max = 10, step = 1,
	value = update_delay,
	OnChange = function(self)
		update_delay = self.value
	end,

}

options.max_update_time = {
	name = 'Max time allowed per update',
	desc = 'Helpful for potato comp with many images to update',
	type = 'number',
	min = 0.005, max = 0.5, step = 0.005,
	value = max_update_time,
	OnChange = function(self)
		max_update_time = self.value
	end,
}
options.note = {
	name = 'NOTE:',
	type = 'text',
	value = 'Options below are globals.\nEach marker object can be customized separately through Right Click.\n',
}

options.mode = {
	name = 'Mode',
	type = 'radioButton',
	value = p.mode.default,
	items = {
		{name = 'Contour',    key = 'contour'   },
		{name = 'Spaghetti',  key = 'spaghetti' },
		{name = 'Plain',      key = 'plain'     },
	},
	noHotkey = true,
	OnChange = function(self)
		p[self.key].default = self.value
		initialized = false
	end,
}


options.pix_detect = {
	OnChange = function(self)
		p[self.key].default = self.value
		initialized = false
	end,
}

options.analyze_size = {
	OnChange = function(self)
		p[self.key].default = self.value
		initialized = false
	end,
}

options.onscreen_size = {
	OnChange = function(self)
		showFrame = false
		if self.value ~= p[self.key].default then
			local oldDefault = p[self.key].default
			local newValue = self.value
			p[self.key].default = newValue
			for i, obj in ipairs(holder) do
				if obj.useDefault then
					if obj.s_onscreen_size == oldDefault then
						obj.onscreen_size = newValue
						obj:SetScreenRatio()
						obj:Save()
					end
				end
			end
		end
	end,

	tooltipFunction = function(self, ...)
		if initialized then
			local control = WG.Chili and WG.Chili.Screen0.hoveredControl
			if control and control.name == self.name then
				showFrame = self.value
			end
		end
		return self.value
	end,
}

options.angle_tolerance = {
	OnChange = function(self)
		p[self.key].default = self.value
		initialized = false
	end,
}

options.noise_reduction = {
	OnChange = function(self)
		p[self.key].default = self.value
		initialized = false
	end,
}

options.refine_curve = {
	OnChange = function(self)
		p[self.key].default = self.value
		initialized = false
	end,
}

options.devMode = {
	name = 'Dev Mode',
	desc = '',
	type = 'bool',
	value = devMode,
	OnChange = function(self)
		devMode = self.value
		if initialized and WG.crude.IsDevMode() then
			RemakeCustomizationPanel()
		end
	end,
	dev = true,
}

options.console_debugging = {
	name = 'Console Debugging',
	desc = '',
	type = 'bool',
	value = console_debugging,
	OnChange = function(self)
		console_debugging = self.value
	end,
	dev = true,
}


for name, opt in pairs(options) do
	local param = p[name]
	if param and param.generic then
		opt.name = param.title
		opt.desc = param.desc
		opt.type = 'number'
		opt.default = param.default
		opt.value = param.default
		opt.min, opt.max, opt.step = param.min, param.max, param.step
		opt.forceResetDate = forceResetDate
	end
end

function DevOptions(bool) -- new callback from epic menu telling us when user toggle the dev options
	if initialized then
		RemakeCustomizationPanel()
	end
end

local function ReturnSelf(self)
	return self
end

local SortByLength = function(a, b)
	return a[#b + 1] -- probably faster than #a > #b
end
--- making Rotator clockwise usage: rotateClock[x][z] = rotatedCoords
local function SpiralSquare(layers, step, callback, offset, reverse, ortho)
	-- LOOP iterating squares clockwise from center to exterior, starting at bottom left corner
	-- reverse is anticlockwise, from exterior to center, starting at top right
	-- first point is always at center if offset is explicit 0
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
do
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

	local antiClockCoords, r = {}, 0
	local add = function(_, x, z)
		r = r + 1
		antiClockCoords[r] = {z,x}
	end
	SpiralSquare(1, 1, add, nil, true)
	for i, r in ipairs(antiClockCoords) do
		rotateAntiClock[ r[1] ][ r[2] ] = antiClockCoords[i + 1] or antiClockCoords[1]
	end
	setmetatable(rotateAntiClock, nil)
	--[[ verif
	local function verif(_, x, z)
		local coords = rotateClock[z][x]
		Echo(x, z .. ' =>> ' .. coords[2], coords[1])
	end
	SpiralSquare(1, 1, verif)
	--]]

	-- local deg = math.deg(math.atan2(x,z))
end

local function UnminifyJSON(jsonStr, indent)
	indent = indent or '\t'
	local level = 0
	local suppress = false
	return jsonStr:gsub('([{%[,%]}])()', function(c, p)
		if c == '[' then
			suppress = true
			if jsonStr:sub(p, p) == '[' then
				level = level + 1
				return '[\n'..('\t'):rep(level)
			end
		elseif c == ']' then
			suppress = false
			if jsonStr:sub(p, p) == ']' then
				level = level - 1
				return ']\n'..('\t'):rep(level)
			end
		elseif suppress then
			return
		elseif c == '{' then
			level = level + 1
			return '{\n'..('\t'):rep(level)
		elseif c == '}' then
			level = level - 1
			return '\n'..('\t'):rep(level)..'}'
		else
			return ',\n'..('\t'):rep(level)
		end
	end)
end

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
	local files = VFS.DirList(DRAWINGS_DIR, ALLOWED_FORMATS)
	local byKey = {}
	local newCats = {}
	local lastCat
	local c = 0
	for i, file in ipairs(files) do
		if not holder[file] then -- wait for it to be added
			return
		end
		local filename = file:gsub(DRAWINGS_DIR, '')
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
				if not win then
					return
				end
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
					if child.y  + (off - paddingBot) > MAX_SELECTOR_HEIGHT then
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
				if newWinHeight > MAX_SELECTOR_HEIGHT then
					win.maxHeight = newWinHeight
				else
					win.maxHeight = MAX_SELECTOR_HEIGHT
				end
				lastTimeY = lastY
				if newWinHeight and win.height ~= math.min(newWinHeight, win.maxHeight) then
					local selWidth = SELECTOR_BUTTON_W + (scrollbar and scroll.scrollbarSize or 0)
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
		width = SELECTOR_BUTTON_W,
		name = 'marker_scrollpanel',
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
		x = scaled_vsx - (SELECTOR_BUTTON_W + 23 + 4),
		y = 200,
		height = 0,
		padding = {0,7,5,5},
		resizable = false,
		maxHeight = 200,
		width = SELECTOR_BUTTON_W + 23,
		OnResize = {
			function(self)
				updateCategories = 0
				curScrollPosY = scroll.scrollPosY
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

function RemakeCustomizationPanel()
	local obj = customize
	if customPanel then
		customPanel.win:Dispose()
	end
	MakeCustomizationPanel()
	if obj then
		obj:SetupCustomPanel()
	else
		customPanel.win:Hide()
	end

end

function MakeCustomizationPanel()
	local devMode = WG.crude.IsDevMode() and devMode
	local cp = {}
	local win_width = 800
	local win_height = 250

	local panel_bottom = 30
	local panel_top = 15
	local panel_right = 5
	local panel_left = 5
	local button_height = 20
	local control_width = "48%"
	local panel_col_width = (win_width - panel_left - panel_right) / 2
	local left = 10
	local y = 0

	local color_text = {1,1,1,1}
	local color_header = {1,1,0,1}
	local active_color_text = {1,1,1,1}
	local active_color_header = {1,1,0,1}

	local defaults_tooltip
	do
		local _defaults = {}
		for _, name in ipairs(CUSTOM_PARAMS_ORDER) do
			local param = p[name]
			if devMode or not param.devMode then
				if not param.no_s then
					_defaults[#_defaults+1] = ('%s: '..param.format):format(param.title, param.default)
				end
			end
		end
		defaults_tooltip = table.concat(_defaults, '\n')

	end


	local function MakeGenericControl(name)
		local param = p[name]
		if not param.generic or param.devMode and not devMode then
			return
		end
		local value = param.default
		y = y + 25
		cp['header_'..name] = WG.Chili.Label:New{
			y = y,
			x = left,
			width = control_width,
			caption = param.title,
			tooltip = param.desc,
			HitTest = ReturnSelf,

			textColor = color_header,
		}

		y = y + 15
		cp[name] = WG.Chili.Trackbar:New{
			x = left,
			y = y,
			width = control_width,
			-- right = panel_col_width,
			value = value,
			trackColor = color_text, -- trackColor has not been implemented yet
			min = param.min,
			max = param.max,
			step = param.step,
			OnMouseUp = {
				function(self)
					if customize then
						-- Echo('mouse up', self.value, 'customize', customize, customize.pix_detect, customize.spix_detect)
					end
					if customize then
						if customize[name] ~= self.value then
							customize[name] = self.value
							if not customize.useDefault and (not param.noPlain or customize.mode ~= 'plain') then
								customize:FastUpdate()
							else
								customize:Save()
								local header = customPanel['header_'..name]
								local caption = header.caption:gsub(': %d.*$', '')
								header:SetCaption(('%s: '..(p[name].format)):format(caption, self.value))
							end
						end
					end
				end
			},
		}
	end

	cp.useDefault = WG.Chili.Checkbox:New{
		x = left,
		y = y,
		width = control_width,
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
		tooltip = 'Ignore customization, but keep it memorized\nDefault values are:\n'..defaults_tooltip,

		HitTest = ReturnSelf,

	}


	y = y + 25
	cp.header_mode = WG.Chili.Label:New{
		y = y,
		x = left,
		width = control_width,
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
			width = control_width,
			caption = '   ' .. m,
			textColor = color_text,
			checked = m:lower() == p.mode.default,
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

	MakeGenericControl('pix_detect')

	MakeGenericControl('analyze_size')

	y = y + 25
	cp.header_onscreen_size = WG.Chili.Label:New{
		x = left,
		y = y,
		width = control_width,
		caption = 'Onscreen Size',
		textColor = active_color_header,
		tooltip = 'Final size on screen',
		HitTest = ReturnSelf,

		-- align='leftr',
	}

	y = y + 15
	local function react(self, x, y, button, mods)
		if customize then
			if customize.onscreen_size ~= self.value then
				customize.onscreen_size = self.value
				customize:SetScreenRatio()
				showMultFrame = 1
				local header = cp.header_onscreen_size
				local caption = header.caption:gsub(': %d.*$', '')
				header:SetCaption(('%s: '..(p.onscreen_size.format)):format(caption, self.value))
			end
			if button and customize.onscreen_size ~= customize.s_onscreen_size then -- only OnMouseUp and saved doesnt match current
				customize:Save()
			end
		end
	end
	cp.onscreen_size = WG.Chili.Trackbar:New{
		x = left,
		y = y,
		width = control_width,
		value = p.onscreen_size.default,
		trackColor = active_color_text,
		min = p.onscreen_size.min,
		max = p.onscreen_size.max,
		step = p.onscreen_size.step,
		OnChange = { react },
		OnMouseUp = { react },
		tooltipFunction = function(self)
			if customize and self == WG.Chili.Screen0.hoveredControl then
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
			showMultFrame = false
		end}
	}

	MakeGenericControl('angle_tolerance')

	MakeGenericControl('noise_reduction')

	MakeGenericControl('refine_curve')

	MakeGenericControl('angle_gap')

	MakeGenericControl('window_len')

	MakeGenericControl('arrow_limit')

	MakeGenericControl('max_seg_angle')

	MakeGenericControl('radius_ref')

	-----
	local function CreateCustomizationMarkerImage()
		cp.marker_image = WG.Chili.Image:New{
			file = '',
			-- fake dimensions but this allow to not be clipped out when the window start getting out of screen
			width = 500,
			height = y,
			---
			drawcontrolv2 = true,
			DrawControl = function(self) -- hack to set UI image as pure gl
				local obj = customize
				if obj and obj.list then
					local w = cp.win.width/2  - panel_left - panel_right
					local h = cp.win.height - panel_top  - panel_bottom
					local ratio = math.min((w - 65) / (obj.midx * 2), (h - 60) / (obj.midy * 2))

					glPushMatrix()
					glColor(LINE_COLOR)
					glTranslate(w + 20, 0, 0)
					glScale(ratio, -ratio, 1)
					glTranslate(obj.midx, -(obj.midy + 3), 0)
					if devMode and obj.dbg_list then
						glCallList(obj.dbg_list)
					else
						glCallList(obj.list)
					end

					glPopMatrix()
					glColor(1, 1, 1, 1)

				end
			end,
		}
	end

	CreateCustomizationMarkerImage()

	cp.scroll_panel = WG.Chili.ScrollPanel:New{
		name = 'marker_custom_panel',
		x = panel_left,
		y = panel_top,
		right = panel_right,
		bottom = panel_bottom,
		orientation   = "vertical",
		OnResize = {
			function(self)
				for i, v in ipairs(self.children) do -- hack to adapt our image size manually
					if v.classname == 'image' then
						if v._own_dlist then
							gl.DeleteList(v._own_dlist)
							v._own_dlist = gl.CreateList(v.DrawControl, v)
						end
					end
				end
			end
		}
	}
	cp.scroll_panel:AddChild(cp.useDefault)

	cp.scroll_panel:AddChild(cp.header_mode)

	for i, ctrl in ipairs(cp.modes) do
		cp.scroll_panel:AddChild(ctrl)
	end

	for i, name in ipairs(CUSTOM_PARAMS_ORDER) do
		if p[name].generic then
			local control = cp[name]
			if control then
				cp.scroll_panel:AddChild(cp['header_' .. name])
				cp.scroll_panel:AddChild(control)
			end
		end
	end

	cp.scroll_panel:AddChild(cp.marker_image)

	cp.reset_defaults = WG.Chili.Button:New{
		x = 10,
		bottom = 6,
		width = 160,
		height = button_height,
		-- right = panel_col_width,
		caption = 'Reset Customization',
		tooltip = 'Return to default values:\n' .. defaults_tooltip,
		trackColor = color_text,
		OnClick = {
			function(self)
				if customize then
					for i, m in ipairs({'contour', 'spaghetti', 'plain'}) do
						if p.mode.default == m then
							if not cp.modes[i].checked then
								cp.modes[i]:Toggle()
							end
							break
						end
					end

					for i, name in ipairs(CUSTOM_PARAMS_ORDER) do
						local param = p[name]
						if param.generic then
							local control = cp[name]
							if control and math.abs(control.value - param.default) > 1e-6 then -- value of angle_tolerance can differ a tiny bit when getting digested by the trackbar control
								control:SetValue(param.default)
								control.OnMouseUp[1](control, -1, -1, 1)
							end
						end
					end
					showMultFrame = false
				end
			end
		},
	}

	if devMode then
		cp.devModeToggle = WG.Chili.Checkbox:New{
			x = '47%',
			bottom = 6,
			width = 80,
			caption = 'Dev Mode',
			boxalign = 'left',
			checked = devMode,
			OnChange = {function(self)
				local newchecked = not self.checked
				if options.devMode.value ~= newchecked then
					options.devMode.value = newchecked
					options.devMode:OnChange()
				end
			end},
			tooltip = "",
			round = true,
		}
	end

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
	local win_children = {
		cp.scroll_panel,
		cp.reset_defaults,
		cp.closeButton,
	}
	if cp.devModeToggle then
		table.insert(win_children, 3, cp.devModeToggle)
	end

	cp.win = {
		x = (vsx - win_width) / 2,
		y = 200,
		name = 'marker_custom_win',
		width  = win_width,
		height = y + cp.closeButton.height + 8 + 58,
		classname = "main_window_small_tall",
		parent = WG.Chili.Screen0,
		-- backgroundColor = color.sub_bg,
		-- resizable = false,
		caption = 'filename' .. '\'s params',
		-- minWidth = win_width,
		-- minHeight = win_height,
		children = win_children,
	}

	cp.RemakeImage = function()
		cp.scroll_panel:RemoveChild(cp.marker_image)
		CreateCustomizationMarkerImage()
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
	end
	RemakeCustomizationPanel()
	tasks = {}
	taskTime = 0

	for file, obj in pairs(holder) do
		obj:Remove()
	end
	initialized = true
end


function MarkerMaker:New(file, index, params)
	-- Echo('new obj', file, index, params, params and params.mode, params and params.useDefault)
	params = params or {}
	local obj = {
		file = file,
		filename = nil,
		sizeX = nil,
		sizeY = nil,
		mul = nil,
		size = nil, -- the size is used as a signature to recognize the file

		lines = {},
		midx = nil, midy = nil,


		useDefault       = params.useDefault ~= false, -- false only if param is false else true
		mode             = params.mode               or p.mode.default,              smode             = nil,
		pix_detect       = params.pix_detect         or p.pix_detect.default,        spix_detect       = nil,
		analyze_size     = params.analyze_size       or p.analyze_size.default,      sanalyze_size     = nil,
		onscreen_size    = params.onscreen_size      or p.onscreen_size.default,     sonscreensize     = nil,
		angle_tolerance  = params.angle_tolerance    or p.angle_tolerance.default,   sangle_tolerance  = nil,
		noise_reduction  = params.noise_reduction    or p.noise_reduction.default,   snoise_reduction  = nil,
		refine_curve     = params.refine_curve       or p.refine_curve.default,      srefine_curve     = nil,
		angle_gap        = params.angle_gap          or p.angle_gap.default,         sangle_gap        = nil,
		window_len       = params.window_len         or p.window_len.default,        swindow_len       = nil,
		arrow_limit      = params.arrow_limit        or p.arrow_limit.default,       sarrow_limit      = nil,
		max_seg_angle    = params.max_seg_angle      or p.max_seg_angle.default,     smax_seg_angle    = nil,
		radius_ref       = params.radius_ref         or p.radius_ref.default,        sradius_ref       = nil,

		---- live params
		index = nil,
		list = nil, -- drawing list
		dbg_list = nil, -- drawing list
		control = nil,

		screen_ratio = nil,

		pressed = false,
		mx = false, my = false,
		onMapDirX = 1, onMapDirY = 1,

	}

	if params == customize then
		customize = obj
	end
	setmetatable(obj, MarkerMaker.mt)
	local lines

	if obj.useDefault and p.mode.default == "plain" or not obj.useDefault and obj.mode == "plain" then
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

local cnt = 0
function MarkerMaker:IsConform()
	local wrong
	local type = type
	local useDefault = self.useDefault ~= false
	local plainMode = self.s_mode == 'plain' and (useDefault and p.mode.default == 'plain' or not useDefault and self.mode == 'plain')

	for name, param in pairs(p) do
		if param.mandatory then
			if type(self[name]) ~= param.type then
				wrong = true
				break
			end
		elseif param.default and param.need_remake then
			if useDefault then
				if self['s_'..name] ~= param.default then
					if not plainMode or not param.noPlain then
						if console_debugging then
							Echo(self.filename, os.clock()%3600, 'wrong, using default', name, 'got', self['s_'..name], 'wanted', param.default, 'isPlain', plainMode, 'param.noPlain', param.noPlain)
						end
						wrong = true
						break
					end
				end
			else
				if self['s_'..name] ~= self[name] then
					if not plainMode or not param.noPlain then
						if console_debugging then
							Echo(self.filename, os.clock()%3600, 'wrong, using custom', name, 'got', self['s_'..name], 'wanted', self[name], 'isPlain', plainMode, 'param.noPlain', param.noPlain)
						end
						wrong = true
						break
					end
				end
			end
		end
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
	if console_debugging then
		Echo('save', self.filename, os.clock()%3600, 'useDefault', self.useDefault)
	end
	if self.useDefault then
		for name, param in pairs(p) do
			if param.default and not param.no_s then
				if param.always_custom then
					self['s_'..name] = self[name]	
				else
					self['s_'..name] = param.default
				end
			end
		end
	else
		for name, param in pairs(p) do
			if param.default and not param.no_s then
				self['s_'..name] = self[name]
			end
		end
	end

	self.file = self.file:gsub('\\', '/')
	self.filename = self.file:gsub(DRAWINGS_DIR, '')
	local jsonfile = self.file  .. '.json'
	-- local jsonfile = file:sub(1, (file:find('%.[^%.]+$') or 0) - 1)  .. '.json'
	local toSave = {}
	for key, v in pairs(self) do
		local param = p[key:gsub('^s_', '')]
		if param and (param.mandatory or param.default) then
			 toSave[key] = v
		end
	end
	local success, jsonstring = pcall(json.encode, toSave)
	if success then
		local f = io.open(jsonfile, "w")
		if f then
			f:write((UnminifyJSON(jsonstring)))
			f:close()
		else
			Echo(sig..'Couldn\'t write file '..jsonfile)
		end
	else
		Echo(sig..'Json encoding failed for '..self.file)
		Echo('Error:', jsonstring)
	end
end

function MarkerMaker:LoadObj(file)
	-- local jsonfile = file:sub(1, (file:find('%.[^%.]+$') or 0) - 1)  .. '.json'
	local jsonfile = file  .. '.json'
	local code = io.open(jsonfile, "r")
	if code then
		local success, obj = pcall(json.decode, code:read('*a'))
		if not success then
			Echo(sig..'Couldn\'t load the json file ' .. jsonfile, obj)
			code:close()
			return
		else
			obj.file = obj.file:gsub('\\', '/')
			local add = {}
			local tonumber, type = tonumber, type
			local lines = obj.lines
			for k,v in pairs(lines) do
				if type(k) == 'string' and tonumber(k) then
					lines[k] = nil
					-- lines[tonumber(k)] = v
					add[k] = v
				end
			end
			for k, v in pairs(add) do
				lines[tonumber(k)] = v
			end

			for name, param in pairs(p) do
				if param.default then
					if type(obj[name]) ~= param.type then
						obj[name] = p[name].default
					end
				elseif param.initial then
					obj[name] = param.value
				end
			end
		end
		code:close()
		setmetatable(obj, MarkerMaker.mt)
		return obj
	end
end


function MarkerMaker:AddNewContouredImage()
	local raster = self:GetRaster()
	if not raster then
		Echo(sig..'File ' .. self.file .. ' couldn\'t get loaded')
	else
		local contours = self:AcquireContours(raster)
		if not contours then
			Echo(sig..'File ' .. self.file .. ' couldn\'t make any contour')
			self.midx = 25 self.midy = 25
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
			-- local isSpaghetti = self.useDefault and mode == 'spaghetti' or self.mode == 'spaghetti'
			-- if isSpaghetti then
			--  self:SimplifyContoursOLD(contours, true)
			-- else
				self:SimplifyContours(contours)
			-- end
			if not contours[1] then
				Echo(sig..'File ' .. self.file .. ' couldn\'t make any contour after simplification')
				self.midx = 25 self.midy = 25
				return {}
			end
			if debugContour then
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
	local mode = self.useDefault and p.mode.default or self.mode
	local pix_detect = self.useDefault and p.pix_detect.default or self.pix_detect
	local left, top, right, bottom = huge, -huge, -huge, huge
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
	glTexture(0, file)
	local info = glTextureInfo(file)
	if not info or info.xsize == -1 then
		Echo("CAN'T LOAD FILE " .. file)
		glTexture(0, false)
		glDeleteTexture(file)
		return
	end
	-- f.Page(info)

	local analyze_size = self.useDefault and p.analyze_size.default or self.analyze_size

	local sizeX = info.xsize
	local sizeY = info.ysize
	local diag = math.diag(sizeX, sizeY)
	local mul = analyze_size / diag
	sizeX = sizeX * mul
	sizeY = sizeY * mul
	self.sizeX, self.sizeY = sizeX, sizeY
	self.mul = mul
	local tex = gl.CreateTexture(sizeX, sizeY, {
		format = GL.RGBA8,
		fbo = true,
	})

	gl.RenderToTexture(tex, function()
		gl.Clear(GL.COLOR_BUFFER_BIT)
		glTexRect(-1, -1, 1, 1)
		-- FIXME gl.ReadPixels is bugged when asking a map (w > 1 and h > 1), giving values at the wrong place
		-- so we ask line by line...
		for y = sizeY-1, 0, -1 do -- y0 is at bottom
			t[y+1] = gl.ReadPixels(0, y, sizeX, 1)
		end
	end)
	glTexture(0, false)
	gl.DeleteTextureFBO(tex)
	glDeleteTexture(tex)
	glDeleteTexture(file)
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
			if tries > 25000 then
				Echo(sig..'TOO MANY TRIES CONTOUR')
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

function MarkerMaker:SimplifyContoursOLD(contours, gross)
	-- for debugging only
	-- local float = function(n, dec)
	--  return tostring(n):ftrim(dec or 2)
	-- end
	local angle_tolerance = self.useDefault and p.angle_tolerance.default or self.angle_tolerance
	local noise_reduction = self.useDefault and p.noise_reduction.default or self.noise_reduction
	-- angle_tolerance = angle_tolerance*3
	local abs, diag = math.abs, math.diag
	local atan2 = math.atan2
	local remove = table.remove
	local sizeX, sizeY = contours.right - contours.left, contours.top - contours.bottom
	local step = math.max(3, diag(sizeX, sizeY) / 30)
	local suppress_length =  diag(sizeX, sizeY) * (noise_reduction / 100)

	-- Echo('*--------------------------------------------------')
	-- Echo('--------------------------------------------------')
	-- Echo('STEP', step)

	for c, contour in ipairs(contours) do
		local len = #contour
		if DBG then
			Echo('**** CONTOUR '.. c ..'#'..len..' ****')
		end
		if len > 0 then
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
			local points = {}
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
						points = {}
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
				if devLastAngle then
					points[i] = devLastAngle
				end
				if travel > step or i == len then
					-- local ratio = travel/straight
					-- local ratioed = ratio > sensitivity
					local devied = devAngle and devAngle > (angle_tolerance) -- deviation from origin of segment
					local devied2 = devLastAngle and devLastAngle > 1/(COUNT_FOR_ANGLE * (1-angle_tolerance)) -- deviation from a little distance
					-- Echo(i,devied,devied2,'x'..last[1]..'-'..cur[1],'y'..last[2]..'-'..cur[2], "lastAngle is ", lastAngle)
					-- Echo(i,devied,devied2,'x'..last[1]..'-'..cur[1],'y'..last[2]..'-'..cur[2], lastAngle and "lastAngle:"..f(lastAngle), devLastAngle and 'devLastAngle:'..f(devLastAngle))
					if --[[ratioed or]] devied or devied2 or i == len then
						-- Echo(string.color({1,1,0,1})..'x'..last[1]..'-'..cur[1],'y'..last[2]..'-'..cur[2] .. ' => ', ratioed and 'ratio:' .. f(ratio), devied and 'devied:'..f(devAngle), devied2 and 'devied2:'..f(devLastAngle), (i == len) and 'end')
						if segI < i-2 then
							if not gross then
								local maxAngle, maxI = 0, segI
								for j = i, segI, -1 do
									local angle = points[j]
									if angle then
										-- Echo("angle:"..tostring(angle))
										if angle > maxAngle then
											maxAngle, maxI = angle, j
										-- else
										--  break
										end
									end
								end
								i = maxI
							end
							-- if c == 1 then
							--  if devied then
							--      Echo
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

	local c = 1
	local contour = contours[c]
	while contour do
		local travel = 0
		local point = contour[1] 
		local x, z = point[1], point[2]
		local toRemove = true
		for i = 2, #contour do
			local nex_point = contour[i]
			local nx, nz = nex_point[1], nex_point[2]
			travel = travel + diag(nx - x, nz - z)
			if travel > suppress_length then
				toRemove = false
				break
			end
			x, z = nx, nz
		end
		if toRemove then
			remove(contours, c)
		else
			c = c + 1
		end
		contour = contours[c]
	end

	-- Echo('simplified')
	-- for i, contour in ipairs(contours) do
	--  Echo('contour',i,'#'..#contour)
	--  if i >= 4 then
	--      for i,v in pairs(contour) do
	--          Echo(i,unpack(v))
	--      end
	--  end
	-- end
	-- Echo("contours", #contours, 'COUNT',COUNT)
end



local function BreakStaircase(contour) -- unused
	local c, c2, c3 = contour[1], contour[2], contour[3]
	if not c3 then
		return contour
	end
	local i, n = 1, 1
	local new = table.new(#contour*2/3)
	local cx, cy = c[1], c[2]
	local c2x, c2y = c2[1], c2[2]
	local c3x, c3y = c3[1], c3[2]
	new[n] = c
	local cut = false
	while c3 do
		n = n + 1
		if n < 10 then
			Echo('=>', cx, cy, '|', c2x, c2y)
		end
		if cx == c2x or cy == c2y then
			new[n] = c3
			i = i + 2
			c, c2, c3 = c3, contour[i + 1], contour[i + 2]
			cut = true
		else
			new[n] = c2
			i = i + 1
			c, c2, c3 = c2, c3, contour[i + 2]
			cut = false
		end
	end
	if not cut then
		n = n + 1
		new[n] = c2
	end
	return new
end

function MarkerMaker:SimplifyContours(contours)
	local min, max, clamp, abs, diag, pi, atan2
		= math.min, math.max, math.clamp, math.abs, math.diag, math.pi, math.atan2
	local pi2 = pi * 2
	local remove = table.remove
	---
	local sizeX, sizeY = contours.right - contours.left, contours.top - contours.bottom
	local size = diag(sizeX, sizeY)
	---
	local console_debugging = console_debugging
	local minRatioR, maxRatioR, downRatioR = minRatioR, maxRatioR, downRatioR

	local angle_tolerance, noise_reduction, angle_gap, window_len, refine_curve, arrow_limit, max_seg_angle, radius_ref
	if self.useDefault then
		local p = p
		angle_tolerance   = p.angle_tolerance.default
		noise_reduction   = p.noise_reduction.default
		angle_gap         = p.angle_gap.default
		window_len        = p.window_len.default
		refine_curve      = p.refine_curve.default
		arrow_limit       = p.arrow_limit.default
		max_seg_angle     = p.max_seg_angle.default
		radius_ref        = p.radius_ref.default
	else
		local self = self
		angle_tolerance   = self.angle_tolerance
		noise_reduction   = self.noise_reduction
		angle_gap         = self.angle_gap
		window_len        = self.window_len
		refine_curve      = self.refine_curve
		arrow_limit       = self.arrow_limit
		max_seg_angle     = self.max_seg_angle
		radius_ref        = self.radius_ref
	end
	---
	local size_ratio = size / 400
	local suppress_length =  noise_reduction * size / 100
	arrow_limit = arrow_limit * angle_tolerance
	arrow_limit = arrow_limit * size_ratio -- normalize to size
	radius_ref = max(1, radius_ref * size_ratio) 
	-- angle_gap = max(1.5, angle_gap * size_ratio)
	window_len = max(1, window_len * size_ratio)
	local suppressCurvesFromCorners = false

	local dbgcount = 0

	local function partdown(x, min, max, n) -- reduce a bit min value if n > 1, reduce max values if n < 1
		local norm = (x - min) / (max - min)
		local w = n < 1 and norm or (1 - norm)
		local p = (n < 1 and n or 1 / n) ^ w
		-- Echo(('x: %.2f, norm: %.2f, n: %.1f, pow: %.2f => %.2f'):format(x, norm, n, p, p * x))
		return x * p
	end

	local function CurveReady(angle, arc)
		if angle > max_seg_angle then return true end
		if angle <= 1e-5 or arc <= 1e-5 then return false end
		local radius = max(arc, 1e-5) / max(angle, 1e-5) -- coord / angle => radius
		local ratioRadius = (radius/radius_ref)
		local limitMult = clamp(ratioRadius, minRatioR, maxRatioR) 
		limitMult = partdown(limitMult, minRatioR, maxRatioR, refine_curve)
		dbgcount = dbgcount + 1
		-- if dbgcount%50 == 0 and (radius > 30 or radius < 5) then
		--  Echo(
		--      ('#%d angle: %.2f, arc: %.2f, radius: %.2f, ratioRadius: %.2f, refine_curve: %.2f, limitMult: %.2f'): format(
		--              dbgcount, angle, arc, radius, ratioRadius, refine_curve, limitMult
		--          )
		--  )
		-- end
		return angle * arc > arrow_limit * 8 * limitMult
	end
	--
	if console_debugging then
		Echo('-------------------------------------')
		Echo(
			('PARAMS[ size: %d (mul:%.2f), window_len: %.3f, angle_gap: %.3f, tolerance: %.4f,  suppress_length: %.2f ]')
			:format(size, self.mul, window_len, angle_gap, angle_tolerance, suppress_length)
		)
	end

	local function angleDiff(pin, cur, pout)
		local angleIn = atan2(cur[1]-pin[1], cur[2]-pin[2])
		local angleOut = atan2(pout[1]-cur[1], pout[2]-cur[2])
		local d = angleOut - angleIn
		while d > pi do d = d - pi2 end
		while d < -pi do d = d + pi2 end
		return d
	end
	local total_lines, total_simplified = 0, 0
	local total_curves, total_too_sharps, total_noises, total_small_noises, total_supp_count = 0, 0, 0, 0, 0
	local c = 1
	local contour = contours[c]
	local deletion = false
	while contour do -- sliding window system

		------ angle_gap adaptative, >=77 px diag of contour to get to full angle_gap
		local GAP_RATIO = 0.1 * (angle_gap / BASE_ANGLE_GAP)
		local minx, maxx, miny, maxy = huge, -huge, huge, -huge
		for n = 1, #contour do
			local pt = contour[n]
			local x, y = pt[1], pt[2]
			if x < minx then minx = x end
			if x > maxx then maxx = x end
			if y < miny then miny = y end
			if y > maxy then maxy = y end
		end
		-- Echo('c'..c, 'diag', diag(maxx - minx, maxy - miny), diag(maxx - minx, maxy - miny) * GAP_RATIO, MIN_ANGLE_GAP, angle_gap, '=>', clamp(diag(maxx - minx, maxy - miny) * GAP_RATIO, MIN_ANGLE_GAP, angle_gap))
		local angle_gap = clamp(diag(maxx - minx, maxy - miny) * GAP_RATIO, MIN_ANGLE_GAP, angle_gap)
		------
		local _first, _last = contour[1], contour[#contour]
		local isLoop = _first[1] == _last[1] and _first[2] == _last[2]
		local len = #contour
		total_lines = total_lines + len
		local travel = 0
		-- Passe 1 : distance cumulée le long du contour, point par point.
		local cum = {[1] = 0}
		local winJ, winK = {}, {}
		if len > 1 then
			for i = 2, len do
				local p, q = contour[i-1], contour[i]
				travel = travel + diag(q[1]-p[1], q[2]-p[2])
				cum[i] = travel
			end
		end
		local maxTurn, minTurn = 0, math.huge
		if travel > suppress_length then
			local avgStep = cum[len] / len
			-- if devMode and c == 1 then
			--  Echo('travel', cum[len], 'avgStep', avgStep, 'window_len', window_len, 'avgItems', (window_len*2)/avgStep, 'cum[len]', cum[len])
			-- end
			 -- fill up cum[0], cum[-1], cum[-2] ...
			local k = 1
			local winStart = 1
			local cumEnd = len
			if isLoop then
				local full_travel = cum[len]
				local from_start = 0
				for i = len-1, 1, -1 do
					from_start = full_travel - cum[i]
					winStart = i-len+1
					cum[winStart] = -from_start
					if from_start > max(window_len, angle_gap) then
						break
					end
				end
				-- Prolonge cum en avant (indices > len) : après len, on revisite virtuellement
				-- contour[2], contour[3]... puisque contour[len] == contour[1]
				for m = 2, len do
					local extra = cum[m]
					cumEnd = len + m - 1
					cum[cumEnd] = full_travel + extra
					if extra > max(window_len, angle_gap) then
						break
					end
				end
			end
			local function idx(i)
				if i < 1 then
					return i + len - 1
				elseif i > len then
					return i - len + 1
				else
					return i
				end
			end
			local r = math.round
			----
			if cum[len] > window_len then

				-- Passe 2 : angle de rotation en chaque point
				local turnAngle = {[1] = 0, [len] = 0} -- [1] = 0 [len] = 0 for non loop case
				local k = 1
				local j = winStart
				for i = 1, len do
					while cum[j] and cum[i] - cum[j] >= angle_gap do -- j is start of window
						j = j + 1
					end
					while cum[k+1] and cum[k+1] - cum[i] < angle_gap do -- k is end of window   
						k = k + 1
					end
					if j < i and i < k then
						local cur = contour[i]
						-- local pin, pout = contour[j<1 and len+j-1 or j], contour[k]
						local pin, pout = contour[idx(j)], contour[idx(k)]

						local turn = angleDiff(pin, cur, pout)
						turnAngle[i] = turn
						winJ[i], winK[i] = j, k
						if turn > maxTurn then maxTurn = turn end
						if turn < minTurn then minTurn = turn end

						-- local r = math.round
						-- local str = ('contour %d, [ %d=>%d cum%d <-- (%d=>%d/%d cum%d) --> %d=>%d cum%d ] angle: %.4f'):format(c , j, idx(j), r(cum[j]), i, idx(i), len, r(cum[i]), k, idx(k), r(cum[k]), turnAngle[i])
						-- Echo(str)
					end
				end
				-- Echo("len:"..tostring(len), 'isLoop', isLoop, '#turnAngle', #turnAngle)
				if isLoop then
					for i = winStart, 0 do
						turnAngle[i] = turnAngle[idx(i)]
					end
					for i = len + 1, cumEnd do
						turnAngle[i] = turnAngle[idx(i)]
					end
				end
				-- Passe 3 : 
				local i = 1
				local keep = {}
				if not isLoop then
					keep[1], keep[len] = DBG_EXTREMITY, DBG_EXTREMITY
					i = 2
				end
				local winEnd = 2
				local curves, too_sharps, noises, small_noises = 0, 0, 0, 0
				local accuAngle = 0
				local startCum = 0

				local lastAngleRaw, lastAngleTurn = false, false
				while i <= len - 1 do -- len -1 because: if not isLoop => we keep both extremities, if isLoop => first point window == last point window
					local turn = turnAngle[i]
					local startAccuI, endAccuI
					local isNoise = false
					--[[
					isNoise = abs((turnAngle[i-1] or 0) - (turnAngle[i+1] or 0)) < 0.001
					--isNoise = abs(turn + (turnAngle[i-1] or 0)) < 0.001
					if i < 20 then
						Echo(turn, (turnAngle[i-1] or 0))
					end
					if isNoise then
						if c == 1
							and i < 20
						then
							-- Echo(('#%d/%s [noise]'):format(i, len))
						end
						small_noises = small_noises + 1
					end
					i = i + 1
					]]
					-- [[
					local turnAbs = abs(turn)
					-- Echo(('# %d, turn: %.4f tol %s'):format(i, turn, tostring(turn <= angle_tolerance)))
					local foundNoise, foundAngle, foundCurve = false, false, false

					local tj = abs(turnAngle[winJ[i]] or 0)
					local tk = abs(turnAngle[winK[i]] or 0)
					if turnAbs > angle_tolerance 
						-- and turnAbs > 1.5 * max(tj, tk)
					then
						while cum[winStart] and cum[i] - cum[winStart] >= window_len do
							winStart = winStart + 1
						end
						while cum[winEnd+1] and cum[winEnd+1] - cum[i] < window_len do
							winEnd = winEnd + 1
						end

						local maxAngleI, maxAngleAbs = i, 0
						local maxAngle = 0
						local sum, sumPast, sumAbs = 0, 0, 0
						local dbg = devMode and c == 1 and ''
						for m = winStart, winEnd do
							dbg = dbg and dbg..('#%d (%.3f) | '):format(idx(m), turnAngle[m])

							local thisTurnAngle = turnAngle[m]
							local thisTurnAngleAbs = abs(thisTurnAngle)
							if thisTurnAngleAbs > maxAngleAbs then
								maxAngleI, maxAngleAbs = m, thisTurnAngleAbs
								maxAngle = thisTurnAngle
							end
							sum = sum + thisTurnAngle
							sumAbs = sumAbs + thisTurnAngleAbs
							if m >= i then
								sumPast = sumPast + thisTurnAngle
							end
						end
						-- Echo(('window [ %d <-> %d, maxI %d ]'):format(winStart, winEnd, maxAngleI))
						-- if devMode and c == 1 then
						--  Echo(('#%d/%d, Window %d angles ratio:%.2f, [ %s ]'):format(i, len, (winEnd - winStart + 1), abs(sum / sumAbs), dbg:sub(1, -3)))
						-- end
						if abs(sum / sumAbs) < 0.5 then -- detect noise, might need to tinker the 0.5 threshold
							-- if c == 1 then
							--  Echo(('#%d/%d, Found noise at%d ratio sum is %.3f on %.3f'):format(i, len, maxAngleI, abs(sum / sumAbs), cum[winEnd] - cum[winStart]))
							-- end
							foundNoise = winStart
							startAccuI, endAccuI = i, min(winEnd, len-1)

							i = winEnd + 1
						else -- detect sharp angle
							-- if c == 1 then
							--  Echo(('#%d/%d, Found maxAngle at %d: %.4f in window [ %d <- %d -> %d ], sum %.4f, avg %.4f'):format(i, len, maxAngleI, maxAngle, winStart, i, winEnd, sum, sum/(winEnd - winStart + 1)))
							-- end
							foundAngle = idx(maxAngleI)
							-- local MIN_RULER = 3 -- en dessous, la corde est trop courte pour donner un angle fiable
							-- local m = maxAngleI + 1
							-- while cum[m] and cum[m] - cum[maxAngleI] < angle_gap do
							-- 	local k = winK[m]
							-- 	if cum[m] - cum[maxAngleI] >= MIN_RULER and k and m < k then
							-- 		turnAngle[m] = angleDiff(contour[idx(maxAngleI)], contour[idx(m)], contour[idx(k)])
							-- 	end
							-- 	m = m + 1
							-- end
							if suppressCurvesFromCorners then
								lastAngleRaw = maxAngleI
								lastAngleTurn = maxAngle
								----- remove before
								local k = maxAngleI - 1
								local d, dprev = cum[maxAngleI], cum[k]
								while dprev and d-dprev < angle_gap/3 do
									if keep[k] == DBG_CURVE then
										keep[k] = nil
										curves = curves - 1
									end
									k = k - 1
									dprev = cum[k]
								end
							end

							accuAngle = 0
							startCum = cum[maxAngleI]
							startAccuI, endAccuI = max(maxAngleI+1, i), min(winEnd, len-1)
							-- startAccuI, endAccuI = i, winEnd
							-- startAccuI, endAccuI = winEnd + 1, winEnd -- will not iterate for accuAngle
							i = winEnd + 1
						end
					else
						startAccuI, endAccuI = i, i
						i = i + 1
					end

					-- detecting curves

					if foundAngle then
						local old = keep[foundAngle]
						if old ~= DBG_SHARP_ANGLE then
							-- if c == 1 then
							--  Echo(('[angle added %d]'):format(foundAngle))
							-- end
							if old ~= DBG_EXTREMITY then
								keep[foundAngle] = DBG_SHARP_ANGLE
							end
							too_sharps = too_sharps + 1
							if old == DBG_CURVE then curves = curves - 1 end
						end
					end
					for i = startAccuI, endAccuI do
						local t = turnAngle[i]
						if lastAngleRaw then
							local d = cum[i] - cum[lastAngleRaw]
							if d >= 0 and d < angle_gap then
								t = t - lastAngleTurn * (1 - d / angle_gap)
							end
						end
						local w = cum[i-1] and (cum[i] - cum[i-1]) / angle_gap or avgStep / angle_gap
						accuAngle = accuAngle + t * w
						-- accuAngle = accuAngle + turnAngle[i] * (cum[i] - cum[i-1]) / angle_gap
						if c == 1 then
							-- if devMode and turnAngle[i] ~= 0 and (i <= 20 or i >= len-20) then
							--  Echo(('accuAngle #%d %d/%d,%s%.3f = %.3f'):format(i, i-startAccuI+1, endAccuI-startAccuI+1, turnAngle[i] >= 0 and '+' or '', turnAngle[i], accuAngle))
							-- end
						end
						-- if abs(accuAngle) * (cum[i] - startCum) > arrow_limit * 8 or abs(accuAngle) > max_seg_angle then
						if CurveReady(abs(accuAngle), cum[i] - startCum) then
							-- Echo('foundCurve', i, idx(i))
							-- if not lastAngleRaw or cum[i] - cum[lastAngleRaw] > angle_gap then -- don't pose a curve just after a sharp angle
								foundCurve = i
								-- if devMode and c == 1 and (i <= 20 or i >= len-20)  then
								--  Echo(('#%d/%d, Found curve: accuAngle %s%.3f = %.3f in [ %d %d ]'):format(foundCurve, len, turnAngle[foundCurve] >= 0 and '+' or '', turnAngle[foundCurve], accuAngle, startAccuI, endAccuI))
								-- end
								if not keep[foundCurve] then
									keep[foundCurve] = DBG_CURVE
									-- if devMode and c == 1 then
									--  Echo(('[curve added %d]'):format(foundCurve))
									-- end
									curves = curves + 1
								end
							-- end
							accuAngle = 0
							startCum = cum[i]
						end
					end
					if foundNoise and not (foundCurve or foundAngle) then
						if devMode and c == 1 then
							-- Echo(('noise [ %d <-> %d ]'):format(foundNoise, i-1))
						end
						if isNoise then
							small_noises = small_noises + 1
						else
							noises = noises + 1
						end
					end
					--]]

				end
				-- if devMode and c <= 3 then
				--  local prev, maxGap, gi = nil, 0, nil
				--  for k = 1, len - 1 do
				--      if keep[k] then
				--          if prev and cum[k] - cum[prev] > maxGap then maxGap, gi = cum[k] - cum[prev], prev end
				--          prev = k
				--      end
				--  end
				--  Echo(('contour %d: plus long segment %.0f px (moyen %.0f), depuis #%s type %s')
				--      :format(c, maxGap, cum[len] / max(1, curves + too_sharps), tostring(gi), tostring(gi and keep[gi])))
				-- end
				if isLoop then -- completing the curvature after last kept point
					local F -- premier point gardé
					for k = 1, len - 1 do
						if keep[k] then F = k break end
					end
					local L
					for k = len, 1, -1 do
						if keep[k] then L = k break end
					end
					-- if devMode and c == 1 then
					--  Echo('FIRST KEPT', F, 'LAST KEPT', L, '-'..len-L, 'LEN', len)
					-- end
					if F then
						for k = 1, F - 1 do
							if keep[F] == DBG_SHARP_ANGLE and cum[F] - cum[k] < angle_gap then break end -- don't add just before a sharp angle
							local w = cum[k-1] and (cum[k] - cum[k-1]) / angle_gap or avgStep / angle_gap
							accuAngle = accuAngle + turnAngle[k] * w
							-- if abs(accuAngle) * (cum[len] - startCum + cum[k]) > arrow_limit * 8 or abs(accuAngle) > max_seg_angle then
							if CurveReady(abs(accuAngle), cum[len] - startCum + cum[k]) then
								if not keep[k] then
									keep[k] = DBG_CURVE
									-- if devMode and c == 1 then
									--  Echo('ADDED CURVE', k)
									-- end
									curves = curves + 1
								end
								-- if k >= F * 0.6 and keep[F] == DBG_CURVE then 
								--  keep[F] = nil
								--  curves = curves - 1
								-- end
								if keep[F] == DBG_CURVE and cum[k] > 0.6 * cum[F] then -- remove F curve if the new curve point is too close from curve F
									-- if devMode and c == 1 then
									--  Echo('REMOVED CURVE', F)
									-- end
									keep[F] = nil
									curves = curves - 1
								end
								break
							end
						end
					end
				end
				total_curves, total_too_sharps, total_noises, total_small_noises = total_curves + curves, total_too_sharps + too_sharps, total_noises + noises, total_small_noises + small_noises
				if console_debugging and c == 1 then
					Echo(" C1: total_curves:"..tostring(total_curves)..", total_too_sharps:"..tostring(total_too_sharps), 'total_noises:'..tostring(total_noises), 'total_small_noises:'..tostring(total_small_noises))
					Echo(
						('PARAMS[ size: %d (mul:%.2f), window_len: %.3f, angle_gap %.3f, tolerance: %.3f, avgItems: %.3f, suppress_length: %.2f'
							..' radius_ref: %.2f, arrow_limit: %.2f]')
						:format(size, self.mul, window_len, angle_gap, angle_tolerance, (window_len*2)/avgStep, suppress_length, radius_ref, arrow_limit)
					)
					Echo('minTurn', minTurn, 'maxTurn', maxTurn)
				end
				local simplified, s = {}, 0
				local first
				local prev, p_prev, p_p_prev
				local supp_count = 0
				for i = 1, len do
					local toKeep = keep[i]
					if toKeep then
						local point = contour[i]
						if isLoop and not first then
							first = point
							first[5] = --[[tonumber(toKeep) or ]]DBG_EXTREMITY
						elseif toKeep ~= true then
							point[5] = toKeep
						end
						if not p_prev or abs(angleDiff(p_prev, prev, point)) > 0.01 then
							s = s + 1
						else
							supp_count = supp_count + 1
							p_prev, prev = p_p_prev, p_prev
						end
						simplified[s] = point
						p_p_prev, p_prev, prev = p_prev, prev, point
					end
				end
				total_supp_count = total_supp_count + supp_count
				if first then
					local last = simplified[s]
					if first[1] ~= last[1] or first[2] ~= last[2] then
						s = s + 1
						simplified[s] = first
					end
				end
				if s > 1 then
					total_simplified = total_simplified + s
					contours[c] = simplified
				else
					contours[c] = nil
					deletion = true
				end
			else -- cum[len] <= window_len
				contour[1][5], contour[len][5] = DBG_EXTREMITY, DBG_EXTREMITY
			end
		else
			contours[c] = nil
			deletion = true
		end
		c = c + 1
		contour = contours[c]
	end

	if deletion then
		table.restoreArray(contours) 
	end
	if console_debugging then
		-- Echo(
		--  ('PARAMS[ size: %d (mul:%.2f), window_len: %.3f, tolerance: %.4f, suppress_length: %.2f ]')
		--  :format(size, self.mul, window_len, angle_tolerance, suppress_length)
		-- )
		Echo(('simplification: %d => %d, %d%%'):format(total_lines, total_simplified, 100*total_simplified/total_lines))
		Echo("total_curves:"..tostring(total_curves)..", total_too_sharps:"..tostring(total_too_sharps), 'total_noises:'..tostring(total_noises), 'total_small_noises:'..tostring(total_small_noises), 'total_supp_count:'..tostring(total_supp_count))
	end
	-- (inchangé) : suppression des contours trop courts
end

function MarkerMaker:SetScreenRatio()
	local onscreen_size = self.onscreen_size or p.onscreen_size.default
	self.screen_ratio = onscreen_size / math.diag((self.midx + self.midy) * 2)
	return
end

function MarkerMaker:ContourToLineObj(contours)
	local onscreen_size = self.onscreen_size or p.onscreen_size.default
	local analyze_size = self.useDefault and p.analyze_size.default or self.analyze_size
	table.sort(contours, SortByLength)
	local lines, l = {}, 0
	local bottom, top = huge, -huge
	local left, right = huge, -huge
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
			Echo(sig..self.filename .. ' !no line at contour ' .. i)
		end
	end
	self.l = l
	local midx, midy = ((right or left) - left) / 2, ((top or bottom) - bottom) / 2
	midx, midy = math.max(midx, 0.5), math.max(midy, 0.5)
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
	glTexture(0, file)
	local info = glTextureInfo(file)
	if not info or info.xsize == -1 then
		Echo(sig.."CAN'T LOAD FILE " .. file)
		glTexture(0, false)
		glDeleteTexture(file)
		return
	end
	local analyze_size, onscreen_size, pix_detect
	if self.useDefault then
		analyze_size = p.analyze_size.default
		pix_detect = p.pix_detect.default
	else
		analyze_size = self.analyze_size
		pix_detect = self.pix_detect
	end
	onscreen_size = self.onscreen_size or p.onscreen_size.default
	local sizeX = info.xsize
	local sizeY = info.ysize
	local diag = math.diag(sizeX, sizeY)
	local mul = analyze_size / diag
	self.sizeX, self.sizeY = sizeX, sizeY
	self.mul = mul
	sizeX = sizeX * mul
	sizeY = sizeY * mul
	-- Echo("sizeX:"..tostring(sizeX)..", sizeY:"..tostring(sizeY))

	local temp_screen_ratio = onscreen_size / analyze_size -- FIXME the real screen_ratio will be defined by getting the top, left, right, bottom later :(
	-- FIXME gl.ReadPixels is bugged when asking a map (w > 1 and h > 1), giving values at the wrong place
	-- so we ask line by line...
	local lines, l = {}, 0
	local left, right = huge, -huge
	local modf = math.modf
	local skip = modf(1/temp_screen_ratio) -- reduce the number of line
	if skip < 2 then
		skip = false
	end
	local tex = gl.CreateTexture(sizeX, sizeY, {
		format = GL.RGBA8,
		fbo = true,
	})


	gl.RenderToTexture(tex, function()
		gl.Clear(GL.COLOR_BUFFER_BIT)
		glTexRect(-1, -1, 1, 1)
		-- FIXME gl.ReadPixels is bugged when asking a map (w > 1 and h > 1), giving misaligned values
		-- so we ask line by line...
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
							end
							line[3], line[4] = lastX, lastY
							line = false
						else
							lastX, lastY = x, y
						end
						if lastX > right then
							right = lastX
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
	end)
	glTexture(0, false)
	gl.DeleteTextureFBO(tex)
	glDeleteTexture(tex)
	glDeleteTexture(file)
	if l == 0 then
		Echo('!No lines created from', file)
		self.midx = 25 self.midy = 25
		return {}
	end

	bottom, top = lines[l][2], lines[1][2]

	self.l = l

	local midx, midy = ((right or left) - left) / 2, (top - bottom) / 2
	midx, midy = math.max(midx, 0.5), math.max(midy, 0.5)
	local offx, offy = -left - midx, -top + midy
	for i, line in ipairs(lines) do
		line[1], line[2], line[3], line[4] =
			line[1] + offx,
			line[2] + offy,
			line[3] + offx,
			line[4] + offy
	end
	self.midx, self.midy = midx, midy
	return lines
end



function MarkerMaker:AddLineObj(index, isLoaded)
	self:SetScreenRatio()
	if not isLoaded then
		self.filename = self.file:gsub(DRAWINGS_DIR, '')
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
	local visual_debug = self.lines[1] and self.lines[1][5]
	if visual_debug then
		self.dbg_list = gl.CreateList(
			function()
				gl.BeginEnd(
					GL.LINES,
					function()
						local lines = self.lines
						for i, line in ipairs(lines) do
							local next_line = lines[i+1]
							local isCurve = next_line and next_line[5] == DBG_CURVE
							if isCurve then
								glColor(KIND_COLORS[DBG_CURVE])
							end
							glVertex(line[1], line[2], 0)
							glVertex(line[3], line[4], 0)
							if isCurve then
								glColor(LINE_COLOR)
							end

						end
					end
				)
				if visual_debug then
					gl.PointSize(1.5)
					gl.BeginEnd(
						GL.POINTS,
						function()
							for i, line in ipairs(self.lines) do
								local dbg_kind = line[5]
								local dbg_color = (dbg_kind == DBG_CURVE or dbg_kind == DBG_EXTREMITY or dbg_kind == DBG_SHARP_ANGLE) and KIND_COLORS[dbg_kind]
								if dbg_color then
									glColor(dbg_color)
									glVertex(line[1], line[2], 0)
								end
							end
						end
					)
					glColor(LINE_COLOR)
					gl.PointSize(1)
				end

			end
		)
	end
	self.list = gl.CreateList(
		gl.BeginEnd,
		GL.LINES,
		function()
			for i, line in ipairs(self.lines) do
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
	local w = SELECTOR_BUTTON_W 
	local wmargin = SELECTOR_BTN_PADDING[1] + SELECTOR_BTN_PADDING[3]
	local hmargin = SELECTOR_BTN_PADDING[2] + SELECTOR_BTN_PADDING[4]
	local hratio = (obj.midy+1) / (obj.midx+1)
	-- for reducing image when height ratio is too big and repositionning at the middle of the button
	local reduce = 1
	if hratio > 2 then
		reduce = 2 / hratio
		hratio = 2
	end
	local h = (w - wmargin) * (hratio) + hmargin
	h = math.floor(h + 0.5)
	h = h + 2
	local y
	local off = 0
	local control = WG.Chili.Button:New{
		caption = '',
		tooltip = '#' .. index .. ' ' .. obj.filename,
		y = y,
		width = w,
		height = h,
		backgroundColor = backgroundColor,
		padding = SELECTOR_BTN_PADDING,
		OnMouseDown = {
			function(self)
				local mx, my, leftButton, _, rightButton = spGetMouseState()
				if rightButton then
					obj:SetupCustomPanel()
					customPanel.win:Show()
				elseif select(3, spGetModKeyState()) then
					WG.crude.OpenPath(widget.options_path)
					return true
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
				drawcontrolv2 = true,
				DrawControl = function(self)
					local ratio = self.width / (obj.midx * 2)
					ratio = ratio * 0.9
					glPushMatrix()
					glColor(LINE_COLOR)
					glTranslate(self.width/2, self.height/2, 0)
					glScale(ratio * reduce, ratio * reduce, 1)
					glScale(1,-1,1)
					glCallList(obj.list)
					glPopMatrix()
					glColor(1,1,1,1)
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
	local len = #self.lines
	customPanel.win.caption = ('%s  (%d lines, %d sec to draw)'):format(self.filename, len, math.ceil(MARKER_DELAY * len))
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

	for _, name in ipairs(CUSTOM_PARAMS_ORDER) do
		if p[name].generic then
			local control = customPanel[name]
			if control then
				local value = self[name]
				local header = customPanel['header_'..name]
				local caption = header.caption:gsub(': %d.*$', '')
				if control.value ~= value then
					control:SetValue(value)
				end
				header:SetCaption(('%s: '..(p[name].format)):format(caption, value))
			end
		end
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

do
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
end

function MarkerMaker:PrepareMarker()
	if selected ~= self then
		Echo(sig..'Drawing Marker Obj Selection Mismatch !')
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
	local mx, my = self.mx, self.my
	local dirx, diry = self.onMapDirX, self.onMapDirY
	local watch_duplicate = self.s_mode == 'plain' or self.s_mode == 'spaghetti'
	local lastline = {-1,-1,1e8,-1}
	local min, max, r = math.min, math.max, math.round
	for i = 1, #lines do
		local line = lines[i]
		local x1, y1, x2, y2 = line[1] * (dirx or 1), line[2] * (diry or 1), line[3] * (dirx or 1), line[4] * (diry or 1)
		local _, c1 = spTraceScreenRay(mx + x1 * screen_ratio, my + y1 * screen_ratio, true, false, false, false) --onlyCoords, useMinimap, includeSky, ignoreWater
		local _, c2 = spTraceScreenRay(mx + x2 * screen_ratio, my + y2 * screen_ratio, true, false, false, false)
		if c1 and c2 then
			local draw = true
			if watch_duplicate then
				---- ignore lines that will not be drawn anyway
				local nwy1, nwy2, nwx1, nwx2 = r(c1[3]), r(c2[3]), r(c1[1]), r(c2[1])
				local wy1, wy2, wx1, wx2 = lastline[1], lastline[2], lastline[3], lastline[4]
				if nwx1 > nwx2 then nwx1, nwx2 = nwx2, nwx1 end
				if nwy1 == wy1 and nwy2 == wy2 then
					if nwx1 >= wx1 and nwx2 <= wx2 then
						draw = false
					end
					nwx1, nwx2 = min(nwx1, wx1), max(nwx2, wx2)
				end
				lastline[1], lastline[2], lastline[3], lastline[4] = nwy1, nwy2, nwx1, nwx2
			end
			-----
			if draw then
				l = l + 1
				toDraw[l] = {c1, c2}
			end
		end
	end
	return l
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
			if not conform then
				customParams = loaded
				loaded = nil
			end
		end
	else
		conform = obj:IsConform()
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

local Timer = Spring.GetTimer
local Diff = Spring.DiffTimers
function MarkerMaker:UpdateFiles()
	local files = VFS.DirList(DRAWINGS_DIR, ALLOWED_FORMATS, VFS.RAW)
	local count = 0
	if not files[current] then
		current = 1
	end
	local time = 0
	local timer = Timer()
	local batchUpdated = 0
	for i, file in ipairs(files) do
		files[file] = true
		count = count + 1
		if count >= current and time <= max_update_time then
			self:UpdateFile(file, i)
			local endTimer = Timer()
			time = time + Diff(endTimer, timer)
			timer = endTimer
			current = count + 1
			batchUpdated = batchUpdated + 1
		end
		
		-- end
	end
	-- Echo('batchUpdated', batchUpdated)
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
	--  updateCategories = 0
	-- end
end

function MarkerMaker:Remove(fastUpdate)
	if selected == self then
		selected:Deselect()
	end
	if self.list then
		gl.DeleteList(self.list)
	end
	if self.dbg_list then
		gl.DeleteList(self.dbg_list)
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
		Echo(sig..'Removed the wrong obj, '..self.filename..', file didn\'t have the correct index ' .. self.index .. ', instead '..rem.filename..' got removed')
	end
	holder[self.file] = nil

	for i = index, #holder do
		if not holder[i] then
			Echo(sig..'Indexing problem! Trying to reindex image from #'.. i .. ' to', #holder)
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
			Echo(sig..'Object missing at index', i, 'after removing', self.filename, 'at index', self.index)
			err = true
		end
	end
	if err then
		error()
	end

	selector:RemoveChild(self.control)
	scroll:UpdateLayout()
	updateCategories = 0
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
			if not WG.Chili.Screen0.hoveredControl then
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
		if markerTime > MARKER_DELAY then
			markerTime = 0
			currentMarkerLine = currentMarkerLine + 1
			if pendingLists[currentMarkerLine] then
				glDeleteList(pendingLists[currentMarkerLine])
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
		glCallList(list)
	end
end
function widget:DrawScreen()
	if not initialized then
		Init()
		MarkerMaker:UpdateFiles()
		updateTime = update_delay
	end
	if updateTime >= update_delay then
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
				if FileExists(file, VFS.RAW) then
					-- Echo('tasking', file, 'index:', index, 'cp', customParams)
					MarkerMaker:New(file, index, customParams)
				end
				tasks[file] = nil
				break
			end
		end
		taskTime = 0
	end

	if selected then
		local mx, my  = spGetMouseState()
		glPushMatrix()
		if selected.pressed then
			glTranslate(selected.mx, selected.my, 0)
		else
			glTranslate(mx, my, 0)
		end
		glScale(selected.onMapDirX * selected.screen_ratio, selected.onMapDirY * selected.screen_ratio, 1)
		glCallList(selected.list)
		if placing_frame then
			glScale(selected.midx, selected.midy, 1)
			glCallList(frame)
		end
		glPopMatrix()
	end
	if customize and showMultFrame then
		glPushMatrix()
		glTranslate(vsx/2, vsy/2, 0)
		glScale(showMultFrame * customize.midx * customize.screen_ratio, showMultFrame * customize.midy * customize.screen_ratio, 1)
		glCallList(frame)
		glPopMatrix()
	end
	if showFrame then
		glPushMatrix()
		glTranslate(vsx/2, vsy/2, 0)
		local side = hyp_to_side(showFrame)
		glScale(side/2, side/2, 1)
		glCallList(frame)
		glPopMatrix()
	end

end

function widget:Initialize()
	widget:ViewResize(Spring.GetViewGeometry())
end

function widget:Shutdown()
	for _, obj in ipairs(holder) do
		if obj.list then
			glDeleteList(obj.list)
		end
		if obj.dbg_list then
			glDeleteList(obj.dbg_list)
		end
	end
	for _, list in pairs(pendingLists) do
		glDeleteList(list)
	end
	glDeleteList(frame)
end


function widget:ViewResize(viewSizeX, viewSizeY)
	scaled_vsx, scaled_vsy = viewSizeX, viewSizeY
	vsx, vsy = Spring.Orig.GetViewGeometry()
end

if f then
	f.DebugWidget(widget)
end
