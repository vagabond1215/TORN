$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'TravelProfile.ps1')
. (Join-Path $PSScriptRoot 'AtomicFile.ps1')

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$RuntimeCycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$SeedCycleFile = Join-Path $SeedDir 'cycles.jsonl'

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-DynamicProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-StateKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in @(Read-TravelAssistantSharedLines -Path $Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $index = $line.IndexOf('=')
        if ($index -lt 1) { continue }
        $key = $line.Substring(0, $index).Trim([char]0xFEFF).Trim()
        $values[$key] = $line.Substring($index + 1).Trim()
    }
    return $values
}

function Write-StateKvAtomic {
    param([hashtable]$Values, [string]$Path)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r", ' ').Replace("`n", ' ')
        $lines.Add("$key=$value")
    }
    Write-TravelAssistantAtomicLines -Path $Path -Lines $lines.ToArray()
}

function Get-Median {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return 0.0 }
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Load-Cycles {
    param([string]$Country, [int]$ItemId, [long]$Cutoff)
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($path in @($SeedCycleFile, $RuntimeCycleFile)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in Get-Content -LiteralPath $path) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $row = $line | ConvertFrom-Json } catch { continue }
            if ([string]$row.country -ne $Country -or [int]$row.itemId -ne $ItemId) { continue }
            if (-not $row.PSObject.Properties['soldOutAt'] -or [long]$row.soldOutAt -lt $Cutoff) { continue }
            $key = ('{0}|{1}|{2}|{3}|{4}' -f [string]$row.country, [int]$row.itemId, [long]$row.restockAt, [long]$row.soldOutAt, [long]$row.foreignPrice)
            if ($seen.Add($key)) { $rows.Add($row) }
        }
    }
    return $rows.ToArray()
}

function Get-ProfitabilitySettings {
    $base = Read-JsonFile (Join-Path $ConfigDir 'settings.example.json')
    if ($null -eq $base) { throw 'config/settings.example.json is missing or invalid.' }
    $profitability = $base.profitability
    $local = Read-JsonFile (Join-Path $ConfigDir 'settings.local.json')
    if ($null -ne $local -and $local.PSObject.Properties['profitability'] -and $null -ne $local.profitability) {
        foreach ($name in @('capacityOverride','resaleStaleAfterSeconds')) {
            $localProp = $local.profitability.PSObject.Properties[$name]
            if ($null -eq $localProp) { continue }
            $targetProp = $profitability.PSObject.Properties[$name]
            if ($null -eq $targetProp) { $profitability | Add-Member NoteProperty $name $localProp.Value }
            else { $targetProp.Value = $localProp.Value }
        }
    }
    return $profitability
}

$settings = Read-JsonFile (Join-Path $ConfigDir 'settings.example.json')
$localSettings = Read-JsonFile (Join-Path $ConfigDir 'settings.local.json')
$itemsConfig = Read-JsonFile (Join-Path $ConfigDir 'items.json')
$countriesConfig = Read-JsonFile (Join-Path $ConfigDir 'countries.json')
$perksConfig = Read-JsonFile (Join-Path $ConfigDir 'travel-perks.json')
$engineState = Read-JsonFile $EngineStateFile
$state = Read-StateKv $StateKvFile

if ($null -eq $settings -or $null -eq $itemsConfig -or $null -eq $countriesConfig -or $null -eq $perksConfig -or $null -eq $engineState -or $state.Count -eq 0) { return }

$enabledItem = @($itemsConfig.items | Where-Object { $_.enabled -eq $true } | Select-Object -First 1)
if ($enabledItem.Count -eq 0) { return }
$item = $enabledItem[0]
$itemId = [int]$item.itemId
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$profitability = Get-ProfitabilitySettings
$travelProfile = Get-TravelProfile -BaseSettings $settings -LocalSettings $localSettings
$travelEffects = Get-TravelProfileEffects -Profile $travelProfile -PerksConfig $perksConfig -Item $item
$mode = [string]$state['TravelMode']
if ([string]::IsNullOrWhiteSpace($mode)) { $mode = [string]$settings.travelMode }

$state['ProfileCompany'] = [string]$travelProfile.companyType
$state['ProfileCompanyStars'] = [int]$travelProfile.companyStars
$state['ProfileFactionCapacityBonus'] = [int]$travelEffects.factionCapacityBonus
$state['ProfileGeneralCapacityBonus'] = [int]$travelEffects.generalCapacityBonus
$state['ProfileItemCapacityBonus'] = [int]$travelEffects.itemCapacityBonus
$state['ProfileTravelCostReductionPercent'] = [int]$travelEffects.travelCostReductionPercent
$state['ProfileFreeBusinessClass'] = if ([bool]$travelEffects.freeBusinessClass) { 1 } else { 0 }

$resale = if ($engineState.PSObject.Properties['resaleCache']) { Get-DynamicProperty $engineState.resaleCache ([string]$itemId) } else { $null }
$marketValue = 0L
$resaleFetchedAt = 0L
if ($null -ne $resale) {
    if ($resale.PSObject.Properties['average'] -and [long]$resale.average -gt 0) { $marketValue = [long]$resale.average }
    elseif ($resale.PSObject.Properties['price']) { $marketValue = [long]$resale.price }
    if ($resale.PSObject.Properties['fetchedAt']) { $resaleFetchedAt = [long]$resale.fetchedAt }
}
$resaleStaleAfter = if ($profitability.PSObject.Properties['resaleStaleAfterSeconds']) { [long]$profitability.resaleStaleAfterSeconds } else { 21600L }
if ($resaleStaleAfter -lt 60) { $resaleStaleAfter = 60 }
$resaleFresh = ($marketValue -gt 0 -and $resaleFetchedAt -gt 0 -and ($now - $resaleFetchedAt) -le $resaleStaleAfter)
$capacityOverride = if ($profitability.PSObject.Properties['capacityOverride']) { [int]$profitability.capacityOverride } else { 0 }
if ($capacityOverride -lt 0) { $capacityOverride = 0 }

$cutoff = $now - ([long]$settings.cycleRetentionDays * 86400)
$minimumRestockSamples = [int]$settings.recommendation.minimumComparableCycles

foreach ($country in @($countriesConfig.countries | Where-Object { $_.enabled -eq $true })) {
    $prefix = if ([string]$country.id -eq 'united_kingdom') { 'UK' } elseif ([string]$country.id -eq 'japan') { 'JP' } else { ([string]$country.id).ToUpperInvariant() }
    $destKey = ([string]$country.id) + ':' + ([string]$itemId)
    $destState = if ($engineState.PSObject.Properties['destinations']) { Get-DynamicProperty $engineState.destinations $destKey } else { $null }
    $stock = 0
    $foreignPrice = 0L
    if ($state.ContainsKey($prefix + 'Stock')) { [void][int]::TryParse([string]$state[$prefix + 'Stock'], [ref]$stock) }
    if ($state.ContainsKey($prefix + 'ForeignPrice')) { [void][long]::TryParse([string]$state[$prefix + 'ForeignPrice'], [ref]$foreignPrice) }

    # Restock/sellout evidence is independent of profitability and remains useful
    # even when the current item has negative trade value.
    if ($null -ne $destState) {
        $activeCycle = Get-DynamicProperty $destState 'activeCycle'
        if ($stock -gt 0 -and $null -ne $activeCycle -and $activeCycle.PSObject.Properties['restockAt'] -and [long]$activeCycle.restockAt -gt 0) {
            $state[$prefix + 'RestockEstimateAt'] = [long]$activeCycle.restockAt
            $state[$prefix + 'RestockSampleCount'] = 'live'
        } else {
            $lastSellOutAt = if ($destState.PSObject.Properties['lastSellOutAt']) { [long]$destState.lastSellOutAt } else { 0L }
            if ($lastSellOutAt -gt 0) {
                $restockCycles = @(Load-Cycles -Country ([string]$country.id) -ItemId $itemId -Cutoff $cutoff | Where-Object {
                    $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0
                })
                if ($restockCycles.Count -ge $minimumRestockSamples) {
                    $delays = [double[]]@($restockCycles | ForEach-Object { [double]$_.restockDelaySeconds })
                    $medianDelay = [long][Math]::Round((Get-Median $delays))
                    $state[$prefix + 'RestockEstimateAt'] = $lastSellOutAt + $medianDelay
                    $state[$prefix + 'RestockSampleCount'] = $restockCycles.Count
                    $state[$prefix + 'RestockMinDelay'] = [long](($delays | Measure-Object -Minimum).Minimum)
                    $state[$prefix + 'RestockMaxDelay'] = [long](($delays | Measure-Object -Maximum).Maximum)
                }
            }
        }
    }

    $economics = Get-EffectiveTravelEconomics -Country $country -TravelMode $mode -Effects $travelEffects -CapacityOverride $capacityOverride
    $travelCostKnown = [bool]$economics.travelCostKnown
    $travelCost = [long]$economics.travelCost
    $capacity = [int]$economics.capacity

    $state[$prefix + 'TravelCost'] = if ($travelCostKnown) { $travelCost } else { -1 }
    $state[$prefix + 'Capacity'] = $capacity
    $state[$prefix + 'ResaleFresh'] = if ($resaleFresh) { 1 } else { 0 }
    $state[$prefix + 'MarketValue'] = $marketValue
    $state[$prefix + 'RequiredTripProfit'] = 0

    # Economics are informational only. They must never rewrite Status/Message or
    # clear SAFE_WINDOW/BEST_ODDS timing. The 0.5 optimizer separately applies
    # optional profitable-only filtering while allowing negative-value candidates
    # by default.
    if ($marketValue -gt 0 -and $foreignPrice -gt 0 -and $capacity -gt 0) {
        $profitPerItem = [long]($marketValue - $foreignPrice)
        $tripProfit = if ($travelCostKnown) { [long](($profitPerItem * $capacity) - $travelCost) } else { [long]($profitPerItem * $capacity) }
        $tripSpend = if ($travelCostKnown) { [long](($foreignPrice * $capacity) + $travelCost) } else { [long]($foreignPrice * $capacity) }
        $tripMargin = if ($tripSpend -gt 0) { 100.0 * $tripProfit / [double]$tripSpend } else { 0.0 }
        $state[$prefix + 'NetResalePrice'] = $marketValue
        $state[$prefix + 'NetProfitPerItem'] = $profitPerItem
        $state[$prefix + 'TripProfit'] = $tripProfit
        $state[$prefix + 'TripMarginPercent'] = ('{0:F4}' -f $tripMargin)
    }
}

Write-StateKvAtomic -Values $state -Path $StateKvFile
return