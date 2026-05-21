function widget:GetInfo()
	return {
	name      = "Phoenix Drop",
	desc      = "Simulates DGUN/Drop behaviour like it would with a Thunderbird\n(EXPERIMENTAL working using D key)",
	author    = "Helwor",
	date      = "May 2024",
	license   = "GNU GPL, v2 or later",
	layer     = -1, -- before Keep Attack
	enabled   = true,  --  loaded by default?
	handler   = true,
	}
end
-------- CONFIG ---------
-- local PING_LEEWAY = 0.02
local opt = {
	removeAnyAttack = true
}

include('keysym.h.lua')
local DROP_KEY = KEYSYMS.D
KEYSYMS = nil
local HALF_LENGTH = 200

------
-------------------------
local debugging = false
local previsual = false
options_path = 'Hel-K/' .. widget.GetInfo().name
options = {}
options_order = {'previsual', 'debugging'}
options.previsual = {
	name = 'Previsualization',
	type = 'bool',
	value = previsual,
	OnChange = function(self)
		previsual = self.value
	end,
}

options.debugging = {
	name = 'Debugging',
	type = 'bool',
	value = debugging,
	OnChange = function(self)
		debugging = self.value
	end,
	dev = true,
}


-- speeds up
local Echo = Spring.Echo

local spGetUnitPosition = Spring.GetUnitPosition
local spGetGroundHeight = Spring.GetGroundHeight
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitVelocity = Spring.GetUnitVelocity
-- local spGetUnitHeading = Spring.GetUnitHeading
-- local spValidUnitID = Spring.ValidUnitID
-- local spGetUnitIsDead = Spring.GetUnitIsDead
-- local spGetUnitWeaponState = Spring.GetUnitWeaponState
-- local spGetUnitIsStunned = Spring.GetUnitIsStunned

local diag = math.diag
local max = math.max
local clamp = math.clamp

local CMD_INSERT, CMD_REMOVE = CMD.INSERT, CMD.REMOVE
local CMD_OPT_ALT, CMD_OPT_SHIFT, CMD_OPT_INTERNAL = CMD.OPT_ALT, CMD.OPT_SHIFT, CMD.OPT_INTERNAL
local CMD_ATTACK = CMD.ATTACK

local EMPTY_TABLE = {}

local phoenixDefID = UnitDefNames['bomberriot'].id
local selectedPhoenixes = false
local unloaded = {}
local prevR, prevG, prevB = 1, 0.5, 0
local prevAlpha = 0.8
local selectionChanged = false


local function IsReloaded(id)
	local noammo = spGetUnitRulesParam(id,'noammo')
	return noammo == 0 or noammo == nil
end
local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ
local function clampMap(x, z)
	return clamp(x, 1, mapSizeX-1), clamp(z, 1, mapSizeZ-1)
end
local function GetClosestDropLocation(id, ping, wantLine)
	local bx ,by ,bz = select(4, spGetUnitPosition(id, false, true))
	if not bx then
		return
	end
	local vx, vy, vz, v = spGetUnitVelocity(id)
	if not vx then
		return
	end
	local y = spGetGroundHeight(bx, bz)
	local distToGround = by - y
	local atkDist = max(distToGround, 50)
	local front, up, right = Spring.GetUnitVectors(id)
	-- -- Echo("turnrate is ", string.format('%.1f', turnrate))
	-- vx, vz = fx * v, fz * v
	local v2D = diag(vx, vz)
	-- Echo(string.format('frontX%.1f, frontY%.1f, frontZ%.1f', unpack(front)))
	local fx, fy, fz = front[1], front[2], front[3]
	-- local headx, headz = (fx * v), (fz * v)
	-- local headx, headz = fx * v2D, fz * v2D
	-- local turndx, turndz = headx - vx, headz - vz
	-- local turnrate = math.diag(turndx, turndz) /2

	local pingFact = 15 * ping
	-- local off = 25 + pingFact
	local gx, gy, gz, gx2, gy2, gz2, dotx, doty, dotz
	if wantLine then
		gx, gy, gz = bx, by, bz
		gx2, gz2 = clampMap(bx + fx *  atkDist, bz + fz  * atkDist)
		gy2 = spGetGroundHeight(gx2, gz2)
		local tries = 0
		local dist = atkDist
		if by - gy2 < 0 then
			while by - gy2 < 0 and tries < 20 and diag(bx - gx2, bz - gz2) > 40 do
				tries = tries + 1
				dist = dist * 0.9
				gx2, gz2 = clampMap(bx + fx * dist, bz + fz  * dist)
				gy2 = spGetGroundHeight(gx2, gz2)
			end
		elseif by - gy2 > diag(bx - gx2, bz - gz2) * 2 then
			local tries = 0
			local dist = atkDist
			while by - gy2 > diag(bx - gx2, bz - gz2) * 2 and tries < 20 do
				tries = tries + 1
				dist = dist * 1.1
				gx2, gz2 = clampMap(bx + fx * dist, bz + fz  * dist)
				gy2 = spGetGroundHeight(gx2, gz2)
			end
		end

		dotx = bx + fx * (atkDist + HALF_LENGTH/2)
		dotz = bz + fz * (atkDist + HALF_LENGTH/2)
		doty = spGetGroundHeight(dotx, dotz)
		doty = doty + 32
	else -- attack location
		-- local off = 15 * (1.5 + ping * 5)
		-- gx, gz = bx + headx * off * 1, bz + headz * off
		-- gy = spGetGroundHeight(gx, gz)
		gx, gz = clampMap(bx + fx * atkDist, bz + fz  * atkDist)
		gy = spGetGroundHeight(gx, gz)
		local tries = 0
		local dist = atkDist
		if by - gy < 0 then
			while by - gy < 0 and tries < 20 and diag(bx - gx, bz - gz) > 40 do
				tries = tries + 1
				dist = dist * 0.9
				gx, gz = clampMap(bx + fx * dist, bz + fz  * dist)
				gy = spGetGroundHeight(gx, gz)
			end
			if debugging then
				if tries > 0 then
					Echo('fixed climb,  tries ' .. tries, 'diag', diag(bx - gx, bz - gz), 'by-gy', by - gy, 'cond', by - gy < 0, tries < 20 , diag(bx - gx, bz - gz) > 40)
				else
					Echo("diag(bx - gx, bz - gz) is ", 'diag', diag(bx - gx, bz - gz), 'by-gy', by - gy, 'cond', by - gy < 0, tries < 20 , diag(bx - gx, bz - gz) > 40)
				end
			end
		elseif by - gy > diag(bx - gx, bz - gz) * 2 then
			local tries = 0
			local dist = atkDist
			while by - gy > diag(bx - gx, bz - gz) * 2 and tries < 20 do
				tries = tries + 1
				dist = dist * 1.1
				gx, gz = clampMap(bx + fx * dist, bz + fz  * dist)
				gy = spGetGroundHeight(gx, gz)
			end
			if debugging then
				if tries > 0 then
					Echo('fixed slide,  tries ' .. tries, 'diag', diag(bx - gx, bz - gz), 'by-gy', by - gy)
				else
					Echo("diag(bx - gx, bz - gz) is ", 'diag', diag(bx - gx, bz - gz), 'by-gy', by - gy)
				end
			end
		end
		dotx = bx + fx * (atkDist + HALF_LENGTH/2)
		dotz = bz + fz * (atkDist + HALF_LENGTH/2)
		doty = spGetGroundHeight(dotx, dotz)
		if debugging then
			X, Y, Z = bx ,by ,bz
			X2, Y2, Z2 = gx, gy, gz
		end
		doty = doty + 32
	end
	return gx, gy, gz, gx2, gy2, gz2, dotx, doty, dotz
end



local pass = {}
local function DrawPrevisualization(id, ping, r, g, b, new)
	local now = Spring.GetGameSeconds()
	local unload = unloaded[id]
	if not (unload) or unload == true then
		local gx, gy, gz, gx2, gy2, gz2, dotx, doty, dotz
		if new or not pass[id] then
			gx, gy, gz, gx2, gy2, gz2, dotx, doty, dotz = GetClosestDropLocation(id, ping, true)
			pass[id] = {gx, gy, gz, gx2, gy2, gz2, dotx, doty, dotz}
		else
			gx, gy, gz, gx2, gy2, gz2, dotx, doty, dotz = unpack(pass[id])
		end
		gl.Color(r, g, b, prevAlpha/2)
		if unload then
			unload = {
				endtime = now + 5,
				dot = {
					{v = {dotx, doty, dotz}--[[, c = {prevR, prevG, prevB, prevAlpha/2}]]},
				}
			}
			gl.Shape(GL.POINTS, unload.dot )
			unloaded[id] = unload
		elseif IsReloaded(id) then
			gl.BeginEnd(GL.LINE_STRIP, function()
				gl.Color(r, g, b, prevAlpha/3)
				gl.Vertex(gx, gy, gz)
				gl.Color(r, g, b, prevAlpha/4)
				-- gl.Vertex(gx1, gy1, gz1)
				gl.Vertex(gx2, gy2, gz2)
			end )
			if dotx then
				gl.Color(r, g, b, prevAlpha/2)
				gl.BeginEnd(GL.POINTS, function() gl.Vertex(dotx, doty, dotz) end)
			end
		end
	else
		if unload.endtime < now then
			unloaded[id] = nil
		else
			gl.Color(r, g, b, prevAlpha * (unload.endtime - now) / 5)
			-- gl.Shape(GL.LINE_STRIP, unload.vertices )
			gl.Shape(GL.POINTS, unload.dot )
		end
	end
end

local function InsertAttackGround(id, x,y,z)
	spGiveOrderToUnit(id, CMD_INSERT,{0, CMD_ATTACK, 0, x,y,z}, CMD_OPT_ALT)
end

local function RemoveAnyAttack(id)
	spGiveOrderToUnit(id, CMD_REMOVE, CMD_ATTACK, CMD_OPT_ALT)
end

local function Process()
	if not selectedPhoenixes then
		return
	end
	for i = 1, #selectedPhoenixes do
		local id = selectedPhoenixes[i]
		local pingNow = select(6,Spring.GetPlayerInfo(Spring.GetMyPlayerID(), true))
		if IsReloaded(id) 
			-- and not spGetUnitRulesParam(id,'att_abilityDisabled')==1
		then
			if opt.removeAnyAttack then
				RemoveAnyAttack(id)
			end
			local x, y, z, x2, y2, z2, x3, y3, z3 = GetClosestDropLocation(id, pingNow)
			if not x then
				return
			end
			InsertAttackGround(id, x, y, z)
			-- InsertAttackGround(id, x2, y2, z2)
			-- InsertAttackGround(id, x3, y3, z3)
			-- InsertAttackGround(id, x4, y4, z4)
			-- RemoveAnyAttack(id)
			unloaded[id] = true

		end
	end
end

function widget:KeyPress(key,m, isRepeat)
	if isRepeat then
		return
	end
	if key == DROP_KEY then
		Process()
	end
end

local selectionChanged = false
function widget:SelectionChanged()
	selectionChanged = true
end
function widget:CommandsChanged() 
	if selectionChanged then
		selectedPhoenixes = (WG.selectionDefID or spGetSelectedUnitsSorted() or EMPTY_TABLE)[phoenixDefID]
		selectionChanged = false
		pass = {}
	end
end

local currentFrame = -1
local lastFrame = -2
function widget:GameFrame(f)
	currentFrame = f
	if f%500 == 0 then -- rare cleanup
		local now = Spring.GetGameSeconds()
		for id, unload in pairs(unloaded) do
			if unload ~= true and  now - unload.endtime > 0 then
				unloaded[id] = nil
			end
		end
	end
end

function widget:DrawWorldPreUnit()
	local pingNow = select(6,Spring.GetPlayerInfo(Spring.GetMyPlayerID(), true))
	if selectedPhoenixes then
		gl.DepthTest(false)
		gl.Blending('alpha_add')
		-- gl.PointParameter(1, 0.001, 0, 0, 10, 1)
		-- Echo("WG.Cam.relDist / 1000 is ", WG.Cam.relDist / 1000, clamp(WG.Cam.relDist / 1000, 0, 8), 10 - clamp(WG.Cam.relDist / 1000, 0, 5))
		if debugging and X then
			local ptSize = 10 - clamp(WG.Cam.relDist / 1000, 0, 5)
			gl.PointSize(ptSize)
			gl.Color(0,0,1,1)
			gl.BeginEnd(GL.POINTS, function() gl.Vertex(X, Y, Z) end)
			gl.Color(1,0,0,1)
			gl.BeginEnd(GL.POINTS, function() gl.Vertex(X2, Y2, Z2) end)
			local text = string.format('2d%d\n3d%d', math.diag(X2-X, Z2-Z), math.diag(X2-X, Y2-Y, Z2-Z))
			gl.PushMatrix()
			gl.Translate(X2, Y2, Z2)
			gl.Billboard()
			gl.Text(text, 0, 0, 10, 'no')
			gl.PopMatrix()
			gl.PointSize(1)
			gl.Color(1,1,1,1)
		end
		if previsual then
			local ptSize = 10 - clamp(WG.Cam.relDist / 1000, 0, 5)
			gl.PointSize(ptSize)
			gl.DepthTest(true)

			gl.DepthTest(GL.GREATER)
			for i, id in ipairs(selectedPhoenixes) do
				DrawPrevisualization(id, pingNow, 1-prevR, 1-prevG, 1-prevB, currentFrame ~= lastFrame)
			end
			gl.DepthTest(GL.LEQUAL)
			for i, id in ipairs(selectedPhoenixes) do
				DrawPrevisualization(id, pingNow, prevR, prevG, prevB)
			end

			gl.Blending('disable')
			gl.DepthTest(false)
			gl.Color(1,1,1,1)
			-- gl.PointParameter(1, 0, 0, 0, 1024, 1)
			gl.PointSize(1)
		end
		lastFrame = currentFrame
	end
end

function widget:Initialize()
	if Spring.GetSpectatingState() then
		widgetHandler:RemoveWidget(self)
		return
	end
	selectionChanged = true
	widget:CommandsChanged()
end


-----------------------------

f.DebugWidget(widget)
