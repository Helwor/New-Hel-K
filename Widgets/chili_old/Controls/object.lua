--// =============================================================================

--- Object module

--- Object fields.
-- @table Object
-- @bool[opt = true] visible control is displayed
-- @tparam {Object1, Object2, ...} children table of visible children objects (default {})
-- @tparam {Object1, Object2, ...} children_hidden table of invisible children objects (default {})
-- @tparam {"obj1Name" = Object1, "obj2Name" = Object2, ...} childrenByName table mapping name- > child
-- @tparam {func1, func2, ...} OnDispose  function listeners for object disposal, (default {})
-- @tparam {func1, func2, ...} OnClick  function listeners for mouse click, (default {})
-- @tparam {func1, func2, ...} OnDblClick  function listeners for mouse double click, (default {})
-- @tparam {func1, func2, ...} OnMouseDown  function listeners for mouse press, (default {})
-- @tparam {func1, func2, ...} OnMouseUp  function listeners for mouse release, (default {})
-- @tparam {func1, func2, ...} OnMouseMove  function listeners for mouse movement, (default {})
-- @tparam {func1, func2, ...} OnMouseWheel  function listeners for mouse scrolling, (default {})
-- @tparam {func1, func2, ...} OnMouseOver  function listeners for mouse over...?, (default {})
-- @tparam {func1, func2, ...} OnMouseOut  function listeners for mouse leaving the object, (default {})
-- @tparam {func1, func2, ...} OnKeyPress  function listeners for key press, (default {})
-- @tparam {func1, func2, ...} OnFocusUpdate  function listeners for focus change, (default {})
-- @bool[opt = false] disableChildrenHitTest if set childrens are not clickable/draggable etc - their mouse events are not processed
Object = {
	classname = 'object',
	--x         = 0,
	--y         = 0,
	--width     = 10,
	--height    = 10,
	defaultWidth  = 10, --FIXME really needed?
	defaultHeight = 10,

	visible  = true,
	--hidden   = false, --// synonym for above

	preserveChildrenOrder = false, --// if false adding/removing children is much faster, but also the order (in the .children array) isn't reliable anymore

	children    = {},
	children_hidden = {},
	childrenByName = CreateWeakTable(),

	OnDispose       = {},
	OnClick         = {},
	OnDblClick      = {},
	OnMouseDown     = {},
	OnMouseUp       = {},
	OnMouseMove     = {},
	OnMouseWheel    = {},
	OnMouseOver     = {},
	OnMouseOut      = {},
	OnKeyPress      = {},
	OnTextInput     = {},
	OnTextModified  = {},
	OnTextEditing   = {},
	OnFocusUpdate   = {},
	OnHide          = {},
	OnShow          = {},
	OnOrphan        = {},
	OnParent        = {},
	OnParentPost    = {}, -- Called after parent is set

	disableChildrenHitTest = false, --// if set childrens are not clickable/draggable etc - their mouse events are not processed
	--ancestor      = false --// the greatest parent that is not screen
}
-- before
	-- added .ancestor giving the grand parent of object just before Screen (if it exsists)
	-- added IsAncestorOf
	-- added some "descendants" methods to apply action on (like CallChildrenInverse etc)
	-- added .generic_name to identify easier object by name
-- April 2025 
	-- remove unuseful hard link of object as key in children
	-- fix SetLayer method indexing
	-- remove unuseful SetLayer call
	-- fix AddChild() with index parameter
	-- maintain child index by obj after a remove
	-- fix child as key in children being always the objDirect
	-- implemented Object:Clone(toReplace) -- TEST IT
-- May 2025
	-- trigger OnParentPost once object become child and not before
	-- trigger OnOrphan once object left the children table and not before
do
	local __lowerkeys = {}
	Object.__lowerkeys = __lowerkeys
	for i, v in pairs(Object) do
		if (type(i) == "string") then
			__lowerkeys[i:lower()] = i
		end
	end
end

local this = Object
local inherited = this.inherited

local Echo = Spring.Echo
local DEBUG_INDEXATION = false
--// =============================================================================
--// used to generate unique objects names
local cic = {}
local function GetUniqueId(classname)
	local ci = cic[classname] or 0
	cic[classname] = ci + 1
	return ci
end
local function GetCloneName(name)
	local dup
	name, dup = name:gsub('(_clone)(%d+)$', function(t,n) return t .. (n+1) end)
	if dup == 0 then
		name = name .. '_clone1'
	end
	return name
end

--// =============================================================================

--- Object constructor
-- @tparam Object obj the object table
function Object:GetUniqueID()
	return GetUniqueId(self.classname)
end
function Object:New(obj, isClone)
	if not obj then
		obj = {}
	elseif type(obj) == 'userdata' then
		obj = UnlinkSafe(obj)
		if not obj then
			error()
		end
	end
	
	--// check if the user made some lower-/uppercase failures
	for i, v in pairs(obj) do
		if (not self[i]) and (isstring(i)) then
			local correctName = self.__lowerkeys[i:lower()]
			if (correctName) and (obj[correctName] == nil) then
				obj[correctName] = v
			end
		end
	end

	--// give name
	if (not obj.name) then
		if obj.generic_name then
			obj.name = obj.generic_name .. GetUniqueId(obj.generic_name)
		else
			obj.name = self.classname .. GetUniqueId(self.classname)
		end
	end

	--// make an instance
	for k, v in pairs(self) do --// `self` means the class here and not the instance!
		if (k ~= "inherited") then
			local classt = type(v)
			if (classt == "table") or (classt == "metatable") then
				local ot = type(obj[k])
				if (ot == "nil") then -- create table for Object class param not specified by user
					obj[k] = {};
					ot = "table";
				end
				if (ot ~= "table") and (ot ~= "metatable") then
					Spring.Echo("Chili: " .. obj.name .. ": Wrong param type given to " .. k .. ": got " .. ot .. " expected table.")
					obj[k] = {}
				end

				table.merge(obj[k], v)
				if (classt == "metatable") then
					setmetatable(obj[k], getmetatable(v))
				end
			-- We don't need to copy other types (allegedly) -- yes because of the inheritance system
			--elseif (ot == "nil") then
			--  obj[i] = v
			end
		end
	end
	setmetatable(obj, {__index = self})

	--// auto dispose remaining Dlists etc. when garbage collector frees this object
	local hobj = MakeHardLink(obj)

	--// handle children & parent
	local parent = obj.parent
	if (parent) then
		if parent.classname == 'screen' then
			obj.ancestor = obj
		else
			obj.ancestor = parent.ancestor
			if not parent.ancestor then -- never happened
				error('Object:New() PROBLEM parent dont have ancestor yet !',obj.classname,obj.name or '',parent.classname,parent.name or '')
			end
		end

		obj.parent = nil
		--// note: we are using the hardlink here,
		--//       else the link could get gc'ed and dispose our object
		parent:AddChild(hobj)

	else
		obj.ancestor = obj
	end
	local children = obj.children
	local clen = #children
	obj.children = {}
	if clen > 0 then
		for i = 1, clen do
			obj:AddChild(children[i], true)
		end
	end
	self:VerifyIndexation('NEW AFTER')
	if children[1] then
		obj:SetDescendants('ancestor', obj.ancestor)
		-- obj:VerifyDescendants('ancestor', obj.ancestor)
	end

	--// sets obj._widget
	DebugHandler:RegisterObject(obj)

	return hobj
end


--- Disposes of the object.
-- Calling this releases unmanaged resources like display lists and disposes of the object.
-- Children are disposed too.
-- TODO: use scream, in case the user forgets.
-- nil - > nil
function Object:Dispose(_internal)
	self:VerifyIndexation('Dispose before OnDispose' .. '( disposed:' .. tostring(self.disposed)..')')
	if (not self.disposed) then

		--// check if the control is still referenced (if so it would indicate a bug in chili's gc)
		if _internal then
			if self._hlinks and next(self._hlinks) then
				local hlinks_cnt = table.size(self._hlinks)
				local i, v = next(self._hlinks)
				if hlinks_cnt > 1 or (v ~= self) then --// check if user called Dispose() directly
					Spring.Echo(("Chili: tried to dispose \"%s\"! It's still referenced %i times!"):format(self.name, hlinks_cnt))
				end
			end
		end

		if self.state and self.state.focused then
			local screenCtrl = self:FindParent("screen")
			if screenCtrl then
				screenCtrl:FocusControl(nil)
			end
		end
		self:CallListeners(self.OnDispose)

		self.disposed = true

		TaskHandler.RemoveObject(self)
		--DebugHandler:UnregisterObject(self) --// not needed
		-- Echo("self.classname, (UnlinkSafe(self.parent)) is ", self.classname, (UnlinkSafe(self.parent)))
		local index
		if (UnlinkSafe(self.parent)) then
			index = self.parent.children[self]
			self.parent:RemoveChild(self)
		end
		self:SetParent(nil, index)
		self:ClearChildren()
		self:VerifyIndexation('Dispose after OnDispose')
	end
end


function Object:AutoDispose()
	self:Dispose(true)
end
local classByName
function Object:GetClass()
	if not classByName then
		classByName = {}
		for k,v in pairs(WG.Chili) do
			if type(v) == 'table' and v.classname then
				classByName[v.classname] = v
			end
		end
	end
	return classByName[self.classname]
end
function Object:Clone(toReplace)
	local obj = UnlinkSafe(self)
	local class = obj:GetClass()

	-- Echo('*****')
	-- Echo('*****')
	-- Echo("obj.name is ", obj.name)
	-- Echo("table.size(obj) is ", table.size(obj))
	local clone = {}
	for k, v in pairs(obj) do
		-- Echo('copy', k, v)
		if k == 'font' and type(v) == 'userdata' then
			-- for font essentially
			-- Echo("Unlinking", k)
			v = UnlinkSafe(v)
			-- clone[k] = WG.Chili.Font:New(UnlinkSafe(v))
		end
		if k == 'font' then
			v = nil
		end
		if type(v) == 'table' then
			v = table.shallowcopy(v)
		end
		clone[k] = v
	end
	if toReplace then
		table.update(clone, toReplace)
	end
	local children = obj.children
	local hidden_children = obj.children_hidden

	-- unhide children for them to appear all in children list
	local toHide = {}
	for child in pairs(hidden_children) do
		child:Show()
		toHide[child] = true
	end

	-- remove data uniques to the control
	local parent = obj.parent
	clone.parent = nil

	clone.childrenByName = nil
	clone.children = nil
	clone._hlinks = nil
	clone._wlinks = nil
	clone.hidden_children = nil

	if clone.name then
		clone.name = GetCloneName(clone.name)
	end

	-- create a cloned object with no parent
	local hclone = class:New(clone)

	if clone.classname == 'font' then
		-- skip: after a new font is created, it will have a child linked to it that we don't have to touch
	elseif children and children[1] then
		for i, child in ipairs(children) do
			-- recreate children controls with no parent, then add them to the cloned parent
			local parent = child.parent
			child.parent = nil
			local c = child:Clone()
			child.parent = parent
			clone:AddChild(c)
			if toHide[child] then
				c:Hide()
			end

		end
	end
	if parent then -- add the original parent when not in recursion, or add the cloned parent 
		parent:AddChild(clone)
	end
	-- rehide original children if any
	for child in pairs(toHide) do
		child:Hide()
	end
	-- return the hardlink of the clone, as would do any New() function
	return hclone
end

function Object:Inherit(class)
	class.inherited = self

	for i, v in pairs(self) do
		if (class[i] == nil) and (i ~= "inherited") and (i ~= "__lowerkeys") then
			t = type(v)
			if (t == "table") --[[or(t == "metatable")--]] then
				class[i] = table.shallowcopy(v)
			else
				class[i] = v
			end
		end
	end

	local __lowerkeys = {}
	class.__lowerkeys = __lowerkeys
	for i, v in pairs(class) do
		if (type(i) == "string") then
			__lowerkeys[i:lower()] = i
		end
	end

	--setmetatable(class, {__index = self})

	--// backward compability with old DrawControl gl state (change was done with v2.1)
	local w = DebugHandler.GetWidgetOrigin()
	if (w ~= widget) and (w ~= Chili) then
		class._hasCustomDrawControl = true
	end

	return class
end

--// =============================================================================

--- Sets the parent object
-- @tparam Object obj parent object
function Object:SetParent(obj, index)
	self = UnlinkSafe(self)
	obj = UnlinkSafe(obj)
	local exParent = self.parent
	local oldancestor = self.ancestor
	if (type(obj) ~= "table") then
		self.parent = nil
		self.ancestor = self
		-- apply to descendants now? for performance, maybe dont do it until we find some problem
		self:SetDescendants('ancestor', self)
		self:CallListeners(self.OnOrphan, self, exParent, index)
		return
	end
	self:CallListeners(self.OnParent, self, exParent, obj, index)

	if obj.classname ~= 'screen' then
		self.ancestor = obj.ancestor or obj
	else
		self.ancestor = self
	end

	-- Children always appear to visible when they recieve new parents because they
	-- are added to the visible child list.
	self.visible = true
	self.hidden = false

	self.parent = MakeWeakLink(obj, self.parent)

	self:Invalidate()
	if oldancestor ~= self.ancestor then
		self:SetDescendants('ancestor',self.ancestor)
	end

	self:CallListeners(self.OnParentPost, self, exParent, obj, index)
end

--- Adds the child object
-- @tparam Object obj child object to be added
function Object:AddChild(obj, dontUpdate, index)
	self = UnlinkSafe(self)
	local objDirect = UnlinkSafe(obj)
	local children = self.children

	if (children[objDirect]) then
		Spring.Echo(("Chili: tried to add multiple times \"%s\" to \"%s\"!"):format(obj.name, self.name))
		return
	end
	local hobj = objDirect._hlinks and objDirect._hlinks[1]
	if not hobj then
		hobj = MakeHardLink(objDirect)
	end
	self:VerifyIndexation('ADD BEFORE '..(index and 'idx'..index or ''), index)
	if (objDirect.name) then
		if (self.childrenByName[objDirect.name]) then
			Echo(("Chili: There is already a control with the name `%s` in `%s`!"):format(obj.name, self.name))
			error()
			return
		end
		self.childrenByName[objDirect.name] = hobj
	end
	local setNewParent = not CompareLinks(objDirect.parent, self)
	if setNewParent then
		if objDirect.parent then
			objDirect.parent:RemoveChild(objDirect)
		end
	end

	local clen = #children
	if index and (index <= clen) then

		for k, v in pairs(children) do 
			if type(v) == "number" and v >= index then
				children[k] = v + 1
			end
		end

		table.insert(children, index, objDirect)
		children[objDirect] = index

	else
		local i = clen + 1
		children[i] = objDirect
		children[objDirect] = i
	end
	if setNewParent then
		objDirect:SetParent(self, math.min(index or clen+1, clen+1))
	end
	-- self:VerifyIndexation('ADD AFTER '..(index and 'idx'..index or ''))
	if not dontUpdate then
		self:Invalidate()
	end
end
local DEBUG_INDEXATION = false
function Object:VerifyIndexation(from, addToIndex)
	if not DEBUG_INDEXATION then
		return
	end
	-- if DONE then
	-- 	return
	-- end
	DONE = false
	from = from or '--'
	local count = 0
	local children = self.children
	local index, childAtIndex, childAsKey, otherIndex

	for k,v in pairs(children) do
		if type(v) == 'number' then
			otherIndex = v
			childAtIndex, childAsKey = children[v], k
			index = children[childAsKey]
			if not childAtIndex then
				Echo('FROM '..from..', CHILD INDEXED DOESNT EXIST', childAsKey.name, 'give wrong index:'..tostring(otherIndex),'owner', self.name, self.classname, 'parent', self.parent, self.parent and self.parent.name)
				DONE = true
			elseif childAtIndex ~= childAsKey then
				Echo('FROM '..from..', WRONG INDEX FOR CHILD', childAtIndex and childAtIndex.name, 'index:' ..tostring(index), childAsKey and childAsKey.name, 'index:'..tostring(otherIndex),'owner', self.name, self.classname, 'parent', self.parent, self.parent and self.parent.name)
				DONE = true
			end
		elseif type(k) == 'number' then
			count = count + 1
			index, childAtIndex = k, v
			otherIndex = children[childAtIndex]
			if otherIndex ~= index then
				Echo('FROM '..from..', CHILD GIVE WRONG INDEX', childAtIndex and childAtIndex.name, 'real index:' ..tostring(index), 'given index:' .. tostring(otherIndex),'owner', self.name, self.classname, 'parent', self.parent, self.parent and self.parent.name)
				DONE = true
			end
		end
		-- if child ~= realChild then
		-- 	local c = self.children[v]
		-- 	Echo('FROM '..from..', WRONG INDEX FOR CHILD', k, c, 'index:' ..tostring(v), c and tostring(self.children[c]) , 'name:'..k.name, c and c.name, 'txt:'.. (c and (c.caption or c.text) or ''), 'ancestor',  k.ancestor.name, k.ancestor.classname, k.ancestor.caption, k.ancestor.text)
		-- end
		-- else
		-- 	local index = self.children[v]
		-- 	if v ~= self.children[index] then
		-- 		Echo('FROM'..from..', WRONG INDEX FOR CHILD2',v,self.children[index],index, v.name, v.ancestor.name, v.ancestor.clasname, v.ancestor.caption, v.ancestor.text)
		-- 	end
		-- end
	end
	-- if DONE then
	-- 	Echo('parent', self.parent, self.parent and self.parent.name, self.parent and self.parent.classname)
	-- 	Echo('all children')
	-- 	for k,v in pairs(self.children) do
	-- 		local child = type(k) == 'number' and v or k
	-- 		Echo(k,v, child.name, child.classname)
	-- 	end
	-- end
	if count ~= #self.children then
		Echo('FROM '..from..', WRONG NUMBER OF CHILD/INDEX', self.name, self.ancestor.name, self.ancestor.clasname, self.ancestor.caption, self.ancestor.text)
	end
end

--- Removes the child object
-- @tparam Object child child object to be removed
function Object:RemoveChild(child)
	self = UnlinkSafe(self)
	self:VerifyIndexation('Remove BEFORE')
	if not isindexable(child) then
		return child
	end
	local childDirect = UnlinkSafe(child)
	-- if not (self.children[childDirect] or self.children_hidden[childDirect]) then
	-- 	Echo('PARENT', child.parent, CompareLinks(child.parent, self))
	-- 	Echo(childDirect.ancestor.name, childDirect.ancestor.classname, childDirect.ancestor.caption)
	-- end


	if (self.children_hidden[childDirect]) then
		self.children_hidden[childDirect] = nil
		return true
	end

	if (not self.children[childDirect]) then
		-- it's only happening with Fonts, not sure why yet
		-- Spring.Echo(("Chili: tried remove none child \"%s\" from \"%s\"! \"%s\""):format(childDirect.name, self.name, self.caption or self.text or ''))
		-- Spring.Echo(DebugHandler.Stacktrace())
		return false
	end

	if (childDirect.name) then
		self.childrenByName[childDirect.name] = nil
	end

	local children = self.children

	local index = children[childDirect]
	local clen = #children
	
	children[childDirect] = nil -- remove index

	if clen == index then
		children[clen] = nil
	elseif not self.preserveChildrenOrder then
		-- replace with last
		children[index] = children[clen]
		children[clen] = nil
		children[ children[index] ] = index
	else
		table.remove(children, index)
		for i = index, clen-1 do -- update indexes
			children[ children[i] ] = i
		end
	end
	-- for k,v in pairs(children) do
	-- 	if type(v) == 'number' then
	-- 		children[k] = nil
	-- 	end
	-- end
	-- for i, child in ipairs(children) do
	-- 	children[child] = i
	-- end
	if CompareLinks(child.parent, self) then
		child:SetParent(nil, index)
    end

	self:VerifyIndexation('Remove AFTER')
	self:Invalidate()
	return true

	-- for i = 1, clen do
	-- 	if CompareLinks(childDirect, children[i]) then
	-- 		if (self.preserveChildrenOrder) then
	-- 			--// slow
	-- 			for j = i + 1, clen do
	-- 				children[ children[j] ] = j - 1
	-- 			end
	-- 			table.remove(children, i)
	-- 		else
	-- 			--// fast

	-- 			children[i] = children[clen]
	-- 			children[ children[i] ] = i
	-- 			children[clen] = nil
	-- 		end

	-- 		-- children[child] = nil --FIXME (unused/unuseful?)
	-- 		children[childDirect] = nil

	-- 		self:Invalidate()
	-- 		return true
	-- 	end
	-- end
	-- return false
end

--- Removes all children
function Object:ClearChildren()
	--// make it faster
	-- Echo('Clear')
	self:VerifyIndexation('Clear Children BEFORE')
	local old = self.preserveChildrenOrder
	self.preserveChildrenOrder = false

	--// remove all children
		-- for c in pairs(self.children_hidden) do
		-- 	self:ShowChild(c)
		-- end

		-- for i = #self.children, 1, -1 do
		-- 	self:RemoveChild(self.children[i])
		-- end
		local hidden = self.children_hidden
		for child in pairs(hidden) do
			hidden[child] = nil
			child:SetParent(nil)
		end
		local children = self.children
		local childrenByName = self.childrenByName
		for k, v in pairs(children) do
			if type(v) ~= 'number' then
				v:SetParent(nil, k)
				childrenByName[v.name] = nil
			end
			children[k] = nil
		end
		self:Invalidate()
	--// restore old state
	self:VerifyIndexation('Clear Children AFTER')
	self.preserveChildrenOrder = old
end

--- Specifies whether the object has any visible children
-- @treturn bool
function Object:IsEmpty()
	return (not self.children[1])
end

--// =============================================================================

--- Hides a specific child
-- @tparam Object obj child to be hidden
function Object:HideChild(obj)
	--FIXME cause of performance reasons it would be usefull to use the direct object, but then we need to cache the link somewhere to avoid the auto calling of dispose
	local objDirect = UnlinkSafe(obj)
	self:VerifyIndexation('Hide Before')
	if not objDirect then
		Spring.Echo("Chili: tried to hide a fake child (".. type(obj) ..")")
		return
	end
	if (not self.children[objDirect]) then
		--if (self.debug) then
			Spring.Echo("Chili: tried to hide a non-child (".. (obj.name or "") ..")")
			Echo(objDirect.parent)
		--end
		return
	end

	if (self.children_hidden[objDirect]) then
		--if (self.debug) then
			Spring.Echo("Chili: tried to hide the same child multiple times (".. (obj.name or "") ..")")
		--end
		return
	end

	-- local hobj = MakeHardLink(objDirect)
	local hobj = objDirect._hlinks[1]
	if not hobj then
		error('ERROR NO HOBJ')
	end
	local pos = {hobj, 0, nil, nil}

	local children = self.children
	local cn = #children
	for i = 1, cn + 1 do
		if CompareLinks(objDirect, children[i]) then
			pos = {hobj, i, MakeWeakLink(children[i-1]), MakeWeakLink(children[i + 1])}
			break
		end
	end

	self:RemoveChild(objDirect)
	self:VerifyIndexation('Hide AFTER')

	self.children_hidden[objDirect] = pos
	obj.parent = self
end

--- Makes a specific child visible
-- @tparam Object obj child to be made visible
function Object:ShowChild(obj)
	--FIXME cause of performance reasons it would be usefull to use the direct object, but then we need to cache the link somewhere to avoid the auto calling of dispose
	local objDirect = UnlinkSafe(obj)
	self:VerifyIndexation('Show Before')
	if (not self.children_hidden[objDirect]) then
		--if (self.debug) then
			Spring.Echo("Chili: tried to show a non-child (".. (obj.name or "") ..")")
		--end
		return
	end

	if (self.children[objDirect]) then
		--if (self.debug) then
			Spring.Echo("Chili: tried to show the same child multiple times (".. (obj.name or "") ..")")
		--end
		return
	end

	local params = self.children_hidden[objDirect]
	self.children_hidden[objDirect] = nil

	local children = self.children
	local clen = #children

	if (params[3]) then
		for i = 1, clen do
			if CompareLinks(params[3], children[i]) then
				self:AddChild(objDirect, nil, i + 1)
				return true
			end
		end
	end

	self:AddChild(objDirect, nil, params[2])
	self:VerifyIndexation('Show AFTER')

	return true
end

--- Sets the visibility of the object
-- @bool visible visibility status
function Object:SetVisibility(visible)
	if self.visible == ((visible and true) or false) then
		return
	end
	if (visible) then
		self.parent:ShowChild(self)
	else
		self.parent:HideChild(self)
	end
	self.visible = visible
	self.hidden  = not visible

	if not visible and self.state and self.state.focused then
		local screenCtrl = self:FindParent("screen")
		if screenCtrl then
			screenCtrl:FocusControl(nil)
		end
	end

	if visible then
		self:CallListeners(self.OnShow, self)
	else
		self:CallListeners(self.OnHide, self)
	end
end

--- Hides the objects
function Object:Hide()
	local wasHidden = self.hidden
	self:SetVisibility(false)
	if not wasHidden then
		self:CallListeners(self.OnHide, self)
	end
end

--- Makes the object visible
function Object:Show()
	local wasVisible = not self.hidden
	self:SetVisibility(true)
	if not wasVisible then
		self:CallListeners(self.OnShow, self)
	end
end

--- Toggles object visibility
function Object:ToggleVisibility()
	self:SetVisibility(not self.visible)
end

--// =============================================================================

function Object:SetChildLayer(child, index, dontUpdate)
	self:VerifyIndexation('Set Child Layer BEFORE')
	local objDirect = UnlinkSafe(child)
	local children = self.children
	local clen = #children 
	if index <= 0 then
		index = clen
	else
		index = math.min(index, clen)	
	end
	-- hidden case
	local pos_hidden = self.children_hidden[objDirect]
	if pos_hidden then
		pos_hidden[2], pos_hidden[3], pos_hidden[4] = index, MakeWeakLink(children[index-1]), MakeWeakLink(children[index + 1])
		return
	end
	--
	local oldindex 
	for i = 1, clen do
		-- if CompareLinks(children[i], objDirect) then
		if children[i] == objDirect then
			oldindex = i
			if oldindex == index then
				return
			end
			table.insert(children, index, table.remove(children, oldindex))
			break
		end
	end


	for k, v in pairs(children) do 
		if type(v) == "number" then
			if oldindex < index then
				if v > oldindex and v <= index then
					children[k] = v - 1
				end
			else
				if v >= index and v < oldindex then
					children[k] = v + 1
				end
			end
		end
	end
	children[objDirect] = index
	self:VerifyIndexation('Set Child Layer AFTER')
	if not dontUpdate then
		self:Invalidate()
	end
end


function Object:SetLayer(index)
	if (self.parent) then
		(self.parent):SetChildLayer(self, index)
	end
end

function Object:SendToBack()
	self:SetLayer(-1)
end

function Object:BringToFront()
	self:SetLayer(1)
end

--// =============================================================================

function Object:InheritsFrom(classname)
	if (self.classname:find(classname)) then
		return true
	elseif not self.inherited then
		return false
	else
		return self.inherited.InheritsFrom(self.inherited, classname)
	end
end

--// =============================================================================

--- Returns a child by name
-- @string name child name
-- @treturn Object child
function Object:GetChildByName(name)
	local cn = self.children
	for i = 1, #cn do
		if (name == cn[i].name) then
			return cn[i]
		end
	end

	for c in pairs(self.children_hidden) do
		if (name == c.name) then
			return MakeWeakLink(c)
		end
	end
end

--// Backward-Compability
Object.GetChild = Object.GetChildByName


--- Resursive search to find an object by its name
-- @string name name of the object
-- @treturn Object
function Object:GetObjectByName(name)
	local r = self.childrenByName[name]
	if r then
		return r
	end

	for i = 1, #self.children do
		local c = self.children[i]
		if (name == c.name) then
			return c
		else
			local result = c:GetObjectByName(name)
			if (result) then
				return result
			end
		end
	end

	for c in pairs(self.children_hidden) do
		if (name == c.name) then
			return MakeWeakLink(c)
		else
			local result = c:GetObjectByName(name)
			if (result) then
				return result
			end
		end
	end
end


--// Climbs the family tree and returns the first parent that satisfies a
--// predicate function or inherites the given class.
--// Returns nil if not found.
function Object:FindParent(predicate)
	if not self.parent then
		return -- not parent with such class name found, return nil
	elseif (type(predicate) == "string" and (self.parent):InheritsFrom(predicate)) or (type(predicate) == "function" and predicate(self.parent)) then
		return self.parent
	else
		return self.parent:FindParent(predicate)
	end
end


function Object:IsDescendantOf(object, _already_unlinked)
	if (not _already_unlinked) then
		object = UnlinkSafe(object)
	end
	if (UnlinkSafe(self) == object) then
		return true
	end
	if (self.parent) then
		return (self.parent):IsDescendantOf(object, true)
	end
	return false
end

function Object:IsVisibleDescendantByName(name)
	if not self.visible then
		return false
	end
	if self.name == name then
		return true
	end
	if (self.parent) then
		return (self.parent):IsVisibleDescendantByName(name)
	end
	return false
end

function Object:IsAncestorOf(object, _level, _already_unlinked)
	_level = _level or 1

	if (not _already_unlinked) then
		object = UnlinkSafe(object)
	end

	local children = self.children

	for i = 1, #children do
		if (children[i] == object) then
			return true, _level
		end
	end

	_level = _level + 1
	for i = 1, #children do
		local c = children[i]
		local res, lvl = c:IsAncestorOf(object, _level, true)
		if (res) then
			return true, lvl
		end
	end

	return false
end

--// =============================================================================

function Object:CallListeners(listeners, ...)
	for i = 1, #listeners do
		local eventListener = listeners[i]
		if eventListener(self, ...) then
			return true
		end
	end
end


function Object:CallListenersInverse(listeners, ...)
	for i = #listeners, 1, -1 do
		local eventListener = listeners[i]
		if eventListener(self, ...) then
			return true
		end
	end
end


function Object:CallChildren(eventname, ...)
	local children = self.children
	for i = 1, #children do
		local child = children[i]
		if (child) then
			local obj = child[eventname](child, ...)
			if (obj) then
				return obj
			end
		end
	end
end
function Object:CallFuncOnChildren(func, ...)
	local children = self.children
	for i = 1, #children do
		local child = children[i]
		if (child) then
			local obj = func(child , ...)
			if (obj) then
				return obj
			end
		end
	end
end
function Object:CallFuncOnDescendants(func, ...)
	local children = self.children
	for i = 1, #children do
		local child = children[i]
		if (child) then
			local obj = func(child , ...) or child:CallFuncOnDescendants(func, ...)
			if (obj) then
				return obj
			end
		end
	end
end

function Object:CallDescendants(eventname, ...)
	local children = self.children
	for i = 1, #children do
		local child = children[i]
		if child then
			local obj = child[eventname](child, ...) or child:CallDescendants(eventname, ...)
			if obj then
				return obj
			end
		end
	end
end
function Object:CallDescendantsInverse(eventname, ...)
	local children = self.children
	for i = #children, 1, -1 do
		local child = children[i]
		if child then
			local obj = child[eventname](child, ...) or child:CallDescendantsInverse(eventname, ...)
			if obj then
				return obj
			end
		end
	end
end
function Object:CallDescendantsInverseCheckFunc(checkfunc, eventname, ...)
	local children = self.children
	for i = #children, 1, -1 do
		local child = children[i]
		if child  then
			local obj = checkfunc(self, child) and child[eventname](child, ...) or child:CallDescendantsInverseCheckFunc(checkfunc, eventname, ...)
			if obj then
				return obj
			end
		end
	end
end
function Object:SetChildren(k, v)
	local children = self.children
	for i = 1, #children do
		local child = children[i]
		if (child) then
			child[k] = v
		end
	end
end
function Object:SetDescendants(k, v)
	local children = self.children
	if not children then
		return
	end
	for i = 1, #children do
		local child = children[i]
		if (child) then
			child[k] = v
			child:SetDescendants(k, v)
		end
	end
end
function Object:VerifyDescendants(k, v)
	local children = self.children
	for i = 1, #children do
		local child = children[i]
		if (child) then
			if child[k] ~= v then
				Echo('PROBLEM Verify Descendants, values differ')
			end
			child:VerifyDescendants(k, v)
		end
	end
end
function Object:CallChildrenInverse(eventname, ...)
	local children = self.children
	for i = #children, 1, -1 do
		local child = children[i]
		if (child) then
			local obj = child[eventname](child, ...)
			if (obj) then
				return obj
			end
		end
	end
end


function Object:CallChildrenInverseCheckFunc(checkfunc, eventname, ...)
	local children = self.children
	for i = #children, 1, -1 do
		local child = children[i]
		if (child) and (checkfunc(self, child)) then
			local obj = child[eventname](child, ...)
			if (obj) then
				return obj
			end
		end
	end
end


local function InLocalRect(cx, cy, w, h)
	return (cx >= 0) and (cy >= 0) and (cx <= w) and (cy <= h)
end


function Object:CallChildrenHT(eventname, x, y, ...)
	if self.disableChildrenHitTest then
		return nil
	end
	local children = self.children
	for i = 1, #children do
		local c = children[i]
		if (c) then
			local cx, cy = c:ParentToLocal(x, y)
			if InLocalRect(cx, cy, c.width, c.height) and c:HitTest(cx, cy) then
				local obj = c[eventname](c, cx, cy, ...)
				if (obj) then
					return obj
				end
			end
		end
	end
end


function Object:CallChildrenHTWeak(eventname, x, y, ...)
	if self.disableChildrenHitTest then
		return nil
	end
	local children = self.children
	for i = 1, #children do
		local c = children[i]
		if (c) then
			local cx, cy = c:ParentToLocal(x, y)
			if InLocalRect(cx, cy, c.width, c.height) then
				local obj = c[eventname](c, cx, cy, ...)
				if (obj) then
					return obj
				end
			end
		end
	end
end

--// =============================================================================

function Object:RequestUpdate()
	--// we have something todo in Update
	--// so we register this object in the taskhandler
	TaskHandler.RequestUpdate(self)
end


function Object:Invalidate()
	--FIXME should be Control only
end


function Object:Draw()
	self:CallChildrenInverse('Draw')
end


function Object:TweakDraw()
	self:CallChildrenInverse('TweakDraw')
end

--// =============================================================================

function Object:TraceDebug(parameters)
	local echo = {}
	for i = 1, #parameters do
		echo[#echo + 1] = parameters[i]
		echo[#echo + 1] = (self[parameters[i]] ~= nil and self[parameters[i]]) or "nil"
	end
	Spring.Echo(unpack(echo))
	if self.parent then
		self.parent:TraceDebug(parameters)
	end
end


--// =============================================================================

function Object:LocalToParent(x, y)
	return x + self.x, y + self.y
end


function Object:ParentToLocal(x, y)
	return x - self.x, y - self.y
end


Object.ParentToClient = Object.ParentToLocal
Object.ClientToParent = Object.LocalToParent


function Object:LocalToClient(x, y)
	return x, y
end

-- LocalToScreen does not do what it says it does because
-- self:LocalToParent(x, y) = 2*self.x, 2*self.y
-- However, too much chili depends on the current LocalToScreen
-- so this working version exists for widgets.
function Object:CorrectlyImplementedLocalToScreen(x, y)
	if (not self.parent) then
		return x, y
	end
	return (self.parent):ClientToScreen(x, y)
end


function Object:LocalToScreen(x, y)
	if (not self.parent) then
		return x, y
	end
	return (self.parent):ClientToScreen(self:LocalToParent(x, y))
end


function Object:UnscaledLocalToScreen(x, y)
	if (not self.parent) then
		return x, y
	end
	--Spring.Echo((not self.parent) and debug.traceback())
	return (self.parent):UnscaledClientToScreen(self:LocalToParent(x, y))
end


function Object:ClientToScreen(x, y)
	if (not self.parent) then
		return self:ClientToParent(x, y)
	end
	return (self.parent):ClientToScreen(self:ClientToParent(x, y))
end


function Object:UnscaledClientToScreen(x, y)
	if (not self.parent) then
		return self:ClientToParent(x, y)
	end
	return (self.parent):UnscaledClientToScreen(self:ClientToParent(x, y))
end


function Object:ScreenToLocal(x, y)
	if (not self.parent) then
		return self:ParentToLocal(x, y)
	end
	return self:ParentToLocal((self.parent):ScreenToClient(x, y))
end


function Object:ScreenToClient(x, y)
	if (not self.parent) then
		return self:ParentToClient(x, y)
	end
	return self:ParentToClient((self.parent):ScreenToClient(x, y))
end


function Object:LocalToObject(x, y, obj)
	if CompareLinks(self, obj) then
		return x, y
	end
	if (not self.parent) then
		return -1, -1
	end
	x, y = self:LocalToParent(x, y)
	return self.parent:LocalToObject(x, y, obj)
end


function Object:IsVisibleOnScreen()
	if (not self.parent) or (not self.visible) then
		return false
	end
	return (self.parent):IsVisibleOnScreen()
end

--// =============================================================================

function Object:_GetMaxChildConstraints(child)
	return 0, 0, self.width, self.height
end

--// =============================================================================


function Object:HitTest(x, y)
	if not self.disableChildrenHitTest then
		local children = self.children
		for i = 1, #children do
			local c = children[i]
			if (c) then
				local cx, cy = c:ParentToLocal(x, y)
				if InLocalRect(cx, cy, c.width, c.height) then
					local obj = c:HitTest(cx, cy)
					if (obj) then
						return obj
					end
				end
			end
		end
	end

	return false
end


function Object:IsAbove(x, y, ...)
	return self:HitTest(x, y)
end


function Object:MouseMove(...)
	if (self:CallListeners(self.OnMouseMove, ...)) then
		return self
	end

	return self:CallChildrenHT('MouseMove', ...)
end


function Object:MouseDown(...)
	if (self:CallListeners(self.OnMouseDown, ...)) then
		return self
	end

	return self:CallChildrenHT('MouseDown', ...)
end


function Object:MouseUp(...)
	if (self:CallListeners(self.OnMouseUp, ...)) then
		return self
	end

	return self:CallChildrenHT('MouseUp', ...)
end


function Object:MouseClick(...)
	if (self:CallListeners(self.OnClick, ...)) then
		return self
	end

	return self:CallChildrenHT('MouseClick', ...)
end


function Object:MouseDblClick(...)
	if (self:CallListeners(self.OnDblClick, ...)) then
		return self
	end

	return self:CallChildrenHT('MouseDblClick', ...)
end


function Object:MouseWheel(...)
	if (self:CallListeners(self.OnMouseWheel, ...)) then
		return self
	end

	return self:CallChildrenHTWeak('MouseWheel', ...)
end


function Object:MouseOver(...)
	if (self:CallListeners(self.OnMouseOver, ...)) then
		return self
	end
end


function Object:MouseOut(...)
	if (self:CallListeners(self.OnMouseOut, ...)) then
		return self
	end
end


function Object:KeyPress(...)
	if (self:CallListeners(self.OnKeyPress, ...)) then
		return self
	end

	return false
end


function Object:TextInput(...)
	if (self:CallListeners(self.OnTextInput, ...)) then
		return self
	end

	return false
end


function Object:TextModified(...)
	if (self:CallListeners(self.OnTextModified, ...)) then
		return self
	end

	return false
end


function Object:TextEditing(...)
	if (self:CallListeners(self.OnTextEditing, ...)) then
		return self
	end

	return false
end


function Object:FocusUpdate(...)
	if (self:CallListeners(self.OnFocusUpdate, ...)) then
		return self
	end

	return false
end

--// =============================================================================
