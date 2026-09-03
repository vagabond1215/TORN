local function trim(value)
    local text=tostring(value or '')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function meterText(name)
    local meter=SKIN:GetMeter(name)
    if meter==nil then return '' end
    return trim(meter:GetOption('Text',''))
end

local function setText(name,value)
    if SKIN:GetMeter(name)~=nil then
        SKIN:Bang('!SetOption',name,'Text',tostring(value or ''))
    end
end

local function hasAuthoritativeChance(text)
    local raw=trim(text)
    local value=tonumber(raw:match('^(%d+)%%$'))
    return value~=nil and value>=0 and value<=100
end

local function isNonInformativeAction(text)
    local value=trim(text):lower()
    if value=='' then return true end
    if value=='wait data' or value=='market data pending' or value=='next cycle unavailable' or value=='window closed.' then return true end
    if value:find('collecting data',1,true)~=nil then return true end
    return false
end

function Update()
    -- CardPresenter / travel-state presentation own the action and Chance meters.
    -- This final pass enforces one cross-field invariant only: an authoritative
    -- visible probability cannot coexist with a non-informative WAIT DATA-style
    -- action. The percentage already passed the upstream probability authority;
    -- replace only the contradictory action label and touch no geometry/model state.
    for i=1,8 do
        local prefix='MeterOpportunity'..tostring(i)
        local chance=meterText(prefix..'Chance')
        local action=meterText(prefix..'Leave')
        if hasAuthoritativeChance(chance) and isNonInformativeAction(action) then
            setText(prefix..'Leave','Chance to hit:')
        end
    end
    return 0
end
