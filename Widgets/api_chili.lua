--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name        = "Chili Framework",
		desc        = "Hot GUI Framework",
		author      = "jK",
		date        = "WIP",
		license     = "GPLv2",
		version     = "2.1",
		layer       = 1000,
		enabled     = true,  --  loaded by default?
		handler     = true,
		api	        = true,
		alwaysStart = true,
	}
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local Echo = Spring.Echo
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Use old chili if unable to use RTT
local USE_OLD_CHILI = (Spring.GetConfigInt("ZKUseNewChiliRTT") ~= 1) or not ((gl.CreateFBO and gl.BlendFuncSeparate) ~= nil)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local useOld

-- UI Scaling
local UI_SCALE_MESSAGE = "SetInterfaceScale "
local uiScale = 1
local vsx, vsy = Spring.Orig.GetViewSizes()
local vsx_scaled, vsy_scaled = vsx/uiScale, vsy/uiScale
local function SetUiScale(scaleFactor)
	-- Scale such that width is an integer, because the UI aligns along the bottom of the screen.
	local realWidth = gl.GetViewSizes()
	uiScale = realWidth/math.floor(realWidth/scaleFactor)
	WG.uiScale = uiScale
end
SetUiScale((Spring.GetConfigInt("interfaceScale", 100) or 100)/100)

function widget:RecvLuaMsg(msg)
	if string.find(msg, UI_SCALE_MESSAGE) == 1 then
		local value = tostring(string.sub(msg, 19))
		if value then
			SetUiScale(value/100)
			vsx, vsy = Spring.Orig.GetViewSizes()
			local widgets = widgetHandler.widgets

			for i = 1, #widgets do
				local w = widgets[i]
				if w.ViewResize then
					w:ViewResize(vsx, vsy)
				end
			end
		end
	end
end

local glPushMatrix 	= gl.PushMatrix
local glTranslate 	= gl.Translate
local glScale 		= gl.Scale
local glPopMatrix 	= gl.PopMatrix
local glColor 		= gl.Color
local glCreateList, glCallList, glDeleteList = gl.CreateList, gl.CallList, gl.DeleteList

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if not USE_OLD_CHILI then
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

Spring.Echo("Not USE_OLD_CHILI")

useOld = false
local Chili
local screen0
local th
local tk
local tf
local th_Update, tk_Update, tf_Update
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Chili's location

local function GetDirectory(filepath)
	return filepath and filepath:gsub("(.*/)(.*)", "%1")
end

local source = debug and debug.getinfo(1).source
local DIR = GetDirectory(source) or (LUAUI_DIRNAME.."Widgets/")
CHILI_DIRNAME = DIR .. "chili/"

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


local ezSelectNoUpdate, panningNoUpdate, drawpNoUpdate = true, true, true
local newUpdateMethod = true
-- not really helping
options_path = 'Tweakings'
options_order = {
	-- RTT options made at Initialize
	'switchChili',
	'showDrawCount',
	'ezSelectNoUpdate', 'panningNoUpdate', 'drawpNoUpdate',
	-- dev part
	'refreshTexRate','debugTexUpdate','updateMethod','debugUpdates',
	'tellFonts', 'tellUpdates', 'tellTextures', 'deleteTextures',
	'useWrappedScreen0',
	-- 'useFontLists',
	-- 'drawAllFonts',
	'useLists',
	'checkAllObjects',
	--

}
options = {}
options.switchChili = {
	name = 'Switch Chili',
	desc = 'New Chili is currently ' .. (Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1 and 'ON' or 'OFF'),
	type = 'button',
	value = Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1,
	OnChange = function(self)
		local isOn = Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1
		Spring.SetConfigInt('ZKUseNewChiliRTT',isOn and 0 or 1)
		local myName = Spring.GetPlayerInfo(Spring.GetMyPlayerID())
		local isAlready = useOld == isOn
		local msg = 'New Chili set ' .. (isAlready and 'back' or '') .. ' to ' .. (isOn and 'OFF' or 'ON') .. ( not isAlready and ', but you need /luaui reload to apply it.' or '.')
		Echo(msg, myName, 'w ' .. myName .. ' ' .. msg)
		Spring.SendCommands('w ' .. myName .. ' ' .. msg)
		self.desc = 'New Chili is set ' .. (Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1 and 'ON' or 'OFF')
	end,
	action = 'switchchili',
}

options.updateMethod = {
	name = 'Chili New Update Method',
	desc = 'Unordered update, ~30% faster',
	type = 'bool',
	alwaysOnChange = true,
	value = newUpdateMethod,
	OnChange = function(self)
		newUpdateMethod = self.value
		if TaskHandler.SwitchMethod then
			TaskHandler.SwitchMethod(self.value)
		end
	end,
	dev = true,
}
options.debugUpdates = {
	name = 'Debug Update Func',
	type = 'bool',
	value = false,
	OnChange = function(self)
		if  TaskHandler.DebugUpdates then
			TaskHandler.DebugUpdates(self.value)
			-- tk_Update = TaskHandler.Update
		end
	end,
	dev = true,
}
options.ezSelectNoUpdate = {
	name = 'Suppress Update on EzSelector',
	type = 'bool',
	value = ezSelectNoUpdate,
	alwaysOnChange = true,
	OnChange = function(self)
		ezSelectNoUpdate = self.value
		TaskHandler.ezSelectNoUpdate = ezSelectNoUpdate
		Echo('now update are '.. (ezSelectNoUpdate and 'OFF' or 'ON') .. ' when using EzSelector')
	end,
}
options.panningNoUpdate = {
	name = 'Suppress Update on PanView',
	type = 'bool',
	alwaysOnChange = true,
	value = panningNoUpdate,
	OnChange = function(self)
		panningNoUpdate = self.value
		TaskHandler.panningNoUpdate = panningNoUpdate
		Echo('now update are '.. (panningNoUpdate and 'OFF' or 'ON') .. ' when using PanView')
	end,
}
options.drawpNoUpdate = {
	name = 'Suppr. Upd. on Drawing Placement',
	type = 'bool',
	alwaysOnChange = true,
	value = drawpNoUpdate,
	OnChange = function(self)
		drawpNoUpdate = self.value
		TaskHandler.drawpNoUpdate = drawpNoUpdate
		Echo('now update are '.. (drawpNoUpdate and 'OFF' or 'ON') .. ' when using Placement')
	end,
}


local defautRefreshRate = 0.2/15
options.refreshTexRate = {
	name = 'Max Texturing time',
	desc = 'how much time we allocate to render texture between each cycle',
	type = 'number',
	value = defautRefreshRate,
	min = defautRefreshRate / 10, max = defautRefreshRate * 10, step = defautRefreshRate / 30,
	OnChange = function(self)
		if TextureHandler.timeLimit then
			TextureHandler.timeLimit = self.value
		end
	end,
	dev = true,
}
options.debugTexUpdate = {
	name = 'Texture Update Debugging',
	type = 'bool',
	value = false,
	OnChange = function(self)
		if TextureHandler.DebugUpdate then
			TextureHandler.DebugUpdate(self.value)
			-- th_Update = TextureHandler.Update
		end
	end,
	dev = true,
}
options.tellUpdates = {
	name = 'Tell Updates to be done',
	type = 'button',
	OnChange = function(self)
		if TaskHandler.Tell then
			TaskHandler.Tell()
		end
	end,
	dev = true,
}

options.tellFonts = {
	name = 'Tell Loaded Fonts',
	type = 'button',
	OnChange = function(self)
		if FontHandler.Tell then
			FontHandler.Tell()
		end
	end,
	dev = true,
}
options.tellTextures = {
	name = 'Tell Loaded Textures',
	type = 'button',
	OnChange = function(self)
		if TextureHandler.Tell then
			TextureHandler.Tell()
		end
	end,
	dev = true,
}
options.deleteTextures = {
	name = 'Delete All Textures',
	type = 'button',
	OnChange = function(self)
		if TextureHandler._scream.func then
			TextureHandler._scream.func()
		end
	end,
	dev = true,
}
options.useWrappedScreen0 = {
	name = 'Use Safe Screen0',
	type = 'bool',
	value = false,
	OnChange = function(self)
		local mt = getmetatable(screen0)
		if self.value then
			if not mt.__indexwrap then
				screen0 = Chili.DebugHandler.SafeWrap(screen0)
				mt.__indexwrap = mt.__index
			else
				mh.__index = mt.__indexwrap
			end
		else
			mt.__index = mt.__indexori
		end
	end,
	dev = true,
}
-- options.useFontLists = {
-- 	name = 'Use Font List',
-- 	type = 'bool',
-- 	value = false,
-- 	OnChange = function(self)
-- 		if WG.Chili and WG.Chili.Font.SetUseLists then
-- 			WG.Chili.Font.SetUseLists(self.value)
-- 		else
-- 			Echo("couldn't Set Use Lists for Font")
-- 		end
-- 	end,
-- 	dev = true,
-- }
-- options.drawAllFonts = {
-- 	name = 'Draw Fonts in batch',
-- 	type = 'bool',
-- 	value = false,
-- 	OnChange = function(self)
-- 		local Font = WG.Chili and WG.Chili.Font
-- 		if Font and Font.DrawAllFonts then
-- 			TaskHandler.DrawAllFonts = self.value and Font.DrawAllFonts
-- 			if Font.SetUseBatch then
-- 				Font.SetUseBatch(self.value)
-- 				Echo('setting Draw Fonts in batch: '..tostring(self.value))
-- 			end
-- 		else
-- 			Echo("Chili Couldn't set Draw Fonts in batch")
-- 		end
-- 	end,
-- 	dev = true,

-- }
options.useLists = { -- FIXME cant switch at run time, DrawW funcs in skinutils are wrapped somewhere
	name = 'Draw By Lists',
	type = 'bool',
	value = false,
	OnChange = function(self)
		local Window = WG.Chili and WG.Chili.Window
		if Window and Window.SetUseLists then
			Window.SetUseLists(self.value)
			Echo('setting Use Lists: '..tostring(self.value))
			-- DrawButton = self.value and DrawButtonList or DrawButtonNoList
		else
			Echo("Chili Couldn't set Draw Fonts in batch")
		end
	end,
	dev = true,
}


options.checkAllObjects = {
	name = 'Check all Chili objects',
	type = button,
	OnChange = function(self)
		Echo('================================')
		Echo('Number of Chili objects: ' .. #WG.Chili.DebugHandler.allObjects)
		for w, t in pairs(WG.Chili.DebugHandler.objectsOwnedByWidgets) do
			Echo(#t .. ' owned by ' .. w.GetInfo().name)
		end
		Echo('================================')
	end,
	noHotkey = true,
	dev = true,
}

options.showDrawCount = { 
	name = 'Show Draw Count',
	desc = 'action: /showdrawcount',
	type = 'bool',
	value = false,
	OnChange = function(self)
		if WG.Chili and WG.Chili.Control then
			WG.Chili.Control.showDrawCount = self.value
		end
	end,
	noHotkey = true,
	action = 'showdrawcount',
}





function widget:Initialize()
	Chili = VFS.Include(CHILI_DIRNAME .. "core.lua", nil, VFS.ZIP)
	Echo("Chili.positionCommand is ", Chili.positionCommand)
	screen0 = Chili.Screen:New{}
	th = Chili.TextureHandler
	tk = Chili.TaskHandler
	tf = Chili.FontHandler
	th_Update, tk_Update, tf_Update = th.Update, tk.Update, tf.Update
	--// Export Widget Globals
	--// do this after the export to the WG table!
	--// because other widgets use it with `parent=Chili.Screen0`,
	--// but chili itself doesn't handle wrapped tables correctly (yet)
	WG.Chili = Chili
	WG.Chili.Screen0 = screen0

	-- automatic options

	local order = {} -- OBSOLETE TODO UPDATE
	for class,v in pairs(WG.Chili) do 
		if type(v) == 'table' and v.classname
		and class:match('[A-Z]')
		then
			options[class..'RTT'] = {
				type = 'number',
				min = -1, max = 1, step = 1,
				name = class .. ' RTT default',
				value = 0,
				tooltipFunction = function(self)
					return self.value == -1 and 'false'
						or self.value == 0 and 'nil'
						or 'true'
				end,
				OnChange = function(self)
					if WG.Chili then
						if self.value == -1 then
							WG.Chili[class].useRTT = false
						elseif self.value == 0 then
							WG.Chili[class].useRTT = nil
						else
							WG.Chili[class].useRTT = true
						end
					end
					screen0:CallChildren("RequestRealign")
					screen0:CallChildren("InvalidateSelf")
				end,
				path = 'Tweakings/RTT dev',
				noHotkey = true,
				alwaysOnChange = true,
				dev = true,
				hidden = true,
			}
			order[#order+1] = class .. 'RTT'
			-- t[#t+1] = k .. ', '
		end
	end
	options.allRTT = {
		type = 'button',
		name = 'All RTT/reverse',
		OnChange = function(self)
			if WG.Chili then
				local allWereTrue = true
				for class,v in pairs(WG.Chili) do
					if type(v) == 'table'
					and class:match('[A-Z]') and v.classname
					then
						Spring.Echo('CLASS',class,v.classname,'useRTT',v.useRTT)
						if v.useRTT ~= true then
							allWereTrue = false
							break
						end
					end
				end
				for class,v in pairs(WG.Chili) do
					if type(v) == 'table'
					and class:match('[A-Z]') and v.classname
					then
						if allWereTrue then
							local optvalue = options[class..'RTT'].value
							if optvalue == 0 then
								value = nil
							else
								value = optvalue == 1
							end
						else
							value = true
						end
						v.useRTT = value
					end
				end
				if allWereTrue then
					Spring.Echo('all class set RTT to their current setting by default')
				else
					Spring.Echo('all class set RTT to true by default')
				end
			end
			screen0:CallChildren("RequestRealign")
			screen0:CallDescendants("InvalidateSelf")
		end,
		path = 'Tweakings/RTT dev',
		noHotkey = true,
		alwaysOnChange = true,
		dev = true,
		hidden = true,
	}
	options.showRedrawRTT = {
		name = 'Show RTT Redraw',
		desc = 'command /showrtt',
		type = 'bool',
		value = false,
		OnChange = function(self)
			if WG.Chili and WG.Chili.Control then
				WG.Chili.Control.showRedrawRTT  = self.value
				Echo('show redraw count of RTT texture at their pos :'..tostring(self.value))
				screen0:CallChildren("RequestRealign")
				screen0:CallDescendants("InvalidateSelf")

			end
		end,
		path = 'Tweakings',
		action = 'showrtt',
		noHotkey = true,
	}
	options.tryRTT = {
		name = 'UI Render To Texture',
		desc = 'Texturing UI windows to improve performance, command /rtt',
		type = 'bool',
		value = false,
		OnChange = function(self)
			for class,v in pairs(WG.Chili) do
				if type(v) == 'table'
				and class:match('[A-Z]') and v.classname
				then
					local tovalue = 0
					if (class == 'Window' --[[or class == 'Label'--]]) and self.value then
						tovalue = 1
					end
					options[class..'RTT'].value = tovalue
					options[class..'RTT']:OnChange()
				end
			end
			Echo('RTT switched to ' .. (self.value and 'ON' or 'OFF'))

			gl.DeleteList(rttlist or 0)
			rttlist = nil
			if self.value then
				local x,y = vsx - 5, 100
				rttlist = gl.CreateList(
					function()
						gl.Color(1, 1, 0, 1)
						gl.PushMatrix()
							gl.Translate(x, y, 0)
							gl.Scale(1,-(2/vsy+y)/y,1)
							gl.Text('RTT',0, 0, 11, "rno")
						gl.PopMatrix()
						gl.Color(1, 1, 1, 1)
					end
				)
			end
		end,
		path = 'Tweakings',
	}
	---
	table.sort(order)
	table.insert(order,1,'allRTT')
	for i,v in ipairs(order) do
		options_order[#options_order+1] = v
	end

	table.insert(options_order,1,'showRedrawRTT')
	table.insert(options_order,1,'tryRTT')


	widgetHandler.actionHandler:AddAction(widget, 'rtt', function()
			options.tryRTT.value = not options.tryRTT.value
			options.tryRTT:OnChange()
		end,
		nil, 't'
	)


	---------------------------------------------
	--------- CHECKING WITHOUT DebugHandler Wrap
	local mt = getmetatable(screen0)
	local __indexori = mt.__index
	mt.__indexori = __indexori

	widget:ViewResize(Spring.Orig.GetViewSizes())

end

function widget:Shutdown()
	--table.clear(Chili) the Chili table also is the global of the widget so it contains a lot more than chili's controls (pairs,select,...)
	widgetHandler.actionHandler:RemoveAction(widget, 'rtt')
	WG.Chili = nil
end

function widget:Dispose()
	screen0:Dispose()
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:DrawScreen()
	if (not screen0:IsEmpty()) then
		glPushMatrix()
		local vsx,vsy = gl.GetViewSizes()
		glTranslate(0,vsy,0)
		glScale(1,-1,1)
		glScale(uiScale,uiScale,1)
		screen0:Draw()
	    if rttlist then
	        gl.CallList(rttlist)
	    end

		glPopMatrix()
	end
end


function widget:TweakDrawScreen()
	if (not screen0:IsEmpty()) then
		glPushMatrix()
		local vsx,vsy = gl.GetViewSizes()
		glTranslate(0,vsy,0)
		glScale(1,-1,1)
		glScale(uiScale,uiScale,1)
		screen0:TweakDraw()
		glPopMatrix()
	end
end

function widget:DrawGenesis()
	glColor(1,1,1,1)
	tf.Update()
	th.Update()
	tk.Update()
	glColor(1,1,1,1)
end


function widget:IsAbove()
	local x, y, lmb, mmb, rmb, outsideSpring = Spring.ScaledGetMouseState()
	return (not outsideSpring) and (not screen0:IsEmpty()) and screen0:IsAbove(x,y)
end


local mods = {}
function widget:MousePress(x,y,button)
	if uiScale and uiScale ~= 1 then
		x, y = x/uiScale, y/uiScale
	end
	if Spring.IsGUIHidden() then return false end
	
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;
	return screen0:MouseDown(x,y,button,mods)
end


function widget:MouseRelease(x,y,button)
	if uiScale and uiScale ~= 1 then
		x, y = x/uiScale, y/uiScale
	end
	if Spring.IsGUIHidden() then return false end
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;

	return screen0:MouseUp(x,y,button,mods)
end


function widget:MouseMove(x,y,dx,dy,button)
	if uiScale and uiScale ~= 1 then
		x, y, dx, dy = x/uiScale, y/uiScale, dx/uiScale, dy/uiScale
	end
	if Spring.IsGUIHidden() then return false end
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;

	return screen0:MouseMove(x,y,dx,dy,button,mods)
end


function widget:MouseWheel(up,value)
	local x,y = Spring.ScaledGetMouseState()
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;

	return screen0:MouseWheel(x,y,up,value,mods)
end


local keyPressed = true
function widget:KeyPress(key, mods, isRepeat, label, unicode, scanCode)
	keyPressed = screen0:KeyPress(key, mods, isRepeat, label, unicode, scanCode)
	return keyPressed
end


function widget:KeyRelease()
	local _keyPressed = keyPressed
	keyPressed = false
	return _keyPressed -- block engine actions when we processed it
end


function widget:TextInput(utf8, ...)
	if Spring.IsGUIHidden() then return false end

	return screen0:TextInput(utf8, ...)
end


function widget:ViewResize(_vsx, _vsy)
	vsx, vsy = _vsx, _vsy
	vsx_scaled, vsy_scaled = _vsx/(uiScale or 1), _vsy/(uiScale or 1)
	Chili.vsx_scaled, Chili.vsy_scaled = vsx, vsy

	screen0:Resize(vsx, vsy)
	if rttlist then
		gl.DeleteList(rttlist)
		local x,y = vsx_scaled - 5, 100
		rttlist = gl.CreateList(
			function()
				gl.Color(1, 1, 0, 1)
				gl.PushMatrix()
					gl.Translate(x, y, 0)
					gl.Scale(1,-(2/vsy_scaled+y)/y,1)
					gl.Text('RTT',0, 0, 11, "rno")
				gl.PopMatrix()
				gl.Color(1, 1, 1, 1)
			end
		)
	end
end

widget.TweakIsAbove	  = widget.IsAbove
widget.TweakMousePress   = widget.MousePress
widget.TweakMouseRelease = widget.MouseRelease
widget.TweakMouseMove	= widget.MouseMove
widget.TweakMouseWheel   = widget.MouseWheel

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
else -- Old Chili
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
useOld = true
Spring.Echo("USE_OLD_CHILI")

local Chili
local screen0
local th
local tk
local tf
local th_Update, tk_Update, tf_Update

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Chili's location

local function GetDirectory(filepath)
	return filepath and filepath:gsub("(.*/)(.*)", "%1")
end

assert(debug)
local source = debug and debug.getinfo(1).source
local DIR = GetDirectory(source) or ((LUA_DIRNAME or LUAUI_DIRNAME) .."Widgets/")
CHILI_DIRNAME = DIR .. "chili_old/"

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local slowDownGen = false
local slowDownScreen = false


local list, list2 = false, false
local count, count2 = 0, 0
local lastTime, lastTime2 = os.clock(), os.clock()
local ezSelectNoUpdate, panningNoUpdate, drawpNoUpdate = true, true, true
local newUpdateMethod = true
-- not really helping
options_path = 'Tweakings'
options_order = {
	'switchChili', 'showDrawCount',
	'refreshTexRate','debugTexUpdate','updateMethod','debugUpdates',

	'slowdownScreen','slowdownGen', -- hidden

	'ezSelectNoUpdate', 'panningNoUpdate', 'drawpNoUpdate',
}
options = {}

options.switchChili = {
	name = 'Switch Chili',
	desc = 'New Chili is currently ' .. (Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1 and 'ON' or 'OFF'),
	type = 'button',
	value = Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1,
	OnChange = function(self)
		local isOn = Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1
		Spring.SetConfigInt('ZKUseNewChiliRTT',isOn and 0 or 1)
		local myName = Spring.GetPlayerInfo(Spring.GetMyPlayerID())
		local isAlready = useOld == isOn
		local msg = 'New Chili set ' .. (isAlready and 'back' or '') .. ' to ' .. (isOn and 'OFF' or 'ON') .. ( not isAlready and ', but you need /luaui reload to apply it.' or '.')
		Echo(msg)
		Spring.SendCommands('w ' .. myName .. ' ' .. msg)
		self.desc = 'New Chili is set ' .. (Spring.GetConfigInt('ZKUseNewChiliRTT',0) == 1 and 'ON' or 'OFF')

	end,
	action = 'switchchili',
}


options.updateMethod = {
	name = 'Chili New Update Method',
	desc = 'Unordered update, ~30% faster',
	type = 'bool',
	alwaysOnChange = true,
	value = newUpdateMethod,
	OnChange = function(self)
		newUpdateMethod = self.value
		if TaskHandler.SwitchMethod then
			TaskHandler.SwitchMethod(self.value)
		end
	end,
}
options.debugUpdates = {
	name = 'Debug Update Func',
	type = 'bool',
	value = false,
	OnChange = function(self)
		if  TaskHandler.DebugUpdates then
			TaskHandler.DebugUpdates(self.value)
			-- tk_Update = TaskHandler.Update
		end
	end,
}
options.ezSelectNoUpdate = {
	name = 'No Update when using EzSelector',
	desc = 'Suppress Update when using EzSelector',
	type = 'bool',
	value = ezSelectNoUpdate,
	alwaysOnChange = true,
	OnChange = function(self)
		ezSelectNoUpdate = self.value
		TaskHandler.ezSelectNoUpdate = ezSelectNoUpdate
		Echo('now update are '.. (ezSelectNoUpdate and 'OFF' or 'ON') .. ' when using EzSelector')
	end,
}
options.panningNoUpdate = {
	name = 'No Update when using PanView',
	desc = 'Suppress Update when using PanView',
	type = 'bool',
	alwaysOnChange = true,
	value = panningNoUpdate,
	OnChange = function(self)
		panningNoUpdate = self.value
		TaskHandler.panningNoUpdate = panningNoUpdate
		Echo('now update are '.. (panningNoUpdate and 'OFF' or 'ON') .. ' when using PanView')
	end,
}
options.drawpNoUpdate = {
	name = 'No Update when using Drawing Placement',
	desc = 'Suppress Update when using Drawing Placement',
	type = 'bool',
	alwaysOnChange = true,
	value = drawpNoUpdate,
	OnChange = function(self)
		drawpNoUpdate = self.value
		TaskHandler.drawpNoUpdate = drawpNoUpdate
		Echo('now update are '.. (drawpNoUpdate and 'OFF' or 'ON') .. ' when using Placement')
	end,
}


local defautRefreshRate = 0.2/15
options.refreshTexRate = {
	name = 'Max Texturing time',
	desc = 'how much time we allocate to render texture between each cycle',
	type = 'number',
	value = defautRefreshRate,
	min = defautRefreshRate / 10, max = defautRefreshRate * 10, step = defautRefreshRate / 30,
	OnChange = function(self)
		if TextureHandler.timeLimit then
			TextureHandler.timeLimit = self.value
		end
	end,
}
options.debugTexUpdate = {
	name = 'Texture Update Debugging',
	type = 'bool',
	value = false,
	OnChange = function(self)
		if TextureHandler.DebugUpdate then
			TextureHandler.DebugUpdate(self.value)
			-- th_Update = TextureHandler.Update
		end
	end,
}

options.slowdownScreen = {
	hidden = true,
	name = 'Slow down Chili DrawScreen',
	value = slowDownScreen,
	type = 'bool',
	OnChange = function(self)
		slowDownScreen = self.value
		if not slowDownScreen and list then
			glDeleteList(list)
			list = false
		end
	end,
}
options.slowdownGen = {
	hidden = true,
	name = 'Slow down Chili DrawGenesis',
	value = slowDownGen,
	type = 'bool',
	OnChange = function(self)
		slowDownGen = self.value
		if not slowDownGen and list2 then
			glDeleteList(list2)
			list2 = false
		end
	end,
}
options.showDrawCount = { 
	name = 'Show Draw Count',
	desc = 'action: /showdrawcount',
	type = 'bool',
	value = false,
	OnChange = function(self)
		if WG.Chili and WG.Chili.Control then
			WG.Chili.Control.showDrawCount = self.value
		end
	end,
	noHotkey = true,
	action = 'showdrawcount',
}

function widget:Initialize()
	Chili = VFS.Include(CHILI_DIRNAME .. "core.lua", nil, VFS.ZIP)

	screen0 = Chili.Screen:New{}
	th = Chili.TextureHandler
	tk = Chili.TaskHandler
	tf = Chili.FontHandler
	th_Update, tk_Update, tf_Update = th.Update, tk.Update, tf.Update

	--// Export Widget Globals
	WG.Chili = Chili
	WG.Chili.Screen0 = screen0

	--// do this after the export to the WG table!
	--// because other widgets use it with `parent=Chili.Screen0`,
	--// but chili itself doesn't handle wrapped tables correctly (yet)
	screen0 = Chili.DebugHandler.SafeWrap(screen0)

	widget:ViewResize(Spring.Orig.GetViewSizes())
end

function widget:Shutdown()
	--table.clear(Chili) the Chili table also is the global of the widget so it contains a lot more than chili's controls (pairs,select,...)
	WG.Chili = nil
	if list then 
		glDeleteList(list)
		list = false
	end
	if list2 then 
		glDeleteList(list2)
		list2 = false
	end
	if rttlist then
		glDeleteList(rttlist)
	end
end

function widget:Dispose()
	screen0:Dispose()
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local DrawScreenFunc = function()
	glColor(1,1,1,1)
	if (not screen0:IsEmpty()) then
		glPushMatrix()
			glTranslate(0,vsy,0)
			glScale(1,-1,1)
			glScale(uiScale,uiScale,1)
			screen0:Draw()
		glPopMatrix()
	end
	glColor(1,1,1,1)
end
function widget:DrawScreen()
	if slowDownScreen then
		count = count + 1
		local now = os.clock()
		if count>30 or now - lastTime > 1 then
			if list then
				glDeleteList(list)
			end

			list = false
			count = 0
			lastTime = now
		end
		if not list then
			list = glCreateList(DrawScreenFunc)
		end
		glCallList(list)
	else
		DrawScreenFunc()
	end
end


function widget:DrawLoadScreen()
	glColor(1,1,1,1)
	if (not screen0:IsEmpty()) then
		glPushMatrix()
			glScale(1/vsx,1/vsy,1)
			glTranslate(0,vsy,0)
			glScale(1,-1,1)
			screen0:Draw()
		glPopMatrix()
	end
	glColor(1,1,1,1)
end


function widget:TweakDrawScreen()
	glColor(1,1,1,1)
	if (not screen0:IsEmpty()) then
		glPushMatrix()
			glTranslate(0,vsy,0)
			glScale(1,-1,1)
			glScale(uiScale,uiScale,1)
			screen0:TweakDraw()
		glPopMatrix()
	end
	glColor(1,1,1,1)
end

local DrawGenesisFunc = function()
	glColor(1,1,1,1)
	tf.Update()
	th.Update()
	tk.Update()
	glColor(1,1,1,1)
end

function widget:DrawGenesis()
	if slowDownGen then
		count2 = count2 + 1
		local now = os.clock()
		if count2>30 or now - lastTime2 > 1 then
			if list2 then
				glDeleteList(list2)
			end

			list2 = false
			count2 = 0
			lastTime2 = now
		end
		if not list2 then
			list2 = glCreateList(DrawGenesisFunc)
		end
		glCallList(list2)
	else
		DrawGenesisFunc()
	end
end


function widget:IsAbove(x,y)
	if uiScale and uiScale ~= 1 then
		x, y = x/uiScale, y/uiScale
	end
	if Spring.IsGUIHidden() then
		return false
	end
	local x, y, lmb, mmb, rmb, outsideSpring = Spring.ScaledGetMouseState()
	if outsideSpring then
		return false
	end

	return screen0:IsAbove(x,y)
end


local mods = {}
function widget:MousePress(x,y,button)
	if uiScale ~= 1 then
		x, y = x/uiScale, y/uiScale
	end
	if Spring.IsGUIHidden() then return false end

	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;
	return screen0:MouseDown(x,y,button,mods)
end


function widget:MouseRelease(x,y,button)
	if uiScale ~= 1 then
		x, y = x/uiScale, y/uiScale
	end
	if Spring.IsGUIHidden() then return false end

	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;
	return screen0:MouseUp(x,y,button,mods)
end


function widget:MouseMove(x,y,dx,dy,button)
	local uiScale = uiScale
	if uiScale ~= 1 then
		x, y, dx, dy = x/uiScale, y/uiScale, dx/uiScale, dy/uiScale
	end
	if Spring.IsGUIHidden() then return false end

	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;
	return screen0:MouseMove(x,y,dx,dy,button,mods)
end


function widget:MouseWheel(up,value)
	if Spring.IsGUIHidden() then return false end

	local x,y = Spring.ScaledGetMouseState()
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	mods.alt=alt; mods.ctrl=ctrl; mods.meta=meta; mods.shift=shift;
	return screen0:MouseWheel(x,y,up,value,mods)
end


local keyPressed = true
function widget:KeyPress(key, mods, isRepeat, label, unicode, scanCode)
	if Spring.IsGUIHidden() then return false end

	keyPressed = screen0:KeyPress(key, mods, isRepeat, label, unicode, scanCode)
	return keyPressed
end


function widget:KeyRelease()
	if Spring.IsGUIHidden() then return false end

	local _keyPressed = keyPressed
	keyPressed = false
	return _keyPressed -- block engine actions when we processed it
end

function widget:TextInput(utf8, ...)
	if Spring.IsGUIHidden() then return false end

	return screen0:TextInput(utf8, ...)
end


function widget:ViewResize(_vsx, _vsy)
	vsx, vsy = _vsx, _vsy
	vsx_scaled, vsy_scaled = _vsx/(uiScale or 1), _vsy/(uiScale or 1)
	Chili.vsx, Chili.vsy = _vsx, _vsy
	Chili.vsx_scaled, Chili.vsy_scaled = vsx_scaled, vsy_scaled
	screen0:Resize(vsx_scaled, vsy_scaled)
end


widget.TweakIsAbove	  = widget.IsAbove
widget.TweakMousePress   = widget.MousePress
widget.TweakMouseRelease = widget.MouseRelease
widget.TweakMouseMove	= widget.MouseMove
widget.TweakMouseWheel   = widget.MouseWheel

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------



end
