local statePath = nil
local heartbeatPath = nil
local pollInterval = 60
local failureRetryInterval = 15
local failureRetryArmed = false
local nextPollAt = nil

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

    -- Keep control markers ASCII. Rainmeter may interpret UTF-8 skin literals as
    -- ANSI on some installations, which renders the old triangle as mojibake.
    SKIN:Bang('!SetOption', 'MeterItemFilter', 'Text', 'ITEM  ' .. itemText .. '  v')
    SKIN:Bang('!SetOption', 'MeterTripExpand', 'Text', 'v')
    SKIN:Bang('!SetOption', 'MeterCategoryFilter', 'Text', 'CAT  ' .. categoryText .. '  v')
end

local function updateSort(data)
    local mode = safeText(data.OpportunitySortMode, 'optimal'):lower()
    local active = '82,174,255,255'
    local inactive = '145,152,164,255'
    setVariable('SortOptimalColor', mode == 'optimal' and active or inactive)
    setVariable('SortUpcomingColor', mode == 'upcoming' and active or inactive)
    setVariable('SortProfitColor', mode == 'profit' and active or inactive)
    setVariable('SortTimeColor', mode == 'time' and active or inactive)
end

local function updateOpportunities(data)
    local count = math.max(0, math.min(8, math.floor(number(data.OpportunityCount))))
    setVariable('OpportunityMessageText', safeText(data.OpportunityMessage, 'Learning opportunities...'))
    setMeterVisible('MeterOpportunityMessage', count == 0)

    for i = 1, 8 do
        local prefix = 'Opportunity' .. i
        for _, suffix in ipairs({
            'Key','RankText','OptimalText','Name','Country','CountryCode','WindowText','LeaveText',
            'ChanceText','TimeText','GrossText','PriceText','MarketValueText','PriceColor','AccentColor','Tooltip'
        }) do
            local fallback = ''
            if suffix == 'PriceColor' then fallback = '145,152,164,255' end
            if suffix == 'AccentColor' then fallback = '58,64,73,255' end
            setVariable(prefix .. suffix, safeText(data[prefix .. suffix], fallback))
        end
        SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'FontColor', safeText(data[prefix .. 'PriceColor'], '145,152,164,255'))
        setGroupVisible('OpportunityRow' .. i, i <= count)
    end

    local panelHeight = 164
    if count > 0 then panelHeight = 120 + count * 54 + 8 end
    setVariable('PanelHeight', panelHeight)
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
end

function OpenFilter(filterName)
    setVariable('FilterRequest', filterName)
    SKIN:Bang('!CommandMeasure', 'MeasureFilterPopup', 'Run')
end

function ToggleTripBand(band)
    setVariable('PreferenceAction', 'ToggleTripBand')
    setVariable('PreferenceValue', band)
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function ResetFilters()
    setVariable('PreferenceAction', 'ResetFilters')
    setVariable('PreferenceValue', '')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function SetSortMode(mode)
    setVariable('PreferenceAction', 'SetSortMode')
    setVariable('PreferenceValue', mode)
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function OpenViewer(marketKey)
    setVariable('ViewerMarketKey', marketKey or '')
    SKIN:Bang('!CommandMeasure', 'MeasureItemViewer', 'Run')
end

function Update()
    local now = os.time()
    local data = readState()
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
    updateSort(data)
    updateOpportunities(data)
    return 0
end
