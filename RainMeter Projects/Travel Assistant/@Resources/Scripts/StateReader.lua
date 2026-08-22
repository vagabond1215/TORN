local statePath = nil
local heartbeatPath = nil
local generatedDir = nil
local pollInterval = 60
local failureRetryInterval = 15
local failureRetryArmed = false
local nextPollAt = nil
local lastProjectionData = nil
local lastRenderData = nil
local lastDisplayedData = nil
local pendingSortMode = nil
local expandedKey = ''
local expandedRow = 0
local lastInlineRenderRequestAt = 0
local lastLayoutSignature = ''
local lastFlagKeys = {}
local lastGraphSignature = ''

local graphExtra = 122
local collapsedCardHeight = 50
local expandedCardHeight = collapsedCardHeight + graphExtra
local invisibleShape = 'Rectangle 0,0,0,0 | Fill Color 0,0,0,0 | StrokeWidth 0'

local opportunitySuffixes = {
    'Key','RankText','Name','Country','CountryCode','WindowText','LeaveText',
    'ChanceText','TimeText','GrossText','QuantityText','ProfitHourText','PriceText','MarketValueText',
    'PriceColor','AccentColor','Tooltip','GrossValue','ProfitHourValue','WindowStartAt','ProbabilityValue','ElapsedSeconds'
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

local function formatInteger(v)
    local value = math.floor(math.abs(number(v)) + 0.5)
    local text = tostring(value)
    while true do
        local changed, count = text:gsub('^(%d+)(%d%d%d)', '%1,%2')
        text = changed
        if count == 0 then break end
    end
    if number(v) < 0 then text = '-' .. text end
    return text
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
    for key, value in pairs(data) do
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
            local incomingSortText = data.OpportunitySortText
            for key, value in pairs(lastProjectionData) do
                if key:match('^Opportunity') then data[key] = value
                elseif key:match('^UI') and data[key] == nil then data[key] = value end
            end
            if incomingSortMode ~= nil then data.OpportunitySortMode = incomingSortMode end
            if incomingSortText ~= nil then data.OpportunitySortText = incomingSortText end
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

local function setShape(meter, index, value)
    local option = index == 1 and 'Shape' or ('Shape' .. index)
    SKIN:Bang('!SetOption', meter, option, value)
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
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'FontColor', mode == 'name' and active or inactive)
    setVariable('SortOptimalColor', mode == 'upcoming' and active or inactive)
    setVariable('SortUpcomingColor', mode == 'gross' and active or inactive)
    setVariable('SortProfitColor', mode == 'profit_per_hour' and active or inactive)
    setVariable('SortTimeColor', inactive)
end

local function configureInteractiveMeters()
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'Text', 'NAME')
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'X', '12')
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'Y', '89')
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'W', '40')
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'FontFace', 'Segoe UI Semibold')
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'FontSize', '9')
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'ToolTipText', 'Alphabetical item name')
    SKIN:Bang('!SetOption', 'MeterSortLabel', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"SetSortMode('name')\"]")

    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'Text', 'UPCOMING')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'X', '56')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'W', '70')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'ToolTipText', 'Soonest modeled stock windows first')
    SKIN:Bang('!SetOption', 'MeterSortOptimal', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"SetSortMode('upcoming')\"]")

    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'Text', 'GROSS PROFIT')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'X', '130')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'W', '92')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'ToolTipText', 'Highest total trip gross first')
    SKIN:Bang('!SetOption', 'MeterSortUpcoming', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"SetSortMode('gross')\"]")

    SKIN:Bang('!SetOption', 'MeterSortProfit', 'Text', 'PROFIT/HR')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'X', '226')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'W', '78')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'ToolTipText', 'Trip gross divided by total elapsed hours; likelihood stays separate')
    SKIN:Bang('!SetOption', 'MeterSortProfit', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"SetSortMode('profit_per_hour')\"]")
    SKIN:Bang('!HideMeter', 'MeterSortTime')

    for _, meter in ipairs({
        'MeterSettings','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand',
        'MeterCategoryFilter','MeterFilterReset','MeterSortLabel','MeterSortOptimal','MeterSortUpcoming','MeterSortProfit','MeterViewer'
    }) do
        SKIN:Bang('!SetOption', meter, 'SolidColor', '0,0,0,1')
    end

    for i = 1, 8 do
        local p = 'MeterOpportunity' .. i
        SKIN:Bang('!SetOption', p .. 'Rank', 'X', '30')
        SKIN:Bang('!SetOption', p .. 'Rank', 'W', '36')
        SKIN:Bang('!SetOption', p .. 'Rank', 'StringAlign', 'Center')
        SKIN:Bang('!SetOption', p .. 'Rank', 'FontFace', 'Segoe UI Semibold')
        SKIN:Bang('!SetOption', p .. 'Rank', 'FontSize', '7')
        SKIN:Bang('!SetOption', p .. 'Rank', 'FontColor', '#Muted#')
        SKIN:Bang('!SetOption', p .. 'Rank', 'Text', '')

        SKIN:Bang('!SetOption', p .. 'Name', 'X', '56')
        SKIN:Bang('!SetOption', p .. 'Name', 'W', '248')
        SKIN:Bang('!SetOption', p .. 'Gross', 'X', '504')
        SKIN:Bang('!SetOption', p .. 'Gross', 'W', '130')
        SKIN:Bang('!SetOption', p .. 'Gross', 'StringAlign', 'Right')
        SKIN:Bang('!SetOption', p .. 'Window', 'X', '56')
        SKIN:Bang('!SetOption', p .. 'Window', 'W', '86')
        SKIN:Bang('!SetOption', p .. 'Leave', 'X', '146')
        SKIN:Bang('!SetOption', p .. 'Leave', 'W', '88')
        SKIN:Bang('!SetOption', p .. 'Chance', 'X', '238')
        SKIN:Bang('!SetOption', p .. 'Chance', 'W', '58')
        SKIN:Bang('!SetOption', p .. 'Price', 'X', '300')
        SKIN:Bang('!SetOption', p .. 'Price', 'W', '198')

        SKIN:Bang('!SetOption', p .. 'Graph', 'X', '520')
        SKIN:Bang('!SetOption', p .. 'Graph', 'W', '18')
        SKIN:Bang('!SetOption', p .. 'Graph', 'StringAlign', 'Center')
        SKIN:Bang('!SetOption', p .. 'Graph', 'FontSize', '11')
        SKIN:Bang('!SetOption', p .. 'Graph', 'Text', 'v')
        SKIN:Bang('!SetOption', p .. 'Graph', 'ToolTipText', 'Expand 8-hour stock history in this card')
        SKIN:Bang('!SetOption', p .. 'Graph', 'LeftMouseUpAction', "[!CommandMeasure MeasureState \"ToggleInlineGraph(" .. i .. ")\"]")
        SKIN:Bang('!SetOption', p .. 'Graph', 'SolidColor', '0,0,0,1')

        SKIN:Bang('!HideMeter', p .. 'Country')
        SKIN:Bang('!HideMeter', p .. 'Time')
        SKIN:Bang('!HideMeter', p .. 'Optimal')
    end
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
            if a.probability ~= b.probability then return a.probability > b.probability end
            if a.elapsed ~= b.elapsed then return a.elapsed < b.elapsed end
            return string.lower(a.name) < string.lower(b.name)
        elseif mode == 'profit_per_hour' then
            if a.profitHour ~= b.profitHour then return a.profitHour > b.profitHour end
            if a.gross ~= b.gross then return a.gross > b.gross end
            if a.probability ~= b.probability then return a.probability > b.probability end
            return string.lower(a.name) < string.lower(b.name)
        else
            if a.windowStart > 0 and b.windowStart > 0 and a.windowStart ~= b.windowStart then return a.windowStart < b.windowStart end
            if a.probability ~= b.probability then return a.probability > b.probability end
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
        out[targetPrefix .. 'RankText'] = ''
    end
    out.OpportunitySortMode = mode
    return out
end

local function updateSort(mode)
    applySortColors(mode)
end

local function countryIdFromKey(key)
    return safeText(key, ''):match('^([a-z0-9_]+):') or ''
end

local function applyFlagForRow(index, key)
    if lastFlagKeys[index] == key then return end
    lastFlagKeys[index] = key
    local meter = 'MeterOpportunity' .. index .. 'Card'
    for shapeIndex = 2, 9 do setShape(meter, shapeIndex, invisibleShape) end

    local country = countryIdFromKey(key)
    if country == 'mexico' then
        setShape(meter,2,'Rectangle 4,4,12,28 | Fill Color 0,104,71,255 | StrokeWidth 0')
        setShape(meter,3,'Rectangle 16,4,12,28 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,4,'Rectangle 28,4,12,28 | Fill Color 206,17,38,255 | StrokeWidth 0')
        setShape(meter,5,'Ellipse 22,18,2.5,2.5 | Fill Color 76,112,72,255 | StrokeWidth 0')
    elseif country == 'cayman_islands' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 0,36,125,255 | StrokeWidth 0')
        setShape(meter,3,'Line 4,10,20,10 | StrokeWidth 3 | Stroke Color 255,255,255,255')
        setShape(meter,4,'Line 12,4,12,16 | StrokeWidth 3 | Stroke Color 255,255,255,255')
        setShape(meter,5,'Line 4,10,20,10 | StrokeWidth 1 | Stroke Color 207,20,43,255')
        setShape(meter,6,'Line 12,4,12,16 | StrokeWidth 1 | Stroke Color 207,20,43,255')
        setShape(meter,7,'Ellipse 32,20,4,5 | Fill Color 112,183,226,255 | StrokeWidth 1 | Stroke Color 255,255,255,255')
    elseif country == 'canada' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 216,36,45,255 | StrokeWidth 0')
        setShape(meter,3,'Rectangle 13,4,18,28 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,4,'Rectangle 20,11,4,14 | Fill Color 216,36,45,255 | StrokeWidth 0')
        setShape(meter,5,'Rectangle 17,16,10,4 | Fill Color 216,36,45,255 | StrokeWidth 0')
    elseif country == 'hawaii' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 204,20,43,255 | StrokeWidth 0')
        setShape(meter,3,'Rectangle 4,8,36,4 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,4,'Rectangle 4,16,36,4 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,5,'Rectangle 4,24,36,4 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,6,'Rectangle 4,4,16,12 | Fill Color 0,40,104,255 | StrokeWidth 0')
        setShape(meter,7,'Line 4,10,20,10 | StrokeWidth 2 | Stroke Color 255,255,255,255')
    elseif country == 'united_kingdom' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 1,33,105,255 | StrokeWidth 0')
        setShape(meter,3,'Line 4,4,40,32 | StrokeWidth 5 | Stroke Color 255,255,255,255')
        setShape(meter,4,'Line 40,4,4,32 | StrokeWidth 5 | Stroke Color 255,255,255,255')
        setShape(meter,5,'Rectangle 4,15,36,6 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,6,'Rectangle 4,17,36,3 | Fill Color 200,16,46,255 | StrokeWidth 0')
        setShape(meter,7,'Rectangle 20,4,4,28 | Fill Color 200,16,46,255 | StrokeWidth 0')
    elseif country == 'argentina' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 116,172,223,255 | StrokeWidth 0')
        setShape(meter,3,'Rectangle 4,13,36,10 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,4,'Ellipse 22,18,2.5,2.5 | Fill Color 246,180,14,255 | StrokeWidth 0')
    elseif country == 'switzerland' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 218,41,28,255 | StrokeWidth 0')
        setShape(meter,3,'Rectangle 13,15,18,6 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,4,'Rectangle 19,9,6,18 | Fill Color 255,255,255,255 | StrokeWidth 0')
    elseif country == 'japan' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,3,'Ellipse 22,18,7,7 | Fill Color 188,0,45,255 | StrokeWidth 0')
    elseif country == 'china' then
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 222,41,16,255 | StrokeWidth 0')
        setShape(meter,3,'Ellipse 11,11,3,3 | Fill Color 255,222,0,255 | StrokeWidth 0')
        setShape(meter,4,'Ellipse 17,8,1.2,1.2 | Fill Color 255,222,0,255 | StrokeWidth 0')
        setShape(meter,5,'Ellipse 19,12,1.2,1.2 | Fill Color 255,222,0,255 | StrokeWidth 0')
        setShape(meter,6,'Ellipse 18,16,1.2,1.2 | Fill Color 255,222,0,255 | StrokeWidth 0')
    elseif country == 'united_arab_emirates' then
        setShape(meter,2,'Rectangle 4,4,36,9.4 | Fill Color 0,122,61,255 | StrokeWidth 0')
        setShape(meter,3,'Rectangle 4,13.3,36,9.4 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,4,'Rectangle 4,22.6,36,9.4 | Fill Color 0,0,0,255 | StrokeWidth 0')
        setShape(meter,5,'Rectangle 4,4,10,28 | Fill Color 206,17,38,255 | StrokeWidth 0')
    elseif country == 'south_africa' then
        setShape(meter,2,'Rectangle 4,4,36,14 | Fill Color 222,56,49,255 | StrokeWidth 0')
        setShape(meter,3,'Rectangle 4,18,36,14 | Fill Color 0,35,149,255 | StrokeWidth 0')
        setShape(meter,4,'Rectangle 4,14,36,8 | Fill Color 255,255,255,255 | StrokeWidth 0')
        setShape(meter,5,'Rectangle 4,16,36,4 | Fill Color 0,119,73,255 | StrokeWidth 0')
        setShape(meter,6,'Line 4,5,18,18 | StrokeWidth 8 | Stroke Color 0,0,0,255')
        setShape(meter,7,'Line 4,31,18,18 | StrokeWidth 8 | Stroke Color 0,0,0,255')
    else
        setShape(meter,2,'Rectangle 4,4,36,28 | Fill Color 90,96,106,255 | StrokeWidth 0')
    end
end

local function graphSpecPath(key)
    if generatedDir == nil then return '' end
    local safe = safeText(key, ''):gsub('[^%w_-]', '_')
    return generatedDir .. 'inline-graph-' .. safe .. '.kv'
end

local function readGraphSpec(key)
    local path = graphSpecPath(key)
    if path == '' then return nil end
    local values = readKv(path)
    if safeText(values.MarketKey, '') ~= key then return nil end
    return values
end

local function clearGraphShapes(index)
    local meter = 'MeterOpportunity' .. index .. 'Card'
    for shapeIndex = 10, 23 do setShape(meter, shapeIndex, invisibleShape) end
    SKIN:Bang('!SetOption', meter, 'GraphPath', '44,150 | LineTo 520,150')
end

local function applyGraphShapes(index, spec)
    local meter = 'MeterOpportunity' .. index .. 'Card'
    setShape(meter,10,'Rectangle 8,54,520,116,4 | Fill Color 20,23,27,255 | StrokeWidth 1 | Stroke Color 58,64,73,255')
    setShape(meter,11,'Line 44,76,520,76 | StrokeWidth 1 | Stroke Color 58,64,73,180')
    setShape(meter,12,'Line 44,113,520,113 | StrokeWidth 1 | Stroke Color 58,64,73,140')
    setShape(meter,13,'Line 44,150,520,150 | StrokeWidth 1 | Stroke Color 58,64,73,180')
    setShape(meter,14,'Line 44,76,44,150 | StrokeWidth 1 | Stroke Color 58,64,73,180')
    setShape(meter,15,'Line 103.5,76,103.5,150 | StrokeWidth 1 | Stroke Color 58,64,73,110')
    setShape(meter,16,'Line 163,76,163,150 | StrokeWidth 1 | Stroke Color 58,64,73,110')
    setShape(meter,17,'Line 222.5,76,222.5,150 | StrokeWidth 1 | Stroke Color 58,64,73,110')
    setShape(meter,18,'Line 282,76,282,150 | StrokeWidth 1 | Stroke Color 58,64,73,110')
    setShape(meter,19,'Line 341.5,76,341.5,150 | StrokeWidth 1 | Stroke Color 58,64,73,110')
    setShape(meter,20,'Line 401,76,401,150 | StrokeWidth 1 | Stroke Color 58,64,73,110')
    setShape(meter,21,'Line 460.5,76,460.5,150 | StrokeWidth 1 | Stroke Color 58,64,73,110')
    setShape(meter,22,'Line 520,76,520,150 | StrokeWidth 1 | Stroke Color 58,64,73,180')
    if spec ~= nil and safeText(spec.GraphPath, '') ~= '' then
        SKIN:Bang('!SetOption', meter, 'GraphPath', safeText(spec.GraphPath, '44,150 | LineTo 520,150'))
        setShape(meter,23,'Path GraphPath | StrokeWidth 2 | Stroke Color 82,174,255,255 | Fill Color 0,0,0,0')
    else
        setShape(meter,23,invisibleShape)
    end
end

local function syncExpandedRow(data, count)
    if expandedKey == '' then expandedRow = 0 return end
    local found = 0
    for i = 1, count do
        if safeText(data['Opportunity' .. i .. 'Key'], '') == expandedKey then found = i break end
    end
    if found == 0 then
        expandedKey = ''
        expandedRow = 0
        lastGraphSignature = ''
    else
        expandedRow = found
    end
end

local function layoutRows(data, count)
    syncExpandedRow(data, count)
    local signature = tostring(count) .. ':' .. tostring(expandedRow)
    if signature ~= lastLayoutSignature then
        lastLayoutSignature = signature
        for i = 1, 8 do
            local p = 'MeterOpportunity' .. i
            local extraBefore = (expandedRow > 0 and i > expandedRow) and graphExtra or 0
            local y = 120 + ((i-1) * 54) + extraBefore
            local isExpanded = (i == expandedRow)
            local cardHeight = isExpanded and expandedCardHeight or collapsedCardHeight
            SKIN:Bang('!SetOption', p .. 'Card', 'Y', tostring(y))
            SKIN:Bang('!SetOption', p .. 'Card', 'H', tostring(cardHeight))
            setShape(p .. 'Card',1,'Rectangle 0,0,536,' .. cardHeight .. ',5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Opportunity' .. i .. 'AccentColor#')
            SKIN:Bang('!SetOption', p .. 'Rank', 'Y', tostring(y+35))
            SKIN:Bang('!SetOption', p .. 'Name', 'Y', tostring(y+6))
            SKIN:Bang('!SetOption', p .. 'Gross', 'Y', tostring(y+6))
            SKIN:Bang('!SetOption', p .. 'Window', 'Y', tostring(y+27))
            SKIN:Bang('!SetOption', p .. 'Leave', 'Y', tostring(y+27))
            SKIN:Bang('!SetOption', p .. 'Chance', 'Y', tostring(y+27))
            SKIN:Bang('!SetOption', p .. 'Price', 'Y', tostring(y+26))
            SKIN:Bang('!SetOption', p .. 'Graph', 'Y', tostring(y+24))
            SKIN:Bang('!SetOption', p .. 'Graph', 'Text', isExpanded and '^' or 'v')

            if isExpanded then
                -- Reuse hidden compatibility string meters as sparse chart axis labels.
                SKIN:Bang('!SetOption', p .. 'Country', 'X', '40')
                SKIN:Bang('!SetOption', p .. 'Country', 'Y', tostring(y+67))
                SKIN:Bang('!SetOption', p .. 'Country', 'W', '38')
                SKIN:Bang('!SetOption', p .. 'Country', 'StringAlign', 'Right')
                SKIN:Bang('!SetOption', p .. 'Country', 'FontSize', '7')
                SKIN:Bang('!SetOption', p .. 'Country', 'FontColor', '#Muted#')

                SKIN:Bang('!SetOption', p .. 'Optimal', 'X', '40')
                SKIN:Bang('!SetOption', p .. 'Optimal', 'Y', tostring(y+143))
                SKIN:Bang('!SetOption', p .. 'Optimal', 'W', '38')
                SKIN:Bang('!SetOption', p .. 'Optimal', 'StringAlign', 'Right')
                SKIN:Bang('!SetOption', p .. 'Optimal', 'FontSize', '7')
                SKIN:Bang('!SetOption', p .. 'Optimal', 'FontColor', '#Muted#')
                SKIN:Bang('!SetOption', p .. 'Optimal', 'Text', '0')

                SKIN:Bang('!SetOption', p .. 'Time', 'X', '44')
                SKIN:Bang('!SetOption', p .. 'Time', 'Y', tostring(y+154))
                SKIN:Bang('!SetOption', p .. 'Time', 'W', '44')
                SKIN:Bang('!SetOption', p .. 'Time', 'StringAlign', 'Left')
                SKIN:Bang('!SetOption', p .. 'Time', 'FontSize', '7')
                SKIN:Bang('!SetOption', p .. 'Time', 'FontColor', '#Muted#')
                SKIN:Bang('!SetOption', p .. 'Time', 'Text', '-8h')
            else
                SKIN:Bang('!HideMeter', p .. 'Country')
                SKIN:Bang('!HideMeter', p .. 'Optimal')
                SKIN:Bang('!HideMeter', p .. 'Time')
                clearGraphShapes(i)
            end
        end
    end

    local panelHeight = 164
    if count > 0 then panelHeight = 120 + (count * 54) + ((expandedRow > 0) and graphExtra or 0) + 8 end
    setVariable('PanelHeight', panelHeight)
end

local function updateExpandedGraph(data)
    if expandedRow <= 0 or expandedKey == '' then
        if lastGraphSignature ~= '' then lastGraphSignature = '' end
        return
    end
    local p = 'MeterOpportunity' .. expandedRow
    local spec = readGraphSpec(expandedKey)
    local signature = expandedKey .. ':' .. safeText(spec and spec.UpdatedAt or '', '')
    if signature ~= lastGraphSignature then
        lastGraphSignature = signature
        applyGraphShapes(expandedRow, spec)
        local maxText = ''
        if spec ~= nil and number(spec.MaxStock) > 0 then maxText = formatInteger(spec.MaxStock) end
        SKIN:Bang('!SetOption', p .. 'Country', 'Text', maxText)
    end
    SKIN:Bang('!ShowMeter', p .. 'Country')
    SKIN:Bang('!ShowMeter', p .. 'Optimal')
    SKIN:Bang('!ShowMeter', p .. 'Time')
end

local function updateOpportunityGrossMeter(data, prefix, index)
    local grossText = safeText(data[prefix .. 'GrossText'], '')
    SKIN:Bang('!SetOption', 'MeterOpportunity' .. index .. 'Gross', 'Text', grossText)
    SKIN:Bang('!SetOption', 'MeterOpportunity' .. index .. 'Gross', 'ToolTipText', safeText(data[prefix .. 'Tooltip'], ''))
end

local function updateOpportunities(data)
    local count = math.max(0, math.min(8, math.floor(number(data.OpportunityCount))))
    setVariable('OpportunityMessageText', safeText(data.OpportunityMessage, 'No current opportunities'))
    setMeterVisible('MeterOpportunityMessage', count == 0)

    for i = 1, 8 do
        local prefix = 'Opportunity' .. i
        for _, suffix in ipairs(opportunitySuffixes) do
            local fallback = ''
            if suffix == 'PriceColor' then fallback = '145,152,164,255' end
            if suffix == 'AccentColor' then fallback = '58,64,73,255' end
            setVariable(prefix .. suffix, safeText(data[prefix .. suffix], fallback))
        end
        local p = 'MeterOpportunity' .. i
        SKIN:Bang('!SetOption', p .. 'Gross', 'FontColor', safeText(data[prefix .. 'PriceColor'], '145,152,164,255'))
        SKIN:Bang('!SetOption', p .. 'Rank', 'Text', safeText(data[prefix .. 'TimeText'], ''))
        updateOpportunityGrossMeter(data, prefix, i)
        local visible = i <= count
        setGroupVisible('OpportunityRow' .. i, visible)
        if visible then applyFlagForRow(i, safeText(data[prefix .. 'Key'], '')) end
    end

    layoutRows(data, count)
    for i = 1, 8 do
        if i ~= expandedRow then
            SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'Country')
            SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'Optimal')
            SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'Time')
        end
    end
    updateExpandedGraph(data)
end

local function deferPolling(seconds)
    local now = os.time()
    local target = now + (seconds or 5)
    if nextPollAt == nil or nextPollAt < target then nextPollAt = target end
end

local function runViewerMeasure(marketKey)
    setVariable('ViewerMarketKey', marketKey or '')
    -- Dynamic RunCommand parameters are refreshed explicitly so a prior Viewer
    -- key cannot leak into an inline chart request (or vice versa).
    SKIN:Bang('!UpdateMeasure', 'MeasureItemViewer')
    SKIN:Bang('!CommandMeasure', 'MeasureItemViewer', 'Run')
end

local function requestInlineGraph(key)
    if key == '' then return end
    lastInlineRenderRequestAt = os.time()
    runViewerMeasure('inline_' .. key)
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
    pollInterval = math.floor(configuredPoll)
    failureRetryInterval = math.floor(configuredFailureRetry)
    failureRetryArmed = false
    nextPollAt = os.time() + pollInterval
    pendingSortMode = nil
    expandedKey = ''
    expandedRow = 0

    configureInteractiveMeters()
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
    setVariable('PreferenceAction', 'ResetFilters')
    setVariable('PreferenceValue', '')
    SKIN:Bang('!UpdateMeasure', 'MeasurePreferenceAction')
    SKIN:Bang('!CommandMeasure', 'MeasurePreferenceAction', 'Run')
end

function SetSortMode(mode)
    mode = safeText(mode, 'upcoming'):lower()
    if mode ~= 'name' and mode ~= 'upcoming' and mode ~= 'gross' and mode ~= 'profit_per_hour' then mode = 'upcoming' end
    deferPolling(5)
    pendingSortMode = mode
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
        expandedKey = ''
        expandedRow = 0
        lastGraphSignature = ''
        lastLayoutSignature = ''
    else
        expandedKey = key
        expandedRow = row
        lastGraphSignature = ''
        lastLayoutSignature = ''
        requestInlineGraph(key)
    end
    updateOpportunities(lastDisplayedData)
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

function OpenViewer(marketKey)
    deferPolling(5)
    runViewerMeasure(marketKey or '')
end

function Update()
    local now = os.time()
    local baseData = stabilizeProjection(readState())
    lastRenderData = baseData

    local projectedMode = safeText(baseData.OpportunitySortMode, 'upcoming'):lower()
    if projectedMode ~= 'name' and projectedMode ~= 'upcoming' and projectedMode ~= 'gross' and projectedMode ~= 'profit_per_hour' then projectedMode = 'upcoming' end
    if pendingSortMode ~= nil and projectedMode == pendingSortMode then pendingSortMode = nil end
    local renderMode = pendingSortMode or projectedMode
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
    updateSort(renderMode)
    updateOpportunities(data)
    return 0
end
