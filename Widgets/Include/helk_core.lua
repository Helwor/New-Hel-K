	VFS.Include("LuaUI\\Widgets\\Include\\helk_core\\addon_handler_register_global_multi.lua")
	VFS.Include("LuaUI\\Widgets\\Include\\helk_core\\addon_handler_cmd_insertwidget.lua")
	VFS.Include("LuaUI\\Widgets\\Include\\helk_core\\addon_handler_sleep_wake.lua")

	local copy = function(t) local t2 = {} for k,v in pairs(t) do t2[k] = v end return t2 end
	VFS.Include("LuaUI\\Widgets\\Include\\helk_core\\lib_funcs.lua", copy(getfenv()) )
	f = WG.utilFuncs

	VFS.Include('LuaUI\\Widgets\\Include\\helk_core\\addon_gl.lua')

	local Echo = Spring.Echo

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
			local source = debug.getinfo(1).source
			-- local this_widget_pat = source:sub(source:find('[%w_]+%.lua')) .. '$'
			local this_widget_pat = 'api_apm_stats.lua' .. '$'
			-- Echo("this_widget_pat is ", this_widget_pat)
			local on_widget_state_pat = '-OnWidgetState.lua' .. '$'
			-- local add_sleep_wake_pat = '-AddSleepWake.lua' .. '$'
			local this_widget_index, on_widget_state_index , add_sleep_wake_index
			for i=1, #widgetFiles do
				
				local filename = widgetFiles[i]
				if not this_widget_index then
					if filename:find(this_widget_pat) then
						-- Echo('FOUND FILENAME',i,filename)
						this_widget_index = i
					end
				else
					-- if not add_sleep_wake_index then
					--  if filename:find(add_sleep_wake_pat) then
					--      -- Echo('FOUND FILENAME',i,filename)
					--      add_sleep_wake_index = i
					--  end
					-- end
					-- if not on_widget_state_index then
					-- 	if filename:find(on_widget_state_pat) then
					-- 		-- Echo('FOUND FILENAME',i,filename)
					-- 		on_widget_state_index = i
					-- 	end
					-- end
					--if --[[add_sleep_wake_index and]] on_widget_state_index then
						break
					--end
				end
			end
			if this_widget_index then
				-- local i = 1
				-- if add_sleep_wake_index then
				-- 	table.insert(widgetFiles, this_widget_index + i, table.remove(widgetFiles, add_sleep_wake_index))
				-- 	-- Echo('Insert sleep wake at ',this_widget_index + i)
				-- 	i = i + 1
				-- end
				-- if on_widget_state_index then
				-- 	Echo('Insert on widget state at ',this_widget_index + i)
				-- 	table.insert(widgetFiles, this_widget_index + i, table.remove(widgetFiles, on_widget_state_index))
				-- 	i = i + 1
				-- end
				for i, file in pairs(VFS.DirList("LuaUI\\Widgets\\Include\\helk_core\\widgets\\", "*.lua")) do
					table.insert(widgetFiles, this_widget_index + i, file)
				end
			end
		end
	end
