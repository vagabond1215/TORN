local statePath = nil
local publishedState = nil

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

local function rowCountryAndTravel(index)
    local text=meterOption('MeterOpportunity'..index..'Flag','ToolTipText')
    local country,travel=text:match('^(.-)%s*|%s*travel%s+(.+)$')
    return trim(country or ''),trim(travel or '')
end

local function split(text,separator)
    local result={}
    if text==nil or text=='' then return result end
    local pattern='([^'..separator..']+)'
    for part in tostring(text):gmatch(pattern) do table.insert(result,part) end
    return result
end

local function parseWindowPlan(rawTooltip)
    local raw=tostring(rawTooltip or '')
    local machine=raw:match('^WP2:([^#]*)#')
    if machine==nil then return nil end
    local header,groupsText=machine:match('^(.-)~(.*)$')
    if header==nil then return nil end
    local anchorText,phase,pairsText=header:match('^(%d+),([RS]),(.*)$')
    if anchorText==nil then return nil end

    local plan={anchorAt=number(anchorText),anchorPhase=phase,cycles={},groups={}}
    for _,pair in ipairs(split(pairsText,'/')) do
        local delay,available=pair:match('^(%d+):(%d+)$')
        if delay~=nil then table.insert(plan.cycles,{delay=number(delay),available=number(available)}) end
    end
    for _,entry in ipairs(split(groupsText,'/')) do
        local f=split(entry,',')
        if f[1]=='G' and #f>=11 then
            table.insert(plan.groups,{
                ordinal=number(f[2]),
                earlyRestock=number(f[3]),
                earlySellout=number(f[4]),
                lateRestock=number(f[5]),
                lateSellout=number(f[6]),
                safeStart=number(f[7]),
                safeEnd=number(f[8]),
                bestStart=number(f[9]),
                bestEnd=number(f[10]),
                bestProbability=number(f[11])
            })
        end
    end
    table.sort(plan.groups,function(a,b) return a.ordinal<b.ordinal end)
    return plan
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
                plan=parseWindowPlan(state[prefix..'Tooltip'])
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

local function medianAvailableSeconds(plan)
    if plan==nil then return 0 end
    local values={}
    for _,cycle in ipairs(plan.cycles or {}) do
        local available=number(cycle.available)
        if available>0 then table.insert(values,available) end
    end
    if #values==0 then return 0 end
    table.sort(values)
    local middle=math.floor((#values+1)/2)
    if (#values%2)==1 then return values[middle] end
    return math.floor((values[middle]+values[middle+1])/2+0.5)
end

local function findPreferredGroup(plan,now)
    if plan==nil then return nil,nil end
    for _,group in ipairs(plan.groups or {}) do
        local safeValid=group.safeStart>0 and group.safeEnd-group.safeStart>=60
        if safeValid and group.safeEnd>now then return group,'safe' end

        local bestValid=group.bestStart>0 and group.bestEnd>group.bestStart and group.bestProbability>0.5
        if bestValid and group.bestEnd>now then return group,'best' end
    end
    return nil,nil
end

local function findFutureEvidenceGroup(plan,now)
    if plan==nil then return nil end
    for _,group in ipairs(plan.groups or {}) do
        if number(group.lateSellout)>now then return group end
    end
    return nil
end

local function formatMoment(at,now)
    if at<=0 then return '?' end
    local relative=''
    if at>=now then relative=formatDuration(at-now)..' away'
    else relative=formatDuration(now-at)..' ago' end
    return os.date('%H:%M',at)..' ('..relative..')'
end

local function finalWindowLine(group,mode,now)
    if group==nil then return 'Best Hit Window: unavailable' end
    if mode=='safe' then
        local startClock=os.date('%H:%M',group.safeStart)
        local endClock=os.date('%H:%M',group.safeEnd)
        local relative=''
        if now<group.safeStart then relative='starts in '..formatDuration(group.safeStart-now)
        elseif now<group.safeEnd then relative='closes in '..formatDuration(group.safeEnd-now)
        else relative='closed '..formatDuration(now-group.safeEnd)..' ago' end
        return 'Guaranteed Window: '..startClock..' to '..endClock..' ('..relative..')'
    end

    if mode~='best' or group.bestStart<=0 or group.bestEnd<=group.bestStart then
        return 'Best Hit Window: unavailable'
    end
    local target=math.floor((group.bestStart+group.bestEnd)/2)
    local chance=string.format('%.0f%%',number(group.bestProbability)*100)
    return 'Best Hit Window: '..formatMoment(target,now)..' ['..chance..']'
end

local function buildHomeTooltip(plan,travelText,now)
    if plan==nil then return '' end
    local group,mode=findPreferredGroup(plan,now)
    if group==nil then group=findFutureEvidenceGroup(plan,now) end
    if group==nil then return '' end

    local arrival=travelText~='' and travelText or '?'
    local stocked=medianAvailableSeconds(plan)
    local stockedText=stocked>0 and formatDuration(stocked) or '?'
    local nl='#CRLF#'
    return 'Estimated Arrival in '..arrival..nl..
        'Estimated In Stock Duration '..stockedText..nl..
        'Early Restock: '..formatMoment(group.earlyRestock,now)..nl..
        'Late Restock: '..formatMoment(group.lateRestock,now)..nl..
        finalWindowLine(group,mode,now)
end

local function applyTooltip(prefix,tooltip)
    local hidden=trim(tooltip)=='' and 1 or 0
    setOption(prefix..'Leave','ToolTipTitle','Window estimate')
    setOption(prefix..'Leave','ToolTipText',tooltip)
    setOption(prefix..'Leave','ToolTipHidden',hidden)
    setOption(prefix..'Info','ToolTipTitle','Window estimate')
    setOption(prefix..'Info','ToolTipText',tooltip)
    setOption(prefix..'Info','ToolTipHidden',hidden)
end

local function updateRow(index,lookup,now,state)
    local prefix='MeterOpportunity'..index
    local travelState=trim(state.TravelState):lower()

    -- Non-home travel states have a separate owner in TravelStateWindowTweaks.
    -- Never read or rewrite those tooltips here.
    if travelState=='traveling' or travelState=='returning' or travelState=='abroad' or travelState=='foreign' then
        setOption(prefix..'Chance','Text','')
        return
    end

    local name=trim(meterOption(prefix..'Name','Text'))
    local country,travelText=rowCountryAndTravel(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(name)]
    if row~=nil and row.plan~=nil then
        applyTooltip(prefix,buildHomeTooltip(row.plan,travelText,now))
    end
    setOption(prefix..'Chance','Text','')
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
    local heartbeatPath=SKIN:MakePathAbsolute(SELF:GetOption('HeartbeatFile','#@#Generated\\last-update.txt'))
    publishedState=dofile(SKIN:MakePathAbsolute('#@#Scripts\\PublishedState.lua')); publishedState.configure(statePath,heartbeatPath)
end

function Update()
    local state=publishedState.read()
    local lookup=buildLookup(state)
    local now=os.time()
    for i=1,8 do updateRow(i,lookup,now,state) end
    return 0
end
