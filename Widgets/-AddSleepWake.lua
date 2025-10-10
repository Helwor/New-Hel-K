function widget:GetInfo()
    return {
        name      = "Add Sleep/WakeUp",-- Add Sleep Wake must be called '-AddSleepWake.lua' in order to be loaded firstly and before '-OnWidgetState.lua'
        desc      = "Add smart Sleep and WakeUp call to widgetHandler, switching all callins of a widget",
        author    = "Helwor",
        date      = "April 2023",
        license   = "GNU GPL, v2",
        layer     = -10e38, 
        handler   = true,
        enabled   = true,
        api       = true,
    }
end
local Echo = Spring.Echo

local function GetRealHandler()
    local i, n = 0, true
    while n do
        i=i+1
        n,v=debug.getupvalue(widgetHandler.RemoveCallIn, i)
        if n=='self' and type(v)=='table' and v.LoadWidget then
            return v
        end
    end
end
local widgetWakeExceptions = {}
widgetHandler = GetRealHandler()
if not widgetHandler then
    return false
end
local EMPTY_TABLE = {}
local DEFAULT_EXCEPTION = {PlayerChanged = true}
local function Copy(t)
    local t2 = {}
    for k,v in pairs(t) do
        t2[k] = v
    end
    return t2
end
function widgetHandler:Sleep(w,exception)
    if type(w) == 'string' then
        w = widgetHandler:FindWidget(w)
    end

    if not w then 
        return false
    end
    if w.isSleeping then
        -- Echo('Widget ' .. w.whInfo.name .. ' is already sleeping.')
        return 
    end
    exception = exception or w.sleepException or DEFAULT_EXCEPTION
    for k,v in pairs(w) do
        if type(k)=='string' and type(v)=='function' then
            if not exception[k] and self[k .. 'List'] then
                local alreadyRemoved = true
                for i,listed_w in ipairs(self[k .. 'List']) do
                    if w == listed_w then
                        alreadyRemoved = false
                        break
                    end
                end
                if alreadyRemoved then
                    -- Echo('the callin',k,'of', w.whInfo.name,'was already removed')
                    widgetWakeExceptions[w] = widgetWakeExceptions[w] or {}
                    widgetWakeExceptions[w][k] = true
                else
                    self:RemoveWidgetCallIn(k,w)
                end
            end
        end
    end
    Echo(w.whInfo.name .. ' has been put to sleep.')
    w.isSleeping = true
    return w
end
function widgetHandler:Wake(w,exception)
    if type(w) == 'string' then
        w = widgetHandler:FindWidget(w)
    end
    if not w then
        return false
    end
    if not w.isSleeping then
        -- Echo('Widget ' .. w.whInfo.name .. " doesn't need to be woken up")
        return 
    end
    exception = exception or EMPTY_TABLE
    if widgetWakeExceptions[w] then
        exception = Copy(exception)
        for k,v in pairs(widgetWakeExceptions[w]) do
            if not exception[k] then
                -- Echo('not waking up',k,'for',w.whInfo.name)
                exception[k] = v
            end
        end
        widgetWakeExceptions[w] = nil
    end
    for k,v in pairs(w) do
        if type(k)=='string' and type(v)=='function' then
            if not exception[k] and self[k .. 'List'] then
                self:UpdateWidgetCallIn(k,w)
            end
        end
    end
    Echo(w.whInfo.name .. ' has woken.')
    w.isSleeping = false
    return w
end

------------------------------------
-- INSERTWIDGET COMMAND -- to try a reload of widget that did crash or that didnt exist at begining or to change the VFS mode of the widget toggling vanilla/modded
local WIDGET_DIRNAME = LUAUI_DIRNAME .. 'Widgets/'
local oriConfigLayout = widgetHandler.ConfigureLayout
function widgetHandler:ConfigureLayout(command)
    if command:find('insertwidget') == 1 then

        local basename, mode = unpack(command:sub(14):explode(' ')) -- is it something new? now explode
        Echo("basename is ", basename)
        if not basename or basename == '' then
            Echo('No basename found in command')
            return true
        end
        if not basename:find('%.lua$') then 
            basename = basename .. '.lua'
        end
        -- Echo("basename is ", basename)
        local filename = WIDGET_DIRNAME ..basename
        mode = mode and VFS[mode] or VFS.RAW_FIRST
        Echo("basename, mode, filename, VFS.FileExists( filename, mode) is ", basename, mode, filename, VFS.FileExists( filename, mode))
        if basename and VFS.FileExists( filename, mode) then
            for name, ki in pairs(self.knownWidgets) do
                if (ki.basename == basename) then
                    Echo('found in knownWidgets')
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


return false -- get persistent, don't appear/get handled by the widget list