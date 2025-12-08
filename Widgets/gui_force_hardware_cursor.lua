function widget:GetInfo()
    return {
        name      = "Force Hardware Cursor",
        desc      = "",
        author    = "Helwor",
        date      = "Dec 2025",
        license   = "Free domain",
        layer     = 0,
        enabled   = false,  --  loaded by default?
    }
end
function widget:Initialize()
    Spring.SetConfigInt('HardwareCursor', 1)
    Spring.SendCommands('HardwareCursor 1')
end