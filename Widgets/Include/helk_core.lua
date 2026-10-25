-- Author Helwor
-- license GNU GPL v2 or later
local WIDGET_DIR = "LuaUI/Widgets/"
local UTILITIES_DIR = "LuaUI/Utilities/"
local HELK_CORE_DIR = WIDGET_DIR .. "Include/helk_core/"
local sig = '[Hel-K]: '

local apiOrder = {
	'api_on_widget_state.lua',
	'api_view_changed.lua',
	'api_unit_data.lua',
	'api_unit_handler.lua',
	'api_visible_units.lua',
	'api_command_tracker.lua',
	'api_click_handler.lua',
	'api_selection_handler.lua',
	'api_clamp_mouse_to_world.lua',
	'api_my_font.lua',
	'api_code_handler.lua',
	'api_log_handler.lua',
	'api_my_zones.lua',
	'api_load_ai.lua',
	'addon_chili.lua',
	'api_draw_utils.lua',
	'api_range_renderer_gl4.lua',
	'api_ground_decal_drawer.lua',
}

local importantWidgets = {
	'gui_epicmenu.lua',
	'api_chili.lua',
	'gui_chili_selections_and_cursortip.lua',
	'api_preselection.lua',
	'api_chili_widgetselector.lua',
	'api_shared_functions.lua',
	'gui_chili_integral_menu.lua',
	'camera_cofc.lua',
	'unit_healthbars.lua',
}

local includes = {
	'aim_from_pieces.lua',
	'aim_from_pieces_2.lua',
	'aim_from_poses.lua',
	'api_debug_tools.lua',
	'prefab_window.lua',
	'weap_ranges.lua',
	'win_table_editer.lua',
}

local function GetRealHandler()
	if widgetHandler.LoadWidget then
		return widgetHandler
	else
		local i, n = 0, true
		while n do
			i = i + 1
			n, v = debug.getupvalue(widgetHandler.RemoveCallIn, i)
			if n == 'self' and type(v) == 'table' and v.LoadWidget then
				return v
			end
		end
	end
end
local function GetLocal(func, searchname)
	local i = 1
	local found
	while i < 10 do
		i = i + 1
		if debug.getinfo(i,'f').func == func then
			found = i
			break
		end
	end
	if not found then
		return
	end
	local j, name, value = 0, true, nil 
	while name do
		j = j + 1
		name, value = debug.getlocal(found, j)
		if name == searchname then
			return value, j
		end
	end
end

local function GetUpvalue(func, searchname)
	local i = 1
	local found
	while i < 10 do
		i = i + 1
		if debug.getinfo(i,'f').func == func then
			found = i
			break
		end
	end
	if not found then
		return
	end
	local j, name, value = 0, true, nil 
	while name do
		j = j + 1
		name, value = debug.getupvalue(func, j)
		if name == searchname then
			return value, j
		end
	end
end

local copy = function(t) local t2 = {} for k,v in pairs(t) do t2[k] = v end return t2 end
-------

Echo = Spring.Echo
realHandler = GetRealHandler()
if not realHandler then
	Echo(sig .. 'FAILED TO INSTALL, Couldn\'t get realHandler')
	return
end
local widgetFiles = GetLocal(realHandler.Initialize, 'widgetFiles')
-- Echo('SOURCE',source)
-- for i, v in ipairs(widgetFiles) do
--  Spring.Echo('#'..i, v)
-- end
if not widgetFiles then
	Echo(sig .. 'FAILED TO INSTALL, Couldn\'t retrieve widgetFiles')
	return
end
local source = debug.getinfo(3).source
local this_widget_file = source:sub(source:find('[%w_]+%.lua'))
local this_widget_pat = this_widget_file .. '$'
local this_widget_index
local this_widget_name = widget.GetInfo().name
for i=1, #widgetFiles do
	if widgetFiles[i]:find(this_widget_pat) then
		this_widget_index = i
		break
	end
end
-------WORK AROUND Verify ourself local widgets due to cawidgets.lua not respecting it
local localWidgetsFirst = false
local localWidgets = false
local CONFIG_FILENAME    = LUAUI_DIRNAME .. 'Config/ZK_data.lua'
if VFS.FileExists(CONFIG_FILENAME) then 
	local cadata = VFS.Include(CONFIG_FILENAME)
	if cadata and cadata["Local Widgets Config"] then
		localWidgetsFirst = cadata["Local Widgets Config"].useLocalWidgetsFirst
		localWidgets = cadata["Local Widgets Config"].useLocalWidgets
	end
end
local wantedVFSMODE, wantedVFSNAME
wantedVFSNAME = localWidgetsFirst and "RAW_FIRST"
wantedVFSNAME = wantedVFSNAME or localWidgets and "ZIP_FIRST"
wantedVFSNAME = wantedVFSNAME or "ZIP"
if wantedVFSNAME == "ZIP_FIRST" then
	Echo(sig .. 'WARN: wanted VFSMODE forced to VFS.RAW_FIRST instead of ZIP_FIRST, as it is needed for Hel-K to run correctly')
	wantedVFSNAME = "RAW_FIRST"
end
wantedVFSMODE = VFS[wantedVFSNAME]
-- verify the current VFS used by cawidgets.lua
local VFSMODE, upv_index = GetUpvalue(realHandler.Initialize, 'VFSMODE')
if not VFSMODE then
	Echo(sig .. 'ERROR: Couldn\'t find the current VFSMODE!')
	if not localWidgets then
		Echo(sig .. 'ERROR: User set local widgets to NOT be loaded but we cannot change it, HEL-K WILL BE LOADED ANYWAY')
	end
elseif VFSMODE ~= wantedVFSMODE then
	debug.setupvalue(realHandler.Initialize, upv_index, wantedVFSMODE)
	VFSMODE = GetUpvalue(realHandler.Initialize, 'VFSMODE')
	if VFSMODE == wantedVFSMODE then
		Echo(sig .. 'VFSMODE correctly set to ' .. wantedVFSNAME)
	else
		local modeName
		for k, v in pairs(VFS) do
			if v == VFSMODE then
				modeName = k
			end
		end
		Echo(sig .. 'ERROR: Couldn\'t change the current VFSMODE, staying on ' .. modeName)
	end
end
if VFSMODE == VFS.ZIP then
	Echo(sig .. 'User doesn\'t want local widgets, aborting installation process')
	-- removing the local files that shouldnt be in the list
	local i, filename = this_widget_index or 1, widgetFiles[1]
	local count = 0
	while filename do
		if not VFS.FileExists(filename, VFS.ZIP) then
			count = count + 1
			table.remove(widgetFiles, i)
		else
			i = i + 1
		end
		filename = widgetFiles[i]
	end
	Echo(sig .. 'Removed '.. count ..' purely local widgets from the to-be-loaded widget list.')
	Echo(sig .. 'Replacing function VFS.Include to prevent accidentally loading annex local files')
	VFS.oriInclude = VFS.Include
	VFS.Include = function(filename, env, mode, ...)
		if not mode then
			mode = VFS.DEF_MODE
		end
		local i_stack
		if not env then
			i_stack = 3 -- 3+ in stack where 1 is pcall env, and 2 is here
			local success
			while not env and i_stack < 50 do
				success, env = pcall(getfenv, i_stack)
				if success then
					break
				else 
					env = nil
				end
				i_stack = i_stack + 1
			end
		else
			i_stack = 'custom env' 
		end
		local absfile = filename:gsub('\\', '/')
		if mode == VFS.RAW_FIRST and VFS.FileExists(filename, VFS.ZIP) and (absfile:find(WIDGET_DIR) or absfile:find(UTILITIES_DIR)) then
			-- Echo('mode changed for ', filename, env, mode, 'env stack #', i_stack, ...)
			mode = VFS.ZIP
		else
			-- Echo('normal include ', filename, env, mode, 'env stack #', i_stack, ...)
		end
		return VFS.oriInclude(filename, env, mode, ...)
	end
	Echo(sig .. 'Installation process cancelled.')
	return
end
---------
Echo(sig .. 'Installing at ' .. tostring(this_widget_file) .. '\'s loading.')

VFS.Include(HELK_CORE_DIR .. "def_shortcuts.lua")
VFS.Include(HELK_CORE_DIR .. "sign_order.lua")
VFS.Include(HELK_CORE_DIR .. "addon_handler_register_global_multi.lua")
VFS.Include(HELK_CORE_DIR .. "addon_handler_cmd_insertwidget.lua")
VFS.Include(HELK_CORE_DIR .. "addon_handler_sleep_wake.lua")
VFS.Include(HELK_CORE_DIR .. "addon_handler_console_catcher.lua")
VFS.Include(HELK_CORE_DIR .. "addon_handler_pong.lua")
VFS.Include(HELK_CORE_DIR .. "keycodes.lua")


VFS.Include(HELK_CORE_DIR .. "lib_funcs.lua", copy(getfenv()) )
f = WG.utilFuncs

VFS.Include(HELK_CORE_DIR .. "addon_gl.lua")





if this_widget_index then
	local function GetLuaFileName(file)
	    local s, e = file:find('[/\\][^/\\]+%.lua$')
	    return file:sub(s+1, e)
	end

	local files = {}
	for i, file in ipairs(widgetFiles) do
		local filename = GetLuaFileName(file)
		if filename then
			files[filename] = true
		end
	end
	local off = 0
	local anyMissing = false
	for i, filename in ipairs(apiOrder) do
		local file = HELK_CORE_DIR .. "widgets/" .. filename
		if VFS.FileExists(file) then
			table.insert(widgetFiles, this_widget_index + 1 + off, file)
			Echo(sig .. 'Inserted widget ' .. filename .. ' at #' .. this_widget_index + 1 + off)
			off = off + 1
		else
			Echo(sig .. 'WARN IMPORTANT API MISSING: ' .. file)
			anyMissing = true
		end
	end
	if this_widget_index > 1 then
		local unsortedWidgets = GetLocal(widgetHandler.Initialize, 'unsortedWidgets')
		local function IsLocalVersionLoaded(file)
			local filename = GetLuaFileName(file)
			for i, w in ipairs(unsortedWidgets) do
				if not w.whInfo.fromZip and GetLuaFileName(w.whInfo.filename) == filename then
					return true
				end
			end

		end
		Echo('[HEL-K]: There have already been ' .. (this_widget_index - 1) .. ' widgets loaded before this one, reinserting the failed local ones')
		for i = 1, this_widget_index-1 do
			local file = widgetFiles[i]
			if VFS.FileExists(file, VFS.RAW) and not IsLocalVersionLoaded(file) then
				if GetLuaFileName(file) ~= this_widget_file then
					local index = this_widget_index + 1 + off
					Echo('Local widget ' .. GetLuaFileName(file) .. ' seemingly crashed before Hel-K, reinserting it at #' .. index)
					table.insert(widgetFiles, index, file)
					off = off + 1
				end
			end
		end
	end


	-- for i, file in ipairs(VFS.DirList(HELK_CORE_DIR .. "widgets/", "*.lua")) do
	-- 	local filename = GetLuaFileName(file)
	-- 	if filename then
	-- 		local index = files[filename]
	-- 		if index then
	-- 			if index > this_widget_index then -- not replacing already loaded widget
	-- 				widgetFiles[index + off] = file
	-- 				Echo(sig .. 'Replaced widget origin ' .. filename .. ' at #' .. index + off)
	-- 			end
	-- 		else
	-- 			table.insert(widgetFiles, this_widget_index + 1 + off, file)
	-- 			Echo(sig .. 'Inserted widget ' .. filename .. ' at #' .. this_widget_index + 1 + off)
	-- 			off = off + 1
	-- 		end
	-- 	end					
	-- end
else
	Echo('[Hel-K] FATAL: couldn\'t get the current widget\'s index')
	return
end



for i, filename in ipairs(includes) do
	local file = WIDGET_DIR .. "Include/" .. filename
	if not VFS.FileExists(file, VFS.RAW) then
		Echo(sig .. 'MISSING FILE: ' .. file)
	end
end
for i, filename in ipairs(importantWidgets) do
	local file = WIDGET_DIR .. filename
	if not VFS.FileExists(file, VFS.RAW) then
		Echo(sig .. 'IMPORTANT FILE MISSING: ' .. file)
	end
end



