Set-StrictMode -Version 2.0

function Get-TornTravelModeBaseCapacity {
    param([string]$TravelMode)
    $mode = ([string]$TravelMode).Trim().ToLowerInvariant()
    if ($mode -in @('airstrip','wlt','business')) { return 15 }
    return 10
}

function Get-TornTravelCapacityBonusFromPerkText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $value = $Text.Trim()

    # Flower/Toy capacity is item-specific and must not be interpreted as a
    # general travel-capacity bonus. Category-specific parsing happens below.
    if ($value -match '(?i)flower|plush') { return $null }

    # Only accept strings that explicitly refer to travel/carry capacity/items.
    if ($value -notmatch '(?i)(travel|travelling|traveling|carry|carrying)' -or $value -notmatch '(?i)(capacity|items?)') { return $null }

    foreach ($pattern in @(
        # "Increases maximum traveling capacity by 10" / "capacity by +3"
        '(?i)(?:maximum\s+)?(?:travel(?:ing|ling)?\s+)?capacity\D{0,30}(?:by\s*)?\+?\s*(\d{1,2})',
        # "Increases travel item capacity by 2"
        '(?i)(?:increase(?:s|d)?|additional|extra|adds?|plus|\+)\D{0,40}(\d{1,2})\s*(?:additional\s*)?(?:travel(?:ing|ling)?\s*)?(?:items?|capacity)',
        # "Increases travel items by 10 for 31 days"
        '(?i)(?:travel(?:ing|ling)?\s*)?(?:items?|capacity)\D{0,30}(?:by|of|to|plus|\+)?\D{0,8}(\d{1,2})',
        # "Able to carry 2 additional items"
        '(?i)carry(?:ing)?\D{0,12}(\d{1,2})\D{0,20}(?:additional\s*)?items?'
    )) {
        $m = [regex]::Match($value, $pattern)
        if ($m.Success) {
            $parsed = 0
            if ([int]::TryParse($m.Groups[1].Value, [ref]$parsed) -and $parsed -ge 0 -and $parsed -le 50) { return $parsed }
        }
    }
    return $null
}

function Get-TornTravelCapacityCategoryFromPerkText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    if ($Text -match '(?i)flowers?') { return 'Flower' }
    if ($Text -match '(?i)plush(?:ie|ies|y)?') { return 'Plushie' }
    return ''
}

function Get-TornCategoryTravelCapacityBonusFromPerkText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $value = $Text.Trim()
    $category = Get-TornTravelCapacityCategoryFromPerkText -Text $value
    if ([string]::IsNullOrWhiteSpace($category)) { return $null }
    if ($value -notmatch '(?i)(travel|travelling|traveling|carry|carrying|abroad)') { return $null }

    foreach ($pattern in @(
        # "Able to carry 5 additional flowers when traveling"
        '(?i)carry(?:ing)?\D{0,20}(\d{1,2})\D{0,24}(?:additional\s*)?(?:flowers?|plush(?:ie|ies|y)?)',
        # "+5 flowers abroad" / "5 additional plushies abroad"
        '(?i)(?:\+|adds?|additional|extra|increase(?:s|d)?)?\D{0,20}(\d{1,2})\D{0,20}(?:additional\s*)?(?:flowers?|plush(?:ie|ies|y)?)\D{0,20}(?:abroad|travel(?:ing|ling)?)',
        # "Flower travel capacity +5" / "Plushie carrying capacity by 5"
        '(?i)(?:flowers?|plush(?:ie|ies|y)?)\D{0,30}(?:travel|carry|carrying|capacity|items?)\D{0,30}(?:by|of|plus|\+)?\D{0,8}(\d{1,2})'
    )) {
        $m = [regex]::Match($value, $pattern)
        if (-not $m.Success) { continue }
        $parsed = 0
        if ([int]::TryParse($m.Groups[1].Value, [ref]$parsed) -and $parsed -ge 0 -and $parsed -le 50) {
            return [pscustomobject]@{ Category = $category; Bonus = $parsed }
        }
    }
    return $null
}

function Get-TornSuitcaseCapacityFromPerks {
    param([object]$PerksPayload)

    if ($null -eq $PerksPayload -or -not $PerksPayload.PSObject.Properties['perks'] -or $null -eq $PerksPayload.perks) {
        return [pscustomobject]@{ Resolved = $false; Bonus = 0; Summary = 'Perks response did not contain current perks.'; Recognized = @(); Unparsed = @() }
    }

    $enhancerProp = $PerksPayload.perks.PSObject.Properties['enhancer']
    if ($null -eq $enhancerProp) {
        return [pscustomobject]@{ Resolved = $false; Bonus = 0; Summary = 'Current perks did not contain the enhancer bucket.'; Recognized = @(); Unparsed = @() }
    }

    $recognized = New-Object System.Collections.Generic.List[object]
    $unparsed = New-Object System.Collections.Generic.List[object]
    $best = 0

    foreach ($raw in @($enhancerProp.Value)) {
        $text = [string]$raw
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $interesting = ($text -match '(?i)(travel|travelling|traveling|carry|carrying)' -and $text -match '(?i)(capacity|items?)')
        if (-not $interesting) { continue }

        $bonus = Get-TornTravelCapacityBonusFromPerkText -Text $text
        if ($null -eq $bonus) {
            $unparsed.Add([pscustomobject]@{ Bucket = 'enhancer'; Text = $text })
            continue
        }

        $parsed = [int]$bonus
        if ($parsed -gt $best) { $best = $parsed }
        $recognized.Add([pscustomobject]@{ Bucket = 'enhancer'; Text = $text; Bonus = $parsed })
    }

    $resolved = ($unparsed.Count -eq 0)
    $summary = if ($resolved) { ('Current suitcase/enhancer travel capacity +{0}' -f $best) } else { ('Current suitcase/enhancer +{0}; {1} enhancer capacity string(s) need parser review' -f $best, $unparsed.Count) }
    return [pscustomobject]@{ Resolved = $resolved; Bonus = $best; Summary = $summary; Recognized = $recognized.ToArray(); Unparsed = $unparsed.ToArray() }
}

function Get-TornActiveTravelCapacityPerks {
    param([object]$PerksPayload)

    $recognized = New-Object System.Collections.Generic.List[object]
    $unparsed = New-Object System.Collections.Generic.List[object]
    $total = 0

    if ($null -eq $PerksPayload -or -not $PerksPayload.PSObject.Properties['perks'] -or $null -eq $PerksPayload.perks) {
        return [pscustomobject]@{ Resolved = $false; Bonus = 0; Recognized = @(); Unparsed = @(); Summary = 'Perks response did not contain current perks.' }
    }

    # Property and stock establish the 15-item base travel method and are not
    # additive here. Enhancer is handled separately as the non-stacking
    # suitcase bonus. Additive general capacity comes from faction/job/book.
    foreach ($bucket in @('faction','job','book')) {
        $prop = $PerksPayload.perks.PSObject.Properties[$bucket]
        if ($null -eq $prop) { continue }
        foreach ($raw in @($prop.Value)) {
            $text = [string]$raw
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $interesting = ($text -match '(?i)(travel|travelling|traveling|carry|carrying)' -and $text -match '(?i)(capacity|items?)')
            if (-not $interesting) { continue }

            if ($text -match '(?i)flower|plush') {
                # Category-specific perks are handled separately and are not an
                # unresolved general-capacity string.
                continue
            }

            $bonus = Get-TornTravelCapacityBonusFromPerkText -Text $text
            if ($null -eq $bonus) {
                $unparsed.Add([pscustomobject]@{ Bucket = $bucket; Text = $text })
            } else {
                $total += [int]$bonus
                $recognized.Add([pscustomobject]@{ Bucket = $bucket; Text = $text; Bonus = [int]$bonus })
            }
        }
    }

    $resolved = ($unparsed.Count -eq 0)
    $summary = if ($resolved) { ('Active additive travel perks +{0}' -f $total) } else { ('Active additive travel perks +{0}; {1} travel-capacity string(s) need parser review' -f $total, $unparsed.Count) }
    return [pscustomobject]@{ Resolved = $resolved; Bonus = $total; Recognized = $recognized.ToArray(); Unparsed = $unparsed.ToArray(); Summary = $summary }
}

function Get-TornCategoryTravelCapacityPerks {
    param([object]$PerksPayload)

    $bonuses = [pscustomobject]@{ Flower = 0; Plushie = 0 }
    $resolved = [pscustomobject]@{ Flower = $true; Plushie = $true }
    $recognized = New-Object System.Collections.Generic.List[object]
    $unparsed = New-Object System.Collections.Generic.List[object]

    if ($null -eq $PerksPayload -or -not $PerksPayload.PSObject.Properties['perks'] -or $null -eq $PerksPayload.perks) {
        $resolved.Flower = $false
        $resolved.Plushie = $false
        return [pscustomobject]@{ Bonuses = $bonuses; Resolved = $resolved; Recognized = @(); Unparsed = @(); Summary = 'Perks response did not contain current perks.' }
    }

    foreach ($bucketProp in @($PerksPayload.perks.PSObject.Properties)) {
        $bucket = [string]$bucketProp.Name
        foreach ($raw in @($bucketProp.Value)) {
            $text = [string]$raw
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $category = Get-TornTravelCapacityCategoryFromPerkText -Text $text
            if ([string]::IsNullOrWhiteSpace($category)) { continue }
            if ($text -notmatch '(?i)(travel|travelling|traveling|carry|carrying|abroad)') { continue }

            $parsed = Get-TornCategoryTravelCapacityBonusFromPerkText -Text $text
            if ($null -eq $parsed) {
                $resolved.PSObject.Properties[$category].Value = $false
                $unparsed.Add([pscustomobject]@{ Bucket = $bucket; Category = $category; Text = $text })
                continue
            }

            $bonuses.PSObject.Properties[$category].Value = [int]$bonuses.PSObject.Properties[$category].Value + [int]$parsed.Bonus
            $recognized.Add([pscustomobject]@{ Bucket = $bucket; Category = $category; Text = $text; Bonus = [int]$parsed.Bonus })
        }
    }

    $summary = ('Category travel capacity: Flower {0:+0;-0;0} ({1}), Plushie {2:+0;-0;0} ({3})' -f [int]$bonuses.Flower, $(if ([bool]$resolved.Flower) { 'resolved' } else { 'unresolved' }), [int]$bonuses.Plushie, $(if ([bool]$resolved.Plushie) { 'resolved' } else { 'unresolved' }))
    return [pscustomobject]@{ Bonuses = $bonuses; Resolved = $resolved; Recognized = $recognized.ToArray(); Unparsed = $unparsed.ToArray(); Summary = $summary }
}

function Get-TornEffectiveItemCapacity {
    param(
        [Parameter(Mandatory = $true)][string]$TravelMode,
        [Parameter(Mandatory = $true)][object]$PerksPayload,
        [string]$ItemCategory = ''
    )

    $base = Get-TornTravelModeBaseCapacity -TravelMode $TravelMode
    $suitcase = Get-TornSuitcaseCapacityFromPerks -PerksPayload $PerksPayload
    $active = Get-TornActiveTravelCapacityPerks -PerksPayload $PerksPayload
    $categoryPerks = Get-TornCategoryTravelCapacityPerks -PerksPayload $PerksPayload

    $category = ([string]$ItemCategory).Trim()
    $categoryBonus = 0
    $categoryResolved = $true
    if ($category -in @('Flower','Plushie')) {
        $bonusProp = $categoryPerks.Bonuses.PSObject.Properties[$category]
        $resolvedProp = $categoryPerks.Resolved.PSObject.Properties[$category]
        if ($null -ne $bonusProp) { $categoryBonus = [int]$bonusProp.Value }
        if ($null -eq $resolvedProp -or -not [bool]$resolvedProp.Value) { $categoryResolved = $false }
    }

    $resolved = ([bool]$suitcase.Resolved -and [bool]$active.Resolved -and $categoryResolved)
    $capacity = $base + [int]$suitcase.Bonus + [int]$active.Bonus + $categoryBonus

    return [pscustomobject]@{
        Resolved = $resolved
        TravelMode = ([string]$TravelMode).Trim().ToLowerInvariant()
        ItemCategory = $category
        BaseCapacity = $base
        SuitcaseBonus = [int]$suitcase.Bonus
        ActivePerkBonus = [int]$active.Bonus
        CategoryCapacityBonus = $categoryBonus
        CategoryCapacityResolved = $categoryResolved
        CategoryBonuses = $categoryPerks.Bonuses
        CategoryResolved = $categoryPerks.Resolved
        Capacity = $capacity
        SuitcaseSummary = [string]$suitcase.Summary
        PerkSummary = [string]$active.Summary
        CategorySummary = [string]$categoryPerks.Summary
        RecognizedPerks = @($suitcase.Recognized) + @($active.Recognized) + @($categoryPerks.Recognized)
        UnparsedPerks = @($suitcase.Unparsed) + @($active.Unparsed) + @($categoryPerks.Unparsed)
    }
}

function Get-TornEffectiveXanaxCapacity {
    param(
        [Parameter(Mandatory = $true)][string]$TravelMode,
        [Parameter(Mandatory = $true)][object]$PerksPayload
    )

    # Backward-compatible wrapper. Xanax is a Drug, so Flower/Plushie bonuses
    # are parsed and exposed for later use but never increase this capacity.
    return Get-TornEffectiveItemCapacity -TravelMode $TravelMode -PerksPayload $PerksPayload -ItemCategory 'Drug'
}
