--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "Widget Profiler New 2",
		desc      = "",
		author    = "jK, Bluestone, rewrite, improved, and optimized Helwor",
		version   = "2.0",
		date      = "2007+",
		license   = "GNU GPL, v2 or later",
		layer     = math.huge,
		handler   = true,
		enabled   = true
	}
end
local profilerName = widget.GetInfo().name
local profilerStats = {''}

local WATCHDOG_MODE = false
local watchdog_threshold = 0.1
local watchdog_threshold_framework = 0.3
local WANT_MEM_USAGE = false
local SORT_ALPHABETICAL = false
local MIN_TIME_PER = 5
local tick = 2
local averageTime = 4
local upd_round = 0
local init_round = 15
local glText = gl.Text
local vsx, vsy
local usePrefixedNames = true
local PROFILE_POS_X = 425
local PROFILE_POS_Y = 80
local COL_SPACING = 420
local WATCHDOG = {}
local WATCHDOG_IDX = 0
local hooked
local winObjects = {}
local recapWin
local Echo = Spring.Echo
local Chili
local Start, Stop
local StartHook, StopHook
local Init
local enabled = false

options_path = 'Hel-K/' .. widget:GetInfo().name
options = {
	enable = {
		type = 'bool',
		name = 'Enable profiling',
		value = enabled,
		OnChange = function(self)
			enabled = self.value
			if enabled then
				if upd_round >= init_round then
					Start()
				end
			else
				Stop()
			end
		end,
	},
	watchDog = {
		type = 'bool',
		name = 'Watch Dog Mode',
		value = WATCHDOG_MODE,
		OnChange = function(self)
			WATCHDOG_MODE = self.value
			if enabled then
				Init()
			end
		end,
	},
	updateRate = {
		name = 'Update Rate',
		type = 'number',
		value = tick,
		min = 0.1, max = 4, step = 0.1,
		update_on_the_fly = true,
		OnChange = function(self)
			tick = self.value
			averageTime = math.max(averageTime, tick)
		end,
		linkToControls = {},

	},
	smoothingTime = {
		name = 'Smoothing Time',
		type = 'number',
		value = averageTime,
		min = 0.5, max = 10, step = 0.5,
		update_on_the_fly = true,
		OnChange = function(self)
			averageTime = math.max(self.value, tick)
		end
	},
	watchdog_threshold = {
		name = 'Watch Dog Threshold',
		desc = 'Minimal time spent that trigger a warning in second.',
		type = 'number',
		value = watchdog_threshold,
		min = 0.001, max = 0.2, step = 0.001,
		update_on_the_fly = true,
		OnChange = function(self)
			watchdog_threshold = self.value
		end,

	},
	watchdog_threshold_framework = {
		name = 'Watch Dog Threshold Framework',
		desc = 'Minimal time spent that trigger a warning for Chili Framework.',
		type = 'number',
		value = watchdog_threshold_framework,
		min = 0.001, max = 0.5, step = 0.001,
		update_on_the_fly = true,
		OnChange = function(self)
			watchdog_threshold_framework = self.value
		end,

	},
	show_mem = {
		name = 'Show Memory Usage',
		type = 'bool',
		value = WANT_MEM_USAGE,
		OnChange = function(self)
			WANT_MEM_USAGE = self.value
		end
	},
	sort_alpha = {
		name = 'Sort Alphabetically',
		desc = 'Getting widgets at fixed position.',
		type = 'bool',
		value = SORT_ALPHABETICAL,
		OnChange = function(self)
			SORT_ALPHABETICAL = self.value
		end
	},
	min_filter = {
		name = 'Filter Min Time % Consumers',
		desc = 'Filter out unconsequential widgets',
		min = 0, max = 0.8, step = 0.01,
		type = 'number',
		value = MIN_TIME_PER,
		OnChange = function(self)
			MIN_TIME_PER = self.value
		end,
		tooltipFunction = function(self)
			return ('%.2f%%'):format(self.value)
		end,
	},
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local callinStats = {}

local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local spGetLuaMemUsage = Spring.GetLuaMemUsage
local concat = table.concat
local exp = math.exp
local floor = math.floor
local char = string.char
local max = math.max
local min = math.min
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function ArrayInsert(t, f, g)
	if (f) then
		local layer = g.whInfo.layer
		local index = 1
		for i,v in ipairs(t) do
			if (v == g) then
				return -- already in the table
			end
			if (layer >= v.whInfo.layer) then
				index = i + 1
			end
		end
		table.insert(t, index, g)
	end
end


local function ArrayRemove(t, g)
	for k,v in ipairs(t) do
		if (v == g) then
			table.remove(t, k)
			-- break
		end
	end
end

local function RemoveWindows()
	if recapWin then
		recapWin.win:Dispose()
		recapWin = nil
		for name, winObj in pairs(winObjects) do
			winObj.win:Dispose()
			winObjects[name] = nil
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local prefixedWnames = {}
local prefixes = {}
local function ConstructPrefixedName (whInfo, name)
	local widgetName = name or whInfo.name
	local baseName = whInfo.basename
	local _pos = baseName:find("_", 1)
	-- local prefix = ((_pos and usePrefixedNames) and "["..(baseName:sub(1, _pos-1).."] ") or "[--] ")
	local prefix = ((_pos and usePrefixedNames) and (baseName:sub(1, _pos-1)..": ") or "")
	local prefixedWidgetName = "\255\200\200\200" .. prefix .. "\255\255\255\255" .. widgetName
	
	prefixedWnames[widgetName] = prefixedWidgetName
	return prefixedWidgetName
end

local function GetPrefix(whInfo, name)
	local widgetName = name or whInfo.name
	local baseName = whInfo.basename
	local _pos = baseName:find("_", 1)
	-- local prefix = ((_pos and usePrefixedNames) and "["..(baseName:sub(1, _pos-1).."] ") or "[--] ")
	local prefix = ((_pos and usePrefixedNames) and (baseName:sub(1, _pos-1)..": ") or "")
	if prefix == ": " then
		prefix = ""
	else
		prefix = "\255\200\200\200" .. prefix .. "\255\255\255\255"
	end
	
	prefixes[widgetName] = prefix
	return prefix
end





-- TextBox

local function CreateWindow(name,height,caption, shutdown)
	local win = Chili.Window:New{
		parent = Chili.Screen0,
		y = 35,
		height = height or 600,
		width = 500,
		horizontalScrollbar = false,
		verticalScrollbar = false,
		caption = caption or name,
		OnDispose = {
			function(self)

			end
		},
		itemPadding = {0,0,0,0},
		padding = {0,0,0,0},
		-- ,autosize = true
		-- ,height =800
		-- ,width = 800

	}

	-- local scroll = Chili.ScrollPanel:New{
	-- 	parent = win
	-- 	,x = 0
	-- 	,y = 24
	-- 	,right = 0
	-- 	,left = 0
	-- 	,top = 0
	-- 	,autosize = true
	-- 	,align = "left"
	-- 	,valign = "left"
	-- 	-- ,verticalSmartScroll = true
	-- 	,fontsize = 12
	-- 	,bottom = 0
	-- 	-- workaround to trigger the text updating on scroll, but there's probably a more decent way to do it
	-- 	,Update = function(self,...) self.children[1]:Invalidate() self.inherited.Update(self,...)   end
	-- }
	-- local textControl = Chili.TextBox:New{
	local profHeader = Chili.Label:New{
		parent = win,
		x= 15,y = 40,
		autosize = false,
		width = 1000,
		valign = 'top',
		autoArrangeH = false,
		autoArrangeV = false,
		-- parent = scroll,
		-- autosize = true,
		-- text=name..'\nTEXT...',
		caption = 'Profiler Consumption: -',
		OnParentPost = {function(self) self.font.size = 10 end }
	}

	local scrollPanel = Chili.ScrollPanel:New{
		parent = win,
		backgroundColor = {0, 0, 0, 0},
		color = {0, 0, 0, 0},
		borderColor = {0, 0, 0, 0},
		-- border = {0,0,0,0},
		width = '100%',
		height = '100%',
		y = profHeader.y + profHeader.height + 1, 
		bottom = 13,
		-- top = 13,

		-- minHeight = 100,
		-- autosize = true,
		-- scrollbarSize = 6,
		horizontalScrollbar = false,
        padding = {0,-7,0,0},
        -- itemPadding = {0,-7,0,0},
        -- itemMargin = {0,-7,0,0},
        -- margin =  {0,-7,0,0},
        -- itemPadding = {0,-25,0,0},
	}

	local label = Chili.Label:New{
		parent = scrollPanel,
		x = 15,
		y = 5,
		autosize = true,
		width = 1000,
		height = 50,
		valign = 'top',
		autoArrangeH = false,
		autoArrangeV = false,
		-- parent = scroll,
		-- autosize = true,
		-- text=name..'\nTEXT...',
		caption = name..'\nTEXT...',
		OnParentPost = {function(self) self.font.size = 10 end }
	}


	local shutdown = Chili.Button:New{
		x = -25,
		width = 25,
		y = 2, height = 20,
		caption = "X",
		OnClick = {
			function(self)
				Stop()
				options.enable.value = false; options.enable:OnChange()
				-- widgetHandler:ToggleWidget(widget:GetInfo().name)
			end
		},
		parent = win,
	}

	local button = Chili.Button:New{
		x = -100,
		width = 75,
		y=2, height = 20,
		caption="Stop",
		OnClick = {
			function(self)
				local newcaption
				if hooked then
					StopHook()
					newcaption = 'Start'
				else
					StartHook()
					newcaption = 'Stop'
				end
				for k, v in pairs(winObjects) do
					v.button.caption = newcaption
					v.button:Invalidate()
				end
				recapWin.button.caption = newcaption
				recapWin.button:Invalidate()

			end
		},
		parent = win,
	}

	local function ImplementLinkedTrackBar(option, off)
		local numberPanel = WG.Chili.Panel:New{
			x = (5 + (off or 0))..'%',
			y = 5,
			width = "28%",
			height = 35,
			backgroundColor = {0, 0, 0, 0},
			padding = {0, 0, 0, 0},
			margin = {0, 0, 0, 0},
			--itemMargin = {2, 2, 2, 2},
			autosize = false,
		}
		-- FIXME: multiple origOnChange due to multiple control created, the real origOnChange is not kept track of
		-- if not origOnChange then
		-- 	origOnChange = options.updateRate.OnChange
		-- end

		local trackbar = WG.Chili.Trackbar:New{
			y = 14,
			width = "100%",
			caption = option.name,
			value = option.value,
			min = option.min or 0,
			max = option.max or 100,
			step = option.step or 1,
			useValueTooltip = not option.tooltipFunction,
			tooltipFunction = function(self, ...) -- TODO: imperfect work around because we add something to the tooltip, if we add tooltipFunction while there is none in the original option the default behaviour of gui_epicmenu for formatting will not be respected
				local ret = option.name .. ': '
				if option.tooltipFunction then
					ret = ret .. option:tooltipFunction(...)
				elseif option.tooltip_format then
					ret = ret .. (option.tooltip_format):format(self.value)
				else
					local sdec, dec = tostring(option.step):find('%.[0]*%d')
					if dec then
						dec = dec - sdec
					end
					ret = ret .. (dec and '%.'..dec..'f' or '%s'):format(self.value)
				end
				return  ret
			end,
			tooltip_format = option.tooltip_format,
			-- OnDispose = {
			-- 	function(self)
			-- 		option.OnChange = origOnChange
			-- 	end
			-- }
		}
		numberPanel:AddChild(trackbar)
		win:AddChild(numberPanel)
 		-- change option update to include the parallel trackbar original update
		-- option.OnChange = function(self)
		-- 	origOnChange(self)
		-- 	WG.Chili.Trackbar.SetValue(trackbar, self.value)
		-- end
		WG.crude.LinkOptionToControl(option, trackbar)

		-- this parallel control pass the value to and trigger the option update which will in turn Set the value in here properly


	end
	ImplementLinkedTrackBar(options.updateRate)
	ImplementLinkedTrackBar(options.min_filter, 50)

	if WG.MakeMinizable then
		WG.MakeMinizable(win, true)
	end
	local winObj = {}
	winObj.text = label
	winObj.win = win
	winObj.scrollPanel = scrollPanel
	winObj.button = button
	winObj.profHeader = profHeader
	return winObj
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- make a table of the names of user widgets
local userWidgets = {}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local oldUpdateWidgetCallIn
local oldInsertWidget

local listOfHooks = {}
setmetatable(listOfHooks, { __mode = 'k' })

local inHook = false
local function IsHook(func)
	return listOfHooks[func]
end

local function Hook(w, cname) -- cname is the callin
	local wname = w.whInfo.name

	-- wname = prefixedWnames[widgetName] or ConstructPrefixedName(w.whInfo)

	local realFunc = w[cname]
	w["_old" .. cname] = realFunc

	-- if (widgetName=="Widget Profiler New") then
	-- 	-- return realFunc -- don't profile the profilers callins (it works, but it is better that our DrawScreen call is unoptimized and expensive anyway!)
	-- end

	local widgetCallinTime = callinStats[wname]
	if not widgetCallinTime then
		widgetCallinTime = {}
		callinStats[wname] = widgetCallinTime
	end
	local c = widgetCallinTime[cname]
	if not c then
		c = {0,0,0,0}
		widgetCallinTime[cname] = c
	end

	local t

	local helper_func = function(...)
		local dt = spDiffTimers(spGetTimer(),t)
		if dt > 0.075 then
			-- Echo(name .. ' in ' .. widgetName .. ' took more than 0.075 sec: ' .. ('%.2f'):format(dt),'Active command ?',Spring.GetActiveCommand())
		end
		c[1] = c[1] + dt
		c[2] = c[2] + dt
		if WANT_MEM_USAGE then
			local _,_,new_s,_ = spGetLuaMemUsage()
			local ds = new_s - s
			c[3] = c[3] + ds
			c[4] = c[4] + ds
		end
		inHook = nil
		return ...
	end

	local hook_func = function(...)
		if (inHook) then
			return realFunc(...)
		end

		inHook = true
		t = spGetTimer()
		if WANT_MEM_USAGE then
			local _, _, new_s, _ = spGetLuaMemUsage()
			s = new_s
		end
		return helper_func(realFunc(...))
	end

	listOfHooks[hook_func] = true

	return hook_func
end

StartHook = function()
	if hooked then
		return
	end
	Spring.Echo("start profiling")

	local wh = widgetHandler

	local CallInsList = {}
	for name, e in pairs(wh) do
		local i = name:find("List")
		if i and type(e) == "table" then
			CallInsList[#CallInsList+1] = name:sub(1,i-1)
		end
	end

	--// hook all existing callins
	for _,callin in ipairs(CallInsList) do
		local callinGadgets = wh[callin .. "List"]
		for _,w in ipairs(callinGadgets or {}) do
			w[callin] = Hook(w,callin)
		end
	end

	Spring.Echo("hooked all callins")

	--// hook the UpdateCallin function
	oldUpdateWidgetCallIn =  wh.UpdateWidgetCallIn
	wh.UpdateWidgetCallIn = function(self,name,w)
		local listName = name .. 'List'
		local ciList = self[listName]
		if (ciList) then
			local func = w[name]
			if (type(func) == 'function') then
				if (not IsHook(func)) then
					w[name] = Hook(w,name)
				end
				ArrayInsert(ciList, func, w)
			else
				ArrayRemove(ciList, w)
			end
			self:UpdateCallIn(name)
		else
			print('UpdateWidgetCallIn: bad name: ' .. name)
		end
	end

	Spring.Echo("hooked UpdateCallin")

	--// hook the InsertWidget function
	oldInsertWidget =  wh.InsertWidget
	if wh.OriginalInsertWidget then
		oldInsertWidget = wh.OriginalInsertWidget
	else
		oldInsertWidget = wh.InsertWidget
	end

	widgetHandler.InsertWidget = function(self,widget)
		if (widget == nil) then
			return
		end
		GetPrefix(widget.whInfo)
		oldInsertWidget(self,widget)

		for _,callin in ipairs(CallInsList) do
			local func = widget[callin]
			if (type(func) == 'function') then
				widget[callin] = Hook(widget,callin)
			end
		end
	end
	hooked = true
	Spring.Echo("hooked InsertWidget")
end


StopHook = function()
	if not hooked then
		return
	end
	Spring.Echo("stop profiling")

	local wh = widgetHandler

	local CallInsList = {}
	for name,e in pairs(wh) do
		local i = name:find("List")
		if i and type(e) == "table" then
			CallInsList[#CallInsList+1] = name:sub(1,i-1)
		end
	end

	--// unhook all existing callins
	for _,callin in ipairs(CallInsList) do
		local callinWidgets = wh[callin .. "List"]
		for _,w in ipairs(callinWidgets or {}) do
			if (w["_old" .. callin]) then
				w[callin] = w["_old" .. callin]
			end
		end
	end

	Spring.Echo("unhooked all callins")

	--// unhook the UpdateCallin and InsertWidget functions
	wh.UpdateWidgetCallIn = oldUpdateWidgetCallIn
	Spring.Echo("unhooked Handler UpdateCallin")
	if wh.OriginalInsertWidget then
		wh.OriginalInsertWidget = oldInsertWidget
	else
		wh.InsertWidget = oldInsertWidget
	end
	Spring.Echo("unhooked Handler InsertWidget")
	hooked = false
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local timeLoadAverages = {}
local spaceLoadAverages = {}
local startTimer

local lm,_,gm,_,um,_,sm,_ = spGetLuaMemUsage()

local totalTime = 0
local allOverTimeSec = 0 -- currently unused
local totalMem = 0
local totalSpace = {}

local fullList = {}

local deltaTime
local redStrength = {}

local minPerc = 0.0025 -- above this value, we fade in how red we mark a widget
local maxPerc = 0.05 -- above this value, we mark a widget as red
local minSpace = 10 -- Kb
local maxSpace = 1000

local title_colour = "\255\160\255\160"
local totals_colour = "\255\200\200\255"
local STRING_COL_MUL = ((255-64)/255)
local function ColourString(R,G,B)
	local R255 = floor(R*255)
	local G255 = floor(G*255)
	local B255 = floor(B*255)
	if (R255%10 == 0) then R255 = R255+1 end
	if (G255%10 == 0) then G255 = G255+1 end
	if (B255%10 == 0) then B255 = B255+1 end
	return "\255"..char(R255)..char(G255)..char(B255)
end
local function GetRedColourStrings(v, max_w_space) --tRatio is %
	local tTime = v.tTime
	local sLoad = v.sLoad
	local name = v.wname
	local u = exp(-deltaTime/5) --magic colour changing rate

	if tTime > maxPerc then tTime = maxPerc end
	if tTime < minPerc then tTime = minPerc end

	-- time
	local new_r = (tTime-minPerc) / (maxPerc-minPerc)
	local redStrT = redStrength[name..'_time'] or 0
	redStrT = u*redStrT + (1-u)*new_r
	local r,g,b = 1, 1-redStrT * STRING_COL_MUL, 1-redStrT * STRING_COL_MUL
	v.timeColourString = ColourString(r,g,b)
	redStrength[name..'_time'] = redStrT
	-- space
	if max_w_space then
		local redStrS = redStrength[name..'_space'] or 0
		new_r = max(0, min(1,(sLoad-minSpace)/(maxSpace-minSpace)))
		redStrS = u * redStrS + (1-u)*new_r
		g = 1-redStrS * STRING_COL_MUL
		b = g
		v.spaceColourString = ColourString(r,g,b)
		redStrength[name..'_space'] = redStrS
	end
end
local function CalcLoad(old_load, new_load, t)
	return old_load * exp(-tick/t) + new_load*(1 - exp(-tick/t))
end


local function SortByTime(a,b)
	local aratio, bratio = a.tRatio, b.tRatio
	if aratio < 0.1 and bratio < 0.1 or aratio == bratio then
		return a.wname:lower() < b.wname:lower()
	else
		return aratio > bratio
	end
end
local function SortAlpha(a, b)
	return a.wname:lower() < b.wname:lower()
end
function DrawWidgetList(list, name)
	local part1 = ('%.2f%%'):format(list.totalTime)
	local part2 = WANT_MEM_USAGE and (('%.0f'):format(list.totalMem) .. 'kB/s') or ''
	local caption = title_colour..name.." WIDGETS ".. part1 .. ' ' .. part2
	local t = {
		-- title_colour..name.." WIDGETS".. '\n'
		-- 	.. title_colour..part1..('  '):rep(16-part1:len())
		-- 	.. title_colour..part2

	}
	winObjects[name] = winObjects[name] or CreateWindow(name, nil, caption)
	local winObj = winObjects[name]
	if caption ~= winObj.win.caption then
		winObj.win.caption = caption
		winObj.win:Invalidate()
		-- if winObj.win.InvalidateSelf then
		-- 	winObj.win:InvalidateSelf()
		-- else
		-- 	winObj.win:Invalidate()
		-- end
		-- winObj.win:RequestUpdate()
	end
	-- winObj.win:UpdateClientArea()

	local want_mem = WANT_MEM_USAGE
	local min_time = MIN_TIME_PER
	-- winObj.win:Resize(winObj.win.width,winObj.win.height)
	-- Echo("winObj.text.classname is ", winObj.parent.parent.caption)
	
	local j = 0
	for i = 1, #list do
		local v = list[i]
		local tRatio = v.tRatio
		if tRatio >= min_time or v.wname == profilerName then
			-- engine bug float cannot be aligned at all, and alignement of strings of numbers are not good enough, '\t' is just the space needed to adjust per number missing
			local off0 = tRatio < 10 and 1 or 0
			tRatio = ('\t'):rep(off0)..('%.2f'):format(tRatio)
			local tTime = v.tTime * 1000
			local off1 = tTime < 10 and 3 or tTime < 100 and 2 or tTime < 1000 and 1 or 0
			tTime = ('\t'):rep(off1)..('%d'):format(tTime)
			----- decomposing
			-- local part1 = ('%10s%%'):format(tRatio)
			-- local part2 = ('%7sms'):format(tTime)
			-- local part3 = ('%10s'):format(v.spaceColourString)
			-- local part4 = ('%11skB'):format(sLoad)
			-- local part6 = ('%s'):format(v.fullname)
			-- t[j] = v.timeColourString .. part1 .. part2 .. part3 .. part4 .. part5
			-----
			local str
			if want_mem then
				local sLoad = v.sLoad
				local off2 = sLoad < 10 and 4 or sLoad < 100 and 3 or sLoad < 1000 and 2 or sLoad < 10000 and 1 or 0
				sLoad = ('\t'):rep(off2)..('%.1f'):format(sLoad)
				str = ('%s%10s%%%7sms%13skB%10s%s'):format(v.timeColourString, tRatio, tTime, v.spaceColourString..sLoad, '', v.fullname)
			else
				str = ('%s%10s%%%7sms%10s%s'):format(v.timeColourString, tRatio, tTime, '', v.fullname)
			end
			if v.wname == profilerName then
				profilerStats[1] = str
			else
				j = j + 1
				t[j] = str
			end
		end


	end
	winObj.profHeader:SetCaption('Profiler Consumption ' .. profilerStats[1])
	-- winObj:SetText(concat(t, '\n'))
	winObj.text:SetCaption(concat(t, '\n'))

	-- winObj.win:Invalidate()
	return
end

local function UpdateRecap()
	local str = ''
	local line, part = '', ''


	-- Echo("recapWin.win.caption is ", recapWin.win.caption)
	-- glText(str, x+152, y-1-(12)*j, 10, "no")
	local want_mem = WANT_MEM_USAGE
	local t = {
		title_colour.."ALL",
		totals_colour.."total percentage of running time spent in luaui callins",
		totals_colour..('%.1f%%'):format(totalTime),
		totals_colour.."total rate of mem allocation by luaui callins",
		want_mem and totals_colour..('%.0f'):format(totalMem) .. 'kB/s' or '<Enable "Show Memory Usage in options>',
	}
	local i = 5
	if gm then
		i=i+1 t[i] = totals_colour..'total lua memory usage is '.. ('%.0f'):format(gm/1000) .. 'MB, of which:'
		if lm then
			i=i+1 t[i] = totals_colour..'  '..('%.0f%s'):format(100*lm/gm, '% is from luaui')
		end
		if um then
			i=i+1 t[i] = totals_colour..'  '..('%.0f%s'):format(100*um/gm, '% is from unsynced states (luarules+luagaia+luaui)')
		end
		if sm then
			i=i+1 t[i] = totals_colour..'  '..('%.0f%s'):format(100*sm/gm, '% is from synced states (luarules+luagaia)')
		end
	end
	i=i+1 t[i] = title_colour.."All data excludes load from garbage collection & executing GL calls"
	i=i+1 t[i] = title_colour.."Callins in brackets are heaviest per widget for (time,allocs)"
	i=i+1 t[i] = title_colour.."Tick time: " .. tick .. "s"
	i=i+1 t[i] = title_colour.."Smoothing time: " .. averageTime .. "s"
	i=i+1 t[i] = title_colour.."Profiler comsumption: " .. profilerStats[1]

	-- recapWin:SetText(concat(t,'\n'))
	local txt = concat(t,'\n')
	recapWin.text:SetCaption(concat(t,'\n'))
	-- recapWin.caption = txt
	-- recapWin._caption = txt
	-- recapWin:Invalidate()
end

function Start()
	Init()
	StartHook()
	startTimer = spGetTimer()

end
function Stop()
	StopHook()
	RemoveWindows()
end

local started



local function UpdateStats()
	started = true
	startTimer = spGetTimer()
	fullList = {}

	totalTime = 0
	totalMem = 0
	local n = 1
	-- get the time per widget and slowest callin per widget
	local want_mem = WANT_MEM_USAGE
	local max_w_space = 0
	for wname, callins in pairs(callinStats) do
		local t = 0 -- would call it time, but protected
		local cmax_t = 0
		local cmaxname_t = "-"
		local space = 0
		local cmax_space = 0
		local cmaxname_space = "-"
		for cname, c in pairs(callins) do
			t = t + c[1]
			if c[2] > cmax_t then
				cmax_t = c[2]
				cmaxname_t = cname
			end
			c[1] = 0
			if want_mem then
				space = space + c[3]
				if c[4] > cmax_space then
					cmax_space = c[4]
					cmaxname_space = cname
				end
			end
			c[3] = 0
		end
		if space > max_w_space then
			max_w_space = space
		end

		local relTime = 100 * t / deltaTime
		timeLoadAverages[wname] = CalcLoad(timeLoadAverages[wname] or relTime, relTime, averageTime)
		local tRatio = timeLoadAverages[wname]
		allOverTimeSec = allOverTimeSec + t

		local sLoad = 0
		if want_mem then
			local relSpace = space / deltaTime
			spaceLoadAverages[wname] = CalcLoad(spaceLoadAverages[wname] or relSpace, relSpace, averageTime)
			sLoad = spaceLoadAverages[wname]
		end

		fullList[n] = {
			wname = wname,
			tRatio = tRatio,
			sLoad = sLoad,
			tTime = t / deltaTime,
			isProfiler = wname:find(profilerName),
			fullname = prefixes[wname] .. wname ..' \255\200\200\200('..cmaxname_t..','..cmaxname_space..')',
		}
		
		totalTime = totalTime + tRatio
		totalMem = totalMem + sLoad
		n = n + 1
	end
	if not fullList[1] then
		return
	end
	for i = 1, #fullList do
		GetRedColourStrings(fullList[i], want_mem and max_w_space)
	end

	
	lm,_,gm,_,um,_,sm,_ = spGetLuaMemUsage()

	if (not fullList[1]) then
		return --// nothing to do
	end

	-- add to category and set colour
	local userList = {}
	local gameList = {}
	local userTime = 0
	local userMem = 0
	local gameTime = 0
	local gameMem = 0
	local now = os.clock()
	for i = 1, #fullList do
		local item = fullList[i]
		local wname = item.wname
		if userWidgets[wname] then
			userList[#userList+1] = item
			userTime = userTime + item.tRatio
			if WATCHDOG_MODE then
				local trigger = false
				if wname:find('Chili Framework') then
					trigger = item.tTime > watchdog_threshold_framework
				else
					trigger = item.tTime > watchdog_threshold
				end
				if trigger then
					local obj = WATCHDOG[wname]
					if not obj then
						WATCHDOG_IDX = WATCHDOG_IDX + 1
						WATCHDOG[wname] = {
							txt = item.fullname .. '- time: ' .. ('%.3f'):format(item.tTime),
							time = now,
							index = WATCHDOG_IDX,
						}
						Echo('Warn widget time: ' .. item.fullname .. '- time: ' .. item.tTime)
					else
						obj.time = now
						obj.txt = item.fullname .. '- time: ' .. ('%.3f'):format(item.tTime)
					end
				end
			end
			userMem = userMem + item.sLoad
		else
			gameList[#gameList+1] = item
			gameTime = gameTime + item.tRatio
			if want_mem then
				gameMem = gameMem + item.sLoad
			end
		end
	end
	if SORT_ALPHABETICAL then
		table.sort(gameList, SortAlpha)
		table.sort(userList, SortAlpha)
	else
		table.sort(gameList, SortByTime)
		table.sort(userList, SortByTime)
	end
	userList.totalTime = userTime
	userList.totalMem = userMem
	gameList.totalTime = gameTime
	gameList.totalMem = gameMem
	if not WATCHDOG_MODE then
		DrawWidgetList(gameList, "GAME")
		DrawWidgetList(userList, "USER")
		UpdateRecap()
	end




end



function widget:DrawScreen()

	if not hooked then
		return
	end
	if next(WATCHDOG) then
		local now = os.clock()
		for name, obj in pairs(WATCHDOG) do
			if now - obj.time > 5 then
				WATCHDOG[name] = nil
				WATCHDOG_IDX = WATCHDOG_IDX - 1
				local index = obj.index
				for name, obj in pairs(WATCHDOG) do
					if obj.index > index then
						obj.index = obj.index - 1
					end
				end
			else
				glText(obj.txt, vsx, 500 - 13 * obj.index, 12, 'rno')
			end
		end
	end
	if not (next(callinStats)) then
		return --// nothing to do
	end

	deltaTime = spDiffTimers(spGetTimer(),startTimer)

	-- sort & count timing
	if (deltaTime >= tick) or not started then
		UpdateStats()
	end

end
function Init()
	Chili = WG.Chili
	if WATCHDOG_MODE then
		RemoveWindows()
	else
		recapWin = recapWin or CreateWindow('recap', 165, title_colour .. 'Widget Profiler', true)
	end
	for name, wData in pairs(widgetHandler.knownWidgets) do
		-- userWidgets[prefixedWnames[name] or ConstructPrefixedName(wData,name)] = (not wData.fromZip)
		GetPrefix(wData,name)
		userWidgets[name] = not wData.fromZip
	end
	vsx, vsy = Spring.Orig.GetViewGeometry()
end

function widget:GetViewSizes()
	vsx, vsy = Spring.Orig.GetViewGeometry()
end

function widget:Update()
	upd_round = upd_round + 1
	if upd_round == init_round then
		widgetHandler:RemoveWidgetCallIn("Update", self)
		if enabled then
			Start()
		end
	end
end
local panel
local sub_global_buttons = {}
local img = {
	profiler = 'LuaUI/Images/epicmenu/stop_watch_icon.png',
	profiler2 = 'LuaUI/Images/epicmenu/speed-test-icon.png',
	enabled = 'LuaUI/Images/dynamic_comm_menu/tick.png',
	enabled2 = 'LuaUI/Images/epicmenu/check.png',
	disabled = 'LuaUI/Images/dynamic_comm_menu/cross.png',
	disabled2 = 'LuaUI/Images/epicmenu/quit.png',
	watch = 'LuaUI/Images/dynamic_comm_menu/eye.png',
	watch2 = 'sidepics/teamspec.png',
	options = 'LuaUI/Images/commands/repair.png',
}
buttons = {
	{
		image = img.enabled,
		tooltip = 'Show most consuming widgets in windows',
		func = 	function() 
			options.watchDog.value = false; options.watchDog:OnChange()
			options.enable.value = true; options.enable:OnChange()
			panel:Hide()
		end,
	},
	{
		image = img.watch,
		tooltip = 'Alert on screen when a widget spend too much time',
		func = function() 
			options.watchDog.value = true; options.watchDog:OnChange()
			options.enable.value = true; options.enable:OnChange()
			panel:Hide()
		end,
	},
	{
		image = img.disabled,
		tooltip = 'Disable',
		func = function()
			options.enable.value = false; options.enable:OnChange()
			panel:Hide()
		end,
	},
	{
		image = img.options,
		tooltip = 'Display Options',
		func = function()
			if WG.crude and WG.crude.OpenPath then
				WG.crude.OpenPath(options_path)
			end
			panel:Hide()
		end,
	},
}
function widget:Shutdown()
	StopHook()
	-- this make it disabled for the next game if widgetHandler is shutting down
	-- if not WATCHDOG_MODE then
	-- 	widgetHandler:DisableWidget(widget:GetInfo().name)
	-- end
end

function widget:ViewResizes(_vsx, _vsy)
	vsx, vsy = _vsx, _vsy
end

local buttonSize = 30
local margin = 5
function widget:Initialize()
	if widgetHandler:FindWidget("Widget Profiler New") then
		widgetHandler:DisableWidget("Widget Profiler New")
	end
	if WG.GlobalCommandBar then
		if WG.Chili then
			local function Toggle(...)
				if panel and not panel.disposed then
					if panel.visible then
						panel:Hide()
					else
						panel:Show()
						panel:BringToFront()
					end
				end
			end
			if WG.profiler_global_button then -- work around since GlobalCommandBar doesn't have a remove function
				WG.profiler_global_button.OnClick = {Toggle}
				WG.profiler_global_button.children[1].file = img.profiler
				WG.profiler_global_button.tooltip = 'Widget Profiler'
				WG.profiler_global_button:Show()
			else
				WG.profiler_global_button = WG.GlobalCommandBar.AddCommand(img.profiler, "Widget Profiler", Toggle)
			end
			local bx, by = WG.profiler_global_button:LocalToScreen(0, 0)
			panel = WG.Chili.Panel:New({
				parent = WG.Chili.Screen0,
				x = bx - 7,
				y = by + 30,
				height = buttonSize * #buttons + 10,
				width = 40,
				padding = {5,0,0,0},
			})
			for i, button in ipairs(buttons) do
				panel:AddChild(
					WG.Chili.Button:New({
						width = buttonSize,
						height = buttonSize,
						-- x = 5,
						y = 5 + (i-1) * buttonSize,
						tooltip = button.tooltip,
						classname = "button_tiny",
						noFont = true,
						margin = {0,0,0,0},
						padding = {2,2,2,2},
						children = {
							WG.Chili.Image:New({
								file = button.image,
								x = 0,
								y = 0,
								right = 0,
								bottom = 0,
							})
						},
						
						OnClick = {
							button.func
						},

					})
				)
			end
			panel:Hide()
		end
	end
end
f.DebugWidget(widget)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
