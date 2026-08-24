local statePath = nil

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
    if value <= 0 then return '?' end
    local hours = math.floor(value/3600)
    local minutes = math.floor((value%3600)/60)
    if hours > 0 then return string.format('%dh %dm',hours,minutes) end
    if minutes > 0 then return string.format('%dm',minutes) end
    return '<1m'
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

local function rowFlightText(state,country,defaultTravel)
    local countryId = countryIdsByName[country] or ''
    local travelState = trim(state.TravelState):lower()
    local destinationId = trim(state.TravelDestinationCountryId):lower()
    local timeLeft = number(state.TravelTimeLeft)
    if travelState == 'traveling' and countryId ~= '' and destinationId == countryId and timeLeft > 0 then
        return formatDuration(timeLeft) .. ' left'
    end
    if defaultTravel ~= '' then return defaultTravel end
    return '?'
end

local function statusText(windowText,leaveText)
    local window = trim(windowText)
    local leave = trim(leaveText)
    if window == '' then return leave end
    if leave == '' or leave == window then return window end
    return window .. ' / ' .. leave
end

local function updateRow(index,state)
    local prefix = 'MeterOpportunity'..index
    local rawTitle = meterOption(prefix..'Name','Text')
    if rawTitle == '' then return end

    local country,travel = rowCountryAndTravel(index)
    local itemName = removeCountrySuffix(rawTitle,country)
    local totalProfit = parseMoney(meterOption(prefix..'Gross','Text'))
    local tooltip = meterOption(prefix..'Gross','ToolTipText')
    local quantity = quantityFromTooltip(tooltip)
    local unitProfit = 0
    if quantity > 0 then unitProfit = totalProfit / quantity end

    local equation = formatMoney(unitProfit) .. '/ea'
    if quantity > 0 then
        equation = equation .. ' x' .. tostring(quantity) .. ' = ' .. formatMoney(totalProfit)
    else
        equation = formatMoney(totalProfit)
    end

    local buyPrice = buyPriceFromVisibleText(meterOption(prefix..'Price','Text'))
    local take = 0
    if buyPrice > 0 and quantity > 0 then
        take = math.ceil(buyPrice * quantity * 1.05)
    end

    local window = meterOption(prefix..'Window','Text')
    local leave = meterOption(prefix..'Leave','Text')
    local certainty = meterOption(prefix..'Chance','Text')

    setOption(prefix..'Name','Text',itemName)
    setOption(prefix..'Name','ToolTipText','')
    setOption(prefix..'Gross','Text',equation)
    setOption(prefix..'Gross','ToolTipText','Net profit per item x planned inventory quantity = total net profit')
    setOption(prefix..'Window','Text',rowFlightText(state,country,travel))
    setOption(prefix..'Leave','Text',statusText(window,leave))
    setOption(prefix..'Chance','Text',certainty)
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
end

function Update()
    local state = readKv(statePath)
    for i=1,8 do updateRow(i,state) end
    return 0
end
