--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name      = "Widget Profiler New",
		desc      = "",
		author    = "jK, Bluestone",
		version   = "2.0",
		date      = "2007+",
		license   = "GNU GPL, v2 or later",
		layer     = math.huge,
		handler   = true,
		enabled   = false  --  loaded by default?
	}
end
-- April 2025
	-- WATCHDOG MODE implemented
	-- options implemented
local WATCHDOG_MODE = false
local watchdog_threshold = 0.1
local watchdog_threshold_framework = 0.3
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
local boxes = {}
local recapbox
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
			Init()
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
			averageTime = self.value
		end
	},
	watchdog_threshold = {
		name = 'Watch Dog Threshold',
		desc = 'Minimal time spent that trigger a warning in second.',
		type = 'number',
		value = watchdog_threshold,
		min = 0.01, max = 0.3, step = 0.01,
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
		min = 0.01, max = 0.5, step = 0.01,
		update_on_the_fly = true,
		OnChange = function(self)
			watchdog_threshold_framework = self.value
		end,

	}
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local prefixedWnames = {}
local function ConstructPrefixedName (ghInfo, name)
	local gadgetName = name or ghInfo.name
	local baseName = ghInfo.basename
	local _pos = baseName:find("_", 1)
	local prefix = ((_pos and usePrefixedNames) and (baseName:sub(1, _pos-1)..": ") or "")
	local prefixedWidgetName = "\255\200\200\200" .. prefix .. "\255\255\255\255" .. gadgetName
	
	prefixedWnames[gadgetName] = prefixedWidgetName
	return prefixedWnames[gadgetName]
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local callinStats       = {}

local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local spGetLuaMemUsage = Spring.GetLuaMemUsage
local concat = table.concat
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
	if recapbox then
		recapbox.win:Dispose()
		recapbox = nil
		for name, box in pairs(boxes) do
			box.win:Dispose()
			boxes[name] = nil
		end
	end
end



-- TextBox

local function newbox(name,height,caption, shutdown)
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
	-- local box = Chili.TextBox:New{
	local box = Chili.Label:New{
		parent = win,
		top=15,
		x=15,y=30,
		autosize = false,
		width = 1000,
		height = 1500,
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
				RemoveWindows()
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
				for k, v in pairs(boxes) do
					v.button.caption = newcaption
					v.button:Invalidate()
				end
				recapbox.button.caption = newcaption
				recapbox.button:Invalidate()

			end
		},
		parent = win,
	}

	local function ImplementLinkedTrackBar(option)
		local numberPanel = WG.Chili.Panel:New{
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
			tooltipFunction = option.tooltipFunction,
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
	if WG.MakeMinizable then
		WG.MakeMinizable(win, true)
	end
	box.win = win
	box.button = button
	return box
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

local function Hook(w,name) -- name is the callin
	local widgetName = w.whInfo.name

	local wname = prefixedWnames[widgetName] or ConstructPrefixedName(w.whInfo)

	local realFunc = w[name]
	w["_old" .. name] = realFunc

	if (widgetName=="Widget Profiler New") then
		-- return realFunc -- don't profile the profilers callins (it works, but it is better that our DrawScreen call is unoptimized and expensive anyway!)
	end

	local widgetCallinTime = callinStats[wname] or {}
	callinStats[wname] = widgetCallinTime
	widgetCallinTime[name] = widgetCallinTime[name] or {0,0,0,0}
	local c = widgetCallinTime[name]

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
	for name,e in pairs(wh) do
		local i = name:find("List")
		if (i)and(type(e)=="table") then
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
		if (i)and(type(e)=="table") then
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
	Spring.Echo("unhooked UpdateCallin")
	if wh.OriginalInsertWidget then
		wh.OriginalInsertWidget = oldInsertWidget
	else
		wh.InsertWidget = oldInsertWidget
	end
	Spring.Echo("unhooked InsertWidget")
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

local sortedList = {}
local function SortFunc(a,b)
	return a.wname < b.wname
end

local deltaTime
local redStrength = {}

local minPerc = 0.005 -- above this value, we fade in how red we mark a widget
local maxPerc = 0.02 -- above this value, we mark a widget as red
local minSpace = 10 -- Kb
local maxSpace = 100

local title_colour = "\255\160\255\160"
local totals_colour = "\255\200\200\255"
local maxLines = 50

local function CalcLoad(old_load, new_load, t)
	return old_load*math.exp(-tick/t) + new_load*(1 - math.exp(-tick/t))
end

function ColourString(R,G,B)
	local R255 = math.floor(R*255)
	local G255 = math.floor(G*255)
	local B255 = math.floor(B*255)
	if (R255%10 == 0) then R255 = R255+1 end
	if (G255%10 == 0) then G255 = G255+1 end
	if (B255%10 == 0) then B255 = B255+1 end
	return "\255"..string.char(R255)..string.char(G255)..string.char(B255)
end

function GetRedColourStrings(v) --tLoad is %
	local tTime = v.tTime
	local sLoad = v.sLoad
	local name = v.wname
	local u = math.exp(-deltaTime/5) --magic colour changing rate

	if tTime > maxPerc then tTime = maxPerc end
	if tTime < minPerc then tTime = minPerc end

	-- time
	local new_r = ((tTime-minPerc)/(maxPerc-minPerc))
	redStrength[name..'_time'] = redStrength[name..'_time'] or 0
	redStrength[name..'_time'] = u*redStrength[name..'_time'] + (1-u)*new_r
	local r,g,b = 1, 1-redStrength[name.."_time"]*((255-64)/255), 1-redStrength[name.."_time"]*((255-64)/255)
	v.timeColourString = ColourString(r,g,b)
	
	-- space
	new_r = math.max(0,math.min(1,(sLoad-minSpace)/(maxSpace-minSpace)))
	redStrength[name..'_space'] = redStrength[name..'_space'] or 0
	redStrength[name..'_space'] = u*redStrength[name..'_space'] + (1-u)*new_r
	g = 1-redStrength[name.."_space"]*((255-64)/255)
	b = g
	v.spaceColourString = ColourString(r,g,b)
end


local sortByTime = function(a,b)
	local aload, bload = a.tLoad, b.tLoad
	if aload < 0.1 and bload < 0.1 or aload == bload then
		return a.fullname < b.fullname
	else
		return aload > bload
	end
end
function DrawWidgetList(list,name,x,y,j)
	local str, line = '', ''
	-- glText(title, x+152, y-1-(12)*j, 10, "no")
	local part1 = ('%.2f%%'):format(list.totalTime)
	local part2 = WANT_MEM and (('%.0f'):format(list.totalMem) .. 'kB/s') or ''
	local caption = title_colour..name.." WIDGETS ".. part1 .. ' ' .. part2
	local t = {
		title_colour..name.." WIDGETS".. '\n'
			.. title_colour..part1..('  '):rep(16-part1:len())
			.. title_colour..part2
	}
	boxes[name] = boxes[name] or newbox(name, nil, caption)
	local box = boxes[name]
	if caption ~= box.win.caption then
		box.win.caption = caption
		-- if box.win.InvalidateSelf then
		-- 	box.win:InvalidateSelf()
		-- else
		-- 	box.win:Invalidate()
		-- end
		-- box.win:RequestUpdate()
	end
	-- box.win:UpdateClientArea()

	local want_mem = WANT_MEM_USAGE
	-- box.win:Resize(box.win.width,box.win.height)
	-- Echo("box.classname is ", box.parent.parent.caption)
	table.sort(list, sortByTime)
	local j = 0
	for i=1,#list do
		local v = list[i]
		--local name = v.wname
		-- local part1 = ('%.2f%%'):format(v.tLoad)
		-- local part2 = ('%.0f'):format(v.sLoad) .. 'kB/s'
		-- t[i+1] =  v.timeColourString .. part1..('  '):rep(16-part1:len())
		-- 		.. v.spaceColourString .. part2..('\t'):rep(16-part2:len())
		-- 		.. v.fullname
		if v.tLoad >= 0.5 then
			j = j + 1
			-- with mem
			-- t[j] = (' %s%.2f%% %-18s%s%-18.0fkB/s %-16s %s'):format(v.timeColourString, v.tLoad, '', v.spaceColourString, v.sLoad,'', v.fullname)
			-- without
			t[j] = (' %s%-18.2f%% %-10s %s'):format(v.timeColourString, v.tLoad, '', v.fullname)
		end


	end

	-- box:SetText(concat(t, '\n'))
	box:SetCaption(concat(t, '\n'))

	-- box.win:Invalidate()
	return
end

local function UpdateRecap()
	local str = ''
	local line, part = '', ''


	-- Echo("recapbox.win.caption is ", recapbox.win.caption)
	-- glText(str, x+152, y-1-(12)*j, 10, "no")
	local t = {
		title_colour.."ALL",
		totals_colour.."total percentage of running time spent in luaui callins",
		totals_colour..('%.1f%%'):format(totalTime),
		totals_colour.."total rate of mem allocation by luaui callins",
		totals_colour..('%.0f'):format(totalMem) .. 'kB/s',
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

	-- recapbox:SetText(concat(t,'\n'))
	local txt = concat(t,'\n')
	recapbox:SetCaption(concat(t,'\n'))
	-- recapbox.caption = txt
	-- recapbox._caption = txt
	-- recapbox:Invalidate()
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
	sortedList = {}

	totalTime = 0
	totalMem = 0
	local n = 1
	-- get the time per widget and slowest callin per widget
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
			
			space = space + c[3]
			if c[4] > cmax_space then
				cmax_space = c[4]
				cmaxname_space = cname
			end
			c[3] = 0
		end

		local relTime = 100 * t / deltaTime
		timeLoadAverages[wname] = CalcLoad(timeLoadAverages[wname] or relTime, relTime, averageTime)
		
		local relSpace = space / deltaTime
		spaceLoadAverages[wname] = CalcLoad(spaceLoadAverages[wname] or relSpace, relSpace, averageTime)

		allOverTimeSec = allOverTimeSec + t

		local tLoad = timeLoadAverages[wname]
		local sLoad = spaceLoadAverages[wname]
		sortedList[n] = {
			wname = wname,
			fullname = wname ..' \255\200\200\200('..cmaxname_t..','..cmaxname_space..')',
			tLoad = tLoad,
			sLoad = sLoad,
			tTime = t / deltaTime
		}
		totalTime = totalTime + tLoad
		totalMem = totalMem + sLoad

		n = n + 1
	end
	if not sortedList[1] then
		return
	end
	if SORT_ALPHABETICAL then
		table.sort(sortedList, SortFunc)
	end
	
	for i = 1, #sortedList do
		GetRedColourStrings(sortedList[i])
	end

	lm,_,gm,_,um,_,sm,_ = spGetLuaMemUsage()

	if (not sortedList[1]) then
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
	for i = 1, #sortedList do
		local item = sortedList[i]
		local wname = item.wname
		if userWidgets[wname] then
			userList[#userList+1] = item
			userTime = userTime + item.tLoad
			if WATCHDOG_MODE then
				if item.tTime > watchdog_threshold then
					if not wname:find('Chili Framework') or item.tTime > watchdog_threshold_framework then
						local obj = WATCHDOG[wname]
						if not obj then
							WATCHDOG_IDX = WATCHDOG_IDX + 1
							WATCHDOG[wname] = {
								txt = item.fullname .. '- time: ' .. item.tTime,
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
			end
			userMem = userMem + item.sLoad
		else
			gameList[#gameList+1] = item
			gameTime = gameTime + item.tLoad
			gameTime = gameTime + item.sLoad
		end
	end
	userList.totalTime = userTime
	userList.totalMem = userMem
	gameList.totalTime = gameTime
	gameList.totalMem = gameMem
	if not WATCHDOG_MODE then
		x, j = DrawWidgetList(gameList, "GAME", x, y, j)
		DrawWidgetList(userList, "USER", x, y, j)
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
		recapbox = recapbox or newbox('recap', 165, title_colour .. 'Widget Profiler', true)
	end
	for name, wData in pairs(widgetHandler.knownWidgets) do
		userWidgets[prefixedWnames[name] or ConstructPrefixedName(wData,name)] = (not wData.fromZip)
	end
	vsx, vsy = Spring.GetViewGeometry()
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
}
buttonImage = {
	img.enabled,
	img.watch,
	img.disabled
}
buttonTooltip = {
	'Show Most consuming widgets in windows',
	'Alert spend too much time',
	'Disable',
}
buttonClick = {
	function() 
		options.watchDog.value = false; options.watchDog:OnChange()
		if not options.enable.value then
			options.enable.value = true; options.enable:OnChange()
		end
		panel:Hide()
	end,
	function() 
		options.watchDog.value = true; options.watchDog:OnChange()
		if not options.enable.value then
			options.enable.value = true; options.enable:OnChange()
		end
		panel:Hide()
	end,
	function()
		options.enable.value = false; options.enable:OnChange()
		panel:Hide()
	end,
	
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
				height = buttonSize*3 + 10,
				width = 40,
				padding = {5,0,0,0},
			})
			for i = 1, 3 do
				panel:AddChild(
					WG.Chili.Button:New({
						width = buttonSize,
						height = buttonSize,
						-- x = 5,
						y = 5 + (i-1) * buttonSize,
						tooltip = buttonTooltip[i],
						classname = "button_tiny",
						noFont = true,
						margin = {0,0,0,0},
						padding = {2,2,2,2},
						children = {
							WG.Chili.Image:New({
								file = buttonImage[i],
								x = 0,
								y = 0,
								right = 0,
								bottom = 0,
							})
						},
						
						OnClick = {
							buttonClick[i]
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
