

function widget:GetInfo()
return {
	name    = "_Lua Socket Server",
	desc    = "Lua socket server side",
	author  = "abma",
	date    = "June 2024",
	license = "GNU GPL, v2 or later",
	layer   = 0,
	enabled = false,
    handler = true,
}
end
local Echo = Spring.Echo
local sig = '[' .. widget:GetInfo().name .. ']:'


if not (Spring.GetConfigInt("LuaSocketEnabled", 0) == 1) then
    Echo(sig .. "LuaSocketEnabled is disabled")
    return false
end

local EMPTY_TABLE = {}


local socket = socket


local server, client
local to_send = WG.BufferClass:new()
local host = 'localhost' --"127.0.0.1"
local port = 8201

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
    return (s:gsub('tcp(.-: )0+%w%w%w%w%w','SERV_A%1'))
    -- return (s:gsub('tcp(.-: )0+%w%w%w%w%w','%1'))
end
-----------------------


-- initiates a connection to host:port, returns true on success
local function ServerStart()
    server = socket.bind(host, port)
    if server==nil then
        Spring.Echo("Error binding to " .. host .. ":" .. port)
        return false
    end
    server:settimeout(0)
    sockets:insert(server)
    Echo(socketFormat(server) .. ' initialized at ' .. host .. ':' .. port)
    return true
end


local function ClientConnected()
    local err
    client, err = server:accept() -- happening only once, this represent the remote connection from which we can retrieve client message and reply back to
    if client == nil  then
        Spring.Echo("Accept failed: " .. err)
        return
    end
    client:settimeout(0)
    sockets:insert(client)
    local ip, port = client:getsockname()
    Spring.Echo('Server ' .. socketFormat(server) .. " accepted connection of " .. socketFormat(client) .. " from " .. ip .. ':' .. port)
 end

-------------------------------------


-- called when data was received through a connection
local function ReceiveFromClient(client, str)
    Echo('Server received from ' .. socketFormat(client) ..': ' .. str)
end


-- called when data can be written to a socket
local function SendToClient(sock)
    local data = to_send:shift(sock)
    if data~=nil then
        Echo('We got something to write to '..socketFormat(sock)..': ' .. data .. ' (remaining in buffer: ' .. to_send:len(sock) .. ')')
        sock:send(data)
    end
end
-- called when a connection is closed
local function ClientClosed(sock)
    Echo("closed connection",socketFormat(sock))
    sock:close()
    sockets:remove(sock)
    to_send:removebuf(sock)
end


---------------------------------------

---


function widget:Update(dt)
    local readable, writeable, err = socket.select(sockets, sockets, 0)
    if err then
        if err=="timeout" then
            return
        end
        Spring.Echo("Error in select: " .. err)
        return
    end

    for _, sock in ipairs(readable) do
        if sock == server then -- server socket got readable (client connected) once done we will use the resulting inter communication client 'inter' to interact with the remote 'client'
            ClientConnected()
        else
            local s, status, partial = sock:receive() --try to read all data
            if status == "timeout" or status == nil then
                ReceiveFromClient(sock, s or partial)
            elseif status == "closed" then
                ClientClosed(sock)
            end
        end
    end

    for _, sock in ipairs(writeable) do
        SendToClient(sock)
    end
end

-----------------------------


function widget:Initialize()
    assert(ServerStart())

end

function widget:Shutdown()
    for _, sock in ipairs(sockets) do
       sock:close()
    end
    if to_send then
        to_send:delete()
    end
end
