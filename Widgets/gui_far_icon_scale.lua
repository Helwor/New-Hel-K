function widget:GetInfo()
	return {
		name      = "Far Icon Scale",
		desc      = "Allow you to have bigger icons via the Spring setting \"IconsAsUI\" when very zoomed out\nAdapt to your convenience in the options"
					.."\nWARN 1 Engine bug: If you use the widget \"Infos On Icons\", some infos might not show if you draw only when unit is icon (for some reason units under 95% build progress are not considered as icon when using the mode IconsAsUI)"
					.."\nWARN 2 Engine bug: The mode IconsAsUI also leak some icons display out of radar range",
		author    = "Helwor",
		date      = "Apr 2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = false,  --  loaded by default?
		handler   = true,
	}
end
local on = false
local spSendCommands = Spring.SendCommands
local threshold = 6600
local scale = 1.43
local oriOn, oriScale, oriFadeVanish, oriFadeStart
options_path = 'Hel-K/' .. widget.GetInfo().name

options = {
	threshold = {
		name = 'Far Zoom Out Threshold',
		type = 'number',
		min = 4000, max = 15000, step = 100,
		value = threshold,
		update_on_the_fly = true,
		desc = 'Toggle the Spring Command IconsAsUI ON above this camera distance which allow use to have custom and fixed size of icon',
		OnChange = function(self)
			threshold = self.value
		end
	},
	scale = {
		name = 'Far Icon Scale',
		type = 'number',
		min = 1.0, max = 2.5, step = 0.01,
		update_on_the_fly = true,
		value = scale,
		OnChange = function(self)
			scale = self.value
			spSendCommands('IconScaleUI ' .. scale)
		end
	}
}

function widget:Update()
	if WG.Cam.relDist >= threshold then
		if not on then
			spSendCommands('IconsAsUI 1')
			on = true
		end
	elseif on then
		spSendCommands('IconsAsUI 0')
		on = false
	end
end
local wasFiltered
function widget:Initialize()
	local pro_console_widget = widgetHandler:FindWidget('Chili Pro Console')
	if pro_console_widget then
		local opt = pro_console_widget.options.filter_icons_as_ui
		if opt then
			wasFiltered = opt.value
			if not wasFiltered then
				opt.value = true
				opt:OnChange()
			end
		end
	end
	spSendCommands('IconFadeStart 0', 'IconFadeVanish 0', 'IconScaleUI ' .. scale)
end

function widget:Shutdown()
	spSendCommands('IconsAsUI 0')
	if not wasFiltered then
		local pro_console_widget = widgetHandler:FindWidget('Chili Pro Console')
		if pro_console_widget then
			local opt = pro_console_widget.options.filter_icons_as_ui
			if opt then
				opt.value = false
				opt:OnChange()
			end
		end
	end

end
