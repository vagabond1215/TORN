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

local function parsePlannedQuantity(text)
    return tonumber(trim(text):match('(%d+)')) or 0
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

local function buildLookup(state)
    local lookup={}
    local count=math.max(0,math.min(256,math.floor(number(state.OpportunityCount))))
    for i=1,count do
        local prefix='Opportunity'..i
        local name=trim(state[prefix..'Name'])
        local country=trim(state[prefix..'Country'])
        if name~='' and country~='' then
            lookup[normalizeName(country)..'|'..normalizeName(name)]={
                plan=parseWindowPlan(state[prefix..'Tooltip']),
                plannedQuantity=parsePlannedQuantity(state[prefix..'QuantityText'])
            }
        end
    end
    return lookup
end

local function applyTooltip(prefix,tooltip,title)
    local text=trim(tooltip)
    local heading=trim(title)
    if heading=='' then heading='Window estimate' end
    setOption(prefix..'Leave','ToolTipTitle',heading)
    setOption(prefix..'Leave','ToolTipText',text)
    setOption(prefix..'Leave','ToolTipHidden',text=='' and 1 or 0)
    setOption(prefix..'Leave','DynamicVariables',1)
    setOption(prefix..'Info','ToolTipTitle',heading)
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

local function returningTooltip(state,now)
    return 'Home in: '..formatDuration(liveTravelRemainingSeconds(state,now))
end

local function expectedRestockAt(plan,group)
    if plan==nil or group==nil then return 0 end
    if group.ordinal==0 and plan.anchorPhase=='S' then
        local delay=averageRestockDelay(plan)
        if delay>0 then return plan.anchorAt+delay end
    elseif group.ordinal==0 and plan.anchorPhase=='R' then
        return plan.anchorAt
    end
    if group.earlyRestock>0 and group.lateRestock>=group.earlyRestock then
        return math.floor((group.earlyRestock+group.lateRestock)/2)
    end
    return 0
end

local function expectedSelloutAt(plan,group,restockAt)
    if plan==nil or group==nil then return 0 end
    local available=averageAvailability(plan)
    if restockAt>0 and available>0 then return restockAt+available end
    if group.earlySellout>0 and group.lateSellout>=group.earlySellout then
        return math.floor((group.earlySellout+group.lateSellout)/2)
    end
    return 0
end

local function landingRelevantGroup(plan,landingAt)
    if plan==nil then return nil end
    for _,group in ipairs(plan.groups or {}) do
        if number(group.lateSellout)>landingAt then return group end
    end
    return nil
end

local function outboundTooltip(row,state,now)
    local remaining=liveTravelRemainingSeconds(state,now)
    local landingAt=now+remaining
    local plan=row and row.plan or nil
    local group=landingRelevantGroup(plan,landingAt)
    local nl='#CRLF#'
    local lines={'Landing in '..formatDuration(remaining)}

    if group==nil then
        table.insert(lines,'Estimated Stock at arrival: ?')
        return table.concat(lines,nl)
    end

    local restockAt=expectedRestockAt(plan,group)
    local selloutAt=expectedSelloutAt(plan,group,restockAt)
    local estimatedStock='0'
    if restockAt>0 and selloutAt>restockAt and landingAt>=restockAt and landingAt<selloutAt then
        if number(row.plannedQuantity)>0 then estimatedStock='>='..tostring(math.floor(number(row.plannedQuantity))) else estimatedStock='available' end
    end
    table.insert(lines,'Estimated Stock at arrival: '..estimatedStock)

    if restockAt>now then
        table.insert(lines,'Restock in: '..formatDuration(restockAt-now))
    elseif selloutAt>now then
        table.insert(lines,'Sold out in: '..formatDuration(selloutAt-now))
    end
    return table.concat(lines,nl)
end

local function outboundStatus(plan,state,now)
    if plan==nil then return 'EN ROUTE' end
    local remaining=liveTravelRemainingSeconds(state,now)
    local landingAt=now+remaining
    local group=landingRelevantGroup(plan,landingAt)
    if group==nil then return 'EN ROUTE' end
    local restockAt=expectedRestockAt(plan,group)
    local selloutAt=expectedSelloutAt(plan,group,restockAt)
    if restockAt>now then return 'UPCOMING - RESTOCK IN '..formatDuration(restockAt-now) end
    if selloutAt>now then return 'UPCOMING - SELLOUT IN '..formatDuration(selloutAt-now) end
    return 'EN ROUTE'
end

local function currentCycleStatus(plan,now)
    if plan==nil or plan.anchorAt<=0 then return 'WAIT DATA','' end
    if plan.anchorPhase=='S' then
        local delay=averageRestockDelay(plan)
        if delay<=0 then return 'WAIT DATA','' end
        local restockAt=plan.anchorAt+delay
        local outOfStockFor=math.max(0,now-plan.anchorAt)
        return 'OoS: '..formatDuration(outOfStockFor)..'. Restock: '..formatRelativeTarget(restockAt,now),
            'Restock in: '..formatRelativeTarget(restockAt,now)
    end

    local available=averageAvailability(plan)
    if available<=0 then return 'IN STOCK','' end
    local selloutAt=plan.anchorAt+available
    if selloutAt>now then
        return 'IN STOCK FOR '..formatDuration(selloutAt-now),'Sold out in: '..formatDuration(selloutAt-now)
    end
    return 'IN STOCK - AVG SELLOUT '..formatDuration(now-selloutAt)..' AGO',''
end

local function syncPanelHeight()
    local bottom=164
    for i=1,8 do
        local prefix='MeterOpportunity'..i
        if meterOption(prefix..'Name','Text')~='' then
            local y=number(meterOption(prefix..'Card','Y'))
            local h=number(meterOption(prefix..'Card','H'))
            if y>0 and h>0 then bottom=math.max(bottom,y+h+8) end
        end
    end
    SKIN:Bang('!SetVariable','PanelHeight',tostring(math.floor(bottom)))
end

local function updateRow(index,state,lookup,now)
    local prefix='MeterOpportunity'..index
    local name=meterOption(prefix..'Name','Text')
    if name=='' then return end

    local travelState=trim(state.TravelState):lower()

    if travelState=='returning' then
        setOption(prefix..'Leave','Text',returningStatus(state,now))
        setOption(prefix..'Chance','Text','')
        applyTooltip(prefix,returningTooltip(state,now),'Return estimate')
        return
    end

    local country=rowCountry(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(name)]
    if row==nil or row.plan==nil then return end

    local destinationId=trim(state.TravelDestinationCountryId):lower()
    local countryId=countryIdsByName[country] or ''
    if countryId=='' or countryId~=destinationId then return end

    if travelState=='traveling' then
        setOption(prefix..'Leave','Text',outboundStatus(row.plan,state,now))
        setOption(prefix..'Chance','Text','')
        applyTooltip(prefix,outboundTooltip(row,state,now),'Arrival estimate')
        return
    end

    if travelState=='abroad' or travelState=='foreign' then
        local status,tooltip=currentCycleStatus(row.plan,now)
        setOption(prefix..'Leave','Text',status)
        setOption(prefix..'Chance','Text','')
        applyTooltip(prefix,tooltip,'Market estimate')
    end
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
end

function Update()
    local state=readKv(statePath)
    local lookup=buildLookup(state)
    local now=os.time()
    for i=1,8 do updateRow(i,state,lookup,now) end
    syncPanelHeight()
    return 0
end
