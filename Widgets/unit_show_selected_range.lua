-- mod version externalize the function to  draw units range WG.DrawUnitTypeRanges
-- if not Game.modName:find('^Zero-K') then
-- 	-- Echo(" is ", (VFS.LoadFile(LUAUI_DIRNAME .. 'Widgets/unit_show_selected_range.lua', VFS.ZIP) or ''):sub(1, 100))
-- 	VFS.Include(LUAUI_DIRNAME .. 'Widgets/unit_show_selected_range.lua', widget, VFS.ZIP)
-- 	return
-- end
function widget:GetInfo() return {
	name    = "Show selected unit range",
	author  = "very_bad_soldier / versus666, Helwor implement Ballistic Calc",
	date    = "October 21, 2007 / September 08, 2010",
	license = "GNU GPL v2",
	layer   = 0,
	enabled = true,
} end


local Echo = Spring.Echo

local spGetSelUnitsSorted		= Spring.GetSelectedUnitsSorted
local spGetUnitViewPosition		= Spring.GetUnitViewPosition
local spGetUnitRulesParam   	= Spring.GetUnitRulesParam
local spGetUnitWeaponState  	= Spring.GetUnitWeaponState
local spIsGUIHidden 			= Spring.IsGUIHidden
local spGetSelectedUnitsCount 	= Spring.GetSelectedUnitsCount
local spGetUnitPosition			= Spring.GetUnitPosition

local glColor            = gl.Color
local glLineWidth        = gl.LineWidth
local glDrawGroundCircle = gl.DrawGroundCircle

local CalcBallisticCircle 		= VFS.Include("LuaUI/Utilities/engine_range_circles.lua")
local max_selection = 20
local max_selection_ballistic = 1
local use_ballistic = true
local EMPTY_TABLE = {}

local helk_path = 'Hel-K/' .. widget:GetInfo().name
options_path = 'Settings/Interface/Defence and Cloak Ranges'
options = {}
options_order = {
	'showselectedunitrange',
	'max_selection',
	'use_ballistic',
	'max_selection_ballistic',
}
options.showselectedunitrange = {
	name = 'Show selected unit(s) range(s)',
	type = 'bool',
	value = false,
	OnChange = function (self)
		if self.value then
			widgetHandler:UpdateCallIn("DrawWorldPreUnit")
			widgetHandler:UpdateCallIn("CommandsChanged")
			widget:CommandsChanged()
		else
			widgetHandler:RemoveCallIn("DrawWorldPreUnit")
			widgetHandler:RemoveCallIn("CommandsChanged")
		end
	end,
}
options.max_selection = {
	type = 'number',
	name = 'Max Selection',
	desc = 'Max selection under which we allow drawing of ranges',
	min = 0, max = 301, step = 1,
	value = max_selection,
	update_on_the_fly = true,
	tooltipFunction = function(self)
		if self.value == 301 then
			return 'unlimited'
		else
			return tostring(self.value)
		end
	end,
	OnChange = function(self)
		if self.value == 301 then
			max_selection = math.huge
		else	
			max_selection = self.value
		end
		if widget.CommandsChanged then
			widget:CommandsChanged()
		end
	end,
	path = helk_path,
}

options.use_ballistic = {
	name = 'Use Ballistic Calc',
	desc = 'Beware it might be heavy on big numbers',
	type = 'bool',
	value = use_ballistic,
	OnChange = function (self)
		use_ballistic = self.value
		if widget.CommandsChanged then
			widget:CommandsChanged()
		end
	end,
	path = helk_path,
}

options.max_selection_ballistic = {
	type = 'number',
	name = 'Max Selection Ballistic',
	desc = 'Max of units under which we calculate ballistic range.\n(if the option Use Ballistic Range is set)',
	min = 0, max = 301, step = 1,
	value = max_selection_ballistic,
	update_on_the_fly = true,
	tooltipFunction = function(self)
		if self.value == 301 then
			return 'unlimited'
		else
			return tostring(self.value)
		end
	end,
	OnChange = function(self)
		if self.value == 301 then
			max_selection_ballistic = math.huge
		else	
			max_selection_ballistic = self.value
		end
		if widget.CommandsChanged then
			widget:CommandsChanged()
		end
	end,
	path = helk_path,
}


local commDefIDs = WG.commDefIDs or {}
WG.commDefIDs = WG.commDefIDs or (function()
	for unitDefID, unitDef in pairs(UnitDefs) do
		if unitDef.customParams.dynamic_comm then
			commDefIDs[unitDefID] = true
		end
	end
	return commDefIDs
end)()
VFS.Include(LUAUI_DIRNAME ..'/Widgets/Include/weap_ranges.lua')

local weapRanges = WG.weapRanges


local function RangeColor(strengthIdx, color, ballistic)
	local strength = (1 - strengthIdx/5)
	if color then
		glColor(color[1] * strength, color[2] * strength, color[3] - strength, color[4] or 0.35)
	else
		glColor(1.0 - (strengthIdx / 5), ballistic and 1.0 or 0, 0, 0.35)
	end
end
local function CircleVerts(verts)
	for i = 1, #verts do
		gl.Vertex(verts[i])
	end
	gl.Vertex(verts[1])
end
local function DrawRangeCircle(x, y, z, weap, range, rangeInfo, strengthIdx, color, use_ballistic)
	RangeColor(strengthIdx, color, use_ballistic)
	if use_ballistic then
		local vertices = (WG.CalcBallisticCircle or CalcBallisticCircle)(x, y + rangeInfo['offY' .. weap], z, range, rangeInfo['weaponDef' .. weap])
		gl.BeginEnd(GL.LINE_STRIP, CircleVerts, vertices)
	else
		glDrawGroundCircle(x, y, z, range, 40)
	end

end


local knownUnits = setmetatable({},{__mode = 'v'})
local reused = 0

local function DrawComRanges(defID, units, color, isEnemy, use_ballistic)
	for i, unitID in ipairs(units) do
		local x,y,z = select(4, spGetUnitPosition(unitID, false , true))
		if x then
			local known = knownUnits[unitID]
			if not known then
				local weap1 = spGetUnitRulesParam(unitID, "comm_weapon_num_1")
				local range1 =  spGetUnitWeaponState(unitID, weap1, "range")
				local weap2 = spGetUnitRulesParam(unitID, "comm_weapon_num_2")
				local range2 = weap2 and spGetUnitWeaponState(unitID, weap2, "range")
				local rangeInfo = weapRanges[defID]
				known = {
					rangeInfo,
					weap1,
					range1,
					weap2,
					range2,
				}
				knownUnits[unitID] = known
			else
				reused = reused + 1
			end
				
			local rangeInfo, weap1, range1, weap2, range2 = known[1], known[2], known[3], known[4], known[5]

			if rangeInfo then
				if weap1 then
					DrawRangeCircle(x, y, z, weap1, range1, rangeInfo, 1, color, use_ballistic)
				end
				if weap2 then
					DrawRangeCircle(x, y, z, weap2, range2, rangeInfo, 2, color, use_ballistic)
				end
			end
		end
	end
end

local function DrawUnitsRanges(defID, units, color, use_ballistic)
	local rangeInfo = weapRanges[defID]
	if rangeInfo then
		for _, unitID in ipairs(units) do
			-- local ux,uy,uz = select(4, spGetUnitPosition(unitID, false , true))
			local x,y,z = spGetUnitPosition(unitID)
			if x then
				for weap, range in ipairs(rangeInfo) do
					DrawRangeCircle(x, y, z, weap, range, rangeInfo, weap, color, use_ballistic)
				end
			end
		end
	end
end
local function DrawUnitTypeRanges(defID, units, use_ballistic, color, width, isEnemy)
	if width then
		glLineWidth(width)
	end
	if commDefIDs[defID] then -- Dynamic comm have different ranges and different weapons activated
		DrawComRanges(defID, units, color, isEnemy, use_ballistic)
	else
		DrawUnitsRanges(defID, units, color, use_ballistic)
	end
	if width then
		glLineWidth(1)
	end
end

-- local to = 0
-- function widget:Update(dt)
-- 	to = to + dt
-- 	if to >= 100 then
-- 		Echo('reused', reused,'size of known',table.size(knownUnits))
-- 		to = 0
-- 	end
-- end


local selUnits, selCount

function widget:CommandsChanged()
	selCount = spGetSelectedUnitsCount()
	if selCount <= max_selection then
		selUnits = WG.selectionDefID or spGetSelUnitsSorted()
	else
		selUnits = EMPTY_TABLE
	end
end

function widget:DrawWorldPreUnit()
	if spIsGUIHidden() then
		return
	end

	glLineWidth(1.5)

	for defID, units in pairs(selUnits) do
		DrawUnitTypeRanges(defID, units, use_ballistic and selCount <= max_selection_ballistic)
	end

	glColor(1, 1, 1, 1)
	glLineWidth(1.0)
end

function widget:Initialize()
	widgetHandler:RemoveCallIn("DrawWorldPreUnit")
	widgetHandler:RemoveCallIn("CommandsChanged")
	WG.DrawUnitTypeRanges = DrawUnitTypeRanges
end

function widget:Shutdown()
	WG.DrawUnitTypeRanges = nil
end

if f then
	f.DebugWidget(widget)
end