function widget:GetInfo()
  return {
	name      = "Chili Widget Selector", --needs epic menu to dynamically update widget checkbox colors.
	desc      = "v1.013 Chili Widget Selector",
	author    = "CarRepairer",
	date      = "2012-01-11", --2013-06-11 (add crude filter/search capability)
	license   = "GNU GPL, v2 or later",
	layer     = -100000,
	handler   = true,
	enabled   = true,
	alwaysStart = true,
  }
end
local dev = true -- implement Ctrl + KP6 to reload the widget
local SUBCAT_LOCAL = false
------------------ Helwor addings
-- before Fev 2024 many things... TODO: fill it
--		-window minizable
-- 		-interactions with widgets through their labels:
-- 			hooking (right click and shift+right click) ,
--  		sleeping (shift + left click), with indicative darker color
-- Fev 2024 
--		-Added User Local Categories, improved categorization
--		-widget having .api in their knownInfos (which is reported from their GetInfo()) are categorized accordingly (thanks to widget OnWidgetState reporting it)
-- April 2024
--		-collapsable categories by clicking on labels
-- May 2024
--		-added dev option (showing or not widget that got .alwaysStart and .api)
--		-widget list rmb its setting and visibility over game
--		-added Mod Vanilla category
--		-added ctrl + click on widget to load it's Vanilla/mod version counterpart
--		-added colors indicating if it's modded vanilla or CAN BE modded vanilla
--		-improved colorization
--		-slight rewriting
--		-scrollback to where we were when window is remade
-- June 2024
--		-add space + click on widget item to open their option menu if they got options_path
--		-add a description extension telling the widget.status string (if any), can be used for example to explain why a widget got removed at initialization 
--		-fixed check behaviour depending on widget being really enabled or not
-- July 2024
--		-make up new category on the fly when finding a new one during scan
--		-make all category collapsable/openable by ctrl + click on one
-- April 2025
--		-improved colorization (discerning uniquely local widgets)
--		-improved helper tooltip and remove the use of \008 that is a dirty workaround of a bug when text is colorized back at line break and may fumble because relying on line breaks from tooltip window
--		 now instead colorizing in white for the rest of the text
--		-fixed checking miss
--		-fixed non-dev mode that was not hiding desired categories
--		-added possibility to search for multiple terms in parallel using separation " && ", in order to isolate multiple widgets that have different names (...)
--		-fixed space + click error on deactivated widget
------------------

local Echo = Spring.Echo


local spGetModKeyState = Spring.GetModKeyState

local initialized = false


function MakeWidgetList() end
function KillWidgetList() end
local window_widgetlist, scrollpanel

options_path = 'Settings/Misc'
options =
{
	widgetlist_2 = {
		name = 'Widget List',
		type = 'button',
		--hotkey = {key='f11', mod='A'}, -- In zk_keys.lua
		advanced = true,
		OnChange = function(self)
			if window_widgetlist then
				KillWidgetList()
			elseif not window_widgetlist then
				MakeWidgetList()
			end
		end
	}
}


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Config file data
--------------------------------------------------------------------------------

local file = LUAUI_DIRNAME .. "Configs/epicmenu_conf.lua"
local confdata = VFS.Include(file, nil, VFS.ZIP)
local color = confdata.color
confdata = nil

local visible = false
local dev_mode = false

local spGetMouseState = Spring.GetMouseState

-- Chili control classes
local Chili
local Button
local Label
local Colorbars
local Checkbox
local Window
local ScrollPanel
local StackPanel
local LayoutPanel
local Grid
local Trackbar
local TextBox
local Image
local Progressbar
local Colorbars
local Control
local Object
local screen0

--------------------------------------------------------------------------------
-- Global chili controls


local categorize = true
local filterUserInsertedTerm = "" --the term used to filter down the list of widget
local startMinized = true
--------------------------------------------------------------------------------
-- Misc
local B_HEIGHT = 26
local C_HEIGHT = 16

local scrH, scrW = 0,0

local window_w = 200
local window_h = 28
local window_x = 0
local window_y = 25


local returnSelf = function(self) return self end

--------------------------------------------------------------------------------
--For widget list
local widget_checks = {}
local widget_children = {}
local widgets_cats = {}
local wdatas = {}

local Mix = function(...)
	local n = select('#', ...)
	local ret = {}

	for i = 1, 4 do
		for c = 1, n do
			local col = select(c, ...)
			ret[i] = (ret[i] or 0) + col[i]
		end
		ret[i] = ret[i] / n
	end
	return ret
end
local yellow		= {1,1,0,1}
local red 			= {1,0.1,0.1,1}
local grey 			= {0.35,0.35,0.35,1}
local black			= {0,0,0,1}
local white			= {1,1,1,1}
local green			= {0,1,0,1}
local blue			= {0,0,1,1}
local lime 			= {0.6,1,0,1}
local blueteal		= {0.2,0.8,1,1}
local orange        = {1,0.5,0,1}

local teal			= Mix(green, blueteal)
local user_col		= lime
local game_col 		= green
local user_alt_col 		= blueteal -- has both user and game version and user version is loaded
local game_alt_col 		= teal -- has both user and game version and game version is loaded
local greyer, darker, crashed = {}, {}, {}

for i, col in ipairs({user_col, game_col, user_alt_col, game_alt_col}) do
	darker[col] = Mix(col, black)
	greyer[col] = Mix(Mix(col, grey, grey, grey, white, white))
	crashed[col] = Mix(col, orange, orange, orange, orange, orange)
end
-- adjust some crashed color
crashed[game_col] = orange
crashed[user_alt_col] = Mix(blueteal, red, red)
crashed[game_alt_col] = Mix(blueteal, orange, red)

local user_col		= Mix(blue, blueteal, blueteal)
local game_col 		= green
local user_alt_col 		= Mix(user_col, teal) -- has both user and game version and user version is loaded
local game_alt_col 		= Mix(game_col, blueteal) -- has both user and game version and game version is loaded
local greyer, darker, crashed = {}, {}, {}

for i, col in ipairs({user_col, game_col, user_alt_col, game_alt_col}) do
	darker[col] = Mix(col, black)
	greyer[col] = Mix(Mix(col, grey, grey, grey, white, white))
	crashed[col] = Mix(col, red, red)
end
-- adjust some crashed color
crashed[game_col] = orange
-- crashed[user_alt_col] = Mix(user_alt_col, red, red)
-- crashed[game_alt_col] = Mix(blueteal, orange, red)







local CatHandler = {} -- meow

CatHandler.titles = {
	-- when ungrouped
	user 			= "Local",
	mod_vanilla 	= "Vanilla Mod",
	game_widgets    = "Game Widgets",
	-- when grouped
	api     		= "API",
	addon			= 'Add On',
	always			= "Always Starting",
	camera  		= "Camera",
	cmd     		= "Commands",
	dbg     		= "Debug",
	gfx     		= "Effects",
	gui     		= "GUI",
	hook    		= "Commands",
	ico     		= "GUI",
	init    		= "Initialization",
	map				= "Map",
	minimap 		= "Minimap",
	mission			= "Mission",
	snd     		= "Sound",
	test    		= "Testing",
	unit    		= "Units",
	ungrouped    	= "Ungrouped",
}

do -- Initialize the categories ordering
	local order = {
		-- prefered group order when categorized

		-- dev_mode only
		'api',
		'addon',
		'init',
		'always',
		--------

		'unit',
		'gui',
		'cmd',

		'map',
		'minimap',
		'ico',

		'gfx',
		'camera',
		'snd',

		---
		'unknown', -- placeholder to tell where to put the newly found categories
		---

		'mission',

		-- dev_mode only
		'hook',
		'dbg',
		'test',
		--------

		'ungrouped',
	}
	CatHandler.order = {}
	local floor = -2000
	local off
	for i=1, #order do
		local cat = order[i]
		if off then
			order[i] = nil
			i = i + off
			order[i] = cat
		end
		local usercat = 'user' .. cat
		order[i + floor] = usercat -- user cat appears before cat
		if cat == 'unknown' then
			off = 1000 -- let some room for the newly found cat to place
		else
			CatHandler.titles[usercat] = CatHandler.titles.user .. ' ' .. CatHandler.titles[cat]
		end
	end
	-- for cat, title in pairs(CatHandler.titles) do
	-- 	CatHandler.titles[cat] = '- ' .. title .. ' -'
	-- end
	for o, cat in pairs(order) do
		CatHandler.order[cat] = o
	end
	-- main categories ('user' is both used as main user and categorized user ungrouped)
	CatHandler.order['user'] = floor -- always first, categorizing or not
	CatHandler.order['mod_vanilla'] = 1 -- only when not categorizing, appear after user
	CatHandler.order['game_widgets'] = 2 -- only when not categorizing, appear after mod_vanilla
	CatHandler.unknowns = {}
	function CatHandler:AddUnknown(cat, filename, categorize)
		local alreadyOne = self.unknowns[cat]
		if not alreadyOne then
			self.unknowns[cat] = filename
			return false
		elseif alreadyOne == filename then
			return false
		end
		-- we found the second wdata having the same unknown cat, creating the new cat
		local i = CatHandler.order.unknown
		local off = 1
		while order[i + off] do
			off = off + 1
		end
		order[i + off] = cat
		local usercat = 'user' .. cat
		CatHandler.order[cat] = i + off
		CatHandler.order[usercat] = CatHandler.order.userunknown + off

		self.titles[cat] = cat -- no idea how to make it look better
		self.titles[usercat] = self.titles['user'] .. ' ' .. self.titles[cat]

		------- change the previous wdata for that new cat
		local wdata = wdatas[alreadyOne]
		local incat = widgets_cats.ungrouped
		for i, dat in ipairs(incat) do
			if dat == wdata then
				table.remove(incat, i)
				break
			end
		end
		if not incat[1] then
			widgets_cats[wdata.cat] = nil
		end
		-- new
		new_cat = wdata.fromZip and cat or usercat
		widgets_cats[new_cat] = {wdata}
		
		wdata.cat = new_cat
		wdata.cat_title = self.titles[new_cat]
		-------

		-- tell this cat is recognized now
		CatHandler.unknowns[cat] = nil
		-- Echo('NEW CAT', cat, 'SND ORDER', CatHandler.order.snd, CatHandler.order.usersnd, 'UNKNOWN', CatHandler.order.unknown, CatHandler.order.userunknown , 'NEW CAT ORDER', CatHandler.order[cat], CatHandler.order[new_cat], 'MISSION', CatHandler.order.mission, CatHandler.order.usermission)

		return cat
	end
end




----------------------------------------------------------------

local function colstr(color)
	local char=string.char
	local round = function(n) -- that way of declaring function ('local f = function()' instead of 'local function f()' make the function ignore itself so I can call round function inside it which is math.round)
		n=math.round(n)
		return n==0 and 1 or n
	end
   return table.concat({char(255),char(round(color[1]*255)),char(round(color[2]*255)),char(round(color[3]*255))})
end
local function colorize(text, color)
	return colstr(color) .. text .. '\255\255\255\255'
end
local function sortInCat(t1, t2)
	return t1.name < t2.name
end
local function sortCats(t1,t2)
	local cat1, cat2 = t1[1], t2[1]
	local order1, order2 = CatHandler.order[cat1], CatHandler.order[cat2]
	if order1 and order2 then
		if order1 == order2 then
			return cat1 < cat2
		else
			return order1 < order2
		end
	elseif order1 then
		return true
	elseif order2 then
		return false
	else
		return cat1 < cat2
	end
end
local function CollapseCategory(self, all)

	local done
	if filterUserInsertedTerm~='' then
		return
	end
	if self.parent then
		local children = self.parent.children
		if children then
			local toHide
			local toTreat, t = {}, 0
			for i = all and 1 or self.order + 1, #widget_children do
				local child = widget_children[i]
				if child and child.classname == 'checkbox' then
					t = t + 1
					toTreat[t] = child
					if toHide == nil then
						toHide = not child.hidden
					end
				elseif not all then
					break
				end
			end
			if toTreat[1] then
				local start = toHide and t or 1
				local End = toHide and 1 or t
				local inc = toHide and -1 or 1
				for i = start, End, inc do -- this is needed for the order of children to be respected
					local child = toTreat[i]
					local ignore = all and toHide == child.hidden
					if ignore then
						t = t - 1
					else
						if toHide then
							child:Hide()
						else
							child:Show()
						end
					end
					-- Echo('set '..child.caption .. ' ' .. (toHide and 'hidden' or 'visible'))
				end
				self.parent:Resize(nil, self.parent.height + t * C_HEIGHT * (toHide and -1 or 1))
				done = true
			end
		end
	end
	return done
end


local zipOnly, rawOnly, zip = VFS.ZIP_ONLY, VFS.RAW_ONLY, VFS.ZIP
local FileExists = VFS.FileExists

local help_tooltip = table.concat({ -- chili bug: broke line by tooltip getting colorized, need to put \008 at those exact spots or order a white color after colorization of words

	'Color Status and Actions:',
	'-' .. colorize('Categories', yellow) .. ' collapsable with ' .. colorize('LClick + Ctrl', red) .. ' to collapse all)',
	'-' .. colorize('Uniquely local widget', user_col),
	'-' .. colorize('Local version loaded', user_alt_col),
	'-' .. colorize('Game version loaded', game_alt_col),
	'-' .. colorize('Uniquely game widget', game_col),
	'-' .. 'Use '.. colorize('Ctrl + LClick', red) .. ' to switch version',
	'-' .. colorize('Shift + LClick', red) .. ' put the widget to ' .. colorize('Sleep', darker[game_col]) .. ' and darker widget color',
	'-' .. colorize('Inactive', greyer[game_col])  .. ' widget with greyed colors',
	'-' .. colorize('Crashed', crashed[game_col]) .. ' widgets have redish colors',
	'-' .. colorize('Shift + RClick', red) .. ' hook the widget to survey it with HookFuncs',
	'-' .. colorize('Space + LClick', red) .. ' open the corresponding option panel',
	'-' .. colorize('RClick', red) .. ' (dev mode required) hook the  widget to survey it with HookFuncs2, much deeper and complete but unstable',
	'-' .. colorize('DEV MODE', red) .. ' Allow deep func survey enable interaction with sensible widgets (apis, always starting ...)',

}, '\n')




-- returns whether widget is enabled
local function WidgetEnabled(wname)
	local order = widgetHandler.orderList[wname]
	return order and (order > 0)
end
			


------ Checking and widget color update
local function CheckWidget(widget, reverse)
	local name
	if type(widget) == 'string' then
		name = widget
		widget = widgetHandler:FindWidget(name)
	else
		name = widget.whInfo.name
	end

	local wcheck = widget_checks[name]
	if wcheck then
		local ki = widgetHandler.knownWidgets[name]
		local confData = widgetHandler.configData[name]
		local useVanilla = not ki.fromZip and confData and confData.useVanilla
		local isModVanilla = not ki.fromZip and VFS.FileExists(ki.filename, VFS.ZIP_ONLY)
		local canBeMod = ki.fromZip and VFS.FileExists(ki.filename, VFS.RAW)
		local userUnique = not canBeMod and not ki.fromZip
		local isSleeping = widget and widget.isSleeping
		local enabled = WidgetEnabled(name)
		local isCrashed = not ki.active and enabled

		local base_color = (isModVanilla and not useVanilla and user_alt_col or canBeMod and game_alt_col or userUnique and user_col or game_col)
		local color = ki.active and (
				isSleeping and darker[base_color]
				or base_color
			) or isCrashed and crashed[base_color]
			or greyer[base_color]
		wcheck.tooltip = ''
		if widget then
			local extra = ''
			if widget.status and type(widget.status) == 'string' then
				extra = extra .. '\n[status]: ' .. widget.status
			end
			if isSleeping then
				extra = extra .. '\n[Sleeping]: Press Shift + LClick to wake it up.'
			end
			wcheck.tooltip = (widget.whInfo.desc or '') .. extra
		end
		if reverse then -- reverse it when it is from a click of the user (OnChange function) because the check is reversed again after that function call
			enabled = not enabled
		end
		if not reverse and not enabled then
			wcheck.tooltip = '[DISABLED]\n' .. wcheck.tooltip
		end
		if dev_mode then
			wcheck.tooltip = wcheck.tooltip .. "\n---------------\n<" .. ki.filename .. ">"
		end
		wcheck.font:SetColor(color)
		-- update the check
		wcheck.checked = enabled
		wcheck.value = enabled
		wcheck.state.checked = enabled
		wcheck:Invalidate()
	end
	-- Spring.SetClipboard(name)
end



local UpdateCheck = function(w, name, preloading) 
	if not preloading then
		CheckWidget(w)
	end
end
local VerifAndUpdateCheck = function(w, name, preloading)
	if not preloading then
		local wdata = wdatas[w.whInfo.filename]
		-- Echo("wdata, wdata and wdata.name is ", wdata, wdata and wdata.name,'name',name)
		if not wdata or wdata and wdata.name ~= name then
			if visible then
				requestRemake = true
				return
			end
		end
		CheckWidget(w)
	end

end
WidgetInitNotify = VerifAndUpdateCheck
WidgetRemoveNotify = UpdateCheck
-- WidgetInitNotify = function(w, name, pre) if name:find('Area Metal Reclaim') then Echo(name, 'notified Init') end return VerifAndUpdateCheck(w, name, pre) end
-- WidgetRemoveNotify = function(w, name, pre) if name:find('Area Metal Reclaim') then Echo(name, 'notified remove') end return UpdateCheck(w, name, pre) end
WidgetSleepNotify = UpdateCheck
WidgetWakeNotify = UpdateCheck

WG.cws_checkWidget = function() end --function is declared in widget:Initialize()

-------------------

local CatClick = function(self, mx,my, button) 
	if button == 1 then
		local ctrl = select(2, spGetModKeyState())
		return CollapseCategory(self, ctrl)
	end
end

local function WidgetClickMod(self, wdata)
	local _, _, lmb, _, rmb = spGetMouseState()
	local alt, ctrl, meta, shift = spGetModKeyState()

	if rmb then
		if dev_mode then
			-- self.checked = not self.checked -- cancel the checking that will occur after
			if widgetHandler:FindWidget(wdata.name) then
				if not shift then
					local HF2 = widgetHandler:FindWidget('HookFuncs2')
					if HF2 and HF2.HookWidget then
						HF2.HookWidget(wdata.name)
					end
				else
					if WG.HOOK then
						local inst = WG.HOOK:New(nil,nil,wdata.name)
						if inst then
							inst:Switch()
						end
					end
				end
			end
		end
		return true
	end
	if meta and lmb then
		-- self.checked = not self.checked
		local w = widgetHandler:FindWidget(wdata.name)
		if w then
			if w.options and w.options_path and WG.crude.OpenPath then
				WG.crude.OpenPath(w.options_path)
			end
		end
		return true
	end
	if shift and lmb then
		-- self.checked = not self.checked -- cancel the checking that will occur after
		if widgetHandler.Sleep then
			local w = widgetHandler:FindWidget(wdata.name)
			if w then
				if w.isSleeping then
					widgetHandler:Wake(w)
				else
					widgetHandler:Sleep(w)
				end
				CheckWidget(wdata.name)
			else
				Echo('The widget',wdata.name,'is not active, cannot sleep/wake it ')
			end
		end
		return true
	end	
	if ctrl and lmb and wdata.canBeMod then
		-------- method using the vanilla switcher, but it needs to be installed in each widget
		-- local w = widgetHandler:FindWidget(wdata.name)
		-- if w then
		-- 	local options = w.options
		-- 	if options then
		-- 		local switch_opt = options.switch_vanilla or options.switch_hel_k
		-- 		if switch_opt then
		-- 			switch_opt:OnChange()
		-- 			CheckWidget(wdata.name)
		-- 		end
		-- 	end
		-- end
		--------
		-- self.checked = not self.checked

		local oriLoadWidget = widgetHandler.LoadWidget
		local nameChanged, w = false, false
		local w
		widgetHandler.LoadWidget = function (self, filename, _VFSMODE)
			local ki = widgetHandler.knownWidgets[wdata.name]
			widgetHandler.knownWidgets[wdata.name] = nil -- force a refresh of knownInfo
			widgetHandler.knownCount = widgetHandler.knownCount - 1

			local wantedMode = not wdata.fromZip and  VFS.ZIP_ONLY or VFS.RAW_FIRST
			-- Echo('wdata.fromZip, wantedMode is ', wdata.fromZip, wantedMode)
			w = oriLoadWidget(self, filename, wantedMode)
			if not w then
				wdata.fromZip = not wdata.fromZip -- 
				Echo('Failed to load ' .. wdata.name .. ' version ' .. (wantedMode == VFS.ZIP_ONLY and 'ZIP' or 'RAW'))
				local fileExist = VFS.FileExists(filename, wantedMode)
				local text
				if fileExist then
					text = VFS.LoadFile(filename, wantedMode)
				end
				Echo('File exists ?', fileExist,'can be loaded?', not not text)
				widgetHandler.knownWidgets[wdata.name] = ki
				ki.active = false
				widgetHandler.knownCount = widgetHandler.knownCount + 1
			elseif w.whInfo.name ~= wdata.name then
				nameChanged = true
			end
			return w
		end

		Spring.SendCommands{'luaui disablewidget ' ..wdata.name}
		Spring.SendCommands{'luaui enablewidget ' ..wdata.name}

		widgetHandler.LoadWidget = oriLoadWidget
		if not w then
			-- if not self.checked then
			-- 	self.checked = true -- it will be set to its opposite at the end of option update
			-- end
			CheckWidget(wdata.name)
			return true
		-- elseif self.checked then -- 
		-- 	self.checked = false
		end

		if nameChanged then
			Echo('Name of widget changed, ' .. w.whInfo.name .. ', reloading window...')
			MakeWidgetList()
			return true
		end
		local ki = widgetHandler.knownWidgets[wdata.name]

		-- Echo('new VFS mode of widget, fromZip?', ki.fromZip)
		wdata.fromZip = ki.fromZip
		wdata.desc = ki.desc
		self.tooltip = ki.desc
			-- TODO: manage the change of name when VFS mode change
		CheckWidget(wdata.name)
		return true
	end
end
-- Adding functions because of "handler=true"
local function AddAction(cmd, func, data, types)
	return widgetHandler.actionHandler:AddAction(widget, cmd, func, data, types)
end
local function RemoveAction(cmd, types)
	return widgetHandler.actionHandler:RemoveAction(widget, cmd, types)
end

----------
--May not be needed with new chili functionality
local function AdjustWindow(window)

	local nx
	if window.x < 0 then
		nx = 0
	elseif (window.x + window.width > screen0.width) then
		nx = screen0.width - window.width
	end

	local ny
	if window.y < 0 then
		ny = 0
	elseif (window.y + window.height > screen0.height) then
		ny = screen0.height - window.height
	end

	if nx or ny then
		window:SetPos(nx or window.x,ny or window.y)
	end
end

----------
KillWidgetList = function()
	if window_widgetlist then
		-- window_h = window_widgetlist.backupH
		-- window_w = window_widgetlist.backupW
		if window_widgetlist.Dispose then
			window_widgetlist:Dispose()
		end
		window_widgetlist = nil
		filterUserInsertedTerm = ""
	end
	visible = false
end

-- Make widgetlist window


MakeWidgetList = function(minize, remake)

	widget_checks = {}
	widget_children = {}
	widgets_cats = {}

	local scrollPosY = 0
	if window_widgetlist then
		if scrollpanel and scrollpanel.scrollPosY then
			scrollPosY = scrollpanel.scrollPosY
			if scrollPosY ~= 0 then
				local contentHeight = scrollpanel.contentArea[4]
				local clientHeight = scrollpanel.clientArea[4]
				local maximum =  contentHeight - clientHeight
				scrollPosY = math.min(scrollPosY, maximum)

			end
		end
		window_widgetlist:Dispose()
	end

	local listIsEmpty = true
	
	local buttonWidth = window_w - 20
	CatHandler.unknowns = {}

	for name,data in pairs(widgetHandler.knownWidgets) do
		local cat, _
		if data.alwaysStart then
			cat = 'always'
		elseif data.api or data.filename:find('api_') then
			cat = 'api'
		else
			_, _, cat = string.find(data.basename, "([^_]+)_[^_]")
		end
		if dev_mode or (cat ~= 'always' and cat ~='api' and cat ~= 'init') then
			if cat then
				if filterUserInsertedTerm == "" and categorize and not CatHandler.order[cat] then
					if cat:len() <= 5 then
						cat = CatHandler:AddUnknown(cat, data.filename)
					end
				end
			end
			cat = cat or ''
			data.basename = data.basename or ''
			data.desc = data.desc or '' --become NIL if zipfile/archive corrupted

			local pass = false
			if filterUserInsertedTerm == "" then
				pass = true
			elseif filterUserInsertedTerm:find(" && ") then
				local terms = filterUserInsertedTerm:explode(" && ")
				for _, term in pairs(terms) do
					if name:lower():find(term)
						or data.desc:lower():find(term)
						or cat:lower():find(term)
					then
						pass = true
						break
					end
				end
			else
				pass = name:lower():find(filterUserInsertedTerm)
					or data.desc:lower():find(filterUserInsertedTerm)
					or cat:lower():find(filterUserInsertedTerm)
			end

			if pass	then
				local isUser = not data.fromZip
				local canBeMod = FileExists(data.filename, isUser and zipOnly or rawOnly)
				if categorize then
					-- if isUser then
					-- 	cat = 'user'..cat
					-- end
				else
					if canBeMod then
						cat = 'mod_vanilla'
					elseif isUser then
						cat = 'user'
					else
						cat = 'game_widgets'
					end
				end
				local cat_title = CatHandler.titles[cat]
				if not cat_title then -- if there's no such subcat  when categorizing
					cat = isUser and 'user' or 'ungrouped'
					cat_title = CatHandler.titles[cat]
				end

				local wdata = {
					cat			 = cat,
					catname      = cat_title,
					name         = name,
					active       = data.active,
					desc         = data.desc,
					filename 	 = data.filename,
					canBeMod 	 = canBeMod,
					fromZip		 = data.fromZip,
					alwaysStart  = data.alwaysStart,
				}
				wdatas[data.filename] = wdata
				local incat = widgets_cats[cat]
				if not incat then
					widgets_cats[cat] = {wdata}
				else
					incat[#incat+1] = wdata
				end
				listIsEmpty = false
			end
		end
	end
	local sorted_cats, i = {}, 0
	for cat, incat in pairs(widgets_cats) do
		i = i + 1
		sorted_cats[i] = {cat, incat}
	end
	-- Echo("widgetHandler.crashedWidgets is ", widgetHandler.crashedWidgets)
	-- if widgetHandler.crashedWidgets then
	-- 	for k,v in pairs(widgetHandler.crashedWidgets) do
	-- 		Echo(k,v)
	-- 	end
	-- end
	--Sort widget categories
	table.sort(sorted_cats, sortCats)
	local n = 0
	for _, data in ipairs(sorted_cats) do
		local cat_title = CatHandler.titles[data[1]]
		local incat = data[2]
		table.sort(incat, sortInCat) -- just sorting widget names alphabetically inside the cat
	
		--Sort widget names within this category
		n = n + 1
		widget_children[n] =
			Label:New{
				caption = '~ '..cat_title .. (dev_mode and ' ('..#incat..') ' or '') .. ' ~', textColor = color.sub_header, align='center',
				HitTest = returnSelf, -- enable OnMouseDown and the like for label
				OnMouseDown = {	CatClick },
				order = n,
			}

		for _, wdata in ipairs(incat) do
			local enabled = WidgetEnabled(wdata.name, wdata)
			
			--Add checkbox to table that is used to update checkbox label colors when widget becomes active/inactive
			n = n + 1
			widget_checks[wdata.name] = Checkbox:New{
					caption = wdata.name,
					checked = enabled,
					tooltip = tostring(wdata.desc),
					OnChange = {
						function(self,value)
							if WidgetClickMod(self,wdata) then
								-- return true
							else
								widgetHandler:ToggleWidget(wdata.name)
								local ki = widgetHandler.knownWidgets[wdata.name]
								if ki then
									wdata.active = ki.active
									-- if self.checked == WidgetEnabled(wdata.name, wdata) then
									-- 	self.checked = not self.checked -- self.checked will be set to its opposite at the end of option update
									-- end
								end
							end


							-- we're controlling the check through CheckWidget function, to make it stay the same, we have to reverse it when the checkbox is clicked (the checked prop is changed afterward)
							CheckWidget(wdata.name, true)
						end,
					},
					order = n,
				}
			wdata.order = n
			widget_children[n] = widget_checks[wdata.name]
			CheckWidget(wdata.name) --sets color of label for this widget checkbox
		end
	end
	if n == 0 then
		widget_children[1] =
			Label:New{ caption = "- no match for \"" .. filterUserInsertedTerm .."\" -", align='center', }
		widget_children[2] =
			Label:New{ caption = " ", align='center', }
	end
	
	local hotkey = WG.crude.GetHotkey("epic_chili_widget_selector_widgetlist_2")
	if hotkey and hotkey ~= "" then
		hotkey = " (" .. hotkey .. ")"
	else
		hotkey = ''
	end
	scrollpanel = ScrollPanel:New{
		x=5,
		y=15,
		right=5,
		bottom = C_HEIGHT*2,
		scrollPosY = scrollPosY,
		children = {
			StackPanel:New{
				name = 'widget_stack',
				x=1,
				y=1,
				height = #widget_children*C_HEIGHT,
				right = 1,
				
				itemPadding = {1,1,1,1},
				itemMargin = {0,0,0,0},
				preserveChildrenOrder = true,
				children = widget_children,
			},
		},
	}
		--
	window_widgetlist = {
		x = window_x,
		y = window_y,
		width  = window_w,
		height = window_h,
		classname = "main_window_small_tall",
		parent = screen0,
		backgroundColor = color.sub_bg,
		caption = 'Widget List' .. hotkey,
		name = 'widget_selector',
		-- dockable = true,
		-- dockableSavePositionOnly = true,
		minWidth = 250,
		minHeight = 400,
		-- height = 28,
		OnMouseDown = {
			function(self, ...)
				window_x = self.x
				window_y = self.y
				
				window_w = self.backupW or self.width
				window_h = self.backupH or self.height 
			end
		},
		OnMouseUp = {
			function(self, ...)
				window_x = self.x
				window_y = self.y
				
				window_w = self.backupW or self.width
				window_h = self.backupH or self.height 
			end
		},
		OnDispose = {
			function(self)
				window_x = self.x
				window_y = self.y
				
				window_w = self.backupW or self.width
				window_h = self.backupH or self.height 
			end
		},

		children = {
			Image:New{
				tooltip = help_tooltip,
				right = 5,
				width = 15, height = 15,
				file = 'LuaUI/images/epicmenu/questionmark.png',
				HitTest = function(self) return self end,
			},
			
			scrollpanel,

			
			--Search button
			Button:New{
				caption = 'Search',
				OnClick = { function() Spring.SendCommands("chat","PasteText /searchwidget:") end },
				--backgroundColor=color.sub_close_bg,
				--textColor=color.sub_close_fg,
				--classname = "navigation_button",
				
				x = '40%',
				bottom=4,
				width='28%',
				height=B_HEIGHT,
			},
			
			--Close button
			Button:New{
				caption = 'Close',
				OnClick = { KillWidgetList },
				--backgroundColor=color.sub_close_bg,
				--textColor=color.sub_close_fg,
				--classname = "navigation_button",
				
				x = '68%',
				bottom=4,
				width='28%',
				height=B_HEIGHT,
			},

		},
	}
			--Categorization checkbox
	if filterUserInsertedTerm == "" then
		table.insert(window_widgetlist.children, 2, Checkbox:New{
				caption = 'Dev',
				OnClick = { function()dev_mode = not dev_mode;  MakeWidgetList(nil,true) end },
				textColor=color.sub_fg,
				checked = dev_mode,
				
				x = 5,
				width = '36%',
				height= C_HEIGHT,
				bottom=16,
			})

		table.insert(window_widgetlist.children, 3, Checkbox:New{
			caption = 'Categorize',
			tooltip = 'List widgets by category',
			OnClick = { function() categorize = not categorize; MakeWidgetList(nil,true) end },
			textColor=color.sub_fg,
			checked = categorize,
			
			x = 5,
			width = '36%',
			height= C_HEIGHT,
			bottom=4,
		})
	else
		
		table.insert(window_widgetlist.children, 2, Button:New{
			caption = 'Back',
			OnClick = { function() filterUserInsertedTerm = ""; MakeWidgetList(nil,true) end },
			--backgroundColor=color.sub_close_bg,
			--textColor=color.sub_close_fg,
			--classname = "navigation_button",
			
			x = 3,
			bottom=4,
			width='39.3%',
			autosize = true,
			autoSize = true,
			height=B_HEIGHT,
		})
	end
	Window:New(window_widgetlist) -- 
	---- Note: if x/y is negative, once the window is made, window is getting moved to the other side minus the x/y
	if window_x ~= window_widgetlist.x and window_x < 0 or window_y ~= window_widgetlist.y and window_y < 0 then
		window_widgetlist:SetPos(window_x,window_y)
	end
	----
	if WG.MakeMinizable then
		WG.MakeMinizable(window_widgetlist, minize == 'minize')
	end
	visible = true
	if not remake then
		AdjustWindow(window_widgetlist)
	end
end


function widget:Initialize()
	if (not WG.Chili) then
		widgetHandler:RemoveWidget(widget)
		return
	end
	-- setup Chili
	Chili = WG.Chili
	Button = Chili.Button
	Label = Chili.Label
	Colorbars = Chili.Colorbars
	Checkbox = Chili.Checkbox
	Window = Chili.Window
	ScrollPanel = Chili.ScrollPanel
	StackPanel = Chili.StackPanel
	LayoutPanel = Chili.LayoutPanel
	Grid = Chili.Grid
	Trackbar = Chili.Trackbar
	TextBox = Chili.TextBox
	Image = Chili.Image
	Progressbar = Chili.Progressbar
	Colorbars = Chili.Colorbars
	Control = Chili.Control
	Object = Chili.Object
	screen0 = Chili.Screen0
	widget:ViewResize(Spring.GetViewGeometry())
	-- window_w = 200
	-- window_h = 28
	-- window_x = (scrW - window_w)/2
	-- window_y = (scrH - window_h)/2
	
	-- window_x = 0
	-- window_y = 80
	
	Spring.SendCommands({
		"unbindkeyset f11"
	})
	
	WG.cws_checkWidget = function(widget)
		CheckWidget(widget)
	end
end
function widget:Update()
	if not initialized then
		initialized = true
		if visible then -- fix widget checks (their order might be updated on initialization)
			MakeWidgetList('minize')
		end
	elseif requestRemake then
		requestRemake = false
		MakeWidgetList()
	end
end
function widget:ViewResize(vsx, vsy)
	scrW = vsx
	scrH = vsy
end


function widget:SetConfigData(data)
	if (data and type(data) == 'table') then
		if data.visible~=nil then
			visible = data.visible
		end
		if data.categorize ~= nil then
			categorize = data.categorize
		end
		if data.dev_mode ~= nil then
			dev_mode = data.dev_mode
		end
		if data.window_x then
			window_x = data.window_x
			window_y = data.window_y
			
			window_h = data.window_h
			window_w = data.window_w
		end
	end
end

function widget:GetConfigData()
	return {
		visible = visible,
		categorize = categorize,
		dev_mode = dev_mode,

		window_x = window_x,
		window_y = window_y,
		
		window_h = window_h,
		window_w = window_w,
	}
end


function widget:Shutdown()
	-- restore key binds
	KillWidgetList()
	Spring.SendCommands({
	"bind f11  luaui selector"
	})
end
function widget:KeyPress(key,mods)
	if dev and mods.ctrl and key==262 then -- Ctrl + KP6 to reload
		Spring.Echo('Reloading ' .. widget:GetInfo().name .. ' api')
		Spring.SendCommands('luaui disablewidget ' .. widget:GetInfo().name)
		Spring.SendCommands('luaui enablewidget ' .. widget:GetInfo().name)
	end
end
function widget:TextCommand(command)
	if window_widgetlist and command:sub(1,13) == "searchwidget:" then
		filterUserInsertedTerm = command:sub(14)
		filterUserInsertedTerm = filterUserInsertedTerm:lower() --Reference: http://lua-users.org/wiki/StringLibraryTutorial
		Spring.Echo("Widget Selector: filtering \"" .. filterUserInsertedTerm.."\"")
		MakeWidgetList()
		return true
	end
	return false
end
