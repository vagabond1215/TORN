local function hideRetiredCardMeters()
    -- The compact card no longer uses the legacy info glyph, split Window meter,
    -- or separate Chance column. StateReader owns geometry; CardPresenter owns text.
    for i=1,8 do
        SKIN:Bang('!HideMeter','MeterOpportunity'..i..'Info')
        SKIN:Bang('!HideMeter','MeterOpportunity'..i..'Window')
        SKIN:Bang('!HideMeter','MeterOpportunity'..i..'Chance')
    end
end

function Initialize()
    hideRetiredCardMeters()
end

function Update()
    hideRetiredCardMeters()
    return 0
end
