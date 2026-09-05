local Echo = Spring.Echo
local sig = '[Hel-K]: '

local function GetRealHandler()
	if widgetHandler.LoadWidget then
		return widgetHandler
	else
		local i, n = 0, true
		while n do
			i=i+1
			n,v=debug.getupvalue(widgetHandler.RemoveCallIn, i)
			if n == 'self' and type(v)=='table' and v.LoadWidget then
				return v
			end
		end
	end
end

local function GetUpvalue(func, name)
	local i, n = 0, true
	while n do
		i=i+1
		n, v = debug.getupvalue(func, i)
		if n == name then
			return v
		end
	end
end

local _G = getfenv(newproxy)
if not _G then
	Echo(sig .. "FAILED TO IMPLEMENT PONG -> COULDN\'T GET _G")
	return false
end

local wh = GetRealHandler()
if not wh then
	Echo(sig .. 'FAILED TO IMPLEMENT PONG -> NO REAL WIDGETHANDLER FOUND')
	return false
end
widgetHandler = wh
if widgetHandler['PongList'] and widgetHandler['Pong'] then
	Echo(sig .. 'Pong CallIn already implemented.')
end

local flexCallInMap = GetUpvalue(widgetHandler.UpdateCallIn, 'flexCallInMap')
local callInLists = GetUpvalue(widgetHandler.UpdateCallIns, 'callInLists')
local tracy = _G.tracy

if not (flexCallInMap and callInLists and tracy) then
	Echo(sig .. 'FAILED TO IMPLEMENT PONG -> MISSING UPVALUE: flexCallInMap', flexCallInMap, 'callInLists', callInLists, 'tracy', tracy)
	return false
end

flexCallInMap['Pong'] = true
table.insert(callInLists, 'Pong')
widgetHandler['PongList'] = {}
function widgetHandler:Pong(pingTag, pktSendTime, pktRecvTime)
	tracy.ZoneBeginN("W:Pong")
	for _, w in ipairs(self.PongList) do
		tracy.ZoneBeginN("W:Pong:" .. w.whInfo.name)
		if w:Pong(pingTag, pktSendTime, pktRecvTime) then
			tracy.ZoneEnd()
			break
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

Echo(sig .. 'Successfully implemented Pong CallIn.')


