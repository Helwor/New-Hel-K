

function widget:GetInfo()
return {
	name    = "_Lua Socket Demo",
	desc    = "Demonstrate how server/client can interact with lua socket",
	author  = "abma total rewrite Helwor",
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


local server, client, inter
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
    return (s:gsub('tcp(.-: )0+%w%w%w%w%w','%1'))
end
local function Comment(readable, writeable, ROUND)
    local str
    if readable then
        str = (str or '') .. 'READ: '
        if readable[1] then
            for k,v in ipairs(readable) do
                str = str .. socketFormat(v) .. ', '
            end
        else
            str = str .. 'NONE, '
        end
    end
    if writeable then
        str = (str or '') .. '    ||    WRITE: '
        if writeable[1] then
            for k,v in ipairs(writeable) do
                str = str .. socketFormat(v) .. ', '
            end
        else
            str = str .. 'NONE, '
        end

    end
    if str then
        Echo('#' .. ROUND .. ' --------  ' .. str:sub(1,-3) .. '  --------')
    end
end

--------------------------------------


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

local function ClientStart()
    client = socket.tcp()
    client:settimeout(0)
    sockets:insert(client)
    local success, err = client:connect(host, port)
    if not success and err and err ~= 'timeout' then
        Echo(sig .. err)
        return false
    end
    Echo(socketFormat(client) .. ' attempt connection to ' .. host .. ':' .. port)
    return true
end

local function ClientConnected(writeable)
    local err
    inter, err = server:accept() -- happening only once, this represent the remote connection from which we can retrieve client message and reply back to
    if inter == nil  then
        Spring.Echo("Accept failed: " .. err)
        return
    end
    inter:settimeout(0)
    sockets:insert(inter)
    local ip, port = inter:getsockname()
    Spring.Echo("Accepted connection of " .. socketFormat(inter) .. " from " .. ip .. ':' .. port)
    Buffer:movebuf('client_wait', client)
    Buffer:add(inter,"OK, Server accepted new client")
    Echo('buffering server response...')
end

-------------------------------------



-- called when data was received through a connection
local function SocketReceived(socket, str)
	Echo(socketFormat(socket) ..' received ' .. str  .. (socket == inter and ', buffering a response ...' or ''))
    if socket == inter then
        Buffer:add(socket,'"OK, server received ' .. str .. '"')
    end
end


-- called when data can be written to a socket
local function SocketWriteAble(sock)
    local data = Buffer:shift(sock)
	if data~=nil then
        Echo(socketFormat(sock) .. ' got something to write: ' .. data .. ' (remaining in buffer: ' .. Buffer:len(sock) .. ')')
		sock:send(data)
	end
end
-- called when a connection is closed
local function SocketClosed(sock)
	Spring.Echo("closed connection",socketFormat(sock))
end


---------------------------------------

local CountDown
do
    local WAIT = 3
    local msgs = 0
    function CountDown(dt)
        if WAIT then
            WAIT = WAIT - dt
            Echo(math.round(WAIT))
            if math.round(WAIT*10)%20 == 1 then
                msgs = msgs + 1
                Echo('buffering Message #' .. msgs)
                Buffer:add('client_wait','Message #' .. msgs)
            end
            if WAIT <= 0 then
                WAIT = false
                Echo('Starting a client to connect')
                ClientStart()
            else
                return true
            end
        end
    end
end

---

local ROUND = 0
function widget:Update(dt)
    if CountDown(dt) then
        return
    end
	local readable, writeable, err = socket.select(sockets, sockets, 0)
	if err then
		if err=="timeout" then
			return
		end
		Spring.Echo("Error in select: " .. err)
        return
	end
    ROUND = ROUND + 1
    Comment(readable, nil, readable[1] and ROUND or 'END')
	for _, sock in ipairs(readable) do
        if sock == server then -- server socket got readable (client connected) once done we will use the resulting inter communication client 'inter' to interact with the remote 'client'
			ClientConnected(writeable)
		else
			local s, status, partial = sock:receive() --try to read all data
			if status == "timeout" or status == nil then
				SocketReceived(sock, s or partial)
			elseif status == "closed" then
				SocketClosed(sock)
				sock:close()
				sockets:remove(sock)
                Buffer:removebuf(sock)
			end
		end
	end
    if readable[1] then
        Comment(nil, writeable, readable[1] and ROUND or 'END')
    	for _, sock in ipairs(writeable) do
    		SocketWriteAble(sock)
    	end
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
    if not (ServerStart()--[[ and ClientStart()--]]) then
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
