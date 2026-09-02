local statePath=nil
local heartbeatPath=nil
local staleAfter=300
local hardStaleAfter=21600

local function trim(value)
    local text=tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function number(value)
    return tonumber(trim(value)) or 0
end

local function readKv(path)
    local manifest=io.open((path:match('^(.*[\\/])') or '')..'last-update.txt','r'); if manifest then local raw=manifest:read('*a') or ''; manifest:close(); local name=raw:match('^%d+|(ui%-state%-%d+%-%x+%.kv)'); if name then path=(path:match('^(.*[\\/])') or '')..name end end
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
    return tonumber(trim(raw):match('^(%d+)')) or 0
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

local function hideOpportunityRows(message)
    for i=1,8 do
        SKIN:Bang('!HideMeterGroup','OpportunityRow'..i)
        SKIN:Bang('!HideMeter','MeterOpportunity'..i..'InlineGraph')
        SKIN:Bang('!SetOption','MeterOpportunity'..i..'InlineGraph','ImageName','')
    end
    setVariable('PanelHeight',160)
    setVariable('OpportunityMessageText',message or 'Foreign stock is unavailable')
    SKIN:Bang('!ShowMeter','MeterOpportunityMessage')
end

local function enterDegradedMode(data)
    setVariable('StockFreshnessMode','degraded')
    if opportunityCount(data)>0 then
        -- OpportunityState has already converted stale stock evidence into recurring
        -- forecast rows. Keep those cards visible and make the stale source explicit
        -- in the header instead of treating the old stock count as live.
        SKIN:Bang('!HideMeter','MeterOpportunityMessage')
    else
        hideOpportunityRows('No retained-cycle forecast is available from the stale stock evidence - waiting for the normal updater poll')
    end
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
    heartbeatPath=SKIN:MakePathAbsolute(SELF:GetOption('HeartbeatFile','#@#Generated\\last-update.txt'))
    staleAfter=math.max(60,math.floor(tonumber(SELF:GetOption('StaleAfter','300')) or 300))
    hardStaleAfter=math.max(staleAfter+60,math.floor(tonumber(SELF:GetOption('HardStaleAfter','21600')) or 21600))
end

function Update()
    local now=os.time()
    local data=readKv(statePath)
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
    local hardStale=(freshestAt<=0) or (freshestAge>hardStaleAfter)

    if hardStale then
        setVariable('StockFreshnessMode','hard-stale')
        hideOpportunityRows('Foreign stock evidence is over six hours old - waiting for a usable Prometheus/YATA snapshot')
        setVariable('UpdatedText',uiText..'STOCK UNAVAILABLE - '..provider..' '..ageText)
    else
        enterDegradedMode(data)
        setVariable('UpdatedText',uiText..'FORECAST ONLY - '..provider..' '..ageText)
    end

    -- Display-only fence. StateReader owns updater cadence; this measure must never
    -- launch MeasureUpdate from the one-second render loop.
    return 0
end
