function widget:GetInfo()
	return {
		name      = "Round CheckBox",
		desc      = "",
		author    = "Helwor",
		date      = "August 2024",
		license   = "GNU GPL, v2 or later",
		-- layer     = 2, -- after Unit Start State
		layer     = 0,
		enabled   = true,  --  loaded by default?
		-- api       = true,
		handler   = true,
	}
end
local Echo = Spring.Echo

local requirements = {
	value = {
		[ [[
			WG.Chili.Control.InvalidateSelf 		and VFS.FileExists(LUAUI_DIRNAME .. 'Widgets/chili/controls/object.lua', VFS.RAW)
			or not WG.Chili.Control.InvalidateSelf 	and VFS.FileExists(LUAUI_DIRNAME .. 'Widgets/chili_old/controls/object.lua', VFS.RAW)
		]] ] = {' local version of:\n '..WIDGET_DIRNAME..'chili_old/controls/object.lua or '.. WIDGET_DIRNAME ..'chili/controls/object.lua is required'}
	}
}


local function ChangeGraphicRoundCheck(round)
	local function ChangeSkinRoundCheck(arrow)
		local function getupvalue(func, searchName)
			local i, name, value = 0, true
			while name do
				i = i + 1
				name, value = debug.getupvalue(func, i)
				if name == searchName then
					return value
				end
			end
		end
		local GetSkin = getupvalue(WG.Chili.SkinHandler.LoadSkin, 'GetSkin')
		local skin = GetSkin(WG.Chili.theme.skin.general.skinName:lower())
		local checkbox = skin.checkbox
		if checkbox then
			if arrow then
				if checkbox.TileImageFG_round then
					if not checkbox.ori_TileImageFG_round then
						checkbox.ori_TileImageFG_round = checkbox.TileImageFG_round
						checkbox.TileImageFG_round = checkbox.TileImageFG
						-- Echo('changed round check mark to arrow')
						return checkbox.TileImageFG_round
					else
						-- Echo('already modified, nothing to change')		
						return false
					end
				else
					Echo('The skin you\'re using doesn\'t have round checkbox.')
					return false
				end
			elseif checkbox.ori_TileImageFG_round then
				checkbox.TileImageFG_round = checkbox.ori_TileImageFG_round
				checkbox.ori_TileImageFG_round = nil
				-- Echo('switched back default round check mark to default')
				return checkbox.TileImageFG_round
			else
				-- Echo('already set to original, nothing to change')
				return false
			end
		else
			-- Echo('your skin doesn\'t have checkbox o_O')
			return false
		end
	end
	
	local function UpdateCurrentObjects(TileImageFG_round)
		local checkfunc = function(parent, self)
			if self.classname:lower():find('checkbox') then
				self.TileImageFG_round = TileImageFG_round
				return true
			end
		end
		WG.Chili.Screen0:CallDescendantsInverseCheckFunc(checkfunc, 'Invalidate')
	end
	local function ChangeDefaultRoundBox(round)
		WG.Chili.Checkbox.round = round or nil
	end
	local TileImageFG_round = ChangeSkinRoundCheck(round) -- set round checkbox having checkmarks as the original, because it's neat
	if TileImageFG_round then
		UpdateCurrentObjects(TileImageFG_round)
		ChangeDefaultRoundBox(round)
		if not round then
			Echo('Reverted GUI original checkbox')
		else
			Echo('Applied new rounded checkbox to GUI')
		end
	end
end


local newValue
options = {}
options_path = 'Tweakings'
options.useRoundCheckbox = { 
	name = 'Use Round Checkbox',
	desc = 'Use rounded checkbox as default for GUI, but with the original checkmark.',
	type = 'bool',
	value = false,
	OnChange = function(self)
		if not WG.Chili then
			newValue = self.value
			widgetHandler:UpdateWidgetCallIn('Update', widget)
		else
			ChangeGraphicRoundCheck(self.value)
		end
	end,
	noHotkey = true,
}

function widget:Update()
	ChangeGraphicRoundCheck(newValue)
	widgetHandler:RemoveWidgetCallIn('Update', widget)
end
function widget:Shutdown()
	ChangeGraphicRoundCheck(false)
end
function widget:Initialize()
	if not widget:Requires(requirements) then
		return
	end
	widgetHandler:RemoveWidgetCallIn('Update', widget)
end
