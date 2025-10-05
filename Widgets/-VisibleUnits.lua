function widget:GetInfo()
	return {
		name      = "VisibleUnits",
		desc      = "Register the visible/iconized unit",
		author    = "Helwor",
		date      = "May 2023",
		license   = "GNU GPL, v2 or later",
		layer     = 10e37,
		enabled   = true,  --  loaded by default?
		api		  = true,
	}
end

-- !!the layer is high because the order in which widget are called during drawing like DrawWorldPreUnit is reversed
-- !!it is at DrawWorldPreUnit that we can tell if a unit is really iconized or not

local Echo = Spring.Echo
local spIsUnitVisible = Spring.IsUnitVisible
local spIsUnitInView = Spring.IsUnitInView
local spIsUnitIcon = Spring.IsUnitIcon
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

local spGetVisibleUnits = Spring.GetVisibleUnits
local _, _, origGetVisibleUnits = f.GetUpvaluesOf(Spring.GetVisibleUnits, 'GetVisibleUnits')

-- for k,v in pairs(t) do
-- 	Echo(k,v)
-- end
local Cam
local Visibles
local inSight
local Units


local UpdateVisibleUnits2

local useMethod = 'new'

options_path = 'Hel-K/' .. widget:GetInfo().name
options_order = {
	'useMethod',
}
options = {}
options.useMethod = {
	name = 'Method',
	type = 'radioButton',
	value = useMethod,
	items = {
		{key = 'ori2', 			name='Old method'},
		{key = 'new', 			name='New method'},
	},
	OnChange = function(self)
		if self.value == 'ori2' then
			UpdateVisibleUnits = NewUpdateVisibleUnitsTEST
		elseif self.value == 'new' then
			UpdateVisibleUnits = NewUpdateVisibleUnits2
		end
	end,
	dev = true,
}

local function clear()
	for _, t in pairs(Visibles) do
		for i in pairs(t) do
			t[i] = nil
		end
	end

end
local radius = nil

function Ori2UpdateVisibleUnits() -- this is faster
	-- if not Visibles.test then
	-- 	Visibles.test = {}
	-- end
	clear()

	local anyMap, not_iconsMap, iconsMap = Visibles.anyMap, Visibles.not_iconsMap, Visibles.iconsMap
	local n, n2, n3 = 0, 0, 0
	-- local undetectedIcons = 0
	-- local invalid, justDead, _invalid, _justDead, undetected = 0, 0, 0, 0, 0
	-- local justDeadGood = 0
	-- origGetVisibleUnits is cached and doesnt give 100% of the time the correct units, especially when switching spec view

	-- asking for visible units that are not icons
	for _, id in ipairs(origGetVisibleUnits(ALL_UNITS,radius,false)) do 
		if inSight[id] then
			not_iconsMap[id] = true
			-- if not inSight[id] then
			-- 	if spGetUnitIsDead(id) then
			-- 		justDeadGood = justDeadGood + 1
			-- 	elseif not spValidUnitID(id) then
			-- 		invalid = invalid +1
			-- 	else
			-- 		undetected = undetected + 1
			-- 		local unit = Units[id]
			-- 		local isInSight = unit and unit.isInSight

			-- 		local defID = spGetUnitDefID(id)
			-- 		local name = defID and UnitDefs[defID].name
			-- 		local team = defID and spGetUnitTeam(id)
			-- 		local isAllied = unit and unit.isAllied
			-- 		local isAllied2 = team and spAreTeamsAllied(myTeamID,team)
			-- 		local isMine = unit and unit.isMine or team == myTeamID
			-- 		local losState = defID and spGetUnitLosState(id)
			-- 		local isRealInSight = losState and losState.los
			-- 		Echo('visible unit not present in inSight ! unit?',unit,'isInSight?',isInSight,'isRealInSight?',isRealInSight,'currentFrame?',currentFrame,'sight checked frame?',unit and unit.sightCheckedFrame,'defID?',defID,'name?',name,'is allied?',isAllied,isAllied2)
			-- 	end
			-- elseif spGetUnitIsDead(id) then
			-- 	_justDead = _justDead + 1
			-- elseif not spValidUnitID(id) then
			-- 	_invalid = _invalid +1
			-- end
			-- if spIsUnitIcon(id) then
			-- 	undetectedIcons = undetectedIcons + 1
			-- end
		end
	end

	for _, id in ipairs(origGetVisibleUnits(ALL_UNITS,radius,true)) do -- 
		if inSight[id] then -- purge from  dead unit and invalidate
			anyMap[id] = true
			-- if not inSight[id] then
			-- 	if spGetUnitIsDead(id) then
			-- 		justDeadGood = justDeadGood + 1
			-- 	elseif not spValidUnitID(id) then
			-- 		invalid = invalid +1
			-- 	else
			-- 		undetected = undetected + 1
			-- 		local unit = Units[id]
			-- 		local isInSight = unit and unit.isInSight

			-- 		local defID = spGetUnitDefID(id)
			-- 		local name = defID and UnitDefs[defID].name
			-- 		local team = defID and spGetUnitTeam(id)
			-- 		local isMine = unit and unit.isMine
			-- 		local isAllied = unit and unit.isAllied
			-- 		local isAllied2 = team and spAreTeamsAllied(myTeamID,team)
					
			-- 		local losState = defID and spGetUnitLosState(id)
			-- 		local isRealInSight = losState and losState.los
			-- 		Echo('visible unit not present in inSight ! unit?',unit,'isInSight?',isInSight,'isRealInSight?',isRealInSight,'currentFrame?',currentFrame,'sight checked frame?',unit and unit.sightCheckedFrame,'defID?',defID,'name?',name,'is allied?',isAllied,isAllied2,'isMine?',isMine)
			-- 	end
			-- elseif spGetUnitIsDead(id) then
			-- 	_justDead = _justDead + 1
			-- elseif not spValidUnitID(id) then
			-- 	_invalid = _invalid +1
			-- end
			if not not_iconsMap[id] then
				iconsMap[id] = true
			end
			-- local x = spGetUnitViewPosition(id)
			-- if not x then
			-- 	Echo('Unit ', id, 'visible but no position !')
			-- end
		end

	end
	-- Echo('any:',#any,"#icons is ",  #icons,  'not icons',#not_icons,'undetectedIcons',undetectedIcons)
	-- any.frame, not_icons.frame, icons.frame = currentFrame, currentFrame, currentFrame

	-- if justDead > 0 then
	-- 	Echo('GetVisibleUnits reported ' .. justDead .. ' just dead units')
	-- end
	-- if invalid > 0 then
	-- 	Echo('GetVisibleUnits reported ' .. invalid .. ' invalid units  correctly detected by inSight')
	-- end
	-- if _justDead > 0 then
	-- 	Echo('GetVisibleUnits reported ' .. justDead .. ' just dead units NOT correctly detected by inSight')
	-- end
	-- if _invalid > 0 then
	-- 	Echo('GetVisibleUnits reported ' .. invalid .. ' invalid units  NOT correctly detected by inSight')
	-- end
	-- if undetected > 0 then
	-- 	Echo('inSight didnt detect ' .. undetected .. ' visible units !')
	-- end
	-- return any, not_icons, icons, anyMap, not_iconsMap, iconsMap
end

function AltUpdateVisibleUnits()
	clear()
	local anyMap, not_iconsMap, iconsMap  = Visibles.anyMap, Visibles.not_iconsMap, Visibles.iconsMap
	local n, n2, n3 = 0, 0, 0

	for id, unit in pairs(Units) do
		if spIsUnitVisible(id) then
			anyMap[id] = true
			if not spIsUnitIcon(id) then
				not_iconsMap[true] = true
			else
				iconsMap[id] = true
			end
		end
	end

	-- Echo("#any is ", #any)
	-- Echo('any:',#any,"#icons is ",  #icons,  'not icons',#not_icons)
	return any, not_icons, icons
end

function NewUpdateVisibleUnits() -- this is faster
	-- if not Visibles.test then
	-- 	Visibles.test = {}
	-- end
	clear()

	local anyMap, not_iconsMap, iconsMap = Visibles.anyMap, Visibles.not_iconsMap, Visibles.iconsMap
	-- origGetVisibleUnits is cached and doesnt give 100% of the time the correct units when icons just appear

	-- asking for visible units that are not icons
	for _, id in ipairs(origGetVisibleUnits(ALL_UNITS,radius,false)) do 
		if inSight[id] then
			if not spIsUnitIcon(id) then
				n2 = n2 + 1
				not_iconsMap[id] = true
				anyMap[id] = true
			end
		end
	end
	local no_rendered = n2 == 0
	for _, id in ipairs(origGetVisibleUnits(ALL_UNITS,radius,true)) do -- 
		if inSight[id] then -- purge from  dead unit and invalidate
			if no_rendered or not not_iconsMap[id] then
				iconsMap[id] = true
				anyMap[id] = true
			end
		-- else
		-- 	Echo('got missed',id,spIsUnitIcon(id))
		end

	end
	-- any.frame, not_icons.frame, icons.frame = currentFrame, currentFrame, currentFrame
	-- return any, not_icons, icons, anyMap, not_iconsMap, iconsMap
end
function NewUpdateVisibleUnitsTEST() -- this is faster
	-- if not Visibles.test then
	-- 	Visibles.test = {}
	-- end
	clear()

	local anyMap, not_iconsMap, iconsMap = Visibles.anyMap, Visibles.not_iconsMap, Visibles.iconsMap
	local n, n2, n3 = 0, 0, 0
	-- asking for visible units that are not icons
	for _, id in ipairs(origGetVisibleUnits(ALL_UNITS,radius,false)) do  -- this should be fast, when many units are on screen, player is zoomed out and none or few are usually not icons
		if inSight[id] then -- inSight should already be purged from dead units
		-- 	if not spIsUnitIcon(id) then
			not_iconsMap[id] = true
			anyMap[id] = true
			n2 = n2 + 1
		end
	end

	local no_rendered = n2 == 0
	-- asking for any visible unit on screen
	for _, id in ipairs(origGetVisibleUnits(ALL_UNITS,radius,true)) do -- 
		if Units[id] then -- purged from dead units
			n = n + 1
			if no_rendered or not not_iconsMap[id] then
				iconsMap[id] = true
				anyMap[id] = true
			end
		end

	end

	-- Echo('visible', 'not icons', n2, 'icons', n3, 'total', n)
	-- any.frame, not_icons.frame, icons.frame = currentFrame, currentFrame, currentFrame
	-- return any, not_icons, icons, anyMap, not_iconsMap, iconsMap
end
function NewUpdateVisibleUnits2()
	-- if not Visibles.test then
	-- 	Visibles.test = {}
	-- end
	clear()

	local anyMap, not_iconsMap, iconsMap = Visibles.anyMap, Visibles.not_iconsMap, Visibles.iconsMap
	local n, n2, n3 = 0, 0, 0

	for _, id in pairs(origGetVisibleUnits(ALL_UNITS, radius, true)) do
		if Units[id] then
			anyMap[id] = true
			if spIsUnitIcon(id) then
				iconsMap[id] = true
			else
				not_iconsMap[id] = true
			end
		end
	end
	return 
end
local compare = false
local done = false


function widget:DrawWorldPreUnit()
	if WG.requestUpdateVisibleUnits then
		WG.requestUpdateVisibleUnits = false
		UpdateVisibleUnits()
	end
	-- test Old vs New
	if compare and not done then
		local val = options.useMethod.value
		options.useMethod.value = 'old'
		options.useMethod:OnChange()
		local old = UpdateVisibleUnits
		options.useMethod.value = 'new'
		options.useMethod:OnChange()
		local new = UpdateVisibleUnits
		options.useMethod.value = val
		options.useMethod:OnChange()
		
		f.Benchmark(old, new, 500)
		old()
		local copy = {}
		for id in pairs(Visibles.iconsMap) do
			copy[id] = true
		end
		new()
		local missing = 0
		for id in pairs(Visibles.iconsMap) do
			if not copy[id] then
				missing = missing + 1
			end
		end
		missing = missing + math.abs(table.size(copy) - table.size(Visibles.iconsMap))
		Echo('missing', missing)
		done = true
	end
end



function widget:Initialize()
	Cam = WG.Cam
	Visibles = WG.Visibles

	inSight = Cam.inSight
	Units = Cam.Units
	options.useMethod:OnChange()
	WG.UpdateVisibleUnits = UpdateVisibleUnits
	WG.requestUpdateVisibleUnits = true
end


