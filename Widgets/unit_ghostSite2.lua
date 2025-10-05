
function widget:GetInfo()
	return {
		name      = "Ghost Site2",
		desc      = "Display ghosted buildings and enemy left out from Los for a brief moment"
					.. "[LIMITATION AS SPECTATOR]:There is currently no way to know the discovered buildings of an ally team from engine,"
					.. " therefore the widget discover them while spectating, if the team wasn't spectated all along, some discovered buildings may be missed.",
		author    = "Helwor",
		date      = "Oct 2022",
		license   = "GNU GPL v2",
		layer     = 0,
		enabled   = true
	}
end
local Echo = Spring.Echo
local debugging = false

--------
local spIsUnitAllied			= Spring.IsUnitAllied
local spGetTeamColor			= Spring.GetTeamColor
local spIsSphereInView 			= Spring.IsSphereInView
local spGetUnitDefID 			= Spring.GetUnitDefID
local spGetUnitPosition			= Spring.GetUnitPosition
local spGetFeaturePosition		= Spring.GetFeaturePosition
local spGetUnitHealth			= Spring.GetUnitHealth
local spGetUnitBuildFacing		= Spring.GetUnitBuildFacing
local spGetGroundHeight			= Spring.GetGroundHeight
local spGetPositionLosState		= Spring.GetPositionLosState
local spGetFeatureDefID			= Spring.GetFeatureDefID
local spGetFeatureTeam			= Spring.GetFeatureTeam
local spGetFeatureAllyTeam		= Spring.GetFeatureAllyTeam
local spGetAllFeatures			= Spring.GetAllFeatures
local spGetCameraState			= Spring.GetCameraState
local spGetSpectatingState		= Spring.GetSpectatingState
local spGetConfigInt			= Spring.GetConfigInt
local spIsUnitIcon				= Spring.IsUnitIcon
local spGetUnitLosState			= Spring.GetUnitLosState
local spGetUnitIsDead			= Spring.GetUnitIsDead
local spValidUnitID				= Spring.ValidUnitID
local spIsPosInLos				= Spring.IsPosInLos
local spugetMoveType			= Spring.Utilities.getMovetype
local spGetUnitTeam				= Spring.GetUnitTeam


local glPushMatrix				= gl.PushMatrix
local glPopMatrix				= gl.PopMatrix
local glTexEnv					= gl.TexEnv
local glUnitShape				= gl.UnitShape
local glUnitShapeTextures		= gl.UnitShapeTextures
local glTranslate				= gl.Translate
local glRotate					= gl.Rotate
local glGetShaderLog 			= gl.GetShaderLog
local glColor					= gl.Color
local glTexture					= gl.Texture
local glBlending				= gl.Blending
local glUseShader				
local glCreateShader			
local glDeleteShader			
local glUniform					= gl.Uniform
local glFeatureShape			= gl.FeatureShape
local glGetUniformLocation		= gl.GetUniformLocation
local glDepthTest				= gl.DepthTest

local glCreateList				= gl.CreateList
local glDeleteList				= gl.DeleteList
local glCallList				= gl.CallList


local GL_SRC_ALPHA				= GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA	= GL.ONE_MINUS_SRC_ALPHA
local GL_ONE					= GL.ONE
local GL_TEXTURE_ENV			= GL.TEXTURE_ENV
local GL_TEXTURE_ENV_MODE		= GL.TEXTURE_ENV_MODE
local GL_REPLACE				= GL.REPLACE

local spGetUnitHeading          = Spring.GetUnitHeading
local DOUBLE = 2^15

local UnitDefs = UnitDefs

local Units, Cam, inSight
local myAllyTeamID
local myPlayerID
local structDiscoveredByAllyTeams
local structureDiscovered
local EMPTY_TABLE = {}

--------

-- CONFIGURATION
local updateInt = 0.2    --seconds for the ::update loop
local updateFrame = 15 -- num of frames to update ghost heading
local ghostTint = {1, 1, 0}
local inProgressTint = {0.0,0.1,0.7}

local BlendTint = function(c1,c2,percent)
	local c = {}
	for i=1,3 do
		c[i] = (c1[i] + c2[i] * percent) / (1+percent)
	end
	return c
end
local function HeadingToDeg(heading)
	return heading / (DOUBLE*2)  * (360 )
end

-- END OF CONFIG

local PARAM_DEFID   = 4
local PARAM_TEAMID  = 5
local PARAM_TEXTURE = 6
local PARAM_RADIUS  = 7
local PARAM_FACING  = 8

local updateTimer = 0
local ghostSites = {}
local ghostFeatures = {}
local UpdateUnitPool    = {}
local scanForRemovalFeatures = {}
local dontCheckFeatures = {}

local gaiaTeamID = Spring.GetGaiaTeamID()

local importantDefID = {
	staticheavyradar = true,
	staticnuke = true,
	staticantinuke = true,
	staticmissilesilo = true,
	mahlazer = true,
	striderhub = true,
	staticheavyarty = true,
	staticarty = true,
	staticshield = true,
	staticjammer = true,
	turretantiheavy = true,
	turretheavy = true,
	turretaaheavy = true,
	zenith = true,
	raveparty = true,
	energysingu = true,
	energyheavygeo = true,
	energyfusion = true,
	turretaafar = true,
	-- moving
	amphtele = true,
	striderbantha = true,
	striderdetriment = true,
	striderdante = true,
	striderscorpion = true,
	striderantiheavy = true,
	athena = true,
}

local alphaMultDefID = {
	-- static
	[UnitDefNames['staticcon'].id] = 3,
	[UnitDefNames['energywind'].id] = 1.5,
	[UnitDefNames['staticstorage'].id] = 0.05,
	[UnitDefNames['staticrearm'].id] = 0.6,
	[UnitDefNames['energysingu'].id] = 0.8,
	[UnitDefNames['staticradar'].id] = 2.5,
	[UnitDefNames['energysolar'].id] = 0.5,
	[UnitDefNames['turretheavy'].id] = 1,
	[UnitDefNames['turretmissile'].id] = 0.35,
	[UnitDefNames['turretheavylaser'].id] = 1.15,
}

local floatOnWaterDefID = {}
for defID, def in pairs(UnitDefs) do
	if def.floatOnWater then
		floatOnWaterDefID[defID] = true
	end
end
local ofImportanceDefID = {}
for defID, def in pairs(UnitDefs) do
	if importantDefID[def.name] or def.name:match('factory') then
		ofImportanceDefID[defID] = true
	end
end
local isImmobileDefID = {}
for defID, def in pairs(UnitDefs) do
	-- if def.isImmobile and def.name ~= 'wolverine_mine' then
	-- 	isImmobileDefID[defID] = true
	-- end
	if not spugetMoveType(def) and def.name ~= 'wolverine_mine' then
		isImmobileDefID[defID] = true
	end
end
local radiusDefID = {}
for defID, def in pairs(UnitDefs) do
	radiusDefID[defID] = def.radius
end

local mineDefID = UnitDefNames['wolverine_mine'].id


local function HaveFullView()
	local spec, fullview = spGetSpectatingState()
	return spec and fullview or Spring.GetGlobalLos(Spring.GetLocalAllyTeamID())
end


local shaderObj
function InitShader()
	-- local shaderTemplate = include("Widgets/Shaders/default_tint.lua")
	local shaderTemplate = VFS.Include(LUAUI_DIRNAME .. "Widgets\\Shaders\\default_tint.lua")


	local shader = glCreateShader(shaderTemplate)
	if not shader then
		Echo("Ghost Site shader compilation failed: " .. glGetShaderLog())
		return
	end
	shaderObj = {
		shader = shader,
		teamColorID = glGetUniformLocation(shader, "teamColor"),
		tint = glGetUniformLocation(shader, "tint"),
	}
	Echo('Shader for Ghost Sites initialized')

end







local inProgressColor = {0.3, 1.0, 0.3, 0.25}
local ofImportanceColor = {0.7,1.0,0.8,0.6}
local teamColors = {}
local timeExpiredCnt = 0






--Commons
local function ResetGl()
	glColor(1.0, 1.0, 1.0, 1.0)
	glTexture(false)
	-- glBlending(false)
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	glDepthTest(false)
end
local function Count()
	local cnt,unfinCnt,ofImpCnt, timeoutCnt = 0, 0, 0, 0
	local totalTimeout = 0
	local time = os.clock()
	for _, ghost in pairs(ghostSites) do
		cnt = cnt + 1
		if ghost.inProgress then
			unfinCnt = unfinCnt + 1
		end
		if ghost.ofImportance then
			ofImpCnt = ofImpCnt + 1 
		end
		if ghost.timeout then
			timeoutCnt = timeoutCnt + 1
			totalTimeout = totalTimeout + (ghost.timeout-time)
		end
	end
	Echo('there are currently ' .. cnt .. ' ghost sites', 'including ' .. unfinCnt .. ' unfinished, ' .. ofImpCnt .. ' of importance and ' .. timeoutCnt .. ' with timeout, average timeout is ' .. totalTimeout/timeoutCnt .. 'sec. There have been ' .. timeExpiredCnt .. ' ghosts expired by timeout.')
	timeExpiredCnt = 0
end

local function DeleteGhost(ghost, id)
	if ghost then
		
		if ghost.list then
			glDeleteList(ghost.list)
		end
		ghostSites[id] = nil
		(Units[id] or EMPTY_TABLE).ghost = nil
		UpdateUnitPool[id] = nil
	end
end

local function UpdateGhostSites()
	-- if not next(UpdateUnitPool) then
	-- 	return
	-- end
	local time = os.clock()
	local Units = Units
	for unitID, ghost in pairs(ghostSites) do
	-- for unitID, ghost in pairs(UpdateUnitPool) do
		-- local udefID = spGetUnitDefID(unitID)
		local unit = Units[unitID]
		if UpdateUnitPool[unitID] then
			-- Echo('in update pool',math.round(time))
			local udefID
			-- if not udefID then
			if not unit then
				DeleteGhost(ghost, unitID)
				-- Echo(unitID,"didn't have defID!")
			else
				udefID = unit.defID
				local inLos = ghost.inLos
				-- if inLos then
					-- local _,_,_,_, buildProgress = spGetUnitHealth(unitID)
					local buildProgress = unit.health[5]
					if buildProgress then
						ghost.inProgress = buildProgress<1
						ghost.buildProgress = buildProgress
					else
						-- Echo(unitID,'dont have bp but is in los !')
					end
				-- end
				if ghost.isUnit then
					if udefID ~= mineDefID then
						if inLos then
							local heading = spGetUnitHeading(unitID)
							if heading then
								ghost.altfacing = HeadingToDeg(heading)
							else
								-- Echo(unitID,'dont got heading but is in los !')
							end
						end
						-- ghost[1], ghost[2], ghost[3] = spGetUnitPosition(unitID)
						ghost[1], ghost[2], ghost[3] = unit:GetPos(3)
						if not ghost[1] then -- FIX it shouldnt happen but it happens
							Echo('ghost', unitID,'dont have pos ! removing it ', unit.name)
							DeleteGhost(ghost, unitID)
						end
					end
				end
			end
		elseif not ghost.isUnit then
			-- if ghost is building and the building position is now in LoS, but the unit doesnt exist, we remove the ghost

			-- local _, losState--[[, inRadar, jammed, identified--]] = spGetPositionLosState(ghost[1], ghost[2], ghost[3])
			-- if losState --[[and not jammed--]] and not spValidUnitID(unitID) then
			-- 	DeleteGhost(ghost, unitID)
			-- end

			if spIsPosInLos(ghost[1], ghost[2], ghost[3]--[[, myAllyTeamID--]]) and not spValidUnitID(unitID) then
				DeleteGhost(ghost, unitID)
			end
		end
	end
end

local function DrawGhostStruct(unit, x,y,z)
	local teamID = unit.teamID
	local defID = unit.defID
	-- local texID = "%"..defID..":0"
	local teamID = unit.teamID
	local facing = unit.altfacing or facing or 1
	local ofImportance = ofImportanceDefID[defID]
	local buildProgress = unit.health[5]
	-- Echo(unitID,"facing,ghost.altfacing,ghost.altfacing or facing is ", facing,ghost.altfacing,ghost.altfacing or facing)


	-- glBlending (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --reset to default blending
	-- glBlending(GL_SRC_ALPHA, GL_ONE)
	-- drawcount = drawcount + 1
	local teamColor = teamColors[teamID]
	if not teamColor then
		teamColors[teamID] = {spGetTeamColor(teamID)}
		teamColor = teamColors[teamID]
		teamColor[4] = nil
	end
	local teamColorR, teamColorG, teamColorB = unpack(teamColor)

	
	if ofImportance then
		glBlending(GL_SRC_ALPHA, GL_ONE)
	else
		glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --normal blending
	end

	glPushMatrix()
	glTranslate(x, y, z)
	glRotate(facing, 0, 1, 0)
	glUnitShapeTextures(defID, true)

	local tint = teamColor

	if buildProgress < 1 then
		tint = BlendTint(tint, inProgressTint, 1 - buildProgress + 0.3)
	end
	local alphaMult = alphaMultDefID[defID] or 1
	if true or ofImportance then
		if shaderObj then

			-- glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, 0.1 + 0.8 * ghost.buildProgress --[[+ (ghost.ofImportance and 0 or 0.2)--]])
			-- glUniform(shaderObj.tint, tint[1],tint[2],tint[3])
			local alpha = 0.1 + 0.17 * (buildProgress or 1)
			alpha = alpha * alphaMult
			-- alpha = alpha * ghost.alphaMult
			glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, alpha)
			glUniform(shaderObj.tint, tint[1],tint[2],tint[3])

		end
		glUnitShape(defID, teamID, true)
	end
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

	-- if ghost.ofImportance then
		-- Add glow effect
		if not unit.isInRadar --[[and not losState--]] --[[or ghost.inProgress--]] then
		-- if ghost.inProgress or not spIsUnitIcon(unitID) then
			glBlending(GL_SRC_ALPHA, GL_ONE) --glow effect
			-- glUniform(shaderObj.tint, teamColorR+0.2, teamColorG+0.2, teamColorB+0.2)	
			if shaderObj then
				glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, 0.2 * alphaMult )
				-- glUniform(shaderObj.tint, teamColorR+0.2, teamColorG+0.2, teamColorB+0.2)
				-- glUniform(shaderObj.tint, 0.5, 0.5, 0.5)
				-- glUniform(shaderObj.tint, teamColorR+0.2, teamColorG+0.2, teamColorB+0.2)	
				if ofImportance then
					glUniform(shaderObj.tint, 0.5, 0.5, 0.5)
				else
					glUniform(shaderObj.tint, teamColorR/2.5, teamColorG/2.5, teamColorB/2.5)	
				end
			end
			glUnitShape(defID, teamID, true)
		end
	-- end

	glUnitShapeTextures(defID, false)
	glPopMatrix()

	-- glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --normal blending
	-- glBlending(false)


end

local function DrawGhost(ghost, time)
	local x, y, z, udefID, teamID, texture, radius, facing = unpack(ghost)
	-- Echo(unitID,"facing,ghost.altfacing,ghost.altfacing or facing is ", facing,ghost.altfacing,ghost.altfacing or facing)

	facing = ghost.altfacing or facing

	-- glBlending (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --reset to default blending
	-- glBlending(GL_SRC_ALPHA, GL_ONE)
	-- drawcount = drawcount + 1
	local teamColor = teamColors[teamID]
	if not teamColor then
		teamColors[teamID] = {spGetTeamColor(teamID)}
		teamColor = teamColors[teamID]
		teamColor[4] = nil
	end
	local teamColorR, teamColorG, teamColorB = unpack(teamColor)

	
	if ghost.ofImportance then
		glBlending(GL_SRC_ALPHA, GL_ONE)
	else

		glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --normal blending
	end

	glPushMatrix()
	glTranslate(x, y, z)
	glRotate(facing, 0, 1, 0)
	glUnitShapeTextures(udefID, true)

	local tint = teamColor

	if ghost.inProgress then
		tint = BlendTint(tint, {0, 1, 1}, 1 - ghost.buildProgress + 0.3)
	end
	local alphaMult = alphaMultDefID[udefID] or 1
	if ghost.timeout then
		alphaMult = alphaMult * ( (ghost.timeout - time) / 5  )
	end
	if true or ghost.ofImportance then
		if shaderObj then

			-- glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, 0.1 + 0.8 * ghost.buildProgress --[[+ (ghost.ofImportance and 0 or 0.2)--]])
			-- glUniform(shaderObj.tint, tint[1],tint[2],tint[3])
			local alpha = 0.1 + 0.17 * ghost.buildProgress
			alpha = alpha * alphaMult
			-- alpha = alpha * ghost.alphaMult
			glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, alpha)
			glUniform(shaderObj.tint, tint[1], tint[2], tint[3])

		end
		glUnitShape(udefID, teamID, true)
	end
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

	-- if ghost.ofImportance then
		-- Add glow effect
		if not inRadar and not losState --[[or ghost.inProgress--]] then
		-- if ghost.inProgress or not spIsUnitIcon(unitID) then
			glBlending(GL_SRC_ALPHA, GL_ONE) --glow effect
			-- glUniform(shaderObj.tint, teamColorR+0.2, teamColorG+0.2, teamColorB+0.2)	
			if shaderObj then
				glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, 0.2 * alphaMult )
				-- glUniform(shaderObj.tint, teamColorR+0.2, teamColorG+0.2, teamColorB+0.2)
				-- glUniform(shaderObj.tint, 0.5, 0.5, 0.5)
				-- glUniform(shaderObj.tint, teamColorR+0.2, teamColorG+0.2, teamColorB+0.2)	
				if ghost.ofImportance then
					glUniform(shaderObj.tint, 0.5, 0.5, 0.5)
				else
					glUniform(shaderObj.tint, teamColorR/2.5, teamColorG/2.5, teamColorB/2.5)	
				end
			end
			glUnitShape(udefID, teamID, true)
		end
	-- end

	glUnitShapeTextures(udefID, false)
	glPopMatrix()

	-- glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --normal blending
	-- glBlending(false)

end



local function DrawGhostSites()
	if Cam.fullview then
		return
	end
	if not (next(ghostSites) or next(structureDiscovered)) then
		return
	end

	-- glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 34160) --34160 = GL_COMBINE_RGB_ARB
	-- --use the alpha given by glColor for the outgoing alpha, else it would interpret the teamcolor channel as alpha one and make model transparent.
	-- glTexEnv(GL_TEXTURE_ENV, 34162, GL_REPLACE) --34162 = GL_COMBINE_ALPHA
	-- glTexEnv(GL_TEXTURE_ENV, 34184, 34167) --34184 = GL_SOURCE0_ALPHA_ARB, 34167 = GL_PRIMARY_COLOR_ARB

	glColor(0.3, 1.0, 0.3, 0.25)
	-- glColor(1,1,1,1)
	-- glColor(0,0,0,0)
	-- glColor(ofImportanceColor)
	glDepthTest(true)

	-- gl.Blending(GL.SRC_ALPHA, GL.ONE)
	teamColors = {}

	if shaderObj then
		glUseShader(shaderObj.shader)
	end
	local time = os.clock()
	local count = 0
	local drawcount = 0
	-- for id, unit in pairs(structureDiscovered) do
	-- 	if unit.isDead then
	-- 		structureDiscovered[id] = nil
	-- 	elseif not unit.isInSight then
	-- 		count = count + 1
	-- 		-- Echo(unitID,"facing,ghost.altfacing,ghost.altfacing or facing is ", facing,ghost.altfacing,ghost.altfacing or facing)
	-- 		local x,y,z = unpack(unit.pos)
	-- 		if spIsSphereInView(x,y,z) then
	-- 			local list = unit.list
	-- 			if not list then
	-- 				list = glCreateList(DrawGhostStruct, unit, x,y,z)
	-- 				unit.list = list
	-- 			end
	-- 			drawcount = drawcount + 1
	-- 			glCallList(list)
	-- 		end
	-- 	end
	-- 		-- Echo("unitID,ghost.identified,ghost.draw is ", unitID,ghost.identified,ghost.draw)
	-- end
	local mobilecount, immobilecount = 0, 0
	for unitID, ghost in pairs(ghostSites) do
		count = count + 1
		if ghost.draw and not inSight[unitID] then --if not inRadar or ghost.inProgress then
			drawcount = drawcount + 1


			if ghost.isUnit then
				mobilecount = mobilecount + 1

				if ghost.timeout - time < 0 then
					timeExpiredCnt = timeExpiredCnt + 1
					ghost.draw = false
					DeleteGhost(ghost, unitID)
					-- Echo('unit',unitID, 'has expired')
				elseif spIsSphereInView(ghost[1], ghost[2], ghost[3]) then
					drawcount = drawcount + 1
					DrawGhost(ghost, time)
				end
			else
				-- Echo(unitID,"facing,ghost.altfacing,ghost.altfacing or facing is ", facing,ghost.altfacing,ghost.altfacing or facing)
				immobilecount = immobilecount + 1
				if spIsSphereInView(ghost[1], ghost[2], ghost[3]) then
					local list = ghost.list
					if not list then
						list = glCreateList(DrawGhost, ghost)
						ghost.list = list
					end
					drawcount = drawcount + 1
					glCallList(list)
				end
			end
			-- Echo("unitID,ghost.identified,ghost.draw is ", unitID,ghost.identified,ghost.draw)
		end
	end
	-- Echo("mobilecount is ", mobilecount,'immobile',immobilecount,table.size(ghostSites))
	if shaderObj then
		glUseShader(0)
	end


	--------------------------Clean up-------------------------------------------------------------
	-- glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 8448) --8448 = GL_MODULATE
	-- --use the alpha given by glColor for the outgoing alpha.
	-- glTexEnv(GL_TEXTURE_ENV, 34162, 8448) --34162 = GL_COMBINE_ALPHA, 8448 = GL_MODULATE
	-- --glTexEnv(GL_TEXTURE_ENV, 34184, 5890) --34184 = GL_SOURCE0_ALPHA_ARB, 5890 = GL_TEXTURE

	-- Echo(drawcount .. ' ghost sites drawn.')
end






local lastFullview
function widget:GameFrame(f)
	if f%updateFrame ~= 7 then
		return
	end

	if Cam.fullview == 1 then
		-- Echo('user is spectating and have full view, ghost sites is deactivated for now')
		return 
	end
	if debugging and (f+7)%150 ~= 0 then
		Count()
	end
	UpdateGhostSites()
end





function widget:DrawWorld()
	if Cam.fullview == 1 then
		return
	end
	DrawGhostSites()
	-- DrawGhostFeatures()
	ResetGl()
end

-- function widget:DrawWorldRefraction()
-- 	DrawGhostSites()
-- 	-- DrawGhostFeatures()
-- 	ResetGl()
-- end
local lastLeftLos = false
local LLLpos = false
local lastDestroyed
function widget:UnitLeftLos(id,unitTeam) -- we can get the pos when unit leave los but not the heading
	local ghost = ghostSites[id]
	if not ghost then
		return
	end
	ghost.inLos = false
	-- if ghost.isUnit then
	-- 	if not ghost[1] then
	-- 		ghost[1], ghost[2], ghost[3] = spGetUnitPosition(id)
	-- 	end
	-- end
end


local dbgcount = 0
function widget:UnitEnteredLos(id, unitTeam)
	local unit = Units[id]

	if not unit  then
		if dbgcount < 5 then
			Echo('ghost site 2; dbg ' ..dbgcount, 'unit ', id,'not created','valid?',Spring.ValidUnitID(id),'dead?',Spring.GetUnitIsDead(id))
			dbgcount = dbgcount + 1
		end
		-- Echo("id entered los but is " .. (not unit and 'not in unit table' or unit.isAllied and 'is allied' or unit.isMine and 'is mine') .. '.')
		return
	elseif unit.isAllied or unit.isMine then
		if dbgcount < 5 then
			Echo('ghost site 2; dbg' .. dbgcount,' unit ', id,'entered LoS while being allied','isAllied',unit.isAllied,'isMine',unit.isMine)
			dbgcount = dbgcount + 1
		end
	end
	if structureDiscovered[id] and not unit.facing then
		unit.facing = spGetUnitBuildFacing(id)
	end
	-- if spIsUnitAllied(id) then
	-- 	return
	-- end


	local ghost = ghostSites[id]

	-- Echo('unit', id, 'entered LOS', 'ghost ?', ghost)


	-- local _,_,_,_,buildProgress = spGetUnitHealth(id)
	if unit.defID == mineDefID then
		return
	end
	local buildProgress = unit.health[5]
	local valid = buildProgress and buildProgress>0.02 --and (ofImportance or buildProgress<1)
	if not valid then
		-- if ghost then
		-- 	-- Echo('ghost deleted, build progress too low')
		-- 	DeleteGhost(ghost, id)
		-- end
		return
	end
	-- update ghost
	if ghost then
		ghost.draw = false
		ghost.inLos = true
		ghost[1], ghost[2], ghost[3] = unpack(unit.pos)
		UpdateUnitPool[id] = ghost
		ghost.identified = ghost[4]
		return
	end
	-- local defID = spGetUnitDefID(id)
	local defID = unit.defID
	-- create ghost
	local ofImportance = ofImportanceDefID[defID]
	local name = UnitDefs[defID].name
	local inProgress = buildProgress<1
	local facing, timeout, altfacing, maxTimeout,isUnit
	local x, y, z = 0, 0, 0
	if isImmobileDefID[defID] then
		-- x, y, z = spGetUnitPosition(id)
		x,y,z = unpack(unit.pos)
		facing = spGetUnitBuildFacing(id) * 90
		y = spGetGroundHeight(x,z) -- every single model is offset by 16, pretty retarded if you ask me. // (Helwor don't think this comment has relevance now)
		if y<0 and floatOnWaterDefID[defID] then
			y = 0
		end
	else
		x,y,z = unpack(unit.pos)
		-- x,y,z = unit:GetPos(0)
		-- x,y,z = unit:GetPos(3)
		-- x,y,z = spGetUnitPosition(id)
		facing = 90
		maxTimeout = (ofImportance and 20 or 5)
		timeout = 0
		local heading = spGetUnitHeading(id)
		if heading then
			altfacing = HeadingToDeg(heading)
		end
		isUnit = true
	end
	local ghost =  {
		x, y, z,
		defID,
		unitTeam,
		"%"..defID..":0",
		radiusDefID[defID] + 100,
		facing,
		inLos = true,
		buildProgress = buildProgress,
		inProgress = inProgress,
		ofImportance = ofImportance,
		alphaMult = alphaMultDefID[defID] or 1,
		name = name,
		timeout = timeout,
		altfacing = altfacing,
		isUnit = isUnit,
		maxTimeout = maxTimeout,
		identified = defID,
		draw = false,
		unit = unit,
	}
	if (ghost.isUnit or ghost.buildProgress < 1) then
		UpdateUnitPool[id] = ghost
	end
	ghostSites[id] = ghost
	unit.ghost = ghost
	-- Echo('creating ghost',ghostSites[id],'defID?', defID, 'is Unit?', isUnit, 'need update?',UpdateUnitPool[id], 'identified?', ghost.identified)
end
function widget:UnitLeftRadar(id, unitTeam) -- unit leave radar even where there is no radar after leaving LoS
	
	-- Echo('unit',id, 'left radar')
	
	local ghost = ghostSites[id]

	if not ghost then
	-- 	Echo('its not registered as ghost')
		return
	end

	UpdateUnitPool[id] = nil
	ghost.inRadar = false
	-- Echo('ghost is unit ?',ghost.isUnit,'identified?',ghost.identified)

	if ghost.buildProgress and ghost.buildProgress<0.02 then
		ghost.draw = false
	elseif ghost.isUnit then
		if ghost.identified then
			ghost.timeout = os.clock()+ghost.maxTimeout
			ghost.draw = true
			ghost.identified = false
		end
	else
		ghost.draw = true
	end
	-- if  id == 9922 then
	-- 	Echo(id,'left radar, draw?',ghost.draw)
	-- end
end

function widget:UnitEnteredRadar(id, unitTeam)
	-- Echo('unit', id, 'entered radar')
	local ghost = ghostSites[id]
	if not ghost then
		-- Echo('not a ghost')
		return
	end
	local unit = Units[id]
	if not unit then
		-- Echo('not in unit table')
		return
	end
	-- ghost.identified = spGetUnitDefID(id)
	-- NOTE:when unit enter Los without radar coverage, UnitEnteredRadar get triggered AFTER UnitEnteredLos
	ghost.identified = (not ghost.isUnit or ghost.inLos) and unit.defID
	ghost.inRadar = true
	if not ghost.isUnit then
		ghost.draw = false
	end
	-- Echo('unit ' .. id .. 'entered radar, identified ?', ghost.identified, 'is Unit ?',ghost.isUnit, 'draw?', ghost.draw,math.round(os.clock()))


	-- if ghost.buildProgress==1 then
	-- 	ghost.draw = false
	-- end
end
local isSpec, isFullRead
function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		local myNewAllyTeamID =Spring.GetMyAllyTeamID()
		if myNewAllyTeamID ~= myAllyTeamID then
			myAllyTeamID = myNewAllyTeamID
			structureDiscovered = WG.structDiscoveredByAllyTeams[myAllyTeamID]
		end
		local wasSpec, wasFullRead = isSpec, isFullRead
		isSpec, isFullRead = Spring.GetSpectatingState()
	end
	
end
local function Init()
	for id, ghost in pairs(ghostSites) do
		-- local inLos = spIsPosInLos(ghost[1], ghost[2], ghost[3], myAllyTeamID)
		-- if losState --[[and not jammed--]] and not spValidUnitID(unitID) then
		-- 	DeleteGhost(ghost, id)
		-- end
		local _, inLos, inRadar, jammed, identified = spGetPositionLosState(ghost[1], ghost[2], ghost[3])
		if ghost.isUnit then
			ghost.identified = false
		end
		local teamID = spGetUnitTeam(id)
		if not inLos then
			if ghost.inLos then
				widget:UnitLeftLos(id,teamID)
				if not inRadar then
					widget:UnitLeftRadar(id,teamID)
				end
			end
		elseif inRadar then

		elseif ghost.inRadar then
			widget:UnitLeftRadar(id,teamID)
		end

	end
	local spIsUnitAllied = Spring.IsUnitAllied

	for i, id in pairs(Spring.GetAllUnits()) do
		if not ghostSites[id] and not spIsUnitAllied(id) then
			local teamID = spGetUnitTeam(id)
			local losState = spGetUnitLosState(id)
			local inLos, inRadar, identified = losState.los, losState.radar, losState.typed
			if inRadar then
				widget:UnitEnteredRadar(id, teamID)
			end

			if inLos then
				widget:UnitEnteredLos(id, teamID)
			end
		end
	end
end
local myWidgetName = widget:GetInfo().name
function WidgetWakeNotify(w,name,preloading)
	if name == myWidgetName then
		Init()
	end

end


function widget:Initialize()
	Cam = WG.Cam
	Units = Cam and Cam.Units
	inSight = Cam and Cam.inSight
	if not Units then
		widgetHandler:RemoveWidget(self)
		Echo(self:GetInfo().name .. ' need WG.Cam to work')
		return
	end

	WG.ghostSites = WG.ghostSites or ghostSites
	ghostSites = WG.ghostSites
	if gl.CreateShader then
		glUseShader				= gl.UseShader
		glCreateShader			= gl.CreateShader
		glDeleteShader			= gl.DeleteShader

		InitShader()
	end
	myPlayerID = Spring.GetMyPlayerID()
	widget:PlayerChanged(myPlayerID)

	Init()
end
function widget:Shutdown()
	if shaderObj then
		glDeleteShader(shaderObj.shader)
	end
	for _, ghost in pairs(ghostSites) do
		if ghost.list then
			glDeleteList(ghost.list)
			ghost.list = nil
		end
	end
	for _, structureDiscovered in pairs(structDiscoveredByAllyTeams or {}) do
		for id, struct in pairs(structureDiscovered) do
			if struct.unit.list then
				glDeleteList(unit.list)
			end
		end
	end
end			
function widget:UnitDestroyed(id)
	DeleteGhost(ghostSites[id], id)
end


--[[
	local function ScanFeatures()
		for _, fID in ipairs(spGetAllFeatures()) do
			if not (dontCheckFeatures[fID] or ghostFeatures[fID]) then
				local fAllyID = spGetFeatureAllyTeam(fID)
				local fTeamID = spGetFeatureTeam(fID)

				if (fTeamID ~= gaiaTeamID and fAllyID and fAllyID >= 0) then
					local fDefId  = spGetFeatureDefID(fID)
					local x, y, z = spGetFeaturePosition(fID)
					ghostFeatures[fID] = { x, y, z, fDefId, fTeamID, "%-"..fDefId..":0", FeatureDefs[fDefId].radius + 100 }
				else
					dontCheckFeatures[fID] = true
				end
			end
		end
	end

	local function DeleteGhostFeatures()
		if not next(scanForRemovalFeatures) then
			return
		end

		for featureID in pairs(scanForRemovalFeatures) do
			local ghost   = ghostFeatures[featureID]
			local x, y, z = ghost[1], ghost[2], ghost[3]
			local _, losState = spGetPositionLosState(x, y, z)

			local featDefID = spGetFeatureDefID(featureID)

			if (not featDefID and losState) then
				ghostFeatures[featureID] = nil
			end
		end
		scanForRemovalFeatures = {}
	end
	local function DrawGhostFeatures()
		local cs = spGetCameraState()
		local gy = spGetGroundHeight(cs.px, cs.pz)
		local cameraHeight
		if cs.name == "ta" then
			cameraHeight = cs.height - gy
		else
			cameraHeight = cs.py - gy
		end
		if cameraHeight < 1 then
			cameraHeight = 1
		end
		if cameraHeight > spGetConfigInt("FeatureDrawDistance") then
			return
		end
		glColor(1.0, 1.0, 1.0, 0.35)
	  
		--glTexture(0,"$units1") --.3do texture atlas for .3do model
		--glTexture(1,"$units1")

		glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 34160) --34160 = GL_COMBINE_RGB_ARB
		--use the alpha given by glColor for the outgoing alpha, else it would interpret the teamcolor channel as alpha one and make model transparent.
		glTexEnv(GL_TEXTURE_ENV, 34162, GL_REPLACE) --34162 = GL_COMBINE_ALPHA
		glTexEnv(GL_TEXTURE_ENV, 34184, 34167) --34184 = GL_SOURCE0_ALPHA_ARB, 34167 = GL_PRIMARY_COLOR_ARB
		
		--------------------------Draw-------------------------------------------------------------
		local lastTexture = ""
		for featureID, ghost in pairs(ghostFeatures) do
			local x, y, z = ghost[1], ghost[2], ghost[3]
			local _, losState = spGetPositionLosState(x, y, z)

			if not losState and spIsSphereInView(x,y,z,ghost[PARAM_RADIUS]) then
				--glow effect?
				--glBlending(GL_SRC_ALPHA, GL_ONE)
				if (lastTexture ~= ghost[PARAM_TEXTURE]) then
					lastTexture = ghost[PARAM_TEXTURE]
					glTexture(0, lastTexture) -- no 3do support!
				end

				glPushMatrix()
				glTranslate(x, y, z)

				glFeatureShape(ghost[PARAM_DEFID], ghost[PARAM_TEAMID], false, true, false)

				glPopMatrix()
			else
				scanForRemovalFeatures[featureID] = true
			end
		end

		--------------------------Clean up-------------------------------------------------------------
		glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 8448) --8448 = GL_MODULATE
		--use the alpha given by glColor for the outgoing alpha.
		glTexEnv(GL_TEXTURE_ENV, 34162, 8448) --34162 = GL_COMBINE_ALPHA, 8448 = GL_MODULATE
		--glTexEnv(GL_TEXTURE_ENV, 34184, 5890) --34184 = GL_SOURCE0_ALPHA_ARB, 5890 = GL_TEXTURE
	end
	local function UpdateGhostSitesOLD()
		if not next(UpdateUnitPool) then
			return
		end
		local time = os.clock()
		for unitID in pairs(UpdateUnitPool) do
			local ghost   = ghostSites[unitID]
			local x, y, z = ghost[1], ghost[2], ghost[3]
			local _, losState, inRadar, jammed, identified
			if ghost.isUnit then
				local los = spGetUnitLosState(unitID)
				if los then
					losState, inRadar = los.los, los.inRadar
				end
			else
				_, losState, inRadar, jammed, identified = spGetPositionLosState(x, y, z)
			end

			local udefID = spGetUnitDefID(unitID)
			if losState then
				if not udefID then
					ghostSites[unitID] = nil
					-- Echo(unitID,'defID',udefID,'has been removed')
				else
					if ghost.inProgress then
						local _,_,_,_, buildProgress = spGetUnitHealth(unitID)
						if buildProgress then
							local valid = buildProgress>0.02 -- and (ghost.ofImportance or buildProgress<1)
							if not valid then 
								-- Echo(unitID,'defID',udefID,'has been removed')
								ghostSites[unitID] = nil
							else
								ghost.inProgress = buildProgress<1
								ghost.buildProgress = buildProgress
							end
						else
							Echo('ghost site: No buildProgress??', buildProgress)
						end
					end
					if ghost.timeout then
						ghost.timeout = time + ghost.maxTimeout
						local x, y, z = spGetUnitPosition(unitID)

						if x then
							ghost[1], ghost[2], ghost[3] = x,y,z
						end
						local heading = spGetUnitHeading(unitID)
						if heading then
							ghost.altfacing = HeadingToDeg(heading)
						end

					end
				end
			end
		end
		UpdateUnitPool = {}
	end
	local dtcount = 0
	function widget:Update(dt)
		-- if true then -- now using GameFrame and new functions cheaper
		-- 	return
		-- end
		dtcount = dtcount + dt
		updateTimer = updateTimer + dt
		if (updateTimer < updateInt) then
			return
		end
		updateTimer = 0
		if Cam.fullview then
		-- if HaveFullView() then
			-- Echo('user is spectating and have full view, ghost sites is deactivated for now')
			return false
		end
		if debugging then
			if dtcount>10 then
				dtcount = 0
				Count()

			end
		end
		-- ScanFeatures()
		UpdateGhostSitesOLD()
		-- DeleteGhostFeatures()
	end
]]--