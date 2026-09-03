local function hideRetiredCardMeters()
    -- The split Window meter remains retired. Chance is now a live dedicated
    -- centered field owned by CardPresenter / travel-state presentation, so this
    -- later compatibility pass must never hide it.
    for i=1,8 do
        SKIN:Bang('!HideMeter','MeterOpportunity'..i..'Window')
    end
end

function Initialize()
    hideRetiredCardMeters()
end

function Update()
    hideRetiredCardMeters()
    return 0
end
