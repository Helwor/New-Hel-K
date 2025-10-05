--//=============================================================================
--//

TextureHandler = {}

local Echo = Spring.Echo
--//=============================================================================
--//TWEAKING

TextureHandler.timeLimit = 0.2/15 --//time per second / desiredFPS


--//=============================================================================
--// SpeedUp

local next = next
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local glActiveTexture = gl.ActiveTexture
local glCallList = gl.CallList

local weakMetaTable = {__mode="k"}


--//=============================================================================
--// local

local loaded = {}
local requested = {}

local placeholderFilename = theme.skin.icons.imageplaceholder
local placeholderDL = gl.CreateList(gl.Texture,CHILI_DIRNAME .. "skins/default/empty.png")
--local placeholderDL = gl.CreateList(gl.Texture,placeholderFilename)

local function AddRequest(filename,obj)
  local req = requested
  if (req[filename]) then
    local t = req[filename]
    t[obj] = true
  else
    req[filename] = setmetatable({[obj]=true}, weakMetaTable)
  end
end


--//=============================================================================
--// Destroy

TextureHandler._scream = Script.CreateScream()
TextureHandler._scream.func = function()
  requested = {}
  for filename,tex in pairs(loaded) do
    gl.DeleteList(tex.dl)
    gl.DeleteTexture(filename)
  end
  loaded = {}
end


--//=============================================================================
--//

function TextureHandler.LoadTexture(arg1,arg2,arg3)
  local activeTexID,filename,obj
  if (type(arg1)=='number') then
     activeTexID = arg1
     filename = arg2
     obj = arg3
  else
     activeTexID = 0
     filename = arg1
     obj = arg2
  end

  local tex = loaded[filename]
  if (not tex) then
    AddRequest(filename,obj)
    glActiveTexture(activeTexID,glCallList,placeholderDL)
  else
    glActiveTexture(activeTexID,glCallList,tex.dl)
  end
end


function TextureHandler.DeleteTexture(filename)
  local tex = loaded[filename]
  if (tex) then
    tex.references = tex.references - 1
    if (tex.references==0) then
      gl.DeleteList(tex.dl)
      gl.DeleteTexture(filename)
      loaded[filename] = nil
    end
  end
end


--//=============================================================================
--//
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local remove = table.remove
local clock = os.clock
local smoothing = 60
local periodicTell = 5
local function Wrap(func)
    local count = 0
    local totalTime, totalLoaded = 0, 0
    local lastTellTime = clock()
    local array = {}
    local wrapped = function()
        local time = spGetTimer()
        local loaded = func()
        time = spDiffTimers(spGetTimer(),time)
        count = count + 1
        if count > smoothing then
            -- remove first element, add new data at end of array
            local swap = remove(array,1)
            totalTime, totalLoaded = totalTime + time - swap.time, totalLoaded + loaded - swap.loaded
            swap.time, swap.loaded = time, loaded
            array[smoothing] = swap
        else
            array[count] = {time = time, loaded = loaded}
            totalTime, totalLoaded = totalTime + time, totalLoaded + loaded
        end
        local now = clock()
        if now > lastTellTime + periodicTell then
            local tell = ('average cycle (%d counts): time: %.2f ms, loaded: %.1f (%d)'):format(
                smoothing,
                (totalTime/smoothing)*1000,
                (totalLoaded > 0) and (totalLoaded/smoothing) or 0,
                totalLoaded
            )
            Echo(tell)
            lastTellTime = now
        end
    end
    return wrapped
end



local usedTime = 0
local lastCall = spGetTimer()
local glTexture = gl.Texture
local glCreateList = gl.CreateList
local OriUpdate = function()
  if WG.drawingPlacement or WG.EzSelecting or WG.panning then
      return 0
  end
  if usedTime>0 then
    thisCall = spGetTimer()

    usedTime = usedTime - spDiffTimers(thisCall,lastCall)
    lastCall = thisCall

    if (usedTime<0) then usedTime = 0 end
  end
  if (not next(requested)) then
    return 0
  end
  local total = 0
  local timerStart = spGetTimer()
  local timeLimit = TextureHandler.timeLimit
  while (usedTime < timeLimit) do
    local filename,objs = next(requested)

    if not filename then
      return total
    end
    local list = glCreateList(glTexture,filename)
    glCallList(list)
    glTexture(false)

    local cnt = 0
    for obj in pairs(objs) do
      cnt = cnt + 1
      obj:Invalidate()
    end
    loaded[filename] = {
      dl = list,
      -- references = #objs -- this can't be, or the lines above would make an error
      references = cnt
    }
    total = total + cnt
    requested[filename] = nil

    local timerEnd = spGetTimer()
    usedTime = usedTime + spDiffTimers(timerEnd,timerStart)
    timerStart = timerEnd
  end

  lastCall = spGetTimer()
  return total
end
TextureHandler.Update = OriUpdate

TextureHandler.DebugUpdate = function(bool)
  if bool then
    if TextureHandler.Update ~= OriUpdate then
      Echo('TextureHandler.Update is already getting debugged, nothing to do.')
      return
    end
    TextureHandler.Update = Wrap(OriUpdate)
    Echo('TextureHandler.Update wrapped to debugger')

  else
    if TextureHandler.Update == OriUpdate then
      Echo('TextureHandler.Update is not yet getting debugged, nothing to do.')
      return
    end
    TextureHandler.Update = OriUpdate
    Echo('TextureHandler.Update reverted to its original')
  end
end

--//=============================================================================
