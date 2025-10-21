local startLoad = Spring.GetTimer()
local totalLoadTime = 0
local totalInitTime = 0
function widget:GetInfo()
	return {
		name      = "API On Widget State",
		desc      = "Home made CallIn to get triggered when a widget change state (load, init, activated, deactivated...)"
					.. "\nAlso retain specific VFS mode to load",
		author    = "Helwor",
		date      = "April 2023",
		license   = "GNU GPL, v2",
		layer     = -math.huge + 1, 
		handler   = true,
		enabled   = true,
		api       = true,
		alwaysStart = true,
	}
end
-- NOTE: unless rewriting cawidgets.lua there is no way to get this widget to be loaded first (it use VFS.DirList result as order and virtual files come first, then local widgets)
	-- to make that widget getting loaded first among local widget, you need to put a dash or double A (caps) at first in the file name
	-- Now fixed, using first original widget api_apm_stats to hijack the list of files to be loaded
local Echo = Spring.Echo
local f = WG.utilFuncs

local debugging = false
local tellTime = false
local Log
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local loaded = {}
local timeloaded = {}
local crashedWidgets = {}
local removed = {}
local silent = {}
local pendingCrash
local newwidget

local knownWidgets
local oriEcho

local whDebug = true
-- Echo("VFS.DirList is ", VFS.DirList,LUAUI_DIRNAME .. 'Config/ZK_order.lua')

-- this trick to get the real widgetHandler at load time instead of init time
local function GetRealHandler()
	if widgetHandler.LoadWidget then
		return widgetHandler
	else
		local i, n = 0, true
		while n do
			i=i+1
			n,v=debug.getupvalue(widgetHandler.RemoveCallIn, i)
			if n=='self' and type(v)=='table' and v.LoadWidget then
				return v
			end
		end
	end
end
local function GetUpvalue(func,searchname)
	local i, name, value = 0, true, nil
	local getupvalue = debug.getupvalue
	while name do
		i = i + 1
		name, value = getupvalue(func,i)
		if name == nil then
			break
		elseif name == searchname then
			return i, value
		end
	end
end
local function GetLocal(funcOrLevel, ...)
	local level, func
	if type(funcOrLevel) == 'number' then
		level = funcOrLevel + 2
	else
		func = funcOrLevel
		local i = 1
		while i < 10 do
			i = i + 1
			if debug.getinfo(i,'f').func == func then
				level = i + 1
				break
			end
		end
		if not level then
			return
		end
	end
	local find = function(searchname)
		local j, name, value = 0, true, nil 
		while name do
			j = j + 1
			name, value = debug.getlocal(level, j)
			if name == searchname then
				return value
			end
		end
	end
	if select(2, ...) then
		local found = {}
		for i, searchname in pairs({...}) do
			found[i] = find(searchname)
		end
		return unpack(found)
	else
		return find(...)
	end
end

local sig = '[' .. widget:GetInfo().name .. ']: '
local debugSig = sig:sub(1,-2) .. '[dbg]: '

local Debug = function (arg1,...)
	if not debugging then
		return
	end
	return Echo(debugSig .. tostring(arg1), ...) or true

end



local wh = GetRealHandler()
if not wh then
	Echo(sig .. 'ERROR ! ' .. "Couldnt retrieve the real widgetHandler !")
	return false
end

widgetHandler = wh
knownWidgets = widgetHandler.knownWidgets
widgetHandler.crashedWidgets = crashedWidgets
local specificMode = {}
local _,VFSMODE = GetUpvalue(widgetHandler.LoadWidget, 'VFSMODE')


-------- catch Echos from cawidgets to register crashes and replace 'Loaded widget' by 'Initialized widget'
do -- WIP
	local function SetCrashedStatus(filename, err)
		local t = {}
		local status = 'unknown reason'
		if err:find('duplicate name') then
			status = 'duplicate name'
			if newwidget and newwidget.whInfo.basename == filename then
				status = status .. ' of widget ' .. newwidget.GetInfo().name
				t.widget = newwidget
			end
		end
		t.status = status
		return status
	end
	oriEcho = Spring.Echo
	Spring.Echo = function(...)
		local arg1 = (...) 
		if type(arg1) == 'string' then
			-- if arg1:find('^Loaded A?P?I? ?widget:') then
			--     return
			-- else
			if arg1:find('^Loaded A?P?I? ?widget:') then
				return oriEcho( (arg1:gsub('Loaded', 'Initialized')) )
			elseif arg1:find('^Failed to load: ') then
				local basename, err = arg1:match(': (%S+)'), select(2, ...)
				crashedWidgets[basename] = err
				-- Echo('CRASHED', basename, err)
			end
		end
		return oriEcho(...)
	end

	local _, HANDLER_BASENAME = GetUpvalue(widgetHandler.SaveConfigData,'HANDLER_BASENAME')
	if not HANDLER_BASENAME then 
		HANDLER_BASENAME = 'cawidgets.lua'
	end
	local LOG_ERROR = LOG.ERROR
	oriLog = Spring.Log
	Spring.Log = function(arg1, arg2, arg3, arg4, ...)
		if arg1 == HANDLER_BASENAME and arg2 == LOG_ERROR then
			if arg3 then
				if arg3:find('^Failed to load: ') then
					local basename, err = arg3:match(': (%S+) ?(.*)')
					if basename then
						if err == '' then
							err = arg4 or 'unknown reason'
						end
						crashedWidgets[basename] = SetCrashedStatus(basename, err, nil, false)
						-- Echo('CRASHED 2', basename, err)
					end
				elseif arg3:find('^Removed widget: ') then
					local widgetName = arg3:match(': (%S+)')
					local err, funcName, w = GetLocal(2, 'error_message', 'funcName', 'widget')
					err = 'Error in ' .. tostring(funcName) .. '() ' .. tostring(err)
					-- Echo('CRASHED 3', err)
					-- crashedWidgets[widgetName] = SetCrashedStatus(widgetName, err, widget, true)
					widget.status = err
				end
			end
		end
		return oriLog(arg1, arg2, arg3, arg4, ...)
	end
end
-----------------------------------

local function InstallElements(w)
	Echo('install element F', f)
	w.f = f
	w.realWidgetHandler = widgetHandler
	w.WIDGET_DIRNAME = f.WIDGET_DIRNAME
	w._G = f._G
	w.vararg = f.vararg
	w.Requires = f.Requires
	w.COLORS = f.COLORS
	w.allCmds = f.allCmds
	w.KEYCODES = f.KEYCODES
	w.KEYSYMS = f.KEYSYMS
	w.EMPTY_TABLE = f.EMPTY_TABLE
	w.positionCommand = f.positionCommand
	w.Echo = Echo
end
-- local path = 
	-- local chunk, err = loadfile(ORDER_FILENAME)
	-- if (chunk == nil) then
	--     self.orderList = {} -- safety
	--     return {}
	-- else
	--     local tmp = {}
	--     setfenv(chunk, tmp)
	--     self.orderList = chunk()
	--     if (not self.orderList) then
	--         self.orderList = {} -- safety
	--     end
options_path = 'Hel-K/' .. widget:GetInfo().name
options_order = {'debugMem', 'debugTime','debug','log',--[['test'--]]}
options = {
	-- test = {
	--     name = 'Invert zoom',
	--     desc = 'Invert the scroll wheel direction for zooming.',
	--     type = 'bool',
	--     value = true,
	--     noHotkey = true,
	-- },
	debugMem = {
		name = 'Debug Memory',
		type = 'bool',
		value = false,
		OnChange = function(self)
			local bool = self.value
			if widget.oriLoadWidget or widgetHandler.LoadWidget then
				local func = widget.oriLoadWidget or widgetHandler.LoadWidget
				local i, value = GetUpvalue(func,'MEMORY_DEBUG')
				if i and value ~= bool then
					-- Echo('MEMORY_DEBUG set to ' .. tostring(bool))
					debug.setupvalue(func, i, bool)
				end
			end
		end,
		dev = true,
	},
	debugTime = {
		name = 'Debug Time',
		type = 'bool',
		value = tellTime,
		-- widgethandler original method
		-- OnChange = function(self)
		--     Echo('DEBUG TIME ON',self.value)
		--     local bool = self.value
		--     if widgetHandler.Initialize then
		--         local _, TimeLoad = GetUpvalue(widgetHandler.Initialize,'TimeLoad')
		--         if TimeLoad then
		--             local i, value = GetUpvalue(TimeLoad,'PROFILE_INIT')
					
		--             if i and value ~= bool then
		--                 -- Echo('PROFILE_INIT set to ' .. tostring(bool))
		--                 local j, value = GetUpvalue(TimeLoad,'lastTime')
		--                 if j then
		--                     if not value then
		--                         debug.setupvalue(TimeLoad, j, startLoad)
		--                     end
		--                     debug.setupvalue(TimeLoad, i, bool)
		--                 end
		--             end
		--         end
		--     end
		-- end,
		OnChange = function(self)
			tellTime = self.value
			-- if tellTime then
			--     if not oriEcho then
			--         local env = getfenv(widgetHandler.IsWidgetKnown)
			--         oriEcho = env.Spring.Echo
			--         env.Spring.Echo = function(...)
			--             local arg1 = (...) or ''
			--             if type(arg1) == 'string' and arg1:find('^Loaded A?P?I? ?widget:') then
			--                 return
			--             end
			--             return oriEcho(...)
			--         end
			--     end
			-- elseif oriEcho then
			--     local env = getfenv(widgetHandler.IsWidgetKnown)
			--     env.Spring.Echo = oriEcho
			--     -- oriEcho = nil
			-- end
		end,
		dev = true,
	},

	debug = {
		name = 'Debug', 
		type = 'bool',
		value = debugging,
		OnChange = function(self) debugging = self.value end,
		noHotkey = true,
		dev = true,
	},
	log = {
		name = 'Log',
		type = 'bool',
		value = false,
		OnChange = function(self)
			if self.value then
				if WG.LogHandler and WG.Chili then
					Log = WG.LogHandler:New(widget)
					Log:ToggleWin()
					Echo = function(...) Log(...) Spring.Echo(...) end
				else
					self.value = false
					self:OnChange()
				end
			elseif Log then
				Log:Delete()
				Log = nil
				Echo = Spring.Echo
			end
		end,
		noHotkey = true,
		dev = true,
	}
}
do -- since EPIC MENU will update the options values at init stage, we check it ourself now
	local file = LUAUI_DIRNAME .. "Config/ZK_data.lua"
	local config = VFS.Include(file, nil, VFS.RAW_FIRST)
	local epicConfig = config["EPIC Menu"].config
	local myWidgetName = widget:GetInfo().name
	local debugTime = epicConfig['epic_' .. myWidgetName .. '_debugTime']
	if debugTime then
		options.debugTime.value = true
		options.debugTime:OnChange()
	end
	local debugMem = epicConfig['epic_' .. myWidgetName .. '_debugMem']
	if debugMem then
		options.debugMem.value = true
		options.debugMem:OnChange()
	end
	local debug = epicConfig['epic_' .. myWidgetName .. '_debug']
	if debug then
		options.debug.value = true
		options.debug:OnChange()
	end

	-- Echo("debugTime, debugMem is ", debugTime, debugMem)
end




Debug(widget:GetInfo().name .. ' IS LOADING and ' .. (widgetHandler.LoadWidget and 'have ' or "DOESN'T HAVE ") ..  'WH LoadWidget callin.')

-- getting to know if we're at widgetHandler initialization
local WHInitPhase = widgetHandler.LoadWidget and not widgetHandler.knownWidgets[widget:GetInfo().name]
Debug('WH INIT PHASE is ' .. (not widgetHandler.LoadWidget and 'UNKNOWN' or WHInitPhase and 'TRUE' or 'FALSE'))
local WHoriginalNames = {
	'LoadWidget',
	'FinalizeWidget',
	'NewWidget',
	'InsertWidget',
	'RemoveWidget',
	'Sleep',
	'Wake',
}
local callback_lists = {
	WidgetPreInitNotify =   true,
	WidgetInitNotify    =   true,
	WidgetLoadNotify    =   true,
	WidgetRemoveNotify  =   true,
	WidgetSleepNotify   =   true,
	WidgetWakeNotify    =   true,

	-- can extends the list to more nuanced callins if needed
}

for funcName in pairs(callback_lists) do
	widget[funcName] = {}
end
-- memorizing who got callbacks to remove then when they shutdown
local callbackOwners = {}
-- when widgetHandler init phase is over, we send callbacks on Initialize one update round after it happens to let widgetHandler finish his work
--, in case the widget receiving the call in want to load another widget
local call_later = {}

local function Restore(arg)
	local callin = WHoriginalNames[1]
	if widget['ori' .. callin] then
		for i,callin in ipairs(WHoriginalNames) do
			-- some may have been modified by EPIC menu, we find and change the original
			local original_callin = widgetHandler['Original' .. callin] and 'Original' .. callin or callin
			widgetHandler[original_callin] = widget['ori' .. callin]
			widget['ori' .. callin] = nil
		end
		Debug('widgetHandler callins successfully restored by ' .. widget:GetInfo().name .. ' from ' .. arg)
	end
end
local function WrapCallBack(w, callback)
	return function(...)
		local _, err = pcall(callback, ...)
		if err then
			Echo('Error ' .. err .. '\nTraceback: \n'..debug.traceback())
			widgetHandler:RemoveWidget(w)
			return true
		end
	end
end
local function RegisterCallbacks(w,name)
	if callbackOwners[name] then
		return
	end
	local hasCallback
	for funcName in pairs(callback_lists) do
		local callback = w[funcName]
		if callback then
			hasCallback = true
			Debug('registered ' .. name .. ', owner of callback ' .. funcName )
			widget[funcName][callback] = WrapCallBack(w, callback)
		end
	end
	if hasCallback then
		callbackOwners[name] = true
		return true
	end
end
local function RemoveCallbacks(w,name)
	if not callbackOwners[name] then
		return
	end
	for funcName in pairs(callback_lists) do
		local callback = w[funcName]
		local cblist = widget[funcName]
		if callback and cblist[callback] then
			Debug('unregistering callback ' .. funcName .. ' of ' .. name)
			cblist[callback] = nil
		end
	end
	callbackOwners[name] = nil
end

local function TellTime(name, time, active, w)
	if not active then
		local term = crashedWidgets[name] and 'crashed' or 'removed'
		local loadtime = timeloaded[name]
		if not loadtime then
			Echo( ("Init ("..term..") widget:   %-28s %.3f (unknown loadtime)"):format(name, time) )
		else
			Echo( ("Init ("..term..") widget:   %-28s %.3f (+ l: %.3f = %.3f)"):format(name, time, loadtime, loadtime + time) )
		end
	else
		local loadtime = timeloaded[name]
		if w.Initialize then
			if not loadtime then
				Echo( ("Init widget:    %-37s %.3f (unknown loadtime)"):format(name, time) )
			else
				Echo( ("Init widget:    %-37s %.3f (+ l: %.3f = %.3f)"):format(name, time, loadtime, loadtime + time) )
			end
		else
			if not loadtime then
				Echo( ("Started widget: %-37s (unknown loadtime)"):format(name) )
			else
				Echo( ("Started widget: %-37s (l: %.3f)"):format(name, loadtime) )
			end
		end
	end
end

local function Init(arg)
	local callin = WHoriginalNames[1]
	if not widgetHandler.LoadWidget then
		widgetHandler = GetRealHandler() or widgetHandler
	end
	-- if not oriLoadWidget and widgetHandler.LoadWidget then
	if not widget['ori' .. callin] and widgetHandler.LoadWidget then
		local problem
		for i,callin in ipairs(WHoriginalNames) do
			-- some may have been modified by EPIC menu, we find and change the original
			local original_callin = widgetHandler['Original' .. callin] and 'Original' .. callin or callin
			if widgetHandler[original_callin] then
				widget['ori' .. callin] = widgetHandler[original_callin]
				widgetHandler[original_callin] = widget['wh' .. callin]
				-- Echo('HOOKING ' .. tostring(original_callin), widget['wh' .. callin])
			else
				problem = original_callin
				Debug('>>> PROBLEM, no ' .. tostring(original_callin) .. ' found in widgetHanlder ! <<<<')
			end
		end
		if not problem then
			Debug('widgetHandler callins successfully changed by ' .. widget:GetInfo().name .. ' at ' .. (arg or 'config') .. ' step')
		else
			Echo(sig .. "PROBLEM, change made at " .. (arg) .. " step but some widgetHandler's callins hasn't beed found !",problem)
		end


		if arg == 'load' then -- it's always 'load'
			-- widgets are loaded in alphabetical order, zip (or zip replaced by local) first then locals
			-- (it would be much better to respect the layer of widgets for loading order
			-- it would not be perfect has if code has been changed meanwhile  but we could use the orderlist in configData)
			-- therefore many widgets has been loaded before this one, so we catch up...
			-- retrieve the previously loaded widgets pending to be initialized and inserted
			local unsortedWidgets = GetLocal(widgetHandler.Initialize, 'unsortedWidgets')
			if not unsortedWidgets then
				Echo(widget:GetInfo().name .. " couldn't retrieve 'unsortedWidgets' !! ")
				return
			end
			local knownWidgets = widgetHandler.knownWidgets
			local names = {}
			local ownWname = widget:GetInfo().name
			local len = #unsortedWidgets
			for i=1, len do
				local name = unsortedWidgets[i].whInfo.name
				names[i] = name
				Echo(name .. ' has been loaded before.')
			end
			for i, w in ipairs(unsortedWidgets) do
				local absfilename = w.whInfo.filename:gsub('[\\/]', '/')
				loaded[absfilename] = w -- we memorize the loaded widget so we prevent cawidgets from loading them again for nothing
				-- local name = names[i]
				local name = w.whInfo.name
				if not knownWidgets[name].fromZip then 
					-- we don't bother checking vanilla widgets, they don't have our call ins
					-- note: w.whInfo is not the same table and does not have the info
					if RegisterCallbacks(w,name) then
						local Notify = w.WidgetLoadNotify
						if Notify then -- we notify those that wants it for the widgets loaded after them
							local stop = false
							Notify = WrapCallBack(Notify)
							for j=i+1, len do
								local  w = unsortedWidgets[j]
								if Notify(w, names[j], true) then
									stop = true
									break
								end
							end
							if not stop then
								Notify(widget, ownWname, true) -- plus this very widget
							end
						end
					end
				end
			end
		end

	end
	-- end

end

function whSleep(wh,w,exception)
	local name = type(w) == 'string' and w
	w = oriSleep(wh,w,exception)
	if w then
		if not name then 
			name = w.whInfo.name
		end
		for _, cb in pairs(WidgetSleepNotify) do
			cb(w,name,WHInitPhase)
		end
	end
	return w
end
function whWake(wh,w,exception)
	local name = type(w) == 'string' and w
	w = oriWake(wh,w,exception)
	if w then
		if not name then 
			name = w.whInfo.name
		end
		for _, cb in pairs(WidgetWakeNotify) do
			cb(w,name,WHInitPhase)
		end
	end
	return w
end



-- Loading

local function DetermineVFSMODE(_VFSMODE, filename, absfilename)
	if WHInitPhase then
		if specificMode[absfilename] then
			-- set the wanted mode configured by setting
			_VFSMODE = specificMode[absfilename]
		end
	else
		if _VFSMODE then
			specificMode[absfilename] = _VFSMODE
		else
			_VFSMODE = specificMode[absfilename]
		end
	end
	if _VFSMODE and _VFSMODE == VFSMODE then
		-- default same as specific, we ignore it
		_VFSMODE = nil
		specificMode[absfilename] = nil
	end

	
	if _VFSMODE then
		local thismode = _VFSMODE
		if _VFSMODE == VFS.RAW or _VFSMODE == VFS.RAW_ONLY then
			-- the current version of cawidgets will not update the 'fromZip' property correctly if we give it VFS.RAW or VFS.RAW_ONLY
			-- in that situation fromZip is checked against FileExists(VFS.ZIP_ONLY) which is currently the same as VFS.ZIP
			-- (for backward compat, see in LuaVFS.cpp, aswell VFS.RAW == VFS.RAW_ONLY)
			-- the current only way to get the accurate fromZip prop if we want RAW is to ask for RAW_FIRST
			-- or nil if there is no other version than RAW and local widgets are accepted
			-- (in latter case the VFSMODE chosen will be the default aka either RAW_FIRST or ZIP_FIRST)
			if VFS.FileExists(filename, VFS.RAW) then
				Echo('Set VFSMODE RAW to VFS.RAW_FIRST for compatibility reason')
				_VFSMODE = VFS.RAW_FIRST
				specificMode[absfilename] = _VFSMODE
			else
				_VFSMODE = nil
			end
		elseif not VFS.FileExists(filename, _VFSMODE) then
			_VFSMODE = nil
		end
		if not _VFSMODE then
			Echo("Specific loading mode is cancelled, the file " .. filename .. " doesn't exist in this mode", thismode, 'default VFS mode will be applied')
		else
			Echo('Loading widget: ' .. filename ..' with specific mode', _VFSMODE)
		end
	end
	return _VFSMODE
end

local count = 0
function whLoadWidget(wh,filename, _VFSMODE)
	-- if _VFSMODE ~= nil then
	--     specificMode[filename] = _VFSMODE
	-- elseif specificMode[filename] then
	--     _VFSMODE = specificMode[filename]
	--     Echo(filename, 'using specific mode',_VFSMODE)
	-- end
	newwidget = nil
	count = count + 1
	-- Echo('LOAD', filename, count)
	crashedWidgets[filename] = nil

	local absfilename = filename:gsub('[\\/]','/')

	if loaded[absfilename] then 
		Debug('Already loaded',filename)
		-- FIX and optimization -- (PR of cawidgets.lua to remove duplicate files has been accepted)
		-- cawidgets is needlessly loading widgets then ONLY AFTER realize that widget has been already loaded because he doesnt got yet the name located in widget:GetInfo().name
		-- as the body of the widget become different, it can cause misbehaviour, this fixes it
		-- cawidgets also load correctly first the local widget if set so, but with the filename of the zip widget
		-- Echo('Refusing to load again ' .. filename)
		-- Also, because all widgets are stuffed by alphabetical order, the first ones are the vanilla widgets, because of their path syntax
		-- So the order of loading is as this: vanilla (modded if existing) THEN any other local widgets
		return
	else
		Echo(('Loading %swidget: %-18s'):format(filename:find('^api_') and 'API ' or '', filename))
	end

	_VFSMODE = DetermineVFSMODE(_VFSMODE, filename, absfilename)
	local time = spGetTimer()
	local w = oriLoadWidget(wh,filename, _VFSMODE) 
	-- add .api in knownInfo of widget, for widget selector to know it and sort them accordingly
	if newwidget and newwidget.GetInfo then
		if newwidget.GetInfo().api then
			local ki = knownWidgets[newwidget.GetInfo().name or '']
			if ki then
				ki.api = true
			end
		end
	end
	-- 
	time = spDiffTimers(spGetTimer(), time)
	totalLoadTime = totalLoadTime + time
	if time > 1.5 then
		Echo((w and w.GetInfo and w.GetInfo().name or filename) .. ' took long to load !', time)
	end
	local thiswidget = newwidget
	newwidget = nil
	-- if w == widget then
	--     return w
	-- end
	local suffix = (WHInitPhase and ' <PRELOADING>.' or '.')
	if w then
		local name = w.whInfo.name or w.whInfo.basename
		Debug(name .. ' has been loaded and is active' .. suffix )
		if tellTime then
			Echo( ("Loaded widget:  %-34s %.3f %-18s <%s>"):format(name, time, '', w.whInfo.basename) )
			timeloaded[name] = time
		end
		loaded[absfilename] = true
		-- loaded[filename] = true
		-- loaded[w] = filename
		--- add callbacks of that widget if we find any
		if w ~= widget then
			RegisterCallbacks(w,name)
		end
		---
		for _, cb in pairs(WidgetLoadNotify) do
			cb(w,name,WHInitPhase)
		end
	elseif thiswidget then

		-- if debugging then
			local name = thiswidget.whInfo.name or thiswidget.whInfo.basename
			local ki = knownWidgets[name]
			if not (ki and ki.active) then
				local err = widgetHandler:ValidateWidget(thiswidget)
				if err then
					Debug(name .. ' has been loaded but is inactive due to ' .. err .. suffix)
				else
					-- set inactive
					Debug(name .. ' has been loaded but is inactive' .. suffix)
				end
			else
				-- duplicate name or no GetInfo
				if debugging then
					Debug(name .. ' has been loaded but dismissed' .. suffix)
				end
			end
		-- end
	else

		-- Echo('CRASHED OR SELF ENDED ?', filename)
		if debugging then
			-- missing file or wrong code or crash or silent death
			Debug(filename .. ' has crashed at loading (or self ended)' .. suffix)
		end
	end
	return w
end
function whNewWidget(wh, exposeRestricted)
	local w = oriNewWidget(wh, exposeRestricted)
	InstallElements(w)
	return w
end
function whFinalizeWidget(wh, widget, filename, basename)
	newwidget = widget

	return oriFinalizeWidget(wh,widget, filename, basename) 
end
--

-- Initializing

local initStarted = false
function whInsertWidget(wh,w)
	if not initStarted then
		Echo('----------------- Initialization Phase -----------------')
		initStarted = true
	end
	local name = w.whInfo.name or w.whInfo.basename
	for _, cb in pairs(WidgetPreInitNotify) do
		cb(w, name, WHInitPhase)
	end
	local time = spGetTimer()
	local ret = oriInsertWidget(wh,w) -- there is no return, but who knows the future
	time = spDiffTimers(spGetTimer(), time)
	totalInitTime = totalInitTime + time

	if time > 0.8 then
		Echo(name .. ' took long to init !', time)
	end

	if w then
		local suffix = WHInitPhase and ' <INIT>.' or '.'
		local active = knownWidgets[name].active
		if tellTime then
			TellTime(name, time, active, w)
		end
		if not active then
			if not crashedWidgets[name] then
				Echo('Removed at Init widget:    ' .. name)
				if not w.status then
					w.status = 'Removed at Initialization'
				end
			else
				removed[name] = true
			end
		else
			Debug(name .. ' has been initialized' .. suffix)
			if not WHInitPhase then -- we let one update cycle happen before sending the callback when not in init phase
				table.insert(call_later, function() 
					for _, cb in pairs(WidgetInitNotify) do
						cb(w,name, WHInitPhase)
					end

				end)
				widgetHandler:UpdateWidgetCallIn('Update',widget)
			else
				for _, cb in pairs(WidgetInitNotify) do
					cb(w,name, WHInitPhase)
				end
			end

			-- when a new widget is initialized, we check if it has some of our callbacks and register them, unless that has been done at load time
			if w ~= widget then
				RegisterCallbacks(w,name)
			end
			-- --
		end
	end
	return ret
end

-- removing
function whRemoveWidget(wh,w)
	if w == widget then
		Restore('whRemoveWidget')
		return widgetHandler:RemoveWidget(widget)
	end
	local absfilename = w.whInfo.filename:gsub('[\\/]','/')
	loaded[absfilename] = nil


	local suffix = WHInitPhase and ' (INIT).' or '.'
	local ret = oriRemoveWidget(wh,w) -- there is no return, but who knows the future
	if w then
		local name = w.whInfo.name or w.whInfo.basename
		Debug(name .. ' has been shut down' .. suffix)
		-- when a widget is shutdown, we check if it had callbacks and remove them from our list
		RemoveCallbacks(w, name)
		if not WHInitPhase then -- we let one update cycle happen before sending the call back when not in init phase
			table.insert(call_later, function() 
				for _, cb in pairs(WidgetRemoveNotify) do
					cb(w, name, WHInitPhase)
				end

			end)
			widgetHandler:UpdateWidgetCallIn('Update',widget)
		else
			for _, cb in pairs(WidgetRemoveNotify) do
				cb(w, name, WHInitPhase)
			end
		end
	end
	return ret
end

local function FirstUpdate(dt)
	local totalTime = spDiffTimers(spGetTimer(), startLoad)
	Echo( ('%d widgets started in %.1f + %.1f = %.1f'):format(table.size(loaded), totalLoadTime, totalInitTime, totalLoadTime + totalInitTime) )
	Echo( ('Total time passed since first widget registered: %.1f'):format(totalTime) )
	if WHInitPhase then
		Debug('first update cycle registered' .. (WHInitPhase and ' WH INIT PHASE is now FALSE.' or '.'))
		WHInitPhase = false
	end
	widget.Update = widget._Update
	widget._Update = nil
	return widget:Update(dt)
end
function widget:Update(dt)
	if call_later[1] then
		-- local err = pcall(table.remove(call_later,1))
		-- if err then
		--     Ehco(err)
		-- end
		table.remove(call_later,1)()
		if not call_later[1] then
			widgetHandler:RemoveWidgetCallIn('Update',widget)
		end
	end
end

WG.OnWidgetState = true
function widget:Initialize()
	widget._Update = widget.Update
	widget.Update = FirstUpdate
	-- Init('init')
end
--------------------------
-- we set a fake configData to trigger SetConfigData even at first ever load
-- not used anymore since we now have to save real settings
if not widgetHandler.configData[widget:GetInfo().name] then
	widgetHandler.configData[widget:GetInfo().name] = {}
end

function widget:GetConfigData()
	if specificMode then
		-- Echo('SEND CFG SPECIFIC', next(specificMode))
		return {specificMode = specificMode}
	else
		-- Echo('SEND DUMMY')
		return ({dummy = true})
	end
end

function widget:SetConfigData(data)
	-- Echo('GETTING CFG', data, data and data.specificMode, data and data.specificMode and next(data.specificMode))
	if data and data.specificMode then
		specificMode = data.specificMode
	end
	-- this is called once the loading is done and successful, we use it as trigger to notify those that want it that this widget is loaded
	-- ...and many more things added since then
	Init('load')
end
-----------------------------
function widget:Shutdown()
	if oriEcho then
		Spring.Echo = oriEcho
		Spring.Log = oriLog
		-- oriEcho = nil
	end
	if Log then
		Log:Delete()
		Log = nil
	end
	Restore("Shutdown")
	WG.OnWidgetState = false

end
totalLoadTime = totalLoadTime + spDiffTimers(spGetTimer(), startLoad)
Echo(widget:GetInfo().name .. ' STARTS')



