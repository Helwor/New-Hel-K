do local skip = VFS.Include("LuaUI/Widgets/Include/helk_core/game_check.lua", nil, VFS.RAW_FIRST).Widget("LuaUI/Widgets/-helk_launcher.lua", getfenv(), "LuaUI/cawidgets.lua", "LuaRules/Configs/customcmds.h.lua") if skip then return unpack(skip, 1, skip.n) end end -- Hel-K game check
function widget:GetInfo()
    return {
        name    = "Hel-K Launcher",
        desc    = "Inject Hel-K system before other widgets load, file name must start with -",
        author  = "Helwor",
        date    = "2026",
        license = "GNU GPL v2 or later",
        layer   = -1,
        alwaysStart = true,
        enabled = true
    }
end

do
    if not WG.utilFuncs then
        if VFS.FileExists("LuaUI/Widgets/Include/helk_core.lua", VFS.RAW_FIRST) then
            VFS.Include("LuaUI/Widgets/Include/helk_core.lua", nil, VFS.RAW_FIRST)
        else
            Spring.Echo('[HEL-K]: FATAL ! HEL-K CORE NOT FOUND !')
        end

    end
end

return true