local statePath = nil
local heartbeatPath = nil
local pollInterval = 60
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
    setVariable(prefix .. 'StatusText', status:gsub('_', ' '))
    setVariable(prefix .. 'StatusColor', statusColor)
    setVariable(prefix .. 'OverlayText', overlayText)

    if lastSoldOutAt > 0 then
        setVariable(prefix .. 'LastSoldOutText', os.date('%H:%M', lastSoldOutAt))
    else
        setVariable(prefix .. 'LastSoldOutText', '-')
    end

    if stock > 0 and restockAt > 0 and restockAt <= now then
        setVariable(prefix .. 'RestockText', 'live +' .. formatDuration(now - restockAt))
    elseif restockAt > now then
        setVariable(prefix .. 'RestockText', '~' .. formatDuration(restockAt - now))
    elseif restockAt > 0 then
        setVariable(prefix .. 'RestockText', 'due / variable')
    else
        setVariable(prefix .. 'RestockText', 'learning')
    end

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

    local age = math.max(0, now - heartbeat)
    if age > (pollInterval * 2) then
        setVariable('UpdatedText', string.format('UPDATE STALE - last %s (%ds ago) | retry %ds', os.date('%H:%M:%S', heartbeat), age, remaining))
    else
        setVariable('UpdatedText', string.format('Updated %s | next poll %ds', os.date('%H:%M:%S', heartbeat), remaining))
    end
end

function Initialize()
    local configured = SELF:GetOption('StateFile', '#@#Generated\\state.kv')
    local heartbeatConfigured = SELF:GetOption('HeartbeatFile', '#@#Generated\\last-update.txt')
    local configuredPoll = tonumber(SELF:GetOption('PollInterval', '60')) or 60
    if configuredPoll < 15 then configuredPoll = 15 end

    statePath = SKIN:MakePathAbsolute(configured)
    heartbeatPath = SKIN:MakePathAbsolute(heartbeatConfigured)
    pollInterval = math.floor(configuredPoll)
    nextPollAt = os.time() + pollInterval
end

function Update()
    local now = os.time()

    if nextPollAt == nil then nextPollAt = now + pollInterval end
    if now >= nextPollAt then
        nextPollAt = now + pollInterval
        SKIN:Bang('!CommandMeasure', 'MeasureUpdate', 'Run')
    end

    local data = readState()
    setVariable('TravelModeText', safeText(data.TravelModeLabel, 'Airstrip'))
    updateHeartbeatText(data, now)
    updateDestination(data, 'UK')
    updateDestination(data, 'JP')
    return 0
end
