local compactOffset = 32
local rowSuffixes = {
    'Card','Flag','FlagMask','CardBorder','ItemImage','Name','DetailEachLabel','Gross','DetailEachNet','DetailEachTax','DetailEachProfitHour','DetailTotalLabel','DetailTotal','DetailTotalNet','DetailTotalTax','DetailTotalProfitHour','Window','Leave','Chance','Price','Take','Make','DetailToggle','Graph','InlineGraph'
}

local function meterY(name)
    local meter=SKIN:GetMeter(name)
    if meter==nil then return nil end
    return tonumber(meter:GetOption('Y','0'))
end

local function shiftMeterY(name,delta)
    local y=meterY(name)
    if y==nil then return end
    SKIN:Bang('!SetOption',name,'Y',tostring(math.floor(y+delta)))
end

function Initialize()
end

function Update()
    -- StateReader owns row layout and uses the historical 120px list origin.
    -- Only compact a freshly-laid-out stack. Once shifted to 88px, leave it
    -- untouched so this presentation pass can never accumulate offsets.
    local firstY=meterY('MeterOpportunity1Card')
    if firstY==nil or firstY<120 then return 0 end

    for i=1,8 do
        local prefix='MeterOpportunity'..i
        for _,suffix in ipairs(rowSuffixes) do
            shiftMeterY(prefix..suffix,-compactOffset)
        end
    end

    local panel=tonumber(SKIN:GetVariable('PanelHeight','164')) or 164
    SKIN:Bang('!SetVariable','PanelHeight',tostring(math.max(160,math.floor(panel-compactOffset))))
    return 0
end
