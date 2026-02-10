-- emulates engine range circles. By very_bad_soldier and versus666
-- corrected and completed by Helwor
local max   = math.max
local abs   = math.abs
local cos   = math.cos
local sin   = math.sin
local sqrt  = math.sqrt
local pi    = math.pi
local clamp = math.clamp
local floor = math.floor
local modf = math.modf
local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ
local spGetGroundHeight = Spring.GetGroundHeight

local GAME_GRAVITY = Game.gravity / (Game.gameSpeed^2)
local spfactor = 0.7071067 -- projectileSpeed factor


local SetCannonParams, SetRange2DWeapon, GetRange2DCannon, GetRange2DWeapon
do

	local range, speed2d, speed2dSq, gravity, heightBoostFactor, rangeFactor
	function SetRange2DWeapon(_range)
		range = _range
	end
	function GetRange2DWeapon(yDiff)
		if yDiff > range  or -yDiff > range then
			return 0
		end
		return sqrt(range * range - yDiff * yDiff)
	end
	function SetCannonParams(_range, _speed2d, _speed2dSq, _gravity, _heightBoostFactor, _rangeFactor)
		range, speed2d, speed2dSq, gravity, heightBoostFactor, rangeFactor
		= _range, _speed2d, _speed2dSq, _gravity, _heightBoostFactor, _rangeFactor

		rangeFactor =  range / ((speed2dSq + speed2d * sqrt(speed2dSq)) / gravity)
		
		if rangeFactor > 1.0 or rangeFactor <= 0.0 then
			rangeFactor = 1.0
		end
		if heightBoostFactor < 0 then
		    heightBoostFactor = (2.0 - rangeFactor) / sqrt(rangeFactor)
		end
	end
	function GetRange2DCannon(yDiff)
		local smoothHeight = 100.0

		if yDiff < -smoothHeight then
			yDiff = yDiff * heightBoostFactor
		elseif yDiff < 0.0 then
			yDiff = yDiff * (1.0 + (heightBoostFactor - 1.0) * -yDiff / smoothHeight)
		end
		local down = 2 * gravity * yDiff
		if down > speed2dSq then
			return 0
		end
		return rangeFactor * (speed2dSq + speed2d * sqrt(speed2dSq - down)) / gravity
	end
end
-- local done = {}
local total = 0
local totalsincos = 0
local count = 0
local timer

local sinCosCache = {}
local function GetSinCosTables(divs)
    if not sinCosCache[divs] then
        local s, c = {}, {}
        for i = 1, divs do
            local rad = 2 * pi * i / divs
            s[i] = sin(rad)
            c[i] = cos(rad)
            -- totalsincos = totalsincos + 1
        end
        sinCosCache[divs] = {s, c}
    end
    return sinCosCache[divs][1], sinCosCache[divs][2]
end
local groundCache = {}
local function GetGroundHeightCached(x, z)
    local ix, iz = floor(x), floor(z)
    local key = ix * 65536 + iz
    local h = groundCache[key]
    if h == nil then
        h = spGetGroundHeight(x, z)
        groundCache[key] = h
    end
    return h
end
local function CalcBallisticCircle( x, y, z, range, wDef)
	-- count = count + 1
	-- For best accuracy, coords has to be the aimFrom piece coords (but weapon may move to aim)
	-- Engine bug: the unit start aiming when a target is in reach of the weapon current pos
	-- fallback to aimpos with spGetUnitPosition(unitID, true, true) (again, unit may not be deployed at this time)
	-- fallback to ground pos +  def.model.midy + (def.aimposoffset or 0) if unit doesnt exist, aimposoffset is a string "x y z".
	-- workaround: I made own hard coded table where I registered y offset of weapons and aim piece by weapon num, which is overall a better option but still far from perfect as tested unit may be inclined, or/and weapon offset X and Z ~= 0
	local rangeLineStrip = {}
	-- local slope = 0.0

	local wType, wName, heightMod = wDef.type, wDef.name, wDef.heightMod
	local projectilespeed = wDef.projectilespeed
	if wType == "LaserCannon" then
	    range = max(1.0, floor(range / projectilespeed)) * projectilespeed
	elseif wName and wType == 'Cannon' and wName:find('blast') then -- for outlaw 
		wType = 'StarburstLauncher'
	end

	if wType == "Cannon" then
		local speed2d = projectilespeed * spfactor
		SetCannonParams(range, speed2d, speed2d * speed2d, wDef.myGravity or GAME_GRAVITY, wDef.heightBoostFactor or -1, 1.0)
		rangefunc = GetRange2DCannon
	else
		SetRange2DWeapon(range)
		rangefunc = GetRange2DWeapon
		if wType == 'Shield' or wType == 'StarburstLauncher' then 
			heightMod = 1
		end
	end

	local divs, steps --  = 40, 49
	divs = clamp(floor((range^0.5 * 1.5) / 30) * 30, 30, 200)
	steps = clamp(modf(range^0.5 * 2), 20, 30)

	local sins, coss = GetSinCosTables(divs)
	for i = 1, divs do

		local rAdj = range

		local sinR = sins[i] -- TEST IF REALLY HELP
		local cosR = coss[i]
		local posx = clamp(x + sinR * rAdj, 0, mapSizeX)
		local posz = clamp(z + cosR * rAdj, 0, mapSizeZ)
		-- local posx = x + sinR * rAdj
		-- local posz = z + cosR * rAdj
		local posy = spGetGroundHeight(posx, posz)

		local heightDiff = (posy - y) --/ 2.0 

		-- rAdj = rAdj - heightDiff * slope
		local adjRadius = rangefunc(heightDiff * heightMod)
		local adjustment = rAdj / 2.0
		local yDiff = 0.0
		local oriAdj = adjRadius
		for j = 0, steps do
			-- if total%100000 == 0 then
			-- 	if total == 0 then
			-- 		timer = Spring.GetTimer()
			-- 	else
			-- 		Echo(total/100000, Spring.DiffTimers(Spring.GetTimer(), timer), 'average', total / count, 'total sincos', totalsincos, 'cur divs', divs)
			-- 	end
			-- end
			-- total = total + 1
			if ( abs( adjRadius - rAdj ) + yDiff <= 0.01 * rAdj ) then
				break
			end

			if ( adjRadius > rAdj ) then
				rAdj = rAdj + adjustment
			else
				rAdj = rAdj - adjustment
				adjustment = adjustment / 2.0
			end
			posx = clamp(x + sinR * rAdj, 0, mapSizeX)
			posz = clamp(z + cosR * rAdj, 0, mapSizeZ)
			-- posx = x + sinR * rAdj
			-- posz = z + cosR * rAdj
			local newY = spGetGroundHeight( posx, posz )
			yDiff = abs( posy - newY )
			posy = newY
			posy = max( posy, 0.0 )  --hack
			heightDiff = ( posy - y )	
			adjRadius = rangefunc(heightDiff * heightMod)
		end

		posx = clamp(x + sinR * rAdj, 0, mapSizeX)
		posz = clamp(z + cosR * rAdj, 0, mapSizeZ)
		-- posx = x + sinR * rAdj
		-- posz = z + cosR * rAdj

		posy = spGetGroundHeight( posx, posz ) + 5.0
		posy = max( posy, 0.0 )   --hack

		rangeLineStrip[i] = { posx, posy, posz }
	end
	return rangeLineStrip
end

return CalcBallisticCircle


