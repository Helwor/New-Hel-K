-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name      = "Draw Before Chili",
        desc      = "Lets widgets with layers above Chili do some of their drawing after Chili",
        author    = "Helwor, variant of gui_api_draw_after_chili.lua from Histidine (L.J. Lim)",
        date      = "Nov 2025",
        license   = "Public domain/CC0",
        handler   = true,
        layer     = 1001, -- Higher than api_chili.lua (drawing callins are executed in reverse order)
        enabled   = true,
        alwaysStart = true,
    }
end

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
local drawFuncs = {}

local function DrawBeforeChili(func)
  drawFuncs[#drawFuncs + 1] = func
end

function widget:DrawScreen()
    for i = #drawFuncs, 1, -1 do
        drawFuncs[i]()
        drawFuncs[i] = nil
    end
end

function widget:Initialize()
    WG.DrawBeforeChili = DrawBeforeChili
end

function widget:Shutdown()
    WG.DrawBeforeChili = nil
end
