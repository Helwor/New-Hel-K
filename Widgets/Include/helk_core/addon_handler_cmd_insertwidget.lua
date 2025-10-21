-- name      = "/luaui insertwidget command  widgetHandler Add On",
-- desc      = "to try a reload of widget that did crash or that didnt exist at begining or to change the VFS mode of the widget toggling vanilla/modded",
-- author    = "Helwor",
-- date      = "April 2023",
-- license   = "GNU GPL, v2",

local Echo = Spring.Echo

local function GetRealHandler()
	if widgetHandler.LoadWidget then
		return widgetHandler
	end
	local i, n = 0, true
	while n do
		i=i+1
		n,v=debug.getupvalue(widgetHandler.RemoveCallIn, i)
		if n=='self' and type(v)=='table' and v.LoadWidget then
			return v
		end
	end
end

local wh = GetRealHandler()
if not wh then
	Echo('FAILED TO IMPLEMENT INSERTWIDGET COMMAND -> NO REAL WIDGETHANDLER FOUND')
	return false
end
widgetHandler = wh

local WIDGET_DIRNAME = LUAUI_DIRNAME .. 'Widgets/'
local oriConfigLayout = widgetHandler.ConfigureLayout
function widgetHandler:ConfigureLayout(command)
	if command:find('insertwidget') == 1 then
		local basename, mode = unpack(command:sub(14):explode(' '))
		if not basename or basename == '' then
			Echo('No basename found in command')
			return true
		end
		if not basename:find('%.lua$') then 
			basename = basename .. '.lua'
		end
		local filename = WIDGET_DIRNAME ..basename
		mode = mode and VFS[mode] or VFS.RAW_FIRST
		if basename and VFS.FileExists( filename, mode) then
			for name, ki in pairs(self.knownWidgets) do
				if (ki.basename == basename) then
					local newWantedMode = 
						ki.fromZip and (
							mode == VFS.RAW
							or mode == VFS.RAW_ONLY
							or mode == VFS.RAW_FIRST and VFS.FileExists( filename, VFS.RAW)
						)
						or (
							mode == VFS.ZIP
							or mode == VFS.ZIP_ONLY
							or mode == VFS.ZIP_FIRST and VFS.FileExists( filename, VFS.ZIP)
						)
					if newWantedMode then
						local w
						if ki.active then
							Echo('Removing current version of widget ' .. name .. ' to load it in the wanted VFS mode')
							self:DisableWidget(name)
						else
							Echo('Inserting widget' .. name ..  'with the new mode')
						end
						local oriLoadWidget = self.LoadWidget
						self.LoadWidget = function (self, filename, _VFSMODE)
							self.knownWidgets[name] = nil -- force a refresh of knownInfo
							self.knownCount = self.knownCount - 1
							w = oriLoadWidget(self, filename, mode)
							if not w then
								Echo('Failed to load ', name, ' with mode', mode)
								ki.active = false
								self.knownWidgets[name] = ki
								self.knownCount = self.knownCount + 1
							end
							return w
						end
						self:EnableWidget(name)

						self.LoadWidget = oriLoadWidget
						return true
					else
						Echo('The wanted widget ' .. name .. ' is already known on the wanted mode', mode, ' enabling it.')
						self:EnableWidget(name)
						return true
					end
				end
			end

			Echo('Inserting new widget',filename, mode)
			local w = self:LoadWidget(filename, mode)
			if w then
				self:InsertWidget(w)
				self:SaveOrderList()
			else
				local inactive
				for name, ki in pairs(self.knownWidgets) do
					if (ki.basename == basename) then
						if not ki.active then
							Echo('widget is not currently active but available')
							return true
						end
					end
				end
				Echo('couldnt load widget')
			end
			return true
		else
			Echo('requested file cannot be found',filename,mode, VFS.FileExists(filename, mode))
			return true
		end
	end

	return oriConfigLayout(widgetHandler, command)
end

Echo('[Hel-K]: Successfully implemented /luaui insertwidget command.')