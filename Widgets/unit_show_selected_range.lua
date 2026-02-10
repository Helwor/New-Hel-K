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
local glVertex           = gl.Vertex
local glCallList         = gl.CallList
local glDeleteList       = gl.DeleteList

local diag = math.diag


local CalcBallisticCircle 		= VFS.Include("LuaUI/Utilities/engine_range_circles.lua")
local max_selection = 20
local max_selection_ballistic = 1
local use_ballistic = true
local EMPTY_TABLE = {}
local dbg = false
local helk_path = 'Hel-K/' .. widget:GetInfo().name
options_path = 'Settings/Interface/Defence and Cloak Ranges'
options = {}
options_order = {
	'showselectedunitrange',
	'max_selection',
	'use_ballistic',
	'max_selection_ballistic',
	'dbg',
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

options.dbg = {
	name = 'Debug Ranges',
	type = 'bool',
	value = dbg,
	OnChange = function(self)
		dbg = self.value
	end,
	path = helk_path,
	dev = true,
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


local function TranslateOffY(bx, by, bz, mx, my, mz, offY)
	local dx = mx - bx
	local dy = my - by
	local dz = mz - bz
	local invDist = 1.0 / diag(dx, dy, dz)
	return bx + offY * (invDist * dx), by + offY * (invDist * dy), bz + offY * (invDist * dz)
end

local function RangeColor(strengthIdx, color, ballistic)
	local strength = (1 - strengthIdx/5)
	if color then
		glColor(color[1] * strength, color[2] * strength, color[3] - strength, color[4] or 0.35)
	else
		glColor(strength, ballistic and 0.9 or 0, 0, 0.35)
	end
end
local function CircleVerts(verts)
	for i = 1, #verts do
		glVertex(verts[i])
	end
	glVertex(verts[1])
end

local lists, templist
do
	lists = setmetatable({}, {__mode = 'k'})
	templist = newproxy(true)
	getmetatable(templist).__gc = function(self)
		if self == templist then
			Echo('master proxy collected')
			return
		else
			 local key = lists[self]
			 if key then
			 	-- Echo("delete list... ", key,  lists[key] )
			 	glDeleteList(lists[key] or 0)
			 	lists[key] = nil
			 -- else
			 -- 	Echo('proxy collected, list already deleted via shutdown')
			 end

		end
	end
	getmetatable(templist).__newindex = function(self, key ,list)
		-- Echo('set temp list',key, list)
		lists[key] = list
		lists[self] = key
	end
end
local function DrawRangeCircle(unitID, x, y, z, i, range, rangeInfo, strengthIdx, color, use_ballistic, noYoff)
	RangeColor(strengthIdx, color, use_ballistic)
	if not dbg and rangeInfo.static then
		local cached = lists[unitID .. '-' .. i .. (use_ballistic and 'b' or '')]
		if not cached then
			cached = gl.CreateList(
				function()
					if use_ballistic then
						local vertices = (WG.CalcBallisticCircle or CalcBallisticCircle)(x, y  + (noYoff and 0 or rangeInfo['offY' .. i]) , z, range, rangeInfo['weaponDef' .. i])
						gl.BeginEnd(GL.LINE_STRIP, CircleVerts, vertices)
					else
						glDrawGroundCircle(x, y, z, range, 40)
					end
				end
			)
			newproxy(templist)[unitID .. '-' .. i .. (use_ballistic and 'b' or '')] = cached
		end
		glCallList(cached)
		return
	end
	if use_ballistic then
		local vertices = (WG.CalcBallisticCircle or CalcBallisticCircle)(x, y  + (noYoff and 0 or rangeInfo['offY' .. i]) , z, range, rangeInfo['weaponDef' .. i])
		gl.BeginEnd(GL.LINE_STRIP, CircleVerts, vertices)
	else
		glDrawGroundCircle(x, y, z, range, 40)
	end

end


local knownUnits = setmetatable({},{__mode = 'v'})
local reused = 0

local Debug
do
	local wType, heightMod, projectilespeed, myGravity, wName, heightBoostFactor
	local lastTime = os.clock()
	function Debug(defID, rangeInfo, range, idx, bx, bz, by, my, ay)
		local def = UnitDefs[defID]
		local aimposoffset = def.customParams.aimposoffset
		local wDef = rangeInfo['weaponDef'..idx]
		local now = os.clock()
		if now - lastTime > 3 
			or wType ~= wDef.type or heightMod ~= wDef.heightMod or projectilespeed ~= wDef.projectilespeed
			or myGravity ~= wDef.myGravity or wName ~= wDef.name or heightBoostFactor ~= (wDef.heightBoostFactor or -1)
		then
			lastTime = now
			wType, heightMod, projectilespeed, myGravity, wName, heightBoostFactor = wDef.type, wDef.heightMod, wDef.projectilespeed, wDef.myGravity, wDef.name, wDef.heightBoostFactor or -1
			Echo("name ".. tostring(wName),"range " .. tostring(range), "type ".. tostring(wType), "heightMod " .. tostring(heightMod), "projSpeed " .. tostring(projectilespeed), "gravity " .. tostring(myGravity), "heightBoost " .. tostring(heightBoostFactor),
			'\nground', math.round(Spring.GetGroundHeight(bx, bz)),"model.midy " .. math.round(def.model.midy),  "aimposoffset ".. tostring(aimposoffset),'unit y:', math.round(by) ..' (+'..math.round(my-by)..' + '..math.round(ay-my)..' => '..math.round(ay-by)..')', 'own offY '.. math.round(rangeInfo["offY"..idx]))
		end
	end
end
local function GetRangeInfoIndex(rangeInfo, weap)
	for idx in ipairs(rangeInfo) do
		if rangeInfo['weaponNum'..idx] == weap then
			return idx
		end
	end
end
local GetRealWeaponPos
do
	local spGetUnitPieceMap = Spring.GetUnitPieceMap
	local spGetUnitPiecePosition = Spring.GetUnitPiecePosition
	local spGetUnitVectors = Spring.GetUnitVectors
	local function GetPieceAbsolutePosition(id, px, py, pz)
		local bx,by,bz = spGetUnitPosition(id)
		local front,top,right = spGetUnitVectors(id)
		return  bx + front[1]*pz + top[1]*py + right[1]*px,
				by + front[2]*pz + top[2]*py + right[2]*px,
				bz + front[3]*pz + top[3]*py + right[3]*px
	end
	function GetRealWeaponPos(unitID, aimPiece)
		local pieceID = spGetUnitPieceMap(unitID)[aimPiece]
		if pieceID then
			return GetPieceAbsolutePosition(unitID, spGetUnitPiecePosition(unitID, pieceID))
		end
	end
end
local function DrawComRanges(defID, units, color, isEnemy, use_ballistic)
	for i, unitID in ipairs(units) do
		local bx, by, bz, mx, my, mz, ax, ay, az = spGetUnitPosition(unitID, true , true)
		if bx then
			local known = knownUnits[unitID]
			local rangeInfo, idx1, range1, idx2, range2
			if not known then
				rangeInfo = weapRanges[defID]
				weap1 = spGetUnitRulesParam(unitID, "comm_weapon_num_1")
				range1 =  weap1 and spGetUnitWeaponState(unitID, weap1, "range")
				idx1 = weap1 and GetRangeInfoIndex(rangeInfo, weap1)
				weap2 = spGetUnitRulesParam(unitID, "comm_weapon_num_2")
				range2 = weap2 and spGetUnitWeaponState(unitID, weap2, "range")
				idx2 = weap2 and GetRangeInfoIndex(rangeInfo, weap2)
				known = {
					rangeInfo,
					idx1,
					range1,
					idx2,
					range2,
				}
				knownUnits[unitID] = known
			else
				reused = reused + 1
				rangeInfo, idx1, range1, idx2, range2 = known[1], known[2], known[3], known[4], known[5]
			end

			if rangeInfo and range1 then
				if idx1 then
					if dbg then
						Debug(defID, rangeInfo, range1, idx1, bx, bz, by, my, ay)
						-- purely aimPoint from GetUnitPosition in black
						DrawRangeCircle(unitID, ax, ay, az, idx1, range1, rangeInfo, 1, COLORS.black, use_ballistic, true)
						for idx1, range1 in ipairs(rangeInfo) do
							-- orange, get real position of aim pieces of every weapons, aim pieces being pre gathered and hard written
							local wx, wy, wz = GetRealWeaponPos(unitID, rangeInfo['aimFromModel' .. idx1])
							if wx then
								DrawRangeCircle(unitID, wx, wy, wz, idx1, range1, rangeInfo, 1, COLORS.orange, use_ballistic, true)
							end
						end
					end
					if diag(mx - bx, mz - bz) > 2.05  then -- cheap way to detect unit being inclined (bu aim point x,z can also be offset naturally without the unit beeing inclined)
						ax, ay, az = TranslateOffY(bx, by, bz, mx, my, mz, rangeInfo['offY'..idx1])
						DrawRangeCircle(unitID, ax, ay, az, idx1, range1, rangeInfo, 1, color, use_ballistic, true)
					else
						DrawRangeCircle(unitID, bx, by, bz, idx1, range1, rangeInfo, 1, color, use_ballistic)
					end
				end
				if idx2 and not dbg then
					DrawRangeCircle(unitID, bx, by, bz, idx2, range2, rangeInfo, 2, color, use_ballistic)
				end
			end
		end
	end
end
-- ENGINE BUG : as of Feb 2026. The unit start aiming its weapon when the target is in reach of the weapon, the problem is that when it start aiming, the weapon move and then can become of reach.
-- which results in a back and forth loop movement of the weapons
-- Fix would be to test from the weapon's position when it's ready to shoot and not its current position
-- this rare case is particularily visible with the detriment
local function DrawUnitsRanges(defID, units, color, use_ballistic)
	local rangeInfo = weapRanges[defID]
	if rangeInfo then
		for _, unitID in ipairs(units) do
			local bx, by, bz, mx, my, mz, ax, ay, az = spGetUnitPosition(unitID, true , true)
			if bx then
				for idx, range in ipairs(rangeInfo) do
					local weap = rangeInfo['weaponNum' .. idx]
					if dbg then
						Debug(defID, rangeInfo, range, idx, bx, bz, by, my, ay)
						-- purely aimPoint from GetUnitPosition
						DrawRangeCircle(unitID, ax, ay, az, idx, range, rangeInfo, 1, COLORS.black, use_ballistic, true)
						for idx, range in ipairs(rangeInfo) do
							-- orange, get real position of aim pieces of every weapons, aim pieces being gathered and hard written
							local wx, wy, wz = GetRealWeaponPos(unitID, rangeInfo['aimFromModel' .. idx])
							if wx then
								DrawRangeCircle(unitID, wx, wy, wz, idx, range, rangeInfo, 1, COLORS.orange, use_ballistic, true)
							end
						end
					end
					if diag(mx - bx, mz - bz) > 2.05  then -- unit is inclined (but aim point x,z can also be offset naturally without the unit beeing inclined)
						ax, ay, az = TranslateOffY(bx, by, bz, mx, my, mz, rangeInfo['offY'..idx])
						DrawRangeCircle(unitID, ax, ay, az, idx, range, rangeInfo, idx, color, use_ballistic, true)
					else
						DrawRangeCircle(unitID, bx, by, bz, idx, range, rangeInfo, idx, color, use_ballistic)
					end
					if dbg then -- that's enough of a spam, let's show only the first weapon
						break
					end
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
	for k, list in pairs(lists) do -- don't wait for auto collection
		if tonumber(list) then
			gl.DeleteList(list)
		end
		lists[k] = nil
	end
	templist = nil
end

if f then
	f.DebugWidget(widget)
end