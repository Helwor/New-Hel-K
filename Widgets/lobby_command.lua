function widget:GetInfo()
    return {
        name      = "_Lobby Command",
        desc      = "",
        author    = "Helwor",
        date      = "Dec 2023",
        license   = "GNU GPL, v2 or later",
        layer     = -10e38,
        -- layer     = 2,
        enabled   = true,  --  loaded by default?
        api       = true,
        handler   = true,
    }
end


local Echo = Spring.Echo


--------------------------------------------------------------------
local f = WG.utilFuncs
--------------------------------------------------------------------
local nextword = function(str,n)
    local count = 0
    for word in str:gmatch('[%w_]+') do
        count = count + 1
        if count == n then
            return word
        end
    end
end
local sentence = function(str, n) -- gather rest of line starting by a word; after n word, omitting newline at end
    if not n or n == 0 then
        return str:match('([^\n\r]+)')
    end
    local st, fin = str:find('[%w_]+')
    local count = 1
    while st and n > count do
        st, fin = str:find('[%w_]+', fin+1)
        count = count + 1
    end
    if st then
        return str:sub(fin+2):match('([^\n\r]+)')
    end
end
function widget:Initialize()
    widgetHandler.__ConfigureLayout = widgetHandler.ConfigureLayout
    function widgetHandler:ConfigureLayout(command)
        -- if not (command:find('grabinput') or command:find('movereset')) then
        --     Echo('command : ',command)
        -- end
        -- if command:find('^pm ') or command:find('^w ') then
        --     local userName
        --     userName, message = message:match('^[/!]p?[wm] ([%w_]+) (.+)')

        if command:find('^join')
        or command:find('^open ')
        or command:find('^reload api')
        or command:find('^reload lobby ')
        or command:find('^pm ')
        or command:find('^tell ')
        then
            WG.SocketClient:Send(command)
            return
        elseif command:find('^lobby') then
            Spring.SendLuaMenuMsg('showLobby') -- WE CAN DISCUSS THROUGH THIS
            return
        elseif command:find('^r ') then
            local msg = sentence(command,1)
            if msg then -- send directly the message
                WG.SocketClient.callback = function(self, user)
                    -- Spring.SendCommands('Say ' .. msg)
                    user = sentence(user)
                    if user and #user > 0 then
                        WG.SocketClient:Send('pm '.. user .. ' '.. msg)
                        self.callback = nil
                    end
                end
            else -- setup up pm message with returned user       
                WG.SocketClient.callback = function(self, user)
                    -- Spring.SendCommands('Say ' .. msg)
                    user = sentence(user)
                    Spring.SendCommands("chatall",'pastetext /pm '.. user .. ' ')
                    self.callback = nil
                end
            end
            WG.SocketClient:Send(command)
        -- end
        ---- old
        -- elseif command:find('^sa ') then
        --     local userName, message = command:match('^sa ([%w_]+) (.+)')
        --     -- Echo("userName, message is ", userName, message)
        --     if message and userName and userName:len() > 0 then
        --         if WG.SocketClient then
        --             local arg, data = 'Say', {Place = 0,Text = message, User = userName}
        --             Echo('send message',WG.SocketClient:Send(arg,data))
        --         end
        --     end
        --     return
        end
        ----
        return widgetHandler:__ConfigureLayout(command)
    end

end
function widget:RecvLuaMsg(msg) -- CAN ALSO RECEIVE FROM LOBBY THROUGH Spring.SendLaUIMsg and SEND TO LOBBY WITH SPring.SendLuaMLenuMsg
    --Echo('ingame RecvLuaMsg',msg)
end

function widget:Shutdown()
    if widgetHandler.__ConfigureLayout then
        widgetHandler.ConfigureLayout = widgetHandler.__ConfigureLayout
    end
end

f.DebugWidget(widget)