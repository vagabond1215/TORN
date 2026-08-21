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

    # Flower/Toy capacity is item-specific and must not increase Xanax capacity.
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
                # Item-specific perks are intentionally ignored for Xanax and
                # are not considered an unresolved general-capacity string.
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

function Get-TornEffectiveXanaxCapacity {
    param(
        [Parameter(Mandatory = $true)][string]$TravelMode,
        [Parameter(Mandatory = $true)][object]$PerksPayload
    )

    $base = Get-TornTravelModeBaseCapacity -TravelMode $TravelMode
    $suitcase = Get-TornSuitcaseCapacityFromPerks -PerksPayload $PerksPayload
    $active = Get-TornActiveTravelCapacityPerks -PerksPayload $PerksPayload
    $resolved = ([bool]$suitcase.Resolved -and [bool]$active.Resolved)
    $capacity = $base + [int]$suitcase.Bonus + [int]$active.Bonus

    return [pscustomobject]@{
        Resolved = $resolved
        TravelMode = ([string]$TravelMode).Trim().ToLowerInvariant()
        BaseCapacity = $base
        SuitcaseBonus = [int]$suitcase.Bonus
        ActivePerkBonus = [int]$active.Bonus
        Capacity = $capacity
        SuitcaseSummary = [string]$suitcase.Summary
        PerkSummary = [string]$active.Summary
        RecognizedPerks = @($suitcase.Recognized) + @($active.Recognized)
        UnparsedPerks = @($suitcase.Unparsed) + @($active.Unparsed)
    }
}
