function widget:GetInfo() return {
	name    = "API Range Renderer GL4",
	author  = "Helwor",
	date    = "Mar 2026",
	license = "GNU GPL v2",
	layer   = -1, -- draw after unit_show_selected_range.lua
	api     = true,
	enabled = true,
	handler = true,
} end


local rangeShader

local clamp = math.clamp
local floor = math.floor
local modf  = math.modf
local max   = math.max

local layout = {
	{id = 1, name = "pos_range", size = 4},
	{id = 2, name = "wParams", size = 4},
	{id = 3, name = "color", size = 4},
	{id = 4, name = "isCannon", size = 1},
}

local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir .. "LuaShader.lua")
VFS.Include(luaShaderDir .. "instancevbotable.lua")
local shaderSourceCache = {
	shaderName = 'Range Renderer GL4',
	vssrcpath = "LuaUI/Widgets/Shaders/range_renderer_gl4.vert.glsl",
	fssrcpath = "LuaUI/Widgets/Shaders/range_renderer_gl4.frag.glsl",
	shaderConfig = {},
	uniformInt = {
		heightmapTex = 0,
		-- losTex = 1,
	},
	uniformFloat = {
		-- lineAlphaUniform = 1,
		-- cannonmode = 0,
		-- fadeDistOffset = 0,
		-- drawMode = 0,
		-- selBuilderCount = 1.0,
		-- selUnitCount = 1.0,
	},
}

local function goodbye(reason)
	Spring.Echo('['..widget.GetInfo().name .. '] ' .. ' exiting with reason: ' .. reason)
	widgetHandler:RemoveWidget(widget)
end

local function MakeShader()
	rangeShader = LuaShader.CheckShaderUpdates(shaderSourceCache, 0)
	if not rangeShader then
		goodbye("Failed to compile rangeShader GL4 ")
		return false
	end
	return true
end
local function NewInstance(divs)
	local vbo, numVerts = makeCircleVBO(divs, 1)
	local instance = makeInstanceVBOTable(layout, 2000, "RangeRenderer_" .. divs)
	local vao = makeVAOandAttach(vbo, instance.instanceVBO)
	instance.VAO = vao
	instance.numVertices = numVerts
	instance.VBO = vbo
	instance.live = {}
	instance.keep = {}
	return instance
end

local GAME_GRAVITY = Game.gravity / (Game.gameSpeed^2)
local spfactor = 0.7071067 -- projectileSpeed factor

local function SetWeaponParams(wDef, range)
	local wType, wName, heightMod = wDef.type, wDef.name, wDef.heightMod
	local projectilespeed = wDef.projectilespeed
	if wType == "LaserCannon" then
	    range = max(1.0, floor(range / projectilespeed)) * projectilespeed
	elseif wName and wType == 'Cannon' and wName:find('blast') then -- for outlaw 
		wType = 'StarburstLauncher'
	end
	if wType == 'Shield' or wType == 'StarburstLauncher' then 
		heightMod = 1
	end
	return range,
		wType == 'Cannon' and 1 or 0,
		heightMod,
		projectilespeed,
		wDef.myGravity or GAME_GRAVITY,
		wDef.heightBoostFactor or -1
end

local service = {}
local instances = setmetatable({},
	{
		__index = function(self, divs)
			local instance = NewInstance(divs)
			rawset(self, divs, instance)
			return instance
		end
	}

)

local instance_by_range = setmetatable({},
	{
		__index = function(self, range)
			local divs = clamp(floor((range^0.5 * 6) / 30) * 30, 30, 200)
			local instance = instances[divs]
			rawset(self, range, instance)
			return instance
		end
	}
)


local cache = {}
local temp = newproxy(true)

getmetatable(temp).__gc = function(self)
	if self == temp then
		-- Echo('master proxy collected')
		return
	else
		local id = cache[self]
		 -- Echo('collected', self, 'id?', id, os.clock())
		if id then
			service[id] = nil
			-- cache[self] = nil
		end
	end
end

setmetatable(
	cache,
	{
		__mode = 'kv',
		__newindex = function(self, id ,cached)
			-- Echo('set new cache', id, cached)
			local cleaner = newproxy(temp)
			cached.cleaner = cleaner
			rawset(self, cleaner, id)
			rawset(self, id, cached)
		end

	}
)

local update_sub_mt = {
	__call = function(self, x, y, z, force_update)
		local instance = self.instance

		local id = self.id
		local new = not instance.instanceIDtoIndex[id] --self.new
		local cached = not force_update and cache[id]

		local update = true
		if not cached then
			local range, isCannon, heightMod, speed2d, gravity, heightBoost = SetWeaponParams(self.wDef, self.range)
			local r,g,b,a = unpack(self.color)
			cached = {
				-- instance data ...
				x, y, z, range,
				heightMod, speed2d, gravity, heightBoost,
				r, g, b, a,
				isCannon,
			}
			cache[id] = cached
		end
		if new then

		elseif cached[1] ~= x or cached[2] ~= y or cached[3] ~= z then
			cached[1], cached[2], cached[3] = x, y, z
		else
			update = force_update
		end
		if update then
			pushElementInstance(
				instance,
				cached,
				id,
				not new,
				true
			)
		end
		instance.live[id] = true
		instance.keep[id] = cached
	end
}

local function NewObject(id, x, y, z, range, wDef, color)
	local obj = setmetatable(
		{
			wDef = wDef,
			range = range,
			instance = instance_by_range[range],
			id = id,
			color = color,
		},
		update_sub_mt
	)
	service[id] = obj
	return obj
end

function WG.RenderRangeGL4(unitID, x, y, z, range, wDef, color, force_update)
	local id = unitID .. '-' .. wDef.id .. '-' .. range
	local obj = service[id]
	if not obj then
		obj = NewObject(id, x, y, z, range, wDef, color)
	end
	obj(x, y, z, force_update)
end

function widget:Initialize()
	if not MakeShader() then
		return
	end
end

function widget:DrawWorldPreUnit()
	gl.Texture(0, '$heightmap')
	rangeShader:Activate()
	gl.LineWidth(1.4)
	for _, instance in pairs(instances) do
		-- update gpu
		local live = instance.live
		for id, alive in pairs(live) do
			if not alive then
				popElementInstance(instance, id, true)
				live[id] = nil
				instance.keep[id] = nil
			else
				live[id] = false
			end
		end
		if instance.dirty then
			uploadAllElements(instance)
		end
		--
		instance:draw(GL.LINE_STRIP)
	end
	
	rangeShader:Deactivate()
	gl.LineWidth(1)
	gl.Texture(0, false)
end

function widget:Shutdown()
	for _, instance in pairs(instances) do
		instance.VBO:Delete() -- not covered by the method instance:Delete()
		instance:Delete()
	end
	if rangeShader then
		rangeShader:Delete()
	end
	for k,v in pairs(cache) do
		cache[k] = nil
	end
end

