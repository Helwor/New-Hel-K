--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- fixed gl z fighting on cutaway border
-- fixed interior wall not showing when no other map extension present
-- fixed NSEW not showing when no other map extension present
-- clarified a bit the indents on vertexs
-- fixed gl translate leaking
function widget:GetInfo()
  return {
    name      = "Map Edge Barrier",
    version   = "v0.22",
    desc      = "Draws a vertical grid along map edge",
    author    = "Pako",
    date      = "2012.02.19 - 2012.02.21", --YYYY.MM.DD, created - updated
    license   = "GPL",
    layer     = -1,	--higher layer is loaded last
    enabled   = false,
    --detailsDefault = 2
  }
end
local Echo = Spring.Echo
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
if VFS.FileExists("nomapedgewidget.txt") then
	return
end

local spGetGroundHeight = Spring.GetGroundHeight
local spTraceScreenRay = Spring.TraceScreenRay
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local wallTex = "bitmaps/PD/hexbig.png"
--local wallTex = "bitmaps/PD/shield2.png"
--local wallTex = "LuaUI/Images/vr_grid.png"

local height = 2048
local minHeight = -height/4
local maxHeight = height*3/4

local texScale = 0.01
local colorFloor = { 0.1, 0.88, 1, 1}
local colorCeiling = { 0.1, 0.88, 1, 0}

local dListWall

local island = false

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
options_path = 'Settings/Graphics/Map/Edge Barrier'
options = {
	drawForIslands = {
		name = "Draw for islands",
		type = 'bool',
		value = true,
		desc = "Draws boundary wall when map is an island",
	},
	wallFromOutside = {
		name = "Visible walls from outside",
		type = 'bool',
		value = false,
		desc = "Map wall is visible from the outside (e.g. when it's between camera and main map)",
		OnChange = function(self)
			if dListWall then
				gl.DeleteList(dListWall)
				widget:Initialize()
			end
		end
	},
    noWall = {
        name = "No wall at all",
        type = 'bool',
        value = false,
        desc = "Don't draw wall at all",
        OnChange = function(self)
            if dListWall then
                gl.DeleteList(dListWall)
                widget:Initialize()
            end
        end
    },
	northSouthText = {
		name = "North, East, South, & West text",
		type = 'bool',
		value = false,
		desc = 'Help you identify map direction under rotation by placing a "North/South/East/West" text on the map edges',
		OnChange = function(self)
			if dListWall then
				gl.DeleteList(dListWall)
				widget:Initialize()
			end
		end,
	},
}
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local offset = (Spring.GetGameRulesParam("waterlevel") or 0)
local function GetGroundHeight(x, z)
	return spGetGroundHeight(x,z) - offset
end

local function IsIsland()
	if WG.GetIslandOverride then
		local override, value = WG.GetIslandOverride()
		if override then
			return value
		end
	end
	local sampleDist = 512
	for i=1,Game.mapSizeX,sampleDist do
		-- top edge
		if GetGroundHeight(i, 0) > 0 then
			return false
		end
		-- bottom edge
		if GetGroundHeight(i, Game.mapSizeZ) > 0 then
			return false
		end
	end
	for i=1,Game.mapSizeZ,sampleDist do
		-- left edge
		if GetGroundHeight(0, i) > 0 then
			return false
		end
		-- right edge
		if GetGroundHeight(Game.mapSizeX, i) > 0 then
			return false
		end
	end
	return true
end

local function TextOutside()

	local mapSizeX = Game.mapSizeX
	local mapSizeZ = Game.mapSizeZ
	local average = (GetGroundHeight(mapSizeX/2,0) + GetGroundHeight(0,mapSizeZ/2) + GetGroundHeight(mapSizeX/2,mapSizeZ) +GetGroundHeight(mapSizeX,mapSizeZ/2))/4
    gl.PushMatrix()
        gl.Rotate(-90,1,0,0)
        gl.Translate (0,0,average)
    	gl.Text("North", mapSizeX/2, 200, 200, "co")
    	
    	gl.Rotate(-90,0,0,1)
    	gl.Text("East", mapSizeZ/2, mapSizeX+200, 200, "co")
    	
    	gl.Rotate(-90,0,0,1)
    	gl.Text("South", -mapSizeX/2, mapSizeZ +200, 200, "co")
    	
    	gl.Rotate(-90,0,0,1)
    	gl.Text("West", -mapSizeZ/2,200, 200, "co")
	gl.PopMatrix()
	-- gl.Text("North", mapSizeX/2, 100, 200, "on")
	-- gl.Text("South", mapSizeX/2,-mapSizeZ, 200, "on")
	-- gl.Text("East", mapSizeX,-(mapSizeZ/2), 200, "on")
	-- gl.Text("West", 0,-(mapSizeZ/2), 200, "on")

end


local function DrawMapWall()
    if not options.noWall.value then

        gl.Texture(wallTex)
        if not options.wallFromOutside.value then
            gl.Culling(GL.FRONT) --'cuts' the outside faces --remove this if you want it to draw over map too
        end
        local zFF = 0.2 -- z Fighting Fix
        local sx = Game.mapSizeX - zFF
        local sz = Game.mapSizeZ - zFF

        gl.Shape( GL.TRIANGLE_STRIP,
            {
                {   
                    v = { zFF, minHeight, zFF},      --top left down
                    texcoord = { 0, 0 },
                    c = colorFloor
                },
                {   
                    v = { zFF, maxHeight, zFF},
                    texcoord = { 0, height*texScale },      --top left up
                    c = colorCeiling
                },
                {   
                    v = { sx, minHeight, zFF},
                    texcoord = { Game.mapSizeX*texScale, 0 },   --top right
                    c = colorFloor
                },
                {
                    v = { sx, maxHeight, zFF},
                    texcoord = { Game.mapSizeX*texScale, height*texScale },
                    c = colorCeiling
                },
                {   
                    v = { sx, minHeight, sz},          -- bottom right
                    texcoord = { Game.mapSizeX*texScale+Game.mapSizeZ*texScale, 0 },
                    c = colorFloor
                },
                {
                    v = { sx, maxHeight, sz},
                    texcoord = { Game.mapSizeX*texScale+Game.mapSizeZ*texScale, height*texScale },
                    c = colorCeiling
                },
                {   
                    v = { zFF, minHeight, sz},  --bottom left
                    texcoord = { Game.mapSizeZ*texScale, 0 },
                    c = colorFloor
                },
                {   
                    v = { zFF, maxHeight, sz},
                    texcoord = { Game.mapSizeZ*texScale, height*texScale },
                    c = colorCeiling
                },
                {
                    v = { zFF, minHeight, zFF},        --back to top right
                    texcoord = { 0, 0 },
                    c = colorFloor
                },
                {   
                    v = { zFF, maxHeight, zFF},
                    texcoord = { 0, height*texScale },
                    c = colorCeiling
                },
            }
        )
        gl.Culling(false)
        gl.Texture(false)
    end
	
	----draw map compass text

    gl.Color(1,1,1,1)
    if (options.northSouthText.value) then
    	-- gl.PushAttrib(GL.ALL_ATTRIB_BITS)
    	-- gl.DepthMask(false)
    	-- gl.DepthTest(false)
    	-- gl.Color(1,1,1,1) -- FIXME: there is some yellow color coming from another widget when all widgets load
        -- TextOutside()
    	-- gl.PopAttrib()
    TextOutside()
    end
	----
end

local function Initialize()
	island = IsIsland()
	dListWall = gl.CreateList(DrawMapWall)
	widgetHandler:RemoveCallIn("Update")
end

function widget:Initialize()
	if Spring.GetGameRulesParam("waterLevelModifier") or Spring.GetGameRulesParam("mapgen_enabled") then
		return
	end
	Initialize()
end

local firstUpdate = true
function widget:Update()
	if firstUpdate then
		firstUpdate = false
		return
	end
	Initialize()
end

function widget:Shutdown()
	gl.DeleteList(dListWall)
end

local function DrawWorldFunc()
  if (not island) or options.drawForIslands.value then
      gl.DepthTest(GL.LESS)
      gl.CallList(dListWall)
      gl.DepthTest(false)
  end
end
function widget:DrawWorldPreUnit()
	DrawWorldFunc()
end
-- function widget:DrawWorld()
-- 	DrawWorldFunc()
-- end

function widget:MousePress(x, y, button)
	local _, mpos = spTraceScreenRay(x, y, true) --//convert UI coordinate into ground coordinate.
	if mpos==nil then --//activate epic menu if mouse position is outside the map
		local _, _, meta, _ = Spring.GetModKeyState()
		if meta then  --//show epicMenu when user also press the Spacebar
			WG.crude.OpenPath(options_path) --click + space will shortcut to option-menu
			WG.crude.ShowMenu() --make epic Chili menu appear.
			return false
		end
	end
end
