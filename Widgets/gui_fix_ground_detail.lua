function widget:GetInfo()
    return {
        name      = "Fix Ground Detail Update",
        desc      = 'Force update ground detail (tesselation) on zoom change, level of detail stay too high after zooming in then out',
        author    = "Helwor",
        date      = "Oct 2025 port from 2023's widget",
        license   = "GNU GPL, v2 or later",
        layer     = 1003, -- after COFC
        handler   = true,
        enabled   = true,
    }
end



local lastDist = 0
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local spForceTesselationUpdate = Spring.ForceTesselationUpdate
local abs = math.abs
local Cam

function widget:Update(dt)
    if WG.EzSelecting or not WG.panning and widgetHandler.mouseOwner then
        return
    end
    if abs(Cam.dist - lastDist) > lastDist * 0.05 then
        lastDist = Cam.dist
        -- local time = spGetTimer()
        spForceTesselationUpdate(true, true)
        -- time = spDiffTimers(spGetTimer(), time)
        -- if time > 0.15 then
        --     Echo('tesselation update took more than 0.15 sec',  ('%.2f'):format(time))
        -- end
    end
end

function widget:Initialize()
    Cam = WG.Cam
    if not Cam then
        Spring.Echo(widget:GetInfo().name .. ' require HasViewChanged')
        widgetHandler:RemoveWidget(self)
        return
    end
end

--  old version
-- local cnt= 0
-- local last_cs = spGetCameraState()
-- function widget:Update(dt)
--     cnt = cnt + dt

--     if cnt>=0.5 then
--         local cs = spGetCameraState()
--         if cs.mode==1 and cs.height ~= last_cs.height or cs.mode==4 and cs.py~=last_cs.py then
--             spSendCommands('GroundDetail ' .. Spring.GetConfigInt('GroundDetail')+1)
--             spSendCommands('GroundDetail ' .. Spring.GetConfigInt('GroundDetail'))
--         end
--         last_cs = cs
--         cnt=0
--     end
--     -- local dist,relDist = GetDistTarget()
--     -- Echo('DIST:', dist,relDist,('%.1f'):format(dist/relDist*100)..'%','ratio12K:'..('%.2f'):format(dist/12000 * 100)..'%')
-- end

-- another old workaround to update the tesselation
    -- function widget:Update(dt)
    --     if WG.EzSelecting or not WG.panning and widgetHandler.mouseOwner then
    --         return
    --     end
    --     if not recover then
    --         local cs = Cam.state
    --         -- if cs.mode==1 and cs.height ~= last_cs.height or cs.mode==4 and cs.py~=last_cs.py then

    --         if math.abs(Cam.dist - lastDist)>lastDist*0.05 then
    --             lastDist = Cam.dist
    --             -- -- Echo("cs.py-last_cs.py is ", cs.py-last_cs.py)
    --             -- -- Echo('WHEEL SET DETAIL',options.map_detail.value+1)
    --             -- local detail = AdaptDetail(options.map_detail.value-1, Cam.fov)
    --             -- -- Echo('set detail ',detail)
    --             local time = spGetTimer()
    --             -- spSendCommands('GroundDetail ' .. detail)
    --             -- time = spDiffTimers(spGetTimer(), time)
    --             Spring.ForceTesselationUpdate(true, true)
    --             if time > 0.15 then
    --                 Echo('tesselation update took more than 0.15 sec',  ('%.2f'):format(time))
    --                 -- Echo('set detail -1 took more than 0.15 sec',  ('%.2f'):format(time))
    --             end
    --             -- recover = true
    --             -- cnt = WG.panning and -0.2 or 0
    --         end
    --         last_cs = cs
    --     end
    --     if recover then
    --         -- if cnt>0.05 then
    --         if cnt>0.20 then
    --             local detail = AdaptDetail(options.map_detail.value, Cam.fov)
    --             -- Echo('UPDATE RECOVER DETAIL',detail,'(' .. options.map_detail.value .. ') fov:' .. Cam.fov)
    --             local time = spGetTimer()
    --             spSendCommands('GroundDetail ' .. detail)
    --             time = spDiffTimers(spGetTimer(), time)
    --             if time > 0.15 then
    --                 Echo('set detail 0 took more than 0.15 sec', ('%.2f'):format(time))
    --             end

    --             cnt = 0
    --             recover = false
    --         end
    --         cnt = cnt + dt
    --     end
    -- end
--

