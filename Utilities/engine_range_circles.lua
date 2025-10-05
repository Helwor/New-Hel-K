-- emulates engine range circles. By very_bad_soldier and versus666
-- corrected and completed by Helwor
local max   = math.max
local abs   = math.abs
local cos   = math.cos
local sin   = math.sin
local sqrt  = math.sqrt
local pi    = math.pi

local spGetGroundHeight = Spring.GetGroundHeight

local function GetRange2DWeapon(range, yDiff)
	local adjRadius = sqrt(range * range - yDiff * yDiff)
	if yDiff > range  or -yDiff > range then
		return 0
	end
	return sqrt(range * range - yDiff * yDiff)
end

local GAME_GRAVITY = Game.gravity / (Game.gameSpeed^2)
local function GetRange2DCannon( range, yDiff, projectileSpeed, rangeFactor, myGravity )
	local factor = 0.7071067
	local smoothHeight = 100.0
	local speed2d = projectileSpeed * factor
	local speed2dSq = speed2d * speed2d
	local gravity = myGravity or GAME_GRAVITY
	local heightBoostFactor = (2.0 - rangeFactor) / sqrt(rangeFactor)

	if yDiff < -smoothHeight then
		yDiff = yDiff * heightBoostFactor
	elseif yDiff < 0.0 then
		yDiff = yDiff * (1.0 + (heightBoostFactor - 1.0) * -yDiff / smoothHeight)
	end
	local down = 2 * gravity * yDiff
	if gravity == 0 then
		return 0
	elseif down > speed2dSq then
		return 0
	end
	return rangeFactor * (speed2dSq + speed2d * sqrt(speed2dSq - down)) / gravity
end
-- local done = {}
local function CalcBallisticCircle( x, y, z, range, wDef)
	-- for best accuracy, coords has to be the aimFrom piece coords
	local rangeLineStrip = {}
	local slope = 0.0

	local rangeFunc = GetRange2DWeapon
	local rangeFactor = 1.0 -- used by range2dCannon
	local wType, heightMod, projectilespeed, myGravity, wName = wDef.type, wDef.heightMod, wDef.projectilespeed, wDef.myGravity, wDef.name
	-- projectilespeed, myGravity = 18, 0.13
	if wName and wName:find('blast') then
		wType = 'StarburstLauncher'
	end
	if wType == "Cannon" then
		rangeFunc = GetRange2DCannon
		rangeFactor = range / GetRange2DCannon(range, 0.0, projectilespeed, rangeFactor, myGravity )
		if rangeFactor > 1.0 or rangeFactor <= 0.0 then
			rangeFactor = 1.0
		end
	elseif wType == 'Shield' or wType == 'StarburstLauncher' then -- TODO: verify other types aswell
		heightMod = 1
	end
	-- Echo("wType, heightMod is ", wType, heightMod, projectilespeed, myGravity)
	local divs, steps = 40, 49
	if range < 1000 then
		divs = max(math.modf(range / 25), 16)
		steps = max(math.modf(range / 20.5), 5)
	end
	-- if not done[range] then
	-- 	done[range] = true
	-- 	Echo('range', range, 'divs,', divs, 'steps', steps)
	-- end
	for i = 1, divs do
		local radians = 2.0 * pi * i / divs
		local rAdj = range

		local sinR = sin(radians)
		local cosR = cos(radians)

		local posx = x + sinR * rAdj
		local posz = z + cosR * rAdj
		local posy = spGetGroundHeight(posx, posz)

		local heightDiff = (posy - y) / 2.0 

		rAdj = rAdj - heightDiff * slope
		local adjRadius = rangeFunc( range, heightDiff * heightMod, projectilespeed, rangeFactor, myGravity )
		local adjustment = rAdj / 2.0
		local yDiff = 0.0
		local oriAdj = adjRadius
		for j = 0, steps do
			if ( abs( adjRadius - rAdj ) + yDiff <= 0.01 * rAdj ) then
				break
			end

			if ( adjRadius > rAdj ) then
				rAdj = rAdj + adjustment
			else
				rAdj = rAdj - adjustment
				adjustment = adjustment / 2.0
			end
			posx = x + ( sinR * rAdj )
			posz = z + ( cosR * rAdj )
			local newY = spGetGroundHeight( posx, posz )
			yDiff = abs( posy - newY )
			posy = newY
			posy = max( posy, 0.0 )  --hack
			heightDiff = ( posy - y )	
			adjRadius = rangeFunc( range, heightDiff * heightMod, projectilespeed, rangeFactor, myGravity, yDiff )
		end

		posx = x + ( sinR * adjRadius )
		posz = z + ( cosR * adjRadius )
		if not pcall(spGetGroundHeight, posx, posz) then
			Echo(os.clock(), 'BREAK DOWN', wName, wType, projectilespeed, rangeFactor, myGravity, yDiff, sinR, heightDiff, heightMod, adjRadius, cosR, range, heightDiff * heightMod, projectilespeed, oriAdj, rangefunc == GetRange2DCannon)
		end
		posy = spGetGroundHeight( posx, posz ) + 5.0

		posy = max( posy, 0.0 )   --hack

		rangeLineStrip[i] = { posx, posy, posz }
	end
	return rangeLineStrip
end

return CalcBallisticCircle
