function widget:GetInfo()
	return {
		name      = "API Placement building Replacer",
		desc      = "Replace building placement of the engine for rescaled models and modified placement position"
					.."\nService via WG.ReplaceBuildingPlacement(defID, teamID, facing, engPosX, engPosY, engPosZ,  px, py, pz, scale)",
		author    = "Helwor",
		version   = "v1",
		date      = "nov 2026",
		license   = "GNU GPL, v2 or later",
		layer     = 999, -- after PBH
		enabled   = true,
	}
end

local debugging = false

local spGetActiveCommand = Spring.GetActiveCommand
local spGetBuildFacing = Spring.GetBuildFacing
local spGetMouseState = Spring.GetMouseState
local spGetMyTeamID = Spring.GetMyTeamID
local spTraceScreenRay = Spring.TraceScreenRay
local spGetGroundHeight = Spring.GetGroundHeight

local glDepthTest = gl.DepthTest
local glPushMatrix = gl.PushMatrix
local glTranslate = gl.Translate
local glScale = gl.Scale
local glPopMatrix = gl.PopMatrix
local glColor = gl.Color

local floor = math.floor

local UnitDefs = UnitDefs

local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ

local rescaleUnitDefIDs = {}
local offsetUnitDefIDs = {}
for i = 1, #UnitDefs do
	local scale = tonumber(UnitDefs[i].customParams.model_rescale)
	local offset = tonumber(UnitDefs[i].customParams.model_zoffset)
	if scale and scale ~= 1 and scale > 0 then
		rescaleUnitDefIDs[i] = scale
	end
	if offset and offset ~= 0 then
		offsetUnitDefIDs[i] = offset
	end
end


local function GetPlacementCoords(defID, x, y, z, facing, placementHeight)
	local offFacing = (facing == 1 or facing == 3)
	
	local def = UnitDefs[defID]
	local footX = def.xsize/2
	local footZ = def.zsize/2
	
	if offFacing then
		footX, footZ = footZ, footX
	end
	
	local oddX = (footX%2)*8
	local oddZ = (footZ%2)*8
	
	local pointX = floor((x + 8 - oddX)/16)*16 + oddX
	local pointZ = floor((z + 8 - oddZ)/16)*16 + oddZ
	local pointY = spGetGroundHeight(pointX, pointZ)
	if def.floatOnWater and pointY < 0 then
		pointY = 0
	end
	return pointX, pointY, pointZ
end

local function ReplaceBuildingPlacement(defID, teamID, facing, engPosX, engPosY, engPosZ,  px, py, pz, scale)
	teamID = teamID or 0
	facing = facing or 0
	scale = scale or 1

	glDepthTest(true)

	-- gl.Blending(GL.SRC_ALPHA, GL.ONE) -- glowy blending
	-------------
	-- it's a bit circumvoluted but I didnt find an easier way to suppress the engine build ghost to replace it with mine
	-- First we mark the stencil with the build shape while respecting the depth
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	gl.StencilTest(true)
	gl.StencilOp(GL.KEEP, GL.KEEP, GL.INCR)
	gl.StencilFunc(GL.EQUAL, 0, 1)
	gl.ColorMask(false, false, false, true)
	if engPosX then
		glPushMatrix()
		glTranslate(engPosX, engPosY, engPosZ)
		gl.Rotate((facing or 0) * 90, 0, 1, 0)
		gl.UnitShape(defID, teamID, true, true, true)
		glPopMatrix()
	end

	-- then we draw aswell our scaled/shifted model to mark also the stencil with it
	glPushMatrix()
	glTranslate(px, py, pz)
	gl.Rotate((facing or 0) * 90, 0, 1, 0)
	glScale(scale, scale, scale)
	gl.UnitShape(defID, teamID, true, true, true)
	glPopMatrix()
	-------------
	-- then we temporary stop the stencil test to make a box just a little larger than the model to avoid z fighting
	-- that box will become 'solid' through gl.DepthMask, that way the engine build will not be drawn because greater than the new depth we create*
	-- new and better: instead of box, making a larger model to envelop it with polygon offset
	gl.StencilTest(false)

	gl.DepthMask(true)

	gl.UnitShape(defID, 0, true, true, true)
	if engPosX then
		glPushMatrix()
		glTranslate(engPosX, engPosY, engPosZ)
		gl.Rotate((facing or 0) * 90, 0, 1, 0)
		---- old using box
		-- local model = UnitDefs[defID].model
		-- gl.Utilities.DrawMyBox(model.minx - 1 , model.miny - 1  , model.minz - 1 , model.maxx + 1 , model.maxy + 1 , model.maxz + 1 )
		---- better with model using polygon offset
		gl.PolygonOffset(-1, -1)
		gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
		gl.UnitShape(defID, teamID, true, true, true)
		gl.PolygonOffset(false)
		glPopMatrix()
	end

	gl.DepthMask(false)
	-------------
	-- finally we take back our stencil test to draw our resized/shifted ghost, the ghost won't respect the depth so it will be drawn despite our solid box
	-- but it will have to respect our stencil, which is respecting the original ground depth, so our ghost will not appear through the terrain
	gl.StencilTest(true)
	gl.DepthTest(GL.ALWAYS)
	gl.StencilOp(GL.KEEP, GL.KEEP, GL.KEEP)
	gl.ColorMask(true, true, true, true)
	gl.StencilFunc(GL.EQUAL, 1, 1)
	
	-- ghost
	glPushMatrix()
	glTranslate(px, py, pz)
	gl.Rotate((facing or 0) * 90, 0, 1, 0)
	glScale(scale, scale, scale)
	gl.UnitShape(defID, teamID, false, true, false)
	glPopMatrix()
	------------- done
	gl.StencilTest(false)
	gl.DepthTest(GL.LEQUAL)


	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA) -- 
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	glDepthTest(false)
	glColor(1, 1, 1, 1)
end

function widget:DrawWorld()
	local defID = select(2, spGetActiveCommand())
	if (defID or 0) < 0 then
		defID = -defID
		local def = UnitDefs[defID]
		local mx, my = spGetMouseState()
		if mx then
			local scale = rescaleUnitDefIDs[defID]
			local offset = false and offsetUnitDefIDs[defID] -- I don't understand, but the offset is not needed, it's already taken into account
			local facing = spGetBuildFacing()
			local placementHeight = WG.placementHeight or WG.buildingPlacementHeight or 0
			local placementX, placementY, placementZ = WG.placementX, WG.placementY, WG.placementZ
			local engPosX, engPosY, engPosZ
			local kind, pos = spTraceScreenRay(mx, my, true, true, true, not def.floatOnWater) -- mx, my, onlyCoords, useMinimap, includeSky, throughWater
			if kind == "sky" then
				if pos[4] < 0 or pos[4] > mapSizeX or pos[6] < 0 or pos[6] > mapSizeZ then
					pos = false
				else
					pos[1], pos[2], pos[3] = pos[4], pos[5], pos[6]
				end
			end
			if pos then
				engPosX, engPosY, engPosZ = GetPlacementCoords(defID, pos[1], pos[2], pos[3], facing, placementHeight)
			end
			local needed = (engPosX or placementX) and (scale or offset or placementHeight ~= 0)
				or placementX and (engPosX ~= placementX or engPosY ~= placementY or engPosZ ~= placementZ) -- hel-k user

			if debugging then				
				local test = ((engPosX or placementX) and (scale or offset or placementHeight ~= 0) and 'A' or '')
					.. (engPosX and 'E' or '')
					.. (placementX and (engPosX ~= placementX or engPosY ~= placementY or engPosZ ~= placementZ) and 'P' or '')
				Echo('test ' .. test .. ' needed ' .. tostring(needed), 'X',engPosX, placementX, 'Y', engPosY, placementY, 'Z', engPosZ, placementZ,'\n',"kind:"..tostring(kind), unpack(pos or {}))
			end

			if needed then
				offset = offset or 0
				local px, py, pz = placementX or engPosX, (placementY or engPosY + placementHeight) + offset, placementZ or engPosZ
				local myTeamID = spGetMyTeamID()
				ReplaceBuildingPlacement(defID, myTeamID, facing, engPosX, engPosY, engPosZ,  px, py, pz, scale)
			end
		end
	end
end

function widget:Initialize()
	WG.ReplaceBuildingPlacement = ReplaceBuildingPlacement
end
function widget:Shutdown()
	WG.ReplaceBuildingPlacement = nil
end