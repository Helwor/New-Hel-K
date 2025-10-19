function widget:GetInfo()
    return {
        name      = "_Lua Socket Demo Simple",
        desc      = "",
        author    = "Helwor",
        date      = "June 2024",
        license   = "GNU GPL, v2 or later",
        layer     = 10e38,
        -- layer     = 2,
        enabled   = false,  --  loaded by default?
        api       = true,
        handler   = true,
    }
end

local Echo = Spring.Echo


local server, client, inter
local sig = '[' .. widget:GetInfo().name .. ']:'
local host = "127.0.0.1";
local port = VFS.LoadFile("chobby_wrapper_port.txt")
if not port then
    Echo(widget:GetInfo().name .. " don't have any port set")
    return
end
port = port + 2

local function SetupServer()
end
function widget:Initialize()
    server = socket.tcp()
    server:settimeout(0.1)
    local success, err = server:bind(host, port)
    if not success then
        Echo(sig .. err)
        widgetHandler:RemoveWidget(widget)
        return
    end
    local success, err = server:listen(1) -- maximum connections allowed
    if not success then
        Echo(sig .. err)
        widgetHandler:RemoveWidget(widget)
        return
    end
    server:settimeout(0)
    -------------------------------
    client = socket.tcp()
    client:settimeout(0.1)

    local success, err = client:connect(host, port)
    if not success then
        Echo(sig .. err)
        widgetHandler:RemoveWidget(widget)
        return
    end
    CONNECTED = true
end

function widget:Update()
    -- local ins, outs, err = socket.select({client}, {client}, 0)
    -- for _, input in pairs(ins or {}) do
    --     Echo("input:read() is ", input:receive())
    -- end
    if not SENT then
        SENT = true
        local res, err = client:send(('MESSAGE'):rep(10) .. '\n')
    end
    if not inter then
        inter = server:accept()
        if inter then
            inter:settimeout(0)
            Echo('RECEIVED', inter:receive())
            inter:send('OK')
        end
    end
    if not inter then
        return
    end
    ------------------------------------------------
    local readable, writeable, err = socket.select({client}, {client}, 0)
    if err then
        if err == 'timeout' then
            return
        else
            Echo('error',err)
            return
        end
    end
    if readable[client] then
        Echo("client:receive() is ", client:receive())
    end
    if CLIENT_TO_WRITE and writeable[client] then
        client:send(CLIENT_TO_WRITE)
        CLIENT_TO_WRITE = false
    end

    -----------------------------------------------------------------
    local readable, writeable, err = socket.select({inter}, {inter}, 0)
    if err then
        if err == 'timeout2' then
            return
        else
            Echo('error2',err)
            return
        end
    end
    if readable[inter] then
        Echo("inter:receive() is ", inter:receive())
        inter:send('OK')
    end
    if SERVER_TO_WRITE and writeable[inter] then
        inter:send(SERVER_TO_WRITE)
        SERVER_TO_WRITE = false
    end

end

function widget:MousePress(mx,my,button)
    if button == 3 then
        local data = 'DATA: ' ..table.concat({my,my,button})
        if math.random()> 0.5 then
            CLIENT_TO_WRITE = data
        else
            SERVER_TO_WRITE = data
        end
    end
end

function widget:Shutdown()
    if server then
        server:close()
    end
    if client then
        client:close()
    end
    if inter then
        inter:close()
    end
end