function widget:GetInfo()
    return {
        name      = 'API Screen Zones',
        desc      = 'Callin for screen interactions',
        author    = 'Helwor',
        date      = 'Winter, 2021',
        license   = 'GNU GPL, v2 or later',
        layer     = -1000001, -- after custom formation 2 to register upvalues of it, then Lowering in Initialize
        enabled   = true,
        handler   = true,
        api       = true,
    }
end
WG.MyZones = WG.MyZones or {}
local allzones = WG.MyZones

function widget:MousePress(mx,my,button)
    for w, zones in pairs(allzones) do
        for i, zone in ipairs(zones) do
            if mx > zone.x and mx < zone.x2 and my > zone.y and my < zone.y2 then
                local callback = zones.callback
                if callback then
                    if callback(zone, mx, my, button) then 
                        return true
                    end
                end
            end
        end
    end
end

function widget:Initialize()
    widgetHandler:LowerWidget(self)
end

function widget:Shutdown()
    for z in pairs(allzones) do
        allzones[z] = nil
    end
end
