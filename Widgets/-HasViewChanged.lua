function widget:GetInfo()
	return {
		name      = "HasViewChanged",
		desc      = "Tell if view may have changed to lessen Draw work and gives VisiblesUnits",
		author    = "Helwor",
		date      = "May 2023",
		license   = "GNU GPL, v2 or later",
		layer     = -10e37,
		enabled   = true,  --  loaded by default?
		api		  = true,
		handler   = true,
	}
end

--IMPORTANT NOTE: 
-- !! Update come before PreUnit, unit visible can be detected in update, BUT ICONIZED STATE IS DETECTED FIRST AT PRE UNIT
-- !! PreUnit order is reversed, widget having lower layer will NOT COME FIRST FOR THIS CALLIN
-- so we have to make another with high layer for registering iconized unit
-- !! Unit discovered directly by Los WILL TRIGGER ENTEREDRADAR AFTER
-- !! Unit STRUCTURE discovered By Los ONCE will be seen as static build icon when entering radar again, BUT THE DEFID CANNOT BE RETRIEVED
	-- to work around this when switching view as spec and determine if a unit structure has been discovered by the current ally team, we check the position of the supposed structure and see if its x and z are multiple of 8
-- aswell, if speccing,  it is not possible to know every building that has been discovered but now out of radar by an ally team X if it has not been watched all along	(FIX IMPLEMENT ACCESS FROM ENGINE)
-- FIXED Destroyed non ally in radar doesnt trigger anything unless my PR is approven
-- !! the currentFrame from GameFrame can be different from spGetGameFrame(), spGetGameFrame() can be more actual, while GameFrame callin has still not updated, we're not using spGetGameFrame() in here
-- !! enemy terra unit in radar can leave radar without any other sign of existence before (probably as soon as it is created)
-- !! Plop Fac trigger first UnitFinished then UnitCreated !
local Echo = Spring.Echo

local spIsUnitVisible = Spring.IsUnitVisible
local spIsUnitInView = Spring.IsUnitInView
local spIsUnitIcon = Spring.IsUnitIcon
local spGetVisibleUnits = Spring.GetVisibleUnits
local spGetCameraPosition = Spring.GetCameraPosition
local spGetCameraVectors = Spring.GetCameraVectors
local spGetCameraFOV = Spring.GetCameraFOV
local spGetGameFrame = Spring.GetGameFrame
local spGetCameraState = Spring.GetCameraState
local spTraceScreenRay = Spring.TraceScreenRay
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGetSpectatingState = Spring.GetSpectatingState
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitLosState = Spring.GetUnitLosState
local spGetGlobalLos = Spring.GetGlobalLos
local spGetLocalAllyTeamID = Spring.GetLocalAllyTeamID
local spGetMyTeamID = Spring.GetMyTeamID
local spAreTeamsAllied = Spring.AreTeamsAllied
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitTeam = Spring.GetUnitTeam
local ALL_UNITS       = Spring.ALL_UNITS
local spGetMyAllyTeamID = Spring.GetMyAllyTeamID
local spGetUnitViewPosition = Spring.GetUnitViewPosition
local spGetUnitIsDead = Spring.GetUnitIsDead
local spValidUnitID = Spring.ValidUnitID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitBuildFacing = Spring.GetUnitBuildFacing

local f = WG.utilFuncs
local formatColumnInfolog = f.formatColumnInfolog

local osclock = os.clock

local myPlayerID = Spring.GetMyPlayerID()

local vsx, vsy = Spring.GetViewGeometry()

local currentFrame = spGetGameFrame()
local requestUpdate
local NewView
local Visibles
local Cam
local fullview, isSpec
local center_x, center_y = vsx/2, vsy/2 -1
local UpdateVisibleUnits, OriUpdateVisibleUnits, Ori2UpdateVisibleUnits, AltUpdateVisibleUnits, NewUpdateVisibleUnits
local function HaveFullView()
	local spec, _fullview = spGetSpectatingState()
	local fullview = _fullview and 1 or spGetGlobalLos(spGetLocalAllyTeamID()) and 2
	isSpec, Cam.isSpec = spec, spec
	return fullview, spec
end
local function DeepCompare(t,t2)
	for k,v in pairs(t) do
		local same = t2[k]==v or type(v)=='table' and DeepCompare(v,t2[k])
		if not same then
			return false
		end
	end
	return true
end
local function DeepCompareAndCopy(t,t2)
	local same = true
	for k,v in pairs(t2) do
		if type(v) == 'table' then
			if not DeepCompareAndCopy(t[k],v) then
				same = false
			end
		elseif t[k] ~= v then
			same = false
			t[k] = v
		end
	end
	return same
end

local function CompareVarargAndCopy(t, ...)
	local same = true
	for i = 1, select('#', ...) do
		local v = select(i, ...)
		if v ~= t[i] then
			same = false
			t[i] = v
		end
	end
	return same
end
--
local right
function CamOrientation() 
    local r1 = right[1]
    local r3 = right[3]
    local r1sq = r1^2

    if r1sq > 0.50 then -- south or north
        if r1 > 0 then
            -- Echo('N')
            return 1, 1, 'N'
        else
            -- Echo('S')
            return -1, -1, 'S'
        end
    else                -- east or west
        if r3 > 0 then
            -- Echo('E')
            return -1, 1, 'E'
        else
            -- Echo('W')
            return 1, -1, 'W'
        end
    end 
end
function CamOrientation8()
    local r1 = right[1]
    local r3 = right[3]
    local r1sq = r1^2
    if r1sq > 0.75 then     -- south or north
        if r1 > 0 then
            -- Echo('N')
            return 1, 1, 'N'
        else
            -- Echo('S')
            return -1, -1, 'S'
        end
    elseif r1sq < 0.25 then -- east or west
        if r3 > 0 then
            -- Echo('E')
            return -1, 1, 'E'
        else
            -- Echo('W')
            return 1, -1, 'W'
        end
    elseif r1 > 0 then      -- NE or NW
        if r3 > 0 then
            -- Echo('NE')
            return 0, 1, 'NE'
        else
            -- Echo('NW')
            return 1, 0, 'NW'
        end
    else                    -- SE or SW
        if r3 > 0 then
            -- Echo('SE')
            return -1, 0, 'SE'
        else
            -- Echo('SW')
            return 0, -1, 'SW'
        end
    end 
end
--
local function SafeTrace() -- FIX ME WINDOW RESIZED + NO GRABINPUT = NO POS
    local type,pos = spTraceScreenRay(center_x, center_y,true,false,true,true)
    if type=='sky' then
        for i=1,3 do
            pos[i], pos[i+3] = pos[i+3], nil
        end
    end
    return pos
end
-- Echo("#Spring.GetVisibleUnits(-1, nil, false) is ", #Spring.GetVisibleUnits(-1, nil, false), #spGetVisibleUnits(-1, nil, false) )
local GetDist = function()
    local cs = Cam.state
    local dist
    local mode = cs.mode
    if mode == 1 then
        dist = cs.height
    elseif mode == 2 then
    	dist = cs.dist
    else
        local pos =  Cam.trace
        dist = ((cs.px-pos[1])^2 + (cs.py-pos[2])^2 + (cs.pz-pos[3])^2)^0.5
    end
    return dist
end
-- each param is stored in unique table for widgets to keep around as local
local lag, lagref = 0, 0.033

WG.lag = WG.lag or {Spring.GetLastUpdateSeconds() or 0.033}
local lag = WG.lag
WG.NewView = WG.NewView or {0,0,0,0,0}
NewView = WG.NewView
WG.Visibles = WG.Visibles or {any = {},icons = {}, not_icons = {}, anyMap = {}, iconsMap = {}, not_iconsMap = {}}
WG.OutOfRadar = WG.OutOfRadar or {}
Visibles = WG.Visibles

WG.Cam  = WG.Cam or  {Units={}, inSight = {}}
Cam = WG.Cam
Cam.frame 	= spGetGameFrame()
if Cam.pos then
	CompareVarargAndCopy(Cam.pos, spGetCameraPosition())
else
	Cam.pos = {spGetCameraPosition()}
end
if Cam.vecs then
	DeepCompareAndCopy(Cam.vecs, spGetCameraVectors())
else
	Cam.vecs = spGetCameraVectors()
end
right = Cam.vecs.right
if Cam.dir4 then
	CompareVarargAndCopy(Cam.dir4, CamOrientation())
else
	Cam.dir4 = {CamOrientation()}
end
if Cam.dir8 then
	CompareVarargAndCopy(Cam.dir8, CamOrientation8())
else
	Cam.dir8 = {CamOrientation8()}
end


Cam.fov 	= spGetCameraFOV()
Cam.state 	= spGetCameraState()
Cam.trace 	= SafeTrace()
Cam.dist 	= GetDist()
Cam.fullview, Cam.isSpec = HaveFullView()
isSpec = Cam.isSpec
Cam.relDist = Cam.dist * (Cam.fov / 45)


local newParams = {frame = spGetGameFrame(), pos = spGetCameraPosition(), vecs = spGetCameraVectors(), fov = spGetCameraFOV()}




-- options.useMethod = {
-- 	name = 'Method',
-- 	type = 'radioButton',
-- 	value = useMethod,
-- 	items = {
-- 		{key = 'ori2', 			name='Ori2 method'},
-- 		{key = 'new', 			name='New method'},
-- 	},
-- 	OnChange = function(self)
-- 		if self.value == 'ori2' then
-- 			UpdateVisibleUnits = Ori2UpdateVisibleUnits
-- 		elseif self.value == 'new' then
-- 			UpdateVisibleUnits = NewUpdateVisibleUnits
-- 		end
-- 	end,
-- }
function widget:PlayerChanged(playerID) -- PlayerChanged also get triggered naturally when switching fullview as spectator
	if myPlayerID ~= playerID then
		return
	end

	local oldfullview = fullview
	local newfullview = HaveFullView()
	if newfullview ~= oldfullview then
		-- Echo('fullview has changed in PlayerChanged, now',newfullview)
		fullview = newfullview
		requestUpdate = true
		Cam.fullview = fullview
	end
end

local HasViewChanged = function()
	local frame, pos, vecs, fov = currentFrame, nil, spGetCameraVectors(), spGetCameraFOV()
	local changed
	Cam.state = spGetCameraState()
	if frame~=Cam.frame then
		NewView[1] = NewView[1] + 1
		Cam.frame = frame
		changed = true
	end
	local needRetrace
	if not CompareVarargAndCopy(Cam.pos, spGetCameraPosition()) then
		NewView[2] = NewView[2] + 1
		changed = true
	end
	if not DeepCompareAndCopy(Cam.vecs, vecs) then
		CompareVarargAndCopy(Cam.dir4, CamOrientation())
		CompareVarargAndCopy(Cam.dir8, CamOrientation8())
		NewView[3] = NewView[3] + 1
		changed = true
	end
	if Cam.fov ~= fov then
		Cam.fov = fov
		NewView[4] = NewView[4] + 1
		changed = true
	end
	if changed then
		Cam.trace = SafeTrace()
		Cam.dist = GetDist()
		Cam.relDist = Cam.dist * (Cam.fov / 45)
	end
	local oldfullview = fullview
	local newfullview = HaveFullView()
	if oldfullview ~= newfullview then
		fullview = newfullview
		changed = true
		Cam.fullview = newfullview
	end
	if changed then
		NewView[5] = NewView[5] + 1
		return true
	end
end
---

function widget:DrawGenesis()
	if count then
		count = count + 1
		Echo('genesis',count)
	end
end

	
local lastCount = 0
local lagCounts = 10
local cnt, lags, total = 0, {}, 0
for i=1, lagCounts do lags[i] = 0 end

local lastFrame = spGetGameFrame()


local dt = 0
local update = false
function widget:Update(delta)

	dt = delta
	NOW = osclock()

	if count then
		count = count + 1
		Echo('update', count)
	end
	cnt = cnt +1
	if cnt > lagCounts then cnt = 1 end
	total = total - lags[cnt] + dt
	lags[cnt] = dt
	local avg = (total / lagCounts)
	lag[1] = math.max(1, avg / lagref )



	-- Echo("=>>>#Spring.GetVisibleUnits(-1, nil, false) is ", #Spring.GetVisibleUnits(-1, nil, false), #spGetVisibleUnits(-1, nil, false) )

	-- for i=1,5000000 do	i = i +1	end

	local newFrame = currentFrame ~= Cam.frame
	update = HasViewChanged()
	if not update and requestUpdate then
		NewView[5] = NewView[5] + 1
		update = true
	end
	if update then
		WG.requestUpdateVisibleUnits = true
	end
end

function widget:GameFrame(f)
	currentFrame = f
end

function widget:Initialize()
	-- options.useMethod:OnChange()

	-- this could be when the icons are generated, but the gadget doesnt send the information ...
  	-- widgetHandler:RegisterGlobal(widget, "buildicon_unitcreated", buildicon_unitcreated)
  	-- Echo("Script.LuaUI('buildicon_unitcreated') is ", Script.LuaUI('buildicon_unitcreated'))

  	widget:PlayerChanged(myPlayerID)
	widget:ViewResized(Spring.GetViewGeometry())
	-- WG.UpdateVisibleUnits = UpdateVisibleUnits
	WG.requestUpdateVisibleUnits = true
end
function widget:Shutdown()
	-- if manager then
	-- 	manager:Renew()
	-- end
end

function widget:ViewResized(vsx, vsy)
	center_x, center_y = vsx/2, vsy/2 -1
	if HasViewChanged() then
		WG.requestUpdateVisibleUnits = true
		-- UpdateVisibleUnits()
	end
end
if DebugWidget then
	DebugWidget(widget)
end