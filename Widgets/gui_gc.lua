--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- requires MyZones.lua
-- requires -OnWidgetState.lua
function widget:GetInfo()
  return {
    name      = "GC",
    desc      = "Garbage Collector visualization and control",
    author    = "Helwor",
    date      = "Jan, 2024",
    license   = "GPLv2",
    layer     = 3,
    enabled   = false  --  loaded by default?
  }
end



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local Echo = Spring.Echo
local f = WG.utilFuncs




local useMemLimit = false
local memLimit = 500


local glColor = gl.Color
local fhDraw = fontHandler.Draw
local font = "LuaUI/Fonts/FreeSansBold_14"
local UseFont = fontHandler.UseFont
local vsx,vsy

local UPDATE_RATE = 3
local TRY_RATE = 7
local clock = os.clock
local lastTime, lastTry = 0, 0
local curUsage, gcLimit = gcinfo()
local width, height
--https://gamedevacademy.org/lua-garbage-collection-tutorial-complete-guide/
--https://www.tutorialspoint.com/lua/lua_garbage_collection.htm
local now = clock()
local offy = -46 -- from top of the screen

options_path = 'Tweakings/' .. widget:GetInfo().name
options = {}
options_order = {'use_mem_limit','mem_limit'}
options.use_mem_limit = {
    name = 'Auto Collect',
    type = 'bool',
    value = useMemLimit,
    OnChange = function(self)
        useMemLimit = self.value
    end,
    children = {'mem_limit'},
}

options.mem_limit = {
    name = 'Max MB before collecting',
    type = 'number',
    value = memLimit,
    min = memLimit/5, max = memLimit * 5, step = memLimit/100,
    OnChange = function(self)
        memLimit = self.value
    end,
    parents = {'use_mem_limit'},
}

-- for k,v in pairs(Spring) do
--     if k:lower():match('draw') and k:lower():match('set') then
--         Echo(k,v)
--     end
-- end
-- for _,id in ipairs(Spring.GetTeamUnits(2)) do
--     -- Spring.SetUnitNoEngineDraw(id,true)
--     Spring.SetUnitNoDraw(id,true)
-- end

-- function widget:DrawWorldPreUnit()
--     local count = 0
--     -- for _,id in ipairs(Spring.GetAllUnits()) do
--         -- Spring.SetUnitNoEngineDraw(id,true)
--         -- count = count + 1
--         -- Spring.SetUnitNoDraw(id,true)
--     -- end
--     -- Echo("Spring.GetGameState() is ", Spring.GetGameState())
-- end
-- for i, v in pairs(Spring.GetUICommands()) do
--     Echo('/' .. v.command .. ': ' .. v.description)
-- end
-- Echo("UnitDefs[408].buildeeBuildRadius is ", UnitDefs[408].buildeeBuildRadius,UnitDefs[408].metalCost)
-- for defID, def in pairs(UnitDefs) do
--     if def.corpse then
--         Echo('GOT IT')
--     end
-- end
function widget:DrawScreen()
    -- gl.DepthTest(false)
    -- Echo("Spring.IsUnitInView(12108) is ", Spring.IsUnitInView(12108), Spring.Utilities.IsUnitTyped)
    glColor(1,1,0,0.8) -- yellow
    UseFont(font)
    local now = clock()
    if now - lastTime > UPDATE_RATE then
    	lastTime = now
    	curUsage, gcLimit = gcinfo()
    end
    if useMemLimit then
        if curUsage > (memLimit*1024) then
            if now - lastTry > TRY_RATE then
                lastTry = now
                local before = collectgarbage('count')
                collectgarbage('collect')
                curUsage = collectgarbage('count')
                Echo(('Auto collected %.2f MB ...'):format((before - curUsage) / 1024))
            end
        end
    end
    fhDraw( ("%.2f MB"):format(curUsage / 1024), math.floor(vsx - width - 2 + 0.5), math.floor(vsy + offy + 0.5))
    glColor(1,1,1,1)
end

function widget:ViewResize(new_vsx,new_vsy)
    vsx, vsy = new_vsx, new_vsy
end
local spGetConfigInt = Spring.GetConfigInt
local spSetConfigInt = Spring.SetConfigInt
function widget:Initialize()
	widget:ViewResize(Spring.Orig.GetViewSizes())

	if WG.MyZones then
        -- Echo('done')
        local testFont = WG.Chili.Font:New({name = font, size = 14})
        local testString= ("%.1f MB"):format(555.5)
        width, height = testFont:GetTextWidth(testString), testFont:GetTextHeight(testString)
        testFont:Dispose()
        testFont = nil

		WG.MyZones[widget] = {
			{
				x = vsx - width - 2,
				y = vsy + offy ,
				x2 = vsx + 1,
				y2 = vsy + offy + height + 1,
			},
            callback = function()
                local before = collectgarbage('count')
                collectgarbage('collect')
                curUsage = collectgarbage('count')
                Echo(('Collected manually %.1fMB.'):format((before - curUsage) / 1024))

                return true
            end
		}
	end
end
function WidgetInitNotify(w, name)
	if name == 'MyZones' then
		widget:Initialize()
	end
end
function WidgetRemoveNotify(w, name)
	if name == 'MyZones' then
		widget:Shutdown()
	end
end
function widget:Shutdown()
	if WG.MyZones then
		WG.MyZones[widget] = nil
	end
end


