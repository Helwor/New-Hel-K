do local skip = VFS.Include("LuaUI/Widgets/Include/helk_core/game_check.lua", nil, VFS.RAW_FIRST).Widget("LuaUI/Widgets/gui_api_draw_before_chili.lua", getfenv(), "LuaUI/cawidgets.lua", "LuaRules/Configs/customcmds.h.lua") if skip then return unpack(skip, 1, skip.n) end end -- Hel-K game check
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

f.DebugWidget(widget)