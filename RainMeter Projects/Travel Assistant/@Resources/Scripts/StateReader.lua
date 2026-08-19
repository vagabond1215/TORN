local statePath = nil

local function trim(s)
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
    if number(value) <= 0 then return '—' end
    return '$' .. formatInteger(value)
end

local function safeText(v, fallback)
    if v == nil or v == '' then return fallback or '—' end
    return v:gsub('[\r\n]', ' ')
end

local function setVariable(name, value)
    SKIN:Bang('!SetVariable', name, tostring(value or ''))
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

    setVariable(prefix .. 'TravelText', formatDuration(travelSeconds))
    setVariable(prefix .. 'StockText', formatInteger(stock))
    setVariable(prefix .. 'PriceText', formatMoney(foreignPrice))
    setVariable(prefix .. 'StatusText', status:gsub('_', ' '))

    if lastSoldOutAt > 0 then
        setVariable(prefix .. 'LastSoldOutText', os.date('%H:%M', lastSoldOutAt))
    else
        setVariable(prefix .. 'LastSoldOutText', '—')
    end

    if restockAt > now then
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
            decision = decision .. string.format('  ·  %.0f%% hist.', hitRate * 100)
        end
    elseif status == 'LOW_MARGIN' or status == 'UNPROFITABLE' then
        decision = message ~= '' and message or 'No departure recommendation'
    elseif status == 'STALE_DATA' then
        decision = message ~= '' and message or 'Data stale — check source'
    elseif decision == '' then
        decision = 'Learning — no departure recommendation'
    end

    setVariable(prefix .. 'DecisionText', decision)
end

function Initialize()
    local configured = SELF:GetOption('StateFile', '#@#Generated\\state.kv')
    statePath = SKIN:MakePathAbsolute(configured)
end

function Update()
    local data = readState()
    setVariable('TravelModeText', safeText(data.TravelModeLabel, 'Airstrip'))
    setVariable('UpdatedText', safeText(data.UpdatedText, 'Waiting for first update…'))
    updateDestination(data, 'UK')
    updateDestination(data, 'JP')
    return 0
end
