function widget:GetInfo()
  return {
	name      = "Command Tweaks",
	desc      = "",
	author    = "Helwor",
	date      = "august 2023",
	license   = "GNU GPL, v2 or later",
	layer     = -10000, 
	enabled   = true,  --  loaded by default?
	handler   = true,
	api       = true
  }
end

local requirements = {
	value = {
		['WG.selectionAPI'] = {'Requires api_selection_handler.lua and running'},
	}
}

local spGiveOrder = Spring.GiveOrder 
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetSelectedUnits = Spring.GetSelectedUnits
local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")
local CMD_RAW_MOVE = customCmds.RAW_MOVE
local CMD_WANTED_SPEED = customCmds.WANTED_SPEED

local mySelection

local opt_widow_shootOnce = false
local opt_rev_shootOnce = false
local opt_puppy_shootOnce = false
local opt_precise_gs_move = true
local opt_precise_plane_move = false
local opt_cautious_athena = false -- not implemented
options_path = 'Hel-K/' .. widget:GetInfo().name
options = {}



options.widowShootOnce = {
	type = 'bool',
	name = 'Widow Shoot Once',
	value = opt_widow_shootOnce,
	OnChange = function(self)
		opt_widow_shootOnce = self.value
	end
}
options.revShootOnce = {
	type = 'bool',
	name = 'Revenant Shoot Once',
	value = opt_rev_shootOnce,
	OnChange = function(self)
		opt_rev_shootOnce = self.value
	end
}
options.preciseGS = {
	type = 'bool',
	name = 'Precise GS move',
	value = opt_precise_gs_move,
	OnChange = function(self)
		opt_precise_gs_move = self.value
	end
}
options.precisePlane = {
	type = 'bool',
	name = 'Precise Plane move',
	value = opt_precise_plane_move,
	OnChange = function(self)
		opt_precise_plane_move = self.value
	end
}
-- options.cautious_athena = {
-- 	name = 'Cautious Athena', -- unused, rather passing by CustomFormation
-- 	type = 'bool',
-- 	value = opt_cautious_athena,
-- 	OnChange = function(self)
-- 		opt_cautious_athena = self.value
-- 	end,
-- }
options.puppyShootOnce = {
	name = 'Puppy shoot once', -- unused, rather passing by CustomFormation
	type = 'bool',
	value = opt_puppy_shootOnce,
	OnChange = function(self)
		opt_puppy_shootOnce = self.value
	end,
}

local Echo = Spring.Echo

local CMD_ATTACK = CMD.ATTACK
local CMD_OPT_CTRL = CMD.OPT_CTRL
-- local customCmds = VFS.Include("LuaRules/Configs/customcmds.lua")
-- local CMD_RAW_MOVE = customCmds.RAW_MOVE
-- customCmds = nil
local EMPTY_TABLE = {}

-- local blastwingDefID = UnitDefNames['gunshipbomb'].id

-- local bombDefID = {}
-- for defID, def in pairs(UnitDefs) do
--     if def.name:match('bomb') then
--         bombDefID[defID] = true
--     end
-- end


local hasBomber, hasWidow = false, false
local hasSmallSelection = false
local hasGunship = false
local hasPuppy = false
local hasAthena, hasOnlyAthena = false, false
local hasPlane = false

local newSequence = true
local ovParams, ovOpts = false, false

function widget:CommandsChanged()
	-- hasBomber = false

	hasWidow = mySelection.hasWidow
	hasRev = mySelection.hasRev
	hasPuppy = mySelection.hasPuppy
	-- hasBobmer = mySelection.hasBomber
	-- hasOnlyAthena = mySelection.hasOnlyAthena
	hasSmallSelection = mySelection.isSmall
	hasGunship = mySelection.hasGunship
	hasPlane = mySelection.hasPlane
end
function Process(cmd, params, opts, giveOrder) -- global function to be accessed by widgets that intervene before
	-- Echo("hasOnlyAthena ,cmd , opts.ctrl is ", hasOnlyAthena ,cmd , opts.ctrl)
	local override = false
	if cmd == CMD_ATTACK and not opts.ctrl and (
		opt_widow_shootOnce and hasWidow 
		-- or hasBomber and params[3] and (not params[4] or params[4]==0)
		or opt_rev_shootOnce and hasRev
		or opt_puppy_shootOnce and hasPuppy
	) then
		opts.ctrl = true
		opts.coded = opts.coded + CMD_OPT_CTRL
		override = true
	-- elseif hasOnlyAthena and cmd == CMD_RAW_MOVE and opts.ctrl then
	--     for i,id in ipairs(WG.selection or spGetSelectedUnits()) do
	--         spGiveOrderToUnit(id,CMD_WANTED_SPEED,{30},0)
	--     end
	--     -- return true
	elseif (
				opt_precise_gs_move and hasSmallSelection and hasGunship
		)
		and cmd == CMD_RAW_MOVE and not (opts.shift or opts.ctrl or opts.meta)
	then 
		if not params[4] then-- force a more precise move, especially for gs that refuse to move to a close destination
			params[4], params[5] = 16, 1 -- (min distance to consider the goal reached, timeout?)
			override = true
		end
	elseif (
				opt_precise_plane_move and hasPlane
		)
		and cmd == CMD_RAW_MOVE and not (opts.shift or opts.ctrl or opts.meta)
	then 
		if not params[4] then-- force a more precise move, especially for gs that refuse to move to a close destination
			params[4], params[5] = 96, 1 -- (min distance to consider the goal reached, timeout?)
			override = true
		end
	end
	if override then
		if giveOrder then
			spGiveOrder(cmd, params,opts)
		end
		return params, opts
	end
end
local Process = Process
function widget:CommandNotify(cmd, params, opts)
	if Process(cmd, params, opts, true) then
		return true
	end
end

function widget:UnitCommandNotify(id, cmd, params, opts)
	if newSequence then
		ovParams, ovOpts =  Process(cmd, params, opts, false)
		newSequence = false
	end
	if ovParams then
		if ovParams[4] then
			params[4], params[5] = ovParams[4], ovParams[5]
		end
		spGiveOrderToUnit(id, cmd, params, ovOpts.coded)
		return true
	end
end

function widget:Update()
	if not newSequence then
		newSequence, ovParams, ovOpts = true, false, false
	end
end

function widget:Initialize()
	if not widget:Requires(requirements) then
		return
	end
	mySelection = WG.mySelection
	widget:CommandsChanged()
end

