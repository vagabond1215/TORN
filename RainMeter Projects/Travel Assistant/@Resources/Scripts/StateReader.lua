local statePath = nil
local heartbeatPath = nil
local generatedDir = nil
local flagDir = nil
local pollInterval = 60
local failureRetryInterval = 15
local failureRetryArmed = false
local nextPollAt = nil
local lastProjectionData = nil
local lastRenderData = nil
local lastDisplayedData = nil
local pendingSortMode = nil
local lastSortMode = nil
local expandedKey = ''
local expandedRow = 0
local lastInlineRenderRequestAt = 0
local lastLayoutSignature = ''
local lastGraphSignature = ''
local lastFlagKeys = {}

local collapsedCardHeight = 50
local rowStride = 54
local graphExtra = 108
local expandedCardHeight = collapsedCardHeight + graphExtra

local opportunitySuffixes = {
    'Key','Name','Country','CountryCode','WindowText','LeaveText','ChanceText','TimeText',
    'GrossText','QuantityText','ProfitHourText','PriceText','MarketValueText','PriceColor',
    'Tooltip','GrossValue','ProfitHourValue','WindowStartAt','ProbabilityValue','ElapsedSeconds'
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
    return value:gsub('[\r\n]', ' ')
end

local function moneyNumber(v)
    local text = safeText(v, ''):gsub(',', ''):gsub('%$', ''):gsub('/hr', '')
    local sign = 1
    if text:sub(1,1) == '-' then sign = -1 end
    text = text:gsub('[^%d%.]', '')
    return sign * (tonumber(text) or 0)
end

local function readKv(path)
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
    return tonumber(trim(raw)) or 0
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

local function updateFilters(data)
    local itemText = safeText(data.UIItemFilterText, 'All')
    local categoryText = safeText(data.UICategoryFilterText, 'All')
    setVariable('ItemFilterText', itemText)
    setVariable('CategoryFilterText', categoryText)
    setVariable('TripShortColor', number(data.UITripShortOn) == 1 and '82,174,255,255' or '145,152,164,255')
    setVariable('TripMediumColor', number(data.UITripMediumOn) == 1 and '82,174,255,255' or '145,152,164,255')
    setVariable('TripLongColor', number(data.UITripLongOn) == 1 and '82,174,255,255' or '145,152,164,255')
end

local function applySortColors(mode)
    local active = '82,174,255,255'
    local inactive = '145,152,164,255'
    setVariable('SortNameColor', mode == 'name' and active or inactive)
    setVariable('SortUpcomingColor', mode == 'upcoming' and active or inactive)
    setVariable('SortGrossColor', mode == 'gross' and active or inactive)
    setVariable('SortProfitHourColor', mode == 'profit_per_hour' and active or inactive)
end

local function currentOpportunityRows(data)
    local count = math.max(0, math.min(8, math.floor(number(data.OpportunityCount))))
    local rows = {}
    for i = 1, count do
        local prefix = 'Opportunity' .. i
        table.insert(rows, {
            sourceIndex = i,
            key = safeText(data[prefix .. 'Key'], ''),
            name = safeText(data[prefix .. 'Name'], ''),
            country = safeText(data[prefix .. 'Country'], ''),
            gross = number(data[prefix .. 'GrossValue']),
            profitHour = number(data[prefix .. 'ProfitHourValue']),
            windowStart = number(data[prefix .. 'WindowStartAt']),
            probability = number(data[prefix .. 'ProbabilityValue']),
            elapsed = number(data[prefix .. 'ElapsedSeconds']),
            grossFallback = moneyNumber(data[prefix .. 'GrossText']),
            profitHourFallback = moneyNumber(data[prefix .. 'ProfitHourText'])
        })
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

local function sortOpportunityRows(rows, mode)
    table.sort(rows, function(a, b)
        if mode == 'name' then
            local an, bn = string.lower(a.name), string.lower(b.name)
            if an ~= bn then return an < bn end
            local ac, bc = string.lower(a.country), string.lower(b.country)
            if ac ~= bc then return ac < bc end
            return a.key < b.key
        elseif mode == 'gross' then
            if a.gross ~= b.gross then return a.gross > b.gross end
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

local function locallySortedProjection(data, mode)
    local rows = currentOpportunityRows(data)
    if #rows <= 1 then
        local out = copyTable(data)
        out.OpportunitySortMode = mode
        return out
    end
    sortOpportunityRows(rows, mode)
    local out = copyTable(data)
    for displayIndex, row in ipairs(rows) do
        local sourcePrefix = 'Opportunity' .. row.sourceIndex
        local targetPrefix = 'Opportunity' .. displayIndex
        for _, suffix in ipairs(opportunitySuffixes) do
            out[targetPrefix .. suffix] = data[sourcePrefix .. suffix] or ''
        end
    end
    out.OpportunitySortMode = mode
    return out
end

local function countryIdFromKey(key)
    return safeText(key, ''):match('^([a-z0-9_]+):') or ''
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

local function collapseInlineGraph()
    expandedKey = ''
    expandedRow = 0
    lastGraphSignature = ''
    lastLayoutSignature = ''
    for i = 1, 8 do
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'InlineGraph')
        SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Graph', 'Text', 'v')
    end
end

local function syncExpandedRow(data, count)
    if expandedKey == '' then expandedRow = 0 return end
    local found = 0
    for i = 1, count do
        if safeText(data['Opportunity' .. i .. 'Key'], '') == expandedKey then found = i break end
    end
    if found == 0 then collapseInlineGraph() else expandedRow = found end
end

local function layoutRows(data, count)
    syncExpandedRow(data, count)
    local signature = tostring(count) .. ':' .. tostring(expandedRow)
    if signature == lastLayoutSignature then return end
    lastLayoutSignature = signature

    for i = 1, 8 do
        local p = 'MeterOpportunity' .. i
        local extraBefore = (expandedRow > 0 and i > expandedRow) and graphExtra or 0
        local y = 120 + ((i-1) * rowStride) + extraBefore
        local isExpanded = (i == expandedRow)
        local cardHeight = isExpanded and expandedCardHeight or collapsedCardHeight

        SKIN:Bang('!SetOption', p .. 'Card', 'Y', tostring(y))
        SKIN:Bang('!SetOption', p .. 'Card', 'H', tostring(cardHeight))
        SKIN:Bang('!SetOption', p .. 'Card', 'Shape', 'Rectangle 0,0,536,' .. cardHeight .. ',5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#')
        SKIN:Bang('!SetOption', p .. 'Flag', 'Y', tostring(y+3))
        SKIN:Bang('!SetOption', p .. 'Name', 'Y', tostring(y+6))
        SKIN:Bang('!SetOption', p .. 'Gross', 'Y', tostring(y+6))
        SKIN:Bang('!SetOption', p .. 'Window', 'Y', tostring(y+27))
        SKIN:Bang('!SetOption', p .. 'Leave', 'Y', tostring(y+27))
        SKIN:Bang('!SetOption', p .. 'Chance', 'Y', tostring(y+27))
        SKIN:Bang('!SetOption', p .. 'Price', 'Y', tostring(y+26))
        SKIN:Bang('!SetOption', p .. 'Graph', 'Y', tostring(y+24))
        SKIN:Bang('!SetOption', p .. 'Graph', 'Text', isExpanded and '^' or 'v')
        SKIN:Bang('!SetOption', p .. 'InlineGraph', 'Y', tostring(y+53))
        if not isExpanded then SKIN:Bang('!HideMeter', p .. 'InlineGraph') end
    end

    local panelHeight = 164
    if count > 0 then panelHeight = 120 + (count * rowStride) + ((expandedRow > 0) and graphExtra or 0) + 8 end
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
    else
        SKIN:Bang('!HideMeter', meter)
    end
end

local function updateOpportunities(data)
    local count = math.max(0, math.min(8, math.floor(number(data.OpportunityCount))))
    setVariable('OpportunityMessageText', safeText(data.OpportunityMessage, 'No current opportunities'))
    setMeterVisible('MeterOpportunityMessage', count == 0)

    for i = 1, 8 do
        local prefix = 'Opportunity' .. i
        local visible = i <= count
        setGroupVisible('OpportunityRow' .. i, visible)
        if visible then
            local key = safeText(data[prefix .. 'Key'], '')
            local tooltip = safeText(data[prefix .. 'Tooltip'], '')
            local gross = safeText(data[prefix .. 'GrossText'], '')
            local price = safeText(data[prefix .. 'PriceText'], '')
            local mv = safeText(data[prefix .. 'MarketValueText'], '')
            local combinedPrice = price
            if mv ~= '' then combinedPrice = price .. ' (' .. mv .. ')' end

            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Name', 'Text', safeText(data[prefix .. 'Name'], ''))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Name', 'ToolTipText', tooltip)
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'Text', gross)
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'FontColor', safeText(data[prefix .. 'PriceColor'], '145,152,164,255'))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'ToolTipText', tooltip)
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Window', 'Text', safeText(data[prefix .. 'WindowText'], ''))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Leave', 'Text', safeLeaveText(data, prefix))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Chance', 'Text', safeText(data[prefix .. 'ChanceText'], ''))
            SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Price', 'Text', combinedPrice)
            applyFlagForRow(data, i, key)
        end
    end

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
    pollInterval = math.floor(configuredPoll)
    failureRetryInterval = math.floor(configuredFailureRetry)
    nextPollAt = os.time() + pollInterval

    local initial = readState()
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
    deferPolling(5)
    setVariable('PreferenceAction', 'ToggleTripBand')
    setVariable('PreferenceValue', band)
    SKIN:Bang('!UpdateMeasure', 'MeasurePreferenceAction')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function ResetFilters()
    deferPolling(5)
    collapseInlineGraph()
    setVariable('PreferenceAction', 'ResetFilters')
    setVariable('PreferenceValue', '')
    SKIN:Bang('!UpdateMeasure', 'MeasurePreferenceAction')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function SetSortMode(mode)
    mode = safeText(mode, 'upcoming'):lower()
    if mode ~= 'name' and mode ~= 'upcoming' and mode ~= 'gross' and mode ~= 'profit_per_hour' then mode = 'upcoming' end
    if lastSortMode ~= mode then collapseInlineGraph() end
    deferPolling(5)
    pendingSortMode = mode
    lastSortMode = mode
    applySortColors(mode)

    if lastRenderData ~= nil then
        local immediate = locallySortedProjection(lastRenderData, mode)
        lastDisplayedData = immediate
        updateOpportunities(immediate)
    end

    setVariable('PreferenceAction', 'SetSortMode')
    setVariable('PreferenceValue', mode)
    SKIN:Bang('!UpdateMeasure', 'MeasurePreferenceAction')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
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
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

function OpenViewer(marketKey)
    deferPolling(5)
    setVariable('ViewerMarketKey', marketKey or '')
    SKIN:Bang('!UpdateMeasure', 'MeasureItemViewer')
    SKIN:Bang('!CommandMeasure', 'MeasureItemViewer', 'Run')
end

function Update()
    local now = os.time()
    local baseData = stabilizeProjection(readState())
    lastRenderData = baseData

    local projectedMode = safeText(baseData.OpportunitySortMode, 'upcoming'):lower()
    if projectedMode ~= 'name' and projectedMode ~= 'upcoming' and projectedMode ~= 'gross' and projectedMode ~= 'profit_per_hour' then projectedMode = 'upcoming' end
    if pendingSortMode ~= nil and projectedMode == pendingSortMode then pendingSortMode = nil end
    local renderMode = pendingSortMode or projectedMode
    if lastSortMode == nil then lastSortMode = renderMode end
    if renderMode ~= lastSortMode then
        collapseInlineGraph()
        lastSortMode = renderMode
    end

    local data = locallySortedProjection(baseData, renderMode)
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

    updateHeartbeatText(data, now)
    updateFilters(data)
    applySortColors(renderMode)
    updateOpportunities(data)
    return 0
end
