local statePath = nil

local function trim(value)
    local text=tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function number(value) return tonumber(value) or 0 end

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

local function meter(name)
    return SKIN:GetMeter(name)
end

local function meterOption(name,option)
    local m=meter(name)
    if m==nil then return '' end
    return trim(m:GetOption(option,''))
end

local function setOption(name,option,value)
    if meter(name)~=nil then SKIN:Bang('!SetOption',name,option,tostring(value or '')) end
end

local function formatMoney(value)
    local rounded=value<0 and -math.floor(math.abs(value)+0.5) or math.floor(value+0.5)
    local negative=rounded<0
    local digits=tostring(math.abs(rounded))
    local out=digits:reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','')
    return (negative and '-$' or '$')..out
end

local function moneyNumber(text)
    local value=trim(text)
    local negative=value:find('%-')~=nil
    value=value:gsub('[^%d]','')
    local n=tonumber(value) or 0
    return negative and -n or n
end

local function parseQuantity(text)
    return tonumber(trim(text):match('(%d+)')) or 0
end

local function normalizeName(value)
    return trim(value):lower():gsub('%s+',' ')
end

local function stripDebugQuantity(value)
    return trim(tostring(value or ''):gsub('%s+%d+%s+qty$',''))
end

local function rowCountry(index)
    local text=meterOption('MeterOpportunity'..index..'Flag','ToolTipText')
    local country=text:match('^(.-)%s*|%s*travel')
    return trim(country or '')
end

local function buildLookup(state)
    local lookup={}
    local count=math.max(0,math.min(256,math.floor(number(state.OpportunityCount))))
    for i=1,count do
        local prefix='Opportunity'..i
        local name=trim(state[prefix..'Name'])
        local country=trim(state[prefix..'Country'])
        if name~='' and country~='' then
            lookup[normalizeName(country)..'|'..normalizeName(name)]={
                name=name,
                quantity=parseQuantity(state[prefix..'QuantityText']),
                price=trim(state[prefix..'PriceText']),
                marketValue=trim(state[prefix..'MarketValueText']),
                gross=number(state[prefix..'GrossValue']),
                priceVaries=trim(state[prefix..'PriceVaries'])=='1',
                minObservedPrice=number(state[prefix..'MinObservedPrice']),
                maxObservedPrice=number(state[prefix..'MaxObservedPrice'])
            }
        end
    end
    return lookup
end

local function clamp(value,minimum,maximum)
    if value<minimum then return minimum end
    if value>maximum then return maximum end
    return value
end

local function mixChannel(a,b,t)
    return math.floor(a+((b-a)*t)+0.5)
end

local function mixColor(a,b,t)
    return string.format('%d,%d,%d,255',mixChannel(a[1],b[1],t),mixChannel(a[2],b[2],t),mixChannel(a[3],b[3],t))
end

local function costColor(row)
    if row==nil or not row.priceVaries then return '255,255,255,255' end
    local cost=moneyNumber(row.price)
    local mv=moneyNumber(row.marketValue)
    if cost<=0 or mv<=0 then return '255,255,255,255' end

    local good={86,190,116}
    local warn={232,178,72}
    local bad={224,90,90}
    local redThreshold=mv/1.05
    if cost>=redThreshold then return '224,90,90,255' end

    local minimum=number(row.minObservedPrice)
    if minimum<=0 then minimum=math.min(cost,redThreshold*0.5) end
    if minimum>=redThreshold then return '224,90,90,255' end

    -- Item-specific scale: the lowest retained purchase cost is green; the point
    -- where MV is only 5% above cost is red. Yellow is the midpoint between them.
    local t=clamp((cost-minimum)/(redThreshold-minimum),0,1)
    if t<=0.5 then return mixColor(good,warn,t*2) end
    return mixColor(warn,bad,(t-0.5)*2)
end

local function configureInfo(index,tooltip)
    local prefix='MeterOpportunity'..index
    local info=prefix..'Info'
    local chance=prefix..'Chance'
    local leave=prefix..'Leave'
    local text=trim(tooltip)
    local show=text~=''

    setOption(info,'ImageAlpha',show and 255 or 0)
    setOption(info,'ToolTipTitle','Window calculation')
    setOption(info,'ToolTipText',text)
    setOption(info,'ToolTipHidden',show and 0 or 1)
    setOption(info,'ToolTipWidth',420)
    setOption(info,'DynamicVariables',1)

    -- Keep the departure text itself hoverable. The image meter is the stable
    -- fallback target and avoids Unicode/font encoding issues entirely.
    setOption(leave,'ToolTipTitle','Window calculation')
    setOption(leave,'ToolTipText',text)
    setOption(leave,'ToolTipHidden',show and 0 or 1)
    setOption(leave,'ToolTipWidth',420)
    setOption(leave,'DynamicVariables',1)
    setOption(leave,'SolidColor','0,0,0,1')

    if meterOption(leave,'Text'):match('^SAFE') then
        setOption(chance,'Text','')
        setOption(chance,'FontFace','Segoe UI')
    end
end

local function applyHeader(index,lookup)
    local prefix='MeterOpportunity'..index
    local currentName=stripDebugQuantity(meterOption(prefix..'Name','Text'))
    if currentName=='' then return end
    local country=rowCountry(index)
    local row=lookup[normalizeName(country)..'|'..normalizeName(currentName)]
    if row==nil then return end

    local quantity=row.quantity
    local unitProfit=(quantity>0) and (row.gross/quantity) or row.gross
    setOption(prefix..'Name','Text',currentName)
    setOption(prefix..'Name','X',78)
    setOption(prefix..'Name','W',153)
    setOption(prefix..'Name','ClipString',1)

    local cost=row.price~='' and row.price or '?'
    local mv=row.marketValue~='' and row.marketValue or '?'
    local header=cost..'   MV:'..mv..' | '..formatMoney(unitProfit)
    setOption(prefix..'Gross','Text',header)
    setOption(prefix..'Gross','X',235)
    setOption(prefix..'Gross','W',293)
    setOption(prefix..'Gross','StringAlign','Left')
    setOption(prefix..'Gross','ClipString',1)
    setOption(prefix..'Gross','FontColor','#Text#')
    setOption(prefix..'Gross','InlinePattern','^-?\\$[0-9,]+')
    setOption(prefix..'Gross','InlineSetting','Color | '..costColor(row))
    setOption(prefix..'Gross','InlinePattern2','-?\\$[0-9,]+$')
    setOption(prefix..'Gross','InlineSetting2','Color | 86,190,116,255')
    setOption(prefix..'Gross','ToolTipText','Foreign cost per item | Torn market value per item | profit per item')
end

local function applySecondLine(index)
    local prefix='MeterOpportunity'..index
    setOption(prefix..'Window','X',78); setOption(prefix..'Window','W',65)
    setOption(prefix..'Leave','X',145); setOption(prefix..'Leave','W',154)
    setOption(prefix..'Info','X',303); setOption(prefix..'Info','W',12); setOption(prefix..'Info','H',12)
    local leaveY=tonumber(meterOption(prefix..'Leave','Y')) or 0
    if leaveY>0 then setOption(prefix..'Info','Y',math.floor(leaveY+1)) end
    setOption(prefix..'Chance','X',319); setOption(prefix..'Chance','W',44); setOption(prefix..'Chance','ClipString',1)
    setOption(prefix..'Price','X',367); setOption(prefix..'Price','W',143)
end

local function shiftMeterY(name,delta)
    local m=meter(name)
    if m==nil then return end
    local y=tonumber(m:GetOption('Y','0')) or 0
    setOption(name,'Y',math.floor(y+delta))
end

local function applyExpandedGraphGeometry()
    local expanded=0
    for i=1,8 do
        if meterOption('MeterOpportunity'..i..'Graph','Text')=='^' then expanded=i break end
    end
    if expanded<=0 then return end

    local card='MeterOpportunity'..expanded..'Card'
    local currentH=tonumber(meterOption(card,'H')) or 0
    if currentH>=180 then return end

    setOption(card,'H',183)
    setOption(card,'Shape','Rectangle 0,0,536,183,5 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#')

    for i=expanded+1,8 do
        local p='MeterOpportunity'..i
        for _,suffix in ipairs({'Card','Flag','Name','Gross','Window','Leave','Info','Chance','Price','Graph','InlineGraph'}) do
            shiftMeterY(p..suffix,25)
        end
    end

    local panel=tonumber(SKIN:GetVariable('PanelHeight','164')) or 164
    SKIN:Bang('!SetVariable','PanelHeight',tostring(math.floor(panel+25)))
end

local function applyGraphSize(index)
    local graph='MeterOpportunity'..index..'InlineGraph'
    setOption(graph,'X',12)
    setOption(graph,'W',528)
    setOption(graph,'H',125)
    setOption(graph,'PreserveAspectRatio',1)
end

function Initialize()
    statePath=SKIN:MakePathAbsolute(SELF:GetOption('StateFile','#@#Generated\\state.kv'))
    for i=1,8 do
        applySecondLine(i)
        applyGraphSize(i)
    end
end

function Update()
    local state=readKv(statePath)
    local lookup=buildLookup(state)
    for i=1,8 do
        applyHeader(i,lookup)
        applySecondLine(i)
        applyGraphSize(i)
        local prefix='MeterOpportunity'..i
        local tooltip=meterOption(prefix..'Leave','ToolTipText')
        if tooltip=='' then tooltip=meterOption(prefix..'Chance','ToolTipText') end
        configureInfo(i,tooltip)
    end
    applyExpandedGraphGeometry()
    return 0
end
