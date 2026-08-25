local statePath = nil

local countryIdsByName = {
    ['Mexico']='mexico', ['Cayman Islands']='cayman_islands', ['Canada']='canada', ['Hawaii']='hawaii',
    ['United Kingdom']='united_kingdom', ['Argentina']='argentina', ['Switzerland']='switzerland', ['Japan']='japan',
    ['China']='china', ['United Arab Emirates']='united_arab_emirates', ['South Africa']='south_africa'
}

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

local function median(values)
    local copy={}
    for _,value in ipairs(values or {}) do
        local n=number(value)
        if n>0 then table.insert(copy,n) end
    end
    if #copy==0 then return 0 end
    table.sort(copy)
    local mid=math.floor((#copy+1)/2)
    if (#copy%2)==1 then return copy[mid] end
    return math.floor((copy[mid]+copy[mid+1])/2+0.5)
end

local function medianAvailability(plan)
    local values={}
    if plan~=nil then
        for _,cycle in ipairs(plan.cycles or {}) do table.insert(values,cycle.available) end
    end
    return median(values)
end

local function expectedTimes(plan,group)
    if group==nil then return 0,0 end
    local restock=0
    if group.earlyRestock>0 and group.lateRestock>0 then
        restock=math.floor((group.earlyRestock+group.lateRestock)/2)
    else
        restock=math.max(group.earlyRestock,group.lateRestock)
    end
    local available=medianAvailability(plan)
    local sellout=restock+available
    if group.earlySellout>0 and group.lateSellout>0 then
        if sellout<group.earlySellout then sellout=group.earlySellout end
        if sellout>group.lateSellout then sellout=group.lateSellout end
    end
    return restock,sellout
end

local function findUpcomingGroup(plan,now)
    if plan==nil then return nil,0,0 end
    for _,group in ipairs(plan.groups or {}) do
        local restock,sellout=expectedTimes(plan,group)
        if sellout>now then return group,restock,sellout end
    end
    return nil,0,0
end

local function formatDuration(seconds)
    local value=math.max(0,math.floor(number(seconds)))
    if value<60 then return '<1m' end
    local hours=math.floor(value/3600)
    local minutes=math.floor((value%3600)/60)
    if hours>0 then return string.format('%dh %dm',hours,minutes) end
    return string.format('%dm',minutes)
end

local function formatMoment(at,now)
    if at<=0 then return '?' end
    local relation=at>=now and (formatDuration(at-now)..' away') or (formatDuration(now-at)..' ago')
    return os.date('%H:%M',at)..' ('..relation..')'
end

local function formatWindowTooltip(group,now)
    if group==nil then return 'Window evidence unavailable' end
    local nl='#CRLF#'
    local safe='none'
    if group.safeStart>0 and group.safeEnd-group.safeStart>=60 then
        safe=os.date('%H:%M',group.safeStart)..' - '..os.date('%H:%M',group.safeEnd)..' ('..formatDuration(group.safeEnd-group.safeStart)..')'
    end
    local best='none'
    if group.bestStart>0 and group.bestEnd>group.bestStart then
        local target=math.floor((group.bestStart+group.bestEnd)/2)
        best=formatMoment(target,now)..' ['..string.format('%.0f%%',group.bestProbability*100)..']'
    end
    return 'Safe formula: max(restock starts) -> min(sellout ends)'..nl..
        'Best formula: completed-cycle overlap / usable cycle count'..nl..
        'Early Restock: '..formatMoment(group.earlyRestock,now)..' - '..formatMoment(group.earlySellout,now)..nl..
        'Late Restock: '..formatMoment(group.lateRestock,now)..' - '..formatMoment(group.lateSellout,now)..nl..
        'Safe Window: '..safe..nl..
        'Best Hit Window: '..best
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

local function applyTooltip(prefix,tooltip)
    local text=trim(tooltip)
    setOption(prefix..'Leave','ToolTipTitle','Window estimate')
    setOption(prefix..'Leave','ToolTipText',text)
    setOption(prefix..'Leave','ToolTipHidden',text=='' and 1 or 0)
    setOption(prefix..'Leave','DynamicVariables',1)
    setOption(prefix..'Info','ToolTipTitle','Window estimate')
    setOption(prefix..'Info','ToolTipText',text)
    setOption(prefix..'Info','ToolTipHidden',text=='' and 1 or 0)
end

local function outboundStatus(plan,now)
    local group,restock,sellout=findUpcomingGroup(plan,now)
    if group==nil then return 'WAIT DATA','' end
    if now<restock then
        return 'UPCOMING - RESTOCK IN '..formatDuration(restock-now),formatWindowTooltip(group,now)
    end
    return 'UPCOMING - SELLOUT IN '..formatDuration(sellout-now),formatWindowTooltip(group,now)
end

local function abroadStatus(plan,now)
    local group,restock,sellout=findUpcomingGroup(plan,now)
    if group==nil then return 'WAIT DATA','' end
    if now<restock then
        return 'RESTOCK IN '..formatDuration(restock-now),formatWindowTooltip(group,now)
    end
    return 'IN STOCK FOR '..formatDuration(sellout-now),formatWindowTooltip(group,now)
end

local function updateRow(index,state,lookup,now)
    local prefix='MeterOpportunity'..index
    local name=meterOption(prefix..'Name','Text')
    if name=='' then return end
    -- FinalCardPolish runs later. At this point the name meter contains only the item name.
    local country=rowCountry(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(name)]
    if row==nil or row.plan==nil then return end

    local travelState=trim(state.TravelState):lower()
    local destinationId=trim(state.TravelDestinationCountryId):lower()
    local countryId=countryIdsByName[country] or ''
    if countryId=='' or countryId~=destinationId then return end

    local status=nil
    local tooltip=''
    if travelState=='traveling' then
        status,tooltip=outboundStatus(row.plan,now)
    elseif travelState=='abroad' or travelState=='foreign' then
        status,tooltip=abroadStatus(row.plan,now)
    else
        return
    end

    setOption(prefix..'Leave','Text',status)
    setOption(prefix..'Chance','Text','')
    applyTooltip(prefix,tooltip)
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
end

function Update()
    local state=readKv(statePath)
    local lookup=buildLookup(state)
    local now=os.time()
    for i=1,8 do updateRow(i,state,lookup,now) end
    return 0
end