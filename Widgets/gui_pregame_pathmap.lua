function widget:GetInfo()
	return {
		name      = "Pregame Path Map",
		desc      = "Show path heat map at pregame for different unit type",
		author    = "Helwor",
		date      = "Mar 2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = false,
		handler   = true,
	}
end
local debugging = false
local vsx, vsy
local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir .. "LuaShader.lua")
local shaderConfig = {}
local identityShaderVert = VFS.LoadFile("LuaUI/Widgets/Shaders/identity.vert.glsl")
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

local sig = '['..widget:GetInfo().name..']: '
local swapFBO, swapTex, maskTex, borderShader
local radarFBO
local mapShader
local mapVBO
local resolution = 8
local active = true
local poly_offset = -6
local alpha = 0.4

options = {}
options_path = 'Hel-K/' .. widget.GetInfo().name

options.alpha = {
	name = 'Alpha',
	type = 'number',
	value = alpha,
	update_on_the_fly = true,
	min = 0.1, max = 1.0, step = 0.01,
	OnChange = function(self)
		alpha = self.value
	end,
}

options.poly_offset = {
	name = 'Polygon offset',
	type = 'number',
	value = poly_offset,
	update_on_the_fly = true,
	min = -50, max = 50, step = 1,
	OnChange = function(self)
		poly_offset = self.value
	end,
	hidden = not debugging,
}

options.active = {
	name = 'Active',
	type = 'bool',
	value = active,
	OnChange = function(self)
		active = self.value
	end,
	hidden = not debugging,
}

local function goodbye(reason)
	Spring.Echo(sig .. "exiting with reason: " .. reason)
	widgetHandler:RemoveWidget()
end
function MakeMapVBO()
	local sizeX, sizeZ = Game.mapSizeX / resolution, Game.mapSizeZ / resolution
	mapVBO = makePlaneVBO(1, 1, sizeX, sizeZ)
	local indice = makePlaneIndexVBO(sizeX, sizeZ)
	mapVAO = gl.GetVAO()
	mapVAO:AttachVertexBuffer(mapVBO)
	mapVAO:AttachIndexBuffer(indice)
end

local function InitShader()
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
	return mapShader
end
local function initgl4()
	if not InitShader() then
		goodbye('mapShader compilation failed')
		return false
	end

	MakeMapVBO()
	return true
end
local startDraw, endDraw
local function DrawHeightMap()
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	gl.StencilTest(true)
	gl.StencilMask(1)
	gl.StencilFunc(GL.EQUAL, 0, 1)  
	gl.StencilOp(GL.KEEP, GL.KEEP, GL.INCR) 

	gl.Culling(true)
	gl.Culling(GL.BACK)
	gl.Blending(GL.SRC_ALPHA, GL.ONE)  
	gl.Blending(true)
	gl.DepthTest(true)
	gl.Texture(0, "$heightmap")
	gl.PolygonOffset(poly_offset, poly_offset)


	mapShader:Activate()
	mapShader:SetUniform("alpha", alpha)
	mapVAO:DrawElements(GL.TRIANGLES)

	mapShader:Deactivate()


	gl.PolygonOffset(0, 0)
	gl.Texture(0, false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	gl.DepthTest(false)
	gl.Culling(false)

	gl.StencilTest(false)
end

function widget:Update() -- get the option values before Initializing
	Init()
	widgetHandler:RemoveWidgetCallIn('Update', widget)
end
local drawList
function widget:DrawWorld()
	if not (WG.InitialQueue or debugging) then
		widgetHandler:RemoveWidget(widget)
		return
	end
	if not active or Spring.IsGUIHidden() then
		return
	end
	if not (debugging or factoryDefs[-(select(2, Spring.GetActiveCommand()) or 0)]) then
		return
	end
	DrawHeightMap()
end

function Init()
	vsx, vsy = Spring.Orig.GetViewSizes()
	if not gl.CreateShader then
		goodbye("Cannot create shader")
		return
	end

	if not initgl4() then
		return
	end
	initialized = true
end
function widget:GetViewSizes()
	vsx, vsy = Spring.Orig.GetViewSizes()
end

function widget:Initialize()
	if not (debugging or WG.InitialQueue) then
		Echo(sig .. ' disabled, not in Pre Game or don\'t have Initial Queue')
		widgetHandler:RemoveWidget(widget)
		return
	end
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
	if drawList then
		gl.DeleteList(drawList)
	end
end

