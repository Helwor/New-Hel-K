-- $Id$

function widget:GetInfo()
	return {
		name      = "Building Starter",
		desc      = "v2 Hold Q to queue a building to be started and not continued.",
		author    = "Google Frog",
		date      = "Dec 13, 2008",
		license   = "GNU GPL, v2 or later",
		layer     = 5,
		enabled   = true  --  loaded by default?
	}
end
local Echo = Spring.Echo
local buildings = {}	-- {[1] = {x = posX, z = posZ, ud = unitID}}	-- unitID is only set when building is created
local toClear = {}	-- {[1] = {x = posX, z = posZ, unitID = unitID}}	-- entries created in UnitCreated, iterated in GameFrame
local numBuildings = 0
local myBuilders = {}
local alt_alone = false

local team = Spring.GetMyTeamID()
include("keysym.lua")
local _, ToKeysyms = include("Configs/integral_menu_special_keys.lua")

local CMD_REMOVE = CMD.REMOVE

local buildingStartKey = KEYSYMS.Q
local function HotkeyChangeNotification()
	local key = WG.crude.GetHotkeyRaw("epic_building_starter_hotkey")
	buildingStartKey = ToKeysyms(key and key[1])
end

options_order = {'hotkey', 'alt_insert'}
options_path = 'Hotkeys/Construction'
local helk_path = 'Hel-K/' .. widget:GetInfo().name
options = {}
options.hotkey = {
	name = 'Place Nanoframes',
	desc = 'Hold this key during structure placement to queue structures which are to placed but not constructed.',
	type = 'button',
	hotkey = "Q",
	bindWithAny = true,
	dontRegisterAction = true,
	OnHotkeyChange = HotkeyChangeNotification,
	path = hotkeyPath,
}

options.alt_insert = {
	name = 'Insert Nano frame with Alt alone',
	desc = 'Hold Alt only to insert nanoframe in front of queue',
	type = 'bool',
	value = alt_alone,
	OnChange = function(self)
		alt_alone = self.value
	end,
	path = helk_path,
}
-- Speedups
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spGetUnitPosition = Spring.GetUnitPosition
local spGetKeyState = Spring.GetKeyState
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted

local abs = math.abs


local builderDefs = {}
local mexDefID = UnitDefNames.staticmex.id
local caretakerDefID = UnitDefNames.staticcon.id
for udid, ud in pairs(UnitDefs) do
	for i, option in pairs(ud.buildOptions) do
		if option == mexDefID or option == caretakerDefID then
			builderDefs[udid] = true
		end
	end
	if ud.customParams.select_show_eco then
		builderDefs[udid] = (tonumber(ud.customParams.select_show_eco) ~= 0)
	end
end


function widget:Initialize()
	 if (Spring.GetSpectatingState() or Spring.IsReplay()) and (not Spring.IsCheatingEnabled()) then
		Spring.Echo("<Building Starter>: disabled for spectators")
		widgetHandler:RemoveWidget()
	end
	HotkeyChangeNotification()
	-- currentFrame = Spring.GetGameFrame()
	local spGetUnitDefID = Spring.GetUnitDefID
	for _, id in pairs(spGetTeamUnits(team) or {}) do
		if builderDefs[spGetUnitDefID(id) or -1] then
			myBuilders[id] = true
		end
	end
end
local buildingMap = {
	ids = {},
	Add = function(self,x,z)
		x, z = x - x%8, z - z%8
		if not self[x] then
			self[x] = {}
		end
		self[x][z] = true
	end,
	Remove = function(self,x,z)
		x, z = x - x%8, z - z%8
		if self[x] and self[x][z] then
			self[x][z] = nil
			if not next(self[x]) then
				self[x] = nil
			end
		end
	end,
	Identify = function(self, x, z, id)
		x, z = x - x%8, z - z%8
		if self[x] and self[x][z] then
			self.ids[id] = {x = x, z = z}
			return true
		end
		return false
	end,
	DeleteItem = function(self, id)
		local item = self.ids[id] 
		if item then
			self:Remove(item.x, item.z)
			self.ids[id] = nil
		end
	end,

}
function widget:CommandNotify(id, params, options)
	-- if (id < 0) then
	if id < 0 and params[1] then
		local ux = params[1]
		local uz = params[3]
		
		if buildingStartKey and spGetKeyState(buildingStartKey)
			or options.alt and not (options.meta or options.shift or options.ctrl) then
			buildingMap:Add(ux, uz)
			-- buildings[numBuildings] = { x = ux, z = uz}
			-- numBuildings = numBuildings+1
		else
			buildingMap:Remove(ux, uz)
			-- for j, i in pairs(buildings) do
			-- 	if (i.x) then
			-- 		if (i.x == ux) and (i.z == uz) then
			-- 			buildings[j] = nil
			-- 		end
			-- 	end
			-- end
		end
	end
end

local function CheckBuilding(ux,uz,ud)
	-- for index, i in pairs(buildings) do
	-- 	if (i.x) then
	-- 		if (abs(i.x - ux) < 16) and (abs(i.z - uz) < 16) then
	-- 			i.ud = ud
	-- 			return true
	-- 		end
	-- 	end
	-- end
	return false
end

function widget:GameFrame(f)
	-- if f % 2 ~= 1 then
	-- 	return
	-- end
	
	-- local newClear = {}
	-- for i=1,#toClear do
	-- 	local entry = toClear[i]
	-- 	-- minimum progress requirement is there because otherwise a con can start multiple nanoframes in one gameframe
	-- 	-- (probably as many as it can reach, in fact)
	-- 	local health, _, _, _, buildProgress = Spring.GetUnitHealth(entry.unitID)
	-- 	if health and health > 3 then
	-- 	--if buildProgress > 0.01 then
	-- 		local ux, uz = entry.x, entry.z
	-- 		local units = spGetTeamUnits(team)
	-- 		for _, unit_id in ipairs(units) do
	-- 			local cmdID, cmdOpt, cmdTag, cx, cy, cz = spGetUnitCurrentCommand(unit_id)
	-- 			if cmdID and cmdID < 0 then
	-- 				if (abs(cx-ux) < 16) and (abs(cz-uz) < 16) then
	-- 					spGiveOrderToUnit(unit_id, CMD_REMOVE, {cmdTag}, 0 )
	-- 				end
	-- 			end
	-- 		end
	-- 	else
	-- 		newClear[#newClear + 1] = entry
	-- 	end
	-- end
	-- toClear = newClear
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	if (unitTeam ~= team) then
		return
	end
	if not builderID then
		return
	end
	local ux, uy, uz  = spGetUnitPosition(unitID)
	
	-- local check = CheckBuilding(ux,uz,unitID)
	local check = buildingMap:Identify(ux, uz, unitID)
	if check then
		-- toClear[#toClear + 1] = {unitID = unitID, x = ux, z = uz}
		-- local units = spGetTeamUnits(team)
		local units = myBuilders
		for unit_id in pairs(myBuilders) do
			local cmdID, cmdOpt, cmdTag, cx, cy, cz = spGetUnitCurrentCommand(unit_id)
			if cmdID and cmdID < 0 then
				if (abs(cx-ux) < 16) and (abs(cz-uz) < 16) then
					spGiveOrderToUnit(unit_id, CMD_REMOVE, cmdTag, 0 )
				end
			end
		end
	end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	buildingMap:DeleteItem(unitID)
	-- for j, i in pairs(buildings) do
	-- 	if (i.ud) then
	-- 		buildings[j] = nil
	-- 	end
	-- end
	if builderDefs[unitDefID] then
		myBuilders[unitID] = true
	end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	-- for j, i in pairs(buildings) do
	-- 	if (i.ud) then
	-- 		buildings[j] = nil
	-- 	end
	-- end
	buildingMap:DeleteItem(unitID)
	myBuilders[unitID] = nil
end
