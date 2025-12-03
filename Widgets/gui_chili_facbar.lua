-------------------------------------------------------------------------------

local version = "v0.053"

function widget:GetInfo()
	return {
	name      = "Chili FactoryBar",
	desc      = version .. " - Chili buildmenu for factories.",
	author    = "Helwor total rewrite from CarRepairer (converted from jK's Buildbar)",
	date      = "2010-11-10",
	license   = "GNU GPL, v2 or later",
	layer     = 1001,
	enabled   = true,
	handler   = true,
	}
end
-- mars 2025 bettered detection (graphical add/remove): multiple facs in the same update round, fixed wrong window_facbar instead of window_facbar2 toward end of file
local Echo = Spring.Echo
include("Widgets/COFCTools/ExportUtilities.lua")
VFS.Include("LuaRules/Configs/customcmds.h.lua")
local GetLeftRightAllyTeamIDs = VFS.Include("LuaUI/Headers/allyteam_selection_utilities.lua")
local UnitDefs = UnitDefs
local vec4Zero = {0,0,0,0}
local DBG_VIS = true
local f = WG.utilFuncs
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local playerActive = false
local specActive = true
local force_update = false
local initialized = false
local newSelection = false

WhiteStr   = "\255\255\255\255"
GreyStr    = "\255\210\210\210"
GreenStr   = "\255\092\255\092"
RedStr     = "\255\255\092\092"

local buttonColor = {0,0,0,0.5}
local queueColor = {0.0,0.55,0.55,0.9}
local progColor = {1,0.7,0,0.6}
local BUTTON_SIZE = 50
local MAX_VISIBLE = 5
local facByID = setmetatable({}, {__mode = 'v'})
local facOrder = {}
local orderTicket = 0
local isSpec = false
local FAC = {} -- fac handler
local WANT_USER_ANIMATE = true
local IM_OPT_altInsertBehind = {value = false}
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local Chili
local Button
local Label
local Window
local StackPanel
local Grid
local TextBox
local Image
local Progressbar
local screen0
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local window_facbar, window_facbar2, stack_main, stackmain2, title, title2
local echo = Spring.Echo

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------



-------------------------------------------------------------------------------

local spGetUnitDefID       = Spring.GetUnitDefID
local spGetUnitHealth      = Spring.GetUnitHealth
local spDrawUnitCommands   = Spring.DrawUnitCommands
local spGetSelectedUnits   = Spring.GetSelectedUnits
local spGetFullBuildQueue  = Spring.GetFullBuildQueue
local spGetUnitIsBuilding  = Spring.GetUnitIsBuilding
local spGetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local spGetUnitAllyTeam    = Spring.GetUnitAllyTeam
local spValidUnitID        = Spring.ValidUnitID
local spGetUnitIsDead      = Spring.GetUnitIsDead
local spGetFactoryCommands = Spring.GetFactoryCommands
local spGetUnitStates      = Spring.GetUnitStates
local spGiveOrderToUnit    = Spring.GiveOrderToUnit

local UnitDefs             = UnitDefs
local push                 = table.insert
local remove               = table.remove
local char                 = string.char
local floor                = math.floor

-------------------------------------------------------------------------------


local function RecreateFacbar() end
local function ShowTitles(bool) end




options_path = 'Settings/HUD Panels/FactoryBar'

options_order = {
	'maxVisibleBuilds',
	'buttonsize',
	'active',
	'spec_active',
	'specAnimation',
	'show_title',
}

options = {
	maxVisibleBuilds = {
		type = 'number',
		name = 'Visible Units in Queue',
		desc = "The maximum units to show in the factory's queue",
		min = 2, max = 14,
		value = MAX_VISIBLE,
		OnChange = function(self)
			MAX_VISIBLE = self.value
		end,
	},
	
	buttonsize = {
		type = 'number',
		name = 'Button Size',
		min = 40, max = 100, step=5,
		value = BUTTON_SIZE,
		OnChange = function(self) 
			BUTTON_SIZE = self.value
			RecreateFacbar(true, false)
			widget:SelectionChanged(spGetSelectedUnits())
			widget:CommandsChanged()

		end,
	},
}
local options = options

local function Sleep(bool)
	if widgetHandler.Sleep then
		return widgetHandler[bool and 'Sleep' or 'Wake'](widgetHandler,widget )
	else
		for k,v in pairs(widget) do
			if type(k)=='string' and type(v)=='function' then
				if widgetHandler[k .. 'List'] 
					-- and k ~= 'PlayerChanged' 
				then
					widgetHandler[(bool and 'Remove' or 'Update')..'WidgetCallIn'](widgetHandler,k,widget)
				end
			end
		end
	end
end

local helk_path = 'Hel-K/' .. widget:GetInfo().name
options.active = {
	name = 'Active as Player',
	type = 'bool',
	value = playerActive,
	OnChange = function(self)
		playerActive = self.value
		if Spring.GetSpectatingState() then
			return
		end
		Sleep(not playerActive)
		if not playerActive then
			widget:Shutdown()
		elseif not initialized then
			widget:Initialize()
		end

	end,
	path = helk_path,
}
options.spec_active = {
	name = 'Active as Spec',
	type = 'bool',
	value = specActive,
	OnChange = function(self)
		specActive = self.value
		if not Spring.GetSpectatingState() then
			return
		end
		Sleep(not specActive)
		if not specActive then
			widget:Shutdown()
		elseif not initialized then
			widget:Initialize()
		end
	end,
	path = helk_path,
}
options.show_title = {
	name = 'Show Title bar',
	type = 'bool',
	value = true,
	OnChange = function(self)
		ShowTitles(self.value)
	end,
	path = helk_path,
}
options.specAnimation = {
	name = 'Icon animation when spec',
	desc = 'Animate icons when speccing to visualize better player order',
	type = 'bool',
	value = WANT_USER_ANIMATE,
	OnChange = function(self)
		WANT_USER_ANIMATE = self.value
	end,
	path = helk_path,
}
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local EMPTY_TABLE = {}

-- list and interface vars
local facs = {}
local teamFacs = {}
local unfinished_facs = {}
local facByControl = {}
local selectedFacI  = -1
local waypointFac = -1
local waypointMode = 0   -- 0 = off; 1=lazy; 2=greedy (greedy means: you have to left click once before leaving waypoint mode and you can have units selected)

local myPlayerID = Spring.GetMyPlayerID()
local myAllyTeamID = Spring.GetMyAllyTeamID()
local myTeamID = Spring.GetMyTeamID()
local inTweak  = false
local leftTweak, enteredTweak = false, false

local UPDATE_RATE = 64 -- update every n cycle
local SPECMODE_1V1 = nil 
local LEFT, RIGHT

local relativeFac = {}
for i = 1, #UnitDefs do
	local ud = UnitDefs[i]
	local cp = ud.customParams
	if (cp.parent_of_plate or cp.child_of_factory) then
		if cp.child_of_factory then
			relativeFac[i] = UnitDefNames[cp.child_of_factory].id
		end
		if cp.parent_of_plate then
			relativeFac[i] = UnitDefNames[cp.parent_of_plate].id
		end
	end
end


-------------------------------------------------------------------------------
-- SOUNDS
-------------------------------------------------------------------------------

local sound_waypoint  = LUAUI_DIRNAME .. 'Sounds/buildbar_waypoint.wav'
local sound_click     = LUAUI_DIRNAME .. 'Sounds/buildbar_click.WAV'
local sound_queue_add = LUAUI_DIRNAME .. 'Sounds/buildbar_add.wav'
local sound_queue_rem = LUAUI_DIRNAME .. 'Sounds/buildbar_rem.wav'
-- local sound_queue_rem = 'sounds/weapon/cannon/generic_cannon2.wav'
-- local sound_queue_rem = 'sounds/misc/teleport2.wav'
-- local sound_queue_rem = 'sounds/reply/rumble2.wav'
-- local sound_queue_rem = 'sounds/explosion/scan_explode.wav'
-------------------------------------------------------------------------------

local image_repeat    = LUAUI_DIRNAME .. 'Images/repeat.png'

local GetTeamColor = Spring.GetTeamColor

-------------------------------------------------------------------------------
-- SCREEN FUNCTIONS
-------------------------------------------------------------------------------
local vsx, vsy   = widgetHandler:GetViewSizes()

function widget:ViewResize(viewSizeX, viewSizeY)
	vsx = viewSizeX
	vsy = viewSizeY
end

local invX, invY = 500, 500
local spIsGUIHidden = Spring.IsGUIHidden
local glScale = gl.Scale
local glTranslate = gl.Translate
local glTexture = gl.Texture
local glPopMatrix = gl.PopMatrix
local glPushMatrix = gl.PushMatrix
local glColor = gl.Color
local glTexture = gl.Texture
local glTexRect = gl.TexRect
local fieldIcon = 'LuaUI/Images/commands/Bold/fac_select.png'
local darkgreen = {0,0.3,0,1}
local darkred = {0.3,0,0,1}
local red = {1,0.2,0.2,1}
local green = {0.2,0.9,0.2,1}
local yellow = {0.7,0.7,0.2,1}
local white = {1,1,1,1}


local function UnlinkSafe(obj)
	local tries = 0
	while type(obj) == 'userdata' do
		tries = tries + 1
		obj = obj()
	end
	return obj
end
local function GetUnitIsRepeat(id)
	return select(4, spGetUnitStates(id, false, true))
end


local anims = {}
local Animater = {stack = {}, lastCtrl = {ctrl = false, x = 0, y = 0}}
Animater.mt = {__index = Animater}
function Animater:Get(param, value)
	if type(param) == 'table' then
		for i, obj in ipairs(self.stack) do
			local found = obj
			for k, v in pairs(param) do
				if obj[k] ~= v then
					found = false
					break
				end
			end
			if found then
				return found
			end
		end
		return false
	end
	for i, obj in ipairs(self.stack) do
		if obj[param] == value then
			return obj
		end
	end
	return false
end
function Animater:Start()
	self.time = os.clock()
	if self.stopped then
		self.stopped = false
		push(self.stack, self)
		self.order = #self.stack
		if self.ctrl and self.ctrl:FindParent('screen') then
			self.ctrlx, self.ctrly = self.ctrl:LocalToScreen(0,0)
		end
	end		
	for i,v in pairs(self.stack) do
		if v.order ~= i then
			Echo('problem at ', i, #self.stack)
			for i,v in pairs(self.stack) do
				Echo(i, v.order, v.text or v.img)
			end
			error()
			return
		end
	end
end
function Animater:Duplicate()
	local obj = {}
	for k,v in pairs(self) do
		obj[k] = v
	end
	obj.stopped = true
	setmetatable(obj, self.mt)
	return obj
end
function Animater:New(obj)
	if obj.ctrl then
		obj.ctrlx, obj.ctrly = obj.ctrl:LocalToScreen(0,0)
	end
	obj.ttl = obj.ttl or 2
	obj.dirx = obj.dirx or 0
	obj.diry = obj.diry or 0
	obj.time = 0
	obj.stopped = true
	if obj.text then
		obj.tsize = obj.tsize or 18
		obj.topt = obj.topt or 'c'
	end
	-- lob safe: remove class own key
	setmetatable(obj, self.mt)
	return obj
end

function Animater:Stop()
	if not self.stopped then
		local order = self.order
		local stack = self.stack 
		remove(stack, order)
		local nex = stack[order]
		while nex do
			nex.order = order
			order = order + 1
			nex = stack[order]
		end
		self.stopped = true
	end
end

function Animater:Run(now, scale, i)
	-- if self.stopped then
	-- 	Echo('PROBLEM2')
	-- end
	scale =  scale or WG.uiScale
	now = now or os.clock()
	local off = (now - self.time) / self.ttl
	if off > 1 then
		if self.followUp then
			for k,v in pairs(self.followUp) do
				self[k] = v
			end
			self.time = now
		else
			self:Stop()
			return false
		end
	end
	local img, text = self.img, self.text
	local color, textColor, bgColor = self.color, text and self.textColor, self.bgColor
	local x, y
	local ctrl = self.ctrl
	if ctrl then
		local lastCtrl = Animater.lastCtrl
		-- Echo(i, lastCtrl.ctrl == ctrl)
		if (lastCtrl.ctrl == ctrl) then
			x, y = lastCtrl.x, lastCtrl.y
			self.ctrlx, self.ctrly = x, y
			-- Echo(i,'reuse ctrl pos',ctrl, self.ctrlx)
		else
			if 
				ctrl.ancestor and ctrl.ancestor.parent or not ctrl.ancestor and
				ctrl:FindParent('screen') then
				x, y = ctrl:LocalToScreen(0, 0)
				self.ctrlx, self.ctrly = x, y
				-- Echo(i,'look for new ctrl pos',ctrl, self.ctrlx)
			else
				-- Echo('fall back', i)
				x, y = self.ctrlx, self.ctrly
			end
			-- Echo("i, x, y is ", i, x, y, ctrl:FindParent('screen'))
			lastCtrl.ctrl, lastCtrl.x, lastCtrl.y = ctrl, x, y
		end
		x, y = x + self.x, y + self.y
	else
		Echo(i, 'obj doesn\'t have ctrl', self.ctrl)
		x, y = self.x, self.y
	end
	glPushMatrix()
	glScale(scale, scale, 1)
	glTranslate(x + off * self.dirx, vsy/scale - (y + (self.h or 0) + off * self.diry), 0)
	if self.mulx or self.muly then 
		glScale(1 + (self.mulx or 0) * off, 1 + (self.muly or 0) * off, 1)
	end

	if bgColor then
		glColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] * (1 - off))
		glTexRect(0, 0, self.w, self.h)
	end
	if color then
		glColor(color[1], color[2], color[3], color[4] * (1 - off))
	else
		glColor(1, 1, 1, 1 * (1 - off))
	end
	if img then
		glTexture(img)
		glTexRect(0, 0, self.w, self.h)
		glTexture(false)
	end
	if text then
		gl.Text(text, 0, 0, self.tsize, self.topt)
	end

	glPopMatrix()
	glColor(1, 1, 1, 1)
	return true
end

function Animater:RunAll()
	local now, scale = os.clock(), WG.uiScale
	Animater.lastCtrl.ctrl = false
	local stack = self.stack
	local obj, i = stack[1], 1
	local tries = 0

	while obj do
		local continue = obj:Run(now, scale, i)
		if continue then
			i = i + 1
		-- else
		-- 	Echo('=> i',i, #stack)
		end
		obj = stack[i]
		tries = tries + 1
		if tries > 500 then
			Echo('PROBLEM', #stack, table.size(stack),'i',i )
			error()
			break
		end
	end
end




local facDefID, facDefIDArray = {}, {}
for defID, def in pairs(UnitDefs) do
	if def.isFactory  and def.buildOptions then
		push(facDefIDArray, defID)
		facDefID[defID] = true
	else
		local cp = def.customParams
		if (cp.child_of_factory) and def.buildOptions then
			push(facDefIDArray, defID)
			facDefID[defID] = true
		end
	end
end



local function GetBuildQueue(fac)
	local result, order = {}, {}
	local id = fac.id
	local queue = spGetFullBuildQueue(id)
	if queue then
		local i = 0
		for _, buildPair in ipairs(queue) do
			local defID, count = next(buildPair, nil)
			local total = result[defID]
			if not total then
				i = i +1
				order[i] = defID
				total = count
			else
				total = total + count
			end
			result[defID] = total
		end

	end
		-- Spring.GetFactoryCounts is completely bugged when given second argument for max count
		-- local queue = spGetFactoryCommands(id, -1) -- current bug rev 2501 the .n prop and the count asked by arg #2 represent

		-- Echo("queue")
		-- for k,v in pairs(queue) do
		-- 	if type(v) == 'table' then
		-- 		Echo(k,v, table.toline(v),'ALT?', v.options.alt)
		-- 	else
		-- 		Echo(k,v)
		-- 	end
		-- end
	return result, order
end






local tooltipButton = WG.Translate("interface", "lmb") .. ' - ' .. GreenStr .. WG.Translate("interface", "select") .. '\n'
	.. '\n' .. WhiteStr ..  WG.Translate("interface", "mmb") .. ' - ' .. GreenStr .. WG.Translate("interface", "go_to") .. '\n'
	.. '\n' .. WhiteStr ..  WG.Translate("interface", "rmb") .. ' - ' .. GreenStr .. WG.Translate("interface", "quick_rallypoint_mode")
	.. '\n' .. WhiteStr ..  'Ctrl + ' .. WG.Translate("interface", "lmb") .. ' - ' .. GreenStr .. 'Move Window'
local function copy(t)
	local t2 = {}
	for k,v in pairs(t) do t2[k] = v end
	return t2
end

local gen_image = setmetatable(
	{},
	{ 
		__index = function(self, defID)
			rawset(self, defID, {
				file = "#"..defID,
				file2 = WG.GetBuildIconFrame(UnitDefs[defID]),
				keepAspect = false;
				width = '100%',
				height = '100%',
			})
			return self[defID]
		end
	}
)
local function funcSelectFac(id, stackIndex)
	return function(self,_,_,button)
		if MOVING then
			if button == 1 then
				MOVING = false
			end
			return
		end
		if button == 2 then
			local x,y,z = Spring.GetUnitPosition(id)
			SetCameraTarget(x,y,z)
		elseif button == 3 then
			Spring.Echo("FactoryBar: Entered easy waypoint mode")
			Spring.PlaySoundFile(sound_waypoint, 1, 'ui')
			waypointMode = 2 -- greedy mode
			waypointFac  = stackIndex
		else
			Spring.PlaySoundFile(sound_click, 1, 'ui')
			Spring.SelectUnitArray({id})
		end
	end

end
local function AddFacButton(id, defID, stack, stackIndex, prefTooltip)
	-- Echo(debug.traceback)
	local main = StackPanel:New{
		-- name = stackIndex .. '_q',
		itemMargin = vec4Zero,
		itemPadding = vec4Zero,
		padding = vec4Zero,
		--margin = vec4Zero,,
		x = 0,
		width = 850,
		height = BUTTON_SIZE*1,
		resizeItems = false,
		orientation = 'horizontal',
		centerItems = false,
	}
	local facButton = Button:New{
		-- name = 'fac_bar_' .. id,
		caption = '',
		width = BUTTON_SIZE*1.2,
		height = BUTTON_SIZE*1,
		tooltip = (prefTooltip or '') .. tooltipButton
			,
		backgroundColor = buttonColor,
		OnClick = {
			id ~= 0 and	funcSelectFac(id, stackIndex) or nil
		},
		OnMouseDown = {function(self, x, y, button)
			if select(2, Spring.GetModKeyState()) then -- if ctrl
				local cx, cy = self:LocalToScreen(x,y)
				local win = self.parent.parent.parent
				local wx, wy = win.x, win.y
				MOVING = {wx - cx, wy - cy}
			end
		end},
		OnMouseMove = {function(self, x, y, button) 
			if MOVING then
				local sx, sy = Spring.GetMouseState()
				local win = self.parent.parent.parent
				win:SetPos(sx + MOVING[1], vsy - sy + MOVING[2] )
			end
		end},
		padding = {3, 3, 3, 3},
		--margin = vec4Zero,,
		children = {
			id ~= 0 and
			Image:New(copy(gen_image[defID]))
			or nil,
		},
	}


	local qStack = StackPanel:New{
		-- name = stackIndex .. '_q',
		itemMargin = vec4Zero,
		itemPadding = vec4Zero,
		padding = vec4Zero,
		--margin = vec4Zero,,
		x = 0,
		width = 700,
		height = BUTTON_SIZE,
		resizeItems = false,
		orientation = 'horizontal',
		preserveChildrenOrder = true,
		centerItems = false,
	}
	local qStore = {}
	

	main:AddChild(facButton)
	main:AddChild( qStack )
	stack:AddChild(main)

	return main, facButton, qStack, qStore
end
-- NOTE Instead of repeating CMD.INSERT order, we can insert once with proper 3rd param as coded option, need to remove OPT_ALT to take effect
-- NOTE2 CMD.OPT_INTERNAL allow a one time build when on repeat, it can also be used  with CMD.INSERT in 3rd param as coded option
local funcOnClick = setmetatable(
	{},
	{
		__index = function(self, defID)
			local func = function(self,_,_,button)
				local alt, ctrl, meta, shift = Spring.GetModKeyState()
				local rb = button == 3
				local lb = button == 1
				if not (lb or rb) then
					return
				end
				local fac = facByControl[UnlinkSafe(self.parent)]
				local facID = fac.id
				local opt = 0
				local cmd
				if alt and rb then
					-- remove all
					opt = CMD.OPT_ALT + CMD.OPT_CTRL
					cmd = CMD.REMOVE
					params = -defID

				else
					cmd = -defID
					params = EMPTY_TABLE
					if alt   then opt = opt + CMD.OPT_ALT   end
					if ctrl  then opt = opt + CMD.OPT_CTRL  end
					if meta  then opt = opt + CMD.OPT_META  end
					if shift then opt = opt + CMD.OPT_SHIFT end
					if rb    then opt = opt + CMD.OPT_RIGHT end
				end
				if alt and lb and not fac.isRepeat and IM_OPT_altInsertBehind.value then
					-- force insert behind, engine doesn't do it when fac is not on repeat
					cmd = CMD.INSERT
					params = {1, -defID, opt - CMD.OPT_ALT}
					opt = CMD.OPT_ALT + CMD.OPT_CTRL
				end
				if alt and not (fac.selected or isSpec) then
					ALT_HELD = true
				end


				spGiveOrderToUnit(facID, cmd, params, opt)

				
				-- spGiveOrderToUnit(facs[selectedFacI].id, -(defID), EMPTY_TABLE, opt)
				
				if rb then
					Spring.PlaySoundFile(sound_queue_rem, 0.97, 'ui')

				else
					
					if WG.noises then
						WG.noises.PlayResponse(facID, -defID)
					else
						Spring.PlaySoundFile(sound_queue_add, 0.95, 'ui')
					end
				end
			end
			rawset(self, defID, func)
			return func
		end
	}
)


local function MakeButton(defID, facID, facIndex)

	local ud = UnitDefs[defID]
	local tooltip = "Build Unit: " .. ud.humanName .. " - " .. ud.tooltip .. "\n"
	
	return
		Button:New{
			name = defID,
			tooltip=tooltip,
			x=0,
			caption='',
			width = BUTTON_SIZE,
			height = BUTTON_SIZE,
			padding = {4, 4, 4, 4},
			--padding = {0,0,0,0},
			--margin={0, 0, 0, 0},
			backgroundColor = queueColor,
			OnClick = {
				funcOnClick[defID]
			},
			children = {
				Label:New {
					name='count',
					autosize=false;
					width="100%";
					height="100%";
					align="right";
					valign="top";
					caption = '';
					fontSize = 14;
					fontShadow = true;
				},

				
				Label:New{ caption = ud.metalCost .. ' m', fontSize = 11, x=2, bottom=2, fontShadow = true, },
				Image:New {
					name = 'bp',
					file = "#"..defID,
					file2 = WG.GetBuildIconFrame(ud),
					keepAspect = false;
					width = '100%',height = '80%',
					children = {
						Progressbar:New{
							value = 0.0,
							name    = 'prog';
							max     = 1;
							color       = progColor,
							backgroundColor = {1,1,1,  0.01},
							x=4,y=4, bottom=4,right=4,
							skin=nil,
							skinName='default',
						},
					},
				},
			},
		}
	
end


-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local function WaypointHandler(x,y,button)
	if button == 1 or button > 3 then
		Spring.Echo("FactoryBar: Exited easy waypoint mode")
		Spring.PlaySoundFile(sound_waypoint, 1, 'ui')
		waypointFac  = -1
		waypointMode = 0
		return
	end

	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	local opt = CMD.OPT_RIGHT
	if alt   then opt = opt + CMD.OPT_ALT   end
	if ctrl  then opt = opt + CMD.OPT_CTRL  end
	if meta  then opt = opt + CMD.OPT_META  end
	if shift then opt = opt + CMD.OPT_SHIFT end

	local type, param = Spring.TraceScreenRay(x,y)
	if type == 'ground' then
		spGiveOrderToUnit(facs[waypointFac].id, CMD_RAW_MOVE,param,opt)
	elseif type == 'unit' then
		spGiveOrderToUnit(facs[waypointFac].id, CMD.GUARD,{param},opt)
	elseif type ~= 'feature' then
		return -- sky, ignore
	else --feature
		type, param = Spring.TraceScreenRay(x,y,true)
		if not param then
			return -- there's sky behind the feature, ignore
		end
		spGiveOrderToUnit(facs[waypointFac].id, CMD_RAW_MOVE,param,opt)
	end

	--if not shift then waypointMode = 0; return true end
end
local SAVED_CONTROLS = {}

local function CreateFacControls(fac, i)
	local facDefID = fac.defID
	
	local progress
	local facID = fac.id
	--[[local curBuildDefID = -1
	local curBuildID    = -1
	-- building?
	curBuildID      = spGetUnitIsBuilding(facID)
	if curBuildID then
		curBuildDefID = spGetUnitDefID(curBuildID)
		_, _, _, _, progress = spGetUnitHealth(curBuildID)
		facDefID      = curBuildDefID
	else--]]if (unfinished_facs[facID]) then
		_, _, _, _, progress = spGetUnitHealth(facID)
		if (progress>=1) then
			progress = -1
			unfinished_facs[facID] = nil
		end
	end
	-- Echo("fac.allyTeamID is ", fac.allyTeamID)
	local stack = stack_main
	local prefTooltip
	if SPECMODE_1V1 ~= nil then
		if fac.allyTeamID == RIGHT.allyTeamID then
			stack = stack_main2
			prefTooltip = RIGHT.tooltip .. '\n'
			-- Echo('ok put to stack 2')
		else
			prefTooltip = LEFT.tooltip .. '\n'
		end
	end
	local array = SAVED_CONTROLS[facDefID]
	-- Echo('create fac', i, "cache for " .. facDefID .. " is ", array and #array or 0)
	if array and array[1] then
		local controls = table.remove(array, 1)
		fac.main, fac.facButton, fac.qStack, fac.qStore = unpack(controls)
		local hButton = UnlinkSafe(fac.facButton)
		hButton.OnClick[1] = funcSelectFac(facID, i)
		hButton.tooltip = (prefTooltip or '') .. tooltipButton
		stack:AddChild(fac.main)
		facByControl[UnlinkSafe(fac.qStack)] = fac
		return
	end
	local main, facButton, qStack, qStore = AddFacButton(facID, facDefID, stack, i, prefTooltip)
	fac.main      = main
	fac.facButton = facButton
	fac.qStack    = qStack
	fac.qStore    = qStore
	if not UNI_STORE then
		UNI_STORE = qStore
	end
	-- Echo("stack_main, facButton is ", stack_main, facButton)

	local buildList   = fac.buildList

	for _, buildDefID in ipairs(buildList) do
		qStore[buildDefID] = MakeButton(buildDefID, facID, i)
	end
	facByControl[UnlinkSafe(qStack)] = fac
end
function FAC:New(id, defID, allyTeam)
	defID = defID or spGetUnitDefID(id)
	local fac = setmetatable(
		{ 
			id = id,
			defID = defID,
			allyTeamID = allyTeam or spGetUnitAllyTeam(id),
			buildList = ((UnitDefs[defID] or EMPTY_TABLE).buildOptions or EMPTY_TABLE),
			isRepeat = GetUnitIsRepeat(id),
		},
		{__index = FAC}
	)
	push(facs, fac)
	facByID[id] = fac
	return fac
end
function FAC:CreateControls(index)
	return CreateFacControls(self, index)
end
local function AddFactory(id, defID, allyTeam)
	local fac = FAC:New(id, defID, allyTeam)
	fac:CreateControls(#facs)
end

function FAC:Remove(id, save)
	local fac = self
	for i, _fac in ipairs(facs) do
		if _fac.id  == id then
			fac = _fac
			table.remove(facs, i)
			local parent = fac.main.parent
			if save then
				local array = SAVED_CONTROLS[fac.defID]
				if not array then
					array = {}
					SAVED_CONTROLS[fac.defID] = array
				end
				array[#array+1] = {fac.main, fac.facButton, fac.qStack, fac.qStore}
				-- Echo('add to cache for '..fac.id..': ', #array)
			else
				facOrder[id] = nil
			end
			if facs[selectedFacI] == fac then
				selectedFacI = -1
			end
			parent:RemoveChild(fac.main)
			facByControl[UnlinkSafe(fac.qStack)] = nil
			facByID[id] = nil
			break
		end
	end

	unfinished_facs[id] = nil
end

local function RemoveFactories(complete)
	if complete then
		for i, _fac in ipairs(facs) do
			local parent = _fac.main.parent
			parent:RemoveChild(_fac.main)
			facByControl[UnlinkSafe(_fac.qStack)] = nil
		end
		if SPECMODE_1V1 ~= nil then
			stack_main2:ClearChildren()
		end
		for i, array in pairs(SAVED_CONTROLS) do
			for i, obj in ipairs(array) do
				obj:Dispose()
			end
			array[i] = nil
		end
		for obj, v in pairs(facByControl) do
			if not obj.disposed then
				obj:Dispose()
			end
		end
		selectedFacI = -1
	else
		while facs[1] do
			facs[1]:Remove(facs[1].id, true)
		end
	end

end


local function sortByAppearance(a,b)
	return facOrder[a] < facOrder[b]
end

local function ListFactoryTeam(teamID)

	-- Echo('list factory',teamID,'myTeamID',myTeamID,'myAllyTeamID', myAllyTeamID)
	local allyTeamID
	local toSort = {}
	for i, id in ipairs(spGetTeamUnitsByDefs(teamID, facDefIDArray)) do
		if not allyTeamID then
			allyTeamID = spGetUnitAllyTeam(id)
		end
		toSort[#toSort+1] = id
		local _, _, _, _, buildProgress = spGetUnitHealth(id)
		if (buildProgress)and(buildProgress<1) then
			unfinished_facs[id] = true
		end
	end

	for i, id in ipairs(toSort) do
		if not facOrder[id] then
			orderTicket = orderTicket + 1
			facOrder[id] = orderTicket
		end
	end
	table.sort(toSort, sortByAppearance)
	for i, id in ipairs(toSort) do
		FAC:New(id)
	end
end

local function AddTeamFactories(teamID)
	local start = #facs + 1
	ListFactoryTeam(teamID)
	if not facs[start] then
		return
	end
	for i = start, #facs do
		facs[i]:CreateControls(i)
	end

	stack_main:Invalidate()
	stack_main:UpdateLayout()
	if SPECMODE_1V1 ~= nil then
		stack_main2:Invalidate()
		stack_main2:UpdateLayout()
	end
end

local function UpdateFactoryList()
	facs = {}
	if SPECMODE_1V1 then
		ListFactoryTeam(0)
		ListFactoryTeam(1)
	else
		ListFactoryTeam(myTeamID)
	end
end
local facIsBuilding = {}

function widget:UnitFromFactory(id, defID, teamID)
	local fac = facIsBuilding[id]
	if fac then
		facIsBuilding[id]  = false
		facIsBuilding[fac] = false
		fac.isBuildingDef  = false
	end
end

local function UpdateFac(i, fac)
	--local defID = fac.defID
	
	local curBuildDefID = -1
	local curBuildID    = -1
	local facID = fac.id
	local qStore = fac.qStore
	-- building?
	local progress = 0
	curBuildID = spGetUnitIsBuilding(facID)
	local lastInProgress = facIsBuilding[fac]
	local lastBuildAlt = fac.isBuildingAlt
	local isSelected = fac.selected

	local buildList   = fac.buildList
	local buildQueue, order  = GetBuildQueue(fac)
	local buildCancelled = false
	if lastInProgress then
		if curBuildID ~= lastInProgress then
			buildCancelled = fac.isBuildingDef
			facIsBuilding[fac] = false
			facIsBuilding[lastInProgress] = false
			fac.isBuildingDef = false
			fac.isBuildingAlt = false
		end
	end
	if curBuildID then
		curBuildDefID = spGetUnitDefID(curBuildID)
		_, _, _, _, progress = spGetUnitHealth(curBuildID)
		if not facIsBuilding[curBuildID] then
			facIsBuilding[curBuildID] = fac
			facIsBuilding[fac] = curBuildID
			fac.isBuildingDef = curBuildDefID
			fac.isBuildingAlt = spGetFactoryCommands(facID, 1)[1].options.alt
		end
	else
		if (unfinished_facs[facID]) then
			_, _, _, _, progress = spGetUnitHealth(facID)
			if (progress>=1) then
				progress = -1
				unfinished_facs[facID] = nil
			end
		end
	end
	---
	local isRepeat = GetUnitIsRepeat(facID)
	local qStore = fac.qStore
	for j, buildDefID in ipairs(buildList) do

		local qButton = qStore[buildDefID]
		local qCount = qButton.childrenByName['count']
		local qPic = qButton.childrenByName['bp']
		local qBar = qPic.childrenByName['prog']

		local oldAmount = qCount.caption
		local amount = buildQueue[buildDefID] or 0
		if oldAmount == '' then
			oldAmount = 0
		end
		local increment = amount - oldAmount
		-- guess user interaction with the queue
		-- if buildCancelled == buildDefID then
		-- 	Animater:New(qPic, 0, 50, 2, darkred)
		-- elseif increment < -1 then
		-- 	Animater:New(qPic, 0, 50, 2, darkred)
		-- elseif increment == -1 then
		-- 	if isRepeat and not lastBuildAlt then
		-- 		Animater:New(qPic, 0, 50, 2, darkred)
		-- 	end
		-- elseif increment > 0 then
		-- 	Animater:New(qPic, 0, -50, 2)
		-- end
		qBar:SetValue(buildDefID == curBuildDefID and progress or 0)
		qCount:SetCaption(amount > 0 and amount or '')




		local color = isSelected and amount > 0 and queueColor or buttonColor
		if color ~= qButton.backgroundColor then
			qButton.backgroundColor = color
			qButton:Invalidate()
		end

	end
	if not (isSelected or ALT_HELD) then
		
		local qStack = fac.qStack
		-- qStack:ClearChildren()

		local child = qStack.children[1]
		while child do
			local remove = qStack:RemoveChild(child)
			if remove ~= true then
				Echo('PROBLEM', remove)	
				break
			end
			child = qStack.children[1]
		end

		if next(qStack.children) then
			Echo('GOT CHILDREN')
			for k,v in pairs(qStack.children) do
				Echo(k,v)
				if type(v) == 'table' or type(v) == 'userdata' then
					Echo("v.name is ", v.name, UnitDefs[v.name].humanName)
				end
			end
		end
		-- for k,v in ipairs(fac.qStack.children) do
		-- 	Echo(UnitDefs[v.name].humanName)
		-- end
		for j, defID in ipairs(order) do
			-- Echo("j, defID is ", j, defID)
			local success, err = pcall(fac.qStack.AddChild, fac.qStack, qStore[defID])
			if not success then
				Echo('ERROR', "defID, fac.qStack, qStore[defID], qStore[defID] and qStore[defID].parent is ",i, defID, fac.qStack, qStore[defID], qStore[defID] and qStore[defID].parent)
				Echo('order')
				for i,v in pairs(order) do
					Echo(k,v, UnitDefs[v].humanName)
				end
				Echo('qStack')
				for k,v in ipairs(fac.qStack.children) do
					Echo(UnitDefs[v.name].humanName)
				end
				Echo(err)
				error()
			end
			if j == MAX_VISIBLE then
				break
			end
		end
	end
end


local function InstantUpdate()
	for i,fac in ipairs(facs) do
		if spValidUnitID( fac.id ) then
			UpdateFac(i, fac)
		end
	end
end

--------------- Update on the fly from unit command + animate managing

local function AnimateIcon(qPic, up, increment, count, alt)
	local anim = anims[qPic]
	if not anim then
		local x, y = qPic:LocalToScreen(0,0)
		local w, h = qPic.width, qPic.height
		anim = {
			increase          = Animater:New({ctrl = qPic, x = 0, y = 0, w = w, h = h, img = qPic.file, diry = -50 }),
			decrease          = Animater:New({ctrl = qPic, x = 0, y = 0, w = w, h = h, img = qPic.file, diry = 50, bgColor = darkred }),
			total             = Animater:New({ctrl = qPic, x = 0 + w/2, y = h/2 + 18/2, text = count + increment, topt = 'co', update = 'total' }),
			text_increase     = Animater:New({ctrl = qPic, x = 0 + w/2, y = 0, text = increment, diry = -50, color = green }),
			text_increase_alt = Animater:New({ctrl = qPic, x = 0 + w/2, y = 0, text = increment, diry = -50, color = yellow }),
			text_decrease     = Animater:New({ctrl = qPic, x = 0 + w/2, y = h + 18, text = increment, diry = 50, color = red }),
		}
		anims[qPic] = anim
	end
	((up and anim.increase or anim.decrease):Duplicate()):Start()
	local tkey = not up and 'text_decrease' 
					  or alt and 'text_increase_alt' 
					  or 'text_increase'
	local anim_text = anim[tkey]
	if not anim_text.stopped then
		if os.clock() - anim_text.time < 1 then
			local num = tostring(anim_text.text):match('(%d+)$')
			anim_text.text = (tonumber(num) + increment)
			anim_text:Start()
		else
			anim_text = anim_text:Duplicate() 
			anim_text.text = increment
			anim_text:Start()
			anim[tkey] = anim_text
		end
	else
		anim_text.text = increment
		anim_text:Start()
	end
	anim.total.text = count + increment
	anim.total:Start()
end



local function MoveObject(obj, p2)
	local parent = obj.parent
	local children = parent.children
	if not children[p2] then
		return
	end
	local p1 = children[UnlinkSafe(obj)]
	if not p1 then
		Echo('OBJ', obj.name, UnitDefs[obj.name].humanName, ' is not indexed !?')
		Echo('want to move obj to', p2)
		for k,v in pairs(children) do
			Echo(
				type(k),
				(type(k) == 'userdata' or type(k) == 'table') and UnitDefs[k.name].humanName or k,
				(type(v) == 'userdata' or type(v) == 'table') and UnitDefs[v.name].humanName or v
			)
		end
		error()
	end
	children[p1], children[p2] = children[p2], children[p1]
	for k, v in pairs(children) do
		if v == p2 then
			children[k] = p1
		elseif v == p1 then
			children[k] = p2
		end
	end
end
local function InsertObject(parent, obj, index)
	-- AddChild with index is broken, doesn't map the hObj and objDirect
	parent:AddChild(obj)
	MoveObject(obj, index)
end



local function UpdateQButton(defID, increment, fac, alt)
	if defID == '-all' then
		for defID in pairs(fac.qStore) do
			UpdateQButton(defID, '-all', fac, true, alt)
		end
		return
	end
	local qStack = fac.qStack
	local qStore = fac.qStore
	local qButton = qStore[defID]
	local qPic = UnlinkSafe(qButton.childrenByName['bp'])
	local qCount = qButton.childrenByName['count']

	local count = qCount.caption

	if count == '' then
		count = 0
	end
	if increment == '-all' then
		increment = -count
	end
	if increment == 0 then
		return
	end
	if count == 0 and increment < 0 then
		return
	end
	if count + increment <= 0 then
		increment = -count
	end
	if increment > 0 then
		if count > 0 or fac.selected then -- if count == 0 we wait to add the control first
			if (isSpec and WANT_USER_ANIMATE) or DBG_VIS then
				local color
				if alt then
					color = yellow
					if false and not fac.selected then
						-- this is actually not practical to move it right away, let it do via the slow update
						local place = (IM_OPT_altInsertBehind.value or fac.isRepeat) and 2 or 1
						-- move already the control
						if qStack.children[UnlinkSafe(qButton)] > place then 
							MoveObject(qButton, place)
							qStack:Realign()
						end
					end
				else
					color = green
				end
				AnimateIcon(qPic, true, increment, count, alt)
			end
		end
	else
		if (isSpec and WANT_USER_ANIMATE) or DBG_VIS then
			AnimateIcon(qPic, false, increment, count)
		end
	end
	if count + increment == 0 then
		count = 0

		if fac.selected then
			qButton.backgroundColor = buttonColor
			qButton:Invalidate()
		else



			fac.qStack:RemoveChild(qButton)
		end

	else
		if count == 0 then
			
			if fac.selected then
				qButton.backgroundColor = queueColor
				qButton:Invalidate()
			else
				-- Echo('add new '.. defID ..' at ' .. place)
				local qStack = fac.qStack
				local color
				if alt then
					local place = (IM_OPT_altInsertBehind.value or fac.isRepeat) and 2 or 1
					InsertObject(qStack, qButton, place)
					qStack:Realign()
					color = yellow
				else
					qStack:AddChild(qButton)
					color = green
				end
				if qStack.children[MAX_VISIBLE + 1] then
					for i = MAX_VISIBLE + 1, #qStack.children do
						qStack:RemoveChild(qStack.children[i])
					end
				end
				if ((isSpec and WANT_USER_ANIMATE) and qButton.parent) or DGB_VIS then
					if qButton.parent then
						AnimateIcon(qPic, true, increment, count, alt)
					end
				end
			end
		end
		count = count + increment
	end
	qCount:SetCaption(count == 0 and '' or count)
end


RecreateFacbar = function(complete, relist)
	if not initialized then
		return
	end
	enteredTweak = false
	if inTweak then
		return
	end

	RemoveFactories(complete)

	if relist then
		facs = {}
		if SPECMODE_1V1 then
			ListFactoryTeam(0)
			ListFactoryTeam(1)
		else
			ListFactoryTeam(myTeamID)
		end
	end


	for i,fac in ipairs(facs) do
		fac:CreateControls(i)
	end

	stack_main:Invalidate()
	stack_main:UpdateLayout()
	if SPECMODE_1V1 ~= nil then
		stack_main2:Invalidate()
		stack_main2:UpdateLayout()
	end
	ShowTitles(options.show_title.value)
	widget:SelectionChanged(spGetSelectedUnits())
	widget:CommandsChanged()

end


local CMD_REPEAT = CMD.REPEAT
local CMD_OPT_SHIFT = CMD.OPT_SHIFT
local CMD_OPT_ALT = CMD.OPT_ALT
local CMD_OPT_RIGHT = CMD.OPT_RIGHT
local TO_UPDATE = {}
local PAGE = 0
local SEQUENCE = -1
local function FindOrder(fac, tag)
	for i, order in ipairs(spGetFactoryCommands(fac.id, -1) or EMPTY_TABLE) do
		if order.tag == tag then
			return order
		end
	end
end
function widget:KeyPress(key, mods, isRepeat)
	if key == 103 and mods.ctrl and not isRepeat then -- ctrl+G
		local fac = facs[1]
		if fac then
			local qStack = fac.qStack
			local qStore = fac.qStore
			local len = table.size(fac.qStore)
			if not TRY then
				TRY = 0
			end
			if qStack.children[2] then
				TRY = (TRY or 0) + 1
			end
			if TRY%2 == 1 then
				local len = #qStack.children
				local p1 = math.random(len)
				local qButton = qStack.children[p1]
				local p2 = p1
				while p2 == p1 do
					p2 = math.random(len)
				end
				local hName1 = UnitDefs[qStack.children[p1].name].humanName
				Echo('try to move ' .. hName1  .. ' from ' .. p1 .. ' to ' .. p2)
				qStack:SetChildLayer(qButton, p2)
				qStack:Realign()

				-- qButton:Invalidate()
			else
				if not qStack.children[len] then
					local tries = 0
					local function ChooseRandomControl()
						tries = tries + 1
						if tries == 100 then
							return
						end
						local chosen = math.random(len)
						local defID 
						local i = 0
						for _defID, control in pairs(qStore) do
							i = i + 1
							if i == chosen then
								defID = _defID
								break
							end
						end
						if not qStack.childrenByName[defID] then
							return qStore[defID], UnitDefs[defID].humanName
						else
							return ChooseRandomControl()
						end
					end
					local qButton, hName1 = ChooseRandomControl()
					local p1 = not qStack.children[1] and 1 or math.random(#qStack.children)
					if qButton then
						Echo('try to insert ' .. hName1  .. ' at ' .. p1, 'try finding', tries)
						qStack:AddChild(qButton, false, p1)
					end
				end
			end
		end
	end
end
function widget:UnitCommand(id, defID, teamID, cmd, params, opts)
	local fac =  facByID[id]
	if fac then
		if cmd == CMD_REPEAT then
			fac.isRepeat = params[1] == 1
		elseif cmd < 0 then
			UpdateQButton(-cmd, (opts.right and -1 or 1) * (opts.ctrl and 20 or 1) * (opts.shift and 5 or 1), fac, opts.alt)
		elseif cmd == 2 then -- can be to move a block, to delete a bunch, to delete a type, to delete all
			if params[1] then
				if params[1] < 0 and opts.alt then
					-- remove a type
					UpdateQButton(-params[1], '-all', fac)
				elseif SEQUENCE ~= PAGE then
					SEQUENCE = PAGE
				end
				if not TO_UPDATE.ignore then
					local obj = TO_UPDATE[fac]
					if not obj then
						local order = FindOrder(fac, params[1])
						obj = {order and -order.id or false, -1, 1}
						TO_UPDATE[fac] = obj
					else
						obj[3] = obj[3] + 1
					end
				end

				-- if params[1] < 0 and opts.alt then
				-- 	-- remove a type
				-- 	UpdateQButton(-params[1], '-all', fac)
				-- elseif SEQUENCE ~= PAGE then
				-- 	SEQUENCE = PAGE

				-- 	local order = FindOrder(fac, params[1])
				-- 	TO_UPDATE = {fac, order and -order.id or false, -1, 1}
				-- elseif TO_UPDATE then
				-- 	if TO_UPDATE ~= 'moving block' then
				-- 		TO_UPDATE[4] = TO_UPDATE[4] + 1
				-- 	end
				-- end
			end
		elseif cmd == 1 then
			if (params[2] or 0) < 0 then
				if SEQUENCE ~= PAGE then
					SEQUENCE = PAGE
					local opt = params[3]
					local mul
					if opt > 0 then
						mul = opt%(2*CMD.OPT_SHIFT) > CMD.OPT_SHIFT and 5 or 1
						mul = mul * (opt%(2*CMD.OPT_CTRL) > CMD.OPT_CTRL and 20 or 1)
					else
						mul = 1
					end
					TO_UPDATE[fac] = {-params[2], 1, 1 * mul}
				elseif not TO_UPDATE.ignore then
					local obj = TO_UPDATE[fac]
					if obj then
						if obj[2] == -1 then
							TO_UPDATE.ignore = true
							-- if params[1] == 0 or params[1] == 1 then
								-- do something? has moved to first position and cancelled the current build
							-- end
						else
							obj[3] = obj[3] + 1
						end
					end
				end
			end
		elseif cmd == 5 and not TO_UPDATE.ignore then -- happens after the order removings when stop production is called and help us detecting it
			-- stopping production
			local obj = TO_UPDATE[fac]
			if obj and obj[2] == -1 and obj[3] > 1 then
				TO_UPDATE = {}
				UpdateQButton('-all', '-all', fac)
			end
		end
		-- debug command received
		-- if cmd == 1 then
		-- 	Echo(cmd, 'params['..table.toline({params[1], params[2]})..', '..f.ReadOpts(params[3])..']' , 'opts['.. f.ReadOpts(opts)..']', os.clock())
		-- else			
		-- 	Echo(cmd, 'params['..table.toline(params)..']', 'opts['.. f.ReadOpts(opts)..']', os.clock())
		-- end
	end
end
function widget:Update()
	PAGE = PAGE + 1
	if TO_UPDATE.ignore then
		TO_UPDATE = {}
	elseif next(TO_UPDATE) then
		for fac, facUp in pairs(TO_UPDATE) do
			local defID, sign, amount = unpack(facUp)
			if defID then
				UpdateQButton(defID, sign * amount, fac)
			end
			TO_UPDATE[fac] = nil
		end
	end
	inTweak = widgetHandler.tweakMode
	
	if PAGE % UPDATE_RATE == 1 then
		for i,fac in ipairs(facs) do
			if spValidUnitID(fac.id) then
				UpdateFac(i, fac)
			end
		end
	end
	
	
	if inTweak and not enteredTweak then
		enteredTweak = true
		RemoveFactories()
		for i = 1,5 do
			AddFactory(0, 0, SPECMODE_1V1 ~= nil and LEFT.allyTeamID or 0)
		end
		stack_main:Invalidate()
		stack_main:UpdateLayout()
		if stack_main2 then
			for i = 1,5 do
				AddFactory(0, 0, SPECMODE_1V1 ~= nil and RIGHT.allyTeamID or 1)
			end
			stack_main2:Invalidate()
			stack_main2:UpdateLayout()
		end
		leftTweak = true
	end
	
	if not inTweak and leftTweak then
		enteredTweak = false
		leftTweak = false
		RecreateFacbar(false, true)
	end
end

function widget:KeyRelease(key, mods, isRepeat)
	if ALT_HELD and not mods.alt then
		ALT_HELD = false
	end
end

------------------------------------------------------

function widget:DrawWorld()
	-- Draw factories command lines
	if waypointMode > 1 then
		local id
		if waypointMode > 1 then
			id = facs[waypointFac].id
		end
		spDrawUnitCommands(id)
	end
end

function widget:UnitCreated(id, defID, teamID, builderID)
	if (teamID ~= myTeamID and not SPECMODE_1V1) then
		return
	end
	-- if builderID then
	-- 	local fac = facByID[builderID]
	-- 	if fac then
	-- 		facIsBuilding[id] = fac
	-- 		facIsBuilding[fac] = id
	-- 		fac.isBuildingDef = defID
	--		fac.isBuildingAlt = spGetFactoryCommands(builderID, 1)[1].options.alt
	-- 		return
	-- 	end
	-- end
	if not facDefID[defID] then
		return
	end

	AddFactory(id, defID, spGetUnitAllyTeam(id))
	orderTicket = orderTicket + 1
	facOrder[id] = orderTicket

	unfinished_facs[id] = true
end

function widget:UnitGiven(id, defID, unitTeam, oldTeam)
	widget:UnitCreated(id, defID, unitTeam)
end

function widget:UnitDestroyed(id, defID, unitTeam)
	if (unitTeam ~= myTeamID and not SPECMODE_1V1) then
		return
	end
	if not facDefID[defID] then
		return
	end
	for i,fac in ipairs(facs) do
		if id==fac.id then
			fac:Remove(id)
			return
		end
	end
end

function widget:UnitTaken(id, defID, unitTeam, newTeam)
	widget:UnitDestroyed(id, defID, unitTeam)
end


function widget:PlayerChanged(playerID)
	if myPlayerID ~= playerID then
		return
	end
	local myNewAllyTeamID = Spring.GetMyAllyTeamID()
	local myNewTeamID = Spring.GetMyTeamID()
	-- Echo("myAllyTeamID is ", myAllyTeamID)
	local spectating, fullread = Spring.GetSpectatingState()
	isSpec = spectating
	if SPECMODE_1V1 ~= nil then
		
		if SPECMODE_1V1 == false then
			if fullread then -- add the other player facs
				-- Echo('add team facs',myAllyTeamID == 0 and 1 or 0)
				SPECMODE_1V1 = true
				if force_update then
					RecreateFacbar(false, true)
					force_update = false
				else
					AddTeamFactories(myTeamID == 0 and 1 or 0)
				end
				myAllyTeamID = myNewAllyTeamID
				myTeamID = myNewTeamID
				return
			else
				if myAllyTeamID == myNewAllyTeamID then
					if force_update then
						RecreateFacbar(false, true)
						force_update = false
					end
					return -- nothing to do
				end
			end
		else
			if fullread then
				myAllyTeamID = myNewAllyTeamID
				myTeamID = myNewTeamID

				if force_update then
					RecreateFacbar(false, true)
					force_update = false
				end
				return -- nothing todo we still track both team
			end
			SPECMODE_1V1 = false
		end
	end
	myAllyTeamID = myNewAllyTeamID
	myTeamID = myNewTeamID

	RecreateFacbar(false, true)
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function FAC:Unselect()
	self.qStack:ClearChildren()
	self.selected = false
	local index = selectedFacI
	selectedFacI = -1
	UpdateFac(index, self)
end
function FAC:Select(index)
	self.qStack:ClearChildren()
	for i, defID in ipairs(self.buildList) do
		local qButton = self.qStore[defID]
		self.qStack:AddChild(qButton)
	end
	selectedFacI = index
	self.selected = true
	UpdateFac(selectedFacI, self)
end
function widget:SelectionChanged(selectedUnits)
	newSelection = selectedUnits
end
function widget:CommandsChanged()
	if not newSelection then
		return
	end
	local newID = not newSelection[2] and newSelection[1]
	newSelection = false
	local newI = -1
	if newID then
		for i, fac in ipairs(facs) do
			if newID == fac.id then
				newI = i
				break
			end
		end
	end
	if newSelectedFacI == selectedFacI then
		return
	end
	if selectedFacI ~= -1 then
		facs[selectedFacI]:Unselect()
	end
	if newI == -1 then
		return
	end
	selectedFacI = newI
	facs[selectedFacI]:Select(selectedFacI)
end


function widget:MouseRelease(x, y, button)
	if (waypointMode>0)and(not inTweak) and (waypointMode>0)and(waypointFac>0) then
		WaypointHandler(x,y,button)
	end
	return -1
end

function widget:MousePress(x, y, button)
	-- if not DONE then
	-- 	window_facbar:SetPos(winx, winy)
	-- 	window_facbar2:SetPos(win2x, win2y)
	-- 	DONE = true
	-- end
	if waypointMode>1 then
		-- greedy waypointMode
		return (button~=2) -- we allow middle click scrolling in greedy waypoint mode
	end
	if waypointMode>1 then
		Spring.Echo("FactoryBar: Exited easy waypoint mode")
		Spring.PlaySoundFile(sound_waypoint, 1, 'ui')
	end
	waypointFac  = -1
	waypointMode = 0
	return false
end

local function CreateWin(winx, winy, i, title)
	-- setup Chili
	local stack = Grid:New{
		padding = {0,0,0,0},
		itemPadding = {0, 0, 0, 0},
		itemMargin = {0, 0, 0, 0},
		width='100%',
		height = '100%',
		resizeItems = false,
		orientation = 'horizontal',
		centerItems = false,
		preserveChildrenOrder = true,
		columns=1,
		dockable = false,
	}
	local titlectrl = Label:New{ 
		x = 2,
		caption = title or WG.Translate("interface", "factories"),
		-- padding = 
	}
	local win = Window:New{

		padding = {3,3,3,3,},
		dockable = true,
		name = "facbar_win" .. i,
		x = winx, y = winy,
		width  = 600,
		height = 200,
		parent = Chili.Screen0,
		draggable = false,
		tweakDraggable = true,
		tweakResizable = true,
		resizable = false,
		dragUseGrip = false,
		minWidth = 56,
		minHeight = 56,
		color = {0,0,0,0},
		children = {
			titlectrl,
			stack,
		},
		OnClick = {
			function(self)
				local alt, ctrl, meta, shift = Spring.GetModKeyState()
				if meta then 
					WG.crude.OpenPath(options_path)
					WG.crude.ShowMenu()
					return true
				end
				return false
			end 
		},
	}
	local font = titlectrl.font
	font.autoOutlineColor = false
	return win, stack, titlectrl
end
local function ShowTitle(stack, title, bool)
	if not (stack and title) then
		return
	end
	if bool and not stack.children[1] then
		bool = false
	end
	if title.hidden ~= not bool then
		if bool then
			title:Show()
			stack.y = 10
		else
			title:Hide()
			stack.y = 0
		end
	end
end
function ShowTitles(bool)
	if stack_main then
		ShowTitle(stack_main, title, bool)
	end
	if stack_main2 then
		ShowTitle(stack_main2, title2, bool)
	end
end

local function GetOpposingAllyTeams()
	local gaiaAllyTeamID = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID(), false))
	local allyObjs = {}
	local allyTeamList = GetLeftRightAllyTeamIDs()
	for i = 1, #allyTeamList do
		local allyTeamID = allyTeamList[i]

		local teamList = Spring.GetTeamList(allyTeamID)

		if allyTeamID ~= gaiaAllyTeamID and teamList[1] then
			local name = Spring.GetGameRulesParam("allyteam_long_name_" .. allyTeamID)
			-- if string.len(name) > 10 then
			-- 	name = Spring.GetGameRulesParam("allyteam_short_name_" .. allyTeamID)
			-- end
			allyObjs[i] = {
				allyTeamID = allyTeamID, 
				name = name, 
				teamID = teamList[1], 
				color = {Spring.GetTeamColor(teamList[1])} or {1,1,1,1},
			}
		end
	end
	if #allyObjs ~= 2 then
		return
	end
	return allyObjs[1], allyObjs[2]
end

local function strColor(str, c)
	return '\255' .. char(floor(c[1]*255))..char(floor(c[2]*255))..char(floor(c[3]*255)) .. str .. '\008'
end
function Init()
	local winx, winy, win2x, win2y
	if SPECMODE_1V1 ~= nil then
		winx, winy, win2x, win2y = vsx * 1/10, vsy * 1/9, vsx * (1/2 + 1/20), vsy * 1/9
		winx, winy, win2x, win2y = math.round(winx), math.round(winy), math.round(win2x), math.round(win2y) -- if not rounded the controls are blurry
		window_facbar, stack_main, title = CreateWin(winx, winy, 1, LEFT.tooltip)
		window_facbar2, stack_main2, title2 = CreateWin(win2x, win2y, 2, RIGHT.tooltip)
	else
		winx, winy = 0, '30%'
		window_facbar, stack_main, title = CreateWin(winx, winy, '')
	end
	ShowTitles(options.show_title.value)
	initialized = true

	RecreateFacbar(false, true)
	widget:SelectionChanged(spGetSelectedUnits())
	widget:CommandsChanged()
end

function widget:Initialize()
	IM_OPT_altInsertBehind = WG.GetWidgetOption('Chili Integral Menu','Settings/HUD Panels/Command Panel', 'altInsertBehind') or false
	if (not WG.Chili) then
		widgetHandler:RemoveWidget(widget)
		return
	end
	local spectating, fullread = Spring.GetSpectatingState()
	if not spectating and not options.active.value then
		options.active:OnChange()
		return
	elseif spectating and not options.spec_active.value then
		option.spec_active:OnChange()
		return
	end
	myAllyTeamID = Spring.GetMyAllyTeamID()
	myTeamID = Spring.GetMyTeamID()

	-- Echo('myTeamID',myTeamID,'myAllyTeamID',myAllyTeamID)
	if spectating then
		isSpec = true
		local teams = Spring.GetTeamList()
		if teams[3] and not teams[4] then
			LEFT, RIGHT = GetOpposingAllyTeams()
			LEFT.tooltip = strColor(LEFT.name, LEFT.color)
			RIGHT.tooltip = strColor(RIGHT.name, RIGHT.color)
			SPECMODE_1V1 = fullread
		end
	end
	self:ViewResize(widgetHandler:GetViewSizes())

	Chili = WG.Chili
	Button = Chili.Button
	Label = Chili.Label
	Window = Chili.Window
	StackPanel = Chili.StackPanel
	Grid = Chili.Grid
	TextBox = Chili.TextBox
	Image = Chili.Image
	Progressbar = Chili.Progressbar
	screen0 = Chili.Screen0

	Init()

end
-- ANIMATER


function widget:DrawScreenPost()
	if not initialized or spIsGUIHidden() then
		return
	end
	Animater:RunAll()
end


function widget:Shutdown()
	if window_facbar  then
		if window_facbar.parent then
			window_facbar.parent:RemoveChild(window_facbar)
		end
		window_facbar = nil
	end
	if window_facbar2  then
		if window_facbar2.parent then
			window_facbar2.parent:RemoveChild(window_facbar2)
		end
		window_facbar2 = nil
	end
	if stack_main then
		stack_main:Dispose()
		stack_main = nil
	end
	if stack_main2 then
		stack_main2:Dispose()
		stack_main2 = nil
	end
	if title then
		title:Dispose()
		title = nil
	end
	if title2 then
		title2:Dispose()
		title2 = nil
	end


	for obj, v in pairs(facByControl) do
		if not obj.disposed then
			obj:Dispose()
		end
	end
end

f.DebugWidget(widget)