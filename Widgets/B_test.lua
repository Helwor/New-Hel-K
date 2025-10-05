function widget:GetInfo()
    return {
        name      = "B_test",
        desc      = "",
        author    = "Helwor",
        date      = "Dec 2023",
        license   = "GNU GPL, v2 or later",
        layer     = 10e38,
        -- layer     = 2,
        enabled   = true,  --  loaded by default?
        api       = true,
        handler   = true,
    }
end


local Echo = Spring.Echo
-- local done = false
-- function widget:DrawWorldPreUnit()
--     if not done and Spring.IsUnitVisible(subjectID) then
--         Echo('IS VISIBLE IN PRE UNIT',Spring.IsUnitIcon(subjectID))
--         done = true
--     end
-- end

local testCalls = {
    'GameFrame',

    'Update',
    'DrawScreen',
    'DrawGenesis',
    'DrawWorld',
    'DrawWorldPreUnit',
    'DrawWorldPreParticles',
    'DrawWorldShadow',
    'DrawWorldReflection',
    'DrawWorldRefraction',
    'DrawUnitsPostDeferred',
    'DrawFeaturesPostDeferred',
    'DrawScreenEffects',
    'DrawScreenPost',
    'DrawInMiniMap',
    'DefaultCommand',

    'DrawOpaqueUnitsLua',
    'DrawOpaqueFeaturesLua',
    'DrawAlphaUnitsLua',
    'DrawAlphaFeaturesLua',
    'DrawShadowUnitsLua',
    'DrawShadowFeaturesLua',


}
-- order of triggered callins, gameframe can be processed multiple time then all the updating occur, or the reverse, if game frame is slower
-- DrawInMiniMap seems to be called every 7 draw cycles, all the rest is called everytime, the order is always the same
-- 1 => GameFrame
-- 2 => Update
-- 3 => DrawGenesis
-- 4 => DrawInMiniMap
-- 5 => DrawWorldShadow
-- 6 => DrawShadowUnitsLua
-- 7 => DrawShadowFeaturesLua
-- 8 => DrawWorldPreUnit
-- 9 => DrawOpaqueUnitsLua
-- 10 => DrawOpaqueFeaturesLua
-- 11 => DrawAlphaUnitsLua
-- 12 => DrawAlphaFeaturesLua
-- 13 => DrawAlphaUnitsLua
-- 14 => DrawAlphaFeaturesLua
-- 15 => DrawWorldPreParticles
-- 16 => DrawWorld
-- 17 => DrawScreenEffects
-- 18 => DrawScreen
-- 19 => DrawScreenPost


--------------------------------------------------------------------
local f = WG.utilFuncs
--------------------------------------------------------------------

local comptable = function(t, t2)
    local diff = {}
    local changed = false
    for k,v in pairs(t) do
        if t2[k] ~= v then
            diff[k] = v
            changed = true
        end
    end
    return next(diff) and diff
end

local Units = WG.Cam.Units
local spGetUnitLosState = Spring.GetUnitLosState
local spIsUnitInRadar = Spring.IsUnitInRadar
local UnitDefs = UnitDefs
-- function widget:RenderUnitDestroyed(id)
--     Echo('render unit destroyed',id)
-- end
-- function widget:UnitCreated(id)
--     Echo('unit created',id)
-- end
-- function widget:UnitEnteredRadar(id)
--     Echo('unit entered radar', id)
-- end
-- function widget:UnitLeftRadar(id,...)
--     Echo('unit left radar', id,...)
-- end
-- function widget:UnitDestroyedByTeam(id)
--     Echo('unit destroyed by team',id)
-- end
-- function widget:UnitDestroyed(id)
--     Echo('unit destroyed',id)
-- end
-- function widget:UnitLeftLos(id)
--     local losState = Spring.GetUnitLosState(id)
--     Echo('B_TEST','unit' .. id .. 'left los',(losState and losState.radar))
-- end


--  * @function Spring.GetTeamInfo
--  * @number teamID
--  * @bool[opt=true] getTeamKeys whether to return the customTeamKeys table
--  * @treturn nil|number teamID
--  * @treturn number leader
--  * @treturn number isDead
--  * @treturn number hasAI
--  * @treturn string side
--  * @treturn number allyTeam
--  * @treturn number incomeMultiplier
--  * @treturn {[string]=string,...} customTeamKeys when getTeamKeys is true, otherwise nil

function widget:DrawScreen()
    -- local x,y,z = Spring.GetUnitPosition(12590)
    -- local x,y,z,_
    -- local unit = WG.Cam.Units[15608]
    -- if unit then
    --     _,_,_,x,y,z = unit:GetPos(1)
    -- end
    -- local x,y,z = WG.Cam.Units[19401]:GetPos(1)
    if x then
        gl.Color(1,1,1,1)
        x,y = Spring.WorldToScreenCoords(x,y,z)
        gl.Utilities.DrawScreenDisc(x,y, 10)
    end
end



-- function widget:UnitLeftRadar(id)
--     if id == WG.X then
--         Echo('unit',id, 'left radar in B_TEST')
--     end
-- end


-- GetLocalsOf= function(level,searchname, searchvalue)
--     local i = 1
--     local getlocal = debug.getlocal
--     if searchname or searchvalue ~= nil then
--         while true do
--             local name, value = getlocal(level+1, i)
--             if not name then break end
--             if not searchname or searchname == name then
--                 if searchvalue == nil or searchvalue == value then
--                     return i, name, value
--                 end
--             end
--             i = i + 1
--         end
--         return
--     end
--     local T, indexes = {}, {}
--     while true do
--         local name, value = getlocal(level+1, i)
--         if not name then break end
--         T[name]=value
--         indexes[name]=i
--         i = i + 1
--     end
--     return T,indexes
-- end
-- GetWidgetInfos =function() 
--     local getinfo = debug.getinfo
--     local wid
--     for i=1,13 do
--         local info = getinfo(i)
--         if info.name and info.name:match("LoadWidget") then
--             local locals=GetLocalsOf(i)

--             if locals.text and locals.widget and locals.filename then
--                 wid={
--                     code=locals.text,               
--                     handler=locals.self,
--                     wid=locals.widget,
--                     filename=locals.filename,
--                     basename = locals.basename,
--                     source=getinfo(i).source, -- actually it's a long src
--                     [getinfo(i).source]=true,
--                     name = locals.basename,
--                     nicename = locals.widget.GetInfo and locals.widget:GetInfo().name or locals.basename -- if the chunk had error, we won't get the nice name
--                 }
--                 break
--             end

--         end
--     end
--     if not wid then
--         -- local wenv = getfenv()
--         -- if wenv ~= getfenv(debug.getinfo(1)) then
--         --     Echo('ok')
--         -- end
--         Echo('ERROR, couldnt find the wid source')
--         return
--         -- wid={name='unknown',code=''}
--     end
--     --- now registering funcs---
--     -- adding current environment's function (utilfuncs)
--     local utilfuncs={}  
--     local source=debug.getinfo(1).source    
--     if source~=wid.source then
--         utilfuncs[source]=true
--         for k,v in pairs(getfenv(1)) do -- get global functions in here
--             if type(v)=="function" then
--                 defined=debug.getinfo(v).linedefined
--                 utilfuncs[k]=defined
--                 utilfuncs[defined]=k
--             end
--         end
--     end
--     wid.utilfuncs=utilfuncs


--     -- adding callins and main function by scanning the code
--     local callins,mainfuncs={},{}
--     local linecount=0
--     local code = f.UncommentCode(wid.code or '',false)

    
--     -- Spring.SetClipboard(code)
--     local word
    
--     -- matching function to find a word or wordA.wordB.wordC... within a given pattern (pattern before, pattern with dot or not, pattern after, occurrences)



--     local codelines={}
--     local commented
--     for line in code:gmatch('[^\n]+') do
--         linecount=linecount+1
--         --if linecount>32 and linecount<37 then
--         -- line,commented = line:purgecomment(commented)
--         --Echo(linecount..':'..line)
--         --end

--         codelines[linecount]=line
--         word = line:match("function%s-wid:".."([%a]+)",1)
--         if word then
--              callins[word]=linecount
--              callins[linecount]=word
--         else
--             local word = 
--                          line:matchOptDot('function%s-','[%a_]+',':([%a_]+)%(',1) or  -- syntax function A:b(
--                          line:matchOptDot('function%s-(','[%a_]+',')%s-%(',1) or
--                          line:matchOptDot('(','[%a_]+',')%s-=%s-%(-%s-function',1) -- syntax a = function( or a = (function(   NOTE:the latter might not be a function everytime
--             if word then
--              mainfuncs[word]=linecount
--              mainfuncs[linecount]=word
--             end
--         end
--     end

--     local comp_linecount = 0
--     local commented_code = wid.code
--     for line in commented_code:gmatch('[^\n]+') do
--         comp_linecount = comp_linecount + 1
--     end
    
--     wid.codelines = codelines
--     mainfuncs[wid.source]=wid.nicename
--     wid.callins=callins
--     wid.mainfuncs=mainfuncs

--     return wid
-- end
-- WG.GetWidgetInfos = GetWidgetInfos
-- Echo("WG.utilsFunc.GetWidgetInfos is ", WG.utilsFunc.GetWidgetInfos and WG.utilsFunc.GetWidgetInfos())

-- local wid = WG.utilFuncs and WG.utilFuncs.GetWidgetInfos and WG.utilFuncs.GetWidgetInfos()
-- Echo("wid.name is ", wid.name)
--------------------------------------------------------------------

local lists = {}


local texOpt = {
    -- target = GL_TEXTURE_2D,
    border = false,
    min_filter = GL.LINEAR,
    mag_filter = GL.LINEAR,
    wrap_s = GL.CLAMP_TO_EDGE,
    wrap_t = GL.CLAMP_TO_EDGE,
    -- format = GL.RGBA16F_ARB, -- transparency
    format = GL.DEPTH_COMPONENT32, -- no transparency
}
        -- min_filter = GL.NEAREST,
        -- mag_filter = GL.NEAREST,

        -- format = GL_DEPTH_COMPONENT32,
TEX = gl.CreateTexture(300,300, texOpt)

local function test()
    -- if not DONE_TEX then
    --     gl.GenTextures(1, "TEST");
    --     gl.BindTexture(GL.TEXTURE_2D, 'TEST');
    --     gl.TexImage2D(GL.TEXTURE_2D, 0, GL.RGBA, 1, 1, 0, GL.RGBA, GL.FLOAT, {1.0,0.0,0.0,1.0});
    --     DONE_TEX = true
    -- end
-- gl.Blending(false)
gl.Color(1,0,0,1)
  gl.Texture(0,TEX);
  -- gl.TexImage2D(GL.TEXTURE_2D, 0, GL.RGBA, 1, 1, 0, GL.RGBA, GL.FLOAT, {1.0,0.0,0.0,1.0});
  local _, vsy = gl.GetViewSizes()
  gl.TexRect(400,vsy - 100,600,vsy - 200,100,100,200,200);

  gl.Texture(0,false);
-- gl.Blending(false)
    -- if not TRY then
    --     gl.Color(1, 1, 1, 1)
    --     gl.Texture(0, 'TEST')
    --     gl.TexRect(100, 100, 200, 200)
    --     gl.Texture(0, false)
    -- end
gl.Color(1,1,1,1)
end

-- function widget:DrawScreen()
--     -- local mx,my = Spring.GetMouseState()
--     -- gl.Color(1,1,1,1)
--     -- local vsx, vsy = Spring.GetViewGeometry()
--     -- -- gl.Utilities.DrawScreenCircle(mx,my, 50)
--     -- -- gl.Utilities.DrawScreenCircle(vsx/2,vsy/2, 50)
--     -- -- gl.Utilities.DrawCircle(vsx/2,vsy/2, 50) -- HOW TO USE GLU DRAWCIRCLE
--     -- gl.LineWidth(20)
--     -- gl.Utilities.DrawCircle(mx,my, 500)
--     -- gl.Color(1,1,1,1)
--     -- gl.LineWidth(1)
--     -- Echo("pcall(test) is ", pcall(test))




--     -- test()
-- end

function widget:DrawWorld()
    -- local mx,my = Spring.GetMouseState()
    -- local nature, pos = Spring.TraceScreenRay(mx, my, true, false, true) -- onlyCoords, useMinimap, includeSky, ignoreWater
    -- if not pos then
    --     return
    -- end
    -- if nature == 'sky' then
    --     pos[1], pos[2], pos[3] = pos[4], pos[5], pos[6]
    -- end
    -- gl.Color(0,1,0,0.5)
    -- -- gl.Utilities.DrawGroundCircle(pos[1],pos[3], 50)
    -- -- gl.Utilities.DrawGroundDisc(pos[1], pos[3], 50)
    -- gl.Color(1,1,1,1)
end





--------------------------------------------------------------



function widget:Shutdown()

    if TEX then
        gl.DeleteTexture(TEX)
    end
end












--------------------------------------------------------------------



-- local WIDGET_DIRNAME = LUAUI_DIRNAME .. 'Widgets/'



-- Echo("VFS.FileExists(WIDGET_DIRNAME .. 'unit_shapes.lua', VFS.ZIP_ONLY) is ", VFS.FileExists(WIDGET_DIRNAME .. 'unit_shapes.lua', VFS.RAW_ONLY))
-- sortWidgets = function(w1, w2)
--     local l1 = w1.whInfo.layer
--     local l2 = w2.whInfo.layer
--     if (l1 ~= l2) then
--         return (l1 < l2)
--     end
--     local n1 = w1.whInfo.name
--     local n2 = w2.whInfo.name
--     local o1 = self.orderList[n1]
--     local o2 = self.orderList[n2]
--     if (o1 ~= o2) then
--         return (o1 < o2)
--     else
--         return (n1 < n2)
--     end
-- end



--------------------------------------------------------------------
-- local spGetTimer = Spring.GetTimer
-- local spDiffTimers = Spring.DiffTimers

-- local t1,t2 = {}, {}
-- local n = 7500
-- for i=1, n do
--     t1[i] = i
--     t2[i] = i
-- end
-- t2[n+1] = n + 1

-- local function test(t)
--     for i=1, n do
--         t[i] = nil
--     end

--     for i=1, n do
--         t[i] = i
--     end
-- end

-- local time2 = spGetTimer()
-- for i = 1, 100 do
--     test(t2)
-- end
-- time2 = spDiffTimers(spGetTimer(), time2)

-- local time1 = spGetTimer()
-- for i = 1, 100 do
--     test(t1)
-- end
-- time1 = spDiffTimers(spGetTimer(), time1)


-- Echo("time1, time2 is ", time1, time2)

--------------------------------------------------------------------

-- local test = function(command)
--     if (string.find(command, 'insertwidget') == 1) then
--         local basename, mode = unpack(command:sub(13):explode(' '))
--         if basename == '' then
--             Echo('No basename found in command')
--             return true
--         end
--         if not basename:find('%.lua$') then 
--             basename = basename .. '.lua'
--         end
--         local filename = WIDGET_DIRNAME ..basename
--         mode = mode and VFS[mode] or VFS.RAW_FIRST
--         local order
--         if basename and VFS.FileExists( filename, mode) then
--             for name, ki in pairs(widgetHandler.knownWidgets) do
--                 if (ki.basename == basename) then
--                     if ki.fromZip and (
--                         mode == VFS.RAW
--                         or mode == VFS.RAW_FIRST and VFS.FileExists( filename, VFS.RAW)
--                     )
--                     or (
--                         mode == VFS.ZIP
--                         or mode == VFS.ZIP_FIRST and VFS.FileExists( filename, VFS.ZIP)
--                     )
--                     then
--                         if ki.active then
--                             Echo('Removing current version of widget ' .. name .. ' to load it in the wanted VFS mode')
--                             -- widgetHandler:DisableWidget(name)
--                             for i, w in ipairs(widgetHandler.widgets) do
--                                 if ki.name == w.whInfo.name then
--                                     Echo('FOUND')
--                                     widgetHandler:RemoveWidget(w)
--                                 end
--                             end
                            
--                         end
--                         widgetHandler.knownWidgets[name] = nil
--                     else
--                         Echo('The wanted widget ' .. name .. ' is already known, enabling it.')
--                         widgetHandler:EnableWidget(name)
--                         return true
--                     end
--                 end
--             end
--             Echo('Inserting new widget',filename, mode)
--             local w = widgetHandler:LoadWidget(filename, mode)
--             if w then
--                 widgetHandler:InsertWidget(w)
--                 widgetHandler:SaveOrderList()
--             else
--                 Echo('couldnt load widget')
--             end
--             return true
--         else
--             Echo('requested file cannot be found',filename,mode, VFS.FileExists(filepath, mode))
--             return true
--         end
--     end

--     -- return oriConfigLayout(widgetHandler, command)
-- end
-- function widget:Initialize()
--     local command = 'insertwidget gui_persistent_build_spacing ZIP'
--     test(command)
-- end

f.DebugWidget(widget)