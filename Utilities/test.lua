local Echo = Spring.Echo
local function exec()
end
local function A()
    exec()
end
local function B()
    exec()
end
local function go()
    local c = A
    if math.random() > 0.5 then
        c = B
    end
    for i = 1, 2 do
        c()
    end
end
-- emulates engine range circles. By very_bad_soldier and versus666
-- corrected and completed by Helwor



return go
-- return CalcBallisticCircle
