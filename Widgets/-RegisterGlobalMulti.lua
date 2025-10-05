function widget:GetInfo()
    return {
        name      = "RegisterGlobalMulti",
        desc      = "Allow CallIn registered in handler globals to call back more than one widget",
        author    = "Helwor",
        date      = "Oct 2023",
        license   = "GNU GPL, v2",
        layer     = -10e38, 
        handler   = true,
        enabled   = true,
        api       = true,
        alwaysStart = true,
    }
end
local Echo = Spring.Echo
local sig = '['..widget:GetInfo().name..']: '

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

widgetHandler = GetRealHandler()
if not widgetHandler then
    Echo(sig .. "couldn't get the real handler.")
    return false
end
-------------
local _G = getfenv(widgetHandler.RegisterGlobal)._G


if not _G then
    Echo(sig .. "couldn't get _G.")
    return false
end

VFS.Include("LuaUI/callins.lua", nil, VFS.Game) -- getting CallInsMap

-------------
_G.multiOwners = {}
_G.multiFunc = {}

local function Distribute(name,...)
    local funcs = _G.multiFunc[name]
    for i, owner in ipairs(_G.multiOwners[name]) do
        -- Echo("calling ", name, owner and owner.GetInfo and owner.GetInfo().name, funcs[owner])
        if funcs[owner](...) then
            return true
        end
    end
end

local function CreateMulti(name)
    -- Echo('Create Multi for', name)
    _G[name] = function(...) return Distribute(name,...) end
    _G.multiOwners[name] = {}
    _G.multiFunc[name] = {}
    widgetHandler.globals[name] = _G.multiOwners[name] 
end
local function OwnerName(owner)
    return type(owner) == 'table' and owner.GetInfo and owner.GetInfo().name or 'no_name:' .. tostring(owner)
end
function widgetHandler:RegisterGlobal(owner, name, value, override)
    if not (name and owner) then
        return false
    end
    -- if CallInsMap[name] then
    --     Echo(sig .. 'widget ' .. OwnerName(owner) .. ' Trying to register a Call-In ' .. tostring(name))
    --     return false
    -- end
    if type(value) ~= 'function' then
        if _G[name] or self.globals[name] then
            return false
        end

        _G[name] = value
        self.globals[name] = owner
        return true
    else
        if _G[name] then
            if not self.globals[name] then -- global might exist and not being owned by any widget but by the system
                Echo(sig .. 'widget ' .. OwnerName(owner) .. ' Trying to register an already existing global ' .. tostring(name) .. " which doesn't have any owner (system?)")
                return false
            elseif type(_G[name]) ~= 'function' then
                Echo(sig .. 'widget ' .. OwnerName(owner) .. ' Trying to override a non-function already existing global ' .. tostring(name) .. " by a function")
                return false
            end
        end
        if override or not _G[name] then
            CreateMulti(name)
        elseif not _G.multiOwners[name] then -- ?? the multiOwner array hasnt been created, RegisterGlobal must have been used before we modify it
            local cur_owner = self.globals[name]
            local cur_func = _G[name]
            CreateMulti(name)
            table.insert(_G.multiOwners[name], cur_owner)
            _G.multiFunc[name][cur_owner] = cur_func
        end
        table.insert(_G.multiOwners[name], owner)
        -- Echo(sig .. 'inserting in ', name,owner and owner.GetInfo and owner.GetInfo().name,'total',#_G.multiOwners[name])
        _G.multiFunc[name][owner] = value
        return true
    end
end


function widgetHandler:DeregisterGlobal(owner, name)
    if name == nil or owner == nil then
        return false
    elseif not _G.multiOwners[name] then
        if ((self.globals[name] and (self.globals[name] ~= owner))) then
            return false
        end
        _G[name] = nil
        self.globals[name] = nil
        return true
    else
        for i, thisowner in pairs(_G.multiOwners[name]) do
            if thisowner == owner then
                table.remove(_G.multiOwners[name], i)
                _G.multiFunc[name][owner] = nil
                -- remove the multi if empty
                if not _G.multiOwners[name][1] then
                    _G[name] = nil
                    _G.multiOwners[name] = nil
                    _G.multiFunc[name] = nil
                    self.globals[name] = nil
                end
                return true
            end
        end
        return false
    end
end


function widgetHandler:SetGlobal(owner, name, value)
    if name == nil or owner == nil then
        return false
    else
        if not _G.multiOwners[name] then
            if ((self.globals[name] ~= owner)) then
                return false
            end
            if type(value) == 'function' then
                return widgetHandler:RegisterGlobal(owner, name, value, true)
            else
                _G[name] = value
                return true
            end
        else
            if type(value) == 'function' then
                -- replace func
                for i, thisowner in ipairs(_G.multiOwners[name]) do
                    if thisowner == owner then
                        _G.multiFunc[name][owner] = value
                        return true
                    end
                end
            else
                -- remove multi if any
                widgetHandler:DeregisterGlobal(owner, name)
                -- register normal
                return widgetHandler:RegisterGlobal(owner, name, value)
            end
        end
    end
end


function widgetHandler:RemoveWidgetGlobals(owner)
    local count = 0
    for name, o in pairs(self.globals) do
        if _G.multiOwners[name] then
            if widgetHandler:DeregisterGlobal(owner, name) then
                count = count + 1
            end
        elseif (o == owner) then
            _G[name] = nil
            self.globals[name] = nil
            count = count + 1
        end
    end
    return count
end


