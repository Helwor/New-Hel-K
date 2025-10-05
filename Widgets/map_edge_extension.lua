-- fixed useless initialization repetition
-- fixed having to disable map extension for some options to take effect (not using shader)
-- fixed shader not being deleted at new initialization

-- removed echo
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function widget:GetInfo()
  return {
    name      = "Map Edge Extension",
    version   = "v0.5",
    desc      = "Draws a mirrored map next to the edges of the real map",
    author    = "Pako",
    date      = "2010.10.27 - 2011.10.29", --YYYY.MM.DD, created - updated
    license   = "GPL",
    layer     = 3,
    enabled   = true,
    --detailsDefault = 3
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
local gridTex = "LuaUI/Images/vr_grid_cell.dds"
local realTex = '$grass'

local dList
local mirrorShader

local umirrorX
local umirrorZ
local ulengthX
local ulengthZ
local uup
local uleft
local ugrid
local ubrightness

local island = nil -- Later it will be checked and set to true of false
local drawingEnabled = true
local requestUpdate = false

local SPACE_CLICK_OUTSIDE = false
local HEIGHT_UP = 0.1
local HEIGHT_LEEWAY = 1400
local fogFrontier = 1
local fogThickness = 1
local forceTextureToGrid = false
local DrawWorldFunc = function() end
local Request = function()
	requestUpdate = true
end
function WG.game_SetCustomExtensionGridTexture(newGridTex, newForceTextureToGrid)
	gridTex = newGridTex
	forceTextureToGrid = newForceTextureToGrid
	Request()
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


options_path = 'Settings/Graphics/Map Exterior'
options_order = {'mapBorderStyle', 'drawForIslands', 'gridSizeExp', 'gridTextureSizeExp', 'fogEffect', 'fogFrontier', 'fogThickness', 'curvature2', 'textureBrightness3', 'useShader'}
options = {
	--when using shader the map is stored once in a DL and drawn 8 times with vertex mirroring and bending
    --when not, the map is drawn mirrored 8 times into a display list
	mapBorderStyle = {
		type='radioButton',
		name='Exterior Effect',
		items = {
			{name = 'Texture',  key = 'texture', desc = "Mirror the heightmap and texture.",              hotkey = nil},
			{name = 'Grid',     key = 'grid',    desc = "Mirror the heightmap with grid texture.",        hotkey = nil},
			{name = 'Cutaway',  key = 'cutaway', desc = "Draw the edge of the map with a cutaway effect", hotkey = nil},
			{name = 'Disable',  key = 'disable', desc = "Draw no edge extension",                         hotkey = nil},
		},
		value = 'cutaway',
		OnChange = function(self)
			drawingEnabled = (self.value == "texture") or (self.value == "grid")
			Request()
		end,
		noHotkey = true,
	},
	drawForIslands = {
		name = "Draw for islands",
		type = 'bool',
		value = false,
		desc = "Draws mirror map when map is an island",
		noHotkey = true,
	},
	useShader = {
		name = "Use shader",
		type = 'bool',
		value = true,
		advanced = true,
		desc = 'Use a shader when mirroring the map',
		OnChange = Request,
		noHotkey = true,
	},
	gridSizeExp = {
		name = "Heightmap resolution (2^n)",
		type = 'number',
		min = 4,
		max = 8,
		step = 1,
		value = 5,
		desc = '',
		OnChange = Request,
	},
	gridTextureSizeExp = {
		name = "Grid tile size (2^n)",
		desc = "Cannot be less than heightmap resolution",
		type = 'number',
		min = 4,
		max = 8,
		step = 1,
		value = 5,
		desc = '',
		OnChange = Request,
	},
	textureBrightness3 = {
		name = "Texture Brightness",
		type = 'number',
		min = 0,
		max = 1,
		step = 0.01,
		value = 0.29,
		desc = 'Sets the brightness of the realistic texture (doesn\'t affect the grid)',
		OnChange = Request,
	},
	fogEffect = {
		name = "Edge Fog Effect",
		type = 'bool',
		value = false,
		desc = 'Blurs the edges of the map slightly to distinguish it from the extension.',
		OnChange = Request,
		noHotkey = true,
	},
	fogFrontier = {
		name = "Fog Frontier",
		type = 'number',
		value = fogFrontier,
		min = 0.1, max = 10, step = 0.1,
		desc = 'Set the frontier of the opaque fog',
		update_on_the_fly = true,
		tooltipFunction = function(self)
			-- Echo('self',self,self.value)
			return ('%.1f'):format(self.value^1.5)
		end,
		OnChange = function(self)
			fogFrontier = self.value^1.5
			Request()
		end,
		noHotkey = true,
	},
	fogThickness = {
		name = "Fog Thickness",
		type = 'number',
		value = fogThickness,
		min = 1, max = 10, step = 0.01,
		desc = 'Set the fog thickness',
		update_on_the_fly = true,
		tooltipFunction = function(self)
			-- Echo('self',self,self.value)
			return ('%.1f'):format(self.value^3 / 1000)
		end,
		OnChange = function(self)
			fogThickness = self.value^3 /1000
			Request()
		end,
		noHotkey = true,
	},
	curvature2 = {
		name = "Curvature Effect",
		type = 'bool',
		value = true,
		desc = 'Add a curvature to the extension.',
		OnChange = Request,
		noHotkey = true,
	},
	
}
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local shaderTable
local function SetupShaderTable()
  shaderTable = {
	  uniform = {
		mirrorX = 0,
		mirrorZ = 0,
		lengthX = 0,
		lengthZ = 0,
		tex0 = 0,
		up = 0,
		left = 0,
		grid = 0,
		brightness = 1.0,
	  },
	  vertex = (options.curvature2.value and "#define curvature \n" or '')
		.. (options.fogEffect.value and "#define edgeFog \n" or '')
		.. [[
		// Application to vertex shader
		uniform float mirrorX;
		uniform float mirrorZ;
		uniform float lengthX;
		uniform float lengthZ;
		uniform float left;
		uniform float up;
		uniform float brightness;

		varying vec4 vertex;
		varying vec4 color;
  
		void main()
		{
			gl_TexCoord[0]= gl_TextureMatrix[0]*gl_MultiTexCoord0;
			vec4 mirrorVertex = gl_Vertex;
			mirrorVertex.x = abs(mirrorX-mirrorVertex.x);
			mirrorVertex.z = abs(mirrorZ-mirrorVertex.z);
			
			float alpha = 1.0;
			#ifdef curvature
				if(mirrorX != 0.0) mirrorVertex.x += ((1.0 - left)*pow(mirrorVertex.x, 5.0) - left*pow(mirrorX - mirrorVertex.x, 5.0)) / pow(mirrorX, 4.0);
				if(mirrorZ != 0.0) mirrorVertex.z += ((1.0 - up)*pow(mirrorVertex.z, 5.0) - up*pow(mirrorZ - mirrorVertex.z, 5.0)) / pow(mirrorZ, 4.0);
				
				float offset = pow(abs(mirrorVertex.z-up*mirrorZ) * mirrorZ / lengthZ * 0.006, 2.0) +
					pow(abs(mirrorVertex.x-left*mirrorX) * mirrorX / lengthX * 0.006, 2.0);
				if (offset > 1.0 && mirrorVertex.y < -400) mirrorVertex.y += ]] .. HEIGHT_LEEWAY .. [[;
				mirrorVertex.y -= offset;
				
				alpha = 0.0;
				if(mirrorX != 0.0) alpha -= pow(abs(mirrorVertex.x-left*mirrorX)/lengthX, 2.0);
				if(mirrorZ != 0.0) alpha -= pow(abs(mirrorVertex.z-up*mirrorZ)/lengthZ, 2.0);
				alpha = 1.5 + alpha*0.5 + mirrorVertex.y*0.0001;
			#endif
	  
	  
			gl_Position  = gl_ModelViewProjectionMatrix*mirrorVertex;
			#ifdef edgeFog
				//gl_Position.z-=ff;
				//gl_FogFragCoord = length((gl_ModelViewMatrix * mirrorVertex).xyz)-ff; //see how Spring shaders do the fog and copy from there to fix this
				//gl_FogFragCoord += ff*0.8; //see how Spring shaders do the fog and copy from there to fix this
				//gl_FogFragCoord *= length((gl_ModelViewMatrix * mirrorVertex).xyz)-ff;

			#endif
			
			gl_FrontColor = vec4(brightness * gl_Color.rgb, alpha);

			color = gl_FrontColor;
			vertex = mirrorVertex;
		}
	  ]],


		-- uniform sampler2D tex0;

		-- void main()
		-- {

		-- 	float fog;
		-- 	fog = clamp( (gl_Fog.end - abs(gl_FogFragCoord)) * gl_Fog.scale ,0.0,1.0);
		-- 	gl_FragColor = vec4(
		-- 		mix(
		-- 			gl_Fog.color,
		-- 			gl_FragColor.rgb,
		-- 			fog
		-- 		),
		-- 		0.5,
		-- 	) * texture2D(tex0, gl_TexCoord[0].xy) ;
		-- }

	 --  ]],
	  fragment = [[
		uniform float mirrorX;
		uniform float mirrorZ;
		uniform float lengthX;
		uniform float lengthZ;
		uniform float left;
		uniform float up;
		uniform int grid;
		uniform sampler2D tex0;

		varying vec4 vertex;
		varying vec4 color;

		void main()
		{
			//float alpha = 0.0;
			//if(mirrorX) alpha -= pow(abs(vertex.x-left*mirrorX)/lengthX * ]]..'1'..[[, 2);
			//if(mirrorZ) alpha -= pow(abs(vertex.z-up*mirrorZ)/lengthZ * ]]..'1'..[[, 2);
			//alpha = 0.1 + ( ]]..'1000'..[[*(alpha));
			//alpha = 1;

			float alpha = 0;
			if(mirrorX) alpha -= pow(abs(vertex.x-left*mirrorX)/lengthX, 2);
			if(mirrorZ) alpha -= pow(abs(vertex.z-up*mirrorZ)/lengthZ, 2);
			alpha = 1.0 + (4.0 * (alpha + 0.28));

			float border = 0;
			if(mirrorX) border += pow(abs(vertex.x-left*mirrorX)/150.0, 2);
			if(mirrorZ) border += pow(abs(vertex.z-up*mirrorZ)/150.0, 2);


			float dist = 0;
			if(mirrorX)
			  	dist += pow(vertex.x-left*mirrorX, 2.0) ;
			if(mirrorZ)
			  	dist += pow(vertex.z-up*mirrorZ, 2.0);
			 if (dist != 0.0)
			 	dist = pow(dist, 0.5);



		 	float fog = clamp( (gl_Fog.end - abs(gl_FogFragCoord)) * gl_Fog.scale ,0.5,1.0) * border;
		 	gl_FragColor = vec4(
		 		mix(
		 			gl_Fog.color,
					color.rgb,
					fog
				),
				1
			) * texture2D(tex0, gl_TexCoord[0].xy) * alpha ;



			// vec3(1.0, 1.0, 1.0)

			//float fog;
		    //fog = clamp( (gl_Fog.end - abs(gl_FogFragCoord)*100) * gl_Fog.scale ,0.0,1.0);
			//gl_FragColor.rgb = mix(gl_Fog.color.rgb, gl_FragColor.rgb, fog );


			// cool effect
		 	//float fog;
		 	//fog = clamp( (gl_Fog.end - abs(gl_FogFragCoord)) * gl_Fog.scale ,0.5,1.0) * alpha/2;
		 	//gl_FragColor = vec4(
		 	//	mix(
		 	//		gl_Fog.color,
			//		color.rgb,
			//		fog
			//	),
			//	1
			//) * texture2D(tex0, gl_TexCoord[0].xy) * alpha ;
		}
	]]
  }
end

local offset = (Spring.GetGameRulesParam("waterlevel") or 0)
local function GetGroundHeight(x, z)
	return spGetGroundHeight(x,z) - offset
end

local function IsIsland()
	-- Spring.Echo("IsIsland", WG.GetIslandOverride, WG.GetIslandOverride())
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

local function ReverseTile(value)
	value = value%2
	if value % 2 > 1 then
		return 1 - (value%1)
	end
	return value
end

local function DrawMapVertices(useMirrorShader, tile)
	local floor = math.floor
	local ceil = math.ceil
	local abs = math.abs

	gl.Color(1,1,1,1)

	local function doMap(dx,dz,sx,sz)
		local Scale = math.pow(2, options.gridSizeExp.value)
		local GridSize = math.max(Scale, math.pow(2, options.gridTextureSizeExp.value))
		local sggh = Spring.GetGroundHeight
		local Vertex = gl.Vertex
		local glColor = gl.Color
		local TexCoord = gl.TexCoord
		local Normal = gl.Normal
		local GetGroundNormal = Spring.GetGroundNormal
		local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ
		local sten = {0, floor(mapSizeZ/Scale)*Scale, 0}--do every other strip reverse
		local xm0, xm1 = 0, 0
		local xv0, xv1 = 0, math.abs(dx)+sx
		local ind = 0
		local zv
		local h

		if not useMirrorShader then
			gl.TexCoord(0, sten[2]/mapSizeZ)
			Vertex(xv1, sggh(0,sten[2]),abs(dz+sten[2])+sz)--start and end with a double vertex
		end
		
		if tile then
			for x = 0,Game.mapSizeX - Scale, Scale do
				xv0, xv1 = xv1, abs(dx+x+Scale)+sx
				xm0, xm1 = xm1, xm1+Scale
				ind = (ind+1)%2
				for z = sten[ind+1], sten[ind+2], (1+(-ind*2))*Scale do
					zv = abs(dz+z)+sz
					TexCoord(ReverseTile(xm0 / GridSize), ReverseTile(z / GridSize))
					-- Normal(GetGroundNormal(xm0,z))
					h = sggh(xm0,z) + HEIGHT_UP
					Vertex(xv0,h,zv)
					TexCoord(ReverseTile(xm1 / GridSize), ReverseTile(z / GridSize))
					--Normal(GetGroundNormal(xm1,z))
					h = sggh(xm1,z) + HEIGHT_UP
					Vertex(xv1,h,zv)
				end
			end
			
			if useMirrorShader then
				TexCoord(0.5, 0.5)
				-- this sems to actually doing glitch when using close fog
				local z = mapSizeZ - 0.05
				-- for x = mapSizeX, 0, -Scale do
				-- 	local height = sggh(x, z)
				-- 	Vertex(x, height + HEIGHT_UP, z)
				-- 	Vertex(x, height - HEIGHT_LEEWAY, z)
				-- end
				local x = 0.05
				-- for z = mapSizeZ, 0, -Scale do
				-- 	local height = sggh(x, z)
				-- 	Vertex(x, height + HEIGHT_UP, z)
				-- 	Vertex(x, height - HEIGHT_LEEWAY, z)
				-- end
				z = 0.05
				-- for x = 0, mapSizeX, Scale do
				-- 	local height = sggh(x, z)
				-- 	Vertex(x, height + HEIGHT_UP, z)
				-- 	Vertex(x, height - HEIGHT_LEEWAY, z)
				-- end
				x = mapSizeX - 0.05
				-- for z = 0, mapSizeZ, Scale do
				-- 	local height = sggh(x, z)
				-- 	Vertex(x, height + HEIGHT_UP, z)
				-- 	Vertex(x, height - HEIGHT_LEEWAY, z)
				-- end
			end
		else
			for x=0,mapSizeX-Scale,Scale do
				xv0, xv1 = xv1, abs(dx+x+Scale)+sx
				xm0, xm1 = xm1, xm1+Scale
				ind = (ind+1)%2
				for z=sten[ind+1], sten[ind+2], (1+(-ind*2))*Scale do
					zv = abs(dz+z)+sz
					TexCoord(xm0/mapSizeX, z/mapSizeZ)
					-- Normal(GetGroundNormal(xm0,z))
					h = sggh(xm0,z)
					Vertex(xv0,h,zv)
					TexCoord(xm1/mapSizeX, z/mapSizeZ)
					--Normal(GetGroundNormal(xm1,z))
					h = sggh(xm1,z)
					Vertex(xv1,h,zv)
				end
			end
		end
		if not useMirrorShader then
			Vertex(xv1,h,zv)
		end
	end

	if useMirrorShader then
		doMap(0,0,0,0)
	else
		doMap(-Game.mapSizeX,-Game.mapSizeZ,-Game.mapSizeX,-Game.mapSizeZ)
		doMap(0,-Game.mapSizeZ,0,-Game.mapSizeZ)
		doMap(-Game.mapSizeX,-Game.mapSizeZ,Game.mapSizeX,-Game.mapSizeZ)
	
		doMap(-Game.mapSizeX,0,-Game.mapSizeX,0)
		doMap(-Game.mapSizeX,0,Game.mapSizeX,0)
	
		doMap(-Game.mapSizeX,-Game.mapSizeZ,-Game.mapSizeX,Game.mapSizeZ)
		doMap(0,-Game.mapSizeZ,0,Game.mapSizeZ)
		doMap(-Game.mapSizeX,-Game.mapSizeZ,Game.mapSizeX,Game.mapSizeZ)
	end

end

local function DrawOMap(useMirrorShader)
	gl.Blending(GL.SRC_ALPHA,GL.ONE_MINUS_SRC_ALPHA)
	gl.DepthTest(GL.LEQUAL)
		if options.mapBorderStyle.value == "texture" and not forceTextureToGrid then
			gl.Texture(realTex)
		else
			gl.Texture(gridTex)
		end
	gl.BeginEnd(GL.TRIANGLE_STRIP,DrawMapVertices, useMirrorShader, options.mapBorderStyle.value == "grid")
	gl.DepthTest(false)
	gl.Color(1,1,1,1)
	gl.Blending(GL.SRC_ALPHA,GL.ONE_MINUS_SRC_ALPHA)
end
local function DrawWorldShaderLess()
	if dList and ((not island) or options.drawForIslands.value) then
		gl.DepthMask(true)
		--gl.Texture(tex)
		gl.CallList(dList)
		gl.DepthMask(false)
		gl.Texture(false)
	end
end
local function DrawWorldShader() --is overwritten when not using the shader
    if dList and ((not island) or options.drawForIslands.value) then
        local glTranslate = gl.Translate
        local glUniform = gl.Uniform
        local GamemapSizeZ, GamemapSizeX = Game.mapSizeZ,Game.mapSizeX
        
        gl.FogCoord(1)
        gl.UseShader(mirrorShader)
        gl.PushMatrix()
        gl.DepthMask(true)
        if options.mapBorderStyle.value == "texture" and not forceTextureToGrid then
        	-- Echo('use brightness',options.textureBrightness3.value,math.round(os.clock()))
			gl.Texture(realTex)
			glUniform(ubrightness, options.textureBrightness3.value)
			glUniform(ugrid, 0)
		else
			gl.Texture(gridTex)
			glUniform(ubrightness, options.textureBrightness3.value)
			glUniform(ugrid, 1)
		end
        if wiremap then -- wiremap doesnt exist, but it could be nice to find how to know if the wiremap mode is active or not and make this happen
            gl.PolygonMode(GL.FRONT_AND_BACK, GL.LINE)
        end

        glUniform(umirrorX, GamemapSizeX)
        glUniform(umirrorZ, GamemapSizeZ)
        glUniform(ulengthX, GamemapSizeX)
        glUniform(ulengthZ, GamemapSizeZ)


        -- gl.PushMatrix()
        	local stepx, stepz = 4, 4 -- fixing the tiling effect
        	local offx, offz = 0, 0
        	-- top left
	        glUniform(uleft, 1) -- those seems to be useless
	        glUniform(uup, 1)
	        -- offx, offz = stepx, stepz
	        glTranslate(-GamemapSizeX+offx,0,-GamemapSizeZ+offz)
	       	gl.CallList(dList)

	        
	        -- top right
	        glUniform(uleft , 0)
	        -- offx, offz = -2*stepx, 0
	        glTranslate(GamemapSizeX*2 + offx,0,0 + offz)
	    	gl.CallList(dList)


	    	-- bottom right
	        gl.Uniform(uup, 0)
	        -- offx, offz = 0, -2*stepz
	        glTranslate(0+offx,0,GamemapSizeZ*2+offz)
	        gl.CallList(dList)

	        glUniform(uleft, 1)
	        glTranslate(-GamemapSizeX*2,0,0)
	        gl.CallList(dList)
	        
	        glUniform(umirrorX, 0)
	        glTranslate(GamemapSizeX,0,0)
	        gl.CallList(dList)

	        glUniform(uleft, 0)
	        glUniform(uup, 1)
	        glTranslate(0,0,-GamemapSizeZ*2)
	        gl.CallList(dList)
	        
	        glUniform(uup, 0)
	        glUniform(umirrorZ, 0)
	        glUniform(umirrorX, GamemapSizeX)
	        glTranslate(GamemapSizeX,0,GamemapSizeZ)
	        gl.CallList(dList)

	        glUniform(uleft, 1)
	        glTranslate(-GamemapSizeX*2,0,0)
	        gl.CallList(dList)
	       -- gl.PopMatrix()

        if wiremap then
            gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
        end
        gl.DepthMask(false)
        gl.Texture(false)
        gl.PopMatrix()
        gl.UseShader(0)
        
        gl.FogCoord(0)
    end
end

local function Reset()
	if not drawingEnabled then
		return
	end
	if Spring.GetGameRulesParam("waterLevelModifier") or Spring.GetGameRulesParam("mapgen_enabled") then
		return
	end
	
	if island == nil then
		island = IsIsland()
	end
	local enableMapBorder = false
	if island and not options.drawForIslands.value then
		enableMapBorder = false
	elseif options and (
			options.mapBorderStyle.value == 'cutaway'
			or options.mapBorderStyle.value == 'grid'
			or (options.mapBorderStyle.value == 'texture' and (not forceTextureToGrid))
		)
	then
		enableMapBorder = true
	end
	Spring.SendCommands("mapborder " .. ((enableMapBorder and "1") or "0"))

	
	Spring.SendCommands("luaui disablewidget External VR Grid")
	if dList then
		gl.DeleteList(dList)
		dList = nil
	end
	if mirrorShader then
		gl.DeleteShader(mirrorShader)
		mirrorShader = nil
	end

	if gl.CreateShader and options.useShader.value then
		SetupShaderTable()
		mirrorShader = gl.CreateShader(shaderTable)
		if (mirrorShader == nil) then
			Spring.Log(widget:GetInfo().name, LOG.ERROR, "Map Edge Extension widget: mirror shader error: "..gl.GetShaderLog())
		end
	end
	if not mirrorShader then
		dList = gl.CreateList(DrawOMap, mirrorShader)
		DrawWorldFunc = DrawWorldShaderLess
	else
		umirrorX = gl.GetUniformLocation(mirrorShader,"mirrorX")
		umirrorZ = gl.GetUniformLocation(mirrorShader,"mirrorZ")
		ulengthX = gl.GetUniformLocation(mirrorShader,"lengthX")
		ulengthZ = gl.GetUniformLocation(mirrorShader,"lengthZ")
		uup = gl.GetUniformLocation(mirrorShader,"up")
		uleft = gl.GetUniformLocation(mirrorShader,"left")
		ugrid = gl.GetUniformLocation(mirrorShader,"grid")
		ubrightness = gl.GetUniformLocation(mirrorShader,"brightness")
		dList = gl.CreateList(DrawOMap, mirrorShader)
		DrawWorldFunc = DrawWorldShader
	end
	--Spring.SetDrawGround(false)
end

function widget:Initialize()
	Request()
end

local firstUpdate = true
function widget:Update()
	if firstUpdate then
		firstUpdate = false
		return
	end
	if requestUpdate then
		requestUpdate = false
		Reset()
	end
end


function widget:Shutdown()
	--Spring.SetDrawGround(true)
	if dList then
		gl.DeleteList(dList)
	end
	if mirrorShader then
		gl.DeleteShader(mirrorShader)
	end
end

function widget:DrawWorldPreUnit()
	if drawingEnabled then
		DrawWorldFunc()
	end
end
function widget:DrawWorldRefraction()
	if drawingEnabled then
		DrawWorldFunc()
	end
end

if SPACE_CLICK_OUTSIDE then
	function widget:MousePress(x, y, button)
		local _, mpos = spTraceScreenRay(x, y, true) --//convert UI coordinate into ground coordinate.
		if mpos == nil then --//activate epic menu if mouse position is outside the map
			local _, _, meta, _ = Spring.GetModKeyState()
			if meta then  --//show epicMenu when user also press the Spacebar
				WG.crude.OpenPath(options_path) --click + space will shortcut to option-menu
				WG.crude.ShowMenu() --make epic Chili menu appear.
				return false
			end
		end
	end
end
