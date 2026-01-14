-- can use chili_addon.lua


--[[ Helwor addings: 
Implementations:
	- add 'table' option type to edit a table in widget, table is kept unique, can be directly declared from widget and used at runtime after modifying it by option, 
		-- pre and post processing the table can be added function .preTReatment and function .postTreatment
		-- .noRemove key will prevent user from removing hardcoded keys of table during game time
		-- table can be opened/closed via action
	- add key option 'alwaysOnChange' to apply user's OnChange function even if value hasn't changed
	- add key option 'onChangeAtLoading' to apply OnChange function before widget Initialization 
		, (fixed now?) but EPIC MENU must be already present before the widget get loaded to catch it
	- add auto hiding option system for the user to hide sub option(s) he don't wanna show when the main option(s) is/are not enabled
		, => key option 'parents' and 'children' which would contain option.key of the respective targets
	- add a dev checkbox on main window, matching any option.dev for showing/hiding some experimental/debugging options
	- add options_path_alphabetical = {[path] = true} for a widget to tell that path should be sorted alphabetically, the path or a direct child of it must be created when widget is integrated
	- back button send back to the last search results list if user changed page or moved forward
	- add .desc tooltip key for options that got a label and lacked it (list, radioButton)
	- add .desc tooltip, .clickable property and .value (bool) for label option, triggering OnChange if clickable (can be used to make collapsable subcats with hidden switching)
	- render back button unusable when at root, reset button unusable when on search result
	- add .resetDefault if the dev want to modify the option.default to the new hard coded option.value
	- add .reset if the dev want to set the option value to its default
	- add .slim key option for slimer control (WIP)
	- add .category, to regroup options together even coming from different widgets, order is kept besides it
	- add .checkForChangeAtLoading for updating option.value and triggering OnChange if values differ from the saved config at loading stage
	- add a default option.name as option.key when option doesn't have one
	- add DRAFT WG.crude.LinkOptionToControl(option, control) for type number so far
	- add DRAFT .control for type number so far
	- add .path to every options
	- add .linkOption = {path, wname .. key} to link together two options values and trigger their respective OnChange function
	- add .extraButton table that will be made and added to the table editer, when launched
	- add WG.crude.OpenMultiPath to display options from multiple path. Usage WG.crude.OpenMultiPat({"path/dir1", "path/dir2", ...})
	- add WG.crude.OpenCustomList to display custom combination of option. Usage WG.crude.OpenCustomList({option1, option2, ...})
	- add WG.crude.OpenWidgetOptions collect the options belonging to a widget through and in order with widget.options_order, combine different paths if needed. Usage WG.crude.OpenWidgetOptions(widget)
	- Implement real history: parent Button, a back Button and a forward Button, smart detect to avoid duplicate at same history point
	- automatically add widget's description to a directory if that directory is the name of its widget
Convenience:
	- added a main menu caption when at root
	- menu window is minizable (clicking on title bar shrink the window to its title) requires chili_addon
	- maintain smart scroll position on visited path/when window need to be remade
	- don't show empty directory (if all options are hidden, or a widget removed, recursive check)
	- access widget options through .wOptions 
	- access widget name through .wname 
	- sort alphabetically vanilla directory that contains a lot of subdirectories
	- Color bars now update the color table on the fly
	- Color bars stop switching colors or unfocus themselves because the user didnt follow that fucking thin slide bar
	- controls are better sized and positionned
	- complete the springsetting handling using appropriate type, get default value if none found
Optimization:	
	- don't remake window when not needed
	- don't need to subtilize widgetHandler's function, if widget API On Widget State is present ('api_on_widget_state.lua')
	- removed one nested .OnChange being redundant
	- Fasten searching
	- Reuse same window component instead of remaking window each time
	- Start rewriting in OOP style
	- remove unused variables
	- optimized path breakdown
	- use unique metatable for all options
Fix:
	- radioButton old wrong value get fixed if user changed code
	- fixed path labeling for search result
	- various other bugfixes I can't rmb
	- fixed infinite loop with action of button (now in vanilla)
	- (not?) fix option.OnChange getting triggered at trackbar creation when having update_on_the_fly property
	- show results even if too many, just limit them to max number
	- fix virtualCategoryHit from search function
	- stop triggering OnChange when option is just displayed
	- smart scroll fixed
	- options and their directory are always updated when shown
]]

function widget:GetInfo()
	return {
		name      = "EPIC Menu",
		desc      = "v1.439 Extremely Powerful Ingame Chili Menu.", -- I would say even EPIC !
		author    = "CarRepairer, improved, rewrote and fixed Helwor",
		date      = "2009-06-02", --2014-05-3
		license   = "GNU GPL, v2 or later",
		layer     = -100001,
		handler   = true,
		enabled   = true,
		alwaysStart = true,
	}
end

local Echo = Spring.Echo
local dev = true
local debugMe = false
local sig = '['..widget:GetInfo().name .. ']: '
local CheckLUAFileAndBackup = VFS.Include("LuaUI/file_backups.lua", nil, VFS.GAME)

--CRUDE EXPLAINATION (third party comment) on how things work: (by Msafwan)
--1) first... a container called "OPTION" is shipped into epicMenuFactory from various sources (from widgets or epicmenu_conf.lua)
--Note: "OPTION" contain a smaller container called "OnChange" (which is the most important content).
--2) "OPTION" is then brought into epicMenuFactory\AddOption() which then attach a tracker which calls "SETTINGS" whenever "OnChange" is called.
--Note: "SETTINGS" is container which come and go from epicMenuFactory. Its destination is at CAWidgetFactory which save into "Zk_data.lua".
--4) "OPTION" are then brought into epicMenuFactory\MakeSubWindow() which then wrap the content(s) into regular buttons/checkboxes. This include the modified "OnChange"
--5) then Hotkey buttons is created in epicMenuFactory\MakeHotkeyedControl() and attached to regular buttons horizontally (thru 'StackPanel') which then sent back to  epicMenuFactory\MakeSubWindow()
--6) then epicMenuFactory\MakeSubWindow() attaches all created button(s) to main "Windows" and finished the job. (now waiting for ChiliFactory to render them all).
--Note: hotkey button press is handled by Spring, but its registration & attachment with "OnChange" is handled by epicMenuFactory
--Note: all button rendering & clicking is handled by ChiliFactory (which receive button settings & call "OnChange" if button is pressed)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local spGetConfigInt            = Spring.GetConfigInt
local spSendCommands            = Spring.SendCommands
local min = math.min
local max = math.max
local gameSpeed = Game.gameSpeed
local preintegrated = {}
local installed = {}
local optionsToLink = {}
local linkedOptions = {}
local optionTriggered = {}
local displayedOptions = {}
local currentPaths = {}
local MAX_HISTORY = 12
local history = {cur = 0}
local MENU = {}
--------------------------------------------------------------------------------
local isMission = Game.modDesc:find("Mission Mutator")
local isServerHost = Spring.GetModOptions().sendspringiedata and not Spring.IsReplay()

-- Config file data
local keybind_dir, keybind_file, defaultkeybinds, defaultkeybind_date, confdata
do
	--load config file:
	local file = LUAUI_DIRNAME .. "Configs/epicmenu_conf.lua"
	confdata = VFS.Include(file, nil, VFS.RAW_FIRST)
	--assign keybind file:
	keybind_dir = LUAUI_DIRNAME .. 'Configs/'
	keybind_file = 'zk_keys.lua'
	if isMission then
		--FIXME: find modname instead of using hardcoded mission_keybinds_file name
		keybind_file = (confdata.mission_keybinds_file and confdata.mission_keybinds_file) or keybind_file --example: singleplayer_keys.lua
	end
	--check for validity, backup or delete
	CheckLUAFileAndBackup(keybind_dir .. keybind_file)

	--load default keybinds:
	--FIXME: make it automatically use same name for mission, multiplayer, and default keybinding file
	local default_keybind_file = keybind_dir .. confdata.default_source_file
	local file_return = VFS.FileExists(default_keybind_file, VFS.ZIP) and VFS.Include(default_keybind_file, nil, VFS.ZIP) or {keybinds = {}, date = 0}
	defaultkeybinds = file_return.keybinds
	defaultkeybind_date = file_return.date
end

local epic_options = confdata.eopt
local color = confdata.color
local title_text = confdata.title
local title_image = confdata.title_image
local subMenuIcons = confdata.subMenuIcons
subMenuIcons['Hel-K'] = LUAUI_DIRNAME .. 'images/commands/reclaim.png'
subMenuIcons['Tweakings'] = LUAUI_DIRNAME .. 'images/advplayerslist/robots.png'
subMenuIcons['/Reload EPIC MENU'] = LUAUI_DIRNAME .. 'images/advplayerslist/robots.png'
local useUiKeys = false

--file_return = nil

local custom_cmd_actions = include("Configs/customCmdTypes.lua")

local allSettings = {}
for i, v in pairs (Spring.GetConfigParams()) do 
	if type(v) == 'table' then
		allSettings[v.name] = {
			type = v.type:find('string') and 'string' or v.type,
			default = v.defaultValue,
			min = v.minValue,
			max = v.maxValue,
			desc = v.description,
			safemode = v.safemodeValue,
			readOnly = v.readOnly
		}
	end
end

--------------------------------------------------------------------------------

-- Chili control classes
local Chili
local Control
local Button
local Label
local Colorbars
local Checkbox
local Window
local Panel
local ScrollPanel
local StackPanel
local LayoutPanel
local Grid
local Trackbar
local TextBox
local Image
local Progressbar
local Colorbars
local screen0

--------------------------------------------------------------------------------
-- Global chili controls
local ui = {
	window_crude = false,
	panel_crude = false,
	panel_background = false,
	window_exit = false,
	window_exit_confirm = false,
	window_flags = false,
	window_help = false,
	window_getkey = false,
	lbl_gtime = false,
	lbl_fps = false,
	lbl_clock = false,
	lbl_flag = false,
}

local userSearch = "" --the term used to search the button list
local mem = {
	last_scrollY = {}
}
--------------------------------------------------------------------------------
-- Misc
local MAIN_MENU_CAPTION = "INGAME MENU"

local B_HEIGHT = 26
local B_HEIGHT_MAIN = 26
local B_WIDTH_TOMAINMENU = 80
local C_HEIGHT = 16

local scrH, scrW = 0, 0
local cycle = 1

local currentPath = ''
local parentPath = false
local currentWidget = false

local eventObj = {
	standard = true,
	scrollY = 0,
	label = nil,
	search = nil,
	path = '',
	paths = nil,
	pathLabeling = nil,
	widget = nil,
	tree_start = nil,
}

local init = false
local scrollTo
local scrollToInit
local requestRefresh = false

local pathoptions = {}
local actionToOption = {}

local br = '\n'
local showTidal = false
if not confdata.description then confdata.description = '' end
local gameInfoText = ''
	..Game.modName ..br..br
	..'Spring Engine version: '..Spring.Utilities.GetEngineVersion()..br..br
	..'Map: ' ..Game.mapName ..br
	
	..'    Size: '..Game.mapX..' x '..Game.mapY..br
	..'    Gravity: '..math.round(Game.gravity)..br
	.. (showTidal and ('    Tidal Power: '..Game.tidal..br) or '')
	..'    Water Damage: '..Game.waterDamage..br
	..'    '.. Game.mapDescription..br
	..br..br
	..confdata.description

local function returnSelf(self) return self end
local function UserDetected(self)
	local hoveredControl = WG.Chili.Screen0.hoveredControl
	return hoveredControl and hoveredControl.name == self.name
end
local languages, flagByLang, langByFlag = VFS.Include("LuaUI/Headers/languages.lua")

--------------------------------------------------------------------------------
-- Key bindings
-- KEY BINDINGS AND YOU:
-- First, Epic Menu checks for a keybind bound to the action in LuaUI/Configs/zk_keys.lua.
--     If the local copy has a lower date value than the one in the mod,
--     it overwrites ALL conflicting keybinds in the local config.
--    Else it just adds any action-key pairs that are missing from the local config.
--    zk_keys.lua is written to at the end of loading LuaUI and on LuaUI shutdown.
-- Next, if it's a widget command, it checks if the widget specified a default keybind.
--    If so, it uses that command.
-- Lastly, it checks uikeys.txt (read-only).

include("keysym.lua")
local keysyms = {}
for k, v in pairs(KEYSYMS) do
	keysyms['' .. v] = k
end

local get_key, get_key_bind_mod, get_key_bind_without_mod = false, false, false
local get_key_bind_with_any, get_key_bind_notify_function = false
local kb_path, kb_button, kb_control, kb_option, kb_action

local transkey = include("Configs/transkey.lua")

local wantToReapplyBinding = false

local hackyOptionMemory = {}
local hackyOptionMemoryWhitelist = {
	['Master Volume'] = true,
	['Music Volume'] = true,
}

--------------------------------------------------------------------------------
-- Widget globals
WG.crude = {}
if not WG.Layout then
	WG.Layout = {}
end

--------------------------------------------------------------------------------
-- Luaui config settings
local keybounditems = {}
local keybind_date = 0

local EPIC_SETTINGS_VERSION = 51
local MUSIC_VOLUME_DEFAULT = 0.25

local min_subwindow_width = 280
local min_subwindow_height = 350
local settings = {
	versionmin = EPIC_SETTINGS_VERSION,
	widgets = {},
	show_crudemenu = true,
	music_volume = MUSIC_VOLUME_DEFAULT,
	showAdvanced = false, -- Enable to show all settings.
	simpleSettingsMode = true,
	dev = false,
	minized = false,
	config = {},
	subwindow_width = min_subwindow_width,
	subwindow_height = min_subwindow_height,
}

local confLoaded = false


----------------------------------------------------------------
-- Helper Functions
-- [[

local function to_string(data, indent)
	local str = ""

	if(indent == nil) then
		indent = 0
	end
	local indenter = "    "
	-- Check the type
	if(type(data) == "string") then
		str = str .. (indenter):rep(indent) .. data .. "\n"
	elseif(type(data) == "number") then
		str = str .. (indenter):rep(indent) .. data .. "\n"
	elseif(type(data) == "boolean") then
		if(data == true) then
			str = str .. "true"
		else
			str = str .. "false"
		end
	elseif(type(data) == "table") then
		local i, v
		for i, v in pairs(data) do
			-- Check for a table in a table
			if(type(v) == "table") then
				str = str .. (indenter):rep(indent) .. i .. ":\n"
				str = str .. to_string(v, indent + 2)
			else
				str = str .. (indenter):rep(indent) .. i .. ": " .. to_string(v, 0)
			end
		end
	elseif(type(data) == "function") then
		str = str .. (indenter):rep(indent) .. 'function' .. "\n"
	else
		Echo(1, "Error: unknown data type: %s", type(data))
	end

	return str
end
--]]

local function CapCase(str)
	local str = str:lower()
	str = str:gsub( '_', ' ' )
	str = str:sub(1, 1):upper() .. str:sub(2)
	
	str = str:gsub( ' (.)',
		function(x) return (' ' .. x):upper(); end
		)
	return str
end


local function explode(div, str)
	if (div == '') then
		return false
	end
	local pos, arr = 0, {}
	-- for each divider found
	for st, sp in function() return string.find(str, div, pos, true) end do
		table.insert(arr, string.sub(str, pos, st-1)) -- Attach chars left of current divider
		pos = sp + 1 -- Jump past current divider
	end
	table.insert(arr, string.sub(str, pos)) -- Attach chars right of last divider
	return arr
end


local function GetIndex(t, v)
	local idx = 1
	while (t[idx]<v)and(t[idx+1]) do
		idx = idx+1
	end
	return idx
end

local function CopyTable(tableToCopy, deep)
	local copy = {}
	for key, value in pairs(tableToCopy) do
		if (deep and type(value) == "table") then
			copy[key] = Spring.Utilities.CopyTable(value, true)
		else
			copy[key] = value
		end
	end
	return copy
end

local function sortDirAlphabetical(a,b)
	return a[2].name < b[2].name
end

local function radioButtonGotKey(opt, key)
	for i,v in ipairs(opt.items) do
		if v.key == key then
			return true
		end
	end
	return false
end
local Copy = function(t)
	local t2 = {}
	for k,v in pairs(t) do
		t2[k] = v
	end
	return t2
end

local function Identical(t, t2)
	if table.size(t) ~= table.size(t2) then
		return false
	end
	for k, v in pairs(t) do
		if t2[k] == nil then
			return false
		elseif type(v) ~= type(t2[k]) then
			return false
		elseif type(v) == 'table' then
			if not Identical(v, t2[k]) then
				return false
			end
		elseif v ~= false and v ~= t2[k] then
			return false
		end
	end
	for k in pairs(t2) do
		if t[k] == nil then
			return false
		end
	end
	return true
end

local function SearchInText(randomTexts, searchText) --this allow search term to be unordered (eg: "sel view" == "view sel")
	local explodedTerms = explode(' ', searchText)
	local found = true --this return true if all term match (eg: found("sel") && found("view"))
	for i = 1, #explodedTerms do
		local subSearchTerm = explodedTerms[i]
		local findings = randomTexts:find(subSearchTerm)
		if not findings then
			found = false
			break
		end
	end
	return found
end


--[[
local function tableMerge(t1, t2, appendIndex)
	for k, v in pairs(t2) do
		if type(v) == "table" then
			if type(t1[k] or false) == "table" then
				tableMerge(t1[k] or {}, t2[k] or {}, appendIndex)
			else
				if type(k) == 'number' and appendIndex then
					t1[#t1+1] = v
				else
					t1[k] = v
				end
			end
		else
			if type(k) == 'number' and appendIndex then
				t1[#t1+1] = v
			else
				t1[k] = v
			end
		end
	end
	return t1
end
--]]

local function tableremove(table1, item)
	local table2 = {}
	for i = 1, #table1 do
		local v = table1[i]
		if v ~= item then
			table2[#table2+1] = v
		end
	end
	return table2
end

local function ColStr(color)
	local char=string.char
	local round = function(n) -- that way of declaring function ('local f = function()' instead of 'local function f()' make the function ignore itself so I can call round function inside it which is math.round)
		n=math.round(n)
		return n==0 and 1 or n
	end
   return table.concat({char(255),char(round(color[1]*255)),char(round(color[2]*255)),char(round(color[3]*255))})
end
-- function GetTimeString() taken from trepan's clock widget
local function GetTimeString(secs)
	if (timeSecs ~= secs) then
		timeSecs = secs
		local h = math.floor(secs / 3600)
		local m = math.floor((secs % 3600) / 60)
		local s = math.floor(secs % 60)
		if (h > 0) then
			timeString = string.format('%02i:%02i:%02i', h, m, s)
		else
			timeString = string.format('%02i:%02i', m, s)
		end
	end
	return timeString
end

local SetColorButton
do
	local oriBGColor = {}
	local oriColor = {}
	function SetColorButton(button, mul)
		if not oriColor[button] then
			oriBGColor[button] = {unpack(button.backgroundColor)}
			oriColor[button] = {unpack(button.borderColor)}
		end
		local bgColor = button.backgroundColor
		local color = button.borderColor
		if mul == 1 then
			-- color[1], color[2], color[3], color[4] = unpack(oriColor[button])
			bgColor[1], bgColor[2], bgColor[3] = unpack(oriBGColor[button])
		else
			-- color[1], color[2], color[3] = 1,1,1,1
			bgColor[1], bgColor[2], bgColor[3] = bgColor[1]*mul, bgColor[2]*mul, bgColor[3]*mul
		end
		button:Invalidate()
	end
end

local function BoolToInt(bool)
	return bool and 1 or 0
end

local function IntToBool(int)
	return int ~= nil and int ~= 0
end

-- cool new framework for ordered table that has keys
local function otget(t, key)
	for i = 1, #t do
		if not t[i] then
			return
		end
		if t[i][1] == key then --key stored in index 1, while value at index 2
			return t[i][2]
		end
	end
	return nil
end

local function otset(t, key, val)
	for i = 1, #t do
		if t[i][1] == key then --key stored in index 1, while value at index 2
			if val == nil then
				table.remove( t, i )
			else
				t[i][2] = val
			end
			return
		end
	end
	if val ~= nil then
		t[#t+1] = {key, val}
	end
end
local function otvalidate(t)
	for i = 1, #t do
		if not t[i] then
			return false
		end
	end
	return true
end
local function SortCategories(dir) -- keep the whole order, but when meeting a category for the first time, put the others next
	local tinsert, tremove = table.insert, table.remove
	local i, len = 1, #dir
	local tries = 0
	while i < len do
		local cat = dir[i][2].category
		if cat then
			local j = i + 1
			while j <= len do
				if dir[j][2].category == cat then
					i  = i + 1
					if i ~= j then
						-- dir[i], dir[j] = dir[j], dir[i]
						tinsert(dir, i, tremove(dir,j))
					end
				end
				j = j + 1
			end
		end
		i  = i + 1
	end
end

local function CheckRemoveBranch(path, needRemake) --  if empty, remove parent directory (recursive), report if the sub window need to be refreshed
	if not path or path == '' then
		return needRemake
	end
	if pathoptions[path] and not pathoptions[path][1] then
		local parentDir, pathEnd
		if not path:match('/') then -- we're at the root
			parentDir, pathEnd = '', path
		else
			parentDir, pathEnd = path:match('(.*)/'), path:match('/([^/]+)$')
		end
		if parentDir then
			needRemake = needRemake or parentDir == currentPath
			if pathEnd and pathoptions[parentDir] then
				if path == currentPath then -- for convenience, don't remove yet the path where we're at, it will be removed at MENU:Navigate() stage
					return true
				end
				otset( pathoptions[parentDir], path..pathEnd, nil)
				pathoptions[path] = nil
				return CheckRemoveBranch(parentDir, needRemake)
			end
		end
	end
	return needRemake or path == currentPath or currentPaths[path]
end

local function DirIsEmpty(path, isDevMode, showAdvanced)
	local dir = pathoptions[path]
	if dir then
		for k,v in pairs(dir) do
			if type(v) == 'table' then
				local pathopt, opt = v[1], v[2]
				
				local hidden = opt.hidden 
					or opt.dev and not isDevMode
					or opt.advanced and not showAdvanced
					or opt.isDirectoryButton and DirIsEmpty(pathopt:gsub(opt.name .. '$','',1), isDevMode, showAdvanced)
				if not hidden then
					return false
				end
			end
		end
		return true	
	else
		Echo('path options found non-existant:',path)
	end
end

--end cool new framework

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local musicTrackbar, masterVolumeTrackbar

WG.crude.SetMasterVolume = function (newVolume, viaTrackbar)
	spSendCommands{"set snd_volmaster " .. newVolume}
	if viaTrackbar then
		if hackyOptionMemory['Master Volume'] then
			hackyOptionMemory['Master Volume'].value = newVolume
		end
	elseif masterVolumeTrackbar then
		masterVolumeTrackbar:SetValue(newVolume)
	end
end

WG.crude.SetMusicVolume = function (newVolume, viaTrackbar)
	if Spring.Utilities.IsNanOrInf(newVolume) then
		newVolume = 0
	end
	if ((WG.music_start_volume or 0) > 0) then
		Spring.SetSoundStreamVolume(newVolume / WG.music_start_volume)
	else
		Spring.SetSoundStreamVolume(newVolume)
	end
	if settings.config then
		settings.config["epic_Settings/Audio_Music_Volume"] = newVolume
	end
	WG.music_volume = newVolume
	if viaTrackbar then
		if hackyOptionMemory['Music Volume'] then
			hackyOptionMemory['Music Volume'].value = newVolume
		end
	elseif musicTrackbar then
		musicTrackbar:SetValue(newVolume)
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

WG.crude.SetSkin = function(Skin)
  if Chili then
	Chili.theme.skin.general.skinName = Skin
  end
end

--Reset custom widget settings, defined in Initialize
WG.crude.ResetSettings = function() end

--Reset hotkeys, defined in Initialized
WG.crude.ResetKeys         = function() end

--Get hotkey by actionname, defined in Initialize()
WG.crude.GetHotkey = function() end
WG.crude.GetHotkeys = function() end
WG.crude.GetHotkeyRaw = function() end

--Set hotkey by actionname, defined in Initialize(). Is defined in Initialize() because trying to iterate pathoptions table here (at least if running epicmenu.lua in local copy) will return empty pathoptions table.
WG.crude.SetHotkey =  function() end

--Callin often used for space+click shortcut, defined in Initialize(). Is defined in Initialize() because it help with testing epicmenu.lua in local copy
WG.crude.OpenPath = function() end
WG.crude.OpenMultiPath = function() end
WG.crude.OpenPathToLabel = function() end
WG.crude.OpenWidgetOptions = function() end
WG.crude.OpenCustomList = function() end
--Allow other widget to toggle-up/show Epic-Menu remotely, defined in Initialize()
WG.crude.ShowMenu = function() end --// allow other widget to toggle-up Epic-Menu which allow access to game settings' Menu via click on other GUI elements.

WG.crude.GetActionOption = function(actionName)
	return actionToOption[actionName]
end

local function SaveKeybinds()
	local keybindfile_table = {keybinds = keybounditems, date = keybind_date }
	--table.save( keybindfile_table, keybind_file )
	WG.SaveTable(keybindfile_table, keybind_dir, keybind_file, nil, {concise = true, prefixReturn = true, endOfFile = true})
end

local function LoadKeybinds()
	local loaded = false
	if VFS.FileExists(keybind_dir .. keybind_file, VFS.RAW) then
		local file_return = VFS.Include(keybind_dir .. keybind_file, nil, VFS.RAW)
		if file_return then
			keybounditems, keybind_date = file_return.keybinds, file_return.date
			if keybounditems and keybind_date then
				
				if not otvalidate(keybounditems) then
					keybounditems = {}
				end
				
				loaded = true
				keybind_date = keybind_date or defaultkeybind_date    -- reverse compat
				if not keybind_date or keybind_date == 0 or (keybind_date+0) < defaultkeybind_date then
					-- forcibly assign default keybind to actions it finds
					-- note that it won't do anything to keybinds if the action is not defined in default keybinds
					-- to overwrite such keys, assign the action's keybind to "None"
					keybind_date = defaultkeybind_date
					for _, elem in ipairs(defaultkeybinds) do
						local action = elem[1]
						local keybind = elem[2]
						otset( keybounditems, action, keybind)
					end
				else
					for _, elem in ipairs(defaultkeybinds) do
						local action = elem[1]
						local keybind = elem[2]
						otset( keybounditems, action, otget( keybounditems, action ) or keybind )
					end
				end
			end
		end
	end
	
	if not loaded then
		keybounditems = CopyTable(defaultkeybinds, true)
		keybind_date = defaultkeybind_date
	end
	
	if not otvalidate(keybounditems) then
		keybounditems = {}
	end
	
end

----------------------------------------------------------------
--May not be needed with new chili functionality
local function AdjustWindow(window)
	local nx
	if (0 > window.x) then
		nx = 0
	elseif (window.x + window.width > screen0.width) then
		nx = screen0.width - window.width
	end

	local ny
	if (0 > window.y) then
		ny = 0
	elseif (window.y + window.height > screen0.height) then
		ny = screen0.height - window.height
	end

	if (nx or ny) then
		window:SetPos(nx, ny)
	end
end


-- Adding functions because of "handler = true"
local function AddAction(cmd, func, data, types)
	return widgetHandler.actionHandler:AddAction(widget, cmd, func, data, types)
end
local function RemoveAction(cmd, types)
	return widgetHandler.actionHandler:RemoveAction(widget, cmd, types)
end

local sentBug = false
local function GetFullKey(path, option)
	if not option.key then
		if not sentBug then
			Echo(">>> Error, option missing key", path, option.wname)
			Spring.Utilities.TableEcho(option, "option")
			Echo("<<<")
			Echo(debug.traceback())
			sentBug = true
		end
		return "badKey"
	end
	--local curkey = path .. '_' .. option.key
	local fullkey = ('epic_'.. option.wname .. '_' .. option.key)
	fullkey = fullkey:gsub(' ', '_')
	return fullkey
end

local option_mt = {
	__index = function(option, key)
		if key == 'value' then
			return option.priv_value
		end
	end,
	__newindex = function(option, key, val)
		-- For some reason this is called twice per click with the same parameters for most options
		-- => the reason is because controlfunc aswell as origOnChange set option.value
		-- a few rare options have val = nil for their second call which resets the option.
		
		if key == 'value' then
			if val ~= nil then -- maybe this isn'option needed
			  --Echo ('set val', wname, k, key, val)
			  option.priv_value = val
			  
			  local fullkey = GetFullKey(option.path, option)
			  fullkey = fullkey:gsub(' ', '_')
			  settings.config[fullkey] = val
			end
		else
			rawset(option, key, val)
		end
	end
}

local function GetActionName(path, option)
	local fullkey = GetFullKey(path, option):lower()
	return option.action or fullkey
end

WG.crude.GetActionName = GetActionName

WG.crude.GetOptionHotkey = function(path, option)
	return WG.crude.GetHotkey(GetActionName(path, option))
end


-- returns whether widget is enabled
local function WidgetEnabled(wname)
	local order = widgetHandler.orderList[wname]
	return order and (order > 0)
end

-- by default it allows if player is not spectating and there are no other players
-- arg: true means trying to pause, false means trying to unpause
local function AllowPauseOnMenuChange(pause)
	if pause == nil then
		pause = true
	end
	
	if Spring.GetSpectatingState() then
		return false
	end
	
	if pause then
		if settings.config['epic_Settings/HUD_Panels/Pause_Screen_Menu_pauses_in_SP'] == false then
			return false
		end
	else
		if settings.config['epic_Settings/HUD_Panels/Pause_Screen_Menu_unpauses_in_SP'] == false then
			return false
		end
	end
	
	if Spring.Utilities.Gametype.IsSinglePlayer() == false then
		return false
	end
	
	return true
end
WG.crude.AllowPauseOnMenuChange = AllowPauseOnMenuChange


local function CanSaveGame()
	if Spring.IsCheatingEnabled() then
		return true
	end
	
	if isMission then
		return IntToBool(Spring.GetModOptions().cansavegame)
	end
	
	return Spring.Utilities.Gametype.IsSinglePlayer()
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Kill submenu window
function MENU:Kill(makingNew)
	if self.win then
		self.win:Dispose()
		self.win = nil
		currentPath = ''
		if makingNew then
			self:Navigate(eventObj)
		elseif AllowPauseOnMenuChange(false) then
			spSendCommands("pause 0")
		end
	end
end
WG.crude.KillSubWindow = function(makingNew) return MENU.Kill(makingNew) end

-- Update colors for labels of widget checkboxes in widgetlist window
local function checkWidget(widget)
	if WG.cws_checkWidget then
		WG.cws_checkWidget(widget)
	end
end

-- VFS.Include("LuaUI/Utilities/json.lua");

local function SetLang(self)
	Echo('Setting language: "' .. self.lang .. '" ')

	settings.lang = self.lang

	if WG.lang then
		WG.lang(self.lang)
	end

	if ui.lbl_flag then
		ui.lbl_flag.file = ":cn:".. LUAUI_DIRNAME .. "Images/flags/".. flagByLang[settings.lang] ..'.png'
		ui.lbl_flag:Invalidate()
	end
end

--Make language chooser window
local function MakeFlags()

	if ui.window_flags then return end

	local flagChildren = {}

	for i = 1, #languages do
		local langData = languages[i]
		flagChildren[#flagChildren + 1] = Image:New{
			file = ":cn:".. LUAUI_DIRNAME .. "Images/flags/".. langData.flag ..'.png',
			lang = langData.lang,
			OnClick = {SetLang }
		}
		flagChildren[#flagChildren + 1] = Button:New{
			caption = langData.name,
			objectOverrideFont = WG.GetFont(),
			name = 'countryButton' .. langData.lang;
			width = '100%',
			lang = langData.lang,
			OnClick = {SetLang }
		}
	end
	local window_height = 300
	local window_width = 170
	ui.window_flags = Window:New{
		caption = 'Choose Language',
		x = settings.sub_pos_x,
		y = settings.sub_pos_y,
		clientWidth  = window_width,
		clientHeight = window_height,
		classname = "main_window_small_tall",
		maxWidth = 200,
		parent = screen0,
		backgroundColor = color.sub_bg,
		children = {
			ScrollPanel:New{
				x = 5, y = 15,
				right = 5, bottom = 3+B_HEIGHT,
				
				children = {
					Grid:New{
						columns = 2,
						x = 0, y = 0,
						width = '100%',
						height = #flagChildren/2*B_HEIGHT*1,
						children = flagChildren,
					}
				}
			},
			--close button
			Button:New{caption = 'Close',  x = 5, y = 0-B_HEIGHT, bottom = 5, right = 5,
				name = 'makeFlagCloseButton';
				objectOverrideFont = WG.GetFont(),
				OnClick = {function(self) ui.window_flags:Dispose(); ui.window_flags = nil; end },
				width = window_width-20,
				--backgroundColor = color.sub_close_bg, textColor = color.sub_close_fg,
				--classname = "navigation_button",
			},
		}
	}
end

--Make help text window
local function MakeHelp(caption, text)
	local window_height = 400
	local window_width = 400
	
	ui.window_help = Window:New{
		caption = caption or 'Help?',
		x = settings.sub_pos_x,
		y = settings.sub_pos_y,
		clientWidth  = window_width,
		clientHeight = window_height,
		classname = "main_window_small",
		parent = screen0,
		backgroundColor = color.sub_bg,
		children = {
			ScrollPanel:New{
				x = 5, y = 15,
				right = 5,
				bottom = B_HEIGHT + 3,
				height = window_height - B_HEIGHT*3 ,
				children = {
					TextBox:New{x = 0, y = 10, text = text, objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}), width  = window_width - 40}
				}
			},
			--Close button
			Button:New{
				caption = 'Close', OnClick = {function(self) self.parent:Dispose() end },
				objectOverrideFont = WG.GetFont(),
				x = 45, bottom = 1, right = 45, height = B_HEIGHT,
				name = 'makeHelpCloseButton';
				--backgroundColor = color.sub_close_bg, textColor = color.sub_close_fg,
				--classname = "navigation_button",
			},
		}
	}
end

-- window table editer
local isbool = {
	['true'] = true,
	['false'] = false,
}
local tablecode = function(T)
	local follow = 1
	local equal = ' = '
	local parts, n = {}, 0
	for k,v in pairs(T)do
		if type(v) == 'string' then
			if v:find('\n') then
				v = '[['..v..']]'
			elseif isbool[v] == nil then
				v = "'"..v:gsub('([\'\"])','\\%1').."'"
			end
		else
			v = tostring(v)
		end
		if type(k)=='string' then
			if k:match('[^%w_]') then
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
		n = n + 1
		parts[n] = k..equal..v..", "
	end
	return '{\n\t' .. table.concat(parts,'\n\t') .. '\n}'
end

local CreateWindowTableEditer
if VFS.FileExists("LuaUI/Widgets/Include/win_table_editer.lua") then
	CreateWindowTableEditer = VFS.Include("LuaUI/Widgets/Include/win_table_editer.lua")
end


local function GetReadableHotkeyMod(mod)
	local modlowercase = mod:lower()
	return (modlowercase:find('a%+') and 'Alt+' or '') ..
		(modlowercase:find('c%+') and 'Ctrl+' or '') ..
		(modlowercase:find('m%+') and 'Meta+' or '') ..
		(modlowercase:find('s%+') and 'Shift+' or '') ..
		''
end

local function HotKeyBreakdown(hotkey) --convert hotkey string into a standardized hotkey string
	hotkey = hotkey:gsub('numpad%+', 'numpadplus')
	local hotkey_table = explode('+', hotkey)
	local alt, ctrl, meta, shift

	for i = 1, #hotkey_table-1 do
		local str2 = hotkey_table[i]:lower()
		if str2 == 'a' or str2 == 'alt'         then     alt = true
		elseif str2 == 'c' or str2 == 'ctrl'     then ctrl = true
		elseif str2 == 's' or str2 == 'shift'     then shift = true
		elseif str2 == 'm' or str2 == 'meta'     then meta = true
		end
	end
	
	local mod = '' ..
		(alt and 'A+' or '') ..
		(ctrl and 'C+' or '') ..
		(meta and 'M+' or '') ..
		(shift and 'S+' or '')
	
	local key = hotkey_table[#hotkey_table]
	key = key:gsub( 'numpadplus', 'numpad+')
	
	return mod, key
end
local function GetReadableHotkey(hotkey)
	local mod, key = HotKeyBreakdown(hotkey)
	return GetReadableHotkeyMod(mod) .. CapCase(key)
end

local function GetActionHotkeys(action)
	return Spring.GetActionHotKeys(action)
end

local function GetActionHotkey(action)
	local actionHotkeys = Spring.GetActionHotKeys(action)
	if actionHotkeys and actionHotkeys[1] then
		return (actionHotkeys[1])
	end
	return nil
end

local function AssignKeyBindAction(hotkey, actionName, verbose)
	if verbose then
		--local actions = Spring.GetKeyBindings(hotkey.mod .. hotkey.key)
		local actions = Spring.GetKeyBindings(hotkey)
		if (actions and #actions > 0) then
			Echo( 'Warning: There are other actions bound to this hotkey combo (' .. GetReadableHotkey(hotkey) .. '):' )
			for i = 1, #actions do
				for actionCmd, actionExtra in pairs(actions[i]) do
					Echo ('  - ' .. actionCmd .. ' ' .. actionExtra)
				end
			end
		end
		Echo( 'Hotkey (' .. GetReadableHotkey(hotkey) .. ') bound to action: ' .. actionName )
	end
	
	--actionName = actionName:lower()
	if type(hotkey) == 'string' then
		--otset( keybounditems, actionName, hotkey )
		
		--Echo("bind " .. hotkey .. " " .. actionName)
		spSendCommands("bind " .. hotkey .. " " .. actionName)
		
		local buildCommand = actionName:find('buildunit_')
		local isUnitCommand
		local isUnitStateCommand
		local isUnitInstantCommand
		
		if custom_cmd_actions[actionName] then
			local number = custom_cmd_actions[actionName].cmdType
			isUnitCommand = number == 1
			isUnitStateCommand = number == 2
			isUnitInstantCommand = number == 3
		end
			
		if custom_cmd_actions[actionName] or buildCommand then
			-- bind shift+hotkey as well if needed for unit commands
			local alreadyShift = hotkey:lower():find("s%+") or hotkey:lower():find("shift%+")
			if not alreadyShift then
				if isUnitCommand or buildCommand then
					spSendCommands("bind S+" .. hotkey .. " " .. actionName)
				elseif isUnitStateCommand or isUnitInstantCommand then
					spSendCommands("bind S+" .. hotkey .. " " .. actionName .. " queued")
				end
			end
		end
			
	end
end

--create spring action for this option. Note: this is used by AddOption()
local function CreateOptionAction(path, option)

	local kbfunc = function() return option.OnChange(nil, true) end
	
	if option.type == 'bool' then
		kbfunc = function()
			local wname = option.wname
			-- [[ Note: following code between -- [[ and  --]] is just to catch an exception. Is not part of code's logic.
			local dir = pathoptions[path]
			if not dir or not otget( dir, wname..option.key ) then
				Spring.Echo("Warning, detected keybind mishap. Please report this info and help us fix it:")
				Spring.Echo("Option path is "..path)
				Spring.Echo("Option name is "..wname..option.key)
				if not dir then --both option table & pathoptions[path] was missing, probably was never initialized
					Spring.Echo("case: whole path was never initialized")
					dir = {}
					pathoptions[path] = dir
					otset( dir, wname..option.key, option )
				else --pathoptions[path] table still intact, but option table missing
					Spring.Echo("case: option table was missing")
					otset( dir, wname..option.key, option )
				end
				-- [f = 0088425] Error: LuaUI::RunCallIn: error = 2, ConfigureLayout, [string "LuaUI/Widgets/gui_epicmenu.lua"]:583: attempt to index field '?' (a nil value)
			end
			--]]
			option.value = not option.value
			option.OnChange({checked = newval}, true)
			
			if MENU.win and MENU.win.visible then
				if displayedOptions[option] then
					MENU:Navigate(eventObj, false)
				end
			end
		end
	end
	local actionName = GetActionName(path, option)

	if (not option.dontRegisterAction) then
		AddAction(actionName, kbfunc, nil, "t")
	end
	actionToOption[actionName] = option
	
	if option.hotkey then
		local existingRegister = otget( keybounditems, actionName) --check whether existing actionname is already bound with a custom hotkey in zkkey
		if existingRegister == nil then
			Spring.Echo("Epicmenu: " .. option.hotkey .. " (" .. option.key .. ", " .. option.wname..")") --tell user (in infolog.txt) that a widget is adding hotkey
			otset(keybounditems, actionName, option.hotkey ) --save new hotkey if no existing key found (not yet applied. Will be applied in IntegrateWidget())
		end
	end
end

--remove spring action for this option
local function RemoveOptionAction(path, option)
	local actionName = GetActionName(path, option)
	RemoveAction(actionName)
end


-- Unassign a keybinding from settings and other tables that keep track of related info
local function UnassignKeyBind(actionName, verbose)
	local actionHotkeys = GetActionHotkeys(actionName)
	if actionHotkeys then
		for _, actionHotkey in ipairs(actionHotkeys) do
				
			--[[
				unbind and unbindaction don't work on a command+params, only on the command itself
			--]]
			
			local actionName_split = explode(' ', actionName)
			local actionName_cmd = actionName_split[1]
			
			--Echo("unbind " .. actionHotkey .. ' ' .. actionName_cmd:lower())
			spSendCommands("unbind " .. actionHotkey .. ' ' .. actionName_cmd:lower()) -- must be lowercase when calling unbind
			--spSendCommands("unbindaction " .. actionName ) --don't do this, unbinding one select would unbind all.
			
			if verbose then
				Echo( 'Unbound hotkeys from action: ' .. actionName )
			end
		end
	end
	--otset( keybounditems, actionName, nil )
end

--unassign and reassign keybinds
local function ReApplyKeybinds()
	--[[
	To migrate from uikeys:
	Find/Replace:
	bind\s*(\S*)\s*(.*)
	{"\2", "\1" },
	]]
	--Echo 'ReApplyKeybinds'
	
	if useUiKeys then
		return
	end
	
	for _, elem in ipairs(keybounditems) do
		local actionName = elem[1]
		local hotkey = elem[2]
		--actionName = actionName:lower()
		UnassignKeyBind(actionName, false)
		
		local hotkeyTable = type(hotkey) == 'table' and hotkey or {hotkey}
		
		for _, hotkey2 in ipairs(hotkeyTable) do
			if hotkey2 ~= 'None' then
				AssignKeyBindAction(hotkey2, actionName, false)
			end
		end
		
		--Echo("unbindaction(1) ", actionName)
		--Echo("bind(1) ", hotkey, actionName)
	end
end

local function UpdateI18n(option, checkRedundancy)
	if not option.i18nKey then
		return
	end

	local name = WG.Translate('epicmenu', option.i18nKey)
	if checkRedundancy and option.name and name then
		echo("Warning: overwriting name of option '" .. option.key .. "' from i18n" )
	end
	option.name = name or option.name

	-- Suppress logging for description as it is optional
	local desc = WG.Translate('epicmenu', option.i18nKey .. '_desc', nil, { suppressWarnings = true })
	if checkRedundancy and option.desc and desc then
		echo("Warning: overwriting desc of option '" .. option.key .. "' from i18n" )
	end
	option.desc = desc or option.desc
end
-- first run with an option, discover taht the path doesnt exist and rerun and create it, if parent path doesnt exist either, rerun again  and creates it and so on
local function AddOption(path, option, wname, options, alphabetical ) --Note: this is used when loading widgets and in Initialize()
	if not wname then
		wname = path
	end
	local needRemake = path == currentPath
	local dir = pathoptions[path]
	local path2 = path
	if not option then 
		if not dir then
			dir = {}
			pathoptions[path] = dir
		end
		if alphabetical then
			dir.alphabeticalSort = true
		end

		-- must be before path var is changed
		local icon = subMenuIcons[path] or currentWidget and currentWidget.path_option_icon and currentWidget.path_option_icon[path]
		local pathend
		path, pathend = path:match('(.-)/?([^/]-)$')
		needRemake = needRemake or path == currentPath or currentPaths[path]
		option = {
			type = 'button',
			name = pathend,
			icon = icon,
			OnChange = function(self)
				MENU:Navigate({standard = true, path = path2}, false)  --this made this button open another menu
			end,
			isDirectoryButton = dir,
			desc = currentWidget and pathend == currentWidget:GetInfo().name and currentWidget:GetInfo().desc or '',
			path = path,
		}
		dir = pathoptions[path]


		if currentWidget then
			if currentWidget.options_path_alphabetical and currentWidget.options_path_alphabetical[path] then
				dir.alphabeticalSort = true
			end
		end


		if path == '' and path2 == '' then --prevent adding '...' button on '' (Main Menu)
			return
		end
	else
		option.path = option.path or path
		needRemake = needRemake or currentPaths[option.path]
	end
	if not dir then
		needRemake = AddOption( path ) or needRemake
		dir = pathoptions[path]
	end
	option.wOptions = options
	if not dir.alphabeticalSort then
		if currentWidget and currentWidget.options_path_alphabetical and currentWidget.options_path_alphabetical[path]
		then
			dir.alphabeticalSort = true
		end
	end


	if not option.key then
		option.key = option.name
	end
	option.wname = wname
	
	local fullkey = GetFullKey(path, option)
	fullkey = fullkey:gsub(' ', '_')
	
	--get spring config setting
	local valuechanged = false
	local newval
	if option.reset and settings.config[fullkey] ~= nil then
		settings.config[fullkey] = nil
	end
	if option.springsetting ~= nil then --nil check as it can be false but maybe not if springconfig only assumes numbers
		local setting = allSettings[option.springsetting]
		local typeSet = setting.type
		if (option.type == 'bool' or option.type == 'number') and typeSet == 'string' then
			Echo('['..widget:GetInfo().name..']:' ..'Error Spring Setting mismatch option type requires number while setting ' .. tostring(option.springsetting) .. ' is a string.')
		else
			if typeSet == 'string' then
				newval = Spring.GetConfigString(option.springsetting, setting.defaultValue or "")
			elseif typeSet == 'int' or typeSet == 'bool' then
				newval = Spring.GetConfigInt( option.springsetting, setting.defaultValue or 0)	
			else
				newval = Spring.GetConfigFloat( option.springsetting, setting.defaultValue or 0)
			end
			if option.type == 'bool' and type(newval) then
				newval = IntToBool(newval)
			end
		end
	elseif not option.noSave then
		--load option from widget settings (LuaUI/Config/ZK_data.lua).
		--Read/write is handled by widgethandler; see widget:SetConfigData and widget:GetConfigData
		if settings.config[fullkey] ~= nil then --nil check as it can be false
			if option.type == 'radioButton' and not radioButtonGotKey(option, settings.config[fullkey]) then
				settings.config[fullkey] = nil
			elseif option.type == 'table' then
				local saved = settings.config[fullkey]
				if type(saved) == 'table' then
					if type(option.value) == 'table' then
						local changed = false
						local wtable = option.value
						for k,v in pairs(saved) do
							if wtable[k] ~= v then
								changed = true
								wtable[k] = v
							end
						end
						if not option.noRemove then
							for k,v in pairs(wtable) do
								if saved[k] == nil then
									changed = true
									wtable[k] = nil
								end
							end
						end
						if changed then
							newval = wtable
						end
					else
						newval = saved
					end
				end
			else
				newval = settings.config[fullkey]
			end
		end
	end
	if option.type == 'radioButton' then
		if option.default ~= nil and not radioButtonGotKey(option, option.default) then
			option.default = nil
		end
		if option.value ~= nil and not radioButtonGotKey(option, option.value) then
			option.value = nil
		end
	end

	if (option.default == nil or option.resetDefault) and option.type ~= 'button' and (option.type ~= 'label' or not option.clickable) then
		if option.value ~= nil then
			if option.type == 'table' then
				if type(option.value) == 'table' then
					local t = {}
					for k,v in pairs(option.value) do
						t[k] = v
					end
					option.default = t
				end
			else
				option.default = option.value
			end
		else
			option.default = newval
		end
	end
	
	if newval ~= nil and (option.value ~= newval or option.alwaysOnChange or option.type == 'table') then --must nilcheck newval
		valuechanged = true
		option.value = newval

	elseif option.value ~= nil and option.alwaysOnChange then
		valuechanged = true
		option.value = option.value -- trigger the metatable
	end

	local userOnChange = option.OnChange or function() end

	local function refreshRelatives(self) -- auto hide/show children options whenever all their parents value are non (true)/ any (true)
		local wOptions = self.wOptions
		if not wOptions then
			return
		end
		if self.children then
			for i, cname in ipairs(self.children) do
				local child = wOptions[cname]
				if child and child.parents then
					local hideChild = true

					for i, pname in ipairs(child.parents) do
						local parent = wOptions[pname]
						if parent and parent.value and not parent.hidden then
							hideChild = false
							break
						end
					end
					if hideChild ~= child.hidden then
						child.hidden = hideChild
						if child.children then
							refreshRelatives(child)
						end
						if displayedOptions[child] or displayedOptions[self] then
							requestRefresh = true
						end
						
					end
				end
			end
		end
	end
	local controlfunc = function() end
	if (option.type == 'button') and (option.action) and (not option.noAutoControlFunc) then
		-- this cause an infinite loop unless option.dontRegisterAction is true (the action call option.OnChange which call this func ...)
		-- option.action can be either used to provoke the call of an action by a click,
		-- or to provoke the OnChange when calling the action, but not both...
		if option.dontRegisterAction then
			controlfunc = function(self)
				spSendCommands{option.action} 
			end
		end
	elseif option.type == 'label' and option.clickable then
		controlfunc = function(self)
			if self ~= option then
				option.value = self.value
			end
			if displayedOptions[option] then
				requestRefresh = true
			end
		end

	elseif option.type == 'bool' then
		controlfunc = function(self)
			if self ~= option then
				option.value = self.checked
			end
			if option.springsetting then --if widget supplies option for springsettings
				Spring.SetConfigInt( option.springsetting, BoolToInt(option.value) )
			end
		end
		if displayedOptions[option] then
			requestRefresh = true
		end
	elseif option.type == 'number' then
		if option.valuelist then
			option.min     = 1
			option.max     = #(option.valuelist)
			option.step    = 1
		end
		--option.desc_orig = option.desc or ''
		controlfunc = function(self)
			if self ~= option then
				if option.valuelist then
					option.value = option.valuelist[self.value]
				else
					option.value = self.value
				end
				--self.tooltip = option.desc_orig .. ' - Current: ' .. option.value
			end
			if option.linkToControls then
				for k, control in pairs(option.linkToControls) do
					WG.Chili.Trackbar.SetValue(control, option.value)
				end
			end
			
			if option.springsetting then
				if not option.value then
					Echo ('<EPIC Menu> Error #444', fullkey)
				else
					local setting = allSettings[option.springsetting]
					local typeSet = setting.type
					if typeSet == 'int' then
						Spring.SetConfigInt(option.springsetting, option.value)	
					elseif typeSet == 'float' then
						Spring.SetConfigFloat( option.springsetting, option.value )
					end
				end
			end
		end
	
	elseif option.type == 'colors' then
		controlfunc = function(self)
			if self ~= option then
				option.value = self.color
			end
		end
		if option.colorizeName and option.origName then
			option.name = ColStr(option.value) .. option.origName
		end
	elseif option.type == 'list' then
		controlfunc = function(item)
			if item ~= option then
				option.value = item.value
			end
			if option.springsetting then
				local typeSet = allSettings[option.springsetting].type
				if typeSet == 'string' then
					Spring.SetConfigString(option.value)
				else
					local number = tonumber(option.value)
					if number then
						if typeSet == 'float' then
							Spring.SetConfigFloat(option.springsetting, option.value)
						else
							Spring.SetConfigInt(option.springsetting, option.value)
						end
					else
						Echo(sig ..  'Error, ' .. option.springsetting .. 'is of type ' .. typeSet .. ' while option trying to set : ' .. tostring(option.value))
					end
				end
			end

			if displayedOptions[option] then
				requestRefresh = true
			end
		end
	elseif option.type == 'radioButton' then
		controlfunc = function(item)
			option.value = item.value
			if displayedOptions[option] then --we need to refresh the window to show changes, and current path is irrelevant if we are doing search
				requestRefresh = true
			end
			if option.springsetting then
				local setting = allSettings[option.springsetting]
				local typeSet = setting.type
				if typeSet == 'string' then
					Spring.SetConfigString(option.value)
				else
					local number = tonumber(option.value)
					if number then
						if typeSet == 'float' then
							Spring.SetConfigFloat(option.springsetting, option.value)
						else
							Spring.SetConfigInt(option.springsetting, option.value)
						end
					else
						Echo(sig ..  'Error, ' .. option.springsetting .. 'is of type ' .. typeSet .. ' while option trying to set : ' .. tostring(option.value))
					end
				end
			end
		end
	elseif option.type == 'table' then
		local setPropWindow
		local saveValue = function(value)
			option.value = value
			userOnChange(option)
		end
		controlfunc = function(self, fromAction)
			if self and self.classname == 'button' or fromAction then
				-- dont trigger if OnChange has been called by other mean through epic menu
				if setPropWindow and not setPropWindow.disposed then
					setPropWindow:Dispose()
					setPropWindow = nil
				else
					if CreateWindowTableEditer then
						setPropWindow = CreateWindowTableEditer(option.value, 'table editer', saveValue, option.preTreatment, option.postTreatment, option.extraButton)
					end
				end
			elseif setPropWindow and self == option then
				-- else if window is up, refresh it
				setPropWindow:Dispose()
				userOnChange(option)
				setPropWindow = CreateWindowTableEditer(option.value, 'table editer', saveValue, option.preTreatment, option.postTreatment)
			end

		end
	end

	option.OnChange = function(obj, fromAction)
		controlfunc(obj, fromAction) --note: 'obj' (NOT ALWAYS AT ALL self, hence the redundancy with userOnChange) can refer to the button/checkbox/slider control or to an arbitrary table
		if option.type ~= 'table' then
			userOnChange(option)
		end
		if option.children then
			refreshRelatives(option)
		end
		if option.links and not optionTriggered[option] then
			-- Echo('['..option.path..']'.."=> LOCK", option.path, option.key)
			optionTriggered[option] = true
			for opt in pairs(option.links) do
				if not optionTriggered[opt] then
					-- Echo('['..option.path..']'.."GOTO=>", opt.path, opt.key)
					-- Echo('SetWidgetOption =>', opt.wname)
					WG.SetWidgetOption(opt.wname, opt.path, opt.key, option.color or option.value )
				else
					-- Echo('['..option.path..']'..'***', opt.path, opt.key, 'blocked')
				end
			end

			optionTriggered[option] = nil
			-- Echo('['..option.path..']'.."unlock", option.path, option.key)
			-- Echo('---------------')
		end
		-- Echo('EXIT ' .. option.path)
	end
	----- link option-option system
	if option.linkOption then
		local path, name = unpack(option.linkOption)
		local linked 
		if pathoptions[path] then
			linked = otget(pathoptions[path], name)
		end
		if linked then
			-- option is up, we can link it right now
			Echo('OPTION IS ALREADY UP', path, '=>', linked.path)
			linked.links = linked.links or {}
			linked.links[option] = true
			option.links = option.links or {}
			option.links[linked] = true
		else
			-- we wait for the target option to get loaded sometime later
			optionsToLink[path .. name] = option
		end
	end
	-- case an option to be linked wasn't loaded yet and now it is
	local linked = optionsToLink[path..wname..option.key]
	if linked then
		Echo('OPTION IS NOW UP', path, '=>', linked.path)
		linked.links = linked.links or {}
		linked.links[option] = true
		option.links = option.links or {}
		option.links[linked] = true

		optionsToLink[path..wname..option.key] = nil
	end
	-----
	--call onchange once
	if valuechanged and (option.type ~= 'button')
		--and not option.springsetting --need a different solution
		then
		option:OnChange()
	elseif option.children then
		refreshRelatives(option)
	end
	
	--Keybindings
	if (option.type == 'button' and not option.isDirectoryButton) or option.type == 'bool' or option.type == 'table' then
		-- local actionName = GetActionName(path, option)
		
		--migrate from old logic, make sure this is done before setting orig_key
		if option.hotkey and type(option.hotkey) == 'table' then
			option.hotkey = option.hotkey.mod .. option.hotkey.key --change hotkey table into string
		end
		
		if option.hotkey then
		  local orig_hotkey = ''
		  orig_hotkey = option.hotkey
		  option.orig_hotkey = orig_hotkey
		end
		
		CreateOptionAction(path, option)
	--Keybinds for radiobuttons
	elseif option.type == 'radioButton' then --if its a list of checkboxes:
		for i = 1, #option.items do --prepare keybinds for each of radioButton's checkbox
			local item = option.items[i] --note: referring by memory
			item.wname = wname.."radioButton" -- unique wname for Hotkey
			item.value = option.items[i].key --value of this item is this item's key
			item.OnChange = function() option.OnChange(item) end --OnChange() is an 'option.OnChange()' that feed on an input of 'item'(instead of 'self'). So that it always execute the 'value' of 'item' regardless of current 'value' of 'option'
			local actionName = GetActionName(path, item)
			if item.hotkey then
			  local orig_hotkey = ''
			  orig_hotkey = item.hotkey
			  item.orig_hotkey = orig_hotkey
			end
			
			CreateOptionAction(path, item)
		end
	end

	otset( pathoptions[path], wname..option.key, option )--is used for remake epicMenu's button(s)

	-- hax
	if hackyOptionMemoryWhitelist[option.name] then
		hackyOptionMemory[option.name] = option
	end

	return needRemake
end

local function RemOption(path, option, wname )
	-- Echo('rem option',wname, option.key)
	if not pathoptions[path] then
		--this occurs when a widget unloads itself inside :init
		--Echo ('<epic menu> error #333 ', wname, path)
		--Echo ('<epic menu> ...error #333 ', (option and option.key) )
		return
	end

	if option.links then
		-- Echo('Removing links of', option.path .. option.key)
		for opt in pairs(option.links) do
			-- Echo('...' .. opt.path .. opt.key)
			option.links[opt] = nil
			for lopt in pairs(opt.links) do
				if lopt == option then
					-- Echo('removed own link from this linked option')
					opt.links[lopt] = nil
					if opt.linkOption then
						-- remind to relink it when shutting down option is getting loaded again
						optionsToLink[option.path..option.wname..option.key] = opt
					end
					if not next(opt.links) then
						opt.links = nil
					end
					break
				end
			end
		end
		option.links = nil
	end
	RemoveOptionAction(path, option)
	otset( pathoptions[path], wname..option.key, nil )
end


-- sets key and wname for each option so that GetOptionHotkey can work before widget initialization completes
local function PreIntegrateWidget(w, alreadyLoaded)
	currentWidget = w
	local options = w.options
	if type(options) ~= 'table' then
		return false
	end
	if preintegrated[w] then
		return
	end
	preintegrated[w] = true

	local wname = w.whInfo.name
	local defaultpath = w.options_path or ('Settings/Misc/' .. wname)
	
	if w.options.order then
		Echo ("<EPIC Menu> " .. wname ..  ", don't index an option with the word 'order' please, it's too soon and I'm not ready.")
		w.options.order = nil
	end
	--Generate order table if it doesn't exist
	if not w.options_order then
		w.options_order = {}
		for k, v in pairs(options) do
			w.options_order[#(w.options_order) + 1] = k
		end
		table.sort(w.options_order)
	end

	-- verify invalid spring setting
	local i = 1
	local option = w.options[w.options_order[i]]
	while option do
		if option.springsetting and not allSettings[option.springsetting] then
			Echo(sig .. 'Error ' .. option.springsetting .. ' is not a Spring option.')
			table.remove(w.options_order, i)
		else
			i = i + 1
		end
		option = w.options[w.options_order[i]]
	end
	--
	for i = 1, #w.options_order do
		local k = w.options_order[i]
		local option = options[k]
		if not option then
			Spring.Log(widget:GetInfo().name, LOG.ERROR,  '<EPIC Menu> Error in loading custom widget settings in ' .. wname .. ', option',k,"doesn't exist." )
			return
		end

		option.key = k
		option.name = option.name or option.key
		option.wname = wname
		if not alreadyLoaded then
			if option.checkForChangeAtLoading then
				local fullkey = 'epic_'.. wname .. '_' .. k
				fullkey = fullkey:gsub(' ','_')
				local saved = settings.config[fullkey]
				if saved ~= nil and saved ~= option.value then
					option.value = saved
					if option.OnChange then
						option:OnChange()
					end
				end
			elseif option.onChangeAtLoading and option.OnChange then
				option:OnChange()
			end
		end
	end
end


--(Un)Store custom widget settings for a widget
local function IntegrateWidget(w, addoptions, index)
	currentWidget = w
	local options = w.options
	local options_order = w.options_order
	if type(options) ~= 'table' then
		return
	end
	if not preintegrated[w] then
		PreIntegrateWidget(w, true)
	end
	if not addoptions then
		installed[w] = nil
		preintegrated[w] = nil
	else
		installed[w] = true
	end
	local wname = w.whInfo.name
	
	local defaultpath =  w.options_path or ('Settings/Misc/' .. wname)
	local needRemake
	if MENU.win and MENU.win.visible then
		if eventObj.standard then
			needRemake = eventObj.path == defaultpath
		end
	end


	-- Echo(defaultpath,"defaultpath:match('.*/+') is ", defaultpath:match('(.*)/'), currentPath)
	--[[
	--If a widget disables itself in widget:Initialize it will run the removewidget before the insertwidget is complete. this fix doesn't work
	if not WidgetEnabled(wname) then
		return
	end
	--]]
	
	if options.order then
		Echo ("<EPIC Menu> " .. wname ..  ", don't index an option with the word 'order' please, it's too soon and I'm not ready.")
		options.order = nil
	end

	--Generate order table if it doesn't exist

	if not options_order then
		options_order = {}
		w.options_order = options_order
		table.sort(options_order)
	end
	
	
	for i = 1, #options_order do
		local k = options_order[i]
		local option = options[k]
		if not option then
			Spring.Log(widget:GetInfo().name, LOG.ERROR,  '<EPIC Menu> Error in loading custom widget settings in ' .. wname .. ', option', k, "doesn't exist." )
			Echo(debug.traceback())
			return
		end
		local path = option.path or defaultpath
		if addoptions then
			--Add empty onchange function if doesn't exist
			if not option.OnChange or type(option.OnChange) ~= 'function' then
				option.OnChange = function(self) end
			end
			
			--store default
			if option.type == 'table' then
				if type(option.value) == 'table' then
					local t = {}
					for k,v in pairs(option.value) do
						t[k] = v
					end
					option.default = t
				end
			elseif option.springsetting and not option.value then
				local setting = allSettings[option.springsetting]
				option.default = setting.default or 0
				if option.type == 'bool' then
					option.default = IntToBool(option.default)
				end
			else
				option.default = option.value
			end

			
			local origOnChange = option.OnChange 
			-- VERIFY IF WORKING
			-- if option.type ~= 'button' then
			-- 	option.OnChange =
			-- 		function(self)
			-- 			if self then
			-- 				option.value = self.value
			-- 			end
			-- 			origOnChange(self)
			-- 		end
			-- else
			-- 	option.OnChange = origOnChange
			-- end
			
			if option.type == 'colors' then
				option.origName = option.origName or option.name
			end

			option.priv_value = option.value
			option.value = nil
			setmetatable( option, option_mt )
			needRemake = AddOption(path, option, wname, options ) or needRemake
		else
			RemOption(path, option, wname )
			if path ~= defaultpath then
				needRemake = CheckRemoveBranch(path, needRemake)
			end
		end
		if not needRemake and currentPaths[path] then
			needRemake = true
		end
	end
	if not addoptions then
		needRemake = CheckRemoveBranch(defaultpath, needRemake)
	end
	if MENU.win and needRemake then 
		requestRefresh = true
		-- not needed anymore, for convenience we stay on the empty path, in the case the user is just reloading widget
		-- if currentPath and currentPath == defaultpath then
		-- 	if not pathoptions[defaultpath] then
		-- 		local parentDir = defaultpath:match('(.*)/')
		-- 		if parentDir then
		-- 			requestRefresh = false
		-- 			currentPath = parentDir
		-- 			WG.RemakeEpicMenu()
		-- 		end
		-- 	end
		-- end
	end
	
	wantToReapplyBinding = true --request ReApplyKeybind() in widget:Update(). IntegrateWidget() will be called many time during LUA loading but ReApplyKeybind() will be done only once in widget:Update()
	currentWidget = false
end

--Store custom widget settings for all active widgets
local function AddAllCustSettings()
	for i, w in ipairs(widgetHandler.widgets) do
		PreIntegrateWidget(w, true)
		IntegrateWidget(w, true)
	end
end

local function RemakeEpicMenu()
end


-- Spring's widget list
local function ShowWidgetList(self)
	spSendCommands{"luaui selector"}
end

-- Crudemenu's widget list
WG.crude.ShowWidgetList2 = function(self)
	MakeWidgetList()
end

WG.crude.ShowFlags = function()
	MakeFlags()
end
WG.crude.LinkOptionToControl = function(option, control)
	option.linkToControls = option.linkToControls or {}
	option.linkToControls[#option.linkToControls + 1] = control
	if option.type == 'number' then
		control.__SetValue = control.SetValue
		control.SetValue = function(self, value)
			if option.control and option.control:IsVisibleOnScreen() then 
				option.control:SetValue(value)
			else
				option.value = value
				option:OnChange()
			end
		end
	end
end
WG.crude.UnlinkOptionToControl = function(option, control)
	if option.linkToControls then
		for i, ctrl in ipairs(option.linkToControls) do
			if ctrl == control then
				table.remove(option.linkToControls, i)
			end
		end
	end
	if option.type == 'number' then
		if control.__SetValue then
			control.SetValue = control.__SetValue
			control.__SetValue = nil
		end
	end
end
--Make little window to indicate user needs to hit a keycombo to save a keybinding
local function MakeKeybindWindow( path, option, hotkeyButton, optionControl, option )
	local window_height = 80
	local window_width = 300
	
	get_key = true
	get_key_bind_mod = option.bindMod
	get_key_bind_without_mod = option.bindWithoutMod
	get_key_bind_with_any = option.bindWithAny
	get_key_bind_notify_function = option.OnHotkeyChange
	kb_path = path
	kb_button = hotkeyButton
	kb_control = optionControl
	kb_option = option
	kb_action = GetActionName(path, option)
	
	UnassignKeyBind(kb_action, true) -- 2nd param = verbose
	--otset( keybounditems, kb_action, nil )
	otset( keybounditems, kb_action, 'None' )
		
	ui.window_getkey = Window:New{
		caption = 'Set a HotKey',
		x = (scrW-window_width)/2,
		y = (scrH-window_height)/2,
		classname = "main_window_small_flat",
		clientWidth  = window_width,
		clientHeight = window_height,
		parent = screen0,
		backgroundColor = color.sub_bg,
		resizable = false,
		draggable = false,
		children = {
			Label:New{x = 8, y = 20, caption = 'Press a key combo', objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg})},
			Label:New{x = 8, y = 38, caption = '(Hit "Escape" to clear keybinding)', objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg})},
		}
	}
end

--Get hotkey action and readable hotkey string. Note: this is used in MakeHotkeyedControl() which make hotkey handled by Chili.
local function GetHotkeyData(path, option)
	local actionName = GetActionName(path, option)
	
	local hotkey = otget( keybounditems, actionName )
	if type(hotkey) == 'table' then
		hotkey = hotkey[1]
	end
	if hotkey and hotkey ~= 'None' then --if ZKkey contain definitive hotkey: return zkkey's hotkey
		if hotkey:find('%+%+') then
			hotkey = hotkey:gsub( '%+%+', '+plus' )
		end
		
		return GetReadableHotkey(hotkey)
	end
	if (not hotkey ) and option.hotkey then  --if widget supplied default hotkey: return widget's hotkey (this only effect hotkey on Chili menu)
		return option.hotkey
	end
	
	return 'None' --show "none" on epicmenu's menu
end

--Make a stack with control and its hotkey button
local function MakeHotkeyedControl(control, path, option, icon, noHotkey, minHeight, padding)
	padding = padding or 0
	local children = {}
	if noHotkey then
		control.x = 0
		if icon then
			control.x = 20
		end
		control.right = 0
		control:DetectRelativeBounds()
			
		if icon then
			local iconImage = Image:New{file = icon, width = 16, height = 16}
			children = {iconImage}
		end
		children[#children+1] = control
	else
		local hotkeystring = GetHotkeyData(path, option)
		local font = WG.GetFont()
		local hklength = font:GetTextWidth(hotkeystring)
		hklength = math.max( hklength + 4, 20)
		local control2 = control
		control.x = 0
		if icon then
			control.x = 20
		end
		control.right = hklength --room for hotkey button on right side
		control:DetectRelativeBounds()
		local hkbutton = Button:New{
			name = option.wname .. ' hotKeyButton';
			minHeight = minHeight or 30,
			y = control.y,
			right = 0,
			width = hklength,
			caption = hotkeystring,
			objectOverrideFont = font,
			OnClick = {
				function(self)
					if not get_key then
						MakeKeybindWindow( path, option, self, control, option )
					end
				end
			},
			--classname = "submenu_navigation_button",
			--backgroundColor = color.sub_button_bg,
			--textColor = color.sub_button_fg,
			tooltip = 'Hotkey: ' .. hotkeystring,
		}
		
		--local children = {}
		if icon then
			local iconImage = Image:New{file = icon, width = 16, height = 16}
			children = {iconImage}
		end
		children[#children+1] = control
		children[#children+1] = hkbutton
	end
	
	return Panel:New{
		width = "100%",
		orientation = 'horizontal',
		resizeItems = false,
		centerItems = false,
		autosize = true,
		backgroundColor = {0, 0, 0, 0},
		itemMargin = {0, 0, 0, 0},
		margin = {0, 0, 0, 0},
		itemPadding = {0, 0, 0, 0},
		padding = {0, 0, 0, padding},
		children = children,
	}
end

local function GetDefaultKeybind(path, option, defaultKeysMap)
	local action = GetActionName(path, option)
	if defaultKeysMap[action] then
		local keybind = defaultKeysMap[action]
		if type(v) == "table" then
			keybind = keybind[1]
		end
		return keybind
	end
	return keybind
end

local function ResetWinHotkeys(path)
	local defaultKeysMap = {}
	for i = 1, #defaultkeybinds do
		defaultKeysMap[defaultkeybinds[i][1]] = defaultkeybinds[i][2]
	end
	for _, elem in ipairs(pathoptions[path]) do
		local option = elem[2]
		local keybind = GetDefaultKeybind(path, option, defaultKeysMap)
		local action = GetActionName(path, option)
		
		UnassignKeyBind(action)
		if keybind and type(keybind) == 'table' then
			option.hotkey = GetReadableHotkey(keybind[1])
		elseif keybind then
			option.hotkey = GetReadableHotkey(keybind)
		else
			option.hotkey = "None"
		end
		Spring.Echo("keybind", option.name, keybind, option.hotkey)
		if keybind and keybind ~= "None" then
			AssignKeyBindAction(keybind, action)
			otset( keybounditems, action, hotkey )
		end
		if get_key_bind_notify_function then
			get_key_bind_notify_function()
			get_key_bind_notify_function = false
		end
		
		if WG.COFC_HotkeyChangeNotification then
			WG.COFC_HotkeyChangeNotification()
		end
	end
	ReApplyKeybinds()
end
local unresetableSettings = {button = true, --[[label = true, --]]menu = true}
local function ResetWinSettings(path)
	for option in pairs(displayedOptions) do
		if not (unresetableSettings[option.type]) then
			if option.default ~= nil then --fixme : need default
				if option.type == 'bool' or option.type == 'number'  then
					option.value = option.valuelist and GetIndex(option.valuelist, option.default) or option.default
					option.checked = option.value
					option:OnChange()
				elseif option.type == 'list' or option.type == 'radioButton' or option.type == 'label' and option.clickable then
					option.value = option.default
					option:OnChange()
				elseif option.type == 'colors' then
					option.color = option.default
					option:OnChange()
				elseif option.type == 'table' then
					if option.default and type(option.default) == 'table' then
						if type(option.value) == 'table' then
							for k,v in pairs(option.value) do
								option.value[k] = nil
							end
							for k,v in pairs(option.default) do
								option.value[k] = v
							end
							option:OnChange()
						end
					end
				end
			elseif option.type == 'label' and option.clickable then
				Spring.Log(widget:GetInfo().name, LOG.ERROR, '<EPIC Menu> Error #627', option.name, option.type, 'doesn\'t have default valut')
			end
		end
	end
end
local function HasSettingsToReset()
	for option in pairs(displayedOptions) do
		if not unresetableSettings[option.type] or option.type == 'label' and not option.clickable then
			if option.default ~= nil then --fixme : need default
				Echo('option ' .. option.name .. ' is lacking default !')
				return true
			else
				Spring.Log(widget:GetInfo().name, LOG.ERROR, '<EPIC Menu> Error #627', option.name, option.type)
			end
		end
	end
	return false
end

--[[ WIP
WG.crude.MakeHotkey = function(path, optionkey)
	local option = pathoptions[path][optionkey]
	local hotkey, hotkeystring = GetHotkeyData(path, option)
	if not get_key then
		MakeKeybindWindow( path, option, hotkey )
	end
	
end
--]]

function MENU:Search(termToSearch, path)
	local filtered_pathOptions = {}
	local tree_children = {} --used for displaying buttons
	local maximumResult = 100 --maximum result to display
	local showAdvanced = settings.showAdvanced
	local isDevMode = settings.dev
	local count = 0
	local function DigDeeper(path)
		local virtualCategoryHit = false --category deduced from the text label preceding the option(s)
		for _, elem in ipairs(pathoptions[path]) do
			local option = elem[2]
			local add = false
			local fromCategory = virtualCategoryHit
			virtualCategoryHit = false

			local lowercase_name = option.name:lower()
			local lowercase_text = option.text and option.text:lower() or ''
			local lowercase_desc = option.desc and option.desc:lower() or ''
			local add = SearchInText(lowercase_name, termToSearch) or SearchInText(lowercase_text, termToSearch) or SearchInText(lowercase_desc, termToSearch) or virtualCategoryHit
					
			--if option.advanced and not settings.config['epic_Settings_Show_Advanced_Settings'] then
			if option.hidden or (option.advanced and not showAdvanced) or (option.dev and not isDevMode) then
				--do nothing
			else
				add = SearchInText(lowercase_name, termToSearch) or SearchInText(lowercase_text, termToSearch) or SearchInText(lowercase_desc, termToSearch) or virtualCategoryHit

				if option.type == 'number' or option.type == 'colors' then
					add = fromCategory or add
					-- nothing more to do
				elseif option.type == 'button' or option.type == 'table' then
					local hide = false
					if option.isDirectoryButton then --this type of button is defined in AddOption(path, option, wname) (a link into submenu)
						local menupath = path .. ((path == "") and "" or "/") .. option.name
						if pathoptions[menupath] then
							if #pathoptions[menupath] >= 1 and menupath ~= "" then
								DigDeeper(menupath) --travel into & search into this branch
							else --dead end
								hide = true
							end
						end
					end
					
					if not hide then
						if not add then
							local hotkeystring = GetHotkeyData(path, option)
							local lowercase_hotkey = hotkeystring:lower()
							add = lowercase_hotkey:find(termToSearch)
						end
					end

				elseif option.type == 'label' then
					local virtualCategory = type(option.value) == 'string' and option.value or option.name
					virtualCategory = virtualCategory:lower()
					virtualCategoryHit = SearchInText(virtualCategory, termToSearch)
					if virtualCategoryHit then
						add = true
					end
				elseif option.type == 'bool' then
					add = fromCategory or add
					if not add then
						local hotkeystring = GetHotkeyData(path, option)
						local lowercase_hotkey = hotkeystring:lower()
						add = lowercase_hotkey:find(termToSearch)
					end
				elseif option.type == 'list' then
					add = fromCategory or add
					if not add then
						for i = 1, #option.items do
							local item = option.items[i]
							lowercase_name = item.name:lower()
							lowercase_desc = item.desc and item.desc:lower() or ''
							add = SearchInText(lowercase_name, termToSearch) or SearchInText(lowercase_desc, termToSearch)
							if add then
								break
							end
						end
					end
				elseif option.type == 'radioButton' then
					add = fromCategory or add
					if not add then
						for i = 1, #option.items do
							local item = option.items[i]
							lowercase_name = item.name and item.name:lower() or ''
							lowercase_desc = item.desc and item.desc:lower() or ''
							local hotkeystring = GetHotkeyData(path, item)
							local lowercase_hotkey = hotkeystring:lower()
							add = SearchInText(lowercase_name, termToSearch) or SearchInText(lowercase_desc, termToSearch) or lowercase_hotkey:find(termToSearch)
							if add then
								break
							end
						end
					end
				end
				if add then
					count = count + 1
					if count <= maximumResult then
						filtered_pathOptions[count] = {path, option}
					end
				end
			end
		end
	end

	DigDeeper(path)

	if count == 0 then
		tree_children[1] = Label:New{caption = "- No match for \"" .. termToSearch .."\" -",  objectOverrideFont = WG.GetSpecialFont(13, "epic_postit", {color = color.postit})}
	else
		tree_children[1] = Label:New{caption = "- \"" .. termToSearch .."\" matched "..count.." times -", objectOverrideFont = WG.GetSpecialFont(13, "epic_postit", {color = color.postit})}
		if  count > maximumResult then
			tree_children[2] = Label:New{caption = "- Displaying only the first "..maximumResult.." -",  objectOverrideFont = WG.GetSpecialFont(13, "epic_postit", {color = color.postit})}
			tree_children[3] = Label:New{caption = "- Navigate the menu to narrow results -",  objectOverrideFont = WG.GetSpecialFont(13, "epic_postit", {color = color.postit})}
		end			
	end
	return filtered_pathOptions, tree_children
end

local function Epic_SetShowAdvancedSettings(newAdvanced)
	settings.showAdvanced = newAdvanced
	RemakeEpicMenu()
end

WG.Epic_SetShowAdvancedSettings = Epic_SetShowAdvancedSettings

-- Make submenu window based on index from flat window list
local function GetPageTooltip(obj)
	local str = ''
	if obj.paths then
		str = 'paths'
		for _, path in pairs(obj.paths) do
			str = str ..'\n'.. (path == '' and 'ROOT' or path)
		end
	elseif obj.custom then
		str = 'custom'
		for i, opt in ipairs(obj.custom) do
			if i > 5 then
				str = str .. '\n...'
				break
			else
				str = str .. '\n' .. opt.name
			end
		end
	else
		str = obj.widget and "widget\n" .. obj.widget:GetInfo().name
			or obj.search and 'search \n"' .. obj.search .. '"'
			or obj.standard and 'path \n' .. (obj.path == '' and 'ROOT' or obj.path)
	end

	return str
end


function MENU:Navigate(newEventObj, pause)
	-- Echo('navigate', table.kConcat(newEventObj))
	if not self.win then
		self:MakeWin()
	end
	self.win:Show()
	if pause == nil then
		pause = true
	end
	local path
	local tree_children = {}
	local usingHistory = tonumber(newEventObj)

	if usingHistory then
		local v = newEventObj
		newEventObj = false
		while not newEventObj do
			newEventObj = history[history.cur + v]
			if not newEventObj then
				return
			end
			path = newEventObj.path
			if pathoptions[path] then
				history.cur = history.cur + v
			else
				newEventObj = false
				table.remove(history, history.cur + v)
				if v == -1 then
					history.cur = history.cur + v
				end
			end
		end
	else
		-- case refresh
		if not (newEventObj.widget or newEventObj.paths) and (
			newEventObj == eventObj and eventObj[1]
			or newEventObj.standard and eventObj.standard and newEventObj.path == eventObj.path and eventObj[1]
			or newEventObj.search and newEventObj.search == eventObj.search
			-- or newEventObj.paths and eventObj.paths and Identical(newEventObj.paths, eventObj.paths)
			or newEventObj.custom and eventObj.custom and Identical(newEventObj.custom, eventObj.custom)
		)
		then
			newEventObj = eventObj
			eventObj.label = nil
			path = eventObj.path
		-- 
		else
			local newPage = true
			if newEventObj.widget then
				local name = newEventObj.widget:GetInfo().name
				local nowWidget = widgetHandler:FindWidget(name)
				if nowWidget then
					newEventObj.widget = nowWidget
				end
				local w = newEventObj.widget
				if not w.options_order then
					Echo(sig .. w:GetInfo().name .. ' doesn\'t have any options.')
					return
				end
				if eventObj.widget then
					local curname = eventObj.widget:GetInfo().name
					local ki = widgetHandler.knownWidgets[name]
					local curki = widgetHandler.knownWidgets[curname]
					local kiFilename = ki.filename:gsub('\\', '/')
					local curkiFilename = curki.filename:gsub('\\', '/')
					if eventObj.widget and kiFilename == curkiFilename then
						newPage = false
						eventObj.scrollY = newEventObj.scrollY
						eventObj.widget = w
					end
				end
				local commons = {}
				local list = {}
				for i, name in ipairs(w.options_order) do
					local opt = w.options[name]
					if opt then
						local path = opt.path
						if not opt.path then
							Echo(sig .. '!! no opt path for', opt.wname, opt.name)
						else
							if not commons[path] then
								commons[path] = true
								for j = i, #w.options_order do
									local name = w.options_order[j]
									local opt = w.options[name]
									if opt.path == path then
										list[#list + 1] = {opt.path, opt}
									end
								end
							end
						end
					end
				end
				if not list[1] then
					return
				end
				
				newEventObj.standard = nil
				local p = list[1][1]
				local realLength = pathoptions[p] and #pathoptions[p] or 0

				if realLength == 0 or realLength == #list then
					newEventObj.standard = true
					path = p
				end
				if not newEventObj.standard then
					tree_children[1] = Label:New{caption = "- Options of \"" .. w:GetInfo().name .."\" -",  objectOverrideFont = WG.GetSpecialFont(13, "epic_postit", {color = color.postit})}
					path = '' -- going from root, good?
					newEventObj.pathLabeling = ''
				else
					path = p
					newEventObj.pathLabeling = p
					if eventObj.standard and eventObj.path == p then
						newPage = false
					end
				end
				newEventObj[1] = list
			elseif newEventObj.paths then
				for i in ipairs(newEventObj) do
					-- in case of refresh, we must empty the pathobjs, in case they don't exist anymore
					newEventObj[i] = nil
				end
				local got = false
				for i, p in ipairs(newEventObj.paths) do
					local pathobj = pathoptions[p]
					if pathobj then
						newEventObj[#newEventObj + 1] = pathobj
						got = p
					end
				end
				if not got then
					return
				end
				if not newEventObj[2] then
					newEventObj.standard = true
					path = got
				else
					newEventObj.pathLabeling = eventObj.path
					newEventObj.standard = nil
					path = eventObj.path
				end
			elseif newEventObj.custom then
				path = false
				for i in ipairs(newEventObj) do
					-- in case of refresh, we must empty the pathobjs, they might not be valid anymore
					newEventObj[i] = nil
				end
				local list = {}
				for i, opt in ipairs(newEventObj.custom) do
					local elem
					local dir = pathoptions[opt.path]
					local pathopt = opt.wname .. opt.key
					if dir then
						local realopt = otget(dir, pathopt)
						if realopt then
							elem = {opt.path, realopt}
						end
					end
					if elem then
						list[#list + 1] = elem
						if not path then
							path = elem[2].path
						end
					end
				end
				newEventObj[1] = list
				path = eventObj.path
				newEventObj.pathLabeling = path
			elseif newEventObj.standard then
				path = newEventObj.path
				local pathobj = pathoptions[path]
				if not pathobj then
					return
				end
				newEventObj[1] = pathoptions[path]
			elseif newEventObj.search then
				if eventObj.search == newEventObj.search then
					newPage = false
				end
				path = eventObj.path
				local searchResults, tree_start = self:Search(newEventObj.search, eventObj.path)
				newEventObj[1] = searchResults
				newEventObj.pathLabeling = path
				newEventObj.tree_start = tree_start
				
			end
			if newPage then
				-- remove everything after current history point and add our new event
				for i = history.cur + 1, #history do
					history[i] = nil
				end
				if history.cur >= MAX_HISTORY then
					table.remove(history, 1)
				else
					history.cur = history.cur + 1
				end
			end
		end
	end
	history[history.cur] = newEventObj   
	newEventObj.path = path

	if newEventObj.tree_start then
		for i, obj in ipairs(newEventObj.tree_start) do
			tree_children[i] = obj
		end
	end

	local pathLabeling = newEventObj.pathLabeling
	eventObj.scrollY = self.stackpanel.scrollPosY
	eventObj = newEventObj
	-- Echo('path', path, 'elements', #eventObj)
	displayedOptions = {}
	currentPaths = {}

	-- Echo('list : '..#eventObj)
	for e, elements in ipairs(eventObj) do
		if eventObj.standard then
			if elements.alphabeticalSort then
				table.sort(elements, sortDirAlphabetical)
			end
			if elements.hasCategory == nil then
				elements.hasCategory = false
				for i, t in ipairs(elements) do
					if t[2].category then
						elements.hasCategory = true
						break
					end
				end
			end
			if elements.hasCategory then
				SortCategories(elements)
			end
		end
		-- Echo('elements : '..#elements)
		for i, elem in ipairs(elements) do
			local option = elem[2]
			displayedOptions[option] = true
			currentPaths[option.path] = true

			local pathopt = elem[1]
			local dir = pathoptions[option.path]
			-- Echo('pathopt', pathopt, 'dir', option.path, dir, 'element', dir and otget( dir, option.wname .. option.key ))
			if not (dir and otget( dir, option.wname .. option.key )) then
				option = false
			elseif option.isDirectoryButton then
				pathopt = pathopt:gsub(option.name..'$', '', 1)
				local dir = pathoptions[pathopt]
				if dir then
					-- Echo('Dir '..pathopt..' : '..#dir)
					if not dir[1] then
						otset( dir, path .. pathopt, nil)
						pathoptions[pathopt] = nil
						option = false
						-- Echo('no options in ' .. pathopt)
					else
						if DirIsEmpty(pathopt, settings.dev, settings.showAdvanced) then
							-- Echo('virtually empty ' .. pathopt)
							option = false
						end
					end
				end
			end
			if option then
				if not eventObj.standard then
					if pathLabeling then
						local sub_path = false
						if eventObj.paths then
							local newPath = eventObj.paths[e]
							if pathLabeling ~= newPath then
								pathLabeling = newPath
								sub_path = pathLabeling:gsub('^'..eventObj.path, ""):gsub('^/','')
							end
						--note: during search mode the first entry in "elements[index]" table will contain search result's path, in normal mode the first entry in "pathoptions[path]" table will contain indexes.
						elseif pathLabeling ~= pathopt then --add label which shows where this option is found
							sub_path = pathopt:gsub('^'..eventObj.path, ""):gsub('^/','') --remove where we are
							pathLabeling = pathopt
						end
						if sub_path then
							if sub_path == '' then
								sub_path = 'here'
							end
							-- tree_children[#tree_children+1] = Label:New{caption = "- Location: " .. sub_path,  textColor = color.tooltip_bg}
							-- Echo('create sub path label for ',pathopt,sub_path .. #tree_children)
							local font = WG.GetFont(11, "epic_postit", {color = color.postit})
							local caption = "- Location: " .. sub_path
							tree_children[#tree_children+1] = Button:New{
								name = sub_path .. #tree_children; --note: name must not be same as existing button or crash.
								x = 0,
								width = font:GetTextWidth(caption)+5,
								minHeight = 20,
								objectOverrideFont = font,
								caption = caption,
								OnClick = {function()
									self:Navigate({standard = true, path = sub_path}, false)  --this made this "label" open another path when clicked
								end},
								backgroundColor = color.transGray,
								tooltip = sub_path,
								padding = {2, 2, 2, 2},
							}
							
						end
					end
				end
				
				if not option.desc then
					option.desc = ''
				end
				
				local simpleModeCull = (not root) and ((not option.simpleMode) == settings.simpleSettingsMode) and (not option.everyMode)
				if simpleModeCull and confdata.simpleModeFullDirectory then
					for i = 1, #confdata.simpleModeFullDirectory do
						if string.find(path, confdata.simpleModeFullDirectory[i]) then
							simpleModeCull = false
							break
						end
					end
				end
				if simpleModeCull and option.isDirectoryButton and confdata.simpleModeDirectory[option.name] then
					simpleModeCull = false
				end

				--if option.advanced and not settings.config['epic_Settings_Show_Advanced_Settings'] then
				if option.hidden or (option.advanced and not settings.showAdvanced) or simpleModeCull or (option.dev and not settings.dev) then
					--do nothing
				elseif option.type == 'button' or option.type == 'table' then
					local hide = false
					
					if option.wname == 'epic' then --menu
						local menupath = option.desc
						if pathoptions[menupath] and #(pathoptions[menupath]) == 0 then
							hide = true
						end
					end
					if not hide then
						local escapeSearch = eventObj.search and option.desc and option.desc:find(currentPath) and option.isDirectoryButton --this type of button will open sub-level when pressed (defined in "AddOption(path, option, wname )")
						local disabled = option.DisableFunc and option.DisableFunc()
						local icon = option.icon
						local slim = option.slim
						local button_height = slim and 25 or 36
						local button = Button:New{
							name = option.wname .. " " .. option.name;
							x = 0,
							y = 1,
							minHeight = button_height,
							--caption = option.name,
							noFont = true,
							OnClick = escapeSearch and {option.OnChange} or {option.OnChange},
							--backgroundColor = disabled and color.disabled_bg or {1, 1, 1, 1},
							--textColor = disabled and color.disabled_fg or color.sub_button_fg,
							classname = (disabled and "button_disabled") or nil,
							tooltip = option.desc,
							
							padding = {2, 2, 2, 2},
						}
						
						if icon then
							local width = root and 24 or 16
							local pos = root and 4 or 8
							Image:New{file = icon, width = width, height = width, parent = button, x = pos, y = pos}
						end
						
						Label:New{parent = button, x = 35, y = button_height*(slim and 0.1 or 0.2),  caption = option.name, objectOverrideFont = WG.GetFont(),}
						
						tree_children[#tree_children+1] = MakeHotkeyedControl(button, path, option, nil, option.isDirectoryButton or option.noHotkey, button_height)
					end
					
				elseif option.type == 'label' then
					tree_children[#tree_children+1] = Label:New{
						caption = (not option.clickable and option.value) or option.name,
						objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_header",{color = color.sub_header}),
						tooltip = option.desc,
						HitTest = (option.desc~='' or option.clickable) and returnSelf or nil,
						OnMouseDown = option.clickable and {function() option.OnChange({value = not option.value}) return true end},
					}

					if eventObj.label and (eventObj.label == (option.value or option.name)) then
						eventObj.scrollY = tree_children[#tree_children].y
						eventObj.label = nil
					end
				elseif option.type == 'text' then
					tree_children[#tree_children+1] = Label:New{caption = option.name, objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_header", {color = color.sub_header})}
					tree_children[#tree_children+1] =
						TextBox:New{
							name = option.wname .. " " .. option.name;
							width = "100%",
							minHeight = 30,
							text = option.value,
							WG.GetFont(),
							tooltip = option.desc,
							HitTest = option.desc~='' and returnSelf or nil,
						}
					
				elseif option.type == 'bool' then
					local slim = option.slim
					local hasHotkey = option.noHotkey
					local chbox = Checkbox:New{
						x = 0,
						y = 0,
						right = 35,
						defaultHeight = 22,
						caption = option.name,
						checked = option.value or false,
						valign = 'center',
						v_align = 'center',
						OnClick = {option.OnChange},
						objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}),
						tooltip   = option.desc,
					}
					option.epic_reference = chbox
					tree_children[#tree_children+1] = MakeHotkeyedControl(chbox,  path, option, icon, option.noHotkey, 22, 8)
				elseif option.type == 'number' then
					local icon = option.icon
					local numberPanel = Panel:New{
						width = "100%",
						height = 35,
						backgroundColor = {0, 0, 0, 0},
						padding = {0, 0, 0, 0},
						margin = {0, 0, 0, 0},
						--itemMargin = {2, 2, 2, 2},
						autosize = false,
					}
					if icon then
						numberPanel:AddChild(Image:New{file = icon, width = 16, height = 16, x = 4, y = 0})
						numberPanel:AddChild(Label:New{caption = option.name, objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}), x = 20, y = 0, HitTest = returnSelf, tooltip = option.desc})
					else
						numberPanel:AddChild(Label:New{padding = {0, 0, 0, 0}, caption = option.name, tooltip = option.desc, y = 0,
							objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}), HitTest = returnSelf})
					end
					if option.valuelist then
						option.value = GetIndex(option.valuelist, option.value)
					end
					local trackbar = Trackbar:New{
						x = 3,
						right = 3,
						y = 14,
						width = "100%",
						caption = option.name,
						value = option.value,
						trackColor = color.sub_fg,
						min = option.min or 0,
						max = option.max or 100,
						step = option.step or 1,
						useValueTooltip = not option.tooltipFunction,
						tooltipFunction = option.tooltipFunction and (function(self, ...) if UserDetected(self) then return option.tooltipFunction(self,...) else return self.value end end) or nil,
						tooltip_format = option.tooltip_format,
					}

					if option.update_on_the_fly then
						trackbar.OnChange[1] = function(self, ...) if UserDetected(self) then return option.OnChange(self, ...) end end
					else
						trackbar.OnMouseUp[1] = option.OnChange
					end
					option.control = trackbar

					numberPanel:AddChild(trackbar)

					tree_children[#tree_children+1] = numberPanel
					displayedOptions[option] = true
				elseif option.type == 'list' then
					tree_children[#tree_children+1] = Label:New{
						caption = option.name,
						objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_header", {color = color.sub_header}),
						tooltip = option.desc,
						HitTest = option.desc and returnSelf,
					}
					displayedOptions[option] = true
					local items = {};
					for i = 1, #option.items do
						local item = option.items[i]
						item.value = item.key --for 'OnClick'
						tree_children[#tree_children+1] = Button:New{
								name = option.wname .. " " .. item.name;
								width = "100%",
								caption = item.name,
								objectOverrideFont = WG.GetFont(),
								OnClick = {function() option.OnChange(item) end },
								--classname = "submenu_navigation_button",
								--backgroundColor = color.sub_button_bg,
								--textColor = color.sub_button_fg,
								tooltip = item.desc,
							}
					end
					--[[
					tree_children[#tree_children+1] = ComboBox:New {
						items = items;
						topHeight = 10,
					}
					]]--
				elseif option.type == 'radioButton' then
					local slim = option.slim
					tree_children[#tree_children+1] = Control:New{
						height = 1, minHeight = 0, padding = {0, 0, 0, 0},
					}
					tree_children[#tree_children+1] = Label:New{
						caption = option.name,
						objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_header", {color = color.sub_header}),
						tooltip = option.desc,
						HitTest = option.desc and returnSelf,
					}
					for i = 1, #option.items do
						local item = option.items[i]
						local cb = Checkbox:New{
							--x = 0,
							right = 35,
							y = 0,
							caption = '  ' .. item.name,
							checked = (option.value == item.value),
							OnChange = {function(self) if UserDetected(self) then option.OnChange(item) end end},
							objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}),
							tooltip = item.desc,
							round = true,
						}
						local icon = option.items[i].icon
						tree_children[#tree_children+1] = MakeHotkeyedControl( cb, path, item, icon, option.noHotkey, slim and 25, 1)
						
					end
					tree_children[#tree_children+1] = Control:New{
						height = 2, minHeight = 0, padding = {0, 6, 0, 0},
					}
					displayedOptions[option] = true
				elseif option.type == 'colors' then
					tree_children[#tree_children+1] = Label:New{caption = option.name, objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}),}
					tree_children[#tree_children+1] =
						Colorbars:New{
							width = "100%",
							height = B_HEIGHT*2,
							tooltip = option.desc,
							color = option.value or {1, 1, 1, 1},
							OnChange = {option.OnChange},
						}
				end
			end
		end
	end
	if eventObj.standard then
		parentPath = eventObj.path ~= '' and eventObj.path:match('(.-)/?([^/]-)$')
	else
		parentPath = eventObj.path
	end
	self:UpdateControls(tree_children)
	if pause and AllowPauseOnMenuChange(true) then
		spSendCommands("pause 1")
	end
end


function MENU:UpdateControls(tree_children)
	currentPath = eventObj.path


	self.stackpanel:ClearChildren()
	for i, obj in ipairs(tree_children) do
		self.stackpanel:AddChild(obj)
	end
	-- self.stackpanel:UpdateClientArea()
	-- self.win:UpdateClientArea()
	local caption = eventObj.path == '' and MAIN_MENU_CAPTION or currentPath
	if eventObj.standard then
		--nothing more
	elseif eventObj.custom then
		caption = '[custom] ' .. caption
	elseif eventObj.paths then
		caption = '[multi] ' .. caption
	elseif eventObj.search then
		caption = '[search] ' .. caption
	elseif eventObj.widget then
		caption = '[widget] ' .. caption
	end
	if history.cur > 1 then
		caption = '['..history.cur..'/'..#history..'] ' .. caption
	end
	self.win.caption = caption

	self.parentButton.supressButtonReaction = eventObj.standard and eventObj.path == ''
	if parentPath then
		self.parentButton.tooltip = 'to parent\n' .. (parentPath:match('[^/]+$') or MAIN_MENU_CAPTION) .. (parentPath ~= '' and '\n(+ctrl to '..MAIN_MENU_CAPTION..')' or '')
		SetColorButton(self.parentButton, 1)
	else
		self.parentButton.tooltip = ''
		SetColorButton(self.parentButton, 0.66)
	end

	self.resetButton.supressButtonReaction = eventObj.paths or eventObj.search or eventObj.custom

	if history.cur > 1 then
		self.backButton.tooltip = ''..(history.cur-1)..'/'..#history..' back to ' .. GetPageTooltip(history[history.cur-1]) .. ( history.cur > 2 and '\n(+CTRL for first page)' or '')
		self.backButton.supressButtonReaction = false
		SetColorButton(self.backButton, 1)
	else
		self.backButton.tooltip = ''
		self.backButton.supressButtonReaction = true
		SetColorButton(self.backButton, 0.66)
	end
	self.backButton.supressButtonReaction = not history[history.cur - 1]
	-- self.backButton.tooltip = self.backButton.tooltip:gsub('^Back in [^ ]+', 'Back in ' .. backIn)
	if history.cur < #history then
		self.forwardButton.tooltip = ''..(history.cur+1)..'/'..#history..' forward to ' .. GetPageTooltip(history[history.cur+1]) .. ( history.cur < #history-1 and '\n(+CTRL for last page)' or '')
		self.forwardButton.supressButtonReaction = false
		SetColorButton(self.forwardButton, 1)
	else
		self.forwardButton.tooltip = history.cur..'/'..#history
		self.forwardButton.supressButtonReaction = true
		SetColorButton(self.forwardButton, 0.66)
	end
	if eventObj.standard or table.size(displayedOptions) <= 40 then
		self.resetButton.supressButtonReaction = false
		self.resetButton.tooltip = "Reset the settings within this submenu. Use 'Settings/Reset Settings' to reset all settings."
		SetColorButton(self.resetButton, 1)
	else
		self.resetButton.supressButtonReaction = true
		SetColorButton(self.resetButton, 0.66)
		self.resetButton.tooltip = 'Too many options to reset in that custom list (40+)'
	end
	if eventObj.scrollY then
		self.stackpanel.scrollPosY = eventObj.scrollY
	-- elseif mem.last_scrollY[currentPath] then
	-- 	self.stackpanel.scrollPosY = mem.last_scrollY[currentPath]
	end

	self.win:UpdateClientArea() -- a way to refresh the window caption
end




function MENU:MakeWin()
	if self.win then
		self.win:Dispose()
	end

	local window_children = {}
		
	self.stackpanel = StackPanel:New{
		x = 0,
		y = 0,
		right = 0,
		orientation = "vertical",
		-- width  = "100%",
		height = "100%",
		backgroundColor = color.sub_bg,
		children = tree_children,
		itemMargin = {2, 0, 2, 0},
		resizeItems = false,
		centerItems = false,
		autosize = true,
	}

	self.scrollpanel = ScrollPanel:New{
		x = 3, y = 15,
		bottom = B_HEIGHT + (onSearchResults and 7 or 26),
		padding = {0,0,0,0},
		itemPadding = {0,0,0,0},
		right = 3,
		children = {
			self.stackpanel
		}
	}
	window_children[1] = self.scrollpanel
	---- menu checks

	self.devCheck = Checkbox:New{
		--x = 0,
		width = 150;
		x = 5,
		bottom = B_HEIGHT + 5;
		tooltip = 'Show the dev options',
		caption = 'Dev',
		checked = settings.dev,
		boxalign = 'left',
		-- textalign = 'right',
		textoffset = 8,
		OnChange = {function(self)
			settings.dev = not settings.dev
			if self.win then -- for case of menu refresh, retain the scroll
				eventObj.scrollY = self.win.children[1] and self.win.children[1].scrollPosY or 0
			end
			MENU:Navigate(eventObj, false)
		end },
		objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}),
	}
	window_children[#window_children+1] = self.devCheck
	----
	self.simpleCheck = Checkbox:New{
		--x = 0,
		width = 125;
		right = 5,
		bottom = B_HEIGHT + 5;
		tooltip = 'Untick to expand the number of graphics and interface options.',
		caption = 'Simple Settings',
		checked = settings.simpleSettingsMode,
		OnChange = {function(self)
			settings.simpleSettingsMode = not settings.simpleSettingsMode
			if self.win then -- for case of menu refresh, retain the scroll
				eventObj.scrollY = self.win.children[1] and self.win.children[1].scrollPosY or 0
			end
			MENU:Navigate(eventObj, false)
		end },
		objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_fg", {color = color.sub_fg}),
	}
	window_children[#window_children+1] = self.simpleCheck
	-----
	--- Navigations buttons
	self.buttonBar = Grid:New{
		x = 5;bottom = 5;
		right = 5, height = B_HEIGHT,
		columns = 6,
		padding = {0, 0, 0, 0},
		itemMargin = {0, 0, 0, 0}, --{1, 1, 1, 1},
		autosize = true,
		resizeItems = true,
		centerItems = true,
	}

	
	window_children[#window_children+1] = self.buttonBar
	
	--back button
	self.parentButton = Button:New{
		name = 'parentButton',
		noFont = true,
		OnClick = {
			function(_, _, _, button)
				if button == 1 then
					local ctrl = select(2, Spring.GetModKeyState())
					local targetPath = ctrl and '' or parentPath
					if targetPath ~= eventObj.path or not eventObj.standard then
						if history.cur > 1 then
							local ev = history[history.cur-1]
							if ev.path == targetPath and ev.standard then
								MENU:Navigate(-1, false)
								return
							end
						end
						MENU:Navigate({standard = true, path = targetPath}, false)
					end
				end
			end
		},
		--backgroundColor = color.sub_back_bg, textColor = color.sub_back_fg,
		--classname = "back_button",
		height = B_HEIGHT,
		padding = {2, 2, 2, 2},
		parent = self.buttonBar,
		tooltip = '',
		supressButtonReaction = true,
		children = {
			Image:New{
				file = LUAUI_DIRNAME  .. 'images/resbar/arrow_up.png',
				-- width = 16, height = 16, parent = button, x = 4, y = 2
				keepAspect = false,
				width = 24, height = 18, parent = button, x = 10, y = 2,
			},
			-- Label:New{caption = 'Back', x = 24, y = 4, objectOverrideFont = WG.GetFont(),}
		}
	}
	SetColorButton(self.parentButton, 0.66)

	self.backButton = Button:New{
		name = 'backButton',
		noFont = true,
		OnClick = {
			function(_, _, _, button)
				if button == 1 then
					local target = select(2, Spring.GetModKeyState()) and - (history.cur - 1) or -1 -- (ctrl pull back to first history event)
					if target ~= 0 and history[history.cur + target] then
						MENU:Navigate(target, false, nil)
					end
				end
			end
		},
		--backgroundColor = color.sub_back_bg, textColor = color.sub_back_fg,
		--classname = "back_button",
		height = B_HEIGHT,
		padding = {2, 2, 2, 2},
		parent = self.buttonBar,
		tooltip = '',
		supressButtonReaction = true,
		children = {
			Image:New{
				file = LUAUI_DIRNAME  .. 'images/epicmenu/arrow_left.png',
				-- width = 16, height = 16, parent = button, x = 4, y = 2
				keepAspect = false,
				width = 24, height = 18, parent = button, x = 10, y = 2,
			},
			-- Label:New{caption = 'Back', x = 24, y = 4, objectOverrideFont = WG.GetFont(),}
		}
	}
	SetColorButton(self.backButton, 0.66)

	self.forwardButton = Button:New{
		name = 'forwardButton',
		noFont = true,
		OnClick = {
			function(_, _, _, button)
				if button == 1 then
					local target = select(2, Spring.GetModKeyState()) and #history - history.cur or 1 -- (ctrl push back to last history event)
					if target ~= 0 and history[history.cur + target] then
						MENU:Navigate(target, false, nil)
					end
				end
			end
		},
		--backgroundColor = color.sub_back_bg, textColor = color.sub_back_fg,
		--classname = "back_button",
		height = B_HEIGHT,
		padding = {2, 2, 2, 2},
		parent = self.buttonBar,
		tooltip = '',
		supressButtonReaction = true,

		OnResize = {
			function(self) -- a (very) dirty hack to flip the image horizontally since we don't have this option (YET)
				local fwdButton = self.children[1]
				if fwdButton and not fwdButton.flipx then 
					if fwdButton.DrawControl == Image.DrawControl then
						fwdButton.DrawControl = function(self)
							gl.PushMatrix()
								gl.Translate(self.x*2 + self.width, 0, 0)
								gl.Scale(-1, 1, 1)
								Image.DrawControl(self)
							gl.PopMatrix()
						end
					end
				end
			end
		},
		
		children = {
			Image:New{
				file = LUAUI_DIRNAME  .. 'images/epicmenu/arrow_left.png',
				flipx = Image.flipx ~= nil or nil,
				keepAspect = false,
				width = 24, height = 18, parent = button, x = 10, y = 2},
			-- Label:New{caption = 'Back', x = 24, y = 4, objectOverrideFont = WG.GetFont(),}
		},
	}
	SetColorButton(self.forwardButton, 0.66)


	
	--search button
	self.searchButon = Button:New{
		name = 'searchButton',
		noFont = true,
		OnClick = {
			function(_, _, _, button)
				if button == 1 then
					spSendCommands("chat", "PasteText /search:" )
				end
			end
		},
		--textColor = color.sub_close_fg, backgroundColor = color.sub_close_bg,
		--classname = "navigation_button",
		height = B_HEIGHT,
		padding = {2, 2, 2, 2},
		parent = self.buttonBar,
		tooltip = 'Search',
		children = {
			Image:New{
				file = LUAUI_DIRNAME  .. 'images/epicmenu/find.png',
			 	-- width = 16, height = 16, parent = button, x = 4, y = 2
				keepAspect = false,
				width = 24, height = 18, parent = button, x = 10, y = 2,
			},
			-- Label:New{caption = 'Search', x = 24, y = 4, objectOverrideFont = WG.GetFont(),}
		}
	}
	
	self.resetButton = Button:New{
		name = 'resetButton',
		noFont = true,
		OnClick = {
			function(_, _, _, button)
				if button == 1 then
					if table.size(displayedOptions) < 40 then
						ResetWinSettings(eventObj.path)
						MENU:Navigate(eventObj, false)
					end
				end
			end
		},
		--textColor = color.sub_close_fg, backgroundColor = color.sub_close_bg,
		--classname = "navigation_button",
		tooltip = "Reset the settings within this submenu. Use 'Settings/Reset Settings' to reset all settings.",
		height = B_HEIGHT,
		padding = {2, 2, 2, 2},
		parent = self.buttonBar,
		tooltip = 'Reset',
		supressButtonReaction = not not (eventObj.search or eventObj.multi),
		children = {
			Image:New{
				file = LUAUI_DIRNAME  .. 'images/epicmenu/undo_white.png',
				-- width = 16, height = 16, parent = button, x = 4, y = 2
				keepAspect = false,
				width = 24, height = 18, parent = button, x = 10, y = 2,
			},
			-- Label:New{caption = 'Reset', x = 24, y = 4, objectOverrideFont = WG.GetFont(),}
		}
	}
	
	--close button
	self.closeButton = Button:New{
		name = 'menuCloseButton',
		noFont = true,
		OnClick = {
			function(_, _, _, button)
				if button == 1 then
					self.win:Hide()
				end
			end
		},
		--textColor = color.sub_close_fg, backgroundColor = color.sub_close_bg,
		--classname = "navigation_button",
		height = B_HEIGHT,
		padding = {2, 2, 2, 2},
		parent = self.buttonBar,
		tooltip = 'Close',
		children = {
			Image:New{
				file = LUAUI_DIRNAME  .. 'images/epicmenu/close.png', width = 16,
				-- height = 16, parent = button, x = 4, y = 2,
				keepAspect = false,
				width = 24, height = 18, parent = button, x = 10, y = 2,
			}
			-- Label:New{caption = 'Close', x = 24, y = 4, objectOverrideFont = WG.GetFont(),}
		}
	}
	local saveDimensions = function(self, from)
		settings.sub_pos_x = self.x
		settings.sub_pos_y = self.y
		settings.subwindow_height = self.height
		settings.subwindow_width = self.width
		settings.minized = self.minized
		-- Echo('save dimensions', self.width, 'from', from)
	end
	local caption = currentPath == '' and MAIN_MENU_CAPTION or currentPath
	self.win = Window:New{
		caption = (eventObj.search and 'Search in: "' .. caption .. '..."' or caption),
		x = settings.sub_pos_x,
		y = math.floor(settings.sub_pos_y),
		-- clientWidth = 270,
		classname = "main_window_tall",
		--clientHeight = window_height+B_HEIGHT*4,
		-- height = math.floor(settings.subwindow_height),
		width = settings.subwindow_width,
		height = settings.subwindow_height,
		minWidth = min_subwindow_width,
		minHeight = min_subwindow_height,
		--resizable = false,
		parent = settings.show_crudemenu and screen0 or nil,
		backgroundColor = color.sub_bg,
		children = window_children,
		OnResize = { function(self) saveDimensions(self, 'resize') end 	},
		-- OnDispose = { function(self) saveDimensions(self, 'dispose') end  },
		-- OnShow = { function(self) saveDimensions(self, 'show') end  },
		-- OnHide = { function(self) saveDimensions(self, 'hide') end  },

	}

	AdjustWindow(self.win)
	self.win:UpdateClientArea()
	if WG.MakeMinizable then
		WG.MakeMinizable(self.win, settings.minized)
	end


	if not settings.show_crudemenu then
		self.win:Hide()
	end

end


-- Show or hide menubar
local function ShowHideCrudeMenu(dontChangePause)
	--WG.crude.visible = settings.show_crudemenu -- HACK set it to wg to signal to player list
	if settings.show_crudemenu then
		if MENU.bar then
			screen0:AddChild(MENU.bar)
			--WG.chat.showConsole()
			--MENU.bar:UpdateClientArea()
		end
		if MENU.win and not MENU.win.visible then
			MENU.win:Show()
			-- screen0:AddChild(MENU.win)
			if (not dontChangePause) and AllowPauseOnMenuChange(true) then
				if (not ui.window_exit_confirm) then
					spSendCommands("pause 1")
				end
			end
		end
	else
		if MENU.bar then
			screen0:RemoveChild(MENU.bar)
			--WG.chat.hideConsole()
		end
		if MENU.win then
			screen0:RemoveChild(MENU.win)
			if (not dontChangePause) and AllowPauseOnMenuChange(true) then
				if (not ui.window_exit_confirm) then
					spSendCommands("pause 1")
				end
			end
		end
	end
	if MENU.win then
		AdjustWindow(MENU.win)
	end
end


local function DisposeExitConfirmWindow()
	if ui.window_exit_confirm then
		ui.window_exit_confirm:Dispose()
		ui.window_exit_confirm = nil
	end
end

local function LeaveExitConfirmWindow()
	DisposeExitConfirmWindow()
end

local function UnpauseFromExitConfirmWindow()
	if AllowPauseOnMenuChange(false) then
		spSendCommands("pause 0")
	end
end
WG.crude.UnpauseFromExitConfirmWindow = UnpauseFromExitConfirmWindow

local function MakeExitConfirmWindow(text, action, height, unpauseOnYes, unpauseOnNo)
	local screen_width, screen_height = Spring.GetViewGeometry()
	local menu_width = 320
	local menu_height = height or 64

	LeaveExitConfirmWindow()
	
	ui.window_exit_confirm = Window:New{
		name = 'exitwindow_confirm',
		parent = screen0,
		x = math.floor(screen_width/2 - menu_width/2),
		y = math.floor(screen_height/2 - menu_height/2),
		classname = "main_window_small_flat",
		dockable = false,
		clientWidth = menu_width,
		clientHeight = menu_height,
		draggable = false,
		tweakDraggable = false,
		resizable = false,
		tweakResizable = false,
		minimizable = false,
	}
	Label:New{
		parent = ui.window_exit_confirm,
		caption = text,
		objectOverrideFont = WG.GetFont(),
		width = "100%",
		y = 4,
		align = "center",
		objectOverrideFont = WG.GetSpecialFont(13, "epic_main_fg", {color = color.main_fg})
	}
	Button:New{
		name = 'confirmExitYesButton';
		parent = ui.window_exit_confirm,
		caption = "Yes",
		objectOverrideFont = WG.GetFont(),
		OnClick = {
			function()
				action()
				LeaveExitConfirmWindow()
				if unpauseOnYes then
					UnpauseFromExitConfirmWindow()
				end
			end
		},
		height = 32,
		x = 4,
		right = "55%",
		bottom = 4,
	}
	Button:New{
		name = 'confirmExitNoButton';
		parent = ui.window_exit_confirm,
		caption = "No",
		objectOverrideFont = WG.GetFont(),
		OnClick = {
			function()
				LeaveExitConfirmWindow()
				if unpauseOnNo then
					UnpauseFromExitConfirmWindow()
				end
			end
		},
		height = 32,
		x = "55%",
		right = 4,
		bottom = 4,
	}
end
WG.crude.MakeExitConfirmWindow = MakeExitConfirmWindow

local oldWidth, oldHeight
local function GetMainPanel(parent, width, height)
	if oldWidth == width and oldHeight == height then
		return false
	end
	oldWidth = width
	oldHeight = height

	local luaMenu = Spring.GetMenuName and Spring.SendLuaMenuMsg and Spring.GetMenuName()
	if luaMenu == "" then
		luaMenu = nil
	end

	if luaMenu then
		Spring.SendLuaMenuMsg("disableLobbyButton")
	end

	local stackChildren = {}
	local holderWidth = 6
	local sliderWidth = 96
	if width < 372 then
		sliderWidth = width - 276
	end
	
	if height < 45 then
		if width > 435 then
			stackChildren[#stackChildren + 1] = StackPanel:New{
				orientation = 'horizontal',
				width = 62,
				height = '100%',
				resizeItems = false,
				autoArrangeV = false,
				autoArrangeH = false,
				padding = {0, 2, 0, 0},
				itemMargin = {1, 0, 0, 0},
				children = {
					Image:New{file = LUAUI_DIRNAME .. 'Images/clock.png', width = 20, height = 26},
					ui.lbl_clock,
				},
			}
			holderWidth = holderWidth + 64
		end
		
		stackChildren[#stackChildren + 1] = StackPanel:New{
			orientation = 'horizontal',
			width = 78,
			height = '100%',
			resizeItems = false,
			autoArrangeV = false,
			autoArrangeH = false,
			padding = {0, 2, 0, 0},
			itemMargin = {1, 0, 0, 0},
			children = {
				Image:New{file = LUAUI_DIRNAME .. 'Images/epicmenu/game.png', width = 20, height = 26},
				ui.lbl_gtime,
			},
		}
		holderWidth = holderWidth + 80
		
		stackChildren[#stackChildren + 1] = Image:New{tooltip = 'Volume', file = LUAUI_DIRNAME .. 'Images/epicmenu/vol.png', width = 18, height = 18}
		stackChildren[#stackChildren + 1] = Grid:New{
			height = 24,
			width = sliderWidth - 25,
			columns = 1,
			rows = 2,
			resizeItems = false,
			margin = {0, 0, 0, 0},
			padding = {0, -2, 0, 0},
			itemPadding = {0, 0, 0, 0},
			itemMargin = {0, 0, 0, 0},
			
			children = {
				Trackbar:New{
					tooltip = 'Volume',
					height = 12,
					width = sliderWidth - 25,
					trackColor = color.main_fg,
					value = spGetConfigInt("snd_volmaster", 50),
					OnChange = {
						function(self)
							WG.crude.SetMasterVolume(self.value, true)
							if WG.ttsNotify then
								WG.ttsNotify()
							end
						end
					},
				},
				
				Trackbar:New{
					tooltip = 'Music',
					height = 12,
					width = sliderWidth - 25,
					min = 0,
					max = 1,
					step = 0.01,
					trackColor = color.main_fg,
					value = settings.config["epic_Settings/Audio_Music_Volume"] or MUSIC_VOLUME_DEFAULT,
					OnChange = {
						function(self)
							if WG.crude and WG.crude.SetMusicVolume then
								WG.crude.SetMusicVolume(self.value, true)
							end
						end
					},
				},
			},
		}
		masterVolumeTrackbar = stackChildren[#stackChildren].children[1]
		musicTrackbar = stackChildren[#stackChildren].children[2]
		--stackChildren[#stackChildren + 1] = Trackbar:New{
		--    tooltip = 'Volume',
		--    height = 15,
		--    width = sliderWidth - 25,
		--    trackColor = color.main_fg,
		--    value = spGetConfigInt("snd_volmaster", 50),
		--    OnChange = {
		--        function(self)
		--            spSendCommands{"set snd_volmaster " .. self.value}
		--            if WG.ttsNotify then
		--                WG.ttsNotify()
		--            end
		--        end
		--    },
		--}
		
		holderWidth = holderWidth + sliderWidth + 2
	else
		stackChildren[#stackChildren + 1] = Grid:New{
			orientation = 'horizontal',
			columns = 1,
			rows = 2,
			width = 80,
			height = '100%',
			--height = 40,
			resizeItems = true,
			autoArrangeV = true,
			autoArrangeH = true,
			padding = {0, 0, 0, 0},
			itemPadding = {0, 0, 0, 0},
			itemMargin = {0, 0, 0, 0},
			
			children = {
				StackPanel:New{
					orientation = 'horizontal',
					width = 70,
					height = '100%',
					resizeItems = false,
					autoArrangeV = false,
					autoArrangeH = false,
					padding = {0, 1, 0, 0},
					itemMargin = {2, 0, 0, 0},
					children = {
						Image:New{file = LUAUI_DIRNAME .. 'Images/epicmenu/game.png', width = 20, height = 20},
						ui.lbl_gtime,
					},
				},
				StackPanel:New{
					orientation = 'horizontal',
					width = 80,
					height = '100%',
					resizeItems = false,
					autoArrangeV = false,
					autoArrangeH = false,
					padding = {0, 0, 0, 0},
					itemMargin = {2, 0, 0, 0},
					children = {
						Image:New{file = LUAUI_DIRNAME .. 'Images/clock.png', width = 20, height = 20},
						ui.lbl_clock,
					},
				},
			},
		}
		
		holderWidth = holderWidth + 82
		
		stackChildren[#stackChildren + 1] = Grid:New{
			height = '100%',
			width = sliderWidth,
			columns = 2,
			rows = 2,
			resizeItems = false,
			margin = {0, 0, 0, 0},
			padding = {0, 0, 0, 0},
			itemPadding = {1, 1, 1, 1},
			itemMargin = {1, 1, 1, 1},
			
			children = {
				--Label:New{caption = 'Vol', width = 20, objectOverrideFont = WG.GetSpecialFont(13, "epic_main_fg", {color = color.main_fg}) },
				Image:New{tooltip = 'Volume', file = LUAUI_DIRNAME .. 'Images/epicmenu/vol.png', width = 18, height = 18},
				Trackbar:New{
					tooltip = 'Volume',
					height = 15,
					width = sliderWidth - 25,
					trackColor = color.main_fg,
					value = spGetConfigInt("snd_volmaster", 50),
					OnChange = {
						function(self)
							WG.crude.SetMasterVolume(self.value, true)
							if WG.ttsNotify then
								WG.ttsNotify()
							end
						end
					},
				},
				
				Image:New{tooltip = 'Music', file = LUAUI_DIRNAME .. 'Images/epicmenu/vol_music.png', width = 18, height = 18},
				Trackbar:New{
					tooltip = 'Music',
					height = 15,
					width = sliderWidth - 25,
					min = 0,
					max = 1,
					step = 0.01,
					trackColor = color.main_fg,
					value = settings.config["epic_Settings/Audio_Music_Volume"] or MUSIC_VOLUME_DEFAULT,
					OnChange = {
						function(self)
							if WG.crude and WG.crude.SetMusicVolume then
								WG.crude.SetMusicVolume(self.value, true)
							end
						end
					},
				},
			},
		}
		masterVolumeTrackbar = stackChildren[#stackChildren].children[2]
		musicTrackbar = stackChildren[#stackChildren].children[4]
		
		holderWidth = holderWidth + sliderWidth + 2
	end
	
	stackChildren[#stackChildren + 1] = ui.lbl_flag
	holderWidth = holderWidth + 26
	
	stackChildren[#stackChildren + 1] = Button:New{
		name = 'subMenuButton',
		OnClick = {function() ActionSubmenu() end},
		objectOverrideFont = WG.GetSpecialFont(13, "epic_game_fg", {color = color.game_fg}),
		height = height - 9,
		width = B_WIDTH_TOMAINMENU + 1,
		caption = "Menu (\255\0\255\0"..WG.crude.GetHotkey("crudesubmenu").."\008)",
		padding = btn_padding,
		margin = btn_margin,
		tooltip = '',
		children = {
			--Image:New{file = title_image, height = B_HEIGHT-2, width = B_HEIGHT-2, x = 2, y = 4},
			--Label:New{caption = "Menu (\255\0\255\0"..WG.crude.GetHotkey("crudesubmenu").."\008)", valign = "center"}
		},
	}
	holderWidth = holderWidth + 80
	
	if luaMenu then
		stackChildren[#stackChildren + 1] = Button:New{
			name = 'lobbyButton',
			OnClick = {function() ViewLobby() end},
			objectOverrideFont = WG.GetSpecialFont(13, "epic_game_fg", {color = color.game_fg}),
			height = height - 9,
			width = B_WIDTH_TOMAINMENU + 1,
			caption = "Lobby (\255\0\255\0"..WG.crude.GetHotkey("viewlobby").."\008)",
			padding = btn_padding,
			margin = btn_margin,
			tooltip = '',
			children = {
				--Image:New{file = title_image, height = B_HEIGHT-2, width = B_HEIGHT-2, x = 2, y = 4},
				--Label:New{caption = "Menu (\255\0\255\0"..WG.crude.GetHotkey("crudesubmenu").."\008)", valign = "center"}
			},
		}
		holderWidth = holderWidth + 80
	end
	
	-- FPS
	--Grid:New{
	--    orientation = 'horizontal',
	--    columns = 1,
	--    rows = 2,
	--    width = 60,
	--    height = '100%',
	--    --height = 40,
	--    resizeItems = true,
	--    autoArrangeV = true,
	--    autoArrangeH = true,
	--    padding = {0, 0, 0, 0},
	--    itemPadding = {0, 0, 0, 0},
	--    itemMargin = {0, 0, 0, 0},
	--
	--    children = {
	--        ui.lbl_fps,
	--        ui.lbl_flag,
	--    },
	--},
	
	-- Game Logo
	--Image:New{tooltip = title_text, file = title_image, height = B_HEIGHT, width = B_HEIGHT},
	--
	--Button:New{
	--    name = 'tweakGuiButton',
	--    caption = "", OnClick = {function() spSendCommands{"luaui tweakgui"} end}, textColor = color.menu_fg, height = B_HEIGHT+4, width = B_HEIGHT+5,
	--    padding = btn_padding, margin = btn_margin, tooltip = "Move and resize parts of the user interface (\255\0\255\0Ctrl+F11\008) (Hit ESC to exit)",
	--    children = {
	--        Image:New{file = LUAUI_DIRNAME .. 'Images/epicmenu/move.png', height = B_HEIGHT-2, width = B_HEIGHT-2},
	--    },
	--},
	
	local mainPanel = Panel:New{
		y = 0,
		right = 0,
		bottom = 0,
		clientWidth = holderWidth,
		backgroundColor = color.empty,
		color = color.empty,
		margin = {0, 0, 0, 0},
		padding = {0, 0, 3, 6},
		parent = parent,
		
		children = {
			StackPanel:New{
				name = 'stack_main',
				orientation = 'horizontal',
				width = '100%',
				height = '100%',
				resizeItems = false,
				padding = {0, 0, 0, 0},
				itemPadding = {1, 1, 1, 1},
				itemMargin = {1, 1, 1, 1},
				autoArrangeV = false,
				autoArrangeH = false,
				
				children = stackChildren,
			}
		}
	}
	
	return mainPanel
end

local function MakeMenuBar()
	local btn_padding = {4, 3, 3, 2}
	local btn_margin = {0, 0, 0, 0}
	local exit_menu_width = 210
	local exit_menu_height = 280
	local exit_menu_btn_width = 7*exit_menu_width/8
	local exit_menu_btn_height = max(exit_menu_height/8, 30)
	local exit_menu_cancel_width = exit_menu_btn_width/2
	local exit_menu_cancel_height = 2*exit_menu_btn_height/3

	local crude_width = 380
	local crude_minWidth = 350
	local crude_height = B_HEIGHT_MAIN + 8
	
	-- A bit evil, but par for the course
	ui.lbl_fps = Label:New{name = 'ui.lbl_fps', caption = 'FPS:', objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_header", {color = color.sub_header}), margin = {0, 5, 0, 0}}
	ui.lbl_gtime = Label:New{name = 'ui.lbl_gtime', caption = '00:00', width = 55, height = 5, objectOverrideFont = WG.GetSpecialFont(13, "epic_sub_header", {color = color.sub_header})}
	ui.lbl_clock = Label:New{name = 'ui.lbl_clock', caption = 'Clock', width = 45, height = 5, objectOverrideFont = WG.GetSpecialFont(13, "epic_main_fg", {color = color.main_fg})} -- autosize = false}
	ui.lbl_flag = Image:New{tooltip = 'Choose Language', file = ":cn:".. LUAUI_DIRNAME .. "Images/flags/".. flagByLang[settings.lang] ..'.png', width = 16, height = 11, OnClick = {MakeFlags }, padding = {4, 4, 4, 6}  }
	
	local screen_width, screen_height = Spring.GetWindowGeometry()
	
	MENU.bar = Window:New{
		name = 'epicmenubar',
		x = screen_width - crude_width,
		y = 0,
		width = crude_width,
		height = crude_height,
		minHeight = crude_height,
		minWidth = crude_minWidth,
		draggable = false,
		tweakDraggable = true,
		tweakResizable = true,
		resizable = false,
		minimizable = false,
		dockable = true,
		backgroundColor = color.empty,
		color = color.empty,
		padding = {0, -1, 0, 0},
		parent = screen0,
		OnResize = {
			function (obj)
				local newPanel = GetMainPanel(obj, obj.width, obj.height)
				if newPanel then
					if ui.panel_crude then
						ui.panel_crude:Dispose()
					end
					ui.panel_crude = newPanel
				end
				ui.panel_crude:BringToFront()
			end
		}
	}
	
	ui.panel_background = Panel:New{
		classname = settings.menuClassname,
		x = 0,
		y = 0,
		right = 0,
		bottom = 0,
		backgroundColor = {1, 1, 1, 1},
		color = {1, 1, 1, 1},
		parent = MENU.bar,
	}
	settings.show_crudemenu = true
	--ShowHideCrudeMenu()
end

local function MakeSaveLoadButtons()
	local imgPath = LUAUI_DIRNAME  .. 'images/'
	AddOption('',
	{
		type='button',
		name='Save Game',
		desc = 'Save game (not available in multiplayer and tutorials).',
		OnChange = function()
				if WG.SaveGame and CanSaveGame() then
					WG.SaveGame.CreateSaveWindow()
				end
			end,
		key='Save Game',
		icon = imgPath .. 'commands/Bold/unload.png',
		DisableFunc = function() return not CanSaveGame() end
	})
	
	AddOption('',
	{
		type='button',
		name='Load Game',
		desc = '',
		OnChange = function()
				if WG.SaveGame then
					WG.SaveGame.CreateLoadWindow()
				end
			end,
		key='Load Game',
		icon = imgPath .. 'commands/Bold/load.png',
	})
end
local function PlayingButNoTeammate() --I am playing and playing alone with no teammate
	if Spring.GetSpectatingState() then
		return false
	end
	local myAllyTeamID = Spring.GetMyAllyTeamID() -- get my alliance ID
	local teams = Spring.GetTeamList(myAllyTeamID) -- get list of teams in my alliance
	if #teams == 1 then -- if I'm alone and playing (no ally)
		return true
	end
	return false
end

local function DisableVoteResign()
	return Spring.GetPlayerRulesParam(Spring.GetLocalPlayerID(), "initiallyPlayingPlayer") ~= 1 or PlayingButNoTeammate() or isMission
end

local function MakeQuitButtons()
	--AddOption('', {
	--	type = 'label',
	--	name = 'Quit game',
	--	value = 'Quit game',
	--	key = 'Quit game',
	--})
	
	local imgPath = LUAUI_DIRNAME  .. 'images/'

	AddOption('', {
		type = 'button',
		name = 'Vote Resign',
		desc = "Ask teammates to resign",
		icon = imgPath..'epicmenu/whiteflag_check.png',
		OnChange = function()
				if not DisableVoteResign() then
					spSendCommands("say !poll resign")
					ActionMenu()
				end
			end,
		key = 'Vote Resign',
		DisableFunc = DisableVoteResign, --function that trigger grey colour on buttons (not actually disable their functions)
	})
	AddOption('', {
		type = 'button',
		name = 'Resign',
		desc = "Abandon team and become spectator",
		icon = imgPath..'epicmenu/whiteflag.png',
		OnChange = function()
				if not (isMission or Spring.GetSpectatingState()) then
					MakeExitConfirmWindow("Are you sure you want to resign?", function()
						if AllowPauseOnMenuChange(true) then
							spSendCommands("pause 1")
						end
						local frame = Spring.GetGameFrame()
						if frame and frame > 0 then
							if WG.MissionResign then
								WG.MissionResign()
							else
								Spring.SendLuaRulesMsg("forceresign")
								spSendCommands{"spectator"}
							end
						end
					end, nil, true, true)
				end
			end,
		key = 'Resign',
		DisableFunc = function()
			return (Spring.GetSpectatingState() or isMission)
		end, --function that trigger grey colour on buttons (not actually disable their functions)
	})
	AddOption('', {
		type = 'button',
		name = 'Restart',
		desc = "Restart the game",
		icon = imgPath..'epicmenu/undo.png',
		OnChange = function()
				-- Only allow restarting for local games or by the host of steam coop.
				if (not isServerHost) and Spring.GetMenuName and Spring.SendLuaMenuMsg and Spring.GetMenuName() then
					local myPing = select(6, Spring.GetPlayerInfo(Spring.GetMyPlayerID(), false))
					if myPing and myPing < 0.04 then
						MakeExitConfirmWindow("Are you sure you want to restart?", function()
							Spring.SendLuaMenuMsg("restartGame")
						end, nil, false, true)
					end
				end
			end,
		key = 'Restart',
		DisableFunc = function()
			-- Only allow restarting for local games or by the host of steam coop.
			if isServerHost then
				return true
			end
			if Spring.GetMenuName and Spring.SendLuaMenuMsg and Spring.GetMenuName() then
				local myPing = select(6, Spring.GetPlayerInfo(Spring.GetMyPlayerID(), false))
				return not (myPing and myPing < 0.04)
			end
			return true
		end,
	})

	AddOption('', {
		type = 'button',
		name = 'Exit to Lobby',
		desc = "Leave the game.",
		icon = imgPath..'epicmenu/exit.png',
		OnChange = function()
			MakeExitConfirmWindow("Are you sure you want to leave the battle?", function()
				if AllowPauseOnMenuChange(true) then
					spSendCommands("pause 1")
				end
				if Spring.GetMenuName and Spring.GetMenuName() ~= "" then
					Spring.Reload("")
				else
					spSendCommands{"quit", "quitforce"}
				end
			end, nil, false, true)
		end,
		key = 'Exit to Desktop',
	})

	AddOption('', {
		type ='button',
		name = 'Reload EPIC MENU',
		icon = imgPath..'epicmenu/undo_white.png',
		desc = "",
		OnChange = function(self)
			ReloadEPIC()
		end,
		key = 'Reload EPIC MENU',
		dev = true,
	})
	AddOption('', {
		type ='bool',
		name = 'Debug EPIC MENU',
		desc = "",
		OnChange = function(self)
			debugMe = self.value
		end,
		key = 'Debug EPIC MENU',
		dev = true,
	})

end

--Remakes crudemenu and remembers last submenu open
RemakeEpicMenu = function()
	local lastPath = currentPath
	local wasOpen = MENU.win and MENU.win.visible
	-- Do not change pause state.
	MENU:Kill(true)
	if wasOpen then
		MENU:Navigate(eventObj, false)
	end
end

WG.RemakeEpicMenu = RemakeEpicMenu
local function LanguageChanged ()
	for path, subtable in pairs(pathoptions) do
		for _, element in ipairs(subtable) do
			UpdateI18n(element[2])
		end
	end
	WG.RemakeEpicMenu()
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:ViewResize(vsx, vsy)
	scrW = vsx
	scrH = vsy
end

function widget:Initialize()
	if (not WG.Chili) then
		widgetHandler:RemoveWidget(widget)
		Echo('EPIC MENU needs Chili !')
		return
	end
	init = true
	
	
	spSendCommands("unbindaction hotbind")
	spSendCommands("unbindaction hotunbind")
	

	-- setup Chili
	Chili = WG.Chili
	Control = Chili.Control
	Button = Chili.Button
	Label = Chili.Label
	Colorbars = Chili.Colorbars
	Checkbox = Chili.Checkbox
	Window = Chili.Window
	Panel = Chili.Panel
	ScrollPanel = Chili.ScrollPanel
	StackPanel = Chili.StackPanel
	LayoutPanel = Chili.LayoutPanel
	Grid = Chili.Grid
	Trackbar = Chili.Trackbar
	TextBox = Chili.TextBox
	Image = Chili.Image
	Progressbar = Chili.Progressbar
	Colorbars = Chili.Colorbars
	screen0 = Chili.Screen0

	widget:ViewResize(Spring.GetViewGeometry())
	
	-- Set default positions of windows on first run
	local screenWidth, screenHeight = Spring.GetWindowGeometry()
	if not settings.subwindow_height then
		settings.subwindow_height = 582
	end
	if not settings.sub_pos_x then
		settings.sub_pos_x = math.floor(screenWidth/2 - 150)
		settings.sub_pos_y = math.floor(screenHeight/2 - settings.subwindow_height * 0.55)
	end
	
	if not keybounditems then
		keybounditems = {}
	end
	if not settings.config then
		settings.config = {}
	end

	if not confLoaded then
		if not settings.lang or not flagByLang[settings.lang] then
			local flag = select(8, Spring.GetPlayerInfo(Spring.GetLocalPlayerID(), false)):lower()
			settings.lang = langByFlag[flag]
		end

		WG.lang(settings.lang)
	end

	-- add custom widget settings to crudemenu
	AddAllCustSettings()

	--this is done to establish order the correct button order
	AddOption('Settings')
	AddOption('Hotkeys')
	AddOption('Settings/Unit Behaviour')
	AddOption('Help')
	
	local imgPath = LUAUI_DIRNAME  .. 'images/'
	AddOption('Settings/Reset Settings')
	AddOption('Settings/Audio')
	-- (setting directory that contains only subdirs to be sorted alphabetically)
	AddOption('Settings/Camera', nil, nil, nil, true)
	AddOption('Settings/Graphics', nil, nil, nil, true)
	AddOption('Settings/Accessibility')
	AddOption('Settings/HUD Panels', nil, nil, nil, true)
	AddOption('Settings/HUD Presets')
	AddOption('Settings/Interface', nil, nil, nil, true)
	AddOption('Settings/Misc')


	-- Add pre-configured button/options found in epicmenu config file
	local options_temp = CopyTable(epic_options, true)
	for i = 1, #options_temp do
		local option = options_temp[i]
		AddOption(option.path, option)
	end
	
	MakeSaveLoadButtons()
	MakeQuitButtons()
	
	AddOption('', {type = 'label', name = '', value = '', key = ''})
	
	-- About button
	--AddOption('Settings', {
	--    type = 'text',
	--    name = 'About',
	--    value = gameInfoText,
	--    --desc = "about game",
	--    key = 'About',
	--})
	
	-- Clears all saved settings of custom widgets stored in crudemenu's config
	WG.crude.ResetSettings = function()
		for path, _ in pairs(pathoptions) do
			ResetWinSettings(path)
		end
		Echo 'Cleared all settings.'
		if MENU.win and MENU.win.visible then
			MENU:Navigate(eventObj, false)
		end
	end
	
	-- clear all keybindings
	WG.crude.ResetKeys = function()
		keybounditems = {}
		keybounditems = CopyTable(defaultkeybinds, true) --restore with mods zkkey's default value
		
		--restore with widget's default value:
		for path, subtable in pairs ( pathoptions) do
			for _, element in ipairs(subtable) do
				local option = element[2]
				local defaultHotkey = option.orig_hotkey
				if defaultHotkey then
					option.hotkey = defaultHotkey --make chili menu display the default hotkey
					local actionName = GetActionName(path, option)
					otset( keybounditems, actionName, defaultHotkey) --save default hotkey to zkkey
				end
			end
		end
		
		ReApplyKeybinds() --unbind all hotkey and re-attach with stuff in keybounditems table
		Echo 'Reset all hotkeys to default.'
		if MENU.win and MENU.win.visible then
			MENU:Navigate(eventObj, false)
		end
	end
	
	-- get hotkey
	WG.crude.GetHotkey = function(actionName, all) --Note: declared here because keybounditems must not be empty
		local actionHotkey = GetActionHotkey(actionName)
		--local hotkey = keybounditems[actionName] or actionHotkey
		local hotkey = otget( keybounditems, actionName ) or actionHotkey
		if not hotkey or hotkey == 'None' then
			return all and {} or ''
		end
		if not all then
			if type(hotkey) == 'table' then
				hotkey = hotkey[1]
			end
			return GetReadableHotkey(hotkey)
		else
			local ret = {}
			if type(hotkey) == 'table' then
				for k, v in pairs( hotkey ) do
					ret[#ret+1] = GetReadableHotkey(v)
				end
			else
				ret[#ret+1] = GetReadableHotkey(hotkey)
			end
			return ret
		end
	end
	
	WG.crude.GetHotkeys = function(actionName)
		return WG.crude.GetHotkey(actionName, true)
	end
	
	WG.crude.GetHotkeyRaw = function(actionName, all) --Note: declared here because keybounditems must not be empty
		local actionHotkey = GetActionHotkey(actionName)
		--local hotkey = keybounditems[actionName] or actionHotkey
		local hotkey = otget(keybounditems, actionName ) or actionHotkey
		if not hotkey or hotkey == 'None' then
			return
		end
		if not all then
			if type(hotkey) ~= 'table' then
				hotkey = {hotkey}
			end
			return hotkey
		else
			local ret = {}
			if type(hotkey) == 'table' then
				for k, v in pairs(hotkey) do
					ret[#ret+1] = v
				end
			else
				ret[#ret+1] = hotkey
			end
			return ret
		end
	end
	
	-- set hotkey
	WG.crude.SetHotkey =  function(actionName, hotkey, func) --Note: declared here because pathoptions must not be empty
		if hotkey then
			hotkey = GetReadableHotkey(hotkey) --standardize hotkey (just in case stuff happen)
		end
		if hotkey == '' then
			hotkey = nil --convert '' into NIL.
		end
		if func then
			if hotkey then
				AddAction(actionName, func, nil, "t") --attach function to action
			else
				RemoveAction(actionName) --detach function from action
			end
		end
		if hotkey then
			AssignKeyBindAction(hotkey, actionName, false) --attach action to keybinds
		else
			UnassignKeyBind(actionName, false) --detach action from keybinds
		end
		otset(keybounditems, actionName, hotkey) --update epicmenu's hotkey table
		for path, subtable in pairs (pathoptions) do
			for _, element in ipairs(subtable) do
				local option = element[2]
				local indirectActionName = GetActionName(path, option)
				local directActionName = option.action
				if indirectActionName == actionName or directActionName == actionName then
					option.hotkey = hotkey or "None" --update pathoption hotkey for Chili menu display & prevent conflict with hotkey registerd by Chili . Note: LUA is referencing table, so we don't need to change same table elsewhere.
				end
			end
		end
	end
	
	function WG.crude.SetMenuSkinClass(newClassName)
		if newClassName == settings.menuClassname then
			return
		end
		settings.menuClassname = newClassName
		
		local currentSkin = Chili.theme.skin.general.skinName
		local skin = Chili.SkinHandler.GetSkin(currentSkin)
		
		local newClass = skin[newClassName]
		if not newClass then
			newClass = skin.panel
			newClassName = "panel"
		end
		ui.panel_background.classname = newClassName
		
		ui.panel_background.tiles = newClass.tiles
		ui.panel_background.TileImageFG = newClass.TileImageFG
		--ui.panel_background.backgroundColor = newClass.backgroundColor
		ui.panel_background.TileImageBK = newClass.TileImageBK
		if newClass.padding then
			ui.panel_background.padding = newClass.padding
			ui.panel_background:UpdateClientArea()
		end
		ui.panel_background:Invalidate()
	end
		
	-- Add custom actions for the following keybinds
	AddAction("crudemenu", ActionMenu, nil, "t")
	AddAction("show_toggle_crudemenu", ToggleActionMenu, nil, "t")
	AddAction("crudesubmenu", ActionSubmenu, nil, "t")
	AddAction("viewlobby", ViewLobby, nil, "t")
	AddAction("exitwindow", ActionExitWindow, nil, "t")
	AddAction("reloadepic", ReloadEPIC, nil, "t")
	MakeMenuBar()
	
	useUiKeys = settings.config['epic_Settings/Misc_Use_uikeys.txt']
	
	if not useUiKeys then
		spSendCommands("unbindall")
	else
		Echo('You have opted to use the engine\'s uikeys.txt. The menu keybind system will not be used.')
	end
	
	LoadKeybinds()
	ReApplyKeybinds()
	
	-- Override widgethandler functions for the purposes of alerting crudemenu
	-- when widgets are loaded, unloaded or toggled
	if not WG.OnWidgetState then
		widgetHandler.OriginalInsertWidget = widgetHandler.InsertWidget
		widgetHandler.InsertWidget = function(self, widget)
			PreIntegrateWidget(widget)
			
			local ret = self:OriginalInsertWidget(widget)
			
			if type(widget) == 'table' and type(widget.options) == 'table' then
				IntegrateWidget(widget, true)
			end
			
			
			checkWidget(widget)
			return ret
		end
		
		widgetHandler.OriginalRemoveWidget = widgetHandler.RemoveWidget
		widgetHandler.RemoveWidget = function(self, widget)
			local ret = self:OriginalRemoveWidget(widget)
			if preintegrated[widget] then
				IntegrateWidget(widget, false)
			end
			installed[widget] = false
			
			checkWidget(widget)
			return ret
		end
		
		widgetHandler.OriginalToggleWidget = widgetHandler.ToggleWidget
		widgetHandler.ToggleWidget = function(self, name)
			local ret = self:OriginalToggleWidget(name)
			local w = widgetHandler:FindWidget(name)
			if w then
				checkWidget(w)
			else
				checkWidget(name)
			end
			return ret
		end
	end
	init = false
	



	--intialize remote menu trigger
	WG.crude.OpenPath = function(path, pause) --Note: declared here so that it work in local copy
		if not settings.simpleSettingsMode then -- Menus are mostly empty in simpleSettingsMode
			MENU:Navigate({standard = true, path = path}, pause) -- FIXME should pause the game
		end
	end
	WG.crude.OpenWidgetOptions = function(widget, pause)
		MENU:Navigate({widget = widget})
	end
	WG.crude.OpenMultiPath = function(paths, pause)
		MENU:Navigate({paths = paths}, pause)
	end
	WG.crude.OpenCustomList = function(list, pause)
		MENU:Navigate({custom = list}, pause, nil, list) -- FIXME should pause the game
	end

	WG.crude.OpenPathToLabel = function(path, pause, labelName)
		MENU:Navigate({standard = true, path = path, label = labelName}, pause)
	end
	
	--intialize remote menu trigger 2
	WG.crude.ShowMenu = function()  --// allow other widget to toggle-up Epic-Menu. This'll enable access to game settings' Menu via click on other GUI elements.
		if MENU.win and MENU.win.hidden then
			MENU.win:Show()
		elseif not settings.show_crudemenu then
			ShowHideCrudeMenu()
		end
	end
	
	--intialize remote option fetcher
	WG.GetWidgetOption = function(wname, path, key)  -- still fails if path and key are un-concatenatable
		return (pathoptions and path and key and wname and pathoptions[path] and otget( pathoptions[path], wname .. key ) ) or {}
	end
	--initialize remote option setter
	WG.SetWidgetOption = function(wname, path, key, value)
		local option
		local dir = pathoptions[path]
		if dir then
			option = otget( pathoptions[path], wname..key )
		end
		if option then
			if option.checked ~= nil then
				option.checked = value
			end
			if option.value ~= nil then
				option.value = value
			end
			if option.color ~= nil then
				option.color = value
			end
			option:OnChange()
			-- option.OnChange({checked = value, value = value, color = value})
			-- Echo("currentPath, path is ", currentPath, path)
			if currentPaths[path] then
				requestRefresh = true
			end
		else
			Echo(sig .. 'Couldn\'t set option, no option found !', wname, path, pathoptions[path], key, value)
		end
	end
	WG.InitializeTranslation (LanguageChanged, GetInfo().name)
end
function WidgetLoadNotify(w, name)
	if w.options then
		PreIntegrateWidget(w)
	end
end
function WidgetPreInitNotify(w, name)
	if w.options then
		PreIntegrateWidget(w)
	end
end

function WidgetInitNotify(w, name)
	if w.options then
		IntegrateWidget(w, true)
		checkWidget(w)
	end
end
function WidgetRemoveNotify(w,name)
	if preintegrated[w] then
		IntegrateWidget(w, false)
		preintegrated[w] = nil
		checkWidget(name)
	end
	-- Echo('removed', name)
end
function widget:Shutdown()
	-- Restore widgethandler functions to original states
	if widgetHandler.OriginalRemoveWidget then
		widgetHandler.InsertWidget = widgetHandler.OriginalInsertWidget
		widgetHandler.OriginalInsertWidget = nil

		widgetHandler.RemoveWidget = widgetHandler.OriginalRemoveWidget
		widgetHandler.OriginalRemoveWidget = nil
		
		widgetHandler.ToggleWidget = widgetHandler.OriginalToggleWidget
		widgetHandler.OriginalToggleWidget = nil
	end
	

  if MENU.bar then
	-- screen0:RemoveChild(MENU.bar)
	MENU.bar:Dispose()
  end
  if MENU.win then
  	MENU.win:Dispose()
	-- screen0:RemoveChild(MENU.win)
  end

  RemoveAction("crudemenu")
  RemoveAction("crudesubmenu")
  RemoveAction("reloadepic")
 
  spSendCommands("unbind esc crudemenu")
end


function widget:GetConfigData()
	SaveKeybinds()
	return settings
end

function widget:SetConfigData(data)
	confLoaded = true
	if (data and type(data) == 'table') then
		if data.versionmin and data.versionmin >= EPIC_SETTINGS_VERSION then
			settings = data
		else
			for key, value in pairs(data) do
				settings[key] = value
			end
			settings.versionmin = EPIC_SETTINGS_VERSION
		end
	end

	-- set language. Needs to be done ASAP, before other widgets are even loaded!
	-- This is because option paths are done right on load and they can use translations.
	if not settings.lang or not flagByLang[settings.lang] then
		local flag = select(8, Spring.GetPlayerInfo(Spring.GetLocalPlayerID(), false)):lower()
		settings.lang = langByFlag[flag]
	end

	settings["epic_Settings/Misc_Show_Advanced_Settings"] = settings.showAdvanced

	WG.lang(settings.lang)

	if settings.music_volume then
		settings.config["epic_Settings/Audio_Music_Volume"] = settings.music_volume
		settings.music_volume = nil
	end

	WG.crude.SetMusicVolume(settings.config["epic_Settings/Audio_Music_Volume"] or MUSIC_VOLUME_DEFAULT)
	LoadKeybinds()
end

local function HandleScroll()
	if scrollTo then
		if not scrollToInit then
			scrollToInit = true
			return
		end
		if MENU.stackpanel then
			MENU.stackpanel:SetScrollPos(0,scrollTo.y, false, true)
		end
		scrollTo = false
		scrollToInit = false
	end
end

function widget:Update()
	if requestRefresh then
		local path = requestRefresh
		requestRefresh = false
		if MENU.win and MENU.win.visible then
			MENU:Navigate(eventObj, false)
		end
	end
	cycle = cycle%10 + 1
	if cycle == 1 then
		--Update clock, game timer and fps meter that show on menubar
		if ui.lbl_fps then
			ui.lbl_fps:SetCaption( 'FPS: ' .. Spring.GetFPS() )
		end
		if ui.lbl_clock then
			--local displaySeconds = true
			--local format = displaySeconds and "%H:%M:%S" or "%H:%M"
			local format = "%H:%M" --fixme: running game for over an hour pushes time label down
			--ui.lbl_clock:SetCaption( 'Clock\n ' .. os.date(format) )
			ui.lbl_clock:SetCaption( os.date(format) )
		end
	end
	
	if wantToReapplyBinding then --widget integration request ReApplyKeybinds()?
		ReApplyKeybinds() --unbind all action/key, rebind action/key
		wantToReapplyBinding = false
	end
	
	HandleScroll()
end

function widget:GameFrame(n)
	if ui.lbl_gtime then
		local gameOverFrame = Spring.GetGameRulesParam("MissionGameOver_frames")
		if gameOverFrame then
			ui.lbl_gtime:SetCaption(GetTimeString(gameOverFrame/gameSpeed))
			widgetHandler:RemoveWidgetCallIn("GameFrame", self)
		end
		if n%gameSpeed == 0 then
			ui.lbl_gtime:SetCaption(GetTimeString(n/gameSpeed))
		end
	end
end

function widget:PreGameTimekeeping(secondsUntilStart)
	if ui.lbl_gtime then
		ui.lbl_gtime:SetCaption("-"..GetTimeString(secondsUntilStart))
	end
end

local ignoreModKey = {
	[KEYSYMS.LCTRL] = true,
	[KEYSYMS.RCTRL] = true,
	[KEYSYMS.LALT] = true,
	[KEYSYMS.RALT] = true,
	[KEYSYMS.LSHIFT] = true,
	[KEYSYMS.RSHIFT] = true,
	[KEYSYMS.LMETA] = true,
	[KEYSYMS.RMETA] = true,
	[KEYSYMS.SPACE] = true,
}
function widget:KeyPress(key, modifier, isRepeat, label)
	if not get_key_bind_mod then
		if ignoreModKey[key] then
			return
		end
	end
	
	local modstring =
		(modifier.alt and 'A+' or '') ..
		(modifier.ctrl and 'C+' or '') ..
		(modifier.meta and 'M+' or '') ..
		(modifier.shift and 'S+' or '')
	
	--Set a keybinding
	if get_key then
		get_key = false
		ui.window_getkey:Dispose()
		if get_key_bind_mod or get_key_bind_without_mod or get_key_bind_with_any then
			-- get_key_bind_mod allows mod keys to be directly bound to an action.
			-- get_key_bind_without_mod gets the key bind without any modifiers.
			if get_key_bind_with_any then
				modstring = 'Any+'
			else
				modstring = ''
			end
			get_key_bind_mod = false
			get_key_bind_without_mod = false
			get_key_bind_with_any = false
		end

		if key == 0 and label:sub(0, 2) == '0x' then
			translatedkey = label
		else
			translatedkey = transkey[ keysyms[''..key]:lower() ] or keysyms[''..key]:lower()
			--local hotkey = {key = translatedkey, mod = modstring}
			translatedkey = translatedkey:gsub("n_", "") -- Remove 'n_' prefix from number keys.
		end
		local hotkey = modstring .. translatedkey
		
		Spring.Echo("Binding key code", key, "Translated", translatedkey, "Modifer", modstring)
		
		if key ~= KEYSYMS.ESCAPE then
			--otset( keybounditems, kb_action, hotkey )
			AssignKeyBindAction(hotkey, kb_action, true) -- param4 = verbose
			otset( keybounditems, kb_action, hotkey )
		end
		ReApplyKeybinds()
		
		if kb_path == currentPath and kb_button then
			local hotkeystring = GetHotkeyData(kb_path, kb_option)
			kb_button:SetCaption(hotkeystring)
			local hklength = math.max( hotkeystring:len() * 10, 20)
			if kb_control then
				kb_button:SetPos(nil, nil, hklength)
				kb_control._relativeBounds.right = hklength + 2 --room for hotkey button on right side
				kb_control:UpdateClientArea()
			end
		end
		
		if get_key_bind_notify_function then
			get_key_bind_notify_function()
			get_key_bind_notify_function = false
		end
		
		if WG.COFC_HotkeyChangeNotification then
			WG.COFC_HotkeyChangeNotification()
		end
		
		return true
	end
	
end




function ActionExitWindow()
	WG.crude.ShowMenu()
	MENU:Navigate({standard = true, path = submenu or ''}, false)
end

function ActionSubmenu(_, submenu)
	if MENU.win and MENU.win.visible then
		if not submenu or submenu == eventObj.path and eventObj.standard then
			MENU.win:Hide()
		else
			MENU:Navigate({standard = true, path = submenu}, false)
		end
	else
		WG.crude.ShowMenu()
		if not submenu then
			MENU:Navigate(eventObj, false)	
		else
			MENU:Navigate({standard = true, path = submenu}, false)
		end
	end
end

function ReloadEPIC()
	Spring.SendCommands('luaui disablewidget ' .. widget:GetInfo().name)
	Spring.SendCommands('luaui enablewidget ' .. widget:GetInfo().name)
	WG.crude.OpenPath("")
end

function ViewLobby()
	if Spring.SendLuaMenuMsg then
		Spring.Echo("SendLuaMenuMsg showLobby")
		if WG.ShowInterface then
			WG.ShowInterface()
		end
		if AllowPauseOnMenuChange(true) then
			spSendCommands("pause 1")
		end
		Spring.SendLuaMenuMsg("showLobby")
	end
end

function ActionMenu()
	ActionSubmenu()
end

function ToggleActionMenu()
	settings.show_crudemenu = not settings.show_crudemenu
	DisposeExitConfirmWindow()
	ShowHideCrudeMenu()
end

do --Set our prefered camera mode when first screen frame is drawn. The engine always go to default TA at first screen frame, so we need to re-apply our camera settings.
	if Spring.GetGameFrame() == 0 then  --we check if this code is run at midgame (due to /reload). In that case we don't need to re-apply settings (the camera mode is already set at gui_epicmenu.lua\AddOption()).
		local screenFrame = 0
		function widget:DrawScreen() --game event: Draw Screen
			if screenFrame >= 1 then --detect frame no.2
				local option = otget( pathoptions['Settings/Camera'], 'Settings/Camera'..'Camera Type' ) --get camera option we saved earlier in gui_epicmenu.lua\AddOption()
				
				option.OnChange(option) --re-apply our settings
				Spring.Echo("Epicmenu: Switching to " .. option.value .. " camera mode") --notify in log what happen.
				widgetHandler:RemoveWidgetCallIn("DrawScreen", self) --stop updating "widget:DrawScreen()" event. Note: this is a special "widgetHandler:RemoveCallIn" for widget that use "handler = true".
			end
			screenFrame = screenFrame+1
		end
	end
end
--]]
-------------------------------------------------------
-------------------------------------------------------
-- detect when user press ENTER to insert search term for searching option in epicmenu
function widget:TextCommand(command)
	if MENU.win and command:sub(1, 7) == "search:" then
		local userSearch = command:sub(8):lower()  --Reference: http://lua-users.org/wiki/StringLibraryTutorial
		Spring.Echo("EPIC Menu: searching \"" .. userSearch.."\"")
		MENU:Navigate({search = userSearch}, true) --remake the menu window. If search term is not "" the MakeSubWindowSearch(currentPath) will be called instead
		return true
	end
	return false
end



if f then
	f.DebugWidget(widget)
end


Echo('[HEL-K]: EPIC MENU LOADED')