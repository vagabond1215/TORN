local statePath = nil
local heartbeatPath = nil
local generatedDir = nil
local flagDir = nil
local flagMaskDir = nil
local itemImageDir = nil
local pollInterval = 60
local failureRetryInterval = 15
local failureRetryArmed = false
local nextPollAt = nil
local lastProjectionData = nil
local lastRenderData = nil
local lastDisplayedData = nil
local pendingSortMode = nil
local lastSortMode = nil
local pendingTripBands = nil
local activeTripBands = { short=true, medium=true, long=true }
local expandedKey = ''
local expandedRow = 0
local expandedDetailKey = ''
local expandedDetailRow = 0
local lastInlineRenderRequestAt = 0
local lastLayoutSignature = ''
local lastGraphSignature = ''
local lastFlagKeys = {}
local lastItemImageRequestSignature = ''
local lastItemImageRequestAt = 0

local collapsedCardHeight = 50
local rowStride = 54
local detailExtra = 34
local graphExtra = 133
local footerExtra = 16
local maxCandidateRows = 256
local maxGraphHoverRegions = 48

local opportunitySuffixes = {
    'Key','Name','Country','CountryCode','TripBand','WindowText','LeaveText','ChanceText','TimeText',
    'GrossText','QuantityText','ProfitHourText','PriceText','MarketValueText','PriceColor',
    'Tooltip','GrossValue','ProfitHourValue','WindowStartAt','ProbabilityValue','ElapsedSeconds',
    'MarketValueValue','PurchaseCostValue','TotalCostValue','GrossSaleValue','GrossProfitValue',
    'MarketTaxValue','MakeValue','ProfitEachValue','MarketFeePercent',
    'PriceVaries','PriceVariationReason',
    'MinObservedPrice','MaxObservedPrice',
    'MultiCycleChanceEligible','MultiCycleChanceProbability','MultiCycleTargetProbability','MultiCycleDutyCycleProbability',
    'MultiCycleMeanPeriodSeconds','MultiCycleMeanInStockSeconds','MultiCyclePeriodStdDevSeconds','MultiCycleArrivalCycleRatio',
    'MultiCycleExpectedFullCycles','MultiCyclePhaseStdDevSeconds','MultiCyclePhaseStdDevCycles','MultiCycleSampleCount',
    'MultiCycleEffectiveSampleSize','MultiCycleMaximumOrdinal','MultiCycleArrivalAt','MultiCycleGeneratedAt',
    'MultiCycleSimulationCount','MultiCycleModelVersion','MultiCycleReason',
    'CurrentStockSafetyEligible','CurrentStockSafetySampleCount','CurrentStockSafetyEvidenceSpanSeconds',
    'CurrentStockSafetyPercentileUnitsPerHour','CurrentStockSafetyGuardedUnitsPerHour','CurrentStockSafetyRunwaySeconds',
    'CurrentStockSafetyArrivalHorizonSeconds','CurrentStockSafetyMarginSeconds','CurrentStockSafetySelloutEstimateAt',
    'CurrentStockSafetyReason'
}

local flagCodes = {
    mexico='MX',
    cayman_islands='KY',
    canada='CA',
    hawaii='US',
    united_kingdom='GB',
    argentina='AR',
    switzerland='CH',
    japan='JP',
    china='CN',
    united_arab_emirates='AE',
    south_africa='ZA'
}

local tripBandsByCountry = {
    mexico='short', cayman_islands='short', canada='short',
    hawaii='medium', united_kingdom='medium', argentina='medium', switzerland='medium',
    japan='long', china='long', united_arab_emirates='long', south_africa='long'
}

-- Defensive local names for the most common foreign-shop goods. Normal rendering
-- prefers projected catalog/provider names; this also replaces generic Item <id>
-- placeholders when the ID is already known locally.
local itemNameFallbacks = {
    [110]='Leather Bullwhip', [175]='Taser', [206]='Xanax', [226]='Smoke Grenade', [227]='Spear',
    [230]='Flare Gun', [231]='Heckler & Koch SL8', [258]='Jaguar Plushie', [260]='Dahlia',
    [261]='Wolverine Plushie', [262]='Hockey Stick', [263]='Crocus', [264]='Orchid', [265]='Pele Charm',
    [266]='Nessie Plushie', [267]='Heather', [268]='Red Fox Plushie', [269]='Monkey Plushie',
    [270]='Soccer Ball', [271]='Ceibo Flower', [272]='Edelweiss', [273]='Chamois Plushie',
    [274]='Panda Plushie', [275]='Jade Buddha', [276]='Peony', [277]='Cherry Blossom',
    [278]='Kabuki Mask', [279]='Maneki Neko', [280]='Elephant Statue', [281]='Lion Plushie',
    [282]='African Violet', [294]='Bottle of Sake', [384]='Camel Plushie', [385]='Tribulus Omanense',
    [406]='Afro Comb', [426]='Bottle of Tequila', [616]='Trout', [617]='Banana Orchid',
    [618]='Stingray Plushie', [619]='Steel Drum', [620]='Nodding Turtle',
    [1487]='Patagonian Fossil', [1488]='Meteorite Fragment', [1494]='Pangolin Scales',
    [1495]='Ambergris Lump', [1496]='Natural Pearls', [1497]='Uncut Diamonds',
    [1498]='Tiger Bone Powder', [1499]='Obsidian Point', [1500]='Quartzite Point',
    [1501]='Chert Point', [1502]='Basalt Point', [1503]='Chalcedony Point', [1504]='Quartz Point'
}

local function trim(s)
    s = tostring(s or ''):gsub('^\239\187\191', '')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function number(v)
    local n = tonumber(v)
    if n == nil then return 0 end
    return n
end

local function safeText(v, fallback)
    local value = trim(v)
    if value == '' then return fallback or '' end
    -- string.gsub returns (text, substitutionCount). Parentheses deliberately
    -- collapse that multi-return so a final safeText(...) argument cannot leak an
    -- extra numeric Config argument into SKIN:Bang('!SetOption', ...).
    return (value:gsub('[\r\n]', ' '))
end

local function moneyNumber(v)
    local text = safeText(v, ''):gsub(',', ''):gsub('%$', ''):gsub('/hr', '')
    local sign = 1
    if text:sub(1,1) == '-' then sign = -1 end
    text = text:gsub('[^%d%.]', '')
    return sign * (tonumber(text) or 0)
end

local function readKv(path)
    if path==statePath then
        local manifest=io.open((path:match('^(.*[\\/])') or '')..'last-update.txt','r')
        if manifest then
            local raw=manifest:read('*a') or ''; manifest:close()
            local name=raw:match('^%d+|(ui%-state%-%d+%-%x+%.kv)')
            if name then path=(path:match('^(.*[\\/])') or '')..name end
        end
    end
    local out = {}
    local file = io.open(path, 'r')
    if not file then return out end
    for line in file:lines() do
        local key, value = line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)] = trim(value) end
    end
    file:close()
    return out
end

local function readState()
    return readKv(statePath)
end

local function copyTable(data)
    local out = {}
    for key, value in pairs(data or {}) do out[key] = value end
    return out
end

local function copyProjectionFields(data)
    local out = {}
    for key, value in pairs(data or {}) do
        if key:match('^Opportunity') or key:match('^UI') then out[key] = value end
    end
    return out
end

local function stabilizeProjection(data)
    if data.OpportunityCount ~= nil then
        local incomingCount = math.max(0, math.floor(number(data.OpportunityCount)))
        local incomingMessage = safeText(data.OpportunityMessage, '')
        local cachedCount = 0
        if lastProjectionData ~= nil then cachedCount = math.max(0, math.floor(number(lastProjectionData.OpportunityCount))) end

        if incomingCount > 0 then
            lastProjectionData = copyProjectionFields(data)
        elseif cachedCount > 0 and incomingMessage:match('^Learning') then
            local incomingSortMode = data.OpportunitySortMode
            for key, value in pairs(lastProjectionData) do
                if key:match('^Opportunity') then data[key] = value
                elseif key:match('^UI') and data[key] == nil then data[key] = value end
            end
            if incomingSortMode ~= nil then data.OpportunitySortMode = incomingSortMode end
            data.OpportunityMessage = ''
        else
            lastProjectionData = copyProjectionFields(data)
        end
    elseif lastProjectionData ~= nil then
        for key, value in pairs(lastProjectionData) do
            if data[key] == nil then data[key] = value end
        end
    end
    return data
end

local function readEpochFile(path)
    if path == nil then return 0 end
    local file = io.open(path, 'r')
    if not file then return 0 end
    local raw = file:read('*a') or ''
    file:close()
    return tonumber(trim(raw):match('^(%d+)')) or 0
end

local function setVariable(name, value)
    SKIN:Bang('!SetVariable', name, tostring(value or ''))
end

local function setGroupVisible(group, visible)
    if visible then SKIN:Bang('!ShowMeterGroup', group)
    else SKIN:Bang('!HideMeterGroup', group) end
end

local function setMeterVisible(meter, visible)
    if visible then SKIN:Bang('!ShowMeter', meter)
    else SKIN:Bang('!HideMeter', meter) end
end

local function refreshPresentation()
    -- Explicit redraws must finish the same presentation chain as the normal
    -- one-second Rainmeter pass. Otherwise the intermediate StateReader/CardTweaks
    -- surface can flash before freshness and final polish run.
    for _, measure in ipairs({
        'MeasureHeaderLayout',
        'MeasureCardPresenter',
        'MeasureCardTweaks',
        'MeasureFreshnessGuard',
        'MeasureTravelStateWindowTweaks',
        'MeasureFinalCardPolish'
    }) do
        SKIN:Bang('!UpdateMeasure', measure)
    end
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

local function providerLabel(provider)
    if provider == 'prometheus' then return 'Prometheus' end
    if provider == 'yata' then return 'YATA' end
    return safeText(provider, '')
end

local function oldestSourceTimestamp(data)
    local projected = number(data.UIOldestMarketSourceTimestamp)
    if projected > 0 then return projected end
    local values = {}
    for _, key in ipairs({'UKSourceTimestamp','JPSourceTimestamp'}) do
        local value = number(data[key])
        if value > 0 then table.insert(values, value) end
    end
    if #values == 0 then return 0 end
    local oldest = values[1]
    for i = 2, #values do if values[i] < oldest then oldest = values[i] end end
    return oldest
end

local function updateHeartbeatText(data, now)
    local remaining = 0
    if nextPollAt ~= nil then remaining = math.max(0, nextPollAt - now) end
    local heartbeat = readEpochFile(heartbeatPath)
    if heartbeat <= 0 then
        setVariable('UpdatedText', string.format('Waiting for first update | next poll %ds', remaining))
        return
    end
    local provider = providerLabel(data.LiveProvider)
    local sourceTimestamp = oldestSourceTimestamp(data)
    local sourceText = ''
    if provider ~= '' and sourceTimestamp > 0 then
        sourceText = string.format(' | %s %ds old', provider, math.max(0, now - sourceTimestamp))
    elseif provider ~= '' then
        sourceText = ' | ' .. provider
    end
    local age = math.max(0, now - heartbeat)
    if age > pollInterval * 2 then
        setVariable('UpdatedText', string.format('UPDATE STALE - last %s (%ds ago)%s | retry %ds', os.date('%H:%M:%S', heartbeat), age, sourceText, remaining))
    else
        setVariable('UpdatedText', string.format('Updated %s%s | next poll %ds', os.date('%H:%M:%S', heartbeat), sourceText, remaining))
    end
end

local function copyTripBands(bands)
    return {
        short = bands and bands.short == true or false,
        medium = bands and bands.medium == true or false,
        long = bands and bands.long == true or false
    }
end

local function tripBandSignature(bands)
    return (bands.short and '1' or '0') .. (bands.medium and '1' or '0') .. (bands.long and '1' or '0')
end

local function parseTripBandCsv(value)
    local bands = { short=false, medium=false, long=false }
    for token in safeText(value, ''):gmatch('[^,]+') do
        local band = trim(token):lower()
        if bands[band] ~= nil then bands[band] = true end
    end
    return bands
end

local function projectedTripBands(data)
    if data.UISelectedTripBands ~= nil then return parseTripBandCsv(data.UISelectedTripBands) end
    return {
        short = number(data.UITripShortOn) == 1,
        medium = number(data.UITripMediumOn) == 1,
        long = number(data.UITripLongOn) == 1
    }
end

local function applyTripColors(bands)
    local active = '126,190,73,255'
    local inactive = '150,150,150,255'
    setVariable('TripShortColor', bands.short and active or inactive)
    setVariable('TripMediumColor', bands.medium and active or inactive)
    setVariable('TripLongColor', bands.long and active or inactive)
end

local function updateFilters(data, bands)
    setVariable('ItemFilterText', safeText(data.UIItemFilterText, 'All'))
    setVariable('CategoryFilterText', safeText(data.UICategoryFilterText, 'All'))
    applyTripColors(bands)
end

local function applySortColors(mode)
    local active = '126,190,73,255'
    local inactive = '150,150,150,255'
    setVariable('OpportunityRenderMode', mode)
    setVariable('SortUpcomingColor', mode == 'upcoming' and active or inactive)
    setVariable('SortGrossColor', mode == 'gross' and active or inactive)
    setVariable('SortProfitHourColor', mode == 'profit_per_hour' and active or inactive)
end

local function countryIdFromKey(key)
    return safeText(key, ''):match('^([a-z0-9_]+):') or ''
end

local function itemIdFromKey(key)
    local raw = safeText(key, ''):match(':([1-9][0-9]*)$')
    return tonumber(raw) or 0
end

local function fallbackItemName(key)
    local id = itemIdFromKey(key)
    if itemNameFallbacks[id] ~= nil then return itemNameFallbacks[id] end
    if id > 0 then return 'Item ' .. tostring(id) end
    return 'Unknown item'
end

local function resolvedItemName(key, projectedName)
    local name = safeText(projectedName, '')
    local placeholder = (name == '' or name == 'Unknown item' or name:match('^Item%s+%d+$') ~= nil)
    if placeholder then
        local fallback = fallbackItemName(key)
        if fallback ~= '' then return fallback end
    end
    return name
end

local function currentOpportunityRows(data)
    local count = math.max(0, math.min(maxCandidateRows, math.floor(number(data.OpportunityCount))))
    local rows = {}
    for i = 1, count do
        local prefix = 'Opportunity' .. i
        local key = safeText(data[prefix .. 'Key'], '')
        if key ~= '' then
            local countryId = countryIdFromKey(key)
            local band = safeText(data[prefix .. 'TripBand'], tripBandsByCountry[countryId] or ''):lower()
            local name = resolvedItemName(key, data[prefix .. 'Name'])
            table.insert(rows, {
                sourceIndex = i,
                key = key,
                name = name,
                country = safeText(data[prefix .. 'Country'], countryId),
                tripBand = band,
                gross = number(data[prefix .. 'GrossValue']),
                displayProfit = number(data[prefix .. 'MakeValue']),
                profitHour = number(data[prefix .. 'ProfitHourValue']),
                windowStart = number(data[prefix .. 'WindowStartAt']),
                timeKnown = number(data[prefix .. 'WindowStartAt']) > 0,
                profitKnown = number(data[prefix .. 'MarketValueValue']) > 0 and number(data[prefix .. 'PurchaseCostValue']) > 0,
                probability = number(data[prefix .. 'ProbabilityValue']),
                elapsed = number(data[prefix .. 'ElapsedSeconds']),
                grossFallback = moneyNumber(data[prefix .. 'GrossText']),
                profitHourFallback = moneyNumber(data[prefix .. 'ProfitHourText'])
            })
        end
    end
    for _, row in ipairs(rows) do
        if row.gross == 0 and row.grossFallback ~= 0 then row.gross = row.grossFallback end
        if row.profitHour == 0 and row.profitHourFallback ~= 0 then row.profitHour = row.profitHourFallback end
    end
    return rows
end

local function actionRank(probability)
    if probability > 0 then return 0 end
    if probability < 0 then return 1 end
    return 2
end

local function effectiveSortMode(rows, requestedMode)
    for _, row in ipairs(rows) do
        if row.timeKnown or row.profitKnown then return requestedMode end
    end
    return 'name'
end

local function sortOpportunityRows(rows, mode)
    table.sort(rows, function(a, b)
        if mode == 'name' then
            local an, bn = string.lower(a.name), string.lower(b.name)
            if an ~= bn then return an < bn end
            local ac, bc = string.lower(a.country), string.lower(b.country)
            if ac ~= bc then return ac < bc end
            return a.key < b.key
        elseif mode == 'gross' then
            if a.displayProfit ~= b.displayProfit then return a.displayProfit > b.displayProfit end
            if actionRank(a.probability) ~= actionRank(b.probability) then return actionRank(a.probability) < actionRank(b.probability) end
            if a.elapsed ~= b.elapsed then return a.elapsed < b.elapsed end
            return string.lower(a.name) < string.lower(b.name)
        elseif mode == 'profit_per_hour' then
            if a.profitHour ~= b.profitHour then return a.profitHour > b.profitHour end
            if a.gross ~= b.gross then return a.gross > b.gross end
            return string.lower(a.name) < string.lower(b.name)
        else
            if actionRank(a.probability) ~= actionRank(b.probability) then return actionRank(a.probability) < actionRank(b.probability) end
            if a.windowStart > 0 and b.windowStart > 0 and a.windowStart ~= b.windowStart then return a.windowStart < b.windowStart end
            if a.gross ~= b.gross then return a.gross > b.gross end
            return a.sourceIndex < b.sourceIndex
        end
    end)
end

local function locallyFilteredSortedProjection(data, mode, bands)
    local rows = currentOpportunityRows(data)
    local filtered = {}
    for _, row in ipairs(rows) do
        if bands[row.tripBand] == true then table.insert(filtered, row) end
    end
    local effectiveMode = effectiveSortMode(filtered, mode)
    sortOpportunityRows(filtered, effectiveMode)

    local out = copyTable(data)
    for displayIndex = 1, 8 do
        local targetPrefix = 'Opportunity' .. displayIndex
        for _, suffix in ipairs(opportunitySuffixes) do out[targetPrefix .. suffix] = '' end
    end

    local visibleCount = math.min(8, #filtered)
    for displayIndex = 1, visibleCount do
        local row = filtered[displayIndex]
        local sourcePrefix = 'Opportunity' .. row.sourceIndex
        local targetPrefix = 'Opportunity' .. displayIndex
        for _, suffix in ipairs(opportunitySuffixes) do
            out[targetPrefix .. suffix] = data[sourcePrefix .. suffix] or ''
        end
        out[targetPrefix .. 'Name'] = row.name
        out[targetPrefix .. 'TripBand'] = row.tripBand
    end

    out.OpportunityCandidateCount = #rows
    out.OpportunityFilteredCount = #filtered
    out.OpportunityCount = visibleCount
    out.OpportunitySortMode = mode
    out.OpportunitySortEffectiveMode = effectiveMode
    if visibleCount == 0 and #rows > 0 then out.OpportunityMessage = 'No opportunities in selected trip bands' end
    return out
end

local function formatDuration(seconds)
    local value = math.max(0, math.floor(number(seconds)))
    if value <= 0 then return '?' end
    local hours = math.floor(value / 3600)
    local minutes = math.floor((value % 3600) / 60)
    if hours > 0 then return string.format('%dh %dm', hours, minutes) end
    if minutes > 0 then return string.format('%dm', minutes) end
    return '<1m'
end

local function liveTravelRemaining(data, now)
    local arrivalAt = number(data.TravelArrivalAt)
    if arrivalAt > now then return arrivalAt - now end
    local projectedLeft = number(data.TravelTimeLeft)
    local projectedAt = number(data.TravelContextLastSuccessAt)
    if projectedLeft > 0 and projectedAt > 0 then
        return math.max(0, projectedLeft - math.max(0, now - projectedAt))
    end
    return math.max(0, projectedLeft)
end

local function travelHeaderText(data, now)
    local state = safeText(data.TravelState, 'home'):lower()
    local destination = safeText(data.TravelDestination, '')
    if destination == '' then destination = safeText(data.TravelDestinationCountryId, ''):gsub('_', ' ') end

    if state == 'home' then return 'In Torn' end
    if state == 'returning' then
        local remaining = liveTravelRemaining(data, now)
        if remaining <= 600 then return 'Landing in Torn: ' .. formatDuration(remaining) end
        return 'In Flight to Torn: ' .. formatDuration(remaining)
    end
    if state == 'traveling' then
        local remaining = liveTravelRemaining(data, now)
        if destination == '' then destination = 'destination' end
        if remaining <= 600 then return 'Landing in ' .. destination .. ': ' .. formatDuration(remaining) end
        return 'In Flight to ' .. destination .. ': ' .. formatDuration(remaining)
    end
    if state == 'abroad' or state == 'foreign' then
        if destination == '' then destination = 'destination' end
        return 'Abroad in ' .. destination
    end
    return 'Travel status unavailable'
end

local function updateTravelHeader(data, now)
    SKIN:Bang('!SetOption', 'MeterTitle', 'Text', travelHeaderText(data, now))
    SKIN:Bang('!SetOption', 'MeterTitle', 'ToolTipText', '')
end

local function travelSecondsForCountry(data, countryId)
    local key = nil
    if countryId == 'united_kingdom' then key = 'UKTravelSeconds'
    elseif countryId == 'japan' then key = 'JPTravelSeconds'
    else key = string.upper(countryId) .. 'TravelSeconds' end
    return number(data[key])
end

local function flagImagePath(countryId)
    local code = flagCodes[countryId]
    if code == nil or flagDir == nil then return '' end
    return flagDir .. code .. '@3x.png'
end

local function flagMaskImagePath(detailExpanded, graphExpanded)
    if flagMaskDir == nil then return '' end
    if detailExpanded and graphExpanded then return '' end
    if detailExpanded then return flagMaskDir .. 'flag-mask-bottom.png' end
    if graphExpanded then return flagMaskDir .. 'flag-mask-top.png' end
    return flagMaskDir .. 'flag-mask-both.png'
end

local function fileExists(path)
    if path == nil or path == '' then return false end
    local file = io.open(path, 'rb')
    if not file then return false end
    file:close()
    return true
end

local function itemImagePath(itemId)
    if itemImageDir == nil or itemId == nil or itemId <= 0 then return '' end
    return itemImageDir .. tostring(itemId) .. '.png'
end

local function applyItemImageForRow(data, index, key)
    local meter = 'MeterOpportunity' .. index .. 'ItemImage'
    local itemId = itemIdFromKey(key)
    if itemId <= 0 then
        SKIN:Bang('!SetOption', meter, 'ImageName', '')
        SKIN:Bang('!HideMeter', meter)
        return 0
    end

    local path = itemImagePath(itemId)
    SKIN:Bang('!SetOption', meter, 'ToolTipText', '')
    if fileExists(path) then
        SKIN:Bang('!SetOption', meter, 'ImageName', path)
        SKIN:Bang('!ShowMeter', meter)
        return 0
    end

    SKIN:Bang('!SetOption', meter, 'ImageName', '')
    SKIN:Bang('!HideMeter', meter)
    return itemId
end

local function requestItemImages(itemIds)
    local seen = {}
    local ordered = {}
    for _, itemId in ipairs(itemIds or {}) do
        if itemId > 0 and not seen[itemId] then
            seen[itemId] = true
            table.insert(ordered, itemId)
        end
    end
    local parts = {}
    for _, itemId in ipairs(ordered) do table.insert(parts, tostring(itemId)) end
    local signature = table.concat(parts, ',')
    if signature == '' then
        lastItemImageRequestSignature = ''
        return
    end

    local now = os.time()
    if signature == lastItemImageRequestSignature and (now - lastItemImageRequestAt) < 300 then return end
    lastItemImageRequestSignature = signature
    lastItemImageRequestAt = now
    setVariable('VisibleItemImageIds', signature)
    SKIN:Bang('!UpdateMeasure', 'MeasureItemImages')
    SKIN:Bang('!CommandMeasure', 'MeasureItemImages', 'Run')
end

local function applyFlagForRow(data, index, key)
    local countryId = countryIdFromKey(key)
    local prefix = 'Opportunity' .. index
    local countryName = safeText(data[prefix .. 'Country'], countryId)
    local travelSeconds = travelSecondsForCountry(data, countryId)
    local tooltip = countryName .. ' | travel ' .. formatDuration(travelSeconds)
    local image = flagImagePath(countryId)
    local meter = 'MeterOpportunity' .. index .. 'Flag'
    if lastFlagKeys[index] ~= key then
        lastFlagKeys[index] = key
        SKIN:Bang('!SetOption', meter, 'ImageName', image)
    end
    SKIN:Bang('!SetOption', meter, 'ToolTipText', tooltip)
end

local function safeFileKey(key)
    return safeText(key, ''):gsub('[^%w_-]', '_')
end

local function graphSpecPath(key)
    if generatedDir == nil then return '' end
    return generatedDir .. 'inline-graph-' .. safeFileKey(key) .. '.kv'
end

local function hideGraphHoverRegions()
    for i = 1, maxGraphHoverRegions do
        local name = 'MeterGraphHover' .. i
        SKIN:Bang('!HideMeter', name)
        SKIN:Bang('!SetOption', name, 'ToolTipText', '')
        SKIN:Bang('!SetOption', name, 'LeftMouseUpAction', '')
    end
end

local function updateGraphHoverRegions(spec, graphMeterName, row)
    hideGraphHoverRegions()
    if spec == nil or graphMeterName == nil or graphMeterName == '' then return end
    local graphMeter = SKIN:GetMeter(graphMeterName)
    if graphMeter == nil then return end

    local baseX = number(graphMeter:GetX())
    local baseY = number(graphMeter:GetY())
    local count = math.max(0, math.min(maxGraphHoverRegions, math.floor(number(spec.HoverCount))))
    for i = 1, count do
        local prefix = 'Hover' .. i
        local x = number(spec[prefix .. 'X'])
        local y = number(spec[prefix .. 'Y'])
        local w = math.max(1, number(spec[prefix .. 'W']))
        local h = math.max(1, number(spec[prefix .. 'H']))
        local tooltip = safeText(spec[prefix .. 'Text'], '')
        if tooltip ~= '' then
            local name = 'MeterGraphHover' .. i
            SKIN:Bang('!SetOption', name, 'X', tostring(baseX + x))
            SKIN:Bang('!SetOption', name, 'Y', tostring(baseY + y))
            SKIN:Bang('!SetOption', name, 'W', tostring(w))
            SKIN:Bang('!SetOption', name, 'H', tostring(h))
            SKIN:Bang('!SetOption', name, 'Shape', 'Rectangle 0,0,' .. tostring(w) .. ',' .. tostring(h) .. ' | Fill Color 0,0,0,1 | StrokeWidth 0')
            SKIN:Bang('!SetOption', name, 'ToolTipText', tooltip)
            SKIN:Bang('!SetOption', name, 'LeftMouseUpAction', '[!CommandMeasure MeasureState "ToggleCardExpanded(' .. tostring(row) .. ')"]')
            SKIN:Bang('!ShowMeter', name)
        end
    end
end

local function graphImagePath(key)
    if generatedDir == nil then return '' end
    return generatedDir .. 'inline-graph-' .. safeFileKey(key) .. '.png'
end

local function readGraphSpec(key)
    local path = graphSpecPath(key)
    if path == '' then return nil end
    local values = readKv(path)
    if safeText(values.MarketKey, '') ~= key then return nil end
    return values
end

local function setGraphButtonState(name, expanded)
    local fill=expanded and '126,190,73,255' or '0,0,0,1'
    local icon=expanded and '38,38,38,255' or '190,190,190,255'
    SKIN:Bang('!SetOption', name, 'GraphExpanded', expanded and '1' or '0')
    SKIN:Bang('!SetOption', name, 'Shape', 'Rectangle 0,0,24,23 | Fill Color '..fill..' | StrokeWidth 0')
    SKIN:Bang('!SetOption', name, 'Shape2', 'Line 7,16,7,7 | StrokeWidth 1 | Stroke Color '..icon)
    SKIN:Bang('!SetOption', name, 'Shape3', 'Line 7,16,17,16 | StrokeWidth 1 | Stroke Color '..icon)
    SKIN:Bang('!SetOption', name, 'Shape4', 'Line 8,14,11,11 | StrokeWidth 1 | Stroke Color '..icon)
    SKIN:Bang('!SetOption', name, 'Shape5', 'Line 11,11,13,13 | StrokeWidth 1 | Stroke Color '..icon)
    SKIN:Bang('!SetOption', name, 'Shape6', 'Line 13,13,17,8 | StrokeWidth 1 | Stroke Color '..icon)
end

local function setDetailButtonState(name, expanded)
    SKIN:Bang('!SetOption', name, 'Text', '$')
    SKIN:Bang('!SetOption', name, 'FontColor', expanded and '38,38,38,255' or '190,190,190,255')
    SKIN:Bang('!SetOption', name, 'SolidColor', expanded and '126,190,73,255' or '0,0,0,1')
end

local function collapseInlineGraph()
    hideGraphHoverRegions()
    expandedKey = ''
    expandedRow = 0
    lastGraphSignature = ''
    lastLayoutSignature = ''
    for i = 1, 8 do
        local graphMeter = 'MeterOpportunity' .. i .. 'InlineGraph'
        SKIN:Bang('!HideMeter', graphMeter)
        SKIN:Bang('!SetOption', graphMeter, 'ImageName', '')
        setGraphButtonState('MeterOpportunity' .. i .. 'Graph', false)
    end
end

local function detailTaxRate(data, index)
    if index == nil or index <= 0 then return 0 end
    return math.max(0, math.min(5, math.floor(number(data['Opportunity' .. index .. 'MarketFeePercent']) + 0.5)))
end

local function detailExtraForRow(data, index)
    if index == nil or index <= 0 then return 0 end
    -- Two fixed economics rows: Tax is conditional at lower-left, while
    -- round-trip flight $/hr is always rendered at lower-right.
    return detailExtra
end

local function collapseCardDetails()
    expandedDetailKey = ''
    expandedDetailRow = 0
    lastLayoutSignature = ''
    for i = 1, 8 do
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachLabel')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'Gross')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachGrossValue')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachNet')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachNetValue')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachTax')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachTaxValue')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachProfitHour')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailEachPriceValue')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalLabel')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotal')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalGrossValue')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalNet')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalNetValue')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalTax')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalTaxValue')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalProfitHour')
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'DetailTotalPriceValue')
        setDetailButtonState('MeterOpportunity' .. i .. 'DetailToggle', false)
        SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'DetailToggle', 'ToolTipText', '')
    end
end

local function syncExpandedRows(data, count)
    if expandedKey == '' then
        expandedRow = 0
    else
        local found = 0
        for i = 1, count do
            if safeText(data['Opportunity' .. i .. 'Key'], '') == expandedKey then found = i break end
        end
        if found == 0 then collapseInlineGraph() else expandedRow = found end
    end

    if expandedDetailKey == '' then
        expandedDetailRow = 0
    else
        local found = 0
        for i = 1, count do
            if safeText(data['Opportunity' .. i .. 'Key'], '') == expandedDetailKey then found = i break end
        end
        if found == 0 then collapseCardDetails() else expandedDetailRow = found end
    end
end

local function layoutRows(data, count)
    syncExpandedRows(data, count)

    local activeDetailExtra = detailExtraForRow(data, expandedDetailRow)
    local activeDetailHasTax = expandedDetailRow > 0 and detailTaxRate(data, expandedDetailRow) > 0

    -- ShowMeterGroup runs before layout and can resurrect hidden child meters.
    -- Reassert the compact-card visibility contract on every pass even when Y/H
    -- geometry is unchanged.
    for i = 1, 8 do
        local p = 'MeterOpportunity' .. i
        if i == expandedDetailRow then
            SKIN:Bang('!ShowMeter', p .. 'DetailEachLabel')
            SKIN:Bang('!ShowMeter', p .. 'Gross')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachGrossValue')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachNet')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachNetValue')
            if activeDetailHasTax then
                SKIN:Bang('!ShowMeter', p .. 'DetailEachTax')
                SKIN:Bang('!ShowMeter', p .. 'DetailEachTaxValue')
            else
                SKIN:Bang('!HideMeter', p .. 'DetailEachTax')
                SKIN:Bang('!HideMeter', p .. 'DetailEachTaxValue')
            end
            SKIN:Bang('!ShowMeter', p .. 'DetailEachProfitHour')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachPriceValue')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalLabel')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotal')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalGrossValue')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalNet')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalNetValue')
            if activeDetailHasTax then
                SKIN:Bang('!ShowMeter', p .. 'DetailTotalTax')
                SKIN:Bang('!ShowMeter', p .. 'DetailTotalTaxValue')
            else
                SKIN:Bang('!HideMeter', p .. 'DetailTotalTax')
                SKIN:Bang('!HideMeter', p .. 'DetailTotalTaxValue')
            end
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalProfitHour')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalPriceValue')
        else
            SKIN:Bang('!HideMeter', p .. 'DetailEachLabel')
            SKIN:Bang('!HideMeter', p .. 'Gross')
            SKIN:Bang('!HideMeter', p .. 'DetailEachGrossValue')
            SKIN:Bang('!HideMeter', p .. 'DetailEachNet')
            SKIN:Bang('!HideMeter', p .. 'DetailEachNetValue')
            SKIN:Bang('!HideMeter', p .. 'DetailEachTax')
            SKIN:Bang('!HideMeter', p .. 'DetailEachTaxValue')
            SKIN:Bang('!HideMeter', p .. 'DetailEachProfitHour')
            SKIN:Bang('!HideMeter', p .. 'DetailEachPriceValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalLabel')
            SKIN:Bang('!HideMeter', p .. 'DetailTotal')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalGrossValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalNet')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalNetValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalTax')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalTaxValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalProfitHour')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalPriceValue')
        end
        local maskImage = ''
        if i <= count then maskImage = flagMaskImagePath(i == expandedDetailRow, i == expandedRow) end
        if maskImage == '' then
            SKIN:Bang('!SetOption', p .. 'FlagMask', 'ImageName', '')
            SKIN:Bang('!HideMeter', p .. 'FlagMask')
        else
            SKIN:Bang('!SetOption', p .. 'FlagMask', 'ImageName', maskImage)
            SKIN:Bang('!ShowMeter', p .. 'FlagMask')
        end
        SKIN:Bang('!HideMeter', p .. 'Name')
        SKIN:Bang('!HideMeter', p .. 'Window')
        SKIN:Bang('!HideMeter', p .. 'Chance')
    end

    local signature = tostring(count) .. ':' .. tostring(expandedRow) .. ':' .. tostring(expandedDetailRow) .. ':' .. tostring(activeDetailExtra)
    if signature == lastLayoutSignature then return end
    lastLayoutSignature = signature

    for i = 1, 8 do
        local p = 'MeterOpportunity' .. i
        local extraBefore = 0
        if expandedDetailRow > 0 and i > expandedDetailRow then extraBefore = extraBefore + activeDetailExtra end
        if expandedRow > 0 and i > expandedRow then extraBefore = extraBefore + graphExtra end

        local y = 120 + ((i-1) * rowStride) + extraBefore
        local detailExpanded = (i == expandedDetailRow)
        local graphExpanded = (i == expandedRow)
        local bodyOffset = detailExpanded and activeDetailExtra or 0
        local cardHeight = collapsedCardHeight + bodyOffset + (graphExpanded and graphExtra or 0)

        SKIN:Bang('!SetOption', p .. 'Card', 'Y', tostring(y))
        SKIN:Bang('!SetOption', p .. 'Card', 'H', tostring(cardHeight))
        SKIN:Bang('!SetOption', p .. 'Card', 'Shape', 'Rectangle 0,0,536,' .. cardHeight .. ',5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#')
        SKIN:Bang('!SetOption', p .. 'CardBorder', 'Y', tostring(y))
        SKIN:Bang('!SetOption', p .. 'CardBorder', 'H', tostring(cardHeight))
        SKIN:Bang('!SetOption', p .. 'CardBorder', 'Shape', 'Rectangle 0,0,536,' .. cardHeight .. ',5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#')
        SKIN:Bang('!SetOption', p .. 'Card', 'Shape2', 'Line 510,' .. bodyOffset .. ',510,' .. (bodyOffset+50) .. ' | StrokeWidth 1 | Stroke Color #Border#')
        SKIN:Bang('!SetOption', p .. 'Card', 'Shape3', 'Line 510,' .. (bodyOffset+25) .. ',536,' .. (bodyOffset+25) .. ' | StrokeWidth 1 | Stroke Color #Border#')
        if detailExpanded then
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape4', 'Line 268,0,268,' .. bodyOffset .. ' | StrokeWidth 1 | Stroke Color #Border#')
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape5', 'Line 0,' .. bodyOffset .. ',536,' .. bodyOffset .. ' | StrokeWidth 1 | Stroke Color #Border#')
            local separatorBottom = math.max(1, bodyOffset-1)
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape6', 'Line 150,1,150,' .. separatorBottom .. ' | StrokeWidth 1 | Stroke Color 64,64,64,150')
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape7', 'Line 418,1,418,' .. separatorBottom .. ' | StrokeWidth 1 | Stroke Color 64,64,64,150')
        else
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape4', 'Line 0,0,0,0 | StrokeWidth 0')
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape5', 'Line 0,0,0,0 | StrokeWidth 0')
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape6', 'Line 0,0,0,0 | StrokeWidth 0')
            SKIN:Bang('!SetOption', p .. 'Card', 'Shape7', 'Line 0,0,0,0 | StrokeWidth 0')
        end

        local detailLabelHeight = detailExpanded and math.max(16, bodyOffset-2) or 16
        local detailLabelCenterY = y + (detailExpanded and math.floor(bodyOffset/2) or 9)
        SKIN:Bang('!SetOption', p .. 'DetailEachLabel', 'Y', tostring(detailLabelCenterY))
        SKIN:Bang('!SetOption', p .. 'DetailEachLabel', 'H', tostring(detailLabelHeight))
        SKIN:Bang('!SetOption', p .. 'Gross', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailEachGrossValue', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailEachNet', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailEachNetValue', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailEachTax', 'Y', tostring(y+25))
        SKIN:Bang('!SetOption', p .. 'DetailEachTaxValue', 'Y', tostring(y+25))
        SKIN:Bang('!SetOption', p .. 'DetailEachProfitHour', 'Y', tostring(y+25))
        SKIN:Bang('!SetOption', p .. 'DetailEachPriceValue', 'Y', tostring(y+25))
        SKIN:Bang('!SetOption', p .. 'DetailTotalLabel', 'Y', tostring(detailLabelCenterY))
        SKIN:Bang('!SetOption', p .. 'DetailTotalLabel', 'H', tostring(detailLabelHeight))
        SKIN:Bang('!SetOption', p .. 'DetailTotal', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailTotalGrossValue', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailTotalNet', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailTotalNetValue', 'Y', tostring(y+8))
        SKIN:Bang('!SetOption', p .. 'DetailTotalTax', 'Y', tostring(y+25))
        SKIN:Bang('!SetOption', p .. 'DetailTotalTaxValue', 'Y', tostring(y+25))
        SKIN:Bang('!SetOption', p .. 'DetailTotalProfitHour', 'Y', tostring(y+25))
        SKIN:Bang('!SetOption', p .. 'DetailTotalPriceValue', 'Y', tostring(y+25))
        if detailExpanded then
            SKIN:Bang('!ShowMeter', p .. 'DetailEachLabel')
            SKIN:Bang('!ShowMeter', p .. 'Gross')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachGrossValue')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachNet')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachNetValue')
            if activeDetailHasTax then
                SKIN:Bang('!ShowMeter', p .. 'DetailEachTax')
                SKIN:Bang('!ShowMeter', p .. 'DetailEachTaxValue')
            else
                SKIN:Bang('!HideMeter', p .. 'DetailEachTax')
                SKIN:Bang('!HideMeter', p .. 'DetailEachTaxValue')
            end
            SKIN:Bang('!ShowMeter', p .. 'DetailEachProfitHour')
            SKIN:Bang('!ShowMeter', p .. 'DetailEachPriceValue')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalLabel')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotal')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalGrossValue')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalNet')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalNetValue')
            if activeDetailHasTax then
                SKIN:Bang('!ShowMeter', p .. 'DetailTotalTax')
                SKIN:Bang('!ShowMeter', p .. 'DetailTotalTaxValue')
            else
                SKIN:Bang('!HideMeter', p .. 'DetailTotalTax')
                SKIN:Bang('!HideMeter', p .. 'DetailTotalTaxValue')
            end
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalProfitHour')
            SKIN:Bang('!ShowMeter', p .. 'DetailTotalPriceValue')
        else
            SKIN:Bang('!HideMeter', p .. 'DetailEachLabel')
            SKIN:Bang('!HideMeter', p .. 'Gross')
            SKIN:Bang('!HideMeter', p .. 'DetailEachGrossValue')
            SKIN:Bang('!HideMeter', p .. 'DetailEachNet')
            SKIN:Bang('!HideMeter', p .. 'DetailEachNetValue')
            SKIN:Bang('!HideMeter', p .. 'DetailEachTax')
            SKIN:Bang('!HideMeter', p .. 'DetailEachTaxValue')
            SKIN:Bang('!HideMeter', p .. 'DetailEachProfitHour')
            SKIN:Bang('!HideMeter', p .. 'DetailEachPriceValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalLabel')
            SKIN:Bang('!HideMeter', p .. 'DetailTotal')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalGrossValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalNet')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalNetValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalTax')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalTaxValue')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalProfitHour')
            SKIN:Bang('!HideMeter', p .. 'DetailTotalPriceValue')
        end

        SKIN:Bang('!SetOption', p .. 'Flag', 'X', '8')
        SKIN:Bang('!SetOption', p .. 'Flag', 'Y', tostring(y+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'Flag', 'W', '67')
        SKIN:Bang('!SetOption', p .. 'Flag', 'H', '50')
        SKIN:Bang('!SetOption', p .. 'FlagMask', 'X', '8')
        SKIN:Bang('!SetOption', p .. 'FlagMask', 'Y', tostring(y+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'FlagMask', 'W', '67')
        SKIN:Bang('!SetOption', p .. 'FlagMask', 'H', '50')
        SKIN:Bang('!SetOption', p .. 'ItemImage', 'X', '77')
        SKIN:Bang('!SetOption', p .. 'ItemImage', 'Y', tostring(y+3+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'ItemImage', 'W', '44')
        SKIN:Bang('!SetOption', p .. 'ItemImage', 'H', '44')
        SKIN:Bang('!SetOption', p .. 'Name', 'Y', tostring(y+6+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'Price', 'Y', tostring(y+6+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'Take', 'Y', tostring(y+6+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'Make', 'Y', tostring(y+25+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'DetailToggle', 'Y', tostring(y+13+bodyOffset))
        setDetailButtonState(p .. 'DetailToggle', detailExpanded)
        SKIN:Bang('!SetOption', p .. 'DetailToggle', 'ToolTipText', '')

        SKIN:Bang('!SetOption', p .. 'Window', 'Y', tostring(y+34+bodyOffset))
        SKIN:Bang('!HideMeter', p .. 'Window')
        SKIN:Bang('!SetOption', p .. 'Leave', 'Y', tostring(y+34+bodyOffset))
        SKIN:Bang('!SetOption', p .. 'Chance', 'Y', tostring(y+34+bodyOffset))
        SKIN:Bang('!HideMeter', p .. 'Chance')

        SKIN:Bang('!SetOption', p .. 'Graph', 'Y', tostring(y+26+bodyOffset))
        setGraphButtonState(p .. 'Graph', graphExpanded)
        SKIN:Bang('!SetOption', p .. 'InlineGraph', 'Y', tostring(y+53+bodyOffset))
        if not graphExpanded then SKIN:Bang('!HideMeter', p .. 'InlineGraph') end
    end

    local panelHeight = 192
    if count > 0 then
        panelHeight = 120 + (count * rowStride) + activeDetailExtra + ((expandedRow > 0) and graphExtra or 0) + 8 + footerExtra
    end
    setVariable('PanelHeight', panelHeight)
end

local function safeLeaveText(data, prefix)
    local leave = safeText(data[prefix .. 'LeaveText'], '')
    local probability = number(data[prefix .. 'ProbabilityValue'])
    if leave == 'LEAVE NOW' then
        if probability < 0 then return 'WAIT DATA' end
        if probability <= 0 then return 'NO HIT' end
    end
    return leave
end

local function displayChanceText(data, prefix)
    local chance = safeText(data[prefix .. 'ChanceText'], '')
    if chance ~= '' then return chance end
    local raw = safeText(data[prefix .. 'ProbabilityValue'], '')
    if raw == '' then return '' end
    local p = tonumber(raw)
    if p == nil then return '' end
    if p < 0 then return 'LEARNING' end
    return string.format('%.0f%%', p * 100)
end

local function cardTitle(data, prefix, key)
    local name = resolvedItemName(key, data[prefix .. 'Name'])
    local country = safeText(data[prefix .. 'Country'], '')
    if country ~= '' then return name .. ' - ' .. country end
    return name
end

local function updateExpandedGraph()
    if expandedRow <= 0 or expandedKey == '' then return end
    local spec = readGraphSpec(expandedKey)
    local signature = expandedKey .. ':' .. safeText(spec and spec.UpdatedAt or '', '')
    local meter = 'MeterOpportunity' .. expandedRow .. 'InlineGraph'
    if spec ~= nil and safeText(spec.UpdatedAt, '') ~= '' then
        if signature ~= lastGraphSignature then
            lastGraphSignature = signature
            SKIN:Bang('!SetOption', meter, 'ImageName', graphImagePath(expandedKey))
        end
        SKIN:Bang('!ShowMeter', meter)
        updateGraphHoverRegions(spec, meter, expandedRow)
    else
        SKIN:Bang('!HideMeter', meter)
        hideGraphHoverRegions()
    end
end

local function updateOpportunities(data)
    local count = math.max(0, math.min(8, math.floor(number(data.OpportunityCount))))
    setVariable('OpportunityMessageText', safeText(data.OpportunityMessage, 'No current opportunities'))
    setMeterVisible('MeterOpportunityMessage', count == 0)
    local missingItemImages = {}

    for i = 1, 8 do
        local prefix = 'Opportunity' .. i
        local visible = i <= count
        setGroupVisible('OpportunityRow' .. i, visible)
        if visible then
            local key = safeText(data[prefix .. 'Key'], '')
            local gross = safeText(data[prefix .. 'GrossText'], '')
            local price = safeText(data[prefix .. 'PriceText'], '')
            local mv = safeText(data[prefix .. 'MarketValueText'], '')
            local combinedPrice = ''
            if price ~= '' then combinedPrice = 'BUY ' .. price .. '/ea' end
            if mv ~= '' then
                if combinedPrice ~= '' then combinedPrice = combinedPrice .. ' | ' end
                combinedPrice = combinedPrice .. 'MV ' .. mv
            end

            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Name', 'Text', cardTitle(data, prefix, key))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Name', 'ToolTipText', '')
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'Text', gross)
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'FontColor', safeText(data[prefix .. 'PriceColor'], '150,150,150,255'))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'ToolTipText', '')
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Window', 'Text', safeText(data[prefix .. 'WindowText'], ''))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Leave', 'Text', safeLeaveText(data, prefix))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Chance', 'Text', displayChanceText(data, prefix))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Price', 'Text', combinedPrice)
            applyFlagForRow(data, i, key)
            local missingItemId = applyItemImageForRow(data, i, key)
            if missingItemId > 0 then table.insert(missingItemImages, missingItemId) end
        end
    end
    requestItemImages(missingItemImages)

    layoutRows(data, count)
    updateExpandedGraph()
end

local function deferPolling(seconds)
    local now = os.time()
    local target = now + (seconds or 5)
    if nextPollAt == nil or nextPollAt < target then nextPollAt = target end
end

local function requestInlineGraph(key)
    if key == '' then return end
    lastInlineRenderRequestAt = os.time()
    setVariable('InlineGraphMarketKey', key)
    SKIN:Bang('!UpdateMeasure', 'MeasureInlineGraph')
    SKIN:Bang('!CommandMeasure', 'MeasureInlineGraph', 'Run')
end

local function currentRenderMode(data)
    local mode = pendingSortMode or lastSortMode or safeText(data and data.OpportunitySortMode or '', 'upcoming'):lower()
    if mode ~= 'upcoming' and mode ~= 'gross' and mode ~= 'profit_per_hour' then mode = 'upcoming' end
    return mode
end

function Initialize()
    local configured = SELF:GetOption('StateFile', '#@#Generated\\state.kv')
    local heartbeatConfigured = SELF:GetOption('HeartbeatFile', '#@#Generated\\last-update.txt')
    local configuredPoll = tonumber(SELF:GetOption('PollInterval', '60')) or 60
    local configuredFailureRetry = tonumber(SELF:GetOption('FailureRetryInterval', '15')) or 15
    if configuredPoll < 15 then configuredPoll = 15 end
    if configuredFailureRetry < 5 then configuredFailureRetry = 5 end
    if configuredFailureRetry > configuredPoll then configuredFailureRetry = configuredPoll end

    statePath = SKIN:MakePathAbsolute(configured)
    heartbeatPath = SKIN:MakePathAbsolute(heartbeatConfigured)
    generatedDir = statePath:match('^(.*[\\/])') or ''
    flagDir = SKIN:ReplaceVariables('#@#Images\\Flags\\')
    flagMaskDir = SKIN:ReplaceVariables('#@#Images\\UI\\')
    itemImageDir = generatedDir .. 'Items\\'
    pollInterval = math.floor(configuredPoll)
    failureRetryInterval = math.floor(configuredFailureRetry)
    nextPollAt = os.time() + pollInterval

    local initial = readState()
    activeTripBands = projectedTripBands(initial)
    if initial.OpportunityCount ~= nil then
        lastProjectionData = copyProjectionFields(initial)
        lastRenderData = stabilizeProjection(initial)
    end
end

function OpenFilter(filterName)
    deferPolling(5)
    setVariable('FilterRequest', filterName)
    SKIN:Bang('!UpdateMeasure', 'MeasureFilterPopup')
    SKIN:Bang('!CommandMeasure', 'MeasureFilterPopup', 'Run')
end

function ToggleTripBand(band)
    band = safeText(band, ''):lower()
    if band ~= 'short' and band ~= 'medium' and band ~= 'long' then return end

    local nextBands = copyTripBands(activeTripBands)
    nextBands[band] = not nextBands[band]
    pendingTripBands = copyTripBands(nextBands)
    activeTripBands = copyTripBands(nextBands)
    collapseInlineGraph()
    applyTripColors(activeTripBands)
    deferPolling(2)

    if lastRenderData ~= nil then
        local immediate = locallyFilteredSortedProjection(lastRenderData, currentRenderMode(lastRenderData), activeTripBands)
        lastDisplayedData = immediate
        updateOpportunities(immediate)
    end

    setVariable('PreferenceAction', 'ToggleTripBand')
    setVariable('PreferenceValue', band)
    SKIN:Bang('!UpdateMeasure', 'MeasurePreferenceAction')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
    refreshPresentation()
end

function ResetFilters()
    deferPolling(5)
    collapseInlineGraph()
    activeTripBands = { short=true, medium=true, long=true }
    pendingTripBands = copyTripBands(activeTripBands)
    applyTripColors(activeTripBands)
    setVariable('PreferenceAction', 'ResetFilters')
    setVariable('PreferenceValue', '')
    SKIN:Bang('!UpdateMeasure', 'MeasurePreferenceAction')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function SetSortMode(mode)
    mode = safeText(mode, 'upcoming'):lower()
    if mode ~= 'upcoming' and mode ~= 'gross' and mode ~= 'profit_per_hour' then mode = 'upcoming' end
    if lastSortMode ~= mode then collapseInlineGraph() end
    deferPolling(2)
    pendingSortMode = mode
    lastSortMode = mode
    applySortColors(mode)

    if lastRenderData ~= nil then
        local immediate = locallyFilteredSortedProjection(lastRenderData, mode, activeTripBands)
        lastDisplayedData = immediate
        updateOpportunities(immediate)
    end

    setVariable('PreferenceAction', 'SetSortMode')
    setVariable('PreferenceValue', mode)
    SKIN:Bang('!UpdateMeasure', 'MeasurePreferenceAction')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
    refreshPresentation()
end

function ToggleCardExpanded(index)
    if lastDisplayedData == nil then return end
    local row = math.floor(number(index))
    if row < 1 or row > 8 then return end
    local key = safeText(lastDisplayedData['Opportunity' .. row .. 'Key'], '')
    if key == '' then return end

    local bothExpanded = (expandedDetailKey == key and expandedKey == key)
    if bothExpanded then
        collapseCardDetails()
        collapseInlineGraph()
    else
        collapseCardDetails()
        collapseInlineGraph()
        expandedDetailKey = key
        expandedDetailRow = row
        expandedKey = key
        expandedRow = row
        requestInlineGraph(key)
    end
    updateOpportunities(lastDisplayedData)
    refreshPresentation()
end

function ToggleCardDetails(index)
    if lastDisplayedData == nil then return end
    local row = math.floor(number(index))
    if row < 1 or row > 8 then return end
    local key = safeText(lastDisplayedData['Opportunity' .. row .. 'Key'], '')
    if key == '' then return end

    if expandedDetailKey == key then
        collapseCardDetails()
    else
        collapseCardDetails()
        expandedDetailKey = key
        expandedDetailRow = row
    end
    updateOpportunities(lastDisplayedData)
    refreshPresentation()
end

function ToggleInlineGraph(index)
    if lastDisplayedData == nil then return end
    local row = math.floor(number(index))
    if row < 1 or row > 8 then return end
    local key = safeText(lastDisplayedData['Opportunity' .. row .. 'Key'], '')
    if key == '' then return end

    if expandedKey == key then
        collapseInlineGraph()
    else
        collapseInlineGraph()
        expandedKey = key
        expandedRow = row
        requestInlineGraph(key)
    end
    updateOpportunities(lastDisplayedData)
    refreshPresentation()
end

function Update()
    local now = os.time()
    local baseData = stabilizeProjection(readState())
    lastRenderData = baseData

    local projectedMode = safeText(baseData.OpportunitySortMode, 'upcoming'):lower()
    if projectedMode ~= 'upcoming' and projectedMode ~= 'gross' and projectedMode ~= 'profit_per_hour' then projectedMode = 'upcoming' end
    if pendingSortMode ~= nil and projectedMode == pendingSortMode then pendingSortMode = nil end
    local renderMode = pendingSortMode or projectedMode
    if lastSortMode == nil then lastSortMode = renderMode end
    if renderMode ~= lastSortMode then
        collapseInlineGraph()
        lastSortMode = renderMode
    end

    local projectedBands = projectedTripBands(baseData)
    if pendingTripBands ~= nil and tripBandSignature(projectedBands) == tripBandSignature(pendingTripBands) then pendingTripBands = nil end
    if pendingTripBands ~= nil then activeTripBands = copyTripBands(pendingTripBands)
    else activeTripBands = copyTripBands(projectedBands) end

    local data = locallyFilteredSortedProjection(baseData, renderMode, activeTripBands)
    lastDisplayedData = data

    local sourceStatus = safeText(data.UpdatedText, '')
    local sourceFailed = sourceStatus:find('failed', 1, true) ~= nil
    if nextPollAt == nil then nextPollAt = now + pollInterval end
    if sourceFailed and not failureRetryArmed then
        local retryAt = now + failureRetryInterval
        if retryAt < nextPollAt then nextPollAt = retryAt end
        failureRetryArmed = true
    elseif not sourceFailed then
        failureRetryArmed = false
    end

    if now >= nextPollAt then
        nextPollAt = now + pollInterval
        SKIN:Bang('!CommandMeasure', 'MeasureUpdate', 'Run')
    end

    if expandedKey ~= '' and (now - lastInlineRenderRequestAt) >= 60 then requestInlineGraph(expandedKey) end

    updateTravelHeader(data, now)
    updateHeartbeatText(data, now)
    updateFilters(data, activeTripBands)
    applySortColors(renderMode)
    updateOpportunities(data)
    return 0
end
