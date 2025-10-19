

function widget:GetInfo()
return {
	name    = "_Lua Socket Connection Handler",
	desc    = "create global socket handler",
	author  = "Helwor",
	date    = "June 2024",
	license = "GNU GPL, v2 or later",
	layer   = 0,
	enabled = false,
    handler = true,
}
end

local f = WG.utilFuncs
local Echo = Spring.Echo
local sig = '[' .. widget:GetInfo().name .. ']:'

LIB_LOBBY_DIRNAME = "libs/liblobby/lobby/" 
VFS.Include(LIB_LOBBY_DIRNAME .. "json.lua")
if not json then
    Echo(sig .. 'wrong include dir: ' .. LIB_LOBBY_DIRNAME .. "json.lua")
    return false
end

if not (Spring.GetConfigInt("LuaSocketEnabled", 0) == 1) then
    Echo(sig .. "LuaSocketEnabled is disabled")
    return false
end

local EMPTY_TABLE = {}


local socket = socket
local Debug = false
local dbg = Debug and Echo or function() end
local dbg_proxies = true
if dbg_proxies then
    proxies = {}
end
local function socketFormat(sock)
    local s = tostring(sock)
    if dbg_proxies and proxies[sock] then
        s = s:gsub('client','proxy')
    end
    return (s:gsub('tcp(.-: )0+%w%w%w%w%w','%1'))
end


local SocketSet = {}
function SocketSet:new()
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
end





local SocketHandler = {
    server = {
        instances = {},
        sig = sig:sub(1,-2) .. '[server]:',
    },
    client = {
        instances = {},
        sig = sig:sub(1,-2) .. '[client]:',
    },
}
local client, server = SocketHandler.client, SocketHandler.server
---------------------------------------------
--------------- GLOSSARY --------------------

function server:New(host, port, obj)                                end
function server:Shutdown()                                          end
-- callback
function     OnNewClient(self, newclient, ip, port)                 end
function     OnReceived(self, msg, client)                          end
function     OnTimeOut(self, timeout_client, readable, writeable)   end
function     OnSent(self, data, client)                             end
-- internal
function server:CallListener(name, ...)                             end
function server:Start(host, port)                                   end
function server:Connected()                                         end
function server:ReceiveFromClient(client, data)                     end
function server:CanSendToClient(client, to_send)                    end
function server:Closed(client)                                      end
function server:Update(dt)                                          end

--------------------------------------------                ---

function client:New(host, port, obj)                                end
function client:Shutdown()                                          end
function client:AddToSend(data)                                     end
-- callback
function     OnConnected(self, client)                              end
function     OnReceived(self, msg)                                  end
function     OnClosed(self, client)                                 end
function     OnSent(self, data, client)                             end

-- internal
function client:CallListener(name, ...)                             end
function client:Start(host, port)                                   end
function client:Reconnect()                                         end
function client:CanSend(client, to_send)                            end
function client:Received(client, data)                              end
function client:Closed(client)                                      end
function client:Update(dt)                                          end



function widget:MousePress(mx,my,button)                            end
function widget:Initialize()                                        end




-------------- SERVER PART ----------------




function server:New(host, port, obj)
    host = host or 'localhost' --"127.0.0.1"
    port = port or 8201
    local server = self:Start(host, port)
    if not server then
        return false
    end
    local obj = obj or {}
    obj.class = self
    obj.classname = 'server'
    obj.server = server
    obj.clients = {}
    obj.to_send = WG.BufferClass:new()
    obj.host = host
    obj.port = port
    obj.sockets = SocketSet:new()
    obj.sockets:insert(server)
    self.instances[obj] = true
    return setmetatable(obj, {__index = self})
end

function server:Shutdown()
    for client in pairs(self.clients) do
        self.to_send:removebuf(client)
        self.sockets:remove(client)
        client:close()
        self.clients[client] = nil
    end
    self.server:close()
    self.class.instances[self] = nil
end

function server:CallListener(name, ...)
    local ret
    if self[name] then
        ret = self[name](self, ...)
    end
    return ret
end

function server:Start(host, port)
    local server = socket.bind(host, port)
    if server==nil then
        Echo(self.sig .. "Error binding to " .. host .. ":" .. port)
        return false
    end
    server:settimeout(0)
    Echo(socketFormat(server) .. ' initialized at ' .. host .. ':' .. port)
    return server
end

-----------------------

function server:Connected()
    local err
    local client, err = self.server:accept() -- happening only once, this represent the remote connection from which we can retrieve client message and reply back to
    if client == nil  then
        Spring.Echo("Accept failed: " .. err)
        return
    end
    if dbg_proxies then
        proxies[client] = true -- only  used for debugging
    end
    client:settimeout(0)
    self.sockets:insert(client)
    local ip, port = client:getpeername()
    dbg(socketFormat(self.server) .. " accepts connection of " .. socketFormat(client) .. " from " .. ip .. ':' .. port)
    self.clients[client] = true
    self.client = client
    local ask = self:CallListener('OnNewClient', client, ip, port)
    if ask then
        self.to_send:add(client, ask)
    end
 end

-------------------------------------


-- called when data was received through a connection
function server:ReceiveFromClient(client, data)
    data = json.decode(data)
    dbg('Server ' .. socketFormat(self.server) .. ' received from ' .. socketFormat(client) ..' => ' .. data)
    local reply = self:CallListener('OnReceived', data, client)
    if reply then
        self.to_send:add(client, reply)
    end
end


-- called when data can be written to a socket
function server:CanSendToClient(client, to_send)
    local data = to_send:shift(client)
    if data~=nil then
        client:send(json.encode(data))
        local more = self:CallListener('OnSent', data, client)
        if more then
            to_send:add(client, more)
        end
        dbg(socketFormat(self.server) .. ' got something to write to '..socketFormat(client)..': ' .. data .. ' (remaining in buffer: ' .. to_send:len(client) .. ')')
    end

end
-- called when a connection is closed
function server:Closed(client)
    Echo("closed connection of " .. socketFormat(client) .. ' for ' .. socketFormat(self.server))
    client:close()
    self.clients[client] = nil
    self.sockets:remove(client)
    self.to_send:removebuf(client)
end


---------------------------------------

---
function server:Update(dt)
    local sockets, to_send = self.sockets, self.to_send
    local readable, writeable, err = socket.select(sockets, sockets, 0)
    if err then
        if err=="timeout" then
            return
        end
        Echo("Error in select: " .. err)
        return
    end

    for _, sock in ipairs(readable) do
        if sock == self.server then -- server socket got readable (client connected) once done we will use the resulting inter communication client 'inter' to interact with the remote 'client'
            self:Connected()
        else
            local s, status, partial = sock:receive() --try to read all data
            if status == "timeout" or status == nil then
                self:ReceiveFromClient(sock, s or partial)
            elseif status == "closed" then
                self:Closed(sock)
            end
        end
    end

    for _, client in ipairs(writeable) do

        if to_send:check(client) then
            self:CanSendToClient(client, to_send)
        end
    end
    -----
    local timeout = self.timeout
    if timeout then
        timeout = timeout - dt
        if timeout < 0 then
            self.timeout = false
            local toclient = self.timeout_client
            self:CallListener('OnTimeOut',toclient, toclient and readable[toclient], toclient and writeable[toclient])
        else
            self.timeout = timeout
        end
    end
end




------------------------------------------------------------------------
----------------------------- CLIENT PART ------------------------------
------------------------------------------------------------------------





function client:New(host, port, obj)
    host = host or 'localhost' --"127.0.0.1"
    port = port or 8201
    local client, reconnect = self:Start(host, port)
    if not client then
        return false
    end
    Echo(socketFormat(client) .. ' initialized at ' .. host .. ':' .. port)
    obj = obj or {}
    obj.class = self
    obj.classname = 'client'
    obj.client = client
    obj.to_send = WG.BufferClass:new()
    obj.host = host
    obj.port = port
    obj.sockets = SocketSet:new()
    obj.sockets:insert(client)
    obj.wait = reconnect and 0.15 or 0
    obj.reconnect = reconnect
    self.instances[obj] = true

    return setmetatable(obj, {__index = self})
end
function client:Shutdown()
    self.to_send:removebuf(self.client)
    self.sockets:remove(self.client)
    self.client:close()
    self.class.instances[self] = nil
end

function client:AddToSend(data)
    self.to_send:add(self.client, data)
end



function client:CallListener(name, ...)
    local ret
    if self[name] then
        ret = self[name](self, ...)
    end
    return ret
end
function client:Start(host, port)
    local client = socket.tcp()
    local reconnect = false
    client:settimeout(0)
    local success, err = client:connect(host, port)
    if err then
        if err == 'timeout' then
            reconnect = true
        else
            Echo(self.sig .. err)
            return false
        end
    end
    if success then
        local reply = self:CallListener('OnConnected', client)
        if reply then
            self.to_send:add(client,reply)
        end
    end
    return client, reconnect
end
-- initiates a connection to host:port, returns true on success
function client:Reconnect()
    -- return true if we have to retry connection on next round
    local client = self.client
    local success, err = client:connect(self.host, self.port)
    if err then
        if err == 'Operation already in progress' then
            return true
        elseif err == 'already connected' then
            -- skip
        elseif err == 'timeout' then
            Echo(socketFormat(self.client) .. ' attempting to reconnect ...')
            return true
        else
            error(self.sig .. err)
            return false
        end
    end

    self.reconnect = false
    local reply = self:CallListener('OnConnected', client) -- FIXME: check writeable instead to see it is connected
    if reply then
        self.to_send:add(client, reply)
    end
    return false
end

function client:Received(client, data)
    data = json.decode(data)
    local reply = self:CallListener('OnReceived', data, client)
    if reply then
        self.to_send:add(client, reply)
    end
end

-- called when data can be written to a socket
function client:CanSend(client, to_send)
    local data = to_send:shift(client)
    if data~=nil then
        dbg(socketFormat(client) .. ' got something to write: ' , data , ' (remaining in buffer: ' .. to_send:len(client) .. ')')
        client:send(json.encode(data))
        local more = self:CallListener('OnSent', data, client)
        if more then
            to_send:add(client, more)
        end
    end
end
-- called when a connection is closed
function client:Closed(client)
    Echo(socketFormat(client) .. " got connection closed")

    client:close()
    self.sockets:remove(client)
    if self:CallListener('OnClosed', client) then -- are we renewing the connection
        local old_client = client
        local reconnect
        client, reconnect = self:Start(self.host, self.port)
        if not client then
            Echo(self.sig .. 'cannot renew client')
            return
        end
        self.client = client
        self.sockets:insert(client)
        self.to_send:movebuf(old_client,client)
        -- to_send:removebuf(client)
        if reconnect then
            self.wait = 0.15
        end
        self.reconnect = reconnect
    else
        Echo(socketFormat(client) .. ' shutting down')
        self:Shutdown()
    end
end

function client:Update(dt)
    if self.wait - dt > 0 then
        self.wait = self.wait - dt
        return
    end
    if self.reconnect and self:Reconnect() then
        self.wait = 0.2
        return
    end
    local sockets, client, to_send = self.sockets, self.client, self.to_send
    local readable, writeable, err = socket.select(sockets, sockets, 0)

    if err then
        if err=="timeout" then
            return
        end
        Echo(self.sig .. "Error in select: " .. err)
        return
    end

    if readable[client] then
        local s, status, partial = client:receive() --try to read all data
        if status == "timeout" or status == nil then
            self:Received(client, s or partial)
        elseif status == "closed" then
            self:Closed(client)
            return
        end
    end
    if writeable[client] and to_send:check(client) then
        self:CanSend(client, to_send)
        -- client:send(to_send:shift(client))
    end
end


-----------------------------

function widget:MousePress(mx,my,button)
    if button == 3 and myClientObj then
        dbg('new data',mx)
        local data = table.concat({mx,my,button},',') .. '\n'
        myClientObj.to_send:add(myClientObj.client or 'client_wait', data)
    end
end


------------------------------------------------------------------------

function widget:Initialize()
    Demo()
end

local servers = server.instances
local clients = client.instances
function widget:Update(dt)
    for obj in pairs(servers) do
        obj:Update(dt)
    end
    for obj in pairs(clients) do
        obj:Update(dt)
    end
end


function widget:Shutdown()
    for obj in pairs(servers) do
        obj:Shutdown()
    end
    for obj in pairs(clients) do
        obj:Shutdown()
    end
end

---------------------------------

function Demo()
    -- [[ -- Demo
    server:New(nil, nil, 
        {
            banned = { -- instead of name it would be ips, but for the demo we call always from the same ip
                Mario = true, 
            },
            -- return the reply if any
            OnNewClient = function(self, newclient, ip, port)

                Echo('a new ' .. socketFormat(newclient) .. ' arrived !','ip, port is ', ip, port)
                if self.banned[ip] then
                    -- timeout_client:shutdown('receive') -- shadowban, ignore the messages from client
                    -- timeout_client:shutdown() -- don't see any diff from close() if no param
                    newclient:close()
                end
                return 'WANT_IDENTITY'
            end,
            -- return reply if any
            OnReceived = function(self,msg, client)
                Echo('my server received message !', msg)
                local id = msg:match("That's me ! ([%w]+)")
                if id then
                    if self.banned[id] then
                        self.timeout = 3
                        self.timeout_client = client
                        return "Get lost."
                   else
                        self.clients[client] = id
                        return "Welcome " .. id ..' !'
                    end
                end
            end,
            OnTimeOut = function(self, timeout_client, readable, writeable)
                Echo('bye bye')
                timeout_client:close()

            end,
            -- return more to send if needed
            OnSent = function(self, data, client)
                return more
            end
        }
    )
    client:New(nil, nil, 
        {
            -- return the reply if any
            attempts = 0,
            OnConnected = function(self, client)
                Echo('my ' .. socketFormat(client) .. ' got connected !')
                return reply
            end,
            -- -- return the reply if any
            OnReceived = function(self, msg)
                Echo('my client received message !', msg)
                if msg:find('WANT_IDENTITY') then
                    local name = math.random() > 0.3 and 'Mario' or 'Luigi'
                    return "That's me ! ".. name .." !"
                end
            end,
            -- -- return true to ask for client to be renewed, (server disconnected or closed us, we retry to connect every 0.15 sec until the server come back)
            OnClosed = function(self, client) 
                self.attempts = self.attempts + 1
                if self.attempts <= 2 then
                    return true 
                else
                    Echo('Giving up ...')
                end
            end, 
            OnSent = function(self, data, client)
                -- Echo('my message got sent !')
                return more
            end,

        }
    )
    --]]
end



f.DebugWidget(widget)