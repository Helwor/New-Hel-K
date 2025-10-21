----------------------------------------------------------------------------
----------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name    = "EndGame APM stats",
		desc    = "Adding the engine APM stats back in, to be called from endgamewindow",
		author  = "DavetheBrave",
		date    = "2021",
		license = "public domain",
		layer   = -1,
		enabled = true
	}
end

local spGetTeamInfo         = Spring.GetTeamInfo
local spGetTeamList         = Spring.GetTeamList
local spGetGameSeconds      = Spring.GetGameSeconds
local spGetPlayerStatistics = Spring.GetPlayerStatistics
local spGetPlayerInfo       = Spring.GetPlayerInfo

local timedPlayerList = {}
local storedPlayerStats = {}
local statsFinal = {}

local myPlayerID = Spring.GetMyPlayerID()
local myTeamID
local wantStats = false
local SendLuaUIMsg = Spring.SendLuaUIMsg

local floor = math.floor
----------------------------------------------------------------------------
----------------------------------------------------------------------------

local function GameRunning()
	return (Spring.GetGameFrame() > 0 and not Spring.IsGameOver())
end

local function round(number)
	return floor(number + 0.5)
end

local function SetTimedPlayerList()
	local gaiaTeamID = Spring.GetGaiaTeamID()
	for _,teamID in ipairs(Spring.GetTeamList()) do
		local _,leader,_,isAI,_,_ = Spring.GetTeamInfo(teamID, false)
		if not isAI then
			if teamID~=gaiaTeamID then
				timedPlayerList[leader] = {}
				timedPlayerList[leader].inactiveTime = 0
			end
		end
	end
end

local function SendMyPlayerStats()
	if not wantStats then
		return
	end
	local MP, MC, KP, NC, NUC = spGetPlayerStatistics(myPlayerID, true)
	timedPlayerList[myPlayerID].inactiveTime = timedPlayerList[myPlayerID].inactiveTime or 0
	local activeTime = spGetGameSeconds()-timedPlayerList[myPlayerID].inactiveTime
	local playerStats = {
		teamID = myTeamID,
		MPS = round(MP/activeTime),
		MCM = round(MC*60/activeTime),
		KPM = round(KP*60/activeTime),
		APM = round(NC*60/activeTime),
	}
	--If sending own stats, we need to clear previous set incase we have left the game and come back
	WG.AddPlayerStatsToPanel(playerStats)
	MP = VFS.PackU16(MP)
	MC = VFS.PackU16(MC)
	KP = VFS.PackU16(KP)
	NC = VFS.PackU16(NC)
	NUC = VFS.PackU16(NUC)
	SendLuaUIMsg("pStats"..MP..MC..KP..NC..NUC)
end

local function SendPlayerInactiveTime(playerID)
	local inactiveTimeStr = "inactiveTime"..VFS.PackU16(playerID)..VFS.PackU16(timedPlayerList[playerID].inactiveTime)
	SendLuaUIMsg(inactiveTimeStr)
end

local function ProcessPlayerInactiveTime(msg)
	local playerID = tonumber(VFS.UnpackU16(msg:sub(13)))
	local inactiveTime = tonumber(VFS.UnpackU16(msg:sub(15)))
	return inactiveTime, playerID
end

local function ProcessPlayerStats(msg, playerID)
	if not timedPlayerList[playerID] then
		return
	end
	local teamID = select(4,spGetPlayerInfo(playerID, false))
	local MP = tonumber(VFS.UnpackU16(msg:sub(7)))
	local MC = tonumber(VFS.UnpackU16(msg:sub(9)))
	local KP = tonumber(VFS.UnpackU16(msg:sub(11)))
	local NC = tonumber(VFS.UnpackU16(msg:sub(13)))
	local NUC = tonumber(VFS.UnpackU16(msg:sub(15)))
	timedPlayerList[playerID].inactiveTime = timedPlayerList[playerID].inactiveTime or 0
	local activeTime = spGetGameSeconds() - timedPlayerList[playerID].inactiveTime
	if activeTime > 0 then
		local playerStats = {
			teamID = teamID,
			MPS = round(MP/activeTime),
			MCM = round(MC*60/activeTime),
			KPM = round(KP*60/activeTime),
			APM = round(NC*60/activeTime),
		}
		WG.AddPlayerStatsToPanel(playerStats)
	end
end

function widget:Initialize()
	local _, _, isSpec, teamID = spGetPlayerInfo(myPlayerID, false)
	--This will also get called if coming back into game as a spectator -- in that case we don't want to start logging stats again
	--so wantStats will be false
	if not isSpec then
		myTeamID = teamID
		wantStats = true
	end
	SetTimedPlayerList()
end

function widget:RecvLuaMsg(msg, playerID)
	if playerID == myPlayerID then
		return true
	end
	if (msg:sub(1,6)=="pStats") then
		if not GameRunning() then
			ProcessPlayerStats(msg, playerID)
		else
			storedPlayerStats[playerID] = msg
		end
	elseif (msg:sub(1,12)=="inactiveTime") and timedPlayerList[timedPlayerID] then
		--Ensure that the maximum amount of inactive time is getting sent for each player
		--Because local player won't have information on their own inactive time, and some others may not have
		--complete information if they have left and come back
		local inactiveTime, timedPlayerID = ProcessPlayerInactiveTime(msg)
		if inactiveTime > timedPlayerList[timedPlayerID].inactiveTime then
			timedPlayerList[timedPlayerID].inactiveTime = inactiveTime
		end
	end
end

function widget:Shutdown()
	--ensure that stats are getting sent if the player leaves before the game ends.
	if Spring.IsGameOver() then
		return
	end
	SendMyPlayerStats()
end

function widget:PlayerChanged(playerID)
	--ensure that stats are getting sent if a player is resigning early
	--log time after resign as inactive time
	if playerID == myPlayerID and GameRunning() and timedPlayerList[playerID] then
		timedPlayerList[playerID].inactiveStartTime = spGetGameSeconds()
		SendMyPlayerStats()
	end
end

function widget:PlayerRemoved(playerID)
	--this is useless for now
	if playerID ~= myPlayerID and GameRunning() and timedPlayerList[playerID] then
		timedPlayerList[playerID].inactiveStartTime = spGetGameSeconds()
	end
end

function widget:PlayerAdded(playerID)
	--When a player gets added, Spring.GetPlayerStatistics starts anew
	--So any time before this should be considered inactive time
	if (playerID ~= myPlayerID) and GameRunning() and timedPlayerList[playerID] then
		if timedPlayerList[playerID].inactiveStartTime then
			timedPlayerList[playerID].inactiveTimeDC = spGetGameSeconds()
			timedPlayerList[playerID].inactiveStartTime = false
		end
	end
end

function widget:GameOver()
	for playerID, data in pairs(timedPlayerList) do
		if data.inactiveStartTime then
			data.inactiveTimeRes = spGetGameSeconds() - timedPlayerList[playerID].inactiveStartTime
		end
		--If a player has some DC time, and also resigned early, the cumulative total needs to be considered
		data.inactiveTimeDC = data.inactiveTimeDC or 0
		data.inactiveTimeRes = data.inactiveTimeRes or 0
		data.inactiveTime = data.inactiveTimeDC + data.inactiveTimeRes
		SendPlayerInactiveTime(playerID)
	end
	SendMyPlayerStats()
	for playerID, msg in pairs(storedPlayerStats) do
		ProcessPlayerStats(msg, playerID)
	end
end




--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Hack to load -OnWidgetState.lua  and AddSleepWake just after this widget
do
	VFS.Include("LuaUI\\Widgets\\Include\\add_on_handler_register_global_multi.lua")
	local function GetRealHandler()
		if widgetHandler.LoadWidget then
			return widgetHandler
		else
		    local i, n = 0, true
		    while n do
		        i=i+1
		        n,v=debug.getupvalue(widgetHandler.RemoveCallIn, i)
		        if n=='self' and type(v)=='table' and v.LoadWidget then
		            return v
		        end
		    end
		end
	end
	local realHandler = GetRealHandler()
	if realHandler then
		local function GetLocal(func, searchname)
		    local i = 1
		    local found
		    while i < 10 do
		        i = i + 1
		        if debug.getinfo(i,'f').func == func then
		            found = i
		            break
		        end
		    end
		    if not found then
		        return
		    end
		    local j, name, value = 0, true, nil 
		    while name do
		        j = j + 1
		        name, value = debug.getlocal(found, j)
		        if name == searchname then
		            return value
		        end
		    end
		end
		local widgetFiles = GetLocal(realHandler.Initialize, 'widgetFiles')
		-- Echo('SOURCE',source)
		-- for i, v in ipairs(widgetFiles) do
		-- 	Spring.Echo('#'..i, v)
		-- end
		if widgetFiles then
			local source = debug.getinfo(1).source
			local this_widget_pat = source:sub(source:find('[%w_]+%.lua')) .. '$'
			-- Echo("this_widget_pat is ", this_widget_pat)
			local on_widget_state_pat = '-OnWidgetState.lua' .. '$'
			local add_sleep_wake_pat = '-AddSleepWake.lua' .. '$'
			local this_widget_index, on_widget_state_index , add_sleep_wake_index
			for i=1, #widgetFiles do
				
				local filename = widgetFiles[i]
				if not this_widget_index then
					if filename:find(this_widget_pat) then
						-- Echo('FOUND FILENAME',i,filename)
						this_widget_index = i
					end
				else
					if not add_sleep_wake_index then
						if filename:find(add_sleep_wake_pat) then
							-- Echo('FOUND FILENAME',i,filename)
							add_sleep_wake_index = i
						end
					end
					if not on_widget_state_index then
						if filename:find(on_widget_state_pat) then
							-- Echo('FOUND FILENAME',i,filename)
							on_widget_state_index = i
						end
					end
					if add_sleep_wake_index and on_widget_state_index then
						break
					end
				end
			end
			if this_widget_index then
				if add_sleep_wake_index then
					table.insert(widgetFiles, this_widget_index + 1, table.remove(widgetFiles, add_sleep_wake_index))
					-- Echo('Insert sleep wake at ',this_widget_index + 1)
				end
				if on_widget_state_index then
					-- Echo('Insert on widget state at ',this_widget_index + 2)
					table.insert(widgetFiles, this_widget_index + 2, table.remove(widgetFiles, on_widget_state_index))
				end
			end
			local function RemoveDuplicateFilenames(files)
				local commons = {}
				local i = 1
				while files[i] do
					local filename = files[i]:gsub('\\','/')
					if commons[filename] then
						table.remove(files,i)
					else
						commons[filename] = true
						i = i + 1
					end
				end
			end
			RemoveDuplicateFilenames(widgetFiles)
		end
	end
end
