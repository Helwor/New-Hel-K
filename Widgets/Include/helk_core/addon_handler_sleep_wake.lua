-- name      = "Sleep/WakeUp widgetHandler Add On",-- Add Sleep Wake must be called '-AddSleepWake.lua' in order to be loaded firstly and before '-OnWidgetState.lua'
-- desc      = "Add smart Sleep and WakeUp call to widgetHandler, switching all callins of a widget",
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
    Echo('FAILED TO IMPLEMENT SLEEP/WAKE -> NO REAL WIDGETHANDLER FOUND')
    return false
end
widgetHandler = wh

local widgetWakeExceptions = {}

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

Echo('[Hel-K]: Successfully implemented Sleep/Wake Handler functions.')
