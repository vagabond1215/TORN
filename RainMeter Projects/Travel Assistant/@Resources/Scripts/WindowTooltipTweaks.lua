local statePath=nil

local function trim(value)
    local text=tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function number(value)
    return tonumber(value) or 0
end

local function readKv(path)
    local out={}
    local file=io.open(path,'r')
    if not file then return out end
    for line in file:lines() do
        local key,value=line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)]=trim(value) end
    end
    file:close()
    return out
end

local function meter(name)
    return SKIN:GetMeter(name)
end

local function meterOption(name,option)
    local m=meter(name)
    if m==nil then return '' end
    return trim(m:GetOption(option,''))
end

local function setOption(name,option,value)
    if meter(name)~=nil then SKIN:Bang('!SetOption',name,option,tostring(value or '')) end
end

local function normalizeName(value)
    return trim(value):lower():gsub('%s+',' ')
end

local function rowCountry(index)
    local text=meterOption('MeterOpportunity'..index..'Flag','ToolTipText')
    local country=text:match('^(.-)%s*|%s*travel')
    return trim(country or '')
end

local function buildLookup(state)
    local lookup={}
    local count=math.max(0,math.min(256,math.floor(number(state.OpportunityCount))))
    for i=1,count do
        local prefix='Opportunity'..i
        local name=trim(state[prefix..'Name'])
        local country=trim(state[prefix..'Country'])
        if name~='' and country~='' then
            lookup[normalizeName(country)..'|'..normalizeName(name)]={
                windowPlan=trim(state[prefix..'Tooltip'])
            }
        end
    end
    return lookup
end

local function formatDuration(seconds)
    local value=math.max(0,math.floor(number(seconds)))
    if value<60 then return '<1m' end
    local hours=math.floor(value/3600)
    local minutes=math.floor((value%3600)/60)
    if hours>0 then return string.format('%dh %dm',hours,minutes) end
    return string.format('%dm',minutes)
end

local function tooltipLine(text,label)
    local raw=tostring(text or '')
    local line=raw:match(label..':%s*(.-)#CRLF#')
    if line==nil then line=raw:match(label..':%s*(.*)$') end
    return trim(line or '')
end

local function clockFromLine(line)
    return trim(line):match('(%d%d:%d%d)') or ''
end

local function medianAvailableSeconds(rawPlan)
    local machine=tostring(rawPlan or ''):match('^WP2:([^#]*)#')
    if machine==nil then return 0 end
    local pairs=machine:match('^%d+,[RS],(.-)~')
    if pairs==nil then return 0 end
    local values={}
    for part in pairs:gmatch('[^/]+') do
        local _,available=part:match('^(%d+):(%d+)$')
        if available~=nil and number(available)>0 then table.insert(values,number(available)) end
    end
    if #values==0 then return 0 end
    table.sort(values)
    local middle=math.floor((#values+1)/2)
    if (#values%2)==1 then return values[middle] end
    return math.floor((values[middle]+values[middle+1])/2+0.5)
end

local function parseSafeWindows(rawPlan)
    local windows={}
    local machine=tostring(rawPlan or ''):match('^WP2:([^#]*)#')
    if machine==nil then return windows end
    local groups=machine:match('^[^~]*~(.*)$')
    if groups==nil then return windows end
    for entry in groups:gmatch('[^/]+') do
        local ordinal,earlyRestock,earlySellout,lateRestock,lateSellout,safeStart,safeEnd,bestStart,bestEnd,bestProbability=
            entry:match('^G,(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),([%d%.]+)$')
        if ordinal~=nil then
            local startAt=number(safeStart)
            local endAt=number(safeEnd)
            if startAt>0 and endAt>startAt then table.insert(windows,{startAt=startAt,endAt=endAt}) end
        end
    end
    return windows
end

local function findMatchingSafeWindow(rawPlan,startClock,endClock,now)
    local best=nil
    local bestScore=nil
    for _,window in ipairs(parseSafeWindows(rawPlan)) do
        if os.date('%H:%M',window.startAt)==startClock and os.date('%H:%M',window.endAt)==endClock then
            local score=0
            if now>=window.startAt and now<window.endAt then score=-1
            elseif window.startAt>now then score=window.startAt-now
            else score=1000000000+(now-window.endAt) end
            if best==nil or score<bestScore then best=window; bestScore=score end
        end
    end
    return best
end

local function guaranteedText(rawPlan,now)
    local current=tooltipLine(rawPlan,'Safe Window')
    if current=='' or current:lower()=='none' then return '' end
    local startClock,endClock=current:match('^(%d%d:%d%d)%s+%-%s+(%d%d:%d%d)')
    if startClock==nil or endClock==nil then return 'Guaranteed: '..current end

    local relative=''
    local window=findMatchingSafeWindow(rawPlan,startClock,endClock,now)
    if window~=nil then
        if now<window.startAt then relative='starts in '..formatDuration(window.startAt-now)
        elseif now<window.endAt then relative='closes in '..formatDuration(window.endAt-now)
        else relative='closed '..formatDuration(now-window.endAt)..' ago' end
    end
    local suffix=relative~='' and ' ('..relative..')' or ''
    return 'Guaranteed: '..startClock..' to '..endClock..suffix
end

local function bestHitText(rawPlan)
    local current=tooltipLine(rawPlan,'Best Hit Window')
    if current=='' or current:lower()=='none' then return '' end
    local clock=clockFromLine(current)
    local chance=current:match('%[(%d+%%)%]') or ''
    if clock=='' then return 'Best hit: '..current end
    if chance~='' then return 'Best hit: '..clock..' ['..chance..']' end
    return 'Best hit: '..clock
end

local function liveTravelRemainingSeconds(state,now)
    local arrivalAt=number(state.TravelArrivalAt)
    if arrivalAt>now then return arrivalAt-now end
    local projectedLeft=number(state.TravelTimeLeft)
    local projectedAt=number(state.TravelContextLastSuccessAt)
    if projectedLeft>0 and projectedAt>0 then return math.max(0,projectedLeft-math.max(0,now-projectedAt)) end
    return 0
end

local function conciseTooltip(rawPlan,state,now)
    local lines={}
    local travelState=trim(state.TravelState):lower()
    if travelState=='returning' then
        local remaining=liveTravelRemainingSeconds(state,now)
        if remaining>0 then table.insert(lines,'Home in: '..formatDuration(remaining)) end
    end

    local early=clockFromLine(tooltipLine(rawPlan,'Early Restock'))
    local late=clockFromLine(tooltipLine(rawPlan,'Late Restock'))
    if early~='' and late~='' then
        if early==late then table.insert(lines,'Restock: '..early)
        else table.insert(lines,'Restock: '..early..' - '..late) end
    elseif early~='' then table.insert(lines,'Restock: '..early)
    elseif late~='' then table.insert(lines,'Restock: '..late) end

    local stocked=medianAvailableSeconds(rawPlan)
    if stocked>0 then table.insert(lines,'Typical stock duration: '..formatDuration(stocked)) end

    local guaranteed=guaranteedText(rawPlan,now)
    if guaranteed~='' then table.insert(lines,guaranteed)
    else
        local best=bestHitText(rawPlan)
        if best~='' then table.insert(lines,best) end
    end

    return table.concat(lines,'#CRLF#')
end

local function updateRow(index,lookup,now,state)
    local prefix='MeterOpportunity'..index
    local travelState=trim(state.TravelState):lower()

    -- Outbound/foreign presentation is owned by TravelStateWindowTweaks. Home and
    -- active return-flight tooltips are rebuilt from raw state, never prior meter text.
    if travelState~='' and travelState~='home' and travelState~='returning' then
        setOption(prefix..'Chance','Text','')
        return
    end

    local name=trim(meterOption(prefix..'Name','Text'))
    local country=rowCountry(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(name)]
    if row~=nil and row.windowPlan~='' then
        local tooltip=conciseTooltip(row.windowPlan,state,now)
        local hidden=tooltip=='' and 1 or 0
        setOption(prefix..'Leave','ToolTipTitle','Window estimate')
        setOption(prefix..'Leave','ToolTipText',tooltip)
        setOption(prefix..'Leave','ToolTipHidden',hidden)
        setOption(prefix..'Info','ToolTipTitle','Window estimate')
        setOption(prefix..'Info','ToolTipText',tooltip)
        setOption(prefix..'Info','ToolTipHidden',hidden)
    end
    setOption(prefix..'Chance','Text','')
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
end

function Update()
    local state=readKv(statePath)
    local lookup=buildLookup(state)
    local now=os.time()
    for i=1,8 do updateRow(i,lookup,now,state) end
    return 0
end
