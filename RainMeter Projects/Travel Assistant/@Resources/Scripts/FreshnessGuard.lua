local statePath=nil
local heartbeatPath=nil
local staleAfter=300
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

local function hideOpportunityRows()
    for i=1,8 do
        SKIN:Bang('!HideMeterGroup','OpportunityRow'..i)
        SKIN:Bang('!HideMeter','MeterOpportunity'..i..'InlineGraph')
        SKIN:Bang('!SetOption','MeterOpportunity'..i..'InlineGraph','ImageName','')
        SKIN:Bang('!SetOption','MeterOpportunity'..i..'Graph','Text','v')
    end
    setVariable('PanelHeight',164)
    setVariable('OpportunityMessageText','Foreign stock is stale - waiting for a fresh Prometheus/YATA snapshot')
    SKIN:Bang('!ShowMeter','MeterOpportunityMessage')
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
    heartbeatPath=SKIN:MakePathAbsolute(SELF:GetOption('HeartbeatFile','#@#Generated\\last-update.txt'))
    staleAfter=math.max(60,math.floor(tonumber(SELF:GetOption('StaleAfter','300')) or 300))
    retryInterval=math.max(5,math.floor(tonumber(SELF:GetOption('RetryInterval','15')) or 15))
end

function Update()
    local now=os.time()
    local data=readKv(statePath)
    local sourceAt=sourceTimestamp(data)
    local sourceAge=(sourceAt>0) and math.max(0,now-sourceAt) or math.huge
    local stale=sourceAge>staleAfter
    if not stale then return 0 end

    hideOpportunityRows()

    local heartbeat=readEpoch(heartbeatPath)
    local uiText=''
    if heartbeat>0 then uiText='UI '..os.date('%H:%M:%S',heartbeat)..' | ' end
    local provider=providerLabel(data.LiveProvider)
    local ageText=(sourceAt>0) and (tostring(math.floor(sourceAge))..'s old') or 'age unknown'
    local retryRemaining=math.max(0,retryInterval-(now-lastRetryAt))
    setVariable('UpdatedText',uiText..'STOCK STALE - '..provider..' '..ageText..' | retry '..tostring(retryRemaining)..'s')

    if lastRetryAt<=0 or (now-lastRetryAt)>=retryInterval then
        lastRetryAt=now
        SKIN:Bang('!CommandMeasure','MeasureUpdate','Run')
    end
    return 0
end
