--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "Chili Pro Console",
    desc      = "v0.016 Chili Chat Pro Console.",
    author    = "CarRepairer",
    date      = "2014-04-20",
    license   = "GNU GPL, v2 or later",
    layer     = 50,
    experimental = false,
    enabled   = true,
  }
end
-- Before
	-- Many things...
	-- implement battle room chat messages
-- April 2025
	-- improve performance and memory
local Echo = Spring.Echo
include("keysym.lua")
include("Widgets/COFCTools/ExportUtilities.lua")

local missionMode = Spring.GetModOptions().singleplayercampaignbattleid
local f = WG.utilFuncs
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- message rules - widget stuff
--[[
each message definition can have:
	- either 1 format
	- either name + output, output containing pairs of { name = '', format = '' }
all the names are used when displaying the options

format syntax:
- #x : switch to color 'x' where 'x' can be:
	- a : ally (option)
	- e : everyone (option)
	- o : other (option)
	- s : spec (option)
	- h : highlight (option)
	- p : color of the player who sent message (dynamic)
- $var : gets replaced by msg['var'] ; interesting vars:
	- playername
	- argument	for messages, this is only the message part; for labels, this is the caption
	- msgtype	type of message as identified by parseMessage()
	- priority	as received by widget:AddConsoleLine()
	- text		full message, as received by widget:AddConsoleLine()

--]]
local MESSAGE_RULES = {
	player_to_allies = {
		name = "Player to allies message",
		output = {
			{
				name = "Only bracket in player's color, message in 'ally' color",
				format = '#p<#e$playername#p> #a$argument'
			},
			{
				name = "Playername in his color, message in 'ally' color",
				format = '#p<$playername> #a$argument',
				default = true
			},
			{
				name = "Playername and message in player's color",
				format = '#p<$playername> $argument'
			},
		}
	},
	player_to_self = {format = '#p$argument' },
	player_to_player_received = { format = '#p*$playername* $argument' },
	player_to_player_sent = { format = '#p -> *$playername* $argument' }, -- NOTE: #p will be color of destination player!
	player_to_specs = { format = '#p<$playername> #s$argument' },
	player_to_everyone = { format = '#p<$playername> #e$argument' },

	spec_to_specs = { format = '#s[$playername] $argument' },
	spec_to_allies = { format = '#s[$playername] $argument' }, -- TODO is there a reason to differentiate spec_to_specs and spec_to_allies??
	spec_to_everyone = { format = '#s[$playername] #e$argument' },

	-- shameful copy-paste -- TODO remove this duplication
	replay_spec_to_specs = { format = '#s[$playername (replay)] $argument' },
	replay_spec_to_allies = { format = '#s[$playername (replay)] $argument' }, -- TODO is there a reason to differentiate spec_to_specs and spec_to_allies??
	replay_spec_to_everyone = { format = '#s[$playername (replay)] #e$argument' },

	label = {
		name = "Labels",
		output = {
			{
				name = "Show label text in white",
				format = '#p$playername#e added label: $argument',
				default = true
			},
			{
				name = "Show label text in 'ally' color",
				format = '#p$playername#e added label: #a$argument',
			},
			{
				name = "Show label text in the player's color",
				format = '#p$playername#e added label: #p$argument'
			},
		}
	},
	point = { format = '#p$playername#e added point.' },
	autohost = { format = '#o> $argument', noplayername = true },
	other = { format = '#o$text' }, -- no pattern... will match anything else
	game_message = { format = '#o$text' }, -- no pattern...
	game_priority_message = { format = '#e$text' }, -- no pattern...
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local SOUNDS = {
	ally = "sounds/talk.wav",
	label = "sounds/talk.wav",
	lobby = "sounds/beep4_decrackled.wav",
	highlight = "LuaUI/Sounds/communism/cash-register-01.wav" -- TODO find a better sound :)
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local HIGHLIGHT_SURROUND_SEQUENCE_1 = ' >>> '
local HIGHLIGHT_SURROUND_SEQUENCE_2 = ' <<<'
local DEDUPE_SUFFIX = 'x '

local MIN_HEIGHT = 50
local MAX_HEIGHT = 2160
local MIN_WIDTH = 300
local MAX_LINES = 60
local MAX_STORED_MESSAGES = 300

local inputsize = 25
local CONCURRENT_SOUND_GAP = 0.1 -- seconds

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local fontColor = {0.5,0.8,0.8,1}
local tZeroes = {0,0,0,0}
local tOnes = {1,1,1,1}
local tTwos = {2,2,2,2}
local tThreeOnes = {3,3,1,1}
local Image, Panel, TextBox, Button

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

WG.enteringText = false
WG.chat = WG.chat or {}

local screen0
local myName -- my console name
local myAllyTeamId
local firstUpdate = true
local bufferMessages = true -- buffer until the first update round

local control_id = 0
local stack_console, stack_chat, stack_backchat
local window_console, window_chat
local fadeTracker = {}
local scrollpanel_chat, scrollpanel_console, scrollpanel_backchat
local inputspace
local backlogButton
local backlogButtonImage
local color2incolor
local widgetbuffer = {}
local wbuffered = 0


local incolor_dup
local incolor_highlight
local incolors = {} -- incolors indexed by playername + special #a/#e/#o/#s/#h colors based on config
local done = false
local consoleMessages = {}

local chatMessages = {} -- message buffer
local highlightPattern -- currently based on player name -- TODO add configurable list of highlight patterns

local firstEnter = true --used to activate ally-chat at game start. To run once
local recentSoundTime = false -- Limit the rate at which sounds are played.
local requestRemake = false
local requestUpdate = false
local lastMsgChat, lastMsgBackChat, lastMsgConsole

------------------------------------------------------------
-- options

options_path = "Settings/HUD Panels/Chat"

local dedupe_path = options_path .. '/De-Duplication'
local hilite_path = options_path .. '/Highlighting'
local filter_path = options_path .. '/Filtering'
local color_path = options_path .. '/Color Setup'

options_order = {
	
	'lblGeneral',
	
	'enableConsole',
	
	--'mousewheel',
	'defaultAllyChat',
	'defaultBacklogEnabled',
	'mousewheelBacklog',
	'enableSwap',
	'backlogHideNotChat',
	'backlogShowWithChatEntry',
	'backlogArrowOnRight',
	'changeFont',
	'enableChatBackground',
	'hideChat',
	'toggleBacklog',
	'text_height_chat',
	'text_height_console',
	'backchatOpacity',
	'autohide_text_time',
	'max_lines',
	'clickable_points',
	
	'lblMisc',
	
	'color_chat_background','color_console_background',
	'color_chat', 'color_ally', 'color_other', 'color_spec',
	'color_usernames',
	
	'hideSpec', 'hideAlly', 'hidePoint', 'hideLabel', 'hideLog',
	'error_opengl_source',
    'filter_luaHandleCheckStack',
	--'pointButtonOpacity',
	
	'highlight_all_private', 'highlight_filter_allies', 'highlight_filter_enemies', 'highlight_filter_specs', 'highlight_filter_other',
	'highlight_surround', 'highlight_sound', 'send_lobby_updates', 'sound_for_lobby', 'color_highlight', 'color_from_lobby',
	
	--'highlighted_text_height',
	
	'dedupe_messages', 'dedupe_points','color_dup',
}

local function onOptionsChanged()
	requestRemake = true
	-- RemakeConsole()
end

local showingBackchat = false
local showingNothing = false
local wantHidden = false

local hideSpec = false
local hideAlly = false
local hidePoint = false
local hideLabel = false
local hideLog = false

local highlight_all_private = true
dontHighlightThatSource = {
	ally = false,
	enemy = false,
	spec = false,
	other = true,
}
local text_height_chat = 14
local text_height_console = 14

local function SwapBacklog()
	if showingBackchat then
		if not showingNothing then
			window_chat:RemoveChild(scrollpanel_backchat)
		end
		if wantHidden then
			showingBackchat = false
			showingNothing = true
			return
		else
			window_chat:AddChild(scrollpanel_chat)
			backlogButtonImage.file = 'LuaUI/Images/arrowhead.png'
			backlogButtonImage:Invalidate()
		end
	else
		if not showingNothing then
			window_chat:RemoveChild(scrollpanel_chat)
		end
		window_chat:AddChild(scrollpanel_backchat)
		backlogButtonImage.file = 'LuaUI/Images/arrowhead_flipped.png'
		backlogButtonImage:Invalidate()
	end
	showingBackchat = not showingBackchat
	showingNothing = false
end

local function SetHidden(hidden)
	if hidden == wantHidden then
		return
	end
	wantHidden = hidden
	
	if wantHidden then
		if showingBackchat then
			window_chat:RemoveChild(scrollpanel_backchat)
		else
			window_chat:RemoveChild(scrollpanel_chat)
		end
		showingNothing = true
	else
		showingBackchat = true
		SwapBacklog()
	end
end

local function UpdateStackFontSize(stack, fontSize)
	for i, child in ipairs(stack.children) do
		if child.classname == 'textbox' then
			child.font.size = fontSize
			child.font:_LoadFont()
		else
			UpdateStackFontSize(child, fontSize)
		end
	end
end

options = {
	
	--lblFilter = {name='Filtering', type='label', advanced = false},
	--lblPointButtons = {name='Point Buttons', type='label', advanced = true},
	lblAutohide = {name='Auto Hiding', type='label'},
	--lblHilite = {name='Highlighting', type='label'},
	--lblDedupe = {name='De-Duplication', type='label'},
	lblGeneral = {name='General Settings', type='label'},
	lblMisc = {name='Misc. Settings', type='label'},
	
	error_opengl_source = {
		name = "Filter out \'Error: OpenGL: source\' error",
		type = 'bool',
		value = true,
		desc = "This filter out \'Error: OpenGL: source\' error message from ingame chat, which happen specifically in Spring 91 with Intel Mesa driver."
		.."\nTips: the spam will be written in infolog.txt, if the file get unmanageably large try set it to Read-Only to prevent write.",
		path = filter_path ,
		advanced = true,
	},
	filter_luaHandleCheckStack = {
		name = "Filter out \'LuaHandle::CheckStack\' error",
		type = 'bool',
		value = true,
		desc = "This filters out a message that appears usesless, and started being spammed in 105.1.1-2511.",
		path = filter_path ,
		advanced = true,
	},
	enableConsole = {
		name = "Enable the debug console",
		type = 'bool',
		value = false,
		advanced = true,
		OnChange = function(self)
			if window_console then
				if self.value then
					screen0:AddChild(window_console)
				else
					screen0:RemoveChild(window_console)
				end
			end
		end
	},
	
	text_height_chat = {
		name = 'Chat Text Size',
		type = 'number',
		value = text_height_chat,
		min = 8, max = 30, step = 1,
		OnChange = function(self)
			text_height_chat = self.value
			if stack_chat then
				UpdateStackFontSize(stack_chat, text_height_chat)
				UpdateStackFontSize(stack_backchat, text_height_chat)
				stack_chat:UpdateLayout()
				stack_backchat:UpdateLayout()
			else
				onOptionsChanged(self)
			end
		end,
	},
	text_height_console = {
		name = 'Log Text Size',
		type = 'number',
		value = text_height_console,
		min = 8, max = 30, step = 1,
		OnChange = function(self)
			text_height_console = self.value
			if stack_console then
				UpdateStackFontSize(stack_console, text_height_console)
				stack_console:UpdateLayout()
			else
				onOptionsChanged(self)
			end
		end,
	},
	
	highlighted_text_height = {
		name = 'Highlighted Text Size',
		type = 'number',
		value = 16,
		min = 8, max = 30, step = 1,
		OnChange = onOptionsChanged,
	},
	clickable_points = {
		name = "Clickable points and labels",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = onOptionsChanged,
		advanced = true,
	},
	--[[
	pointButtonOpacity = {
		name = "Point button opacity",
		type = 'number',
		value = 0.25,
		min = 0, max = 1, step = 0.05,
		advanced = true,
	},
	--]]
	-- TODO work in progress
	dedupe_messages = {
		name = "Dedupe messages",
		type = 'bool',
		value = true,
		OnChange = onOptionsChanged,
		advanced = true,
		noHotkey = true,
		path = dedupe_path,
	},
	dedupe_points = {
		name = "Dedupe points and labels",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = onOptionsChanged,
		advanced = true,
		path = dedupe_path,
	},
	highlight_all_private = {
		name = "Highlight all private messages",
		type = 'bool',
		value = highlight_all_private,
		OnChange = function(self)
			highlight_all_private = self.value
		end,
		noHotkey = true,
		advanced = true,
		path = hilite_path,
	},
	highlight_filter_allies = {
		name = "Check allies messages for highlight",
		type = 'bool',
		value = not dontHighlightThatSource['ally'],
		OnChange = function(self)
			dontHighlightThatSource['ally'] = not self.value
		end,
		noHotkey = true,
		advanced = true,
		path = hilite_path,
	},
	highlight_filter_enemies = {
		name = "Check enemy messages for highlight",
		type = 'bool',
		value = not dontHighlightThatSource['enemy'],
		OnChange = function(self)
			dontHighlightThatSource['enemy'] = not self.value
		end,
		noHotkey = true,
		advanced = true,
		path = hilite_path,
	},
	highlight_filter_specs = {
		name = "Check spec messages for highlight",
		type = 'bool',
		value = not dontHighlightThatSource['spec'],
		OnChange = function(self)
			dontHighlightThatSource['spec'] = not self.value
		end,
		noHotkey = true,
		advanced = true,
		path = hilite_path,
	},
	highlight_filter_other = {
		name = "Check other messages for highlight",
		type = 'bool',
		value = not dontHighlightThatSource['other'],
		OnChange = function(self)
			dontHighlightThatSource['other'] = not self.value
		end,
		noHotkey = true,
		advanced = true,
		path = hilite_path,
	},
--[[
	highlight_filter = {
		name = 'Highlight filter',
		type = 'list',
		OnChange = onOptionsChanged, -- NO NEED
		value = 'allies',
		items = {
			{ key = 'disabled', name = "Disabled" },
			{ key = 'allies', name = "Highlight only allies messages" },
			{ key = 'all', name = "Highlight all messages" },
		},
		advanced = true,
	},
--]]
	
	highlight_surround = {
		name = "Surround highlighted messages",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = onOptionsChanged,
		advanced = true,
		path = hilite_path,
	},
	highlight_sound = {
		name = "Sound for highlighted messages",
		type = 'bool',
		value = false,
		noHotkey = true,
		OnChange = onOptionsChanged,
		advanced = true,
		path = hilite_path,
	},
	send_lobby_updates = {
		name = "Display lobby chat and updates",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = onOptionsChanged,
		path = hilite_path,
	},
	sound_for_lobby = {
		name = "Play sound for lobby updates",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = onOptionsChanged,
		path = hilite_path,
	},
	hideSpec = {
		name = "Hide Spectator Chat",
		type = 'bool',
		value = hideSpec,
		OnChange = function(self)
			hideSpec = self.value
			onOptionsChanged(self)
		end,
		advanced = false,
		path = filter_path,
	},
	hideAlly = {
		name = "Hide Ally Chat",
		type = 'bool',
		value = hideAlly,
		OnChange = function(self)
			hideAlly = self.value
			onOptionsChanged(self)
		end,
		advanced = true,
		path = filter_path,
	},
	hidePoint = {
		name = "Hide Points",
		type = 'bool',
		value = hidePoint,
		OnChange = function(self)
			hidePoint = self.value
			onOptionsChanged(self)
		end,
		advanced = true,
		path = filter_path,
	},
	hideLabel = {
		name = "Hide Labels",
		type = 'bool',
		value = hideLabel,
		OnChange = function(self)
			hideLabel = self.value
			onOptionsChanged(self)
		end,
		advanced = true,
		path = filter_path,
	},
	hideLog = {
		name = "Hide Engine Logging Messages",
		type = 'bool',
		value = hideLog,
		OnChange = function(self)
			hideLog = self.value
			onOptionsChanged(self)
		end,
		advanced = true,
		path = filter_path,
	},
	max_lines = {
		name = 'Maximum Lines (1-300)',
		type = 'number',
		value = MAX_LINES,
		min = 1, max = MAX_STORED_MESSAGES, step = 1,
		OnChange = function(self)
			MAX_LINES = self.value
			onOptionsChanged(self)
		end,
	},
	
	color_chat = {
		name = 'Everyone chat text',
		type = 'colors',
		value = { 1, 1, 1, 1 },
		OnChange = onOptionsChanged,
		path = color_path,
	},
	color_ally = {
		name = 'Ally text',
		type = 'colors',
		value = { 0.2, 1, 0.2, 1 },
		OnChange = onOptionsChanged,
		path = color_path,
	},
	color_other = {
		name = 'Other text',
		type = 'colors',
		value = { 0.6, 0.6, 0.6, 1 },
		OnChange = onOptionsChanged,
		path = color_path,
	},
	color_spec = {
		name = 'Spectator text',
		type = 'colors',
		value = { 0.8, 0.8, 0.8, 1 },
		OnChange = onOptionsChanged,
		path = color_path,
	},
	color_usernames = {
		name = "Color usernames in messages",
		type = 'bool',
		value = true,
		OnChange = onOptionsChanged,
		advanced = true,
		path = color_path,
	},
	color_dup = {
		name = 'Duplicate message mark',
		type = 'colors',
		value = { 1, 0.2, 0.2, 1 },
		OnChange = onOptionsChanged,
		path = dedupe_path,
	},
	color_highlight = {
		name = 'Highlight mark',
		type = 'colors',
		value = { 1, 1, 0.2, 1 },
		OnChange = onOptionsChanged,
		path = hilite_path,
	},
	color_from_lobby = {
		name = 'Lobby notification color',
		type = 'colors',
		value = { 0.8, 0.3, 1, 1 },
		OnChange = onOptionsChanged,
		path = hilite_path,
	},
	color_chat_background = {
		name = "Chat Background color",
		type = "colors",
		value = { 0, 0, 0, 0},
		OnChange = function(self)
			scrollpanel_chat.backgroundColor = self.value
			scrollpanel_chat.borderColor = self.value
			scrollpanel_chat:Invalidate()
		end,
		path = color_path,
	},
	color_console_background = {
		name = "Console Background color",
		type = "colors",
		value = { 0, 0, 0, 0},
		OnChange = function(self)
			-- [[
			scrollpanel_console.backgroundColor = self.value
			scrollpanel_console.borderColor = self.value
			scrollpanel_console:Invalidate()
			--]]
			window_console.backgroundColor = self.value
			window_console.color = self.value
			window_console:Invalidate()
		end,
		path = color_path,
	},
	--[[
	mousewheel = {
		name = "Scroll with mousewheel",
		type = 'bool',
		value = false,
		OnChange = function(self) scrollpanel_console.ignoreMouseWheel = not self.value; end,
	},
	--]]
	defaultAllyChat = {
		name = "Default Chat Mode",
		type = 'radioButton',
		desc = "Sets default chat mode to allies at game start",
		value = 'auto',
		items = {
			{key = 'on',   name = 'Ally/Spectator Chat', desc = "Always start the game with ally chat or spectator chat enabled."},
			{key = 'auto', name = 'Context Dependant',   desc = "Start the game with ally chat enabled if you have any allies. Always start the game with spectator chat enabled."},
			{key = 'off',  name = 'All Chat',            desc = "Start the game with ally and spectator chat disabled."},
		},
		OnChange = CheckHide,
		noHotkey = true,
	},
	defaultBacklogEnabled = {
		name = "Enable backlog at start",
		desc = "Starts with the backlog chat enabled.",
		type = 'bool',
		value = false,
		noHotkey = true,
	},
	toggleBacklog = {
		name = "Toggle backlog",
		desc = "The toggle backlog button is here to let you hotkey this action.",
		type = 'button',
	},
	mousewheelBacklog = {
		name = "Mousewheel Backlog",
		desc = "Scroll the backlog chat with the mousewheel.",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = function(self)
			scrollpanel_backchat.ignoreMouseWheel = not options.mousewheelBacklog.value
			scrollpanel_backchat:Invalidate()
		end,
	},
	enableSwap = {
		name = "Show backlog arrow",
		desc = "Enable the button to swap between chat and backlog chat.",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = function(self)
			if self.value then
				window_chat:AddChild(backlogButton)
				if options.enableChatBackground.value then
					window_chat:RemoveChild(inputspace)
				end
				inputspace = WG.Chili.ScrollPanel:New{
					x = (options.backlogArrowOnRight.value and 0) or inputsize,
					right = ((not options.backlogArrowOnRight.value) and 0) or inputsize,
					bottom = 0,
					height = inputsize,
					noFont = true,
					backgroundColor = {1,1,1,1},
					borderColor = {0,0,0,1},
					--backgroundColor = {1,1,1,1},
				}
				if options.enableChatBackground.value then
					window_chat:AddChild(inputspace)
				end
			else
				window_chat:RemoveChild(backlogButton)
				if options.enableChatBackground.value then
					window_chat:RemoveChild(inputspace)
				end
				inputspace = WG.Chili.ScrollPanel:New{
					x = 0,
					bottom = 0,
					right = 0,
					height = inputsize,
					noFont = true,
					backgroundColor = {1,1,1,1},
					borderColor = {0,0,0,1},
					--backgroundColor = {1,1,1,1},
				}
				if options.enableChatBackground.value then
					window_chat:AddChild(inputspace)
				end
			end
			window_chat:Invalidate()
		end,
	},
	backlogHideNotChat = {
		name = "Hide arrow when not chatting",
		desc = "Enable to hide the backlog arrow when not entering chat.",
		type = 'bool',
		value = false,
		OnChange = function(self)
			if self.value then
				if backlogButton and backlogButton.parent then
					backlogButton:SetVisibility(WG.enteringText)
				end
			else
				if backlogButton and backlogButton.parent then
					backlogButton:SetVisibility(true)
				end
			end
		end
	},
	backlogShowWithChatEntry = {
		name = "Auto-toggle backlog",
		desc = "Enable to have the backlog enabled when entering text and disabled when not entering text.",
		type = 'bool',
		value = false,
	},
	backlogArrowOnRight = {
		name = "Backlong Arrow On Right",
		desc = "Puts the backlong arrow on the right. It appear on the left if disabled..",
		type = 'bool',
		value = true,
		noHotkey = true,
		OnChange = function(self)
			if window_chat and window_chat:GetChildByName("backlogButton") then
				backlogButton._relativeBounds.left = ((not self.value) and 0) or nil
				backlogButton._relativeBounds.right = (self.value and 0) or nil
				backlogButton:UpdateClientArea()
				
				window_chat:Invalidate()
			end
		end,
	},
	changeFont = {
		name = "Change message entering font.",
		desc = "With this enabled the text-entering font will be changed to match the chat. May cause Spring to competely lock up intermittently on load. Requires reload to update.",
		type = 'bool',
		value = false,
		advanced = true,
		noHotkey = true,
	},
	enableChatBackground = {
		name = "Enable chat background.",
		desc = "Enables a background for the text-entering box.",
		type = 'bool',
		value = false,
		noHotkey = true,
		advanced = true,
		OnChange = function(self)
			if self.value then
				window_chat:AddChild(inputspace)
			else
				window_chat:RemoveChild(inputspace)
			end
			scrollpanel_console:Invalidate()
		end,
	},
	hideChat = {
		name = "Hide when not chatting",
		desc = "Hide the chat completely when not entering chat.",
		type = 'bool',
		value = false,
		OnChange = function(self)
			SetHidden(self.value)
		end,
	},
	backchatOpacity = {
		name = "Backlog Border Opacity",
		type = 'number',
		value = 0.5,
		min = 0, max = 1, step = 0.05,
		OnChange = function(self)
			scrollpanel_backchat.borderColor = {0,0,0,self.value}
			scrollpanel_backchat:Invalidate()
		end,
	},
	autohide_text_time = {
		name = "Text decay time",
		type = 'number',
		value = 20,
		min = 10, max = 60, step = 5,
		--OnChange = onOptionsChanged,
	},
	
}
local options = options
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--functions

local function SetInputFontSize(size)
	if options.changeFont.value then
		Spring.SetConfigInt("FontSize", size, true) --3rd param true is "this game only"
		Spring.SendCommands('font ' .. WG.Chili.EditBox.font.font)
	end
end

--------------------------------------------------------------------------------
-- TODO : should these pattern/escape functions be moved to some shared file/library?

local function nocase(s)
  return string.gsub(s, "%a", function (c)
		return string.format("[%s%s]", string.lower(c), string.upper(c))
	  end
  )
end

local function escapePatternMatchChars(s)
  return string.gsub(s, "(%W)", "%%%1")
end

local function caseInsensitivePattern(s)
  return nocase(escapePatternMatchChars(s))
end

-- local widget only
function getMessageRuleOptionName(msgtype, suboption)
  return msgtype .. "_" .. suboption
end

for msgtype,rule in pairs(MESSAGE_RULES) do
	if rule.output and rule.name then -- if definition has multiple output formats, make associated config option
		local option_name = getMessageRuleOptionName(msgtype, "output_format")
		options_order[#options_order + 1] = option_name
		local o = {
			name = "Format for " .. rule.name,
			type = 'list',
			OnChange = function (self)
				Spring.Echo('Selected: ' .. self.value)
				onOptionsChanged()
			end,
			value = '1', -- may be overriden
			items = {},
			advanced = true,
		}
		
		for i, output in ipairs(rule.output) do
			o.items[i] = { key = i, name = output.name }
			if output.default then
				o.value = i
			end
		end
		options[option_name] = o
    end
end

local function getOutputFormat(msgtype)
  local rule = MESSAGE_RULES[msgtype]
  if not rule then
		Spring.Echo("UNKNOWN MESSAGE TYPE: " .. (msgtype or "NiL"))
		-- local _,msg = debug.getlocal(2, 1)
		-- if msg and type(msg) == 'table' then
		-- 	for k,v in pairs(msg) do
		-- 		Echo('...',k,v)
		-- 	end
		-- end
		return
  elseif rule.output then -- rule has multiple user-selectable output formats
    local option_name = getMessageRuleOptionName(msgtype, "output_format")
    local value = options[option_name].value
    return rule.output[value].format
  else -- rule has only 1 format defined
	return rule.format
  end
end

local function getSource(spec, allyTeamId)
	return (spec and 'spec')
		or ((Spring.GetMyTeamID() == allyTeamId) and 'ally')
		or 'enemy'
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function escape_lua_pattern(s)

	local matches =
	{
		["^"] = "%^";
		["$"] = "%$";
		["("] = "%(";
		[")"] = "%)";
		["%"] = "%%";
		["."] = "%.";
		["["] = "%[";
		["]"] = "%]";
		["*"] = "%*";
		["+"] = "%+";
		["-"] = "%-";
		["?"] = "%?";
		["\0"] = "%z";
	}

  
	return (s:gsub(".", matches))
end

local function PlaySound(id)
	if recentSoundTime then
		return
	end

	local file = SOUNDS[id]
	if file then
		Spring.PlaySoundFile(file, 1, 'ui')
		recentSoundTime = CONCURRENT_SOUND_GAP
	end
end

local function detectHighlight(msg)
	-- must handle case where we are spec and message comes from player
	
	if msg.msgtype == 'game_priority_message'
		or msg.msgtype == 'player_to_player_received' and highlight_all_private
		or msg.msgtype == 'player_to_self'
	then
		msg.highlight = true
	end
	
--	Spring.Echo("msg.source = " .. (msg.source or 'NiL'))
	if dontHighlightThatSource[msg.source] then
		return
	end

	if (msg.argument and msg.argument:find(highlightPattern)) then
		msg.highlight = true
	end
end

local function formatMessage(msg)
	local format = getOutputFormat(msg.msgtype) or getOutputFormat("other")

	-- Find and colour any usernames in the message body
	if options.color_usernames.value then
		-- This could be slightly faster by caching the value for each format rule,
		-- but that's more effort elsewhere, risks cache bugs,
		-- this operation is much faster than the N regex replacements,
		-- and this code path isn't that hot to begin with (not many chat messages per second)
		local last_colour_code = format:match('.*(#%w)') or '#o'
		local message_colour = incolors[last_colour_code]

		-- Lua lacks \b, so we match with spaces instead and strip the added ones afterwards
		local formatted_arg = ' '..msg.argument..' '
		-- incolors contains the control codes #[aehos] and also each player's username
		-- we get all the usernames by iterating it and just ignoring the #[aehos] control codes
		for name, colour in pairs(incolors) do
			if name:sub(1,1) ~= '#' then
				local pattern = '([^%w_])(' .. name .. ')([^%w_])'
				local sub = '%1'..colour..'%2'..message_colour..'%3'
				formatted_arg, _ = formatted_arg:gsub(pattern, sub)
			end
		end
		msg.argument = formatted_arg:sub(2, -2)  -- strip added spaces
	end

	-- insert/sandwich colour string into text
	local formatted, _ = format:gsub('([#%$]%w+)', function(parameter) -- FIXME pattern too broad for 1-char color specifiers
			if parameter:sub(1,1) == '$' then
				return msg[parameter:sub(2,parameter:len())]
			elseif parameter == '#p' then
				if msg.playername and incolors[msg.playername] then
					return incolors[msg.playername]
				else
					return incolors['#o'] -- player still at lobby, use grey text
				end
			else
				return incolors[parameter]
			end
		end)
	msg.formatted = formatted
	--]]
	msg.textFormatted = msg.text
	if msg.playername then
		local out = msg.text
		local playerName = escape_lua_pattern(msg.playername)
		out = out:gsub( '^<' .. playerName ..'> ', '' )
		out = out:gsub( '^%[' .. playerName ..'%] ', '' )
		msg.textFormatted = out
	end
	msg.source2 = msg.playername or ''
end

local function MessageIsChatInfo(arg)
	return arg:find('Speed set to') or
		arg:find('following') or
		arg:find('Connection attempted') or
		arg:find('exited') or
		arg:find('is no more') or
		arg:find('paused the game') or
		arg:find('^Sync error for') or
		arg:find('^Cheating is') or
		arg:find('GodModeAction') or
		arg:find('GlobalLosActionExecutor') or
		arg:find('Everything%-for%-free') or
		arg:find('resigned') or
		(arg:find('left the game') and arg:find('Player'))
	--string.find(msg.argument,'Team') --endgame comedic message. Engine message, loaded from gamedata/messages.lua (hopefully 'Team' with capital 'T' is not used anywhere else)
end

local function hideMessage(msgtype)
	return msgtype == 'userinfo'
		or hideSpec and msgtype == "spec_to_everyone" -- can only hide spec when playing
		or hideAlly and msgtype == "player_to_allies"
		or hidePoint and msgtype == "point"
		or hideLabel and msgtype == "label"
		or hideLog and msgtype == 'other' and not MessageIsChatInfo(msg.argument)
end




local function AddMessage(msg, target, remake)
	if hideMessage(msg.msgtype) then
		return
	end
	if not Image then
		Image = WG.Chili.Image
		Panel = WG.Chili.Panel
		TextBox = WG.Chili.TextBox
 		Button = WG.Chili.Button
	end
	local stack
	local fade
	local size
	local lastMsg
	local size
	if target == 'chat' then
		stack = stack_chat
		size = text_height_chat
		if not remake then
			fade = true 
		end
		lastMsg = lastMsgChat
	elseif target == 'console' then
		stack = stack_console
		size = text_height_console
		lastMsg = lastMsgConsole
	elseif target == 'backchat' then
		size = text_height_chat
		stack = stack_backchat
		lastMsg = lastMsgBackChat
	end
	
	if not stack then
		-- stack_console may not yet be created.
		return
	end
	
	--if msg.highlight and options.highlighted_text_height.value
	
	-- TODO betterify this / make configurable
	local highlight_sequence1 = (msg.highlight and options.highlight_surround.value and (incolor_highlight .. HIGHLIGHT_SURROUND_SEQUENCE_1) or '')
	local highlight_sequence2 = (msg.highlight and options.highlight_surround.value and (incolor_highlight .. HIGHLIGHT_SURROUND_SEQUENCE_2) or '')
	local text = (msg.dup > 1 and (incolor_dup .. msg.dup .. DEDUPE_SUFFIX) or '') .. highlight_sequence1 .. msg.formatted .. highlight_sequence2

	if msg.dup > 1 and not remake then
		--local last = stack.children[#(stack.children)]
		
		if lastMsg then
			if lastMsg.SetText then
				lastMsg:SetText(text)
				-- UpdateClientArea() is not enough - last message keeps disappearing until new message is added
				lastMsg:Invalidate()
			end
		end
		return
	end

	local textbox = TextBox:New{
		width = '100%',
		align = "left",
		valign = "ascender",
		lineSpacing = 0,
		padding = tZeroes,
		-- text = '['..COUNT..']'..maxReached..':Len:'..#stack.children..', prev:'..prevTxt..' | '..text,
		text = text,
		
		--[[
		autoHeight=true,
		autoObeyLineHeight=true,
		--]]
		objectOverrideFont = WG.GetSpecialFont(size, "proconsole", {
			outlineWidth = 3,
			outlineWeight = 5,
			outline = true,
		})
	}
	
	local control = textbox
	if options.clickable_points.value then
		if msg.point then --message is a marker, make obvious looking button
			local padding
			if target == 'chat' then
				padding = tThreeOnes
			else
				padding = tOnes
			end
			textbox:SetPos( 35, 3, stack.width - 40 )
			textbox:Update()
			local tbheight = textbox.height -- not perfect
			tbheight = math.max( tbheight, 15 ) --hack
			--Echo('tbheight', tbheight)
			control = Panel:New{
				width = '100%',
				height = tbheight + 8,
				padding = padding,
				margin = tZeroes,
				backgroundColor = tZeroes,
				caption = '',
				children = {
					Button:New{
						noFont = true,
						x=0;y=0;
						width = 30,
						height = 20,
						classname = "overlay_button_tiny",
						-- backgroundColor = {1,1,1,options.pointButtonOpacity.value},
						padding = tTwos,
						children = {
							Image:New {
								x=7;y=2;
								width = 14,
								height = 14,
								keepAspect = true,
								file = 'LuaUI/Images/Crystal_Clear_action_flag.png',
							}
						},
						OnClick = {function(self, x, y, button)
							if button == 1 then
								local alt,ctrl, meta,shift = Spring.GetModKeyState()
								if (shift or ctrl or meta or alt) then  --skip modifier key since they indirectly meant player are using click to issue command (do not steal click)
									return false
								end
								SetCameraTarget(msg.point.x, msg.point.y, msg.point.z, 1)
							end
						end}
					},
					textbox,
				},
				
			}
		elseif target == 'chat' then
			-- Make a panel for each chat line because this removes the message jitter upon fade.
			textbox:SetPos( 3, 3, stack.width - 3 )
			textbox:Update()
			local tbheight = textbox.height + 2 -- not perfect
			--Echo('tbheight', tbheight)
			control = Panel:New{
				width = '100%',
				height = tbheight,
				padding = tZeroes,
				backgroundColor = tZeroes,
				caption = '',
				-- useRTT = false,

				children = {
					textbox,
				},
			}
		elseif WG.alliedCursorsPos and msg.player and msg.player.id then --message is regular chat, make hidden button
			local cur = WG.alliedCursorsPos[msg.player.id]
			if cur then
				textbox.OnMouseDown = {
					function(self, x, y, button)
						if button == 1 then
							local alt,ctrl, meta,shift = Spring.GetModKeyState()
							if ( shift or ctrl or meta or alt ) then
								--skip all modifier key
								return false
							end
							if x <= textbox.font:GetTextWidth(self.text) then
								-- use self.text instead of text to include dedupe message prefix
								SetCameraTarget(cur[1], 0,cur[2], 1) --go to where player is pointing at. NOTE: "cur" is table referenced to "WG.alliedCursorsPos" so its always updated with latest value
							end
						end
					end
				}
				function textbox:HitTest(x, y)  -- copied this hack from chili bubbles
					return self
				end
			end
		end
	end
	if stack.children[MAX_LINES] then
		stack:RemoveChild(stack.children[1])
	end
	stack:AddChild(control, false)
	if fade then
		control.fade = 1
		fadeTracker[control_id] = control
		control_id = control_id + 1
	end
	
	if target == 'chat' then
		lastMsgChat = textbox
	elseif target == 'backchat' then
		lastMsgBackChat = textbox
	else
		lastMsgConsole = textbox
	end
	-- stack:UpdateClientArea()
	requestUpdate = stack
end


local function setupColors()
	incolor_dup			= color2incolor(options.color_dup.value)
	incolor_highlight	= color2incolor(options.color_highlight.value)
	-- incolor_fromlobby	= color2incolor(options.color_from_lobby.value)
	local lobbycolor 	= options.color_from_lobby.value
	incolor_fromlobby_text = color2incolor(lobbycolor[1], lobbycolor[2], lobbycolor[3], lobbycolor[4])
	local min = math.min
	incolor_fromlobby_head = color2incolor(min(lobbycolor[1]*8/5, 1), min(lobbycolor[2]*8/5, 1), min(lobbycolor[3]*8/5, 1), lobbycolor[4])
	incolors['#h']		= incolor_highlight
	incolors['#a'] 		= color2incolor(options.color_ally.value)
	incolors['#e'] 		= color2incolor(options.color_chat.value)
	incolors['#o'] 		= color2incolor(options.color_other.value)
	incolors['#s'] 		= color2incolor(options.color_spec.value)
	incolors['#p'] 		= '' -- gets replaced with a player-specific color later; here just not to crash
end
local function setupPlayers(playerID)
	if playerID then
		local name, active, spec, teamId, allyTeamId = Spring.GetPlayerInfo(playerID, false)
		--lobby: grey chat, spec: white chat, player: color chat
		incolors[name] = (spec and incolors['#s']) or color2incolor(Spring.GetTeamColor(teamId))
	else
		local playerroster = Spring.GetPlayerList()
		for i, id in ipairs(playerroster) do
			local name,active, spec, teamId, allyTeamId = Spring.GetPlayerInfo(id, false)
			--lobby: grey chat, spec: white chat, player: color chat
			incolors[name] = (spec and incolors['#s']) or color2incolor(Spring.GetTeamColor(teamId))
		end
	end
end

local function SetupAITeamColor() --Copied from gui_chili_chat2_1.lua
	-- register any AIs
	-- Copied from gui_chili_crudeplayerlist.lua
	local teamsSorted = Spring.GetTeamList()
	for i=1,#teamsSorted do
		local teamID = teamsSorted[i]
		if teamID ~= Spring.GetGaiaTeamID() then
			local isAI = select(4,Spring.GetTeamInfo(teamID, false))
			if isAI then
				local name = select(2,Spring.GetAIInfo(teamID))
				incolors[name] = color2incolor(Spring.GetTeamColor(teamID))
			end
		end --if teamID ~= Spring.GetGaiaTeamID()
	end --for each team
end

local function setupMyself()
	myName, _, _, _, myAllyTeamId = Spring.GetPlayerInfo(Spring.GetMyPlayerID(), false) -- or do it in the loop?
	highlightPattern = caseInsensitivePattern(myName)
end

local function setup()
	setupMyself()
	setupColors()
	setupPlayers()
	SetupAITeamColor()
end

function RemakeConsole()
	setup()
	-- stack_console:ClearChildren() --disconnect from all children
	if stack_console then
		stack_console:ClearChildren()
	end
	
	stack_backchat:ClearChildren()
	
	for i = 1, #chatMessages do
		local msg = chatMessages[i]
		-- AddMessage(msg, 'chat', true, true )
		AddMessage(msg, 'backchat', true )
	end

	if window_console.parent then
		local len = #consoleMessages
		for i = math.max(1, len - MAX_LINES + 1), len do
			AddMessage(consoleMessages[i], 'console', true )
		end
	end

	if window_console then
		window_console:Resize(window_console.width, window_console.height)
	end

end

local function ShowInputSpace()
	WG.enteringText = true
	inputspace.backgroundColor = tOnes
	inputspace.borderColor = {0,0,0,1}
	inputspace:Invalidate()
	
	if options.backlogHideNotChat.value and backlogButton and backlogButton.parent then
		backlogButton:SetVisibility(true)
	end
end
local function HideInputSpace()
	WG.enteringText = false
	inputspace.backgroundColor = tZeroes
	inputspace.borderColor = tZeroes
	inputspace:Invalidate()
	
	if options.backlogHideNotChat.value and backlogButton and backlogButton.parent then
		backlogButton:SetVisibility(false)
	end
end

local function MakeMessageStack(margin, name)
	return WG.Chili.StackPanel:New{
		name = 'message_stack_'..name,
		margin = tZeroes,
		padding = tZeroes,
		x = 0,
		y = 0,
		--width = '100%',
		right=5,
		height = 10,
		resizeItems = false,
		itemPadding  = tOnes,
		itemMargin  = { margin, margin, margin, margin },
		autosize = true,
		preserveChildrenOrder = true,
		-- useRTT = false,
	}
end

local function MakeMessageWindow(name, enabled, ParentFunc)

	local x,y,bottom,width,height,resizable
	local screenWidth, screenHeight = Spring.GetViewGeometry()
	if name == "ProChat" then
		local integralWidth = math.max(350, math.min(450, screenWidth*screenHeight*0.0004))
		local integralHeight = math.min(screenHeight/4.5, 200*integralWidth/450)
		width = 450
		x = integralWidth
		height = integralHeight*0.84
		bottom = integralHeight*0.84
		resizable = false
	else
		local resourceBarWidth = 430
		local maxWidth = math.min(screenWidth/2 - resourceBarWidth/2, screenWidth - 400 - resourceBarWidth)
		bottom = nil
		width  = 380 - 4	--screenWidth * 0.30	-- 380 is epic menu bar width
		height = screenHeight * 0.20
		x = screenWidth - width
		y = 50
		if maxWidth < width then
			y = 50 -- resource bar height
		end
		resizable = true
	end
	if enabled and ParentFunc then
		ParentFunc()
	end
	
	return WG.Chili.Window:New{
		parent = (enabled and screen0) or nil,
		margin = tZeroes,
		padding = tZeroes,
		noFont = true,
		dockable = true,
		name = name,
		x = x,
		y = y,
		bottom = bottom,
		width  = width,
		height = height,
		draggable = false,
		resizable = resizable,
		tweakDraggable = true,
		tweakResizable = true,
		minimizable = false,
		parentWidgetName = widget:GetInfo().name, --for gui_chili_docking.lua (minimize function)
		minWidth = MIN_WIDTH,
		minHeight = MIN_HEIGHT,
		maxHeight = MAX_HEIGHT,
		color = tZeroes,
		-- useRTT = false,

		-- MouseDown = function(self,...)
		-- 	Echo('down',...)
		-- 	self.useRTT = false
		-- 	return self.inherited.MouseDown(self,...)
		-- end,
		-- OnResize = {
  --           function(self,clientWidth,clientHeight,a,b)
  --           	Echo('resizing',clientWidth,clientHeight)
  --           end
  --       },
		-- MouseUp = function(self,...)
		-- 	Echo('up',...)
		-- 	self.useRTT = true
		-- 	self:Invalidate()
		-- 	return self.inherited.MouseUp(self,...)
		-- end,


		OnMouseDown = {
			function(self) --//click on scroll bar shortcut to "Settings/HUD Panels/Chat/Console".
				local _,_, meta,_ = Spring.GetModKeyState()
				if not meta then return false end
				WG.crude.OpenPath(options_path)
				WG.crude.ShowMenu() --make epic Chili menu appear.
				return true
			end
		},
		OnParent = ParentFunc and {
			ParentFunc
		},
	}
end

local function SetBacklogShow(newShow)
	if newShow == showingBackchat then
		return
	end
	SwapBacklog()
end

options.toggleBacklog.OnChange = SwapBacklog

-----------------------------------------------------------------------
-- callins
-----------------------------------------------------------------------

local function CheckEnableAllyChat()
	if options.defaultAllyChat.value == "off" then
		return false
	elseif options.defaultAllyChat.value == "on" then
		return true
	end
	if Spring.GetSpectatingState() then
		return true
	end
	local myAllyTeamID = Spring.GetMyAllyTeamID()
	if not myAllyTeamID then
		return true
	end
	local myTeamList = Spring.GetTeamList(myAllyTeamID)
	return (not myTeamList) or (#myTeamList > 1)
end

local keypadEnterPressed = false

function widget:KeyPress(key, modifier, isRepeat)
	if key == KEYSYMS.KP_ENTER then
		keypadEnterPressed = true
	end
	if (key == KEYSYMS.RETURN) or (key == KEYSYMS.KP_ENTER) then
		if firstEnter then
			if (not (modifier.Shift or modifier.Ctrl)) and CheckEnableAllyChat() then
				Spring.SendCommands("chatally")
			else
				Spring.SendCommands("chatall")
			end
			firstEnter = false
		end
		
		if options.backlogShowWithChatEntry.value then
			SetBacklogShow(true)
		end
		ShowInputSpace()
	else
		if options.backlogShowWithChatEntry.value then
			SetBacklogShow(false)
		end
		HideInputSpace()
	end
end

function widget:KeyRelease(key, modifier, isRepeat)
	if (key == KEYSYMS.RETURN) or (key == KEYSYMS.KP_ENTER) then
		if key == KEYSYMS.KP_ENTER and keypadEnterPressed then
			keypadEnterPressed = false
			return
		end
		if options.backlogShowWithChatEntry.value then
			SetBacklogShow(false)
		end
		HideInputSpace()
	end
	keypadEnterPressed = false
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function widget:TextCommand(cmd)
	if cmd == 'epic_chili_pro_console_enableconsole' then
		requestRemake = true
		-- RemakeConsole()
	end
end

function widget:MapDrawCmd(playerId, cmdType, px, py, pz, caption)
--	Spring.Echo("########### MapDrawCmd " .. playerId .. " " .. cmdType .. " coo="..px..","..py..","..pz .. (caption and (" caption " .. caption) or ''))
	if (cmdType == 'point') then
		widget:AddMapPoint(playerId, px, py, pz, caption) -- caption may be an empty string
		return false
	end
end

function widget:AddMapPoint(playerId, px, py, pz, caption)
	local playerName, active, spec, teamId, allyTeamId = Spring.GetPlayerInfo(playerId, false)

	widget:AddConsoleMessage({
		msgtype = ((caption:len() > 0) and 'label' or 'point'),
		playername = playerName,
		source = getSource(spec, allyTeamId),
		text = 'MapDrawCmd ' .. caption,
		argument = caption,
		priority = 0, -- just in case ... probably useless
		point = { x = px, y = py, z = pz }
	})
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local function isChat(msg)
	return msg.msgtype ~= 'other' 
		or MessageIsChatInfo(msg.argument)
		or msg.argument:find('^%[self%]:')
end

-- new callin! will remain in widget
local function IsValid(msg)
	if msg.msgtype == 'other' then
		local arg = msg.argument
		if arg:find('Error: OpenGL: source') and options.error_opengl_source.value
			or arg:find("Warning: [LuaHandle::CheckStack] LuaRules stack-top", 0, true) and options.filter_luaHandleCheckStack.value
			or arg:find('added point')
			or arg:find("LuaMenuServerMessage")
			or arg:find("GroundDetail set to")
		then
			return false
		end
	elseif msg.msgtype == 'point' and not msg.argument then
		return false
	end
	return true
end
function widget:AddConsoleMessage(msg, skip)
	if not (skip or IsValid(msg)) then
		return
	end
	if bufferMessages then
		wbuffered = wbuffered + 1
		widgetbuffer[wbuffered] = msg
		return
	end
	
	local isChat = isChat(msg)
	if isChat and msg.msgtype == "other" and msg.text:find('^%[self%]:') then
		msg.argument = msg.argument:gsub('%[self%]:','')
		msg.msgtype = "player_to_self"
		msg.playername = myName
		msg.highlight = true
	end
	local isPoint = msg.msgtype == "point" or msg.msgtype == "label"
	local messages = isChat and chatMessages or consoleMessages
	local count = #messages
	local lastMessage = messages[count]
	if lastMessage
		and lastMessage.text == msg.text
		and (isPoint and options.dedupe_points.value or options.dedupe_messages.value)
		then
		
		if isPoint then
			-- update MapPoint position with most recent, as it is probably more relevant
			lastMessage.point = msg.point
		end
		
		lastMessage.dup = lastMessage.dup + 1
		
		if isChat then
			AddMessage(lastMessage, 'chat')
			AddMessage(lastMessage, 'backchat')
		else
			AddMessage(lastMessage, 'console')
		end
		return
	end
	
	msg.dup = 1
	
	detectHighlight(msg)
	formatMessage(msg) -- does not handle dedupe or highlight
	
	messages[count + 1] = msg
	
	if isChat then
		AddMessage(msg, 'chat')
		AddMessage(msg, 'backchat')
	else
		AddMessage(msg, 'console')
	end
	
	if msg.highlight and options.highlight_sound.value then
		PlaySound("highlight")
	elseif (msg.msgtype == "player_to_allies") or (msg.msgtype == "game_priority_message") then -- FIXME not for sent messages
		PlaySound("ally")
	elseif msg.msgtype == "label" then
		PlaySound("label")
	end

	if count > MAX_STORED_MESSAGES then
		table.remove(messages, 1)
	end
	
	-- removeToMaxLines()
end

-----------------------------------------------------------------------

local function InitializeConsole()
	if stack_console then
		return
	end
	stack_console = MakeMessageStack(1,'console')
	scrollpanel_console:AddChild(stack_console)
	-- Echo('initialize console, #message',#consoleMessages)
	if not consoleMessages[1] then
		return
	end
	local max = options.max_lines.value
	local allMessages = #consoleMessages
	local start = math.max(1, allMessages - max + 1)
	local End = allMessages
	-- Echo('Console Initializing, adding the last ' .. (End - start + 1)
	 -- .. ' messages (total '.. allMessages .. ')' --,
	 -- '\nfrom'.. consoleMessages[start].formatted .. '\nto '..consoleMessages[End].formatted
	-- )
	for i = start, End do
		local msg = consoleMessages[i]
		AddMessage(msg, 'console', true )
	end
	-- removeToMaxLines()
end


function widget:Initialize()
	if (not WG.Chili) then
		widgetHandler:RemoveWidget()
		return
	end
	screen0 = WG.Chili.Screen0
	color2incolor = WG.Chili.color2incolor
	
	Spring.SendCommands("bind Any+enter  chat")
	
	stack_chat = MakeMessageStack(0,'chat')
	stack_backchat = MakeMessageStack(1,'backchat')
	inputspace = WG.Chili.ScrollPanel:New{
		x = (options.backlogArrowOnRight.value and 0) or inputsize,
		right = ((not options.backlogArrowOnRight.value) and 0) or inputsize,
		bottom = 0,
		noFont = true,
		height = inputsize,
		backgroundColor = {1,1,1,1},
		borderColor = {0,0,0,0},

		--backgroundColor = {1,1,1,1},
	}
	backlogButtonImage = WG.Chili.Image:New {
		width = "100%",
		height = "100%",
		keepAspect = true,
		--color = {0.7,0.7,0.7,0.4},
		file = 'LuaUI/Images/arrowhead.png',
	}
	backlogButton = WG.Chili.Button:New{
		name = "backlogButton",
		x = ((not options.backlogArrowOnRight.value) and 0) or nil,
		right = (options.backlogArrowOnRight.value and 0) or nil,
		bottom = 4,
		width = inputsize - 3,
		height = inputsize - 3,
		classname = "overlay_button_tiny",
		padding = tOnes,
		noFont = true,
		tooltip = 'Swap between decaying chat and scrollable chat backlog.',
		OnClick = {SwapBacklog},
		children={ backlogButtonImage },
	}
	
	scrollpanel_chat = WG.Chili.ScrollPanel:New{
		--margin = {5,5,5,5},
		padding = { 1,1,1,4 },
		x = 0,
		y = 0,
		width = '100%',
		noFont = true,
		bottom = inputsize + 2, -- This line is temporary until chili is fixed so that ReshapeConsole() works both times! -- TODO is it still required??
		verticalSmartScroll = true,
-- DISABLED FOR CLICKABLE TextBox		disableChildrenHitTest = true,
		backgroundColor = options.color_chat_background.value,
		borderColor = options.color_chat_background.value,
		ignoreMouseWheel = true,
		children = {
			stack_chat,
		},
		verticalScrollbar = false,
		horizontalScrollbar = false,

	}
	
	--spacer that forces chat to be scrolled to bottom of chat window
	WG.Chili.Panel:New{
		width = '100%',
		height = 500,
		backgroundColor = tZeroes,
		parent = stack_chat,

	}
	
	scrollpanel_backchat = WG.Chili.ScrollPanel:New{
		--margin = {5,5,5,5},
		padding = { 3,3,3,3 },
		x = 0,
		y = 0,
		noFont = true,
		width = '100%',
		bottom = inputsize + 2, -- This line is temporary until chili is fixed so that ReshapeConsole() works both times! -- TODO is it still required??
		verticalSmartScroll = true,
		backgroundColor = options.color_chat_background.value,
		borderColor = {0,0,0,options.backchatOpacity.value},
		horizontalScrollbar = false,
		ignoreMouseWheel = not options.mousewheelBacklog.value,

		children = {
			stack_backchat,
		},
	}
	
	scrollpanel_console = WG.Chili.ScrollPanel:New{
		--margin = {5,5,5,5},
		padding = { 5, 5, 5, 5 },
		x = 5,
		y = 5,
		right = 5,
		bottom = 5,
		noFont = true,
		verticalSmartScroll = true,
		backgroundColor = tZeroes,
		borderColor = tZeroes,
		
		--ignoreMouseWheel = not options.mousewheel.value,
		children = {
		},
	}
	
	window_chat = MakeMessageWindow("ProChat", true)
	window_chat:AddChild(scrollpanel_chat)
	window_chat:AddChild(backlogButton)
	if options.enableChatBackground.value then
		window_chat:AddChild(inputspace)
	end

	window_console = MakeMessageWindow("ProConsole", options.enableConsole.value, InitializeConsole)
	window_console:AddChild(scrollpanel_console)
end

local function Initialize()

	setup()
	local max = options.max_lines.max
	local verymax = max * 2 -- count twice as many because some msg get discarded for various reason

	--------------------------------
	bufferMessages = false
	if wbuffered >= max then
		for i, msg in ipairs(widgetbuffer) do
			-- fix points and label just being text when grabbed from the buffer
			-- if (msg.msgtype == "point" or msg.msgtype == "label") and not msg.argument then 
			-- 	Echo('POINT FIXED')
			-- 	msg.argument = msg.text
			-- end
		  	widget:AddConsoleMessage(msg, true)
		end
		-- Echo(wbuffered .. ' buffered messages')
	else
		local whbuffer = widget:ProcessConsoleBuffer(nil, verymax)
		local count = 0
		local len = #whbuffer
		local invalid = 0
		for i = len, 1, -1 do
			if not IsValid(whbuffer[i]) then
				whbuffer[i] = false
				invalid = invalid + 1
			else
				count = count + 1
				if count == max then
					break
				end
			end
		end
		for i = len - count, len do
			local msg = whbuffer[i]
			if msg then
				widget:AddConsoleMessage(msg, true)
			end
		end

	end



	--------------------------------
	--[[
	local whbufferLength = 0
	if wbuffered <= verymax then
		whbufferLength = verymax - wbuffered
		local whbuffer = widget:ProcessConsoleBuffer(nil, verymax)

		Echo('process console buffer from WH, ask ' .. whbufferLength, 'got', #whbuffer)
		-- for i = whbufferLength, whbufferLength - 6, -1 do
		-- 	Echo(i,'=>>>>',whbuffer[i].text)
		-- end
		for i=1, #whbuffer do
			local msg = whbuffer[i]
			-- fix points and label just being text when grabbed from the buffer
			if (msg.msgtype == "point" or msg.msgtype == "label") and not msg.argument then 
				msg.argument = msg.text
			end
			msg.argument = '[WH BUFFER '..i..'] ' ..msg.argument
		  	widget:AddConsoleMessage(msg)
		end
	else
		Echo('widgetbuffer ', wbuffered,' is large enough, skipping older messages from WH')
	end
	if wbuffered > 0 then
		local start = math.max(1, wbuffered - verymax + 1)
		local End = wbuffered
		Echo("widgetbuffer size is ", wbuffered, 'asked ' .. End - start + 1)
		for i=start,End do
			local msg = widgetbuffer[i]
			-- fix points and label just being text when grabbed from the buffer
			-- if (msg.msgtype == "point" or msg.msgtype == "label") and not msg.argument then 
			-- 	Echo('POINT FIXED')
			-- 	msg.argument = msg.text
			-- end
			msg.argument = '[MY BUFFER'..i..'] ' ..msg.argument
		  	widget:AddConsoleMessage(msg)
		end
	end
	Echo('end releasing messages')
	Echo('total msg in WHBuffer ?', #widget:ProcessConsoleBuffer(nil, 100000))
	--]]
	-----------------------------
	widgetbuffer = nil
	Spring.SendCommands({"console 0"})

	HideInputSpace()
		
	widget:LocalColorRegister()
end

local timer = 0

local initialSwapTime = 0.2
local firstSwap = true

-- FIXME wtf is this obsessive function?

function widget:Update(s)
	if firstUpdate then
		Initialize()
		requestRemake = false
	elseif requestRemake then
		requestRemake = false
		RemakeConsole()
	end
	if requestUpdate then
		local stack = requestUpdate
		requestUpdate = false
		stack:RequestUpdate()
		-- stack:UpdateClientArea()
	end
	if recentSoundTime then
		recentSoundTime = recentSoundTime - s
		if recentSoundTime < 0 then
			recentSoundTime = false
		end
	end
	timer = timer + s
	if timer > 2 then
		timer = 0
		local sub = 2 / options.autohide_text_time.value
		
		local inputWidthAdd = 0
		if not options.backlogArrowOnRight.value then
			inputWidthAdd = inputsize
		end
		
		Spring.SendCommands(
			{
				string.format("inputtextgeo %f %f 0.02 %f",
					(window_chat.x + inputWidthAdd)/ screen0.width + 0.003,
					1 - (window_chat.y + window_chat.height) / screen0.height + 0.004,
					window_chat.width / screen0.width
				)
			}
		)
		for k,control in pairs(fadeTracker) do
			fadeTracker[k].fade = math.max( control.fade - sub, 0 ) --removes old lines
			
			if control.fade == 0 then
				control:Dispose()
				fadeTracker[k] = nil
			end
		end
	end
	
	if firstUpdate then
		if options.defaultBacklogEnabled.value then
			SwapBacklog()
		end
		firstUpdate = false
		SetInputFontSize(15)
		if missionMode then
			SetHidden(true)
		end
	end
	
	-- Workaround bugged display on first open of the backlog
	if initialSwapTime then
		initialSwapTime = initialSwapTime - s
		if initialSwapTime < 0.1 and firstSwap then
			SwapBacklog()
			firstSwap = nil
		elseif initialSwapTime < 0 then
			SwapBacklog()
			SetBacklogShow(options.defaultBacklogEnabled.value)
			initialSwapTime = nil
		end
		if missionMode then
			SetHidden(true)
		end
	end
end

-----------------------------------------------------------------------

function widget:PlayerChanged(playerID)
	setupPlayers(playerID)
end

-----------------------------------------------------------------------
function widget:LocalColorRegister()
	if WG.LocalColor and WG.LocalColor.RegisterListener then
		WG.LocalColor.RegisterListener(widget:GetInfo().name, onOptionsChanged)
	end
end

function widget:LocalColorUnregister()
	if WG.LocalColor and WG.LocalColor.UnregisterListener then
		WG.LocalColor.UnregisterListener(widget:GetInfo().name)
	end
end

-----------------------------------------------------------------------



function widget:GameStart()
	setupPlayers() --re-check teamColor at gameStart for Singleplayer (special case. widget Initialized before player join).
end

function widget:RecvLuaMsg(msg, playerID)
	local _, st = msg:find('^LobbyChatUpdate')
	if st then
		local message
		local headcol, textcol = incolor_fromlobby_head, incolor_fromlobby_text
		local playerName
		if msg:find('^2_', st + 1) then
			playerName = true
			message = msg:sub(st + 3)
			_, st, playerName = message:find('^([%w_]+)') 
			message = message:sub(st + 2)

		elseif msg:find('^_', st + 1) then
			message = msg:sub(st + 2)
		end
		if message then -- FIXME: why does an in-world object care about the overlay?

			if options.send_lobby_updates.value then
				local comp_msg
				if playerName then
					comp_msg = {
						formatted = textcol .. "[" .. headcol .. playerName .. textcol .. "]: " .. message,
						dup = 0,
					}
				else
					if #message > 200 then
						message = message:sub(1, 200) .. '...'
					end
					comp_msg = {
						formatted = textcol .. "[" .. headcol .. "LOBBY" .. textcol .. "]: ".. message,
						dup = 0,
					}
				end
				AddMessage(comp_msg, 'chat')
				AddMessage(comp_msg, 'backchat')
			end
			if options.sound_for_lobby.value and not Spring.IsGameOver() then
				PlaySound('lobby')
			end
		end
	end
end

-----------------------------------------------------------------------

function widget:Shutdown()
	if (window_chat) then
		window_chat:Dispose()
	end
	SetInputFontSize(20)
	Spring.SendCommands({"console 1", "inputtextgeo default"}) -- not saved to spring's config file on exit
	Spring.SetConfigString("InputTextGeo", "0.26 0.73 0.02 0.028") -- spring default values
	
	self:LocalColorUnregister()
end



f.DebugWidget(widget)