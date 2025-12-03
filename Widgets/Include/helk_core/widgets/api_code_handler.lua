-- abc
-- def


function widget:GetInfo()
        return {
        name      = 'API Code Handler',
        desc      = "Manage and exploit file codes",
        author    = "Helwor",
        date      = "Jan 2024",
        license   = "GNU GPL, v2 or later",
        layer     = 1,
        enabled   = true,  --  loaded by default?
        handler   = true,
        api       = true,
}
end


local Echo = Spring.Echo
local f = WG.utilFuncs





local Code = {
    wrapped = {},
    isWrapped = false,
    instances = {},

}
WG.Code = Code
local CodeHelpers = {}
WG.CodeHelpers = CodeHelpers

local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers

do  -- usage: local code, codeObj = Code:GetCode(source, escaped)
    -- or local codeObj, code = Code:New(source)
    -- or local code = codeObj:GetCode(escaped)
    local function getfile(source)
        if source:find('\\') then
            return io.open(source)
        end     
        local file
        if not source:find('/') then
            file = io.open(source)
        end
        local code
        if not file then
            code = VFS.LoadFile(source, VFS.ZIP)
            if code then
                file = io.tmpfile()
                file:write(code)
                file:seek("set")
            end
        end
        return file, code
    end
    local function getlines(file, code, tellTime) -- writing 8K lines tmp file takes practically 0, io.line takes 0.022, while gsub takes 0.033
        -------------

        local l = 1
        local lines
        local lpos = {1}
        local pos = 1
        -- by file
        local codelen
        local time1 = spGetTimer()
        local beforeLast
        if file then
            file:seek('set')
            lines = {''}
            for line in file:lines() do
                -- Echo(" #", i,'pos',pos,'len', line:len(),code:sub(pos,pos+line:len()):readnl())
                -- Echo('line given is',line,'at pos',code:find(line))
                lines[l] = line
                l = l + 1
                pos = pos + line:len() + 1
                lpos[l]  = pos -- pos of the next line, if there is
            end
            codelen = file:seek('cur')
            file:seek('cur',-1)

            beforelast = file:read(1)

            file:close()
        elseif code then
            code:gsub('\n()', function(p) -- much faster to use gsub if we don't want lines
                l = l + 1
                lpos[l]  = p 
                pos = p
            end)
            beforeLast = code:sub(-2, -2)
            codelen = code:len()
        end

        if (beforelast == '\n' or l==1 and beforelast == '') then
            -- Echo('set last line as empty string')
            if lines then
                lines[l] = '' -- we already set the last line pos but not the line
            end
        else
            -- Echo('we set one pos of line too much')
            lpos[l] = nil -- we set one pos of line too much
            l = l - 1
        end
        -------------------
        time1 = spDiffTimers(spGetTimer(), time1)



        ------------------------------------
        -- making shortcuts to get pos-to-line  quicker, any pos in the code will get teleported to the nearest shortcut line pos
        local time2 = spGetTimer()
        local shortcuts = {}
        local div = 800 -- one shortcut every that many character in the file (around 300k char for 8.5K line ~= 375 shortcuts with 800 shortcut size)

        local lastshort = -1
        local last_line = 1
        for i=1, l+1 do 
            local pos = lpos[i] or codelen
            local d = pos/div
            local short = d-d%1 -- like floor or modf but a tiny bit faster
            if short > lastshort then
                shortcuts[short] = i
                if short - lastshort > 1 then -- reporting the last line on missing shortcut(s) (when last line was bigger than min size of shortcut)
                    for sh=lastshort, short-1 do
                        shortcuts[sh] = last_line
                    end
                end
                lastshort = short
                last_line = i
            end
        end

        lpos.div = div
        lpos.shortcuts = shortcuts
        lpos.len = l

        local lineObj = {count=l, lines=lines, lpos=lpos, code = wantCode and code or nil}
        function lineObj.getline(pos, start)
            if l == 1 then
                return 1
            end

            local d = pos/div
            local shortcut = shortcuts[d - d%1]
            -- Echo("table.size(shortcuts) is ", table.size(shortcuts),d - d%1,'len',pos..' vs '.. code:len())
            if not start or start < shortcut then
                start = shortcut
            end
            local lpos = lpos
            for i = start, l do
                if lpos[i] > pos then
                    return i-1, lpos[i-1]
                end
            end
            return l, lpos[l]
        end
        ------------------------------------


        time2 = spDiffTimers(spGetTimer(),time2)
        if tellTime then
            Echo('getlines using '..((code) and 'code' or 'file'), time1, time2,'lines',l)
        end
        return lineObj, time1 + time2
    end


    --------- debugging -----------
    function Code.Wrap(name)
        local func = Code[name]
        local wrapped = Code.wrapped[name]
        if not wrapped then
            wrapped = {name = name, original = func, time = 0, count = 0}
            Code.wrapped[name] = wrapped
        end
        local time, count = 0, 0
        Code[name] = function(...)
            local this_time = spGetTimer()
            local ret = {func(...)}
            count = count + 1
            time = time + spDiffTimers(spGetTimer(), this_time)
            wrapped.time = time
            wrapped.count = count
            return unpack(ret)
        end
    end
    function Code.UnWrap(name)
        Code[name] = Code.wrapped[name].original
    end

    function Code.WrapOperations(bool)
        local ignoreNames = {
            Wrap = true,
            WrapOperations = true,
            UnWrap = true,
            ReportOperations = true,
        }
        if bool then
            if Code.isWrapped then
                return
            end
            Code.isWrapped = true
            for k,v in pairs(Code) do
                if type(v) == 'function' and not ignoreNames[k] then
                    Code.Wrap(k)
                end
            end
        else
            if not Code.isWrapped then
                return
            end
            Code.isWrapped = false
            for k,v in pairs(Code) do
                if type(v) == 'function' and not ignoreNames[k] then
                    Code.UnWrap(k)
                end
            end

        end
    end

    function Code.ReportOperations(clip)
        local lines = {}
        for name,t in pairs(Code.wrapped) do
            local per
            if t.count> 0 then
                if t.count == 1 then
                    per = ''
                else
                    per = ('per: %f'):format(t.time/t.count)
                end

                local line = t.name .. ' x' .. t.count .. ' time ' .. ('%.6f'):format(t.time):ftrim(6) .. ' ' .. per
                lines[#lines+1] = line
            end
        end
        if string.linecount and string.linecount > 0 then
            local count, time = string.linecount, string.linetime
            local per
            if count < 1 then
                per = ''
            else
                per = ('per: %f'):format(time/count)
            end

            local line = 'string:line()' .. ' x' .. count .. ' time ' .. ('%.6f'):format(time):ftrim(6) .. ' ' .. per
            lines[#lines+1] = line
            string.resetline()

        end
        local report = table.concat(lines,'\n')
        if clip then
            Spring.SetClipboard(report)
        end
        return report
    end
    ---------------------------
    function Code:Clear()
        if self == Code then
            for k, v in pairs(Code.instances) do
                Code.instances[k] = nil
            end
        else
            for k,v in pairs(self) do
                if k~='source' then
                    self[k] = nil
                end
            end
            self:GetCode()
        end
    end
    function Code:Update()
        local code = self.code
        self.code = nil
        local newcode = self:GetCode()
        if not self.code then
            return
        end
        if code ~= newcode then
            Echo('change detected in code ',self.source)
            self:Clear()
            self.code = newcode
        end
        return code, newcode
    end
    function Code:New(source)
        local codeObj = self.instances[source]
        if codeObj then
            codeObj:Update()
            return codeObj
        end
        codeObj = setmetatable({source=source, isInstance = true},{__index=Code})
        self.instances[source] = codeObj
        if not codeObj:GetCode() then
            return
        end
        return codeObj, codeObj.code
    end
    function Code:GetFile(wantUnco)
        if not wantUnco then
            return getfile(self.source, "r")
        end
        local uncommented = self.uncommented
        if not uncommented then
            local code = self:GetCode()
            if not code then
                Echo("couldnt retrieve the code of " .. self.source)
                return
            end
            local blanked
            uncommented, blanked = self:GetUncommentedAndBlanked3()
            self.uncommented, self.blanked = uncommented, blanked
        end
        if uncommented then
            local tmp = io.tmpfile()
            tmp:write(uncommented)
            tmp:seek("set")
            return tmp
        end
    end
    function Code:GetLines(wantUnco, wantLines)
        -- NOTE io.lines >>> gsub > gmatch
        -- len() > find > match
        -- testlines()
        if wantUnco then
            if self.lineuncoObj and (not wantLines or self.lineuncoObj.lines) then
                return self.lineuncoObj
            end
        elseif self.lineObj and (not wantLines or self.lineObj.lines) then
            return self.lineObj
        end
        local code, file
        if wantLines then
            file = self:GetFile(wantUnco)
        else -- we go faster using gsub if we dont want lines
            code = self:GetCode(wantUnco)
        end

        lineObj = getlines(file, code)
        -- Echo("getlinestime is ", (spDiffTimers(spGetTimer(), getlinestime)))


        if wantUnco then
            self.lineuncoObj = lineObj
        else
            self.lineObj = lineObj
        end
        return lineObj
    end
    function Code:GetCode(arg, arg2)
        local wantUnco
        if self==Code then
            self = self:New(arg)
            if not self then
                return
            end
            wantUnco = arg2
        else
            wantUnco = arg
        end
        if wantUnco then
            if self.uncommented then
                return self.uncommented, self
            end
        elseif self.code then
            return self.code, self
        end
        local file = self:GetFile(wantUnco)
        if file then
            local subject = file:read('*a')
            local len
            if subject and subject:find('\r') then
                Echo('code contains returns', self.source:match('[\\/][^\\/]+$'))
                subject = subject:removereturns()
                len = subject:len()
            else
                len = file:seek()
            end
            if wantUnco then
                self.uncommented = subject
                self.uncolen = len
            else
                self.code = subject
                self.codelen = len
            end
            file:close()
            return subject, self
        else
            Echo("couldnt retrieve file of " .. self.source)
        end
    end
    function Code:GetUncommentedAndBlanked3(tellTime) -- only checking one char at a time, 9K lines in 0.035 without blank string and 0.04 with 
        if self.uncommented and self.blanked then
            return self.uncommented, self.blanked
        end
        local code = self.code
        if not code then
            code = self:GetCode()
        end
        -- version checking only one char at a time, less convoluted but a tiny bit less fast too
        
        -- to acertain validity of char we check in precise order, short circuiting all the rest of checks
            --> block --> end of block
            --> comment --> check for block or end of line
            --> string --> end of string
            --> comment start
            --> string start
            --> block start

        -- gsub is fastest, avoiding using find is much better
        local pos = 1
        local pat = '()([\\\'\"%[%]%-\n])'
        local strStart, commentStart, blockStart = false, false, false
        local bracket, endBracket, minus = false, false, false
        local escaped = false

        -- code = code:codeescape()
        local n = 0
        local parts = {}
        local strings, sc, blocks = {}, 0, {}
        -- counts are only for debugging and can be commented out
        -- local count = 0
        -- local blockCount, stringCount, commentCount = 0,0,0
        local lens = {}
        local time = spGetTimer()
        code:gsub(
            pat,
            function(p, s)
                -- BLOCK PAIRING
                -- count = count + 1
                -- if count < 5 then
                --  Echo(p, code:at(p):readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
                -- end


                if blockStart then
                    if s == ']' then

                        if endBracket == p - 1 then
                            blockStart = false
                            -- blockCount = blockCount + 1
                            if commentStart then -- we end the block comment
                                commentStart = false
                                -- commentCount = commentCount + 1
                                -- keep only newlines in the block comment
                                local _, nl = code:sub(pos,p):gsub('\n','')
                                if nl==0 then -- check if both ends will be touching and conflicting
                                    if code:find('^%w',pos-3) and code:find('^%w',p+1) then
                                        n = n + 1
                                        parts[n] = ' '
                                    end
                                else
                                    n = n + 1
                                    parts[n] = ('\n'):rep(nl)
                                end
                                pos = p + 1 -- continue after brackets
                            else
                                n = n + 1
                                parts[n] = code:sub(pos, p-2) 
                                sc = sc + 1
                                strings[sc] = n--  note position in the table parts
                                blocks[n] = true
                                pos = p-1 -- continue at brackets
                            end
                        else
                            endBracket = p
                        end
                    end
                -- COMMENT ENDING
                elseif commentStart then
                    if s == '\n' then
                        commentStart = false
                        -- commentCount = commentCount + 1
                        pos = p
                    elseif s == '[' then 
                        if commentStart == p-3 and bracket == p-1 then
                            blockStart = true-- we're in block comment
                        elseif commentStart == p-2 then
                            bracket = p
                        end
                    end
                -- QUOTE PAIRING
                elseif strStart then
                    if escaped then
                        if escaped == p-1 then
                            escaped = false
                            return
                        else
                            escaped = false
                        end
                    end
                    if s == '\\' then
                        escaped = p

                    elseif s == strStart then  -- finish quote pairing
                        strStart = false
                        -- stringCount = stringCount + 1
                        if p-pos > 0 then
                            n = n + 1
                            parts[n] = code:sub(pos, p-1) -- isolate string and note position in the table parts
                            sc = sc + 1
                            strings[sc] = n
                            lens[sc] = p-pos
                            pos = p
                        end
                    end
                -- DETECTING STARTS
                -- checking comment start, then string start then block start
                elseif s == '-' then
                    -- Echo('check',p,'minus',minus)
                    if minus == p-1 then 
                        commentStart = p-1
                        n = n + 1
                        parts[n] = code:sub(pos, p-2) -- pick before the comment
                        pos = p+1 -- set after the comment
                    else
                        minus = p
                    end
                elseif s == '"' or s == "'" then
                        strStart = s -- quote pairing start
                        n = n + 1
                        parts[n] = code:sub(pos,p) -- include the quote
                        pos = p+1 
                elseif s == '[' then
                    if bracket == p-1 then
                        blockStart = true
                        n = n + 1
                        parts[n] = code:sub(pos, p) -- include the brackets
                        pos = p+1
                    else
                        bracket = p
                    end
                end
            end
        )
        if not commentStart then
            n = n + 1
            parts[n] = code:sub(pos)
        end



        local uncommented = table.concat(parts) --:decodeescape()
        time = spDiffTimers(spGetTimer(),time)
        local time2 = spGetTimer()
        for i=1, sc do -- substitute the string with spaces (or newline)
            local n = strings[i]
            local part = parts[n]
            if blocks[n] then
                parts[n] = part:gsub('[^\n\t]',' ')
            else
                parts[n] = (' '):rep(lens[i])
            end
        end
        local blanked = table.concat(parts)
        time2 = spDiffTimers(spGetTimer(),time2)
        if tellTime then
            Echo("TIME B3 ", time,time2, 'count',count,'parts',n,'strings parts',sc,'uncommented == blanked len',uncommented:len()==blanked:len())
        end
        -- Echo("stringCount, blockCount, commentCount is ", stringCount, blockCount, commentCount)
        -- Echo("strStart, blockStart, commentStart is ", strStart, blockStart, commentStart)

        -- Spring.SetClipboard(code)
        self.uncommented, self.blanked = uncommented, blanked
        return uncommented, blanked, time
    end
    do --- GET SCOPES AND FUNCS
        local function maketext(obj)
            local l, lend, p,s, name, auto, loc, inloop = obj.l,obj.lend,obj.p,obj.s,obj.name,obj.auto,obj.loc, obj.looplevel

            -- return ('[%d%s][%d]: %s%s%s%s end'):format(
            return ('[%d%s]: %s%s%s%s%s end'):format(
                l, (lend and (' - ' .. lend) or ''),
                -- p,
                s,
                (name and ( " '"..name.."'") or ''),
                (inloop>0 and ( " ~~"..inloop) or ''),
                (auto and " ['auto']" or ''),
                (loc and " ['local']" or '')
            )
        end
        local function getfunctionpos(blanked,unco,p,sol)
            -- Echo("lastpos is ", blanked:sub(lastpos,lastpos):readnl(),blanked:sub(p,p):readnl()) 
            -- Echo("nexposline is ", nexposline)
            local endPos = blanked:find('%)',p)
            -- Echo("blanked:sub(p, endPos) is ", blanked:sub(p, nexposline))
            local section =  unco:sub(sol,p-1)
            local _, name, loc, auto, field
            -- look after the word function
            _,_,name = unco:find('^%s-([%w%.:_]+)', p+8)
            if name then
                _,_,field = name:find('[%.%:]([^%.%:%s]+)$')
                loc = section:find('local%s+$')
                if loc then
                    p = loc + sol - 1
                end
            else
            -- look before

                auto = section:find('%(%s-%s-$')
                if auto then
                    section = section:sub(1, auto-1)
                end
                local sp
                -- look for field [something] -- TODO: OPTIMIZE
                sp, _, field = section:find('%[(.-)%]%s-=%s-$')
                if field then
                    local _sp
                    _sp, _, name = section:find('([^%s=]+)%s-=%s-$')
                    sp = _sp or sp
                else
                    sp, _, name  =  section:find('([%w%._]+)%s-=%s-$')
                    if name then
                        _,_,field = name:find('[%.%:]([^%.%:%s]+)$')
                    end
                end
                if sp then
                    loc = section:sub(1,sp-1):find('local%s+$')
                    p = sol + (loc or sp) - 1
                end
            end

            return p, endPos, auto, name, loc, field
        end

        local function getfunction(blanked, unco, p, l, sol)
            local fp = p
            local p, p2, auto, name, loc, field = getfunctionpos(blanked, unco, p, sol)
            s = unco:sub(p, p2)
            if auto then
                s = s:gsub('%(-%s-function','function')
            end

            return {
                fp = fp, p = p, p2 = p2,
                s = s, auto = auto, name = field or name, loc = loc, field = field,
                fullname = name or field,
                l = l,
            }
        end
        -- make the very start and very end of code to check
        function Code:GetFuncsAndLoops(wantLoops, tellTime, debugMe)
            local unco, blanked = self:GetUncommentedAndBlanked3()
            local lineObj = self:GetLines(true)
            local getline = lineObj.getline
            local time
            local parts, n
            if tellTime then
                time = spGetTimer()
            end
            if debugMe then
                parts, n = {}, 0
            end
            local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
            local ro2 = '[%s%(rin]'
            local le, re = '[%s%)}%]]', '[%s%(%)%]}%,;]'
            -- local anyl = '[%s%(%){}%[%]=,;\'\"]'

            local op1, op2 = '[idfwreu]', '[fouhen]' -- first and second letter possible for an opening
            local UEND = '^til'..ro
            local RPEND = '^peat'..ro
            local WEND = '^ile'..ro
            local FEND = '^nction'..ro
            local REND = '^r'..ro
            local DEND = '^d'..re
            local RO = '^'..ro

            local l, sol = 1
            local index,i  = {}, 0
            local loops, ends, funcs, reps = {}, {}, {}, {}

            index[10000] = true
            local function process(blanked,pat)
                local UEND, RPEND, WEND, FEND, REND, DEND, RO = UEND, RPEND, WEND, FEND, REND, DEND, RO
                local unco = unco
                local getline = getline
                local getfunction = getfunction
                blanked:gsub(
                    pat,
                    function(p,s)
                        if s == 'en' then
                            if blanked:find(DEND,p+2) then
                                i = i + 1
                                index[i] = p
                                ends[p] = true
                            end
                        elseif s == 'if' then
                            if blanked:find(RO,p+2) then
                                i = i + 1
                                index[i] = p
                            end
                        elseif s=='do' then
                            if blanked:find(RO,p+2) then
                                i = i + 1
                                index[i] = p
                            end
                        elseif s =='fo' then 
                            if blanked:find(REND,p+2) then
                                i = i + 1
                                index[i] = p
                                loops[p] = true
                            end
                        elseif s =='fu' then
                            if blanked:find(FEND,p+2) then
                                i = i + 1
                                index[i] = p
                                l, sol = getline(p)
                                funcs[p] = getfunction(blanked, unco, p, l, sol)
                            end
                        elseif s == 'wh' then
                            if blanked:find(WEND, p+2) then
                                i = i + 1
                                index[i] = p
                                loops[p] = true
                            end
                        elseif s =='re' then 
                            if blanked:find(RPEND,p+2) then-- a lot of useless match because of the term return or ret
                                i = i + 1
                                index[i] = p
                                reps[p] = true
                            end
                        elseif s =='un' then
                            if blanked:find(UEND,p+2) then
                                i = i + 1
                                index[i] = p
                                ends[p] = true
                            end
                        end

                    end
                )
            end
            -------------------------
            ----- get very first term if any
            local startcode = blanked:sub(1,8)
            local _,_,s = startcode:find('^('..op1..op2..')')
            if s == 'fu' then
                -- expand startcode to get to end of eventual function
                startcode = blanked:sub(1,blanked:find('%)'))
            end
            if s then
                process(startcode,'^()('..op1..op2..')')
            end
            ----- process rest except very end
            process(blanked,lo..'()('..op1..op2..')')
            -----
            ----- get very last end
            local _,_,p = blanked:find('()end',-3)
            if p then
                i = i + 1
                index[i] = p
                ends[p] = true
            end
            -------------------------
            -------------------------
            if index[10000] == true then index[10000] = nil end
            local started, s = {}, 0
            local level = 1
            local looplevel = 0
            local funcByLine = {}
            local loopPos = wantLoops and {}
            l = 1
            for i=1, i do
                local p = index[i]
                if ends[p] then
                    level = level - 1
                    -- Echo(p,'end at line',l)
                    local thing = started[level]
                    if thing then
                        if wantLoops then
                            if tonumber(thing) then -- end of for/while/repeat
                                local loopdef = thing..'-'..p
                                l = getline(p,l)
                                loopPos[thing..'-'..l] = looplevel
                                if debugMe then
                                    n = n + 1
                                    parts[n] = '['..thing..' - '..l..']: ~' ..looplevel ..  ('\t'):rep(40)..'end'
                                end
                                thing = true
                            end
                        end
                        if thing == true then
                            looplevel = looplevel - 1
                        else
                            looplevel = thing.looplevel
                            l = getline(p,l)
                            thing.lend = l
                            local def = thing.l..'-'..l
                            thing.def = def
                            local byline = funcByLine[def]
                            if byline then
                                if byline.extra then
                                    table.insert(byline.extra, thing)
                                else
                                    byline.extra = {thing}
                                end
                            else
                                funcByLine[def] = thing
                            end
                            -- Echo('func end at l',l)
                            if debugMe then
                                n = n + 1
                                parts[n] = maketext(thing)
                            end
                        end
                        started[level] = nil
                    end
                elseif loops[p] then
                    -- Echo(p,'loop at', level)
                    started[level] = true
                elseif funcs[p] then
                    local thing = funcs[p]
                    started[level] = thing
                    -- Echo(p,'func at ',level)
                    thing.looplevel = looplevel
                    looplevel = 0
                    level = level + 1
                elseif reps[p] then
                    if wantLoops then
                        started[level] = p
                    else
                       started[level] = true
                    end
                    looplevel = looplevel + 1
                    level = level + 1
                else -- do or if
                    if started[level] then
                        -- do after a for or while
                        if wantLoops then
                            l = getline(p,l)

                            started[level] = l
                        end
                        looplevel = looplevel + 1
                    end
                    level = level + 1
                    -- Echo(level,'do',p)
                end
            end
            if debugMe then
                Spring.SetClipboard(table.concat(parts,'\n'))
            end
            if tellTime then
                time = spDiffTimers(spGetTimer(),time)
                Echo('time',time,'matches',i)
            end

            self.funcByLine = funcByLine
            self.loops = loopPos
        end

    end




    function Code:GetFullCodeInfos(source)
        local obj = Code:New(source)
        obj:GetFuncsAndLoops(true) 
        return obj
    end

end















-- local N
-- do
--     include('keysym.h.lua')
--     N = KEYSYMS.N
--     KEYSYMS = nil
-- end
-- function widget:KeyPress(key,mods, isRepeat)
--     if isRepeat then
--         return
--     end
--     if key == N and mods.alt then
--         Reload()
--         return true
--     end
-- end
-- Echo('CodeHandler is loaded.')
function Reload()
        Echo('CodeHandler is getting reloaded.')
    Spring.SendCommands('luaui disablewidget '.. widget.GetInfo().name)
    Spring.SendCommands('luaui enablewidget ' .. widget.GetInfo().name)
end
WG.Code.Reload = Reload


































----------------------------------------------------------------------------
--------------------------------DRAFT-----------------------------------
--[[
function Code:GetUncommented() -- only checking one char at a time, 9K lines in 0.035 without blank string and 0.04 with 
    -- version checking only one char at a time, less convoluted but a tiny bit less fast too
    local code = self:GetCode()

    if code:find('\r') then
        code = code:removereturns()
    end
    -- to acertain validity of char we check in precise order, short circuiting all the rest of checks
        --> block --> end of block
        --> comment --> check for block or end of line
        --> string --> end of string
        --> comment start
        --> string start
        --> block start

    -- gsub is fastest, avoiding using find is much better
    local pos = 1
    local pat = '()([\\\'\"%[%]%-\n])'
    local strStart, commentStart, blockStart = false, false, false
    local bracket, endBracket, minus = false, false, false
    local escaped = false

    -- code = code:codeescape()
    local n = 0
    local parts = {}

    -- counts are only for debugging and can be commented out
    -- local count = 0
    -- local blockCount, stringCount, commentCount = 0,0,0

    local time = spGetTimer()
    code:gsub(
        pat,
        function(p, s)
            -- BLOCK PAIRING
            -- count = count + 1
            -- if count < 5 then
            --  Echo(p, code:at(p):readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
            -- end


            if blockStart then
                if s == ']' then

                    if endBracket == p - 1 then
                        blockStart = false
                        -- blockCount = blockCount + 1
                        if commentStart then -- we end the block comment
                            commentStart = false
                            -- commentCount = commentCount + 1
                            -- keep only newlines in the block comment
                            local _, nl = code:sub(pos,p):gsub('\n','')
                            if nl==0 then -- check if both ends will be touching and conflicting
                                if code:find('^%w', pos-3) and code:find('^%w',p+1) then
                                    n = n + 1
                                    parts[n] = ' '
                                end
                            else
                                n = n + 1
                                parts[n] = ('\n'):rep(nl)
                            end
                            pos = p + 1 -- continue after brackets
                        end
                    else
                        endBracket = p
                    end
                end
            -- COMMENT ENDING
            elseif commentStart then
                if s == '\n' then
                    commentStart = false
                    -- commentCount = commentCount + 1
                    pos = p
                elseif s == '[' then 
                    if bracket == p-1 and commentStart == p-3 then
                        blockStart = true-- we're in block comment
                    elseif commentStart == p-2 then
                        bracket = p
                    end
                end
            -- QUOTE PAIRING
            elseif strStart then
                if escaped then
                    if escaped == p-1 then
                        escaped = false
                        return
                    else
                        escaped = false
                    end
                end
                if s == '\\' then
                    escaped = p

                elseif s == strStart then  -- finish quote pairing
                    strStart = false
                end
            -- DETECTING STARTS
            -- checking comment start, then string start then block start
            elseif s == '-' then
                -- Echo('check',p,'minus',minus)
                if minus == p-1 then 
                    commentStart = p-1
                    n = n + 1
                    parts[n] = code:sub(pos, p-2) -- pick before the comment
                    pos = p+1 -- set after the comment
                else
                    minus = p
                end
            elseif s == '"' or s == "'" then
                    strStart = s
            end
        end
    )
    if not commentStart then
        n = n + 1
        parts[n] = code:sub(pos)
    end



    code = table.concat(parts) --:decodeescape()
    time = spDiffTimers(spGetTimer(),time)

    Echo("TIME U ", time, 'count',count,'parts',n)
    -- Echo("stringCount, blockCount, commentCount is ", stringCount, blockCount, commentCount)
    -- Echo("strStart, blockStart, commentStart is ", strStart, blockStart, commentStart)

    -- Spring.SetClipboard(code)
    return code, time
end
--]]
--[[
function Code:BlankStrings() -- faster solution exists
    if self.blanked then
        return self.blanked
    end
    local code = self:GetUncommented()-- the code need to be uncommented for this to work properly
    code = code:codeescape()
    local patterns = {
        ["'"] = "'",['"'] = '"',['[['] = '%s-%[%[', [']\]'] = '%]%]'
    }
    local strStarts = {"'",'"','[['}
    local strEnds = {["'"] = "'", ['"'] = '"', ['[['] = ']\]' }
    local isBlock = {[']\]'] = true}
    local endCode = code:len()
    -- local strings, scount = {}, 0
    local find = string.find
    local pos = 1
    local parts, n = {}, 0
    while pos < endCode do
        local strStart, this_s
        for i, s in ipairs(strStarts) do
            local _, spos = find(code,patterns[s],pos)
            if spos then
                if not strStart or spos < strStart then
                    strStart = spos
                    this_s = s
                end
            end
        end
        if strStart then
            local this_sEnd = strEnds[this_s]
            local _, strEnd = find(code,patterns[this_sEnd],strStart + 1)
            if strEnd then
                if strStart > 1 then
                    n = n + 1
                    parts[n] = code:sub(pos,strStart)
                end
                n = n + 1
                local substitute
                if isBlock[this_sEnd] then

                    substitute = code:sub(strStart+1, strEnd - this_sEnd:len()):gsub('[^\n\t]',' ')
                else
                    local len = strEnd - strStart - this_sEnd:len()
                    substitute = (' '):rep(len)
                end
                parts[n] = substitute .. this_sEnd

                pos = strEnd + 1
                Echo('=> pos',strEnd)
            else
                break
            end
        else
            break
        end
    end
    local ret
    if n > 0 then
        n = n + 1
        parts[n] = code:sub(pos, endCode):decodeescape()
        ret = table.concat(parts)
    else
        ret = self.code
    end
    self.blanked = ret
    return ret
end
--]]
--[[
function Code.RemoveEmptyLines(str)
    local charSym = '%S'
    local t, n = {}, 0
    for line in str:gmatch('[^\n]+') do
        local _,chars = line:gsub(charSym,'')
        if chars>0 then
            n = n + 1
            t[n] = line
        end
    end
    return table.concat(t,'\n')
end
--]]
--[[
function Code.CheckIfValid(pos,line,sym,endPos) -- -- NOTE: CheckIfValid is used to Uncomment in a particular order, it doesn't ensure the validity of a sym in any circumstance
    local tries = 0
    local inString, str_end, quote = line:find("([\"']).-"..sym..".-%1")
    -- check if the found sym is not actually before this, or if the number of quotes are actually even
    if inString and ( pos<inString or select(2, line:sub(1,str_end):gsub(quote,''))%2==1 ) then
        inString=false
    end
    while inString do -- try a next one in the line, if any
        tries = tries + 1 if tries>100 then Echo('TOO MANY TRIES 2') return end
        pos, endPos = line:find(sym, str_end+1)
        if not pos then
            return
        end
        inString, str_end, quote = line:find("([\"']).-"..sym..".-%1",str_end+1)
        if inString and ( pos<inString or select(2, line:sub(1,str_end):gsub(quote,''))%2==1 ) then
            inString=false
        end
    end
    return pos, endPos
end
--]]
--[[
function Code.GetSym(sym,curPos,code, tries) -- NOTE: GetSym is used to Uncomment in a particular order, it doesn't ensure the validity of a sym in any circumstance
    local pos, endPos = code:find(sym, curPos)
    if not pos then
        return
    end
    local line,sol = code:line(pos)
    
    pos, endPos = Code.CheckIfValid(pos - sol + 1, line, sym, endPos - sol + 1)-- convert to pos of the line
    if not pos then
        tries = (tries or 0) + 1 if tries>500 then Echo('TOO MANY TRIES 3') return end
        return Code.GetSym(sym,sol+line:len(),code,tries)
    end
    return pos and pos + sol - 1, line, sol, endPos and endPos + sol - 1
end
--]]
--[[
function Code.GetSym(sym,curPos,code,lines,getline,tries) -- NOTE: GetSym is used to Uncomment in a particular order, it doesn't ensure the validity of a sym in any circumstance
    local pos, endPos = code:find(sym, curPos)
    if not pos then
        return
    end

    local l, sol = getline(pos)
    local line = lines[l]
    
    pos, endPos = Code.CheckIfValid(pos - sol + 1, line, sym, endPos - sol + 1)-- convert to pos of the line
    if not pos then
        tries = (tries or 0) + 1 if tries>500 then Echo('TOO MANY TRIES 3') return end
        return Code.GetSym(sym,sol+line:len(),code,lines,getline,tries)
    end
    return pos and pos + sol - 1, line, sol, endPos and endPos + sol - 1
end
--]]


--[[
local function TooSlow(code) -- too slow, getting only uncommented
    local commentSym ='%-%-'
    local blockSym = '%[%['
    local endBlockSym = '%]%]'
    local charSym = '%S'
    local nl = '\n'
    code = code:codeescape():removereturns()
    -- as they are rare, we isolate blocks to treat the rest easily
    local parts, n = {}, 0
    local count = 0
    local pos = 1
    local count = 0
    local remaining = 0
    local function removecommentlines(code)
        return code:gsub(
            -- '()(' .. noquoteSym .. '-)' .. commentSym .. '.-\n',
            -- '\n' .. commentSym .. '.-',
            -- commentSym .. '.-\n',
            -- '(.)(' .. commentSym .. '.-)\n',
            -- '\n' .. commentSym .. '.-\n',
            '\n[^\n%S]-' .. commentSym .. '[^\n]+',
            function(s,s2)
                -- count = count +1
                -- if count < 15 then
                    -- Echo(s:readnl())
                -- end
                -- if count < 5 then
                --  Echo(select(2,code:sub(1,p):gsub('\n','')),s:readnl(),s:len(),s2)
                -- end
                return '\n'
            end
        )
    end
    local incount = 0
    local function verifinstring(code, after)
        local inString = false
        code:gsub(
            "[\"\']",
            function(s)
                if not inString then
                    inString = s
                elseif inString == s then
                    inString = false
                end
            end
        )
        if not inString then
            return code
        else
            local es = after:find(inString)
            if es then
                return code .. after:sub(1,es) ..  after:sub(es+1):gsub( 
                    '([^\n]-)(' .. commentSym .. '[^\n]+)',
                    verifinstring
                )
            end
        end
    end



    local lonely = 0
    local function removecommentlines(code)
        if code:find('^([^\n"]-)' .. commentSym .. '.-\n') then
            code = code:gsub(
                '^([^\n\'\"]-)' .. commentSym .. '[^\n]+','%1'
            )
            code = code:gsub( 
                '^([^\n]-)(' .. commentSym .. '[^\n]+)',
                verifinstring
            )

        end
        -- line comments where line doesnt contain any string (cannot catch lonely comment -- we avoid using .- as it take much longer)
        code = code:gsub(
            '(\n[^\n\'\"]-)' .. commentSym .. '[^\n]+','%1'
        )
        code = code:gsub( 
            '(\n[^\n]-)(' .. commentSym .. '[^\n]+)',
            verifinstring
        )
        code = code:gsub( -- this up the time by 0.004 :/
            '(\n[^\n\'\"]-)%-%-','%1'
            -- function(p,s, s2)
            --  -- Echo("s2:len() is ", s2:len(),'l',code:nline(p),code:line(p):readnl(),'s2',s2 and s2:readnl())
            --  lonely = lonely + 1
            --  return s
            --  -- if s2 == '' then
            --  --  return s
            --  -- else
            --  --  Echo('S2 HAS SOMETHING')
            --  -- end
            -- end
        )
        return code
    end


    -- Spring.SetClipboard(removecommentlines(1,1000))
    -- if true then
    --  return
    -- end
    local pat = '()([\"\'%-])'
    local function verify(pos)
        local sol = code:sol(pos)
        local strStart, minus, inComment
        code:sub(sol,pos-1):gsub(
            pat,
            function(p,s)
                if inComment then
                    return false
                elseif strStart then
                    if s == strStart then
                        strStart = false
                    end
                elseif s== '-' then
                    if minus == p-1 then
                        inComment = p
                    else
                        minus = p
                    end
                else
                    strStart = s
                end
            end
        )
        return inComment and inComment + sol - 1, strStart
    end
    local pos = 1
    local block, b = {}, 0
    local patBlock = blockSym .. '.-' .. endBlockSym
    local blkStart, blkEnd = code:find(blockSym .. '.-' .. endBlockSym)

    local tries = 0
    local done = 0
    while blkStart do
        tries = tries + 1 if tries > 1000 then Echo('WRONG LOOP BLK') break end
        local inComment, inString = verify(blkStart)
        -- Echo("inComment, inString is ", inComment, inString,'start end', blkStart, blkEnd)
        if inComment then
            if inComment == blkStart-1 then
                -- b = b + 1 block[b] = code:sub(blkStart, blkEnd)
                if done < 1000 then
                    done = done + 1
                    n = n + 1
                    -- -- Echo('==',pos,blkStart - 3,'l',code:nline(pos),code:nline(blkStart))
                    local code = code:sub(pos, blkStart - 3)
                    -- code = removecommentlines(code)
                    parts[n] = removecommentlines(code) -- treat before the block
                else
                    n = n + 1
                    -- -- Echo('==',pos,blkStart - 3,'l',code:nline(pos),code:nline(blkStart))
                    local code = code:sub(pos, blkStart - 3)
                    parts[n] = code

                end
                -- Echo('block comment',n,code:sub(blkStart-2,blkEnd))
                -- parts[n] = ('\n'):rep(code:sub(blkStart-2,blkEnd):gsub('\n',''))

                -- parts[n] = code:sub(blkStart-2,blkEnd):gsub('[^%]%[]','-')
                local _,nl = code:sub(blkStart-2,blkEnd):gsub('\n','')
                if nl > 0 then
                    n = n + 1
                    parts[n] = ('\n'):rep(nl)
                elseif code:sub(blkStart-3,blkStart-3):find('%w') and code:sub(blkEnd+1,blkEnd+1):find('%w') then
                    n = n + 1
                    parts[n] = ' '
                end
                pos = blkEnd+1
                blkStart, blkEnd = code:find(patBlock, pos)
            else
                local p = code:find('\n',inComment)
                blkStart, blkEnd = code:find(patBlock, p+1)
            end
        elseif inString then
            local p = code:find(inString,blkStart)
            blkStart, blkEnd = code:find(patBlock, p+1)
        else
            -- n = n + 1
            -- b = b + 1 block[b] = code:sub(blkStart, blkEnd)
            -- parts[n] = removecommentlines(pos, blkStart - 1)

            -- Echo('block ',n,code:sub(blkStart, blkEnd))
            n = n + 1
            parts[n] = code:sub(blkStart, blkEnd)
            pos = blkEnd+1
            blkStart, blkEnd = code:find(patBlock, blkEnd+1)

        end
    end
    -- Echo("pos is ", pos,'parts',n)
    n = n + 1
    local c = code:sub(pos)
    parts[n] = removecommentlines(c)
    code = table.concat(parts)
    Echo('lonely',lonely)

    -- Echo('blocks',b)
    -- Spring.SetClipboard(block[1])
    code = code:decodeescape()
    return code
end
--]]
---- counting time of string:line
    -- if string.oriline then
    --     string.line = string.oriline
    --     string.oriline = nil
    -- end
    -- if false and not string.oriline then
    --     string.oriline = string.line
    --     string.linetime = 0
    --     string.linecount = 0
    --     function string.line(self,p)
    --         local time = spGetTimer()
    --         local line, sol = string.oriline(self,p)
    --         string.linetime = string.linetime + spDiffTimers(spGetTimer(), time)
    --         string.linecount = string.linecount + 1
    --         return line, sol
    --     end
    --     function string.resetline()
    --         string.linetime = 0
    --         string.linecount = 0
    --     end
    -- end
--[[
local function testlines()
    local time1 = Spring.GetTimer()
    local source = "LuaUI\\Widgets\\UtilsFunc.lua"
    local file = io.open(source, "r")
    local code = file:read('*a')
    file:close()
    local tmp = io.tmpfile()
    tmp:write(code:codeescape())
    tmp:seek("set")

    time1 = Spring.DiffTimers(Spring.GetTimer(), time1)
    local time2 = Spring.GetTimer()
    local i = 1
    local lines = {''}
    local lpos = {1}
    local pos = 1
    for line in tmp:lines() do
        lines[i] = line
        i = i + 1
        pos = pos + line:len() + 1
        lpos[i]  = pos
    end
    lpos[i] = nil
    tmp:close()
    time2 = Spring.DiffTimers(Spring.GetTimer(), time2)
    Echo(time1, time2,'lines',#lines)
end
--]]
-----------------------------------------------------------------
----------------------- GET SCOPES AND FUNCS DRAFT -- not fully working (when double repeat loop) but keeping the code
-----------------------------------------------------------------
--[[
do -------- MakeFuncInfo ------------
    local namePat = '([%w_]+)'
    local methodPat = '[%a_]+[%w_%.]-:([%a_]+[%w_]+)'
    local fieldPat = '[^%s%c()]+([%.%[]+[^%.%[%s%c()]+)'
    local typePatterns = {
        local1 = 'local%s+'..namePat..'%s-=%s-function',
        local2 = 'local%s+function%s+'..namePat,
        up1 = 'function%s+'..namePat..'%s-%(',
        up2 = namePat..'%s-=%s-function%s-%(',
        field1 = 'function%s+'..fieldPat..'%s-%(',
        field2 = fieldPat..'%s-=%s-function%s-%(',
        field3 = 'function%s+'..methodPat..'%s-%(',
    }
    local patternOrder = {
        'local1', 'local2', 'up1', 'field1', 'field2', 'field3', 'up2'
    }
    local revPrefixes = {
        local1 = ('local%s+'..namePat..'%s-=%s-'):patternreverse(),
        local2 = ('local%s+'):patternreverse(),
        up2 = (namePat..'%s-=%s-'):patternreverse(),
        field2 = (fieldPat..'%s-=%s-'):patternreverse(),
    }
    local prefOrder = {
        'local1',
        'local2',
        'field2',
        'up2',
    }
    function MakeFuncInfo(code,stPosFunc,endFunc,level,line,l, lend, lpos)
        local format, name = 'anonymous', 'no_name'
        local definition = 'anonymous function'
        local funcLPos = stPosFunc - lpos + 1
        local offset = 0
        -- find the real start of the function definition
        for _, p in ipairs(prefOrder) do
            local patPrefix = revPrefixes[p]
            local ps, pe = line:reversefind(patPrefix,funcLPos, true)
            if ps then
                offset = pe - ps + 1
                break
            end
        end
        funcLPos = funcLPos - offset
        stPosFunc = stPosFunc - offset

        local linepart = line:sub(funcLPos)
        for _, f in ipairs(patternOrder) do
            local pat = typePatterns[f]
            local s,e, _name = linepart:find(pat)
            if _name then
                format = f
                name = _name
                definition = linepart:sub(s,e)
                break
            end
        end
        if format:match('field') and name:at(1)=='.' then
            name = name:remove(1,1)
        end

        local funcInfo = {
            definition = definition,
            name = name,
            pos = stPosFunc,
            inline = funcLPos,
            line = l,
            linepos = lpos,
            format = format,
            endcode = endFunc,
            lend = lend,
            level = level,
            autoexec = code:find('^%s-%)%s-%(',endFunc+1),
            defID = l .. '-' .. lend,

        }
        return funcInfo
    end
end

do ------------------ GetCodeScope ------------------
    -- local lo, ro = '[%s%(%)%]}%[]', '[%s%(]'
    -- local le, re = '[%s%)%]}]', '[%s%(%)%]}%,]'
    local lo, ro = '[%s%(%){}%[%]=,;\'\"]', '[%s%(;]'
    -- local ro2 = '[%s%(rin]'
    local le, re = '[%s%)%]}]', '[%s%(%)%]}%,;]'
    -- local anyl = '[%s%(%){}%[%]=,;\'\"]'
    local anyl = '[^%w_:.]'
    local insert, remove = table.insert, table.remove

    local openings, startOpenings = {}, {}
    local purged_openings = {}
    local openingTerms = {
        'IF',
        'DO',
        'FUNCTION',
        'WHILE',
        'FOR',
        'REPEAT',
    }

    local correspondingEnds = {
        IF = 'end',
        DO = 'end',
        FUNCTION = 'end',
        WHILE = 'do',
        FOR = 'do',
        REPEAT = 'until',
    }
    local uniques = {}
    for _,term in pairs(openingTerms) do
        openings[term] = lo..term:lower()..ro
        if term~='WHILE' and term~='FOR' then
            purged_openings[term] = openings[term]
        end
        startOpenings[term] = '^'..term:lower() .. ro
        local End = correspondingEnds[term]
        if not uniques[End] then
            uniques[End] = { le..End..re, le..End..'$' }
        end
        correspondingEnds[term] = uniques[End]
    end
    uniques = nil

    local function GetScopeStart(pos, code, searchTerms)
        -- look for a keyword at pos
        if code:at(pos):find('%a') then -- get the start of word in case we're in the middle of it
            while pos>1 and code:at(pos-1):find('%a') do
                pos = pos -1
            end
        end
        -- look first anchored terms
        for _,term in pairs(searchTerms) do
            local _, this_o = code:find(startOpenings[term], pos)
            if this_o then
                return this_o, _, term
            end
        end
        --
        local o
        for _,term in pairs(searchTerms) do
            local _, this_o = code:find(openings[term], pos)
            if this_o and (not o or this_o < o) then
                o = this_o
                scopeStart, scopeName = _+1, term
            end
        end
        return o, scopeStart, scopeName
    end
    function Code:GetCodeScope(pos,searchTerms, debugMe)
        local code = self.blanked
        if not code then
            code = select(2,self:GetUncommentedAndBlanked3())
        end
        -- debugMe = true
        local line, lvl
        local level = 1
        -- if debugMe then
            local lineObj = self:GetLines(true)
            local getline = lineObj.getline
            line = function(p) return '['..getline(p)..']' end
            lvl = function(level) return level..('    '):rep(level) end
        -- end
        local o, c, _ = false, false, false
        local scopeStart, scopeName
        pos = pos or 1
        o, scopeStart, scopeName = GetScopeStart(pos, code, searchTerms or openingTerms)
        if not o then
            -- Echo("Couldn't find any opening from pos " .. pos .. (term and ' with term '..term or '') ..'.')
            return
        end
        if self.source:match('debughandler') and line(o):match('61') then
            debugMe = true
        end
        -- purge from WHILE,FOR,REPEAT to make it faster
        local openings = purged_openings
        --
        local currentOpening = false
        local newOpening = scopeName
        local closePat = false
        local buffered = {}

        if debugMe then
            Echo(lvl(level)..'first opening ' .. newOpening .. ' at '..line(o)..o)
        end
        local tries = 0
        local pushClosing = false
        while true do
            tries = tries+1
            -- if debugMe and tries>5 or tries>20 then Echo('ERROR, too many tries',o) return c or o end
            if debugMe and tries>20 or tries>500 then Echo('ERROR TOO MANY OPENINGS FOUND IN SCOPE',o) return c or o end
            local c_start

            if closePat ~= correspondingEnds[newOpening] then 
                -- update the pattern and look for closing from the opening pos
                closePat = correspondingEnds[newOpening]
                c_start = o
                if debugMe then
                    -- Echo(lvl(level)..'new ending to find, starting from last opening ' ..line(o).. o)
                    -- Echo(lvl(level)..'search closing from o' ..line(o).. o)
                end
            else
                -- we already found that closing, push a further closing if we are going down a level
                if pushClosing then
                    if debugMe then
                        Echo(lvl(level)..'closing already found  but consumed '.. line(c)..c .. ' ('..#buffered..' left) and get next closing')
                    end
                    c_start = c
                end
            end
            if c_start then
                for i = 1, 2 do
                    _, c = code:find(closePat[i], c_start)
                    if c then
                        break
                    end
                end
                if not c then
                    if not debugMe then
                        local lineObj = self:GetLines(true)
                        local getline = lineObj.getline
                        line = function(p) return '['..getline(p)..']' end
                    end
                    Echo('ERROR, couldnt find ending of current opening '.. newOpening, line(o)..o,'c_start',line(c_start)..c_start,code:at(c_start),'source len',code:len(),source,'source')
                    return
                end
                if debugMe then

                    Echo(lvl(level)..'new closing: => ' ..correspondingEnds[newOpening][1]:match('%a%a+'):upper()..line(c).. c)
                end
            end
            currentOpening = newOpening
            newOpening = false
            pushClosing = false
            local new_o = false
            -- opening is resolved to current closing c,
            -- look for a next opening positionned before the current closing
            for term,pat in pairs(openings) do
                if (currentOpening~='WHILE' and currentOpening~='FOR') or term~='DO' then
                    if debugMe then
                        Echo('look for new opening from ',o)
                    end
                    local _, this_o = code:find(pat, o)
                    if (this_o and this_o < c) and (not new_o or this_o < new_o) then
                        new_o = this_o
                        newOpening = term
                    end
                end
            end
            if new_o then
                o = new_o
                insert(buffered, currentOpening) -- buffer the last found opening before going to new
                level = level + 1
                if debugMe then
                    -- Echo(lvl(level)..'new opening ' .. newOpening .. ' at ' ..line(new_o).. new_o, 'buffering previous opening ' .. currentOpening)
                    Echo(lvl(level)..'new opening ' .. newOpening .. ' at ' ..line(new_o).. new_o)
                end
            else
                if currentOpening == 'WHILE' or currentOpening == 'FOR' then
                    if debugMe then
                        Echo(lvl(level)..'special case ' .. currentOpening .. ' adding DO in the buffer' )
                    end
                    insert(buffered,'DO')
                    o = c
                    level = level + 1
                end
                -- no new opening found, that opening has been resolved by c, we pick the remaining buffered
                newOpening = remove(buffered)
                level = level - 1
                if newOpening then
                    pushClosing = true -- even if we already found the corresponding closing, we push for a new one
                    if debugMe then
                        Echo(lvl(level)..'retrieved ' .. newOpening)
                    end
                end
                if not newOpening then
                    -- the whole closure is resolved
                    if debugMe then
                        Echo(lvl(level)..'concluded with '..currentOpening ..'...'..correspondingEnds[currentOpening][1]:match('%a%a+'):upper() .. ' at ' ..line(c).. c, code:sub(c-1,c+1))
                    end
                    ----- now useless
                    -- if currentOpening == 'WHILE' or currentOpening == 'FOR' then
                    --  if debugMe then
                    --      Echo('special case for ' .. currentOpening, 'redoing scope search from ' .. correspondingEnds[currentOpening][1]:match('%a%a+'):upper())
                    --  end
                    --  c = select(2,GetCodeScope(c-1, code))
                    -- end
                    ------
                    c = c and code:at(c)~='%a' and c-1 or c
                    return scopeStart, c, scopeName
                else
                    if debugMe then
                        -- Echo(lvl(level)..'openings to be solved '..#buffered+1 .. (buffered[#buffered] and ' (last buffered '..buffered[#buffered]..')' or '') ..', now solving ' .. newOpening,line(o)..o,'cur close:'..line(c)..c)
                        -- Echo(lvl(level)..'popped one, now :'..line(o)..o..newOpening)
                        -- Echo(lvl(level)..'next to solve '..newOpening)
                    end
                end
            end
            -- find the next closing
        end
    end
end
    -------------------
function Code:GetCodeScopes(wantFuncs, wantLoops, debugMe,pos, endArg) 
    if self == Code then
        self = self:New(wantFuncs)
        wantFuncs, wantLoops, debugMe,pos = wantLoops, debugMe,pos, endArg
    end
    if self.source:match('debughandler') then
        Echo('OK')
        debugMe = true
    end
    -- debugMe = true
    local code, blanked = self:GetUncommentedAndBlanked3()
    local searchTerms = {}
    if wantLoops then
        table.insert(searchTerms, 'FOR')
        table.insert(searchTerms, 'WHILE')
        table.insert(searchTerms, 'REPEAT')
    end
    if wantFuncs then
        table.insert(searchTerms, 'FUNCTION')
    end
    local lineObj = self:GetLines(true, true)
    local getline = lineObj.getline
    local lines = lineObj.lines

    local funcByLine = {}
    local loops = {}
    local loopTerms = {
        'WHILE',
        'FOR',
        'REPEAT',
    }
    pos = pos or 1
    local tries = 0
    local scopeStart, scopeEnd, scopeName
    local count = 0
    local tbl =  debugMe and {}
    -- pos = lpos[587]
    local level = 0
    local endcode = 0
    local looplevel = 0
    local scopeInfo = {
        endcode = 0,
        looplevel = 0,
    }
    local inScope = {[0]=scopeInfo}

    local scopeInfo
    local l, lend, lpos = 1, 1, 1
    while pos do
        tries = tries + 1
        if tries > 1000 then Echo('too many tries to find scopes!!') break end
        -- Echo('----')
        local new_pos = false
        local scopeStart, scopeEnd, scopeName = self:GetCodeScope(pos,searchTerms,false)
        if scopeEnd then
            -- MakeFuncInfo(code,stPosFunc,endFunc,level,lines,lpos)
            while scopeEnd > endcode and level>0 do
                level = level - 1
                scopeInfo = inScope[level]
                looplevel = scopeInfo.looplevel
                endcode = scopeInfo.endcode
            end

            l, lpos = getline(scopeStart,lend)
            lend = getline(scopeEnd,l)
            if scopeName == 'FUNCTION' then
                local funcInfo = MakeFuncInfo(code,scopeStart,scopeEnd,level,lines[l],l, lend, lpos)
                local defID = funcInfo.defID -- so it can be found out from debug.getinfo
                if not funcByLine[defID] then
                    funcByLine[defID] = {}
                end
                table.insert(funcByLine[defID], funcInfo) -- multiple function can be on the same line, (we can't discern it from debug.getinfo??)
                looplevel = 0
            else
                local defID = l .. '-' .. lend
                if not loops[defID] then
                    loops[defID] = {}
                end
                local loop = {defID = defID, line=l, endline=lend, pos = scopeStart, endcode = scopeEnd, name=scopeName, looplevel = looplevel}
                table.insert(loops[defID], loop) 

                looplevel = looplevel + 1
            end
            endcode = scopeEnd
            level = level + 1
            local scopeInfo = {
                looplevel = looplevel,
                endcode = scopeEnd,
            }
            -- Echo(tries,"scopeName, looplevel is ", scopeName, looplevel)
            inScope[level] = scopeInfo
            local this_pos = blanked:find('%A',scopeStart)
            if this_pos and (not new_pos or this_pos < new_pos) then
                new_pos = this_pos
            end
            count = count + 1
            if tbl then
                local l = getline(scopeStart)
                local lend = getline(scopeEnd)
                local msg = '#' .. count .. ' ' ..
                    scopeName .. ' at ' .. scopeStart .. '...' .. scopeEnd
                    .. '\n['..l..']'..blanked:sub(scopeStart, scopeStart+20) .. '...'
                    .. '\n['..lend..']'..lines[lend]
                    .. '\nlevel '..level..', looplevel '..looplevel
                    .. '\n-------------'
                tbl[count] = msg
            end
        end
        pos = new_pos
    end

    if tbl then
        Echo('SET CLIP')
        Spring.SetClipboard(table.concat(tbl,'\n'))
    end
    self.funcByLine = funcByLine
    self.loops = loops
    self.scopeCount = count
    return funcByLine, loops, count
end
--]]

-----------------------------------------------------------------
----------------------- ///End scopes and funcs DRAFT 
-----------------------------------------------------------------
--[[
-- interesting but doesnt better really the speed using table instead of a long if/elseif
local GetUncommentedAndBlanked4
do
    local pos = 1
    local commentStart, blockStart = false, false
    local bracket, endBracket, minus = false, false, false
    local escaped = false
    local status = false
    local code
    -- code = code:codeescape()
    local n = 0
    local parts = {}
    local strings, sc, blocks = {}, 0, {}
    local lens = {}

    local tbl = {}
    local function clear()
        for i,t in pairs({ parts, strings, blocks, lens}) do
            for k,v in pairs(t) do
                t[k] = nil
            end
        end
    end

    tbl['blkCom'] = function(p,s)
        if s == ']' then
            if endBracket == p - 1 then
                -- blockCount = blockCount + 1
                status = false
                -- commentCount = commentCount + 1
                -- keep only newlines in the block comment
                local _, nl = code:sub(pos,p):gsub('\n','')
                if nl==0 then -- check if both ends will be touching and conflicting
                    if code:sub(pos-3,pos-3):find('%w') and code:sub(p+1,p+1):find('%w') then
                        n = n + 1
                        parts[n] = ' '
                    end
                else
                    n = n + 1
                    parts[n] = ('\n'):rep(nl)
                end
                pos = p + 1 -- continue after brackets

            else
                endBracket = p
            end
        end
    end

    tbl['blk'] = function(p,s)
        if s == ']' then
            if endBracket == p - 1 then
                status = false
                -- blockCount = blockCount + 1
                n = n + 1
                parts[n] = code:sub(pos, p-2) -- add string and note position in the table parts
                sc = sc + 1
                strings[sc] = n
                blocks[n] = true
                pos = p-1 -- continue at brackets
            else
                endBracket = p
            end
        end
    end

    tbl['comm'] = function(p,s)

        if s == '\n' then
            commentStart = false
            status = false
            -- commentCount = commentCount + 1
            pos = p
        elseif s == '[' then 
            if commentStart == p-3 and bracket == p-1 then
                status = 'blkCom'
                commentStart = false
            elseif commentStart == p-2 then
                bracket = p
            end
        end
    end
    tbl['str'] = function(p, s)
        -- QUOTE PAIRING
        if s == "'" then
            status = false
            -- stringCount = stringCount + 1
            if p-pos > 0 then
                n = n + 1
                parts[n] = code:sub(pos, p-1) -- isolate string and note position in the table parts
                sc = sc + 1
                strings[sc] = n
                lens[sc] = p-pos
                pos = p
            end
        elseif s == '\\' then
            escaped = p
        end
    end
    tbl['strD'] = function(p, s)
    -- QUOTE PAIRING
        if s == '"' then
            status = false
            -- stringCount = stringCount + 1
            if p-pos > 0 then
                n = n + 1
                parts[n] = code:sub(pos, p-1) -- isolate string and note position in the table parts
                sc = sc + 1
                strings[sc] = n
                lens[sc] = p-pos
                pos = p
            end
        elseif s == '\\' then
            escaped = p
        end
    end
    tbl['-'] = function(p)
        if minus == p-1 then 
            commentStart = p-1
            status = 'comm'
            n = n + 1
            parts[n] = code:sub(pos, p-2) -- pick before the comment
            pos = p+1 -- set after the comment
        else
            minus = p
        end
    end
    tbl["'"] = function(p)
        status = "str" -- quote pairing start
        arg = "'"
        n = n + 1
        parts[n] = code:sub(pos,p) -- include the quote
        pos = p+1 
    end
    tbl['"'] = function(p)
        status = 'strD' -- quote pairing start
        arg = '"'
        n = n + 1
        parts[n] = code:sub(pos,p) -- include the quote
        pos = p+1 
    end
    tbl['['] = function(p)
        if bracket == p-1 then
            status = 'blk'
            n = n + 1
            parts[n] = code:sub(pos, p) -- include the brackets
            pos = p+1
        else
            bracket = p
        end
    end
    tbl['\n'] = function() end
    tbl[']'] = function() end
    tbl['\\'] = function() end
    function Code.GetUncommentedAndBlanked4(source, c) -- faster, only checking one char at a time, 9K lines in 0.035 without blank string and 0.04 with 
        -- version checking only one char at a time, less convoluted but a tiny bit less fast too
        code = c
        if not code then
            code = WG.Code:GetCode(source or "LuaUI\\Widgets\\UtilsFunc.lua")
        end


        -- to acertain validity of char we check in precise order, short circuiting all the rest of checks
            --> block --> end of block
            --> comment --> check for block or end of line
            --> string --> end of string
            --> comment start
            --> string start
            --> block start

        -- gsub is fastest, avoiding using find is much better
        local pat = '()([\\\'\"%[%]%-\n])'
        -- counts are only for debugging and can be commented out
        -- local count = 0
        -- local blockCount, stringCount, commentCount = 0,0,0
        local tbl = tbl
         pos = 1
         commentStart, blockStart = false, false
         bracket, endBracket, minus = false, false, false
         escaped = false
         status = false
         arg = ''
        -- code = code:codeescape()
         n = 0
        
        sc = 0


        local time = spGetTimer(p)
        code:gsub(
            pat,
            function(p, s)
                -- count = count + 1
                -- if count < 5 then
                --  Echo(p, code:at(p):readnl(), "blockStart,commentStart, strStart is ", blockStart,commentStart, strStart)
                -- end
                if escaped then
                    if escaped == p-1 then
                        escaped = false
                        return
                    else
                        escaped = false
                    end
                end
                tbl[status or s](p,s)
            end
        )

        n = n + 1
        parts[n] = code:sub(pos)

        local uncommented = table.concat(parts) --:decodeescape()
        time = spDiffTimers(spGetTimer(),time)
        local time2 = spGetTimer()
        for i=1, sc do -- substitute the string with spaces (or newline)
            local n = strings[i]
            local part = parts[n]
            if blocks[n] then
                local _, nl = part:gsub('\n','')
                parts[n] = ('\n'):rep(nl)
            else
                parts[n] = (' '):rep(lens[i])
            end
        end
        local blanked = table.concat(parts)
        time2 = spDiffTimers(spGetTimer(),time2)

        Echo("TIME B3 ", time,time2, 'count',count,'parts',n,'strings parts',sc,'uncommented == blanked len',uncommented:len()==blanked:len())
        -- Echo("stringCount, blockCount, commentCount is ", stringCount, blockCount, commentCount)
        -- Echo("strStart, blockStart, commentStart is ", strStart, blockStart, commentStart)

        -- Spring.SetClipboard(code)
        clear()
        code = nil
        return uncommented, blanked, time
    end
end

--]]