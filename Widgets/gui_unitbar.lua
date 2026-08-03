function widget:GetInfo()
	return {
		name	  = "UnitBar",
		desc	  = "Shows currently owned units",
		author	= "PetTurtle",
		date	  = "2020",
		layer	 = 0,
		enabled   = true,
	}
end
VFS.Include("LuaRules/Configs/customcmds.h.lua")
if not string.find((Game.modName or ''):lower(), 'arena mod') then
	return false
end
if Game.modName ~= 'Arena Mod v1.0.10' then
	Echo('Wrong arena mod version, loading original gui_unitbar.lua')
	VFS.Include('LuaUI/Widgets/gui_unitbar.lua', nil, VFS.ZIP)
	return
end

local TIER_COLORS = {
	{0.1, 0.1, 0.1, 0.9},
	{0.1, 0.9, 0.1, 0.9},
	{0.1, 0.1, 0.9, 0.9},
	{0.9, 0.1, 0.9, 0.9},
	{1, 0.8, 0.1, 1}
}

local CMD_INSERT = CMD.INSERT
local CMD_OPT_SHIFT	= CMD.OPT_SHIFT

local CMD_HQ_SELL = 49737
local CMD_HQ_SPAWN = 49738

local CMD_OPT_ALT = CMD.OPT_ALT
local spGetModKeyState = Spring.GetModKeyState
local isVisible = true
local selectedHQID = nil

local Chili = nil
local window = nil

local mainPanel = nil
local buttons = {}
local buttonImages = {}
local buttonSell = {}
local buttonCostLabels = {}
local buttonCountLabels = {}

local function giveSellCommand(self, sellID)
	local defID = Spring.GetUnitRulesParam(selectedHQID, "HQSpawnUnit" .. sellID)
	if WG.ArenaShop.rerollForID[defID] then
		WG.ArenaShop.rerollForID[defID] = nil
	end
	Spring.GiveOrderToUnit(selectedHQID, CMD_INSERT, {0, CMD_HQ_SELL, CMD_OPT_SHIFT, sellID}, CMD_OPT_ALT)
end

local function giveSpawnCommand(self, spawnID)
	Spring.GiveOrderToUnit(selectedHQID, CMD_INSERT, {0, CMD_HQ_SPAWN, CMD_OPT_SHIFT, spawnID}, CMD_OPT_ALT)
end

local function updateUI()
	local rerollForID = WG.ArenaShop.rerollForID
	for i = 1, 8 do
		local ud = Spring.GetUnitRulesParam(selectedHQID, "HQSpawnUnit" .. i)

		if ud == -1 then
			buttonImages[i].file = "LuaUI/Images/Neon/glass.png"
			buttonImages[i]:Invalidate()
			buttons[i].backgroundColor = TIER_COLORS[1]
			buttons[i]:Invalidate()
			buttonCostLabels[i]:SetCaption("----")
			buttonCountLabels[i]:SetCaption("")
		else
			local spawnUnitCost = Spring.GetUnitRulesParam(selectedHQID, "HQSpawnUnitCost" .. i)
			local spawnUnitCount = Spring.GetUnitRulesParam(selectedHQID, "HQSpawnUnitCount" .. i)
			local spawnUnitTier = Spring.GetUnitRulesParam(selectedHQID, "HQSpawnUnitTier" .. i)
			buttonImages[i].file = "unitpics/" .. UnitDefs[ud].buildpicname
			buttonImages[i]:Invalidate()
			buttons[i].backgroundColor = TIER_COLORS[spawnUnitTier]
			buttons[i]:Invalidate()
			buttonCostLabels[i]:SetCaption(spawnUnitCost)
			buttonCountLabels[i]:SetCaption(spawnUnitCount .. (rerollForID[ud] and '~'..rerollForID[ud] or ''))
		end
	end
end

local function setVisible(value)
	if value and not isVisible then
		Chili.Screen0:AddChild(window)
		isVisible = true
	elseif not value and isVisible then
		Chili.Screen0:RemoveChild(window)
		isVisible = false
	end
end

function widget:CommandsChanged()
	local units = Spring.GetSelectedUnits()
	if units then
		for i = 1, #units do
			if Spring.GetUnitRulesParam(units[i], "isHQ") then
				selectedHQID = units[i]
				updateUI()
				setVisible(true)
				return
			end
		end
	end
	setVisible(false)
	selectedHQID = nil
end

local function CreateUnitButton(buttonID)
	local buttonPanel = Chili.StackPanel:New{
		width = 64,
		height = 110,
		itemPadding = {0,0,0,0},
		itemMargin = {0,0,0,0},
		padding = {0,0,0,0},
		margin = {0,0,0,0},
		orientation = "vertical",
		resizeItems = false,
		centerItems = false,
		parent = mainPanel,
	}
	
	buttonSell[#buttonSell+1] = Chili.Button:New {
		width= 60;
		height= 16;
		caption = "X",
		textColor = {0.9,0.1,0.1,1.0},
		OnClick = {
			function (self)
				giveSellCommand(self, buttonID)
			end
		},
		parent = buttonPanel
	}

	buttons[#buttons + 1] = Chili.Button:New {
		parent = buttonPanel,
		width = 60,
		height = 75,
		padding = {5,5,5,5},
		caption = "",
		OnClick = {
			function (self, mx, my, button)
				local alt, ctrl, meta, shift = spGetModKeyState()
				if alt then
					if WG.ArenaShop then
						local rerollForID = WG.ArenaShop.rerollForID
						local defID = Spring.GetUnitRulesParam(selectedHQID, "HQSpawnUnit" .. buttonID)
						if defID > 0 then
							if button == 1 then
								rerollForID[defID] = (rerollForID[defID] or 0) + 5 * (shift and 5 or 1) * (ctrl and 20 or 1)
							elseif button == 3 then
								rerollForID[defID] = nil
							end
							WG.ArenaShop.updateUI = true
						end
					end
				else
					for i=1, (shift and 5 or 1) *  (ctrl and 20 or 1) do
						giveSpawnCommand(self, buttonID)
					end
				end
			end
		},
	}

	buttonImages[#buttonImages + 1] = Chili.Image:New {
		width = 50,
		height = 50,
		file = "LuaUI/Images/Neon/glass.png",
		keepAspect = true,
		parent = buttons[#buttons],
	}

	buttonCostLabels[#buttonCostLabels+1] = Chili.Label:New {
		width = 50,
		height = 115,
		valign ="center",
		align = "center",
		caption = "----",
		textColor = {0.9,0.9,0.9,1.0},
		parent = buttons[#buttons]
	}

	buttonCountLabels[#buttonCountLabels+1] = Chili.Label:New {
		width= 45;
		height= 45;
		valign ="top",
		align = "left",
		caption = "",
		fontSize = 16;
		fontShadow = true;
		textColor = {0.2,0.8,0.2,0.9},
		parent = buttonImages[#buttonImages]
	}

	return buttons[#buttons]
end

function widget:UnitCmdDone(unitID)
	if isVisible and selectedHQID == unitID then
		updateUI()
	end
end

function widget:Initialize()
	Chili = WG.Chili
	if not Chili then
		widgetHandler:RemoveWidget()
		return
	end

	window = Chili.Window:New {
		dockable = true,
		name = "Units Spawn Bar",
		x = 0,
		y = Chili.Screen0.height - 325,
		width = (70 * 8),
		height = 105,
		padding = {2,2,2,2},
		classname = "main_window",
		draggable = true,
		resizable = false,
		tweakDraggable = true,
		tweakResizable = false,
		minimizanle = false,
		parent = Chili.Screen0,
	}

	mainPanel = Chili.StackPanel:New{
		x=10,
		y=0,
		right = 0,
		bottom = 0,
		itemPadding = {0,0,0,0},
		itemMargin = {0,0,0,0},
		margin = {0,0,0,0},
		orientation = "horizontal",
		parent = window,
	}
	
	for i = 1, 8 do
		CreateUnitButton(i)
	end
	widget:CommandsChanged()
end