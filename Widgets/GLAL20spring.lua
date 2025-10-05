-- Spring OpenGL abstraction layer (GLAL). Abstracts away the difference between maintenance and develop engines
-- Author: ivand/LHoG
if true then
	return
end
local isDevelop = (gl.CreateVertexArray ~= nil)

if isDevelop then
-----------------------------------------------------------------
-- Develop
-----------------------------------------------------------------

local orig = {
	Vertex = gl.Vertex,
	BeginEnd = gl.BeginEnd,
	Color = gl.Color,
	UseShader = gl.UseShader,
	ActiveShader = gl.ActiveShader,
	TexRect = gl.TexRect,
	Rect = gl.Rect,
	Texture = gl.Texture,
	LoadFont = gl.LoadFont,
	DeleteFont = gl.DeleteFont,
}

local inBeginEnd = false --TODO remove ?

-----------------------------------------------------------------
-- Misc functions
-----------------------------------------------------------------


-----------------------------------------------------------------
-- Display list functions
-----------------------------------------------------------------

gl.CreateList = function(functionName, ...)
	return {
		func = functionName,
		args = {...},
	}
end

gl.CallList = function(dl)
	dl.func(unpack(dl.args))
end

gl.DeleteList = function(dl)
	dl = nil
end

-----------------------------------------------------------------
-- Unit functions
-----------------------------------------------------------------

gl.DrawListAtUnit = function(unitID, listID, midPos, ...)
	gl.DrawFuncAtUnit(unitID, listID, midPos)
end

-----------------------------------------------------------------
-- Line functions
-----------------------------------------------------------------

gl.LineStipple = function(arg1, arg2)
	-- Not Implemented
end

gl.LineWidth = function(width)
	-- Not Implemented
end

-----------------------------------------------------------------
-- State functions
-----------------------------------------------------------------

gl.Fog = function(width)
	-- Not Implemented
end

gl.FogCoord = function(width)
	-- Not Implemented
end

gl.PointSize = function(size)
	-- Not Implemented
end

gl.AlphaTest = function(arg1, arg2)
	-- Not Implemented
end

-----------------------------------------------------------------
-- FFP vertex functions
-----------------------------------------------------------------

local vertexCounter = 0
gl.Vertex = function(arg1, arg2, arg3, arg4)
	vertexCounter = vertexCounter + 1
	orig.Vertex(arg1, arg2, arg3, arg4)
end


local currentColor = {0, 0, 0, 0, 0, 0, 0}
gl.Color = function(r, g, b, a)
	if type(r) == "table" then
		local primColor = unpack(r)
		currentColor[1] = primColor[1]
		currentColor[2] = primColor[2]
		currentColor[3] = primColor[3]
		currentColor[4] = primColor[4]
	else
		currentColor[1] = r
		currentColor[2] = g
		currentColor[3] = b
		currentColor[4] = a
	end

	orig.Color(
		currentColor[1],
		currentColor[2],
		currentColor[3],
		currentColor[4],
		currentColor[5],
		currentColor[6],
		currentColor[7])
end

gl.SecondaryColor = function(r, g, b)
	currentColor[5] = r
	currentColor[6] = g
	currentColor[7] = b
end

-----------------------------------------------------------------
-- Shader functions
-----------------------------------------------------------------

local activeShader = 0
gl.UseShader = function(shaderID)
	if shaderID == 0 then
		activeShader = 0
	else
		 --don't care if shader is wrong, it's only for bookkeeping purpose
		activeShader = shaderID
	end
	orig.UseShader(shaderID)
end

gl.ActiveShader = function(shaderID, glFunc, ...)
	if shaderID == 0 then
		activeShader = 0
		return
	end

	activeShader = shaderID
	orig.ActiveShader(shaderID, glFunc, ...)
	activeShader = 0
end

-----------------------------------------------------------------
-- Texture functions
-----------------------------------------------------------------

local boundTextures = {}
gl.Texture = function(arg1, arg2)
	local tu
	local tex
	if arg2 == nil then
		tu = 0
		tex = arg1
	else
		tu = arg1
		tex = arg2
	end
	boundTextures[tu] = tex
	orig.Texture(tu, tex)
end


-----------------------------------------------------------------
-- Shape functions
-----------------------------------------------------------------


local lastDF = -1
local vertIndices
local quadIndex = 0
local function UpdateVertexIndicesForQuad()
	local df = Spring.GetDrawFrame()

	if lastDF ~= df then
		lastDF = df
		quadIndex = 0
	end

	vertIndices = {}
	local quadsCount = math.floor(vertexCounter / 4)
	for quad = 0, quadsCount - 1 do
		local q = quad + quadIndex
		-- Upper triangle of QUAD
		table.insert(vertIndices, 4 * q + 0) --tl
		table.insert(vertIndices, 4 * q + 1) --tr
		table.insert(vertIndices, 4 * q + 2) --br

		-- Lower triangle of QUAD
		table.insert(vertIndices, 4 * q + 2) --br
		table.insert(vertIndices, 4 * q + 3) --bl
		table.insert(vertIndices, 4 * q + 0) --tl
	end

	quadIndex = quadIndex + quadsCount

	gl.VertexIndices(vertIndices)
end


--[[
struct VA_TYPE_L {
	float4 p; // Lua can freely set the w-component
	float3 n;
	float4 uv; // two channels for basic texturing
	SColor c0; // primary
	SColor c1; // secondary
};
]]--
local vaTypeLShaderSources = {
	vs =
[[
#version 410 core
#extension GL_ARB_explicit_attrib_location : enable
// defines
#define VA_TYPE VA_TYPE_L

// globals
// uniforms
uniform mat4 u_movi_mat;
uniform mat4 u_proj_mat;

// VS input attributes
layout(location = 0) in vec4 a_vertex_xyzw;
layout(location = 1) in vec3 a_normal_xyz;
layout(location = 2) in vec2 a_texcoor_stuv;
layout(location = 3) in vec4 a_color0_rgba;
layout(location = 4) in vec4 a_color1_rgba;
// VS output attributes
 out vec4 v_vertex_xyzw;
 out vec3 v_normal_xyz;
 out vec2 v_texcoor_stuv;
 out vec4 v_color0_rgba;
 out vec4 v_color1_rgba;

void main() {
	gl_Position = u_proj_mat * u_movi_mat * vec4(a_vertex_xyzw          );
	v_vertex_xyzw = a_vertex_xyzw;
	v_normal_xyz = a_normal_xyz;
	v_texcoor_stuv = a_texcoor_stuv;
	v_color0_rgba = a_color0_rgba;
	v_color1_rgba = a_color1_rgba;
}
]],
	fs =
[[
#version 410 core
#extension GL_ARB_explicit_attrib_location : enable
// defines
#define VA_TYPE VA_TYPE_L

// globals
// uniforms
uniform sampler2D u_tex0;
uniform vec4 u_alpha_test_ctrl = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec3 u_gamma_exponents = vec3(1.0, 1.0, 1.0);
uniform float u_tex_loaded = 0.0;

// FS input attributes
 in vec4 v_vertex_xyzw;
 in vec3 v_normal_xyz;
 in vec2 v_texcoor_stuv;
 in vec4 v_color0_rgba;
 in vec4 v_color1_rgba;
// FS output attributes
layout(location = 0) out vec4 f_color_rgba;

void main() {
	f_color_rgba  = mix(vec4(1.0), texture(u_tex0, v_texcoor_stuv.st), u_tex_loaded);
	f_color_rgba *= v_color0_rgba * (1.0 / 255.0);

	float alpha_test_gt = float(f_color_rgba.a > u_alpha_test_ctrl.x) * u_alpha_test_ctrl.y;
	float alpha_test_lt = float(f_color_rgba.a < u_alpha_test_ctrl.x) * u_alpha_test_ctrl.z;
	if ((alpha_test_gt + alpha_test_lt + u_alpha_test_ctrl.w) == 0.0)
		discard;
	f_color_rgba.rgb = pow(f_color_rgba.rgb, u_gamma_exponents);
}
]]
}

local vertexTypes = {
	["VA_TYPE_0"] = true, -- p
	["VA_TYPE_C"] = true, -- p, c
	["VA_TYPE_T"] = true, -- p, st
	["VA_TYPE_T4"] = true, -- p, uvwz
	["VA_TYPE_TN"] = true, -- p, st, n
	["VA_TYPE_TC"] = true, -- p, st, c
	["VA_TYPE_2D0"] = true, -- x, y
	["VA_TYPE_2DT"] = true, -- x, y, st
	["VA_TYPE_2DTC"] = true, -- x, y, st, c
	["VA_TYPE_L"] = vaTypeLShaderSources, -- p, n, uvwz, c0, c1
}

local defaultShaders = {}
local function CompileDefaultShader(shType)
	if not vertexTypes[shType] then
		return
	end

	local shaderSrc = vertexTypes[shType]

	if not shaderSrc then
		return
	elseif type(shaderSrc) == "boolean" then
		shaderSrc = gl.GetDefaultShaderSources(shType)
	end

	local shader = gl.CreateShader({
		vertex = shaderSrc.vs,
		fragment = shaderSrc.fs,
	})

	local shLog = gl.GetShaderLog() or ""

	if not shader then
		--self:ShowError(shLog)
		Spring.Echo("CompileDefaultShader Error", shLog)
		return false
	elseif (shLog ~= "") then
		--self:ShowWarning(shLog)
		Spring.Echo("CompileDefaultShader Warning", shLog)
	end

	return shader
end


local DRAW_NONE               = 0
local DRAW_GENESIS            = 1
local DRAW_WORLD              = 2
local DRAW_WORLD_SHADOW       = 3
local DRAW_WORLD_REFLECTION   = 4
local DRAW_WORLD_REFRACTION   = 5
local DRAW_SCREEN             = 6
local DRAW_MINIMAP            = 7
local DRAW_MINIMAP_BACKGROUND = 8

local worldDrawModes = {
	[DRAW_GENESIS] = true,
	[DRAW_WORLD] = true,
	[DRAW_WORLD_REFLECTION] = true, --?
	[DRAW_WORLD_REFRACTION] = true, --?
}

local mmDrawModes = {
	[DRAW_MINIMAP] = true,
	[DRAW_MINIMAP_BACKGROUND] = true,
}


local m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16
local p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16
local function GetCallinMatrices()
	local currDrawMode, prevDrawMode = gl.GetDrawMode()

	if currDrawMode == prevDrawMode then
		return true
	end

	local m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16
	local p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16

	if worldDrawModes[currDrawMode] then
		m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16 = gl.GetMatrixData("view")
		p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16 = gl.GetMatrixData("projection")
	elseif mmDrawModes[currDrawMode] then
		--skip for now
		----
		----
		----
		----
	elseif currDrawMode == DRAW_SCREEN then
		m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16 = gl.GetScreenViewMatrix()
		p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16 = gl.GetScreenProjMatrix()
	elseif currDrawMode == DRAW_WORLD_SHADOW then
		--skip for now
		----
		----
		----
		----
	end

	return false,
		m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16,
		p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16
end


local function CondEnableDisableDefaultShaders(shType, glCallFunc, ...)
	if activeShader ~= 0 then --someone else activated non-default shader
		glCallFunc(...)
		return
	end

	if defaultShaders[shType] == nil then --can be false
		defaultShaders[shType] = CompileDefaultShader(shType)
	end

	local useOld, _m1, _m2, _m3, _m4, _m5, _m6, _m7, _m8, _m9, _m10, _m11, _m12, _m13, _m14, _m15, _m16,
	_p1, _p2, _p3, _p4, _p5, _p6, _p7, _p8, _p9, _p10, _p11, _p12, _p13, _p14, _p15, _p16 = GetCallinMatrices()

	if not useOld then
		m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16 = _m1, _m2, _m3, _m4, _m5, _m6, _m7, _m8, _m9, _m10, _m11, _m12, _m13, _m14, _m15, _m16
		p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16 = _p1, _p2, _p3, _p4, _p5, _p6, _p7, _p8, _p9, _p10, _p11, _p12, _p13, _p14, _p15, _p16
	end

	activeShader = defaultShaders[shType]
	local viewMatLoc = gl.GetUniformLocation(activeShader, "u_movi_mat")
	local projMatLoc = gl.GetUniformLocation(activeShader, "u_proj_mat")
	local texLoadLoc = gl.GetUniformLocation(activeShader, "u_tex_loaded")

	local tu0 = (boundTextures[0] and 1.0) or 0.0

	orig.UseShader(activeShader)
		gl.UniformMatrix(viewMatLoc, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16)
		gl.UniformMatrix(projMatLoc, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16)
		gl.Uniform(texLoadLoc, tu0)
		glCallFunc(...)
	orig.UseShader(0)

	activeShader = 0
end

local GL_QUADS = GL.QUADS
local GL_TRIANGLES = GL.TRIANGLES
gl.BeginEnd = function(glType, glFuncInput, ...)
	inBeginEnd = true
	vertexCounter = 0

	local glQuads = false
	local glCallFunc

	if glType == GL_QUADS then
		glQuads = true
		glType = GL_TRIANGLES
		glCallFunc = function(...)
			glFuncInput(...)
			UpdateVertexIndicesForQuad()
		end
	else
		glCallFunc = glFuncInput
	end

	CondEnableDisableDefaultShaders("VA_TYPE_L", orig.BeginEnd, glType, glCallFunc, ...)

	vertexCounter = 0
	inBeginEnd = false
end


gl.TexRect = function(...)
	CondEnableDisableDefaultShaders("VA_TYPE_TC", orig.TexRect, ...)
end

gl.Rect = function(...)
	CondEnableDisableDefaultShaders("VA_TYPE_C", orig.Rect, ...)
end

gl.Shape = function(glType, shapeArray)
	--Spring.Echo("gl.Shape")
end

-----------------------------------------------------------------
-- Font functions
-----------------------------------------------------------------


local CompatFont = setmetatable({}, {
	__call = function(self, cf) return
		setmetatable({
			sf = cf,
		}, self)
	end,
	})
CompatFont.__index = CompatFont

function CompatFont:SetTextColor(r, g, b, a)
	self.sf:SetTextColor(r, g, b, a)
end

function CompatFont:SetOutlineColor(r, g, b, a)
	self.sf:SetOutlineColor(r, g, b, a)
end

function CompatFont:SetAutoOutlineColor(enable)
	self.sf:SetAutoOutlineColor(enable)
end

function CompatFont:GetTextWidth(text)
	return self.sf:GetTextWidth(text)
end

function CompatFont:GetTextHeight(text)
	return self.sf:GetTextHeight(text)
end

function CompatFont:WrapText(text, max_width, max_height, size)
	return self.sf:WrapText(text, max_width, max_height, size)
end

function CompatFont:BindTexture(...)
	return self.sf:BindTexture(...)
end

function CompatFont:Begin()
	--self.sf:Begin()
end

function CompatFont:End()
	self.sf:DrawBuffered()
	--self.sf:End()
end

function CompatFont:Print(text, x, y, size, options)
	local vsx, vsy, vx, vy = Spring.GetViewGeometry()

	x, y = x / vsx, y / vsy --keep it simple for now (no vx/vy)

	if options:find("n") then
		options = options:gsub("n", "")
	end

	if not options:find("N") then
		options = options.."N"
	end

	if not options:find("B") then
		options = options.."B"
	end
	--options = options.."nN" --just in case
	--size, options = 23.0, "ocvNB"

	--Spring.Echo(self, self.sf, self.sf.Print, text, x, y, size, options)
	self.sf:Print(text, x, y, size, options)
end

function CompatFont:DrawBuffered()
	self.sf:DrawBuffered()
end

function CompatFont:WorldBegin()
	--origFont
	cfBeginEnd = true
	self.sf:WorldBegin()
end

function CompatFont:WorldEnd()
	self.sf:WorldEnd()
	cfBeginEnd = false
end

function CompatFont:WorldPrint(...)
	self.sf:WorldPrint(...)
end

--RenderDataBufferTC
loadedFonts = {}
gl.LoadFont = function(fn, sz, owi, owe)
	local sf = orig.LoadFont(fn, sz, owi, owe)

	--Spring.Echo("gl.LoadFont", fn, sz, owi, owe, sf, sf.Print)

	if sf then
		loadedFonts[sf] = true
		return CompatFont(sf)
	end
	--return (sf and CompatFont(sf)) or nil
end

gl.DeleteFont = function(cf)
	if cf then
		if loadedFonts[cf.sf] then
			orig.DeleteFont(cf.sf)
			loadedFonts[cf.sf] = nil
		end
		cf = nil
	end
end



-----------------------------------------------------------------
-- Scream Shutdown
-----------------------------------------------------------------

local glalScream = Script.CreateScream()
glalScream.func = function()
	Spring.Echo("GLAL UNLOAD")

	for k, v in pairs(defaultShaders) do
		if v then
			orig.DeleteShader(v)
		end
	end

	-- somehow crashes the game
--[[
	for k, v in pairs(loadedFonts) do
		if v then
			orig.DeleteFont(k)
		end
	end
]]--
end

-----------------------------------------------------------------
-- End of Develop
-----------------------------------------------------------------
end