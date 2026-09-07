local function trim(value)
    local text=tostring(value or '')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function meterOption(name,option)
    local meter=SKIN:GetMeter(name)
    if meter==nil then return '' end
    return trim(meter:GetOption(option,''))
end

local function meterText(name)
    return meterOption(name,'Text')
end

local function setText(name,value)
    if SKIN:GetMeter(name)~=nil then
        SKIN:Bang('!SetOption',name,'Text',tostring(value or ''))
    end
end

local function numericPercent(text)
    local raw=trim(text)
    return tonumber(raw:match('^([%+%-]?[%d%.]+)%%$'))
end

local function hasAuthoritativeChance(text)
    local value=numericPercent(text)
    return value~=nil and value>=0 and value<=100
end

local function suppressChance(prefix)
    setText(prefix..'Chance','')
    if SKIN:GetMeter(prefix..'Chance')~=nil then SKIN:Bang('!HideMeter',prefix..'Chance') end
    if SKIN:GetMeter(prefix..'Leave')~=nil then SKIN:Bang('!SetOption',prefix..'Leave','W','263') end
end

local function sanitizeChance(prefix,text)
    local raw=trim(text)
    local value=numericPercent(raw)
    if value==nil then return raw end

    -- A probability above 100% (or below 0%) is a producer/model invariant
    -- violation, not a special confidence state. Do not turn it into a plausible
    -- looking value at presentation time; suppress it until the next valid update.
    if value<0 or value>100 then
        suppressChance(prefix)
        return ''
    end

    local normalized=string.format('%.0f%%',value)
    if normalized~=raw then setText(prefix..'Chance',normalized) end
    return normalized
end

local function descriptiveAction(text)
    local raw=trim(text)
    local lower=raw:lower()
    for _,status in ipairs({'in stock','window open'}) do
        local prefix=status..' / leave '
        if lower:sub(1,#prefix)==prefix then
            local remainder=trim(raw:sub(#prefix+1))
            if remainder:lower()=='now' then
                return status=='in stock' and 'In stock, leave now' or 'Window open, leave now'
            end
            if remainder:lower():find('before:',1,true)==1 then
                return (status=='in stock' and 'In stock, leave ' or 'Window open, leave ')..remainder
            end
            return (status=='in stock' and 'In stock, leave before: ' or 'Window open, leave before: ')..remainder
        end
    end
    return raw
end

local function isNonInformativeAction(text)
    local value=trim(text):lower()
    if value=='' then return true end
    if value=='wait data' or value=='market data pending' or value=='next cycle unavailable' or value=='window closed.' then return true end
    if value:find('collecting data',1,true)~=nil then return true end
    return false
end

local function rowIdentity(prefix)
    local name=meterText(prefix..'Name'):lower()
    if name=='' then return '' end
    local country=meterOption(prefix..'Flag','ToolTipText'):lower()
    return name..'|'..country
end

local function chanceOutsideAuthoritativePanel(prefix,panelHeight)
    if panelHeight<=0 then return false end
    local meter=SKIN:GetMeter(prefix..'Chance')
    if meter==nil then return false end
    local y=tonumber(meter:GetY()) or 0
    -- StateReader leaves at least the footer gap below the last visible card body.
    -- A Chance meter at or below this fence belongs to a stale physical row slot.
    return y>=(panelHeight-24)
end

function Update()
    -- FreshnessGuard runs after StateReader/CardPresenter and before the travel pass.
    -- Preserve the height it observed so TravelStateWindowTweaks cannot resurrect a
    -- stale old-row height by scanning retained hidden Name text.
    local authoritativePanelHeight=tonumber(SKIN:GetVariable('AuthoritativePanelHeight','0')) or 0
    if authoritativePanelHeight>0 then
        SKIN:Bang('!SetVariable','PanelHeight',tostring(math.floor(authoritativePanelHeight)))
    end

    -- CardPresenter / travel-state presentation own the action and Chance meters.
    -- This final pass enforces cross-field presentation invariants and also fences
    -- stale physical row slots. Hidden rows retain meter options after a reflow, so
    -- a later !ShowMeter on Chance must not be allowed to escape its hidden group.
    local seenRows={}
    for i=1,8 do
        local prefix='MeterOpportunity'..tostring(i)
        local identity=rowIdentity(prefix)
        local stalePhysicalSlot=(identity=='' or seenRows[identity]==true or chanceOutsideAuthoritativePanel(prefix,authoritativePanelHeight))
        if stalePhysicalSlot then
            suppressChance(prefix)
        else
            seenRows[identity]=true
            local chance=sanitizeChance(prefix,meterText(prefix..'Chance'))
            local action=descriptiveAction(meterText(prefix..'Leave'))
            setText(prefix..'Leave',action)

            if hasAuthoritativeChance(chance) and isNonInformativeAction(action) then
                setText(prefix..'Leave','Chance to hit:')
            end
        end
    end
    return 0
end
