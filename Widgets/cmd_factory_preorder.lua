function widget:GetInfo()
	return {
		name      = "Factory Preorder",
		desc      = "Allow to control factory before it is placed",
		author    = "Helwor, few part from cmd_field_factory.lua",
		date      = "Nov 2025",
		license   = "GNU GPL, v2 or later",
		layer     = -12, -- before EzTarget that can trigger cmd_customformations2
		enabled   = true,
		handler   = true,
	}
end
-- to work better, need: api_selection_handler, addon_handler_multi_register_global, api_clamp_mouse_to_world, draw_placements, gui_api_draw_before_chili, api_on_widget_state, (and eventually the whole hel-k system :p)

local Echo = Spring.Echo
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local screenWidth, screenHeight = Spring.GetViewGeometry()
local playerID = Spring.GetMyPlayerID()

-- option defaults
local track_update = 2 -- seconds between checking command queues
local max_instances = 8 -- maximum numbers of UI objects
local spawned_ttl = 10 -- seconds live once the fac nanoframe has been plopped -- will not close until the window is closed/hidden
local ghost_appearance = 3 -- choice 1 to 7 from normal to very glowy
-- local ghostColor = {0.1,0.3,0.9,0.2}
local ghostColor = {0.161, 0.376, 0.547, 0.366}
local ghostColorL = {}
for i = 1, 4 do
	ghostColorL[i] = ghostColor[i] * 4/5
end
local ghost_clickable = false
local button_size = math.max(math.floor(screenHeight / 19))
local auto_develop = false
local auto_develop_as_combined = true
local allow_rightclick = true -- override right click
local allow_commands = true -- override move commands
local close_upon_moveorder = false -- close panel after move order issued

local showTempOrders = false
local showGhost = false
local closeUponShiftRelease = false
--

local IntegralMenu
local Screen0
local EMPTY_TABLE = {}
local ESC_KEY = Spring.GetKeyCode('esc')
local FIGHT_KEY, PATROL_KEY
local fake_command

local TIME_OUT_ORDER = 1 -- seconds to wait before releasing preorders, so the initial states of the fac is applied before 
local SLOW_UPDATE = 10 -- seconds between registered con update in case (to cover rare case when UnitCommand (?) didnt catch anything)
local PREGAME_UPDATE = 0.5 -- seconds between check of pregame queue
local invite_size = 40 -- default size
local ui_relative_x = 6/11 -- relative position of the first invite UI to the screen
local ui_relative_y = 7/10  

local ROWS = 2
local COLUMNS = 6

local Chili
local CMD_RAW_MOVE = Spring.Utilities.CMD.RAW_MOVE

local trackedUnits
local _, factoryUnitPosDef = include("Configs/integral_menu_commands.lua", nil, VFS.RAW_FIRST) -- TODO find how to include that file without getting the bunch of globals going along

local factoryDefs = {}
local plateOfFac = {}
local facOfPlate = {}
-- NOTE:
	-- def.customParams.notreallyafactory => Athena, Airpad
	-- def.customParams.isfakefactory => Athena, Strider Hub
for defID, def in ipairs(UnitDefs) do
	if def.buildOptions and def.buildOptions[1] and (def.isFactory or def.isImmobile) then
		local cp = def.customParams
		if cp.child_of_factory then
			facOfPlate[defID] = UnitDefNames[cp.child_of_factory].id
		end
		if cp.parent_of_plate then
			plateOfFac[defID] = UnitDefNames[cp.parent_of_plate].id
		end
		factoryDefs[defID] = {
			isFactory = def.isFactory,
			range = def.buildDistance * (def.isImmobile and 1 or 7),
			sx = def.xsize * 4,
			sz = def.zsize * 4,
		}
	end
end

local function RandomFac()
	local r = math.random(1, table.size(factoryDefs))
	local defID = next(factoryDefs)
	local i = 1
	while i < r do
		defID = next(factoryDefs, defID)
		i = i + 1
	end
	return defID
end
local amphFacDefID = UnitDefNames['factoryamph'].id

local colors = {}
do
	local file = VFS.LoadFile('cmdcolors.txt')
	for i, cmd in ipairs({'move', 'fight', 'patrol'}) do
		local r, g, b, a = file:match(cmd..'[ ]-([^ ]+)[ ]-([^ ]+)[ ]-([^ ]+)[ ]-([^ ]+).-\n')
		local cmdID = cmd == 'move' and CMD_RAW_MOVE or cmd == 'fight' and CMD.FIGHT or cmd == 'patrol' and CMD.PATROL
		colors[cmdID] = {tonumber(r), tonumber(g), tonumber(b), tonumber(a)}
	end
end
-- speed ups
local spGetUnitsInCylinder      = Spring.GetUnitsInCylinder
local spGetUnitPosition         = Spring.GetUnitPosition
local spGetUnitDefID            = Spring.GetUnitDefID
local spGetUnitIsStunned        = Spring.GetUnitIsStunned
local spGetScreenGeometry       = Spring.GetScreenGeometry
local spIsGUIHidden             = Spring.IsGUIHidden
local spGetUnitIsStunned        = Spring.GetUnitIsStunned
local spGetUnitRulesParam       = Spring.GetUnitRulesParam
local spGetSelectedUnitsSorted  = Spring.GetselectedUnitsSorted
local spGetUnitPosition			= Spring.GetUnitPosition
local spGiveOrderToUnit			= Spring.GiveOrderToUnit
local spuGetUnitRepeat			= Spring.Utilities.GetUnitRepeat
local spGetMouseState			= Spring.GetMouseState
local spGetSelectedUnitsSorted  = Spring.GetSelectedUnitsSorted
local spFindUnitCmdDesc 		= Spring.FindUnitCmdDesc
local spGetCommandQueue 		= Spring.GetCommandQueue
local spGetModKeyState			= Spring.GetModKeyState
local spGetActiveCommand		= Spring.GetActiveCommand
local spSetActiveCommand		= Spring.SetActiveCommand
local spIsUserWriting			= Spring.IsUserWriting
local spGetUnitBuildFacing		= Spring.GetUnitBuildFacing

local glPushMatrix  = gl.PushMatrix
local glTexture     = gl.Texture
local glTranslate   = gl.Translate
local glScale       = gl.Scale
local glTexRect     = gl.TexRect
local glBillboard   = gl.Billboard
local glPopMatrix   = gl.PopMatrix
local glColor       = gl.Color
local glLineStipple	= gl.LineStipple
local glLineWidth	= gl.LineWidth
local glDepthTest	= gl.DepthTest
local glBeginEnd	= gl.BeginEnd
local GL_LINES		= GL.LINES
local glPushAttrib	= gl.PushAttrib
local glPopAttrib	= gl.PopAttrib
local glVertex		= gl.Vertex
local Drawline = function(x,y,z, x2, y2, z2)
	glVertex(x,y,z)
	glVertex(x2,y2,z2)
end
--

local myTeamID
local myPlayerID = Spring.GetMyPlayerID()
local vsx, vsy = Spring.Orig.GetViewSizes()
local invite_x = vsx * ui_relative_x
local invite_y = vsy * ui_relative_y
local ui_icon = 'LuaUI/Images/commands/Bold/buildplate.png'
local offsetY = 0

local tweakMode = false
local preGameCheck = PREGAME_UPDATE
local fac_preorder_tweak_win
local preGame
local trackedUnits ={}
local checkUnits = {}
local trail = false
local spGetSelectedUnits = Spring.GetSelectedUnits
local selMap, selDefID
local myUnitsSelected = false
local GetUnderSea
local CheckPotent
local removeCommandOnShiftRelease = false

local FacUI = {
	stack = {},
	map = {},
	active = false,
	hasInvite = 0,
	hasWin = 0,
	hasDevelopped = 0,
	hasOrder = 0,
	hasTTL = 0,
	time = false,
	combo = false,
	highlight = false,
}
FacUI.mt = {__index = FacUI}

-------- options

options_path = 'Hel-K/' .. widget.GetInfo().name
options = {}
options.track_update = {
	name = 'Unit Order Track Update',
	type = 'number',
	min = 0.1, max = 5, step = 0.1,
	value = track_update,
	desc = "How long between checks for tracked unit's order, watch for performance impact",
	OnChange = function(self)
		track_update = self.value
	end

}

options.max_instances = {
	name = 'Max UI objects',
	type = 'number',
	min = 1, max = 20, step = 1,
	value = max_instances,
	OnChange = function(self)
		max_instances = self.value
	end
}

options.spawned_ttl = {
	name = 'UI object Life Time after plop',
	desc = 'How long the UI objects remain after the real factory got started building. Set to forever if max value.',
	type = 'number',
	min = 1, max = 60, step = 1,
	value = spawned_ttl,
	tooltipFunction = function(self)
		return self.value == self.max and 'Forever' or self.value
	end,
	OnChange = function(self)
		local oldv = spawned_ttl
		spawned_ttl = self.value == self.max and 1e9 or self.value
		for i, obj in ipairs(FacUI.stack) do
			if obj.ttl then
				local time_spent = (TIME_OUT_ORDER + oldv) - obj.ttl
				obj.ttl = TIME_OUT_ORDER + spawned_ttl - time_spent
			end
		end
	end
}

options.ghost_clickable = {
	name = 'Ghost Clickable',
	type = 'bool',
	desc = '',
	value = ghost_clickable,
	OnChange = function(self)
		ghost_clickable = self.value
	end,
}

options.ghost_appearance = {
	name = 'Ghost Appearance',
	type = 'number',
	min = 1, max = 7, step = 1,
	value = ghost_appearance,
	update_on_the_fly = true,
	tooltipFunction = function(self) 
		if (WG.Chili and WG.Chili.Screen0.hoveredControl.name == self.name) then -- hax to make sure the user is touching the slide bar TODO: IMPLEMENT IN EPIC MENU
			ghost_appearance = self.value
			local vsx, vsy = Spring.GetViewGeometry()
			local _, pos = Spring.TraceScreenRay(vsx/2, vsy/2, true)
			if pos then
				showGhost = {defID = showGhost and showGhost.defID or RandomFac(), x = pos[1], y = pos[2], z = pos[3], timeout = 7}
			end
		end
		return self.value
	end,
	OnChange = function(self)
		ghost_appearance = self.value
	end,
}
options.ghost_color = {
	name = 'Ghost Color',
	type = 'colors',
	value = ghostColor,
	OnChange = function(self)
		local r, g, b, a = unpack(self.value)
		ghostColor[1], ghostColor[2], ghostColor[3], ghostColor[4] = r, g, b, a
		ghostColorL = {r*4/5, g*4/5, b*4/5, a*4/5}
		if showGhost then
			showGhost.timeout = 7
		end
	end
}

options.button_size = {
	name = 'Panel Buttons Size',
	type = 'number',
	min = 15, step = 1, max = 70,
	value = button_size,
	update_on_the_fly = true,
	OnChange = function(self)
		button_size = self.value

		for i, obj in ipairs(FacUI.stack) do
			if obj.win then
				local extra = 0
				for i, c in ipairs(obj.win.children) do
					if i > 1 then
						extra = extra + c.height
					end
				end
				local x, y = obj.win.x + obj.win.width/2, obj.win.y + (obj.win.height) - (extra) + 20
				obj.win:Dispose()
				obj.win = nil
				if obj.combined then
					for defID in pairs(obj.combined) do
						obj:GenerateBuildPanel(defID, x, y)
					end
				else
					obj:GenerateBuildPanel(obj.defID, x, y)
				end
				if not obj.developped then
					obj.win:Hide()
				end
			end
		end
	end,
}

options.auto_develop = {
	name = 'Auto Develop New Factory Panel',
	type = 'bool',
	value = auto_develop,
	OnChange = function(self)
		auto_develop = self.value
	end,
}

options.auto_develop_as_combined = {
	name = 'Auto Develop As Combined',
	type = 'bool',
	value = auto_develop_as_combined,
	OnChange = function(self)
		auto_develop_as_combined = self.value
	end,
}

options.allow_rightclick = {
	type = 'bool',
	name = 'Allow Right Click for Move',
	desc = 'When opened, Right click is captured to preorder move commands, ignoring the current real selection',
	value = allow_rightclick,
	OnChange = function (self)
		allow_rightclick = self.value
	end,
}

options.allow_commands = {
	type = 'bool',
	name = 'Allow Moving Command Hotkeys',
	desc = 'When opened, hotkeys for Move, Patrol and Attack Move can be used to preorder the factory, ignoring the current real selection',
	value = allow_commands,
	OnChange = function (self)
		allow_commands = self.value
	end,
}

options.close_upon_moveorder = {
	type = 'bool',
	name = 'Close Panel Upon Move Order',
	value = close_upon_moveorder,
	OnChange = function(self)
		close_upon_moveorder = self.value
	end
}
------------------


do
	local potentDefID = setmetatable({}, {__index = function(self, k) local t = {} rawset(self, k, t) return t end})
	function CheckPotent(defID, cmdID, unitID)
		local can = potentDefID[defID][cmdID]
		if can == nil then
			can = spFindUnitCmdDesc(unitID, cmdID) or false
			potentDefID[defID][cmdID] = can
		end
		return can
	end
end

local function GetMouseWorldPos(x, y)
	local _, pos
	local useMinimap, throughWater = true, FacUI:GetAllDevUnderSea()
	if WG.ClampScreenPosToWorld then
		_, _, pos = WG.ClampScreenPosToWorld(x, y, useMinimap, throughWater)
	else
		_, pos = spTraceScreenRay(x, y, useMinimap, throughWater)
	end
	return pos
end

local function MakeTweakWin() -- a window only to be interacted with during tweak mode
	fac_preorder_tweak_win = {
		parent = WG.Chili.Screen0,
		name = 'fac_preorder_tweak_win',
		-- NOTE: dockable beeing true  and if the control has fixed name, the window pos and size are recovered after unloading/reloading widget (use dockableSavePositionOnly=true to not really dock but only save position)
		-- but what if user doesn't have docking enabled
		-- dockable = true, 
		-- dockableSavePositionOnly = true,
		minWidth = 30,
		minHeight = 30,
		maxHeight = 100,
		maxWidth = 100,
		hitpadding = {0,0,0,0}, -- default is 4,4,4,4 -- need to lower it to catch grip when window is small
		x = invite_x,
		y = invite_y,
		width = invite_size,
		height = invite_size,
		fixedRatio = true,
		resizable = false,
		draggable = false,
		OnResize = { function(self)
			invite_size = self.width
			-- resize grip area doesn't adapt with small window, and only bottom and right are changed to -1, -1 in tweakmode even if it visually appear shrinked
			local min = math.min
			local grip = self.boxes.resize -- -21 -21 -10 -10 as default
			grip[1], grip[2] = - min(invite_size/4, 21), - min(invite_size/4, 21)
			 -- grip[3], grip[4] = - min(invite_size/10, 10), - min(invite_size/10, 10) -- no need if we're doing this only in tweak mode
		end},
		tweakDraggable = true,
		tweakResizable = true,
		borderThickness = 0,
		color = {0,0,0,0}, -- avoid the window flashing between the time the tweak mode goes off and the time we can detect it happened (there's no direct callin to inform us)
	}
	WG.Chili.Window:New(fac_preorder_tweak_win)
end

-------------------------------------------------------------------------------

--------------------------------------------------------------------------------

local function GetOptionsPosition(width, height, x, y)
	if not x then
		x, y = Spring.ScaledGetMouseState()
		y = screenHeight - y
	end
	x = x - width / 2
	y = y - height - 20
	
	if x + width > screenWidth - 2 then
		x = screenWidth - width - 2
	end
	if y + height > screenHeight - 2 then
		y = screenHeight - height - 2
	end
	
	local map = WG.MinimapPosition
	if map then
		-- Only move tooltip up and/or left if it overlaps the minimap. This is because the
		-- minimap does not have tooltips.
		if x < map[1] + map[3] and y < map[2] + map[4] then
			local inX = x + width - map[1] + 2
			local inY = y + height - map[2] + 2
			if inX > 0 and inY > 0 then
				if inX > inY then
					y = y - inY
				else
					x = x - inX
				end
			end
		end
		
		if x < 2 then
			x = 2
		end
		if y < 2 then
			y = 2
		end
		if x + width > screenWidth - 2 then
			x = screenWidth - width - 2
		end
		if y + height > screenHeight - 2 then
			y = screenHeight - height - 2
		end
	end
	
	return math.floor(x), math.floor(y)
end



function FacUI:New(defID, params)
	local index = #self.stack + 1
	if index > max_instances then
		return
	end
	local keyID
	if defID then
		keyID = defID..'-'..params[1]..'-'..params[3]..'-'..(params[4] or 0)
		if FacUI.map[keyID] then
			return
		end
	end
	local obj = {
		created = os.clock(),
		index = index,
		invite_x = invite_x - invite_size * (index - 1),
		invite_y = invite_y,
		icon = ui_icon,
		win = false,
		inviting = true,
		developped = false,
		unitID = false,
		timeout = false,
		combined = false,
		ttl = false,
		amount = {},
		controls = {},
		color = ghostColorL,
	}
	FacUI.hasInvite = FacUI.hasInvite + 1
	self.stack[obj.index] = obj
	setmetatable(obj, self.mt)
	if defID then
		obj.icon = "#" .. defID
		obj.defID = defID
		obj.pos = params
		obj.preOrders = {}
		obj.preMoveOrders = {}
		obj.attached = {}
		obj.hasAttached = 0
		obj.range = factoryDefs[defID].range
		obj.isFactory = factoryDefs[defID].isFactory
		obj.keyID = keyID
		local facing = obj.pos[4] or 0
		local sx, sz = factoryDefs[defID].sx, factoryDefs[defID].sz
		if facing%2 == 1 then
			sx, sz = sz, sx
		end
		obj.sx, obj.sz = sx, sz
		self.map[keyID] = obj
	else
		return obj
	end
	if index == 1 then
		FacUI.active = true
		if not tweakMode then
			FacUI.time = os.clock() + 1
		end
	else
		self:UpdateCombo(defID)
	end
	if auto_develop then
		local combo = FacUI.combo
		if auto_develop_as_combined and combo then
			local x, y
			if combo.win then
				x, y = combo.win.x, combo.win.y
			else
				x, y = invite_x, invite_y + 100
			end
			combo:DevelopInvite(x, y)
			if FacUI.hasDevelopped > 1 then
				for i, obj in ipairs(self.stack) do
					if obj.defID then
						obj:HideWin()
					end
				end
			end
		else
			obj:DevelopInvite(invite_x, invite_y + 100)
		end
	end
	return obj
end


function FacUI:GetClosestBuildPos(defID, px, py, pz)
	return Spring.ClosestBuildPos(myTeamID, defID, px, 0, pz, self.range, 0, 0)
end


function FacUI:ExecuteOrder(cmdID, alt, ctrl, shift, right)
	local opt = (ctrl and CMD.OPT_CTRL or 0) + (shift and CMD.OPT_SHIFT or 0) + (right and CMD.OPT_RIGHT or 0)
	if cmdID >= 0 then
		local pos = alt
		local opt = shift and CMD.OPT_SHIFT or 0
		if not self.isFactory and cmdID == CMD_RAW_MOVE then
			if widgetHandler:CommandNotify(cmdID, pos, {alt = false, ctrl = false, meta = false, shift = shift, right = false, coded = opt}) then -- let strider_hub_alt handle the move
				return
			end
		end
		spGiveOrderToUnit(self.unitID, cmdID, pos, opt)
		return
	elseif not self.isFactory then
		local x, y, z = self:GetClosestBuildPos(-cmdID, unpack(self.pos))
		if x == -1 then
			Echo('['..widget:GetInfo().name..']: '.. UnitDefs[self.defID].humanName .. ' #' .. self.unitID .. ' couldn\'t find a location to build ' .. UnitDefs[-cmdID].humanName .. '.')
		else
			spGiveOrderToUnit(self.unitID, cmdID, {x, y, z, 0}, opt)
		end
		return
	end
	if alt then
		-- Repeat alt has to be handled by engine so that the command is removed after completion.
		if not spuGetUnitRepeat(self.unitID) then
			spGiveOrderToUnit(self.unitID, CMD.INSERT, {1, -cmdID, opt}, CMD.OPT_ALT + CMD.OPT_CTRL)
		else
			spGiveOrderToUnit(self.unitID, cmdID, EMPTY_TABLE, opt + CMD.OPT_ALT)
		end
	else
		spGiveOrderToUnit(self.unitID, cmdID, EMPTY_TABLE, opt)
	end
end

function FacUI:AddPreMoveOrder(cmdID, alt, ctrl, shift, right)
	local diff = 1
	if not shift then
		diff = -#self.preMoveOrders + 1
		self.preMoveOrders = {}
	end
	local preMoveOrders = self.preMoveOrders
	preMoveOrders[#preMoveOrders + 1] = {cmdID, alt, ctrl, shift, right}
	return diff
end

function FacUI:AddPreorder(cmdID, alt, ctrl, shift, right)
	local preOrders = self.preOrders
	preOrders[#preOrders + 1] = {cmdID, alt, ctrl, shift, right}
end

function FacUI:NewOrder(cmdID, alt, ctrl, shift, right)
	if self.unitID and not self.timeout then
		self:ExecuteOrder(cmdID, alt, ctrl, shift, right)
	else
		self:AddPreorder(cmdID, alt, ctrl, shift, right)
		FacUI.hasOrder = FacUI.hasOrder + 1
	end
end

function FacUI:AddMoveOrder(cmdID, pos, multi)
	local shift = select(4, spGetModKeyState())
	local combo = FacUI.combo
	local count = 0
	local toUpdate = {}
	if combo and combo.developped then
		for i, obj in ipairs(self.stack) do
			if obj.defID then
				toUpdate[#toUpdate + 1] = obj
			end
		end
	else
		for i, obj in ipairs(self.stack) do
			if obj.developped then
				toUpdate[#toUpdate + 1] = obj
			end
		end
	end

	if multi then
		ReorderNoX(toUpdate, pos)
	else
		pos[4], pos[5], pos[6] = nil, nil, nil
	end

	for i, obj in ipairs(toUpdate) do
		local pos = pos
		if multi then
			count = count + 1
			pos = pos[count]
		end
		if obj.unitID and not obj.timeout then
			obj:ExecuteOrder(cmdID, pos, false, shift, false)
		else
			local diff = obj:AddPreMoveOrder(cmdID, pos, false, shift, false)
			FacUI.hasOrder = FacUI.hasOrder + diff
		end
	end
	if close_upon_moveorder then
		if not shift then
			FacUI:HideAllWins()
			showTempOrders = 1
		else
			closeUponShiftRelease = true
		end
	end
end



function FacUI:UpdateAmount(facDefID, defID, q, remove)
	local defKey = facDefID..'-'..defID
	local amount = remove and 0 or math.max((self.amount[defKey] or 0) + q, 0)
	self.amount[defKey] = amount
	local control = self.controls['amount'..defID]
	if control then
		control:SetCaption(amount == 0 and '' or amount)
	end
end

function FacUI:RemovePreOrders(facDefID)
	if self.preOrders then
		FacUI.hasOrder = FacUI.hasOrder - #self.preOrders
		self.preOrders = {}
	end
	for defKey, amount in pairs(self.amount) do
		if amount > 0 then
			local _facDefID, _defID = defKey:match('^(%d+)%-(%d+)')
			if _facDefID == tostring(facDefID) then
				self:UpdateAmount(_facDefID, _defID, 0, true)
			end
		end
	end

end

function FacUI:MakeButton(x, y, defID, def, facDefID, stunned)
	local function DoClick(ctrl, _, _, button)
		if defID then
			local toUpdate = {[self] = true}
			if self.combined then
				for i, obj in ipairs(self.stack) do
					if not obj.combined then
						if obj.defID == facDefID or obj.defID == facOfPlate[facDefID] or obj.defID == plateOfFac[facDefID] then
							toUpdate[obj] = true
						end
					end
				end
			elseif FacUI.combo then
				toUpdate[FacUI.combo] = true
			end

			local alt, ctrl, _, shift = spGetModKeyState()
			local right = button == 3
			local fakeFac = not factoryDefs[facDefID].isFactory
			local skip = fakeFac and right
			if fakeFac then -- TODO IMPLEMENT LONG QUEUE FOR FAKE FACTORY SOME DAY
				shift, ctrl = false, false
			end
			local q = (ctrl and 20 or 1) * (shift and 5 or 1) * (right and -1 or 1)

			for obj in pairs(toUpdate) do
				if fakeFac then
					obj:RemovePreOrders(facDefID)
				end
				if not skip then
					if obj.defID then
						obj:NewOrder(-defID, alt, ctrl, shift, right)
					end
					obj:UpdateAmount(facDefID, defID, q)
				end
			end
		else -- remove completely
			self:Delete()
		end
	end

	local button = Chili.Button:New {
		name = def and def.name or 'cancel',
		x = x,
		y = y,
		width = button_size,
		height = button_size,
		caption = false,
		noFont = true,
		padding = {0, 0, 0, 0},
		parent = parent,
		preserveChildrenOrder = true,
		tooltip = def and def.humanName or "Cancel",
		OnClick = {DoClick},
		backgroundColor = stunned and {0.9,0.4,0.2,1} or nil,
		focusColor = stunned and {0.9,0.4,0.2,1} or nil,
		-- backgroundHoveredColor = stunned and {0.9,0.4,0.2,1} or nil,
	}

	if defID then
		local l_height = math.floor(button_size / 4)

		self.controls['amount'..defID] = Chili.Label:New {
			name = "amount",
			y = l_height / 8,
			right = 0,
			height = l_height,
			fontsize = l_height,
			parent = button,
			caption = 'XXX' , -- make the caption non empty to force display
		}
		Chili.Label:New {
			name = "metal_cost",
			x = "15%",
			right = 0,
			bottom = l_height / 8,
			height = l_height,
			fontsize = l_height,
			parent = button,
			caption = def.metalCost,
		}
		Chili.Image:New {
			name = 'image',
			x = "5%",
			y = "4%",
			right = "5%",
			bottom = l_height,
			keepAspect = false,
			file = "#" .. defID,
			file2 = WG.GetBuildIconFrame(def),
			parent = button,
		}

		self.controls['amount'..defID]:SetCaption(self.amount[facDefID..'-'..defID] or '') -- using SetCaption to force the display
	else
		Chili.Image:New {
			name = 'image',
			x = "7%",
			y = "10%",
			right = "7%",
			bottom = "10%",
			keepAspect = true,
			file = "LuaUI/Images/commands/Bold/cancel.png",
			parent = button,
		}
	end
	return button
end

function FacUI:GenerateBuildPanel(facDefID, x, y, stunned)
	-- TODO Uniformize the size handling
	if not combine then
		warned = false
	end
	local padLeft, padTop, padRight, padBot = 14, 22, 14, 10
	COUNT = (COUNT or 0) + 1
	local def = UnitDefs[facDefID]
	if not self.win then
		local width = padLeft + padRight + button_size * COLUMNS
		local height = padTop + padBot + button_size * ROWS
		local x, y = GetOptionsPosition(width, height, x, y)
		self.win = Chili.Window:New{
			x = x,
			y = y,
			width = width,
			height = height,
			padding = {padLeft, padTop, padRight, padBot},
			classname = "main_window_small",
			textColor = {1, 1, 1, 0.55},
			parent = Chili.Screen0,
			dockable  = false,
			resizable = false,
			caption = (self.combined and 'Combined' or def.humanName)..' Preorders: ',
			backgroundColor = {0,0,0,0},
			OnDispose = {function()
				for k, ctrl in pairs(self.controls) do
					ctrl:Dispose()
					self.controls[k] = nil
				end
			end},
		}
		if WG.MakeMinizable then
			WG.MakeMinizable(self.win)
		end
		self.win:BringToFront()
	end
	local def = UnitDefs[facDefID]
	local name = def.name
	local buildList = def.buildOptions
	local layoutData = factoryUnitPosDef[name]
	if not buildList then
		return
	end

	local lastPanel = self.win.children[#self.win.children]
	local extraHeight = lastPanel and 4 or 0
	if lastPanel then
		for i, button in ipairs(lastPanel.children) do
			if button.name:find('cancel') then
				lastPanel:RemoveChild(button)
				break
			end
		end
		self.win:SetPos(nil, self.win.y - (lastPanel and extraHeight or 0), nil, self.win.height + button_size * ROWS + extraHeight)
	end
	local panel = Chili.Panel:New{
		name = 'panel_' .. facDefID,
		x = 0,
		y = lastPanel and (lastPanel.y + lastPanel.height + extraHeight) or 0,
		height = button_size * ROWS,
		right = 0,
		padding = {0, 0, 0, 0},
		backgroundColor = {1, 1, 1, 0},
	}
	
	for i = 1, #buildList do
		local bDefID = buildList[i]
		local bdef = UnitDefs[bDefID]
		local buildName = bdef.name
		local position = buildName and layoutData and layoutData[buildName]
		local row, col
		if position then
			col, row = position.col, position.row
		else
			row = (i > 6) and 2 or 1
			col = (i - 1)%6 + row
		end
		local x, y = (col - 1) * button_size, (row - 1) * button_size
		panel:AddChild(self:MakeButton(x, y, bDefID, bdef, facDefID, stunned))
	end
	panel:AddChild(self:MakeButton(0, button_size))
	self.win:AddChild(panel)
end

function FacUI:Move(index)
	local stack = self.stack
	index = math.min(index, #self.stack)
	table.insert(stack, index, table.remove(stack, self.index))
	self.index = index
	self.invite_x = invite_x - invite_size * (index - 1)
	for i = index + 1, #self.stack do
		local obj = self.stack[i]
		obj.index = i
		obj.invite_x = invite_x - invite_size * (i - 1)
	end
end

function FacUI:UpdateCombo(defID)
	local combo = FacUI.combo
	if not combo then
		combo = FacUI:New()
		if not combo then
			return
		end
		local combined = {}
		combo.combined = combined
		for i, obj in ipairs(self.stack) do
			local defID = obj.defID
			if defID then
				local coDefID = facOfPlate[defID] or plateOfFac[defID]
				if not (combined[defID] or coDefID and combined[coDefID]) then
					combined[defID] = true
				end
			end
		end
		FacUI.combo = combo
		combo:Move(1)
	elseif defID then
		local combined = combo.combined
		local coDefID = facOfPlate[defID] or plateOfFac[defID]
		if not (combined[defID] or coDefID and combined[coDefID]) then
			combined[defID] = true
		end
	end
	if combo.win then
		local wasDevelopped = combo.developped
		local x, y = combo.win.x, combo.win.y
		combo:CloseWin()
		combo:DevelopInvite()
		if not wasDevelopped then
			combo:HideWin()
		end
		combo.win:SetPos(x, y)
	end
end



function FacUI:EndInvite()
	if self.inviting then
		self.inviting = false
		FacUI.hasInvite =  FacUI.hasInvite - 1
		if FacUI.hasInvite == 0 then
			FacUI.time = false
		end
	end
end

function FacUI:Reinvite()
	if not self.inviting then
		self.inviting = true
		FacUI.hasInvite =  FacUI.hasInvite + 1
	end
end

function FacUI:CloseWin()
	if self.win then
		local wasDevelopped = self.developped
		self.win:Dispose()
		self.win = false
		if self.developped then
			FacUI.hasDevelopped = FacUI.hasDevelopped - 1
			self.developped = false
			self.color = ghostColorL
		end
		FacUI.hasWin = FacUI.hasWin - 1
		self:Reinvite()
	end
end

function FacUI:HideWin()
	if self.developped then
		self.win:Hide()
		FacUI.hasDevelopped = FacUI.hasDevelopped - 1
		self.developped = false
		self.color = ghostColorL
		self:Reinvite()
		return true
	end
end

function FacUI:HideAllWins()
	if FacUI.hasDevelopped > 0 then
		for i, obj in ipairs(self.stack) do
			if obj.developped then
				obj.win:Hide()
				obj.developped = false
				obj.color = ghostColorL
				obj:Reinvite()
			end
		end
		FacUI.hasDevelopped = 0
		return true
	end
end

function FacUI:CloseAllWins()
	if FacUI.hasWin > 0 then 
		for i, obj in ipairs(self.stack) do
			if obj.win then
				obj.win:Dispose()
				obj.win = false
				obj.developped = false
				obj.color = ghostColorL
				obj:Reinvite()
			end
		end
		FacUI.hasWin = 0
		FacUI.hasDevelopped = 0
		return true
	end
end

function FacUI:Delete()
	self:CloseWin()
	self:EndInvite()
	table.remove(self.stack, self.index)
	if self.defID then
		FacUI.map[self.keyID] = nil
	end
	for i = self.index, #self.stack do
		local obj = self.stack[i]
		obj.index = i
		obj.invite_x = obj.invite_x + invite_size
	end
	if self.combined then
		FacUI.combo = false
	else
		local combo = FacUI.combo
		if combo then
			local win = combo.win
			local wasDevelopped = combo.developped
			local x, y = win and win.x, win and win.y
			combo:Delete()
			if FacUI.stack[2] then
				FacUI:UpdateCombo()
				if win then
					combo = FacUI.combo
					combo:DevelopInvite()
					combo.win:SetPos(x, y)
					if not wasDevelopped then
						combo:HideWin()
					end
				end
			elseif wasDevelopped and auto_develop then
				local obj = FacUI.stack[1]
				if obj and not obj.developped then
					obj:DevelopInvite()
					obj.win:SetPos(x, y)
				end
			end
		end
	end
end
function FacUI:Shutdown()
	if not FacUI.active then
		return
	end
	for i, obj in pairs(self.stack) do
		obj:CloseWin()
		obj:EndInvite()
		self.stack[i] = nil
	end
	FacUI.hasInvite = 0
	FacUI.hasWin = 0
	FacUI.hasDevelopped = 0
	FacUI.hasOrder = 0
	FacUI.active = false
	FacUI.time = false
	FacUI.combo = false
	FacUI.map = {}

end

function FacUI:DrawInvites(tweakMode)
	if not tweakMode and spIsGUIHidden() then
		return
	end
	if not FacUI.time then
		FacUI.time = os.clock() + 1
	end
	if tweakMode then
		if fac_preorder_tweak_win.dragging then -- no OnDragging callin so we check it here
			invite_x, invite_y = fac_preorder_tweak_win.x, fac_preorder_tweak_win.y
			ui_relative_x, ui_relative_y = invite_x / vsx, invite_y / vsy
			for i, obj in ipairs(self.stack) do
				obj.invite_x = invite_x - invite_size * (obj.index - 1)
				obj.invite_y = invite_y
			end
		end
		FacUI:DrawInvite(invite_x, invite_y, ui_icon)
	else
		for i, obj in ipairs(self.stack) do
			if obj.inviting then
				obj:DrawInvite()
			end
		end
	end
end

function FacUI:ClickInvite(x, y)
	for i, obj in ipairs(self.stack) do
		if obj.inviting then
			if ghost_clickable and obj.defID and not obj.unitID then
				local pos = GetMouseWorldPos(x, y)
				if pos then
					local px, pz = pos[1], pos[3]
					local x, z = obj.pos[1], obj.pos[3]
					local sx, sz = obj.sx, obj.sz
					if (obj.pos[4] or 0)%2 == 1 then
						sx, sz = sz, sx
					end
					if px < (x + sx) and px > (x - sx)
					and pz < (z + sz) and pz > (z - sz)
					then
						obj:DevelopInvite()
						return true
					end
				end
			end
			local y = vsy - y
			if  x > obj.invite_x and x < obj.invite_x + invite_size
			and y > obj.invite_y and y < obj.invite_y + invite_size
			then
				obj:DevelopInvite()
				return true
			end
		end
	end
end

function FacUI:DrawInvite(x, y, icon)
	x, y, icon = x or self.invite_x, y or self.invite_y, icon or self.icon
	gl.DepthTest(true)
	gl.DepthTest(GL.LEQUAL)
	glPushMatrix()
	local scale = WG.uiScale or 1
	glScale(scale, scale, 1)
	glTranslate(x, vsy/scale - (y + invite_size), 0)
	local t = (FacUI.time -  os.clock())%2 - 1.2
	glColor(1, 1, 1, 0.35 + (t < 0 and - t or t))
	glTexture(icon)
	glTexRect(0, 0, invite_size, invite_size)
	glTexture(false)
	glPopMatrix()
	glColor(1, 1, 1, 1)
	gl.DepthTest(false)
	gl.DepthTest(GL.LEQUAL)
end

function FacUI:DevelopInvite(x, y)
	self:EndInvite()
	if self.developped then
		return
	end
	if not self.win then
		FacUI.hasWin = FacUI.hasWin + 1
		if self.combined then
			for defID in pairs(self.combined) do
				self:GenerateBuildPanel(defID, x, y)
			end
		else
			self:GenerateBuildPanel(self.defID, x, y)
		end
		self.win:UpdateLayout()
	else
		self.win:Show()
	end
	self.developped = true
	self.color = ghostColor
	FacUI.hasDevelopped = FacUI.hasDevelopped + 1
end

function FacUI:Detach(unitID)
	if self.attached then
		local freedUnit = false
		self.attached[unitID] = nil
		trackedUnits[unitID][self] = nil
		if not next(trackedUnits[unitID]) then
			trackedUnits[unitID] = nil
			checkUnits[unitID] = nil
			freedUnit = true
		end
		self.hasAttached = self.hasAttached - 1
		return freedUnit
	end
end

function FacUI:DetachAll()
	local attached = self.attached
	if attached then
		for unitID in pairs(attached) do
			attached[unitID] = nil
			trackedUnits[unitID][self] = nil
			if not next(trackedUnits[unitID]) then
				trackedUnits[unitID] = nil
				checkUnits[unitID] = nil
			end
		end
		self.hasAttached = 0
	end
end

function FacUI:SetObjUnitID(unitID, defID, x, z, facing)
	local obj = self.map[defID..'-'..x..'-'..z..'-'..facing]
	if obj then
		obj.unitID = unitID
		obj.timeout = TIME_OUT_ORDER
		obj.ttl = TIME_OUT_ORDER + spawned_ttl
		obj:DetachAll()
		FacUI.hasTTL = FacUI.hasTTL + 1
	end
end

function FacUI:GetAllDevUnderSea()
	if self.hasDevelopped > 0 then
		if self.hasDevelopped == 1 and self.combo and self.combo.developped then
			for i, obj in ipairs(self.stack) do
				if not obj.combined then
					 if not GetUnderSea(obj.defID) then
					 	return false
					 end
				end
			end
		else
			for i, obj in ipairs(self.stack) do
				if not obj.combined and obj.developped then
					 if not GetUnderSea(obj.defID) then
					 	return false
					 end
				end
			end
		end
		return true
	end
end

------------------------------------------------------------------
------------------------------------------------------------------

-- CallIns

function MorphFinished(oldID, newID)
	local tracked = trackedUnits[oldID]
	if tracked then
		trackedUnits[newID] = tracked
		trackedUnits[oldID] = nil
		for obj in pairs(tracked) do
			obj.attached[oldID] = nil
			obj.attached[newID] = true
		end
		if checkUnits[oldID] then
			checkUnits[newID] = checkUnits[oldID]
			checkUnits[oldID] = nil
		else
			checkUnits[newID] = SLOW_UPDATE
		end
	end
end

function widget:GameFrame(f) -- note: unit_initial_queue.lua attach the tasker at frame 2 or 3, we check from 2 to 4 to cover any layer position of our widget
	if f < 2 then
		return
	elseif f > 4 then
		preGame = false
		for i, obj in ipairs(FacUI.stack) do
			if obj.hasAttached == 0 then
				obj:Delete()
			end
		end
		widgetHandler:RemoveWidgetCallIn('GameFrame', widget)
	else
		if FacUI.stack[1] and WG.preGameBuildQueue and WG.preGameBuildQueue.tasker then 
			local tasker = WG.preGameBuildQueue.tasker
			local done = false
			for i, obj in ipairs(FacUI.stack) do
				if obj.defID then
					if obj.hasAttached == 0 then
						local tracked = trackedUnits[tasker]
						if not tracked then
							tracked = {}
							trackedUnits[tasker] = tracked
						end
						tracked[obj] = -obj.defID
						obj.attached = { [tasker] = true }
						obj.hasAttached = obj.hasAttached + 1
						done = true
					end
				end
			end
			if done then
				preGame = false
				widgetHandler:RemoveWidgetCallIn('GameFrame', widget)
			end
		end
	end
end


function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	if trackedUnits[unitID] then
		checkUnits[unitID] = track_update
	end
end

function widget:IsAbove(x, y)
	local highlighted = FacUI.highlight
	local cur_highlight = false
	if FacUI.stack[1] and not Screen0.hoveredControl then
		local _, trace = Spring.TraceScreenRay(x, y, true, true)
		if trace then
			local wx, _, wz = unpack(trace)
			for i, obj in ipairs(FacUI.stack) do
				if obj.defID and not obj.developped then
					local x, _, z, facing = unpack(obj.pos)
					local def = factoryDefs[obj.defID]
					local sx, sz = obj.sx, obj.sz
					if wx > x-sx and wx < x + sx and
						wz > z-sz and wz < z + sz then
						cur_highlight = obj
						break
					end
				end
			end
		end
	end
	if cur_highlight ~= highlighted then
		if highlighted and not highlighted.developped then
			highlighted.color = ghostColorL
		end
		if cur_highlight then
			cur_highlight.color = ghostColor
		end
		FacUI.highlight = cur_highlight
	end
end

function widget:Update(dt)
	if showTempOrders then
		showTempOrders = showTempOrders - Spring.GetLastUpdateSeconds()
		if showTempOrders < 0 then
			showTempOrders = false
		end
	end
	if not WG.panning then
		if fake_command then
			Spring.SetMouseCursor(fake_command)
		elseif allow_rightclick and FacUI.hasDevelopped > 0 then
			if not Screen0.hoveredControl then
				local _, cmdID, _, cmdName = spGetActiveCommand()
				if not cmdID or cmdID >= 0 then
					Spring.SetMouseCursor("GatherWait")
				end
			end
		end
	end

	if preGame and WG.preGameBuildQueue then
		preGameCheck = preGameCheck - dt
		if preGameCheck <= 0 then
			preGameCheck = PREGAME_UPDATE
			local current = {}
			for i, order in ipairs(WG.preGameBuildQueue) do
				if factoryDefs[order[1]] then
					FacUI:New(order[1], {unpack(order, 2)})
					current[order[1]..'-'..order[2]..'-'..order[4]..'-'..order[5]] = true
				end
			end
			for keyID, obj in pairs(FacUI.map) do
				if not current[keyID] then
					obj:Delete()
				end
			end
		end
		return
	end
	-- update unit attachment to build order
	for unitID, to in pairs(checkUnits) do
		to = to - dt
		if to <= 0 then
			to = SLOW_UPDATE
			local okayed = {}
			-- check if the unit got still the orders
			for i, order in ipairs(spGetCommandQueue(unitID, -1)) do
				if order.id < 0 and factoryDefs[-order.id] then
					for obj, cmdID in pairs(trackedUnits[unitID]) do
						if cmdID == order.id then
							local params = order.params
							local x, z, facing = obj.pos[1], obj.pos[3], obj.pos[4] or 0
							if x == params[1] and z == params[3] and facing == (params[4] or 0) then
								okayed[obj] = true
							end
						end
					end
				end
			end
			for obj, cmdID in pairs(trackedUnits[unitID]) do
				if not okayed[obj] then
					if obj:Detach(unitID) then
						to = nil -- stop checking the unit, it has no attachment
					end
					if obj.hasAttached == 0 then
						obj:Delete()
					end
				end
			end
		end
		checkUnits[unitID] = to
	end
	if FacUI.hasOrder > 0 then
		for i, obj in ipairs(FacUI.stack) do
			if obj.timeout then
				obj.timeout = obj.timeout - dt
				if obj.timeout <= 0 then
					obj.timeout = false
					for i, orders in ipairs({obj.preMoveOrders, obj.preOrders}) do
						local order = table.remove(orders, 1)
						while order do
							obj:ExecuteOrder(unpack(order))
							FacUI.hasOrder = FacUI.hasOrder - 1
							order = table.remove(orders, 1)
						end
					end
				end
			end
		end
	end
	if FacUI.hasTTL > 0 then
		for i, obj in ipairs(FacUI.stack) do
			if obj.ttl then
				obj.ttl = obj.ttl - dt
				if obj.ttl <= 0  and not (obj.developped) then
					obj:Delete()
					FacUI.hasTTL = FacUI.hasTTL - 1
				end
			end
		end
	end
end

local selChanged = false
function widget:SelectionChanged()
	selChanged = true
end

function widget:CommandsChanged()
	-- if not selChanged then
	-- 	return
	-- end
	selChanged = false
	if fake_command then
		Spring.SetMouseCursor('none')
		fake_command = false
	end
	selDefID = WG.selectionDefID or spGetSelectedUnitsSorted()	
	local _, units = next(selDefID)
	local teamID = units and Spring.GetUnitTeam(units[1])
	myUnitsSelected = teamID == myTeamID
end

function widget:CommandNotify(cmdID, params, options)
	if not myUnitsSelected then
		return
	end
	if cmdID < 0 and params[3] then
		if factoryDefs[-cmdID] then
			local obj = FacUI:New(-cmdID, params)
			if not obj then
				return
			end
			local attached = {}
			obj.attached = attached
			for defID, units in pairs(selDefID) do
				if CheckPotent(defID, cmdID, units[1]) then
					for i, unitID in ipairs(units) do
						local tracked = trackedUnits[unitID]
						if not tracked then
							tracked = {}
							trackedUnits[unitID] = tracked
						end
						tracked[obj] = cmdID
						attached[unitID] = true
						obj.hasAttached = obj.hasAttached + 1
					end
				end
			end
		end
	end
end

function widget:UnitCreated(unitID, defID, teamID)
	if teamID == myTeamID then
		if factoryDefs[defID] then
			local x, _, z = spGetUnitPosition(unitID)
			if x then
				FacUI:SetObjUnitID(unitID, defID, x, z, spGetUnitBuildFacing(unitID) or 0)
			end
		end
	end
end

function widget:UnitDestroyed(unitID, defID, teamID)
	if teamID == myTeamID then
		local tracked = trackedUnits[unitID]
		if tracked then
			for obj, cmdID in pairs(tracked) do
				obj:Detach(unitID)
				if obj.hasAttached == 0 then
					obj:Delete()
				end
			end
			trackedUnits[unitID] = nil
			checkUnits[unitID] = nil
		end
	end
end



function widget:KeyPress(key, mods, isRepeat, ...)
	-- HotkeyIsBound(keyset)
	if spIsUserWriting() or isRepeat then
		return
	end
	if key == ESC_KEY then
		if fake_command then
			fake_command = false
			Spring.SetMouseCursor('none')
			return true
		elseif FacUI.hasDevelopped then
			for i, obj in ipairs(FacUI.stack) do
				if obj.developped then
					obj:HideWin()
				end
			end
			return true
		end
	elseif allow_commands and FacUI.hasDevelopped > 0 and (key == FIGHT_KEY or key == PATROL_KEY or key == MOVE_KEY) then
		if IntegralMenu and IntegralMenu:KeyPress(key, mods, isRepeat, ...) then
			return true
		end
		fake_command = key == FIGHT_KEY and 'Fight' or key == PATROL_KEY and 'Patrol' or 'Move'
		return true
	end
end

function widget:KeyRelease(key, mods)
	if removeCommandOnShiftRelease then
		removeCommandOnShiftRelease = false
		if fake_command then
			fake_command = false
			Spring.SetMouseCursor('none')
		end
		spSetActiveCommand(nil)
	end
	if closeUponShiftRelease and not mods.shift then
		closeUponShiftRelease = false
		fake_command = false
		FacUI:HideAllWins()
	end
end

local movingCMDs = {
	Move = CMD_RAW_MOVE,
	Patrol = CMD.PATROL,
	Fight = CMD.FIGHT,
}

function widget:MousePress(x, y, button)
	if button == 1 and trail then
		trail = false
		widgetHandler.mouseOwner = nil
		return true
	end
	if fake_command and (button == 3 or button == 1 and not FacUI.hasDevelopped) then
		Spring.SetMouseCursor('none')
		fake_command = false
		return true
	end
	if FacUI.active then
		if WG.uiScale and WG.uiScale ~= 1 then
			x, y = x/WG.uiScale, y/WG.uiScale
		end
		if not Screen0:IsAbove(x,y) then
			if FacUI.hasInvite > 0 and button == 1 and FacUI:ClickInvite(x, y) then
				return true
			elseif FacUI.hasDevelopped > 0 then

				if button == 1 then
					local moveCmdID
					local _, cmdID, _, cmdName = spGetActiveCommand()
					if allow_commands then
						moveCmdID = movingCMDs[cmdName or fake_command]
						
					end
					if moveCmdID then
						local shift = select(4, spGetModKeyState())
						if not shift then
							if fake_command then
								Spring.SetMouseCursor('none')
								fake_command = false
							end
							spSetActiveCommand(nil)
						else
							removeCommandOnShiftRelease = true
						end
						local pos = GetMouseWorldPos(x, y)
						if pos then
							if FacUI.hasDevelopped > 1 or FacUI.combo and FacUI.combo.developped then
								trail = {cmdID = moveCmdID, {x, y}}
							else
								FacUI:AddMoveOrder(moveCmdID, pos)
							end
						end
						return true
					elseif FacUI:HideAllWins() then
						return true
					elseif not cmdID then
						return true -- avoid deselecting
					end
					return
				elseif button == 3 and allow_rightclick then
					local _, cmdID, _, cmdName = spGetActiveCommand()
					if cmdID then
						return
					end
					local pos = GetMouseWorldPos(x, y)
					if pos then
						if FacUI.hasDevelopped > 1 or FacUI.combo and FacUI.combo.developped then
							trail = {cmdID = CMD_RAW_MOVE, {x, y}}
						else
							FacUI:AddMoveOrder(CMD_RAW_MOVE, pos)
						end
					end
					return true
				end
			end
		end
	end
end


function widget:DefaultCommand(targetType, targetID, engineCmd)
	if allow_rightclick and FacUI.hasDevelopped > 0 then
		return CMD_RAW_MOVE
	end
end

function widget:MouseMove(x, y, button)
	if trail then
		trail[#trail + 1] = {x, y}
	end
end

function widget:MouseRelease(x, y)
	if trail then
		if FacUI.hasDevelopped > 1 or FacUI.combo and FacUI.combo.developped then
			trail[#trail + 1] = {x, y}
			local num = FacUI.combo and FacUI.combo.developped and #FacUI.stack - 1
				or FacUI.hasDevelopped - (FacUI.combo and 1 or 0)
			local count = 0
			local len = #trail
			
			local pos = GetMouseWorldPos(unpack(trail[1]))
			local ret = {pos}
			-- Echo('ret #1', 'trail #'..1, trail[1], pos, unpack(pos))
			local p = 1
			for i = 2, num - 1 do
				p = p + math.modf(len / (num - 1))
				pos = GetMouseWorldPos(unpack(trail[p]))
				-- Echo('ret #'..#ret + 1, 'trail '..p, trail[p], pos, unpack(pos))
				ret[#ret + 1] = pos

			end
			pos = GetMouseWorldPos(unpack(trail[#trail]))
			-- Echo('ret #'..#ret +1, 'trail #'..#trail, trail[#trail], pos, unpack(pos))
			ret[#ret +1] = pos
			FacUI:AddMoveOrder(trail.cmdID, ret, true)
		end
		trail = false
	end
end

local function DrawGhost(defID)
	if ghost_appearance == 1 then -- exactly as normal
		gl.UnitShape(defID, myTeamID, false, true, false) -- f
	elseif ghost_appearance == 2 then -- very solid, and slightly tinted
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
		gl.UnitShape(defID, myTeamID, false, true, false) -- f
	elseif ghost_appearance == 3 then -- solid and quite glowy
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
		gl.UnitShape(defID, myTeamID, false, true, false) -- f
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
	elseif ghost_appearance == 4 then -- quite glowy almost no solidity
		gl.UnitShape(defID, myTeamID, false, true, false) -- f
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
	elseif ghost_appearance == 5 then -- super glowy but solid
		gl.UnitShape(defID, myTeamID, false, true, false) -- f
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
	elseif ghost_appearance == 6 then -- glowy no solidity
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
	elseif ghost_appearance == 7 then -- super glowy no solidity
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
		gl.UnitShape(defID, myTeamID, true, true, false) -- g
	end
	-- note:
	-- gl.UnitShape(defID, myTeamID, false, false, false) -- doesnt appear
	-- gl.UnitShape(defID, myTeamID, false, false, true) -- doesnt appear
	-- gl.UnitShape(defID, myTeamID, false, true, true) -- glitchy
	-- gl.UnitShape(defID, myTeamID, false, true, false) -- forced normal appearance
	-- gl.UnitShape(defID, myTeamID, true, false, false) -- glowy
	-- gl.UnitShape(defID, myTeamID, true, false, true) -- glowy
	-- gl.UnitShape(defID, myTeamID, true, true, false) -- glowy
	-- gl.UnitShape(defID, myTeamID, true, true, true) -- glowy
end

local function DrawPath(obj, path, alpha)
	local pos1 = obj.pos
	local cmdID, pos2
	for i = 0, #path - 1 do
		cmdID, pos2 = unpack(path[i + 1])
		if alpha then
			local r, g, b = unpack(colors[cmdID])
			glColor(r, g, b, alpha)
		else
			glColor(colors[cmdID])
		end
		glBeginEnd(GL_LINES, Drawline, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3])
		pos1 = pos2
	end
end

function widget:DrawWorld()
	-- show dummy ghost for option setting
	if showGhost then 
		showGhost.timeout = showGhost.timeout - Spring.GetLastUpdateSeconds()
		if showGhost.timeout < 0 then
			showGhost = false
		else
			local defID = showGhost.defID
			local x, y, z = showGhost.x, showGhost.y, showGhost.z
			glPushMatrix()

			-- gl.Rotate(os.clock()%360 * 50, 0, 90, 90)
			glColor(ghostColor)
			glDepthTest(true)
			glTranslate(x, y, z)
			gl.Rotate(os.clock()%360*50,0,1,0)
			gl.Blending(GL.SRC_ALPHA, GL.ONE) -- glowy blending
			DrawGhost(defID)
			gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
			glDepthTest(false)
			glPopMatrix()
			glColor(1,1,1,1)
		end
	end



	------ draw orders
	glPushAttrib(GL.LINE_BITS)
	glLineStipple("springdefault")
	glDepthTest(false)
	glLineWidth(1)
	local comboDevelopped = FacUI.combo and FacUI.combo.developped
	local shift = select(4, spGetModKeyState())
	local alpha = showTempOrders 
	local toUpdate = {}
	for i, obj in ipairs(FacUI.stack) do
		local path = {}
		if obj.unitID then
			if showTempOrders or shift or comboDevelopped or obj.developped then
				path = {}
				for i, order in ipairs(spGetCommandQueue(obj.unitID, -1) or {}) do
					if (order.id == CMD.FIGHT or order.id == CMD_RAW_MOVE or order.id == CMD.PATROL) and order.params[3] then
						path[#path + 1] = {order.id, order.params}
					end
				end
				DrawPath(obj, path, showTempOrders)
			end
		elseif obj.preMoveOrders  and obj.preMoveOrders[1] then
			if showTempOrders or shift or comboDevelopped or obj.developped then
				DrawPath(obj, obj.preMoveOrders, showTempOrders)
			end
		end
	end
	glColor(1, 1, 1, 1)
	glLineStipple(false)
	glPopAttrib()

	------ draw ghosts
	if FacUI.stack[1] and not preGame then
		local comboDevelopped = FacUI.combo and FacUI.combo.developped
		glDepthTest(true)
		
		gl.Blending(GL.SRC_ALPHA, GL.ONE) -- glowy blending
		for i, obj in ipairs(FacUI.stack) do
			glColor(obj.color)
			
			if not obj.unitID and obj.defID then
				local defID, x, y, z, facing = obj.defID, unpack(obj.pos)
				if Spring.IsSphereInView(x, y, z) then
					glPushMatrix()
					glTranslate(x, y, z)
					gl.Rotate((facing or 0) * 90, 0, 1, 0)
					-- it's a bit circumvoluted but I didnt find an easier way to suppress the engine build ghost to replace it with wine
					-- First we mark the stencil with the build shape while respecting the depth
					gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
					gl.StencilTest(true)
					gl.StencilOp(GL.KEEP, GL.KEEP, GL.INCR)
					gl.StencilFunc(GL.EQUAL, 0, 1)
					gl.ColorMask(false, false, false, true)
					gl.UnitShape(defID, myTeamID, true, true, true)

					-- then we temporary stop the stencil test to make a box just a little larger than the model to avoid z fighting
					-- that box will become 'solid' through gl.DepthMask, that way the engine build will not be drawn because greater than the new depth we create*
					-- instead of box making a larger model to envelop it
					gl.StencilTest(false)
					gl.DepthMask(true)
					-- local model = UnitDefs[defID].model
					-- gl.Utilities.DrawMyBox(model.minx - 1 , model.miny - 1  , model.minz - 1 , model.maxx + 1 , model.maxy + 1 , model.maxz + 1 )
					gl.PolygonOffset(-1, -1)
					gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
    				gl.UnitShape(defID, 0, true, true, true)
					gl.PolygonOffset(false)
					gl.DepthMask(false)

					-- finally we take back our stencil test to draw our ghost, the ghost won't respect the depth so it will be drawn despite our solid box
					-- but it will have to respect our stencil, which is respecting the original ground depth, so our ghost will not appear through the terrain
					gl.StencilTest(true)
					gl.DepthTest(GL.ALWAYS)
					gl.StencilOp(GL.KEEP, GL.KEEP, GL.KEEP)
					gl.ColorMask(true, true, true, true)
					gl.StencilFunc(GL.EQUAL, 1, 1)
					
					-- ghost
					DrawGhost(defID)
					-- done
					glPopMatrix()
					gl.StencilTest(false)
					gl.DepthTest(GL.LEQUAL)
				end
			end
		end
		gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA) -- 
		gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
		glDepthTest(false)
		glColor(1, 1, 1, 1)
	end
end

local function Draw()
	if tweakMode and not widgetHandler.tweakMode then
		tweakMode = false
		fac_preorder_tweak_win:Hide()
	end
	FacUI:DrawInvites(tweakMode)
end

function widget:DrawScreen()
	if WG.DrawBeforeChili then
		WG.DrawBeforeChili(Draw)
		return
	end
	Draw()
end

function widget:TweakDrawScreen()
	if not tweakMode then -- no callin to get informed we're entering Tweak mode
		tweakMode = true
		fac_preorder_tweak_win:Show()
		FacUI.time = os.clock() + 1
	end
end

-- saving position
function widget:GetConfigData()
	return {ui_relative_x = ui_relative_x, ui_relative_y = ui_relative_y, invite_size = invite_size}
end
function widget:SetConfigData(data)
	if data.ui_relative_x then
		ui_relative_x, ui_relative_y = data.ui_relative_x, data.ui_relative_y
		invite_x, invite_y = vsx * ui_relative_x, vsy * ui_relative_y
		invite_size = data.invite_size
	end
end

function widget:ViewResize(x, y)
	screenWidth = x/WG.uiScale
	screenHeight = y/WG.uiScale
	vsx, vsy = x, y
	invite_x, invite_y = ui_relative_x * vsx, ui_relative_y * vsy
end

function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
	end
end

function WidgetInitNotify(w, name)
	if name == 'Chili Integral Menu' then
		IntegralMenu = w
	end
end

function WidgetRemoveNotify(w, name)
	if name == 'Chili Integral Menu' then
		IntegralMenu = nil
	end
end
function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
	end
end
function widget:Initialize()
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		widgetHandler:RemoveWidget(widget)
		return
	end
	myTeamID = Spring.GetMyTeamID()
	-- widgetHandler:RemoveWidgetCallIn('DrawScreen', widget)  -- we can't remove DrawScreen or TweakDrawScreen will not trigger
	widget:ViewResize(gl.GetViewSizes()) -- or Spring.Orig.GetViewSizes
	Chili = WG.Chili

	wh = widgetHandler
	MakeTweakWin()

	fac_preorder_tweak_win:Hide()
	preGame = Spring.GetGameFrame() < 3
	widgetHandler:RegisterGlobal(widget, 'MorphFinished', MorphFinished)
	GetUnderSea = WG.PlacementModule and (function(defID) return WG.PlacementModule:Measure(defID, 0).underSea end)
		or (function(defID) return defID ~= amphDefID end)
	FIGHT_KEY = Spring.GetKeyCode(WG.crude.GetHotkey("fight"):lower())
	PATROL_KEY = Spring.GetKeyCode(WG.crude.GetHotkey("patrol"):lower())
	MOVE_KEY = Spring.GetKeyCode(WG.crude.GetHotkey("rawmove"):lower())
	Screen0 = WG.Chili.Screen0
	if WG.DrawBeforeChili then 
		WG.DrawBeforeChili(widget.DrawScreen)
	end
	widget:CommandsChanged()
	IntegralMenu = widgetHandler:FindWidget('Chili Integral Menu')
end

function widget:Shutdown()
	widgetHandler:DeregisterGlobal(widget, 'MorphFinished', MorphFinished)
end

if f then
	f.DebugWidget(widget)
end




------------------
-- Hungarian methods
-- copied from Custom Formation 2 and modified a bit
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
	-- (the following code is written by gunblob)
	--   this code finds the optimal solution (slow, but effective!)
	--   it uses the hungarian algorithm from http://www.public.iastate.edu/~ddoty/HungarianAlgorithm.html
	--   if this violates gpl license please let gunblob and me know
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
do
	local doPrime, stepPrimeZeroes, stepFiveStar
	local t
	local osclock = os.clock
	local huge = math.huge
	local function FindHungarian(array, n)
		
		t = osclock()
		-- Vars
		local colcover = {}
		local rowcover = {}
		local starscol = {}
		local primescol = {}
		
		-- Initialization
		for i = 1, n do
			rowcover[i] = false
			colcover[i] = false
			starscol[i] = false
			primescol[i] = false
		end
		
		-- Subtract minimum from rows
		for i = 1, n do
			
			local aRow = array[i]
			local minVal = aRow[1]
			for j = 2, n do
				if aRow[j] < minVal then
					minVal = aRow[j]
				end
			end
			
			for j = 1, n do
				aRow[j] = aRow[j] - minVal
			end
		end
		
		-- Subtract minimum from columns
		for j = 1, n do
			
			local minVal = array[1][j]
			for i = 2, n do
				if array[i][j] < minVal then
					minVal = array[i][j]
				end
			end
			
			for i = 1, n do
				array[i][j] = array[i][j] - minVal
			end
		end
		
		-- Star zeroes
		for i = 1, n do
			local aRow = array[i]
			for j = 1, n do
				if (aRow[j] == 0) and not colcover[j] then
					colcover[j] = true
					starscol[i] = j
					break
				end
			end
		end
		
		-- Start solving system
		while true do
			
			-- Are we done ?
			local done = true
			for i = 1, n do
				if not colcover[i] then
					done = false
					break
				end
			end
			
			if done then
				return starscol
			elseif osclock()-t>0.8 then
				Echo('PROBLEM 1 HUNGARIAN IN LOOP OR TOO LONG')
				return
			end
			
			-- Not done
			local r, c = stepPrimeZeroes(array, colcover, rowcover, n, starscol, primescol)
			stepFiveStar(colcover, rowcover, r, c, n, starscol, primescol)
		end
	end
	doPrime = function(array, colcover, rowcover, n, starscol, r, c, rmax, primescol)
		
		primescol[r] = c
		
		local starCol = starscol[r]
		if starCol then
			
			rowcover[r] = true
			colcover[starCol] = false
			
			for i = 1, rmax do
				if not rowcover[i] and (array[i][starCol] == 0) then
					local rr, cc = doPrime(array, colcover, rowcover, n, starscol, i, starCol, rmax, primescol)
					if rr then
						return rr, cc
					end
				end
			end
			
			return
		else
			return r, c
		end
	end
	stepPrimeZeroes = function(array, colcover, rowcover, n, starscol, primescol)
		
		-- Infinite loop
		while true do
			
			-- Find uncovered zeros and prime them
			for i = 1, n do
				if not rowcover[i] then
					local aRow = array[i]
					for j = 1, n do
						if (aRow[j] == 0) and not colcover[j] then
							local i, j = doPrime(array, colcover, rowcover, n, starscol, i, j, i-1, primescol)
							if i then
								return i, j
							end
							break -- this row is covered
						end
					end
				end
			end
			
			-- Find minimum uncovered
			local minVal = huge
			for i = 1, n do
				if not rowcover[i] then
					local aRow = array[i]
					for j = 1, n do
						if (aRow[j] < minVal) and not colcover[j] then
							minVal = aRow[j]
						end
					end
				end
			end
			
			-- There is the potential for minVal to be 0, very very rarely though. (Checking for it costs more than the +/- 0's)
			
			-- Covered rows = +
			-- Uncovered cols = -
			for i = 1, n do
				local aRow = array[i]
				if rowcover[i] then
					for j = 1, n do
						if colcover[j] then
							aRow[j] = aRow[j] + minVal
						end
					end
				else
					for j = 1, n do
						if not colcover[j] then
							aRow[j] = aRow[j] - minVal
						end
					end
				end
			end
		end
	end
	stepFiveStar = function(colcover, rowcover, row, col, n, starscol, primescol)
		
		-- Star the initial prime
		primescol[row] = false
		starscol[row] = col
		local ignoreRow = row -- Ignore the star on this row when looking for next
		
		repeat
			if osclock()-t>0.8 then
				Echo('PROBLEM 2 HUNGARIAN IN LOOP OR TOO LONG')
				break
			end
			local noFind = true

			for i = 1, n do
				
				if (starscol[i] == col) and (i ~= ignoreRow) then
					
					noFind = false
					
					-- Unstar the star
					-- Turn the prime on the same row into a star (And ignore this row (aka star) when searching for next star)
					
					local pcol = primescol[i]
					primescol[i] = false
					starscol[i] = pcol
					ignoreRow = i
					col = pcol
					
					break
				end
			end
		until noFind
		
		for i = 1, n do
			rowcover[i] = false
			colcover[i] = false
			primescol[i] = false
		end
		
		for i = 1, n do
			local scol = starscol[i]
			if scol then
				colcover[scol] = true
			end
		end
	end
	ReorderHungarian = function(objects, poses)
		-- collect distances, allow for asymmetric tables
		local dist_table = {}
		local len1, len2 = #objects, #poses
		local maxLen = len1 >= len2 and len1 or len2
		for i = 1, maxLen do
			local p1 = objects[i].pos
			local x, z = p1[1], p1[3]
			local dist_col = {}
			dist_table[i] = dist_col
			for j = 1, maxLen do 
				local dist
				if not x then
					dist = huge
				else
					local p2 = poses[j]
					if not p2 then
						dist = huge
					else
						dist = math.round((x-p2[1])^2 + (z-p2[3])^2)
					end
					-- Echo('dist '..i..' - '..j..' = '..dist)
				end
				dist_col[j] = dist
			end
		end

		local ret = FindHungarian(dist_table, maxLen)
		local tries = 0
		for here, where in ipairs(ret) do
			if here ~= where then
				local toPlace = objects[where]
				objects[where] = objects[here]
				where, ret[where] = ret[where], where
				while where ~= ret[where] do
					tries = tries + 1
					if tries > maxLen then
						Echo('PROBLEM INF LOOP')
						break
					end
					objects[where], toPlace = toPlace, objects[where]
					where, ret[where] = ret[where], where
				end
			end
		end
	end
end
-- picked from cmd_customformation2.lua and adapted
local maxNoXTime = 0.2
function ReorderNoX(objects, nodes)
	local len = #objects
	-- Remember when we start
	-- This is for capping total time
	-- Note: We at least complete initial assignment
	local osclock = os.clock
	local startTime = osclock()

	---------------------------------------------------------------------------------------------------------
	-- Find initial assignments
	---------------------------------------------------------------------------------------------------------
	local set = {}
	local fdist = -1
	local fm

	for i = 1, len do
		local obj = objects[i]
		local ux, _, uz = unpack(obj.pos)

		set[i] = {ux, obj, uz, -1} -- Such that x/z are in same place as in nodes (So we can use same sort function)

		-- Work on finding furthest points (As we have ux/uz already)
		for j = i - 1, 1, -1 do

			local up = set[i]
			local vx, vz = up[1], up[3]
			local dx, dz = vx - ux, vz - uz
			local dist = dx*dx + dz*dz

			if (dist > fdist) then
				fdist = dist
				fm = (vz - uz) / (vx - ux)
			end
		end
	end

	-- Maybe nodes are further apart than the objects
	for i = 1, len - 1 do

		local np = nodes[i]
		local nx, nz = np[1], np[3]

		for j = i + 1, len do

			local mp = nodes[j]
			local mx, mz = mp[1], mp[3]
			local dx, dz = mx - nx, mz - nz
			local dist = dx*dx + dz*dz

			if (dist > fdist) then
				fdist = dist
				fm = (mz - nz) / (mx - nx)
			end
		end
	end

	local function sortFunc(a, b)
		-- y = mx + c
		-- c = y - mx
		-- c = y + x / m (For perp line)
		return (a[3] + a[1] / fm) < (b[3] + b[1] / fm)
	end

	table.sort(set, sortFunc)
	table.sort(nodes, sortFunc)

	for u = 1, len do
		set[u][4] = nodes[u]
	end

	---------------------------------------------------------------------------------------------------------
	-- Main part of algorithm
	---------------------------------------------------------------------------------------------------------

	-- M/C for each finished matching
	local Ms = {}
	local Cs = {}

	-- Stacks to hold finished and still-to-check objects
	local stFin = {}
	local stFinCnt = 0
	local stChk = {}
	local stChkCnt = 0

	-- Add all objects to check stack
	for u = 1, len do
		stChk[u] = u
	end
	stChkCnt = len

	-- Begin algorithm
	while ((stChkCnt > 0) and (osclock() - startTime < maxNoXTime)) do

		-- Get unit, extract position and matching node position
		local u = stChk[stChkCnt]
		local ud = set[u]
		local ux, uz = ud[1], ud[3]
		local mn = ud[4]
		local nx, nz = mn[1], mn[3]

		-- Calculate M/C
		local Mu = (nz - uz) / (nx - ux)
		local Cu = uz - Mu * ux

		-- Check for clashes against finished matches
		local clashes = false

		for i = 1, stFinCnt do

			-- Get opposing unit and matching node position
			local f = stFin[i]
			local fd = set[f]
			local tn = fd[4]

			-- Get collision point
			local ix = (Cs[f] - Cu) / (Mu - Ms[f])
			local iz = Mu * ix + Cu

			-- Check bounds
			if ((ux - ix) * (ix - nx) >= 0) and
				((uz - iz) * (iz - nz) >= 0) and
				((fd[1] - ix) * (ix - tn[1]) >= 0) and
				((fd[3] - iz) * (iz - tn[3]) >= 0) then

				-- Lines cross

				-- Swap matches, note this retains solution integrity
				ud[4] = tn
				fd[4] = mn

				-- Remove clashee from finished
				stFin[i] = stFin[stFinCnt]
				stFinCnt = stFinCnt - 1

				-- Add clashee to top of check stack
				stChkCnt = stChkCnt + 1
				stChk[stChkCnt] = f

				-- No need to check further
				clashes = true
				break
			end
		end

		if not clashes then

			-- Add checked unit to finished
			stFinCnt = stFinCnt + 1
			stFin[stFinCnt] = u

			-- Remove from to-check stack (Easily done, we know it was one on top)
			stChkCnt = stChkCnt - 1

			-- We can set the M/C now
			Ms[u] = Mu
			Cs[u] = Cu
		end
	end

	for i = 1, len do
		local s = set[i]
		objects[i], nodes[i] = s[2], s[4]
	end
end