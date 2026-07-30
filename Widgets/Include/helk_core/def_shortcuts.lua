if WG.commDefID then
	return
end

local GUNSHIP_MOVE_TYPE = 1
local spuGetMoveType = Spring.Utilities.getMovetype
local airpadDefs = VFS.Include("LuaRules/Configs/airpad_defs.lua", nil, VFS.GAME)


local canAttackDefID = {}
local airAttackerDefID = {}
local bomberDefID = {}
local planeDefID = {}
local gunshipDefID = {}
local airpadDefID = {}
local immobileDefID = {}
local factoryDefID = {}
local energyDefID = {}
local turretDefID = {}
local jumperDefID = {}
local bombDefID = {}
local commDefID = {}
local conDefID = {}
local controllableRepairerDefID = {}
local controllableRepairerDefIDIndex = {}
local impulseDefID = {}


for defID, def in pairs(UnitDefs) do
	---- CAN ATTACK
	if def.canAttack then
		canAttackDefID[defID] = true
	end

	-- AIR
	if def.isAirUnit and def.canAttack then
		airAttackerDefID[defID]=true
	end
	if def.isBomber or def.isBomberAirUnit or def.customParams.reallyabomber then
		-- Echo("def.name is ", def.name, def.isBomber and 'isBomber' or def.isBomberAirUnit and 'isBomberAirUnit' or def.customParams.reallyabomber and 'reallyabomber')
		bomberDefID[defID] = true
		planeDefID[defID] = true
	elseif spuGetMoveType(def) == GUNSHIP_MOVE_TYPE then -- def.isHoveringAirUnit can work too
		gunshipDefID[defID] = true
	elseif def.canFly then
		planeDefID[defID] = true
	elseif airpadDefs[defID] then
		airpadDefID[defID] = true
	end
	-- IMMOBILE
	if def.isImmobile then -- same as (not spuGetMoveType(def))
		immobileDefID[defID] = true
		if def.name == 'striderhub' or def.isFactory and def.name ~= 'staticrearm'  then -- NOTE airpad got .isFactory (should FIX)
			factoryDefID[defID] = true
		elseif def.name:find('^energy') then -- TODO make it more accurate
			energyDefID[defID] = true
		end
		if def.canAttack then
			turretDefID[defID] = true
		end
	---- JUMPER
	elseif def.customParams.canjump then
		if not (def.name:match('plate') or def.name:match('factory')) then
			jumperDefID[defID] = true
		end
	---- BOMBS
	elseif def.name:match('bomb$') or def.name:find('_egg') then
		bombDefID[defID] = true
	end
	---- COMM/CON
	-- if (name:find('^dyn') or name:find('c%d+_base') or name:find('com%d+$') or (name:find('comm') and not name:find('egg')) or name:find('^hero')) then 
	if def.customParams.dynamic_comm or def.customParams.level then
		commDefID[defID] = true
	elseif not def.isImmobile and def.buildOptions[1] then
		conDefID[defID] = true
	end

	---- IMPULSE
	for _, w in pairs(def.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and (wd.customParams or {}).impulse then
			impulseDefID[defID] = true
			break
		end
	end
	---- CONTROLLABLE REPAIRER
	if def.canRepair and not def.isBuilding then -- NOTE: strider hub and caretaker doesn't have .isBuilding, so it's good for us, but if it has in the futur, we need to change this
		controllableRepairerDefID[defID] = true
		table.insert(controllableRepairerDefIDIndex, defID)
	end
	
end


WG.canAttackDefID = canAttackDefID
WG.airAttackerDefID = airAttackerDefID
WG.bomberDefID = bomberDefID
WG.planeDefID = planeDefID
WG.gunshipDefID = gunshipDefID
WG.airpadDefID = airpadDefID
WG.immobileDefID = immobileDefID
WG.factoryDefID = factoryDefID
WG.energyDefID = energyDefID
WG.turretDefID = turretDefID
WG.jumperDefID = jumperDefID
WG.bombDefID = bombDefID
WG.commDefID = commDefID
WG.conDefID = conDefID
WG.impulseDefID = impulseDefID
WG.controllableRepairerDefID = controllableRepairerDefID
WG.controllableRepairerDefIDIndex = controllableRepairerDefIDIndex


local fakeIDTable = {id = -1}
WG.puppyDefID = (UnitDefNames['jumpscout'] or fakeIDTable).id
WG.lobsterDefID = (UnitDefNames['amphlaunch'] or fakeIDTable).id
WG.widowDefID = (UnitDefNames['spiderantiheavy'] or fakeIDTable).id
WG.revDefID = (UnitDefNames['gunshipassault'] or fakeIDTable).id
WG.krowDefID = (UnitDefNames['gunshipkrow'] or fakeIDTable).id
WG.impalerDefID = (UnitDefNames['vehheavyarty'] or fakeIDTable).id
WG.athenaDefID = (UnitDefNames['athena'] or fakeIDTable).id
WG.transportDefID = (UnitDefNames['gunshiptrans'] or fakeIDTable).id
WG.heavyTransportDefID = (UnitDefNames['gunshipheavytrans'] or fakeIDTable).id
WG.terraunitDefID = (UnitDefNames['terraunit'] or fakeIDTable).id
WG.airDgunDefID = { -- TODO make it less arbitrary
	[(UnitDefNames['bomberassault'] or fakeIDTable).id] = true,   
}


WG.minRadius, WG.maxRadius = (function()
	local minRadius, maxRadius = 0, math.huge
	for defID, def in pairs(UnitDefs) do
		local radius = def.radius
		if maxRadius < radius then
			maxRadius = radius
		end
		if minRadius > radius then
			minRadius = radius
		end
	end
	return minRadius, maxRadius
end)()

Spring.Echo('[Hel-K]: Successfully loaded def shortcuts.')