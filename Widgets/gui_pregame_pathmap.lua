function widget:GetInfo()
	return {
		name      = "Pregame Path Map",
		desc      = "Show path heat map at pregame (or any time) for different unit type",
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

local active = false
local dispatchSize2D = 8 -- can be upped but need to change the shader compute. if gpu have > 64 threads but the computing anyway is very light
-- work around with low resolution triangles to make them show despite being eaten by the ground, far from perfect
local poly_offset = 0
local poly_offset_fact = 0
local depth_pow = 1.029 -- finally only using depth_pow and tinkering it with slope in the frag shader
local depth_mul = 0
------
local intensity = 0.14 -- used for new gl.Blending(GL.ONE GL.ONE) instead of gl.Blending(GL.SRC_ALPHA, GL.ONE) 
------
-- debugging
-- local resolution = 16 -- big impact on perf
local botpass = 18
local off_step = 8
local texlod = 1
local mode = 'normal'
local checker = false
local highlight_back = false
local cull_back = true
------
local triangle_strip = true

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

-------
local mapVBO, mapVAO, slopeSSBO
local mapShader, compShader, decalShader
local tex
-------
local updateVBOs = false
local newCompute = true
local newDecal = true
local force_update = true
local use_decal = true
-------

options = {}
options_path = 'Hel-K/' .. widget.GetInfo().name

options.active = {
	name = 'Always Active',
	type = 'bool',
	value = active,
	OnChange = function(self)
		active = self.value
	end,
	hotkey = 'Shift+f2',
	category = 'user',
}

options.use_decal = {
	name = 'Use Decal',
	type = 'bool',
	value = use_decal,
	OnChange = function(self)
		use_decal = self.value
	end,
	category = 'user',
}

options.mode = {
	name = 'Display Mode',
	type = 'list',
	value = mode,
	items = {
		{key = 'normal', name = 'Normal'},
		{key = 'lines', name = 'Lines'},
		{key = 'line_strip', name = 'Lines Strip'},
	},
	
	OnChange = function(self)
		mode = self.value
		newDecal = true
	end,
	dev = true,
	category = 'dev',
}


options.cull_back = {
	name = 'Cull Back Face',
	type = 'bool',
	value = cull_back,
	OnChange = function(self)
		cull_back = self.value
		newDecal = true
	end,
	dev = true,
	category = 'dev_z',
}

options.highlight_back = {
	name = 'Highlight Back Face',
	type = 'bool',
	value = highlight_back,
	OnChange = function(self)
		highlight_back = self.value
		newDecal = true
	end,
	dev = true,
	category = 'dev_z',
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
	category = 'dev',
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
	category = 'dev',
}

options.checker = { 
	name = 'Checker Display',
	type = 'bool',
	value = checker,
	OnChange = function(self)
		checker = self.value
	end,
	dev = true,
	-- hidden = true,
	category = 'dev',
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
	category = 'dev',
}

options.depth_mul = { -- unused
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
	hidden = true,
	category = 'dev',
}


options.intensity = {
	name = 'Intensity',
	type = 'number',
	value = 0.3,
	update_on_the_fly = true,
	min = 0.01, max = 1.0, step = 0.01,
	OnChange = function(self)
		intensity = self.value
		newDecal = true
	end,
	category = 'user',
}

options.botpass = {
	name = "Bot Pass Threshold",
	type = 'number',
	value = botpass,
	min = 12, max = 20, step = 0.1,
	update_on_the_fly = true,
	OnChange = function(self)
		botpass = self.value
		newCompute = true
		newDecal = true
	end,
	dev = true,
	category = 'dev',
}

options.off_step = {
	name = "Comparaison Step",
	type = 'number',
	value = off_step,
	min = 4, max = 32, step = 0.1,
	update_on_the_fly = true,
	OnChange = function(self)
		off_step = self.value
		newCompute = true
		newDecal = true
	end,
	dev = true,
	category = 'dev',
}

options.texlod = {
	name = "Texture LOD",
	type = 'number',
	value = texlod,
	min = 0, max = 2, step = 1,
	update_on_the_fly = true,
	OnChange = function(self)
		texlod = self.value
		newCompute = true
		newDecal = true
	end,
	dev = true,
	category = 'dev',
}

-- options.resolution = {
-- 	name = 'Resolution',
-- 	desc = 'Impact the perf a lot',
-- 	type = 'number',
-- 	value = resolution,
-- 	update_on_the_fly = true,
-- 	min = 8, max = 32, step = 8,
-- 	OnChange = function(self)
-- 		resolution = self.value
-- 		updateVBOs = true
-- 	end,
-- 	dev = true,
-- 	category = 'dev',
-- }
options.triangle_strip = {
	name = 'Triangle Strip',
	type = 'bool',
	value = triangle_strip,
	OnChange = function(self)
		triangle_strip = self.value
		updateVBOs = true
		newDecal = true
	end,
	dev = true,
	category = 'dev',
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
	-- Echo('new compute', math.round(os.clock()))
	newCompute = false
	gl.Texture(0, "$heightmap")
	compShader:Activate()
	compShader:SetUniform("off_step", off_step)
	compShader:SetUniform("texlod", texlod)
	compShader:SetUniform("force_update", force_update and 1 or 0)
	local groupsX = math.ceil((Game.mapSizeX/16) / dispatchSize2D)
	local groupsY = math.ceil((Game.mapSizeZ/16) / dispatchSize2D)
	gl.DispatchCompute(groupsX, groupsY, 1)
	-- SLOPES = slopeSSBO:Download(-1, 0, nil, true)
	compShader:Deactivate()
	force_update = false
	newDecal = true
	gl.Texture(0, false)
end

local function UpdateVBOs()
	updateVBOs = false
	--------
	local sizeX, sizeZ = Game.mapSizeX / 32, Game.mapSizeZ / 32
	if mapVBO32 then
		mapVBO32:Delete()
	end
	mapVBO32 = makePlaneVBO(1, 1, sizeX, sizeZ)
	if not mapVBO32 then
		goodbye('invalid mapVBO32')
		return false
	end
	if mapVAO32 then
		mapVAO32:Delete()
	end
	numIndices32 = 1
	local indexVBO
	if triangle_strip then
		indexVBO, numIndices32 = makePlaneStripIndexVBO(sizeX, sizeZ)
	else
		indexVBO = makePlaneIndexVBO(sizeX, sizeZ)
	end
	mapVAO32 = gl.GetVAO()
	if not mapVAO32 then
		goodbye('invalid mapVAO')
		return false
	end
	mapVAO32:AttachVertexBuffer(mapVBO32)
	mapVAO32:AttachIndexBuffer(indexVBO)
	---------
	local sizeX, sizeZ = Game.mapSizeX / 16, Game.mapSizeZ / 16
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
	numIndices = 1
	local indexVBO
	if triangle_strip then
		indexVBO, numIndices = makePlaneStripIndexVBO(sizeX, sizeZ)
	else
		indexVBO = makePlaneIndexVBO(sizeX, sizeZ)
	end
	mapVAO = gl.GetVAO()
	if not mapVAO then
		goodbye('invalid mapVAO')
		return false
	end
	mapVAO:AttachVertexBuffer(mapVBO)
	mapVAO:AttachIndexBuffer(indexVBO)
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
	------

	newCompute = true
	return true
end

local function MakeComputeShader()
	if compShader then
		compShader:Delete()
	end
	compShader = LuaShader.CheckShaderUpdates({
		cssrcpath = "LuaUI/Widgets/Shaders/pregame_pathmap.comp.old.glsl",
		uniformInt = {
			heightmapTex = 0,
		},
		uniformFloat = {
			invMapSize = {1.0/Game.mapSizeX, 1.0/Game.mapSizeZ},
			mapSize = {Game.mapSizeX, Game.mapSizeZ},
			mapCenter = {Game.mapSizeX / 2, Game.mapSizeZ / 2},
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
		vssrcpath = "LuaUI/Widgets/Shaders/pregame_pathmap.vert.old.glsl",
		fssrcpath = "LuaUI/Widgets/Shaders/pregame_pathmap.frag.old.glsl",
		uniformInt = {
			heightmapTex = 0,
		},
		uniformFloat = {
			invMapSize = {1.0/Game.mapSizeX, 1.0/Game.mapSizeZ},
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

local function MakeDecalShader()
	local decalInclude = [[
	if (worldPos.y <= -16.0 && fragColor.r > 0.0){
		fragColor.r = 0.0;
	} else if (worldPos.y > -16.0 && fragColor.g > 0.0) {
		fragColor.g = 0.0;
	}

]]


	local decalShaderFrag = VFS.LoadFile('LuaUI/Widgets/Shaders/api_ground_decal_drawer.frag.glsl')
	if not decalShaderFrag then
		Echo(sig .. '[WARN] Missing widget API Ground Decal Drawer')
		return false
	end
	decalShaderFrag = decalShaderFrag:gsub("//__ENGINEUNIFORMBUFFERDEFS__", LuaShader.GetEngineUniformBufferDefs())
	decalShaderFrag = decalShaderFrag:gsub("//__USERINCLUDE__", decalInclude)
	local decalShaderVert = VFS.LoadFile('LuaUI/Widgets/Shaders/api_ground_decal_drawer.vert.glsl')
	decalShaderVert = decalShaderVert:gsub("//__ENGINEUNIFORMBUFFERDEFS__", LuaShader.GetEngineUniformBufferDefs())
	decalShader = LuaShader({
		vertex = decalShaderVert,
		fragment = decalShaderFrag,
		uniformInt = {
			mapDepths = 0,
			mapColors = 1,
			decalTex = 2,
		},
		uniformFloat = {
		},
		shaderConfig = {},
		shaderName = sig.." Decal Shader GL4"
	})

	if not decalShader:Initialize() then
		Echo(sig .. '[WARN] Failed to compile Decal Shader')
		return false
	end
end

local function initgl4()
	if not gl.CreateShader then
		goodbye("Cannot create shader")
		return
	end
	MakeDecalShader()
	return UpdateVBOs() and MakeComputeShader() and MakeMapShader()
end

local function CreateHeatmapTex()
	if not tex then
			tex = gl.CreateTexture(Game.mapSizeX/8, Game.mapSizeZ/8, {
			target = GL.TEXTURE_2D,
			format = GL.RGBA,
			border = false,
			min_filter = GL.LINEAR_MIPMAP_LINEAR,
			min_filter = GL.NEAREST,
			mag_filter = GL.LINEAR,
			wrap_s = GL.CLAMP_TO_EDGE,
			wrap_t = GL.CLAMP_TO_EDGE,
			-- fbo = true,
		})
	end
	if not fbo then
		fbo = gl.CreateFBO({
			color0 = tex,
			drawbuffers = {
				GL.COLOR_ATTACHMENT0_EXT,
			}
		})
	end
	-- gl.RenderToTexture(tex, function()
	gl.ActiveFBO(fbo, true, function()
		gl.Clear(GL.COLOR_BUFFER_BIT, 0,0,0,0)
		-- gl.Color(1,1,1,1)
		-- gl.BeginEnd(GL.TRIANGLES, function()
		-- 	gl.Color(1,0,0,1)
		-- 	gl.Vertex(0.5,1,0)
		-- 	gl.Vertex(-0.5,1,0)
		-- 	gl.Color(0,0,0,0)
		-- 	gl.Vertex(0,0.5,0)
		-- end)

		gl.Culling(GL.FRONT) -- reversed in fbo
		gl.DepthTest(false)
		gl.Blending(false)
		-- gl.Blending(GL.SRC_ALPHA, GL.ONE)
		gl.Texture(0, "$heightmap")
		mapShader:Activate()
		mapShader:SetUniform("checker", checker and 1 or 0)
		mapShader:SetUniform("texture_mode", 1)
		mapShader:SetUniform("highlight_back", 0)
		mapShader:SetUniform("intensity", intensity)
		mapShader:SetUniform("botpass", botpass)

		local vao, num
		vao = mapVAO
		num = numIndices

		if triangle_strip then
			vao:DrawElements(mode == 'lines' and GL.LINES or mode == 'line_strip' and GL.LINE_STRIP or GL.TRIANGLE_STRIP, num)
		else
			vao:DrawElements(mode == 'lines' and GL.LINES or mode == 'line_strip' and GL.LINE_STRIP or GL.TRIANGLES)
		end
		mapShader:Deactivate()
		gl.Texture(0, false)
		gl.DepthTest(false)
		gl.Culling(false)

		gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	end)
	gl.GenerateMipmap(tex)
end

local function DrawHeatMap()
	-- dont show back of triangles
	if highlight_back or not cull_back then
		gl.Culling(false)
	else
		gl.Culling(GL.BACK)
	end
	-- don't surimpose triangles
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	gl.StencilTest(true)
	gl.StencilMask(1)
	gl.StencilFunc(GL.EQUAL, 0, 1)  
	gl.StencilOp(GL.KEEP, GL.KEEP, GL.INCR) 
	-- strong additive blending
	gl.Blending(GL.ONE, GL.ONE)  

	gl.Blending(true)
	-- don't show behind ground
	gl.DepthTest(true)
	-- pull triangles more to the front for the edges of ground to not eat them
	gl.PolygonOffset(poly_offset_fact, poly_offset)

	gl.Texture(0, "$heightmap") -- used as sampler by the shader

	mapShader:Activate()
	-- mapShader:SetUniform("resolution", resolution)
	mapShader:SetUniform("highlight_back", highlight_back and 1 or 0)
	mapShader:SetUniform("depth_pow", depth_pow)
	mapShader:SetUniform("depth_mul", depth_mul)
	mapShader:SetUniform("intensity", intensity)
	mapShader:SetUniform("botpass", botpass)
	mapShader:SetUniform("texlod", botpass)
	mapShader:SetUniform("texture_mode", 0)

	local vao, num
	if WG.Cam.relDist < 3000 then
		vao = mapVAO
		num = numIndices
	else
		vao = mapVAO32
		num = numIndices32
	end
	if lastvao ~= vao then
		lastvao = vao
	end
	if triangle_strip then
		vao:DrawElements(mode == 'lines' and GL.LINES or mode == 'line_strip' and GL.LINE_STRIP or GL.TRIANGLE_STRIP, num)
	else
		vao:DrawElements(mode == 'lines' and GL.LINES or mode == 'line_strip' and GL.LINE_STRIP or GL.TRIANGLES)
	end
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

	decalMode = use_decal and WG.GroundDecalTexture and select(2, Spring.HaveAdvShading())

	if newCompute then
		ComputeSlopes()
	end
	if decalMode then
		if newDecal then
			CreateHeatmapTex()
			newDecal = false
		end
		WG.GroundDecalTexture(tex, 0, 0, Game.mapSizeX, Game.mapSizeZ, true, 0, decalShader)
	else
		DrawHeatMap()
	end
end

function widget:Shutdown()
	if tex then
		-- gl.DeleteTextureFBO(tex)
		gl.DeleteTexture(tex)
	end
	if tex2 then
		-- gl.DeleteTextureFBO(tex2)
		gl.DeleteTexture(tex2)
	end
	if fbo then
		gl.DeleteFBO(fbo)
	end
	if mapVAO then
		mapVAO:Delete()
		mapVAO = nil
	end
	if mapVBO then
		mapVBO:Delete()
		mapVBO = nil
	end
	if mapVAO32 then
		mapVAO32:Delete()
		mapVAO32 = nil
	end
	if mapVBO32 then
		mapVBO32:Delete()
		mapVBO32 = nil
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
	if decalShader then
		decalShader:Delete()
	end
end

f.DebugWidget(widget)