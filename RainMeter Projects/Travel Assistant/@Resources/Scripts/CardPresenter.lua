local statePath = nil
local lastTravelStateSignature = ''

local countryIdsByName = {
    ['Mexico']='mexico',
    ['Cayman Islands']='cayman_islands',
    ['Canada']='canada',
    ['Hawaii']='hawaii',
    ['United Kingdom']='united_kingdom',
    ['Argentina']='argentina',
    ['Switzerland']='switzerland',
    ['Japan']='japan',
    ['China']='china',
    ['United Arab Emirates']='united_arab_emirates',
    ['South Africa']='south_africa'
}

local function trim(value)
    local text = tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function readKv(path)
    local out = {}
    local file = io.open(path,'r')
    if not file then return out end
    for line in file:lines() do
        local key,value = line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)] = trim(value) end
    end
    file:close()
    return out
end

local function number(value)
    return tonumber(value) or 0
end

local function meterOption(name, option)
    local meter = SKIN:GetMeter(name)
    if meter == nil then return '' end
    return trim(meter:GetOption(option,''))
end

local function setOption(name, option, value)
    if SKIN:GetMeter(name) ~= nil then
        SKIN:Bang('!SetOption',name,option,tostring(value or ''))
    end
end

local function parseMoney(text)
    local value = trim(text)
    local negative = value:find('%-') ~= nil
    value = value:gsub('[^%d]','')
    local n = tonumber(value) or 0
    return negative and -n or n
end

local function formatMoney(value)
    local rounded
    if value < 0 then rounded = -math.floor(math.abs(value)+0.5)
    else rounded = math.floor(value+0.5) end
    local negative = rounded < 0
    local digits = tostring(math.abs(rounded))
    local out = digits:reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','')
    return (negative and '-$' or '$') .. out
end

local function formatDuration(seconds)
    local value = math.max(0,math.floor(number(seconds)))
    if value <= 0 then return '<1m' end
    local hours = math.floor(value/3600)
    local minutes = math.floor((value%3600)/60)
    if hours > 0 then return string.format('%dh %dm',hours,minutes) end
    if minutes > 0 then return string.format('%dm',minutes) end
    return '<1m'
end

local function parseDurationText(text)
    local value = trim(text):lower()
    local hours = tonumber(value:match('(%d+)%s*h')) or 0
    local minutes = tonumber(value:match('(%d+)%s*m')) or 0
    return (hours*3600)+(minutes*60)
end

local function removeCountrySuffix(title,country)
    title = trim(title)
    country = trim(country)
    if country == '' then return title end
    local suffix = ' - ' .. country
    if #title >= #suffix and title:sub(-#suffix) == suffix then
        return trim(title:sub(1,#title-#suffix))
    end
    return title
end

local function quantityFromTooltip(tooltip)
    local q = trim(tooltip):match('%s+x%s*(%d+)%s*=')
    if q == nil then q = trim(tooltip):match('x(%d+)') end
    return tonumber(q) or 0
end

local function buyPriceFromVisibleText(text)
    local raw = trim(text):match('BUY%s+([^|]+)')
    if raw == nil then raw = text end
    return parseMoney(raw)
end

local function rowCountryAndTravel(index)
    local tooltip = meterOption('MeterOpportunity'..index..'Flag','ToolTipText')
    local country,travel = tooltip:match('^(.-)%s*|%s*travel%s+(.+)$')
    return trim(country),trim(travel)
end

local function liveTravelRemainingSeconds(state,now)
    local arrivalAt = number(state.TravelArrivalAt)
    if arrivalAt > now then return arrivalAt - now end
    local projectedLeft = number(state.TravelTimeLeft)
    local projectedAt = number(state.TravelContextLastSuccessAt)
    if projectedLeft > 0 and projectedAt > 0 then
        return math.max(0,projectedLeft - math.max(0,now-projectedAt))
    end
    return 0
end

local function rowFlightText(state,country,defaultTravel,now)
    local countryId = countryIdsByName[country] or ''
    local travelState = trim(state.TravelState):lower()
    local destinationId = trim(state.TravelDestinationCountryId):lower()
    if travelState == 'traveling' and countryId ~= '' and destinationId == countryId then
        local remaining = liveTravelRemainingSeconds(state,now)
        if remaining > 0 then return formatDuration(remaining) .. ' left' end
    elseif travelState == 'abroad' and countryId ~= '' and destinationId == countryId then
        return 'AT DEST.'
    end
    if defaultTravel ~= '' then return defaultTravel end
    return '?'
end

local function countryTravelSeconds(state,country,defaultTravel)
    local countryId = countryIdsByName[country] or ''
    local key = ''
    if countryId == 'united_kingdom' then key='UKTravelSeconds'
    elseif countryId == 'japan' then key='JPTravelSeconds'
    elseif countryId ~= '' then key=string.upper(countryId)..'TravelSeconds' end
    local seconds = key ~= '' and number(state[key]) or 0
    if seconds > 0 then return seconds end
    return parseDurationText(defaultTravel)
end

local function isDurationOnly(text)
    local value = trim(text):lower()
    if value == '' then return false end
    if value == '<1m' then return true end
    if value:match('^%d+%s*m$') then return true end
    if value:match('^%d+%s*h$') then return true end
    if value:match('^%d+%s*h%s+%d+%s*m$') then return true end
    return false
end

local function statusText(windowText,leaveText)
    local window = trim(windowText)
    local leave = trim(leaveText)
    if isDurationOnly(window) then window = '' end
    if window == '' then return leave end
    if leave == '' or leave == window then return window end
    return window .. ' / ' .. leave
end

local function split(text,separator)
    local result = {}
    if text == nil or text == '' then return result end
    local pattern = '([^'..separator..']+)'
    for part in tostring(text):gmatch(pattern) do table.insert(result,part) end
    return result
end

local function parseWindowPlan(tooltip)
    local machine,human = tostring(tooltip or ''):match('^WP1:([^#]*)#(.*)$')
    if machine == nil then return nil,tostring(tooltip or '') end
    local groupsText,segmentsText = machine:match('^(.-)~(.*)$')
    if groupsText == nil then return nil,human or '' end
    local plan = { groups={}, segments={} }
    for _,entry in ipairs(split(groupsText,'/')) do
        local f=split(entry,',')
        if f[1]=='G' and #f >= 11 then
            table.insert(plan.groups,{
                ordinal=number(f[2]), earlyRestock=number(f[3]), earlySellout=number(f[4]),
                lateRestock=number(f[5]), lateSellout=number(f[6]), safeStart=number(f[7]),
                safeEnd=number(f[8]), bestStart=number(f[9]), bestEnd=number(f[10]),
                bestProbability=number(f[11])
            })
        end
    end
    for _,entry in ipairs(split(segmentsText,'/')) do
        local f=split(entry,',')
        if #f >= 3 then table.insert(plan.segments,{startAt=number(f[1]),endAt=number(f[2]),probability=number(f[3])}) end
    end
    table.sort(plan.groups,function(a,b) return a.ordinal < b.ordinal end)
    table.sort(plan.segments,function(a,b) return a.startAt < b.startAt end)
    return plan,human or ''
end

local function probabilityAt(plan,arrivalAt)
    if plan == nil then return -1,nil end
    for _,segment in ipairs(plan.segments) do
        if arrivalAt >= segment.startAt and arrivalAt < segment.endAt then return segment.probability,segment end
    end
    return 0,nil
end

local function supportRunEndDeparture(plan,currentSegment,flightSeconds)
    if plan==nil or currentSegment==nil then return 0 end
    local runEnd=currentSegment.endAt
    local found=false
    for _,segment in ipairs(plan.segments) do
        if not found then
            if segment.startAt==currentSegment.startAt and segment.endAt==currentSegment.endAt then found=true end
        elseif segment.startAt <= runEnd+1 and segment.probability > 0.5 then
            if segment.endAt > runEnd then runEnd=segment.endAt end
        elseif segment.startAt > runEnd+1 then
            break
        else
            break
        end
    end
    return runEnd-flightSeconds
end

local function groupMode(group)
    if group == nil then return nil end
    if group.safeStart > 0 and group.safeEnd-group.safeStart >= 60 then return 'safe' end
    if group.bestStart > 0 and group.bestEnd > group.bestStart and group.bestProbability > 0.5 then return 'best' end
    return nil
end

local function groupDepartureTimes(group,mode,flightSeconds)
    if mode=='safe' then
        return group.safeStart-flightSeconds,group.safeEnd-flightSeconds,math.floor(((group.safeStart+group.safeEnd)/2)-flightSeconds)
    end
    return group.bestStart-flightSeconds,group.bestEnd-flightSeconds,math.floor(((group.bestStart+group.bestEnd)/2)-flightSeconds)
end

local function formatMoment(at,now)
    if at <= 0 then return '?' end
    local relation
    if at >= now then relation=formatDuration(at-now)..' away'
    else relation=formatDuration(now-at)..' ago' end
    return os.date('%H:%M',at)..' ('..relation..')'
end

local function formatWindowTooltip(group,now)
    if group == nil then return 'Window evidence unavailable' end
    local nl='#CRLF#'
    local safe='none'
    if group.safeStart > 0 and group.safeEnd-group.safeStart >= 60 then
        safe=os.date('%H:%M',group.safeStart)..' - '..os.date('%H:%M',group.safeEnd)..' ('..formatDuration(group.safeEnd-group.safeStart)..')'
    end
    local best='none'
    if group.bestStart > 0 and group.bestEnd > group.bestStart then
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

local function findPreferredGroup(plan,flightSeconds,availableAt,now)
    if plan == nil then return nil,nil end
    for _,group in ipairs(plan.groups) do
        local mode=groupMode(group)
        if mode ~= nil then
            local openAt,closeAt,targetAt=groupDepartureTimes(group,mode,flightSeconds)
            if mode=='safe' then
                if closeAt > availableAt then return group,mode end
            elseif closeAt > availableAt and (targetAt > availableAt or closeAt > now) then
                return group,mode
            end
        end
    end
    return nil,nil
end

local function nextBetterBestBefore(plan,currentGroup,currentProbability,supportEndsAt,flightSeconds,now)
    if plan==nil or currentGroup==nil then return nil end
    for _,group in ipairs(plan.groups) do
        if group.ordinal > currentGroup.ordinal and groupMode(group)=='best' and group.bestProbability > currentProbability then
            local _,_,targetAt=groupDepartureTimes(group,'best',flightSeconds)
            if targetAt > now and targetAt < supportEndsAt then return group end
        end
    end
    return nil
end

local function liveWindowAction(plan,state,country,defaultTravel,now)
    if plan==nil or #plan.groups==0 then return nil,nil,nil end
    local countryId=countryIdsByName[country] or ''
    local travelState=trim(state.TravelState):lower()
    local destinationId=trim(state.TravelDestinationCountryId):lower()
    local flightSeconds=countryTravelSeconds(state,country,defaultTravel)
    if flightSeconds <= 0 then return nil,nil,nil end

    local effectiveFlightSeconds=flightSeconds
    if travelState=='traveling' and destinationId==countryId then
        local remaining=liveTravelRemainingSeconds(state,now)
        if remaining>0 then effectiveFlightSeconds=remaining end
    end
    local availableAt=now
    if travelState=='returning' then availableAt=now+liveTravelRemainingSeconds(state,now) end
    local group,mode=findPreferredGroup(plan,effectiveFlightSeconds,availableAt,now)
    if group==nil then return 'WAIT DATA','',nil end
    local tooltip=formatWindowTooltip(group,now)

    if travelState=='traveling' and destinationId==countryId then
        local arrivalAt=number(state.TravelArrivalAt)
        if arrivalAt <= now then arrivalAt=now+effectiveFlightSeconds end
        local p=probabilityAt(plan,arrivalAt)
        if mode=='safe' and arrivalAt>=group.safeStart and arrivalAt<group.safeEnd then return 'SAFE - EN ROUTE','',tooltip end
        if mode=='best' then return 'BEST - EN ROUTE',p>=0 and string.format('%.0f%%',p*100) or '',tooltip end
        return 'EN ROUTE','',tooltip
    end
    if travelState=='abroad' and destinationId==countryId then return 'AT DEST.','',tooltip end

    local openAt,closeAt,targetAt=groupDepartureTimes(group,mode,flightSeconds)
    if mode=='safe' then
        if now < openAt then return 'SAFE - LEAVE '..formatDuration(openAt-now),'',tooltip end
        if now < closeAt then return 'SAFE - LEAVE BEFORE '..formatDuration(closeAt-now),'',tooltip end
        return 'WAIT DATA','',tooltip
    end

    local currentProbability,currentSegment=probabilityAt(plan,now+flightSeconds)
    if currentProbability > 0.5 then
        local supportEndsAt=supportRunEndDeparture(plan,currentSegment,flightSeconds)
        local _,_,sameTarget=groupDepartureTimes(group,'best',flightSeconds)
        if group.bestProbability > currentProbability and sameTarget > now and sameTarget < supportEndsAt then
            return 'BEST - LEAVE '..formatDuration(sameTarget-now),string.format('%.0f%%',group.bestProbability*100),tooltip
        end
        local better=nextBetterBestBefore(plan,group,currentProbability,supportEndsAt,flightSeconds,now)
        if better~=nil then
            local _,_,betterTarget=groupDepartureTimes(better,'best',flightSeconds)
            return 'BEST - LEAVE '..formatDuration(betterTarget-now),string.format('%.0f%%',better.bestProbability*100),formatWindowTooltip(better,now)
        end
        return 'BEST - LEAVE NOW',string.format('%.0f%%',currentProbability*100),tooltip
    end

    if targetAt > now then return 'BEST - LEAVE '..formatDuration(targetAt-now),string.format('%.0f%%',group.bestProbability*100),tooltip end

    for _,nextGroup in ipairs(plan.groups) do
        if nextGroup.ordinal > group.ordinal and groupMode(nextGroup)~=nil then
            local nextMode=groupMode(nextGroup)
            local nOpen,nClose,nTarget=groupDepartureTimes(nextGroup,nextMode,flightSeconds)
            if nextMode=='safe' and nClose>now then
                if now<nOpen then return 'SAFE - LEAVE '..formatDuration(nOpen-now),'',formatWindowTooltip(nextGroup,now) end
                return 'SAFE - LEAVE BEFORE '..formatDuration(nClose-now),'',formatWindowTooltip(nextGroup,now)
            elseif nextMode=='best' and nTarget>now then
                return 'BEST - LEAVE '..formatDuration(nTarget-now),string.format('%.0f%%',nextGroup.bestProbability*100),formatWindowTooltip(nextGroup,now)
            end
        end
    end
    return 'WAIT DATA','',tooltip
end

local function applyCompactLayout(index)
    local prefix = 'MeterOpportunity'..index
    setOption(prefix..'Name','X',78)
    setOption(prefix..'Name','W',176)
    setOption(prefix..'Gross','X',504)
    setOption(prefix..'Gross','W',244)
    setOption(prefix..'Gross','ClipString',1)
    setOption(prefix..'Window','X',78)
    setOption(prefix..'Window','W',70)
    setOption(prefix..'Leave','X',150)
    setOption(prefix..'Leave','W',164)
    setOption(prefix..'Chance','X',316)
    setOption(prefix..'Chance','W',48)
    setOption(prefix..'Chance','ClipString',1)
    setOption(prefix..'Price','X',366)
    setOption(prefix..'Price','W',144)
end

local function updateRow(index,state,now)
    local prefix = 'MeterOpportunity'..index
    applyCompactLayout(index)
    local rawTitle = meterOption(prefix..'Name','Text')
    if rawTitle == '' then return end

    local country,travel = rowCountryAndTravel(index)
    local itemName = removeCountrySuffix(rawTitle,country)
    local totalProfit = parseMoney(meterOption(prefix..'Gross','Text'))
    local rawTooltip = meterOption(prefix..'Gross','ToolTipText')
    local plan,humanTooltip = parseWindowPlan(rawTooltip)
    local quantity = quantityFromTooltip(humanTooltip)
    local unitProfit = 0
    if quantity > 0 then unitProfit = totalProfit / quantity end

    local equation = formatMoney(unitProfit) .. '/ea'
    if quantity > 0 then equation = equation .. ' x' .. tostring(quantity) .. ' = ' .. formatMoney(totalProfit)
    else equation = formatMoney(totalProfit) end

    local buyPrice = buyPriceFromVisibleText(meterOption(prefix..'Price','Text'))
    local take = 0
    if buyPrice > 0 and quantity > 0 then take = math.ceil(buyPrice * quantity * 1.05) end

    local fallbackWindow = meterOption(prefix..'Window','Text')
    local fallbackLeave = meterOption(prefix..'Leave','Text')
    local fallbackCertainty = meterOption(prefix..'Chance','Text')
    local liveAction,liveCertainty,windowTooltip = liveWindowAction(plan,state,country,travel,now)

    setOption(prefix..'Name','Text',itemName)
    setOption(prefix..'Name','ToolTipText','')
    setOption(prefix..'Gross','Text',equation)
    setOption(prefix..'Gross','ToolTipText','Net profit per item x planned inventory quantity = total net profit')
    setOption(prefix..'Window','Text',rowFlightText(state,country,travel,now))
    setOption(prefix..'Window','FontColor','#Muted#')
    if liveAction~=nil then
        setOption(prefix..'Leave','Text',liveAction)
        setOption(prefix..'Chance','Text',liveCertainty or '')
        setOption(prefix..'Leave','ToolTipText',windowTooltip or '')
        setOption(prefix..'Chance','ToolTipText',windowTooltip or '')
    else
        setOption(prefix..'Leave','Text',statusText(fallbackWindow,fallbackLeave))
        setOption(prefix..'Chance','Text',fallbackCertainty)
        setOption(prefix..'Leave','ToolTipText','')
        setOption(prefix..'Chance','ToolTipText','')
    end
    if take > 0 then
        setOption(prefix..'Price','Text','Take: '..formatMoney(take))
        setOption(prefix..'Price','ToolTipText','Purchase cash required plus a 5% buffer')
    else
        setOption(prefix..'Price','Text','Take: ?')
        setOption(prefix..'Price','ToolTipText','Purchase cash requirement unavailable')
    end
end

function Initialize()
    statePath = SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
    for i=1,8 do applyCompactLayout(i) end
end

function Update()
    local state = readKv(statePath)
    local now = os.time()
    local travelSignature = trim(state.TravelState)..':'..trim(state.TravelDestinationCountryId)
    if lastTravelStateSignature ~= '' and travelSignature ~= lastTravelStateSignature then SKIN:Bang('!UpdateMeasure','MeasureState') end
    lastTravelStateSignature = travelSignature
    for i=1,8 do updateRow(i,state,now) end
    return 0
end
