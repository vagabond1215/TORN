Set-StrictMode -Version 2.0

function New-TravelCategoryBonusMap {
    return [pscustomobject]@{ Flower = 0; Plushie = 0 }
}

function New-TravelCategoryResolvedMap {
    return [pscustomobject]@{ Flower = $false; Plushie = $false }
}

function Get-TravelCategoryMapValue {
    param([object]$Map, [string]$Category, $DefaultValue)
    if ($null -eq $Map -or [string]::IsNullOrWhiteSpace($Category)) { return $DefaultValue }
    $prop = $Map.PSObject.Properties[$Category]
    if ($null -eq $prop) { return $DefaultValue }
    return $prop.Value
}

function Get-TravelProfile {
    param(
        [object]$BaseSettings,
        [object]$LocalSettings
    )

    $profile = [pscustomobject]@{
        companyType = 'none'
        companyStars = 0
        currentCapacityKnown = $false
        currentCapacityMode = ''
        currentCapacity = 0
        currentCapacityBonus = 0
        currentCategoryCapacityBonuses = New-TravelCategoryBonusMap
        currentCategoryCapacityResolved = New-TravelCategoryResolvedMap
        currentCapacitySyncedAt = 0
        factionState = 'manual'
        factionExcursionLevel = 0
        factionTravelCostLevel = 0
        factionPeaceExcursionLevel = 0
        factionPeaceTravelCostLevel = 0
        factionWarExcursionLevel = 0
        factionWarTravelCostLevel = 0
    }

    $fieldNames = @(
        'companyType','companyStars',
        'currentCapacityKnown','currentCapacityMode','currentCapacity','currentCapacityBonus',
        'currentCategoryCapacityBonuses','currentCategoryCapacityResolved','currentCapacitySyncedAt',
        'factionState','factionExcursionLevel','factionTravelCostLevel',
        'factionPeaceExcursionLevel','factionPeaceTravelCostLevel',
        'factionWarExcursionLevel','factionWarTravelCostLevel'
    )
    foreach ($source in @($BaseSettings, $LocalSettings)) {
        if ($null -eq $source -or -not $source.PSObject.Properties['travelProfile'] -or $null -eq $source.travelProfile) { continue }
        foreach ($name in $fieldNames) {
            $prop = $source.travelProfile.PSObject.Properties[$name]
            if ($null -eq $prop) { continue }
            $profile.PSObject.Properties[$name].Value = $prop.Value
        }
    }

    $profile.companyType = [string]$profile.companyType
    if ([string]::IsNullOrWhiteSpace($profile.companyType)) { $profile.companyType = 'none' }
    $profile.companyStars = [Math]::Max(0, [Math]::Min(10, [int]$profile.companyStars))

    $profile.currentCapacityKnown = [bool]$profile.currentCapacityKnown
    $profile.currentCapacityMode = ([string]$profile.currentCapacityMode).Trim().ToLowerInvariant()
    if ($profile.currentCapacityMode -notin @('standard','airstrip','wlt','business')) { $profile.currentCapacityMode = '' }
    $profile.currentCapacity = [Math]::Max(0, [Math]::Min(99, [int]$profile.currentCapacity))
    $profile.currentCapacityBonus = [Math]::Max(0, [Math]::Min(50, [int]$profile.currentCapacityBonus))

    $normalizedCategoryBonuses = New-TravelCategoryBonusMap
    $normalizedCategoryResolved = New-TravelCategoryResolvedMap
    foreach ($category in @('Flower','Plushie')) {
        $bonus = [int](Get-TravelCategoryMapValue -Map $profile.currentCategoryCapacityBonuses -Category $category -DefaultValue 0)
        $normalizedCategoryBonuses.PSObject.Properties[$category].Value = [Math]::Max(0, [Math]::Min(50, $bonus))
        $normalizedCategoryResolved.PSObject.Properties[$category].Value = [bool](Get-TravelCategoryMapValue -Map $profile.currentCategoryCapacityResolved -Category $category -DefaultValue $false)
    }
    $profile.currentCategoryCapacityBonuses = $normalizedCategoryBonuses
    $profile.currentCategoryCapacityResolved = $normalizedCategoryResolved

    $profile.currentCapacitySyncedAt = [Math]::Max(0L, [long]$profile.currentCapacitySyncedAt)
    if ($profile.currentCapacityKnown -and $profile.currentCapacity -le 0 -and $profile.currentCapacityBonus -le 0) {
        $profile.currentCapacityKnown = $false
    }

    $state = ([string]$profile.factionState).ToLowerInvariant()
    if ($state -notin @('peace','war','manual')) { $state = 'manual' }
    $profile.factionState = $state

    $profile.factionPeaceExcursionLevel = [Math]::Max(0, [Math]::Min(10, [int]$profile.factionPeaceExcursionLevel))
    $profile.factionPeaceTravelCostLevel = [Math]::Max(0, [Math]::Min(5, [int]$profile.factionPeaceTravelCostLevel))
    $profile.factionWarExcursionLevel = [Math]::Max(0, [Math]::Min(10, [int]$profile.factionWarExcursionLevel))
    $profile.factionWarTravelCostLevel = [Math]::Max(0, [Math]::Min(5, [int]$profile.factionWarTravelCostLevel))

    # Legacy faction fields remain readable for old local settings. When a
    # current-capacity sync is available, capacity economics no longer infer
    # additive slots from these fields, avoiding double-counting current perks.
    if ($state -eq 'peace') {
        $profile.factionExcursionLevel = [int]$profile.factionPeaceExcursionLevel
        $profile.factionTravelCostLevel = [int]$profile.factionPeaceTravelCostLevel
    } elseif ($state -eq 'war') {
        $profile.factionExcursionLevel = [int]$profile.factionWarExcursionLevel
        $profile.factionTravelCostLevel = [int]$profile.factionWarTravelCostLevel
    } else {
        $profile.factionExcursionLevel = [Math]::Max(0, [Math]::Min(10, [int]$profile.factionExcursionLevel))
        $profile.factionTravelCostLevel = [Math]::Max(0, [Math]::Min(5, [int]$profile.factionTravelCostLevel))
    }
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
    $hasCurrentCapacity = ($Profile.PSObject.Properties['currentCapacityKnown'] -and [bool]$Profile.currentCapacityKnown)
    $itemCategory = ''
    if ($null -ne $Item -and $Item.PSObject.Properties['category']) { $itemCategory = [string]$Item.category }
    $categoryCapacityKnown = $true

    $company = @($PerksConfig.companies | Where-Object { [string]$_.id -eq [string]$Profile.companyType } | Select-Object -First 1)
    if ($company.Count -gt 0) {
        foreach ($effect in @($company[0].effects)) {
            $requiredStars = 0
            if ($effect.PSObject.Properties['stars']) { $requiredStars = [int]$effect.stars }
            if ([int]$Profile.companyStars -lt $requiredStars) { continue }

            # Company identity is still authoritative for non-capacity effects,
            # especially free Business Class. Capacity is sourced from current
            # /user/perks after a successful current-capacity sync.
            if (-not $hasCurrentCapacity) {
                if ($effect.PSObject.Properties['generalCapacityBonus']) { $generalCapacityBonus += [int]$effect.generalCapacityBonus }
                if ($null -ne $Item -and $effect.PSObject.Properties['itemCategory'] -and $effect.PSObject.Properties['itemCapacityBonus']) {
                    if ([string]$effect.itemCategory -eq $itemCategory) { $itemCapacityBonus += [int]$effect.itemCapacityBonus }
                }
            }
            if ($effect.PSObject.Properties['freeBusinessClass'] -and [bool]$effect.freeBusinessClass) { $freeBusinessClass = $true }
            if ($effect.PSObject.Properties['label'] -and -not [string]::IsNullOrWhiteSpace([string]$effect.label)) { $notes.Add([string]$effect.label) }
        }
    }

    $factionCapacity = 0
    $travelCostReductionPercent = 0
    if ($hasCurrentCapacity) {
        $generalCapacityBonus = [Math]::Max(0, [Math]::Min(50, [int]$Profile.currentCapacityBonus))
        if ($generalCapacityBonus -gt 0) { $notes.Add(('Current active travel capacity +{0}' -f $generalCapacityBonus)) }

        if ($itemCategory -in @('Flower','Plushie')) {
            $resolved = $false
            if ($Profile.PSObject.Properties['currentCategoryCapacityResolved']) {
                $resolved = [bool](Get-TravelCategoryMapValue -Map $Profile.currentCategoryCapacityResolved -Category $itemCategory -DefaultValue $false)
            }
            if ($resolved) {
                if ($Profile.PSObject.Properties['currentCategoryCapacityBonuses']) {
                    $itemCapacityBonus = [Math]::Max(0, [Math]::Min(50, [int](Get-TravelCategoryMapValue -Map $Profile.currentCategoryCapacityBonuses -Category $itemCategory -DefaultValue 0)))
                }
                if ($itemCapacityBonus -gt 0) { $notes.Add(('Current {0} travel capacity +{1}' -f $itemCategory, $itemCapacityBonus)) }
            } else {
                $categoryCapacityKnown = $false
                $notes.Add(('Current {0} capacity needs a perks sync' -f $itemCategory))
            }
        }

        # We intentionally do not infer a faction travel-fee reduction from an
        # inaccessible/stale faction loadout. Zero is conservative for Standard
        # travel and irrelevant to zero-cost Airstrip/WLT modes.
        $travelCostReductionPercent = 0
    } elseif ($PerksConfig.PSObject.Properties['faction'] -and $null -ne $PerksConfig.faction) {
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
        capacityKnown = $categoryCapacityKnown
        categoryCapacityKnown = $categoryCapacityKnown
        itemCategory = $itemCategory
        travelCostReductionPercent = $travelCostReductionPercent
        freeBusinessClass = $freeBusinessClass
        currentCapacityKnown = $hasCurrentCapacity
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
        if ($mode.enabled -ne $true) { continue }
        $requiresFreeBusiness = $false
        if ($mode.PSObject.Properties['requiresFreeBusinessClass']) { $requiresFreeBusiness = [bool]$mode.requiresFreeBusinessClass }
        if ($requiresFreeBusiness -and -not [bool]$Effects.freeBusinessClass) { continue }
        $ids.Add($id)
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
        if ([bool]$Effects.freeBusinessClass) { $travelCostKnown = $true; $travelCost = 0L }
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

    $effectsCapacityKnown = $true
    if ($Effects.PSObject.Properties['capacityKnown']) { $effectsCapacityKnown = [bool]$Effects.capacityKnown }

    $capacity = 0
    $capacityKnown = $false
    if ($CapacityOverride -gt 0) {
        $capacity = $CapacityOverride
        $capacityKnown = $true
    } elseif ($baseCapacity -gt 0 -and $effectsCapacityKnown) {
        $capacity = $baseCapacity + [int]$Effects.totalCapacityBonus
        $capacityKnown = $true
    }

    return [pscustomobject]@{
        travelCostKnown = $travelCostKnown
        travelCost = $travelCost
        baseCapacity = $baseCapacity
        capacity = $capacity
        capacityKnown = $capacityKnown
    }
}
