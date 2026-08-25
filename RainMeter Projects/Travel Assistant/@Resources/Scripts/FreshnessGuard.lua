local statePath=nil
local heartbeatPath=nil
local cachePath=nil
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

local function writeKvAtomic(path,data)
    if path==nil or path=='' then return false end
    local keys={}
    for key,_ in pairs(data or {}) do table.insert(keys,key) end
    table.sort(keys)
    local tmp=path..'.tmp'
    local file=io.open(tmp,'w')
    if not file then return false end
    for _,key in ipairs(keys) do
        local value=tostring(data[key] or ''):gsub('[\r\n]',' ')
        file:write(key..'='..value..'\n')
    end
    file:close()
    os.remove(path)
    return os.rename(tmp,path)~=nil
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

local function sourceTimestamps(data)
    local freshest=number(data.UIFreshestMarketSourceTimestamp)
    local oldest=number(data.UIOldestMarketSourceTimestamp)
    local fallback={}
    for _,key in ipairs({'UKSourceTimestamp','JPSourceTimestamp'}) do
        local candidate=number(data[key])
        if candidate>0 then table.insert(fallback,candidate) end
    end
    if freshest<=0 and #fallback>0 then
        freshest=fallback[1]
        for i=2,#fallback do if fallback[i]>freshest then freshest=fallback[i] end end
    end
    if oldest<=0 and #fallback>0 then
        oldest=fallback[1]
        for i=2,#fallback do if fallback[i]<oldest then oldest=fallback[i] end end
    end
    if freshest<=0 and oldest>0 then freshest=oldest end
    if oldest<=0 and freshest>0 then oldest=freshest end
    return freshest,oldest
end

local function opportunityCount(data)
    return math.max(0,math.floor(number(data and data.OpportunityCount)))
end

local function projectionSnapshot(data)
    if opportunityCount(data)<=0 then return nil end
    local out={ OpportunityCount=tostring(opportunityCount(data)) }
    for key,value in pairs(data or {}) do
        if key:match('^Opportunity%d+') then out[key]=value end
    end
    return out
end

local function saveOpportunityCache(data)
    local snapshot=projectionSnapshot(data)
    if snapshot==nil then return false end
    return writeKvAtomic(cachePath,snapshot)
end

local function cachedProjection()
    local cached=readKv(cachePath)
    if opportunityCount(cached)<=0 then return nil end
    return cached
end

local function hasCachedOpportunities(data)
    if opportunityCount(data)>0 then return true end
    return cachedProjection()~=nil
end

local function restoreCachedProjection(data)
    if opportunityCount(data)>0 then return false end
    local cached=cachedProjection()
    if cached==nil then return false end

    for key,value in pairs(cached) do
        if key=='OpportunityCount' or key:match('^Opportunity%d+') then data[key]=value end
    end
    data.OpportunityMessage=''
    if not writeKvAtomic(statePath,data) then return false end

    -- StateReader ran earlier in this update and may already have hidden the rows.
    -- Re-read the merged local projection immediately; later presentation passes
    -- can then refine travel-state labels/tooltips normally.
    SKIN:Bang('!UpdateMeasure','MeasureState')
    SKIN:Bang('!UpdateMeter','*')
    SKIN:Bang('!Redraw')
    return true
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
    -- Rows come from the last evidence-backed opportunity projection. Forecast
    -- timing may continue advancing from retained cycles, but cached stock is not
    -- reclassified as a current provider observation.
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
    cachePath=statePath:gsub('state%.kv$','opportunity-cache.kv')
    if cachePath==statePath then cachePath=statePath..'.opportunity-cache.kv' end
    staleAfter=math.max(60,math.floor(tonumber(SELF:GetOption('StaleAfter','300')) or 300))
    hardStaleAfter=math.max(staleAfter+60,math.floor(tonumber(SELF:GetOption('HardStaleAfter','21600')) or 21600))
    retryInterval=math.max(5,math.floor(tonumber(SELF:GetOption('RetryInterval','15')) or 15))
end

function Update()
    local now=os.time()
    local data=readKv(statePath)

    -- OpportunityState intentionally drops stock older than five minutes. Save the
    -- last non-empty projection separately so an outage cannot erase the only local
    -- forecast we have. A later fresh projection simply replaces this cache.
    if opportunityCount(data)>0 then saveOpportunityCache(data) end

    local freshestAt,oldestAt=sourceTimestamps(data)
    local displayAt=(oldestAt>0) and oldestAt or freshestAt
    local sourceAge=(displayAt>0) and math.max(0,now-displayAt) or math.huge
    local freshestAge=(freshestAt>0) and math.max(0,now-freshestAt) or math.huge
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
    local hardStale=(freshestAt<=0) or (freshestAge>hardStaleAfter) or (not hasCachedOpportunities(data))

    if hardStale then
        setVariable('StockFreshnessMode','hard-stale')
        hideOpportunityRows()
        setVariable('UpdatedText',uiText..'STOCK UNAVAILABLE - '..provider..' '..ageText..' | retry '..tostring(retryRemaining)..'s')
    else
        restoreCachedProjection(data)
        enterDegradedMode()
        setVariable('UpdatedText',uiText..'FORECAST ONLY - '..provider..' '..ageText..' | retry '..tostring(retryRemaining)..'s')
    end

    requestRetry(now)
    return 0
end
