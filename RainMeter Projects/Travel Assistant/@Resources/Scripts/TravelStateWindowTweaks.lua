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

local function averageCycleValue(plan,field)
    if plan==nil then return 0 end
    local total=0
    local count=0
    for _,cycle in ipairs(plan.cycles or {}) do
        local value=number(cycle[field])
        if value>0 then total=total+value; count=count+1 end
    end
    if count==0 then return 0 end
    return math.floor((total/count)+0.5)
end

local function averageRestockDelay(plan)
    return averageCycleValue(plan,'delay')
end

local function averageAvailability(plan)
    return averageCycleValue(plan,'available')
end

local function formatDuration(seconds)
    local value=math.max(0,math.floor(number(seconds)))
    if value<60 then return '<1m' end
    local hours=math.floor(value/3600)
    local minutes=math.floor((value%3600)/60)
    if hours>0 then return string.format('%dh %dm',hours,minutes) end
    return string.format('%dm',minutes)
end

local function formatRelativeTarget(at,now)
    if at<=0 then return '?' end
    if at>now then return 'in '..formatDuration(at-now) end
    return formatDuration(now-at)..' overdue'
end

local function formatMoment(at,now)
    if at<=0 then return '?' end
    local relation=at>=now and (formatDuration(at-now)..' away') or (formatDuration(now-at)..' ago')
    return os.date('%H:%M',at)..' ('..relation..')'
end

local function nearestGroup(plan,now)
    if plan==nil then return nil end
    for _,group in ipairs(plan.groups or {}) do
        if number(group.lateSellout)>now then return group end
    end
    if #(plan.groups or {})>0 then return plan.groups[#plan.groups] end
    return nil
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

local function liveTravelRemainingSeconds(state,now)
    local arrivalAt=number(state.TravelArrivalAt)
    if arrivalAt>now then return arrivalAt-now end
    local projectedLeft=number(state.TravelTimeLeft)
    local projectedAt=number(state.TravelContextLastSuccessAt)
    if projectedLeft>0 and projectedAt>0 then
        return math.max(0,projectedLeft-math.max(0,now-projectedAt))
    end
    return math.max(0,projectedLeft)
end

local function returningStatus(state,now)
    local remaining=liveTravelRemainingSeconds(state,now)
    if remaining<=0 then return 'ARRIVE IN TORN: <1m' end
    return 'ARRIVE IN TORN: '..formatDuration(remaining)
end

local function currentCycleStatus(plan,now)
    if plan==nil or plan.anchorAt<=0 then return 'WAIT DATA','' end
    local group=nearestGroup(plan,now)
    local tooltip=formatWindowTooltip(group,now)

    -- Current market is out of stock. The next restock estimate is always anchored
    -- to the latest observed >0 -> 0 transition plus the arithmetic mean of retained
    -- completed-cycle restock delays. Do not advance to a later recurring ordinal
    -- simply because the mean estimate has already passed while stock remains zero.
    if plan.anchorPhase=='S' then
        local delay=averageRestockDelay(plan)
        if delay<=0 then return 'WAIT DATA',tooltip end
        local restockAt=plan.anchorAt+delay
        local outOfStockFor=math.max(0,now-plan.anchorAt)
        return 'OoS: '..formatDuration(outOfStockFor)..'. Restock: '..formatRelativeTarget(restockAt,now),tooltip
    end

    -- Current market is still observed in stock. Estimate depletion from the latest
    -- observed restock plus average stocked duration, but never pretend it is OOS
    -- until the collector actually observes stock reach zero.
    local available=averageAvailability(plan)
    if available<=0 then return 'IN STOCK',tooltip end
    local selloutAt=plan.anchorAt+available
    if selloutAt>now then
        return 'UPCOMING - SELLOUT IN '..formatDuration(selloutAt-now),tooltip
    end
    return 'IN STOCK - AVG SELLOUT '..formatDuration(now-selloutAt)..' AGO',tooltip
end

local function updateRow(index,state,lookup,now)
    local prefix='MeterOpportunity'..index
    local name=meterOption(prefix..'Name','Text')
    if name=='' then return end

    local travelState=trim(state.TravelState):lower()

    -- Returning to Torn is a recognized API travel state. CardPresenter already
    -- evaluates every country's actionable window from the return landing time;
    -- this final pass only replaces departure wording with the live home-arrival
    -- countdown while the player cannot act from Torn yet.
    if travelState=='returning' then
        setOption(prefix..'Leave','Text',returningStatus(state,now))
        setOption(prefix..'Chance','Text','')
        return
    end

    local country=rowCountry(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(name)]
    if row==nil or row.plan==nil then return end

    local destinationId=trim(state.TravelDestinationCountryId):lower()
    local countryId=countryIdsByName[country] or ''
    if countryId=='' or countryId~=destinationId then return end

    if travelState~='traveling' and travelState~='abroad' and travelState~='foreign' then return end

    local status,tooltip=currentCycleStatus(row.plan,now)
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
