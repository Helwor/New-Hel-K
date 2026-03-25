
function widget:GetInfo()
	return {
		name      = "Ghost Site3",
		desc      = "Display ghosted buildings and enemy left out from Los for a brief moment"
					.. "[LIMITATION AS SPECTATOR]:There is currently no way to know for sure the discovered buildings of an ally team from engine,"
					.. " therefore they are discovered from widget side and might be inaccurate if the targetted wasnt watched all along.",
		author    = "Helwor",
		date      = "Oct 2022",
		license   = "GNU GPL v2",
		layer     = 0,
		enabled   = true,
		handler   = true,
	}
end
local Echo = Spring.Echo
local debugging = false
local useGlow = false
local EDIT_MODE = false
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

local osclock                   = os.clock

local GL_SRC_ALPHA				= GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA	= GL.ONE_MINUS_SRC_ALPHA
local GL_ONE					= GL.ONE
-- local GL_TEXTURE_ENV			= GL.TEXTURE_ENV
-- local GL_TEXTURE_ENV_MODE		= GL.TEXTURE_ENV_MODE
-- local GL_REPLACE				= GL.REPLACE

local spGetUnitHeading          = Spring.GetUnitHeading
local DOUBLE = 2^15

local UnitDefs = UnitDefs

local Units, Cam, inSight
local myAllyTeamID
local myTeamID
local myPlayerID
local isSpec, isFullRead
local structDiscoveredByAllyTeams
local structureDiscovered
local EMPTY_TABLE = {}

--------

-- CONFIGURATION
-- local updateInt = 0.2    --seconds for the ::update loop
local updateFrame = 15 -- num of frames to update ghost heading
local ghostTint = {0, 1, 1}
local inProgressTint = {0.0,0.1,0.7}
local doGhostUnits = false
local lastFrame = -1
local gameFrame = -1

local Init
local inProgressColor = {0.3, 1.0, 0.3, 0.25}
local ofImportanceColor = {0.7,1.0,0.8,0.6}
local teamColors = {}
local timeExpiredCnt = 0


options = {}
options_path = 'Hel-K/' .. widget.GetInfo().name

options.ghost_units = {
	name = 'Ghost Mobile Units',
	type = 'bool',
	desc = 'Show for a short time unit\'s ghost that have left radar/sight range.',
	value = doGhostUnits,
	OnChange = function(self)
		doGhostUnits = self.value
		Init()
	end,
}


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
local updateTimer = 0
local ghostUnits = {}
-- local ghostFeatures = {}
local UpdateUnitPool    = {}
-- local scanForRemovalFeatures = {}
-- local dontCheckFeatures = {}

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

local alphaMult = {
	-- static
	[UnitDefNames['staticcon'].id] = 1.3,
	[UnitDefNames['energywind'].id] = 1,
	[UnitDefNames['staticstorage'].id] = 0.5,
	[UnitDefNames['staticrearm'].id] = 1,
	[UnitDefNames['energysingu'].id] = 0.8,
	[UnitDefNames['staticradar'].id] = 1.5,
	[UnitDefNames['staticheavyradar'].id] = 1.1,
	[UnitDefNames['energysolar'].id] = 1,
	[UnitDefNames['turretheavy'].id] = 1,
	[UnitDefNames['turretmissile'].id] = 0.7,
	[UnitDefNames['turretheavylaser'].id] = 1.15,
	[UnitDefNames['factoryjump'].id] = 0.65,
	[UnitDefNames['factorygunship'].id] = 1.2,
	[UnitDefNames['factoryplane'].id] = 0.85,
	[UnitDefNames['factoryveh'].id] = 0.9,
	[UnitDefNames['factoryshield'].id] = 0.65,
	[UnitDefNames['factorycloak'].id] = 0.85,
	[UnitDefNames['factorytank'].id] = 0.9,
	[UnitDefNames['factoryhover'].id] = 0.8,
	[UnitDefNames['turretriot'].id] = 0.8,
	[UnitDefNames['turretlaser'].id] = 0.9,
	[UnitDefNames['energysingu'].id] = 0.6,
	[UnitDefNames['raveparty'].id] = 0.6,
	[UnitDefNames['staticantinuke'].id] = 0.6,
	[UnitDefNames['turretheavy'].id] = 0.5,
	[UnitDefNames['turretantiheavy'].id] = 0.5,
	[UnitDefNames['turretaaheavy'].id] = 0.7,
	[UnitDefNames['energysingu'].id] = 0.45,
	[UnitDefNames['turretheavylaser'].id] = 0.8,

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
local lists = {}
	-- Echo(drawcount .. ' ghost sites drawn.')

local structs_mt = {
	__index = function(self, id)
		local t = {}
		rawset(self, id, t)
		return t 
	end
}
local defID_mt = {
	__index = function(self, defID)
		local t = setmetatable({}, structs_mt)
		rawset(self, defID, t)
		return t 
	end
}
local struct_ordered = setmetatable(
	{},
	{
		__index = function(self, teamID)
			local t = setmetatable({}, defID_mt)
			rawset(self, teamID, t)
			return t
		end
	}
)

local shaderObj
local glowShader = {
	vertex = [[
		varying vec3 normal;
		varying vec3 eyeVec;
		varying vec4 color;
		uniform mat4 camera;
		uniform mat4 caminv;

		void main() {
			vec4 P = gl_ModelViewMatrix * gl_Vertex;
			eyeVec = P.xyz;
			normal  = gl_NormalMatrix * gl_Normal;
			color = gl_Color.rgba;
			gl_Position = gl_ProjectionMatrix * P;
		}
	]],

	fragment = [[
		varying vec3 normal;
		varying vec3 eyeVec;
		varying vec4 color;

		void main() {
			float opac = dot(normalize(normal), normalize(eyeVec));
			opac = pow(1.0 - abs(opac), 2.5);
			gl_FragColor.rgba = color;
			gl_FragColor.a = gl_FragColor.a * opac;
		}
	]],
}

local tintShader = {
	fragment= VFS.LoadFile('LuaUI/Widgets/Shaders/ghost_tint.frag.glsl'),
	uniformInt = {
		textureS3o1 = 0,
		textureS3o2 = 1,
	},
	uniform = {
		tint = {1, 1, 1},
		strength = 1,
	},
}


function InitShader()
	-- local shader = glCreateShader(shaderTemplate)
	local shader
	if useGlow then
		shader = glCreateShader(glowShader)
	else
		shader = glCreateShader(tintShader)
	end
	if not shader then
		Echo("Ghost Site shader compilation failed: " .. glGetShaderLog())
		return false
	end
	shaderObj = {
		shader = shader,
		teamColorID = glGetUniformLocation(shader, "teamColor"),
		tint = glGetUniformLocation(shader, "tint"),
		strength = glGetUniformLocation(shader, "strength"),
	}
	-- Echo('loc', glGetUniformLocation(shader, 'textureS3o1'))
	Echo('Shader for Ghost Sites initialized')
	return true
end

--Commons
local function ResetGl()
	glColor(1.0, 1.0, 1.0, 1.0)
	glTexture(false)
	-- glBlending(false)
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	-- glDepthTest(false)
	if shaderObj then
		glUseShader(0)
	end
end

function Init()
	-- NOTE Spring.IsUnitInRadar is broken
	local spIsUnitInLos = Spring.IsUnitInLos
	for id, struct in pairs(structureDiscovered) do
		if not struct.unit.isInRadar then
			widget:UnitLeftRadar(id, struct.teamID)
		end
	end

	for id, ghost in pairs(ghostUnits) do
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
		if not spIsUnitAllied(id) then
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

function Init()
	-- NOTE Spring.IsUnitInRadar is broken
	local spIsUnitInLos = Spring.IsUnitInLos
	for id, struct in pairs(structureDiscovered) do
		if not struct.unit.isInRadar then
			widget:UnitLeftRadar(id, struct.teamID)
		end
	end

	for id, ghost in pairs(ghostUnits) do
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
		if not spIsUnitAllied(id) then
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



local function Count()
	local cnt,unfinCnt,ofImpCnt, timeoutCnt = 0, 0, 0, 0
	local totalTimeout = 0
	local time = os.clock()
	for _, ghost in pairs(ghostUnits) do
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
		ghostUnits[id] = nil
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
	for unitID, ghost in pairs(UpdateUnitPool) do
		-- local defID = spGetUnitDefID(unitID)
		local unit = Units[unitID]
		if UpdateUnitPool[unitID] then
			-- Echo('in update pool',math.round(time))
			if not unit then
				DeleteGhost(ghost, unitID)
				-- Echo(unitID,"didn't have defID!")
			else
				local defID = unit.defID
				local inLos = ghost.inLos
				if inLos then
					-- local _,_,_,_, buildProgress = spGetUnitHealth(unitID)
					local buildProgress = unit.health[5]
					if buildProgress then
						ghost.inProgress = buildProgress<1
						ghost.buildProgress = buildProgress
					else
						-- Echo(unitID,'dont have bp but is in los !')
					end
				end
				if defID ~= mineDefID then
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
	end
end



local function GetTeamColors()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local r, g, b, a = spGetTeamColor(teamID)
		local color = {r,g,b}
		local total = r + g + b
		Echo(r, g, b, 'total '.. (r + g + b))
		local max = 2.05
		if total > max then
			for i, c in ipairs(color) do
				color[i] = c - (total - max)
			end
		else
			-- for i, c in ipairs(color) do
			-- 	color[i] = c + (max - total)
			-- end
		end
		-- for i, c in ipairs(color) do
		-- 	color[i] = c + 1
		-- end

		-- local closest = 0 -- get the closest of 1
		-- for i, c in ipairs(color) do
		-- 	if c > closest then
		-- 		closest = c
		-- 	end
		-- end
		-- for i, c in ipairs(color) do
		-- 	c = c + (1 - closest)
		-- 	color[i] = c
		-- end

		color[4] = a
		teamColors[teamID] = color
	end
end
local function GetTeamColors()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local r, g, b, a = spGetTeamColor(teamID)
		local color = {r,g,b}
		local total = r + g + b

		if total > 2.16 then
			-- for i, c in ipairs(color) do
			-- 	color[i] = c-(total - 2)
			-- end
		else
			for i, c in ipairs(color) do
				color[i] = c+(2.16 - total)
			end
		end
		-- for i, c in ipairs(color) do
		-- 	color[i] = c + 1
		-- end

		-- local closest = 0 -- get the closest of 1
		-- for i, c in ipairs(color) do
		-- 	if c > closest then
		-- 		closest = c
		-- 	end
		-- end
		-- for i, c in ipairs(color) do
		-- 	c = c + (1 - closest)
		-- 	color[i] = c
		-- end

		color[4] = a
		teamColors[teamID] = color
	end
end
-- local function GetTeamColors()
-- 	for _, teamID in ipairs(Spring.GetTeamList()) do
-- 		teamColors[teamID] = {spGetTeamColor(teamID)}
-- 	end
-- end
local function NewGhostUnit(id, defID, teamID, buildProgress, unit)
	local ofImportance = ofImportanceDefID[defID]
	local name = UnitDefs[defID].name
	local inProgress = buildProgress < 1
	local facing, timeout, altfacing, maxTimeout
	local x, y, z = unpack(unit.pos)
	facing = 90
	maxTimeout = (ofImportance and 8 or 5)
	timeout = 0
	local heading = spGetUnitHeading(id)
	if heading then
		altfacing = HeadingToDeg(heading)
	end
	isUnit = true

	local ghost =  {
		x, y, z,
		defID,
		teamID,
		"%"..defID..":0",
		radiusDefID[defID] + 100,
		facing,
		inLos = true,
		buildProgress = buildProgress,
		inProgress = inProgress,
		ofImportance = ofImportance,
		alphaMult = alphaMult[defID] or 1,
		name = name,
		timeout = timeout,
		altfacing = altfacing,
		isUnit = true,
		maxTimeout = maxTimeout,
		identified = defID,
		draw = false,
		unit = unit,
	}
	UpdateUnitPool[id] = ghost
	ghostUnits[id] = ghost
	unit.ghost = ghost
	-- Echo('creating ghost',ghostUnits[id],'defID?', defID, 'is Unit?', isUnit, 'need update?',UpdateUnitPool[id], 'identified?', ghost.identified)

end


local newView = WG.NewView
local lastView = newView[5]



local function DrawGhostSites()
	-- if not next(structureDiscovered) then
	-- 	return
	-- end
	local curView = newView[5]
	local noViewCheck = curView == lastView
	lastView = newView

	-- glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 34160) --34160 = GL_COMBINE_RGB_ARB
	-- -- --use the alpha given by glColor for the outgoing alpha, else it would interpret the teamcolor channel as alpha one and make model transparent.
	-- glTexEnv(GL_TEXTURE_ENV, 34162, GL_REPLACE) --34162 = GL_COMBINE_ALPHA
	-- glTexEnv(GL_TEXTURE_ENV, 34184, 34167) --34184 = GL_SOURCE0_ALPHA_ARB, 34167 = GL_PRIMARY_COLOR_ARB

	-- glColor(0.3, 1.0, 0.3, 0.25)
	-- glColor(1, 1, 1, 1)
	glDepthTest(true)

	glBlending(GL_SRC_ALPHA, GL_ONE)
	if shaderObj then
		glUseShader(shaderObj.shader)
	end

-- glUniform(shaderObj.tint, 1 )	
	local UnitDefs = UnitDefs
	for teamID, defs in pairs(struct_ordered) do
		local teamColor = teamColors[teamID]
		-- local teamColorR, teamColorG, teamColorB = unpack(teamColor)
		glColor(1,1,1,1)
		if useGlow then
			glColor(teamColor[1]+0.4, teamColor[2]+0.4, 0, 0.3)
		else
			glUniform(shaderObj.teamColorID, teamColor[1] , teamColor[2], teamColor[3], 1)
			-- glUnitShapeTextures(WG.tex, true)
		end
		for defID, structs in pairs(defs) do
			-- glUnitShapeTextures(40, true)
			-- glUnitShapeTextures(WG.tex, true)
			glUnitShapeTextures(defID, true)
			local alpha = 1
			-- local important = ofImportanceDefID[defID]
			local cost = math.clamp(UnitDefs[defID].cost/300, 1,  4)
			cost = 1 + (cost - 1)/2
			cost = cost * (alphaMult[defID] or 1)
			-- cost = 1
			-- if cost > 1 then
				-- local c = BlendTint(teamColor, {1*}, 1)
			if not useGlow then				
				glUniform(shaderObj.tint, cost, cost, cost )	
			end
			-- else
			-- 	glUniform(shaderObj.tint, teamColor[1] , teamColor[2], teamColor[3])
			-- end

			-- local teamColor = BlendTint(teamColor, {0.1,0.1,0.1}, 1)
			-- Echo("teamColor is ", unpack(teamColor))
			-- if not gamePaused then
			-- 	local second = math.round(os.clock())
			-- 	if second > time then
			-- 		time = second
			-- 		widget:KeyPress(right)
			-- 	end
			-- end
			-- local list = lists[defID]
			-- if not list then
			-- 	list = glCreateList(glUnitShape, defID, 0)
			-- 	lists[defID] = list
			-- end
			-- gl.Texture(0,'#' .. defID)
			local radius = radiusDefID[defID]
			for id, struct in pairs(structs) do
				if not structureDiscovered[id] then
					structs[id] = nil -- the handler removed it meanwhile
				elseif struct.facing then
					local x, y, z
					-- if struct.pos then
					-- 	x, y, z = unpack(struct.pos)
					-- else
						x, y, z = struct[1], struct[2], struct[3]
					-- end
					if spIsSphereInView(x, y, z, radius) then
						glPushMatrix()
						glTranslate(x, y, z)
						glRotate(struct.facing * 90, 0, 1, 0)
						-- glUnitShape(defID, teamID, false, true, false)
						glUnitShape(defID, teamID) 
						glPopMatrix()
					end
				end
			end
			if not useGlow then
				-- glUnitShapeTextures(WG.tex, false)
				glUnitShapeTextures(defID, false)
			end
			-- gl.Texture(false)
		end

	end
	lastFrame = gameFrame

	--------------------------Clean up-------------------------------------------------------------
	-- glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 8448) --8448 = GL_MODULATE
	-- -- --use the alpha given by glColor for the outgoing alpha.
	-- glTexEnv(GL_TEXTURE_ENV, 34162, 8448) --34162 = GL_COMBINE_ALPHA, 8448 = GL_MODULATE
	-- glTexEnv(GL_TEXTURE_ENV, 34184, 5890) --34184 = GL_SOURCE0_ALPHA_ARB, 5890 = GL_TEXTURE

	-- Echo(drawcount .. ' ghost sites drawn.')
end

local function DrawGhost(ghost, time)
	local x, y, z, defID, teamID, texture, radius, facing = unpack(ghost)
	-- Echo(unitID,"facing,ghost.altfacing,ghost.altfacing or facing is ", facing,ghost.altfacing,ghost.altfacing or facing)

	facing = ghost.altfacing or facing
	local teamColor = teamColors[teamID]
	local teamColorR, teamColorG, teamColorB = unpack(teamColor)
	-- glUniform(shaderObj.teamColorID, teamColorR/8, teamColorG/8, teamColorB/8, 1.0)
	-- glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, 1.0)

	glPushMatrix()
	glTranslate(x, y, z)
	glRotate(facing, 0, 1, 0)
			-- glUseShader(0)
   --          gl.Blending(GL.SRC_ALPHA, GL.ONE) -- glowy blending
			-- glColor(teamColorR/13, teamColorG/13, teamColorB/13, 1.0)
   --          -- gl.UnitShape(defID, teamID, true, true, false) -- g
   --          gl.UnitShape(defID, teamID, false, true, false) -- f
   --          -- gl.UnitShape(defID, teamID, true, true, false) -- g

   --          gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

   --          glPopMatrix()
   --          glUseShader(shaderObj.shader)
   --          if true then
   --          	return
   --          end

	-- -- gl.Texture(0, texture)
	-- -- gl.Texture(1, texture:gsub('0', '1'))
	-- gl.Color(0.5,0.5,0.5,0.2)
	-- glUnitShapeTextures(defID, true)
	-- gl.UnitShape(defID, teamID, true)
	-- glUnitShapeTextures(defID, false)
	-- -- gl.Texture(0, false)
	-- -- gl.Texture(1, false)
	-- glPopMatrix()
	-- if true then
	-- 	return
	-- end
	glUnitShapeTextures(defID, true)

	if ghost.ofImportance then
		glBlending(GL_SRC_ALPHA, GL_ONE)
	else
		glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --normal blending
	end

	local tint = teamColor
	if ghost.inProgress then
		tint = BlendTint(tint, ghostTint, 1 - ghost.buildProgress + 0.3)
	end
	local alphaMult = alphaMult[defID] or 1
	if ghost.timeout then
		alphaMult = alphaMult * ( (ghost.timeout - time) / 5  )
	end
	if true or ghost.ofImportance then
		if shaderObj then

			-- glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, 0.1 + 0.8 * ghost.buildProgress --[[+ (ghost.ofImportance and 0 or 0.2)--]])
			-- glUniform(shaderObj.tint, tint[1],tint[2],tint[3])
			local alpha = 0.1 + 0.17 * ghost.buildProgress
			alpha = alpha * alphaMult
			glUniform(shaderObj.tint, tint[1], tint[2], tint[3])
			glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, alpha)
		end
		glUnitShape(defID, teamID, true)
	end

	-- if ghost.inProgress or not spIsUnitIcon(unitID) then
	glBlending(GL_SRC_ALPHA, GL_ONE) --glow effect
	if shaderObj then
		glUniform(shaderObj.teamColorID, teamColorR, teamColorG, teamColorB, 0.6 * alphaMult )
		if ghost.ofImportance then
			glUniform(shaderObj.tint, 0.5, 0.5, 0.5)
		else
			glUniform(shaderObj.tint, teamColorR/1.5, teamColorG/1.5, teamColorB/1.5)	
		end
	end
	glUnitShape(defID, teamID, true)

	glUnitShapeTextures(defID, false)
	glPopMatrix()

	-- glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) --normal blending
	-- glBlending(false)

end


local function DrawGhostUnits()
	if not next(ghostUnits) then
		return
	end

	-- glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 34160) --34160 = GL_COMBINE_RGB_ARB
	-- --use the alpha given by glColor for the outgoing alpha, else it would interpret the teamcolor channel as alpha one and make model transparent.
	-- glTexEnv(GL_TEXTURE_ENV, 34162, GL_REPLACE) --34162 = GL_COMBINE_ALPHA
	-- glTexEnv(GL_TEXTURE_ENV, 34184, 34167) --34184 = GL_SOURCE0_ALPHA_ARB, 34167 = GL_PRIMARY_COLOR_ARB

	-- glColor(0.3, 1.0, 0.3, 0.25)
	glColor(1,1,1,1)
	glDepthTest(true)

	gl.Blending(GL.SRC_ALPHA, GL.ONE)

	if shaderObj then
		-- glUseShader(shaderObj.shader)
	end
	local time = os.clock()
	-- local count = 0
	-- local drawcount = 0
	for unitID, ghost in pairs(ghostUnits) do
		-- count = count + 1
		if ghost.draw and not inSight[unitID] then
			-- drawcount = drawcount + 1
			if ghost.timeout - time < 0 then
				timeExpiredCnt = timeExpiredCnt + 1
				ghost.draw = false
				DeleteGhost(ghost, unitID)
				-- Echo('unit',unitID, 'has expired')
			elseif spIsSphereInView(ghost[1], ghost[2], ghost[3]) then
				-- drawcount = drawcount + 1
				DrawGhost(ghost, time)
			end
			-- Echo("Draw ghost unit", unitID, ghost.identified)
		end
	end
	if shaderObj then
		-- glUseShader(0)
	end
	glColor(1,1,1,1)


	--------------------------Clean up-------------------------------------------------------------
	-- glTexEnv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 8448) --8448 = GL_MODULATE
	-- --use the alpha given by glColor for the outgoing alpha.
	-- glTexEnv(GL_TEXTURE_ENV, 34162, 8448) --34162 = GL_COMBINE_ALPHA, 8448 = GL_MODULATE
	-- --glTexEnv(GL_TEXTURE_ENV, 34184, 5890) --34184 = GL_SOURCE0_ALPHA_ARB, 5890 = GL_TEXTURE

	-- Echo(drawcount .. ' ghost sites drawn.')
end

function widget:GameFrame(f)
	gameFrame = f
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
	if doGhostUnits then
		UpdateGhostSites()
	end
end

function widget:UnitLeftLos(id, teamID) -- we can get the pos when unit leave los but not the heading
	local ghost = ghostUnits[id]
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

function widget:UnitEnteredLos(id, teamID)
	if not doGhostUnits then
		return
	end
	local unit = Units[id]
	if not unit then
		return
	end
	-- Echo('unit', id, 'entered LOS', 'ghost ?', ghost)

	local defID = unit.defID
	if defID == mineDefID or isImmobileDefID[defID] then
		return
	end
	local buildProgress = unit.health[5]
	local valid = buildProgress and buildProgress > 0.02 --and (ofImportance or buildProgress<1)
	if not valid then
		return
	end
	local ghost = ghostUnits[id]
	-- update ghost
	if ghost then
		ghost.draw = false
		ghost.inLos = true
		ghost[1], ghost[2], ghost[3] = unpack(unit.pos)
		UpdateUnitPool[id] = ghost
		ghost.identified = ghost[4]
		return
	else
	-- create ghost
		NewGhostUnit(id, defID, teamID, buildProgress, unit)
	end

end






function widget:UnitLeftRadar(id, unitTeam) -- unit leave radar even where there is no radar after leaving LoS
	local struct = structureDiscovered[id]
	if struct then
		struct_ordered[unitTeam][struct.defID][id] = struct
		return
	end
	local ghost = doGhostUnits and ghostUnits[id]
	if not ghost then
		return
	end

	UpdateUnitPool[id] = nil
	ghost.inRadar = false
	if ghost.buildProgress and ghost.buildProgress < 0.02 then
		ghost.draw = false
	elseif ghost.isUnit then
		if ghost.identified then
			ghost.timeout = osclock() + ghost.maxTimeout
			ghost.draw = true
			ghost.identified = false
		end
	else
		ghost.draw = true
	end
end

function widget:UnitEnteredRadar(id, teamID)
	local struct = structureDiscovered[id]
	if struct then
		struct_ordered[teamID][struct.defID][id] = nil
		return
	end
	local ghost = ghostUnits[id]
	if not ghost then
		return
	end
	local unit = Units[id]
	if not unit then
		return
	end
	-- NOTE:when unit enter Los without radar coverage, UnitEnteredRadar get triggered AFTER UnitEnteredLos
	ghost.identified = (--[[not ghost.isUnit or]] ghost.inLos) and unit.defID
	ghost.inRadar = true
	if not ghost.isUnit then
		ghost.draw = false
	end
	-- Echo('unit ' .. id .. 'entered radar, identified ?', ghost.identified, 'is Unit ?',ghost.isUnit, 'draw?', ghost.draw,math.round(os.clock()))
end

function widget:UnitDestroyed(id, defID, teamID)
	DeleteGhost(ghostUnits[id], id)
end


function widget:PlayerChanged(playerID)
	if playerID == myPlayerID then
		local wasSpec, wasFullRead = isSpec, isFullRead
		isSpec, isFullRead = Spring.GetSpectatingState()
		local myOldTeamID = myTeamID
		myTeamID = Spring.GetMyTeamID()
		if myTeamID ~= myOldTeamID then
			GetTeamColors()
		end
		local myNewAllyTeamID =Spring.GetMyAllyTeamID()
		if myNewAllyTeamID ~= myAllyTeamID then
			myAllyTeamID = myNewAllyTeamID
			for teamID in pairs(struct_ordered) do
				struct_ordered[teamID] = nil
			end
			structureDiscovered = WG.structDiscoveredByAllyTeams[myAllyTeamID]
			if not isFullRead then
				for id, struct in pairs(structureDiscovered) do
					if not struct.unit.isInRadar then
						widget:UnitLeftRadar(id, struct.teamID)
					end
				end
			end
		end
	end
	
end

local GL_STENCIL_LESS = GL.GREATER  -- NOTE: this is totally bugged GL.GREATER work as GL.LESS for gl.StencilFunc(), and probably GL.LESS work as GL.GREATER

function widget:DrawWorld()
	if Cam.fullview == 1 then
		return
	end
	if shaderObj then
		glUseShader(shaderObj.shader)
	end
	-- gl.Culling(GL.BACK)
	-- gl.Culling(true)


	-- limit draw to nlayers?
	-- local nlayers = 3;
	-- gl.Blending(GL.SRC_ALPHA, GL.ONE)
	-- gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	-- gl.StencilTest(true)
	-- gl.StencilMask(0xff)
	-- gl.StencilFunc(GL_STENCIL_LESS, 2 * nlayers - 1 , 0xff)
	-- gl.StencilOp(GL.KEEP, GL.KEEP, GL.INCR) 



	DrawGhostSites()
	if doGhostUnits then
		DrawGhostUnits()
	end
	gl.StencilTest(false)
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	gl.Culling(false)

	if shaderObj then
		glUseShader(0)
	end

	ResetGl()
end



local myWidgetName = widget:GetInfo().name
function WidgetWakeNotify(w,name,preloading)
	if name == myWidgetName then
		Init()
	end

end


local oldWidget
function widget:Initialize()
	oldWidget = widgetHandler:FindWidget("Ghost Site")
	if oldWidget then
		widgetHandler:RemoveWidget(oldWidget)
		oldWidget = true
	end
	Cam = WG.Cam
	if not Cam and Cam.Units then
		Echo(widget.GetInfo().name ..  ' requires api_view_changed.lua and api_unit_data.lua and api_unit_handler.lua to work.')
		widgetHandler:Remove(widget)
		return
	end
	Units = Cam and Cam.Units
	inSight = Cam and Cam.inSight

	WG.ghostUnits = WG.ghostUnits or ghostUnits
	ghostUnits = WG.ghostUnits
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
	if WG.tex and EDIT_MODE then
		local file = LUAUI_DIRNAME .. "Config/ZK_data.lua"
		local config = VFS.Include(file, nil, VFS.RAW_FIRST)
		if config[widget:GetInfo().name] then
			config[widget:GetInfo().name].tex = WG.tex
			table.save(config, file, '-- Widget Custom Data')
		end
	end
	if shaderObj then
		glDeleteShader(shaderObj.shader)
	end
	for _, ghost in pairs(ghostUnits) do
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
	for _, list in pairs(lists) do
		glDeleteList(list)
	end
	if oldWidget then
		widgetHandler:EnableWidget("Ghost Site")
	end
end			










------------------------------------------
local goodtex, gamePaused, time, right

if EDIT_MODE then
	local goodMode = true
	-- gamePaused = select(3, Spring.GetGameSpeed())
	-- time = math.round(os.clock())
	-- function widget:GamePaused(_, status)
	-- 	gamePaused = status
	-- end
	WG.tex = WG.tex or 1
		goodtex = {
		[19] = 'asteroid',
		[62] = 'cloakaa',
		[73] = 'comm_battle_pea',
		[80] = 'comm_cai_hispeed_0',
		[86] = 'comm_cai_range_0',
		[92] = 'comm_cai_riot',
		[98] = 'comm_cai_specialist',
		[105] = 'comm_campaign_biovizier',
		[109] = 'comm_campaign_odin',
		[110] = 'comm_campaign_praetorian',
		[111] = 'comm_campaign_promethean',
		[112] = 'comm_econ_cai',
		[113] = 'comm_flamer',
		[115] = 'comm_hammer',
		[116] = 'comm_hunter',
		[162] = 'commrecon0',
		[174] = 'commsupport0',
		[180] = 'corcom0',
		[194] = 'dronefighter',
		[197] = 'dynassault0',
		[219] = 'dynfancy_recon2_base',
		[223] = 'dynfance_support2_base',
	}
	local file = LUAUI_DIRNAME .. "Config/ZK_data.lua"
	local config = VFS.Include(file, nil, VFS.RAW_FIRST)
	if not config[widget:GetInfo().name] then
		config[widget:GetInfo().name] = {}
		config[widget:GetInfo().name].goodtex = goodtex
		config[widget:GetInfo().name].tex = WG.tex
		table.save(config, file, '-- Widget Custom Data')
	else
		goodtex = config[widget:GetInfo().name].goodtex
		WG.tex = config[widget:GetInfo().name].tex or WG.tex
	end


	right = 275
	local left, S, Q = 276, 115, 113
	function widget:KeyPress(key, mods, isRepeat)
		if key == Q and mods.ctrl and not isRepeat then
			if goodtex[WG.tex] then
				Echo('deleted', WG.tex, goodtex[WG.tex])
				local old =  WG.tex
				WG.tex = next(goodtex, WG.tex) or next(goodtex)
				Echo('testing ' .. (goodMode and next(goodtex) and 'only good' or ''), WG.tex, UnitDefs[WG.tex].name, goodtex[WG.tex] and 'in goodtex' or '')
				goodtex[old] = nil
				table.save(config, file, '-- Widget Custom Data')
				-- f.Page(goodtex,{tocode = true, clip = true, show = false,})
			else
				Echo(WG.tex, goodtex[WG.tex], 'is not there')
			end
		end
		if key == S and mods.ctrl and not isRepeat then
			if not goodtex[WG.tex] then
				goodtex[WG.tex] = UnitDefs[WG.tex].name
				table.save(config, file, '-- Widget Custom Data')
				Echo('saved', WG.tex, goodtex[WG.tex])
				-- f.Page(goodtex,{tocode = true, clip = true, show = false,})
			else
				Echo(WG.tex, goodtex[WG.tex], 'is already there')
			end

		elseif key == left then
			if goodMode and next(goodtex) then
				local nex = next(goodtex)
				while nex do
					local _nex = next(goodtex, nex)
					if _nex == WG.tex then
						break
					end
					nex = _nex
				end
				WG.tex = nex or next(goodtex)
			else
				WG.tex = math.max(WG.tex - 1, 1)
			end
		elseif key == right then
			if goodMode and next(goodtex) then
				WG.tex = goodtex[WG.tex] and next(goodtex, WG.tex) or next(goodtex)
			elseif UnitDefs[WG.tex + 1] then
				WG.tex = WG.tex + 1
			end
		else
			return
		end
		Echo('testing ' .. (goodMode and next(goodtex) and 'only good' or ''), WG.tex, UnitDefs[WG.tex].name, goodtex[WG.tex] and 'in goodtex' or '')
		return true
	end
end

------------------------------------------
f.DebugWidget(widget)










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
			local ghost   = ghostUnits[unitID]
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
					ghostUnits[unitID] = nil
					-- Echo(unitID,'defID',udefID,'has been removed')
				else
					if ghost.inProgress then
						local _,_,_,_, buildProgress = spGetUnitHealth(unitID)
						if buildProgress then
							local valid = buildProgress>0.02 -- and (ghost.ofImportance or buildProgress<1)
							if not valid then 
								-- Echo(unitID,'defID',udefID,'has been removed')
								ghostUnits[unitID] = nil
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