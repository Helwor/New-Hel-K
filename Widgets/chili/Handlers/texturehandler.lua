--// =============================================================================
--//

TextureHandler = {}


--// =============================================================================
--//TWEAKING
-- loading texture time is the least of the problem, insignificant
-- there are hundreds, almost a thousand of undisposed objects remainings
-- flushing completely the textures show that there a few hundred of unused textures loaded uselessly

TextureHandler.timeLimit = 0.2/15 --//time per second / desiredFPS


--// =============================================================================
--// SpeedUp

local next = next
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local glActiveTexture = gl.ActiveTexture
local glCallList = gl.CallList
local Echo = Spring.Echo
local weakMetaTable = {__mode = "k"}


--// =============================================================================
--// local
loadedTextures = {}
local loaded = loadedTextures
local requested = {}
local total = 0
local placeholderFilename = theme.skin.icons.imageplaceholder
local placeholderDL = gl.CreateList(gl.Texture, CHILI_DIRNAME .. "skins/default/empty.png")
--local placeholderDL = gl.CreateList(gl.Texture, placeholderFilename)

local isEngineTexture = { [string.byte("!")] = true, [string.byte("%")] = true, [string.byte("#")] = true, [string.byte("$")] = true, [string.byte("^")] = true }
local allObjs = setmetatable({}, weakMetaTable)
local function AddRequest(filename, obj)
	-- allObjs[obj] = true
	local req = requested[filename]
	if req then
		req[obj] = true
	else
		requested[filename] = setmetatable({[obj] = true}, weakMetaTable)
	end
end


--// =============================================================================
--// Destroy
local deletedCount, deRefCount = 0, 0

TextureHandler._scream = Script.CreateScream()
TextureHandler._scream.func = function()
	for filename in pairs(requested) do
		requested[filename] = nil
	end
	for filename, tex in pairs(loaded) do
		gl.DeleteList(tex.dl)
		gl.DeleteTexture(filename)
		loaded[filename] = nil
	end
	deletedCount = table.size(loaded)
end


--// =============================================================================
--//
local glTexture = gl.Texture

function TextureHandler.LoadTexture(arg1, arg2, arg3)
	local activeTexID, filename, obj
	if type(arg1) == 'number' then
		activeTexID = arg1
		filename = arg2
		obj = arg3
	else
		activeTexID = 0
		filename = arg1
		obj = arg2
	end
	
	local tex = loaded[filename]
	if tex then
		glActiveTexture(activeTexID, glCallList, tex.dl)
		return true
	else
		AddRequest(filename, obj)
		if isEngineTexture[filename:byte(1)] then
			glTexture(activeTexID, filename)
		else
			glActiveTexture(activeTexID, glCallList, placeholderDL)
		end
	end
end

function TextureHandler.DeleteTexture(filename) -- this is basically never happening FIX ME, that system cannot work !
	local tex = loaded[filename]
	if (tex) then
		tex.references = tex.references - 1
		deRefCount = deRefCount + 1
		if (tex.references == 0) then
			gl.DeleteList(tex.dl)
			gl.DeleteTexture(filename)
			loaded[filename] = nil
			deletedCount = deletedCount + 1
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
local nullInfo = {xsize = 0}

local glCreateList = gl.CreateList
local glTextureInfo = gl.TextureInfo
local tsize = table.size
local OriUpdate = function()
	if not next(requested) then
		return 0
	end
	if WG.drawingPlacement or WG.EzSelecting or WG.panning then
		return 0
	end
	if usedTime > 0 then
		thisCall = spGetTimer()

		usedTime = usedTime - spDiffTimers(thisCall,lastCall)
		lastCall = thisCall

		if usedTime < 0 then
			usedTime = 0
		end
	end
	local total = 0
	local timerStart = spGetTimer()
	local timeLimit = TextureHandler.timeLimit
	local broken = {}
	local timerStart = spGetTimer()

	for filename, objs in pairs(requested) do
		if (filename == "") then
			requested[filename] = nil
		else
			local texloaded = loaded[filename]
			if texloaded then
				local refs = tsize(objs)
				total = total - texloaded.references + refs
				texloaded.references = refs
				requested[filename] = nil
			else
				-- glTexture(filename)
				-- glTexture(false)
				local info = glTextureInfo(filename)
				if info and info.xsize then -- so far, there is only one texture that never ever get loaded
					local list = glCreateList(glTexture,filename)
					local cnt = 0
					for obj in pairs(objs) do
						cnt = cnt + 1
						obj:Invalidate()
					end
					loaded[filename] = {
						dl = list,
						references = cnt,
						info = info,
					}
					total = total + cnt
					requested[filename] = nil
				end
			end
		end

		local timerEnd = spGetTimer()
		usedTime = usedTime + spDiffTimers(timerEnd,timerStart)
		if usedTime > timeLimit then
			break
		end
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

function TextureHandler.Tell()
	local cntTex, cntRef = 0, 0
	for _, t in pairs(loaded) do
		cntTex, cntRef = cntTex + 1, cntRef + t.references
	end
	local cntReq, cntObjs = 0, 0
	for _, objs in pairs(requested) do
		cntReq, cntObjs = cntReq + 1, cntObjs + table.size(objs)
	end
	-- local dispPropCnt = 0
	-- for obj in pairs(allObjs) do
	-- 	if obj.disposed then
	-- 		dispPropCnt = dispPropCnt + 1
	-- 	end
	-- end

	Echo(
		'There are currently ' .. cntTex .. ' textures loaded with ' .. cntRef .. ' references '
		.. 'and ' .. cntReq .. ' texture ' .. (
			next(requested) and ('("'..(next(requested)=='' and '<empty string>' or next(requested))..'"...)') or ''
		)..' requested by ' .. cntObjs .. ' objects.'
		.. ' '..deRefCount ..' references has been removed, ' ..deletedCount .. ' textures has been deleted. '
		-- .. "Currently " .. table.size(allObjs) .. " have requested textures and haven't been disposed, "
		-- .. 'among them ' .. dispPropCnt .. ' are marked as disposed.'
	)
end
--//=============================================================================
