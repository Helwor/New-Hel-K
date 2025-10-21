
function widget:GetInfo()
		return {
		name      = 'HookFuncs2',
		desc      = "Deep Widget functions benchmark",
		author    = "Helwor",
		date      = "Jan 2024",
		license   = "GNU GPL, v2 or later",
		layer     = 10000,
		enabled   = true,  --  loaded by default?
		handler   = true,
		-- api       = true,
}
end

VFS.Include("LuaUI\\Widgets\\Include\\prefab_window.lua")

-- April 2025
	-- removed "Remove" feature with simple right click that was buggy and useless, using CutBranch instead

local debugMode = true
local bannedSource = {
	['LuaUI/Widgets/chili_old/handlers/debughandler.lua'] = true,
	['LuaUI/Widgets/chili/handlers/debughandler.lua'] = true,
	['LuaUI\\Widgets\\chili_old\\handlers\\debughandler.lua'] = true,
	['LuaUI\\Widgets\\chili\\handlers\\debughandler.lua'] = true,

	['LuaUI/Widgets/chili_old/headers/links.lua'] = true,
	['LuaUI/Widgets/chili/headers/links.lua'] = true,
	['LuaUI\\Widgets\\chili_old\\headers\\links.lua'] = true,
	['LuaUI\\Widgets\\chili\\headers\\links.lua'] = true,


	['LuaUI/Widgets/gui_epicmenu.lua'] = true,
	['LuaUI\\Widgets\\gui_epicmenu.lua'] = true,
}
-- Notes:
-- for loop is not detected, except when it use a function => for k,v in pairs(t) do end
if debugMode then
	WG.Code.Reload()
end
local Echo = Spring.Echo
local f = WG.utilFuncs
local debugCycle = 2
local PERIODICAL_CHECK
local debugOnSwitch = not not debugCycle
local AUTO_MUTE = true
local GLOBAL_MUTE_LEVEL = 5
local MAKE_RELOAD_BUTTON = false
local ignoredNames = {
	sethook = true,
	-- [''] = true,
	pairs = true,
	['(for generator)'] = true,
	ipairs = true,
	pcall = true,
	xpcall = true,
	gsub = true,
	byte = true,
	sub = true,
	find= true,
	format = true,
	line = true,
	sol = true,
	match = true,
	clock = true,
	size = true,
	unpack = true,
	type = true,

	xpcall_va = true,
	xpcall = true,
	cdxpcall = true,
	isindexable = true,
	isfunc = true,


	HitTest = true,
	IsAbove = true,
	CallListeners = true,
	LocalToClient = true,

	-- those I'm not quite sure what's happening with them but attempting to wrap them provoke a crash as they do not exist anymore
	-- when hovering/clicking on nodes afterward
	-- IsAbove = true,
	-- HitTest = true,
	['?'] = true, -- this cause a crash when hooking debughandler
}

options = {}
options_path = 'Hel-K/' .. widget:GetInfo().name

options.autoMute = {
	name = 'Auto Mute',
	type = 'bool',
	value = AUTO_MUTE,
	desc = "don't update nodes which execution time is too short to worth working on them",
	OnChange = function(self)
		AUTO_MUTE = self.value
	end,
	noHotkey = true,
}
options.globalMuteLevel = {
	name = 'Global Mute Level',
	type = 'number',
	value = GLOBAL_MUTE_LEVEL,
	min = 1, max = 30, step = 1,
	desc = "Don't go beyond that level in any case",
	OnChange = function(self)
		GLOBAL_MUTE_LEVEL = self.value
		if debugOnSwitch then
			debugCycle = 2
		end
	end,
	tooltip_format = '%d',
	noHotkey = true,
}
options.debugCycle = {
	name = 'Debug Cycle',
	type = 'bool',
	value = debugCycle,
	OnChange = function(self)
		debugCycle = self.value and 2
		debugOnSwitch = not not debugCycle
	end,
	noHotkey = true,
}
options.periodicalCheck = {
	name = 'Periodical Check',
	type ='button',
	desc = 'click to check if some wrap are actives.',
	OnChange = function(self)
		PERIODICAL_CHECK = 0
	end,
	noHotkey = true,
}
options.editNames = {
	name = 'Ignore List',
	type ='table',
	value = ignoredNames,
	-- keep the hardcoded key-value pairs written in here at loading, in case code has been updated or if user removed them in a previous session
	noRemove = true, 
	noHotkey = true,
}
-- 
local UPDATE_RATE = 0.2

local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local spGetModKeyState = Spring.GetModKeyState
local getinfo = debug.getinfo
local modf = math.modf
local sethook = debug.sethook
local concat = table.concat

local tree 
local tree2


local objWin
local header

local CURRENT_NODE
local HOOK_ACTIVE = false
local IN_SCOPE = false
local Node = {}
local T = {}
local knownFuncs = {}
local funcObjCount = 0
local knownDefs = {}
local failedcount = 0
local failedcallercount = 0

local count = 0
local windows = {}



local C_HEIGHT, B_HEIGHT = 15, 22

local ismeta = {
	__index = true,
	__newindex = true,
	__tostring = true,
	__call = true,
	__lt  = true,
	__le  = true,
	__gt  = true,
	__ge  = true,
	__eq  = true,
	__add = true,
	__sub = true,
	__mul = true,
	__mod = true,
	__gc = true,
}

local UNKNOWN = '??'
local NOINFO = UNKNOWN .. ' l:' .. UNKNOWN .. ' (' .. UNKNOWN .. ')'
local NO_CURRENT_LINE = {currentline = -1}
local DUM_FUNC = {func=function()end}
local EMPTY_TABLE = {}

local MUTE_LEVEL = false
local p_check = 0
local UTILS = {}
local BRANCH_WRAPS = {}
local CODES = {}
local trace
local level = 0
local stackLVL = {}
local redNuances = {count = 8, apply = function() end} -- unused for now but op
local greyed = ''


do ------------------ OFF TOPIC CODE ANALYSIS DRAFT -------------------------

	local source =  getinfo(1,'S').source

	local source = "LuaUI\\Widgets\\UtilsFunc.lua"



	-- WG.Code.Reload()
	--------- IMPLEMENT GetUncommentedAndBlanked3, GetLines, ()
	local function RemoveAll(code) -- uncomments and blank strings of 9K lines of code in 0.05 sec (0.046 for only uncommenting)
		-- version with two char check, more complex but (faster not)
		-- if not code then
		-- 	code = WG.Code:GetCode(source or "LuaUI\\Widgets\\UtilsFunc.lua")
		-- end
		-- to not get fooled by escaped char we convert them into their byte value
		code = code:codeescape()
		
		-- to acertain validity of char in code we check in precise order, short circuiting all the rest of checks
			--> block --> end of block
			--> comment --> check for block or end of line
			--> string --> end of string
			--> comment start
			--> string start
			--> block start

		local pos = 1

		local pat = '()([\'\"%[%]%-\n])(.)'
		local strStart, commentStart, blockStart = false, false, false
		local bracket, endBracket, minus = false, false, false


		local n = 0
		local parts = {}

		----- debugging
		-- local count = 0
		-- local blockCount, stringCount, commentCount = 0,0,0
		-- local time = spGetTimer()
		------

		code:gsub(
			pat,
			function(p, s1, s2)
				-- waiting ends of started patterns 
				-- count = count + 1
				-- BLOCK PAIRING
				-- if count < 5 then
				-- 	Echo(p, s1:readnl(),s2:readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
				-- end
				if blockStart then
					if s1 == ']' and (s2 == ']' or endBracket == p-1) then
						if endBracket == p-1 then
							p = p - 1
						end
						blockStart = false
						-- blockCount = blockCount + 1
						if commentStart then
							-- keep only newlines in the block comment
							local _, nl = code:sub(pos,p):gsub('\n','')

							if nl==0 then -- check if both ends will be touching and conflicting
								if code:sub(pos-3,pos-3):find('%w') and code:sub(p+2,p+2):find('%w') then
									n = n + 1
									parts[n] = ' '
								end
							else
								n = n + 1
								parts[n] = ('\n'):rep(nl)
							end
							commentStart = false
							-- commentCount = commentCount + 1
							pos = p + 2 -- continue after brackets
						else
							if blankString then
								n = n + 1
								parts[n] = code:sub(pos, p-1):decodeescape():gsub('[^\n]',' ') -- blank the string in brackets, keep brakets, keep newlines
								pos = p -- continue at brackets
							end
						end
					elseif s2 == ']' then
						endBracket = p + 1 -- signal pos of the last found bracket in case
					end
				-- COMMENT ENDING
				elseif commentStart then
					if s1 == '\n' then
						commentStart = false
						-- commentCount = commentCount + 1
						pos = p
						if s2 == '-' then
							minus = p+1
						end
					elseif s1 == '[' and (
						bracket == p-1 and commentStart == p-3
						or s2 == '[' and commentStart == p-2
						)
					then
						blockStart = true
					elseif s2 == '\n' then
						commentStart = false
						-- commentCount = commentCount + 1
						pos = p + 1
					end
				-- QUOTE PAIRING
				elseif strStart then
					if s1 == strStart then  -- finish quote pairing
						strStart = false
						-- stringCount = stringCount + 1
						if blankString and p-pos > 0 then
							n = n + 1
							-- parts[n] = (' '):rep(p-pos) -- blank the string, don't include the quote // rep is 3.5x faster than gsub to make blank string 
							parts[n] = (' '):rep(code:sub(pos,p-1):decodeescape():len()) -- avoid the escaping giving us wrong len
							pos = p
						end
						if s2 == '-' then
							minus = p+1 -- maybe found a start of comment
						end
					elseif s2 == strStart then
						strStart = false
						-- stringCount = stringCount + 1
						if blankString then
							n = n + 1
							-- parts[n] = (' '):rep(p-pos+1) -- blank the string, don't include the quote // rep is 3.5x faster than gsub to make blank string 
							parts[n] = (' '):rep(code:sub(pos,p):decodeescape():len()) -- avoid the escaping giving us wrong len
							pos = p + 1
						end
					end
				-- DETECTING STARTS
				-- checking comment start, then string start then block start
				elseif s1 == '-' then
					if minus == p-1 then 
						commentStart = p-1
						n = n + 1
						parts[n] = code:sub(pos, p-2) -- pick before the comment
						pos = p+1 -- set after the comment
						if s2 == '\n' then
							commentStart = false
							-- commentCount = commentCount + 1
						elseif s2 == '[' then
							bracket = p+1
						end
					elseif s2 == '-' then 
						commentStart = p
						n = n + 1
						parts[n] = code:sub(pos, p-1) -- pick before the comment
						pos = p+2  -- set after the comment
					else
						minus = p
					end
				elseif s1 == '"' or s1 == "'" then
					if s2 == s1 then -- nothing to do, adjacent pair of same quotes
						return
					end
					strStart = s1 -- quote pairing start
					n = n + 1
					parts[n] = code:sub(pos,p)-- include the quote
					pos = p+1 
				elseif s1 == '[' then
					if s2 == '[' then
						blockStart = true
						n = n + 1
						if bracket == p-1 then
							parts[n] = code:sub(pos, p) -- include the brackets
							pos = p+1
						else
							parts[n] = code:sub(pos, p+1) -- include the brackets
							pos = p+2
						end
					elseif s2 == '"' or s2 == "'" then
						strStart = s2 -- quote pairing start
						n = n + 1
						parts[n] = code:sub(pos,p+1)-- include the quote
						pos = p+2
					end
				elseif s1 == '\n' then
					if s2 == '-' then
						minus = p+1
					elseif s2 == ']' then
						endBracket = p+1
					end
				end
			end
		)

		if not commentStart then
			n = n + 1
			parts[n] = code:sub(pos)
		end
		code = table.concat(parts):decodeescape()

		-- time = spDiffTimers(spGetTimer(),time)
		-- Echo("TIME ", time, 'count',count,'parts',n)
		return code, time
	end
	local function RemoveAll2(code) --  
		-- version checking only one char at a time, less convoluted but a tiny bit (less fast too not)

		-- to acertain validity of char we check in precise order, short circuiting all the rest of checks
			--> block --> end of block
			--> comment --> check for block or end of line
			--> string --> end of string
			--> comment start
			--> string start
			--> block start

		local pos = 1
		local t = {}
		local pat = '()([\'\"%[%]%-\n])'
		local strStart, commentStart, blockStart = false, false, false
		local bracket, endBracket, minus = false, false, false



		local n = 0
		local parts = {}
		-- counts are only for debugging and can be commented out
		local count = 0
		local blockCount, stringCount, commentCount = 0,0,0

		code = code:codeescape() 
		local time = spGetTimer()
		code:gsub(
			pat,
			function(p, s)
				-- BLOCK PAIRING
				count = count + 1
				-- if count < 5 then
				-- 	Echo(p, code:at(p):readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
				-- end
				if blockStart then
					if s == ']' then

						if endBracket == p - 1 then
							blockStart = false
							blockCount = blockCount + 1
							if commentStart then -- we end the block comment
								commentStart = false
								commentCount = commentCount + 1
								-- keep only newlines in the block comment
								local _, nl = code:sub(pos,p):gsub('\n','')
								if nl==0 then -- check if both ends will be touching and conflicting
									if code:sub(pos-3,pos-3):find('%w') and code:sub(p+1,p+1):find('%w') then
										n = n + 1
										parts[n] = ' '
									end
								else
									n = n + 1
									parts[n] = ('\n'):rep(nl)
								end
								pos = p + 1 -- continue after brackets
							else
								if blankString then
									n = n + 1
									parts[n] = code:sub(pos, p-2):decodeescape():gsub('[^\n]',' ') -- blank the string in brackets, keep newlines, keep brakets
									-- Echo('continue at bracket ?',code:sub(pos, p-2):readnl(),code:sub(p-1,p):readnl())
									pos = p-1 -- continue at brackets
								end
							end
						else
							endBracket = p
						end
					end
				-- COMMENT ENDING
				elseif commentStart then
					if s == '\n' then
						commentStart = false
						commentCount = commentCount + 1
						pos = p
					elseif s == '[' then 
						if commentStart == p-3 and bracket == p-1 then
							blockStart = true-- we're in block comment
						elseif commentStart == p-2 then
							bracket = p
						end
					end
				-- QUOTE PAIRING
				elseif strStart then
					if s == strStart then  -- finish quote pairing
						strStart = false
						stringCount = stringCount + 1
						-- if count < 5 then
						-- 	Echo('check', blankString,pos, p-1,code:sub(pos, p-1))
						-- end
						if blankString and p-pos > 0 then
							n = n + 1
							-- parts[n] = (' '):rep(p-pos) -- blank the string, don't include the quote // rep is 3.5x faster than gsub to make blank string but the escaping might give us the wrong len
							parts[n] = (' '):rep(code:sub(pos, p-1):decodeescape():len()) -- blank the string, don't include the quote //
							pos = p
						end
					end
				-- DETECTING STARTS
				-- checking comment start, then string start then block start
				elseif s == '-' then
					-- Echo('check',p,'minus',minus)
					if minus == p-1 then 
						commentStart = p-1
						n = n + 1
						parts[n] = code:sub(pos, p-2) -- pick before the comment
						pos = p+1 -- set after the comment
					else
						minus = p
					end
				elseif s == '"' or s == "'" then
						strStart = s -- quote pairing start
						n = n + 1
						parts[n] = code:sub(pos,p) -- include the quote
						pos = p+1 
				elseif s == '[' then
					if bracket == p-1 then
						blockStart = true
						n = n + 1
						parts[n] = code:sub(pos, p) -- include the brackets
						pos = p+1
					else
						bracket = p
					end
				end
			end
		)

		if not commentStart then
			n = n + 1
			parts[n] = code:sub(pos)
		end


		code = table.concat(parts)
		code = code:decodeescape()
		-- Echo("code is ", code)
		time = spDiffTimers(spGetTimer(),time)
		Echo("TIME 2 ", time, 'count',count,'parts',n)
		-- Echo("stringCount, blockCount, commentCount is ", stringCount, blockCount, commentCount)
		-- Echo("strStart, blockStart, commentStart is ", strStart, blockStart, commentStart)

		-- Spring.SetClipboard(code)
		return code, time
	end

	local function GetUncommentedAndBlanked(source, code, tellTime) -- uncomments and blank strings of 9K lines of code in 0.02 sec! but code is ugly
		-- version with two char check, more complex but faster

		if not code then
			code = WG.Code:GetCode(source or "LuaUI\\Widgets\\UtilsFunc.lua")
		end
		-- to not get fooled by escaped char we convert them into their byte value
		
		-- to acertain validity of char in code we check in precise order, short circuiting all the rest of checks
			--> block --> end of block
			--> comment --> check for block or end of line
			--> string --> end of string
			--> comment start
			--> string start
			--> block start

		-- gsub is fastest, avoiding using find is much better
		local pos = 1

		local pair
		local pat = '()([\\\'\"%[%]%-\n])(.)'
		local strStart, commentStart, blockStart = false, false, false
		local bracket, endBracket, minus = false, false, false

		local n = 0
		local parts = {}
		local strings, sc, blocks = {}, 0, {}
		local lens = {}

		-- counts are only for debugging and can be commented out
		local count = 0
		local blockCount, stringCount, commentCount = 0,0,0
		local index = {}
		local time = spGetTimer()

		code:gsub(
			pat,
			function(p, s1, s2)
				count = count + 1
				-- waiting ends of started patterns 
				-- BLOCK PAIRING
				-- if count < 5 then
				-- 	Echo(p, s1=='\n' and '\\n' or s1,s2=='\n' and '\\n' or s2, "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
				-- end
				if escaped then
					if escaped == p-1 then
						escaped = false
						s1 = s2
						s2 = false
					else
						escaped = false
					end
				end
				if blockStart then
					if s1 == ']' and (s2 == ']' or endBracket == p-1) then
						if endBracket == p-1 then
							p = p - 1
						end
						blockStart = false
						blockCount = blockCount + 1
						if commentStart then
							-- keep only newlines in the block comment
							local _, nl = code:sub(pos,p):gsub('\n','')

							if nl==0 then -- check if both ends will be touching and conflicting
								if code:sub(pos-3,pos-3):find('%w') and code:sub(p+2,p+2):find('%w') then
									n = n + 1
									parts[n] = ' '
								end
							else
								n = n + 1
								parts[n] = ('\n'):rep(nl)
							end
							commentStart = false
							commentCount = commentCount + 1
							pos = p + 2 -- continue after brackets
						else
							n = n + 1
							parts[n] = code:sub(pos, p-1)
							sc = sc + 1
							strings[sc] = n -- note position in the table parts
							blocks[n] = true
							pos = p -- continue at brackets
						end
					elseif s2 == ']' then
						endBracket = p + 1 -- signal pos of the last found bracket in case
					end
				-- COMMENT ENDING
				elseif commentStart then
					if s1 == '\n' then
						commentStart = false
						commentCount = commentCount + 1
						pos = p
						if s2 == '-' then
							minus = p+1
						end
					elseif s1 == '[' and (
						bracket == p-1 and commentStart == p-3
						or s2 == '[' and commentStart == p-2
						)
					then
						blockStart = true
					elseif s2 == '\n' then
						commentStart = false
						commentCount = commentCount + 1
						pos = p + 1
					end
				-- QUOTE PAIRING
				elseif strStart then
					if s1 == '\\' then
						escaped = p
					elseif s1 == strStart then  -- finish quote pairing
						strStart = false
						stringCount = stringCount + 1
						if p-pos > 0 then
							n = n + 1
							parts[n] = code:sub(pos, p-1) -- isolate string and note position in the table parts
							sc = sc + 1
							strings[sc] = n
							lens[sc] = p-pos
							pos = p
						end
						if s2 == '-' then
							minus = p+1 -- maybe found a start of comment
						elseif s2 == '\\' then
							escaped = p+1
						end
					elseif s2 == strStart then
						strStart = false
						stringCount = stringCount + 1
						n = n + 1
						parts[n] = code:sub(pos, p) -- isolate string and note position in the table parts
						sc = sc + 1
						strings[sc] = n
						lens[sc] = p-pos+1
						pos = p + 1
					elseif s2 == '\\' then
						escaped = p+1
					end
				-- DETECTING STARTS
				-- checking comment start, then string start then block start
				elseif s1 == '-' then
					if minus == p-1 then 
						commentStart = p-1
						n = n + 1
						parts[n] = code:sub(pos, p-2) -- pick before the comment
						pos = p+1 -- set after the comment
						if s2 == '\n' then
							commentStart = false
							commentCount = commentCount + 1
						elseif s2 == '[' then
							bracket = p+1
						end
					elseif s2 == '-' then 
						commentStart = p
						n = n + 1
						parts[n] = code:sub(pos, p-1) -- pick before the comment
						pos = p+2  -- set after the comment
					else
						minus = p
						-- Echo('note minus',minus)
					end
				elseif s1 == '"' or s1 == "'" then
					if s2 == s1 then -- nothing to do, adjacent pair of same quotes
						return
					end
					strStart = s1 -- quote pairing start
					n = n + 1
					parts[n] = code:sub(pos,p)-- include the quote
					pos = p+1 
					if s2 == '\\' then
						escaped = p+1
					end
				elseif s1 == '[' then
					if s2 == '[' then
						blockStart = true
						n = n + 1
						if bracket == p-1 then
							parts[n] = code:sub(pos, p) -- include the brackets
							pos = p+1
						else
							parts[n] = code:sub(pos, p+1) -- include the brackets
							pos = p+2
						end
					elseif s2 == '"' or s2 == "'" then
						strStart = s2 -- quote pairing start
						n = n + 1
						parts[n] = code:sub(pos,p+1)-- include the quote
						pos = p+2
					end
				elseif s1 == '\n' then
					if s2 == '-' then
						minus = p+1
					elseif s2 == ']' then
						endBracket = p+1
					end
				end
			end
		)


		if not commentStart then
			n = n + 1
			parts[n] = code:sub(pos)
		end


		local uncommented = table.concat(parts) 
		time = spDiffTimers(spGetTimer(),time)
		local time2 = spGetTimer()
		for i=1, sc do -- substitute the string with spaces (or newline)
			local n = strings[i]
			local part = parts[n]
			if blocks[n] then
				local _, nl = part:gsub('\n','')
				parts[n] = ('\n'):rep(nl)
			else
				parts[n] = (' '):rep(lens[i])
			end
		end
		local blanked = table.concat(parts)
		time2 = spDiffTimers(spGetTimer(),time2)
		if tellTime then
			Echo("TIME B ", time,time2, 'count',count,'parts',n,'strings parts',sc,'uncommented == blanked len',uncommented:len()==blanked:len())
		end
		-- Echo("stringCount, blockCount, commentCount is ", stringCount, blockCount, commentCount)
		-- Echo("strStart, blockStart, commentStart is ", strStart, blockStart, commentStart)

		-- Spring.SetClipboard(code)
		return uncommented, blanked, time
	end


	local function BlankStrings(source, code, tellTime) -- need uncommenting first
		if not code then
			code = WG.Code:GetCode(source or "LuaUI\\Widgets\\UtilsFunc.lua")
		end
		-- Echo("code:len() is ", code:len())

		-- to acertain validity of char we check in precise order, short circuiting all the rest of checks
			--> block --> end of block
			--> string --> end of string
			--> string start
			--> block start

		-- gsub is fastest, avoiding using find is much better
		local pos = 1
		local t = {}
		local pat = '()([\\\'\"%[%]])'
		local strStart, blockStart = false, false
		local bracket, endBracket = false, false
		local escaped
		if code:find('\r') then
			code = code:removereturns()
		end


		local n = 0
		local parts = {}
		-- counts are only for debugging and can be commented out
		-- local count = 0
		-- local blockCount, stringCount = 0,0

		local t = {}

		local time = spGetTimer()
		code:gsub(
			pat,
			function(p, s)
				-- BLOCK PAIRING
				-- count = count + 1
				-- if count < 5 then
				-- 	Echo(p, code:at(p):readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
				-- end
				if blockStart then
					if s == ']' then
						if endBracket == p - 1 then
							blockStart = false
							-- blockCount = blockCount + 1
							local _, nl = code:sub(pos, p-2):gsub('\n','')
							if nl > 0 then
								n = n + 1
								parts[n] = ('\n'):rep(p-pos-1)
							end
							pos = p-1 -- continue at brackets
						else
							endBracket = p
						end
					end
				-- QUOTE PAIRING
				elseif strStart then
                    if escaped then
                        if escaped == p-1 then
                            escaped = false
                            return
                        else
                            escaped = false
                        end
                    end
					if s == '\\' then
						escaped = p
					elseif s == strStart then  -- finish quote pairing
						strStart = false
						if p-pos > 0 then
							n = n + 1
							parts[n] = (' '):rep(p-pos) -- blank the string, don't include the quote // rep is 3.5x faster than gsub to make blank string but the escaping might give us the wrong len
							pos = p
						end
					end
				-- DETECTING STARTS
				elseif s == '"' or s == "'" then
						strStart = s -- quote pairing start
						n = n + 1
						parts[n] = code:sub(pos,p) -- include the quote
						pos = p+1 
				elseif s == '[' then
					if bracket == p-1 then
						blockStart = true
						n = n + 1
						parts[n] = code:sub(pos, p) -- include the brackets
						pos = p+1
					else
						bracket = p
					end
				end
			end
		)

		n = n + 1
		parts[n] = code:sub(pos)


		code = table.concat(parts)


		-- Echo("code is ", code)
		time = spDiffTimers(spGetTimer(),time)
		if tellTime then
			Echo("TIME BLKFAST ", time, 'count',count,'parts',n)
		end
		return code, time
	end

	local function Slowest2(code)
	    local commentSym ='%-%-'
	    local blockSym = '%[%['
	    local endBlockSym = '%]%]'
	    
	    
	    local time = spGetTimer()
	    if code:find('\r') then
	    	code = code:removereturns()
	    end
	    -- as they are rare, we isolate blocks to treat the rest easily
	    local parts, n = {}, 0
	    local count = 0
	    local pos = 1
	    local count = 0
	    local remaining = 0
	    




	    local lonely = 0

	    local function removecommentlines(code)
			local pat = '()([\\\'\"%-\n])'
			local comment, str = false, false
			local minus = false
			local escaped = false

	    	local subparts, sub = {}, 0
	    	local pos = 1
	        code:gsub(
	        	pat,
	        	function(p, s)
	        		if comment then
	        			if s == '\n' then
	        				comment = false
	        				pos = p
	        			end
	        		elseif str then
	        			if escaped == p-1 then
	        				-- skip
	        			elseif s == '\\' then
	        				escaped = p
	        			elseif str == s then
	        				str = false
        					-- sub = sub + 1
        					-- subparts[sub] = code:sub(pos, p-1)
	        				-- pos = p
	        			end
	        		elseif s == '-' then
	        			if minus == p - 1 then
	        				comment = p - 1
	        				if p>2 then
	        					sub = sub + 1
	        					subparts[sub] = code:sub(pos, p-2)
	        					pos = p-2
	        				end
	        			end
	        			minus = p
	        		elseif s == '\'' or s == '\"' then
	        			str = s
	        		end
	        	end
	        )
	        sub = sub + 1
	        subparts[sub] = code:sub(pos)
	        return table.concat(subparts)
	    end


	    -- Spring.SetClipboard(removecommentlines(1,1000))
	    -- if true then
	    --  return
	    -- end
	    local pat = '()([\"\'%-])'
	    local function verify(pos)
	        local sol = code:sol(pos)
	        local strStart, minus, inComment
	        code:sub(sol,pos-1):gsub(
	            pat,
	            function(p,s)
	                if inComment then
	                    return false
	                elseif strStart then
	                    if s == strStart then
	                        strStart = false
	                    end
	                elseif s== '-' then
	                    if minus == p-1 then
	                        inComment = p
	                    else
	                        minus = p
	                    end
	                else
	                    strStart = s
	                end
	            end
	        )
	        return inComment and inComment + sol - 1, strStart
	    end
	    local pos = 1
	    local block, b = {}, 0
	    local patBlock = blockSym .. '.-' .. endBlockSym
	    local blkStart, blkEnd = code:find(blockSym .. '.-' .. endBlockSym)

	    local tries = 0
	    local done = 0
	    while blkStart do
	        tries = tries + 1 if tries > 1000 then Echo('WRONG LOOP BLK') break end
	        local inComment, inString = verify(blkStart)
	        -- Echo("inComment, inString is ", inComment, inString,'start end', blkStart, blkEnd)
	        if inComment then
	            if inComment == blkStart-1 then
	                -- b = b + 1 block[b] = code:sub(blkStart, blkEnd)
	                if done < 1000 then
	                    done = done + 1
	                    n = n + 1
	                    -- -- Echo('==',pos,blkStart - 3,'l',code:nline(pos),code:nline(blkStart))
	                    local code = code:sub(pos, blkStart - 3)
	                    -- code = removecommentlines(code)
	                    parts[n] = removecommentlines(code) -- treat before the block
	                else
	                    n = n + 1
	                    -- -- Echo('==',pos,blkStart - 3,'l',code:nline(pos),code:nline(blkStart))
	                    local code = code:sub(pos, blkStart - 3)
	                    parts[n] = code

	                end
	                -- Echo('block comment',n,code:sub(blkStart-2,blkEnd))
	                -- parts[n] = ('\n'):rep(code:sub(blkStart-2,blkEnd):gsub('\n',''))

	                -- parts[n] = code:sub(blkStart-2,blkEnd):gsub('[^%[%]]','-')
	                local _,nl = code:sub(blkStart-2,blkEnd):gsub('\n','')
	                if nl > 0 then
	                    n = n + 1
	                    parts[n] = ('\n'):rep(nl)
	                elseif code:sub(blkStart-3,blkStart-3):find('%w') and code:sub(blkEnd+1,blkEnd+1):find('%w') then
	                    n = n + 1
	                    parts[n] = ' '
	                end
	                pos = blkEnd+1
	                blkStart, blkEnd = code:find(patBlock, pos)
	            else
	                local p = code:find('\n',inComment)
	                blkStart, blkEnd = code:find(patBlock, p+1)
	            end
	        elseif inString then
	            local p = code:find(inString,blkStart)
	            blkStart, blkEnd = code:find(patBlock, p+1)
	        else
	            -- n = n + 1
	            -- b = b + 1 block[b] = code:sub(blkStart, blkEnd)
	            -- parts[n] = removecommentlines(pos, blkStart - 1)

	            -- Echo('block ',n,code:sub(blkStart, blkEnd))
	            n = n + 1
	            parts[n] = code:sub(blkStart, blkEnd)
	            pos = blkEnd+1
	            blkStart, blkEnd = code:find(patBlock, blkEnd+1)

	        end
	    end
	    -- Echo("pos is ", pos,'parts',n)
	    n = n + 1
	    local c = code:sub(pos)
	    parts[n] = removecommentlines(c)
	    code = table.concat(parts)
	    Echo('lonely',lonely)

	    -- Echo('blocks',b)
	    -- Spring.SetClipboard(block[1])
	    time = spDiffTimers(spGetTimer(),time)
		Echo("TIME FS2 ", time,'parts',n)

	    return code
	end


	local function GetUncommentedAndBlanked3(source, code, tellTime) -- only checking one char at a time, 9K lines in 0.035 without blank string and 0.04 with 
		-- version checking only one char at a time, less convoluted but a tiny bit less fast too
		if not code then
			code = WG.Code:GetCode(source or "LuaUI\\Widgets\\UtilsFunc.lua")
		end

        if code:find('\r') then
            code = code:removereturns()
        end
		-- to acertain validity of char we check in precise order, short circuiting all the rest of checks
			--> block --> end of block
			--> comment --> check for block or end of line
			--> string --> end of string
			--> comment start
			--> string start
			--> block start

		-- gsub is fastest, avoiding using find is much better
		local pos = 1
		local pat = '()([\\\'\"%[%]%-\n])'
		local strStart, commentStart, blockStart = false, false, false
		local bracket, endBracket, minus = false, false, false
		local escaped = false

		-- code = code:codeescape()
		local n = 0
		local parts = {}
		local strings, sc, blocks = {}, 0, {}
		-- counts are only for debugging and can be commented out
		-- local count = 0
		-- local blockCount, stringCount, commentCount = 0,0,0
		local lens = {}
		local time = spGetTimer()
		code:gsub(
			pat,
			function(p, s)
				-- BLOCK PAIRING
				-- count = count + 1
				-- if count < 5 then
				-- 	Echo(p, code:at(p):readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
				-- end


				if blockStart then
					if s == ']' then

						if endBracket == p - 1 then
							blockStart = false
							-- blockCount = blockCount + 1
							if commentStart then -- we end the block comment
								commentStart = false
								-- commentCount = commentCount + 1
								-- keep only newlines in the block comment
								local _, nl = code:sub(pos,p):gsub('\n','')
								if nl==0 then -- check if both ends will be touching and conflicting
									if code:find('^%w',pos-3) and code:find('^%w',p+1) then
										n = n + 1
										parts[n] = ' '
									end
								else
									n = n + 1
									parts[n] = ('\n'):rep(nl)
								end
								pos = p + 1 -- continue after brackets
							else
								n = n + 1
								parts[n] = code:sub(pos, p-2) 
								sc = sc + 1
								strings[sc] = n--  note position in the table parts
								blocks[n] = true
								pos = p-1 -- continue at brackets
							end
						else
							endBracket = p
						end
					end
				-- COMMENT ENDING
				elseif commentStart then
					if s == '\n' then
						commentStart = false
						-- commentCount = commentCount + 1
						pos = p
					elseif s == '[' then 
						if commentStart == p-3 and bracket == p-1 then
							blockStart = true-- we're in block comment
						elseif commentStart == p-2 then
							bracket = p
						end
					end
				-- QUOTE PAIRING
				elseif strStart then
                    if escaped then
                        if escaped == p-1 then
                            escaped = false
                            return
                        else
                            escaped = false
                        end
                    end
					if s == '\\' then
						escaped = p

					elseif s == strStart then  -- finish quote pairing
						strStart = false
						-- stringCount = stringCount + 1
						if p-pos > 0 then
							n = n + 1
							parts[n] = code:sub(pos, p-1) -- isolate string and note position in the table parts
							sc = sc + 1
							strings[sc] = n
							lens[sc] = p-pos
							pos = p
						end
					end
				-- DETECTING STARTS
				-- checking comment start, then string start then block start
				elseif s == '-' then
					-- Echo('check',p,'minus',minus)
					if minus == p-1 then 
						commentStart = p-1
						n = n + 1
						parts[n] = code:sub(pos, p-2) -- pick before the comment
						pos = p+1 -- set after the comment
					else
						minus = p
					end
				elseif s == '"' or s == "'" then
						strStart = s -- quote pairing start
						n = n + 1
						parts[n] = code:sub(pos,p) -- include the quote
						pos = p+1 
				elseif s == '[' then
					if bracket == p-1 then
						blockStart = true
						n = n + 1
						parts[n] = code:sub(pos, p) -- include the brackets
						pos = p+1
					else
						bracket = p
					end
				end
			end
		)
		if not commentStart then
			n = n + 1
			parts[n] = code:sub(pos)
		end



		local uncommented = table.concat(parts) --:decodeescape()
		time = spDiffTimers(spGetTimer(),time)
		local time2 = spGetTimer()
		for i=1, sc do -- substitute the string with spaces (or newline)
			local n = strings[i]
			local part = parts[n]
            if blocks[n] then
                parts[n] = part:gsub('[^\n\t]',' ')
			else
				parts[n] = (' '):rep(lens[i])
			end
		end
		local blanked = table.concat(parts)
		time2 = spDiffTimers(spGetTimer(),time2)
		if tellTime then
			Echo("TIME B3 ", time,time2, 'count',count,'parts',n,'strings parts',sc,'uncommented == blanked len',uncommented:len()==blanked:len())
		end
		-- Echo("stringCount, blockCount, commentCount is ", stringCount, blockCount, commentCount)
		-- Echo("strStart, blockStart, commentStart is ", strStart, blockStart, commentStart)

		-- Spring.SetClipboard(code)
		return uncommented, blanked, time
	end


	local function GetCodeAbstract(source, code) -- remove comments and reduce strings/blocks to their ends
		if not code then
			code = WG.Code:GetCode(source or "LuaUI\\Widgets\\UtilsFunc.lua")
		end

        if code:find('\r') then
            code = code:removereturns()
        end
		-- to acertain validity of char we check in precise order, short circuiting all the rest of checks
			--> block --> end of block
			--> comment --> check for block or end of line
			--> string --> end of string
			--> comment start
			--> string start
			--> block start

		-- gsub is fastest, avoiding using find is much better
		local pos = 1
		local pat = '()([\\\'\"%[%]%-\n])'
		local strStart, commentStart, blockStart = false, false, false
		local bracket, endBracket, minus = false, false, false
		local escaped = false

		-- code = code:codeescape()
		local n = 0
		local parts = {}
		local strings, sc, blocks = {}, 0, {}
		-- counts are only for debugging and can be commented out
		-- local count = 0
		-- local blockCount, stringCount, commentCount = 0,0,0
		local lens = {}
		local time = spGetTimer()
		local count = 0
		code:gsub(
			pat,
			function(p, s)
				-- BLOCK PAIRING
				count = count + 1


				if blockStart then
					if s == ']' then

						if endBracket == p - 1 then
							blockStart = false
							-- blockCount = blockCount + 1
							if commentStart then -- we end the block comment
								commentStart = false
								-- commentCount = commentCount + 1
								-- keep only newlines in the block comment
								local _, nl = code:sub(pos,p):gsub('\n','')
								if nl==0 then -- check if both ends will be touching and conflicting
									if code:sub(pos-3,pos-3):find('%w') and code:sub(p+1,p+1):find('%w') then
										n = n + 1
										parts[n] = ' '
									end
								else
									n = n + 1
									parts[n] = ('\n'):rep(nl)
								end
								pos = p + 1 -- continue after brackets
							else
								local _, nl = code:sub(pos,p):gsub('\n','')
								if nl>0 then
									n = n + 1
									parts[n] = ('\n'):rep(nl)
								end
								pos = p-1 -- continue at brackets
							end
						else
							endBracket = p
						end
					end
				-- COMMENT ENDING
				elseif commentStart then
					if s == '\n' then
						commentStart = false
						-- commentCount = commentCount + 1
						pos = p
					elseif s == '[' then 
						if commentStart == p-3 and bracket == p-1 then
							blockStart = true-- we're in block comment
						elseif commentStart == p-2 then
							bracket = p
						end
					end
				-- QUOTE PAIRING
				elseif strStart then
                    if escaped then
                        if escaped == p-1 then
                            escaped = false
                            return
                        else
                            escaped = false
                        end
                    end
					if s == '\\' then
						escaped = p

					elseif s == strStart then  -- finish quote pairing
						strStart = false
						-- stringCount = stringCount + 1
						pos = p
					end
				-- DETECTING STARTS
				-- checking comment start, then string start then block start
				elseif s == '-' then
					-- Echo('check',p,'minus',minus)
					if minus == p-1 then 
						commentStart = p-1
						n = n + 1
						parts[n] = code:sub(pos, p-2) -- pick before the comment
						-- Echo('pick before',n,pos,p-2, code:sub(pos, p-2))
						-- Echo("parts[n-1] is ", parts[n-1])
						pos = p+1 -- set after the comment
					else
						minus = p
					end
				elseif s == '"' or s == "'" then
						strStart = s -- quote pairing start
						n = n + 1
						parts[n] = code:sub(pos,p) -- include the quote
						pos = p+1 
				elseif s == '[' then
					if bracket == p-1 then
						blockStart = true
						n = n + 1
						parts[n] = code:sub(pos, p) -- include the brackets
						pos = p+1
					else
						bracket = p
					end
				end
				-- if count < 15 then
				-- 	Echo(p, code:at(p):readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart,'pos', pos)
				-- end

			end
		)

		if not commentStart then -- comment at the very end of file cannot find newline
			n = n + 1
			parts[n] = code:sub(pos)
		end


		local abstract = table.concat(parts)
		time = spDiffTimers(spGetTimer(),time)

		-- Echo("TIME AB ", time)
		-- Echo("stringCount, blockCount, commentCount is ", stringCount, blockCount, commentCount)
		-- Echo("strStart, blockStart, commentStart is ", strStart, blockStart, commentStart)

		-- Spring.SetClipboard(code)
		return abstract
	end

	local function verify(code, code2)
		local len = math.max(code:len(), code2:len())
		for i=1, len do
			local c2, c1 = code2:at(i), code:at(i)
			if c1 ~= c2 then
				if c1~='' then
					Echo('wrong at code1',i,c1:readnl(),code:nline(i),code:line(i),code:line(i):readnl(),code:line(i):len())
				else
					Echo('code1 has no char at '.. i)
				end
				if c2~='' then
					Echo('c2 has',i, c2:readnl(),code2:nline(i),code2:line(i):readnl(), 'len',code2:line(i):len())
				else
					Echo('c2 has no char at ' .. i)
				end
				break
			end
		end
	end


	function GetFile(source)
		if source:find('\\') then
			return io.open(source)
		end		
		local file
		if not source:find('/') then
			file = io.open(source)
		end
		local code
		if not file then
			code = VFS.LoadFile(source, VFS.ZIP)
			if code then
				file = io.tmpfile()
		        file:write(code)
		        file:seek("set")
		    end
		end
		return file, code
	end
	local function GetCode(source)
		local file, code = GetFile(source)
		if not file then
			return ''
		end
		if not code then
			code = file:read('*a')
		end
		file:close()
		return code
	end

    function testlines(source)
        local time1 = Spring.GetTimer()
        source = source or "LuaUI\\Widgets\\UtilsFunc.lua"
        local file = io.open(source, "r") -- dont find R
        -- local code = file:read('*a')
        -- file:seek("set")

        time1 = Spring.DiffTimers(Spring.GetTimer(), time1)
        local time2 = Spring.GetTimer()
        local i = 1
        local lines = {''}
        local lpos = {1}
        local pos = 1
        for line in file:lines() do
            lines[i] = line..'\n'
            i = i + 1
            pos = pos + line:len() + 1
            lpos[i]  = pos
        end
        lpos[i] = nil
        file:close()
        code = table.concat(lines,'\n') .. '\n'
        time2 = Spring.DiffTimers(Spring.GetTimer(), time2)
        Echo('#1',time1, time2,'lines',#lines)
        return code, lines, lpos
    end

    function testlines2(source, method)
        local time1 = Spring.GetTimer()
        source = source or "LuaUI\\Widgets\\UtilsFunc.lua"

        local code = VFS.LoadFile(source, VFS.RAW_FIRST)

        time1 = Spring.DiffTimers(Spring.GetTimer(), time1)
        local time2 = Spring.GetTimer()

        
        local i = 1
        local lines = {''}
        local lpos = {1}
        local pos = 1
        -- by file
        if method == 1 then--on a 8K line file it is twice faster to make a tmp file and use io.lines than using gsub 
			local tmp = io.tmpfile()
		        tmp:write(code)
		        tmp:seek("set")
		        for line in tmp:lines() do
		            lines[i] = line
		            i = i + 1
		            pos = pos + line:len() + 2
		            lpos[i]  = pos
		        end
			tmp:close()
		else
			-- or with gsub
			local count = 0
	        code:gsub('()\n',function(p)
	        	count = count + 1
	            lines[i] = code:sub(pos,p-1)
	            pos = p + 1
	            i = i + 1
	            lpos[i]  = pos
	        end)
	        --
	    end
        lpos[i] = nil
        time2 = Spring.DiffTimers(Spring.GetTimer(), time2)

        Echo('#2 m'..method, time1, time2,'lines',#lines)
        -- Echo("code:find('\r') is ", code:find('\r'))
        return code, lines, lpos
    end
    function testlines3(source)
        local time1 = Spring.GetTimer()
        source = source or "LuaUI\\Widgets\\UtilsFunc.lua"

        local code = VFS.LoadFile(source, VFS.RAW_FIRST):removereturns()
        local tmp = io.tmpfile()
        tmp:write(code)
        tmp:seek("set")
        time1 = Spring.DiffTimers(Spring.GetTimer(), time1)
        local time2 = Spring.GetTimer()
        local i = 1
        local lines = {''}
        local lpos = {1}
        local pos = 1
        for line in tmp:lines() do
            lines[i] = line..'\n'
            i = i + 1
            pos = pos + line:len() + 1
            lpos[i]  = pos
        end
        tmp:close()
        lpos[i] = nil
        time2 = Spring.DiffTimers(Spring.GetTimer(), time2)
        Echo('#3', time1, time2,'lines',#lines)
        return code, lines, lpos
    end

    function GetLines(source, code, wantLines,wantCode, wantLen, tellTime) -- writing 8K lines tmp file takes practically 0, io.line takes 0.022, while gsub takes 0.033
        local time1 = Spring.GetTimer()
        local file, len
        local codelen
        if not code then
        	source = source or "LuaUI\\Widgets\\UtilsFunc.lua"
        	file, code = GetFile(source) -- FIXME get code by the way from VFS.LoadFile if the file is from zip, until I find a way to use io.open with archived file
        	file:seek('set')
        else
        	---------
        	file = io.tmpfile()
        	file:write(code)
        	file:seek('set')
        end
        time1 = Spring.DiffTimers(Spring.GetTimer(), time1)
        -------------
        if (wantCode or not wantLines) and not code then
        	code = file:read('*a')
        end

        if code and code:find('\r') then
        	Echo('code contains returns', source:match('[\\/][^\\/]+$'))
        end
        local l = 1
        local lines = {''}
        local lpos = {1}
        local pos = 1
        -- by file
        local time2 = Spring.GetTimer()
        if not wantLines then
        	file:seek('set',-1)
        	code:gsub('\n()', function(p) -- much faster to use gsub if we don't want lines
	            l = l + 1
	            lpos[l]  = p 
	            pos = p
			end)
        else
        	file:seek('set')
	        for line in file:lines() do
	        	-- Echo(" #", i,'pos',pos,'len', line:len(),code:sub(pos,pos+line:len()):readnl())
	        	-- Echo('line given is',line,'at pos',code:find(line))
            	lines[l] = line
	            l = l + 1
	            pos = pos + line:len() + 1
	            lpos[l]  = pos -- pos of the next line, if there is
	        end
	    end
        file:seek('cur',-1)

        local beforelast = file:read(1)

        if (beforelast == '\n' or l==1 and beforelast == '') then
        	-- Echo('set last line as empty string')
        	lines[l] = '' -- we already set the last line pos but not the line
        else
        	-- Echo('we set one pos of line too much')
			lpos[l] = nil -- we set one pos of line too much
			l = l - 1
        end
        -------------------
        time2 = Spring.DiffTimers(Spring.GetTimer(), time2)
        if wantLen then
        	codelen = file:seek()
        end

		file:close()


		------------------------------------
		-- making shortcuts to get pos-to-line  quicker, any pos in the code will get teleported to the nearest shortcut line pos
		local time3 = spGetTimer()
	    local shortcuts = {}
		local div = 800 -- one shortcut every that many character in the file (around 300k char for 8.5K line ~= 375 shortcuts with 800 shortcut size)

	    local lastshort = -1
	    local last_line = 1
	    for i=1, l do 
	    	local pos = lpos[i]
	    	local d = pos/div
	    	local short = d-d%1 -- like floor or modf but a tiny bit faster
	    	if short > lastshort then
	    		shortcuts[short] = i
	    		if short - lastshort > 1 then -- reporting the last line on missing shortcut(s) (when last line was bigger than min size of shortcut)
		    		for sh=lastshort, short-1 do
		    			shortcuts[sh] = last_line
		    		end
		    	end
	    		lastshort = short
	    		last_line = i
	    	end
	    end

	    lpos.div = div
	    lpos.shortcuts = shortcuts
		lpos.len = l

		local lineObj = {count=l, lines=lines, lpos=lpos, code = wantCode and code or nil}
	    function lineObj.getline(pos, start)
		    if l == 1 then
		        return 1
		    end

	        local d = pos/div
	        local shortcut = shortcuts[d - d%1]
	        if not start or start < shortcut then
	            start = shortcut
	        end
	        local lpos = lpos
		    for i = start, l do
		        if lpos[i] > pos then
		            return i-1, lpos[i-1]
		        end
		    end
		    return l, lpos[len]
	    end
	    ------------------------------------


	    time3 = spDiffTimers(spGetTimer(),time3)
	    if tellTime then
        	Echo('lines by file ', time1, time2, time3,'lines',l)
        end
        return lineObj, code, codelen, time2 + time1 + time3
    end

	local function GetScopes2BASE(code,pos) --
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'

		local insert, remove = table.insert, table.remove
		pos = pos or 1

		local all = {}
		index, i = {}, 0
		local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
		local op3 = '[%s%(%)%]}%,dnirpt]'
		local time = spGetTimer()
		local tries = 0
		local matches = 0
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
		local process =	function(p,s)
			matches = matches + 1
			if s == 'en' then
				if code:sub(p+2,p+3):find('d'..re) then
					i = i + 1
					index[i] = p
					all[p] = 'end'
				end
			elseif s == 'if' or s == 'do' then
				if code:sub(p+2,p+2):find(ro) then
					i = i + 1
					index[i] = p
					all[p] = s
				end
			elseif s =='fo' then
				if code:sub(p+2,p+3):find('r'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'for'
				end
			elseif s =='fu' then
				if code:sub(p+2,p+8):find('nction'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'function'
				end
			elseif s == 'wh' then
				if code:sub(p+2,p+5):find('ile'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'while'
				end
			elseif s =='re' then -- a lot of useless match because of the term return or ret, FIXME TO IMPROVE
				if code:sub(p+2,p+6):find('peat'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'repeat'
				end
			elseif s =='un' then
				if code:sub(p+2,p+5):find('til'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'until'
				end
			end
		end
		local first_line = code:find('\n')

		code:sub(1, first_line):gsub(
			'^()('..op1..op2..')',
			process
		)
		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		code:gsub(
			anyl..'()('..op1..op2..')',
			process
		)
		local level = 0

		local test, t = {}, 1
		local pos = 1
		local concatAll = false
		local started = false
		local count = 0
		for i, p in pairs(index) do
			local s = all[p]
			-- counts[s] = (counts[s] or 0) + 1
			-- if s then
				count = count + 1

				if s == 'for' or s == 'while' then
					if level == 0 then -- start of new closure
						if not started then -- start of new closure
							if concatAll then
								-- add between closure for test
								local before = code:sub(pos, p-1)
								test[t] = before
								t = t + 1 
							end
							pos = p
							started = true
						end
					end
				elseif s == 'end' or s=='until' then
					level = level - 1
					if level == 0 then -- end of closure
						local len = s=='end' and 3 or 5
						test[t] = code:sub(pos, p + len - 1)
						pos = p + len
						t = t + 1  -- up t in advance so we will fill either with for/while loop or with other opening in order
						started = false
					end
				else
					if level == 0 then
						if not started then -- start of new closure
							if concatAll then
								-- add between closure for test
								local before = code:sub(pos, p-1)
								test[t] = before
								t = t + 1
							end
							pos = p
							started = true
						end

					end
					level = level + 1
				end
			-- end
		end
		if concatAll then
			-- add after last closure for test
			test[t] = code:sub(pos)
		end

		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		time = spDiffTimers(spGetTimer(), time)
		local testReport = concatAll and table.concat(test) or table.concat(test,' ')
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(testReport)

		Echo('TIME GS2B', time,'size',table.size(all),'parts',t,'matches',matches, 'level',level)
		return testReport
	end
	local function GetScopes2(code,pos, concatAll) -- get start and end of first level closures
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'

		local insert, remove = table.insert, table.remove
		pos = pos or 1

		local all = {}
		index, i = {}, 0
		local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
		local op3 = '[%Wdnirpt]'
		local time = spGetTimer()
		local tries = 0
		local matches = 0
		local concatAll = false
		local level = 0
		local UEND = 'til'..ro
		local RPEND = 'peat'..ro
		local WEND = 'ile'..ro
		local FEND = 'nction'..ro
		local REND = 'r'..ro
		local DEND = 'd'..re

		local test, t = {}, 1
		local pos = 1
		local started = false
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')

		local process = function(p,s)
			matches = matches + 1
			if s == 'en' then
				if code:sub(p+2,p+3):find(DEND) then
					-- s = 'end'
					level = level - 1
					if level == 0 then -- end of closure
						test[t] = code:sub(pos, p + 2)
						pos = p + 3
						t = t + 1
						started = false
					end
				end
			elseif s == 'if' or s == 'do' then
				if code:sub(p+2,p+2):find(ro) then
					if level == 0 then
						if not started then -- start of new closure
							if concatAll then
								-- add between closure for test
								local before = code:sub(pos, p-1)
								test[t] = before
								t = t + 1 -- up t in advance so we will fill either with for/while loop or with other opening in order
							end
							pos = p
							started = true
						end
					end
					level = level + 1
				end
			elseif s =='fo' then -- dont up level for 'for' loop as there will be a 'do'
				if code:sub(p+2,p+3):find(REND) then
					-- s = 'for'
					if level == 0 then -- start of new closure
						if not started then
							if concatAll then
								-- add (between/before first) closure for test
								local before = code:sub(pos, p-1)
								test[t] = before
								t = t + 1
							end
							pos = p
							started = true
						end
					end
				end
			elseif s =='fu' then
				if code:sub(p+2,p+8):find(FEND) then
					-- s = 'function'
					if level == 0 then
						if not started then -- start of new closure
							if concatAll then
								-- add between closure for test
								local before = code:sub(pos, p-1)
								test[t] = before
								t = t + 1 -- up t in advance so we will fill either with for/while loop or with other opening in order
							end
							pos = p
							started = true
						end
					end
					level = level + 1
				end
			elseif s == 'wh' then
				if code:sub(p+2,p+5):find(WEND) then
					-- s = 'while'
					if level == 0 then -- start of new closure
						if not started then
							if concatAll then
								-- add (between/before first) closure for test
								local before = code:sub(pos, p-1)
								test[t] = before
								t = t + 1
							end
							started = true
							pos = p
						end
					end
				end
			elseif s =='re' then -- a lot of useless match because of the term return or ret, FIXME TO IMPROVE
				if code:sub(p+2, p+2) ~= 't' and code:sub(p+2,p+6):find(RPEND) then
					-- s = 'repeat'
					if level == 0 then
						if not started then -- start of new closure
							if concatAll then
								-- add between closure for test
								local before = code:sub(pos, p-1)
								test[t] = before
								t = t + 1 -- up t in advance so we will fill either with for/while loop or with other opening in order
							end
							started = true
							pos = p
						end
					end
					level = level + 1
				end
			elseif s =='un' then
				if code:sub(p+2,p+5):find(UEND) then
					-- s = 'until'
					level = level - 1
					if level == 0 then -- end of closure
						test[t] = code:sub(pos, p + 4)
						t = t + 1 -- up t in advance so we will fill either with for/while loop or with other opening in order
						pos = p + 5
						started =  false
					end
				end
			end
		end
		local first_line = code:find('\n')

		code:sub(1, first_line):gsub(
			'^()('..op1..op2..')',
			process
		)
		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		code:gsub(
			anyl..'()('..op1..op2..')',
			process
		)

		if concatAll then
			-- add after last closure for test
			test[t] = code:sub(pos)
		end
		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		time = spDiffTimers(spGetTimer(), time)
		local testReport = concatAll and table.concat(test) or table.concat(test,' ')
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(testReport)
		-- Echo('TIME GS2', time,'size',table.size(all),'matches',matches, 'level',level)
		return testReport, level
	end
	------------------------------
	local function GetScopesABSTRACT(code,pos)
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'

		local insert, remove = table.insert, table.remove
		pos = pos or 1

		local all = {}
		index, i = {}, 0
		local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
		local op3 = '[%s%(%)%]}%,dnirpt]'
		local time = spGetTimer()
		local tries = 0
		local matches = 0
		--
	  --       local l = 1
	  --       local nl = {}
	  --       local lpos = 1
			-- local tmp = io.tmpfile()
		 --        tmp:write(code)
		 --        tmp:seek("set")
		 --        for line in tmp:lines() do
		 --            l = l + 1
		 --            lpos = lpos + line:len() + 1
		 --            nl[i]  = lpos
		 --        end
			-- tmp:close()
		
		--
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
		local process = function(p,s)
			matches = matches + 1
			if s == 'en' then
				if code:sub(p+2,p+3):find('d'..re) then
					i = i + 1
					index[i] = p
					all[p] = 'end'
				end
			elseif s == 'if' or s == 'do' then
				if code:sub(p+2,p+2):find(ro) then
					i = i + 1
					index[i] = p
					all[p] = s
				end
			elseif s =='fo' then
				if code:sub(p+2,p+3):find('r'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'for'
				end
			elseif s =='fu' then
				if code:sub(p+2,p+8):find('nction'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'function'
				end
			elseif s == 'wh' then
				if code:sub(p+2,p+5):find('ile'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'while'
				end
			elseif s =='re' then -- a lot of useless match because of the term return or ret, FIXME TO IMPROVE
				if code:sub(p+2,p+6):find('peat'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'repeat'
				end
			elseif s =='un' then
				if code:sub(p+2,p+5):find('til'..ro) then
					i = i + 1
					index[i] = p
					all[p] = 'until'
				end
			end
		end

		local first_line = code:find('\n')
		-- Echo("first_line is ", first_line)
		code:sub(1, first_line):gsub(
			'^()('..op1..op2..')',
			process
		)
		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		code:gsub(
			anyl..'()('..op1..op2..')',
			process
		)


		local level = 0

		local test, t = {}, 1
		local pos = 1
		local concatAll = false
		local started = false


		for i, p in pairs(index) do
			local s = all[p]

			-- counts[s] = (counts[s] or 0) + 1
			-- if s then
				if s == 'for' or s == 'while' then
					if level == 0 then -- start of new closure
						if not started then -- start of new closure
							-- 
								local _,before = code:sub(pos, p-1):gsub('\n','')
								test[t] = ('\n'):rep(before)
								t = t + 1 
							-- 
							pos = p
							started = true
						end
					end
				elseif s == 'end' or s=='until' then
					level = level - 1
					if level == 0 then -- end of closure
						local len = s=='end' and 3 or 5
						test[t] = code:sub(pos, p + len - 1)
						pos = p + len
						t = t + 1  -- up t in advance so we will fill either with for/while loop or with other opening in order
						started = false
					end
				else
					if level == 0 then
						if not started then -- start of new closure

								local _,before = code:sub(pos, p-1):gsub('\n','')
								test[t] = ('\n'):rep(before)
								t = t + 1

							pos = p
							started = true
						end

					end
					level = level + 1
				end
			-- end
		end
		local _, after = code:sub(pos):gsub('\n','')
		test[t] = ('\n'):rep(after)

		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		time = spDiffTimers(spGetTimer(), time)
		local testReport = concatAll and table.concat(test) or table.concat(test,' ')
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(testReport)
		-- Spring.SetClipboard(testReport)
		Echo('TIME GSABST', time,'size',table.size(all),'matches',matches, 'level',level)
		return testReport
	end

	local function GetScopesABSTRACT2(code,pos) -- faster but uglier
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'

		local insert, remove = table.insert, table.remove
		pos = pos or 1

		local all = {}
		index, i = {}, 0
		local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
		local op3 = '[%Wdnirpt]'
		local time = spGetTimer()
		local tries = 0
		local matches = 0
		local concatAll = false
		local level = 0
		local UEND = 'til'..ro
		local RPEND = 'peat'..ro
		local WEND = 'ile'..ro
		local FEND = 'nction'..ro
		local REND = 'r'..ro
		local DEND = 'd'..re

		local test, t = {}, 1
		local pos = 1
		local started = false
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')

		local process = function(p,s)
			if  matches == 0 then
				Echo("p,s is ", p,s)
			end
			matches = matches + 1
			if s == 'en' then
				if code:sub(p+2,p+3):find(DEND) then
					-- s = 'end'
					level = level - 1
					if level == 0 then -- end of closure
						test[t] = code:sub(pos, p + 2)
						pos = p + 3
						t = t + 1
						started = false
					end
				end
			elseif s == 'if' or s == 'do' then
				if code:sub(p+2,p+2):find(ro) then
					if level == 0 then
						if not started then -- start of new closure

							local _,before = code:sub(pos, p-1):gsub('\n','')
							test[t] = ('\n'):rep(before)
							t = t + 1

							pos = p
							started = true
						end
					end
					level = level + 1
				end
			elseif s =='fo' then -- dont up level for 'for' loop as there will be a 'do'
				if code:sub(p+2,p+3):find(REND) then
					-- s = 'for'
					if level == 0 then -- start of new closure
						if not started then

							local _,before = code:sub(pos, p-1):gsub('\n','')
							test[t] = ('\n'):rep(before)
							t = t + 1

							pos = p
							started = true
						end
					end
				end
			elseif s =='fu' then
				if code:sub(p+2,p+8):find(FEND) then
					-- s = 'function'
					if level == 0 then
						if not started then -- start of new closure

							local _,before = code:sub(pos, p-1):gsub('\n','')
							test[t] = ('\n'):rep(before)
							t = t + 1

							pos = p
							started = true
						end
					end
					level = level + 1
				end
			elseif s == 'wh' then
				if code:sub(p+2,p+5):find(WEND) then
					-- s = 'while'
					if level == 0 then -- start of new closure
						if not started then

							local _,before = code:sub(pos, p-1):gsub('\n','')
							test[t] = ('\n'):rep(before)
							t = t + 1

							started = true
							pos = p
						end
					end
				end
			elseif s =='re' then -- a lot of useless match because of the term return or ret, FIXME TO IMPROVE
				if code:sub(p+2, p+2) ~= 't' and code:sub(p+2,p+6):find(RPEND) then
					-- s = 'repeat'
					if level == 0 then
						if not started then -- start of new closure

							local _,before = code:sub(pos, p-1):gsub('\n','')
							test[t] = ('\n'):rep(before)
							t = t + 1

							started = true
							pos = p
						end
					end
					level = level + 1
				end
			elseif s =='un' then
				if code:sub(p+2,p+5):find(UEND) then
					-- s = 'until'
					level = level - 1
					if level == 0 then -- end of closure
						test[t] = code:sub(pos, p + 4)
						t = t + 1 -- up t in advance so we will fill either with for/while loop or with other opening in order
						pos = p + 5
						started =  false
					end
				end
			end
		end
		local first_line = code:find('\n')

		code:sub(1, first_line):gsub(
			'^()('..op1..op2..')',
			process
		)
		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		code:gsub(
			anyl..'()('..op1..op2..')',
			process
		)

		local _, after = code:sub(pos):gsub('\n','')
		test[t] = ('\n'):rep(after)
		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		time = spDiffTimers(spGetTimer(), time)
		local testReport = concatAll and table.concat(test) or table.concat(test,' ')
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(testReport)
		Echo('TIME GS2', time,'size',table.size(all),'matches',matches, 'level',level)
		return testReport
	end

	local function GetScopesABSTRACT3(code,pos) -- replace anything out of main scope with newlines
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'

		pos = pos or 1

		index, i = {}, 0

		local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
		local op3 = '[%Wdnirpt]'
		local time = spGetTimer()
		local tries = 0
		local matches = 0
		local concatAll = false
		local level = 0
		local UEND = 'til'..ro
		local RPEND = 'peat'..ro
		local WEND = 'ile'..ro
		local FEND = 'nction'..ro
		local REND = 'r'..ro
		local DEND = 'd'..re
		local test, t = {}, 1
		local pos = 1
		local lastpos = 1
		local started = false
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
	        local l = 1
	        local nl = {1}
	        local lpos = 1
			local tmp = io.tmpfile()
		        tmp:write(code)
		        tmp:seek("set")
		        for line in tmp:lines() do

		            l = l + 1
		            lpos = lpos + line:len() + 1
		            nl[l]  = lpos-- there is voluntarily one more pos of line than there are lines
		        end
			tmp:close()
			
		--

		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
		local curline, nexposline = 1, nl[2]
		local function endclosure(p)
			test[t] = code:sub(pos, p + 2)
			pos = p + 3
			t = t + 1
			started = false
			while p >= nexposline do 
				curline = curline + 1
				nexposline = nl[curline+1]
			end
		end
		local function startclosure(p)
			local nls = 0
			while p >= nexposline do 
				curline = curline + 1
				nexposline = nl[curline+1]
				nls = nls + 1
			end
			if nls > 0 then
				-- local _,before = code:sub(pos, p-1):gsub('\n','')
				test[t] = ('\n'):rep(nls)
				t = t + 1
			end

			pos = p
			started = true
		end
		local function startfunctionclosure(p)
			local nls = 0
			while p >= nexposline do 
				curline = curline + 1
				nexposline = nl[curline+1]
				nls = nls + 1
			end
			if nls > 0 then
				-- local _,before = code:sub(pos, p-1):gsub('\n','')
				test[t] = ('\n'):rep(nls)
				t = t + 1
			end
			--
			local sol = nl[curline]
			local section =  code:sub(sol,p-1)
			local sp =  section:find('[%w%.]+%s-=%s-$')
			if sp then
				p = sol + (section:sub(1,sp):find('local%s+$') or sp) - 1
			end
			pos = p
			started = true
		end

		local process = function(p,s)
			matches = matches + 1
			if s == 'en' then
				if code:sub(p+2,p+3):find(DEND) then
					-- s = 'end'
					-- Echo(matches,'matched', code:sub(p+2,p+3))
					level = level - 1
					if level == 0 then -- end of closure
						endclosure(p)
					end
				-- else
				-- 	Echo(matches,'missed',p,code:sub(p+2,p+5):readnl()..'test')
				end
			elseif s == 'if' or s == 'do' then
				if code:sub(p+2,p+2):find(ro) then
					if level == 0 then
						if not started then -- start of new closure
							startclosure(p)
						end
					end
					level = level + 1
				end
			elseif s =='fo' then -- dont up level for 'for' loop as there will be a 'do'
				if code:sub(p+2,p+3):find(REND) then
					-- s = 'for'
					if level == 0 then -- start of new closure
						if not started then
							startclosure(p)
						end
					end
				end
			elseif s =='fu' then
				if code:sub(p+2,p+8):find(FEND) then
					-- s = 'function'

					if level == 0 then
						if not started then -- start of new closure
							startfunctionclosure(p)
						end
					end
					level = level + 1
				end
			elseif s == 'wh' then
				if code:sub(p+2,p+5):find(WEND) then
					-- s = 'while'
					if level == 0 then -- start of new closure
						if not started then
							startclosure(p)
						end
					end
				end
			elseif s =='re' then 
				if code:sub(p+2, p+2) ~= 't' and code:sub(p+2,p+6):find(RPEND) then-- a lot of useless match because of the term return or ret
					-- s = 'repeat'
					if level == 0 then
						if not started then -- start of new closure
							startclosure(p)
						end
					end
					level = level + 1
				end
			elseif s =='un' then
				if code:sub(p+2,p+5):find(UEND) then
					-- s = 'until'
					level = level - 1
					if level == 0 then -- end of closure
						endclosure(p+5)
					end
				end
			end
			-- Echo("matches,p,s,level is ", matches,p,s,level)
		end
		---

		local first_line = code:find('\n')

		code:sub(1, first_line):gsub(
			'^()('..op1..op2..')',
			process
		)

		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		(code..' '):gsub(
			anyl..'()('..op1..op2..')',
			process
		)

		local _, after = code:sub(pos):gsub('\n','')
		test[t] = ('\n'):rep(after)
		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		time = spDiffTimers(spGetTimer(), time)
		local testReport = table.concat(test)
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(testReport)
		Echo('TIME GS ABS3 ', time,'matches',matches, 'level',level)
		return testReport
	end

	local function GetScopesABSTRACT_FULL(code,pos) --  keep only scope marker but slow 
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'

		pos = pos or 1

		index, i = {}, 0

		local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
		local op3 = '[%Wdnirpt]'
		local time = spGetTimer()
		local tries = 0
		local matches = 0
		local concatAll = false
		local level = 0
		local UEND = 'til'..ro
		local RPEND = 'peat'..ro
		local WEND = 'ile'..ro
		local FEND = 'nction'..ro
		local REND = 'r'..ro
		local DEND = 'd'..re
		local parts, n = {}, 1
		local lastpos = 1
		local started = false
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
  		-- TODO: adapt to new GetLines func
        local l, _, nl = GetLines(false,code)
		--
		if l == 0 then
			Echo('Code given is empty')
			return code
		end
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
		local curline, nexposline = 1, nl[2]

		local function updateline(p)
			local nls = 0
			-- Echo('wanted',p,'current nexposline',nexposline,'next',nl[curline+2])
			while curline<l and p >= nexposline do 
				curline = curline + 1
				nexposline = nl[curline+1]
				nls = nls + 1
			end
			-- Echo('update line at',code:sub(p,p+3):readnl(),'=>',nls)
			return nls
		end
		local function getfunctionpos(p) -- SEE NEXT VERSION GetFuncAndLoop
			-- Echo("lastpos is ", code:sub(lastpos,lastpos):readnl(),code:sub(p,p):readnl()) 
			local nls = updateline(p)
			-- Echo("nexposline is ", nexposline)
			local endPos = code:sub(p):find('%)')+p-1
			-- Echo("code:sub(p, endPos) is ", code:sub(p, nexposline))

			local sol = nl[curline]
			local section =  code:sub(sol,p-1)
			local auto = section:find('%(%s-%s-$')
			if auto then
				section = section:sub(1, auto-1)
			end
			local sp =  section:find('[%w%.%]%[\'\"]+%s-=%s-$') -- this wont find the name due to using blank string, see next verision GetFuncAndLoop
			if sp then
				p = sol + (section:sub(1,sp-1):find('local%s+$') or sp) - 1
			end
			return p, endPos, auto, nls
		end

		local function removebetween(p) -- keep only space/tab/newline between
			if p-1 > lastpos then
				parts[n] = code:sub(lastpos+1,p-1):gsub('[^%s]','')
				n = n + 1
			end
		end
		local function endclosure(s,p, p2)
			removebetween(p)
			parts[n] = s
			n = n + 1
			updateline(p2+1)
			lastpos = p2
			started = false
		end
		local function startclosure(s,p, p2, isFunction)
			local nls
			if isFunction then
				local auto
				p, p2, auto, nls = getfunctionpos(p)
				local after = code:sub(p2+1,p2+1)
				if after:find('[,)%]%.}]$') then
					s = code:sub(p, p2) .. ' '
				else
					s = code:sub(p, p2+1)
				end
				p2 = p2 + 1
				if auto then
					s = s:gsub('%(-%s-function','function')
				end

			else
				nls = updateline(p)
			end
			-- Echo(code:nline(p),"nls is ", nls,'p,p2',p,p2,code:sub(p,p2):readnl())
			if nls > 0 then
				parts[n] = ('\n'):rep(nls) -- replace before with only newline
				n = n + 1
			end
			parts[n] = s
			n = n + 1

			lastpos = p2
			started = true
		end
		local function continueclosure(s,p, p2, isFunction)
			if isFunction then
				local auto
				p, p2, auto = getfunctionpos(p)
				s = code:sub(p, p2)
				local after = code:sub(p2+1,p2+1)
				if after:find('[,)%]%.}]$') then
					s = code:sub(p, p2) .. ' '
				else
					s = code:sub(p, p2+1)
				end
				p2 = p2 + 1
				if auto then
					s = s:gsub('%(-%s-function','function')
				end
			end
			removebetween(p)
			parts[n] = s
			n = n + 1
			lastpos = p2
		end

		local process = function(p,s)
			matches = matches + 1
			if s == 'en' then
				local section = code:sub(p+2,p+3)
				if section:find(DEND) then
					-- s = 'end'
					-- Echo(matches,'matched', code:sub(p+2,p+3))
					level = level - 1
					if section:find('[,)%]%.}]$') then
						s = 'end '
					else
						s = code:sub(p, p+3)
					end
					if level == 0 then -- end of closure
						endclosure(s,p,p+3)
					else
						continueclosure(s,p, p+3)
					end
				end
			elseif s == 'if' then
				if code:sub(p+2,p+2):find(ro) then
					s = code:sub(p, p+2) .. 'then ' -- NOTE the 'then' is purely cosmetic when reading result,
													-- there may be some sub closure between if and then that will not appear correctly between them but after
													-- we don'n inspect 'then/else/elseif' for performance sake, we stuff all those at same level
					if level == 0  then-- start of new closure
						startclosure(s,p,p+2)
					else
						continueclosure(s,p,p+2)
					end
					level = level + 1
				end
			elseif s == 'do' then
				if code:sub(p+2,p+2):find(ro) then
					s = code:sub(p, p+2)
					if level == 0  and not started then-- start of new closure if it's not already from a loop
						startclosure(s,p,p+2)
					else
						continueclosure(s,p,p+2)
					end
					level = level + 1
				end
			elseif s =='fo' then 
				if code:sub(p+2,p+3):find(REND) then
					s = code:sub(p,p+3)
					-- s = 'for'
					if level == 0 then -- start of new closure
						startclosure(s,p,p+3)
					else
						continueclosure(s,p, p+3)
					end
					-- dont up level for 'for' loop as there will be a 'do'
				end
			elseif s =='fu' then
				if code:sub(p+2,p+8):find(FEND) then
					-- s = 'function'
					if level == 0 then -- start of new closure
						startclosure('function',p,p+8, true)
					else
						continueclosure('function',p, p+8, true)
					end
					level = level + 1
				end
			elseif s == 'wh' then
				if code:sub(p+2,p+5):find(WEND) then
					-- s = 'while'
					s = code:sub(p,p+5)
					if level == 0 then -- start of new closure
						startclosure(s,p, p+5)
					else
						continueclosure(s,p, p+5)
					end
				end
			elseif s =='re' then 
				if code:sub(p+2, p+2) ~= 'n' and code:sub(p+2,p+6):find(RPEND) then-- a lot of useless match because of the term return or ret
					-- s = 'repeat'
					s = code:sub(p,p+6)
					if level == 0 then -- start of new closure
						startclosure(s,p,p+6)
					else
						continueclosure(s,p, p+6)
					end
					level = level + 1
				end
			elseif s =='un' then
				if code:sub(p+2,p+5):find(UEND) then
					-- s = 'until'
					s = code:sub(p,p+5)
					level = level - 1
					if level == 0 then -- end of closure
						endclosure(s,p,p+5)
					else
						continueclosure(s,p, p+5)
					end
				end
			end
			-- Echo("matches,p,s,level is ", matches,p,s,level)
		end
		---

		local first_line = nl[2] - 1

		code:sub(1, first_line-1):gsub(
			'^()('..op1..op2..')',
			process
		)

		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		(code..' '):gsub(
			anyl..'()('..op1..op2..')',
			process
		)

		local _, nlafter = code:sub(lastpos==1 and 1 or lastpos+1):gsub('\n','')
		if nlafter > 0 then
			-- Echo('nlafter',nlafter)
			parts[n] = ('\n'):rep(nlafter)
		else
			n = n - 1
		end
		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		time = spDiffTimers(spGetTimer(), time)
		local abstract = table.concat(parts)
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(testReport)
		-- Echo('TIME GS ABS3 ', time,'matches',matches, 'level',level)
		return abstract, level
	end
	-----------------------------
	local function GetFuncAndLoop(code,unco,pos) -- TODO: loops !
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'

		pos = pos or 1

		index, i = {}, 0

		local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
		local op3 = '[%Wdnirpt]'
		local tries = 0
		local matches = 0
		local concatAll = false
		local level = 0
		local UEND = 'til'..ro
		local RPEND = 'peat'..ro
		local WEND = 'ile'..ro
		local FEND = 'nction'..ro
		local REND = 'r'..ro
		local DEND = 'd'..re
		local parts, n = {}, 1
		local lastpos = 1
		local started = false
	    local l, _, nl, _, time0 = GetLines(false,code)

		local time = spGetTimer()
		if l == 0 then
			Echo('Code given is empty')
			return code
		end
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
		local curline, nexposline = 1, nl[2]

		local function updateline(p)
			local nls = 0
			-- Echo('wanted',p,'current nexposline',nexposline,'next',nl[curline+2])
			while curline<l and p >= nexposline do 
				curline = curline + 1
				nexposline = nl[curline+1]
				nls = nls + 1
			end
			-- Echo('update line at',code:sub(p,p+3):readnl(),'=>',nls)
			return nls
		end
		local function getfunctionpos(p)
			-- Echo("lastpos is ", code:sub(lastpos,lastpos):readnl(),code:sub(p,p):readnl()) 
			local nls = updateline(p)
			-- Echo("nexposline is ", nexposline)
			local endPos = code:sub(p):find('%)')+p-1
			-- Echo("code:sub(p, endPos) is ", code:sub(p, nexposline))

			local sol = nl[curline]
			local section =  unco:sub(sol,p-1)
			local auto = section:find('%(%s-%s-$')
			if auto then
				section = section:sub(1, auto-1)
			end
			local loc

			local sp, _, name = section:find('(%[.-%])%s-=%s-$')
			if not sp then
				sp, _, name  =  section:find('([%w%.]+)%s-=%s-$')
			end
			if sp then

				loc = section:sub(1,sp-1):find('local%s+$')
			
				p = sol + (loc or sp) - 1
			else
				loc = section:find('local%s+$')
				_,_,name = unco:find('%s-([%w%.:]+)', p+8)
				if loc then
					p = loc + sol - 1
				end
			end

			return p, endPos, auto, name, loc
		end


		local function endclosure(s,p, p2)
			updateline(p2+1)
			lastpos = p2
			started = false
		end
		local function startclosure(s,p, p2, isFunction)
			local nls
			if isFunction then
				local auto, name, loc
				p, p2, auto, name, loc = getfunctionpos(p)
				local after = code:sub(p2+1,p2+1)
				s = unco:sub(p, p2)
				p2 = p2 + 1
				if auto then
					s = s:gsub('%(-%s-function','function')
				end
				parts[n] = '['..curline..']: ' .. s
				.. (name and ( " '"..name.."'") or '') .. (auto and " ['auto']" or '') .. (loc and " ['local']" or '')
				 .. ' end'
				 n = n + 1
			else
				nls = updateline(p)
			end
			-- Echo(code:nline(p),"nls is ", nls,'p,p2',p,p2,code:sub(p,p2):readnl())
			lastpos = p2
			started = true
		end
		local function continueclosure(s,p, p2, isFunction)
			if isFunction then
				local auto, name, loc
				p, p2, auto, name, loc = getfunctionpos(p)
				local after = code:sub(p2+1,p2+1)
				s = unco:sub(p, p2)
				p2 = p2 + 1
				if auto then
					s = s:gsub('%(-%s-function','function')
				end
				parts[n] = '['..curline..']: ' .. s
				.. (name and ( " '"..name.."'") or '') .. (auto and " ['auto']" or '') .. (loc and " ['local']" or '')
				 .. ' end'
				 n = n + 1
			end
			lastpos = p2
		end

		local process = function(p,s)
			matches = matches + 1
			if s == 'en' then
				local section = code:sub(p+2,p+3)
				if section:find(DEND) then
					-- s = 'end'
					-- Echo(matches,'matched', code:sub(p+2,p+3))
					level = level - 1
					if level == 0 then -- end of closure
						endclosure(s,p,p+3)
					else
						continueclosure(s,p, p+3)
					end
				end
			elseif s == 'if' then
				if code:sub(p+2,p+2):find(ro) then
					if level == 0  then-- start of new closure
						startclosure(s,p,p+2)
					else
						continueclosure(s,p,p+2)
					end
					level = level + 1
				end
			elseif s == 'do' then
				if code:sub(p+2,p+2):find(ro) then
					if level == 0  and not started then-- start of new closure if it's not already from a loop
						startclosure(s,p,p+2)
					else
						continueclosure(s,p,p+2)
					end
					level = level + 1
				end
			elseif s =='fo' then 
				if code:sub(p+2,p+3):find(REND) then
					-- s = 'for'
					if level == 0 then -- start of new closure
						startclosure(s,p,p+3)
					else
						continueclosure(s,p, p+3)
					end
					-- dont up level for 'for' loop as there will be a 'do'
				end
			elseif s =='fu' then
				if code:sub(p+2,p+8):find(FEND) then
					-- s = 'function'
					if level == 0 then -- start of new closure
						startclosure('function',p,p+8, true)
					else
						continueclosure('function',p, p+8, true)
					end
					level = level + 1
				end
			elseif s == 'wh' then
				if code:sub(p+2,p+5):find(WEND) then
					-- s = 'while'
					if level == 0 then -- start of new closure
						startclosure(s,p, p+5)
					else
						continueclosure(s,p, p+5)
					end
				end
			elseif s =='re' then 
				if code:sub(p+2, p+2) ~= 'n' and code:sub(p+2,p+6):find(RPEND) then-- a lot of useless match because of the term return or ret
					-- s = 'repeat'
					if level == 0 then -- start of new closure
						startclosure(s,p,p+6)
					else
						continueclosure(s,p, p+6)
					end
					level = level + 1
				end
			elseif s =='un' then
				if code:sub(p+2,p+5):find(UEND) then
					-- s = 'until'
					level = level - 1
					if level == 0 then -- end of closure
						endclosure(s,p,p+5)
					else
						continueclosure(s,p, p+5)
					end
				end
			end
			-- Echo("matches,p,s,level is ", matches,p,s,level)
		end
		---

		local first_line = (nl[2] or code:len()+1) - 1

		code:sub(1, first_line-1):gsub(
			'^()('..op1..op2..')',
			process
		)

		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		(code..' '):gsub(
			anyl..'()('..op1..op2..')',
			process
		)

		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		time = spDiffTimers(spGetTimer(), time)
		local abstract = table.concat(parts,'\n')
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(testReport)
		Echo('TIME FNC', time, '+lines',time0,'matches',matches, 'level',level)
		return abstract, level
	end

	local function GetFuncs(code,unco,lineObj, getText, tellTime)
		local parts, n = {}, 0
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		-- local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		-- local anyl = '[%s%(%){}%[%]=,;\'\"]'
		local anyl = '[^%w_:.]'


		local op1, op2 = '[idfe]', '[foun]' -- first and second letter possible for an opening
		-- local op3 = '[%Wdnirpt]'
		local tries = 0
		local matches = 0
		local concatAll = false
		local level = 0
		local UEND = 'til'..ro
		local RPEND = 'peat'..ro
		local WEND = 'ile'..ro
		local FEND = '^nction'..ro
		local REND = 'r'..ro
		local DEND = '^d'..re
		local END = '^'..ro
		local started = false
		lineObj = lineObj or GetLines(false,code)
		local getline = lineObj.getline
	    local l, nl = lineObj.count, lineObj.lpos
	    local lines = lineObj.lines
		local currentFunction
		local lvlHolder = {[0]=nil}
		local funcs = {}
		if l == 0 then
			Echo('Code given is empty')
			return code
		end
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
		local curline, nexposline = 1, nl[2]



		local function updateline(p)
			if curline<l and p >= nexposline then
				curline = getline(p)
				nexposline = nl[curline+1]
			end
			-- Echo('update line at',code:sub(p,p+3):readnl(),'=>',nls)
		end
		local timeFunc = 0
		local wasted = 0

		local function endclosure(s,p, p2)
			updateline(p2+1)
			started = false
		end
		local function getfunctionpos(p)
			-- Echo("lastpos is ", code:sub(lastpos,lastpos):readnl(),code:sub(p,p):readnl()) 
			updateline(p)
			-- Echo("nexposline is ", nexposline)
			local endPos = code:find('%)',p)
			-- Echo("code:sub(p, endPos) is ", code:sub(p, nexposline))
			local sol = nl[curline]
			local section =  unco:sub(sol,p-1)

			local _, name, loc, auto
			_,_,name = unco:find('^%s-([%w%.:]+)', p+8)
			if name then
				loc = section:find('local%s+$')
				if loc then
					p = loc + sol - 1
				end
			else
				auto = section:find('%(%s-%s-$')
				if auto then
					section = section:sub(1, auto-1)
				end
				local sp
				sp, _, name = section:find('(%[.-%])%s-=%s-$')
				if not sp then
					sp, _, name  =  section:find('([%w%.]+)%s-=%s-$')
				end
				if sp then
					loc = section:sub(1,sp-1):find('local%s+$')
					p = sol + (loc or sp) - 1
				end
			end

			return p, endPos, auto, name, loc
		end
		local function getfunction(p)
			local nls
			local p2
			n = n + 1
			local timer = spGetTimer()
			local auto, name, loc
			p, p2, auto, name, loc = getfunctionpos(p)
			s = unco:sub(p, p2)
			if auto then
				s = s:gsub('%(-%s-function','function')
			end

			currentFunction = {
				line = curline, index = n,
				p = p, endPos = p2, auto = auto, s = s, name = name, loc = loc
			}
			if getText then
				parts[n] = s
				.. (name and ( " '"..name.."'") or '') .. (auto and " ['auto']" or '') .. (loc and " ['local']" or '')
				 .. ' end'
			end
			local alreadyFunc = funcs[curline]

			if alreadyFunc then
				local others = alreadyFunc.others
				if not others then
					alreadyFunc.others = {currentFunction}
				else
					others[#others+1] = currentFunction
				end
				
			else
				funcs[curline] = currentFunction
			end
			lvlHolder[level] = currentFunction

			timeFunc = timeFunc + spDiffTimers(spGetTimer(),timer)
			started = true
		end
		local functionFound = false
		local process = function(--[[b,--]]p,s)
			matches = matches + 1
			-- if not s then
			-- 	p, s = b, p
			-- else
			-- 	-- Echo(code:line(p):readnl(),'s',s:readnl(),'b',b:readnl(),'=>',b:find('%W'))
			-- 	-- Echo(code:line(p):readnl(),'s',s:readnl(),'b',b:readnl(),'=>',b:find('[%s%(%){}%[%]=,;\'\"]'))
			-- end
			if s =='fu' then
				if code:find(FEND,p+2) then
					-- Echo('ok')
					-- s = 'function'
					level = level + 1
					getfunction(p)
					functionFound = true
				else
					wasted = wasted + 1
					-- Echo('skip')
				end
			elseif not functionFound then
				return
			elseif s == 'en' then
				if code:find(DEND,p+2) then
					-- s = 'end'
					-- Echo(matches,'matched', code:sub(p+2,p+3))
					local funcObj = lvlHolder[level]
					if funcObj then
						updateline(p)
						funcObj.lineEnd = curline
						lvlHolder[level] = nil
					end
					level = level - 1
					if level == 0 then
						functionFound = false
					end
				else
					-- if wasted < 15 then
					-- 	Echo('wasted',code:line(p):readnl())
					-- end
					wasted = wasted + 1
				end
			elseif s == 'if' or s == 'do' then
				if code:find(END,p+2) then
					level = level + 1
				else
					wasted = wasted + 1
				end
			else
				wasted = wasted + 1
				-- Echo('wasted',s)
			end
			-- -- Echo("matches,p,s,level is ", matches,p,s,level)
		end
		---

		local first_line = (nl[2] or code:len()+1) - 1

		code:sub(1, first_line-1):gsub(
			'^()('..op1..op2..')',
			process
		)

		if not code:sub(-1,-1):find(re) then
			code = code ..' '
		end
		local time = spGetTimer();
		(code..' '):gsub(
			anyl..'()('..op1..op2..')',
			process
		)
		local cnt = 0

		time = spDiffTimers(spGetTimer(), time);
		-- for k,v in pairs(counts) do
		-- 	Echo('count',k,v)
		-- end
		-- Echo("level is ", level)
		if tellTime then
			Echo('TIME FNC', time,'matches',matches, 'level',level,'found',n,'wasted',wasted,'func time',timeFunc)
		end
		local funcTxt
		if getText then
			for l,func in pairs(funcs) do
				local i = func.index
				parts[i] = '['..func.line..' - '..func.lineEnd..']: ' .. parts[i]
				local others = func.others
				if others then
					for i=1, #others do
						func = others[i]
						local i = func.index
						parts[i] = '['..func.line..' - '..func.lineEnd..']: ' .. parts[i]
					end
				end

			end
			funcTxt = table.concat(parts,'\n')
		end
		-- Echo(funcTxt)
		-- local _, funcCounted2 = testReport:gsub(lo..'function'..ro,'')
		-- Echo("funcCounted, funcCounted2 is ", funcCounted, funcCounted2)
		-- Spring.SetClipboard(funcTxt)
		return funcs, funcTxt, level
	end
	--------------------------
	-- get single func from scratch (but need uncommented and blanked still)
	local GetFuncRaw 
	do
		local function maketext(obj)
			local curline, lineEnd, p,s, name, auto, loc = obj.line,obj.lineEnd,obj.p,obj.s,obj.name,obj.auto,obj.loc

			-- return ('[%d%s][%d]: %s%s%s%s end'):format(
			return ('[%d%s]: %s%s%s%s end'):format(
				curline, (lineEnd and (' - ' .. lineEnd) or ''),
				-- p,
				s,
				(name and ( " '"..name.."'") or ''),
				(auto and " ['auto']" or ''),
				(loc and " ['local']" or '')
			)
		end
		local function getfunctionpos(blanked,unco,p,linep)
			-- Echo("lastpos is ", blanked:sub(lastpos,lastpos):readnl(),blanked:sub(p,p):readnl()) 
			-- Echo("nexposline is ", nexposline)
			local endPos = blanked:find('%)',p)
			-- Echo("blanked:sub(p, endPos) is ", blanked:sub(p, nexposline))
			local sol = linep
			local section =  unco:sub(sol,p-1)

			local _, name, loc, auto
			_,_,name = unco:find('^%s-([%w%.:]+)', p+8)
			if name then
				loc = section:find('local%s+$')
				if loc then
					p = loc + sol - 1
				end
			else
				auto = section:find('%(%s-%s-$')
				if auto then
					section = section:sub(1, auto-1)
				end
				local sp
				sp, _, name = section:find('(%[.-%])%s-=%s-$')
				if not sp then
					sp, _, name  =  section:find('([%w%.]+)%s-=%s-$')
				end
				if sp then
					loc = section:sub(1,sp-1):find('local%s+$')
					p = sol + (loc or sp) - 1
				end
			end

			return p, endPos, auto, name, loc
		end
		local function updateinline(alreadyFunc, currentFunction, funcs, curline)
			local others = alreadyFunc.others
			if not others then
				alreadyFunc.others = {currentFunction}
			else
				local movefunc = currentFunction
				if alreadyFunc.fp > fp then
					-- currentFunction becomes the head, the ex-head move to others
					funcs[curline] = currentFunction
					currentFunction.others = others
					alreadyFunc.others = nil
					movefunc = alreadyFunc
					fp = alreadyFunc.fp
				end
				local index = #others + 1
				for i=1, index-1 do
					if others[i].fp > fp then
						index = i
						break
					end
				end
				table.insert(others,index, movefunc)
			end
		end

		local function verifyinline(funcs, curline, p, name)
			local alreadyFunc = funcs[curline]
			local found
			if alreadyFunc then
				if name then
					if alreadyFunc.name == name then
						found = alreadyFunc
					end
				elseif alreadyFunc.fp == p then
					found = alreadyFunc
				end
				if not found then
					local others = alreadyFunc.others
					if others then
						for i=1, #others do
							if name and others[i].name == name
							or not name and others[i].fp == p then
								found = others[i]
								break
							end
						end
					end
				end
			end
			return alreadyFunc, found
		end
		local function getfunction(blanked, unco, funcs, p, curline, linep, wantedName)

			local alreadyFunc, found = verifyinline(funcs, curline, p, wantedName)

			if found then
				return found, true
			end
			-- Echo("p,alreadyFunc and alreadyFunc.fp is ", p,alreadyFunc and alreadyFunc.fp)

			local p2
			local auto, name, loc
			local fp = p

			p, p2, auto, name, loc = getfunctionpos(blanked, unco, p, linep)
			s = unco:sub(p, p2)
			if auto then
				s = s:gsub('%(-%s-function','function')
			end
			local currentFunction = {
				s = s, -- the declaration
				line = curline, index = n,
				fp = fp, -- pos of word 'function'
				p = p, endPos = p2, -- poses of full declaration
				auto = auto, name = name, loc = loc,
				maketext = maketext
			}

			if alreadyFunc then
				updateinline(alreadyFunc, currentFunction, funcs, curline)
			else
				funcs[curline] = currentFunction
			end
			return currentFunction
		end
		--
		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		-- local ro2 = '[%s%(rin]'
		local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
		-- local anyl = '([%s%(%){}%[%]=,;\'\"])'
		local anyl = '[%s%(%){}%[%]=,;\'\"]'
		-- local anyl = '([^%w_:.])'
		local anyl = '[^%w_:.]'

		local function search(blanked, p) -- find valid function
			local pEnd
			p,pEnd = blanked:find('function',p)
			if not p then
				return false
			end

			if endSearch and p > endSearch then
				return false
			else
				while p and not ((p==1 or blanked:find('^' ..anyl,p-1)) and blanked:find('^' ..re,p+8)) do
					p, pEnd = blanked:find('function',pEnd+1)
					if not p or endSearch and p > endSearch then
						return false
					end
				end
			end
			return p, pEnd
		end

		function GetFuncRaw(blanked,unco,line,lineObj,name,funcs, getText, tell) -- very slow without lineObj, else, super fast, get single func

			local funcText
			local reused = false
			local time = spGetTimer()
			funcs = funcs or {}

			------------------------------
			local linep, endSearch = 1
			if lineObj then
				local lpos = lineObj.lpos
				if line>1 then
					linep = lpos[line]
				end
				endSearch = lpos[line+1]
			elseif line > 1 then
				blanked:gsub('\n()',function(p) linep = p  end,line -1 )
				endSearch = blanked:find('\n',linep)
			end

			---------
			--------
			local p, pEnd = search(blanked, linep)
			if not p then
				if tell then
					Echo('cannot find function on line',line)
				end
				return false
			end
			--------
			local timeFunc = spGetTimer() 
			local fn, reused =  getfunction(blanked, unco, funcs, p, line, linep, name)
			if name then
				-- get searched func by name on same line
				while fn.name ~= name do
					p, pEnd = search(blanked, pEnd+1)
					if not p then
						if tell then
							Echo('found function(s) on line ',line,'but not with searched name',name)
						end
						return false
					end
					fn =  getfunction(blanked, unco, funcs, p, line, linep, name)
				end
			end
			timeFunc = spDiffTimers(spGetTimer(), timeFunc)
			time = spDiffTimers(spGetTimer(), time)
			if getText then
				funcText = maketext(fn)
			end
			if tell then
				if funcText then
					Echo(time, timeFunc, funcText)
				else
					Echo('function',fn.name or 'anonymous')
				end
			end
			return fn, reused, time,  timeFunc, funcText
		end
	end

	-- local code, codeObj = WG.Code:GetCode("LuaUI\\Widgets\\-MyClicks2.lua")
	-- codeObj:GetFuncsAndLoops(true, true,true) 




	--*******************************************
	--*******************************************
	--*******************************************
	local function ReachEndOfFunction2(funcObj,code,unco,lineObj, tellTime)
		if funcObj.lineEnd then
			return funcObj.lineEnd, true, funcObj, 0
		end

		local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
		local le, re = '[%s%)}%];]', '[%s%(%)%]}%,;]'
		-- local anyl = '[%s%(%){}%[%]=,;\'\"]'
		local anyl = '[^%w_:.]'

		local time = spGetTimer();
		index, i = {}, 0

		local op1, op2 = '[idfe]', '[foun]' -- first and second letter possible for an opening
		local matches = 0

		local level = 0

		local FEND = '^nction'..ro
		local DEND = '^d'..re
		local END = '^'..ro

		lineObj = lineObj or GetLines(false,code)
		local getline = lineObj.getline
	    local l, nl = lineObj.count, lineObj.lpos
	    local lines = lineObj.lines
		local currentFunction



		if l == 0 then
			Echo('Code given is empty')
			return code
		end
		-- local _, funcCounted = code:gsub(lo..'function'..ro,'')
		local curline = funcObj.line
		local nexposline = curline + 1

		local pos = nl[funcObj.line]
		-- local offset = pos - 1
		-- if pos > 1 then
		-- 	code = code:sub(pos)
		-- end
		local lastline = nl[nl.len]
		local endfile = code:len()

		local wasted = 0

		local function updateline(p)
			if curline<l and p >= nexposline then
				curline = getline(p)
				nexposline = nl[curline+1]
			end
			-- Echo('update line at',code:sub(p,p+3):readnl(),'=>',nls)
		end
		---------------------
		local level = 1
		local pEnd = funcObj.endPos
		local p, _, s
		while true do
			p, pEnd, s = code:find(anyl..'('..op1..op2..')', pEnd+1)
			if s then
				if s =='fu' then
					if code:find(FEND,pEnd+1) then
						pEnd = pEnd + 6
						-- s = 'function'
						level = level + 1
					else
						wasted = wasted + 1
						-- Echo('skip')
					end
				elseif s == 'en' then
					if pEnd+1 == endfile or code:find(DEND,pEnd+1) then
						pEnd = pEnd + 1
						level = level - 1
						if level == 0 then
							updateline(p+1)
							funcObj.lineEnd = curline
							break
						end
					else
						-- Echo("'d[%s%(;]' == DEND is ", 'd[%s%(%)%]}%,;]' == DEND, ro == '[%s%(%)%]}%,;]')
						wasted = wasted + 1
					end
				elseif s == 'if' or s == 'do' then
					if code:find(END,pEnd+1) then
						level = level + 1
					else
						wasted = wasted + 1
					end
				else
					wasted = wasted + 1
					-- Echo('wasted',s)
				end
			else
				break
			end
		end

		time = spDiffTimers(spGetTimer(), time);

		-- Echo("level is ", level)
		if tellTime then
			Echo('TIME FEND', time,'lineEnd',funcObj.lineEnd,'matches',matches, 'level',level,'wasted',wasted)
		end
		return funcObj.lineEnd, false, funcObj, time
	end

	-- init for testings
	--***************
		-- local WIDGET_DIRNAME     = LUAUI_DIRNAME .. 'Widgets/'
		-- local widgetFiles = VFS.DirList(WIDGET_DIRNAME, "*.lua", VFS.RAW_FIRST)
		-- local len = #widgetFiles
		-- local code, code2, time, time2
		-- local iter = 10

		-- local len = #widgetFiles

		-- source = "LuaUI\\Widgets\\testfuncs.lua"
		-- -- source = widgetFiles[math.random(len)]
		-- -- Echo("source is ", source)
		-- local ftime = f.time
		-- local code, codeObj = WG.Code:GetCode(source or "LuaUI\\Widgets\\UtilsFunc.lua")
	--*************
	-- Echo("code:len() is ", code:len())
	-- local unco, blanked = GetUncommentedAndBlanked3(false,code)
	-- local code1, code2
	-- mass testing random files
	--***********
		-- ftime:before()
		-- local notok = 0
		-- local len = #widgetFiles
		-- local iter = 5
		-- local time
		-- local totaltime, totallen = 0, 0
		-- for i = 1, iter do
		-- 	local source = widgetFiles[i]
		-- 	-- local source = widgetFiles[math.random(len)]
		-- 	-- while source:match('/') do -- for using only local file
		-- 	-- 	source = widgetFiles[math.random(len)]
		-- 	-- end
		-- 	-- Echo('treating ',source:match('[\\/][^\\/]+$'))
		-- 	local obj, _, codelen, time = GetLines(source,false,false,false,true)
		-- 	-- local obj2, _, codelen2, time2 = GetLines(source,false,true,false,true)
		-- 	-- if obj.count ~= obj2.count then
		-- 	-- 	Echo('wrong line count !',obj.count, obj2.count)
		-- 	-- end
		-- 	totaltime = totaltime + time + (time2 or 0)
		-- 	totallen = totallen + codelen + (codelen2 or 0)
		-- 	-- -- local n, lines, lpos, code = GetLines(source)
		-- 	-- -- for i = 1,5 do
		-- 	-- -- 	code = code or GetCode(source)
		-- 	-- -- 	local lp, lp2 = lpos[i], lpos[i+1]
		-- 	-- -- 	Echo(lines[i], lines[i] == code:sub(lp,lp2-2))
		-- 	-- -- end
		-- 	-- local code = GetCode(source)
		-- 	-- local orilen = code:len()
		-- 	-- -- local blanked = GetCodeAbstract(false,code)
		-- 	-- local unco = GetUncommented(false,code)

		-- 	-- -- local abstract, level = GetScopesABSTRACT_FULL(blanked)
		-- 	-- local abstract, level = GetScopes2(unco,1,false)
		-- 	-- Spring.SetClipboard(abstract)
		-- 	-- -- Echo('SIZE: ' .. orilen ..' => '..abstract:len())

		-- 	-- local l1, l2 = GetLines(source), GetLines(false,abstract)
		-- 	-- -- Echo('LINES: '..l1.. ' = > ' ..l2, l1 == l2  and 'OK' or 'WRONG')
		-- 	-- -- Echo("level is ", level)
		-- 	-- -- if l1 ~= l2 or level ~= 0 then
		-- 	-- -- 	notok = notok + 1
		-- 	-- -- end
		-- end
		-- ftime:after('TOTAL TIME')
		-- Echo('TOTAL', totaltime, (totaltime / (totallen/1e6)) .. ' per million char')

		-- if notok > 0 then
		-- 	Echo('GOT WRONGS',notok)
		-- else
		-- 	Echo('ALL GOOD',iter,'treated')
		-- end
	--************


	-- -- Echo("GetLines() is ",( GetLines(false,code)))
	-- -- local blanked = GetCodeAbstract(false,code)
	-- local unco, blanked = GetUncommentedAndBlanked3(false, code, false)
	-- -- local unco = GetUncommented(false, code)
	-- -- local blanked = BlankStrings(false, unco)
	-- local lineObj, timelines = GetLines(false,unco, true)
	-- -- Echo('Time lines',timelines)
	-- local funcs, funcTxt, level = GetFuncs(blanked, unco, lineObj, true, true)

	-- Spring.SetClipboard(funcTxt)
	----- mass testing
	-------********------
		-- local t, names, i = {}, {}, 0
		-- for line,fObj in pairs(funcs) do
		-- 	i = i + 1
		-- 	t[i] = line
		-- 	if fObj.others then
		-- 		names[line] = {}
		-- 		local those_names = names[line]
		-- 		for i, other in ipairs(fObj.others) do
		-- 			those_names[i] = other.name
		-- 		end
		-- 	end

		-- end
		-- local iter = 10000
		-- local freshfuncs = {}
		-- local random = math.random
		-- local notok = 0
		-- local totaltime, totaltimeFunc = 0, 0
		-- local totalreused, totalreused_end = 0, 0
		-- local endtime = 0
		-- local tell, getText = false,false
		-- local withname = 0
		-- ftime:before()
		-- for j=1, iter do
		-- 	local line = t[random(i)]
		-- 	local name
		-- 	if names[line] then
		-- 		withname = withname + 1
		-- 		local len = #names[line]
		-- 		local r = random(len+1)
		-- 		if r > len then
		-- 			name = funcs[line].name
		-- 		else
		-- 			name = names[r]
		-- 		end
		-- 	end
		-- 	-- Echo('testing ' .. (name or '') .. ' at line ' .. line)
		-- 	local func, reused, time, timeFunc, funcText = GetFuncRaw(blanked,unco,line,lineObj,name,freshfuncs, true, tell)
		-- 	if not func or name and func.name~= name then
		-- 		notok = notok + 1
		-- 	else
		-- 		local lineEnd, _reused, func, _time = ReachEndOfFunction2(func,blanked,unco,lineObj, false)
		-- 		if not lineEnd then
		-- 			notok = notok + 1
		-- 		else
		-- 			endtime = endtime + _time
		-- 			totaltime = totaltime + time + _time
		-- 			totaltimeFunc = totaltimeFunc + timeFunc
		-- 			if reused then
		-- 				totalreused = totalreused + 1
		-- 			end
		-- 			if _reused then
		-- 				totalreused_end = totalreused_end + 1
		-- 			end
		-- 		end
		-- 	end
		-- end
		-- Echo(
		-- 	(notok>0 and 'wrongs!: ' .. notok or '')
		-- 	..'total checked', iter,'Total Time',totaltime,
		-- 	'end time ' .. endtime, 'reused end',totalreused_end,
		-- 	withname .. ' with name',
		-- 	'time for func', ('%.3f%%'):format((totaltimeFunc>0 and (totaltimeFunc / totaltime) or 0) * 100) ,
		-- 	'per 100 check',totaltime / (iter/100),'reused',totalreused
		-- )
		-- ftime:after('global time')
		-- local parts, n = {}, 0
		-- for line in pairs(funcs) do
		-- 	local fresh = freshfuncs[line]
		-- 	if fresh then
		-- 		n = n + 1
		-- 		parts[n] = fresh
		-- 		local others = fresh.others
		-- 		if others then
		-- 			for i, fn in ipairs(others) do
		-- 				n = n + 1
		-- 				parts[n] = fn
		-- 			end
		-- 		end
		-- 	end
		-- end
		-- table.sort(
		-- 	parts,
		-- 	function(a,b)
		-- 		return a.line < b.line
		-- 	end
		-- )
		-- for i,part in pairs(parts) do
		-- 	parts[i] = part:maketext()
		-- end
		-- if n>0 then
		-- 	local report = table.concat(parts,'\n')
		-- 	Spring.SetClipboard(report)
		-- end
	---------*******---------
	-- local unco = GetUncommented(false,code)
	-- local abstract = GetScopesABSTRACT_FULL(blanked)
	-- -- -- Echo("code:len() .. ' = > ' abstract:len() is ", code:len() .. ' = > ' .. abstract:len())
	-- Echo( "GetLines(code) is ", (GetLines(false,code)),(GetLines(false,blanked)), (GetLines(false,abstract)) )
	-- Spring.SetClipboard(abstract)
	-- Spring.SetClipboard(blanked)
	 -- Spring.SetClipboard(funcTxt)
end

--************************  WRAPPER  *************************
WRAPPER = {}
local SIMPLE_DEBUG = false

do
	local WRAPPER = WRAPPER
	local ismeta = {
		__index = true,
		__newindex = true,
		__call = true,
		__lt  = true,
		__le  = true,
		__gt  = true,
		__ge  = true,
		__eq  = true,
		__add = true,
		__sub = true,
		__tostring = true,
		__concat = true,
		__gc = true,
	}
	local badnames = {
		sethook = true,
		Echo = true,
		tostring = true,
		getinfo = true,
		[''] = true,
	}
	-- local wrapped = {}

	-- WRAPPER.wrapped = wrapped
	local wraps = {}
	local wrappedFunc = {}

	local failed = {}
	local failedcaller = {}
	WRAPPER.wraps = wraps
	WRAPPER.wrappedFunc = wrappedFunc
	WRAPPER.badnames = badnames
	WRAPPER.failed = failed
	WRAPPER.failedcaller = failedcaller


	function WRAPPER.findwidget(func, stacklevel)
		local found = false
		local i = 1
		while i<30 do
			i = i + 1
			local inf = getinfo(stacklevel + i,'S')
			if inf and inf.source and inf.source:match('cawidgets.lua') then
				-- climb up to cawidgets at a callin or at LoadWidget
				inf = getinfo(stacklevel + i,'f')
				if inf.func then
					local locals, indexes = f.GetLocalsOf(stacklevel + i)
					for k,v in pairs(locals) do
						if k == 'w' or k=='widget' then
							return v
						end
					end
				end
			end
		end

	end
	-- OUT OF DATE useless (hopefully)
	function WRAPPER.Get(namewhat,func,name,caller, stacklevel)
		local wrappedObj = wrapped[func]
		if wrappedObj then
			if namewhat == 'global' then
				local env = getfenv(func)
				if wrapped[env] then
					return wrapped[env][name]
				end
			elseif namewhat == 'field' then
				local env = WRAPPER.GetTableHolder(func, name, caller, stacklevel+1)
				if wrapped[env] then
					return wrapped[env][name]
				end
			else
				if namewhat == 'upvalue' then
					if wrappedObj.upvalues then
						local index = f.GetUpvaluesOf(caller.func,name, info.func)
						if index then
							return wrappedObj.upvalues[index]
						end
					end
				elseif namewhat == 'local' then
					if wrappedObj.locals then
						local index = f.GetLocalsOf(stacklevel + 1)
						if index then
							return wrappedObj.locals[index]
						end
					end
				end
			end
		end
	end
	---
	function WRAPPER.wraplocal(func,name,callerfunc,index,level, nwhat)
		if not func then
			Echo('NO FUNC',name, nwhat, comment)
			return
		end

		local banned = false
		local level = level
		local nwhat = '(local)'
		local run, wrap
		if debugCycle then
			Echo('wrapping',name, nwhat)
		end
		local unwrap, sleep = false, true
		local Unwrap = function()
			if not wraps[run] then
				if debugCycle then
					Echo('already unwrapped ',name,nwhat)
				end
				return
			end

			if debugCycle then
				Echo('ordering unwrap',name, nwhat) -- afaik cannot unwrap it immediately, will have to wait for it to be run again
			end
			unwrap = true
			wraps[run] = nil
		end
		run = function(...)
			if PERIODICAL_CHECK then
				PERIODICAL_CHECK = PERIODICAL_CHECK + 1
			end
			if unwrap then
				if debugCycle then
					Echo('exec unwrap',name, nwhat)
				end
				debug.setlocal(2,index,func)
				return func(...)
			elseif sleep or banned or not IN_SCOPE or level >= GLOBAL_MUTE_LEVEL then
				-- Echo(name,'wrap is sleeping')
				return func(...)
			end

			if SIMPLE_DEBUG then
				local offset = -1
				local info = getinfo(2,'l')
				if info.currentline == -1 then 
					offset = offset+1
				end
				for i = 1+offset, 2+offset do
					offset = i
					local finfo = getinfo(i+2,'f')
					if not wraps[finfo.func] then
						if i==1 then
							break
						else
							info = getinfo(i+2,'l')
							break
						end
					end
				end
				Echo('wrap ',name,nwhat,'is running at',info.currentline,'stkoffset',offset)
				return func(...)
			end






			local info = getinfo(2,'l')
			if info.currentline == -1 and not wrap.lines[info.currentline] then
				for i = 1, 2 do
					info = getinfo(i+2,'f')
					if not wraps[info.func] then
						info = getinfo(i+2,'l')
						break
					end
				end
			end
			-- Echo('running wrap ',name,'(local)',info.currentline)
			local funcObj = wrap.lines[info.currentline]
			if not funcObj then
				if debugCycle then
					Echo('!! wrap',name,nwhat,'not finding the funcObj! at',info.currentline)
				end
				return func(...)
			end
			local node = funcObj.node

			node:Open(true)
			local ret = {func(...)}
			node:Close(true)

			return unpack(ret)
		end
		local Sleep = function(bool)
			if debugCycle then
				Echo('set sleep '..tostring(bool)..' for ',name,nwhat)
			end
			sleep = bool
			wrap.silent = bool
		end
		local Ban = function(bool)
			banned = bool
		end


		wrap = {Unwrap=Unwrap, Sleep=Sleep, Ban=Ban, name=name, lines = {}, silent = sleep, silentHead = false
		,func = func,nwhat = nwhat, callerfunc = callerfunc,index = index,env = env}
		wraps[run] =  wrap
		wrappedFunc[func] = wrap
		debug.setlocal(level+1,index,run) -- run become the function under the original name
		return wrap
	end
	function WRAPPER.wrapglobal(func, name, env, stacklevel, comment)
		if not func then
			Echo('NO FUNC',name, nwhat, comment)
			return
		end

		local banned = false
		local level = level
		local nwhat = comment or '(global)'
		local run, wrap
		if env._G then -- avoid wrapping stuff from real global
			local w = WRAPPER.findwidget(func, stacklevel+1)
			if w and w[name] and w[name] == func then
				Echo('reporting env to widget env')
				env = w
			else
				failed[env] = failed[env] or {}
				if not name then
					Echo('no name ????')
					return
				elseif not failed[env][name] then
					failed[env][name] = true
					failedcount = failedcount + 1
				end
				return
			end
		end



		local sleep = true
		if debugCycle then
			Echo('wrapping ',name,nwhat)
		end
		local Unwrap = function()
			if not wraps[run] then
				if debugCycle then
					Echo('already unwrapped ',name,nwhat)
				end
				return
			end

			if debugCycle then
				Echo('unwrapping ',name,nwhat)
			end
			env[name] = func
			if not func or env[name] ~= func then
				Echo('Problem restoring func in table !',name,func, env[name], env.classname)
			end
			wraps[run] = nil

		end
		run = function(...)
			if PERIODICAL_CHECK then
				PERIODICAL_CHECK = PERIODICAL_CHECK + 1
			end

			if sleep or banned or not IN_SCOPE or level >= GLOBAL_MUTE_LEVEL then
				-- Echo('wrap is sleeping',name,nwhat)
				return func(...)
			end


			if SIMPLE_DEBUG then
				local offset = -1
				local info = getinfo(2,'l')
				if info.currentline == -1 then 
					offset = offset+1
				end
				for i = 1+offset, 2+offset do
					offset = i
					local finfo = getinfo(i+2,'f')
					if not wraps[finfo.func] then
						if i==1 then
							break
						else
							info = getinfo(i+2,'l')
							break
						end
					end
				end
				Echo('wrap ',name,nwhat,'is running at',info.currentline,'stkoffset',offset)
				return func(...)
			end


			local info = getinfo(2,'l')
			if info.currentline == -1 and not wrap.lines[info.currentline] then
				for i = 1, 2 do
					info = getinfo(i+2,'f')
					if not wraps[info.func] then
						info = getinfo(i+2,'l')
						break
					end
				end
			end
			local funcObj = wrap.lines[info.currentline]
			-- Echo('running wrap ',name,'(global)',info.currentline)
			if not funcObj then
				if debugCycle then
					Echo('!! wrap',name,nwhat,'not finding the funcObj! at',info.currentline)
				end
				return func(...)
			end
			local node = funcObj.node
			node:Open(true)

			local ret = {func(...)}
			node:Close(true)


			return unpack(ret)
		end
		local Sleep = function(bool)
			if debugCycle then
				Echo('set sleep '..tostring(bool)..' for ',name,nwhat)
			end
			sleep = bool
			wrap.silent = bool
		end
		local Ban = function(bool)
			banned = bool
		end
		local _tostring = env.tostring
		env[name] = run -- run become the function under the original name
		

		if env[name] ~= run then
			-- the talbe/env got a metatable refusing to set it
			Echo(name ,'couldnt be wrapped (metamethod probably preventing)')
			failed[env] = failed[env] or {}
			if not failed[env][name] then
				failed[env][name] = true
				failedcount = failedcount + 1
			end

			return
		end


		wrap = {Unwrap=Unwrap, Sleep=Sleep, Ban=Ban, name=name, lines = {}, silent = sleep, silentHead = false
		,func = func,nwhat = nwhat, callerfunc = callerfunc,index = index,env = env}
		wraps[run] = wrap
		wrappedFunc[func] = wrap
		return wrap
	end
	function WRAPPER.wrapupvalue(func, name, callerfunc, index, comment)
		if not func then
			Echo('NO FUNC',name, nwhat, comment)
			return
		end

		local banned = false
		local level = level
		local nwhat = comment or '(upvalue)'
		local Echo = Spring.Echo
		local run, wrap
		if debugCycle then
			Echo('wrapping', name, nwhat)
		end
		local sleep = true
		local Unwrap = function()
			if not wraps[run] then
				if debugCycle then
					Echo('already unwrapped ',name,nwhat)
				end
				return
			end

			if debugCycle then
				Echo('unwrapping ',name,nwhat)
			end
			local i2,n2,v2 = f.GetUpvaluesOf(callerfunc, nil, run)

			if not i2 then
				Echo('problem ! our wrap is not found as upvalue !')
			elseif i2 ~= index then
				Echo('our wrap has moved', index,')>',i2)
				index = i2
			-- else
			-- 	Echo('our wrap has been found correctly at',i2,' under the name ',n2)
			end
			debug.setupvalue(callerfunc,index,func)
			wraps[run] = nil
			wrappedFunc[wrap.func] = nil
		end
		run = function(...)
			if PERIODICAL_CHECK then
				PERIODICAL_CHECK = PERIODICAL_CHECK + 1
			end

			if sleep or banned or not IN_SCOPE or level >= GLOBAL_MUTE_LEVEL then
				-- Echo('wrap is sleeping',name,nwhat)
				return func(...)
			end


			if SIMPLE_DEBUG then
				local offset = -1
				local info = getinfo(2,'l')
				if info.currentline == -1 then 
					offset = offset+1
				end
				for i = 1+offset, 2+offset do
					offset = i
					local finfo = getinfo(i+2,'f')
					if not wraps[finfo.func] then
						if i==1 then
							break
						else
							info = getinfo(i+2,'l')
							break
						end
					end
				end
				Echo('wrap ',name,nwhat,'is running at',info.currentline,'stkoffset',offset)
				return func(...)
			end




			local wasted = spGetTimer()
			local info = getinfo(2,'l')
			if info.currentline == -1 and not wrap.lines[info.currentline] then
				for i = 1, 4 do
					info = getinfo(i+2,'f')
					if not wraps[info.func] then
						info = getinfo(i+2,'l')
						break
					end
				end
			end

			local funcObj = wrap.lines[info.currentline]
			if not funcObj then
				if debugCycle then
					Echo('!! wrap',name,nwhat,'not finding the funcObj! at',info.currentline)
				end
				return func(...)
			end
			local node = funcObj.node
			-- if node.level < CURRENT_NODE.level then
			-- 	if debugCycle then
			-- 		Echo('!! wrong wrap execution '..tostring(node.name)..' (id:'..funcObj.id.. ') level '..node.level,'while current node is at ', CURRENT_NODE.level)
			-- 	end
			-- 	return func(...)
			-- end
			-- funcObj.node:OpenForwardID(funcObj.id, true)
			node:Open(true)

			local ret = {func(...)}


			node:Close(true)


			-- do stuff after
			return unpack(ret)
		end
		local Sleep = function(bool)
			if debugCycle then
				Echo('set sleep '..tostring(bool)..' for ',name,nwhat)
			end
			sleep = bool
			wrap.silent = bool
		end
		local Ban = function(bool)
			banned = bool
		end
		wrap = {Unwrap=Unwrap, Sleep=Sleep, Ban=Ban, name=name, lines = {}, silent = sleep, silentHead = false
		,func = func,nwhat = nwhat, callerfunc = callerfunc,index = index,env = env}
		wraps[run] = wrap
		wrappedFunc[func] = wrap
		--
		debug.setupvalue(callerfunc,index,run)-- run become the function under the original name
		return wraps[run]
	end
	function WRAPPER.wrapfield(func, name, env, nwhat, comment)
		-- if true then
		-- 	Echo('refusing to wrap',name,namewhat, comment)
		-- 	for k,wrap in pairs(BRANCH_WRAPS) do
		-- 		if wrap.func == func then
		-- 			Echo(' this is a branch func !')
		-- 		elseif wrap.run == func then
		-- 			Echo('this is a branch wrap !')
		-- 		elseif env[name] == wrap.run then
		-- 			Echo('that func field has already a branch wrap !')
		-- 		elseif env[name] == wrap.func then
		-- 			Echo('that func is already wrapped by a branch wrap !')
		-- 		end
		-- 	end

		if type(name) == 'function' then
			Echo('error ! name is a function',nwhat,comment,env)
			return
		end
		-- Echo('check',name, namewhat,comment)
		-- Echo('check =>',env[name])



			if env[name] ~= func then
				Echo(' the given func or given env is wrong !',name,namewhat,comment or '','mt?',getmetatable(env))
				for k,v in pairs(env) do
					if v == func then
						Echo(' but correct in pairs !',k)
					elseif k == name then
						Echo('but name exist in env !')
					end
				end
				-- Echo("debug.traceback() is ", debug.traceback())
				return
			end
		-- end
		if not func then
			Echo('NO FUNC',name, nwhat, comment)
			return
		end
		-- if true then
		-- 	Echo('wrapping ',namewhat,comment,name,'verifying...')
		-- 	for k,wrap in pairs(wraps) do
		-- 		if wrap.func == func then
		-- 			Echo('that function has been found already wrapped, with name',wrap.name)
		-- 		end
		-- 	end
		-- 	if wraps[func] then
		-- 		Echo('that function appears to be a wrap ! with name',wraps[func].name)
		-- 	end
		-- end
		local banned = false
		local level = level
		local _nwhat = nwhat
		local nwhat = comment or nwhat
		local run, wrap
		local sleep = true
		if debugCycle then
			Echo('wrapping ',name,nwhat)
		end
		local Unwrap = function()
			if not wraps[run] then
				if debugCycle then
					Echo('already unwrapped ',name,nwhat)
				end
				return
			end

			if debugCycle then
				Echo('unwrapping ',name,nwhat)
			end
			env[name] = func
			if name == 'CallListeners' then
				Echo('unwrapped ',name,'from',env.classname,'verify',func,env[name],func == env[name])
			end
			wraps[run] = nil

			-- wrapped[env][name] = nil
			-- if not next(wrapped[env]) then
			-- 	wrapped[env] = nil
			-- end
		end
		run = function(...)
			if PERIODICAL_CHECK then
				PERIODICAL_CHECK = PERIODICAL_CHECK + 1
			end

			if sleep or banned or not IN_SCOPE or level >= GLOBAL_MUTE_LEVEL then
				-- Echo('wrap ', name, '(global) is sleeping')
				-- NO EXTRA FUNCTION FROM WRAP MUST BE CALLED WHEN HOOK IS RUNNING
				return func(...)
			end


			if SIMPLE_DEBUG then
				local offset = -1
				local info = getinfo(2,'l')
				if info.currentline == -1 then 
					offset = offset+1
				end
				for i = 1+offset, 2+offset do
					offset = i
					local finfo = getinfo(i+2,'f')
					if not wraps[finfo.func] then
						if i==1 then
							break
						else
							info = getinfo(i+2,'l')
							break
						end
					end
				end
				Echo('wrap ',name,nwhat,'is running at',info.currentline,'stkoffset',offset)
				return func(...)
			end



			local info = getinfo(2,'l')
			if info.currentline == -1 and not wrap.lines[info.currentline] then
				for i = 1, 2 do
					info = getinfo(i+2,'f')
					if not wraps[info.func] then
						info = getinfo(i+2,'l')
						break
					end
				end
			end
			-- Echo('running wrap ',name,nwhat,info.currentline)
			local funcObj = wrap.lines[info.currentline]
			if not funcObj then
				if debugCycle or name == 'CallListeners' then
					Echo('!! wrap',name,nwhat,'not finding the funcObj! at',info.currentline)
				end
				return func(...)
			end
			local node = funcObj.node
			-- if node.level < CURRENT_NODE.level then
			-- 	if debugCycle then
			-- 		Echo('!! wrong wrap execution '..tostring(node.name)..' (id:'..funcObj.id.. ') level '..node.level,'while current node is at ', CURRENT_NODE.level)
			-- 	end
			-- 	return func(...)
			-- end
			-- funcObj.node:OpenForwardID(funcObj.id, true)
			node:Open(true)

			local ret = {func(...)}
			node:Close(true)


			return unpack(ret)
		end
		local Sleep = function(bool)
			if debugCycle then
				Echo('set sleep '..tostring(bool)..' for ',name,nwhat)
			end

			sleep = bool
			wrap.silent = bool
		end
		local Ban = function(bool)
			banned = bool
		end

		env[name] = run
		-- if name == 'CallListeners' then
		-- 	Echo(
		-- 		'wrapping ',name,nwhat,_nwhat,'env is an instance?',env.classname,
		-- 		'env has metatable?',getmetatable(env),'func is the Object method?',WG.Chili.Object[name],'=>',WG.Chili.Object[name] == func,
		-- 		'env has successfully beend updated?',env[name] == run, env[name] ~= func

		-- 	)
		-- end
		if env[name] ~= run then
			Echo('!!' , name,'couldnt be wrapped (methamethod probably preventing)')
			failed[env] = failed[env] or {}
			if not failed[env][name] then
				failedcount = failedcount + 1
				failed[env][name] = true
			end

			return
		end

		wrap = {Unwrap=Unwrap, Sleep=Sleep, Ban=Ban, name=name, lines = {}, silent = sleep, silentHead = false
		,func = func,nwhat = nwhat, callerfunc = callerfunc,index = index,env = env}
		wraps[run] = wrap -- run become the function under the original name

		wrappedFunc[func] = wrap
		-- if not wrapped[env] then
		-- 	wrapped[env] = {[name]=true}
		-- else
		-- 	wrapped[env][name] = true
		-- end


		return wrap
	end
	---
	local failedFuncs, alreadyTried = {}, {}
	function WRAPPER.Wrap(what, namewhat, func, name, caller, stacklevel)
		if failed[func] then
			return
		end
		-- Echo('wrapping', name, namewhat)
		local fcaller = failedcaller[caller.func]
		if fcaller and fcaller[namewhat] and fcaller[namewhat][func] then
			return
		end
		local comment
		local wrap
		local index, env
		local calledline, comment, callername
		-- if name and name:match('nowrap') then
		-- 	return
		-- end
		if namewhat == '' then
			if ismeta[name] then
				stacklevel = stacklevel - 1
			end
			namewhat, name, index, env, caller, callername, calledline, stacklevel, comment = WRAPPER.LocateFunc(func,name,stacklevel+1)
			-- if type(env) == 'metatable' then
			-- 	local _env = getmetatable(env)
			-- 	Echo("type(_env) is ", type(_env))
			-- end

			-- Echo('located:',namewhat, name, index, env, caller, callername, calledline, stacklevel, comment)
			if wraps[func] or caller.func and wraps[caller.func] then
				return
			end
			if type(env) == 'table' then
				local _env = getmetatable(env)
				if type(_env) == 'table' then
					comment = 'metamethod'
					env = _env
				elseif _env then
					failed[env] = true
					Echo('bad retrieve metatable for', name)
					return
				end

			end
			if env then
				if namewhat == 'field' or namewhat == 'method' then
					return WRAPPER.wrapfield(func, name,env, namewhat, comment ), comment
				else
					return WRAPPER.wrapglobal(func, name,env, stacklevel+1, comment ), comment
				end
			elseif namewhat == 'upvalue' then
				return WRAPPER.wrapupvalue(func, name, caller.func, index, comment )
			end
			stacklevel = stacklevel + 1
			if namewhat then
				if badnames[name] then
					if not failed[func] then
						failedcount = failedcount + 1
						failed[func] = name ..' retrieved'
					end
					return
				elseif env and failed[env] and failed[env][name] then
					return
				end
			end
		end
		if namewhat == 'local' then

			-- NOTE
			-- there is no use of wrapping an ephemeral local made in a function in many situations,
			-- and would be very costly as it has to be done at every new call of the function caller
			-- we can't know if it worth to wrap it as it may run some long code interesting to time and debug
			-- if that local is made from upvalue or field or global, what would be good is to wrap it instead
			-- and indicate that nuance
			----- cancelled ---------
			-- local index = index or f.GetLocalsOf(stacklevel + 1, name, func)
			-- if index then
			-- 	wrap = WRAPPER.wraplocal(func, name, caller.func, index, stacklevel + 1)
			-- end
			-------------------------
			local foundname, index, env, tbl, com = WRAPPER.LocateLocal(func, name, caller, stacklevel + 1)
			if index then
				comment = com
				wrap = WRAPPER.wrapupvalue(func, foundname, caller.func, index, comment )
			elseif env then
				comment = com
				wrap = WRAPPER.wrapglobal(func, foundname,env, stacklevel+1, comment )
			elseif tbl then
				comment = com
				wrap = WRAPPER.wrapfield(func, foundname,tbl, 'field', stacklevel+1, comment )
			end


		elseif namewhat == 'global' then
			local env = env or getfenv(func)
			wrap = WRAPPER.wrapglobal(func, name,env, stacklevel+1, comment)
		elseif namewhat == 'upvalue' then
			if caller.func then
				local index = f.GetUpvaluesOf(caller.func, name, func)
				if not index then
					local nm
					index, nm = f.GetUpvaluesOf(caller.func, nil, func)
					if index then
						comment = (comment or 'upvalue, ') .. 'NAME DIFFER: ' .. nm .. ' != ' .. name
					end
				end
				if index then
					wrap = WRAPPER.wrapupvalue(func, name, caller.func, index, comment)
				end
			end
		elseif namewhat == 'field' or namewhat =='method' then
			local tbl, com = WRAPPER.GetTableHolder(func, name, caller, stacklevel+1)
			if tbl then
				comment = com
				wrap = WRAPPER.wrapfield(func, name, tbl, namewhat, comment)
			end
		end
		if not wrap then
			namewhat = tostring(namewhat)
			local callerfunc = caller.func
			if not callerfunc then
				failedcount = failedcount + 1
				failed[func] = true
			else
				failedcount = failedcount + 1
				if not failedcaller[callerfunc] then failedcaller[callerfunc] = {} end
				if not failedcaller[callerfunc][namewhat] then failedcaller[callerfunc][namewhat] = {} end
				if not failedcaller[callerfunc][namewhat][func] then
					failedcallercount = failedcallercount + 1
					failedcaller[callerfunc][namewhat][func] = true
				end

			end

		end
		-- Echo('wrap success', wrap, comment)
		return wrap, comment
	end
	-----------------------
	-----------------------
	function WRAPPER.GetTableHolder(func, name, caller, stacklevel)
		-- look for tables in the caller
		if failedFuncs[func] then
			Echo('check1')
			return
		end

		-- if alreadyTried[func] then
		-- 	Echo('check2')
		-- 	-- Echo('already tried to find', name, 'caller',caller and caller.func, alreadyTried[func] == caller and caller.func)
		-- 	return
		-- end
		-- alreadyTried[func] = caller and caller.func
		local found = false
		---- locals
		------- we don't wanna wrap ephemeral tables --------
		-- local locals = f.GetLocalsOf(stacklevel + 1)
		-- if locals then
		-- 	for n,value in pairs(locals) do
		-- 		-- Echo('local', k,v)
		-- 		if type(value) == 'table' then
		-- 			if value[name] == func then
		-- 				local mt = getmetatable(value)
		-- 				if mt and type(mt)=='table' and  type(mt.__index) == 'table' then
		-- 					if mt.__index[name] == func then
		-- 						found = mt.__index
		-- 					end
		-- 				end
		-- 				if not found then
		-- 					found = value
		-- 				end
		-- 			end
		-- 		end
		-- 		if found then
		-- 			break
		-- 		end
		-- 	end
		-- end
		----------
		---- upvalues

		if not found and caller.func then
			local upvalues = f.GetUpvaluesOf(caller.func)
			local known = {}
			for n, value in pairs(upvalues) do
				if type(value) == 'userdata' then
					local mt = getmetatable(value)
					if mt and mt._islink then
						while type(value) == 'userdata' do
							value = value()
						end
					end
				end
				if type(value) == 'table' then
					if n ~= 'inherited' then
						-- Echo('looking for ',name,'in table...',n,value,'already wrapped?',WRAPPER.wraps[func],'known?',known[value])
						if not known[value] then
							known[value] = true
							if ismeta[name] then
								local mt = getmetatable(value)
								if mt then
									if mt[name] == func then
										found = mt
										return mt, '(meta method)'
									end
								end
							else

								local mt = getmetatable(value)
								local cant = false
								if mt then
									if type(mt)=='table' then
										if mt.__index then
											if type(mt.__index) == 'table' then
												if mt.__index[name] == func then
													found = mt.__index
													return mt.__index, '(in meta index tbl)'
												end
											elseif mt.__index == func then
												found = mt
												return mt, '(is meta __index)'
											else
												-- 
												cant = true
											end
										elseif mt[name] then
											return mt, '(is meta field)'
										end
									end
								end
								if not cant then
									if value[name] == func then
										if not found then
											return value
										end
									end
								end
							end
						end
					end

				end
				if found then
					break
				end
			end
		end
		---- globals
		if not found then
			for i = 1, 3 do
				local env
				if i == 1 then
					env = WRAPPER.findwidget(func, stacklevel + 1)
				elseif i == 2 then
					env = getfenv(func)
				elseif i == 3 then
					env = WG
				end
				if env then
					if env[name] == func then
						local mt = getmetatable(env)
						if type(mt) == 'table' then
							local __index = mt.__index
							if __index then
								if type(__index) == 'table' then
									if __index[name] == func then
										return __index, '(meta index table)'
									end
								end
							end
						end
						return env
					else
						for ntable, v in pairs(env) do
							if type(v) == 'table' then
								for subk, subv in pairs(v) do
									if subk == name and subv == func then
										if i == 1 then
											if dbg then
												Echo('=> in widget',subk,func,'env is Object ?',WG.Chili.Object,v == WG.Chili.Object)
											end
											return v, '(tbl in widget)'
										elseif i == 2 then
											if dbg then
												Echo('=> in global',subk,func)
											end

											return v, '(tbl in global)'
										else
											if dbg then
												Echo('=> in WG table',subk,func)
											end
											return v, '(tbl in WG)'
										end
									end
								end
							end
						end
					end
				end
			end
		end
		if not found then
			-- Echo('failed to find',name)
			failedcount = failedcount + 1
			local callerfunc = caller.func
			if not failedcaller[callerfunc] then failedcaller[callerfunc] = {} end
			if not failedcaller[callerfunc]['field'] then failedcaller[callerfunc]['field'] = {} end
			if not failedcaller[callerfunc]['field'][func] then
				failedcallercount = failedcallercount + 1
				failedcaller[callerfunc]['field'][func] = true
			end
		end
		return found
	end
	-----------------------
	function WRAPPER.LocateLocal(func, name, caller, stacklevel)
		local upv, indexes = f.GetUpvaluesOf(caller.func)
		for k,value in pairs(upv) do
			if type(value) == 'function' then
				if value == func then
					return k, indexes[k], false, false, "(upvalue from local '"..tostring(name).."')"
				end
			elseif type(value) == 'table' then
				if value[name] == func then -- if by chance the name of the field is the same as the local, also can trigger the meta index which is not possible with pairs
					local mt = getmetatable(value)
					if mt and type(mt) == 'table' then
						if mt.__index and mt.__index[name] == func then
							Echo('found1')
							return name, false, false, mt.__index, "(in meta index in upval tbl from local '"..tostring(name).."')"
						end
					end
					return name, false, false, value, "(in tbl upval from local '"..tostring(name).."')"
				end
				for k,v in pairs(value) do
					if v == func then
						return k, false, false, value, "(in tbl upval from local '"..tostring(name).."')"
					end
				end
			end
		end
		local env = getfenv(func)
		if env then
			for k,v in pairs(env) do
				if env[k] == func then
					-- Echo('local is made from global ' .. tostring(k) .. ' of caller func')
					-- if wraps[func] then
					-- 	Echo('func is a wrap????')
					-- 	return
					-- elseif wraps[caller.func] then
					-- 	Echo('func is wrapped ????')
					-- 	return
					-- else
						return k, false, env, false, "(global from local '"..tostring(name).."')"
					-- end
				end
			end
		end

	end
	function WRAPPER.LocateFunc(func,name,stacklevel)
		-- Echo('locate func', name)
		local caller = getinfo(stacklevel+2,'fln')
		local callerfunc = caller and caller.func
		local callername, calledline
		local comment = '(located)'

		if not callerfunc then
			local s = getinfo(stacklevel+2,'S').source
			if s and s:find('tail call') then
				stacklevel = stacklevel + 1
				caller = getinfo(stacklevel+2,'fln')
				callerfunc = caller and caller.func
			end

		end
		if callerfunc then
			if wraps[callerfunc] then
				if SIMPLE_DEBUG then
					Echo('trying to locate',name,'caller is a wrap, getting up one more')
				end
				stacklevel = stacklevel + 1
				caller = getinfo(stacklevel+2,'fln')
				callerfunc = caller and caller.func
				if debugCycle and not callerfunc then
					Echo('!! LocateFunc detected wrap and failed to get uptop caller func',caller.name, caller.what, caller.namewhat,caller.currentline,getinfo(stacklevel+2,'S').source)
				end

			end
			callername, calledline = caller.name, caller.currentline
		else

			if debugCycle and not callerfunc then 
				Echo('!! LocateFunc couldnt retrieve an uptop level caller func',caller.name, caller.what, caller.namewhat,caller.currentline,getinfo(stacklevel+2,'S').source)
			end

		end
		local namewhat
		local index
		local env
		-- Echo("callers... ", caller.name, caller.name)
		-- Echo('level 1')
		-- for k,v in pairs(f.GetUpvaluesOf(caller.func)) do
		-- 	Echo(k,v)
		-- end
		-- Echo('level 2')
		-- for k,v in pairs(f.GetUpvaluesOf(caller.func)) do
		-- 	Echo(k,v)
		-- end
		if callerfunc then
			index, name = f.GetUpvaluesOf(callerfunc,nil,func)
			if index then
				namewhat = 'upvalue'
				comment = '(located upv)'
				-- wrap = WRAPPER.wrapupvalue(func, name, caller.func, index)
			else
				------ dont wrap locals
				-- index, name = f.GetLocalsOf(stacklevel+2,nil,func)
				-- if index then
				-- 	namewhat = 'local'
				-- 	-- wrap = WRAPPER.wraplocal(func, name, caller.func, index ,stacklevel + 2)
				-- end
				------
			end
		end
		if not namewhat then
			if callerfunc then
				local ups, indexes = f.GetUpvaluesOf(callerfunc)
				for k,value in pairs(ups) do
					if type(value) == 'table' then
						local mt = getmetatable(value)
						if mt then
							if type(mt) == 'table' then
								for k,v in pairs(mt) do
									if v == func then
										comment = '(located meta method from upvalue)'
										name = k
										namewhat = 'field'
										env = value
										break
									end
								end
							end
						end
						if not namewhat then
							for k,v in pairs(value) do
								if v == func then
									comment = '(located tbl from upvalue)'
									name = k
									namewhat = 'field'
									env = value
									Echo('name from upvalue is',name)
									break
								end
							end
						end
						if namewhat then
							break
						end
					end
				end
			end
		end
		if not namewhat then
			local _env = getfenv(func)
			if not name then
				for k,v in pairs(_env) do
					if v == func then
						name = k
						break
					end
				end
			end
			if name then
				if _env[name] == func then
					namewhat = 'global'
					env = _env
					comment = '(located in global)'
				end
			end
			-- if name then
			-- 	if not (badnames[name] or failed[env] and failed[env][name]) then
			-- 		wrap = WRAPPER.wrapglobal(func, name,env, stacklevel+1)
			-- 	else
			-- 		failed[func] = name
			-- 	end
			-- end
		end
		return namewhat, name, index, env, caller, callername, calledline, stacklevel-1, comment
	end
	function WRAPPER.UnwrapAll()
		for k,v in pairs(wraps) do
			v.Unwrap()
		end
	end
	function  WRAPPER.SleepAll()
		for _,wrap in pairs(WRAPPER.wraps) do
			wrap.Sleep(true) -- wraps sleep when hook is active
		end
	end
end
--************************************************************
do ------** TESTING WRAPPER **------
	local count = 0
	local badnames = WRAPPER.badnames
	local wraps = WRAPPER.wraps
	local failed = WRAPPER.failed
	local failedcaller = WRAPPER.failedcaller
	local function traceme(event, stacklevel) 
		count = count+1
		if count > 500 then
			debug.sethook(nil)
			for wfunc, wrap in pairs(WRAPPER.wraps) do
				wrap.Unwrap()
			end
			Echo('abnormal number of calls, aborting hook')
			return
		end
		stacklevel = (stacklevel or 0) + 2
		local info = debug.getinfo(stacklevel)
		local name = info.name
		local func = info.func

		
		local caller = debug.getinfo(stacklevel + 1)
		Echo(
			'#'..count,"name", info.name,info.what,info.namewhat,'line',
			caller and (caller.currentline or '??') or 'no caller',
			wraps[func] and '(WRAP)'
				or caller and wraps[caller.func] and '(WRAPPED)'
				or failed[func] and '(ABANDONED)' .. ' ('..tostring(failed[func])..')'
				or badnames[name] and '(BAD NAME)'
				or failedcaller[caller.func] and failedcaller[caller.func][info.namewhat]
					and failedcaller[caller.func][info.namewhat][func] and '(ABANDONED "'..info.namewhat..'")'
				or '(attempting wrap...)'
		)
		if not (caller and caller.currentline) or caller.currentline == -1 then
			Echo('current line func', info.currentline, 'def',info.linedefined,'-',info.lastlinedefined,wraps[caller.func])
		end


		if name and badnames[name] then
			-- Echo('bad name',name,'skipping')
			return
		end
		if wraps[func] then
			-- Echo('its a wrap, skipping...')

			return
		end
		if wraps[caller.func] then
			-- Echo('is wrapped, skipping...')
			return
		end
		if failed[func] then
			return
		end
		local namewhat = info.namewhat
		local failedcaller = failedcaller[caller.func]
		if failedcaller and failedcaller[namewhat] and failedcaller[namewhat][func] then
			return
		end
		local what = info.what
		local wrap = WRAPPER.Wrap(what, namewhat,func,name,caller, stacklevel+1)
		if not wrap then
			Echo('FAILED')
		end
	end
	local nofail = function(event)
		local success, err = pcall(traceme,event,2)
		if not success then
			debug.sethook(nil)
			Echo('problem happened, unhooked\n',err)
			for _, wrap in pairs(WRAPPER.wraps) do
				wrap.Unwrap()
			end
		end
	end


	t = {field = function() end}
	-- local testB = testA
	testC = function() end
	local count = 0
	local testB = function(bool) 
		if bool then
			gl.CreateList(testC)
		end
	end

	local testA = function()
		-- Echo('testA is running')
		-- local t = t
		count = count + 1
		testB(count>1)
		-- t.field()
	end
	local Z = function() end
	local count = 0
	local testX = function()
		count = count + 1
		if count > 1 then
			Z()
		end
	end
	local meta = function() end
	local T = setmetatable({},{__index = meta})
	local function testing()
			debug.sethook(nofail, 'c')

			-- testX()
			-- testX()
			local b = T.a

			debug.sethook(nil)

			Echo('-- hook end --')
			for wfunc, wrap in pairs(WRAPPER.wraps) do
				wrap.Sleep(false)
			end

			-- testX()

			Echo('-- unwrapping --')
			for wfunc, wrap in pairs(WRAPPER.wraps) do
				wrap.Unwrap()
			end

			Echo('-- done')

	end
	local done = false
	-- function widget:DrawScreen()
		if not done then

			debugCycle = 2
			SIMPLE_DEBUG = true
			IN_SCOPE = true

			-- testing()

			debugCycle = false
			SIMPLE_DEBUG = false
			IN_SCOPE = false

			done = true
		end
	-- end
end
--*************************************



-----------------------------------------------------------------------------


--------********************************************--------
--------********************************************--------
--------***************** TRACING ******************--------
--------********************************************--------
--------********************************************--------


-- remove hook when window is disposed if anything goes wrong
local function CloseWindows()
	if debug.gethook() == trace then
		sethook(nil)
	end
	for obj in pairs(windows) do
		if obj.win and not obj.win.disposed then
			local children = obj.win.children
			obj.win:Dispose()
		end
		windows[obj] = nil
	end
end
local function DestroyWhole()
	if debug.gethook() == trace then
		sethook(nil)
	end
	WRAPPER.UnwrapAll()
	for k,branchwrap in pairs(BRANCH_WRAPS) do
		branchwrap.Unwrap()
	end
	if debugOnSwitch then
		debugCycle = 2
	end
	for k,v in pairs(knownFuncs) do
		knownFuncs[k] = nil
	end
	for k in pairs(knownDefs) do
		knownDefs[k] = nil
	end
	funcObjCount = 0
	for k,v in pairs(CODES) do
		CODES[k] = nil
	end
	tree = nil
	tree2 = nil
end
local DBGNOW = false
local realLevel, PATH = 2, ''

local function tracefunc(event, s, calledline,stacklevel)
	-- NOTE:
	-- first event is the return of sethook because it's been called before trace began
	-- last event is the call of sethook with no return since it commend the end of tracing
	count = count + 1


	if event == 'call' then
		realLevel= realLevel + 1
		PATH = PATH .. '|' .. (s.name or UNKNOWN)
		-- if s.name == 'Rotate' or DBGNOW then
		-- 	Echo('+>>', s.name)
		-- 	DBGNOW = true
		-- end
		if MUTE_LEVEL then
			return
		end
		if debugCycle then
			Echo('#',count,'->lvl'..level)
		end
		if ignoredNames[s.name or ''] then
			if debugCycle then
				Echo('-- line '..tostring(calledline), tostring(s.name)..' ('..tostring(s.namewhat)..')' .. ' has been ignored. (trace ignored name) event#' .. count )
			end
			-- Echo(cnt(count).. ' ignored bc of name '..tostring(s.name))
			return
		end
		local func = s.func
		-- if not obj then
		-- 	Echo('starting with',s.name)
		-- end
		if not s.func then
			if debugCycle then
				Echo('-- line '..tostring(calledline), tostring(s.name)..' ('..tostring(s.namewhat)..')' .. ' has been ignored. (trace no func)  event#' .. count )
			end
		elseif not CURRENT_NODE then
			Echo('NO CURRENT NODE?!')
			sethook(nil)
			return
		else
			local node = CURRENT_NODE:Get(s, calledline, stacklevel+1) 

			if node then
				stackLVL[level] = node
				node:Open()
			end

		end
	else
		-- if DBGNOW then
		-- 	Echo('<<+', s and s.name or 'no s')
		-- 	if (s and s.name) == 'Rotate' then
		-- 		DBGNOW = false
		-- 	end
		-- end
		PATH = PATH:sub(1, (PATH:find('|[^|]+$') or 1)-1)
		realLevel = realLevel - 1
		if MUTE_LEVEL then
			if MUTE_LEVEL == level+1 then
				MUTE_LEVEL = false
			end
			return
		end
		if not stackLVL[level+1] then
			if debugCycle then
				Echo('-- ignoring return staying at '..(tostring(CURRENT_NODE.name or CURRENT_NODE.isTree and 'tree')) ..  ' event#' .. count)
			end
		elseif CURRENT_NODE then
			-- Echo("CURRENT_NODE.parent is ", CURRENT_NODE.parent,CURRENT_NODE.name,'is tree',CURRENT_NODE.isTree)
			CURRENT_NODE:Close() 
			stackLVL[level+1] = nil

		else
			if debugCyle then
				Echo('no more CURRENT_NODE!?')
			end
		end
		if debugCycle then
			Echo('#',count,'lvl'..level..'<-'
				--,(stackLVL[level] and ('['..tostring(stackLVL[level].name or stackLVL[level].isTree and 'tree')..']'))
			)
		end

	end
end

local ErrorReport = function(...)
	DestroyWhole()
	Echo(...)
	local traceback = debug.traceback()
	Echo(traceback:gsub('[^\n]-\n','',2))
	Echo('tracing ended with error')
end

trace = function(event)
	local s, calledline
	if event == 'call' then
		level = level + 1
		if level >= GLOBAL_MUTE_LEVEL then
			return
		end
		s = getinfo(2,'Snf')
		calledline = getinfo(3,'l').currentline
	else
		level = level - 1
		if level+1 >= GLOBAL_MUTE_LEVEL then
			return
		end
	end
	return xpcall(
		function() return tracefunc(event, s, calledline,5) end,
		ErrorReport
	)
end


------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------

----------------------------------------
local wraps = WRAPPER.wraps
local wrappedFunc = WRAPPER.wrappedFunc
----------------------------------------

-- separate treatment for branch head wrap
local function WrapBranchHead(branchfunc, callerfunc, index, env, tree, name,source)
	local branch
	local wrap
	local sleep = false
	local banned = false
	local sethook = debug.sethook
	local hookstarted = false
	local nwhat = type(index) == 'number' and callerfunc and '(upvalue)' or '(field)'
	local run = function(...)
		local gtime  = spDiffTimers(spGetTimer(),Node.timer)
		Node.globalTime = gtime
		CURRENT_NODE = tree
		level = level + 1
		IN_SCOPE = true
		tree.timer = spGetTimer()
		-- Echo("branchfunc is ", branchfunc)
		if debugCycle then
			debugCycle = debugCycle - 1
			Echo('========== CYCLE ' ..(debugCycle).. ' =============')
			if debugCycle == 0 then
				debugCycle = false
			end
		end
		if level >= GLOBAL_MUTE_LEVEL or banned then

		elseif HOOK_ACTIVE then
			PATH, realLevel = '', 2
			sethook(trace,'cr')
			hookstarted = true
		else
			if not branch then
				for k,child in pairs(tree.children) do
					if child.name == name then
						branch = child
						break
					end
				end
				if branch then
					branch.source = tostring(source)
				end
			end
			if branch and not sleep then
				branch:Open(true)
			else
				Echo('branch ',name,' not running, existing?',branch,'sleeping?',sleep)
			end
		end
		-------------------------
		local ret = {branchfunc(...)}
		-------------------------
		level = level - 1
		if hookstarted then
			sethook(nil)
			hookstarted = false
		end
		if level+1 >= GLOBAL_MUTE_LEVEL or banned then
			-- in some case (click ban MousePress callin especially) the ban come in the middle of the cycle

		elseif HOOK_ACTIVE then
			sethook(nil)
		elseif not sleep and branch then
			branch:Close(true)
		end
		IN_SCOPE = false


		local exe = tree.exe + spDiffTimers(spGetTimer(), tree.timer)
		tree.exe = exe
		local gtime = Node.globalTime
		if gtime >= tree.updateTime + UPDATE_RATE then 
			tree.updateTime = gtime
			tree.chilinode:SetText(
				('%s  -  %.1f/%.1f = %.1f%%'):format(
					tree.name, exe, gtime, (gtime>0 and (exe / gtime * 100) or 0)
				)
			)
			return
		end

		return unpack(ret)
	end
	local Unwrap = function()
		if not BRANCH_WRAPS[branchfunc] then
			return
		end
		if nwhat == '(upvalue)' then
			local i2,n2,v2 = f.GetUpvaluesOf(callerfunc, nil, run)

			if not i2 then
				Echo('problem ! our wrap is not found as upvalue !')
			elseif i2 ~= index then
				Echo('our wrap has moved', index,')>',i2)
				index = i2
			-- else
			-- 	Echo('our wrap has been found correctly at',i2,' under the name ',n2)
			end

			debug.setupvalue(callerfunc,index, branchfunc)
		end
		BRANCH_WRAPS[branchfunc] = nil
	end
	local Sleep = function(bool)
		sleep = bool
		wrap.silent = bool
	end
	local Ban = function(bool)
		banned = bool
	end
		wrap = {Unwrap=Unwrap, Sleep=Sleep, Ban=Ban, name=name, lines = {}, silent = sleep, silentHead = false
		,func = branchfunc,nwhat = nwhat, callerfunc = callerfunc,index = index,env = env, isBranch = true
		,run = run}

	BRANCH_WRAPS[branchfunc] = wrap
	tree.branchFuncs[branchfunc] = name
	tree.chilinode:SetText(tree.name)
	if nwhat == '(upvalue)' then
		debug.setupvalue(callerfunc,index, run)
	else
		if getmetatable(env) then
			Echo('branch env ',name,'got metatable !')
		end
		env[name] = run
	end
end



local function HeaderUpdate()
	if not (header and header.control) then
		return
	end
	if CURRENT_NODE.globalTime < header.updateTime + UPDATE_RATE then 
		return
	end
	header.updateTime = CURRENT_NODE.globalTime
	local currentcaption = header.control.caption
	-- local finalcaption = ('%s processed time: %.2fs, source fetched in: %.2fs'):format(
	-- 	header.caption, header.processed_time, header.source_fetch_time
	-- )
	local finalcaption = ('source fetched in: %.2fs'):format(
		header.source_fetch_time
	)

	if finalcaption ~= currentcaption then
		header.control:SetCaption(finalcaption)
	end
end
------********* NUANCER *********-------
do -- reNuances and greyed
	local function ColStr(color)
	    local char=string.char
	    local round = function(n) -- that way of declaring function ('local f = function()' instead of 'local function f()' make the function ignore itself so I can call round function inside it which is math.round)
	        n=math.round(n)
	        return n==0 and 1 or n
	    end
	   return table.concat({char(255),char(round(color[1]*255)),char(round(color[2]*255)),char(round(color[3]*255))})
	end
	greyed = ColStr({0.5,0.5,0.5})
	local nuances = redNuances.count
	local reddish = {}
	for i=0, nuances-1 do
		local redStrength = (1 / (nuances-1) * i) 
		local r,g,b = 1, 1-redStrength, 1-redStrength

		reddish[i+1] = ColStr({r,g,b}) 
	end
	function redNuances:apply(str, n)
		local int = n*nuances
		int = 1+(int-int%1)
		return reddish[int] .. str .. '\008'
	end
	function redNuances:get(n)
		if n>1 then
			n = 1
		end
		local int = n*nuances
		int = 1+(int-int%1)
		return reddish[int]
	end
	------- debugging
	-- for i = 1, 10 do
	-- 	local r = math.random()
	-- 	local int = r*nuances
	-- 	int = 1+(int-int%1)

	-- 	Echo(r..' -> '..int..' ===>>> '..redNuances:apply('RED',r).. '...ok')
	-- end
	--------
end
--------********************************************--------
--------********************************************--------
--------*************** INTERACTING ****************--------
--------********************************************--------
--------********************************************--------

local function Warn(intensity,holder,tell,...)
	local t = {...}
	for k,v in pairs(t) do
		t[k] = tostring(v)
	end
	local already
	local msg = redNuances:apply(concat(t),intensity)
	if holder then
		for k,v in pairs(holder) do
			if v == msg then
				already = true
				break
			end
		end
		if not already then
			holder[#holder+1] = msg
		end
	end
	if tell then
		Echo(msg)
	end
	return msg, already
end
local function SwitchHook(self)
	HOOK_ACTIVE = not HOOK_ACTIVE
	if debugOnSwitch then
		debugCycle = 2
	end
	Node.globalTime = 0
	Node.timer = spGetTimer()
	tree:Reset()
	self:SetCaption('Hook is '..(HOOK_ACTIVE and 'On' or 'Off'))
	for _,wrap in pairs(WRAPPER.wraps) do
		wrap.Sleep(HOOK_ACTIVE) -- wraps sleep when hook is active
	end
end
local function ClickNode(self, x,y,button)
	if y<C_HEIGHT then
		local inscope = IN_SCOPE
		local mute_lvl = GLOBAL_MUTE_LEVEL
		-- IN_SCOPE = false
		GLOBAL_MUTE_LEVEL = -1
		local alt, ctrl, meta, shift = spGetModKeyState()
		if button == 3 then
			if ctrl then
				self.node:CutBranch()
			elseif alt then
				self.node:Ban()
			else
				-- self.node:Remove()
				self.node:CutBranch()
			end
		elseif ctrl and alt then
			self.node:Isolate()
		elseif ctrl then
			self.node:MuteBranch()
		else
			self:Toggle()
		end
		GLOBAL_MUTE_LEVEL = mute_lvl
		return true
		-- IN_SCOPE = inscope
	end
	-- self:Select()
	-- local n = self:HitTest(x,y)
	-- if n and n == self then
		-- if not self.parent.root or y<C_HEIGHT then

			-- self:Toggle()
			-- return self
		-- end
	-- end
	-- Echo("n and n.children[1].text is ", n and n.children[1].text)
end



local function MakeTree(name)
	local objWin = WG.WINDOW.Tree:New()
	local panel = objWin:Add() 
	local chilinode = panel.root:Add(name)

	windows[objWin] = chilinode
	return objWin, chilinode, panel
end
-------------------------------



--------********************************************--------
--------********************************************--------
--------**************** NODE CLASS ****************--------
--------********************************************--------
--------********************************************--------

Node.globalTime = 0
Node.timer = spGetTimer()
Node.mt = {__index = Node}
function Node:Reset()
	if self.isTree then
		Node.globalTime = 0
		self.timer = spGetTimer()
		Node.timer = spGetTimer()
		self.updateTime = 0
		self.exe = 0
	else
		self.wasted = 0
		self.wasteful = 0
		self.wastedround = 0
		self.exe = 0
		self.count = 0
		self.updateTime = 0
		self.sleep = false
		self.dynatooltip[1] = ''
		self:FormatName()
		self:FormatTooltip()

		local wrap = self.funcObj.wrap
		if wrap then
			wrap.silentHead = false
			if not HOOK_ACTIVE then
				wrap.Sleep(false)
			end
		end
	end
	if self.children then
		for _,child in pairs(self.children) do
			child:Reset()
		end
	end
end
function Node:SleepBranch(bool)
	if self.children then
		for _,child in pairs(self.children) do
			child.sleep = bool
			child.chilinode:SetText((bool and greyed or '') .. child.chilinode.caption)
			child:SleepBranch(bool)
		end
	end
end
function Node:SleepBranchWraps(bool)
	if self.children then
		for _,child in pairs(self.children) do
			local wrap = child.funcObj.wrap
			if wrap then
				wrap.Sleep(bool)
				wrap.silentHead = false

			end

			child.chilinode:SetText((bool and greyed or '') .. child.chilinode.caption)
			child.dynatooltip[1] = bool and '[muted]' or ''
			child.chilinode.tooltip = table.concat(child.dynatooltip,'\n') ..'\n'..child.statictooltip

			child:SleepBranchWraps(bool)
		end
	end
end
function Node:MuteBranch(bool)
	if HOOK_ACTIVE then
		-- when hook is active, the first ever node to be muted prevent the subs to be active anyway
		if bool == nil then
			bool = not self.sleep
		end
		self.sleep = bool
		self:SleepBranch(bool)
	else
		local wrap = self.funcObj.wrap
		if not wrap then
			return
		end
		if bool == nil then
			bool = not wrap.silent
		end
		if not bool then
			-- dont allow sub wrap getting unmuted if the branch head has not been unmuted
			if wrap.silent and not wrap.silentHead then 
				return
			end
		end
		wrap.Sleep(bool)
		wrap.silentHead = bool
		self:SleepBranchWraps(bool)
	end

	self.chilinode:SetText((bool and greyed or '') .. self.chilinode.caption:gsub(greyed, ''))
	self.dynatooltip[1] = bool and '[muted]' or ''
	self.chilinode.tooltip = table.concat(self.dynatooltip,'\n') ..'\n'..self.statictooltip
end
function Node:Isolate()
	local funcObj = self.funcObj
	if funcObj then
		local wrap = funcObj.wrap
		if wrap then
			if wrap.nwhat == '(upvalue)' then
				Echo('isolate',wrap.nwhat,wrap.name, wrap.callerfunc, wrap.index,wrap.callerfunc and WRAPPER.wraps[wrap.callerfunc] and 'caller is wrap' or '')
				if wrap.callerfunc and (WRAPPER.wraps[wrap.callerfunc] or BRANCH_WRAPS[wrap.callerfunc]) then
					Echo('Cannot run a new tree from a wrap func !', self.name)
					return
				end
			elseif wrap.nwhat == '(field)' or wrap.nwhat == '(global)' then
				Echo('isolate ',wrap.nwhat,wrap.name, wrap.env)
			end
			local newTreename = self.parent and self.parent.name or tree.name
			HookFunction(funcObj.func, wrap.callerfunc, wrap.name, wrap.index, wrap.env, newTreename, (funcObj.info and funcObj.info.source or UNKNOWN) )
		else
			Echo(self.name, "cannot be isolated, it didn't get located")
		end
	end
end


function Node:FormatName()
	local parent = self.parent
	local exe = self.exe
	local name = self.name
	local inloop = self.funcObj.looplevel
	local ephemeral = self.funcObj.ephemeral
	local red = not self.silent and self.red

	if inloop then
		name = name ..' ~'..inloop..'~ '
	end
	if ephemeral then
		name = '* '..name
	end
    local parentTime = parent and parent.exe or self.globalTime
    local newcaption
    if parentTime then
    	local count = self.count
        newcaption = ('%s %.1f = %.0f%% --%s'):format(
            name,
            exe, parentTime>0 and (exe / parentTime * 100) or 0,
            count>999 and ('%.1fK'):format(count/1000) or count
        )
    else
        newcaption = ('%s %.1f --%d'):format(
            name, self.exe, self.count
        )

    end
    if red then
    	newcaption = red..newcaption
    end
    -- if newcaption ~= self.label.caption then
    if newcaption ~= self.chilinode.caption then
        if true or (parent and parent.expanded) then
            -- self.label:SetText(newcaption)
            self.chilinode:SetText(newcaption)
        end
    end
end
function Node:FormatTooltip()
	
	if not self.statictooltip then
		local funcObj = self.funcObj
		local codesource = funcObj.def.codesource
		local code_proc = codesource and codesource.processed
		local looplevel = funcObj.looplevel
		local calledline = funcObj.calledline
		local funcID = funcObj.id
		local defID = funcObj.defID
		local info = funcObj.info
		local caller = funcObj.caller
		local ld, lld = info.linedefined, info.lastlinedefined
		local cld, clld = caller.linedefined, caller.lastlinedefined
		local namewhat = funcObj.comment and funcObj.comment:gsub('[%(%)]','') or info.namewhat
		local ephemeral = funcObj.ephemeral
		local warn = funcObj.warn

		tbl = {}
		-- tbl[#tbl+1] = ephemeral and '(ephemeral)' or nil
		tbl[#tbl+1] = 'lvl: '..self.level..' ('..realLevel..')'
		tbl[#tbl+1] = 'calledline:' .. calledline .. (funcObj.wrap and ' (wrapped)' or '')
		tbl[#tbl+1] = namewhat and namewhat~='' and '['..namewhat..']' or nil
		-- tbl[#tbl+1] = loop and 'in loop '..loop.name..' (looplevel:'..(loop.looplevel+1)..')' or nil
		tbl[#tbl+1] = looplevel and 'loop ~'..looplevel or nil

		tbl[#tbl+1] = warn and concat(warn,'\n') or nil
		tbl[#tbl+1] = '\n------------\n'
		tbl[#tbl+1] = 'defname: '..tostring(funcObj.def.fullname)
		tbl[#tbl+1] = 'source: '..(info.source:match('^LuaUI') and info.source:sub(7) or info.source and info.source:sub(-30,-1))
		tbl[#tbl+1] = ld and lld and 'defined: ['..ld..'-'..lld..']' or nil
		tbl[#tbl+1] = info.what and info.what~='' and 'what: '..info.what or nil
		tbl[#tbl+1] = 'ID:' .. funcID
		tbl[#tbl+1] = 'defID: ' .. defID
		tbl[#tbl+1] = 'PATH: ' .. PATH
		-- tbl[#tbl+1] = 'func: '..info.func
		-- tbl[#tbl+1] = 'nups: '..info.nups
		-- tbl[#tbl+1] = 'short_src: '..info.short_src
		-- tbl[#tbl+1] = 'name: '..tostring(info.name)
		-- tbl[#tbl+1] = 'currentline: '..info.currentline

		tbl[#tbl+1] = '\n--- CALLER ---\n'
		tbl[#tbl+1] = caller.name and caller.name~='' and 'name: '..caller.name or nil
		tbl[#tbl+1] = caller.namewhat and caller.namewhat~='' and '['..caller.namewhat..']' or nil
		tbl[#tbl+1] = 'source: '..(caller.source:match('^LuaUI') and caller.source:sub(7) or caller.source and caller.source:sub(-30,-1))
		tbl[#tbl+1] = cld and clld and 'defined: ['..cld..'-'..clld..']' or nil
		tbl[#tbl+1] = caller.what and caller.what~='' and 'what: '..caller.what or nil

		-- tbl[#tbl+1] = 'func: '..caller.func
		-- tbl[#tbl+1] = 'nups: '..caller.nups
		-- tbl[#tbl+1] = 'short_src: '..caller.short_src
		-- tbl[#tbl+1] = 'currentline: '..caller.currentline


		tbl[#tbl+1] = '\n------------\n'
		tbl[#tbl+1] = code_proc and 'source info processed in:' .. ('%.2f'):format(code_proc) or nil
		self.statictooltip = concat(tbl, '\n')
		self.dynatooltip = {'',''}
	end
    local wasteful = self.wasteful
    if self.exe == 0 then
		self.dynatooltip[2] = ('wasted: %.1f/%.1f = %s%%'):format(self.wasted, self.exe == 0 and self.wasted or self.exe, wasteful)
    else
    	self.dynatooltip[2] = ('wasted: %.1f/%.1f = %.0f%%'):format(self.wasted, self.exe == 0 and self.wasted or self.exe, (wasteful>0 and wasteful or 0) * 100)
    end

    self.chilinode.tooltip = concat(self.dynatooltip,'\n')
	.. '\n' .. self.statictooltip

end
local MuteMode
do	
	local g_mute_level = GLOBAL_MUTE_LEVEL
	function MuteMode(bool) -- prevent catching processing new functions during sensitive operation
		if bool then
			while CURRENT_NODE~=tree do
				CURRENT_NODE:Close()
			end
			IN_SCOPE = false
			g_mute_level = GLOBAL_MUTE_LEVEL
			GLOBAL_MUTE_LEVEL = -1
		else
			GLOBAL_MUTE_LEVEL = g_mute_level
		end
	end
end
function Node:Remove()
	MuteMode(true)
	if self.isBranch then
		return self:CutBranch()
	end
	local node = self
	local id = node.id
	local fobj = node.funcObj
	fobj.banned = true
	if fobj.wrap then
		fobj.wrap:Ban(true)
	end
	local id = node.id
	local chilinodeParent = node.chilinode and node.chilinode.parent
	-- Echo('removing ',node.name, node.id)
	-- remove node and join node children to the parent
	if chilinodeParent then
		-- select parent to avoid crash when removing self or self children nodes
		self.chilinode.treeview:Select(chilinodeParent)
		chilinodeParent:RemoveChild(node.chilinode)
		if node.chilinode.nodes then
			for i,v in ipairs(node.chilinode.nodes) do
				chilinodeParent:Add(v)
			end
		end
	else
		Echo('no chilinode parent',node.parent and node.parent.name)
	end
	local children = node.children
	-- do the same for our node class
	if node.parent then
		if node.parent.children[id] then
			node.parent.children[id] = nil
			if children then
				for cid,n in pairs(children) do
					-- Echo('transfert children of',node.name..':'..n.name.. ' to ' ..node.parent.name,cid)
					node.parent.children[cid] = n
					n.parent = node.parent
					if node.silentHead then
						n.silentHead = true
						if n.funcObj.wrap then
							n.funcObj.wrap.silentHead = true
						end
					end
				end
			end
		end
	end
	MuteMode(false)
end
function Node:CutBranch()
	MuteMode(true)
	local node = self
	local id = node.id
	node.cut = true
	local fobj = node.funcObj
	fobj.banned = true
	if fobj.wrap then
		fobj.wrap:Ban(true)
	end
	local id = node.id
	local chilinodeParent = node.chilinode and node.chilinode.parent
	-- Echo('removing ',node.name, node.id)
	-- remove parent and join grandchildren to the parent
	if chilinodeParent then
		self.chilinode.treeview:Select(chilinodeParent)
		chilinodeParent:RemoveChild(node.chilinode)
	else
		Echo('no chilinode parent',node.parent and node.parent.name)
	end
	-- do the same for our node class
	if node.parent then
		if node.parent.children[id] then
			node.parent.children[id] = nil
			local children = node.children
			if children then
				local function delete(children)
					for cid,n in pairs(children) do
						local fobj = n.funcObj
						fobj.banned = true
						if n.funcObj.wrap then
							n.funcObj.wrap:Ban(true)
						end
						if n.children then
							delete(n.children)
						end
					end

				end
				delete(children)
			end
		end
	end
	MuteMode(false)
end
function Node:Ban() -- remove all nodes having the same function defID
	MuteMode(true)

	local funcObj = self.funcObj
	local wrap = funcObj.wrap
	local def = funcObj.def
	if def then
		def.banned = true
	else
		Echo('no def')
	end
	-- Echo('banning ', funcObj.def.id)
	local done = false
	if def and def.executed then
		for _,fobj in pairs(def.executed) do
			-- FIXME until fixed, the way funcObj is identified is not unique, same funcObj can be on two different nodes (if same level)
			local node = fobj.node
			if node == self then 
				done = true
			end
			fobj.node:Remove()

		end
	end
	if not done then
		self:Remove()
	end
	MuteMode(false)
end
function Node:New(id,name,chilinode)

	if self.chilinode then
		-- Echo('Node '..self.name..' asking to ad	d ',id,name)
		chilinode = self.chilinode:Add(name)
		chilinode.OnMouseDown = chilinode.OnMouseDown or {}
		table.insert(chilinode.OnMouseDown,ClickNode)
	elseif chilinode then
		chilinode.OnMouseDown = chilinode.OnMouseDown or {}
		table.insert(chilinode.OnMouseDown,ClickNode)
	end

	local level = self.level or 0
	local obj = {
		id = id,
		name = name,
		parent = self ~= Node and self or nil,
		isTree = self == Node,
		tree = self == Node and self or self.tree,
		isBranch = self.isTree,
		level = level + 1,
		count = 0,
		wasted = 0,
		wastedround = 0,
		wasteful = 0,
		exe = 0,
		sleep = false,
		updateTime = self.globalTime,
		chilinode = chilinode,
	}
	setmetatable(obj, self.mt )

	chilinode.node = obj
	return obj
end

function Node:FindForward(id) -- op tool but unnecessary to search per sub level and getting intermediaries

	local children = self.children
	if not children then
		return false
	end
	local node = children[id]
	if node then
		return node, false
	else
		local int
		local _node
		local find = function(children, id, t)
			-- Echo('children size',table.size(children))
			for cid, child in pairs(children) do
				-- Echo("k,child is ", k,child,table.size(child.children or {}))
				local sub = child.children
				-- for k,v in pairs(sub) do
				-- 	-- Echo('in sub', k,v)
				-- end
				-- Echo('add children of',k)
				if sub then
					if sub[id] then
						return sub[id], child
					else
						t[sub] = true
					end
				end
			end
		end
		local t = {}
		node, int = find(children, id, t)

		if node then
			return node, {int}
		end
		while next(t) do
			-- local str = ''
			-- -- Echo('children objs',table.size(t))
			-- for c in pairs(t) do
			-- 	for k,v in pairs(c) do
			-- 		Echo(k,v)
			-- 		str = str.. k ..','
			-- 	end
			-- end
			-- str = str:sub(1,-2)
			-- Echo('next batch',str)
			local subt = {}
			for children in pairs(t) do
				_node = find(children, id, subt)
				if _node then 
					local interms = {}
					local parent = node.parent
					while parent and parent ~= node do
						table.insert(interms,1,parent)
						parent = parent.parent
					end
					return _node, interms
				end
			end
			t = subt
		end
	end
	return false
end

function Node:OpenForwardID(id,fromWrap) -- working but unnecessary
	local wasted = spGetTimer()
	local node, interms = CURRENT_NODE:FindForward(id)

	if interms then
		if debugCycle then
			Echo(CURRENT_NODE and (CURRENT_NODE.name or CURRENT_NODE.isTree and 'tree'),'*fast forward to ' .. node.name)
			-- for i,v in ipairs(interms) do
			-- 	Echo('--interm'..tostring(v.name))
			-- end
		end
		for i = 1, #interms do
			local n = interms[i]
			if debugCycle then
				Echo('-- fast open '..tostring(n.name))
			end
			n:Open(fromWrap)
		end
	end
	if node then
		node.wastedround = node.wastedround + spDiffTimers(spGetTimer(),wasted)
		node:Open(fromWrap)
	else
		if debugCycle then
			Echo('!!couldnt warp open ' .. id .. 'from ' .. tostring(node.name or node.isTree and 'tree' ),'opening directly...')
		end
		if self.wastedround then
			self.wastedround = self.wastedround + spDiffTimers(spGetTimer(),wasted)
		end
		self:Open()
	end
end
------- Node.Get annexes
local function GetSourceInfos(source)
	local codesource, isnew = CODES[source]
	if not codesource then
		local time = spGetTimer()
		CODES[source] = WG.Code:GetFullCodeInfos(source) or 'failed'
		codesource = CODES[source]
		if codesource == 'failed' then
			return
		end
		isnew = true
		codesource.processed = spDiffTimers(spGetTimer(),time)
		-- Echo('fetching infos of '.. source, os.clock(),'processed:',codesource.processed)
	end
	if codesource == 'failed' then
		return
	end
	return codesource, isnew
end

local function GetExecInfo(info, stacklevel)
	local callerInfo = getinfo(stacklevel+1)
	if wraps[callerInfo.func] then
		Echo('ever happening')
		callerInfo = getinfo(stacklevel+2)
	end
	local lineInfo = callerInfo
	local line
	local lineSuffix = ''
	if not lineInfo or lineInfo.currentline == -1 then
		lineInfo = info
		lineSuffix = ' (from called func)'
	end
	line = lineInfo.currentline
	if not line or line == -1 then
		line = UNKNOWN
	end
	return line .. lineSuffix, callerInfo
end
local discovered = 0
local function GetFuncObj(s, calledline, stacklevel, defID)
	local name = s.name
	if ignoredNames[name] then
		return false, false, true
	end
	if s.source and bannedSource[s.source] then
		return false, false, true
	end
	-- Echo("s.source is ", s.source)
	local funcDef = false
	local func = s.func
	local wrap = wraps[func]

	if wrap then -- it is already a wrap
		if wrap.funcObj.banned then
			return false, false, true
		end
		funcDef = wrap.funcObj.def
	else
		funcDef = knownFuncs[func]
	end
	if funcDef and funcDef.banned then
		return false, false, true
	end

	local ld, lld, namewhat = s.linedefined, s.lastlinedefined, s.namewhat
	local what = s.what
	local skip_caller
	local located_caller
	local funcDefID 
	local knownDef = false
	local def, ephemeral
	local wrapped = wrappedFunc[func]

	if funcDef then -- the function is known
		funcDefID = funcDef.id
		knownDef = true
		-- Echo('funcDef already known', funcDef.name, funcDef.id)
	else
		funcDefID = (name or UNKNOWN)..'-'..(namewhat or UNKNOWN)..'-'..ld..'-'..lld..'-'..(s.source or UNKNOWN)
		-- Echo("funcDefID is ", funcDefID)
		-- FIXME IMPROVE FAST IDENTIFICATION
		-- so the name of the invocation is used as defID, while the real name can be retrieved via funcAtLine
		-- but the method is supposed to be as fast as we can to identify the function
		-- if the real def name is used as identifier, we need the CODES[source].funcByLine[ld..'-'..lld] (or .fullname)
		-- if, to go fast, we check by funcs and the func is ephemeral, that cannot work
		discovered = discovered + 1
		-- if discovered%750 == 0 then
		-- 	Echo(discovered .. ' discovered funcs','last',funcDefID,'size of known funcs',table.size(knownFuncs),table.size(knownDefs),'funcObjs:',funcObjCount,'failed',failedcount,'failed callers',failedcallercount)
		-- end
		funcDef = knownDefs[funcDefID]
		if funcDef then -- the function is from the same code but is dynamic
			if funcDef.banned then
				return false, false, true
			end
			if debugCycle then
				Echo('not remaking funcDef with funcObjs from ephemeral function',funcDef.id)
			end
			knownDef = true
			ephemeral = true
			funcDefID = funcDef.id
			if not funcDef.ephemeral then
				funcDef.ephemeral = true
				for k,funcObj in pairs(funcDef.executed) do
					funcObj.ephemeral = true
					funcObj.warn = funcObj.warn or {}
					Warn(0.15,funcObj.warn, false, '(ephemeral)')
					funcObj.warnred = (funcObj.warnred or 0) + 0.15
					local node = funcObj.node
					node.red = redNuances:get(funcObj.warnred)
					node.statictooltip = nil
					node:FormatName()
					node:FormatTooltip()
				end
			end
		end
	end
	if not funcDef then
		-- local funcInfo = knownFuncs[]
		local codesource, isnew
		local name = name
		if s.source and s.source:match('%.lua$') then
			local source = s.source
			if source:find('/') then
				local locsource = source:gsub('/','\\')
				local test = io.open(locsource)
				if test then
					source = locsource
					-- Echo('SOURCE WAS WRONGLY SET AS IN SYNCED BUT GOT IT IN LOCAL',source)
					test:close()
				end

			end
			codesource, isnew = GetSourceInfos(source)
		end
		if isnew then
			-- Echo('got code source infos for '..funcDefID,os.clock())
			header.processed_time = header.processed_time + codesource.processed
			header.source_fetch_time = header.source_fetch_time + codesource.processed
			HeaderUpdate()
		end
		local fullname
		if codesource then
			local funcAtLine = codesource.funcByLine[ld..'-'..lld]
			-- if s.source:match('debug') then
			-- 	for k,v in pairs(codesource.funcByLine) do
			-- 		Echo(ld..'-'..lld..' vs '..k,v[1].name)
			-- 	end
			-- 	-- Echo("funcAtLine and table.size(funcAtLine) is ", codesource.funcByLine and table.size(codesource.funcByLine))
			-- end

			if funcAtLine then
				-- Echo("funcAtLine is ", funcAtLine.name)
				local defname = funcAtLine.name
				-- Echo(name, "at line",ld..'-'..lld, "defname is ", defname)
				------------------------
				name = defname -- TODO later manage to find out which one is the good one if several func defined on same line
				fullname = funcAtLine.fullname -- get the full name written in code (method etc...)
			else
				Echo('no funcs at line',ld,lld,' found in',codesource.source)
			end
			-- Echo(ld..'-'..lld, funcSource, funcSource and funcSource.name)
		end
		----------
		-- if (not namewhat or namewhat == '') and func then -- workaround to find out unidentified func by debug.getinfo
		-- 	local _namewhat, _name, _, _, _caller, _callername, _calledline, _stacklevel = WRAPPER.LocateFunc(func,name,stacklevel+1)
		-- 	-- Echo("namewhat, name, calledline is ", namewhat, name, calledline,'=>',_callername,_calledline)
		-- 	if _namewhat and (not namewhat or namewhat == '') then
		-- 		namewhat = _namewhat
		-- 		name = _name
		-- 		located_caller = _caller
		-- 		calledline = _calledline
		-- 		if stacklevel < _stacklevel then
		-- 			skip_caller = true
		-- 		end
		-- 		-- Echo('func located',name,namewhat,'skip caller',skip_caller)

		-- 	end

		-- 	-- namewhat, name, index, env, caller, callername, calledline
		-- end
		----------


		funcDef = {
			id = funcDefID,
			executed = {},
			func = (s.func or DUM_FUNC),
			name = name or UNKNOWN,
			fullname = fullname or name or UNKNOWN,
			defined = ld,
			lastdefined = lld,
			namewhat = namewhat or UNKNOWN,
			codesource = codesource,
			banned = false,
		}
		-- knownFuncs[funcDefID] = funcDef
		knownFuncs[func] = funcDef
		knownDefs[funcDefID] = funcDef

	end
	----------
	-- if (not namewhat or namewhat == '') and func then
	-- 	local _namewhat, _name, _, _, _caller, _callername, _calledline, _stacklevel = WRAPPER.LocateFunc(func,name,stacklevel+1)
	-- 	-- Echo("namewhat, name, calledline is ", namewhat, name, calledline,'=>',_callername,_calledline)
	-- 	if _namewhat and (not namewhat or namewhat == '') then
	-- 		namewhat = _namewhat
	-- 		name = _name
	-- 		located_caller = _caller
	-- 		calledline = _calledline
	-- 		if stacklevel < _stacklevel then
	-- 			skip_caller = true
	-- 		end
	-- 		-- Echo('func located',name,namewhat,'skip caller',skip_caller)
	-- 	end

	-- 	-- namewhat, name, index, env, caller, callername, calledline
	-- end
	----------

	local funcObj = funcDef.executed[calledline]

	if funcObj then
		if not knownDef then
			Echo('WARN', 'a funcObj is using a different funcDef and making a duplicate !!',name,'id',funcObj.id,'func def',funcDefID)
		end
		if funcObj.banned then
			return false, false, true
		end
	end
	local isnew
	if not funcObj then
		isnew = true
		local info = wrap and wrap.funcObj.info or getinfo(stacklevel)
		local line, caller = GetExecInfo(info,stacklevel+1 + (skip_caller and 1 or 0))
		-- if name == 'IndexWrappedLink' then
			-- Echo(name,'=>',"skip", skip_caller, line, wrap, wrap and wrap.funcObj.info and wrap.funcObj.info.currentline)
		-- end
		local codesource =  funcDef.codesource
		local looplevel
		if codesource then
			local loops = codesource.loops
			if loops then
				local shortestrange
				for loopID, level in pairs(loops) do
					bef, aft = loopID:match('(%d+)%-(%d+)')
					bef, aft =  tonumber(bef), tonumber(aft)

					local range = aft - bef
					-- we don't have where in the line it is executed so we can't know which loop it is in, if there are several loops on the same line
					if calledline >= bef and calledline <= aft
						and (not shortestrange or range < shortestrange)
					then
						shortestrange = range
						looplevel = level
					end
				end
			end
			-- for defID,t in pairs(codesource.funcByLine) do

			-- end
		end
		local showName = name or funcDef.name or UNKNOWN
		if name and funcDef.name ~= name then
			showName = name..'('..funcDef.name..')'
		end
		funcObj = {
			id = funcDefID .. '-'..level..'-'..calledline,
			executed = 0,
			executed_time = 0,
			time = 0,
			name = '['..calledline..']:'..showName,
			namewhat = namewhat or UNKNOWN,
			def = funcDef,
			defID = funcDefID,
			line = line,
			info = info,
			func = func,
			caller = caller,
			path = PATH,
			looplevel = looplevel,
			calledline = calledline,
			ephemeral = ephemeral,
			banned = false,
		}
		local warn, warnred = {}, 0
		if ephemeral then
			Warn(0.1,warn, false, '(ephemeral)')
			warnred = warnred + 0.1
			if debugCycle then
				Echo('!!', name, namewhat,' is ephemeral', calledline)
			end
		elseif wrapped then
			wrapped.lines[calledline] = funcObj
			funcObj.wrap = wrapped
		elseif wrap then
			local wraplines = wrap.lines
			if not wraplines[calledline] then
				wraplines[calledline] = funcObj
				funcObj.wrap = wraps[func]
				if debugCycle then
					Echo('func', what, namewhat, func, name, 'already wrapped, adding new line', calledline)
				end
			else
				Warn(0.1, warn, debugCycle, '!! func', what, namewhat,func,name, 'already wrapped, had already line ', calledline)
				warnred = warnred + 0.1
			end
		elseif wraps[caller.func] then
			Warn(0.3, warn, debugCycle, 'funcObj', name, 'shouldnt be made!, not wrapping!')
			warnred = warned + 0.3
		elseif BRANCH_WRAPS[func] then
			funcObj.wrap = BRANCH_WRAPS[func]
			if debugCycle then
				Echo('not wrapping, func', name, 'is the main branch wrap')
			end
		else
			if debugCycle then
				Echo('Asking to wrap', what, namewhat,func,name,'for line',calledline)
			end

			local wrap, comment = WRAPPER.Wrap(what, namewhat, func, name, located_caller or caller, stacklevel+1)
			if wrap then
				wrap.funcID = funcObj.id
				wrap.funcDefID = funcDefID
				wrap.lines[calledline] = funcObj
				wrap.funcObj = funcObj
				funcObj.wrap = wrap
				funcObj.comment = comment
				if debugCycle then
					Echo('success')
				end
			else
				if debugCycle then
					Echo('FAILED')
				end
				-- Echo("funcObj.id is ", funcObj.id)
				Warn(0.15, warn, false,'!! wrap failed')
				warnred = warnred + 0.15
			end
		end
		if warnred>0 then
			funcObj.warn = warn
			funcObj.warnred = warnred
		end

		funcDef.executed[calledline] = funcObj
		funcObjCount = funcObjCount + 1
		if funcObjCount%25 == 0 then
			-- Echo('funcObjs created ',funcObjCount,'last ',funcObj.id)
		end

	end
	return funcObj, isnew
end
------------------------

function Node:Get(s, calledline,stacklevel) -- create or get funcObj/node during tracing 
	if CURRENT_NODE.sleep then
		return
	end
	local wasted = spGetTimer()
	local funcObj, isnew

	local caller = getinfo(stacklevel + 1,'fln')
	local callerfunc = caller.func
	local funcDefID
	local wrap = wraps[s.func]

	if wrap then
		funcDefID = wrap.funcDefID
		funcObj = wrap.funcObj
		if funcObj then
			if funcObj.calledline ~= calledline then
				funcObj = false
			elseif funcObj.banned then
				MUTE_LEVEL = level
				return
			end
		end
	elseif callerfunc then
		if wraps[callerfunc] then -- the func is wrapped, we ignore it
			if debugCycle then
				Echo('-- line '..tostring(calledline), tostring(s.name)..' ('..tostring(s.namewhat)..')' .. ' has been ignored. (wrapped func)  event#' .. count )
			end
			self.wastedround = self.wastedround + spDiffTimers(spGetTimer(), wasted)
			return
		end
	end
	-- Echo("calledline is ", calledline,caller and caller.name)
	local isBanned
	if not funcObj then
		funcObj, isnew, isBanned = GetFuncObj(s, calledline,stacklevel+1, funcDefID)

		if isBanned then
			MUTE_LEVEL = level
			return
		end
	end
	if not funcObj then
		if debugCycle then
			Echo('-- line '..tostring(calledline), tostring(s.name)..' ('..tostring(s.namewhat)..')' .. ' has been ignored. (no funcObj made)  event#' .. count )
		end
		if self.wastedround then
			self.wastedround = self.wastedround + spDiffTimers(spGetTimer(), wasted)
		end
		return
	end

	local id = funcObj.id

	local children = self.children
	if not children then
		children = {}
		self.children = children
	end
	local node = children[id]
	if not node then
		local name
		if self.isTree then -- get the real name of the callin that has been wrapped
			for i=3,8 do
				local inf = getinfo(i,'f')
				if inf.func then
					name = self.branchFuncs[inf.func]
					if name then
						break
					end
				end
			end
		end
		node = self:New(id,name or funcObj.name)
		local msg, color
		if not isnew then
			funcObj.warn = funcObj.warn or {}
			local msg, already = Warn(0.2,funcObj.warn, debugCycle,
				'!! duplicate invocation, another node got that funcObj id ...?') -- FIXME find a way to uniquely identifies any invocation but fast
			if not already then
				funcObj.warnred = (funcObj.warnred or 0) + 0.2
			end

		elseif debugCycle then
			Echo('*creating new node ',node.name,id,  'event#' .. count  )

		end

		node.funcObj = funcObj
		funcObj.node = node
		if funcObj.warnred then
			node.red = redNuances:get(math.min(1,funcObj.warnred))
		end
		node:FormatName()
		node:FormatTooltip()
		children[id] = node
		node.wastedround = spDiffTimers(spGetTimer(), wasted)

		return node, true
	elseif node.sleep or node.cut then
		MUTE_LEVEL = level
		return
	end


	node.wastedround = spDiffTimers(spGetTimer(), wasted)
	return node, false
end

function Node:Open(fromWrap, fake)
	if fromWrap then
		if self.level <= CURRENT_NODE.level then
			if debugCycle then
				Echo('opening '..self.name.. ', closing artifically unwrapped node(s) from ' .. CURRENT_NODE.name)
			end
			while self.level <= CURRENT_NODE.level do
				CURRENT_NODE:Close(fromWrap, debugCycle and 'closing until ' .. (tostring(self.parent and self.parent.name)) or '')
			end
		elseif self.parent and self.parent ~= CURRENT_NODE then
			self.parent:Open(fromWrap, true)
		end
	end
	-- Echo(count,"calledline, _node is ", calledline, _node)

	if debugCycle then
		Echo((self.level)..('  '):rep(self.level)
			.. tostring(self.parent and self.parent.name) .. ' -> ' .. tostring(self.name) .. (fake and ' (faked, no wrap)' or '')
		)
	end


	local now = spGetTimer()

	self.timer = now
	CURRENT_NODE = self
	return node
end
function Node:Close(fromWrap, fake)
	local parent = self.parent
	if fromWrap then
		if self ~= CURRENT_NODE then
			if CURRENT_NODE.level > self.level then
				while CURRENT_NODE.level > self.level do
					CURRENT_NODE:Close(fromWrap, 'closing '..self.name)
				end
			end
		end
	end

	if debugCycle then
		Echo(
			self.level..('  '):rep(self.level) .. tostring(self.parent and self.parent.name) .. ' <- ' .. tostring(CURRENT_NODE.name) .. (fake and ' (faked '..tostring(fake)..')' or '')
		)
	end
	if parent then
		local returnTimer = spGetTimer()
		local exe = self.exe + spDiffTimers(returnTimer, self.timer)
		local count = self.count + 1
		self.exe = exe 
		self.count = count

		-- update waste

		-- updating visuals
		-- wastedround is the accumalated waste from this node and its children in that current round
		local wastedround =  self.wastedround
		local wasted = wastedround + self.wasted
		local wasteful = wasted / exe
		self.wasted = wasted
		self.wasteful = wasteful

		if count==1 or self.tree.globalTime >= self.updateTime + UPDATE_RATE then 

			self.updateTime = self.tree.globalTime
			self:FormatName()
			self:FormatTooltip()
		end

		if wasteful > 1.5 and count>500 and exe > 0.025 and AUTO_MUTE and wasted > 0.05 then
			self:MuteBranch(true)
		end

		parent.wastedround = parent.wastedround + wastedround
		self.wastedround = spDiffTimers(spGetTimer(), returnTimer)

		CURRENT_NODE = parent
		return parent
	else
		CURRENT_NODE = self
		return self
	end
end
function Node:Browse(level) -- unused/for debugging
	level = level or 0
	if self.children then
		for name, child in pairs(self.children) do 
			Echo(self.level, name)
			if child.children then
				child:Browse(level+1)
			end
		end
	end
end

------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
-- for k,v in pairs(gl) do
-- 	if k:lower():find('get') then
-- 		Echo(k,v)
-- 	end
-- end 


--------********************************************--------
--------********************************************--------
--------*************** INITIALIZE *****************--------
--------********************************************--------
--------********************************************--------
local hook_desc = "Hook allow to discover new function running, when Off, the wrapped functions will get in charge for better performance, WARN: some function may fail to get wrapped (indicated on red) and the downstream tracking will then be cut down"
function Reinitialization(wname)
	if tree then
		CloseWindows()
	end
	if not tree then
		--- INITIALIZE
		local _objWin, chilinode, panel = MakeTree('hook tree')
		if _objWin and _objWin.win and not _objWin.win.disposed then
			--------- MAKE FIRST TREE OF PANEL
			objWin = _objWin


			--
			local caption = wname
			header = {
				caption = caption,
			 	control = objWin.header, 
			 	source_fetch_time = 0,
			 	processed_time = 0,
			 	updateTime = 0,
			 }
			tree = Node:New('tree',wname,chilinode)

			tree.objWin = objWin
			tree.branchFuncs = {}
			tree.updateTime = 0
			tree.timer = spGetTimer()
			--
			Node.timer = tree.timer
			Node.globalTime = 0
			--
			-- panel.OnMouseDown = {ClickNode}
			--------------------
			objWin.win:SetPos(nil,nil,500)
			objWin.win.OnDispose = objWin.win.OnDispose or {}
			table.insert(objWin.win.OnDispose, 1, DestroyWhole)

			objWin.searchButton.OnClick = {SwitchHook}
			objWin.searchButton:SetCaption('Hook On')
			objWin.searchButton.tooltip = hook_desc
			objWin.searchButton:Invalidate()
			objWin.closeButton.OnClick = objWin.closeButton.OnClick or {}
			table.insert(objWin.closeButton.OnClick, 1, WRAPPER.SleepAll)

			objWin.extraButton.OnClick = {function() tree:Reset() end}
			objWin.extraButton:SetCaption('Reset')
			local roff = 10 -- offset from right of win

			objWin.mute_level = WG.Chili.TextBox:New{
				parent = objWin.win,
				text = 'lvl ' .. GLOBAL_MUTE_LEVEL,
		        right = 8 + roff,
		        y=3,
		        width=40,
		        height=15,

			}
			objWin.minusButton = WG.Chili.Button:New{
				parent = objWin.win,
		        caption = '-',
		        OnClick = {
		        	function(self) GLOBAL_MUTE_LEVEL = math.max(GLOBAL_MUTE_LEVEL-1, 1)
		        		objWin.mute_level:SetText('lvl ' .. GLOBAL_MUTE_LEVEL)
		        	end
		        },
		        tooltip = 'change maximum sub-level, anything beyond will not be treated',
		        right = 55+roff,
		        top=4,
		        width=15,
		        height=15,
			}
			objWin.plusButton = WG.Chili.Button:New{
				parent = objWin.win,
		        caption = '+',
		        OnClick = { 
		        	function(self) GLOBAL_MUTE_LEVEL = math.min(GLOBAL_MUTE_LEVEL+1, 30)
		        		objWin.mute_level:SetText('lvl ' .. GLOBAL_MUTE_LEVEL)
		        	end
		        },
		        tooltip = 'change maximum sub-level, anything beyond will not be treated',
		        right = roff,
		        top=4,
		        width=15,
		        height=15,
			}
			objWin.win.caption = 'HookFuncs2 '..wname
			CURRENT_NODE = tree
		end
	end
end
function HookFunction(target, caller, targetName, index, env, treename, source)
	Reinitialization(treename)
	if not tree then
		Echo('NO TREE??')
		return
	end
	if target and (caller and index) or (targetName and env and env[targetName]) then
		WrapBranchHead(target, caller, index, env, tree, targetName, source)
		HOOK_ACTIVE = true
		-- debugCycle = 2
	else
		Echo("given arguments weren't enough to start hooking",targetName)
	end
end
function HookWidget(wname)
	Reinitialization(wname)
	if not tree then
		Echo('NO TREE??')
		return
	end
	-------------- Make Branches (different callins of same widget for example)
	for callinName in pairs(UTILS:GetCallInNames(wname)) do
		local target, caller, targetName, callerName, upVPos, w, isGlobal, source = UTILS:GetArgs(callinName,nil,wname)
		-- Echo('found', target, caller, targetName, callerName, upVPos, w, isGlobal)
		-- local target, caller, targetName, callerName, upVPos, w, isGlobal = UTILS:GetArgs('DrawWorld',nil,'HookFuncs2')
		if target and caller and upVPos then
			WrapBranchHead(target, caller, upVPos, nil, tree, targetName, source)
			HOOK_ACTIVE = true
			-- debugCycle = 2
		end
	end

	-- local target, caller, targetName, callerName, upVPos, w, isGlobal = UTILS:GetArgs('GameFrame')
	-- if target and caller and upVPos then
	-- 	WrapBranchHead(target, caller, upVPos, tree, nil, targetName, source)
	-- end
	----------------------------------------
	------ pattern to make a second tree inside the same panel
	-- local chilinode2 = panel.root:Add('tree2')
	-- tree2 = Node:New('tree2')
	-- tree2.objWin = objWin
	-- tree2.chilinode = chilinode2
	-- chilinode2.OnMouseDown = chilinode2.OnMouseDown or {}
	-- table.insert(chilinode2.OnMouseDown, ClickNode)
	--------
	return true
end 

------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------

function widget:Shutdown()
	for _, wrap in pairs(WRAPPER.wraps) do
		wrap:Unwrap()
	end
	for k in pairs(knownDefs) do
		knownDefs[k] = nil
	end
	for k in pairs(knownFuncs) do
		knownFuncs[k] = nil
	end
	funcObjCount = 0
	CloseWindows()

end
if debugMe then
	function widget:DrawScreen()
		if PERIODICAL_CHECK then
			if PERIODICAL_CHECK > 0 then
				Echo('there are ' .. PERIODICAL_CHECK.. ' active wraps')
			elseif tries == 0 then
				tries = tries + 1
			else
				tries = 0
				PERIODICAL_CHECK = false
			end
		end
		p_check = p_check + 1
		if p_check == 60000 then
			p_check = 0
			PERIODICAL_CHECK = 0
		end
	end
end
-------********** FIND TARGET *********
local sig = '['..widget:GetInfo().name..']: '
function UTILS:SearchCallIn(funcs,source,maxLevel,level, debugMe)
    level = level or 1
    local nextFuncs,n = {},0
    -- stop at the first encountered function that is in the targetted widget
    for f,func in ipairs(funcs) do
        local name,i,item = true,1
        while name do
            name, item = debug.getupvalue(func,i)
            -- 
            if type(item) == 'function' then
                local s = debug.getinfo(item,'S')
                if debugMe then
                    Echo(level,name,item,'target source:',source,'source:', s and s.source,'matching?',s.source == source,s.source,s.linedefined, s.lastlinedefined)
                end
                if s.source == source and s.linedefined~=-1 then
                    if debugMe then
                        Echo('>>> returning first upvalue matching the source: ' .. name)
                    end
                    return item, func, i, name
                end
                n = n + 1
                nextFuncs[n] = item
            end
            i = i + 1
        end
    end
    if level == maxLevel then
        return
    end
    return UTILS:SearchCallIn(nextFuncs,source,maxLevel,level+1,debugMe)
end

do -- UTILS:GetCallInNames
	VFS.Include("LuaUI/callins.lua", nil, VFS.Game)
	local CallInsMap = CallInsMap
	CallInsMap['Update'] = true
	widget.CallInsMap = nil
	function UTILS:GetCallInNames(wname)
		local t = {}
		local w = widgetHandler:FindWidget(wname)
		if w then
			for k,v in pairs(w) do
				if type(v) == 'function' and CallInsMap[k] then
					t[k] = true
				end
			end
		end
		return t
	end
end

-- loc = widget name
-- caller = widget[caller] or function (calling the targetted function)
-- target = widget [target] or function (the target to hook) 
function UTILS:GetArgs(target, caller, loc, debugMe) -- used to get callin or global widget func or func upvalue of another func identifiable (being widget global or given func)
    local targetName, callerName, w, upVPos, isGlobal 
    if type(loc) == 'string' then
    	local wname = loc
        loc = widgetHandler:FindWidget(loc)
        if not loc then
        	Echo('the widget ',loc,"couldnt be retrieved")
        	return
        end
    end
    w = loc or widget
    local source = w.whInfo.filename
    if caller then
        if type(caller) == 'string' then
            callerName = caller
            caller = w[callerName]
        elseif type(caller) == 'function' then
            callerName = debug.getinfo(caller,'n').name
        end
        if type(caller) ~= 'function' then
        	Echo('wrong caller type',caller)
        	return
        end
        local s = debug.getinfo(caller,'S').short_src
        if s ~= source then
            Echo(sig .. 'looking for ' .. callerName .. ' in ' .. w.whInfo.name .. '...')
            caller = UTILS:SearchCallIn({caller}, source, 5, false, debugMe)
        end
    end
    -- Echo("target, caller, loc, debugMe is ", target, caller, loc, debugMe)
    if type(target) == 'string' then
        targetName = target
        target = w[targetName]
        -- Echo("w,targetName,w[targetName], target is ", w,targetName,w[targetName], target)
    elseif type(target) == 'function' then
        targetName = debug.getinfo(target,'n').name
    end
    if type(target)~='function' then
    	Echo('wrong target type',target)
    	return
    end
    local s = debug.getinfo(target,'S').source
    if s ~= source then
        target, caller, upVPos, callerName = UTILS:SearchCallIn({target}, source, 5, false, debugMe)
    end

    if not upVPos then
        if not w[targetName] then
            Echo(sig .. 'no upVPos for ' .. targetName)
            return false
        else
            isGlobal = true
        end
    end
    return target, caller, targetName, callerName, upVPos, w, isGlobal, source
end
--------***********************
-- limited old method of detecting loop (method 2)
do
	local gencount = 0
	local gens = {}
	local lastgen = 0
	local function OldGenDetection(name,node, parent)
		-------- TREATING FOR GENERATOR (can only treat for gen made by a function, can't see others)
		-- since for gen are called and return immediately ...
		-- every call after the first one, any caught func will be tagged as being in gen
		if new then 
			if name:match('for generator') then 
				-- Echo('FOR')
				node.count = 0 
				node.for_gen = true
				node.ins = {}
			end
		elseif node.current_gen then
				 -- we gone out of potential current_gen by going down a level, forgetting the funcs
			local ins = node.current_gen.ins
			for n in pairs(ins) do
				ins[n] = nil
			end
			node.current_gen.count = node.current_gen.count -1
			node.current_gen = false

		end
		local current_gen = parent.current_gen
		if node.for_gen then
			-- the nested loop was not continuing and now we're back to the parent loop
			if current_gen and current_gen.in_gen == node then
				parent.current_gen = node
				current_gen = node
			elseif current_gen and node.ins[current_gen] then
				current_gen.count = current_gen.count - 1 -- dont count the last count of for generator stopping the iteration
				local ins = current_gen.ins
				for n in pairs(ins) do
					ins[n] = nil
				end
				parent.current_gen = node
				current_gen = node


			end
			if current_gen == node then
				-- here we detected a second call and confirmed that we were in that for gen
				local ins = node.ins
				for n in pairs(ins) do
					n.in_gen = node
					n.chilinode.tooltip = 'IN GEN : ' .. node.name .. '\n' .. n.chilinode.tooltip
					n.caption = '[G]~' .. n.caption
					-- Echo('confirm ',n.name,'as in ',node.name)
					n.chilinode:SetText(n.caption)
					ins[n] = nil
				end
			else
				if current_gen then
					if not node.in_gen then
						-- a new for gen appear while we were listening to another
						-- note it as potentially belonging to the current_gen
						if not node.ins[current_gen] then
							-- Echo('note ' .. node.name, ' potentially in loop ' .. current_gen.name)
							current_gen.ins[node] = true
							node.nest = current_gen
							-- Echo('set ',node.name,'nested in ',current_gen.name)
						end
					end
				end
				-- here we start listening and register future funcs getting called
				parent.current_gen = node
				current_gen = node
			end
		elseif not node.in_gen then
			if current_gen then
				-- note that func as potentially belonging to the current_gen
				-- Echo('note ' .. node.name, 'potentially in loop ' .. current_gen.name)
				current_gen.ins[node] = true
				if current_gen.nest then
					local nest = current_gen.nest
					while nest do
					-- note as potentially belonging to its parent for loop and not him
						if not nest.ins then
							-- Echo('NO NEST INS !')
						else
							nest.ins[node] = true
						end
						if nest.nest then
							if nest.nest == nest then
								-- Echo('INFINITE LOOP !')
								break
							elseif nest.nest.nest == nest then
								-- Echo("TRIPLE ",nest.nest, nest.nest.nest)
								break
							end
						end
						nest = nest.nest
					end
				end
			end
		end
	end
end
local function CheckObj(obj)
	
	local count = 0
	local done ={}
	local function check(obj, level)
		level = level or 1
		count = count + 1
		local children = obj.children
		for k, v in pairs(children) do
			if type(k) == 'number' then
				if children[v] ~= k then
					Echo('level', level, 'WRONG index', k, children[v])
				end
				if not done[v] then
					check(v, level + 1)
				end
			else
				if v ~= children[k] then
					Echo('level', level, 'WRONG index', v, children[k])
					if children[k] and not done[ children[k] ] then
						check(children[k], level + 1)
					end
				end
			end
		end
		done[obj] = true
	end
	check(obj)
	return count
end
function widget:Update()
	local wsize = table.size(windows)
	local count = 0
	for obj in pairs(windows) do
		-- local win = obj.win
		local win = obj.win
		-- local panels = obj.panels

		if type(win) == 'userdata' then
			while type(win) == 'userdata' do
				win = win()
			end
		end
		if win then
			Echo('count check', CheckObj(win))
		end
	end
end
---------------------------------------
f.DebugWidget(widget)