function widget:GetInfo()
  return {
    name      = "debug active command",
    desc      = "widget debugging",
    author    = "Helwor",
    date      = "august 2023",
    license   = "GNU GPL, v2 or later",
    layer     = -math.huge, 
    enabled   = false,  --  loaded by default?
    handler   = true,
    api       = true
  }
end
local Echo = Spring.Echo
local origSpSetActiveCommand = Spring.SetActiveCommand



-- local minimapFullProx = Spring.GetConfigInt("MiniMapFullProxy", 0)

-- local origSpIsAboveMiniMap
-- if minimapFullProx == 0 then
--     origSpIsAboveMiniMap = Spring.IsAboveMiniMap
--     Spring.IsAboveMiniMap = function(...)
--         if WG.MiniMapFaded then
--             return false
--         else
--             return origSpIsAboveMiniMap(...)
--         end
--     end
-- end

local spGetActiveCommand = Spring.GetActiveCommand
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spIsSelectionBoxActive = Spring.IsSelectionBoxActive
local Echo = Spring.Echo

local spGetGameSeconds = Spring.GetGameSeconds
local spGetActiveCommand = Spring.GetActiveCommand
local spGetMouseState = Spring.GetMouseState
local spGetModKeyState   = Spring.GetModKeyState
local spGiveOrder = Spring.GiveOrder
local osclock = os.clock
local traceback = debug.traceback
local concat = table.concat

include('keysym.h.lua')


local CMD_ATTACK = CMD.ATTACK
local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")
local CMD_RAW_MOVE = customCmds.RAW_MOVE
customCmds = nil

local f = WG.utilFuncs





function widget:UnitCommand(id,defid,team,cmd,params)
    -- Echo("id,defid,cmd,params is ", id,defid,team,cmd,unpack(params))
end


-- disable the selection box until we travel some distance with the mouse
-- local single_selecting = false
-- local box_select = false
-- local boxX, boxY = 0, 0
-- local POINT_SEL_LEEWAY = 150
-- local selTravel = 0
-- local Screen0
-- function widget:MousePress(mx, my, button)
--     if not Screen0 then
--         Screen0 = WG.Chili and WG.Chili.Screen0
--         if not Screen0 then
--             return
--         end
--     end
--     if button == 1 and not Screen0:IsAbove(mx,my) and  spGetActiveCommand() == 0 then
--         Echo('single selecting', os.clock())
--         single_selecting  = true
--         selTravel = 0
--         boxX, boxY = mx, my
        
--     end
--     -- 
-- end
-- function widget:Update(dt)
--     if single_selecting then
--         local mx, my, lmb, mmb, rmb, outsideSpring = spGetMouseState()
--         if not lmb or rmb or outsideSpring then
--             single_selecting = false
--             selTravel = 0
--             if selbox_disabled then
--                 Echo('reenable sel box')
--                 Spring.SetBoxSelectionByEngine(true, false)
--                 selbox_disabled = false
--             end
--             Echo('end single selecting', os.clock())

--         elseif not WG.PreSelection_IsSelectionBoxActive() then
--             -- skip
--         else
--             selTravel = selTravel + ((mx - boxX)^2 + (my - boxY)^2)^0.5
--             boxX, boxY = mx, my
--             if selTravel > POINT_SEL_LEEWAY then
--                 single_selecting = false
--                 selTravel = 0
--                 if selbox_disabled then
--                     Echo('reenable sel box')
--                     Spring.SetBoxSelectionByEngine(true, false)
--                     selbox_disabled = false
--                 end
--                 Echo('end single selecting', os.clock())
--             elseif not selbox_disabled then
--                 Echo('disable sel box')
--                 selbox_disabled = true
--                 Spring.SetBoxSelectionByEngine(false, false)
--             end
--         end    
--     end
-- end




local FormatTime = function(n)
    local h = math.floor(n/3600)
    h = h>0 and h
    local m = math.floor( (n%3600) / 60 )
    m = (h or m>0) and m
    local s = ('%.3f'):format(n%60)
    return (h and h .. ':' or '') .. (m and m .. ':' or '') .. s
end

---- debugging when spSetActiveCommand is getting spammed, except when it is from build commmand ------
local function SetAcomEcho()
    local time = osclock()
    local count = 0
    local txt = ''

    function Spring.SetActiveCommand(n, line)
        line = line or ''
        local now = osclock()
        local comID, num, cmd, comname
        local ignore = true
        if now - time  < 0.05 then
            count = count + 1
            comID, cmd, num,  comname = spGetActiveCommand()
            -- plate is spammed from vanilla ZK when using the plate hotkey/button until the cursor is in the area around the given fac (maybe some dirty code ?)
            -- ignore = cmd and cmd < 0 or comname == 'plate'
        end
        if not ignore then
            -- local cur = select(4,Spring.GetActiveCommand())
            local cur
            if comname then
                cur = concat({comID, cmd, num, comname}, ', ')
            else
                cur = comID
            end

            txt = txt .. '\n' .. 'interval: ' .. now - time .. ' wanted Acom: ' .. n .. 'current: ' .. cur
                -- .. '\n' .. traceback():sub(1,30)
            if count > 5 then 
                Echo(traceback())
                Echo('SetActiveCommand Getting spammed !', txt)
                Echo('game time:', spGetGameSeconds())
                count = 0
                txt = ''
            end
        else
            count = 0
            txt = ''
        end
        time = now
        return origSpSetActiveCommand(n)
    end
end

local DP

local AComHistory = {}
local function SetAcomHistory()
    local time = osclock()
    local count = 0
    function Spring.SetActiveCommand(n, comment)
        local shift = select(4,spGetModKeyState())
        local txt = concat(
            {comment and '\nCOMMENT: ' .. tostring(comment) or ''
            ,'\n'..FormatTime(spGetGameSeconds())
            ,n or 'nil'
            ,shift and 'shift is held' or 'no shift'
            ,'DP status ' .. tostring(DP and DP.dstatus)
            ,'current command : ' .. tostring(spGetActiveCommand())
            ,debug.traceback()
            }, '\n')
        if count == 10 then
            table.remove(AComHistory,1)
        else
            count = count + 1
        end
        AComHistory[count] = txt
        return origSpSetActiveCommand(n)
    end
end
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount
function widget:MousePress(mx, my, button)
    -- Echo("mx,my, button,minimapFullProx is ", mx,my, button,minimapFullProx)
    -- if minimapFullProx == 0 then
    --     if origSpIsAboveMiniMap(mx,my) and WG.MiniMapFaded then
    --         -- if button == 3 and spGetSelectedUnitsCount() == 0 then
    --         --     return true
    --         -- end
    --         -- for k,v in pairs(Spring) do
    --         --     if k:lower():match('selection') then
    --         --         Echo(k,v)
    --         --     end
    --         -- end
    --         -- Echo("Spring.GetBoxSelectionByEngine() is ", Spring.GetBoxSelectionByEngine())
    --         -- Echo("Spring.GetBoxSelection() is ", Spring.GetSelectionBox())

    --     end
    -- end
end
function widget:KeyPress(key,mods, isRepeat)
    if key == 105 and mods.alt then -- alt + i
        if AComHistory[1] then
            local len = #AComHistory
            Echo('debug Acom',FormatTime(spGetGameSeconds())) 
            -- for i=math.max(len-10,1), len do    --- from end-10 to end
            for i=len, math.max(len-10, 1), -1 do --- from end to end-10
                Echo(AComHistory[i])
                Echo('------')
            end
        end
    end
end
-- function widget:DefaultCommand(type, id, engineCmd)
--     Echo(type,id, engineCmd,"spGetActiveCommand() is ", spGetActiveCommand())

-- end
function WidgetInitNotify(w, name, preloading)
    if name == 'Draw Placement' then
        DP = w
    end
end
function widget:Initialize()
    DP = widgetHandler:FindWidget('Draw Placement')
    SetAcomHistory()
    -- SetAcomEcho()
end
function widget:Shutdown()
    Spring.SetActiveCommand = origSpSetActiveCommand
    if origSpIsAboveMiniMap then
        Spring.IsAboveMiniMap = origSpIsAboveMiniMap
    end
end


f.DebugWidget(widget)