function widget:GetInfo()
    return {
        name      = "Fix Area Metal Reclaim (EXP)",
        desc      = "Order to reclaim remaining metal feature before/after an incomplete Area reclaim\nThat fix is not and cannot be perfect, it would take too much resource",
        -- some maps, like Mechadansonian and Mecharavaged contains features that has metal 
        -- but doesn't have the definition prop .autoreclaim which render them unable to be reclaimable
        -- when user ordered a metal-only area reclaim
        author    = "Helwor",
        date      = "July 2024",
        license   = "GNU GPL, v2 or later",
        layer     = -10, -- Before NoDuplicateOrders
        enabled   = true,  --  loaded by default?
        api       = true,
        handler   = true,
    }
end
local sig = '['..widget:GetInfo().name..']: '
local Echo = Spring.Echo


-------- Managing activation

local myPlayerID
local active = false -- default
local maxScan = 50 -- don't scan more features than this to detect their metal when processing at order issued
local maxCompare = 25 -- don't compare more distances than this when processing at order issued
local isSpec
local EMPTY_TABLE = {}
sleepException = {GamePaused = true, PlayerChanged = true}
local function Sleep(bool)
    if widgetHandler.Sleep then
        return widgetHandler[bool and 'Sleep' or 'Wake'](widgetHandler,widget, sleepException)
    elseif not widget.isSleeping then
        for k, v in pairs(widget) do
            if type(k)=='string' and type(v)=='function' then
                if not sleepException[k] and widgetHandler[k .. 'List'] then
                    widgetHandler[(bool and 'Remove' or 'Update')..'WidgetCallIn'](widgetHandler,k,widget)
                end
            end
        end
        widget.isSleeping = bool
    end
end
local function UpdateStatus(newActive, newSpec, force)
    if force or active ~= newActive or isSpec ~= newSpec then
        Sleep(newSpec or not newActive)
    end
    active, isSpec = newActive, newSpec
end

options_path = 'Hel-K'
options = {}
options.active = {
    name = widget:GetInfo().name,
    tooltip = widget.GetInfo().desc,
    type = 'bool',
    value = active,
    OnChange = function(self)
        Echo('on change')
        UpdateStatus(self.value, Spring.GetSpectatingState())
    end,
}

function widget:PlayerChanged(playerID)
    if playerID ~= myPlayerID then
        return
    end
    UpdateStatus(active, Spring.GetSpectatingState())
end
-------

local spGetFeaturesInCylinder   = Spring.GetFeaturesInCylinder
local spGetUnitPosition         = Spring.GetUnitPosition
local spGetFeaturePosition      = Spring.GetFeaturePosition
local spGiveOrderToUnit         = Spring.GiveOrderToUnit
local spGetCommandQueue         = Spring.GetCommandQueue
local spGetUnitCurrentCommand   = Spring.GetUnitCurrentCommand
local spGetPlayerInfo           = Spring.GetPlayerInfo
local spGetFeatureDefID         = Spring.GetFeatureDefID
local spGetFeatureResources     = Spring.GetFeatureResources
local CMD_RECLAIM               = CMD.RECLAIM
local CMD_OPT_SHIFT             = CMD.OPT_SHIFT
local CMD_OPT_ALT               = CMD.OPT_ALT
local CMD_OPT_CTRL              = CMD.OPT_CTRL
local CMD_INSERT                = CMD.INSERT
local CMD_REMOVE                = CMD.REMOVE
local CMD_RAW_BUILD
do
    local customCmds = VFS.Include('LuaRules/Configs/customcmds.lua')
    CMD_RAW_BUILD = customCmds.RAW_BUILD
end
local maxUnits                  = Game.maxUnits
--
local cache = setmetatable({}, {__mode = 'v'})
local fLeft = {}
local SEQUENCE = {}
local gamePaused = select(3, Spring.GetGameSpeed())
local frame = Spring.GetGameFrame()
-------

local function Init()
    local spGetFeatureDefID = spGetFeatureDefID
    local spGetFeatureResources = spGetFeatureResources
    for _, fid in pairs(Spring.GetAllFeatures()) do
        local def = FeatureDefs[spGetFeatureDefID(fid)]
        if not def.autoreclaim and def.reclaimable then
            local _, resM = spGetFeatureResources(fid)
            if resM > 0.1 then
                fLeft[fid] = true
            end
        end
    end
    if not next(fLeft) then
        Echo(sig .. ' is not needed')
        widget.status = 'Not needed.'
        widgetHandler:RemoveWidget(widget)
        return
    end
end

function widget:Update()
    Init()
    widgetHandler:RemoveWidgetCallIn('Update', widget)
    widget.Update = nil
end


local dists = {}
local byDist = function(a,b)
    return dists[a] < dists[b]
end
local function ReorderFids(fids, id)
    if not fids[1] then
        return
    end
    local ux, _, uz = spGetUnitPosition(id)
    dists = {}
    for i, fid in ipairs(fids) do
        local fx, _, fz = spGetFeaturePosition(fid)
        dists[fid] = ((fx - ux)^2 + (fz - uz)^2) ^0.5
    end
    table.sort(fids, byDist)
end

-----
function widget:GameFrame(f)
    frame = f
    if f%3600 == 0 then -- every 2 minutes
        local remaining = false
        for _, id in pairs(Spring.GetAllFeatures()) do
            if fLeft[id] then
                remaining = true
                break
            end
        end
        if not remaining then
            Echo(sig .. ' Finished his job.')
            widget.status = 'Finished his job.'
            widgetHandler:RemoveWidget(widget)
            return
        end
    end
end
local GetPing
do
    local askedPingF = -1
    local ping = 0.25
    function widget:GamePaused(_, status)
        gamePaused = status
    end
    function GetPing()
        local pingNow
        if gamePaused then
            pingNow = 0.25
        elseif askedPingF + 30 < frame then
            pingNow = select(6,spGetPlayerInfo(myPlayerID, true))
            ping = pingNow
            askedPingF = frame
        else
            pingNow = ping
        end
       -- local pingFrame = math.ceil(30  *  pingNow --[[* 1.25--]] )
       return pingNow
    end
end

----- Core

local function GetFeaturesToReclaim(x, z, r, id, before)
    local strID = x..'-'..z..'-'..r
    local cached = cache[strID]
    local all
    if not cached then
        cached = {processed_before = before}
        cache[strID] = cached
        local cnt = 0
        all = spGetFeaturesInCylinder(x, z, r)
        for _, fid in pairs(all) do
            if fLeft[fid] then
                cnt = cnt + 1
                cached[cnt] = fid
            end
        end
        if cnt > 0 then
            ReorderFids(cached, id)
            if before then
                if all[cnt + 1] then
                    -- if we're processing before the area command
                    -- keep only features that are closer than the closest metal feature to be reclaimed automatically
                    -- (so the process cannot be perfect as it only put the very closest before and all the rest after the area command and rely on the current position of the unit only to compare the distance)
                    -- caching feature for after the area command, in case things goes fast and the cache is still alive
                    local metal_fids, mf = {}, 0
                    local FeatureDefs = FeatureDefs
                    for i, fid in pairs(all) do
                        if not fLeft[fid] then
                            local def = FeatureDefs[spGetFeatureDefID(fid)]
                            if def.reclaimable then
                                local _, resM = spGetFeatureResources(fid)
                                if resM > 0.1 then
                                    mf = mf + 1
                                    metal_fids[mf] = fid
                                    if mf == maxCompare then
                                        break
                                    end
                                end
                            end
                            if i == maxScan then
                                break
                            end
                        end
                    end
                    if mf > 0 then
                        local myDists = dists
                        ReorderFids(metal_fids, id)
                        local going_after, g = {}, 0
                        local i, fid = 1, cached[1]
                        local incr
                        while fid do
                            incr = true
                            local dist = myDists[fid]
                            for _, other_fid in ipairs(metal_fids) do
                                if dist > dists[other_fid] then
                                    g = g + 1
                                    going_after[g] = table.remove(cached, i) -- transfert to going_after
                                    incr = false
                                    break
                                end
                            end
                            if incr then
                                i = i + 1
                            end
                            fid = cached[i]
                        end
                        if g > 0 then
                            cached.after = going_after
                        end
                    end
                    Echo(
                        'processing before'
                        , 'all feature in cylinder', #all
                        , 'extra features to insert', cnt
                        , 'other metal features', mf
                        , 'to insert after area command', cached.after and #cached.after or 0
                    )
                else
                    Echo('no other features than what we want, just add Ctrl')
                    cached.just_add_ctrl = true
                end
            end
        end
    end
    return cached
end


local function UpdateSequence(id, fid)
    local sequence = SEQUENCE[id]
    local now = os.clock()
    local count, isDone = 0, false
    if not sequence then
        sequence = {time = now, count = 0, done = {}}
        -- Echo(id ..' sequence create, seq ' .. count)
        SEQUENCE[id] = sequence
    else
        local ping = GetPing()
        if now < sequence.time + ping * 1.5 then
            count = sequence.count
            isDone = sequence.done[fid]
            -- Echo(id ..' sequence: ' .. count)
        else
            -- Echo(id ..' time passed, sequence reset, seq ' .. count)
            -- sequence.time = now
            sequence.done = {}
            sequence.count = 0
        end
        sequence.time = now
    end
    if not isDone then
        sequence.count = count + 1
        sequence.done[fid] = true
        -- Echo(id ..' sequence incremented for next round ' .. (count + 1))
    end
    return count, isDone

end

----- debug
-- local function debugUC(id, defID, team, cmd, params)
--     local tell
--     if cmd == 1 then
--         tell = params[2] .. ' paramX '.. params[4] .. ' inserted at ' .. params[1]
--     elseif cmd == 2 then
--         tell = 'remove ' .. params[1]
--     else
--         tell = cmd .. (params[1] and ' paramX' .. params[1] or '')
--     end
--     Echo('unit command ' .. tell .. ' /'..spGetCommandQueue(id,0))        
-- end
-----

local function Process(x, z, r, id, opts, before)
    local fids = GetFeaturesToReclaim(x, z, r, id, before)
    local toOrder = fids[1] and fids or not before and fids.after
    if before then
        toOrder = not fids.just_add_ctrl and fids[1] and fids
    else
        toOrder = fids.just_add_ctrl and fids
            or fids.processed_before and fids.after
            or not fids.processed_before and fids[1] and fids
    end
    if debugMe then
        Echo(
            before and (
                fids.just_add_ctrl and 'just gonna wait for cmdDone to execute same command with ctrl'
                or fids[1] and 'got '..#fids..' order(s) to insert before'
                or 'nothing to do (before)'
            ) or (
                fids.just_add_ctrl and 'adding ctrl now that cmdDone is executed'
                or fids.processed_before and (
                        fids.after and 'got to do '..#fids.after..' remaining order(s) after the area command'
                        or 'already processed everything before'
                    )
                or  fids[1] and 'got '..#fids..' order(s) to insert after'
                or 'got nothing (after)'
            )
        )
    end
    if toOrder then
        local coded
        --- get if shift and correct
        if type(opts) == 'table' then
            coded = opts.coded
            if not opts.shift then
                coded = coded + CMD_OPT_SHIFT
            end
        else
            coded = opts
            if coded % (CMD_OPT_SHIFT*2) < CMD_OPT_SHIFT then
                coded = coded + CMD_OPT_SHIFT
            end
        end
        ---
        if toOrder.just_add_ctrl then
            coded = coded + CMD_OPT_CTRL
            spGiveOrderToUnit(id, CMD_INSERT, {0, CMD_RECLAIM, coded, x, 0, z, r}, CMD_OPT_ALT)
            return
        end
        local count = 0
        for _, fid in ipairs(toOrder) do
            local toInsert, done = UpdateSequence(id, fid) -- verify if we haven't just given that order
            -- we assume the CmdDone happens at order #1 so the sequence insertion point start at 0
            if not done then
                -- CHECK IF VALID DUE TO CACHE ?
                count = count + 1
                -- Echo("area reclaim done: id: " .. id,'seq',seq,'#queue',queueLen,'real', spGetCommandQueue(id, 0),'paramDoneX', params[1], 'to insert ' .. (fid + maxUnits),toInsert or 'shift')
                if count == 1 then
                    spGiveOrderToUnit(id, CMD_REMOVE, CMD_RAW_BUILD, CMD_OPT_ALT) -- remove raw build order in advance to avoid a miscount
                end
                spGiveOrderToUnit(id, CMD_INSERT, {toInsert, CMD_RECLAIM, coded, fid + maxUnits}, CMD_OPT_ALT)
            else
                -- Echo(fid .. ' already ordered meanwhile server delay')
            end
        end
    end
end

------

function widget:UnitCmdDone(id, defID, teamID, cmd, params, opts, tag)
    if cmd == CMD_RECLAIM and not opts.ctrl then
        if params[4] and not params[5] then
            local x, z, r = params[1], params[3], params[4]
            -- local curCmd, curOptCoded, curTag, curP1, _, curP3, curP4, curP5 = spGetUnitCurrentCommand(id)
            local _, _, curTag = spGetUnitCurrentCommand(id)
            if curTag == tag then
                -- Echo('reclaim command just pushed')
                return
            end
            -- Echo('process cmdDone')
            Process(x, z, r, id, opts)
        end
    else
        local curCmd, curOptCoded, curTag, curP1, _, curP3, curP4, curP5 = spGetUnitCurrentCommand(id)
        if curCmd == CMD_RECLAIM and curOptCoded % (CMD_OPT_CTRL*2) < CMD_OPT_CTRL then
            if curP4 and not curP5 then
                -- Echo('incoming Area Reclaim Metal Command')
                Process(curP1, curP3, curP4, id, curOptCoded, true)
            end
        end
    end
end
function widget:UnitCommand(id, defID, teamID, cmd, params, opts)
    -- more taxing in resource but can insert our wanted features to reclaim before if they are closer
    local inserted
    if cmd == CMD_INSERT then
        cmd = params[2]
        inserted = true
    end
    if cmd == CMD_RECLAIM then
        if inserted and params[1] > 0 and spGetCommandQueue(id, 0) > 0 then
            -- Echo('let cmdDone do the job')
            return
        end
        local ctrl
        local pOffset
        if inserted then
            pOffset = 3
            opts = params[3]
            ctrl = opts % (CMD_OPT_CTRL*2) >= CMD_OPT_CTRL
        else
            pOffset = 0
            ctrl = opts.ctrl
        end
        if not ctrl then
            if params[pOffset + 4] and not params[pOffset + 5] then
                local x, z, r = params[pOffset + 1], params[pOffset + 3], params[pOffset + 4]
                Echo('process UnitCommand')
                Process(x, z, r, id, opts, true)
            end
        end
    end
end

-------------

function widget:Initialize()
    gamePaused = select(3, Spring.GetGameSpeed())
    myPlayerID = Spring.GetMyPlayerID()
    UpdateStatus(active, Spring.GetSpectatingState(), true)
end
