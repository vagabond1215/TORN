local generatedDir=nil
local bandCount=48
local lastRequestedKey=''
local lastRequestedAt=0

local function trim(value)
    local text=tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function number(value) return tonumber(value) or 0 end

local function meter(name) return SKIN:GetMeter(name) end

local function meterOption(name,option)
    local m=meter(name)
    if m==nil then return '' end
    return trim(m:GetOption(option,''))
end

local function setOption(name,option,value)
    if meter(name)~=nil then SKIN:Bang('!SetOption',name,option,tostring(value or '')) end
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

local function safeFileKey(key)
    return trim(key):gsub('[^%w_-]','_')
end

local function specPath(key)
    if generatedDir==nil or key=='' then return '' end
    return generatedDir..'inline-graph-'..safeFileKey(key)..'.kv'
end

local function hideAll()
    for i=1,bandCount do
        SKIN:Bang('!HideMeter',string.format('MeterGraphHover%02d',i))
    end
end

local function expandedRow()
    for i=1,8 do
        if meterOption('MeterOpportunity'..i..'Graph','GraphExpanded')=='1' then return i end
    end
    return 0
end

local function formatNumber(value)
    local n=math.floor(math.max(0,number(value))+0.5)
    local digits=tostring(n)
    return digits:reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','')
end

local function tooltipFor(sample)
    local timestamp,stock,known=tostring(sample or ''):match('^(%d+)|([^|]*)|([01])$')
    if timestamp==nil then return '' end
    local timeText=os.date('%H:%M',number(timestamp))
    if known~='1' then return 'Time: '..timeText..'#CRLF#Stock: unknown' end
    return 'Time: '..timeText..'#CRLF#Stock: '..formatNumber(stock)
end

local function requestHoverData(key)
    local now=os.time()
    if key==lastRequestedKey and (now-lastRequestedAt)<3 then return end
    lastRequestedKey=key
    lastRequestedAt=now
    SKIN:Bang('!SetVariable','GraphHoverMarketKey',key)
    SKIN:Bang('!UpdateMeasure','MeasureGraphHoverData')
    SKIN:Bang('!CommandMeasure','MeasureGraphHoverData','Run')
end

function Initialize()
    generatedDir=SKIN:MakePathAbsolute('#@#Generated\\')
    hideAll()
end

function Update()
    local row=expandedRow()
    local key=trim(SKIN:GetVariable('InlineGraphMarketKey',''))
    if row<=0 or key=='' then hideAll(); return 0 end

    local spec=readKv(specPath(key))
    if trim(spec.MarketKey)~=key or number(spec.HoverCount)~=bandCount then
        hideAll()
        requestHoverData(key)
        return 0
    end

    local graph='MeterOpportunity'..row..'InlineGraph'
    local graphX=number(meterOption(graph,'X'))
    local graphY=number(meterOption(graph,'Y'))
    -- RenderInlineGraph.ps1 uses a 34..522 x 8..98 plot inside a 528x125 image.
    local plotX=graphX+34
    local plotY=graphY+8
    local plotW=488
    local plotH=90

    for i=1,bandCount do
        local name=string.format('MeterGraphHover%02d',i)
        local left=math.floor(plotX+(plotW*(i-1)/bandCount)+0.5)
        local right=math.floor(plotX+(plotW*i/bandCount)+0.5)
        local width=math.max(1,right-left)
        local tip=tooltipFor(spec[string.format('Hover%02d',i)])
        setOption(name,'X',left)
        setOption(name,'Y',plotY)
        setOption(name,'Shape','Rectangle 0,0,'..width..','..plotH..' | Fill Color 0,0,0,1 | StrokeWidth 0')
        setOption(name,'ToolTipText',tip)
        if tip=='' then SKIN:Bang('!HideMeter',name) else SKIN:Bang('!ShowMeter',name) end
    end
    return 0
end
