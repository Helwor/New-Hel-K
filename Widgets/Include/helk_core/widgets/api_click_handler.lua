


function widget:GetInfo()
	return {
		name      = 'API Click Handler',
		desc      = 'callin for click/release of mouse',
		author    = 'Helwor',
		date      = 'Winter, 2021',
		license   = 'GNU GPL, v2 or later',
		layer     = -10e36, 
		enabled   = true,
		handler   = true,
		api       = true,
	}
end
local Echo = Spring.Echo
local capturing, debugCapture = false, false
local debugState = false
options_path = 'Hel-K/' .. widget:GetInfo().name

options = {}
options.debug_state = {
	name = 'Debug State',
	type = 'bool',
	value = debugState,
	OnChange = function(self)
		debugState = self.value
	end,
	dev = true,
	action = 'dbgkeymouse',
}
options.capture = {
	name = 'Shift detection',
	desc = 'Capture click and delay it a bit for better shift detection', 
	type = 'bool',
	value = capturing,
	OnChange = function(self)
		capturing = self.value
	end,
	dev = true,
	hidden = true,
}
options.debugCapture = {
	name = 'Debug Capture',
	type = 'bool',
	value = debugCapture,
	OnChange = function(self)
		debugCapture = self.value
	end,
	dev = true,
	hidden = true
}

local f = WG.utilFuncs

local KEYCODES = f.KEYCODES

local Page = f.Page
local spGetLastUpdateSeconds = spGetLastUpdateSeconds
local spGetMouseState = Spring.GetMouseState
local spGetActiveCommand = Spring.GetActiveCommand
local spGetLastUpdateSeconds = Spring.GetLastUpdateSeconds
local spGetModKeyState = Spring.GetModKeyState
local spWarpMouse = Spring.WarpMouse
local spIsUserWriting = Spring.IsUserWriting

local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
include('keysym.h.lua')
local escape_key = KEYSYMS.ESCAPE-- fixing WG.enteringText misfunctionning, doesnt get falsified when hit escape key
local return_key = KEYSYMS.RETURN
local asterisk_key = KEYSYMS.ASTERISK -- dont count asterisk missed bc of script



local mouseLocked, verifMouseState = false, false
local mouse={false,false,false}
local STATE = {}

local Screen0 = {IsAbove = function()end}

WG.MyClicks = WG.MyClicks or {callbacks={}}
WG.MouseState = WG.MouseState or {spGetMouseState()}
local MouseState = WG.MouseState
local callbacks = WG.MyClicks.callbacks

local myWidgetName = widget:GetInfo().name
local wh
local mm = ''

local hookedCallIns = { -- those we hook
	'Update',
	'MousePress',
	'MouseRelease',
	'MouseWheel',
	'MouseMove',
	'KeyPress',
	'KeyRelease',
	'TextInput',
	'DefaultCommand',
	-- 'ConfigureLayout',
}
local exposedCallIns = { -- those we expose for user
	-- 'Update',
	'MousePress',
	'MouseRelease',
	'MouseWheel',
	'MouseMove',
	'KeyPress',
	'KeyRelease',
	'TextInput',
	-- 'DefaultCommand',
	-- 'ConfigureLayout',

}

local callbackNames = {}
for i, callin in ipairs(exposedCallIns) do
	callbackNames[i*2-1] = 'Before' .. callin
	callbackNames[i*2] = 'After' .. callin
end
-------- real initialization at the Update call
function widget:Update()
end



local lasttime = os.clock()
local function callback(nameFunc, ...)
	-- if os.clock()-lasttime > 3 then
	--     lasttime = os.clock()
	--     Echo('----------')
	-- end
	-- if nameFunc:find('MousePress') then
	--     Echo(nameFunc,'locked:' .. tostring(mouseLocked), 'verifMouseState:' .. tostring(verifMouseState),...)
	-- end
	local callincbs = callbacks[nameFunc]
	if not callincbs then
		return
	end
	for w_name, cb in pairs(callincbs) do
		cb(...)
	end
end

local time, page = 0, 0
local lotusDefID = UnitDefNames['turretlaser'].id
local function CompareModKeys(t)
	local oalt, octrl, ometa, oshift = unpack(t)
	local alt, ctrl, meta, shift = spGetModKeyState()
	local ret
	if oalt~=alt then
		-- Echo('ALT',oalt,'=>',alt)
		ret = true
	end
	if octrl~=ctrl then
		-- Echo('CTRL',octrl,'=>',ctrl)
		ret = true
	end
	if ometa~=meta then
		-- Echo('META',ometa,'=>',meta)
		ret = true
	end
	if oshift~=shift then
		-- Echo('SHIFT',oshift,'=>',shift)
		ret = true
	end
	return ret
end

local function strMods()
	local alt, ctrl, meta, shift = spGetModKeyState()
	return (alt and 'ALT ' or '')
		..(ctrl and 'CTRL ' or '')
		..(meta and 'META ' or '')
		..(shift and 'SHIFT ' or '')
end


local CAPTURED, IGNORE, LET_PASS, TIMER, WAIT_FOR_SHIFT = false, false, false, false, false
local function endCapture()
	CAPTURED = false
end
local CAPTURE_HISTORY = {
	n = 0,
	globalTimer = spGetTimer(),
	occurences = 8,
	tell_over_time = true,
}

function CAPTURE_HISTORY:Register(event)
	if not debugCapture then
		return
	end
	local globalTime = spDiffTimers(spGetTimer(), self.globalTimer)
	local current = self[self.n]
	local acom = select(4,spGetActiveCommand()) or 'none'
	self.n = self.n + 1
	self[self.n] = {
		status = event,
		globalTime = globalTime,
		delta = globalTime - (current and current.globalTime or 0),
		acom = acom,
		mods = strMods(),
		page = event ~= 'CAPTURED' and page,
		owner = wh.mouseOwner and wh.mouseOwner:GetInfo().name or '',
		ignore = IGNORE and 'IGNORE' or '',
	}
	if self.tell_over_time then
		if self.n%self.occurences == 0 then
			self:Tell(self.occurences)
		end
	end
end
function CAPTURE_HISTORY:Tell()
	local t, cnt = {'----------------------------'}, 1
	for i = self.n - self.occurences + 1, self.n do
		local obj = self[i]
		if obj then
			cnt = cnt + 1
			t[cnt] = ('#%d, %s: %.3f %s %s %s %s %s'):format(
				i,
				obj.status,
				obj.delta,
				obj.page and 'page:' .. obj.page  or '',
				tostring(obj.acom or ''),
				obj.mods,
				obj.owner,
				tostring(obj.ignore)
			)
		end
	end

	Echo(table.concat(t,'\n'))
end




local lastclick, lastclick_time = 0, 0
-- local pressed = false
-- function widget:DefaultCommand(type, id, engineCmd)
--     local mx, my, lmb, mmb, rmb = Spring.GetMouseState()
--     if not pressed and rmb then
--         pressed = true
--         Echo('pressed in Default Command', math.round(os.clock()))
--     end
--     if not rmb then
--         pressed = false
--     end
-- end

-- function widget:DefaultCommand()
--     local mx,my, b1, b2, b3, b4, b5 = spGetMouseState()
--     local realstate = {b1, b2, b3, b4, b5}
--     for i=1, 3 do
--         local pressed = mouse[i]
--         local real = realstate[i]
--         if pressed ~= real then
--             if not pressed then

--             end
--         end
--     end
-- end

-- NOTE when dragging an area command with left click this trick will not trigger the mouse release event
local fake = false
local dummyowner = {GetInfo = function() return {name = 'dummy'} end}
local function SetDummyOwner () wh.mouseOwner = dummyowner end
local function NilOwner() wh.mouseOwner = nil end

local testing = false
options.testing = {
	name = 'testing',
	type = 'bool',
	value = testing,
	OnChange = function(self)
		testing = self.value
	end,
	dev = true,
	hidden = true,
}
-------------
-- local Old = Spring.SendCommands
-- Spring.SendCommands = function(...)
--     local args = {...}
--     local arg = tostring(type(args[1])=='table' and args[1][1] or args[1])
--     if debugCapture and not (arg:find('input') or arg:find('luarules')) then
--         CAPTURE_HISTORY:Register(arg)
--     end
--     return Old(...)
-- end
-------------
local MakeSimpleOrder
do
	local spTraceScreenRay = Spring.TraceScreenRay
	local spGetActiveCommand = Spring.GetActiveCommand
	local spGetDefaultCommand = Spring.GetDefaultCommand
	local spGiveOrder = Spring.GiveOrder
	local spSetActiveCommand = Spring.SetActiveCommand
	--
	local positionCommand = WG.positionCommand
	-- local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")
	-- local positionCommand = {
	--     [CMD.MOVE] = true,
	--     [customCmds.RAW_MOVE] = true,
	--     [customCmds.RAW_BUILD] = true,
	--     [CMD.REPAIR] = true,
	--     [CMD.RECLAIM] = true,
	--     [CMD.RESURRECT] = true,
	--     [CMD.MANUALFIRE] = true,
	--     [customCmds.AIR_MANUALFIRE] = true,
	--     [CMD.GUARD] = true,
	--     [CMD.FIGHT] = true,
	--     [CMD.ATTACK] = true,
	--     [customCmds.JUMP] = true,
	-- }
	-- for k,v in pairs(customCmds) do
	--     local num = tonumber(v)
	--     if num and num>39000 and num < 40000 then
	--         positionCommand[num] = true
	--     end
	-- end
	-- customCmds = nil
	--
	local function GetCmdOpts(alt, ctrl, meta, shift, right)
		local opts = {alt = alt, ctrl = ctrl, meta = meta, shift = shift, right = right}
		local coded = 0
		
		if alt   then coded = coded + CMD_OPT_ALT   end
		if ctrl  then coded = coded + CMD_OPT_CTRL  end
		if meta  then coded = coded + CMD_OPT_META  end
		if shift then coded = coded + CMD_OPT_SHIFT end
		if right then coded = coded + CMD_OPT_RIGHT end
		
		opts.coded = coded
		return opts
	end
	local function GetActionCommand(right)
		local _, aCom = spGetActiveCommand()
		if aCom and not right then
			-- Left click means the active command should be issued.
			return aCom
		elseif not aCom and right then
			-- Right click means the default command should be issued, unless
			-- there is an active command, in which case it is cancelled.
			local _, defaultCmd = spGetDefaultCommand()
			return defaultCmd
		end
		return false
	end
	local function GiveNotifyingOrder(cmd, params, opts)
		if wh:CommandNotify(cmd, params, opts) then
			return
		end
		spGiveOrder(cmd, params, opts.coded)
	end

	MakeSimpleOrder = function(mx,my,button)
		local cmd = GetActionCommand(right)
		if not cmd then
			return
		end
		-- trace opts: useMinimap, onlyCoords, includeSky, throughWater
		local params
		if cmd >- 1 and not positionCommand[cmd] then
			local id = WG.PreSelection_GetUnitUnderCursor and WG.PreSelection_GetUnitUnderCursor()
			if id then 
				params = {id}
			end
		end
		if not params then
			local _, pos = spTraceScreenRay(mx,my,true,true,false,true)
			if pos then
				params = {pos[1], pos[2], pos[3]}
			end
		end 
		if params then
			local alt, ctrl, meta, shift = Spring.GetModKeyState()
			local right = button == 3
			local opts = GetCmdOpts(alt, ctrl, meta, shift, right)
			GiveNotifyingOrder(cmd, params, opts)
		end
		if not shift then
			spSetActiveCommand(0)
		end
	end
end

-- function widget:Update()
--     if CAPTURED then
--         page = page + 1
--         if page == 4 or spDiffTimers(spGetTimer(),TIMER) > 0.1 then
--             CAPTURE_HISTORY:Register('TIME OUT')
--             spWarpMouse(unpack(CAPTURED))
--             CAPTURED = false
--             page = 0
--             IGNORE = true
--             -- wh.mouseOwner = nil
--             NilOwner()
--             Spring.SendCommands({'mouse1'})
--             spWarpMouse(spGetMouseState())
--             return true
--         else
--             CAPTURE_HISTORY:Register('update...')
--         end
--     end
-- end
-- function widget:KeyPress(key, mods,...)
--     if CAPTURED and mods.shift then
--         CAPTURE_HISTORY:Register('SHIFT PRESSED')
--         spWarpMouse(unpack(CAPTURED))
--         page = 0
--         CAPTURED = false
--         IGNORE = true
--         NilOwner()
--         Spring.SendCommands({'mouse1'})
--         spWarpMouse(spGetMouseState())
--         return true
--     end
-- end
--------------------------





function widget:BeforeMousePress(mx,my,button,...)
	-- Echo('button press',button,os.clock())
	-- if debugCapture and CAPTURED then
	--     CAPTURE_HISTORY:Register('BEFORE MP')
	-- end
	-- it happens only when mouse is not locked and some lag happening between click, we then notify a release before notifying a press again
	--NOTE: when an active command is getting operated with left click and then a right click occur, the right click will not be detected
	MouseState[1], MouseState[2], MouseState[button+2] = mx, my, true


	-- Echo('mouse press',button,mx,my, 'mouse?',mouse[button])
	if mouse[button] then
		mouse[button] = false
		-- MouseState[button+2] = false -- not wanna give an incorrect value
		verifMouseState = false
		mouseLocked = false
		-- Echo('mouse ' .. button .. ' has been found already pressed')
		callback('AfterMouseRelease', mx, my, button,'from MousePress')
	end
	mouse[button] = true

	-- this trick allow us to track every click release and mouse move (except when mixed clicks), 
	-- more speedily and accurately than our current method, but unfortunately it eats the engine mouse reaction
	-- it could work if a replacement of the engine behaviour is made on the widget side (selection box, selection change, right click on default command, area command)
	-- if fake then
	--     fake = false
	--     return true
	-- end
	--
	callback('BeforeMousePress', mx, my, button,'from MousePress')
	local ret =  wh:_MousePress(mx, my, button)
	
	mouseLocked = ret or mouseLocked -- if the mouse was locked, it means another button has been clicked and locked it and still not has been released
	verifMouseState = not mouseLocked
		-- Echo('mouse press',button,'locked:' .. tostring(mouseLocked),'verif state: ' .. tostring(verifMouseState))
	callback('AfterMousePress',mx,my,button,'from MousePress', mouseLocked, mouseLocked and wh.mouseOwner)
	-- this trick allow us to track every click release and mouse move (except when mixed clicks)
	-- if not ret then
	--     fake = true
	--     return false or Spring.SendCommands('mouse' .. button)
	-- end
	return ret
end
---------- CAPTURING CLICK FOR SHIFT
local function CheckForCapture(mx,my,button)
	------------ block the click and check for shift in Update
	if button == 1 then
		if capturing and not CAPTURED and not wh.mouseOwner and not Screen0.hoveredControl then
			local _, aCom = spGetActiveCommand()
			if aCom and aCom<0 then
				TIMER = spGetTimer()
				MODKEYS = {spGetModKeyState()}
				if MODKEYS[4] then
					-- Echo('started with shift')
				else
					CAPTURED = {mx, my}
					WAIT_FOR_SHIFT = true
					CAPTURE_HISTORY:Register('CAPTURED')
					widget.mouseOwner = widget
					return true
				end
			end
		elseif CAPTURED then
			CAPTURE_HISTORY:Register('LET CLICK')
		end
	end
	-------------------------
end
local function CheckForShift()
	page = page + 1
	if page == 4 or spDiffTimers(spGetTimer(), TIMER) > 0.1 then
		CAPTURE_HISTORY:Register('TIME OUT')
		spWarpMouse(unpack(CAPTURED))
		page = 0
		-- NilOwner()
		WAIT_FOR_SHIFT = false
		-- wh:_MousePress(mx,my,button)
		-- Spring.SendCommands({'mouse1'})
		local mx, my = spGetMouseState()
		-- CAPTURED[1], CAPTURED[2] = mx, my
		CAPTURED = false
		spWarpMouse(mx, my)
		return true
	else
		CAPTURE_HISTORY:Register('waiting...')
	end

end
local function ReleaseCaptured(mx,my,button)
	-- there was no mouse owner so we process the click ourself
	CAPTURE_HISTORY:Register('release')
	if CAPTURED and button ==1 then
		local _mx, _my = unpack(CAPTURED)
		CAPTURED = false
		page = 0
		if WAIT_FOR_SHIFT then
			spWarpMouse(_mx, _my)
			-- the click has been released rapidly
			WAIT_FOR_SHIFT = false
			CAPTURE_HISTORY:Register('CAPTURED RAPID RELEASE')
			-- Spring.SendCommands({'mouse1'})
			-- wh:_MousePress(_mx,_my,button)
			-- CAPTURED = false
			-- NilOwner()
			-- NilOwner()
			MakeSimpleOrder(_mx, _my, button)
			spWarpMouse(mx, my)
			return -1
		end
		-- Echo('CAPTURED AT RELEASE')

		-- Spring.SendCommands({'mouse1'}) -- we can't do that as it will still have the mouse pressed no matter what we do next
		-- wh:_MousePress(_mx,_my,button)
		-- spWarpMouse(mx,my)
		-- if wh.mouseOwner then
		--     -- the mouse release wont get triggered again so we redo it if there is a real mouseOwner
		--     wh:_MouseRelease(mx,my,button)
		--     -- wh.mouseOwner = nil -- mouseOwner is not niled by wh itself (?)
		--     return -1
		-- else
			
		-- end
		CAPTURE_HISTORY:Register('CAPTURED RELEASE')
		-- wh:_MouseRelease(mx,my,button)
		-- Spring.SendCommands('mouse1')
		return -1
	end
	-- if CAPTURED then
	--     -- Echo('CAPTURED AT RELEASE')
	--     CAPTURE_HISTORY:Register('RELEASE CAPTURED')
	--     page = 0
	--     local _mx, _my = unpack(CAPTURED)
	--     spWarpMouse(_mx, _my)
	--     CAPTURED = false
	--     IGNORE = true
	--     -- Spring.SendCommands({'mouse1'}) -- we can't do that as it will still have the mouse pressed no matter what we do next
	--     NilOwner()
	--     wh:_MousePress(_mx,_my,button)
	--     spWarpMouse(mx,my)
	--     if wh.mouseOwner then
	--         -- the mouse release wont get triggered again so we redo it if there is a real mouseOwner
	--         wh:_MouseRelease(mx,my,button)
	--         -- wh.mouseOwner = nil -- mouseOwner is not niled by wh itself (?)
	--         return -1
	--     else
	--         Spring.SendCommands({'mouse1'})
	--     end
	--     return -1
	-- end
end

function widget:MousePress(mx,my,button)
	return CheckForCapture(mx, my, button)
end
function widget:MouseRelease(mx,my,button)
	ReleaseCaptured(mx, my, button)
end

function widget:BeforeMouseRelease(mx,my,button) -- this is the MouseRelease called by he engine, triggered only when a mouse button is locked
	-- Echo('button release',button)
	if debugCapture and CAPTURED then
		CAPTURE_HISTORY:Register('Before MR')
	end

	mm =''
	mouse[button]=false
	MouseState[button+2] = false

	mouseLocked = false -- the first release in case of mixed press will also unlock the mouse
	local wasOwner = wh.mouseOwner
	for i=1,3 do -- verifMouseState is never needed when mouse is locked, but if mixed press, we need it now
		if mouse[i] then
			verifMouseState = true
			break
		end
	end
	callback('BeforeMouseRelease',mx, my, button,'from MouseRelease', wasOwner)
	local ret = wh:_MouseRelease(mx, my, button) -- the ret normally is -1 in any case ?
	callback('AfterMouseRelease', mx, my, button,'from MouseRelease', wasOwner)
	return ret
end


function widget:BeforeUpdate() -- unfortuantely I didnt find a way to get notified by mouse release when MousePress didnt return true
	-- JUST HIDING noted pressed keys when user is writing, bc press and release (except for a few case shown in KeyRelease) are not passing by us
	if WG.enteringText or spIsUserWriting() then
		if next(STATE) then -- dont count the pressed key when starting to type
			STATE[next(STATE)] = nil
		end
	end
	if CAPTURED then
		if WAIT_FOR_SHIFT then
			if CheckForShift() then
				return true
			end
		end
		return
	end
	if verifMouseState then
		verifMouseState = false
		MouseState[1], MouseState[2], MouseState[3], MouseState[4], MouseState[5], MouseState[6] = spGetMouseState()
		for i=1,3 do
			local pressed = MouseState[i+2]
			if pressed then
				verifMouseState = true
			end
			if pressed~=mouse[i] then
				if mouse[i] then
					mouse[i] = false
					callback('AfterMouseRelease',MouseState[1],MouseState[2], i,'from Update')
				else
					mouse[i] = true
					callback('AfterMousePress',MouseState[1],MouseState[2], i,'from Update')
				end
			end
		end
	end


	return wh:_Update()
	-- if not pressRemains then
	--     wh.Update = wh._Update
	-- end
end

function widget:BeforeDefaultCommand(type,id,engineCmd)
	if verifMouseState then
		verifMouseState = false
		MouseState[1], MouseState[2], MouseState[3], MouseState[4], MouseState[5], MouseState[6] = spGetMouseState()
		for i=1,3 do
			local pressed = MouseState[i+2]
			if pressed then
				verifMouseState = true
			end
			if pressed~=mouse[i] then
				if mouse[i] then
					mouse[i] = false
					callback('AfterMouseRelease', MouseState[1], MouseState[2], i, 'from DefaultCommand')
				else
					mouse[i] = true
					callback('AfterMousePress', MouseState[1], MouseState[2], i, 'from DefaultCommand')
				end
			end
		end
	end
	return wh:_DefaultCommand(type,id,engineCmd)
end



-- when mixed button, the last clicked one is the one given as buttom param
function widget:BeforeMouseMove(mx,my,dx,dy,button)
	-- Echo(mx,my,dx,dy,button)
	mm = mx .. 'x' .. my
	callback('BeforeMouseMove',mx, my, dx, dy, button,'from MouseMove')
	MouseState[1], MouseState[2] = mx, my
	local ret = wh:_MouseMove(mx, my, dx, dy, button) 
	callback('AfterMouseMove',mx, my, dx, dy, button,'from MouseMove', ret)
	return ret
end
function widget:BeforeMouseWheel(up,value)
	-- mouse is already locked, user is currently pressing another button that triggered a widget
	--, therefore only the next button release will be detected, so we complete the job by checking in Update()
	callback('BeforeMouseWheel', up, value, 'from MouseWheel')
	local wheelLocked = wh:_MouseWheel(up, value) 
	callback('AfterMouseWheel',up, value,'from MouseWheel', wheelLocked)
	return wheelLocked
end
-- NOTE: once the key to start writing a label or the enter key is hit to start writing, their respective release will never happen 
-- SHOULD WE TRIGGER FAKE KEY RELEASE by using Spring.GetPressedKeys ???
-- ALSO the key UP/DOWN, ENTER and ESCAPE during writing will not trigger a press BUT STILL TRIGGER A RELEASE, press is eaten by the engine
function widget:BeforeKeyPress(key, mods, isRepeat, ...) -- key, mods, isRepeat, label, unicode, scanCode, actions
	-- Echo('KeyPress: ', key, ...)
	callback('BeforeKeyPress', key, mods, isRepeat, ...)
	if not isRepeat then
		if key == return_key then
			-- skip
		elseif STATE[ key ] == 1 then
			if debugState and key ~= asterisk_key then
				Echo("key ", KEYCODES[key], key, 'is found already pressed !')
			end
			-- return
		end
		local cnt = (STATE[ key ] or 0) + 1
		STATE[ key ] = cnt
	end

	-- if KEYCODES[key] == 2 then
	--     Echo('returned')
	--     return
	-- end
	local ret = wh:_KeyPress(key, mods, isRepeat, ...)
	callback('AfterKeyPress', key, mods, isRepeat, ...)

	return ret
end

function widget:BeforeConfigureLayout(...)
	-- Echo('Before ConfigureLayout:', ...)
	local ret = wh:_ConfigureLayout(...)
	return ret
end

function widget:BeforeTextInput(...) 
	-- Echo('Before textInput:', ...)
	callback('BeforeTextInput', ...)
	local ret = wh:_TextInput(...)
	callback('AfterTextInput', ...)
	return ret
end

local ignoreRelease = false

function widget:BeforeKeyRelease(key, ...)
	-- Echo('KeyRelease: ', key, mods, isRepeat, ...)
	if WG.enteringText or spIsUserWriting() then
		------- just hiding: the release of return key after its press to start typing will never happen, same when a label is started
		STATE[ return_key ] = nil
		if next(STATE) then -- if a label has been started using the drawinmap key
			STATE[next(STATE)] = nil
		end
		-----------
		-- ignoreRelease = not return_key
		if key == escape_key or key == return_key then
			WG.enteringText = false -- fixing the bugged variable in the case of escape, and doing it ourself in the case of return
		end

		ignoreRelease = true-- some keys like UP/DOWN, ESCAPE, ENTER, trigger a release while writing but not a press
	end
	callback('BeforeKeyRelease', key, ...)
	if not ignoreRelease then
		local cnt = (STATE[ key ] or 0) - 1
		if cnt <= 0 then
			if cnt < 0 then
				if debugState then
					Echo("key", KEYCODES[key], key, 'was not registered before release !')
				end
			end
			cnt = nil
		end
		STATE[ key ] = cnt
	else
		ignoreRelease = false
	end
	-- if KEYCODES[key] == 2 then
	--     Echo('returned')
	--     return
	-- end

	local ret = wh:_KeyRelease(key, ...)
	callback('AfterKeyRelease', key, ...)
	return ret
end



local Init = function()
	callbacks = WG.MyClicks.callbacks
	for i, callin in ipairs(hookedCallIns) do
		if not wh['_'..callin] then
			wh['_'..callin] = wh[callin]
			wh[callin] = widget['Before'..callin]
		end
	end
end



function WidgetInitNotify(w, name, preloading)
	if name == myWidgetName then
		return
	end
	for _, cbname in pairs(callbackNames) do
		if w[cbname] then
			-- Echo('add callback', cbname)
			if not callbacks[cbname] then
				callbacks[cbname] =  {}
			end
			callbacks[cbname][name] = w[cbname]
		end
	end
end
function WidgetRemoveNotify(w, name, preloading)
	if name == myWidgetName then
		return
	end
	for _,cbname in pairs(callbackNames) do
		if w[cbname] then
			if callbacks[cbname] then
				callbacks[cbname][name] = nil
				if not next(callbacks[cbname]) then
					callbacks[cbname] = nil
				end
			end
			
		end
	end
end

local round = 0
local AfterWidgetsLoaded = function() -- this replace temporarily the widget:Update that we use to run a one time initialization 
	-- round = round +1
	-- if round == 10 then
		Init()
		widget.Update = widget._Update
		widget._Update = nil
		if WG.Chili then
			Screen0 = WG.Chili.Screen0
		end
		-- wh:RemoveWidgetCallIn('Update',widget)
	-- end
end


function widget:Initialize()
	wh = widgetHandler
	widget._Update = widget.Update
	widget.Update = AfterWidgetsLoaded
end

local format = string.format
local glText = gl.Text
local glColor = gl.Color
local height = 180
local buttonTXT = {
	'Left Click',
	'Middle Click',
	'Right Click',
}
-- function widget:TextCommand(command)
--     Echo("command is ", command)
-- end
function widget:DrawScreen()
	-- glColor(0,0.5,1)
	-- Debug verif mouse -- now working perfect, EXCEPT when switching to lobby and coming back
	MouseState[1], MouseState[2], MouseState[3], MouseState[4], MouseState[5], MouseState[6] = spGetMouseState()
	if debugState then
		local str = ''
		for key, cnt in pairs(STATE) do
			str = str .. KEYCODES[key] .. ' ('.. key ..')' .. 'x' .. cnt .. ', '
		end
		str = str:sub(1,-3)
		glText(format(str), 60,height, 15)
		local str2, str3 = '', ''
		for k, v in ipairs(MouseState) do
			
			if k < 3 then
				k = k == 1 and 'x' or 'z'
				str2 = str2 .. k .. tostring(v) .. ', '
			elseif k < 6 then
				local pressed = v
				if mouse[k-2] ~= v then
					if k - 2 ~= 2 then -- ignore mmb bc of script
						v = tostring(v)
						v = v .. ' WRONG'
						-- happens when double press with drawin map to make a label, MousePress is not triggered, spGetMouseState is always correct
						Echo('WE GOT THE MOUSE WRONG ! param: '..(k-2)..':'..tostring(mouse[k-2])..' instead of: '..tostring(v), math.round(os.clock()))
					end
				else 
					v = tostring(v)
				end     
				k = buttonTXT[k-2]
				str3 = str3 .. (pressed and (k .. '  ') or '         ')
			end
			
		end
		str2 = str2:sub(1,-3)
		str3 = str3:sub(1,-3)
		glText(format(str2), 60,height-18*1, 15)
		glText(format(str3), 60,height-18*2, 15)
		local owner
		if  wh.mouseOwner then
			owner = wh.mouseOwner.GetInfo().name
		end
		if mouseLocked or verifMouseState or owner or WG.EzSelecting or WG.enteringText or Spring.IsUserWriting() then
			-- if owner == 'Chili Framework' then
			--     local above = WG.Chili.Screen0.hoveredControl
			--     if above then
			--         above = WG.Chili.Screen0.hoveredControl
			--         if above then
			--             owner = owner ..  ' ' ..(above.caption or above.name or above.className or '')
			--         end
			--     end
			-- end
			glText(  
				(math.round(os.clock()) .. '     ' ) .. 'mm' .. mm .. (mouseLocked and 'locked  ' or '               ')
				.. (verifMouseState and 'need verif ' or '                 ')
				.. (owner or '') 
				,60,height-18*3, 15
			)
			glText((WG.drawingPlacement and 'drawingPlacement' or '                 '  )
				.. (WG.EzSelecting and 'EzSelecting' or '                 '  )
				.. (WG.panning and 'panning' or '                   '  )
				.. (CAPTURED and ' CAPTURED' or '                   '  )
				.. (WG.enteringText and 'enteringText' or spIsUserWriting() and 'User Writing' or '')
				,60,height-18*4, 15
			)
		end
		-- glColor(1,1,1)
	end

end


---------
function widget:Shutdown()
	for i, callin in ipairs(hookedCallIns) do
		if wh['_'..callin] then
			wh[callin] = wh['_'..callin]
			wh['_'..callin] = nil
		end
	end
	WG.MouseState = nil
end