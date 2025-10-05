--//=============================================================================
--// TaskHandler
local Echo = Spring.Echo

TaskHandler = {}

local newMethodUsed = false
-- first method vars

--// type1: use use 2 tables so we can iterate and update at the same time
local objects = {}
local objects2 = {}
local objectsCount = 0

--// type2
local objectsInAnInstant = {}
local objectsInAnInstant2 = {}
local objectsInAnInstantCount = 0

--// make it a weak table (values)

local m = {__mode = "v"}
local k = {__mode = "k"}
setmetatable(objects, m)
setmetatable(objects2, m)
setmetatable(objectsInAnInstant, m)
setmetatable(objectsInAnInstant2, m)


-- second method
--// type1: use use 2 tables so we can iterate and update at the same time
local newUpdate = {}
local currentUpdate = {}


--// type2
local newInstantUpdate = {}
local currentInstantUpdate = {}
local hasNewInstantUpdate = false

--// make it a weak table (values)


setmetatable(newUpdate, k)
setmetatable(currentUpdate, k)
setmetatable(newInstantUpdate, k)
setmetatable(currentInstantUpdate, k)


--//=============================================================================

--// Global Event for when an object gets destructed
local globalDisposeListeners = {}
setmetatable(globalDisposeListeners, {__mode = "k"})

local function CallListenersByKey(listeners, ...)
  for obj in pairs(listeners) do
    obj:OnGlobalDispose(...);
  end
end


function TaskHandler.RequestGlobalDispose(obj)
  globalDisposeListeners[obj] = true
end

--//=============================================================================

function TaskHandler.RequestUpdateOLD(obj)
    obj = UnlinkSafe(obj)
    if (not obj.__inUpdateQueue) then
        obj.__inUpdateQueue = true
        objectsCount = objectsCount + 1
        objects[objectsCount] = obj
    end
end


function TaskHandler.RemoveObjectOLD(obj)
  obj = UnlinkSafe(obj)

  CallListenersByKey(globalDisposeListeners, obj)

  if (obj.__inUpdateQueue) then
    obj.__inUpdateQueue = false
    for i=1,objectsCount do
      if (objects[i]==obj) then
        objects[i] = objects[objectsCount]
        objects[objectsCount] = nil
        objectsCount = objectsCount - 1
        return true
      end
    end
    return false
  end
end


function TaskHandler.RequestInstantUpdateOLD(obj)
    obj = UnlinkSafe(obj)
    if (not obj.__inUpdateQueue) then
        obj.__inUpdateQueue = true
        objectsInAnInstantCount = objectsInAnInstantCount + 1
        objectsInAnInstant[objectsInAnInstantCount] = obj
    end
end

--//=============================================================================

function TaskHandler.UpdateOLD()
    --// type1: run it for all current tasks
    local cnt = objectsCount
    objectsCount = 0 --// clear the array, so all objects needs to reinsert themselves when they want to get called again
    objects,objects2 = objects2,objects
    local sizeUpdate = 0
    for i=1,cnt do
        local obj = objects2[i]
        if (obj)and(not obj.disposed) then
            obj.__inUpdateQueue = false
            local Update = obj.Update
            if (Update) then
                SafeCall(Update, obj)
                sizeUpdate = sizeUpdate + 1
            end
        end
    end

    --// type2: endless loop until job is done
    local runs = 0
    local sizeInstant = 0
    while (objectsInAnInstantCount > 0) do
        runs = runs + 1
        local cnt = objectsInAnInstantCount
        objectsInAnInstantCount = 0
        objectsInAnInstant,objectsInAnInstant2 = objectsInAnInstant2,objectsInAnInstant
        for i=1,cnt do
            local obj = objectsInAnInstant2[i]
            if (obj)and(not obj.disposed) then
                obj.__inUpdateQueue = false
                local InstantUpdate = obj.InstantUpdate
                if (InstantUpdate) then
                    sizeInstant = sizeInstant + 1
                    SafeCall(InstantUpdate, obj)
                end
            end
        end
    end
    return sizeUpdate, sizeInstant, runs
end

--//=============================================================================


function TaskHandler.RemoveObjectNEW(obj)
  obj = UnlinkSafe(obj)

  CallListenersByKey(globalDisposeListeners, obj)

  if obj.__inUpdateQueue then
    obj.__inUpdateQueue = false
    newUpdate[obj] = nil

    return true
  end
end
local done = 0
function TaskHandler.RequestUpdateNEW(obj)
    obj = UnlinkSafe(obj)
    if not obj.__inUpdateQueue then
        obj.__inUpdateQueue = true
        newUpdate[obj] = true
    end
    -- if done < 5 and math.random(30) == 30 then
    --     done = done + 1
    --     Echo('CHECK')
    -- end
end

function TaskHandler.RequestInstantUpdateNEW(obj)
    obj = UnlinkSafe(obj)
    if not obj.__inUpdateQueue then
        obj.__inUpdateQueue = true
        newInstantUpdate[obj] = true
    end
end

--//=============================================================================
local spGetModKeyState = Spring.GetModKeyState
local WG = WG
function TaskHandler.UpdateNEW()
    --// type1: run it for all current tasks
    local th = TaskHandler
    if (th.drawpNoUpdate and WG.drawingPlacement) or (th.ezSelectNoUpdate and WG.EzSelecting and not select(3, spGetModKeyState())) or (th.panningNoUpdate and WG.panning) then
        return 0,0,0
    end
    currentUpdate,newUpdate = newUpdate,currentUpdate
    local current = currentUpdate
    local sizeUpdate = 0
    for obj in pairs(current) do
        obj.__inUpdateQueue = false
        currentUpdate[obj] = nil
        if not obj.disposed then
            local Update = obj.Update
            if Update then
                sizeUpdate = sizeUpdate + 1
                SafeCall(Update, obj)
            end
        end
    end

    --// type2: endless loop until job is done
    local sizeInstant = 0
    local runs = 0
    while next(newInstantUpdate) do
        runs = runs + 1
        currentInstantUpdate,newInstantUpdate = newInstantUpdate,currentInstantUpdate
        local current = currentInstantUpdate
        for obj in pairs(current) do
            obj.__inUpdateQueue = false
            current[obj] = nil
            if not obj.disposed then
                local InstantUpdate = obj.InstantUpdate
                if InstantUpdate then
                    sizeInstant = sizeInstant + 1
                    SafeCall(InstantUpdate, obj)
                end
            end
        end
    end
    return sizeUpdate, sizeInstant, runs
end
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local remove = table.remove
local clock = os.clock
local smoothing = 60
local periodicTell = 5
local function Wrap(func)
    local count = 0
    local totalUpd, totalInst, totalTime, totalRuns = 0, 0, 0, 0
    local lastTellTime = clock()
    local array = {}
    local wrapped = function()
        local time = spGetTimer()
        local upd, inst, runs = func()
        time = spDiffTimers(spGetTimer(),time)
        count = count + 1
        if count > smoothing then
            -- remove first element, add new data at end of array
            local swap = remove(array,1)
            totalTime, totalUpd, totalInst, totalRuns = totalTime + time - swap.time, totalUpd + upd - swap.upd, totalInst + inst - swap.inst, totalRuns + runs - swap.runs
            swap.time, swap.upd, swap.inst, swap.runs = time, upd, inst, runs
            array[smoothing] = swap
        else
            array[count] = {time = time, upd = upd, inst = inst, runs = runs}
            totalTime, totalUpd, totalInst, totalRuns = totalTime + time, totalUpd + upd, totalInst + inst, totalRuns + runs
        end
        local now = clock()
        if now > lastTellTime + periodicTell then
            local tell = ('average cycle (%d counts): time: %.2f ms, (time per update: %.2f ms) load: %.1f updates (%d), %.1f instants (%d), runs %.1f (%d)'):format(
                smoothing,
                (totalTime/smoothing)*1000,
                (totalUpd + totalInst) > 0 and (totalTime / (totalUpd + totalInst)) * 1000 or 0,
                (totalUpd > 0) and (totalUpd/smoothing) or 0,
                totalUpd,
                (totalInst>0) and (totalInst/smoothing) or 0,
                totalInst,
                (totalRuns>0) and (totalRuns/smoothing) or 0,
                totalRuns

            )
            Echo(tell)
            lastTellTime = now
        end
    end
    return wrapped
end


function TaskHandler.SwitchMethod(newMethod)
    if newMethod then
        TaskHandler.Update = TaskHandler.UpdateNEW
        TaskHandler.RequestInstantUpdate = TaskHandler.RequestInstantUpdateNEW
        TaskHandler.RequestUpdate = TaskHandler.RequestUpdateNEW
        TaskHandler.RemoveObject = TaskHandler.RemoveObjectNEW

        for k, obj in pairs(objectsInAnInstant) do
            newInstantUpdate[obj] = true
            objectsInAnInstant[k] = nil
        end
        for k,obj in pairs(objects) do
            newUpdate[obj] = true
            objects[k] = nil
        end

    else
        TaskHandler.Update = TaskHandler.UpdateOLD
        TaskHandler.RequestInstantUpdate = TaskHandler.RequestInstantUpdateOLD
        TaskHandler.RequestUpdate = TaskHandler.RequestUpdateOLD
        TaskHandler.RemoveObject = TaskHandler.RemoveObjectOLD

        objectsInAnInstantCount = 0
        for obj in pairs(newInstantUpdate) do
            objectsInAnInstantCount = objectsInAnInstantCount + 1
            objectsInAnInstant[objectsInAnInstantCount] = obj
            newInstantUpdate[obj] = nil
        end
        objectsCount = 0
        for obj in pairs(newUpdate) do
            objectsCount = objectsCount + 1
            objects[objectsCount] = obj
            newUpdate[obj] = nil
        end
    end
    newMethodUsed = newMethod
    Echo('Chili is now using ' .. (newMethod and 'new' or 'old') .. ' update method.')
    if options.debugUpdates.value then
        TaskHandler.DebugUpdates(true)
    end
end
TaskHandler.Tell = function()
    if newMethodUsed then
        Echo('There are currently ' .. table.size(newUpdate) .. ' updates to be done and ' .. table.size(newInstantUpdate) .. ' instant updates to be done.')
    else
        Echo('There are currently ' .. objectsCount .. ' updates to be done and ' .. objectsInAnInstantCount .. ' instant updates to be done.')
    end
end
TaskHandler.SwitchMethod(newMethodUsed)

function string:sol(pos) -- get start of the line where pos is
    if pos>self:len() then
        return
    end
    return self:sub(1,pos):match(".*\n()") or 1
end
local traces = {}
local counts = {}
local traceRequests = true
function TaskHandler.DebugUpdates(bool)
    if not TaskHandler.Update then
        Echo('TaskHandler.Update doesnt yet exists.')
        return
    end
    if bool then
        if traceRequests then
            if not TaskHandler.OriRequestUpdate then
                TaskHandler.OriRequestUpdate = TaskHandler.RequestUpdate
                TaskHandler.RequestUpdate = function(obj)
                    if math.random(30) == 1 then
                        local trace = debug.traceback()
                        if not trace then
                            return
                        end
                        local wname = tostring(obj._widget and obj._widget.GetInfo and obj._widget.GetInfo().name) or ''
                        if not traces[wname..trace] then
                        
                            local lines = trace:explode('\n')
                                local len = #lines
                                if lines[len]:match('tail call') then
                                    lines[len] = nil
                                    len = len - 1
                                end
                                local short
                                for i = len, 1, -1 do
                                    local line = lines[i]
                                    if line:find('in function') and line:find('Widgets') and not line:find('RequestUpdate')
                                        and not line:find('Invalidate')
                                    then
                                        short = line
                                    end
                                end
                                if not short then
                                    short = lines[len] or trace
                                end
                                short = wname ..'\n'..short
                                traces[wname..trace] = short
                                counts[short] = 0
                                Echo(('----'):rep(10) .. '\n' .. trace)
                        end

                        local short = traces[wname..trace]
                        if short then
                            local count = counts[short] + 1
                            counts[short] = count + 1
                            if count == 1 or count<=25 and count%5 == 0 or count%50 == 0 then
                                Echo(short .. '... X ' .. count)
                            end
                        end
                    end
                    return TaskHandler.OriRequestUpdate(obj)
                end
            end
        end
        if TaskHandler.Update == TaskHandler.UpdateNEW or TaskHandler.Update == TaskHandler.UpdateOLD then
            TaskHandler.Update = Wrap(TaskHandler.Update)
            Echo('TaskHandler.Update is getting debugged.')
        else
            Echo('TaskHandler.Update has already been wrapped.')
        end
    else
        if TaskHandler.OriRequestUpdate then
            TaskHandler.RequestUpdate = TaskHandler.OriRequestUpdate
            TaskHandler.OriRequestUpdate = nil
        end
        if TaskHandler.Update == TaskHandler.UpdateNEW or TaskHandler.Update == TaskHandler.UpdateOLD then
            Echo('TaskHandler.Update is not debugged, nothing to do')
            return
        elseif TaskHandler.RequestUpdate == TaskHandler.RequestUpdateNEW then
            TaskHandler.Update = TaskHandler.UpdateNEW
            Echo('TaskHandler.Update has been stripped off debugging and reverted to its NEW method.')
            for trace in pairs(traces) do
                traces[trace] = nil
            end
        elseif TaskHandler.RequestUpdate == TaskHandler.RequestUpdateOLD then
            TaskHandler.Update = TaskHandler.UpdateOLD
            Echo('TaskHandler.Update has been stripped off debugging and reverted to its OLD method.')
            for trace in pairs(traces) do
                traces[trace] = nil
            end
        else
            -- should never happen
            Echo('problem, cannot find which version is TaskHandler.Update')
        end
    end
end

