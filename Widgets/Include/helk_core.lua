	local WIDGET_DIR = "LuaUI\\Widgets\\"
	local HELK_CORE_DIR = WIDGET_DIR .. "\\Include\\helk_core\\"
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


	local Echo = Spring.Echo


	VFS.Include(HELK_CORE_DIR .. "addon_handler_register_global_multi.lua")
	VFS.Include(HELK_CORE_DIR .. "addon_handler_cmd_insertwidget.lua")
	VFS.Include(HELK_CORE_DIR .. "addon_handler_sleep_wake.lua")
	Echo('OK?')
	VFS.Include(HELK_CORE_DIR .. "keycodes.lua")

	local copy = function(t) local t2 = {} for k,v in pairs(t) do t2[k] = v end return t2 end
	VFS.Include(HELK_CORE_DIR .. "lib_funcs.lua", copy(getfenv()) )
	f = WG.utilFuncs

	VFS.Include(HELK_CORE_DIR .. "addon_gl.lua")


	local function GetRealHandler()
		if widgetHandler.LoadWidget then
			return widgetHandler
		else
			local i, n = 0, true
			while n do
				i=i+1
				n,v=debug.getupvalue(widgetHandler.RemoveCallIn, i)
				if n=='self' and type(v)=='table' and v.LoadWidget then
					return v
				end
			end
		end
	end
	local realHandler = GetRealHandler()
	if realHandler then
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
					return value
				end
			end
		end
		local widgetFiles = GetLocal(realHandler.Initialize, 'widgetFiles')
		-- Echo('SOURCE',source)
		-- for i, v in ipairs(widgetFiles) do
		--  Spring.Echo('#'..i, v)
		-- end
		if widgetFiles then

			-- local source = debug.getinfo(1).source
			-- local this_widget_pat = source:sub(source:find('[%w_]+%.lua')) .. '$'
			local this_widget_pat = 'api_apm_stats.lua' .. '$'
			local this_widget_index, on_widget_state_index , add_sleep_wake_index
			for i=1, #widgetFiles do
				if widgetFiles[i]:find(this_widget_pat) then
					-- Echo('FOUND FILENAME',i,filename)
					this_widget_index = i
					break
				end
			end
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
					local file = HELK_CORE_DIR .. "widgets\\" .. filename
					if VFS.FileExists(file) then
						table.insert(widgetFiles, this_widget_index + 1 + off, file)
						Echo('[Hel-K]: Inserted widget ' .. filename .. ' at #' .. this_widget_index + 1 + off)
						off = off + 1
					else
						Echo('[Hel-K]: IMPORTANT FILE MISSING: ' .. file)
						anyMissing = true
					end
				end


				-- for i, file in ipairs(VFS.DirList(HELK_CORE_DIR .. "widgets\\", "*.lua")) do
				-- 	local filename = GetLuaFileName(file)
				-- 	if filename then
				-- 		local index = files[filename]
				-- 		if index then
				-- 			if index > this_widget_index then -- not replacing already loaded widget
				-- 				widgetFiles[index + off] = file
				-- 				Echo('[Hel-K]: Replaced widget origin ' .. filename .. ' at #' .. index + off)
				-- 			end
				-- 		else
				-- 			table.insert(widgetFiles, this_widget_index + 1 + off, file)
				-- 			Echo('[Hel-K]: Inserted widget ' .. filename .. ' at #' .. this_widget_index + 1 + off)
				-- 			off = off + 1
				-- 		end
				-- 	end					
				-- end
			end
		else
			Echo('[Hel-K]: FAILED TO INSTALL, Couldn\'t retrieve widgetFiles')
			return
		end
		for i, filename in ipairs(includes) do
			local file = WIDGET_DIR .. "Include\\" .. filename
			if not VFS.FileExists(file, VFS.RAW) then
				Echo('[Hel-K]: MISSING FILE: ' .. file)
			end
		end
		for i, filename in ipairs(importantWidgets) do
			local file = WIDGET_DIR .. filename
			if not VFS.FileExists(file, VFS.RAW) then
				Echo('[Hel-K]: IMPORTANT FILE MISSING: ' .. file)
			end
		end
	end
