function widget:GetInfo()
	return {
		name      = "Queue Targets",
		desc      = "[EXPERIMENTAL]\n Queue targets by inserting a Set Target order followed by a Death Wait order",
		author    = "Helwor",
		date      = "Dec 2023",
		license   = "GNU GPL, v2 or later",
		-- layer     = 2, -- after Unit Start State
		layer     = - math.huge,
		enabled   = false,  --  loaded by default?
		-- api       = true,
		handler   = true,
	}
end
local Echo           = Spring.Echo
local spGetUnitDefID = Spring.GetUnitDefID

local Echo = Spring.Echo
local sig = '['..widget:GetInfo().name..']: '

local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGiveOrder = Spring.GiveOrder
local CMD_UNIT_SET_TARGET = Spring.Utilities.CMD.UNIT_SET_TARGET
local CMD_UNIT_SET_TARGET_CIRCLE = Spring.Utilities.CMD.UNIT_SET_TARGET_CIRCLE
local CMD_OPT_INTERNAL = CMD.OPT_INTERNAL
local CMD_INSERT = CMD.INSERT
local CMD_OPT_ALT = CMD.OPT_ALT
local CMD_DEATHWAIT = CMD.DEATHWAIT
local CMD_WAITCODE_DEATH = CMD.WAITCODE_DEATH
local CMD_WAIT = CMD.WAIT
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spValidUnitID = Spring.ValidUnitID
local TARGET_NONE = 0
local TARGET_GROUND = 1
local TARGET_UNIT= 2

function widget:UnitCmdDone(id, defID, team, cmd, params, opts, tag)
	if cmd == CMD_UNIT_SET_TARGET and opts.internal and not params[2] then
		if select(3, spGetUnitCurrentCommand(id)) == tag then -- the order has just been pushed
			return
		end
		if spValidUnitID(id) then
			spGiveOrderToUnit(id, CMD_UNIT_SET_TARGET, params[1], 0)
		end
	end
end


function widget:CommandNotify(cmd, params, opts)
	if cmd == CMD_UNIT_SET_TARGET or cmd == CMD_UNIT_SET_TARGET_CIRCLE and opts.shift then
		local target = not params[2] and params[1]
		if target and opts.shift then
			local coded = opts.coded
			if coded % (CMD_OPT_INTERNAL*2) < CMD_OPT_INTERNAL then
				coded = coded + CMD_OPT_INTERNAL
			end
			-- we don't check every unit in selection, only the first for performance
			-- we don't insert if no current target, we give direct order
			local selected = (Spring.GetSelectedUnits() or {})[1]
			if selected then
				local current_target = spGetUnitRulesParam(selected,"target_type") == TARGET_UNIT and spGetUnitRulesParam(selected,"target_id")
				if current_target then
					if current_target ~= target then
						local cmd, _, _, p1 = spGetUnitCurrentCommand(selected)
						if cmd ~= CMD_WAIT or p1 ~= CMD_WAITCODE_DEATH then
							-- add a death wait command to the current
							spGiveOrder(CMD_DEATHWAIT, current_target, CMD.OPT_SHIFT)
						end
					end
				else
					-- we also set immediate target if none yet set
					spGiveOrder(CMD_UNIT_SET_TARGET, target, 0)
				end
				spGiveOrder(CMD_INSERT, {-1, CMD_UNIT_SET_TARGET, coded, target}, CMD_OPT_ALT)
				spGiveOrder(CMD_DEATHWAIT, target, CMD.OPT_SHIFT)
				return true
			end
		end
	end
end

