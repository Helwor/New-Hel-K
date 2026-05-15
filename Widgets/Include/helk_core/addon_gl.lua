--glAddons
if (not gl) then
	return
end
if not (gl.Utilities and gl.Utilities.DrawMyCircle) then
	VFS.Include("LuaRules/Utilities/glVolumes.lua")
end
if gl.Utilities.DrawDisc then -- this file already loaded
	return
end
local Echo = Spring.Echo
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- CONSTANTS

GL.COLOR_MATERIAL            = 0x0B57 -- use gl.Enable(GL.COLOR_MATERIAL) so set gl.Material ambient and diffusion through gl.Color
GL.COLOR_MATERIAL_FACE       = 0x0B55
GL.COLOR_MATERIAL_PARAMETER  = 0x0B56

GL.CURRENT_COLOR = 2816 --0xb00 use gl.GetNumber(GL.CURRENT_COLOR, 4)




local samplePassedConsts = {
	SAMPLES_PASSED                  = 35092,    -- 0x8914
	ANY_SAMPLES_PASSED              = 35887,    -- 0x8c2f
	ANY_SAMPLES_PASSED_CONSERVATIVE = 36202,    -- 0x8d6a
}
for k,v in pairs(samplePassedConsts) do
	GL[k] = v
end
local stencilResConsts = {
	STENCIL_PASS_DEPTH_FAIL         = 2965,     -- 0xb95
	STENCIL_PASS_DEPTH_PASS         = 2966,     -- 0xb96
	STENCIL_FAIL                    = 2964,     -- 0xb94
	STENCIL_BACK_FAIL               = 34817,    -- 0x8801
	STENCIL_BACK_PASS_DEPTH_FAIL    = 34818,    -- 0x8802
	STENCIL_BACK_PASS_DEPTH_PASS    = 34819,    -- 0x8803
	STENCIL_BITS                    = 3415,     -- 0xd57
}
for k,v in pairs(stencilResConsts) do
	GL[k] = v
end

local stencilOpConsts = {
	KEEP      = 0x1E00,
	INCR_WRAP = 0x8507,
	DECR_WRAP = 0x8508,
}

for k,v in pairs(stencilOpConsts) do
	GL[k] = v
end

local blendConsts = {
	BLEND_COLOR             = 32773,            -- 0x8005
	BLEND_DST               = 3040,             -- 0xbe0
	BLEND_DST_ALPHA         = 32970,            -- 0x80ca
	BLEND_DST_RGB           = 32968,            -- 0x80c8
	BLEND_EQUATION          = 32777,            -- 0x8009
	BLEND_EQUATION_ALPHA    = 34877,            -- 0x883d
	BLEND_EQUATION_RGB      = 32777,            -- 0x8009
	BLEND_SRC               = 3041,             -- 0xbe1
	BLEND_SRC_ALPHA         = 32971,            -- 0x80cb
	BLEND_SRC_RGB           = 32969,            -- 0x80c9
}
for k,v in pairs(blendConsts) do
	GL[k] = v
end
local texFormats = {
	RGBA                    = 0x1908,
	RGBA16F_ARB             = 0x881A,
	RGBA32F_ARB             = 0x8814,
	RGBA12                  = 0x805A,
	RGBA16                  = 0x805B,
	DEPTH_COMPONENT32       = 0x81A7,
	DEPTH24_STENCIL8        = 0x88F0, -- rbo depth/stencil  format
	RGBA4 					= 0x8056,
	R3_G3_B2 				= 0x2A10,
	RGB5_A1 				= 0x8057,
	R8 						= 0x8229,
	RG8 					= 0x822B,
	RGB8 					= 0x8051,
	RGB565 					= 0x8D62,
	R11F_G11F_B10F 			= 0x8C3A,
	COMPRESSED_RGB_ARB 		= 0x84ED,
	COMPRESSED_RGBA_ARB 	= 0x84EE,
	COMPRESSED_RGBA_S3TC_DXT1_EXT = 0x83F1,
}
for k,v in pairs(texFormats) do
	GL[k] = v
end

-------------------------------------------------------
-- gl.Enable / gl.Disable

do -- hax using gl.UnsafeState to enable/disable a state, normally gl.UnsafeState is used to enable and disable (or in reverse) while calling a given function in the same go
	local dumfunc = function() end
	local glUnsafeState = gl.UnsafeState
	gl.Enable = function(state)
		glUnsafeState(state, true, dumfunc)
	end
	gl.Disable = function(state)
		glUnsafeState(state, true, dumfunc)
	end
end

-------------------------------------------------------
-- circles and discs
do
	local glDrawGroundCircle        = gl.DrawGroundCircle -- this one is making hollow circle following ground
	local gluDrawGroundCircle       = gl.Utilities.DrawGroundCircle -- this one is making plain circle following ground
	local glPushMatrix              = gl.PushMatrix
	local glTranslate               = gl.Translate
	local glBillboard               = gl.Billboard
	local glColor                   = gl.Color
	local glText                    = gl.Text
	local glPopMatrix               = gl.PopMatrix
	local gluDrawGroundRectangle    = gl.Utilities.DrawGroundRectangle
	local glPointSize               = gl.PointSize
	local glNormal                  = gl.Normal
	local glVertex                  = gl.Vertex
	local GL_POINTS                 = GL.POINTS
	local glBeginEnd                = gl.BeginEnd
	local glLineStipple             = gl.LineStipple
	local glLineWidth               = gl.LineWidth
	local glCallList                = gl.CallList
	local glScale                   = gl.Scale

	local spWorldToScreenCoords = Spring.WorldToScreenCoords


	local CreateCircle = function(divs,plain, screen)
		local draw = function()
			gl.BeginEnd(plain and GL.TRIANGLE_FAN or GL.LINE_LOOP, function() 
				for i = 0, divs - 1 do
					local r = 2.0 * math.pi * (i / divs)
					local cosv = math.cos(r)
					local sinv = math.sin(r)
					-- gl.TexCoord(cosv, sinv)
					gl.Vertex(cosv, screen and sinv or 0, screen and 0 or sinv)
				end
			end)
		end
		return gl.CreateList(draw)
	end
	local disc = CreateCircle(40,true)
	local circle = CreateCircle(40,false)
	local screen_disc = CreateCircle(40,true, true)
	local screen_circle = CreateCircle(40,false, true)

	local cheap_disc = CreateCircle(20,true)
	local cheap_circle = CreateCircle(20,false)
	local cheap_screen_disc = CreateCircle(20,true, true)
	local cheap_screen_circle = CreateCircle(20,false, true)



	function gl.Utilities.DrawScreenCircle(x,y,r)
		glPushMatrix()
		glTranslate(x, y, 0)
		-- glBillboard()
		glScale(r, r, y)
		glCallList(r < 30 and cheap_screen_circle or screen_circle)
		glPopMatrix()
	end
	function gl.Utilities.DrawScreenDisc(x,y,r)
		glPushMatrix()
		glTranslate(x, y, 0)
		-- glBillboard()
		glScale(r, r, y)
		glCallList(r < 30 and cheap_screen_disc or screen_disc)
		glPopMatrix()
	end
	function gl.Utilities.DrawGroundDisc(x,z,r)
		return gluDrawGroundCircle(x,z,r)
	end
	function gl.Utilities.DrawDisc(x,y,z,r)
		glPushMatrix()
		glTranslate(x, y, z)
		glScale(r, y, r)
		glCallList(r < 50 and cheap_disc or disc)
		glPopMatrix()
	end
	function gl.Utilities.DrawGroundHollowCircle(x,z,r) 
		return glDrawGroundCircle(x,0,z,r,30)
	end
	function gl.Utilities.DrawFlatCircle(x,y,z,r)
		glPushMatrix()
		glTranslate(x, y, z)
		glScale(r, y, r)
		glCallList(r < 50 and cheap_circle or circle)
		glPopMatrix()
	end
end
-- TODO OPTIMIZE THE 3 NEXT
function gl.Utilities.Circle3DVertical(radius, cx, cy, cz, nx, nz, segments)
	local length = math.sqrt(nx*nx + nz*nz)
	if length == 0 then return end  -- Éviter division par zéro
	
	local v1x = -nz / length
	local v1z = nx / length

	gl.BeginEnd(GL.LINE_STRIP, function()
		for i = 0, segments do
			local angle = 2 * math.pi * i / segments
			local cosA = math.cos(angle)
			local sinA = math.sin(angle)
			
			local x = cx + radius * (cosA * v1x)
			local y = cy + radius * (sinA)
			local z = cz + radius * (cosA * v1z)
			
			glVertex(x, y, z)
		end
	end)
end

function gl.Utilities.Circle3D(radius, cx, cy, cz, nx, ny, nz, segments)
	local length = math.sqrt(nx*nx + ny*ny + nz*nz)
	if length == 0 then return end
	
	nx = nx / length
	ny = ny / length
	nz = nz / length
	
	-- Vecteur arbitraire perpendiculaire
	local v1x, v1y, v1z
	if math.abs(nx) < 0.1 then
		v1x, v1y, v1z = 1, 0, 0
	else
		v1x, v1y, v1z = -ny, nx, 0
	end
	
	-- Normaliser v1
	local len1 = math.sqrt(v1x*v1x + v1y*v1y + v1z*v1z)
	v1x, v1y, v1z = v1x/len1, v1y/len1, v1z/len1
	
	-- v2 = normale × v1
	local v2x = ny*v1z - nz*v1y
	local v2y = nz*v1x - nx*v1z
	local v2z = nx*v1y - ny*v1x
	
	gl.BeginEnd(GL.LINE_STRIP, function()
		for i = 0, segments do
			local angle = 2 * math.pi * i / segments
			local cosA = math.cos(angle)
			local sinA = math.sin(angle)
			
			glVertex(
				cx + radius * (cosA * v1x + sinA * v2x),
				cy + radius * (cosA * v1y + sinA * v2y),
				cz + radius * (cosA * v1z + sinA * v2z)
			)
		end
	end)
end

function gl.Utilities.GetNormal2D(dx, dz)
	local length = math.diag(dx, dz)
	if length > 0 then
		return -dz/length, dx/length  -- Perpendiculaire
	end
end

-- STENCIL 
function gl.Utilities.DrawFullScreenQuad()
	gl.MatrixMode(GL.PROJECTION)
	gl.PushMatrix()
	gl.LoadIdentity()
	gl.MatrixMode(GL.MODELVIEW)
	gl.PushMatrix()
	gl.LoadIdentity()

	gl.BeginEnd(GL.QUADS, function()
		gl.TexCoord(0, 0); gl.Vertex(-1, -1)
		gl.TexCoord(1, 0); gl.Vertex( 1, -1)
		gl.TexCoord(1, 1); gl.Vertex( 1,  1)
		gl.TexCoord(0, 1); gl.Vertex(-1,  1)
	end)
	
	gl.MatrixMode(GL.PROJECTION)
	gl.PopMatrix()
	gl.MatrixMode(GL.MODELVIEW)
	gl.PopMatrix()
end

function gl.Utilities.VerifStencil()
	gl.PushAttrib(GL.ENABLE_BIT + GL.COLOR_BUFFER_BIT + GL.DEPTH_BUFFER_BIT + GL.STENCIL_BUFFER_BIT + GL.CURRENT_BIT)
	gl.DepthTest(false)
	gl.Culling(false)
	gl.ColorMask(true, true, true, true)
	gl.StencilOp(GL.KEEP, GL.KEEP, GL.KEEP)
	gl.StencilMask(0xff)

	gl.StencilFunc(GL.EQUAL, 0, 0xff)
	gl.Color(0,0,0,0.2)
	gl.Utilities.DrawFullScreenQuad()

	gl.StencilFunc(GL.EQUAL, 1, 0xff)
	gl.Color(1,0,0,0.2)
	gl.Utilities.DrawFullScreenQuad()

	gl.StencilFunc(GL.EQUAL, 2, 0xff)
	gl.Color(0,1,0,0.2)
	gl.Utilities.DrawFullScreenQuad()

	gl.StencilFunc(GL.EQUAL, 3, 0xff)
	gl.Color(0,0,1,0.2)
	gl.Utilities.DrawFullScreenQuad()

	gl.StencilFunc(GL.EQUAL, 4, 0xff)
	gl.Color(0,1,1,0.2)
	gl.Utilities.DrawFullScreenQuad()

	gl.StencilFunc(GL.EQUAL, 0xff, 0xff)
	gl.Color(1,1,1,0.2)
	gl.Utilities.DrawFullScreenQuad()

	gl.PopAttrib()
end
-- complements to glVolumes.lua
local function GetUpvaluesOf(func)
	local i = 1
	local getupvalue = debug.getupvalue
	local ret = {}
	while true do
		local name, value = getupvalue(func, i)
		if not name then break end
		ret[name] = value
		i = i + 1
	end
	return ret
end
local upvalues = GetUpvaluesOf(gl.Utilities.DrawMergedGroundCircle)
local shapeHeight = upvalues.shapeHeight
local cylinder = upvalues.cylinder
local averageGroundHeight = upvalues.averageGroundHeight

function gl.Utilities.DrawMergedVolumes(vol_dlist) -- really draw merged volumes and not their imprint (misleading name of glVolumes.lua gl.Utilities.DrawMergedVolume)
	gl.StencilTest(true)
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
	gl.StencilMask(3)
	gl.StencilOp(GL.KEEP, GL.KEEP, GL.INCR)
	gl.StencilFunc(GL.NOTEQUAL, 2, 3)
	gl.CallList(vol_dlist)
	gl.StencilTest(false)
	gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
end

if gl.StencilOpSeparate then -- strangely enough, some ppl don't have "Separate" variants of stencil funcs, even though the engine is supposed to expose them
	function gl.Utilities.DrawMergedGroundCircles(items, createList)
		if createList then
			return gl.CreateList(gl.Utilities.DrawMergedGroundCircles, items)
		end
		gl.PushMatrix()
		gl.Translate(0, averageGroundHeight, 0)
		gl.Utilities.DrawMergedVolumesImprint(
			function()
				for _, item in pairs(items) do
					gl.PushMatrix()
					gl.Translate(item.x or item[1], 0, item.z or item[2])
					gl.Scale(item.radius or item[3], shapeHeight, item.radius or item[3])
					gl.CallList(cylinder)
					gl.PopMatrix()
				end
			end
		)
		gl.PopMatrix()
	end
	function gl.Utilities.DrawMergedVolumesImprint(param, createList) -- multi volumes the equivalent of gl.Utilities.DrawMergedVolume(vol_dlist) but in one call for multiple volumes
		if createList then
			return gl.CreateList(gl.Utilities.DrawMergedVolumesImprint, param)
		end
		gl.PushAttrib(GL.ENABLE_BIT + GL.COLOR_BUFFER_BIT + GL.DEPTH_BUFFER_BIT + GL.STENCIL_BUFFER_BIT + GL.CURRENT_BIT)
		gl.DepthMask(false)
		-- fix map edge extension 2 leaving wrong states
		gl.Culling(false)
		gl.DepthTest(GL.LEQUAL)
		--
		if (gl.DepthClamp) then gl.DepthClamp(true) end
		gl.ColorMask(false, false, false, false)
		gl.DepthTest(true)
		gl.Culling(false)
		gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
		gl.StencilTest(true)
		gl.StencilMask(0xff)
		gl.StencilOpSeparate(GL.BACK, GL.KEEP, GL.INCR_WRAP, GL.KEEP)
		gl.StencilOpSeparate(GL.FRONT, GL.KEEP, GL.DECR_WRAP, GL.KEEP)
		gl.StencilFunc(GL.ALWAYS, 0, 0xff)
		if type(param) == 'function' then
			param()
		else
			gl.CallList(param)
		end


		gl.ColorMask(true, true, true, true)
		gl.Culling(GL.BACK)
		gl.StencilFunc(GL.NOTEQUAL, 0, 0xff)
		gl.Utilities.DrawFullScreenQuad()
		gl.Culling(false)
		gl.Clear(GL.STENCIL_BUFFER_BIT, 0)
		gl.StencilTest(false)
		gl.DepthTest(false)
		if (gl.DepthClamp) then gl.DepthClamp(false) end
		gl.PopAttrib()

	end
end


--------------------------------------------------
-- some gl gets and debugging

local oriGlGetFixedState = gl.GetFixedState
function gl.GetFixedState(arg,toString)
	local argStr = tostring(arg):lower()
	local targ
	if argStr == 'stencilop' then
		targ = stencilOpConsts
	elseif argStr == 'samplepassed' then
		targ = samplePassedConsts
	end
	if targ then
		local t = {}
		if toString then
			for k,v in pairs(targ) do
				table.insert(t, gl.GetNumber(v))
			end
			return table.concat(t,', ')
		else
			for k,v in pairs(targ) do
				local s = gl.GetNumber(v)
				t['GL_'..k] = s
			end
			return t
		end
	end
	return oriGlGetFixedState(arg,toString)
end

local GLConstByValue = function(value)
	if type(value) == 'table' then
		if table.tostring then
			return table.tostring(value)
		else
			return tostring(value)
		end
	end

	local str = ''
	for k,v in pairs(GL) do
		if v == value then
			str = str .. k .. ' / '
		end
	end
	return str:sub(1,-3)
end

function gl.ReadFixedState(state)
	local a,b,c,d = gl.GetFixedState(state)
	Echo('--------',state,'is',a==nil and '' or a,b==nil and '' or b,c==nil and '' or c,d==nil and '' or d)
	if a or b or c or d then
		local t = type(a) == 'table' and a
			or type(b) == 'table' and b
			or type(c) == 'table' and c
			or type(d) == 'table' and d
		if t then
			for k,v in pairs(t) do
				Echo(k,v,GLConstByValue(v))
			end
		end
	end
end

function gl.GetBlendState(echo)
	local ret = {}
	for k,v in pairs(blendConsts) do
		ret[k] = gl.GetNumber(v)
	end
	if echo then
		for k,v in pairs(ret) do
			Echo(k,GLConstByValue(v))
		end
	end
	return ret
end
Echo('[HEL-K] Successfully implemented gl Addons')
--// =============================================================================

