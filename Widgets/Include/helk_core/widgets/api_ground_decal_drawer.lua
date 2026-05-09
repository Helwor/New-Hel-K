function widget:GetInfo()
    return {
        name      = "API Ground Decal Drawer",
        desc      = "",
        author    = "Helwor",
        date      = "May 2026",
        license   = "GNU GPL, v2 or later",
        -- layer     = 2, -- after Unit Start State
        layer     = 99999990,
        enabled   = true,  --  loaded by default?
        -- api       = true,
        handler   = true,
    }
end

-- Echo("gl.CopyToTexture is ", gl.CopyToTexture)
local tex, fbo, shader, vao
local sig = '['..widget.GetInfo().name..'] '
local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir .. "LuaShader.lua")
VFS.Include(luaShaderDir .. 'instancevbotable.lua')

local function Draw()
    gl.Color(1, 1, 1, 0.5)
    gl.Rect(-1, -1, 1, 1)
    gl.Color(1, 1, 1, 1)
end
local decals = {}

function widget:DrawWorldPreUnit()
    gl.Texture(0, "$map_gbuffer_zvaltex")
    gl.Texture(1, "$map_gbuffer_difftex")
    for i, decal in pairs(decals) do
        local tex, x, z, w, h, additive, alphaColorMul, userShader = unpack(decal)

        if additive then
            gl.Blending(GL.SRC_ALPHA, GL.ONE)
        end
        gl.Texture(2, tex)
        local shader = userShader or shader
        shader:Activate()
        shader:SetUniform('decalPos', x, z, w, h)
        shader:SetUniform('alphaColorMul', alphaColorMul or 0)
        -- gl.TexRect(-1, -1, 1, 1)
        vao:DrawElements(GL.TRIANGLES, 6)
        shader:Deactivate()
        decals[i] = nil
        if additive then
            gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
        end
    end
    gl.Texture(2, false)
    gl.Texture(1, false)
    gl.Texture(0, false)
end
local userShaders = {}
local function CreateUserShader()
    shader = LuaShader.CheckShaderUpdates({
        fssrcpath = "LuaUI/Widgets/Shaders/api_ground_decal_drawer.frag.glsl",
        vssrcpath = "LuaUI/Widgets/Shaders/api_ground_decal_drawer.vert.glsl",
        uniformInt = {
            mapDepths = 0,
            mapColors = 1,
            decalTex = 2,
        },
        uniformFloat = {
        },
        shaderConfig = {},
        shaderName = sig.." Shader GL4"
    })

end
function widget:Initialize()
    shader = LuaShader.CheckShaderUpdates({
        fssrcpath = "LuaUI/Widgets/Shaders/api_ground_decal_drawer.frag.glsl",
        vssrcpath = "LuaUI/Widgets/Shaders/api_ground_decal_drawer.vert.glsl",
        uniformInt = {
            mapDepths = 0,
            mapColors = 1,
            decalTex = 2,
        },
        uniformFloat = {
        },
        shaderConfig = {},
        shaderName = sig.." Shader GL4"
    })
    if not shader then
        widgetHandler:RemoveWidget(widget)
        return
    end


    vao = MakeTexRectVAO(-1, -1, 1, 1, 0, 0, 1, 1)
    if not vao then
        Echo(sig .. 'Wrong VAO')
        widgetHandler:RemoveWidget(widget)
        return
    end
    function WG.GroundDecalTexture(tex, x, z, w, h, additive, alphaColorMul, userShader)
        decals[#decals + 1] = {tex, x, z, w, h, additive, alphaColorMul, userShader}
    end
end

function widget:Shutdown()
    if shader then
        shader:Delete()
    end
    if vao then
        vao:Delete()
    end
    WG.GroundDecalTexture = nil
end

f.DebugWidget(widget)