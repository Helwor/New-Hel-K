
function widget:GetInfo()
	return {
		name      = "Reclaim Field Highlight",
		desc      = "Highlights clusters of reclaimable material",
		author    = "ivand, refactored by esainane",
		date      = "2020",
		license   = "public",
		layer     = 0,
		enabled   = false  --  loaded by default?
	}
end
local debugging = false
VFS.Include("LuaRules/Configs/customcmds.h.lua")
local Benchmark = debugging and VFS.Include("LuaRules/Gadgets/Include/Benchmark.lua")
local benchmark = Benchmark and Benchmark.new()

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local minTexSize = 65 * 65 -- costly in memory to increase
local checkFrequency = 150
local knownFeatures = {}
local featureNeighborsMatrix = {}
local featuresUpdated = false
local clusterMetalUpdated = false
local forceUpdate = false

-- Options

local flashStrength = 0.0
local fontScaling = 25 / 40
local fontSizeMin = 70
local fontSizeMax = 250

local textParametersChanged = false
local PrepareTextures
local textAsTex = true
local atlasses = {}
local useAtlas = true
local methodUsed = 2

options_path = "Settings/Interface/Reclaim Highlight"
options_order = {
	'fastClusters',
	'textAsTex',
	'useAtlas',
	'showhighlight',
	'showAtPregame',
	'flashStrength',
	'fontSizeMin',
	'fontSizeMax',
	'fontScaling' 
}
local helk_path = 'Hel-K/' .. widget.GetInfo().name
options = {
	textAsTex = {
		type = 'bool',
		name = 'Text as Texture',
		desc = 'Improve Perf a lot',
		value = textAsTex,
		path = helk_path,
		OnChange = function(self)
			textParametersChanged = true
			textAsTex = self.value
		end,
	},
	useAtlas = {
		type = 'bool',
		name = 'Use Atlas',
		desc = 'Improve perf even more',
		value = useAtlas,
		path = helk_path,
		OnChange = function(self)
			textParametersChanged = true
			useAtlas = self.value
		end,
	},
	fastClusters = {
		name = 'Fast Small Clustering',
		desc = 'Improve perf a lot, don\'t aggregate cluster',
		type = 'bool',
		value = methodUsed,
		OnChange = function(self)
			methodUsed = self.value and WG.DBSCAN_cluster3 and 2 or 1
			forceUpdate = true
			for k,v in pairs(knownFeatures) do
				knownFeatures[k] = nil
			end
			for k,v in pairs(featureNeighborsMatrix) do
				featureNeighborsMatrix[k] = nil
			end
			widget:GameFrame(checkFrequency)
		end,
		path = helk_path,
	},

	showhighlight = {
		name = 'Show Field Summary',
		type = 'radioButton',
		value = 'constructors',
		items = {
			{key ='always', name='Always'},
			{key ='withecon', name='With the Economy Overlay'},
			{key ='constructors',  name='With Constructors Selected'},
			{key ='conorecon',  name='With Constructors or Overlay'},
			{key ='conandecon',  name='With Constructors and Overlay'},
			{key ='reclaiming',  name='When Reclaiming'},
		},
		noHotkey = true,
	},
	showAtPregame = {
		name = 'Show during Pre Game',
		type = 'bool',
		value = true,
		OnChange = function(self)
			if self.value and Spring.GetGameFrame() <= 0 and not next(knownFeatures) then
				widget:GameFrame(checkFrequency)
			end
		end,
		path = helk_path,
	},
	flashStrength = {
		name = "Field flashing strength",
		type = 'number',
		value = flashStrength,
		min = 0.0, max = 0.5, step = 0.05,
		desc = "How intensely the reclaim fields should pulse over time",
		OnChange = function()
			flashStrength = options.flashStrength.value
		end,
	},
	fontSizeMin = {
		name = "Minimum font size",
		type = 'number',
		value = fontSizeMin,
		min = 20, max = 150, step = 10,
		desc = "The smallest font size to use for the smallest reclaim fields",
		OnChange = function()
			fontSizeMin = options.fontSizeMin.value
			textParametersChanged = true
		end,
	},
	fontSizeMax = {
		name = "Maximum font size",
		type = 'number',
		value = fontSizeMax,
		min = 20, max = 300, step = 10,
		desc = "The largest font size to use for the largest reclaim fields",
		OnChange = function()
			fontSizeMax = options.fontSizeMax.value
			textParametersChanged = true
		end,
	},
	fontScaling = {
		name = "Font scaling factor",
		type = 'number',
		value = fontScaling,
		min = 0.2, max = 0.8, step = 0.025,
		desc = "How quickly the font size of the metal value display should grow with the size of the field",
		OnChange = function()
			fontScaling = options.fontScaling.value
			textParametersChanged = true
		end,
	}
}

local texFormat = {
	target = GL.TEXTURE_2D,
	format = GL.RGBA16,
	border = false,
	min_filter = GL.LINEAR,
	mag_filter = GL.LINEAR,
	wrap_s = GL.CLAMP_TO_EDGE,
	wrap_t = GL.CLAMP_TO_EDGE,
	fbo = true,
}

local function copy(t)
	local t2 = {}
	for k,v in pairs(t) do
		t2[k] = v
	end
	return t2
end
local function cross(p, q, r)
	return (q.z - p.z) * (r.x - q.x)
		 - (q.x - p.x) * (r.z - q.z)
end
local function JarvisMarch2(points, benchmark) -- ~= 20% faster
	if benchmark then
		benchmark:Enter("JarvisMarch")
	end
	-- We need at least 3 points
	local numPoints = #points
	if numPoints < 3 then return end

	-- Find the left,bottom-most point
	local lbMostPointIndex = 1
	local minpoint = points[1]
	local minx = minpoint.x
	local minz = minpoint.z
	for i = 2, numPoints do
		local point = points[i]
		local x, z = point.x, point.z
		if x < minx then
			lbMostPointIndex = i
		elseif x == minx and z < minz then
			lbMostPointIndex = i
			minx, minz = x, z
		end
	end

	local p = lbMostPointIndex
	local hull = {} -- The convex hull to be returned

	-- Process CCW from the left-most point to the start point
	local h = 0
	repeat
		-- Find the next point q such that (p, i, q) is CCW for all i
		local q = points[p + 1] and p + 1 or 1
		for i = 1, numPoints do
			--Checks if points p, q, r are oriented counter-clockwise
			if cross(points[p], points[i], points[q]) < 0 then
			-- if not DONE then
			-- 	Echo('q )> ' .. i .. ' ('.. p..','..i..','..q..')')
			-- end
				q = i
			end
		end
		h = h + 1
		-- if not DONE then
		-- 	Echo('#'..h..' => ' .. q)
		-- end
		hull[h] = points[q] -- Save q to the hull
		p = q  -- p is now q for the next iteration
	until (p == lbMostPointIndex)
	-- if not DONE then
	-- 	Echo('---------')
	-- 	DONE = true
	-- end

	if benchmark then
		benchmark:Leave("JarvisMarch")
	end
	return hull
end

local sortBottomLeft = function(a, b)
	return a.x == b.x and a.z > b.z or a.x > b.x
end
local tsort = table.sort
local function MonotoneChain2(points, benchmark) -- ~25% faster
	if benchmark then
		benchmark:Enter("MonotoneChain")
	end
	local numPoints = #points
	if numPoints < 3 then return end

	tsort(points, sortBottomLeft)

	local lower, l = {points[1], points[2]}, 2
	for i = 3, numPoints do
		while (l > 1 and cross(lower[l - 1], lower[l], points[i]) <= 0) do
			lower[l] = nil
			l = l - 1
		end
		l = l + 1
		lower[l] = points[i]
	end

	local upper, u = {points[numPoints], points[numPoints-1]}, 2
	for i = numPoints-2, 1, -1 do
		local pt = points[i]
		while (u > 1 and cross(upper[u - 1], upper[u], pt) <= 0) do
			upper[u] = nil
			u = u - 1
		end
		u = u + 1
		upper[u] = pt
	end
	upper[u] = nil
	u = u - 1
	lower[l] = nil
	l = l - 1
	for i, point in ipairs(lower) do
		u = u + 1
		upper[u] = point
	end

	if benchmark then
		benchmark:Leave("MonotoneChain")
	end
	return upper
end




--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Speedups

local glTexCoord			 = gl.TexCoord
local glTexture				 = gl.Texture
local glDeleteTexture		 = gl.DeleteTexture
local glAddAtlasTexture		 = gl.AddAtlasTexture
local glGetAtlasTexture		 = gl.GetAtlasTexture
local glDeleteTextureFBO	 = gl.DeleteTextureFBO
local glDeleteTextureAtlas	 = gl.DeleteTextureAtlas
local glScale				 = gl.Scale
local glBeginEnd			 = gl.BeginEnd
local glBlending			 = gl.Blending
local glCallList			 = gl.CallList
local glColor				 = gl.Color
local glCreateList			 = gl.CreateList
local glDeleteList			 = gl.DeleteList
local glDepthTest			 = gl.DepthTest
local glLineWidth			 = gl.LineWidth
local glPolygonMode			 = gl.PolygonMode
local glPopMatrix			 = gl.PopMatrix
local glPushMatrix			 = gl.PushMatrix
local glRotate				 = gl.Rotate
local glText				 = gl.Text
local glTranslate			 = gl.Translate
local glVertex				 = gl.Vertex
local spGetAllFeatures		 = Spring.GetAllFeatures
local spGetCameraPosition	 = Spring.GetCameraPosition
local spGetFeatureHeight	 = Spring.GetFeatureHeight
local spGetFeaturePosition	 = Spring.GetFeaturePosition
local spGetFeatureResources	 = Spring.GetFeatureResources
local spGetFeatureTeam		 = Spring.GetFeatureTeam
local spGetGaiaTeamID		 = Spring.GetGaiaTeamID
local spGetGameFrame		 = Spring.GetGameFrame
local spGetGroundHeight		 = Spring.GetGroundHeight
local spGetMyAllyTeamID		 = Spring.GetMyAllyTeamID
local spIsGUIHidden			 = Spring.IsGUIHidden
local spIsPosInLos			 = Spring.IsPosInLos
local spTraceScreenRay		 = Spring.TraceScreenRay
local spValidFeatureID		 = Spring.ValidFeatureID
local spGetActiveCommand	 = Spring.GetActiveCommand
local spGetActiveCmdDesc	 = Spring.GetActiveCmdDesc

local sqrt = math.sqrt

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Data

local screenx, screeny

local Optics = VFS.Include("LuaRules/Gadgets/Include/Optics.lua")
local ConvexHull = VFS.Include("LuaRules/Gadgets/Include/ConvexHull.lua")
-- Calculates the signed area
local gaiaTeamId = spGetGaiaTeamID()

local myAllyTeamID

local scanInterval = 1 * Game.gameSpeed
local scanForRemovalInterval = 10 * Game.gameSpeed --10 sec

local minDistance = 300
local minSqDistance = minDistance^2
local minPoints = 2
local minFeatureMetal = 8 --flea

local drawEnabled = true
local BASE_FONT_SIZE = 192


--local reclaimColor = (1.0, 0.2, 1.0, 0.7);
local reclaimColor = {1.0, 0.2, 1.0, 0.3}
local reclaimEdgeColor = {1.0, 0.2, 1.0, 0.5}
local E2M = 0 -- doesn't convert too well, plus would be inconsistent since trees aren't counted

local drawFeatureConvexHullSolidList
local drawFeatureConvexHullEdgeList
local drawFeatureClusterTextList
local textQuadList
local textAtlasQuadList
local cumDt = 0
local minDim = 100


local featureConvexHulls = {}
WG.clusteredFeatures = WG.clusteredFeatures or {}
local featureClusters = WG.clusteredFeatures
for k in pairs(featureClusters) do
	featureClusters[k] = nil
end


local font = gl.LoadFont("FreeSansBold.otf", BASE_FONT_SIZE, 0, 0)


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- State update

local function UpdateTeamAndAllyTeamID()
	myAllyTeamID = spGetMyAllyTeamID()
end

local function UpdateDrawEnabled()
	if spIsGUIHidden() then
		return false
	end
	local optShow = options.showhighlight.value
	if (optShow == 'always')
			or optShow == 'withecon' and WG.showeco
			or optShow == "constructors" and conSelected
			or optShow == 'conorecon' and (conSelected or WG.showeco)
			or optShow == 'conandecon' and (conSelected and WG.showeco)
			or options.showAtPregame.value and spGetGameFrame() <= 0 then
		return true
	end
	
	local currentCmd = spGetActiveCommand()
	if currentCmd then
		local activeCmdDesc = spGetActiveCmdDesc(currentCmd)
		return (activeCmdDesc and (activeCmdDesc.name == "Reclaim" or activeCmdDesc.name == "Resurrect"))
	end
	return false
end

function widget:SelectionChanged(units)
	if (WG.selectionEntirelyCons) then
		conSelected = true
	else
		conSelected = false
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Feature Tracking

local function UpdateFeatureNeighborsMatrix(fID, added, posChanged, removed)
	if methodUsed >1 then
		return
	end
	local fInfo = knownFeatures[fID]

	if added then
		featureNeighborsMatrix[fID] = {}
		for fID2, fInfo2 in pairs(knownFeatures) do
			if fID2 ~= fID then --don't include self into featureNeighborsMatrix[][]
				local sqDist = (fInfo.x - fInfo2.x)^2 + (fInfo.z - fInfo2.z)^2
				if sqDist <= minSqDistance then
					featureNeighborsMatrix[fID][fID2] = true
					featureNeighborsMatrix[fID2][fID] = true
				end
			end
		end
	end

	if removed then
		for fID2, _ in pairs(featureNeighborsMatrix[fID]) do
			featureNeighborsMatrix[fID2][fID] = nil
			featureNeighborsMatrix[fID][fID2] = nil
		end
	end

	if posChanged then
		UpdateFeatureNeighborsMatrix(fID, false, false, true) --remove
		UpdateFeatureNeighborsMatrix(fID, true, false, false) --add again
	end
end

local function UpdateFeatures(gf)
	if benchmark then
		benchmark:Enter("UpdateFeatures")
	end
	featuresUpdated = false
	clusterMetalUpdated = false
	if benchmark then
		benchmark:Enter("UpdateFeatures 1loop")
	end
	for _, fID in ipairs(spGetAllFeatures()) do
		local metal, _, energy = spGetFeatureResources(fID)
		metal = metal + energy * E2M
		local fInfo = knownFeatures[fID]
		if (not fInfo) and (metal >= minFeatureMetal) then --first time seen
			local f = {}
			f.lastScanned = gf

			local fx, _, fz = spGetFeaturePosition(fID)
			local fy = spGetGroundHeight(fx, fz)
			f.x = fx
			f.y = fy
			f.z = fz

			f.isGaia = (spGetFeatureTeam(fID) == gaiaTeamId)
			f.height = spGetFeatureHeight(fID)
			f.drawAlt = ((fy > 0 and fy) or 0) + f.height + 10

			f.metal = metal

			fInfo = f
			knownFeatures[fID] = fInfo
			UpdateFeatureNeighborsMatrix(fID, true, false, false)
			featuresUpdated = true
		elseif fInfo and gf - fInfo.lastScanned >= scanInterval then
			fInfo.lastScanned = gf

			local fx, _, fz = spGetFeaturePosition(fID)
			local fy = spGetGroundHeight(fx, fz)

			if fInfo.x ~= fx or fInfo.y ~= fy or fInfo.z ~= fz then
				fInfo.x = fx
				fInfo.y = fy
				fInfo.z = fz

				fInfo.drawAlt = ((fy > 0 and fy) or 0) + fInfo.height + 10
				UpdateFeatureNeighborsMatrix(fID, false, true, false)
				featuresUpdated = true
			end

			if fInfo.metal ~= metal then
				--Spring.Echo("fInfo.metal ~= metal", metal)
				if fInfo.clID then
					--Spring.Echo("fInfo.clID")
					local thisCluster = featureClusters[ fInfo.clID ]
					thisCluster.metal = thisCluster.metal - fInfo.metal
					if metal >= minFeatureMetal then
						thisCluster.metal = thisCluster.metal + metal
						fInfo.metal = metal
						--Spring.Echo("clusterMetalUpdated = true", thisCluster.metal)
						clusterMetalUpdated = true
					else
						UpdateFeatureNeighborsMatrix(fID, false, false, true)
						fInfo = nil
						knownFeatures[fID] = nil
						featuresUpdated = true
					end
				end
			end
		end
	end

	if benchmark then
		benchmark:Leave("UpdateFeatures 1loop")
		benchmark:Enter("UpdateFeatures 2loop")
	end

	for fID, fInfo in pairs(knownFeatures) do
		if fInfo.isGaia and spValidFeatureID(fID) == false then
			--Spring.Echo("fInfo.isGaia and spValidFeatureID(fID) == false")

			UpdateFeatureNeighborsMatrix(fID, false, false, true)
			fInfo = nil
			knownFeatures[fID] = nil
			featuresUpdated = true
		end

		if fInfo and gf - fInfo.lastScanned >= scanForRemovalInterval then --long time unseen features, maybe they were relcaimed or destroyed?
			local los = spIsPosInLos(fInfo.x, fInfo.y, fInfo.z, myAllyTeamID)
			if los then --this place has no feature, it's been moved or reclaimed or destroyed
				--Spring.Echo("this place has no feature, it's been moved or reclaimed or destroyed")

				UpdateFeatureNeighborsMatrix(fID, false, false, true)
				fInfo = nil
				knownFeatures[fID] = nil
				featuresUpdated = true
			end
		end

		if fInfo and featuresUpdated then
			knownFeatures[fID].clID = nil
		end
	end
	
	if benchmark then
		benchmark:Leave("UpdateFeatures 2loop")
		benchmark:Leave("UpdateFeatures")
	end
end

local spGetTimer,spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local huge = math.huge
local GroupClusters = function(clusters) -- not used/finished/needed yet, complement method 2 to gather clusters
	local mids
	for i = 1, clusters.n do
		local cluster = clusters[i]
		local cnt = cluster.n
		for j = 1, cnt do
			local obj = cluster[j]
			local  x, z = obj[2], obj[3]
			totalx, totalz = totalx + x, totalz + z
		end
		cluster.mid = {totalx/cnt, totalz/cnt}
	end
	for i = 1, clusters.n do
		local cluster = clusters[i]
		if cluster.n > 1 then
			--- . . .
		end
	end
end

local function ClusterizeFeatures()
	local time1, time2
	local debugCluster = true
	if methodUsed == 2 then
				-- error()
		local pointsTable = {}

		--Spring.Echo("#knownFeatures", #knownFeatures)
		if benchmark then
			benchmark:Enter('ClusterizeFeatures() M2')
			benchmark:Enter('ClusterizeFeatures() M2 - Collect')
		end
		local n = 0
		for fID, fInfo in pairs(knownFeatures) do
			n = n + 1
			local x, z = fInfo.x, fInfo.z
			pointsTable[n] = {
				fID, x, z,
				x = x,
				z = z,
				fID = fID,
			}
		end
		pointsTable.n = n 
		for k in pairs(featureClusters or {}) do
			featureClusters[k] = nil
		end
		if benchmark then
			benchmark:Leave('ClusterizeFeatures() M2 - Collect')
			benchmark:Enter('ClusterizeFeatures() M2 - WG.DBSCAN_cluster3')
		end

		local clusters = WG.DBSCAN_cluster3(pointsTable, minDistance, 1)
		for i=1, clusters.n do
			local cluster = clusters[i]
			local members = {}
			local metal = 0
			local xmin, xmax, zmin, zmax = huge, -huge, huge, -huge
			for j = 1, cluster.n do
				local obj = cluster[j]
				local fID, x, z = obj[1], obj[2], obj[3]
				members[j] = fID
				local fInfo = knownFeatures[fID]
				metal = metal + fInfo.metal
				if x < xmin then xmin = x end
				if x > xmax then xmax = x end
				if z < zmin then zmin = z end
				if z > zmax then zmax = z end
				fInfo.clID = i
			end
			featureClusters[i] = {
				members = members,
				metal = metal,
				xmin = xmin,
				xmax = xmax,
				zmin = zmin,
				zmax = zmax,
			}
		end
		if benchmark then
			benchmark:Leave('ClusterizeFeatures() M2 - WG.DBSCAN_cluster3')
			benchmark:Leave('ClusterizeFeatures() M2')
		end
	end
	if methodUsed == 1 then
		if debugCluster then
			time1 = spGetTimer()
		end

		if benchmark then
			benchmark:Enter("ClusterizeFeatures")
		end
		local pointsTable = {}
		local unclusteredPoints  = {}

		--Spring.Echo("#knownFeatures", #knownFeatures)
		local n = 0
		for fID, fInfo in pairs(knownFeatures) do
			n = n + 1
			pointsTable[n] = {
				x = fInfo.x,
				z = fInfo.z,
				fID = fID,
			}
			unclusteredPoints[fID] = true
		end

	--TableEcho(featureNeighborsMatrix, "featureNeighborsMatrix")
		local opticsObject = Optics.new(pointsTable, featureNeighborsMatrix, minPoints, benchmark)
		if benchmark then
			benchmark:Enter("opticsObject:Run()")
		end

		opticsObject:Run()
		
		if benchmark then
			benchmark:Leave("opticsObject:Run()")
			benchmark:Enter("opticsObject:Clusterize(minDistance)")
		end
		featureClusters = opticsObject:Clusterize(minDistance)
		if benchmark then
			benchmark:Leave("opticsObject:Clusterize(minDistance)")
		end
		if debugCluster then
			time1 = spDiffTimers(spGetTimer(),time1)
			time2 = spGetTimer()
		end

		--Spring.Echo("#featureClusters", #featureClusters)

		for i = 1, #featureClusters do
			local thisCluster = featureClusters[i]
			local xmin, xmax, zmin, zmax = huge, -huge, huge, -huge

			local metal = 0
			for j = 1, #thisCluster.members do
				local fID = thisCluster.members[j]
				local fInfo = knownFeatures[fID]
				local x, z = fInfo.x, fInfo.z
				if x < xmin then xmin = x end
				if x > xmax then xmax = x end
				if z < zmin then zmin = z end
				if z > zmax then zmax = z end

				metal = metal + fInfo.metal
				knownFeatures[fID].clID = i
				unclusteredPoints[fID] = nil
			end
			thisCluster.xmin = xmin
			thisCluster.xmax = xmax
			thisCluster.zmin = zmin
			thisCluster.zmax = zmax

			thisCluster.metal = metal
		end

		for fID, _ in pairs(unclusteredPoints) do --add Singlepoint featureClusters
			local fInfo = knownFeatures[fID]
			local thisCluster = {}

			thisCluster.members = {fID}
			thisCluster.metal = fInfo.metal

			thisCluster.xmin = fInfo.x
			thisCluster.xmax = fInfo.x
			thisCluster.zmin = fInfo.z
			thisCluster.zmax = fInfo.z

			featureClusters[#featureClusters + 1] = thisCluster
			knownFeatures[fID].clID = #featureClusters
		end

		if benchmark then
			benchmark:Leave("ClusterizeFeatures")
		end

	end
end
local function ClustersToConvexHull()
	if benchmark then
		benchmark:Enter("ClustersToConvexHull")
	end
	featureConvexHulls = {}
	--Spring.Echo("#featureClusters", #featureClusters)
	for fc = 1, #featureClusters do
		local clusterPoints = {}
		if benchmark then
			benchmark:Enter("ClustersToConvexHull 1st Part")
		end
		local n = 0
		local members = featureClusters[fc].members
		for fcm = 1, #members do
			local fID = members[fcm]
			local feature = knownFeatures[fID]
			n = n + 1
			clusterPoints[n] = {
				x = feature.x,
				y = feature.drawAlt,
				z = feature.z
			}
			--spMarkerAddPoint(knownFeatures[fID].x, 0, knownFeatures[fID].z, string.format("%i(%i)", fc, fcm))
		end
		if benchmark then
			benchmark:Leave("ClustersToConvexHull 1st Part")
		end
		
		--- TODO perform pruning as described in the article below, if convex hull algo will start to choke out
		-- http://mindthenerd.blogspot.ru/2012/05/fastest-convex-hull-algorithm-ever.html
		
		if benchmark then
			benchmark:Enter("ClustersToConvexHull 2nd Part")
		end
		local convexHull
		if clusterPoints[3] then
			--Spring.Echo("#clusterPoints >= 3")
			-- convexHull = ConvexHull.JarvisMarch(clusterPoints, benchmark)
			-- convexHull = ConvexHull.MonotoneChain(clusterPoints, benchmark) --twice faster
			convexHull = MonotoneChain2(clusterPoints, benchmark)
			-- convexHull = JarvisMarch2(clusterPoints, benchmark)
			-- JarvisMarch2(clusterPoints, benchmark)
			-- local jarvis = function()
			-- 	JarvisMarch(clusterPoints)
			-- end
			-- local monotone = function()
			-- 	MonotoneChain(clusterPoints)
			-- end
			-- local monotone2 = function()
			-- 	MonotoneChain2(clusterPoints)
			-- end
			-- local jarvis2 = function()
			-- 	JarvisMarch2(clusterPoints)
			-- end
			-- Echo(#clusterPoints .. ' points')
			-- f.Benchmark(jarvis, monotone, 150)
			-- f.Benchmark(jarvis, jarvis2, 150)
			-- f.Benchmark(jarvis2, monotone2, 150)
			-- f.Benchmark(monotone, monotone2, 150)
		else
			--Spring.Echo("not #clusterPoints >= 3")
			local thisCluster = featureClusters[fc]

			local xmin, xmax, zmin, zmax = thisCluster.xmin, thisCluster.xmax, thisCluster.zmin, thisCluster.zmax

			local dx, dz = xmax - xmin, zmax - zmin

			if dx < minDim then
				xmin = xmin - (minDim - dx) / 2
				xmax = xmax + (minDim - dx) / 2
			end

			if dz < minDim then
				zmin = zmin - (minDim - dz) / 2
				zmax = zmax + (minDim - dz) / 2
			end

			local height = clusterPoints[1].y
			if clusterPoints[2] then
				height = math.max(height, clusterPoints[2].y)
			end

			convexHull = {
				{x = xmin, y = height, z = zmin},
				{x = xmax, y = height, z = zmin},
				{x = xmax, y = height, z = zmax},
				{x = xmin, y = height, z = zmax},
			}
		end

		local cx, cz, cy = 0, 0, 0
		local n = #convexHull
		for i = 1, n do
			local convexHullPoint = convexHull[i]
			cx = cx + convexHullPoint.x
			cz = cz + convexHullPoint.z
			cy = math.max(cy, convexHullPoint.y)
		end

		if benchmark then
			benchmark:Leave("ClustersToConvexHull 2nd Part")
			benchmark:Enter("ClustersToConvexHull 3rd Part")
		end
		
		local totalArea = 0
		local pt1, pt2 = convexHull[1], convexHull[2]
		local x1, z1 = pt1.x, pt1.z
		local x2, z2 = pt2.x, pt2.z
		local a = sqrt((x2 - x1)^2 + (z2 - z1)^2)
		for i = 3, n do
			local pt3 = convexHull[i]
			--Heron formula to get triangle area
			local x3, z3  =  pt3.x, pt3.z
			local b = sqrt((x3 - x2)^2 + (z3 - z2)^2)
			local c = sqrt((x3 - x1)^2 + (z3 - z1)^2)
			local p = (a + b + c)/2 --half perimeter

			local triangleArea = sqrt(p * (p - a) * (p - b) * (p - c))
			totalArea = totalArea + triangleArea
			x2, z2 = x3, z3
			a = c
		end
		if benchmark then
			benchmark:Leave("ClustersToConvexHull 3rd Part")
		end
		
		convexHull.area = totalArea
		convexHull.center = {x = cx/n, z = cz/n, y = cy + 1}

		featureConvexHulls[fc] = convexHull


		--for i = 1, #convexHull do
		--	spMarkerAddPoint(convexHull[i].x, convexHull[i].y, convexHull[i].z, string.format("C%i(%i)", fc, i))
		--end

	end
	if benchmark then
		benchmark:Leave("ClustersToConvexHull")
	end
end

local function ColorMul(scalar, actionColor)
	return {scalar * actionColor[1], scalar * actionColor[2], scalar * actionColor[3], actionColor[4]}
end

local function formatK(metal)
	if metal < 1000 then
		return string.format("%.0f", metal) --exact number
	elseif metal < 10000 then
		return string.format("%.1fK", math.floor(metal / 100) / 10) --4.5K
	else
		return string.format("%.0fK", math.floor(metal / 1000)) --40K
	end
end

local function GetColorText(metal)
	local x100  = 100  / (100  + metal)
	local x1000 = 1000 / (1000 + metal)
	return 1 - x1000, x1000 - x100, x100
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

widget.TeamChanged = UpdateTeamAndAllyTeamID
widget.PlayerChanged = UpdateTeamAndAllyTeamID
widget.Playeradded = UpdateTeamAndAllyTeamID
widget.PlayerRemoved = UpdateTeamAndAllyTeamID
widget.TeamDied = UpdateTeamAndAllyTeamID

function widget:Initialize()
	Spring.Echo(widget.GetInfo().name .. " initialize.")

	UpdateTeamAndAllyTeamID()
	screenx, screeny = widgetHandler:GetViewSizes()
	widget:SelectionChanged()
	if options.showAtPregame.value then
		widget:GameFrame(checkFrequency)
	end
	options.fastClusters:OnChange()
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Drawing
local color
local cameraScale
local Vertices = setmetatable(
	{},
	{
		__index = function(self, num) 
			local t = {}
			for i = 1, num do
				t[i] = {v={}}
			end
			rawset(self, num, t)
			return t
		end
	}
 )

local function DrawHullVertices(hull)
	local t  = {}
	for j = 1, #hull do
		local h = hull[j]
		glVertex(h.x, h.y, h.z)
	end
end

local function DrawHullVertices2(hull)
	local len = #hull
	local verts = Vertices[len]
	for j = 1, len do
		local h = hull[j]
		local v = verts[j].v
		v[1], v[2], v[3] = h.x, h.y, h.z
	end
	return verts
end

local glShape = gl.Shape
local function DrawFeatureConvexHullSolid()
	glPolygonMode(GL.FRONT, GL.FILL)
	-- 	for i = 1, #featureConvexHulls do
	-- 		glBeginEnd(GL.TRIANGLE_FAN, DrawHullVertices, featureConvexHulls[i])
	-- 	end
	for i = 1, #featureConvexHulls do -- 2x faster
		glShape(GL.TRIANGLE_FAN, DrawHullVertices2(featureConvexHulls[i]))
	end




end

local function DrawFeatureConvexHullEdge()
	glPolygonMode(GL.FRONT, GL.LINE)
	-- for i = 1, #featureConvexHulls do
	-- 	glBeginEnd(GL.LINE_LOOP, DrawHullVertices, featureConvexHulls[i])
	-- end
	for i = 1, #featureConvexHulls do
		glShape(GL.LINE_LOOP, DrawHullVertices2(featureConvexHulls[i]))
	end
	glPolygonMode(GL.FRONT, GL.FILL)
end

-- Echo("oriSetCameraTarget == Spring.SetCameraTarget is ", oriSetCameraTarget == Spring.SetCameraTarget)
local function DrawFeatureClusterTextBUFFERED() -- SADLY CANT WORK ENGINE APPLY BILLBOARD WITH PRINTWORLD() WHICH WE DONT WANT
	local lastR, lastG, lastB

	glPushMatrix()
	gl.Rotate(-90, 1, 0, 0)
	gl.Translate(0, -Game.mapSizeZ, 0)
	-- glScale(1.1, 0, 0)

	-- glTranslate(0, -500, 0)
	-- glScale(1.5, 1, 1)

	local dx, dy, dz = Spring.GetCameraDirection()
	local cs = Spring.GetCameraState()
	-- local x, y, z = Spring.GetCameraPosition()
	local x, y, z = cs.px, cs.py, cs.pz
	-- oriSetCameraTarget(x+100, y, z, -1, dx, dy-0.5, dz)
	-- Spring.SetCameraOffset(0,0,0,0,-0.5,0)

	-- gl.Billboard()
	font:Begin()
	-- local viewMatrix = {gl.GetMatrixData("view")}
	-- local billboardMatrix = {gl.GetMatrixData("billboard")}
	-- Echo("unpack(viewMatrix) is ", unpack(viewMatrix))
	-- Echo("unpack(billboardMatrix) is ", unpack(billboardMatrix))
	-- local matrix = GetHorizontalBillboardMatrix()
	-- Echo("unpack(matrix) is ", unpack(matrix))

	-- 
	-- local viewMatrix = {gl.GetMatrixData(GL.MODELVIEW)}
	-- Echo("GL.MODELVIEW, viewMatrix is ", GL.MODELVIEW, unpack(viewMatrix))
	-- glScale(1, -1, 1)

	-- glRotate(-45, 1, 0, 0)
	-- gl.MultMatrix(billboardMatrix)
	-- gl.MultMatrix({0.99991131, 0.00583414, -0.0112321, 0, 0, 1, 0, 0, 0.01265691, -0.4599886, 0.88782781, 0, 0, 0, 0, 1})

	for i = 1, #featureConvexHulls do
		local hull = featureConvexHulls[i]
		-- glPushMatrix()
		-- gl.Rotate(45, 1, 0, 0 )
		-- gl.LoadIdentity()
		-- gl.Billboard()
		local center = hull.center
		-- glRotate(0, 0, 0, 0)

		-- glTranslate(center.x, center.y, center.z)
		-- local sx, sy, sz = Spring.WorldToScreenCoords(center.x, center.y, center.z)

		local fontSize = fontSizeMin * fontScaling
		local area = hull.area
		fontSize = sqrt(area) * fontSize / minDim
		if fontSize < fontSizeMin then
			fontSize = fontSizeMin
		elseif fontSize > fontSizeMax then
			fontSize = fontSizeMax
		end

		local metal = featureClusters[i].metal
		--Spring.Echo(metal)
		local metalText = formatK(metal)
		-- glScale(fontSize / BASE_FONT_SIZE, fontSize / BASE_FONT_SIZE, fontSize / BASE_FONT_SIZE)

		local r, g, b = GetColorText(metal)


		-- glColor(r, g, b, 1.0)
		-- glText(metalText, 0, 0, fontSize, "cv")
		-- font:Begin()
			if lastR ~= r or lastG ~= g or lastB ~= b then
				font:SetTextColor(r, g, b, 1.0)
				lastR, lastG, lastB = r, g, b
			end
			-- font:PrintWorld(metalText, center.x, center.y, center.z, fontSize, "cvB")
			-- font:Print(metalText, 0, 0, fontSize, "cvB")
			font:Print(metalText, center.x, center.z, fontSize, "cvB")

		-- font:End()
		-- glRotate(90, 1, 0, 0)
		-- glPopMatrix()
	end
	-- gl.Billboard()

	font:End()
	glPopMatrix()
	-- oriSetCameraTarget(x, y, z, 5, dx-0.5, dy-0.5, dz)
	-- Spring.SetCameraOffset(0,0,0,0,0,0)
end
local function CreateTextTexture(text, fontSize, hull, r, g, b)
	local mulX, mulY = font:GetTextWidth(text), font:GetTextHeight(text)
	local size = fontSize^2 / BASE_FONT_SIZE
	local texSizeX, texSizeY = mulX * size + 1, mulY * size + 1
	local texSize = texSizeX * texSizeY
	local scale

	if texSize < minTexSize then
		scale = sqrt(texSize / minTexSize)
		if scale > 0 then
			size = size * (1/scale)
			texSizeX, texSizeY = texSizeX * (1/scale), texSizeY * (1/scale)
		end
		-- Echo("scale is ", scale)
	end
	local tex = gl.CreateTexture(texSizeX, texSizeY, texFormat)
	-- Dessiner dans la texture
	gl.RenderToTexture(tex, function()
		-- gl.ColorMask(false, false, false, true)
		gl.Clear(GL.COLOR_BUFFER_BIT, r, g, b, 0) -- to avoid a black antialiasing around the text
		---- debug to see the texture size on screen
		-- gl.Color(0,0,0,0.5)
		-- gl.TexRect(-1,-1,1,1)
		----
		glScale(1/texSizeX, 1/(texSizeY), 1)
		font:SetTextColor(r, g, b, 1)
		font:Print(text, 0, 0, size*2 , "cv")

		------ same result but probably heavier
		-- gl.Clear(GL.COLOR_BUFFER_BIT, 0,0,0,0)
		-- gl.MatrixMode(GL.PROJECTION)
		-- gl.PushMatrix()
		-- gl.LoadIdentity()
		-- gl.Ortho(0, texSizeX, 0, texSizeY, -1, 1)
		-- gl.MatrixMode(GL.MODELVIEW)
		-- gl.PushMatrix()
		-- gl.LoadIdentity()
		-- ---- debug to see the texture size on screen
		-- -- gl.Color(0,0,0,0.5)
		-- -- gl.TexRect(0,0,texSizeX,texSizeY)
		-- ----
		-- font:SetTextColor(r, g, b, 1)
		-- font:Print(text, texSizeX/2, texSizeY/2, size, "cv")
		-- gl.PopMatrix()
		-- gl.MatrixMode(GL.PROJECTION)
		-- gl.PopMatrix()  
	end)
	-- local info = gl.TextureInfo(texName)
	return tex, texSizeX, texSizeY, scale
end
local tex_life = {}
local textures = {}

function PrepareTextures()
	-- for i, hull in ipairs(featureConvexHulls) do
	-- 	if hull.tex then
	-- 		glDeleteTextureFBO(hull.tex)
	-- 		glDeleteTexture(hull.tex)
	-- 		hull.tex = nil
	-- 	end
	-- end
	for texID, texObj in pairs(textures) do
		tex_life[texID] = false
		texObj.hulls = {}
	end

	for i = 1, #featureConvexHulls do
		local hull = featureConvexHulls[i]
		local center = hull.center
		local fontSize = fontSizeMin * fontScaling
		local area = hull.area
		fontSize = sqrt(area) * fontSize / minDim
		if fontSize < fontSizeMin then
			fontSize = fontSizeMin
		elseif fontSize > fontSizeMax then
			fontSize = fontSizeMax
		end

		local metal = featureClusters[i].metal
		local metalText = formatK(metal)
		local r, g, b = GetColorText(metal)
		local texID = table.concat({metalText, fontSize, r, g, b}, '-')
		local texObj = textures[texID]
		if not texObj then
			local tex, texSizeX, texSizeY, scale = CreateTextTexture(metalText, fontSize, hull, r, g, b)
			texObj = {texID = texID, tex = tex, texSizeX = texSizeX, texSizeY = texSizeY, scale = scale, hulls = {}}
			textures[texID] = texObj
		end
		texObj.hulls[hull] = true
		hull.texID = texID
		tex_life[texID] = true
	end

	for texID, alive in pairs(tex_life) do
		if not alive then
			local tex = textures[texID].tex
			glDeleteTextureFBO(tex)
			glDeleteTexture(tex)
			textures[texID] = nil
			tex_life[texID] = nil
		end
	end
end
local done = {}
local function CreateAtlas()
	for i, atlas in ipairs(atlasses) do
		glDeleteTextureAtlas(atlas.obj)
		atlasses[i] = nil
	end
	local n_tex = table.size(textures)
	if n_tex == 0 then
		return
	end
	local atlasMaxX = Spring.GetConfigInt("MaxTextureAtlasSizeX", 4096)
	local atlasMaxY = Spring.GetConfigInt("MaxTextureAtlasSizeY", 4096)
	local area =  0
	for i, texObj in pairs(textures) do
		area = area + texObj.texSizeX * texObj.texSizeY
	end
	local areaNeeded = math.ceil(area * 1.43) -- estimate it will be filled at 70%
	local tries = 0
	local texArray, a = {}, 0
	for _, texObj in pairs(textures) do
		a = a + 1
		texArray[a] = texObj
	end
	while n_tex > 0 do
		tries = tries + 1
		if tries > 40 then
			Echo('['..widget.GetInfo().name .. '] ' .. 'TOO MANY TRIES TO MAKE ATLASSES')
			useAtlas = false
			return false
		end
		local atlas_xsize, atlas_ysize = math.min(atlasMaxX, 2048), math.min(atlasMaxY, 2048)
		while atlas_xsize * atlas_ysize > areaNeeded do
			if (atlas_xsize/2) * atlas_ysize >= areaNeeded and atlas_xsize >= atlas_ysize and atlas_xsize > 512 then
				atlas_xsize = atlas_xsize/2
			elseif atlas_xsize * (atlas_ysize/2) >= areaNeeded and atlas_ysize >= atlas_xsize and atlas_ysize > 512 then
				atlas_ysize  = atlas_ysize/2
			else
				break
			end
		end

		local atlas = gl.CreateTextureAtlas(atlas_xsize, atlas_ysize, 2) --  0 (Legacy), 1 (Quadtree), 2 (Row)
		local n_atlas = #atlasses + 1
		local in_tex = 0
		local toFill = atlas_xsize * atlas_ysize
		local filled = 0
		local atlas_textures = {}

		for i = n_tex, 1, -1 do
			local texObj = texArray[i]
			local texName = texObj.tex
			local xsize, ysize = texObj.texSizeX, texObj.texSizeY
			-- if (xsize > atlas_xsize and xsize > atlas_ysize) or (ysize > atlas_xsize and ysize > atlas_ysize) then -- if they can be rotated ?
			if (xsize > atlas_xsize or ysize > atlas_ysize) then
				Echo('['..widget.GetInfo().name .. '] ' .. 'Texture ' .. texName, 'size', xsize, ysize, 'cannot fit in atlas of size', atlas_xsize, atlas_ysize)
				useAtlas = false
				return false
			end
			local area = (xsize * ysize) * 1.43
			if filled + area > toFill then
				break
			end
			atlas_textures[texObj.texID] = texObj
			filled = filled + area
			in_tex = in_tex + 1
			glAddAtlasTexture(atlas, texName)
		end
		if gl.FinalizeTextureAtlas(atlas) then
			areaNeeded = areaNeeded - filled
			atlasses[n_atlas] = {obj = atlas, num = in_tex, textures = atlas_textures}
			for i = n_tex, n_tex - in_tex + 1, -1 do
				local texObj = texArray[i]
				texObj.u1, texObj.u2, texObj.v1, texObj.v2 = glGetAtlasTexture(atlas, texObj.tex)
			end
			n_tex = n_tex - in_tex
			-- Echo('created atlas', n_atlas, 'size', atlas_xsize, atlas_ysize, 'textures in', in_tex)
		else
			areaNeeded = areaNeeded * 1.20
		end
	end
	-- for i, hull in ipairs(featureConvexHulls) do
	-- 	glDeleteTextureFBO(hull.tex)
	-- 	glDeleteTexture(hull.tex)
	-- end
	return true
end

local function DrawFeatureClusterText()
	local lastR, lastG, lastB
	for i = 1, #featureConvexHulls do
		local hull = featureConvexHulls[i]
		glPushMatrix()

		local center = hull.center

		glTranslate(center.x, center.y, center.z)
		glRotate(-90, 1, 0, 0)

		local fontSize = fontSizeMin * fontScaling
		local area = hull.area
		fontSize = sqrt(area) * fontSize / minDim
		if fontSize < fontSizeMin then
			fontSize = fontSizeMin
		elseif fontSize > fontSizeMax then
			fontSize = fontSizeMax
		end

		local metal = featureClusters[i].metal
		--Spring.Echo(metal)
		local metalText = formatK(metal)
		local r, g, b = GetColorText(metal)
		glScale(fontSize / BASE_FONT_SIZE, fontSize / BASE_FONT_SIZE, fontSize / BASE_FONT_SIZE)

		-- glColor(r, g, b, 1.0)
		-- glText(metalText, 0, 0, fontSize, "cv")
		-- font:Begin()
		
			font:SetTextColor(r, g, b, 1.0)
			font:Print(metalText, 0, 0, fontSize, "cv")
		-- font:End()
		-- gl.Texture(0, hull.tex)
		-- gl.TexRect(0,0,256,256)
		-- gl.Texture(0, false)
		glPopMatrix()
	end
end

local function DrawQuadsWithAtlas()
	glColor(1,1,1,1)

	local count = 0
	for i, atlas in ipairs(atlasses) do
		glTexture(0, atlas.obj)
		for texID, texObj in pairs(atlas.textures) do
			local u1, u2, v1, v2 = texObj.u1, texObj.u2, texObj.v1, texObj.v2
			local texSizeX, texSizeY = texObj.texSizeX, texObj.texSizeY
			local scale = texObj.scale
			for hull in pairs(texObj.hulls) do
				local center = hull.center
				glPushMatrix()
				if scale then -- texture has been scaled up to increase font detail
					glTranslate(center.x - (texSizeX/2) * scale, center.y, center.z + (texSizeY/2) * scale)
					glScale(scale, 1, scale)
				else
					glTranslate(center.x - texSizeX/2, center.y, center.z + texSizeY/2)
				end
				glRotate(-90, 1, 0, 0)
				glBeginEnd(GL.QUADS, function()
					glTexCoord(u1, v1)
					glVertex(0, 0, 0)
					glTexCoord(u2, v1)
					glVertex(texSizeX, 0, 0)
					glTexCoord(u2, v2)
					glVertex(texSizeX, texSizeY, 0)
					glTexCoord(u1, v2)
					glVertex(0, texSizeY, 0)
				end)
				glPopMatrix()
			end
		end
	end
	----- debug show the whole atlas
	-- glTexture(0, atlasses[1].obj)
	-- glPushMatrix()
	-- 	-- glRotate(-90, 1, 0, 0)
	-- 	glColor(1,1,1,1)
	-- 	glBeginEnd(GL.QUADS, function()
	-- 		glTexCoord(0, 0)
	-- 		glVertex(0, 1000, 2048)
	-- 		glTexCoord(1, 0)
	-- 		glVertex(2048, 1000, 2048)
	-- 		glTexCoord(1, 1)
	-- 		glVertex(2048, 3000, 2048)
	-- 		glTexCoord(0, 1)
	-- 		glVertex(0, 3000, 2048)
	-- 	end)
	-- glPopMatrix()
	-- glTexture(0, false)
end

local function DrawQuads()
	glColor(1,1,1,1)
	for texID, texObj in pairs(textures) do
		local u1, u2, v1, v2 = texObj.u1, texObj.u2, texObj.v1, texObj.v2
		local texSizeX, texSizeY = texObj.texSizeX, texObj.texSizeY
		local scale = texObj.scale
		glTexture(0, texObj.tex)
		for hull in pairs(texObj.hulls) do
			local center = hull.center
			glPushMatrix()
			if scale then
				glTranslate(center.x - (texSizeX/2) * scale, center.y, center.z + (texSizeY/2) * scale)
				glScale(scale, 1, scale)
			else
				glTranslate(center.x - texSizeX/2, center.y, center.z + texSizeY/2)
			end
			glRotate(-90, 1, 0, 0)
			glBeginEnd(GL.QUADS, function()
				glTexCoord(0, 0)
				glVertex(0, 0, 0)
				glTexCoord(1, 0)
				glVertex(texSizeX, 0, 0)
				glTexCoord(1, 1)
				glVertex(texSizeX, texSizeY, 0)
				glTexCoord(0, 1)
				glVertex(0, texSizeY, 0)
			end)
			glPopMatrix()
		end
		gl.Texture(0, false)
	end
end
local wasDisabled = true

function widget:Update(dt)
	cumDt = cumDt + dt
	local cx, cy, cz = spGetCameraPosition()

	local desc, w = spTraceScreenRay(screenx / 2, screeny / 2, true)
	if desc then
		local cameraDist = math.min( 8000, math.diag( cx-w[1], cy-w[2], cz-w[3] ) )
		cameraScale = sqrt((cameraDist / 600)) --number is an "optimal" view distance
	else
		cameraScale = 1.0
	end
	local isEnabled = UpdateDrawEnabled()
	wasDisabled = isEnabled and not drawEnabled
	drawEnabled = isEnabled

	local frame = spGetGameFrame()
	color = 0.5 + flashStrength * (frame % checkFrequency - checkFrequency)/(checkFrequency - 1)
	if color < 0 then
		color = 0
	end
	if color > 1 then
		color = 1
	end
end
function widget:GameFrame(frame)

	if not drawEnabled then
		return
	end
	local frameMod = frame % checkFrequency
	if frameMod ~= 0  and not wasDisabled then
		return
	end
	if benchmark then
		benchmark:Enter("GameFrame UpdateFeatures")
	end
	UpdateFeatures(frame)
	if featuresUpdated or (drawFeatureConvexHullSolidList == nil) or forceUpdate then
		forceUpdate = false
		ClusterizeFeatures()
		ClustersToConvexHull()
		
		if benchmark then
			benchmark:Enter("featuresUpdated or drawFeatureConvexHullSolidList == nil")
		end
		--Spring.Echo("featuresUpdated")
		if drawFeatureConvexHullSolidList then
			glDeleteList(drawFeatureConvexHullSolidList)
			drawFeatureConvexHullSolidList = nil
		end

		if drawFeatureConvexHullEdgeList then
			glDeleteList(drawFeatureConvexHullEdgeList)
			drawFeatureConvexHullEdgeList = nil
		end

		drawFeatureConvexHullSolidList = glCreateList(DrawFeatureConvexHullSolid)

		drawFeatureConvexHullEdgeList = glCreateList(DrawFeatureConvexHullEdge)
		if benchmark then
			benchmark:Leave("featuresUpdated or drawFeatureConvexHullSolidList == nil")
		end
	else
	end

	if textParametersChanged or featuresUpdated or clusterMetalUpdated or drawFeatureClusterTextList == nil then
		if benchmark then
			benchmark:Enter("featuresUpdated or clusterMetalUpdated or drawFeatureClusterTextList == nil")
		end
		--Spring.Echo("clusterMetalUpdated")
		if drawFeatureClusterTextList then
			glDeleteList(drawFeatureClusterTextList)
			drawFeatureClusterTextList = nil
		end
		drawFeatureClusterTextList = glCreateList(DrawFeatureClusterText)
		updateTextTextures = true
		textParametersChanged = false
		if benchmark then
			benchmark:Leave("featuresUpdated or clusterMetalUpdated or drawFeatureClusterTextList == nil")
		end
	end
	if benchmark then
		benchmark:Leave("GameFrame UpdateFeatures")
	end
end

function widget:ViewResize(viewSizeX, viewSizeY)
	screenx, screeny = widgetHandler:GetViewSizes()
end

function widget:DrawWorld()
	if not drawEnabled then
		return
	end
	glDepthTest(false)
	glDepthTest(true)
	if benchmark then
		benchmark:Enter('Draw - Solid Hulls')
	end
	glBlending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	if drawFeatureConvexHullSolidList then
		glColor(ColorMul(color, reclaimColor))
		glCallList(drawFeatureConvexHullSolidList)
		--DrawFeatureConvexHullSolid()
	end
	if benchmark then
		benchmark:Leave('Draw - Solid Hulls')
		benchmark:Enter('Draw - Edges')
	end

	if drawFeatureConvexHullEdgeList then
		glLineWidth(6.0 / cameraScale)
		glColor(ColorMul(color, reclaimEdgeColor))
		glCallList(drawFeatureConvexHullEdgeList)
		--DrawFeatureConvexHullEdge()
		glLineWidth(1.0)
	end
	if benchmark then
		benchmark:Leave('Draw - Edges')
	end		
	if updateTextTextures and textAsTex then
		if textAtlasQuadList then
			gl.DeleteList(textAtlasQuadList)
		end
		if textQuadList then
			gl.DeleteList(textQuadList)
		end
		if benchmark then
			benchmark:Enter('PrepareTextures()')
		end
		PrepareTextures()
		if benchmark then
			benchmark:Leave('PrepareTextures()')
		end
		if benchmark and useAtlas then
			benchmark:Enter('CreateAtlas()')
		end
		local haveAtlas = useAtlas and CreateAtlas()
		if benchmark and useAtlas then
			benchmark:Leave('CreateAtlas()')
		end
		if haveAtlas then
			if benchmark then
				benchmark:Enter('glCreateList(DrawQuadsWithAtlas)')
			end
			textAtlasQuadList = glCreateList(DrawQuadsWithAtlas)
			if benchmark then
				benchmark:Leave('glCreateList(DrawQuadsWithAtlas)')
			end
		else
			if benchmark then
				benchmark:Enter('glCreateList(DrawQuads)')
			end
			textQuadList = glCreateList(DrawQuads)
			if benchmark then
				benchmark:Leave('glCreateList(DrawQuads)')
			end
		end
		updateTextTextures = false
	end

	if textAsTex then
		if textAtlasQuadList and useAtlas and atlasses[1] then
			if benchmark then
				benchmark:Enter('Draw - glCallList(textAtlasQuadList)')
			end
			glCallList(textAtlasQuadList)
			if benchmark then
				benchmark:Leave('Draw - glCallList(textAtlasQuadList)')
			end

		elseif textQuadList then
			if benchmark then
				benchmark:Enter('Draw - glCallList(textQuadList)')
			end
			glCallList(textQuadList)
			if benchmark then
				benchmark:Leave('Draw - glCallList(textQuadList)')
			end
		end
	elseif drawFeatureClusterTextList then
		glCallList(drawFeatureClusterTextList)
	end

	glDepthTest(true)
end

function widget:Shutdown()
	if drawFeatureConvexHullSolidList then
		glDeleteList(drawFeatureConvexHullSolidList)
	end
	if drawFeatureConvexHullEdgeList then
		glDeleteList(drawFeatureConvexHullEdgeList)
	end
	if drawFeatureClusterTextList then
		glDeleteList(drawFeatureClusterTextList)
	end
	if textQuadList then
		glDeleteList(textQuadList)
	end
	if textAtlasQuadList then
		glDeleteList(textAtlasQuadList)
	end

	for _, texObj in pairs(textures) do
		glDeleteTextureFBO(texObj.tex)
		glDeleteTexture(texObj.tex)
	end
	for i, atlas in ipairs(atlasses) do
		glDeleteTextureAtlas(atlas.obj)
	end
	if benchmark then
		benchmark:PrintAllStat()
	end
	Echo('REUSED', reused)
end
f.DebugWidget(widget)
