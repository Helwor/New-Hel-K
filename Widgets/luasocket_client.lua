

function widget:GetInfo()
return {
	name    = "_Lua Socket Client",
	desc    = "Demonstrate how server/client can interact with lua socket",
	author  = "abma total rewrite Helwor",
	date    = "June 2024",
	license = "GNU GPL, v2 or later",
	layer   = 0,
	enabled = true,
    handler = true,
}
end
local f = WG.utilFuncs
local Echo = Spring.Echo
local sig = '[' .. widget:GetInfo().name .. ']:'


if not (Spring.GetConfigInt("LuaSocketEnabled", 0) == 1) then
    Echo(sig .. "LuaSocketEnabled is disabled")
    return false
end

local EMPTY_TABLE = {}


local socket = socket


local client
local reconnect, wait = false, 0
local host = 'localhost' --"127.0.0.1"
local port = 8201

local Buffer = WG.BufferClass:new()

local sockets = (function()
    local known = {}
    local set = {}
    return setmetatable(set, {__index = {
        insert = function(set, value)
            if not known[value] then
                table.insert(set, value)
                known[value] = table.getn(set)
            end
        end,
        remove = function(set, value)
            local index = known[value]
            if index then
                known[value] = nil
                local top = table.remove(set)
                if top ~= value then
                    known[top] = index
                    set[index] = top
                end
            end
        end
    }})
end)()

local function socketFormat(sock)
    local s = tostring(sock)
    if s:find('client') and sock == inter then
        s = s:gsub('client','inter')
    end
    return (s:gsub('tcp(.-: )0+%w%w%w%w%w','CLI_A%1'))
end
--------------------------------------


-- initiates a connection to host:port, returns true on success
local function Reconnect()
    local success, err = client:connect(host, port)
    if err then
        if err == 'Operation already in progress' then
            return false
        elseif err == 'already connected' then
            reconnect = false
        elseif err == 'timeout' then
            Echo(socketFormat(client) .. ' attempting to reconnect ...')
            return
        else
            error(sig .. err)
        end
    end
    reconnect = false
end

local function ClientStart()
    client = socket.tcp()
    client:settimeout(0)
    sockets:insert(client)
    local success, err = client:connect(host, port)
    if err then
        if err == 'timeout' then
            reconnect = true
            wait = 0.2
        else
            error(sig .. err)
        end
    end
    Buffer:movebuf('client_wait',client)
    Echo(socketFormat(client) .. ' attempt connection to ' .. host .. ':' .. port)
    return true
end

-------------------------------------
local function ClientReceived(client, str)
    Echo(socketFormat(client) .. ' received ' .. str)

end
-- called when data can be written to a socket
local function ClientCanSend(client)
    local data = Buffer:shift(client)
	if data~=nil then
        -- Echo(socketFormat(client) .. ' got something to write: ' .. data .. ' (remaining in buffer: ' .. Buffer:len(client) .. ')')
		client:send(data)
	end
end
-- called when a connection is closed
local function ClientClosed(client)
	Echo("closed connection",socketFormat(client))
    client:close()
    sockets:remove(client)
    local old_client = client
    ClientStart()
    Buffer:movebuf(old_client,client)
    -- Buffer:removebuf(client)
    reconnect = true

end


---------------------------------------


function widget:Update(dt)
    if wait - dt > 0 then
        wait = wait - dt
        return
    end
    if reconnect then
        Reconnect()
        if reconnect then
            wait = 0.2
            return
        end
    end
	local readable, writeable, err = socket.select(sockets, sockets, 0)

	if err then
		if err=="timeout" then
			return
		end
		Spring.Echo("Error in select: " .. err)
        return
	end
    if readable[client] then
        local s, status, partial = client:receive() --try to read all data
        if status == "timeout" or status == nil then
            ClientReceived(client, s or partial)
        elseif status == "closed" then
            ClientClosed(client)
            return
        end
    end
    if writeable[client] and Buffer:check(client) then
        client:send(Buffer:shift(client))
    end
end

-----------------------------

function widget:MousePress(mx,my,button)
    if button == 3 then
        Echo('new data',mx)
        local data = table.concat({mx,my,button},',') .. '\n'
        Buffer:add(client or 'client_wait', data)
    end
end

function widget:Initialize()
    if not ClientStart() then
        widgetHandler:RemoveWidget(widget)
        return
    end
end

function widget:Shutdown()
    for _, sock in ipairs(sockets) do
       sock:close()
    end
    if Buffer then
        Buffer:delete()
    end
end

f.DebugWidget(widget)