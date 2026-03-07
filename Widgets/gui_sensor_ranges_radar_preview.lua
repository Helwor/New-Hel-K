function widget:GetInfo()
	return {
		name = "Sensor Ranges Radar Preview 3",
		desc = "Raytraced Radar Range Coverage on building Radar (GL4)",
		author = "Beherith, rewrite fix and improvement Helwor",
		date = "2021.07.12",
		license = "Lua: GPLv2, GLSL: see shader files",
		layer = 0,
		enabled = false
	}
end
local spGetActiveCommand = Spring.GetActiveCommand
local spGetGroundHeight = Spring.GetGroundHeight
local spGetSelectedUnits = Spring.GetSelectedUnits

local sig = '['..widget:GetInfo().name..']: '
local initialized = false

local resolution = 32
local radar_color = {0.2, 0.7, 0.3, 0.7}

local modRules = VFS.Include("gamedata/modrules.lua")
local radarMipLevel = modRules and modRules.sensors and modRules.sensors.los and modRules.sensors.los.radarMipLevel or 2
local LuaShader = VFS.Include("LuaRules/Gadgets/Include/LuaShader.lua")

--
local vsx, vsy = Spring.Orig.GetViewSizes()

options_path = 'Hel-K/' .. widget:GetInfo().name
options = {}
options.shaderRes = {
	name = 'Resolution',
	type = 'number',
	min = 16, max = 64, step = 1,
	value = resolution,
	update_on_the_fly = true,
	OnChange = function(self)
		if resolution ~= self.value then
			resolution = self.value
			if initialized then
				UpdateRadarBOs()
			end
		end
	end
}
options.wantOnSelected = {
	name = 'Show also On Selected radar',
	type = 'bool',
	value = WANT_ON_SELECTED,
	OnChange = function(self)
		WANT_ON_SELECTED = self.value
	end
}
options.radar_color = {
	name = 'Color',
	type = 'colors',
	value = radar_color,
	OnChange = function(self)
		radar_color[1], radar_color[2], radar_color[3], radar_color[4] = unpack(self.value)
	end,
	category = 'user',
}
local radarStructureRange = {}
local radarTotalHeight = {}
local radarEmitHeight = {}

local radarRangeVAO, radarRangeVBO = {}, {}
local radarTruthShader = nil
local selectedRadarUnitID = false

for unitDefID, ud in pairs(UnitDefs) do
	if ud.radarDistance > 100 and not ud.customParams.disable_radar_preview then
		local range = ud.radarDistance
		radarStructureRange[unitDefID] = range
		radarEmitHeight[unitDefID] = ud.radarEmitHeight
		radarTotalHeight[unitDefID] = radarEmitHeight[unitDefID] + ud.model.midy
	end
end

local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir .. "LuaShader.lua")
VFS.Include(luaShaderDir .. "instancevbotable.lua")

local shaderConfig = {}

local gridLosSize = 8 * 2 ^ radarMipLevel -- SQUARE_SIZE = 8

local function goodbye(reason)
	Spring.Echo(sig .. "exiting with reason: " .. reason)
	widgetHandler:RemoveWidget()
end




local function CreateRadarTruthShader()
	if radarTruthShader then
		radarTruthShader:Delete()	
	end
	shaderConfig = {}
	radarTruthShader = LuaShader.CheckShaderUpdates({ -- need this function and table to get some engine uniform made by LuaShader
		vssrcpath = "LuaUI/Widgets/Shaders/sensor_ranges_radar_preview.vert.glsl",
		fssrcpath = "LuaUI/Widgets/Shaders/sensor_ranges_radar_preview.frag.glsl",
		uniformInt = {
			heightmapTex = 0,
			distTex = 1,
			radarMiplevel = radarMipLevel,
			gridLosSize = gridLosSize,
			invGridLosSize = 1.0 / gridLosSize,
		},
		uniformFloat = {
			radarcenter_range = { 0, 0, 0, 0 },
			invMapSize = {1.0/Game.mapSizeX, 1.0/Game.mapSizeZ},
		},
		shaderConfig = shaderConfig,
		shaderName = sig.."radarTruthShader GL4"
	})
	return radarTruthShader
end

function UpdateRadarBOs()
	for _, range in pairs(radarStructureRange) do
		local size = range / resolution
		local radarVertex, _ = makePlaneVBO(1, 1, size, size)
		local radarIndex, _ = makePlaneIndexVBO(size, size, true)
		local radVAO = gl.GetVAO()
		radVAO:AttachVertexBuffer(radarVertex)
		radVAO:AttachIndexBuffer(radarIndex)
		radarRangeVAO[range] = radVAO
		radarRangeVBO[range] = radarVertex
	end
end

local function initgl4()
	if not CreateRadarTruthShader() then
		goodbye('radarTruthShader compilation failed')
		return false
	end
	UpdateRadarBOs()
	return true
end

function widget:GetViewSizes()
	vsx, vsy = Spring.Orig.GetViewSizes()
end

function widget:Update() -- get the option values before Initializing
	Init()
	widgetHandler:RemoveCallIn('Update')
end

function Init()
	vsx, vsy = Spring.Orig.GetViewSizes()
	if not gl.CreateShader then -- no shader support, so just remove the widget itself, especially for headless
		goodbye("Cannot create shader")
		return
	end

	if not initgl4() then
		return
	end
	widget:CommandsChanged()
	initialized = true
end

function widget:CommandsChanged()
	local sel = spGetSelectedUnits()
	selectedRadarUnitID = false
	if sel[1] and not sel[2] and Spring.GetUnitDefID(sel[1]) and radarStructureRange[Spring.GetUnitDefID(sel[1])] then
		selectedRadarUnitID = sel[1]
	end
end

local function GetRadarUnitToDraw()
	if selectedRadarUnitID then
		unitDefID = Spring.GetUnitDefID(selectedRadarUnitID)
		if not unitDefID then
			selectedRadarUnitID = false
			return
		end
		return selectedRadarUnitID, unitDefID
	else
		local cmdID = select(2, spGetActiveCommand())
		if cmdID == nil or cmdID >= 0 then
			-- cmdID = WG.currentBuild and WG.currentBuild.defID
			if not cmdID then
				return
			end
		end
		if radarStructureRange[-cmdID] then
			return false, -cmdID
		end
	end
end

local function GetRadarDrawPos(unitID, unitDefID)
	if unitID then
		if WANT_ON_SELECTED then
			local _, by, _, x, y, z = Spring.GetUnitPosition(unitID, true) -- mid position
			-- Echo('HEIGHTS:', 'ground: '.. by, 'mid: ' .. y, 'emit: ' .. radarEmitHeight[unitDefID], 'model.midy: ' .. UnitDefs[unitDefID].model.midy, 'offset: ' .. height_offset, 'given: ' .. y + radarEmitHeight[unitDefID] + height_offset)
			return x, y + radarEmitHeight[unitDefID], z
		end
	else
		local mx, my, lp, mp, rp, offscreen = Spring.GetMouseState()
		local _, coords = Spring.TraceScreenRay(mx, my, true, true)
		if coords and coords[3] or WG.placementX then
			local x, z
			if WG.placementX then
				x, z = WG.placementX, WG.placementZ
			else
				x, z = Spring.Utilities.SnapToBuildGrid(unitDefID, Spring.GetBuildFacing(), coords[1], coords[3])
			end
			local y = (
				WG.placementX and spGetGroundHeight(x,z) or
				coords and coords[2] or
				spGetGroundHeight(x,z)
			) + radarTotalHeight[unitDefID]

			if WG.placementHeight then
				y = y + WG.placementHeight
			end
			return x, y, z
		end
	end
end


local function DrawRadarCoverage(drawX, drawY, drawZ, range)
	gl.Culling(false)
	gl.Culling(GL.BACK)

	gl.DepthTest(true)
	gl.Texture(0, "$heightmap")
	radarTruthShader:Activate()
	radarTruthShader:SetUniform("radarcenter_range", drawX, drawY, drawZ, range)
	radarTruthShader:SetUniform("radar_color", radar_color[1], radar_color[2], radar_color[3], radar_color[4] )
	radarRangeVAO[range]:DrawElements(GL.TRIANGLES)
	radarTruthShader:Deactivate()
	gl.Texture(0, false)
	gl.DepthTest(true)
	gl.Culling(false)
end

function widget:DrawWorld()

	if Spring.IsGUIHidden() then
		return
	end
	local unitID, unitDefID = GetRadarUnitToDraw()
	if not unitDefID then
		return
	end
	local drawX, drawY, drawZ = GetRadarDrawPos(unitID, unitDefID)
	if not drawX then
		return
	end
	DrawRadarCoverage(drawX, drawY, drawZ, radarStructureRange[unitDefID])
end


function widget:Shutdown()
	for k, vao in pairs(radarRangeVAO) do
		vao:Delete()
		radarRangeVAO[k] = nil
	end
	for k, vbo in pairs(radarRangeVBO) do
		vbo:Delete()
		radarRangeVBO[k] = nil
	end
	if radarTruthShader then
		radarTruthShader:Delete()
		radarTruthShader = nil
	end
end
