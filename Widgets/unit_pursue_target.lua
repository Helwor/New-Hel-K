function widget:GetInfo()
	return {
		name      = "Pursue Target",
		desc      = "Pursue the target in the Fog of War",
		author    = "Helwor	",
		license   = "Aug 2026",
		layer     = 0,
		enabled   = false,
		handler   = true,
	}
end
local debugging = false
local draw_debugging = 'minimal'
local widget = widget
local GetSignedWidget, SendSignedOrderToUnit, SendWidgetSignature
local attacking = {}
local attacked = {}
local attackerInit = {}
local orderBuffer = {}
local updateRate = 15 -- in frame
local currentFrame = -1
local maxLeadRadius = 450
local selChanged = false
local selectedAttackers = {}
local gotAttackers = false
local GAME_SPEED = Game.gameSpeed
local maxTimePursue = 15 * GAME_SPEED

----- speed ups

local CMD_RAW_MOVE  = Spring.Utilities.CMD.RAW_MOVE
local CMD_ATTACK    = CMD.ATTACK
local CMD_REMOVE    = CMD.REMOVE
local CMD_STOP      = CMD.STOP
local CMD_OPT_RIGHT = CMD.OPT_RIGHT

local math = math
local min  = math.min
local max  = math.max
local abs  = math.abs
local diag = math.diag
local sqrt = math.sqrt
local huge = math.huge
local modf = math.modf

local spGetUnitPosition             = Spring.GetUnitPosition
local spValidUnitID                 = Spring.ValidUnitID
local spGetUnitDefID                = Spring.GetUnitDefID
local spIsUnitInLos                 = Spring.IsUnitInLos
local spGetUnitCurrentCommand       = Spring.GetUnitCurrentCommand
local spGetGroundHeight             = Spring.GetGroundHeight
local spGetUnitIsDead               = Spring.GetUnitIsDead
local spIsUnitInView                = Spring.IsUnitInView
local spGetSelectedUnitsSorted      = Spring.GetSelectedUnitsSorted
local spGetSelectedUnits            = Spring.GetSelectedUnits
local spWorldToScreenCoords         = Spring.WorldToScreenCoords

local glColor        = gl.Color
local glLineStipple  = gl.LineStipple
local glLineWidth    = gl.LineWidth

local next, pairs, ipairs = next, pairs, ipairs

------

local function clear(t)
	for k in pairs(t) do
		t[k] = nil
	end
end
options_path = 'Hel-K/'..widget.GetInfo().name
options = {
	lead_radius = {
		name = 'Lead Radius',
		type = 'number',
		min = 0, max = 1000, step = 1,
		value = maxLeadRadius,
		OnChange = function(self)
			maxLeadRadius = self.value
		end
	},
	draw_debugging = {
		name = 'Draw Debugging',
		type = 'radioButton',
		value = 'none',
		items = {
			{key = 'none', name = 'None'},
			{key = 'minimal', name = 'Minimal'},
			{key = 'full', name = 'Full'},
		},
		OnChange = function(self)
			if self.value == 'none' then
				draw_debugging = false
				widgetHandler:RemoveWidgetCallIn('DrawWorld', widget)
				widgetHandler:RemoveWidgetCallIn('DrawScreen', widget)
			else
				draw_debugging = self.value
				if draw_debugging == 'minimal' then

					widgetHandler:RemoveWidgetCallIn('DrawWorld', widget)
					widgetHandler:UpdateWidgetCallIn('DrawScreen', widget)
				else
					widgetHandler:UpdateWidgetCallIn('DrawWorld', widget)
					widgetHandler:UpdateWidgetCallIn('DrawScreen', widget)
				end
			end

		end,
		dev = true,
	},
}

local WALL_MARGIN = 16
local mapX = Game.mapSizeX-WALL_MARGIN
local mapZ = Game.mapSizeZ-WALL_MARGIN
local gluDrawScreenDisc = gl.Utilities.DrawScreenDisc


local canAttack = {}
for defID, def in pairs(UnitDefs) do
	if def.canAttack then
		canAttack[defID] = true
	end
end
local speedDefs = {}
for defID, def in pairs(UnitDefs) do
	if def.canMove then
		speedDefs[defID] = def.speed / GAME_SPEED
	end
end

local function TimeToHitBoundary(tx, tz, vtx, vtz)
	local tMin = huge

	if vtx > 0 then
		tMin = min(tMin, (mapX - tx) / vtx)
	elseif vtx < 0 then
		tMin = min(tMin, (WALL_MARGIN - tx) / vtx)
	end

	if vtz > 0 then
		tMin = min(tMin, (mapZ - tz) / vtz)
	elseif vtz < 0 then
		tMin = min(tMin, (WALL_MARGIN - tz) / vtz)
	end

	return tMin -- frames avant de toucher un bord (huge si aucun axe ne bouge vers un bord)
end

local function ClampToRadius(cx, cz, ix, iz, maxRadius)
	local dx, dz = ix - cx, iz - cz
	local dist = diag(dx, dz)
	if dist > maxRadius then
		local reduce = maxRadius / dist
		return cx + dx * reduce, cz + dz * reduce
	end
	return ix, iz
end

local function ComputeInterceptPoint(px, pz, speed, tx, tz, vtx, vtz, radius)
	radius = radius or 0
	local dx, dz = tx - px, tz - pz

	local a = (vtx*vtx + vtz*vtz) - speed*speed -- square diff speed
	local b = 2 * (dx*vtx + dz*vtz) - 2 * speed * radius
	local c = dx*dx + dz*dz - radius*radius

	if c <= 0 then
		-- in range of radius
		return px, pz, 0
	end

	local t

	if abs(a) < 1e-6 then
		if abs(b) < 1e-6 then return nil end
		t = -c / b
		if t < 0 then return nil end
	else
		local disc = b*b - 4*a*c
		if disc < 0 then return nil end

		local sqrtDisc = sqrt(disc)
		local t1 = (-b - sqrtDisc) / (2*a)
		local t2 = (-b + sqrtDisc) / (2*a)

		if t1 > 0 and t2 > 0 then
			t = min(t1, t2)
		elseif t1 > 0 then
			t = t1
		elseif t2 > 0 then
			t = t2
		else
			return nil
		end
	end

	local futureX, futureZ = tx + vtx*t, tz + vtz*t
	local totalDist = speed * t + radius
	if totalDist < 1e-6 then
		return futureX, futureZ, t
	end
	local ratio = (speed * t) / totalDist
	local destX = px + (futureX - px) * ratio
	local destZ = pz + (futureZ - pz) * ratio

	return destX, destZ, t * ratio
end

local function ComputeInterceptPointBounded(px, pz, speed, tx, tz, vtx, vtz, radius)
	radius = radius or 0
	local tWall = TimeToHitBoundary(tx, tz, vtx, vtz)

	local ix, iz, t = ComputeInterceptPoint(px, pz, speed, tx, tz, vtx, vtz, radius)

	if ix and tWall > 0 and t <= tWall then
		return ix, iz, t
	end

	if tWall == huge then
		return tx, tz, 0
	end

	local wallX = tx + vtx * tWall
	local wallZ = tz + vtz * tWall

	local ddx, ddz = wallX - px, wallZ - pz
	local distToWall = diag(ddx, ddz)

	if distToWall <= radius then
		-- in range
		return px, pz, 0
	end

	local ratio = (distToWall - radius) / distToWall
	local destX = px + ddx * ratio
	local destZ = pz + ddz * ratio

	local tToReach = (distToWall - radius) / speed

	return destX, destZ, max(tToReach, tWall)
end

local function SameOrder(id, bufferedOrder, cmd, params, verifCurrent)
	local buffcmd, buffparams = bufferedOrder[1], bufferedOrder[2]
	if buffcmd == cmd then
		if cmd == CMD_RAW_MOVE and buffparams[3] then
			if diag(params[1] - buffparams[1], params[3] - buffparams[3]) < 64 then
				return true
			end
		else
			if buffparams[1] == params[1] then
				return true
			end
		end
	end
	if verifCurrent then
		local curcmd, curopt, curtag, curp1, curp2, curp3 = spGetUnitCurrentCommand(id)
		-- Echo("verif current ", curcmd, curopt, curtag, curp1, curp2, curp3)
		if curcmd == cmd then
			if cmd == CMD_RAW_MOVE and params[3] then
				if (params[1] == curp1 and params[3] == curp3) or diag(params[1] - curp1, params[3] - curp3) < 64 then
					-- Echo('(same current rawmove)')
					return true
				end
			else
				if params[1] == curp1 then
					-- Echo('(same current attack)')
					return true
				end
			end
		end
	end
	return false
end

local function Order(id, cmd, params, update)
	local buffered = orderBuffer[id]
	if cmd == CMD_REMOVE then
		----Echo('['..currentFrame..']'..'Removing Order tag: '.. modf(params[1]))
		SendSignedOrderToUnit(widget, id, cmd, params, 0)
	elseif not buffered then
		if not attacking[id] then
			if debugging then
				Echo('['..currentFrame..']'..'Not sending '..f.cmdNames[cmd]..', the attacker got deleted')
			end
		else
			if debugging then
				Echo('['..currentFrame..']'..'First Ever Order: '.. f.cmdNames[cmd], modf(params[1]))
			end
			orderBuffer[id] = {waiting = true, cmd, params}
			SendSignedOrderToUnit(widget, id, cmd, params, 0)
		end
	elseif update then -- UnitCommand received order
		if debugging then
			Echo('['..currentFrame..']'..'Received '..f.cmdNames[cmd], params[1], params[2], params[3], 'Waiting: '..f.cmdNames[buffered[1]], buffered[2][1], buffered[2][2] or '', buffered[2][3] or '')
		end
		if not SameOrder(id, buffered, cmd, params--[[, true]]) then
			if debugging then
				Echo('['..currentFrame..']'..'\t\t=> send new buffered '..f.cmdNames[buffered[1]], modf(buffered[2][1]))
			end
			SendSignedOrderToUnit(widget, id, buffered[1], buffered[2], 0)
		else
			buffered.waiting = false
			-- Echo('\t\t=> same buffered detected '.. f.cmdNames[cmd], params[1] ..' vs '.. f.cmdNames[buffered[1]], buffered[2][1]--[[.. ' or same as current order']])
		end
	elseif buffered.waiting then
		-- Echo('['..currentFrame..']'..'Replace Waiting Order '..f.cmdNames[buffered[1]], buffered[2][1].. ' for '..f.cmdNames[cmd], params[1])
		buffered[1], buffered[2] = cmd, params
	else -- no waited order
		-- Echo('['..currentFrame..']'..'Immediate Ordering available '..f.cmdNames[cmd], params[1], params[2], params[3], 'buffered: '..f.cmdNames[buffered[1]], buffered[2][1], buffered[2][2] or '', buffered[2][3] or '')
		if not SameOrder(id, buffered, cmd, params, true) then
			if debugging then
				Echo('['..currentFrame..']'..'\t\t=> different order, sending... '..f.cmdNames[cmd], modf(params[1]), params[2] and modf(params[2]) or '', params[3] and modf(params[3]) or '')
			end
			buffered[1], buffered[2] = cmd, params
			buffered.waiting = true
			SendSignedOrderToUnit(widget, id, cmd, params, 0)
		else
			-- Echo('\t\t=> same order, no sending.')
		end

	end
end





local function RemoveAttacked(id, obj)
	for attID in pairs(obj.attackers) do
		attacking[attID] = nil
		attackerInit[attID] = nil
		orderBuffer[attID] = nil
		selectedAttackers[attID] = nil
		if debugging then
			Echo('attacker removed '.. attID)
		end
	end
	attacked[id] = nil
	if debugging then
		Echo('target destroyed '..id, f.GetCalledLine())
	end
end

local function RemoveAttacker(id, obj, removeOrder)
	if debugging then
		Echo('attacker removed '..id)
	end
	obj.attackers[id] = nil
	attacking[id] = nil
	attackerInit[id] = nil
	orderBuffer[id] = nil
	selectedAttackers[id] = nil
	if not next(obj.attackers) then
		attacked[obj.targetID] = nil
		if debugging then
			Echo('target destroyed '..obj.targetID, f.GetCalledLine())
		end
	end
end

local function AddAttacked(id, defID, targetID)
	local obj = attacked[targetID]
	local attObj = attacking[id]
	if attObj then
		if attObj == obj then
			attackerInit[id] = (attackerInit[id] or 0) + 1
			return obj
		else
			RemoveAttacker(id, attObj)
		end
	end
	if obj then
		obj.attackers[id] = defID
		attackerInit[id] = (attackerInit[id] or 0) + 1
		attacking[id] = obj
		if debugging then
			Echo('attacker ' .. id .. ' added')
		end
		return obj
	end
	local x, y, z = spGetUnitPosition(targetID)
	if x then
		obj = {
			attackers = {[id] = defID},
			targetID = targetID,
			targetDefID = spGetUnitDefID(targetID),
			pos = {x, y, z},
			lastpos = {x, y, z},
			temppos = false,
			frame = currentFrame, -- for immediate update
			lastframe = currentFrame,
			updateNow = true,
			inradar = true,
			inlos = spIsUnitInLos(targetID),
			stabilize = false,
		}
		attacked[targetID] = obj
		attackerInit[id] = (attackerInit[id] or 0) + 1
		attacking[id] = obj
		if debugging then
			Echo('attacker ' .. id .. ' added')
		end
		return obj
	end
end

local function PursueTarget(id, obj)
	local pos, lastpos = obj.pos, obj.lastpos
	local copypos = {unpack(pos)}
	local x, y, z = pos[1], pos[2], pos[3]
	local posOrder = (x == lastpos[1] and z == lastpos[3]) and copypos
	local dx2D, dz2D, targetSpeed
	if not posOrder then
		local dx, dy, dz = x - lastpos[1], pos[2] - lastpos[2], z - lastpos[3]
		local dist = diag(dx, dy, dz)
		local nx, ny, nz = dx / dist, dy / dist, dz / dist
		-- Echo("dist", dist, "nx, nz is ", nx, nz, 'v3D', diag(nx, ny, nz))
		local nlen2D = diag(nx, nz)
		dx2D, dz2D = nx / nlen2D, nz / nlen2D
		targetSpeed = obj.targetSpeed
		if not targetSpeed then
			if obj.targetDefID then
				targetSpeed = speedDefs[obj.targetDefID]
				obj.targetSpeed = targetSpeed
			else
				targetSpeed = dist / (obj.frame - obj.lastframe)
			end
		end
	end
	local weapRanges = WG.weapRanges
	for attID, defID in pairs(obj.attackers) do
		local posOrder = posOrder			
		if not posOrder then
			local attackerSpeed = speedDefs[defID]
			local px, _, pz = spGetUnitPosition(attID)
			if not px then
				RemoveAttacker(id ,obj)
			else
				local radius = weapRanges[defID][1]
				local ix, iz, t = ComputeInterceptPointBounded(px, pz, attackerSpeed, x, z, dx2D * targetSpeed, dz2D * targetSpeed, radius)
				if ix then
					if t > maxTimePursue then
						local reduce = maxTimePursue / t
						ix, iz = px + (ix - px) * reduce, pz + (iz - pz) * reduce
					end
					ix, iz = ClampToRadius(x, z, ix, iz, maxLeadRadius)
					---- never go closer than the distance to target 
					local dx, dz = x - px, z - pz
					local len = diag(dx, dz)
					-- local dNow = max(len - radius, 0)
					local dNow = len
					if diag(ix - px, iz - pz) < dNow then
						ix, iz = px + dx / len * dNow, pz + dz / len * dNow
					end
					----
					local iy = spGetGroundHeight(ix, iz)
					posOrder = {ix, iy, iz}
				end
			end
		end
		if not posOrder then
			posOrder = copypos
		end
		Order(attID, CMD_RAW_MOVE, posOrder)
	end
end


function widget:UnitLeftRadar(id, teamID, forAlly, defID)

	local obj = attacked[id]
	if not obj then
		return
	end
	obj.inradar = false
	if spGetUnitIsDead(id) then -- UnitDestroyed doesn't trigger if enemy is not in Los
		RemoveAttacked(id, obj, true)
		return
	end
	obj.stabilize = 6
	-- Echo(id..' left radar')

end


function widget:UnitEnteredRadar(id, teamID, forAlly, defID)
	local obj = attacked[id]
	if obj then
		obj.wantPursue = false
		obj.inradar = true
		obj.stabilize = 1
	end
end

function widget:UnitEnteredLos(id, teamID, forAlly, defID)
	local obj = attacked[id]
	if obj then
		if not obj.targetDefID then
			obj.targetDefID = spGetUnitDefID(id)
		end
		obj.inlos = true
	end
end

function widget:UnitLeftLos(id, teamID, forAlly, defID)
	local obj = attacked[id]
	if obj then
		obj.inlos = false
	end
end

local orderOwner = false

function widget:UnitCommand(id, defID, teamID, cmdID, params, opts, tag, fromSynced, fromLua)
	if debugging then
		Echo('-- Received '..f.cmdNames[cmdID], params[1])
	end
	if cmdID > 1e6 then
		orderOwner  = GetSignedWidget(cmdID)
		if not orderOwner then
			-- Echo('Error, a widget signature has been missed for unit', unitID, UnitDefs[defID].name, teamID, 'sig:', cmdID)
		end
		return
	else
		if attackerInit[id] and cmdID ~= CMD_ATTACK then
			if debugging then
				Echo('RECEIVED ANOTHER ORDER', f.cmdNames[cmdID])
			end
			return
		end
		local handled = orderOwner == widget
		if not handled then
			handled = attackerInit[id]
			if debugging then
				Echo('Init =>', f.cmdNames[cmdID], handled, 'attacking', attacking[id])
			end
			if handled then
				handled = handled - 1
				if handled == 0 then
					attackerInit[id] = nil
				else
					attackerInit[id] = handled
				end
				orderBuffer[id] = {waiting = true, CMD_ATTACK, {params[1]}}
			end
		end
		orderOwner = false
		if handled then
			if cmdID == CMD_REMOVE then
				----- Echo('-- Received REMOVE Order for tag '..params[1])
			elseif cmdID == CMD_STOP then
				--
			else
				local obj = attacking[id]
				if not obj then
					if debugging then
						Echo('['..currentFrame..']' .. 'Received '..f.cmdNames[cmdID].. ' but the attacker got deleted, current order', spGetUnitCurrentCommand(id))
					end
					return
				end
				if cmdID == CMD_ATTACK and not obj.inradar then
					-- by the time the order is received, the target has gone off radar
					-- the ATTACK order will be ignored in the same frame, and verifiable in UnitCmdDone()
					-- however the previous RAW_MOVE will be cancelled
					-- If we give again a RAW_MOVE at the same place it will bug and the unit will not move even though having the command apparently correct
					-- To fix this we place a STOP before
					-- and we ask for the next frame to refresh every attackers
					local cmd, opt, tag, p1, p2, p3 = spGetUnitCurrentCommand(id)
					if debugging then
						Echo('['..currentFrame..']' .. ' Received CMD_ATTACK out of radar <== Ignored ==>', 'current order', cmd, opt, tag, p1, p2 or '', p3 or '')
						Echo('\t\t=> sending immediate stop and pursue at next frame')
					end
					SendSignedOrderToUnit(widget, id, CMD_STOP, 0, 0)
					local bufferedOrder = orderBuffer[id]
					if not bufferedOrder then
						bufferedOrder = {nil, {}}
						orderBuffer[id] = bufferedOrder
					end
					bufferedOrder.waiting = false
					bufferedOrder[1] = 0
					bufferedOrder[2][1], bufferedOrder[2][2], bufferedOrder[2][3] = 0, nil, nil
					orderBuffer[id].waiting = false
					obj.stabilize = 1
				else
					Order(id, cmdID, params, true)
				end
			end
			return
		else
			-- f.DebugUnitCommand(id, defID, teamID, cmdID, params, opts, tag, fromSynced, fromLua)
		end
	end
	------
	local obj = attacking[id]
	if obj and not attackerInit[id] then
		if debugging then
			Echo('unsigned order received', f.cmdNames[cmdID], '#'..#params)
		end
		RemoveAttacker(id, obj, true)
	end
	-- f.DebugUnitCommand(id, defID, teamID, cmdID, params, opts, tag, fromSynced, fromLua)
end

-- engine bug I guess.
-- UnitDestroyed doesn't trigger if the unit is not in Los, but we can still know it in UnitLeftRadar() via spGetUnitIsDead()
function widget:UnitDestroyed(id, defID, teamID)
	-- Echo('destroyed '..id)
	local obj = attacked[id]
	if obj then
		RemoveAttacked(id, obj)
		return
	end
	obj = attacking[id]
	if obj then
		RemoveAttacker(id, obj)
	end
end

function widget:GameFrame(f)
	currentFrame = f
	for id, obj in pairs(attacked) do
		if obj.inradar and (obj.updateNow or f > obj.frame + updateRate) then
			local x, y, z = spGetUnitPosition(obj.targetID)

			if x then
				if obj.wasInLos ~= obj.inlos then
					obj.temppos = {x, y, z}
					obj.updateNow = true
				else
					local pos = obj.pos
					local lastpos = obj.lastpos
					local temp = obj.temppos
					if temp then
						lastpos[1], lastpos[2], lastpos[3] = temp[1], temp[2], temp[3]
						obj.temppos = false
					else
						lastpos[1], lastpos[2], lastpos[3] = pos[1], pos[2], pos[3]
					end
					pos[1], pos[2], pos[3] = x, y, z
				end
			end
			obj.updateNow = false
			obj.lastframe = obj.frame
			obj.wasInLos = obj.inlos
			obj.frame = f
		end
		if obj.stabilize then
			obj.stabilize = obj.stabilize - 1
			if obj.stabilize == 0 then
				obj.stabilize = false
				if obj.inradar then
					local attackParam = {obj.targetID}
					for id in pairs(obj.attackers) do
						if not spValidUnitID(id) then
							RemoveAttacker(id, obj)
						else
							Order(id, CMD_ATTACK, attackParam)
						end
					end
				else
					PursueTarget(id, obj)
				end
			end
		end
	end
end


local red, blue, green, teal, yellow = f.COLORS.red, f.COLORS.blue, f.COLORS.green, f.COLORS.teal, f.COLORS.yellow
local function GetSimulation(id, obj, forceZero)
	if not next(obj.attackers) then
		return
	end
	local lines, l = {}, 0
	local function newLine(p1, p2, color)
		l = l + 1
		lines[l] = {v = p1, c = color}
		l = l + 1
		lines[l] = {v = p2, c = color}
	end
	local pos, lastpos = obj.pos, obj.lastpos
	local x, y, z = pos[1], pos[2], pos[3]
	local copypos = {x, y, z}

	if (x == lastpos[1] and z == lastpos[3]) then
		for attID, defID in pairs(obj.attackers) do
			local px, py, pz = spGetUnitPosition(attID)
			newLine({px, py, pz}, copypos)
		end
		return
	end
	local dx2D, dz2D, targetSpeed

	local dx, dy, dz = x - lastpos[1], pos[2] - lastpos[2], z - lastpos[3]
	local dist = diag(dx, dy, dz)
	local nx, ny, nz = dx / dist, dy / dist, dz / dist
	-- Echo("dist", dist, "nx, nz is ", nx, nz, 'v3D', diag(nx, ny, nz))
	local nlen2D = diag(nx, nz)
	dx2D, dz2D = nx / nlen2D, nz / nlen2D
	targetSpeed = obj.targetSpeed
	if not targetSpeed then
		if obj.targetDefID then
			targetSpeed = speedDefs[obj.targetDefID]
			obj.targetSpeed = targetSpeed
			-- Echo('got defID, speed: ', targetSpeed)
		else
			targetSpeed = dist / (obj.frame - obj.lastframe)
			-- Echo('no defID, speed: ', targetSpeed)
		end
	end
	local weapRanges = WG.weapRanges
	for attID, defID in pairs(obj.attackers) do
		local attackerSpeed = speedDefs[defID]
		local px, py, pz = spGetUnitPosition(attID)
		local attpos = {px, py, pz}
		local radius = weapRanges[defID][1]
		local ix, iz, t = ComputeInterceptPointBounded(px, pz, attackerSpeed, x, z, dx2D * targetSpeed, dz2D * targetSpeed, forceZero and 0 or radius)
		if ix --[[and diag(ix - px, iz - pz) > diag(x - px, z - pz)]] then
			-- ix, iz = math.clamp(ix, 1, Game.mapSizeX - 1), math.clamp(iz, 1, Game.mapSizeZ - 1)
			local iy = spGetGroundHeight(ix, iz)
			newLine(attpos, {ix, iy, iz}, blue)
			if t > maxTimePursue then
				local ratio = maxTimePursue / t
				ix, iz = px + (ix - px) * ratio, pz + (iz - pz) * ratio
				iy = spGetGroundHeight(ix, iz)
				newLine(attpos, {ix, iy, iz}, red)
			end
			local _ix, _iz
			_ix, _iz = ClampToRadius(x, z, ix, iz, maxLeadRadius)
			if _ix ~= ix or _iz ~= iz then
				ix, iz = _ix, _iz
				iy = spGetGroundHeight(ix, iz)
				newLine(attpos, {ix, iy, iz}, green)
				posOrder = {ix, iy, iz}
			end
			---- never go closer than the distance to target 
			local dx, dz = x - px, z - pz
			local len = diag(dx, dz)
			-- local dNow = max(len - radius, 0)
			local dNow = len
			if diag(ix - px, iz - pz) < dNow then
				ix, iz = px + dx / len * dNow, pz + dz / len * dNow
				iy = spGetGroundHeight(ix, iz)
				newLine(attpos, {ix, iy, iz}, teal)
				posOrder = {ix, iy, iz}
			end
			----
		else
			newLine(attpos, yellow)
		end
	end
	return lines
end


function widget:DrawScreen()
	glColor(0,0,1,1)
	for id, obj in pairs(attacking) do
		if spIsUnitInView(id) then
			local x, y, z = spGetUnitPosition(id)
			if x then
				x, y = spWorldToScreenCoords(x, y, z)
				gluDrawScreenDisc(x, y, 2, 12)
				glColor(0,1,1,1)
				gluDrawScreenDisc(x, y, 1, 12)
				glColor(0,0,1,1)
			end
		end
	end
	glColor(1,1,1,1)
end


function widget:DrawWorld()
	glLineWidth(1)
	glLineStipple(true)
	for id, obj in pairs(attacked) do
		local lines = GetSimulation(id, obj)
		if lines and lines[1] then
			gl.Shape(GL.LINES, lines)
		end
	end
	glColor(1,1,1,1)
	glLineStipple(false)
end




function widget:SelectionChanged()
	selChanged = true
end

function widget:CommandsChanged()
	if not selChanged then
		return
	end
	gotAttackers = false
	clear(selectedAttackers)
	for i, id in ipairs(WG.selection or spGetSelectedUnits()) do
		local obj = attacking[id]
		if obj then
			selectedAttackers[id] = obj
			gotAttackers = true
		end
	end
end

function widget:CommandNotify(cmd, params, opt)
	if cmd == CMD_ATTACK and params[1] and not params[2] and opt.coded == CMD_OPT_RIGHT then
		for defID, units in pairs(WG.selectionDefID or spGetSelectedUnitsSorted()) do
			if canAttack[defID] then
				for i, id in ipairs(units) do
					local obj = AddAttacked(id, defID, params[1])
					selectedAttackers[id] = obj
				end
				gotAttackers = true
			end
		end
	elseif gotAttackers then
		for id, obj in pairs(selectedAttackers) do
			RemoveAttacker(id, obj)
			selectedAttackers[id] = nil
		end
		gotAttackers = false
	end
end

function widget:UnitCommandNotify(id, defID, teamID, cmd, params, opt)
	if cmd == CMD_ATTACK and params[1] and not params[2] and opt.coded == CMD_OPT_RIGHT then
		local obj = AddAttacked(id, defID, params[1])
		selectedAttackers[id] = obj
		gotAttackers = true
	elseif gotAttackers then
		local obj = selectedAttackers[id]
		if obj then
			RemoveAttacker(id, obj)
			selectedAttackers[id] = nil
		end
	end
end


function widget:Initialize()
	SendSignedOrderToUnit = WG.SendSignedOrderToUnit
	GetSignedWidget = WG.GetSignedWidget
	SendWidgetSignature = WG.SendWidgetSignature
	widgetHandler:RemoveWidgetCallIn('DrawWorld', widget)
	widgetHandler:RemoveWidgetCallIn('DrawScreen', widget)
end

f.DebugWidget(widget)