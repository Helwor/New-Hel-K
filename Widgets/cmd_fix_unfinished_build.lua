--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    unit_smart_nanos.lua
--  brief:   Enables auto reclaim & repair for idle turrets
--  author:  Owen Martindell
--
--  Copyright (C) 2008.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "FinishIt",
    desc      = "Finish this goddamn build !",
    author    = "Helwor",
    date      = "dec 2022",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = false,  --  loaded by default?
    handler   = true,
  }
end
-- speeds up
local Echo = Spring.Echo
local spGetUnitHealth = Spring.GetUnitHealth
local spValidUnitID = Spring.ValidUnitID
local spGetUnitIsDead = Spring.GetUnitIsDead
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local CMD_INSERT = CMD.INSERT
local CMD_REPAIR = CMD.REPAIR
local CMD_RECLAIM = CMD.RECLAIM
local CMD_OPT_SHIFT = CMD.OPT_SHIFT
local CMD_OPT_ALT = CMD.OPT_ALT
local INSERT_PARAMS = {0, CMD_REPAIR, CMD_OPT_SHIFT}
local spGetCommandQueue = Spring.GetCommandQueue
local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
local osclock = os.clock()
---------- updating teamID
local myTeamID
local myPlayerID = Spring.GetMyPlayerID()
function widget:PlayerChanged(playerID)
    if playerID == myPlayerID then
        myTeamID = Spring.GetMyTeamID()
    end
end

----------
local myDrawOrders
local orderByID = {}
local function OrderDraw(str,id,color)
    local order = orderByID[id]
    if order and myDrawOrders[order] then
        order.timeout = os.clock()+5
    else
        order = {
            str='!',
            type='font',
            pos = {id},
            offy = 8,
            timeout = os.clock()+5,
            blinking = 0.7,
            color = color,
        }

        table.insert(myDrawOrders, order)
        myDrawOrders[order] = true
        orderByID[id] = order
    end
    -- table.insert(DrawUtils.screen[widget]
    --     ,{type='rect',pos={150,200,50,100},timeout=os.clock()+5,blinking = 0.7,color=color}
    -- )

end

-- function widget:Update()
--     Echo('FSAA', Spring.GetConfigInt('FSAA'),'SmoothPoints', Spring.GetConfigInt('SmoothPoints'),'SmoothLines', Spring.GetConfigInt('SmoothLines'),'SetCoreAffinitySim',Spring.GetConfigInt('SetCoreAffinitySim'))
-- end
local toConfirm = {}
local known = {}
function widget:UnitCmdDone(builderID, defID, team, cmd, params, opts, tag)
    if team ~= myTeamID then
        return
    end

    local id, x, z
    if cmd < 0 then
        if params[3] then
            x,z = params[1], params[3]
            id = spGetUnitsInRectangle(x, z, x, z)[1]
        end
    elseif cmd == CMD_REPAIR then
        if not params[2] then
            return
        end
        id = params[1]
        if not spValidUnitID(id) then
            return
        end
    end

    if id then
        local bp = select(5,spGetUnitHealth(id))
        if bp < 1 and bp >= 0.85 then
            local queue = spGetCommandQueue(builderID, 3)
            local isInsert
            for i, order in ipairs(queue) do
                local ignore =  (cmd == CMD_REPAIR and order.id == CMD_REPAIR and order.params[1] == id
                                    or cmd < 0 and order.id == cmd and order.params[1] == x and order.params[3] == z )
                if ignore then
                    return
                end
            end
            toConfirm[builderID] = id 
            -- Echo(id .. ':Finish this build ! ' .. id, 'bp:'..bp)
            -- -- OrderDraw('!', id, 'yellow')
            -- INSERT_PARAMS[4] = id
            -- spGiveOrderToUnit(builderID, CMD_INSERT, INSERT_PARAMS ,CMD_OPT_ALT)
        end
    end
end

function widget:Update()
    for builderID, id in pairs(toConfirm) do
        if spValidUnitID(builderID) then
            local curcmd,_,_,p1,p2 = spGetUnitCurrentCommand(builderID)
            if curcmd ~= CMD_RECLAIM or p1 ~= id or p2 then
                if spValidUnitID(id) then
                    -- -- OrderDraw('!', id, 'yellow')
                    INSERT_PARAMS[4] = id
                    spGiveOrderToUnit(builderID, CMD_INSERT, INSERT_PARAMS ,CMD_OPT_ALT)
                end
            end
        end
        toConfirm[builderID] = nil
    end
end

function widget:Initialize()
    if Spring.GetSpectatingState() or Spring.IsReplay() then
        widgetHandler:RemoveWidget(widget)
        return
    end
    myTeamID = Spring.GetMyTeamID()
    if not WG.DrawUtils then
        OrderDraw = function() end
    else
        DrawUtils = WG.DrawUtils
        DrawUtils.screen[widget] = {}
        myDrawOrders = DrawUtils.screen[widget]
    end
end
function widget:Shutdown()
    if DrawUtils then
        DrawUtils.screen[widget] = nil
    end
end
