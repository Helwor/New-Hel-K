--//=============================================================================
--//  SHORT INFO WHY WE DO THIS:
--// Cause of the reference based system in lua we can't
--// destroy objects ourself, instead we have to tell
--// the GarbageCollector somehow that an object isn't
--// in use anymore.
--//  Now we have a quite complex class system in Chili
--// with parent and children links between objects. Those
--// circles make it normally impossible for the GC to
--// detect if an object (and all its children) can be
--// destructed.
--//  This is the point where so called WeakLinks come
--// into play. Instead of saving direct references to the
--// objects in the parent field, we created a weaktable
--// (use google, if you aren't familiar with this name)
--// which directs to the parent-object. So now the link
--// between children and its parent is 'weak' (the GC can
--// catch the parent), and the link between the parent
--// and its children is 'hard', so the GC won't catch the
--// children as long as there is a parent object.
--//=============================================================================

local wmeta =  {__mode = "v"}
local newproxy = newproxy or getfenv(0).newproxy

-- weaklink will return nil when called if the original object is not referenced anymore
function MakeWeakLink(obj,wlink)
	--// 2nd argument is optional, if it's given it will reuse the given link (-> less garbage)

	obj = UnlinkSafe(obj) --// unlink hard-/weak-links -> faster (else it would have to go through multiple metatables)
	-- if true then
	-- 	return obj
	-- end
	if (not isindexable(obj)) then
	return obj
	end

	local mtab
	if (type(wlink) == "userdata") then
		mtab = getmetatable(wlink)
	end
	if (not mtab) then
		wlink = newproxy(true)
		mtab = getmetatable(wlink)
		setmetatable(mtab, wmeta)
	end
	local getRealObject = function() return mtab._obj end --// note: we are using mtab._obj here, so it is a weaklink -> it can return nil!
	mtab._islink = true
	mtab._isweak = true
	mtab._obj = obj
	mtab.__index = obj
	mtab.__newindex = obj
	mtab.__call = getRealObject --// values are weak, so we need to make it gc-safe
	mtab[getRealObject] = true  --// and buffer it in a key, too

	-- unused
	-- if (not obj._wlinks) then 
	-- 	obj._wlinks = setmetatable({},wmeta)
	-- end
	-- obj._wlinks[#obj._wlinks+1] = wlink

	return wlink
end

-- Hardlinks will dispose the original object when no more of them are referenced anymore
-- typically two hardlink are made, one at creation, returned to the user side, the second as child in childrenByName table when it is appended to a parent
function MakeHardLink(obj,gc)
	obj = UnlinkSafe(obj) --// unlink hard-/weak-links -> faster (else it would have to go through multiple metatables)

	if (not isindexable(obj)) then
	return obj
	end

	local hlink = newproxy(true)
	local mtab = getmetatable(hlink)
	mtab._islink = true
	mtab._ishard = true
	mtab._obj = obj
	mtab.__gc = gc or function() 
		if not obj._hlinks or not obj._hlinks[1] then
			obj:AutoDispose()
		end
	end
	mtab.__index = obj
	mtab.__newindex = obj
	mtab.__call = function() return mtab._obj end

	if (not obj._hlinks) then
		obj._hlinks = setmetatable({},wmeta)
	end
	obj._hlinks[#obj._hlinks+1] = hlink

	return hlink
end


function UnlinkSafe(link)
	while (type(link) == "userdata") do
		local success, err = pcall(link)
		if not success then
			Echo(err)
			Echo(debug.traceback())
			error()
		end
		link = link()
	end
	return link
end


function CompareLinks(link1,link2)
	if UnlinkSafe(link1) == UnlinkSafe(link2) then
		return true
	else
		return false
	end
end


function CheckWeakLink(link)
	return (type(link) == "userdata") and link()
end

--//=============================================================================
