Set-StrictMode -Version 2.0

function Get-TravelProfile {
    param(
        [object]$BaseSettings,
        [object]$LocalSettings
    )

    $profile = [pscustomobject]@{
        companyType = 'none'
        companyStars = 0
        factionExcursionLevel = 0
        factionTravelCostLevel = 0
    }

    foreach ($source in @($BaseSettings, $LocalSettings)) {
        if ($null -eq $source -or -not $source.PSObject.Properties['travelProfile'] -or $null -eq $source.travelProfile) { continue }
        foreach ($name in @('companyType','companyStars','factionExcursionLevel','factionTravelCostLevel')) {
            $prop = $source.travelProfile.PSObject.Properties[$name]
            if ($null -eq $prop) { continue }
            $profile.PSObject.Properties[$name].Value = $prop.Value
        }
    }

    $profile.companyType = [string]$profile.companyType
    if ([string]::IsNullOrWhiteSpace($profile.companyType)) { $profile.companyType = 'none' }
    $profile.companyStars = [Math]::Max(0, [Math]::Min(10, [int]$profile.companyStars))
    $profile.factionExcursionLevel = [Math]::Max(0, [Math]::Min(10, [int]$profile.factionExcursionLevel))
    $profile.factionTravelCostLevel = [Math]::Max(0, [Math]::Min(5, [int]$profile.factionTravelCostLevel))
    return $profile
}

function Get-TravelProfileEffects {
    param(
        [Parameter(Mandatory = $true)][object]$Profile,
        [Parameter(Mandatory = $true)][object]$PerksConfig,
        [object]$Item
    )

    $generalCapacityBonus = 0
    $itemCapacityBonus = 0
    $freeBusinessClass = $false
    $notes = New-Object System.Collections.Generic.List[string]

    $company = @($PerksConfig.companies | Where-Object { [string]$_.id -eq [string]$Profile.companyType } | Select-Object -First 1)
    if ($company.Count -gt 0) {
        foreach ($effect in @($company[0].effects)) {
            $requiredStars = 0
            if ($effect.PSObject.Properties['stars']) { $requiredStars = [int]$effect.stars }
            if ([int]$Profile.companyStars -lt $requiredStars) { continue }

            if ($effect.PSObject.Properties['generalCapacityBonus']) {
                $generalCapacityBonus += [int]$effect.generalCapacityBonus
            }
            if ($effect.PSObject.Properties['freeBusinessClass'] -and [bool]$effect.freeBusinessClass) {
                $freeBusinessClass = $true
            }
            if ($null -ne $Item -and $effect.PSObject.Properties['itemCategory'] -and $effect.PSObject.Properties['itemCapacityBonus']) {
                $itemCategory = ''
                if ($Item.PSObject.Properties['category']) { $itemCategory = [string]$Item.category }
                if ([string]$effect.itemCategory -eq $itemCategory) {
                    $itemCapacityBonus += [int]$effect.itemCapacityBonus
                }
            }
            if ($effect.PSObject.Properties['label'] -and -not [string]::IsNullOrWhiteSpace([string]$effect.label)) {
                $notes.Add([string]$effect.label)
            }
        }
    }

    $factionCapacity = 0
    $travelCostReductionPercent = 0
    if ($PerksConfig.PSObject.Properties['faction'] -and $null -ne $PerksConfig.faction) {
        if ($PerksConfig.faction.PSObject.Properties['excursionCapacity']) {
            $perLevel = [int]$PerksConfig.faction.excursionCapacity.capacityPerLevel
            $maxLevel = [int]$PerksConfig.faction.excursionCapacity.maxLevel
            $level = [Math]::Max(0, [Math]::Min($maxLevel, [int]$Profile.factionExcursionLevel))
            $factionCapacity = $level * $perLevel
        }
        if ($PerksConfig.faction.PSObject.Properties['travelCost']) {
            $perLevel = [int]$PerksConfig.faction.travelCost.reductionPercentPerLevel
            $maxLevel = [int]$PerksConfig.faction.travelCost.maxLevel
            $maxPercent = [int]$PerksConfig.faction.travelCost.maxReductionPercent
            $level = [Math]::Max(0, [Math]::Min($maxLevel, [int]$Profile.factionTravelCostLevel))
            $travelCostReductionPercent = [Math]::Min($maxPercent, $level * $perLevel)
        }
    }

    if ($factionCapacity -gt 0) { $notes.Add(('Faction travel capacity +{0}' -f $factionCapacity)) }
    if ($travelCostReductionPercent -gt 0) { $notes.Add(('Faction travel fee -{0}%' -f $travelCostReductionPercent)) }

    return [pscustomobject]@{
        generalCapacityBonus = $generalCapacityBonus
        itemCapacityBonus = $itemCapacityBonus
        factionCapacityBonus = $factionCapacity
        totalCapacityBonus = ($generalCapacityBonus + $itemCapacityBonus + $factionCapacity)
        travelCostReductionPercent = $travelCostReductionPercent
        freeBusinessClass = $freeBusinessClass
        notes = $notes.ToArray()
    }
}

function Get-AvailableTravelModeIds {
    param(
        [Parameter(Mandatory = $true)][object]$TravelModes,
        [Parameter(Mandatory = $true)][object]$Effects
    )

    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($mode in @($TravelModes.modes)) {
        $id = [string]$mode.id
        if ($mode.enabled -eq $true) {
            $ids.Add($id)
            continue
        }
        if ($id -eq 'business' -and [bool]$Effects.freeBusinessClass) {
            $ids.Add($id)
        }
    }
    return $ids.ToArray()
}

function Get-EffectiveTravelEconomics {
    param(
        [Parameter(Mandatory = $true)][object]$Country,
        [Parameter(Mandatory = $true)][string]$TravelMode,
        [Parameter(Mandatory = $true)][object]$Effects,
        [int]$CapacityOverride = 0
    )

    $travelCostKnown = $false
    $travelCost = 0L
    $rawTravelCost = $null
    if ($Country.PSObject.Properties['travelCosts']) {
        $rawProp = $Country.travelCosts.PSObject.Properties[$TravelMode]
        if ($null -ne $rawProp) { $rawTravelCost = $rawProp.Value }
    }

    if ($TravelMode -eq 'business') {
        if ([bool]$Effects.freeBusinessClass) {
            $travelCostKnown = $true
            $travelCost = 0L
        }
    } elseif ($null -ne $rawTravelCost) {
        $travelCostKnown = $true
        $travelCost = [long]$rawTravelCost
    }

    if ($travelCostKnown -and $travelCost -gt 0 -and [int]$Effects.travelCostReductionPercent -gt 0) {
        $factor = 1.0 - ([double]$Effects.travelCostReductionPercent / 100.0)
        if ($factor -lt 0) { $factor = 0 }
        $travelCost = [long][Math]::Ceiling($travelCost * $factor)
    }

    $baseCapacity = 0
    if ($Country.PSObject.Properties['baseTravelCapacity']) {
        $capacityProp = $Country.baseTravelCapacity.PSObject.Properties[$TravelMode]
        if ($null -ne $capacityProp) { $baseCapacity = [int]$capacityProp.Value }
    }

    $capacity = 0
    if ($CapacityOverride -gt 0) {
        $capacity = $CapacityOverride
    } elseif ($baseCapacity -gt 0) {
        $capacity = $baseCapacity + [int]$Effects.totalCapacityBonus
    }

    return [pscustomobject]@{
        travelCostKnown = $travelCostKnown
        travelCost = $travelCost
        baseCapacity = $baseCapacity
        capacity = $capacity
    }
}
