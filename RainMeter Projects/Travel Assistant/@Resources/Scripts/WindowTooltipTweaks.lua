local statePath = nil

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
    if line==nil then line=raw:match(label..'%s+(.-)#CRLF#') end
    if line==nil then line=raw:match(label..':%s*(.*)$') end
    if line==nil then line=raw:match(label..'%s+(.*)$') end
    return trim(line or '')
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
            if startAt>0 and endAt>startAt then
                table.insert(windows,{startAt=startAt,endAt=endAt})
            end
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
            if now>=window.startAt and now<window.endAt then
                score=-1
            elseif window.startAt>now then
                score=window.startAt-now
            else
                score=1000000000+(now-window.endAt)
            end
            if best==nil or score<bestScore then
                best=window
                bestScore=score
            end
        end
    end
    return best
end

local function bestChanceText(chanceText,existingTooltip,rawPlan)
    local chance=trim(chanceText):match('(%d+%%)')
    if chance~=nil then return chance..' chance to hit' end
    local selected=tostring(existingTooltip or ''):match('Best Hit Window:%s*.-%[(%d+%%)%]')
    if selected~=nil then return selected..' chance to hit' end
    local fallback=tostring(rawPlan or ''):match('Best Hit Window:%s*.-%[(%d+%%)%]')
    if fallback~=nil then return fallback..' chance to hit' end
    return 'Chance to hit unavailable'
end

local function guaranteedLine(existingTooltip,rawPlan,chanceText,now)
    local current=tooltipLine(existingTooltip,'Guaranteed Window')
    if current=='' or current:lower()=='none' then
        return bestChanceText(chanceText,existingTooltip,rawPlan)
    end

    local startClock,endClock=current:match('^(%d%d:%d%d)%s+to%s+(%d%d:%d%d)')
    if startClock==nil or endClock==nil then
        return 'Guaranteed Window: '..current
    end

    local window=findMatchingSafeWindow(rawPlan,startClock,endClock,now)
    if window==nil then
        return 'Guaranteed Window: '..startClock..' to '..endClock
    end

    local relative=''
    if now<window.startAt then
        relative='starts in '..formatDuration(window.startAt-now)
    elseif now<window.endAt then
        relative='closes in '..formatDuration(window.endAt-now)
    else
        relative='closed '..formatDuration(now-window.endAt)..' ago'
    end
    return 'Guaranteed Window: '..startClock..' to '..endClock..' ('..relative..')'
end

local function rebuildTooltip(existingTooltip,rawPlan,chanceText,now)
    local arrival=tooltipLine(existingTooltip,'Estimated Arrival in')
    local stocked=tooltipLine(existingTooltip,'Estimated In Stock Duration')
    local early=tooltipLine(existingTooltip,'Early Restock')
    local late=tooltipLine(existingTooltip,'Late Restock')
    if arrival=='' and stocked=='' and early=='' and late=='' then return existingTooltip end

    local nl='#CRLF#'
    return 'Estimated Arrival in '..arrival..nl..
        'Estimated In Stock Duration '..stocked..nl..
        'Early Restock: '..early..nl..
        'Late Restock: '..late..nl..
        guaranteedLine(existingTooltip,rawPlan,chanceText,now)
end

local function updateRow(index,lookup,now,state)
    local prefix='MeterOpportunity'..index
    local travelState=trim(state.TravelState):lower()

    -- TravelStateWindowTweaks runs immediately before this measure and owns the
    -- concise landing/foreign-market tooltip. Do not reinterpret that tooltip as a
    -- home Safe/Best tooltip or append generic window diagnostics back onto it.
    if travelState=='traveling' or travelState=='abroad' or travelState=='foreign' then
        setOption(prefix..'Chance','Text','')
        return
    end

    local name=trim(meterOption(prefix..'Name','Text'))
    local country=rowCountry(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(name)]
    local leave=prefix..'Leave'
    local info=prefix..'Info'
    local chance=prefix..'Chance'
    local existing=meterOption(leave,'ToolTipText')
    if existing=='' then existing=meterOption(info,'ToolTipText') end
    local chanceText=meterOption(chance,'Text')

    if row~=nil and existing~='' then
        local tooltip=rebuildTooltip(existing,row.windowPlan,chanceText,now)
        setOption(leave,'ToolTipText',tooltip)
        setOption(info,'ToolTipText',tooltip)
        setOption(leave,'ToolTipTitle','Window estimate')
        setOption(info,'ToolTipTitle','Window estimate')
    end

    setOption(chance,'Text','')
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
