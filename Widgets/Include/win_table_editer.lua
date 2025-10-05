local TESTME = false
if TESTME then
	function widget:GetInfo()
		return {
			name      = "_WinTableEditer",
			desc      = "",
			author    = "Helwor",
			date      = "Dec 2023",
			license   = "GNU GPL, v2 or later",
			layer     = 1, -- after Chili
			enabled   = true,  --  loaded by default?
			-- api       = true,
			handler   = true,
		}
	end
end
local Echo                      = Spring.Echo
local Screen0


-- win content to table
local isbool = {
	[true] = true,
	[false] = true,
}
local strBool = {
	['true'] = true,
	['false'] = false,
}

local tablecode = function(T)
	local follow = 1
	local parts, n = {}, 0
	for k,v in pairs(T)do
		local equal = ' = '
		-- Echo(k,v, isbool[v])
		if type(k)=='string' then
			if k:find('[^%w_]') or k:find('%d') then
				k = '["'..k:gsub('([\'\"])','\\%1')..'"]'
				k = k:gsub('\n','\\n')
			end
		elseif type(k)=='number' then
			if follow == k then
				follow = follow + 1
				k = ''
				equal = ''
			else
				k = '['..k..']'
			end
		else
			k = tostring(k)
		end
		if type(v) == 'string' then
			if v:find('\n') then
				v = '[['..v..']]'
			elseif strBool[v] == nil then
				v = "'"..v:gsub('([\'\"])','\\%1').."'"
			end
		else
			v = tostring(v)
		end
		n = n + 1
		parts[n] = k..equal..v..", "
	end
	-- Echo('{\n\t' .. table.concat(parts,'\n\t') .. '\n}')
	return '{\n\t' .. table.concat(parts,'\n\t') .. '\n}'
end

local WinContentToTable = function(control, toT) -- for saving or clipping code
	if toT then
		for k,v in pairs(toT) do
			toT[k] = nil
		end
	else
		toT = {}
	end
	for i,child in ipairs(control.parent.children) do
		if child.classname == 'scrollpanel' then
			local panel = child.children[1]
			for  i, child in ipairs(panel.children) do
				if child.classname == 'editbox' then
					local value = child.text
					if value and type(value) == 'string' then
						if #value > 0 then
							local key
							local pair1, pair2 = value:match('([^=]-) ?= ?(.+)$')
							if pair1 and #pair1>0 and pair2 then
								key, value = pair1, pair2
								if tonumber(key) then
									key = tonumber(key)
								end
							end
							if tonumber(value) then
								value = tonumber(value)
							else
								local bool = strBool[value]
								if bool ~= nil then
									value = bool
								end
							end
							if key then
								toT[key] = value
							else
								-- Echo('saving value', value)
								table.insert(toT, value)
							end
						end
					end
				end
			end
		end
	end
	return toT
end


-- editbox behaviours

local RETURN, UP, DOWN, ESCAPE, DEL = Spring.GetKeyCode('enter'),
									  Spring.GetKeyCode('up'),
									  Spring.GetKeyCode('down'),
									  Spring.GetKeyCode('escape'),
									  Spring.GetKeyCode('delete')
local navKey = {
	[RETURN] = true,
	[ESCAPE] = true,
	[DOWN] = true,
	[UP] = true,
	[DEL] = true,
}

-- common editbox methods

local function FixFocus(self) -- workaround to fix the hovering when another box was focused before the click
	for i, child in ipairs(self.parent.children) do
		if child ~= self then
			child:MouseOut()
		end
	end
end
local function GoAndSelect(control)
	Screen0:FocusControl(control)
	control:Select(1, control.text:len()+1)
end
local function RemoveBox(self, i)
	local panel = self.parent
	panel:RemoveChild(self)
	local neighs = panel.children
	for i = i, #neighs do
		local neigh = neighs[i]
		neigh.y = neigh.y - 19
	end
	panel:Invalidate()

end
local function Navigate(self, key, mods)
	if not navKey[key] then
		self.emptyText = self.text == ''
		return
	end

	if key == ESCAPE then
		Screen0:FocusControl(self.parent)
		return true
	end
	local neighbours = self.parent.children
	local lastFound, gotoNext
	for i = #neighbours, 1, -1  do
		local neigh = neighbours[i]
		if neigh.classname =='editbox' then
			if neigh == self then
				if key == DEL then
					if self.emptyText or mods.ctrl then
						if lastFound then
							GoAndSelect(lastFound)
							RemoveBox(self, i)
						end
					end
					break
				elseif key == RETURN then
					if lastFound then
						GoAndSelect(lastFound)
					else
						self.parent:AddAutoEmptyBox(true)
					end
					break
				elseif key == DOWN then
					if lastFound then
						GoAndSelect(lastFound)
					end
					break
				elseif key == UP then
					gotoNext = true
				end
			elseif gotoNext then
				GoAndSelect(neigh)
				break
			end
			lastFound = neigh
		end
	end
	self.emptyText = self.text == ''
	return true
end

--

local AddAutoEmptyBox -- method definition
local function CreateAutoEmptyBoxMethod()
	local Screen0 = WG.Chili.Screen0
	--
	if not Screen0.FocusControl then
		-- install FocusControl function for Screen0 if we're using old chili
		local wenv = getfenv()
		setfenv(1, WG.Chili)
		local MakeWeakLink, CompareLinks, UnlinkSafe = MakeWeakLink, CompareLinks, UnlinkSafe
		function Screen:FocusControl(control)
			--UnlinkSafe(self.activeControl)
			if not CompareLinks(control, self.focusedControl) then
					local focusedControl = UnlinkSafe(self.focusedControl)
					if focusedControl then
						focusedControl.state.focused = false
						focusedControl:FocusUpdate() --rename FocusLost()
					end
					self.focusedControl = nil
					if control then
						self.focusedControl = MakeWeakLink(control, self.focusedControl)
						self.focusedControl.state.focused = true
						if self.focusedControl.hidden then
							self.focusedControl:Show()
						end
						self.focusedControl:FocusUpdate() --rename FocusGain()
					end
			end
		end
		setfenv(1, wenv)
	end

	local function Click(self)
		if self.text ~= '' then
			local neighbours = self.parent.children
			local lastBox
			for i = #neighbours, 1, -1 do
				local neigh = neighbours[i]
				if neigh.classname == 'editbox' then
					lastBox = neigh
					break
				end
			end
			if lastBox == self then
				self.parent:AddAutoEmptyBox(false)
			end
		end
	end
	function AddAutoEmptyBox(parent, focus)
		local y = 1
		local neighbours = parent.children
		for i = #neighbours, 1, -1 do
			local neigh = neighbours[i]
			local bot = neigh.y + neigh.height
			if not y or bot > y then
				y = bot
			end
		end
		local autobox = WG.Chili.EditBox:New{
			OnClick = { Click },
			OnKeyPress = { Navigate },
			OnFocusUpdate = { FixFocus },
			width = '100%',
			y = y,
			text = '',
			height = 19,
			-- user made
			emptytext = true,
		}
		parent:AddChild(autobox)
		parent:Resize(nil, parent.height + autobox.height)
		parent:Invalidate()
		if focus then
			Screen0:FocusControl(autobox)
		end
		return autobox
	end
end

-- common buttons

local alignedButtons = {"save", "clip", "allBool", "inverse", "extra"}
local buttons = {
	close = {
		caption = 'x',
		y=4,
		height=20,
		right=4,
		width = 20,
		OnClick = { 
			function(self)
				self.parent:Dispose()
			end
		},
	},
	clip = {
		caption = 'Clip Code',
		OnClick = { 
			function(self)
				local result = WinContentToTable(self, {})
				Spring.SetClipboard(tablecode(result))
			end
		},
	},
	save = {
		caption = 'Save',
	},
	allBool = {
		caption = 'Switch All',
		OnClick = {
			function(self) 
				for i, v in ipairs(self.parent.children) do
					if v.classname == 'scrollpanel' then
						local panel = v.children[1]
						local toBool
						for i, child in ipairs(panel.children) do
							if toBool == nil then
								toBool = (child.text == 'false' or child.text:find('= false$')) and true or false
							end
							if toBool == false then
								if child.text == 'true' then
									child:SetText('false')
								elseif child.text:find('= true$') then
									child:SetText(child.text:gsub("= true", "= false"))
								end
							elseif toBool == true then
								if child.text == 'false' then
									child:SetText('true')
								elseif child.text:find('= false$') then
									child:SetText(child.text:gsub("= false", "= true"))
								end
							end
						end
						break
					end
				end
			end
		}
	},
	inverse = {
		caption = 'Inverse All',
		OnClick = {
			function(self) 
				for i, v in ipairs(self.parent.children) do
					if v.classname == 'scrollpanel' then
						local panel = v.children[1]
						local toBool
						for i, child in ipairs(panel.children) do
							if child.text == 'true' then
								child:SetText('false')
							elseif child.text:find('= true$') then
								child:SetText(child.text:gsub("= true", "= false"))
							elseif child.text == 'false' then
								child:SetText('true')
							elseif child.text:find('= false$') then
								child:SetText(child.text:gsub("= false", "= true"))
							end
						end
						break
					end
				end
			end
		}
	},
}

-- main

local function CreateWindowTableEditer(t, tname, Save, preTreatment, postTreatment, extraButton) -- ideally should be implemented in Chili
	if not AddAutoEmptyBox then
		CreateAutoEmptyBoxMethod()
	end

	local offsetY = 0
	local children = {}
	local stack_children = {}
	local win, panel, scrollpanel
	local Screen0 = WG.Chili.Screen0
	--
	-------------
	buttons.save.OnClick = {
		function(self)
			WinContentToTable(self, t)
			if postTreatment and type(postTreatment) == 'function' then
				postTreatment(t)
			end
			Save(t)
		end
	}

	table.insert(children, WG.Chili.Button:New(buttons.close))

	local font = WG.Chili.Font:New({})
	local right = 24
	buttons.extra = extraButton
	for i, name in ipairs(alignedButtons) do
		local button = buttons[name]
		if button then
			local title = button.caption
			if not title or title == '' then
				title = 'button'
				button.caption = title
			end
			local width = font:GetTextWidth(title)
			button.right = right
			button.y = 25
			button.width = width + 14
			local button = WG.Chili.Button:New(button)
			table.insert(children, button)

			right = right + width + 12
		end
	end
	font:Dispose()

	-- if the dev wanna transform the content of the table for it to be better understood for the user
	local copy
	if preTreatment and type(preTreatment) == 'function' then
		copy = {}
		for k,v in pairs(t) do copy[k] = v end
		preTreatment(copy)
	end
	-- set the content to be presentable in window
	local size = table.size(copy or t)
	local len = #(copy or t)
	local showKeys = size ~= len  or len > 8
	local sorted, i = {}, 0

	-- local sortFunc = function(a, b)
	-- 	return tonumber(a) and (
	-- 			not tonumber(b)
	-- 			or tonumber(a) < tonumber(b)
	-- 		)
	-- end
	for k, v in pairs(copy or t) do
		i = i + 1
		if type(k) == 'string' and not tonumber(k) then
			local keys = k:explode('&')
			if keys[2] and keys[2]:match('[^ ]') then
				k = ''
				for j, subk in ipairs(keys) do
					k = k .. subk
					if keys[j+1] then
						k = k .. ' & '
					end
				end
			end
			v = k .. ' = ' .. tostring(v)
		elseif showKeys then
			v = k .. ' = ' .. tostring(v)
		else
			v = tostring(v)
		end

		sorted[i] = v
	end
	table.sort(sorted, sortFunc)
	-- create the fields
	for i, v in ipairs(sorted) do
		local editBox = WG.Chili.EditBox:New{
			OnKeyPress = { Navigate },
			OnFocusUpdate = { FixFocus },
			width = '100%',
			text = v,
			caption = v,
			autosize = false,
			margin = {0,0,0,0},
			-- autoObeyLineHeight = false,
			y = offsetY,
			height = 19,
		}
		table.insert(stack_children, editBox)
		offsetY = offsetY + 19
	end

	local vsx, vsy = Spring.GetScreenGeometry()
	local fullHeight = table.size(t) * 19
	local height = math.min(fullHeight + 65, 500)
	win = WG.Chili.Window:New{
		generic_name = 'table_editer', 
		parent = Screen0,
		caption = 'Edit Property ' .. (tname or ''),
		x = math.max(150, vsx/2 - 200),
		y = math.max(100, (vsy - height) / 2),
		width = 400,
		height = height-100,
		minHeight = 200,
		padding = {0,0,0,0},
		children = children,
	}

	scrollpanel = WG.Chili.ScrollPanel:New{
		savespace = false,
		align = 'center',
		-- width = '100%',
		-- height = '90%',
		x=25,
		y=43,
		right = 25,
		bottom = 25,
		-- padding = {0,0,0,0},
		-- scrollbarSize = 12,
		itemPadding = {0,0,0,0},
		autoresize = false,
		resizeItems = true,
		horizontalScrollbar = false,
		verticalSmartScroll = true,
		padding = {0,0,0,0}, -- if right padding is 0 instead of 1 it create actually a padding
		children = {
		},
	}
	panel = WG.Chili.Control:New{ -- graphics are blurry/glitchy when putting the editboxes in StackPanel
		x=1,
		y=1,
		-- height = height - 55,
		height = fullHeight,
		right = 1,
		AddAutoEmptyBox = AddAutoEmptyBox,
		padding = {0,0,0,0},
		preserveChildrenOrder = true,
		children = stack_children,
		itemMargin = {0,0,0,0},
	}
	panel:AddAutoEmptyBox()
	scrollpanel:AddChild(panel)
	win:AddChild(scrollpanel)
	if WG.MakeMinizable then
		WG.MakeMinizable(win)
	end
	return win

end
if TESTME then
	local test = {}
	for i = 1, 80 do
		-- test[i] = string.char(i+64)
		if i <= 10 then
			test[i] = true
		else
			test[i .. 'a'] = true
		end
	end
	function widget:Initialize()
		if not WG.Chili then
			Echo(widget.GetInfo().name .. ' requires Chili.')
			widgetHandler:RemoveWidget(widget)
			return
		end

		Screen0 = WG.Chili.Screen0
		CreateAutoEmptyBoxMethod()
		-- if not WG.tabletest then
			WG.tabletest = test
		-- end
		test = WG.tabletest
		local extraButton = {
			caption = 'Inverse',
			OnClick = {
				function(self) 
					for i, v in ipairs(self.parent.children) do
						if v.classname == 'scrollpanel' then
							local panel = v.children[1]
							local toBool
							for i, child in ipairs(panel.children) do
								if toBool == nil then
									toBool = (child.text == 'false' or child.text:find('= false$')) and true or false
								end
								if toBool == false then
									if child.text == 'true' then
										child:SetText('false')
									elseif child.text:find('= true$') then
										child:SetText(child.text:gsub("= true", "= false"))
									end
								elseif toBool == true then
									if child.text == 'false' then
										child:SetText('true')
									elseif child.text:find('= false$') then
										child:SetText(child.text:gsub("= false", "= true"))
									end
								end
							end
						end
					end
				end
			}
		}
		CreateWindowTableEditer(test, 'test', function(t) Echo('save', t) end, preTreatment, postTreatment, extraButton)
	end
	return
end

return CreateWindowTableEditer

