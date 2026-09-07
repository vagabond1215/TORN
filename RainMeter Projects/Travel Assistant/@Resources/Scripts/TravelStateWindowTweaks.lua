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

local function optionalProbability(value)
    local raw=trim(value)
    if raw=='' then return nil end
    local p=tonumber(raw)
    if p==nil or p<0 or p>1 then return nil end
    return p
end

local function chancePercent(value)
    return string.format('%.0f%%',math.max(0,math.min(1,value))*100)
end

local function readKv(path)
    local manifest=io.open((path:match('^(.*[\\/])') or '')..'last-update.txt','r'); if manifest then local raw=manifest:read('*a') or ''; manifest:close(); local name=raw:match('^%d+|(ui%-state%-%d+%-%x+%.kv)'); if name then path=(path:match('^(.*[\\/])') or '')..name end end
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
                plannedQuantity=parsePlannedQuantity(state[prefix..'QuantityText']),
                currentStock=number(state[prefix..'CurrentStock']),
                stockEvidenceAt=number(state[prefix..'StockEvidenceAt']),
                activeRestockAt=number(state[prefix..'ActiveRestockAt']),
                activeSelloutAt=number(state[prefix..'ActiveSelloutEstimateAt']),
                nextRestockAt=number(state[prefix..'NextRestockEstimateAt']),
                lastObservedOosAt=number(state[prefix..'LastObservedOosAt']),
                medianRestockDelay=number(state[prefix..'MedianRestockDelaySeconds']),
                restockSampleCount=number(state[prefix..'RestockSampleCount']),
                windowDataQualityReason=trim(state[prefix..'WindowDataQualityReason']),
                forecastMode=trim(state[prefix..'ForecastMode']):lower(),
                liveCycleProjectionMode=trim(state[prefix..'LiveCycleProjectionMode']):lower(),
                immediateArrivalProbability=optionalProbability(state[prefix..'ImmediateArrivalProbabilityValue']),
                multiCycleChanceEligible=number(state[prefix..'MultiCycleChanceEligible'])>=1,
                multiCycleArrivalProbability=optionalProbability(state[prefix..'MultiCycleChanceProbability'])
            }
        end
    end
    return lookup
end

local function applyTooltip(prefix,tooltip,title)
    local text=trim(tooltip)
    local heading=trim(title)
    if heading=='' then heading='Window estimate' end
    -- Empty ToolTipText disables the tooltip without high-frequency numeric
    -- ToolTipHidden bangs, which the target Rainmeter host misparsed after RESET.
    setOption(prefix..'Leave','ToolTipTitle',heading)
    setOption(prefix..'Leave','ToolTipText',text)
    setOption(prefix..'Leave','DynamicVariables',1)
end

local function setTravelChance(prefix,value)
    local chance=trim(value)
    setOption(prefix..'Chance','Text',chance)
    if chance=='' then
        setOption(prefix..'Leave','W',263)
        SKIN:Bang('!HideMeter',prefix..'Chance')
    else
        setOption(prefix..'Leave','W',122)
        SKIN:Bang('!ShowMeter',prefix..'Chance')
    end
end

local function safeStockStatus(value)
    local status=trim(value)
    local normalized=status:lower()
    if normalized=='in stock' or normalized=='stock holding' then return 'In Stock - Safe to Leave' end
    return status
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

local function rowHasUnresolvedOos(row)
    if row==nil then return false end
    local oosAt=number(row.lastObservedOosAt)
    local restockAt=number(row.activeRestockAt)
    return oosAt>0 and (restockAt<=0 or restockAt<=oosAt)
end

local function restockTimingDiagnostic(row)
    if row==nil then return 'Restock unavailable - market row missing','No market row is available for restock diagnostics.' end
    local nl='#CRLF#'
    local samples=math.max(0,math.floor(number(row.restockSampleCount)))
    local medianDelay=number(row.medianRestockDelay)
    local modelReason=trim(row.windowDataQualityReason)
    local lines={}

    if not rowHasUnresolvedOos(row) then
        table.insert(lines,'Sellout anchor: missing or superseded')
        table.insert(lines,'Diagnostic: a verified unresolved OoS boundary is required before a restock timestamp can be projected.')
        if modelReason~='' then table.insert(lines,'Window model: '..modelReason) end
        return 'Restock unavailable - sellout anchor missing',table.concat(lines,nl)
    end

    table.insert(lines,'Sellout anchor: present')
    table.insert(lines,'Verified restock cycles: '..tostring(samples))
    table.insert(lines,'Median restock delay: '..(medianDelay>0 and formatDuration(medianDelay) or 'unavailable'))
    if modelReason~='' then table.insert(lines,'Window model: '..modelReason) end

    if medianDelay<=0 and samples<=0 then
        table.insert(lines,'Diagnostic: no completed cycle currently survives the restock-timing eligibility path. Check collection gaps / boundary quality before treating this as ordinary timing variability.')
        return 'Restock unavailable - 0 verified cycles',table.concat(lines,nl)
    end
    if medianDelay<=0 then
        table.insert(lines,'Diagnostic: verified cycle history exists, but the timing stage did not publish a positive median restock delay.')
        return 'Restock unavailable - no usable delay',table.concat(lines,nl)
    end

    table.insert(lines,'Diagnostic: timing inputs exist, but no next-restock timestamp was published for the current OoS phase.')
    return 'Restock unavailable - estimate not published',table.concat(lines,nl)
end

local function phaseSafePlan(row)
    if row==nil then return nil end
    local plan=row.plan
    if plan~=nil and plan.anchorPhase=='S' and not rowHasUnresolvedOos(row) then
        -- A later restock or otherwise-resolved OoS invalidates sellout-anchored
        -- geometry. Never let an old S-plan resurrect a pre-restock countdown.
        return nil
    end
    return plan
end

local function arrivalChanceText(row)
    if row==nil then return '' end
    if row.immediateArrivalProbability~=nil then
        return chancePercent(row.immediateArrivalProbability)
    end
    if row.multiCycleChanceEligible and row.multiCycleArrivalProbability~=nil then
        return chancePercent(row.multiCycleArrivalProbability)
    end
    return ''
end

local function outboundTooltip(row,state,now)
    local remaining=liveTravelRemainingSeconds(state,now)
    local landingAt=now+remaining
    local plan=phaseSafePlan(row)
    local group=landingRelevantGroup(plan,landingAt)
    local nl='#CRLF#'
    local lines={}
    local hasDirectEvidence=row~=nil and number(row.stockEvidenceAt)>0 and row.liveCycleProjectionMode~='stale-source'
    if hasDirectEvidence and number(row.currentStock)>0 then
        if number(row.activeSelloutAt)>now then
            table.insert(lines,'Sellout in: '..formatDuration(number(row.activeSelloutAt)-now))
        else
            table.insert(lines,'Sellout estimate: learning from live stock')
        end
    elseif hasDirectEvidence then
        if rowHasUnresolvedOos(row) then
            if number(row.nextRestockAt)>now then
                table.insert(lines,'Restock in: '..formatDuration(number(row.nextRestockAt)-now))
            elseif number(row.nextRestockAt)>0 then
                table.insert(lines,'Restock estimate: '..formatRelativeTarget(number(row.nextRestockAt),now))
            else
                local _,diagnostic=restockTimingDiagnostic(row)
                table.insert(lines,'Restock estimate: unavailable')
                table.insert(lines,diagnostic)
            end
        elseif number(row.activeRestockAt)>0 then
            table.insert(lines,'Latest observed phase: restocked; current stock status is stale/unknown')
        else
            table.insert(lines,'Current stock status: unknown; no unresolved OoS phase')
        end
    end
    table.insert(lines,'Landing in '..formatDuration(remaining))

    if group==nil then
        table.insert(lines,'Estimated Stock at arrival: ?')
        return table.concat(lines,nl)
    end

    local restockAt=expectedRestockAt(plan,group)
    local selloutAt=expectedSelloutAt(plan,group,restockAt)
    local estimatedStock='0'
    local directArrivalResolved=false
    if hasDirectEvidence and number(row.currentStock)>0 and number(row.activeSelloutAt)>landingAt then
        if number(row.plannedQuantity)>0 then estimatedStock='>='..tostring(math.floor(number(row.plannedQuantity))) else estimatedStock='available' end
        directArrivalResolved=true
    elseif hasDirectEvidence and number(row.nextRestockAt)>landingAt then
        directArrivalResolved=true
    end
    if not directArrivalResolved and restockAt>0 and selloutAt>restockAt and landingAt>=restockAt and landingAt<selloutAt then
        if number(row.plannedQuantity)>0 then estimatedStock='>='..tostring(math.floor(number(row.plannedQuantity))) else estimatedStock='available' end
    end
    table.insert(lines,'Estimated Stock at arrival: '..estimatedStock)

    if not hasDirectEvidence and restockAt>now then
        table.insert(lines,'Restock in: '..formatDuration(restockAt-now))
    elseif not hasDirectEvidence and selloutAt>now then
        table.insert(lines,'Sold out in: '..formatDuration(selloutAt-now))
    end
    return table.concat(lines,nl)
end

local function outboundStatus(row,state,now)
    local plan=phaseSafePlan(row)
    local hasDirectEvidence=row~=nil and number(row.stockEvidenceAt)>0 and row.liveCycleProjectionMode~='stale-source'
    if hasDirectEvidence then
        if number(row.currentStock)>0 then
            if number(row.activeSelloutAt)>now then return 'Sells out in '..formatDuration(number(row.activeSelloutAt)-now) end
            return 'In stock'
        end
        if rowHasUnresolvedOos(row) then
            if number(row.nextRestockAt)>now then return 'Restocks in '..formatDuration(number(row.nextRestockAt)-now) end
            if number(row.nextRestockAt)>0 then return 'Restock estimate overdue' end
            local status=restockTimingDiagnostic(row)
            return status
        end
        if number(row.activeRestockAt)>0 then return 'Stock status stale' end
        return 'Stock status unknown'
    end

    -- Forecast-only/stale provider mode still has valid phase/cycle geometry when a
    -- verified anchor exists. Use that model instead of degrading the row to
    -- Collecting Data solely because the last stock snapshot is older than 5m.
    if plan==nil then return 'Market data pending' end
    local remaining=liveTravelRemainingSeconds(state,now)
    local landingAt=now+remaining
    local group=landingRelevantGroup(plan,landingAt)
    if group==nil then return 'Market data pending' end
    local restockAt=expectedRestockAt(plan,group)
    local selloutAt=expectedSelloutAt(plan,group,restockAt)
    if restockAt>now then return 'Restocks in '..formatDuration(restockAt-now) end
    if selloutAt>now then return 'Sells out in '..formatDuration(selloutAt-now) end
    return 'Market data pending'
end
local function currentCycleStatus(row,now)
    local plan=phaseSafePlan(row)
    if plan==nil or plan.anchorAt<=0 then
        if row~=nil and rowHasUnresolvedOos(row) then
            return restockTimingDiagnostic(row)
        end
        if row~=nil and number(row.activeRestockAt)>0 and not rowHasUnresolvedOos(row) then
            return 'STOCK STATUS STALE','Latest observed phase: restocked; current stock status is stale/unknown'
        end
        return 'WAIT DATA',''
    end
    if plan.anchorPhase=='S' then
        local delay=averageRestockDelay(plan)
        if delay<=0 then return restockTimingDiagnostic(row) end
        local restockAt=plan.anchorAt+delay
        local outOfStockFor=math.max(0,now-plan.anchorAt)
        return 'OoS: '..formatDuration(outOfStockFor)..'. Restock: '..formatRelativeTarget(restockAt,now),
            'Restock in: '..formatRelativeTarget(restockAt,now)
    end

    local available=averageAvailability(plan)
    if available<=0 then return 'In stock','' end
    local selloutAt=plan.anchorAt+available
    if selloutAt>now then
        return 'In stock for '..formatDuration(selloutAt-now),'Sold out in: '..formatDuration(selloutAt-now)
    end
    return 'In stock - avg sellout '..formatDuration(now-selloutAt)..' ago',''
end

local function syncPanelHeight()
    local footerExtra=28
    local bottom=132
    for i=1,8 do
        local prefix='MeterOpportunity'..i
        if meterOption(prefix..'Name','Text')~='' then
            local y=number(meterOption(prefix..'Card','Y'))
            local h=number(meterOption(prefix..'Card','H'))
            if y>0 and h>0 then bottom=math.max(bottom,y+h+8) end
        end
    end
    SKIN:Bang('!SetVariable','PanelHeight',tostring(math.max(160,math.floor(bottom+footerExtra))))
end

local function updateRow(index,state,lookup,now)
    local prefix='MeterOpportunity'..index
    local name=meterOption(prefix..'Name','Text')
    if name=='' then return end

    local travelState=trim(state.TravelState):lower()

    if travelState=='returning' then
        -- Character travel status belongs in MeterTitle. Preserve CardPresenter's
        -- item-specific post-return departure/window action on each row.
        return
    end

    if travelState=='traveling' or travelState=='abroad' or travelState=='foreign' then
        setTravelChance(prefix,'')
    end

    local country=rowCountry(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(name)]
    if row==nil then
        if travelState=='traveling' or travelState=='abroad' or travelState=='foreign' then applyTooltip(prefix,'','') end
        return
    end

    local destinationId=trim(state.TravelDestinationCountryId):lower()
    local countryId=countryIdsByName[country] or ''
    if countryId=='' or countryId~=destinationId then
        if travelState=='traveling' or travelState=='abroad' or travelState=='foreign' then applyTooltip(prefix,'','') end
        return
    end

    if travelState=='traveling' then
        setOption(prefix..'Leave','Text',safeStockStatus(outboundStatus(row,state,now)))
        setTravelChance(prefix,arrivalChanceText(row))
        applyTooltip(prefix,outboundTooltip(row,state,now),'Arrival estimate')
        return
    end

    if travelState=='abroad' or travelState=='foreign' then
        local status,tooltip=currentCycleStatus(row,now)
        setOption(prefix..'Leave','Text',safeStockStatus(status))
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
