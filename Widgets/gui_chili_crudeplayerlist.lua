
function widget:GetInfo()
	return {
		name      = "Chili Crude Player List",
		desc      = "An inexpensive playerlist.",
		author    = "GoogleFrog",
		date      = "8 November 2019",
		license   = "GNU GPL, v2 or later",
		layer     = 50,
		enabled   = true,
	}
end
local Echo = Spring.Echo
if Spring.GetModOptions().singleplayercampaignbattleid then
	function widget:Initialize()
		Spring.SendCommands("info 0")
	end

	return
end
local countryFull = VFS.Include(LUAUI_DIRNAME .. "Widgets/Include/countryShortname.lua")
local displayResources = false
local debugging = false
local isMatchMaker = false

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local myAllyTeamID          = Spring.GetMyAllyTeamID()
local myTeamID              = Spring.GetMyTeamID()
local myPlayerID            = Spring.GetMyPlayerID()
local mySpectating          = Spring.GetSpectatingState()


local spGetPlayerRulesParam = Spring.GetPlayerRulesParam
local spGetTeamRulesParam   = Spring.GetTeamRulesParam
local spGetGameRulesParam   = Spring.GetGameRulesParam
local spGetPlayerList 		= Spring.GetPlayerList
local spGetPlayerInfo		= Spring.GetPlayerInfo
local spGetTeamInfo			= Spring.GetTeamInfo
local spGetTeamList         = Spring.GetTeamList
local spGetGaiaTeamID       = Spring.GetGaiaTeamID
local spGetGameFrame        = Spring.GetGameFrame
local spGetAIInfo           = Spring.GetAIInfo
local spGetTeamColor        = spGetTeamColor
local spGetUnitTeam         = Spring.GetUnitTeam
local spGetTeamColor        = Spring.GetTeamColor

local min   = math.min
local max   = math.max
local ceil  = math.ceil
local floor = math.floor


local fallbackAllyTeamID    = Spring.GetMyAllyTeamID()

local Chili

local function GetColorChar(colorTable)
	if colorTable == nil then return string.char(255,255,255,255) end
	local col = {}
	for i = 1, 3 do
		col[i] = max(colorTable[i]*255, 1)
	end
	return string.char(255,col[1],col[2],col[3])
end
local function coloredString(str,color)
	return '\255'
		.. string.char(max(color[1]*255, 1))
		.. string.char(max(color[2]*255, 1))
		.. string.char(max(color[3]*255, 1))
		.. str
		.. '\008'
end

local Truncate = function(v, max_length)
	if type(v) == 'string' then
		local len = #v
		if len > 3 and len > max_length - 3 then
			v = v:sub(1, max_length - 3) .. '...'
		end
	end
	return v
end

local pingCpuColors = {
	{0, 1, 0, 1},
	{0.7, 1, 0, 1},
	{1, 1, 0, 1},
	{1, 0.6, 0, 1},
	{1, 0, 0, 1},
	{1, 1, 1, 1},
}

local playerInfo
local myControls
local ShareUnits
local ALLY_COLOR  = {0, 1, 1, 1}
local ENEMY_COLOR = {1, 0, 0, 1}

local PING_TIMEOUT = 2 -- seconds

local MAX_NAME_LENGTH = 100
local SHOW_TEAMID = false

local pingUpdatePeriod = 1
local DEFAULT_TEXT_HEIGHT = 13
local IMAGE_SHARE  = "" .. LUAUI_DIRNAME .. "Images/gift2.png"
local IMAGE_CPU    = ":n:" .. LUAUI_DIRNAME .. "Images/playerlist/cpu.png" -- :n: is for nearest (pixelated)
local IMAGE_PING   = ":n:" .. LUAUI_DIRNAME .. "Images/playerlist/ping.png"
local IMAGE_METAL  = 'LuaUI/Images/ibeam.png'
local IMAGE_ENERGY = 'LuaUI/Images/energy.png'
local defaultamount = 100 -- default amount to give to ally player
local CONTINUE = {energy = {time = 0, target = false, next_time = 0}, metal = {time = 0, target = false, next_time = 0}}
local CONTINUE_TIME = 10 -- how long last the continued sharing
local CONTINUE_FREQUENCY = 1 
local HIDDEN_STORAGE = 10000
local UPDATE_TOOLTIP = false -- update metal or energy tooltip
local LAGOUT_FLASH_THRESHOLD = 4 -- ping threshold in seconds where player start to flash
local BLINK_PERIOD = 1.25 -- total time on/off blink for flashing player
local BLINK_END = BLINK_PERIOD * 4.5 -- timeout where it stop blinking and stay permanent redish
local laggingOut = {} -- holder of player's mainControl to colorize
local time = 0 -- real time spen
local godmode = Spring.IsGodModeEnabled()
local cheating = Spring.IsCheatingEnabled()
local initialized = false
local res_tooltip_mod_info = table.concat({
	"Give " .. defaultamount,
	"Shift: Give " .. 5 * defaultamount,
	"Ctrl: Give " .. defaultamount / 5,
	"Alt: Give maximum",
	"Alt + Shift: Give max for ".. CONTINUE_TIME .." seconds.",
}, '\n')

local playerlistWindow
local scrollPanel
local stackPanel
local header
local listControls = {}
local controlsByPlayerID = {}
local controlsByTeamID = {}
local updatePlayers = {}
local updateTeams = {}

local resortRequired, recolorRequired, updateButtons = false, false, false


options_path = 'Settings/HUD Panels/Player List'
local helk_path = 'Hel-K/'..widget.GetInfo().name
options_order = {'text_height', 'backgroundOpacity', 'alignToTop', 'give_to_hovered', 'show_res', 'debugging'}
options = {
	text_height = {
		name = 'Font Size (10-18)',
		type = 'number',
		value = DEFAULT_TEXT_HEIGHT,
		min = 10, max = 18, step = 1,
		OnChange = function() initialized = false end,
		advanced = true
	},
	backgroundOpacity = {
		name = "Background opacity",
		type = "number",
		value = 0, min = 0, max = 1, step = 0.01,
		OnChange = function(self)
			if playerlistWindow then
				playerlistWindow.backgroundColor = {1,1,1,self.value}
				playerlistWindow.borderColor = {1,1,1,self.value}
				playerlistWindow:Invalidate()
			end
		end,
	},
	alignToTop = {
		name = "Align to top",
		type = 'bool',
		value = false,
		desc = "Align list entries to top (i.e. don't push to bottom)",
		OnChange = function() resortRequired = true end,
	},
	give_to_hovered = {
		type = 'button',
		value = false,
		name = 'Give To Hovered',
		desc = 'Give the selected units to the hovered team (hotkey needed)',
		action = 'givetohovered',
		OnChange = function(self)
			local underID = WG.PreSelection_GetUnitUnderCursor()
			if underID then
				local teamID = spGetUnitTeam(underID)
				if teamID then
					if teamID ~= myTeamID then
						local controls = controlsByTeamID[teamID]
						if controls then
							if not controls.btnShare:DisableFunc() then
								ShareUnits(nil, teamID)
								return true
							else
								Echo('> Impossible to give units in that situation')
							end
						end
					else
						Echo('> Not giving units to self')
					end
				end
			end
		end,
		path = helk_path,
	},
	show_res = {
		type = 'bool',
		value = displayResources,
		name = 'Show Player Resources',
		OnChange = function(self)
			if displayResources ~= self.value then
				displayResources = self.value
				for i, controls in ipairs(listControls) do
					local entry = controls.entry
					if controls.btnMetal and not controls.entry.isSpec then
						if displayResources then
							controls.btnMetal:RemoveChild(controls.btnMetal.children[1]) -- remove image
							controls.btnMetal:SetCaption('0')
							controls.btnEnergy:RemoveChild(controls.btnEnergy.children[1]) -- remove image
							controls.btnEnergy:SetCaption('0')

							controls.btnMetal:SetVisibility(not controls.btnMetal:DisableFunc() or mySpectating and displayResources and not entry.initSpec)
							controls.btnEnergy:SetVisibility(not controls.btnEnergy:DisableFunc() or mySpectating and displayResources and not entry.initSpec)

						else
							Chili.Image:New {
								name = "imMetal",
								x = 0,
								y = 0,
								right = 0,
								bottom = 0,
								parent = controls.btnMetal,
								keepAspect = true,
								file = IMAGE_METAL,
							}
							controls.btnMetal:SetCaption('')
							Chili.Image:New {
								name = "imEnergy",
								x = 0,
								y = 0,
								right = 0,
								bottom = 0,
								parent = controls.btnEnergy,
								keepAspect = true,
								file = IMAGE_ENERGY,
							}
							controls.btnEnergy:SetCaption('')
							controls.btnMetal:SetVisibility(not controls.btnMetal:DisableFunc() or mySpectating and displayResources and not entry.initSpec)
							controls.btnEnergy:SetVisibility(not controls.btnEnergy:DisableFunc() or mySpectating and displayResources and not entry.initSpec)
						end
					end
				end
			end
		end,
		path = helk_path,
	},
	debugging = {
		name = 'Debug via tooltip',
		type = 'bool',
		value = debugging,
		OnChange = function(self)
			initialized = false
			debugging = self.value
		end,
		dev = true,
		path = helk_path,
	}
}
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function PingTimeOut(pingTime)
	if pingTime < 1 then
		return "Ping " .. (floor(pingTime*1000) ..'ms')
	elseif pingTime > 999 then
		return "Ping " .. ('' .. (floor(pingTime*100/60)/100)):sub(1,4) .. 'min'
	end
	--return (floor(pingTime*100))/100
	return "Ping " .. ('' .. (floor(pingTime*100)/100)):sub(1,4) .. 's' --needed due to rounding errors.
end

local function CpuUsageOut(cpuUsage)
	return "CPU usage " .. ceil(cpuUsage*100) .. "%"
end

local grey = {0.6, 0.6, 0.6, 1}

local function ToGrey(v)
	if v < 0.6 then
		return 0.6 - 0.1*(0.6 - v)
	end
	return 0.6 + 0.1*(v - 0.6)
end

local function ColoredGrey(v)
	if v < 0.6 then
		return 0.6 - 0.6*(0.6 - v)
	end
	return 0.6 + 0.25*(v - 0.6)
end

local function Darken(r, g, b, malus)
	local mul = 1 - malus
	return r * mul, g * mul, b * mul
end

local unicodes = {
	ELECTRICITY = string.char(226, 154, 161),        -- ⚡
	HOUR_GLASS = string.char(226, 143, 179),         -- ⏳
	SKULL = string.char(240, 159, 146, 128),         -- 💀
	ZZZ = string.char(240, 159, 146, 164),           -- 💤
	THEATER_MASKS = string.char(240, 159, 142, 173), -- 🎭
	TWO_PERSONS = string.char(240, 159, 145, 165),   -- 👥
	ARROW_RIGHT = string.char(226, 134, 146),        -- →
	ELECTRIC_PLUG = string.char(240, 159, 148, 140), -- 🔌
	ARROW_RETURN = string.char(226, 134, 170),       -- ↪
	SMALL_SPACE = string.char(226, 128, 134),        -- small space
	HAIR_SPACE = string.char(226, 128, 138),         -- hair space
}

local SYMB_CONNECTING    = unicodes.ELECTRICITY
local SYMB_LAG           = unicodes.HAIR_SPACE .. unicodes.HOUR_GLASS .. unicodes.HAIR_SPACE
local SYMB_DEAD          = unicodes.SKULL
local SYMB_AFK           = unicodes.ZZZ .. unicodes.HAIR_SPACE:rep(2)
local SYMB_SQUAD         = unicodes.TWO_PERSONS
local SYMB_IMPERSONATION = unicodes.THEATER_MASKS
local SYMB_GONE          = unicodes.ARROW_RETURN .. unicodes.SMALL_SPACE-- best pick I think

local function GetName(entry, font)
	local name = entry.name
	if not entry.name:find('unknown') then
		if entry.isDead then
			name = SYMB_DEAD .. name
		end
		if entry.isAfk then
			name = SYMB_AFK .. name
		end
		if entry.isLagging then
			name = SYMB_LAG .. name
		elseif entry.isGone then
			name = SYMB_GONE .. name
		elseif entry.isConnecting then
			name = SYMB_CONNECTING .. name
		end
	end
	if entry.impersonating then
		-- name = coloredString('<', {spGetTeamColor(entry.teamID)}) .. name
		if entry.isSpec then
			name = coloredString(SYMB_IMPERSONATION, grey) .. name
		else
			name = coloredString(SYMB_IMPERSONATION, {spGetTeamColor(entry.teamID)}) .. name
		end
	end
	if not entry.initSpec then
		local squad = spGetPlayerList(entry.initTeamID)
		local playerID = entry.playerID
		for i, thisPlayerID in ipairs(squad) do
			if playerID ~= thisPlayerID or entry.isAiTeam then
				local thisControls = controlsByPlayerID[thisPlayerID]
				local thisEntry = thisControls.entry
				name = coloredString(SYMB_SQUAD, thisEntry.initSpec and grey or {spGetTeamColor(thisEntry.initTeamID)}) .. name
			end
		end
	end

	if not font then
		return name
	end

	return Spring.Utilities.TruncateStringIfRequiredAndDotDot(name, font, MAX_NAME_LENGTH) or name
end


local function GetPlayerTeamColor(entry)
	local teamID = entry.initSpec and entry.teamID or entry.initTeamID
	local r, g, b
	if entry.initSpec then
		r, g, b = grey[1], grey[2], grey[3]
	else
		r, g, b = spGetTeamColor(teamID)
		if entry.isDead and not entry.impersonating then
			r, g, b = ColoredGrey(r), ColoredGrey(g), ColoredGrey(b)
		end
	end
	local darkMalus = (not entry.isActive and 0.20 or 0) * (entry.initSpec and 2 or 1) + (entry.isDead and 0.1 or 0)
	r, g, b = Darken(r, g, b, math.min(darkMalus, 0.4))

	return {r, g, b, 1}
end

local function GetTeamName(teamID)
	local name
	local _, leader, _, isAI = spGetTeamInfo(teamID, false)
	if isAI then
		name = select(2,Spring.GetAIInfo(teamID))

	else
 		name = select(1,Spring.GetPlayerInfo(leader > -1 and leader or teamID, false))
	end
	local playerslist = Spring.GetPlayerList(teamID, true)
	if #playerslist > 1 then
		name = name .. "'s squad"
	end
	return name
end

local function FilterOwnUnits(defIDs, count, toTeam)
	-- local godmode, allyControl, enemyControl = Spring.IsGodModeEnabled()
	-- if not godmode then
	-- 	return count
	-- end
	local myTeamID = Spring.GetMyTeamID()
	local GetUnitTeam = Spring.GetUnitTeam
	local AreTeamsAllied = Spring.AreTeamsAllied
	local tremove = table.remove
	-- Echo("myTeamID:"..tostring(myTeamID), 'count', count, 'godmode', godmode, 'allyControl', allyControl, 'enemyControl', enemyControl)
	for defID, units in pairs(defIDs) do
		local i = 1
		local unitID = units[i]
		while unitID do
			if GetUnitTeam(unitID) ~= myTeamID then
				tremove(units, i)
				count = count - 1
			else
				i = i + 1
			end
			unitID = units[i]
		end
		if not units[1] then
			defIDs[defID] = nil
		end
	end
	return count
end


function ShareUnits(playername, teamID)
	-- ENGINE LIMITATION: sadly it is not possible to give units from other controlled team than the original
	if not teamID then
		Spring.Echo('Player List: Invalid team', teamID, 'to share.')
		return
	end
	playername = playername or GetTeamName(teamID)
	local selcnt = Spring.GetSelectedUnitsCount()
	if selcnt == 0 then
		Spring.Echo('Player List: No units selected to share.')
		return
	end
	local sel = Spring.GetSelectedUnitsSorted()
	selcnt = FilterOwnUnits(sel, selcnt, teamID)
	if selcnt == 0 then
		Echo('Player List: No own units in selection to share.')
		return
	end
	local names = ''
	local typecount = 0
	local maxtypecount = 3
	for defID, t in pairs(sel) do
		local name = UnitDefs[defID].humanName
		if name then
			typecount = typecount + 1
			if typecount > maxtypecount then
				names = names .. '..., '
				break
			else
				names = names .. #t .. ' ' .. name .. ', '
			end
		end
	end
	names = names:sub(1,-3)
	local comment
	if names == "" then
		comment = "gave " .. selcnt .. " units to " .. playername .. "."
	else
		if typecount > maxtypecount then
			names = names .. " ("..selcnt..")"
		end
		comment = "gave " .. names.. " to " .. playername .. "."
	end
	if myTeamID ~= myControls.entry.initTeamID then
		comment = ('['..GetTeamName(myTeamID)..'] ') .. comment
		-- sadly can't work
		-- Echo('> Engine doesn\'t allow to transfer unit from impersonated team')
		-- return
	else 
		comment = 'I ' .. comment
	end

	Spring.SendCommands("say a:" .. comment)
	Spring.ShareResources(teamID, "units")
end
local function GetResource(target, kind)
	local tgtCurr, tgtStor = Spring.GetTeamResources(target, kind)
	if tgtCurr then
		tgtStor = tgtStor - HIDDEN_STORAGE
		local maxfill =  tgtStor - tgtCurr
		return tgtCurr, tgtStor, maxfill
	end
end
local function GiveResource(teamID, target, kind, mod, quiet) -- directly copied from gui_chili_share.lua, the TAB playlist
	-- ENGINE LIMITATION: cannot transfer resource accross different ally team
	local tgtCurr, tgtStor, maxfill = GetResource(target, kind)
	local prefix
	local comment
	if tgtStor == nil then
		Echo('> Engine doesn\'t allow to transfer resource across different ally teams')
		return
	end

	if myTeamID ~= WG.myInitialTeamID or mySpectating then
		prefix = '['..GetTeamName(myTeamID)..'] '
	else 
		prefix = ' I '
	end


	if not mod then
		local alt,ctrl,_,shift = Spring.GetModKeyState()
		if alt and shift then
			mod = "continue"
		elseif alt then
			mod = "all"
		elseif ctrl then
			mod = defaultamount/5
		elseif shift then
			mod = defaultamount*5
		else
			mod = defaultamount
		end
	end
	local name = GetTeamName(target)

	local num = 0

	local currentResourceValue = Spring.GetTeamResources(select(1, teamID, kind))
	if mod == "continue" then
		CONTINUE[kind] = {time = os.clock() + CONTINUE_TIME, target = target, next_time = os.clock() + CONTINUE_FREQUENCY}
		if not quiet then
			Spring.SendCommands("say a:" .. prefix .. "Giving continued " .. kind .. " to " .. name .. " for " .. CONTINUE_TIME .. " seconds.")
			quiet = true
		end
		num = currentResourceValue
	elseif mod == "all" then
		num = currentResourceValue
	elseif mod ~= nil then
		num = min(mod, currentResourceValue)
	else
		return
	end


	local comment
	if tgtStor ~= nil then
		if tgtStor <= 0 then
			if not quiet then
				Echo(name .. " don't have " .. kind .. ' storage')
			end
			return
		end

		if maxfill <= 0 then
			if not quiet then
				Echo(name .. "'s " .. kind .. ' storage is full')
			end
			return
		end

		if num > maxfill then
			num = maxfill
		end
		comment = prefix .. "gave " .. floor(num) .. " " .. kind .. " to " .. name .. "."
	else
		-- sadly can't work
		comment = prefix .. "Trying to give " .. floor(num) .. " " .. kind .. " to ennemy " .. name .. "."
	end
	if not quiet then
		Spring.SendCommands("say a:" .. comment)
	end
	Spring.ShareResources(target, kind, num)
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local col_metal   = {136/255,214/255,251/255,1}
local col_energy  = {.93,.93,0,1}
local red = {1,0,0,1}
local green = {0,1,0,1}
local function Mix(...)
	local col = {0,0,0,0}
	local n = select('#', ...)
	for i = 1, n do
		local c = select(i, ...)
		for j = 1, 4 do
			col[j] = col[j] + c[j]
		end
	end
	for i = 1, 4 do
		col[i] = col[i]/n
	end
	return col
end

local prefix = {
	metal = GetColorChar(col_metal),
	metal_low = GetColorChar(Mix(col_metal, col_metal, red)),
	metal_hi = GetColorChar(Mix(col_metal, col_metal, green)),
	energy = GetColorChar(col_energy),
	energy_low = GetColorChar(Mix(col_energy, col_energy, red)),
	energy_hi = GetColorChar(Mix(col_energy, col_energy, green)),
}
local max = max
local modf = math.modf
local function kformat(num)
	if num >= 1000 then
		local th, cen = modf(num/1000)
		if cen >= 0.1 and th < 10 then
			return th .. 'k' .. modf(cen*10)
		else
			return th .. 'k'
		end
	else
		return num
	end
end
local function ColorResString(num, cur, max, type)
	return prefix[type .. ((cur < num or (max) <= 0) and '_low' or cur > (max) and '_hi' or '')] .. kformat(num)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function Compare(ac, bc)
	local a, b = ac.entry, bc.entry
	-- sorting the specs
	if a.initSpec ~= b.initSpec then
		return b.initSpec
	elseif a.initSpec then
		if a.isActive ~= b.isActive then
			return not b.isActive 
		elseif a.elo ~= b.elo then
			return (a.elo or 0) > (b.elo or 0)
		elseif a.isMe ~= b.isMe then
			return a.isMe
		elseif not not a.name:find('unknown') ~= not not b.name:find('unknown') then
			return not a.name:find('unknown')
		else
			return a.playerID < b.playerID
		end
	end
	-- sorting the allies
	if a.initAllyTeamID ~= b.initAllyTeamID then
		return a.initAllyTeamID < b.initAllyTeamID
	-- sorting the ais
	elseif a.isAiTeam ~= b.isAiTeam then
		return b.isAiTeam
	elseif a.isAiTeam then
		if a.name ~= b.name then
			return a.name < b.name
		else
			return a.initTeamID < b.initTeamID
		end
	-- sorting the players playing
	elseif a.elo ~= b.elo then
		return (a.elo or 0) > (b.elo or 0)
	end
	return a.playerID < b.playerID
end

local function SortEntries()
	if not playerlistWindow then
		return
	end
	if debugging then
		Echo('<< Resorting entries >>')
	end
	table.sort(listControls, Compare)
	
	local toTop = options.alignToTop.value
	local offset = options.text_height.value -5

	local teams = {}
	for i = 1, #listControls do
		local control = listControls[i]
		local userControl = control.mainControl
		local entry = control.entry
		local isPlayer = not entry.initSpec
		-- local teamTxt = tonumber(listControls[i].textAllyTeam.caption)
		local allyTeam = entry.initAllyTeamID + (isPlayer and 1 or 0)
		local thisTeam = teams[allyTeam]

		if not thisTeam then
			thisTeam = {}
			teams[allyTeam] = thisTeam
			thisTeam.count = 1
			thisTeam.aiCount = 0
			if isPlayer then
				thisTeam.elo = entry.elo or 0
			end
			-- local color = entry.allyTeamColor
			thisTeam.color = not isPlayer and grey or {spGetTeamColor(entry.initTeamID)}
		else
			thisTeam.count = thisTeam.count + 1
			if isPlayer then
				thisTeam.elo = thisTeam.elo + (entry.elo or 0)
			end
		end

		if entry.isAiTeam then
			thisTeam.aiCount = thisTeam.aiCount + 1
		end
		if toTop then
			userControl._relativeBounds.top = offset
			userControl._relativeBounds.bottom = nil
		else
			userControl._relativeBounds.top = nil
			userControl._relativeBounds.bottom = offset
		end
		userControl:UpdateClientArea(false)
		
		offset = offset + options.text_height.value + 2
	end

	if toTop then
		header._relativeBounds.bottom = false
		header._relativeBounds.top = 1
	else
		header._relativeBounds.top = false
		header._relativeBounds.bottom = options.text_height.value - header.parent.padding[3] + 1
	end

	local headerCaption = ''

	for _, t in ipairs(teams) do
		local countTxt =  coloredString(t.count, t.color)
		local humanPlayers = t.count - t.aiCount
		headerCaption = headerCaption .. countTxt .. (t.elo>0 and ' (' .. ('%.1f'):format(t.elo/(humanPlayers)/1000) .. ') ' or '') .. 'v '
		-- Echo('team count', _, t.count)
	end
	headerCaption = headerCaption:sub(1,-3)
	if not teams[3] and teams[1] and teams[2] and teams[1].elo>0 and teams[2].elo>0 then
		local avgElo1 = teams[1].elo/teams[1].count
		local avgElo2 = teams[2].elo/teams[2].count
		local avgEloDiff = avgElo1 - avgElo2
		-- local eloDiff = teams[1].elo - teams[2].elo -- not relevant since teams can be uneven
		headerCaption = headerCaption .. ' | elo ~'..(avgEloDiff>0 and '+' or '') ..  ('%d'):format(avgEloDiff)
	end
	local specCount = teams[0] and coloredString(teams[0].count, teams[0].color)
	if specCount then
		headerCaption = headerCaption .. ' | ' .. specCount
	end
	header:SetCaption(headerCaption)
	header.font.autoOutlineColor = false -- keep the outline black no matter which color in the string (much less ugly)
end

local function CorrectUserInfo(info)
	if info.clan and not VFS.FileExists("LuaUI/Configs/Clans/" .. info.clan ..".png") then
		if VFS.FileExists("LuaUI/Configs/Factions/" .. info.clan .. ".png") then
			info.faction, info.clan = info.clan, nil
		elseif VFS.FileExists("LuaUI/Images/flags/" .. info.clan ..".png") then
			info.country, info.clan = info.clan, nil
		end
	end
	if info.faction and not VFS.FileExists("LuaUI/Configs/Factions/" .. info.faction .. ".png") then
		if VFS.FileExists("LuaUI/Images/flags/" .. info.faction ..".png") then
			info.country, info.faction = info.faction, nil
		end
	end
end

local function MergeAndUpdateInfo(info, new_info)
	local changed = false
	for k, v in pairs(new_info) do
		-- Echo('Received info: ' .. k .. ' = ' .. tostring(v) .. ', old: ' .. tostring(info[k]))
		if k == 'icon' and info[k] == '0_0' and v and v ~= '' and v ~= '0_0'
			or v ~= '' and info[k] == nil or info[k] == '' then
			-- Echo('completing info ' .. k .. ' => ' .. tostring(v))
			info[k] = v
			changed = true
		end
	end
	return changed
end



local function UpdateName(entry, controls)
	local colorText = GetPlayerTeamColor(entry)
	controls.textName.font.color = colorText
	controls.textName:SetCaption(GetName(entry, controls.textName.font))
	if entry.isSpec then
		controls.textName.tooltip = not controls.textName.caption:find(entry.name) and entry.name or ''
	else
		controls.textName.tooltip = entry.name .. ' (teamID ' .. entry.initTeamID .. ')'
	end
	if debugging then
		local t = {}
		for k,v in pairs(entry) do
			t[#t+1] = k .. ' = ' .. tostring(v)
		end
		controls.textName.tooltip = controls.textName.tooltip .. '\n' .. table.concat(t, '\n')
	end
	-- controls.textName:SetCaption(controls.textName.caption .. 'A')
	controls.textName:Invalidate()
	if controls.textTeamID then
		controls.textTeamID.font.color = colorText
		controls.textTeamID:SetCaption(entry.teamID)
		controls.textTeamID:Invalidate()
	end
end

local function RecolorEntries()
	for _, controls in pairs(listControls) do
		UpdateName(controls.entry, controls)
	end
end

local function UpdateButtons()
	for i = 1, #listControls do
		local controls = listControls[i]
		local entry = controls.entry
		if controls.btnShare then
			controls.btnShare:SetVisibility(not controls.btnShare:DisableFunc())
			controls.btnMetal:SetVisibility(not controls.btnMetal:DisableFunc() or mySpectating and displayResources and not entry.initSpec)
			controls.btnEnergy:SetVisibility(not controls.btnEnergy:DisableFunc() or mySpectating and displayResources and not entry.initSpec)
		end
	end
end


local function UpdateResources(controls, teamID)
	local mCur, mMax, mPull, mInc, mExp, mShar, mSent, mReci = Spring.GetTeamResources(teamID, "metal")

	if mInc then
		local eCur, eMax, ePull, eInc, eExp, eShar, eSent, eReci = Spring.GetTeamResources(teamID, "energy")

		-- local energyOverdrive = Spring.GetTeamRulesParam(teamID,'OD_energyOverdrive') or 0
		-- local extraEnergyPull = Spring.GetTeamRulesParam(teamID,'extraEnergyPull') or 0
		-- local extraMetalPull  = Spring.GetTeamRulesParam(teamID,'extraMetalPull') or 0
		-- local metalMisc       = Spring.GetTeamRulesParam(teamID,'OD_team_metalMisc') or 0
		-- local metalBase       = Spring.GetTeamRulesParam(teamID,'OD_team_metalBase') or 0
		-- local metalOverdrive  = Spring.GetTeamRulesParam(teamID,'OD_team_metalOverdrive') or 0
		local energyIncome    = Spring.GetTeamRulesParam(teamID, "OD_energyIncome") or 0
		-- local energyMisc      = Spring.GetTeamRulesParam(teamID, "OD_energyMisc") or 0
		-- local energyChange    = Spring.GetTeamRulesParam(teamID, "OD_energyChange") or 0
		-- if eMax < 11000 then
			-- Echo("team: "..teamID, "ePull: "..math.round(ePull), "eInc: "..math.round(eInc), "eExp: "..math.round(eExp), "eReci: "..math.round(eReci), "eShar: "..math.round(eShar), "exEPull: "..extraEnergyPull, "eOD: "..math.round(energyOverdrive), "eInc2: "..math.round(energyIncome), "eMisc: "..math.round(energyMisc), "eChange: "..math.round(energyChange))
			-- Echo("mPull: "..math.round(mPull), "mInc: "..math.round(mInc), "mExp: "..math.round(mExp), "mReci: "..math.round(mReci), "mextraPull: "..math.round(extraMetalPull), "mMisc: "..math.round(metalMisc), "mBase: "..math.round(metalBase), "mOD: "..math.round(metalOverdrive))
		-- end
		controls.btnMetal:SetCaption(ColorResString(tonumber(math.round(mInc + mReci)), mCur, mMax - HIDDEN_STORAGE, 'metal'))
		controls.btnEnergy:SetCaption(ColorResString(tonumber(math.round(max(eInc, energyIncome))), eCur, eMax - HIDDEN_STORAGE, 'energy'))
		controls.mainControl:UpdateLayout()
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local function UpdatePing(playerID, controls, forceUpdate)
	local entry = controls.entry
	local teamID, allyTeamID = entry.teamID, entry.allyTeamID
	local spectator = false
	if displayResources and controls and (controls.btnMetal and controls.btnMetal.visible) then
		UpdateResources(controls, teamID)
	end
	if entry.playerID then
		if entry.playerID == 0 then
			local new_godmode = Spring.IsGodModeEnabled()
			local new_cheating = Spring.IsCheatingEnabled()
			if godmode ~= new_godmode or new_cheating ~= cheating then
				cheating = new_cheating
				godmode = new_godmode
				updateButtons = true
			end
		end
		local playerName, active, _spectator, _teamID, _allyTeamID, pingTime, cpuUsage, country, rank, customKeys = spGetPlayerInfo(entry.playerID, true)
		local info = playerInfo[playerName]
		teamID, allyTeamID = _teamID, _allyTeamID

		if _spectator then
			spectator = true
			teamID, allyTeamID = entry.initTeamID,  entry.initAllyTeamID
		end
		
		entry.isMe = (entry.playerID == myPlayerID)

		local isConnecting = not active and entry.isConnecting
		local isGone = not (active or isConnecting) and (entry.isActive or entry.isGone or (info and info.isGone))

		
		if entry.isActive ~= active
			or entry.isGone ~= isGone
			or entry.isConnecting ~= isConnecting
		then
			entry.isActive = active
			entry.isGone = isGone
			if info then
				info.isGone = isGone
			end
			entry.isConnecting = isConnecting
			UpdateName(entry, controls)
		end

		local pingBucket = (active and max(1, min(5, ceil(min(pingTime, 1) * 5)))) or 6
		if pingBucket ~= entry.pingBucket then
			entry.pingBucket = pingBucket
			controls.imPing.color = pingCpuColors[entry.pingBucket]
			controls.imPing:Invalidate()
		end
		local cpuBucket = (active and max(1, min(5, ceil(cpuUsage * 5)))) or 6
		if forceUpdate or cpuBucket ~= entry.cpuBucket then
			entry.cpuBucket = cpuBucket
			controls.imCpu.color = pingCpuColors[entry.cpuBucket]
			controls.imCpu:Invalidate()
		end
		controls.imCpu.tooltip = CpuUsageOut(cpuUsage)
		controls.imPing.tooltip = PingTimeOut(pingTime)
		if not (entry.isDead or entry.isSpec) then
			local laggedOut = laggingOut[controls.mainControl]
			if laggedOut then
				if pingTime <= LAGOUT_FLASH_THRESHOLD then
					local bg = controls.mainControl.backgroundColor
					if bg[1] ~= 0 then
						bg[1], bg[4] = 0, 0
						controls.mainControl:Invalidate()
					end
					laggingOut[controls.mainControl] = nil
				end
			else
				if pingTime > LAGOUT_FLASH_THRESHOLD then
					laggingOut[controls.mainControl] = time + BLINK_END
				end
			end
		end
		local lagging = ((pingTime > PING_TIMEOUT) and true) or false
		if lagging ~= entry.isLagging then
			entry.isLagging = lagging
			UpdateName(entry, controls)
		end
		local afk = false
		if not entry.initSpec then
			afk = not not spGetPlayerRulesParam(entry.playerID, "lagmonitor_lagging")
		else
			afk = not not playerInfo[entry.name].isAfk
		end
		if afk ~= entry.isAfk then
			entry.isAfk = afk
			UpdateName(entry, controls)
		end

	end
end

local function GetInitialTeam(playerID, teamList, gaiaTeamID) -- unused but working for debugging
	local name, active, isSpec, teamID, allyTeamID = spGetPlayerInfo(playerID)
	local debugging = true
	if debugging then
		Echo('Treating player ' .. name)
	end
	-- edge cases impersonation (player changed team through cheat and reloaded the widget, we're deducing his initial team)
	local initSpec = true
	local initTeamID = 0
	local initAllyTeamID = 0
	local impersonating
	local initTeamFound = false
	for i, teamID in ipairs(teamList) do
		if teamID ~= gaiaTeamID then
			local squad = spGetPlayerList(teamID)
			local _, leader, isDead, isAITeam, side, allyTeamID, customTeamKeys, incomeMult = spGetTeamInfo(teamID, true)
			local initLeader = spGetTeamRulesParam(teamID, 'initLeaderID')
			if debugging then
				Echo('Check team', teamID, "leader:"..tostring(leader)..", initLeader:"..tostring(initLeader)..", isDead:"..tostring(isDead)..", isAITeam:"..tostring(isAITeam)..", side:"..tostring(side)..", allyTeamID:"..tostring(allyTeamID), 'isCommSharing', isCommSharing, 'Squad', #squad)
			end
			if (leader == playerID or initLeader == playerID) and not isAITeam then
				initTeamID = teamID
				initAllyTeamID = allyTeamID
				initSpec = false
				initTeamFound = true
				if debugging then
					Echo('found initial team of ' .. name .. ': ' .. teamID)
				end
			end
			if debugging and impersonating == nil then
				for i, pid in ipairs(squad) do
					if playerID == pid then
						if leader == playerID and not isAITeam then
							impersonating = false
							-- Echo('-Not impersonating nor in squad-')
						else
							
							if isAITeam then
								impersonating = true
								Echo('player ' .. name .. ' is impersonating ' .. select(2, spGetAIInfo(teamID)) ..  ' teamID ' .. teamID)
							else
								-- local isCommsharing = spGetTeamRulesParam(teamID, "isCommsharing")
								local commshare_team_id = spGetPlayerRulesParam(playerID, "commshare_team_id")
								local targetPlayerName = tostring(spGetPlayerInfo(leader))
								if commshare_team_id == teamID then
									Echo('player ' .. name .. ' is in the squad of ' .. targetPlayerName)
									impersonating = false
								else
									Echo('player ' .. name .. ' is impersonating ' .. targetPlayerName .. ' teamID ' .. teamID)
									impersonating = true
								end
							end
						end

						break
					end
				end
			end
			if initTeamFound and (not debugging or impersonating ~= nil) then
				break
			end
		end
	end
	return {initSpec = initSpec, initTeamID = initTeamID, initAllyTeamID = initAllyTeamID}
end

local function UpdateClan(entry, info)
	if info.clan and info.clan ~= "" then
		entry.clan = VFS.FileExists("LuaUI/Configs/Clans/" .. info.clan ..".png") and "LuaUI/Configs/Clans/" .. info.clan ..".png" or nil
	elseif info.faction and info.faction ~= "" then
		entry.clan = VFS.FileExists("LuaUI/Configs/Factions/" .. info.faction .. ".png") and "LuaUI/Configs/Factions/" .. info.faction .. ".png"
	end
	return entry.clan
end

local function UpdateEntry(controls, forceUpdate, isConnecting)
	local entry = controls.entry
	local teamID, allyTeamID = entry.teamID, entry.allyTeamID
	local spectator = false
	local active = true
	local isGone = false
	local entry = controls.entry
	local info
	if displayResources and controls and (controls.btnMetal and controls.btnMetal.visible) then
		UpdateResources(controls, teamID)
	end
	if not entry.initSpec or entry.isAiTeam then
		updateTeams[entry.initTeamID] = nil
	end
	if not entry.isAiTeam then
		updatePlayers[entry.playerID] = nil
		if entry.playerID == 0 then
			local new_godmode = Spring.IsGodModeEnabled()
			local new_cheating = Spring.IsCheatingEnabled()
			if godmode ~= new_godmode or new_cheating ~= cheating then
				cheating = new_cheating
				godmode = new_godmode
				updateButtons = true
			end
		end
		local playerName, _active, _spectator, _teamID, _allyTeamID, pingTime, cpuUsage, country, rank, customKeys = spGetPlayerInfo(entry.playerID, true)
		info = playerInfo[playerName]
		if info then
			isGone = not not info.isGone
			if  forceUpdate then
				if info.name and entry.name ~= info.name then
					if debugging then
						Echo('-- changing name of ' .. entry.name .. ' to ' .. info.name .. ' --')
					end
					entry.name = info.name
					UpdateName(entry, controls)
				end
				country = country~='' and country or info.country~='' and info.country or nil
				if country and entry.country ~= country then
					if debugging then
						Echo('-- changing country for ' .. entry.name .. ' to ' .. country .. ' --')
					end
					entry.country = country
					entry.countryFlag = ("LuaUI/Images/flags/" .. country ..".png")
					entry.countryLong = countryFull[country] or 'Unknown'
					if VFS.FileExists(entry.countryFlag) then
						controls.imCountry.file = entry.countryFlag
						controls.imCountry.color = {1,1,1,1} -- remove the transparency, since we made a placeholder for the image (that would have been blank without transparency)
						controls.imCountry.tooltip = entry.countryLong
						controls.imCountry:Invalidate()
					end
				end
				if info.icon and entry.rank == "LuaUI/Images/LobbyRanks/0_0.png" then
					entry.rank = "LuaUI/Images/LobbyRanks/" .. info.icon .. ".png"
					if debugging then
						Echo('-- changing rank of '.. entry.name .. ' to ' .. info.icon .. ' --')
					end
					controls.imRank.file = entry.rank
					controls.imRank:Invalidate()
				end

				if info.elo and not entry.elo then
					entry.elo = tonumber(info.elo)
					controls.txtElo:SetCaption(('%.1f'):format(entry.elo/1000))
					controls.txtElo.tooltip = entry.elo
					if debugging then
						Echo('-- adding elo of ' .. entry.name .. ': ' .. ('%.1f'):format(entry.elo/1000))
					end
					resortRequired = true
				end
				if not entry.clan then
					if UpdateClan(entry, info) then
						if debugging then
							Echo('-- adding clan/faction of ' .. entry.name .. ': ' .. entry.clan .. ' --')
						end
						controls.imClan.file = entry.clan
						controls.imClan.color = {1,1,1,1} -- remove the transparency, since we made a placeholder for the image (that would have been blank without transparency)
						controls.imClan.tooltip = info.clan
						controls.imClan:Invalidate()
					end
				end
				if debugging then
					for k, v in pairs(info) do
						entry['[info]'..k] = Truncate(v, 25)
					end
				end
			end
		end

		teamID, allyTeamID = _teamID, _allyTeamID

		if _spectator then
			spectator = true
			teamID, allyTeamID = entry.initTeamID,  entry.initAllyTeamID
		end

		if not _active then
			active = false
		end
		
		if forceUpdate then
			UpdatePing(entry.playerID, controls, true)
		end
	end
	local isDead = entry.isDead or not entry.initSpec and spGetTeamRulesParam(entry.initTeamID, 'WasKilled') or false
	local isConnecting = not active and (isConnecting or entry.isConnecting)
	local isGone = not (active or isConnecting) and (entry.isActive or entry.isGone or isGone)

	if forceUpdate
		or entry.teamID ~= teamID
		or entry.allyTeamID ~= allyTeamID
		or entry.isSpec ~= spectator
		or entry.isDead ~= isDead
		or entry.isGone ~= isGone
		or entry.isConnecting ~= isConnecting
		or entry.isActive ~= active
	then
		entry.teamID = teamID
		entry.allyTeamID = allyTeamID
		entry.isSpec = spectator
		entry.isDead = isDead
		entry.isGone = isGone
		if info then
			info.isGone = isGone
		end
		entry.isConnecting = isConnecting
		entry.isActive = active

		entry.impersonating = 
			not entry.initSpec and entry.isSpec and not entry.isDead
			or entry.initSpec and not entry.isSpec
			or not entry.initSpec and entry.initTeamID ~= entry.teamID
			or entry.isDead and not entry.isSpec

		resortRequired = true
		recolorRequired = true
		updateButtons = true
		--
		if controls.btnShare then
			controls.btnShare:SetVisibility(not controls.btnShare:DisableFunc())
			controls.btnMetal:SetVisibility(not controls.btnMetal:DisableFunc() or mySpectating and displayResources and not entry.initSpec)
			controls.btnEnergy:SetVisibility(not controls.btnEnergy:DisableFunc() or mySpectating and displayResources and not entry.initSpec)
		end

	end
end

local function CreateEntry(playerID, initTeamID, initAllyTeamID, initSpec, isAiTeam)
	local isDead = not initSpec and spGetTeamRulesParam(initTeamID, 'WasKilled')
	local entry = {
		playerID = playerID,
		teamID = initTeamID,
		allyTeamID = initAllyTeamID,
		initTeamID = initTeamID,
		initAllyTeamID = initAllyTeamID,
		initSpec = initSpec,
		isAiTeam = isAiTeam,
		isDead = isDead,
		isSpec = initSpec,
	}
	
	local info
	if not isAiTeam then
		local playerName, active, spectator, teamID, allyTeamID, pingTime, cpuUsage, country, rank, customKeys = spGetPlayerInfo(playerID, true)
		 -- in replay there is placeholder 'unknown' for future player
		if playerName == 'unknown' then
			playerName = '<unknown'..playerID..'>'
		end
		country = country ~= '' and country or nil
		-- customKeys.icon = customKeys.icon or rank
		customKeys.country = country

		info = playerInfo[playerName]
		if not info then
			info = {playerID = playerID, name = playerName}
			playerInfo[playerName] = info
		end
		MergeAndUpdateInfo(info, customKeys)

		entry.teamID = teamID
		entry.allyTeamID = allyTeamID

		entry.playerID = playerID
		entry.isMe = entry.playerID == myPlayerID and not isAiTeam
		entry.allyTeamID = allyTeamID
		entry.isAiTeam = false
		entry.isDead = isDead
		entry.isGone = not not info.isGone
		entry.isActive = active
		entry.isSpec = spectator
		entry.impersonating = 
			not entry.initSpec and entry.isSpec and not entry.isDead
			or entry.initSpec and not entry.isSpec
			or not entry.initSpec and entry.initTeamID ~= entry.teamID
			or entry.isDead and not entry.isSpec
		if info.country then
			entry.country = country
			entry.countryFlag = ("LuaUI/Images/flags/" .. info.country ..".png")
			entry.countryLong = countryFull[country] or 'Unknown'
		end
		entry.name = playerName

		entry.rank = ("LuaUI/Images/LobbyRanks/" .. (info.icon or "0_0") .. ".png")
		entry.elo = tonumber(customKeys.elo or info.elo)
		UpdateClan(entry, info)
	else
		entry.name = select(2, spGetAIInfo(initTeamID)) or '<unknownAI' .. initTeamID .. '>'
	end
	if debugging then
		Echo(
			('<< Entry Created for %s %s %s initTeamID %d >>'):format(
				initSpec and 'spectator' or 'player',
				entry.name,
				isAiTeam and 'AI' or 'playerID ' .. playerID,
				initTeamID
			)
		)
	end
	return entry
end


local function CreateControls(playerID, teamID, allyTeamID, isSpec, isAiTeam)
	local offset             = 0
	local offsetY            = 0
	local text_height        = options.text_height.value
	local height             = text_height + 4
	local controls = {}
	controls.entry = CreateEntry(playerID, teamID, allyTeamID, isSpec, isAiTeam)
	local entry = controls.entry

	controls.mainControl = Chili.Panel:New {
		TileImageBK = ":cl:empty.png", -- set no background texture so we can colorize it
		backgroundColor = {0,0,0,0},
		x = 0,
		top = 0,
		bottom = 0,
		right = 0,
		height = height,
		padding = {0, 0, 0, 0},
		parent = scrollPanel,
		keepAspect = false,
	}

	offset = offset + 1
	if not isAiTeam then
		controls.imCountry = Chili.Image:New {
			name = "imCountry",
			color = not (entry.country and VFS.FileExists(entry.countryFlag)) and {0,0,0,0} or nil,
			x = offset,
			y = offsetY,
			width = text_height + 3,
			height = text_height + 3,
			parent = controls.mainControl,
			keepAspect = true,
			file = entry.countryFlag,
			-- tooltip = entry.country and entry.country:match('.+/([^%.]+)') or nil,
			tooltip = entry.country and entry.countryLong,
			HitTest = function(self) return self end,
		}
	end

	offset = offset + text_height + 3

	offset = offset + 1

	controls.imRank = Chili.Image:New {
		name = "imRank",
		x = offset,
		y = offsetY,
		width = text_height + 3,
		height = text_height + 3,
		parent = controls.mainControl,
		keepAspect = true,
		file = entry.rank,
	}

	offset = offset + text_height + 3
	
	offset = offset + 1
	if not isAiTeam then
		controls.imClan = Chili.Image:New {
			backGroundColor = {0,0,0,0},
			color = not entry.clan and {0,0,0,0} or nil,
			name = "imClan",
			x = offset,
			y = offsetY,
			width = text_height + 3,
			height = text_height + 3,
			parent = controls.mainControl,
			keepAspect = true,
			file = entry.clan or '',
			tooltip = entry.clan and entry.clan:match('.+/([^%.]+)') or nil,
			HitTest = function(self) return self end,
		}
	end

	offset = offset + text_height + 3

	offset = offset + 1

	controls.txtElo = Chili.Label:New {
		name = "elo",
		x = offset,
		y = offsetY + 1,
		width = text_height * 1.5,
		bottom = 3,
		parent = controls.mainControl,
		caption = entry.elo and ('%.1f'):format(entry.elo/1000) or '',
		fontsize = text_height,
		fontShadow = true,
		autosize = false,
		tooltip = entry.elo,
		HitTest = function(self) return self end or nil,
	}

	if SHOW_TEAMID then
		offset = offset + text_height + 3


		offset = offset + 15


		-- controls.textAllyTeam = Chili.Label:New {
		-- 	name = "textAllyTeam",
		-- 	x = offset,
		-- 	y = offsetY + 1,
		-- 	right = 0,
		-- 	bottom = 3,
		-- 	-- parent = controls.mainControl,
		-- 	caption = entry.allyTeamID + (isSpec and not isDead and 0 or 1),
		-- 	textColor = entry.allyTeamColor,
		-- 	fontsize = text_height,
		-- 	fontShadow = true,
		-- 	autosize = false,
		-- }

		controls.textTeamID = Chili.Label:New {
			name = "textTeamID",
			x = offset,
			y = offsetY + 1,
			right = 0,
			bottom = 3,
			parent = controls.mainControl,
			caption = entry.teamID,
			textColor = entry.allyTeamColor,
			fontsize = text_height,
			fontShadow = true,
			autosize = false,
		}
		offset = offset + text_height --+ 3
		
		offset = offset + 2
	else
		offset = offset + text_height + 8
	end
	controls.textName = Chili.Label:New {
		name = "textName",
		x = offset,
		y = offsetY + 1,
		-- right = 0,
		bottom = 3,
		align = "left",
		width = MAX_NAME_LENGTH,
		parent = controls.mainControl,
		caption = entry.name,
		textColor = GetPlayerTeamColor(entry),
		fontsize = text_height,
		fontShadow = true,
		autosize = false,
		tooltip = entry.name,
		font = {
			autoOutlineColor = false,
		},
		HitTest = function(self) return self end,
	}
	offset = offset + MAX_NAME_LENGTH

	offset = offset + 1
	controls.btnShare = Chili.Button:New {
		name = "btnShare",
		x = offset + 2,
		y = offsetY + 2,
		width = text_height - 1,
		height = text_height - 1,
		parent = controls.mainControl,
		caption = "",
		tooltip = "Click to share the units you have selected to this player.",
		padding ={0,0,0,0},
		DisableFunc = function(self)
			return mySpectating
				or entry.initSpec
				or entry.initTeamID == myTeamID
				or entry.initAllyTeamID ~= myAllyTeamID and not cheating -- cannot give to ennemy team unless cheating
		end,
		OnClick = {function(self)
			if not self:DisableFunc() then
				ShareUnits(entry.name, entry.teamID)
			end
		end, },
	}

	Chili.Image:New {
		name = "imShare",
		x = 0,
		y = 0,
		right = 0,
		bottom = 0,
		parent = controls.btnShare,
		keepAspect = true,
		file = IMAGE_SHARE,
	}
	controls.btnShare:SetVisibility(not controls.btnShare:DisableFunc())
	offset = offset + text_height + 1


	offset = offset + 1
	controls.btnMetal = Chili.Button:New {
		name = "btnMetal",
		x = offset + 2,
		y = offsetY + 2,
		width = text_height - 1,
		height = text_height - 1,
		parent = controls.mainControl,
		caption = displayResources and "0" or "",
		fontsize = text_height-3,
		tooltip = "",
		padding ={0,0,0,0},
		color = {0,0,0,0},
		DisableFunc = function(self)
			return mySpectating
				or entry.initSpec
				or entry.initTeamID == myTeamID
				or entry.initAllyTeamID ~= myAllyTeamID -- never can give metal/energy across allyteam
		end,
		OnMouseOver = {
			function(self)
				local cur, stor = GetResource(entry.initTeamID, 'metal')
				if cur then
					self.tooltip = ('M:' .. '%d' .. '/' .. '%d'):format(cur, stor) 
					if not self:DisableFunc() then
						self.tooltip = self.tooltip .. '\n' .. res_tooltip_mod_info
					end
					UPDATE_TOOLTIP = {control = self, next_time = os.clock() + 1}
				end
			end
		},
		OnClick = {function(self)
			if not self:DisableFunc() then
				GiveResource(myTeamID, entry.initTeamID, "metal")
				local cur, stor = GetResource(entry.initTeamID, 'metal')
				if cur then
					self.tooltip = ('M:' .. '%d' .. '/' .. '%d'):format(cur, stor) .. '\n' .. res_tooltip_mod_info
				end
			end
		end, },
	}
	if not displayResources then
		Chili.Image:New {
			name = "imMetal",
			x = 0,
			y = 0,
			right = 0,
			bottom = 0,
			parent = controls.btnMetal,
			keepAspect = true,
			file = IMAGE_METAL,
		}
	end
	offset = offset + text_height + 1

	offset = offset + 1
	controls.btnEnergy = Chili.Button:New {
		name = "btnEnergy",
		x = offset + 2,
		y = offsetY + 2,
		width = text_height - 1,
		height = text_height - 1,
		parent = controls.mainControl,
		caption = displayResources and "0" or "",
		fontsize = text_height-3,
		align = 'center',
		tooltip = "",
		padding ={0,0,0,0},
		DisableFunc = function(self)
			return mySpectating
				or entry.initSpec
				or entry.initTeamID == myTeamID
				or entry.initAllyTeamID ~= myAllyTeamID -- never can give metal/energy across allyteam
		end,
		OnMouseOver = {
			function(self)
				local cur, stor = GetResource(entry.initTeamID, 'energy')
				if cur then
					self.tooltip = ('E:' .. '%d' .. '/' .. '%d'):format(cur, stor) 
					if not self:DisableFunc() then
						self.tooltip = self.tooltip .. '\n' .. res_tooltip_mod_info
					end
					UPDATE_TOOLTIP = {control = self, next_time = os.clock() + 1}
				end
			end
		},
		OnClick = {function(self)
			if not self:DisableFunc() then
				GiveResource(myTeamID, entry.initTeamID,"energy")
				local cur, stor = GetResource(entry.initTeamID, 'energy')
				if cur then
					self.tooltip = ('E:' .. '%d' .. '/' .. '%d'):format(cur, stor) .. '\n' .. res_tooltip_mod_info
				end
			end
		end, },
	}
	if not displayResources then
		Chili.Image:New {
			name = "imEnergy",
			x = 0,
			y = 0,
			right = 0,
			bottom = 0,
			parent = controls.btnEnergy,
			keepAspect = true,
			file = IMAGE_ENERGY,
		}
	end
	offset = offset + text_height + 1



	offset = offset + 1
	if not isAiTeam then
		controls.imCpu = Chili.Image:New {
			name = "imCpu",
			x = offset,
			y = offsetY,
			width = text_height + 3,
			height = text_height + 3,
			parent = controls.mainControl,
			keepAspect = true,
			file = IMAGE_CPU,
			color = {1,1,1,1},
		}
		function controls.imCpu:HitTest(x,y) return self end
	end

	offset = offset + text_height
	
	offset = offset + 1
	if not isAiTeam then
		controls.imPing = Chili.Image:New {
			name = "imPing",
			x = offset,
			y = offsetY,
			width = text_height + 3,
			height = text_height + 3,
			parent = controls.mainControl,
			keepAspect = true,
			file = IMAGE_PING,
			color = {1,1,1,1},
		}
		function controls.imPing:HitTest(x,y) return self end
	end

	offset = offset + text_height

	if entry.isAiTeam then
		updateTeams[entry.initTeamID] = max(2, updateTeams[entry.initTeamID] or 0)
	else
		updatePlayers[entry.playerID] = max(2, updatePlayers[entry.playerID] or 0)
	end
	return controls
end

local function UpdatePlayer(playerID, info, isConnecting)
	local controls = controlsByPlayerID[playerID]
	local forceUpdate = not not info
	if not controls then
		local name, active, spectator, teamID, allyTeamID = spGetPlayerInfo(playerID)
		local initSpec = spectator and spGetPlayerRulesParam(playerID, "initiallyPlayingPlayer") ~= 1
		controls = CreateControls(playerID, teamID, allyTeamID, initSpec, false)
		listControls[#listControls + 1] = controls
		if not controlsByTeamID[teamID] then
			controlsByTeamID[teamID] = controls
		end
		controlsByPlayerID[playerID] = controls
		forceUpdate = true
	else
		if debugging then
			Echo('<< UpdatePlayer playerID ' .. playerID .. ' ' .. controls.entry.name .. ' >>')
		end
	end
	updatePlayers[playerID] = 3
end






--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


local function InitializePlayerlist()
	if listControls then
		for i = 1, #listControls do
			if listControls[i].mainControl then
				listControls[i].mainControl:Dispose()
			end
		end
		myControls = nil
		listControls = {}
		controlsByPlayerID = {}
		controlsByTeamID = {}
	end
	local screenWidth, screenHeight = Spring.GetViewGeometry()
	local windowWidth = MAX_NAME_LENGTH + 11*(options.text_height.value or 13) + 40 - (SHOW_TEAMID and 0 or 19)

	local x = screenWidth - windowWidth
	local y = floor(screenHeight/10)
	local width = windowWidth
	local minWidth = windowWidth
	local height

	if playerlistWindow then
		playerlistWindow:Dispose()
		x, y, width, height = playerlistWindow.x, playerlistWindow.y, playerlistWindow.width, playerlistWindow.height
		playerlistWindow = nil
	end

	--// WINDOW
	scrollPanel = Chili.ScrollPanel:New{
		backgroundColor = {0, 0, 0, 0},
		color = {0, 0, 0, 0},
		borderColor = {0, 0, 0, 0},
		-- border = {0,0,0,0},
		width = '100%',
		height = '100%',
		y = 13, 
		bottom = 13,
		-- top = 13,

		-- minHeight = 100,
		-- autosize = true,
		-- scrollbarSize = 6,
		horizontalScrollbar = false,
        padding = {0,-7,0,0},
        -- itemPadding = {0,-7,0,0},
        -- itemMargin = {0,-7,0,0},
        -- margin =  {0,-7,0,0},
        -- itemPadding = {0,-25,0,0},
	}
	-- local stackPanel = Chili.StackPanel:New{height = 800, width = 800--[[, autoResize = true--]]}
	header = Chili.Label:New{
		caption = 'recap',
		bottom = 20,
		fontsize = options.text_height.value,
	}
	playerlistWindow = Chili.Window:New{
		backgroundColor = {0, 0, 0, 0},
		color = {0, 0, 0, 0},
		backgroundColor = {1, 1, 1, options.backgroundOpacity.value},
		borderColor = {1, 1, 1, options.backgroundOpacity.value},
		parent = Chili.Screen0,
		-- margin = {0,13,0,0},
		dockable = true,
		name = "Player List", -- NB: this exact string is needed for HUD preset playerlist handling
		padding = {0, 0, 11, 0},
		x = x,
		y = y,
		width = width,
		minWidth = minWidth,
		height = height,
		clientHeight = floor(screenHeight/2),
		minHeight = 100,
		draggable = false,
		resizable = true,
		tweakDraggable = true,
		tweakResizable = true,
		minimizable = false,

		children = {
			header,
			scrollPanel
		},
	}

	local gaiaTeamID = Spring.GetGaiaTeamID()
	local teamList = Spring.GetTeamList()
	for i = 1, #teamList do
		local teamID = teamList[i]
		if teamID ~= gaiaTeamID then
			local _, leaderID, isDead, isAiTeam, side, allyTeamID = spGetTeamInfo(teamID, false)
			local initLeaderID = spGetTeamRulesParam(teamID, "initLeaderID")
			local controls = CreateControls(initLeaderID, teamID, allyTeamID, false, isAiTeam)
			listControls[#listControls + 1] = controls
			controlsByTeamID[teamID] = controls
			if not isAiTeam then
				controlsByPlayerID[initLeaderID] = controls
				Spring.SendCommands('get_userinfo '..controls.entry.name)
				if initLeaderID == myPlayerID then
					myControls = controls
				end
			end
		end
	end

	for i, playerID in ipairs(spGetPlayerList()) do
		if not controlsByPlayerID[playerID] then
			local controls = CreateControls(playerID, 0, 0, true, false)
			local entry = controls.entry
			listControls[#listControls + 1] = controls
			controlsByPlayerID[playerID] = controls
			Spring.SendCommands('get_userinfo '..controls.entry.name)
			if playerID == myPlayerID then
				myControls = controls
			end

		end
	end
	resortRequired = true
	updateButtons = true
end

local function Initialize()
	Chili = WG.Chili

	if (not Chili) then
		widgetHandler:RemoveWidget()
		return
	end
	WG.playerInfo = WG.playerInfo or {}
	playerInfo = WG.playerInfo
	for k in pairs(laggingOut) do
		laggingOut[k] = nil
	end
	UPDATE_TOOLTIP = false
	InitializePlayerlist()

	Spring.SendCommands("info 0")
	if not Spring.IsReplay() then
		Spring.SendCommands('get_mybattleinfo')
	end
	initialized = true
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------



local pingUpdateTime = 0
function widget:Update(dt)
	if not initialized then
		Initialize()
	end
	for playerID, v in pairs(updatePlayers) do
		UpdateEntry(controlsByPlayerID[playerID], v > 1, v > 2)
	end
	for teamID, v in pairs(updateTeams) do
		UpdateEntry(controlsByTeamID[teamID], v > 1, v > 2)
	end
	if resortRequired then
		SortEntries()
		resortRequired = false
	end
	if recolorRequired then
		RecolorEntries()
		recolorRequired = false
	end
	if updateButtons then
		UpdateButtons()
		updateButtons = false
	end

	time = time + dt
	if next(laggingOut) then
		for mainControl, blink_timeout in pairs(laggingOut) do
			local bg = mainControl.backgroundColor
			local current_red = bg[1]
			local red =  time > blink_timeout and 0.5 or time%BLINK_PERIOD < BLINK_PERIOD/2 and 1 or 0
			if red ~= current_red then
				bg[1], bg[4] = red, red
				mainControl:Invalidate()
			end
		end
	end
	if UPDATE_TOOLTIP then
		local now = os.clock()
		if UPDATE_TOOLTIP.next_time < now then
			local control = UPDATE_TOOLTIP.control
			if not control.state.hovered then
				UPDATE_TOOLTIP = false
			else
				control.OnMouseOver[1](control)
				UPDATE_TOOLTIP.next_time = now + 1
			end
		end
	end
	for kind, cont in pairs(CONTINUE) do
		if cont.target then
			local now = os.clock()
			if cont.next_time < now then
				cont.next_time = now + 1
				GiveResource(myTeamID, cont.target, kind, 'all', true)
				if cont.time < now then
					cont.target = false
				end
			end
		end
	end
	pingUpdateTime = pingUpdateTime + dt
	if pingUpdateTime >= pingUpdatePeriod then
		pingUpdateTime = 0
		for playerID, controls in pairs(controlsByPlayerID) do
			UpdatePing(playerID, controls)
		end
	end
end

function widget:PlayerChanged(playerID)
	if debugging then
		Echo('<< PlayerChanged ' .. controlsByPlayerID[playerID].entry.name .. ' playerID ' .. playerID .. '>>')
	end
	if playerID == myPlayerID then
		myTeamID = Spring.GetMyTeamID()
		myAllyTeamID = Spring.GetMyAllyTeamID()
		mySpectating = Spring.GetSpectatingState()
		updateButtons = true
	end
	updatePlayers[playerID] = 1
end

function widget:PlayerAdded(playerID)
	if debugging then
		Echo('<< PlayerAdded '.. playerID .. ' >>')
	end
	UpdatePlayer(playerID, true)
end

function widget:PlayerRemoved(playerID)
	-- local name, active, spectator, teamID, allyTeamID, pingTime, cpuUsage, country, rank, customKeys = spGetPlayerInfo(playerID, true)
	-- Echo('player',playerID,'REMOVED','name?',name,'playerInfo?',playerInfo[name])
	if debugging then
		Echo('<< PlayerRemoved '.. playerID .. ' ' .. controlsByPlayerID[playerID].entry.name .. ' >>')
	end
	updatePlayers[playerID] = 1
end

function widget:TeamDied(teamID)
	if debugging then
		Echo('<< TeamDied '.. teamID .. ' ' .. controlsByTeamID[teamID].entry.name .. ' >>')
	end
	for i, playerID in ipairs(spGetPlayerList()) do
		local controls = controlsByPlayerID[playerID]
		local entry = controls.entry
		if not entry.initSpec and (entry.initTeamID == teamID or entry.teamID == teamID) then
			updatePlayers[playerID] = 1
		end
	end
	local controls = controlsByTeamID[teamID]
	if controls.entry.isAiTeam then
		updateTeams[teamID] = max(1, updateTeams[teamID] or 0)
	end
end

function widget:TeamChanged(teamID)
	if debugging then
		Echo('<< TeamChanged '.. teamID .. ' ' .. controlsByTeamID[teamID].entry.name .. ' >>')
	end
	for i, playerID in ipairs(spGetPlayerList()) do
		local controls = controlsByPlayerID[playerID]
		local entry = controls.entry
		if entry.initTeamID == teamID or entry.teamID == teamID then
			updatePlayers[playerID] = max(1, updatePlayers[playerID] or 0)
		end
	end
	local controls = controlsByTeamID[teamID]
	if controls.entry.isAiTeam then
		updateTeams[teamID] = max(1, updateTeams[teamID] or 0)
	end

end

function widget:ReceiveUserInfo(new_info, simulated)
	local info = playerInfo[new_info.name]
	local isConnecting = false
	if not simulated then
		isConnecting = true
		CorrectUserInfo(new_info)
	end
	if info then
		MergeAndUpdateInfo(info, new_info)
		new_info = info
	else
		playerInfo[new_info.name] = new_info
	end
	if debugging then
		Echo('>>> Received info ' .. new_info.name .. ' #' .. table.size(new_info) .. ' <<<')
	end

	for i,playerID in ipairs(spGetPlayerList()) do
		local name, active, spectator, teamID, allyTeamID, pingTime, cpuUsage, country, rank, customKeys = spGetPlayerInfo(playerID, true)
		if name == new_info.name then
			if debugging then
				Echo('<< ReceiveUserInfo '.. new_info.name .. ' playerID ' .. playerID .. ' teamID ' .. teamID .. (simulated and ' (simulated)' or '') .. ' >>')
			end
			new_info.playerID = playerID
			UpdatePlayer(playerID, new_info, isConnecting)
			Spring.SendCommands('get_userinfo ' .. name) -- complete the job
			break
		end
	end
end

-- Completing user infos (need Hel-Chobby)
local userKeyOrder = {'name', 'accountID', 'steamID', 'admin', 'isBot', 'avatar', 'icon', 'level', 'skill', 'casualSkill', 'country', 'clan', 'faction', 'isInGame', 'isAfk', 'inGameSince', }
local battleKeyOrder = {
	'title', 'battleID', 'founder',
	'playerCount', 'battleMode', 'engineName',
	'engineVersion', 'gameName', 'mapName',
	'maxPlayers', 'maxEvenPlayers',	'spectatorCount',
	'runningSince',	'lastRunningTime', 'passworded',
	'isMatchMaker',	'isRunning', 'disallowBots',
	'disallowCustomTeams',
	-- 'users',
	-- 'battleAis',
}

function widget:RecvLuaMsg(msg, playerID)
	if msg:find('^afk_changed ') then
		local name, isAfk = msg:match('^afk_changed%s+(%S+)%s+(%S+)')
		if name and isAfk then
			isAfk = isAfk == '1'
			local info = playerInfo[name]
			if info then
				local controls = controlsByPlayerID[info.playerID]
				if controls.entry.initSpec then
					info.isAfk = isAfk
					if debugging then
						Echo('Detected spec changing afk state !!', name, isAfk)
					end
				end
			end
		end
	elseif msg:find('mybattleinfo ') then
		local battleStr = msg:sub(('mybattleinfo '):len()+1)
		local battleArray = string.split(battleStr, '|')
		for i, v in ipairs(battleArray) do
			local k = battleKeyOrder[i]
			if v == 'false' then
				v = false
			elseif v == 'true' then
				v = true
			elseif v == 'nil' then
				v = nil
			elseif tostring(tonumber(v)) == v  then
				v = tonumber(v)
			end
			if k == 'isMatchMaker' then
				isMatchMaker = v
				if debugging then
					Echo('Battle ' .. battleArray[1] .. ' isMatchMaker: ' .. tostring(isMatchMaker))
				end
				break
			end
		end
	elseif msg:find('userinfo ') then
		local userStr = msg:sub(('userinfo '):len()+1)
		local userArray = string.split(userStr, '|')
		local NAME = msg:sub(('userinfo '):len()+1, msg:find('|')-1)
		local userInfo = {}
		for i, v in ipairs(userArray) do
			local k = userKeyOrder[i]
			if v == 'false' then
				v = false
			elseif v == 'true' then
				v = true
			elseif v == 'nil' then
				v = nil
			elseif tostring(tonumber(v)) == v  then
				v = tonumber(v)
			end
			userInfo[k] = v
		end
		if isMatchMaker then
			if userInfo.skill then
				userInfo.elo = userInfo.skill
			end
		else
			if userInfo.casualSkill then
				userInfo.elo = userInfo.casualSkill
			end
		end
		if userInfo.name then
			local info = playerInfo[userInfo.name]
			if not info then
				info = {name = userInfo.name}
				for i, playerID in ipairs(spGetPlayerList()) do
					if spGetPlayerInfo(playerID) == userInfo.name then
						info.playerID = playerID
						break
					end
				end
				playerInfo[userInfo.name] = info
			end
			local changed = MergeAndUpdateInfo(info, userInfo)
			if changed then
				if debugging then
					Echo('<<< Completing ' .. info.name .. 'infos from lobby >>>')
				end
				UpdatePlayer(info.playerID, info, true)
			end
		end
	end
end



function widget:Shutdown()
	Spring.SendCommands("info 1")
	for mainControl in pairs(laggingOut) do
		laggingOut[mainControl] = nil
	end
end

if f then
	f.DebugWidget(widget)
end
