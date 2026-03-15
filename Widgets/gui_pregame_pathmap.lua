function widget:GetInfo()
	return {
		name      = "Pregame Path Map",
		desc      = "Show path heat map at pregame for different unit type",
		author    = "Helwor",
		date      = "Mar 2026",
		license   = "GNU GPL, v2 or later",
		layer     = -1, -- after decloak range
		enabled   = false,
		handler   = true,
	}
end

local sig = '['..widget:GetInfo().name..']: '
local slowUpdate = 150 -- 150 frames 5 sec
local resolution = 16 -- big impact on perf
local alpha = 0.15
local active = false
local dispatchSize2D = 8 -- can be upped if gpu have > 64 threads but the computing anyway is very light
-- work around with low resolution triangles to make them show despite being eaten by the ground, far from perfect
local poly_offset = 0
local poly_offset_fact = 0
local depth_pow = 1.029 -- finally only using depth_pow and tinkering it with slope in the frag shader
local depth_mul = 0
------


local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir .. "LuaShader.lua")
VFS.Include(luaShaderDir .. "instancevbotable.lua")

local factoryDefs = {}
do

	local factories = {
		'factoryshield',
		'factorycloak',
		'factoryveh',
		-- 'factoryplane',
		-- 'factorygunship',
		'factoryhover',
		'factoryamph',
		-- 'factoryspider',
		'factoryjump',
		'factorytank',
		'factoryship',
		-- 'striderhub',
		'plateshield',
		'platecloak',
		'plateveh',
		-- 'plateplane',
		-- 'plategunship',
		'platehover',
		'plateamph',
		-- 'platespider',
		'platejump',
		'platetank',
		'plateship',
	}

	for i = 1, #factories do
		local factoryName = factories[i]
		factoryDefs[UnitDefNames[factoryName].id] = true
	end
end


local mapVBO, mapVAO, slopeSSBO
local mapShader, compShader

local updateVBOs = false
local newCompute = true

options = {}
options_path = 'Hel-K/' .. widget.GetInfo().name

options.alpha = {
	name = 'Alpha',
	type = 'number',
	value = alpha,
	update_on_the_fly = true,
	min = 0, max = 1.0, step = 0.01,
	OnChange = function(self)
		alpha = self.value
	end,
}

options.resolution = {
	name = 'Resolution',
	desc = 'Impact the perf a lot',
	type = 'number',
	value = resolution,
	update_on_the_fly = true,
	min = 8, max = 32, step = 1,
	OnChange = function(self)
		resolution = self.value
		updateVBOs = true
	end,
}

options.active = {
	name = 'Always Active',
	type = 'bool',
	value = active,
	OnChange = function(self)
		active = self.value
	end,
}

options.poly_offset = {
	name = 'Polygon offset',
	type = 'number',
	value = poly_offset,
	update_on_the_fly = true,
	min = -500, max = 0, step = 1,
	OnChange = function(self)
		poly_offset = self.value
	end,
	dev = true,
}

options.poly_offset_fact = {
	name = 'Polygon offset fact',
	type = 'number',
	value = poly_offset_fact,
	update_on_the_fly = true,
	min = -50, max = 0, step = 0.1,
	OnChange = function(self)
		poly_offset_fact = self.value
	end,
	dev = true,
}
options.depth_pow = {
	name = 'Depth Pow Mod',
	type = 'number',
	value = depth_pow,
	update_on_the_fly = true,
	min = 1, max = 1.1, step = 0.001,
	OnChange = function(self)
		depth_pow = self.value
	end,
	dev = true,
}

options.depth_mul = {
	name = 'Depth Mul',
	desc = 'multiply Depth by 1 - (value / 1e5)',
	type = 'number',
	value = depth_mul,
	update_on_the_fly = true,
	min = 0, max = 100, step = 1,
	OnChange = function(self)
		depth_mul = 1 - (self.value / 1e5)
	end,
	dev = true,
}

local function goodbye(reason)
	Spring.Echo(sig .. "exiting with reason: " .. reason)
	widgetHandler:RemoveWidget()
end

local function zeroTable(n)
	local t = {}
	for i = 1, n do
		t[i] = 0
	end
	return t
end
local function ComputeSlopes()
	newCompute = false
	gl.Texture(0, "$heightmap")
	compShader:Activate()
	compShader:SetUniform("resolution", resolution)
	local groupsX = math.ceil((Game.mapSizeX/resolution) / dispatchSize2D)
	local groupsY = math.ceil((Game.mapSizeZ/resolution) / dispatchSize2D)
	gl.DispatchCompute(groupsX, groupsY, 1)
	-- SLOPES = slopeSSBO:Download(-1, 0, nil, true)
	compShader:Deactivate()
	gl.Texture(0, false)
end

local function UpdateVBOs()
	updateVBOs = false
	local sizeX, sizeZ = Game.mapSizeX / resolution, Game.mapSizeZ / resolution
	if mapVBO then
		mapVBO:Delete()
	end
	mapVBO = makePlaneVBO(1, 1, sizeX, sizeZ)
	if not mapVBO then
		goodbye('invalid mapVBO')
		return false
	end
	if mapVAO then
		mapVAO:Delete()
	end
	local indice = makePlaneIndexVBO(sizeX, sizeZ)
	mapVAO = gl.GetVAO()
	if not mapVAO then
		goodbye('invalid mapVAO')
		return false
	end
	mapVAO:AttachVertexBuffer(mapVBO)
	mapVAO:AttachIndexBuffer(indice)
	-------
	if slopeSSBO then
		slopeSSBO:Delete()
	end
	slopeSSBO = gl.GetVBO(GL.SHADER_STORAGE_BUFFER, false)
	if not slopeSSBO then
		goodbye('invalid slopeSSBO')
		return false
	end
	local size = ((sizeX + 1) * (sizeZ + 1))
	local nvecs = math.ceil(size / 4)
	slopeSSBO:Define(nvecs, {{id = 1, name = "slopes", type = GL.FLOAT_VEC4, size = 1}})
	slopeSSBO:BindBufferRange(4) -- can't bind below 4
	slopeSSBO:Upload(zeroTable(nvecs * 4)) -- zero the memory just in case?
	newCompute = true
	return true
end

local function MakeComputeShader()
	if compShader then
		compShader:Delete()
	end
	compShader = LuaShader.CheckShaderUpdates({
		cssrcpath = "LuaUI/Widgets/Shaders/pregame_pathmap.comp.glsl",
		uniformInt = {
			heightmapTex = 0,
		},
		uniformFloat = {
			invMapSize = {1.0/Game.mapSizeX, 1.0/Game.mapSizeZ},
			mapSize = {Game.mapSizeX, Game.mapSizeZ},
			mapCenter = {Game.mapSizeX / 2, Game.mapSizeZ / 2},
			alpha = alpha,
		},
		shaderConfig = {},
		shaderName = sig.." compute Shader GL4"
	})
	if not compShader then
		goodbye('compShader compilation failed')
		return false
	end

	return true
end
local function MakeMapShader()
	if mapShader then
		mapShader:Delete()   
	end
	mapShader = LuaShader.CheckShaderUpdates({
		vssrcpath = "LuaUI/Widgets/Shaders/pregame_pathmap.vert.glsl",
		fssrcpath = "LuaUI/Widgets/Shaders/pregame_pathmap.frag.glsl",
		uniformInt = {
			heightmapTex = 0,
		},
		uniformFloat = {
			invMapSize = {1.0/Game.mapSizeX, 1.0/Game.mapSizeZ},
			mapSize = {Game.mapSizeX, Game.mapSizeZ},
			mapCenter = {Game.mapSizeX / 2, Game.mapSizeZ / 2},
			alpha = alpha,
		},
		shaderConfig = {},
		shaderName = sig.." Shader GL4"
	})
	if not mapShader then
		goodbye('mapShader compilation failed')
		return false
	end
	return true
end

local function initgl4()
	if not gl.CreateShader then
		goodbye("Cannot create shader")
		return
	end
	return UpdateVBOs() and MakeComputeShader() and MakeMapShader()
end

local function DrawHeightMap()
	-- don't surimpose triangles
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	gl.StencilTest(true)
	gl.StencilMask(1)
	gl.StencilFunc(GL.EQUAL, 0, 1)  
	gl.StencilOp(GL.KEEP, GL.KEEP, GL.INCR) 
	-- dont show back of triangles
	gl.Culling(true)
	gl.Culling(GL.BACK)
	-- additive blending
	gl.Blending(GL.SRC_ALPHA, GL.ONE)  
	gl.Blending(true)
	-- don't show behind ground
	gl.DepthTest(true)
	-- pull triangles more to the front for the edges of ground to not eat them
	gl.PolygonOffset(poly_offset_fact, poly_offset)

	gl.Texture(0, "$heightmap") -- used as sampler by the shader
	mapShader:Activate()

	mapShader:SetUniform("alpha", alpha)
	mapShader:SetUniform("resolution", resolution)
	mapShader:SetUniform("depth_pow", depth_pow)
	mapShader:SetUniform("depth_mul", depth_mul)

	mapVAO:DrawElements(GL.TRIANGLES)

	mapShader:Deactivate()

	gl.PolygonOffset(0, 0)
	gl.Texture(0, false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	gl.DepthTest(false)
	gl.Culling(false)

	gl.StencilTest(false)
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
end
function widget:GameFrame(f)
	if f%slowUpdate == 0 then
		newCompute = true
	end
end
function widget:Update() -- get the option values before Initializing
	initgl4()
	widgetHandler:RemoveWidgetCallIn('Update', widget)
end

function widget:DrawWorldPreUnit()
	if Spring.IsGUIHidden() then
		return
	end
	if not (active or WG.InitialQueue and factoryDefs[-(select(2, Spring.GetActiveCommand()) or 0)]) then
		return
	end

	if updateVBOs then
		if not UpdateVBOs() then
			return
		end
	end
	if newCompute then
		ComputeSlopes()
	end
	DrawHeightMap()
end

function widget:Shutdown()
	if mapVAO then
		mapVAO:Delete()
		mapVAO = nil
	end
	if mapVBO then
		mapVBO:Delete()
		mapVBO = nil
	end
	if mapShader then
		mapShader:Delete()
		mapShader = nil
	end
	if compShader then
		compShader:Delete()
	end
	if slopeSSBO then
		slopeSSBO:Delete()
	end
end

