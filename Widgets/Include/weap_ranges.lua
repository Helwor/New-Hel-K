if false and WG.weapRanges then
	return WG.weapRanges, WG.CalcBallisticCircleOfUnit, WG.CalcBallisticCircleOfModel, WG.CalcBallisticCircleOfModelSpecRange
end
local aim_from_pieces = VFS.Include(LUAUI_DIRNAME .. '/Widgets/Include/aim_from_pieces.lua')
local aim_from_pieces_2 = VFS.Include(LUAUI_DIRNAME .. '/Widgets/Include/aim_from_pieces_2.lua')
local aim_from_poses = VFS.Include(LUAUI_DIRNAME .. '/Widgets/Include/aim_from_poses.lua')
WG.commDefIDs = WG.commDefIDs or (function()
	local commDefIDs = {}
	for unitDefID, unitDef in pairs(UnitDefs) do
		if unitDef.customParams.dynamic_comm or unitDef.customParams.level then
			commDefIDs[unitDefID] = true
		end
	end
	return commDefIDs
end)()
local commDefIDs = WG.commDefIDs

WG.weapRanges = (function()
	local weapRanges = {}
	local WeaponDefs = WeaponDefs
	local spuGetMoveType = Spring.Utilities.getMovetype
	for defID, def in pairs(UnitDefs) do

		local weapons = def.weapons
		local t
		local entryIndex = 0
		local name = def.name
		local scriptName = def.scriptName:match('/(.*)%....')
		for i, weap in ipairs(def.weapons) do
			local wDef = WeaponDefs[weap.weaponDef]

			if not wDef.name:find('fakegun') then
				-- from testing customParams.combatrange can be incorrect (pyro), now using the same method as gui_contextmenu.lua
				-- local weaponRange = tonumber(wDef.customParams.truerange --[[or wDef.customParams.combatrange--]]) or wDef.range
				local weaponRange = tonumber(wDef.customParams.truerange --[[or wDef.customParams.combatrange--]]) or wDef.range
				if weaponRange <= 32 and wDef.shieldRadius then
					weaponRange = wDef.shieldRadius
				end
				-- if wType == 'StarburstLauncher' then -- TODO CHECK THIS TYPE
				--  -- Echo(weaponRange)
				-- end
				if (weaponRange > 32) then -- 32 and under are fake weapons
					if not t then
						t = {}
						t.static = not spuGetMoveType(def)
						t.isComm = commDefIDs[defID]
					end
					entryIndex = entryIndex + 1
					t['weaponNum' .. entryIndex] = i
					t[entryIndex] = weaponRange
					t['weaponDef' .. entryIndex] = wDef
					local wType = wDef.type
					local poses = aim_from_poses[def.name] 
					local aimFromUnit = aim_from_pieces[scriptName]
					local aimFromModel = aim_from_pieces_2[scriptName]
					local aimPieceModel = type(aimFromModel) == 'table' and aimFromModel[i] or aimFromModel
					local offY = type(poses) == 'table' and poses[i] or poses

					if not offY then
						-- some notable units script doesnt have AimFrom... function
						-- if wType == 'BeamLaser' or wType == 'BeamLaser' == 'LaserCannon' or wType == 'LightningCannon' then
						offY = def.model.midy 
						local aimposoffset = def.customParams.aimposoffset                  
						if aimposoffset then
							offY = offY + (aimposoffset:match('^%-?%d+ (%-?%d+)'))
							-- this is not the "aim from" but the "aim at", which is still better (closer in most of case)
						end
						-- end
						-- Echo("offY is ", offY)
					end
					t['offY' .. entryIndex] = offY or 0
					t['aimFromModel' .. entryIndex] = aimPieceModel
					t['aimFromUnit' .. entryIndex] = aimFromUnit -- can be a function to fill at query time
				end
			end
		end
		weapRanges[defID] = t
	end
	return weapRanges
end)()

local CalcBallisticCircle 		= VFS.Include("LuaUI/Utilities/engine_range_circles.lua")

local spGetUnitPosition          = Spring.GetUnitPosition
local spGetUnitPieceMap          = Spring.GetUnitPieceMap
local spGetUnitPiecePosition     = Spring.GetUnitPiecePosition
local spGetUnitDefID             = Spring.GetUnitDefID
local spGetUnitRulesParam        = Spring.GetUnitRulesParam
WG.CalcBallisticCircleOfUnit = function( unitID, ...) -- give weap numbers or nothing for all
	local defID = spGetUnitDefID(unitID)
	if not defID then
		return
	end
	local obj = WG.weapRanges[defID]
	if not obj then
		return
	end
	local x, y, z = spGetUnitPosition(unitID)
	if not x then
		return
	end
	local pieceMap = spGetUnitPieceMap(unitID)
	local ret = {}
	if not (...) then -- do all
		local index = 1
		local range = obj[index]
		local commWeap1, commWeap2
		if obj.isComm then
			commWeap1 = spGetUnitRulesParam(unitID, "comm_weapon_num_1")
			commWeap2 = spGetUnitRulesParam(unitID, "comm_weapon_num_2")
		end
		while range do
			local wNum = obj['weaponNum' .. index]
			if not commWeap1 or (wNum == commWeap1 or wNum == commWeap2) then
				local wDef = obj['weaponDef' .. index]
				local aimFrom = obj['aimFromUnit' .. index]
				if type(aimFrom) == 'function' then
					aimFrom = aimFrom(wNum, unitID, wNum)
				end
				local pieceIndex = aimFrom and pieceMap[aimFrom] -- TODO maybe we should check on the fly instead of relying to a hard coded table, for compat but how
				if not pieceIndex then
					Echo('aimFrom piece was wrong for unit' .. unitID, UnitDefs[defID].name, 'defID ' .. defID, 'piece ' .. tostring(aimFrom), 'wNum ' .. wNum)
				else
					local wx, wy, wz = spGetUnitPiecePosition(unitID, pieceIndex)
					ret[#ret+1] = CalcBallisticCircle(x + wx, y + wy, z + wz, range, wDef)
				end
			end
			index = index + 1
			range = obj[index]
		end
	else -- do specified weapon nums
		for i = 1, select('#', ...) do
			local weapNum = select(i, ...)
			local index = 0
			local wNum = true
			while wNum and wNum ~= weapNum do
				index = index + 1
				wNum = obj['weaponNum' .. index]
			end
			if wNum then
				local range = obj[index]
				local wDef = obj['weaponDef' .. index]
				local aimFrom = obj['aimFromUnit' .. index]
				if type(aimFrom) == 'function' then
					aimFrom = aimFrom(nil, unitID, wNum)
				end
				local pieceIndex = aimFrom and pieceMap[aimFrom] -- TODO maybe we should check on the fly instead of relying to a hard coded table, for compat but how
				if not pieceIndex then
					Echo('aimFrom piece was wrong for unit' .. unitID, UnitDefs[defID].name, 'defID ' .. defID, 'piece ' .. tostring(aimFrom), 'wNum ' .. wNum)
				else
					local wx, wy, wz = spGetUnitPiecePosition(unitID, pieceIndex)
					ret[#ret+1] = CalcBallisticCircle(x + wx, y + wy, z + wz, range, wDef)
				end
			end
		end
	end
	return ret
end

WG.CalcBallisticCircleOfModel = function(x, y, z, defID, ...) -- give weap numbers or nothing for all
	local obj = WG.weapRanges[defID]
	if not obj then
		return
	end
	local ret = {}
	if not (...) then -- do all
		local index = 1
		local range = obj[index]
		while range do
			local wDef = obj['weaponDef' .. index]
			local wy = obj['offY' .. index]
			ret[#ret+1] = CalcBallisticCircle( x, y + wy, z, range, wDef)
			index = index + 1
			range = obj[index]
		end
	else -- do specified weapon nums
		for i = 1, select('#', ...) do
			local weapNum = select(i, ...)
			local index = 0
			local wNum = true
			while wNum and wNum ~= weapNum do
				index = index + 1
				wNum = obj['weaponNum' .. index]
			end
			if wNum then
				local range = obj[index]
				local wDef = obj['weaponDef' .. index]
				local wy = obj['offY' .. index]
				ret[#ret+1] = CalcBallisticCircle( x, y + wy, z, range, wDef)
			end
		end
	end
	return ret
end

WG.CalcBallisticCircleOfModelSpecRange = function(x, y, z, defID, ...) -- give weap numbers and specified range
	local obj = WG.weapRanges[defID]
	if not obj then
		return
	end
	local ret = {}
	for i = 1, select('#', ...) do
		local weapNum = select(i*2-1, ...)
		local range = select(i*2, ...)
		local index = 0
		local wNum = true
		while wNum and wNum ~= weapNum do
			index = index + 1
			wNum = obj['weaponNum' .. index]
		end
		if wNum then
			local wDef = obj['weaponDef' .. index]
			local wy = obj['offY' .. index]
			ret[#ret+1] = CalcBallisticCircle( x, y + wy, z, range, wDef)
		end
	end
	return ret
end




return WG.weapRanges, WG.CalcBallisticCircleOfUnit, WG.CalcBallisticCircleOfModel, WG.CalcBallisticCircleOfModelSpecRange