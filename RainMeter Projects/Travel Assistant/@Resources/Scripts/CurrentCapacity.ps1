Set-StrictMode -Version 2.0

function Get-TornTravelModeBaseCapacity {
    param([string]$TravelMode)
    $mode = ([string]$TravelMode).Trim().ToLowerInvariant()
    if ($mode -in @('airstrip','wlt','business')) { return 15 }
    return 10
}

function Get-TornSuitcaseCapacityBonus {
    param([object]$InventoryPayload)

    $best = 0
    $name = 'none'
    if ($null -eq $InventoryPayload -or -not $InventoryPayload.PSObject.Properties['inventory'] -or $null -eq $InventoryPayload.inventory) {
        return [pscustomobject]@{ Resolved = $false; Bonus = 0; Name = 'unknown'; Summary = 'Inventory response did not contain inventory data.' }
    }
    if (-not $InventoryPayload.inventory.PSObject.Properties['items']) {
        return [pscustomobject]@{ Resolved = $false; Bonus = 0; Name = 'unknown'; Summary = 'Inventory response did not contain item rows.' }
    }

    foreach ($row in @($InventoryPayload.inventory.items)) {
        if ($null -eq $row -or -not $row.PSObject.Properties['name']) { continue }
        $itemName = [string]$row.name
        $amount = if ($row.PSObject.Properties['amount']) { [long]$row.amount } else { 1L }
        if ($amount -le 0) { continue }

        $candidate = 0
        if ($itemName -match '(?i)^Large Suitcase$') { $candidate = 3 }
        elseif ($itemName -match '(?i)^Medium Suitcase$') { $candidate = 2 }
        elseif ($itemName -match '(?i)^Small Suitcase$') { $candidate = 1 }

        if ($candidate -gt $best) { $best = $candidate; $name = $itemName }
    }

    $summary = if ($best -gt 0) { ('{0} (+{1})' -f $name, $best) } else { 'No suitcase (+0)' }
    return [pscustomobject]@{ Resolved = $true; Bonus = $best; Name = $name; Summary = $summary }
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
        '(?i)(?:increase(?:s|d)?|additional|extra|adds?|plus|\+)\D{0,40}(\d{1,2})\s*(?:travel\s*)?(?:items?|capacity)',
        '(?i)(?:travel\s*)?(?:items?|capacity)\D{0,40}(?:increase(?:s|d)?\s*(?:by)?|additional|extra|adds?|plus|\+)\D{0,10}(\d{1,2})',
        '(?i)(?:maximum\s+)?(?:travel(?:ing|ling)?\s+)?capacity\D{0,30}(?:by\s*)?(\d{1,2})'
    )) {
        $m = [regex]::Match($value, $pattern)
        if ($m.Success) {
            $parsed = 0
            if ([int]::TryParse($m.Groups[1].Value, [ref]$parsed) -and $parsed -ge 0 -and $parsed -le 50) { return $parsed }
        }
    }
    return $null
}

function Get-TornActiveTravelCapacityPerks {
    param([object]$PerksPayload)

    $recognized = New-Object System.Collections.Generic.List[object]
    $unparsed = New-Object System.Collections.Generic.List[object]
    $total = 0

    if ($null -eq $PerksPayload -or -not $PerksPayload.PSObject.Properties['perks'] -or $null -eq $PerksPayload.perks) {
        return [pscustomobject]@{ Resolved = $false; Bonus = 0; Recognized = @(); Unparsed = @(); Summary = 'Perks response did not contain current perks.' }
    }

    # Property and stock can establish the 15-item base travel method. They are
    # deliberately excluded here because the selected Travel Assistant mode
    # already supplies the base capacity. Active additive capacity comes from
    # faction/job/book (plus any future additive bucket we explicitly support).
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
        [Parameter(Mandatory = $true)][object]$PerksPayload,
        [Parameter(Mandatory = $true)][object]$InventoryPayload
    )

    $base = Get-TornTravelModeBaseCapacity -TravelMode $TravelMode
    $suitcase = Get-TornSuitcaseCapacityBonus -InventoryPayload $InventoryPayload
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
        RecognizedPerks = @($active.Recognized)
        UnparsedPerks = @($active.Unparsed)
    }
}
