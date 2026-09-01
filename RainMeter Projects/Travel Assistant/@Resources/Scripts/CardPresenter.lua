local statePath = nil
local lastTravelStateSignature = ''

local countryIdsByName = {
    ['Mexico']='mexico', ['Cayman Islands']='cayman_islands', ['Canada']='canada', ['Hawaii']='hawaii',
    ['United Kingdom']='united_kingdom', ['Argentina']='argentina', ['Switzerland']='switzerland', ['Japan']='japan',
    ['China']='china', ['United Arab Emirates']='united_arab_emirates', ['South Africa']='south_africa'
}

local function trim(value)
    local text=tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function readKv(path)
    local manifest=io.open((path:match('^(.*[\\/])') or '')..'last-update.txt','r'); if manifest then local raw=manifest:read('*a') or ''; manifest:close(); local name=raw:match('^%d+|(ui%-state%-%d+%-%x+%.kv)'); if name then path=(path:match('^(.*[\\/])') or '')..name end end
    local out={}; local file=io.open(path,'r'); if not file then return out end
    for line in file:lines() do local key,value=line:match('^([^=]+)=(.*)$'); if key then out[trim(key)]=trim(value) end end
    file:close(); return out
end

local function number(value) return tonumber(value) or 0 end
local function meterOption(name,option) local m=SKIN:GetMeter(name); if m==nil then return '' end; return trim(m:GetOption(option,'')) end
local function setOption(name,option,value) if SKIN:GetMeter(name)~=nil then SKIN:Bang('!SetOption',name,option,tostring(value or '')) end end

local function parseMoney(text)
    local value=trim(text); local negative=value:find('%-')~=nil; value=value:gsub('[^%d]',''); local n=tonumber(value) or 0
    return negative and -n or n
end

local function formatMoney(value)
    local rounded=value<0 and -math.floor(math.abs(value)+0.5) or math.floor(value+0.5)
    local negative=rounded<0; local digits=tostring(math.abs(rounded)); local out=digits:reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','')
    return (negative and '-$' or '$')..out
end

local function formatDuration(seconds)
    local value=math.max(0,math.floor(number(seconds))); if value<=0 then return '<1m' end
    local hours=math.floor(value/3600); local minutes=math.floor((value%3600)/60)
    if hours>0 then return string.format('%dh %dm',hours,minutes) end
    if minutes>0 then return string.format('%dm',minutes) end
    return '<1m'
end

local function formatBestCountdown(seconds)
    local value=math.max(0,math.floor(number(seconds)))
    if value<60 then return string.format('%02ds',value) end
    return formatDuration(value)
end

local function usefulWindowHorizon(flightSeconds)
    return math.min(8*3600,math.max(3*3600,math.floor(number(flightSeconds)*1.10+0.5)))
end

local function parseDurationText(text)
    local value=trim(text):lower(); local hours=tonumber(value:match('(%d+)%s*h')) or 0; local minutes=tonumber(value:match('(%d+)%s*m')) or 0
    return (hours*3600)+(minutes*60)
end

local function removeCountrySuffix(title,country)
    title=trim(title); country=trim(country); if country=='' then return title end
    local suffix=' - '..country
    if #title>=#suffix and title:sub(-#suffix)==suffix then return trim(title:sub(1,#title-#suffix)) end
    return title
end

local function quantityFromTooltip(tooltip)
    local q=trim(tooltip):match('%s+x%s*(%d+)%s*='); if q==nil then q=trim(tooltip):match('x(%d+)') end
    return tonumber(q) or 0
end

local function buyPriceFromVisibleText(text)
    local raw=trim(text):match('BUY%s+([^|]+)'); if raw==nil then raw=text end; return parseMoney(raw)
end

local function rowCountryAndTravel(index)
    local tooltip=meterOption('MeterOpportunity'..index..'Flag','ToolTipText'); local country,travel=tooltip:match('^(.-)%s*|%s*travel%s+(.+)$')
    return trim(country),trim(travel)
end

local function liveTravelRemainingSeconds(state,now)
    local arrivalAt=number(state.TravelArrivalAt); if arrivalAt>now then return arrivalAt-now end
    local projectedLeft=number(state.TravelTimeLeft); local projectedAt=number(state.TravelContextLastSuccessAt)
    if projectedLeft>0 and projectedAt>0 then return math.max(0,projectedLeft-math.max(0,now-projectedAt)) end
    return 0
end

local function rowFlightText(state,country,defaultTravel,now)
    local countryId=countryIdsByName[country] or ''; local travelState=trim(state.TravelState):lower(); local destinationId=trim(state.TravelDestinationCountryId):lower()
    if travelState=='traveling' and countryId~='' and destinationId==countryId then
        local remaining=liveTravelRemainingSeconds(state,now); if remaining>0 then return formatDuration(remaining)..' left' end
    elseif travelState=='abroad' and countryId~='' and destinationId==countryId then return 'AT DEST.' end
    if defaultTravel~='' then return defaultTravel end; return '?'
end

local function countryTravelSeconds(state,country,defaultTravel)
    local countryId=countryIdsByName[country] or ''; local key=''
    if countryId=='united_kingdom' then key='UKTravelSeconds' elseif countryId=='japan' then key='JPTravelSeconds' elseif countryId~='' then key=string.upper(countryId)..'TravelSeconds' end
    local seconds=key~='' and number(state[key]) or 0; if seconds>0 then return seconds end; return parseDurationText(defaultTravel)
end

local function isDurationOnly(text)
    local value=trim(text):lower(); if value=='' then return false end
    return value=='<1m' or value:match('^%d+%s*m$')~=nil or value:match('^%d+%s*h$')~=nil or value:match('^%d+%s*h%s+%d+%s*m$')~=nil
end

local function statusText(windowText,leaveText)
    local window=trim(windowText); local leave=trim(leaveText); if isDurationOnly(window) then window='' end
    if window=='' then return leave end; if leave=='' or leave==window then return window end; return window..' / '..leave
end

local function split(text,separator)
    local result={}; if text==nil or text=='' then return result end
    local pattern='([^'..separator..']+)'; for part in tostring(text):gmatch(pattern) do table.insert(result,part) end; return result
end

local function parsePriceVarianceEnvelope(text)
    local flag,human=tostring(text or ''):match('^PV([01])#(.*)$')
    if flag==nil then return false,tostring(text or '') end
    return flag=='1',human or ''
end

local function parseWindowPlan(tooltip)
    local raw=tostring(tooltip or '')
    local machine,remainder=raw:match('^WP2:([^#]*)#(.*)$')
    if machine==nil then
        local priceVaries,human=parsePriceVarianceEnvelope(raw)
        return nil,human,priceVaries
    end
    local priceVaries,human=parsePriceVarianceEnvelope(remainder)
    local header,groupsText=machine:match('^(.-)~(.*)$'); if header==nil then return nil,human or '',priceVaries end
    local anchorText,phase,pairsText=header:match('^(%d+),([RS]),(.*)$'); if anchorText==nil then return nil,human or '',priceVaries end
    local plan={anchorAt=number(anchorText),anchorPhase=phase,cycles={},groups={}}
    for _,pair in ipairs(split(pairsText,'/')) do
        local delay,available=pair:match('^(%d+):(%d+)$'); if delay~=nil then table.insert(plan.cycles,{delay=number(delay),available=number(available)}) end
    end
    for _,entry in ipairs(split(groupsText,'/')) do
        local f=split(entry,',')
        if f[1]=='G' and #f>=11 then
            table.insert(plan.groups,{ordinal=number(f[2]),earlyRestock=number(f[3]),earlySellout=number(f[4]),lateRestock=number(f[5]),lateSellout=number(f[6]),safeStart=number(f[7]),safeEnd=number(f[8]),bestStart=number(f[9]),bestEnd=number(f[10]),bestProbability=number(f[11])})
        end
    end
    table.sort(plan.groups,function(a,b) return a.ordinal<b.ordinal end); return plan,human or '',priceVaries
end

local function probabilityAt(plan,arrivalAt)
    if plan==nil or #plan.cycles==0 or arrivalAt<plan.anchorAt then return 0 end
    local age=arrivalAt-plan.anchorAt; local hits=0
    for _,cycle in ipairs(plan.cycles) do
        local period=cycle.delay+cycle.available
        if period>0 then
            local phase=age%period; local hit=false
            if plan.anchorPhase=='R' then hit=phase<cycle.available else hit=phase>=cycle.delay and phase<(cycle.delay+cycle.available) end
            if hit then hits=hits+1 end
        end
    end
    return hits/#plan.cycles
end

local function staysAboveThresholdUntil(plan,startArrival,endArrival,threshold)
    if plan==nil or endArrival<=startArrival then return true end
    if probabilityAt(plan,startArrival)<=threshold then return false end
    local boundaries={}; local startAge=math.max(0,startArrival-plan.anchorAt); local endAge=math.max(0,endArrival-plan.anchorAt)
    for _,cycle in ipairs(plan.cycles) do
        local period=cycle.delay+cycle.available
        if period>0 then
            local base=plan.anchorPhase=='R' and 0 or cycle.delay
            local first=math.max(0,math.floor((startAge-base)/period)-1); local last=math.floor((endAge-base)/period)+1
            for n=first,last do
                local stockStart=plan.anchorAt+base+(n*period); local stockEnd=stockStart+cycle.available
                if stockStart>startArrival and stockStart<endArrival then boundaries[stockStart]=true end
                if stockEnd>startArrival and stockEnd<endArrival then boundaries[stockEnd]=true end
            end
        end
    end
    local times={}; for at,_ in pairs(boundaries) do table.insert(times,at) end; table.sort(times)
    for _,at in ipairs(times) do if probabilityAt(plan,at)<=threshold then return false end end
    return probabilityAt(plan,math.max(startArrival,endArrival-1))>threshold
end

local function groupMode(group)
    if group==nil then return nil end
    if group.safeStart>0 and group.safeEnd-group.safeStart>=60 then return 'safe' end
    if group.bestStart>0 and group.bestEnd>group.bestStart and group.bestProbability>0.5 then return 'best' end
    return nil
end

local function groupDepartureTimes(group,mode,flightSeconds)
    if mode=='safe' then return group.safeStart-flightSeconds,group.safeEnd-flightSeconds,math.floor(((group.safeStart+group.safeEnd)/2)-flightSeconds) end
    return group.bestStart-flightSeconds,group.bestEnd-flightSeconds,math.floor(((group.bestStart+group.bestEnd)/2)-flightSeconds)
end

local function formatMoment(at,now)
    if at<=0 then return '?' end; local relation=at>=now and (formatDuration(at-now)..' away') or (formatDuration(now-at)..' ago')
    return os.date('%H:%M',at)..' ('..relation..')'
end

local function formatCurrentCycleTooltip(selloutAt,deadlineAt,safetySeconds,flightSeconds,basis,now)
    local nl='#CRLF#'
    return 'Current Cycle Sellout: '..formatMoment(selloutAt,now)..nl..
        'Travel Time: '..formatDuration(flightSeconds)..nl..
        '5% Sellout Safety: '..formatDuration(safetySeconds)..nl..
        'Leave Before: '..formatMoment(deadlineAt,now)..nl..
        'Basis: '..basis
end
local function formatWindowTooltip(group,now)
    if group==nil then return 'Window evidence unavailable' end
    local nl='#CRLF#'; local safe='none'
    if group.safeStart>0 and group.safeEnd-group.safeStart>=60 then safe=os.date('%H:%M',group.safeStart)..' - '..os.date('%H:%M',group.safeEnd)..' ('..formatDuration(group.safeEnd-group.safeStart)..')' end
    local best='none'
    if group.bestStart>0 and group.bestEnd>group.bestStart then local target=math.floor((group.bestStart+group.bestEnd)/2); best=formatMoment(target,now)..' '..string.format('%.0f%%',group.bestProbability*100) end
    return 'Safe formula: max(restock starts) -> min(sellout ends)'..nl..'Best formula: completed-cycle overlap / usable cycle count'..nl..'Early Restock: '..formatMoment(group.earlyRestock,now)..' - '..formatMoment(group.earlySellout,now)..nl..'Late Restock: '..formatMoment(group.lateRestock,now)..' - '..formatMoment(group.lateSellout,now)..nl..'Safe Window: '..safe..nl..'Best Hit Window: '..best
end

local function findPreferredGroup(plan,flightSeconds,availableAt,now)
    if plan==nil then return nil,nil end
    for _,group in ipairs(plan.groups) do
        local mode=groupMode(group)
        if mode~=nil then
            local openAt,closeAt,targetAt=groupDepartureTimes(group,mode,flightSeconds)
            if mode=='safe' and closeAt>availableAt then return group,mode end
            if mode=='best' and closeAt>availableAt and (targetAt>availableAt or closeAt>now) then return group,mode end
        end
    end
    return nil,nil
end

local function nextBetterBestBefore(plan,currentGroup,currentProbability,flightSeconds,now)
    if plan==nil or currentGroup==nil then return nil end
    local startArrival=now+flightSeconds
    for _,group in ipairs(plan.groups) do
        if group.ordinal>currentGroup.ordinal and groupMode(group)=='best' and group.bestProbability>currentProbability then
            local _,_,targetAt=groupDepartureTimes(group,'best',flightSeconds)
            if targetAt>now and staysAboveThresholdUntil(plan,startArrival,targetAt+flightSeconds,0.5) then return group end
        end
    end
    return nil
end

local function opportunityStatePrefix(state,country,itemName)
    local count=math.max(0,math.min(256,math.floor(number(state.OpportunityCount))))
    local wantedCountry=trim(country):lower()
    local wantedName=trim(itemName):lower()
    for i=1,count do
        local prefix='Opportunity'..tostring(i)
        if trim(state[prefix..'Country']):lower()==wantedCountry and trim(state[prefix..'Name']):lower()==wantedName then
            return prefix
        end
    end
    return ''
end
local function clampProbability(value)
    return math.max(0,math.min(1,number(value)))
end

local function chancePercent(value)
    return string.format('%.0f%%',clampProbability(value)*100)
end

local function groupByOrdinal(plan,ordinal)
    if plan==nil then return nil end
    for _,group in ipairs(plan.groups or {}) do
        if number(group.ordinal)==ordinal then return group end
    end
    return nil
end

local function nextRestockStartForCycle(plan,cycle,ordinal)
    if plan==nil or cycle==nil then return 0 end
    local delay=number(cycle.delay); local available=number(cycle.available); local period=delay+available
    if period<=0 then return 0 end
    if plan.anchorPhase=='R' then
        if ordinal==0 then return plan.anchorAt end
        if ordinal==1 then return plan.anchorAt+period end
        return 0
    end
    if ordinal==0 then return plan.anchorAt+delay end
    return 0
end

local function bestNextRestockArrival(plan,group,ordinal)
    if plan==nil or group==nil then return 0,0 end
    local bestAt=number(group.earlyRestock); local bestP=clampProbability(probabilityAt(plan,bestAt))
    for _,cycle in ipairs(plan.cycles or {}) do
        local at=nextRestockStartForCycle(plan,cycle,ordinal)
        if at>=number(group.earlyRestock) and at<=number(group.lateRestock) then
            local p=clampProbability(probabilityAt(plan,at))
            if p>bestP or (p==bestP and (bestAt<=0 or at<bestAt)) then bestAt=at; bestP=p end
        end
    end
    return bestAt,bestP
end

local function formatNextCycleTooltip(group,bestArrival,bestChance,flightSeconds,now)
    if group==nil then return 'Next-cycle evidence unavailable' end
    local nl='#CRLF#'
    local safe='none'
    if group.safeStart>0 and group.safeEnd>group.safeStart then
        safe=formatMoment(group.safeStart-flightSeconds,now)..' -> '..formatMoment(group.safeEnd-flightSeconds,now)
    end
    return 'Next Restock Only'..nl..
        'Earliest Departure: '..formatMoment(group.earlyRestock-flightSeconds,now)..nl..
        'Best Departure: '..formatMoment(bestArrival-flightSeconds,now)..' '..chancePercent(bestChance)..nl..
        'Late Restock Departure: '..formatMoment(group.lateRestock-flightSeconds,now)..nl..
        'Safe Departure Window: '..safe
end

local function formatSleepingRestockTooltip(estimateAt,averageDelay,earlyDelay,lateDelay,lifetimeShort,lifetimeLong,samples,now)
    local nl='#CRLF#'
    return 'Lightweight OOS estimate'..nl..
        'Restocks in ~'..formatDuration(math.max(0,estimateAt-now))..nl..
        'Average OOS -> restock: '..formatDuration(averageDelay)..' over '..tostring(math.floor(samples))..' verified cycle(s)'..nl..
        'Recent range: '..formatDuration(earlyDelay)..' to '..formatDuration(lateDelay)..nl..
        'Lifetime range: '..formatDuration(lifetimeShort)..' to '..formatDuration(lifetimeLong)..nl..
        'Detailed forecast wakes 10m before historical earliest restock or while focused.'
end
local function formatCollectingTooltip(reason)
    local nl='#CRLF#'
    local detail=trim(reason)
    if detail=='' then detail='a required stock-cycle boundary was not observed or recovered' end
    return 'Collecting Data'..nl..
        'Reason: '..detail..nl..
        'Stale/frozen intervals are excluded from forecast timing.'..nl..
        'See Weav3r for the current travel-stock snapshot.'
end
local function homeNextCycleAction(plan,currentStock,nextOrdinal,flightSeconds,now)
    if plan==nil or #plan.groups==0 then
        return 'Collecting Data: See Weav3r','',formatCollectingTooltip('verified current/next-cycle evidence could not produce a usable next-restock window')
    end
    local group=groupByOrdinal(plan,nextOrdinal)
    if group==nil then return 'NEXT CYCLE UNAVAILABLE','',nil end

    local estimatedRestock=math.floor((number(group.earlyRestock)+number(group.lateRestock))/2)
    local bestArrival,bestChance=bestNextRestockArrival(plan,group,nextOrdinal)
    local tooltip=formatNextCycleTooltip(group,bestArrival,bestChance,flightSeconds,now)

    -- Scenario 2 Logic 1 only: the immediately next estimated restock must still
    -- be farther away than one full flight. Never search cycle +2/+3 here.
    if estimatedRestock<=0 or (estimatedRestock-now)<=flightSeconds then
        return 'NEXT RESTOCK WITHIN FLIGHT','',tooltip
    end

    local safeValid=group.safeStart>0 and group.safeEnd>group.safeStart
    if safeValid then
        local safeOpen=group.safeStart-flightSeconds
        local safeClose=group.safeEnd-flightSeconds
        local usefulHorizon=usefulWindowHorizon(flightSeconds)
        if now<safeOpen then return 'Safe Hit Window Open: '..formatDuration(safeOpen-now),'',tooltip end
        if now<safeClose then
            if (safeClose-now)>usefulHorizon then return 'Safe Hit Window Open','',tooltip end
            return 'Safe Hit Window Open. Closes: '..formatDuration(safeClose-now),'',tooltip
        end
        local liveChance=clampProbability(probabilityAt(plan,now+flightSeconds))
        if liveChance>0.5 then return 'Safe window closed. Leave Now: '..chancePercent(liveChance),'',tooltip end
        return 'Safe window closed.','',tooltip
    end

    local openDeparture=group.earlyRestock-flightSeconds
    local closeDeparture=group.lateRestock-flightSeconds
    local bestDeparture=bestArrival-flightSeconds
    local openChance=clampProbability(probabilityAt(plan,group.earlyRestock))
    local liveChance=clampProbability(probabilityAt(plan,now+flightSeconds))

    if now<openDeparture then
        return 'Window Open: '..formatDuration(openDeparture-now)..' '..chancePercent(openChance)..' Best: '..formatBestCountdown(math.max(0,bestDeparture-now))..' '..chancePercent(bestChance)..' Closes: '..formatDuration(math.max(0,closeDeparture-now)),'',tooltip
    end
    if now<bestDeparture then
        return 'Window Open: '..chancePercent(liveChance)..' Best: '..formatBestCountdown(bestDeparture-now)..' '..chancePercent(bestChance)..' Closes: '..formatDuration(math.max(0,closeDeparture-now)),'',tooltip
    end
    if now<closeDeparture then
        return 'Window Open: '..chancePercent(liveChance)..' Closes: '..formatDuration(closeDeparture-now),'',tooltip
    end
    return 'Window closed.','',tooltip
end
local function liveWindowAction(index,plan,state,country,defaultTravel,now)
    local countryId=countryIdsByName[country] or ''; local travelState=trim(state.TravelState):lower(); local destinationId=trim(state.TravelDestinationCountryId):lower()
    local flightSeconds=countryTravelSeconds(state,country,defaultTravel); if flightSeconds<=0 then return nil,nil,nil end

    local atHome=(travelState~='traveling' and travelState~='returning' and travelState~='abroad' and travelState~='foreign')
    if atHome then
        local displayedName=removeCountrySuffix(meterOption('MeterOpportunity'..tostring(index)..'Name','Text'),country)
        local statePrefix=opportunityStatePrefix(state,country,displayedName)
        local currentStock=statePrefix~='' and number(state[statePrefix..'CurrentStock']) or 0
        local reachable=statePrefix~='' and number(state[statePrefix..'CurrentCycleReachable'])>0
        local selloutAt=statePrefix~='' and number(state[statePrefix..'ActiveSelloutEstimateAt']) or 0
        local deadlineAt=statePrefix~='' and number(state[statePrefix..'CurrentCycleLeaveDeadlineAt']) or 0
        local safetySeconds=statePrefix~='' and number(state[statePrefix..'CurrentCycleSafetyMarginSeconds']) or 0
        local projectionMode=statePrefix~='' and trim(state[statePrefix..'LiveCycleProjectionMode']) or ''
        local dataQuality=statePrefix~='' and trim(state[statePrefix..'WindowDataQuality']):lower() or ''
        local dataQualityReason=statePrefix~='' and trim(state[statePrefix..'WindowDataQualityReason']) or ''
        local forecastMode=statePrefix~='' and trim(state[statePrefix..'ForecastMode']):lower() or ''
        local restockEstimateAt=statePrefix~='' and number(state[statePrefix..'RestockEstimateAt']) or 0
        local restockAverageDelay=statePrefix~='' and number(state[statePrefix..'RestockAverageDelaySeconds']) or 0
        local restockEarlyDelay=statePrefix~='' and number(state[statePrefix..'RestockEarliestDelaySeconds']) or 0
        local restockLateDelay=statePrefix~='' and number(state[statePrefix..'RestockLatestDelaySeconds']) or 0
        local restockLifetimeShort=statePrefix~='' and number(state[statePrefix..'RestockLifetimeShortestDelaySeconds']) or 0
        local restockLifetimeLong=statePrefix~='' and number(state[statePrefix..'RestockLifetimeLongestDelaySeconds']) or 0
        local restockSamples=statePrefix~='' and number(state[statePrefix..'RestockSampleCount']) or 0
        local nextOrdinal=statePrefix~='' and math.floor(number(state[statePrefix..'NextCycleOrdinal'])) or ((currentStock>0) and 1 or 0)

        if forecastMode=='sleeping_oos' and restockEstimateAt>now then
            return 'Restocks in ~'..formatDuration(restockEstimateAt-now),'',
                formatSleepingRestockTooltip(restockEstimateAt,restockAverageDelay,restockEarlyDelay,restockLateDelay,restockLifetimeShort,restockLifetimeLong,restockSamples,now)
        end

        if dataQuality=='collecting' then
            return 'Collecting Data: See Weav3r','',formatCollectingTooltip(dataQualityReason)
        end

        if currentStock>0 and reachable and selloutAt>now and deadlineAt>=now then
            local action=(deadlineAt-now)<=60 and 'Leave Now to hit.' or ('Leave Before '..formatDuration(deadlineAt-now)..' to hit.')
            local basis=(projectionMode=='historical-duration') and 'active restock + median completed-cycle stock duration' or 'live depletion of current observed stock'
            return action,'',formatCurrentCycleTooltip(selloutAt,deadlineAt,safetySeconds,flightSeconds,basis,now)
        end

        -- Current stock cannot beat the live sellout estimate (or is out of stock).
        -- Evaluate exactly one next-restock group and stop there.
        return homeNextCycleAction(plan,currentStock,nextOrdinal,flightSeconds,now)
    end

    if plan==nil or #plan.groups==0 then return nil,nil,nil end

    local effectiveFlightSeconds=flightSeconds
    if travelState=='traveling' and destinationId==countryId then local remaining=liveTravelRemainingSeconds(state,now); if remaining>0 then effectiveFlightSeconds=remaining end end
    local availableAt=now; if travelState=='returning' then availableAt=now+liveTravelRemainingSeconds(state,now) end
    local group,mode=findPreferredGroup(plan,effectiveFlightSeconds,availableAt,now); if group==nil then return 'WAIT DATA','',nil end
    local tooltip=formatWindowTooltip(group,now)

    if travelState=='traveling' and destinationId==countryId then
        local arrivalAt=number(state.TravelArrivalAt); if arrivalAt<=now then arrivalAt=now+effectiveFlightSeconds end; local p=probabilityAt(plan,arrivalAt)
        if mode=='safe' and arrivalAt>=group.safeStart and arrivalAt<group.safeEnd then return 'SAFE AT ARRIVAL','',tooltip end
        if mode=='best' then return 'BEST AT ARRIVAL',string.format('%.0f%%',p*100),tooltip end
        return 'MARKET DATA PENDING','',tooltip
    end
    if travelState=='abroad' and destinationId==countryId then return 'MARKET DATA PENDING','',tooltip end

    local openAt,closeAt,targetAt=groupDepartureTimes(group,mode,flightSeconds)
    if mode=='safe' then
        if now<openAt then return 'SAFE - LEAVE IN '..formatDuration(openAt-now),'',tooltip end
        if now<closeAt then return 'SAFE - LEAVE BEFORE '..formatDuration(closeAt-now),'',tooltip end
        return 'WAIT DATA','',tooltip
    end

    local currentProbability=probabilityAt(plan,now+flightSeconds)
    if currentProbability>0.5 then
        local _,_,sameTarget=groupDepartureTimes(group,'best',flightSeconds)
        if group.bestProbability>currentProbability and sameTarget>now and staysAboveThresholdUntil(plan,now+flightSeconds,sameTarget+flightSeconds,0.5) then
            return 'BEST - LEAVE IN '..formatBestCountdown(sameTarget-now),string.format('%.0f%%',group.bestProbability*100),tooltip
        end
        local better=nextBetterBestBefore(plan,group,currentProbability,flightSeconds,now)
        if better~=nil then local _,_,betterTarget=groupDepartureTimes(better,'best',flightSeconds); return 'BEST - LEAVE IN '..formatBestCountdown(betterTarget-now),string.format('%.0f%%',better.bestProbability*100),formatWindowTooltip(better,now) end
        return 'BEST - LEAVE NOW',string.format('%.0f%%',currentProbability*100),tooltip
    end

    if now<openAt then return 'BEST - LEAVE IN '..formatBestCountdown(targetAt-now),string.format('%.0f%%',group.bestProbability*100),tooltip end
    for _,nextGroup in ipairs(plan.groups) do
        if nextGroup.ordinal>group.ordinal and groupMode(nextGroup)~=nil then
            local nextMode=groupMode(nextGroup); local nOpen,nClose,nTarget=groupDepartureTimes(nextGroup,nextMode,flightSeconds)
            if nextMode=='safe' and nClose>now then
                if now<nOpen then return 'SAFE - LEAVE IN '..formatDuration(nOpen-now),'',formatWindowTooltip(nextGroup,now) end
                return 'SAFE - LEAVE BEFORE '..formatDuration(nClose-now),'',formatWindowTooltip(nextGroup,now)
            elseif nextMode=='best' and nTarget>now then return 'BEST - LEAVE IN '..formatBestCountdown(nTarget-now),string.format('%.0f%%',nextGroup.bestProbability*100),formatWindowTooltip(nextGroup,now) end
        end
    end
    return 'WAIT DATA','',tooltip
end

local function applyCompactLayout(index)
    local prefix='MeterOpportunity'..index
    setOption(prefix..'Name','X',78); setOption(prefix..'Name','W',176); setOption(prefix..'Gross','X',504); setOption(prefix..'Gross','W',244); setOption(prefix..'Gross','ClipString',1)
    setOption(prefix..'Window','X',78); setOption(prefix..'Window','W',70); setOption(prefix..'Leave','X',150); setOption(prefix..'Leave','W',164); setOption(prefix..'Chance','X',316); setOption(prefix..'Chance','W',48); setOption(prefix..'Chance','ClipString',1); setOption(prefix..'Price','X',366); setOption(prefix..'Price','W',144)
end

local function configureWindowTooltipMeter(name,tooltip)
    -- Empty ToolTipText disables the tooltip naturally. Do not mutate ToolTipHidden
    -- at runtime; target Rainmeter interpreted a dynamic numeric 0 as a config name.
    setOption(name,'DynamicVariables',1)
    setOption(name,'ToolTipTitle','Window calculation')
    setOption(name,'ToolTipWidth',420)
    setOption(name,'ToolTipText',tooltip or '')
    setOption(name,'SolidColor','0,0,0,1')
end

local function updateRow(index,state,now)
    local prefix='MeterOpportunity'..index; applyCompactLayout(index); local rawTitle=meterOption(prefix..'Name','Text'); if rawTitle=='' then return end
    local country,travel=rowCountryAndTravel(index); local itemName=removeCountrySuffix(rawTitle,country); local totalProfit=parseMoney(meterOption(prefix..'Gross','Text'))
    local rawTooltip=meterOption(prefix..'Gross','ToolTipText'); local plan,humanTooltip,priceVaries=parseWindowPlan(rawTooltip); local quantity=quantityFromTooltip(humanTooltip); local unitProfit=quantity>0 and totalProfit/quantity or 0
    local equation=formatMoney(unitProfit)..'/ea'; if quantity>0 then equation=equation..' x'..tostring(quantity)..' = '..formatMoney(totalProfit) else equation=formatMoney(totalProfit) end
    local buyPrice=buyPriceFromVisibleText(meterOption(prefix..'Price','Text')); local bufferRate=priceVaries and 0.05 or 0.0
    local take=(buyPrice>0 and quantity>0) and math.ceil(buyPrice*quantity*(1.0+bufferRate)) or 0
    local fallbackWindow=meterOption(prefix..'Window','Text'); local fallbackLeave=meterOption(prefix..'Leave','Text'); local fallbackCertainty=meterOption(prefix..'Chance','Text')
    local liveAction,liveCertainty,windowTooltip=liveWindowAction(index,plan,state,country,travel,now)

    setOption(prefix..'Name','Text',itemName); setOption(prefix..'Name','ToolTipText','')
    setOption(prefix..'Gross','Text',equation); setOption(prefix..'Gross','ToolTipText','Net profit per item x planned inventory quantity = total net profit')
    setOption(prefix..'Gross','InlinePattern','\\$'); setOption(prefix..'Gross','InlineSetting','Color | 255,255,255,255')
    setOption(prefix..'Gross','InlinePattern2','/ea x[0-9]+ ='); setOption(prefix..'Gross','InlineSetting2','Color | 255,255,255,255')
    setOption(prefix..'Window','Text',rowFlightText(state,country,travel,now)); setOption(prefix..'Window','FontColor','#Muted#')
    if liveAction~=nil then
        local certainty=liveCertainty or ''
        local safeInfo=(liveAction:match('^SAFE')~=nil and certainty=='' and trim(windowTooltip)~='')
        if safeInfo then certainty='ⓘ' end
        setOption(prefix..'Leave','Text',liveAction); setOption(prefix..'Chance','Text',certainty)
        setOption(prefix..'Chance','FontFace',safeInfo and 'Segoe UI Symbol' or 'Segoe UI')
        configureWindowTooltipMeter(prefix..'Leave',windowTooltip or '')
        configureWindowTooltipMeter(prefix..'Chance',windowTooltip or '')
    else
        setOption(prefix..'Leave','Text',statusText(fallbackWindow,fallbackLeave)); setOption(prefix..'Chance','Text',fallbackCertainty); setOption(prefix..'Chance','FontFace','Segoe UI')
        configureWindowTooltipMeter(prefix..'Leave',''); configureWindowTooltipMeter(prefix..'Chance','')
    end
    if take>0 then
        setOption(prefix..'Price','Text','Take: '..formatMoney(take))
        if priceVaries then setOption(prefix..'Price','ToolTipText','Purchase cash required plus a 5% buffer because retained foreign price has varied')
        else setOption(prefix..'Price','ToolTipText','Exact purchase cash; retained foreign price has not varied') end
    else setOption(prefix..'Price','Text','Take: ?'); setOption(prefix..'Price','ToolTipText','Purchase cash requirement unavailable') end
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
    for i=1,8 do applyCompactLayout(i) end
end

function Update()
    local state=readKv(statePath); local now=os.time(); local travelSignature=trim(state.TravelState)..':'..trim(state.TravelDestinationCountryId)
    if lastTravelStateSignature~='' and travelSignature~=lastTravelStateSignature then SKIN:Bang('!UpdateMeasure','MeasureState') end; lastTravelStateSignature=travelSignature
    for i=1,8 do updateRow(i,state,now) end; return 0
end
