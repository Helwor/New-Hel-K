function widget:GetInfo()
    return {
        name      = "Game To Lobby Message",
        desc      = "Socket Communication to Chobby (via chobby widget api_msg_from_game.lua)",
        author    = "Helwor",
        date      = "June 2024",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true,  --  loaded by default?
        api       = true,
        handler   = true,
    }
end

local sig = '[' .. widget:GetInfo().name .. ']:'
local Echo = Spring.Echo


local SocketClient
local host = "127.0.0.1";
local port = VFS.LoadFile("chobby_wrapper_port.txt")
if not port then
    Echo(sig.. " don't have any port set")
    return false
end
port = port + 1

LIB_LOBBY_DIRNAME = "libs/liblobby/lobby/"
VFS.Include(LIB_LOBBY_DIRNAME .. "json.lua")
if not json then
    Echo(sig .. 'wrong include dir: ' .. LIB_LOBBY_DIRNAME .. "json.lua")
    return false
end

local wait = 0
local client_holder = {}
local function Init(self) -- FIX ME the client getting closed after first send
    if not self.client then
        self.client = socket.tcp()
        self.client:settimeout(0.1)
        self.initialized = true
        client_holder[1] = self.client
        -- Echo(sig .. 'client initialized')
    end
    return true
end
local function Renew(self)
    self.client = nil
    self:Init()
end

local function Connect(self)
    local inbox, _, err = socket.select(client_holder, nil, 0)
    if inbox[self.client] then
        local _, status = self.client:receive()
        if status == 'closed' then
            self:Renew()
        end
    end
    local success, err = self.client:connect(host, port)
    -- Echo(sig .. 'attempting connection to lobby messaging widget', success, err)

    if not success then
        if err ~= 'already connected' then
            Echo(sig .. 'The client failed to connect', err)
            return
        end
    end
    -- Echo(sig .. 'client connected to lobby messaging widget')
    ----------------------------------------------------------------------------
    return true
end




local function Send(self, arg, data)
    if not self.initialized then
        self:Init()
    end
    if not self:Connect() then
        Echo(sig .. 'the client is not connected')
        return
    end
    local res, err = self.client:send(arg .. ' ' .. (data and json.encode(data) or '') .. '\n')
    ----------------------------------------------------------------------------
    if err then
        Echo(sig .. 'socket send failed ' .. err)
    end
    return res, err
end
local function WaitForMessage(self)
    local inbox, writeable, err = socket.select(client_holder, client_holder, 0)
    -- Echo('waiting for message',inbox and inbox[1], writeable and writeable[1],err)
    if err then
        if err == "timeout" then
            return
        end
        Spring.Echo("Error in socket.select: " .. err)
        return
    end
    if inbox[self.client] then
        local s, status, partial = self.client:receive()
        if status == "timeout" or status == nil then
            local msg = s or partial
            SocketClient:callback(msg, writeable)
        elseif status == 'closed' then
            SocketClient.callback = nil
            self:Renew()
        end
    end
end

function widget:Update()
    if SocketClient.callback then
        SocketClient:WaitForMessage()
    end
end
function widget:Initialize()
    -------------------------------
    WG.SocketClient = {
        initialized = false,
        Init = Init,
        Send = Send,
        Connect = Connect,
        Renew = Renew,
        WaitForMessage = WaitForMessage,
    }
    SocketClient = WG.SocketClient
    -- SocketClient:Init()
end

function widget:Shutdown()
    if SocketClient and SocketClient.client then
        SocketClient.client:close()
    end
    WG.SocketClient = nil
end