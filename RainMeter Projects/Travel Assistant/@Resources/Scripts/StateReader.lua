local statePath = nil
local heartbeatPath = nil
local pollInterval = 60
local failureRetryInterval = 15
local failureRetryArmed = false
local nextPollAt = nil

local function trim(s)
    s = s:gsub('^\239\187\191', '')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function readState()
    local out = {}
    local f = io.open(statePath, 'r')
    if not f then return out end
    for line in f:lines() do
        local key, value = line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)] = trim(value or '') end
    end
    f:close()
    return out
end

local function readEpochFile(path)
    if path == nil then return 0 end
    local f = io.open(path, 'r')
    if not f then return 0 end
    local raw = f:read('*a') or ''
    f:close()
    return tonumber(trim(raw)) or 0
end

local function number(v)
    local n = tonumber(v)
    if n == nil then return 0 end
    return n
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(number(seconds) + 0.5))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format('%d:%02d:%02d', h, m, s)
    end
    return string.format('%02d:%02d', m, s)
end

local function formatShortElapsed(seconds)
    seconds = math.max(0, math.floor(number(seconds)))
    if seconds < 60 then return '<1m' end
    if seconds < 3600 then return string.format('%dm', math.floor(seconds / 60)) end
    if seconds < 86400 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        if m > 0 then return string.format('%dh %dm', h, m) end
        return string.format('%dh', h)
    end
    return string.format('%dd', math.floor(seconds / 86400))
end

local function formatHoursMinutes(seconds)
    seconds = math.max(0, math.floor(number(seconds)))
    local totalMinutes = math.floor(seconds / 60)
    local h = math.floor(totalMinutes / 60)
    local m = totalMinutes % 60
    return string.format('%d:%02d', h, m)
end

local function formatInteger(value)
    local s = tostring(math.floor(number(value) + 0.5))
    local sign, digits = s:match('^([%-]?)(%d+)$')
    if not digits then return s end
    local reversed = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if reversed:sub(1, 1) == ',' then reversed = reversed:sub(2) end
    return (sign or '') .. reversed
end

local function formatMoney(value)
    if number(value) <= 0 then return '-' end
    return '$' .. formatInteger(value)
end

local function safeText(v, fallback)
    if v == nil or v == '' then return fallback or '-' end
    return v:gsub('[\r\n]', ' ')
end

local function setVariable(name, value)
    SKIN:Bang('!SetVariable', name, tostring(value or ''))
end

local function setRestockVisibility(prefix, visible)
    local iconMeter = 'Meter' .. prefix .. 'RestockIcon'
    local textMeter = 'Meter' .. prefix .. 'Restock'
    if visible then
        SKIN:Bang('!ShowMeter', iconMeter)
        SKIN:Bang('!ShowMeter', textMeter)
    else
        SKIN:Bang('!HideMeter', iconMeter)
        SKIN:Bang('!HideMeter', textMeter)
    end
end

local function providerLabel(provider)
    if provider == 'prometheus' then return 'Prometheus' end
    if provider == 'yata' then return 'YATA' end
    if provider == nil or provider == '' or provider == 'none' then return '' end
    return provider
end

local function getStatusPresentation(status)
    if status == 'SAFE_WINDOW' then
        return '86,190,116,255', ''
    elseif status == 'BEST_ODDS' then
        return '232,178,72,255', ''
    elseif status == 'LOW_MARGIN' then
        return '232,178,72,255', ''
    elseif status == 'UNPROFITABLE' or status == 'WINDOW_CLOSED' then
        return '224,90,90,255', ''
    elseif status == 'STALE_DATA' then
        return '232,178,72,255', 'STALE DATA - CHECK WEAV3R'
    elseif status == 'SOURCE_DISAGREEMENT' then
        return '232,178,72,255', 'SOURCE ISSUE - CHECK WEAV3R'
    elseif status == 'PRICE_REGIME_UNVERIFIED' then
        return '232,178,72,255', 'PRICE REGIME UNVERIFIED - CHECK WEAV3R'
    elseif status == 'CHECK_EXTERNAL' then
        return '232,178,72,255', 'CHECK WEAV3R'
    elseif status == 'INSUFFICIENT_HISTORY' then
        return '145,152,164,255', 'LEARNING - CHECK WEAV3R'
    end
    return '145,152,164,255', ''
end

local function getPriceColor(data, prefix, status)
    local profitRaw = data[prefix .. 'TripProfit']
    local marginRaw = data[prefix .. 'TripMarginPercent']
    local hasEconomics = profitRaw ~= nil and profitRaw ~= '' and marginRaw ~= nil and marginRaw ~= ''

    if hasEconomics then
        local profit = number(profitRaw)
        local margin = number(marginRaw)
        if profit <= 0 or margin <= 0 then return '224,90,90,255' end
        if status == 'LOW_MARGIN' then return '232,178,72,255' end
        return '86,190,116,255'
    end

    if status == 'UNPROFITABLE' then return '224,90,90,255' end
    if status == 'LOW_MARGIN' then return '232,178,72,255' end
    return '145,152,164,255'
end

local function updateDestination(data, prefix)
    local now = os.time()
    local travelSeconds = number(data[prefix .. 'TravelSeconds'])
    local stock = number(data[prefix .. 'Stock'])
    local foreignPrice = number(data[prefix .. 'ForeignPrice'])
    local lastSoldOutAt = number(data[prefix .. 'LastSoldOutAt'])
    local restockAt = number(data[prefix .. 'RestockEstimateAt'])
    local windowOpenAt = number(data[prefix .. 'WindowOpenAt'])
    local windowCloseAt = number(data[prefix .. 'WindowCloseAt'])
    local bestDepartureAt = number(data[prefix .. 'BestDepartureAt'])
    local hitRate = number(data[prefix .. 'HitRate'])
    local status = safeText(data[prefix .. 'Status'], 'INSUFFICIENT_HISTORY')
    local message = safeText(data[prefix .. 'Message'], '')
    local statusColor, overlayText = getStatusPresentation(status)

    setVariable(prefix .. 'TravelText', formatDuration(travelSeconds))
    setVariable(prefix .. 'StockText', formatInteger(stock))
    setVariable(prefix .. 'PriceText', formatMoney(foreignPrice))
    setVariable(prefix .. 'PriceColor', getPriceColor(data, prefix, status))
    setVariable(prefix .. 'StatusText', status:gsub('_', ' '))
    setVariable(prefix .. 'StatusColor', statusColor)
    setVariable(prefix .. 'OverlayText', overlayText)

    if stock > 0 then
        setVariable(prefix .. 'StockHeaderText', 'Stock: ' .. formatInteger(stock))
    elseif lastSoldOutAt > 0 then
        setVariable(prefix .. 'StockHeaderText', 'Out of Stock for ' .. formatHoursMinutes(now - lastSoldOutAt) .. ' since ' .. os.date('%H:%M', lastSoldOutAt))
    else
        setVariable(prefix .. 'StockHeaderText', 'Out of Stock')
    end

    local restockText = 'learning'
    local restockEta = 0
    if stock > 0 and restockAt > 0 and restockAt <= now then
        restockText = 'live +' .. formatDuration(now - restockAt)
    elseif restockAt > now then
        restockEta = restockAt - now
        restockText = '~' .. formatDuration(restockEta)
    elseif restockAt > 0 then
        restockText = 'due / variable'
    end
    setVariable(prefix .. 'RestockText', restockText)

    -- Raw restock timing is only directly actionable before departure when the
    -- predicted restock lies farther away than the flight itself. Once stock is
    -- live, or the restock is expected before arrival, the modeled departure /
    -- safe-window result is the cleaner primary signal.
    local showRestock = stock <= 0 and restockEta > 0 and travelSeconds > 0 and restockEta > travelSeconds
    setRestockVisibility(prefix, showRestock)

    local decision = message
    if status == 'SAFE_WINDOW' then
        if windowOpenAt > now then
            decision = 'Window opens in ' .. formatDuration(windowOpenAt - now)
        elseif windowCloseAt > now then
            decision = 'Leave before ' .. formatDuration(windowCloseAt - now)
        else
            decision = 'Window closed'
        end
    elseif status == 'BEST_ODDS' then
        if bestDepartureAt > now then
            decision = 'Leave in ' .. formatDuration(bestDepartureAt - now)
        elseif bestDepartureAt > 0 and bestDepartureAt >= (now - 60) then
            decision = 'LEAVE NOW'
        else
            decision = message ~= '' and message or 'Best window passed'
        end
        if hitRate > 0 then
            decision = decision .. string.format(' | %.0f%% hist.', hitRate * 100)
        end
    elseif status == 'LOW_MARGIN' or status == 'UNPROFITABLE' then
        decision = message ~= '' and message or 'No departure recommendation'
    elseif status == 'STALE_DATA' then
        decision = message ~= '' and message or 'Data stale - check source'
    elseif decision == '' then
        decision = 'Learning - no departure recommendation'
    end

    setVariable(prefix .. 'DecisionText', decision)

    local tooltip = { decision }
    if travelSeconds > 0 then
        table.insert(tooltip, 'Flight ' .. formatDuration(travelSeconds))
    end
    if restockAt > now then
        table.insert(tooltip, 'Restock estimate ' .. formatDuration(restockAt - now) .. ' (' .. os.date('%H:%M', restockAt) .. ')')
    elseif stock > 0 and restockAt > 0 then
        table.insert(tooltip, 'Current restock began ' .. formatShortElapsed(now - restockAt) .. ' ago (' .. os.date('%H:%M', restockAt) .. ')')
    elseif restockAt > 0 then
        table.insert(tooltip, 'Restock estimate due / variable (' .. os.date('%H:%M', restockAt) .. ')')
    end
    if stock <= 0 and lastSoldOutAt > 0 then
        table.insert(tooltip, 'Sold out ' .. formatShortElapsed(now - lastSoldOutAt) .. ' ago (' .. os.date('%H:%M', lastSoldOutAt) .. ')')
    end
    table.insert(tooltip, 'Departure/window timing uses retained availability and depletion history')
    setVariable(prefix .. 'DecisionTooltipText', table.concat(tooltip, ' | '))
end

local function oldestSourceTimestamp(data)
    local uk = number(data.UKSourceTimestamp)
    local jp = number(data.JPSourceTimestamp)
    if uk > 0 and jp > 0 then return math.min(uk, jp) end
    if uk > 0 then return uk end
    if jp > 0 then return jp end
    return 0
end

local function updateHeartbeatText(data, now)
    local remaining = 0
    if nextPollAt ~= nil then remaining = math.max(0, nextPollAt - now) end

    local sourceStatus = safeText(data.UpdatedText, '')
    if sourceStatus:find('failed', 1, true) then
        setVariable('UpdatedText', sourceStatus .. string.format(' | retry %ds', remaining))
        return
    end

    local heartbeat = readEpochFile(heartbeatPath)
    if heartbeat <= 0 then
        setVariable('UpdatedText', string.format('Waiting for first update | next poll %ds', remaining))
        return
    end

    local provider = providerLabel(safeText(data.LiveProvider, ''))
    local sourceTimestamp = oldestSourceTimestamp(data)
    local sourceText = ''
    if provider ~= '' and sourceTimestamp > 0 then
        sourceText = string.format(' | %s %ds old', provider, math.max(0, now - sourceTimestamp))
    elseif provider ~= '' then
        sourceText = ' | ' .. provider
    end

    local age = math.max(0, now - heartbeat)
    if age > (pollInterval * 2) then
        setVariable('UpdatedText', string.format('UPDATE STALE - last %s (%ds ago)%s | retry %ds', os.date('%H:%M:%S', heartbeat), age, sourceText, remaining))
    else
        setVariable('UpdatedText', string.format('Updated %s%s | next poll %ds', os.date('%H:%M:%S', heartbeat), sourceText, remaining))
    end
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

function Update()
    local now = os.time()
    local data = readState()
    local sourceStatus = safeText(data.UpdatedText, '')
    local sourceFailed = sourceStatus:find('failed', 1, true) ~= nil

    if nextPollAt == nil then nextPollAt = now + pollInterval end

    -- One early retry per failure episode. If that retry also fails, retain the
    -- normal cadence until a successful pass clears the failure state.
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

    setVariable('TravelModeText', safeText(data.TravelModeLabel, 'Airstrip'))
    updateHeartbeatText(data, now)
    updateDestination(data, 'UK')
    updateDestination(data, 'JP')
    return 0
end
