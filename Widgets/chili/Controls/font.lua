--// =============================================================================

--- Font module

--- Font fields
-- Inherits from Control.
-- @see control.Control
-- @table Font
-- @string[opt = "FreeSansBold.otf"] font font name
-- @int[opt = 12] size font size
-- @bool[opt = false] shadow shadow enabled
-- @bool[opt = false] outline outline enabled
-- @tparam {r, g, b, a} color color table (default {1, 1, 1, 1})
-- @tparam {r, g, b, a} outlineColor outlineColor table (default {0, 0, 0, 1})
-- @bool[opt = true] autoOutlineColor ??
Font = Object:Inherit{
	classname     = 'font',

	font          = "FreeSansBold.otf",
	size          = 12,
	outlineWidth  = 3,
	outlineWeight = 3,

	shadow        = false,
	outline       = false,
	color         = {1, 1, 1, 1},
	outlineColor  = {0, 0, 0, 1},
	autoOutlineColor = false,
	useRTT = false,
	uiScale = 1
}

local this = Font
local inherited = this.inherited

--// =============================================================================

function Font:New(obj)
	obj = inherited.New(self, obj)
	obj.uiScale = (WG and WG.uiScale or 1)

	--// Load the font
	obj:_LoadFont()

	return obj
end


function Font:Dispose(...)
	if (not self.disposed) then
		FontHandler.UnloadFont(self._font)
	end
	inherited.Dispose(self, ...)
end

--// =============================================================================

function Font:_LoadFont()
	local oldfont = self._font
	local old_rttfont = self._rttfont
	self._font = FontHandler.LoadFont(self.font, math.floor(self.size*self.uiScale), math.floor(self.outlineWidth*self.uiScale), self.outlineWeight)
	-- self._rttfont = FontHandler.LoadFont(self.font, math.floor(self.size*self.uiScale), math.floor(self.outlineWidth*1.5*self.uiScale), self.outlineWeight*1.2)
	--self._font = FontHandler.LoadFont(self.font, self.size, self.outlineWidth, self.outlineWeight)
	--// do this after LoadFont because it can happen that LoadFont returns the same font again
	--// but if we Unload our old one before, the gc could collect it before, so the engine would have to reload it again
	FontHandler.UnloadFont(oldfont)
	if old_rttfont then
		FontHandler.UnloadFont(old_rttfont)
	end
end

--// =============================================================================

local function NotEqual(v1, v2)
	local t1 = type(v1)
	local t2 = type(v2)

	if (t1 ~= t2) then
		return true
	end

	local isindexable = (t == "table") or (t == "metatable") or (t == "userdata")
	if (not isindexable) then
		return (t1 ~= t2)
	end

	for i, v in pairs(v1) do
		if (v ~= v2[i]) then
			return true
		end
	end
	for i, v in pairs(v2) do
		if (v ~= v1[i]) then
			return true
		end
	end
end


do
	--// Create some Set... methods (e.g. SetColor, SetSize, SetFont, ...)

	local params = {
		font = true,
		size = true,
		outlineWidth = true,
		outlineWeight = true,
		shadow = false,
		outline = false,
		color = false,
		outlineColor = false,
		autoOutlineColor = false,
	}

	for param, recreateFont in pairs(params) do
		local paramWithUpperCase = param:gsub("^%l", string.upper)
		local funcname = "Set" .. paramWithUpperCase

		Font[funcname] = function(self, value, ...)
			local t = type(value)

			local oldValue = self[param]

			if (t == "table") then
				self[param] = table.shallowcopy(value)
			else
				local to = type(self[param])
				if (to == "table") then
					--// this allows :SetColor(r, g, b, a) and :SetColor({r, g, b, a})
					local newtable = {value, ...}
					table.merge(newtable, self[param])
					self[param] = newtable
				else
					self[param] = value
				end
			end

			local p = self.parent
			if (recreateFont) then
				self:_LoadFont()
				if (p) then
					p:RequestRealign()
				end
			else
				if (p) and NotEqual(oldValue, self[param]) then
					p:Invalidate()
				end
			end
		end
	end

	params = nil
end

--// =============================================================================
function Font:GetTextColor(text)
	local _,_, argb = self:find("(\255...)")
	if argb then
		return {argb:byte(2)/255, argb:byte(3)/255, argb:byte(4)/255, 1}
	end
end

function Font:GetLineHeight(size)
	return self._font.lineheight * (size or self.size)
end

function Font:GetAscenderHeight(size)
	local font = self._font
	return (font.lineheight + font.descender) * (size or self.size)
end

function Font:GetTextWidth(text, size)
	return (self._font):GetTextWidth(text) * (size or self.size)
end

function Font:GetTextHeight(text, size)
	if (not size) then
		size = self.size
	end
	local h, descender, numlines = (self._font):GetTextHeight(text)
	return h*size, descender*size, numlines
end

function Font:WrapText(text, width, height, size)
	if (not size) then
		size = self.size
	end
	if (height < 1.5 * self._font.lineheight) or (width < size) then
		return text --//workaround for a bug in <= 80.5.2
	end
	return (self._font):WrapText(text, width, height, size)
end

--// =============================================================================

function Font:AdjustPosToAlignment(x, y, width, height, align, valign)
	local extra = ''

	if self.shadow then
		width  = width  - 1 - self.size * 0.1
		height = height - 1 - self.size * 0.1
	elseif self.outline then
		width  = width  - 1 - self.outlineWidth
		height = height - 1 - self.outlineWidth
	end

	--// vertical alignment
	if valign == "center" then
		y     = y + height/2
		extra = 'v'
	elseif valign == "top" then
		extra = 't'
	elseif valign == "bottom" then
		y     = y + height
		extra = 'b'
	elseif valign == "linecenter" then
		y     = y + (height / 2) + (1 + self._font.descender) * self.size / 2
		extra = 'x'
	else
		--// ascender
		extra = 'a'
	end
	--FIXME add baseline 'd'

	--// horizontal alignment
	if align == "left" then
		--do nothing
	elseif align == "center" then
		x     = x + width/2
		extra = extra .. 'c'
	elseif align == "right" then
		x     = x + width
		extra = extra .. 'r'
	end

	return x, y, extra
end

local function _GetExtra(align, valign)
	local extra = ''

	--// vertical alignment
	if valign == "center" then
		extra = 'v'
	elseif valign == "top" then
		extra = 't'
	elseif valign == "bottom" then
		extra = 'b'
	else
		--// ascender
		extra = 'a'
	end

	--// horizontal alignment
	if align == "left" then
		--do nothing
	elseif align == "center" then
		extra = extra .. 'c'
	elseif align == "right" then
		extra = extra .. 'r'
	end

	return extra
end

--// =============================================================================
function Font:CheckUiScaleChange()
	if (WG and WG.uiScale or 1) ~= self.uiScale then
		self.uiScale = (WG and WG.uiScale or 1)
		self:_LoadFont()
	end
end
local lastScale = false
function Font:ScaleChanged()
	if (WG and WG.uiScale or 1) ~= lastScale then
		lastScale = (WG and WG.uiScale or 1)
		return lastScale
	end
end
---------------------------
---------------------------

local autotable = (function() -- create auto table with given max level
	local auto_mt
	auto_mt = {
		__index=function(self,k)
			local lvl, maxlvl = self._level, self._maxlevel
			if not lvl or lvl == maxlvl then
				rawset(self,k,{})
				return self[k]
			elseif lvl < maxlvl then
				rawset(
					self,
					k,
					setmetatable(
						{_level = lvl+1, _maxlevel = maxlvl},
						auto_mt
					)
				)
				return self[k]
			end
		end
	}
	return function(maxlevel)
		return setmetatable(
			{_level = 1,_maxlevel = maxlevel or 2},
			auto_mt
		)
	end
end)()


local glPushAttrib 	= gl.PushAttrib
local glPushMatrix 	= gl.PushMatrix
local glScale		= gl.Scale
local glBlendFuncSeparate 		= gl.BlendFuncSeparate
local GL_SRC_ALPHA	= GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA	= GL.ONE_MINUS_SRC_ALPHA
local GL_ZERO		= GL.ZERO
local GL_ONE_MINUS_SRC_ALPHA	= GL.ONE_MINUS_SRC_ALPHA
local GL_COLOR_BUFFER_BIT		= GL.COLOR_BUFFER_BIT
local glPopMatrix	= gl.PopMatrix
local glPopAttrib	= gl.PopAttrib



local glCallList = gl.CallList
local glCreateList = gl.CreateList
local glDeleteList = gl.DeleteList
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local lists = setmetatable({},{__mode = 'k'})
local renewed, stayed, created = 0, 0, 0
local elapsed = 0
local texts = setmetatable({},{__mode = 'v'})
local lists = {}
local objs = setmetatable({},{__mode = 'k'})
local done = 0
local lastChange = ''
local time = spGetTimer()




local useLists = false
local todo, td = {}, 0
local useBatch = false
local Echo = Spring.Echo
local const = {
	ZERO = GL.ZERO,
	ONE = GL.ONE,
	SRC_COLOR = GL.SRC_COLOR,
	ONE_MINUS_SRC_COLOR = GL.ONE_MINUS_SRC_COLOR,
	DST_COLOR = GL.DST_COLOR,
	ONE_MINUS_DST_COLOR = GL.ONE_MINUS_DST_COLOR,
	SRC_ALPHA = GL.SRC_ALPHA,
	ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA,
	DST_ALPHA = GL.DST_ALPHA,
	ONE_MINUS_DST_ALPHA = GL.ONE_MINUS_DST_ALPHA,
	-- CONSTANT_COLOR = GL.CONSTANT_COLOR,
	-- ONE_MINUS_CONSTANT_COLOR = GL.ONE_MINUS_CONSTANT_COLOR,
	-- CONSTANT_ALPHA = GL.CONSTANT_ALPHA,
	-- ONE_MINUS_CONSTANT_ALPHA = GL.ONE_MINUS_CONSTANT_ALPHA,
	SRC_ALPHA_SATURATE = GL.SRC_ALPHA_SATURATE,
}
local constI = {
	'ZERO',
	'ONE',
	'SRC_COLOR',
	'ONE_MINUS_SRC_COLOR',
	'DST_COLOR',
	'ONE_MINUS_DST_COLOR',
	'SRC_ALPHA',
	'ONE_MINUS_SRC_ALPHA',
	'DST_ALPHA',
	'ONE_MINUS_DST_ALPHA',
	-- 'CONSTANT_COLOR',
	-- 'ONE_MINUS_CONSTANT_COLOR',
	-- 'CONSTANT_ALPHA',
	-- 'ONE_MINUS_CONSTANT_ALPHA',
	'SRC_ALPHA_SATURATE',
}
-- local checktable = auto_table(3)

RTT_FONT_LISTS = false
local n = 0
local count = 0
-- local addlist = function(list)
-- 	local lists = RTT_FONT_LISTS
-- 	if not lists then
-- 		count = 0
-- 		lists = {}
-- 		RTT_FONT_LISTS = lists
-- 		n = 0
-- 	end
-- 	count = count + 1
-- 	n = n + 1
-- 	lists[n] = list

-- end
local q = 0
local t = {}
local count = 0
local done = false
function Font:_DrawText(text, x, y, extra, querier,index, len)
	self:CheckUiScaleChange()
	------------------------------------------------
	-- --------- trying to gather list 
	-- -- -- gl.MatrixMode(GL.MODELVIEW)
	-- local font = self._font
	-- if AreInRTT() and math.random()<0.5 then
	-- 	gl.PushMatrix()
	-- 		local matrix = {gl.GetMatrixData(GL.TEXTURE)}
	-- 		addlist(
	-- 			gl.CreateList(
	-- 				function()
	-- 					-- glScale(1, -1, 1)
	-- 					gl.LoadMatrix(matrix)
	-- 					gl.PushMatrix()
	-- 						font:Begin()
	-- 							font:SetTextColor(self.color)
	-- 							font:SetOutlineColor(self.outlineColor)
	-- 							font:SetAutoOutlineColor(self.autoOutlineColor)
	-- 							font:Print(text, x, y, self.size, extra)
	-- 						font:End()
	-- 					gl.PopMatrix()
						
	-- 				end
	-- 			)
	-- 		)
	-- 	gl.PopMatrix()
	-- 	if self.parent then
	-- 		self.parent.ancestor:Invalidate()
	-- 	end
	-- 	return
	-- end
	--------------------------------------------
	local font = --[[AreInRTT() and self._rttfont or--]] self._font

	if --[[false and--]] AreInRTT() --[[and math.random()<0.5--]] then
		if querier then
			if querier.font_list then
				gl.DeleteList(querier.font_list)
			end
			if len and len > 1 then
				if index == 1 then
					self.tmp = {{text,y}}
				else
					self.tmp[index] = {text,y}

					if index == len then
						querier.font_list = gl.CreateList(
							function()
								glPushAttrib(GL_COLOR_BUFFER_BIT)
								glPushMatrix()
									-- gl.LoadMatrix(matrix)
									glScale(1, -1, 1)
									font:Begin()
									font:SetTextColor(self.color)
									font:SetOutlineColor(self.outlineColor)
									font:SetAutoOutlineColor(self.autoOutlineColor)

									for _, obj in pairs(self.tmp) do
										font:Print(obj[1], x, -obj[2], self.size, extra)
									end
									font:End()
									-- gl.Color(1,1,1,1)
								glPopMatrix()
								glPopAttrib()
							end
						)
						self.tmp = nil
					end
				end
			else
				-- gl.PushMatrix()
					-- local matrix = {gl.GetMatrixData(GL.MODELVIEW)}
					querier.font_list = gl.CreateList(
						function()

							glPushAttrib(GL_COLOR_BUFFER_BIT)
							glPushMatrix()
								-- gl.LoadMatrix(matrix)
								glScale(1, -1, 1)
								font:Begin()
								font:SetTextColor(self.color)
								font:SetOutlineColor(self.outlineColor)
								font:SetAutoOutlineColor(self.autoOutlineColor)
								-- if AreInRTT() then
								-- 	gl.Color(1,1,0,1)
								-- 	glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE_MINUS_SRC_ALPHA)
								-- end
								font:Print(text, x, -y, self.size, extra)
								font:End()
								-- gl.Color(1,1,1,1)
							glPopMatrix()
							glPopAttrib()
						end
					)
				-- gl.PopMatrix()
				-- querier.ancestor:Invalidate()
			end
		end
		return
	end
	--------------------------------------------

	glPushMatrix()
		glScale(1, -1, 1)
		if AreInRTT() then
			-- gl.Blending(false)
			-- gl.DepthTest(true)
			-- gl.Color(1,1,1,1)
			-- gl.Color(1,1,0,1)
			-- glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE_MINUS_SRC_ALPHA)
			-- gl.ColorMask(false)
			-- gl.ColorMask(false)
			-- gl.StencilTest(false)
			-- gl.Blending(false)
			-- gl.DepthTest(GL.ALWAYS)
			-- gl.ColorMask(false)
			-- gl.StencilFunc(GL.ALWAYS, 1, 0xFF)
			-- gl.StencilOp(GL.KEEP, GL.KEEP, GL.KEEP)
			-- gl.ColorMask(false,false,false,true)
			-- 	font:Begin()
			-- 	font:SetTextColor(self.color)
			-- 	font:SetOutlineColor(self.outlineColor)
			-- 	font:SetAutoOutlineColor(self.autoOutlineColor)
			-- 	font:Print(text, x, -y, self.size, extra)
			-- 	font:End()

			-- gl.ColorMask(true,true,true,true)
			-- return
		end
	glPushAttrib(GL_COLOR_BUFFER_BIT)
		-- if not done and not AreInRTT() and WG.Chili and WG.Chili.TELLBLEND then
		-- 	done = true
		-- -- if not AreInRTT () then
		-- 	-- count = count + 1
		-- 	-- if count < 5 then
		-- 		BLENDSTATE = gl.GetBlendState()
		-- 		Echo('DONE STATE',count,'tell blend is',WG.Chili.TELLBLEND,'text',text)
		-- 		for k,v in pairs(BLENDSTATE) do
		-- 			Echo(k,v)
		-- 		end
		-- 	-- end
		-- end
		---------------
		-- if not done and type(text) == 'string' and not AreInRTT() then
		-- 	local _, stripped = text:stripcolor()
		-- 	if stripped then
		-- 		if type(stripped) ~= 'string' then
		-- 			Echo('wrong stripped type !', type(stripped),stripped)
		-- 		elseif stripped:find('TELL BLEND') or text:find('TELL BLEND') then
		-- 			done = true
		-- 			BLENDSTATE = gl.GetBlendState()
		-- 			Echo('DONE STATE, in RTT?',AreInRTT())
		-- 			local ret = {}
		-- 			for k,v in pairs(BLENDSTATE) do
		-- 				local name = ''

		-- 				for n,const in pairs(GL) do
		-- 					if v == const then
		-- 						name = name .. n .. ' | '
		-- 					end
		-- 				end
		-- 				ret[#ret+1] = tostring(k)..' = ' ..name:sub(1,-4),'('..tostring(v)..')'
		-- 			end
		-- 			ret = table.concat(ret,'\n')
		-- 			Echo(ret)
		-- 			Spring.SetClipboard(ret)
		-- 		elseif stripped:find('TELL STENCIL') then
		-- 			done = true
		-- 			local infoname = 'stencil'
		-- 			local info = gl.GetFixedState(infoname)
		-- 			if type(info) == 'table' then
		-- 				for k,v in pairs(info) do
		-- 					Echo('Stencil props',k,v)
		-- 				end
		-- 			else
		-- 				Echo(infoname .." is ", info)
		-- 			end
		-- 		end
		-- 	end
		-- end
		---------------
		-- if not AreInRTT() then
		-- gl.BlendFuncSeparate(GL.ONE, GL.ONE, GL.ZERO, GL.ZERO)
		if not AreInRTT() then
			font:Begin()
		end
		-- end
		-- if AreInRTT() then
		-- 	gl.BlendFuncSeparate(GL.ZERO, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
		-- 	if not self._color then
		-- 		self._color = self.color
		-- 	end
		-- 	self.color = {1,0,0,1}
		-- elseif self._color then
		-- 	self.color = self._color
		-- 	self._color = nil
		-- end
		font:SetTextColor(self.color)
		font:SetOutlineColor(self.outlineColor)
		font:SetAutoOutlineColor(self.autoOutlineColor)
							
							
		-- gl.BlendFuncSeparate(GL.ONE, GL.ONE, GL.ZERO, GL.ZERO)
		-- font:Print(text, x, -y, self.size, (extra or '')..(AreInRTT() and 'B' or ''))
		-- if not AreInRTT() then
			font:Print(text, x, -y, self.size, extra)
		-- end
		-- if tostring(text):find('hkfuncs2') and not DONE then
		-- 	DONE = true
		-- 	Echo("EXTRA is ", text,extra)
		-- end

		-- font:glPrint(x, -y, self.size, text)
		-- if not AreInRTT() then
		-- end
		-- gl.Color(1,1,1,1)
		if AreInRTT() then
			-- gl.Color(0,0,0,1)
			-- gl.ColorMask(true,true,true,false)
			-- gl.Blending(true)
			-- gl.StencilTest(true)
			-- gl.Blending(true)
			-- gl.ColorMask(false,false,false,true)
			-- gl.BlendFuncSeparate(GL.ONE, GL.ONE, GL.ZERO, GL.ZERO)
			-- glBlendFuncSeparate(GL.ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE_MINUS_SRC_ALPHA)
			-- gl.Blending(false)
			-- font:Print(text, x, -y, self.size, extra)
			-- gl.Blending(true)
			-- gl.ColorMask(true)
			-- gl.ColorMask(true)
			-- gl.StencilFunc(GL.EQUAL, STENCIL_MASK or 1, 0xFF)
			-- gl.ColorMask(true)
			-- gl.StencilOp(GL.KEEP, GL.KEEP, GL.KEEP)
			gl.Blending('reset')
		end
		if not AreInRTT() then
			font:End()
		end
		if AreInRTT() then
			-- gl.Color(1,1,1,1)
			-- gl.ColorMask(true,true,true,true)
		end
		gl.ColorMask(true)
	glPopMatrix()
	glPopAttrib()
end

function Font.SetUseBatch(bool)
	useBatch = bool
end

function Font.DrawAllFonts() -- not working, dont got absolute position
	local newScale = Font.ScaleChanged()
	if newScale then
		for obj in pairs(todo) do
			obj.uiScale = newScale
			obj._LoadFont()
		end
	end


	glPushAttrib(GL_COLOR_BUFFER_BIT)
	glPushMatrix()
	glScale(1, -1, 1)
		if AreInRTT() then
			glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE_MINUS_SRC_ALPHA)
		end
		for obj in pairs(todo) do
			local font = obj._font

			font:Begin()
			font:SetTextColor(obj.color)
			font:SetOutlineColor(obj.outlineColor)
			font:SetAutoOutlineColor(obj.autoOutlineColor)
			font:Print(obj.text, obj.tx, -obj.ty, obj.size, obj.extra)
			font:End()
			todo[obj] = nil
		end
	glPopMatrix()
	glPopAttrib()

end

function Font.SetUseLists(bool)
	useLists = bool
end


function Font:GetList(text, x, y, extra)
	-- elapsed = spDiffTimers(spGetTimer(), time)

	-- local listObj = lists[self]
	-- if not listObj then
	-- 	listObj = {
	-- 		selfParams = {
	-- 			-- color = self.color,
	-- 			-- size = self.size,
	-- 	 	-- 	outlineColor = self.outlineColor,
	-- 	 	-- 	autoOutlineColor = self.autoOutlineColor,
	-- 	 		-- _font = self._font,
	-- 		},
	-- 		params = {
	-- 			text='',
	-- 			-- x=x,
	-- 			-- y=y,
	-- 			-- extra=extra, 
	-- 	 	},
	-- 		list = 0,
	-- 	}
	-- 	created = created + 1
	-- 	lists[self] = listObj
	-- end
	done = done + 1
	if done > 1000000 then
		Echo(
			'screen0', screen0,
			'count', ('%.1fM'):format((renewed+stayed)/1000000),
			'created / reused',('%.4f'):format((stayed>0 and (renewed/stayed) or 1) * 100 ) .. '%',
			'total lists', table.size(lists),
			'total objs', table.size(objs),
			'lastChange', lastChange
		)
 		-- time = spGetTimer()
		for list, obj in pairs(lists) do
			glDeleteList(list)
			lists[list] = nil
			local byText = obj.byText
			for txt in pairs(byText) do
				byText[txt] = nil
			end
		end
		done = 0

	end
	local renew = false
	local byText = self.byText
	if not byText then
		byText = {}
		self.byText = byText
		objs[self] = true
		self.OnDispose = self.OnDispose or {}
		table.insert(self.OnDispose, function() 
			for txt,l in pairs(self.byText) do
				glDeleteList(l) 
				self.byText[txt] = nil
				lists[l] = nil 
			end 
			objs[self] = nil
		end)
	end
	local list = byText[text]
	if not list or self.lastcolor ~= self.color or self.ty ~= y or self.tx ~= x then -- that checking break the time we gained
		self.lastcolor = self.color
		if list then
			glDeleteList(list)
		end
		self.ty = y
		list = glCreateList(Font._DrawText, self, text, x, y, extra)
		byText[text] = list
		renew = true
		lists[list] = self
		lastChange = text
	end
	-- if p.x~=x then renew = true p.x = x end
	-- if p.y~=y then renew = true p.y = y end
	-- if p.extra~=extra then renew = true p.extra = extra end
	-- for k,v in pairs(selfp) do
	-- 	if self[k] ~= v then
	-- 		renew = true
	-- 		selfp[k] = self[k]
	-- 	end
	-- end
	if renew then
		renewed = renewed + 1
	else
		stayed = stayed + 1
	end


	return list

end


function Font:Draw(text, x, y, align, valign, querier,index, len)
	if (not text) then
		return
	end
	self:CheckUiScaleChange()

	local extra = _GetExtra(align, valign)
	if self.outline then
		extra = extra .. 'o'
	elseif self.shadow then
		extra = extra .. 's'
	end
	if useBatch then
		self.text, self.tx, self.ty, self.extra = text, x, y, extra
		todo[self] = true
	elseif useLists then
		glCallList(self:GetList(text, x, y, extra, querier))
	else
		self:_DrawText(text, x, y, extra, querier,index, len)
	end
end


function Font:DrawInBox(text, x, y, w, h, align, valign, querier)
	if (not text) then
		return
	end
	self:CheckUiScaleChange()

	local x, y, extra = self:AdjustPosToAlignment(x, y, w, h, align, valign)

	if self.outline then
		extra = extra .. 'o'
	elseif self.shadow then
		extra = extra .. 's'
	end

	y = y + 1 --// FIXME: if this isn't done some chars as 'R' get truncated at the top
	if useBatch then
		self.text, self.tx, self.ty, self.extra = text, x+w, y+h, extra
		self.tw, self.th = w, h
		todo[self] = true
	elseif useLists then
		glCallList(self:GetList(text, x, y, extra, querier))
	else
		self:_DrawText(text, x, y, extra, querier)
	end
end

Font.Print = Font.Draw
Font.PrintInBox = Font.DrawInBox

--// =============================================================================
