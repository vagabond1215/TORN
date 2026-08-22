local statePath = nil
local heartbeatPath = nil
local pollInterval = 60
local failureRetryInterval = 15
local failureRetryArmed = false
local nextPollAt = nil
local lastProjectionData = nil
local pendingSortMode = nil
local pendingSortUntil = 0

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

local function readState()
    local out = {}
    local file = io.open(statePath, 'r')
    if not file then return out end
    for line in file:lines() do
        local key, value = line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)] = trim(value) end
    end
    file:close()
    return out
end

local function copyProjectionFields(data)
    local out = {}
    for key, value in pairs(data) do
        if key:match('^Opportunity') or key:match('^UI') then out[key] = value end
    end
    return out
end

local function stabilizeProjection(data)
    -- UpdateTracker publishes compatibility fields before OpportunityState completes.
    -- Keep the last complete opportunity/UI projection during that short interval.
    if data.OpportunityCount ~= nil then
        lastProjectionData = copyProjectionFields(data)
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

    SKIN:Bang('!SetOption', 'MeterItemFilter', 'Text', 'ITEM  ' .. itemText .. '  v')
    SKIN:Bang('!SetOption', 'MeterTripExpand', 'Text', 'v')
    SKIN:Bang('!SetOption', 'MeterCategoryFilter', 'Text', 'CAT  ' .. categoryText .. '  v')
end

local function applySortColors(mode)
    local active = '82,174,255,255'
    local inactive = '145,152,164,255'
    -- Existing section names are retained internally to avoid another large skin
    -- rewrite; their visible labels/actions are repurposed below.
    setVariable('SortOptimalColor', mode == 'upcoming' and active or inactive)
    setVariable('SortUpcomingColor', mode == 'gross' and active or inactive)
    setVariable('SortProfitColor', mode == 'profit_per_hour' and active or inactive)
    setVariable('SortTimeColor', inactive)
end

local function configureInteractiveMeters()
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'Text', 'UPCOMING')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'X', '50')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'W', '72')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'ToolTipText', 'Soonest modeled stock windows first')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"SetSortMode('upcoming')\"]")

    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'Text', 'GROSS PROFIT')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'X', '126')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'W', '92')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'ToolTipText', 'Highest total trip gross first; gross is unit spread times purchasable quantity')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"SetSortMode('gross')\"]")

    SKIN:Bang('!SetOption', 'MeterSortProfit', 'Text', 'PROFIT/HR')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'X', '222')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'W', '78')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'ToolTipText', 'Trip gross divided by total elapsed hours; hit likelihood remains a separate displayed percentage')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"SetSortMode('profit_per_hour')\"]")
    SKIN:Bang('!HideMeter', 'MeterSortTime')

    -- Transparent SolidColor gives the text controls a stable rectangular hitbox.
    for _, meter in ipairs({
        'MeterSettings','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand',
        'MeterCategoryFilter','MeterFilterReset','MeterSortOptimal','MeterSortUpcoming','MeterSortProfit','MeterViewer'
    }) do
        SKIN:Bang('!SetOption', meter, 'SolidColor', '0,0,0,1')
    end

    for i = 1, 8 do
        SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'Optimal')
        SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Name', 'X', '48')
        SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Name', 'W', '238')
        SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Graph', 'SolidColor', '0,0,0,1')
    end
end

local function updateSort(data, now)
    local projected = safeText(data.OpportunitySortMode, 'upcoming'):lower()
    if pendingSortMode ~= nil then
        if projected == pendingSortMode or now >= pendingSortUntil then
            pendingSortMode = nil
            pendingSortUntil = 0
        end
    end
    applySortColors(pendingSortMode or projected)
end

local function updateOpportunityGrossMeter(data, prefix, index)
    local grossText = safeText(data[prefix .. 'GrossText'], '')
    local quantityText = safeText(data[prefix .. 'QuantityText'], '')
    local display = grossText
    if display ~= '' then
        display = display .. ' gross'
        if quantityText ~= '' then display = display .. ' ' .. quantityText end
    end
    SKIN:Bang('!SetOption', 'MeterOpportunity' .. index .. 'Gross', 'Text', display)
    SKIN:Bang('!SetOption', 'MeterOpportunity' .. index .. 'Gross', 'ToolTipText', safeText(data[prefix .. 'Tooltip'], ''))
end

local function updateOpportunities(data)
    local count = math.max(0, math.min(8, math.floor(number(data.OpportunityCount))))
    setVariable('OpportunityMessageText', safeText(data.OpportunityMessage, 'Learning opportunities...'))
    setMeterVisible('MeterOpportunityMessage', count == 0)

    for i = 1, 8 do
        local prefix = 'Opportunity' .. i
        for _, suffix in ipairs({
            'Key','RankText','Name','Country','CountryCode','WindowText','LeaveText',
            'ChanceText','TimeText','GrossText','QuantityText','ProfitHourText','PriceText','MarketValueText','PriceColor','AccentColor','Tooltip'
        }) do
            local fallback = ''
            if suffix == 'PriceColor' then fallback = '145,152,164,255' end
            if suffix == 'AccentColor' then fallback = '58,64,73,255' end
            setVariable(prefix .. suffix, safeText(data[prefix .. suffix], fallback))
        end
        SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'FontColor', safeText(data[prefix .. 'PriceColor'], '145,152,164,255'))
        updateOpportunityGrossMeter(data, prefix, i)
        setGroupVisible('OpportunityRow' .. i, i <= count)
    end

    local panelHeight = 164
    if count > 0 then panelHeight = 120 + count * 54 + 8 end
    setVariable('PanelHeight', panelHeight)
end

local function deferPolling(seconds)
    local now = os.time()
    local target = now + (seconds or 10)
    if nextPollAt == nil or nextPollAt < target then nextPollAt = target end
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
    pollInterval = math.floor(configuredPoll)
    failureRetryInterval = math.floor(configuredFailureRetry)
    failureRetryArmed = false
    nextPollAt = os.time() + pollInterval
    pendingSortMode = nil
    pendingSortUntil = 0

    configureInteractiveMeters()
    local initial = readState()
    if initial.OpportunityCount ~= nil then lastProjectionData = copyProjectionFields(initial) end
end

function OpenFilter(filterName)
    deferPolling(10)
    setVariable('FilterRequest', filterName)
    SKIN:Bang('!CommandMeasure', 'MeasureFilterPopup', 'Run')
end

function ToggleTripBand(band)
    deferPolling(10)
    setVariable('PreferenceAction', 'ToggleTripBand')
    setVariable('PreferenceValue', band)
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function ResetFilters()
    deferPolling(10)
    setVariable('PreferenceAction', 'ResetFilters')
    setVariable('PreferenceValue', '')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function SetSortMode(mode)
    mode = safeText(mode, 'upcoming'):lower()
    if mode ~= 'upcoming' and mode ~= 'gross' and mode ~= 'profit_per_hour' then mode = 'upcoming' end
    deferPolling(10)
    pendingSortMode = mode
    pendingSortUntil = os.time() + 10
    applySortColors(mode)
    setVariable('PreferenceAction', 'SetSortMode')
    setVariable('PreferenceValue', mode)
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
    SKIN:Bang('!UpdateMeter', 'MeterSortOptimal')
    SKIN:Bang('!UpdateMeter', 'MeterSortUpcoming')
    SKIN:Bang('!UpdateMeter', 'MeterSortProfit')
    SKIN:Bang('!Redraw')
end

function OpenViewer(marketKey)
    deferPolling(10)
    setVariable('ViewerMarketKey', marketKey or '')
    SKIN:Bang('!CommandMeasure', 'MeasureItemViewer', 'Run')
end

function Update()
    local now = os.time()
    local data = stabilizeProjection(readState())
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

    updateHeartbeatText(data, now)
    updateFilters(data)
    updateSort(data, now)
    updateOpportunities(data)
    return 0
end
