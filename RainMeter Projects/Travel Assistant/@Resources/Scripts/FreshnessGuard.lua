local statePath=nil
local heartbeatPath=nil
local staleAfter=300
local hardStaleAfter=21600
local retryInterval=15
local lastRetryAt=0

local function trim(value)
    local text=tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function number(value)
    return tonumber(trim(value)) or 0
end

local function readKv(path)
    local out={}
    local file=io.open(path,'r')
    if not file then return out end
    for line in file:lines() do
        local key,value=line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)]=trim(value) end
    end
    file:close()
    return out
end

local function readEpoch(path)
    local file=io.open(path,'r')
    if not file then return 0 end
    local raw=file:read('*a') or ''
    file:close()
    return number(raw)
end

local function setVariable(name,value)
    SKIN:Bang('!SetVariable',name,tostring(value or ''))
end

local function providerLabel(value)
    local text=trim(value):lower()
    if text=='prometheus' then return 'Prometheus' end
    if text=='yata' then return 'YATA' end
    if text~='' then return trim(value) end
    return 'provider'
end

local function formatAge(seconds)
    if seconds==math.huge then return 'age unknown' end
    local value=math.max(0,math.floor(number(seconds)))
    if value<60 then return tostring(value)..'s old' end
    local hours=math.floor(value/3600)
    local minutes=math.floor((value%3600)/60)
    if hours>0 then return string.format('%dh %dm old',hours,minutes) end
    return tostring(minutes)..'m old'
end

local function sourceTimestamp(data)
    local value=number(data.UIFreshestMarketSourceTimestamp)
    if value>0 then return value end
    value=number(data.UIOldestMarketSourceTimestamp)
    if value>0 then return value end
    local best=0
    for _,key in ipairs({'UKSourceTimestamp','JPSourceTimestamp'}) do
        local candidate=number(data[key])
        if candidate>best then best=candidate end
    end
    return best
end

local function hasCachedOpportunities(data)
    return math.floor(number(data.OpportunityCount))>0
end

local function hideOpportunityRows()
    for i=1,8 do
        SKIN:Bang('!HideMeterGroup','OpportunityRow'..i)
        SKIN:Bang('!HideMeter','MeterOpportunity'..i..'InlineGraph')
        SKIN:Bang('!SetOption','MeterOpportunity'..i..'InlineGraph','ImageName','')
        SKIN:Bang('!SetOption','MeterOpportunity'..i..'Graph','Text','v')
    end
    setVariable('PanelHeight',164)
    setVariable('OpportunityMessageText','Foreign stock cache is too old - waiting for a usable Prometheus/YATA snapshot')
    SKIN:Bang('!ShowMeter','MeterOpportunityMessage')
end

local function enterDegradedMode()
    setVariable('StockFreshnessMode','degraded')
    -- Keep the already-rendered opportunity rows. They are forecast output based on
    -- retained evidence, not a claim that the cached stock count is still live.
    SKIN:Bang('!HideMeter','MeterOpportunityMessage')
end

local function requestRetry(now)
    if lastRetryAt<=0 or (now-lastRetryAt)>=retryInterval then
        lastRetryAt=now
        SKIN:Bang('!CommandMeasure','MeasureUpdate','Run')
    end
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
    heartbeatPath=SKIN:MakePathAbsolute(SELF:GetOption('HeartbeatFile','#@#Generated\\last-update.txt'))
    staleAfter=math.max(60,math.floor(tonumber(SELF:GetOption('StaleAfter','300')) or 300))
    hardStaleAfter=math.max(staleAfter+60,math.floor(tonumber(SELF:GetOption('HardStaleAfter','21600')) or 21600))
    retryInterval=math.max(5,math.floor(tonumber(SELF:GetOption('RetryInterval','15')) or 15))
end

function Update()
    local now=os.time()
    local data=readKv(statePath)
    local sourceAt=sourceTimestamp(data)
    local sourceAge=(sourceAt>0) and math.max(0,now-sourceAt) or math.huge
    local stale=sourceAge>staleAfter
    if not stale then
        setVariable('StockFreshnessMode','fresh')
        return 0
    end

    local heartbeat=readEpoch(heartbeatPath)
    local uiText=''
    if heartbeat>0 then uiText='UI '..os.date('%H:%M:%S',heartbeat)..' | ' end
    local provider=providerLabel(data.LiveProvider)
    local ageText=formatAge(sourceAge)
    local retryRemaining=math.max(0,retryInterval-(now-lastRetryAt))
    local hardStale=(sourceAt<=0) or (sourceAge>hardStaleAfter) or (not hasCachedOpportunities(data))

    if hardStale then
        setVariable('StockFreshnessMode','hard-stale')
        hideOpportunityRows()
        setVariable('UpdatedText',uiText..'STOCK UNAVAILABLE - '..provider..' '..ageText..' | retry '..tostring(retryRemaining)..'s')
    else
        enterDegradedMode()
        setVariable('UpdatedText',uiText..'FORECAST ONLY - '..provider..' '..ageText..' | retry '..tostring(retryRemaining)..'s')
    end

    requestRetry(now)
    return 0
end
