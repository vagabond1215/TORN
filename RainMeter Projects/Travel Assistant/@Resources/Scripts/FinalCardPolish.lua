local function trim(value)
    local text=tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
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

local function moneyPattern(value)
    return tostring(value or ''):gsub('%$','\\$')
end

local function parenthesizedMoneyPattern(value)
    return '\\('..moneyPattern(value)..'\\)'
end

local function polishSafeText(index)
    local leave='MeterOpportunity'..index..'Leave'
    local text=meterOption(leave,'Text')
    local remaining=text:match('^SAFE%s*%-%s*LEAVE BEFORE%s+(.+)$')
    if remaining~=nil and trim(remaining)~='' then
        setOption(leave,'Text','SAFE FOR '..trim(remaining))
    end
end

local function polishHeader(index)
    local prefix='MeterOpportunity'..index
    local name=meterOption(prefix..'Name','Text')
    local header=meterOption(prefix..'Gross','Text')
    if name=='' or header=='' then return end

    local cost,mv,profit=header:match('^(.-)%s+MV:(.-)%s+|%s+(.+)$')
    cost=trim(cost or '')
    mv=trim(mv or '')
    profit=trim(profit or '')
    if cost=='' or mv=='' or profit=='' then return end

    local costColor=meterOption(prefix..'Gross','InlineSetting')
    if costColor=='' then costColor='Color | 255,255,255,255' end

    setOption(prefix..'Name','Text',name..' - '..cost..' ('..mv..')')
    setOption(prefix..'Name','X',78)
    setOption(prefix..'Name','W',345)
    setOption(prefix..'Name','ClipString',1)
    setOption(prefix..'Name','FontColor','#Text#')
    setOption(prefix..'Name','InlinePattern',moneyPattern(cost))
    setOption(prefix..'Name','InlineSetting',costColor)
    setOption(prefix..'Name','InlinePattern2',parenthesizedMoneyPattern(mv))
    setOption(prefix..'Name','InlineSetting2','Color | #Muted#')
    setOption(prefix..'Name','ToolTipText','Item - foreign cost (Torn market value)')

    setOption(prefix..'Gross','Text',profit)
    setOption(prefix..'Gross','X',500)
    setOption(prefix..'Gross','W',92)
    setOption(prefix..'Gross','StringAlign','Right')
    setOption(prefix..'Gross','ClipString',1)
    setOption(prefix..'Gross','FontColor','86,190,116,255')
    setOption(prefix..'Gross','InlinePattern','')
    setOption(prefix..'Gross','InlineSetting','')
    setOption(prefix..'Gross','InlinePattern2','')
    setOption(prefix..'Gross','InlineSetting2','')
    setOption(prefix..'Gross','ToolTipText','Profit per item')
end

function Update()
    for i=1,8 do
        polishSafeText(i)
        polishHeader(i)
    end
    return 0
end
