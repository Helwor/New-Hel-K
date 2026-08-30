local SendSignedOrder, GetSignedWidget
do
    local CMD_OPT_SHIFT = CMD.OPT_SHIFT
    local spGiveOrderToUnit = Spring.GiveOrderToUnit
    local EMPTY_TABLE = {}
    local rawset = rawset
    local byte = string.byte
    local HASH_MIN = 1000000
    local HASH_MOD = 999983  -- prime number
    local function WidgetToSignature(w)
        local name = w.whInfo.basename
        local hash = 0
        for i = 1, #name do
            hash = (hash * 31 + byte(name, i)) % HASH_MOD 
        end
        return hash + HASH_MIN
    end
    local widgetSignature = setmetatable(
        {},
        {   
            __index = function(self, w)
                if type(w) ~= 'table' then
                    return
                end
                local encodedName = WidgetToSignature(w)
                rawset(self, w, encodedName)
                rawset(self, encodedName, w)
                return encodedName
            end,
            __mode = 'kv',
        }

    )
    function SendSignedOrderToUnit(widget, unitID, ...)
        spGiveOrderToUnit(unitID, widgetSignature[widget], EMPTY_TABLE, CMD_OPT_SHIFT) 
        spGiveOrderToUnit(unitID, ...) 
    end
    function GetSignedWidgetOld(t)
        local encodedName = ''
        for i, n in ipairs(t) do
            encodedName = encodedName..tostring(n)
        end
        return widgetSignature[encodedName]
    end
    function GetSignedWidget(encodedName)
        return widgetSignature[encodedName]
    end
    WG.SendSignedOrderToUnit = SendSignedOrderToUnit
    WG.GetSignedWidget = GetSignedWidget
end

Echo('[Hel-K]: Successfully implemented Sign Order Tool')

--[[ Usage
-- sending
WG.SendSignedOrderToUnit(widget, unitID, cmdID, cmdParams, optionCode)
-- receiving
local orderOwner = false
function widget:UnitCommand(unitID, defID, teamID, cmdID, params, opts, cmdTag, playerID, fromSynced, fromLua)
    if cmdID > 1e6 then
        orderOwner  = WG.GetSignedWidget(cmdID)
        if not orderOwner then
            Echo('Error, a widget signature has been missed for unit', unitID, UnitDefs[defID].name, teamID, 'sig:', cmdID)
        end
    elseif orderOwner then
        Echo('Order received from ', orderOwner.whInfo.name, 'cmdID', cmdID, 'params', unpack(params))
        orderOwner = false
    end
end
]]

