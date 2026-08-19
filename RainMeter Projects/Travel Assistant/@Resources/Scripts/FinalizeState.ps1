$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

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
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $index = $line.IndexOf('=')
        if ($index -lt 1) { continue }
        $key = $line.Substring(0, $index).Trim([char]0xFEFF).Trim()
        $value = $line.Substring($index + 1).Trim()
        $values[$key] = $value
    }
    return $values
}

function Write-StateKvAtomic {
    param([hashtable]$Values, [string]$Path)
    $tmp = $Path + '.tmp'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = [string]$Values[$key]
        $cleanValue = $value.Replace("`r", ' ').Replace("`n", ' ')
        $lines.Add("$key=$cleanValue")
    }
    [System.IO.File]::WriteAllLines($tmp, @($lines), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
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
    return @($rows)
}

function Get-ProfitabilitySettings {
    $base = Read-JsonFile (Join-Path $ConfigDir 'settings.example.json')
    if ($null -eq $base) { throw 'config/settings.example.json is missing or invalid.' }

    $profitability = $base.profitability
    $local = Read-JsonFile (Join-Path $ConfigDir 'settings.local.json')
    if ($null -ne $local -and $local.PSObject.Properties['profitability'] -and $null -ne $local.profitability) {
        foreach ($name in @('sellTarget','itemMarketFeePercent','minimumProfitPerItem','minimumMarginPercent','minimumTotalTripProfit','capacityOverride','resaleStaleAfterSeconds')) {
            $localProp = $local.profitability.PSObject.Properties[$name]
            if ($null -eq $localProp) { continue }
            $targetProp = $profitability.PSObject.Properties[$name]
            if ($null -eq $targetProp) { $profitability | Add-Member NoteProperty $name $localProp.Value }
            else { $targetProp.Value = $localProp.Value }
        }
    }
    return $profitability
}

function Clear-DepartureTiming {
    param([hashtable]$State, [string]$Prefix)
    $State[$Prefix + 'WindowOpenAt'] = 0
    $State[$Prefix + 'WindowCloseAt'] = 0
    $State[$Prefix + 'BestDepartureAt'] = 0
    $State[$Prefix + 'HitRate'] = 0
}

$settings = Read-JsonFile (Join-Path $ConfigDir 'settings.example.json')
$itemsConfig = Read-JsonFile (Join-Path $ConfigDir 'items.json')
$countriesConfig = Read-JsonFile (Join-Path $ConfigDir 'countries.json')
$engineState = Read-JsonFile $EngineStateFile
$state = Read-StateKv $StateKvFile

if ($null -eq $settings -or $null -eq $itemsConfig -or $null -eq $countriesConfig -or $null -eq $engineState -or $state.Count -eq 0) {
    # The primary updater owns first-run state. The finalizer never fabricates a
    # recommendation when its input state is missing or incomplete.
    return
}

$enabledItem = @($itemsConfig.items | Where-Object { $_.enabled -eq $true } | Select-Object -First 1)
if ($enabledItem.Count -eq 0) { return }
$item = $enabledItem[0]
$itemId = [int]$item.itemId
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$profitability = Get-ProfitabilitySettings
$mode = [string]$state['TravelMode']
if ([string]::IsNullOrWhiteSpace($mode)) { $mode = [string]$settings.travelMode }

$resale = Get-DynamicProperty $engineState.resaleCache ([string]$itemId)
$resalePrice = 0L
$resaleFetchedAt = 0L
if ($null -ne $resale) {
    if ($resale.PSObject.Properties['price']) { $resalePrice = [long]$resale.price }
    if ($resale.PSObject.Properties['fetchedAt']) { $resaleFetchedAt = [long]$resale.fetchedAt }
}
$resaleStaleAfter = 600L
if ($profitability.PSObject.Properties['resaleStaleAfterSeconds']) { $resaleStaleAfter = [long]$profitability.resaleStaleAfterSeconds }
if ($resaleStaleAfter -lt 60) { $resaleStaleAfter = 60 }
$resaleFresh = ($resalePrice -gt 0 -and $resaleFetchedAt -gt 0 -and ($now - $resaleFetchedAt) -le $resaleStaleAfter)

$feePercent = 5.0
if ($profitability.PSObject.Properties['itemMarketFeePercent']) { $feePercent = [double]$profitability.itemMarketFeePercent }
if ($feePercent -lt 0) { $feePercent = 0 }
if ($feePercent -gt 100) { $feePercent = 100 }
$minimumProfitPerItem = if ($profitability.PSObject.Properties['minimumProfitPerItem']) { [double]$profitability.minimumProfitPerItem } else { 0.0 }
$minimumMarginPercent = if ($profitability.PSObject.Properties['minimumMarginPercent']) { [double]$profitability.minimumMarginPercent } else { 0.0 }
$minimumTotalTripProfit = if ($profitability.PSObject.Properties['minimumTotalTripProfit']) { [double]$profitability.minimumTotalTripProfit } else { 0.0 }
$capacityOverride = if ($profitability.PSObject.Properties['capacityOverride']) { [int]$profitability.capacityOverride } else { 0 }
if ($capacityOverride -lt 0) { $capacityOverride = 0 }

$cutoff = $now - ([long]$settings.cycleRetentionDays * 86400)
$minimumRestockSamples = [int]$settings.recommendation.minimumComparableCycles
$hardDataStatuses = @('STALE_DATA','SOURCE_DISAGREEMENT')
$timingStatuses = @('SAFE_WINDOW','BEST_ODDS','TOO_EARLY')

foreach ($country in @($countriesConfig.countries | Where-Object { $_.enabled -eq $true })) {
    $prefix = if ([string]$country.id -eq 'united_kingdom') { 'UK' } elseif ([string]$country.id -eq 'japan') { 'JP' } else { ([string]$country.id).ToUpperInvariant() }
    $destKey = ([string]$country.id) + ':' + ([string]$itemId)
    $destState = Get-DynamicProperty $engineState.destinations $destKey
    $stock = 0
    $foreignPrice = 0L
    if ($state.ContainsKey($prefix + 'Stock')) { [void][int]::TryParse([string]$state[$prefix + 'Stock'], [ref]$stock) }
    if ($state.ContainsKey($prefix + 'ForeignPrice')) { [void][long]::TryParse([string]$state[$prefix + 'ForeignPrice'], [ref]$foreignPrice) }

    # Restock display is informational and independent of profitability. Preserve
    # it even when the opportunity is LOW_MARGIN/UNPROFITABLE.
    if ($null -ne $destState) {
        $activeCycle = Get-DynamicProperty $destState 'activeCycle'
        if ($stock -gt 0 -and $null -ne $activeCycle -and [long]$activeCycle.restockAt -gt 0) {
            $state[$prefix + 'RestockEstimateAt'] = [long]$activeCycle.restockAt
            $state[$prefix + 'RestockSampleCount'] = 'live'
        } else {
            $lastSellOutAt = 0L
            if ($destState.PSObject.Properties['lastSellOutAt']) { $lastSellOutAt = [long]$destState.lastSellOutAt }
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

    $status = [string]$state[$prefix + 'Status']
    if ($hardDataStatuses -contains $status) { continue }

    $travelCostValue = Get-DynamicProperty $country.travelCosts $mode
    $capacityValue = Get-DynamicProperty $country.baseTravelCapacity $mode
    $travelCostKnown = ($null -ne $travelCostValue)
    $travelCost = if ($travelCostKnown) { [long]$travelCostValue } else { 0L }
    $capacity = if ($capacityOverride -gt 0) { $capacityOverride } elseif ($null -ne $capacityValue) { [int]$capacityValue } else { 0 }

    $state[$prefix + 'TravelCost'] = if ($travelCostKnown) { $travelCost } else { -1 }
    $state[$prefix + 'Capacity'] = $capacity
    $state[$prefix + 'ResaleFresh'] = if ($resaleFresh) { 1 } else { 0 }

    if (($timingStatuses -contains $status) -and -not $resaleFresh) {
        $state[$prefix + 'Status'] = 'CHECK_EXTERNAL'
        $state[$prefix + 'Message'] = 'Resale reference is stale — no departure recommendation'
        Clear-DepartureTiming -State $state -Prefix $prefix
        continue
    }

    if (($timingStatuses -contains $status) -and (-not $travelCostKnown -or $capacity -le 0)) {
        $state[$prefix + 'Status'] = 'CHECK_EXTERNAL'
        $state[$prefix + 'Message'] = 'Travel-mode economics are unresolved — no departure recommendation'
        Clear-DepartureTiming -State $state -Prefix $prefix
        continue
    }

    if (-not $resaleFresh -or -not $travelCostKnown -or $capacity -le 0 -or $foreignPrice -le 0) { continue }

    $netResalePrice = [long][Math]::Floor($resalePrice * (1.0 - ($feePercent / 100.0)))
    $netProfitPerItem = [long]($netResalePrice - $foreignPrice)
    $tripProfit = [long](($netProfitPerItem * $capacity) - $travelCost)
    $tripSpend = [long](($foreignPrice * $capacity) + $travelCost)
    $tripMargin = if ($tripSpend -gt 0) { 100.0 * $tripProfit / [double]$tripSpend } else { 0.0 }
    $requiredTripProfit = [Math]::Max($minimumTotalTripProfit, ($minimumProfitPerItem * $capacity))

    $state[$prefix + 'NetResalePrice'] = $netResalePrice
    $state[$prefix + 'NetProfitPerItem'] = $netProfitPerItem
    $state[$prefix + 'TripProfit'] = $tripProfit
    $state[$prefix + 'TripMarginPercent'] = ('{0:F4}' -f $tripMargin)
    $state[$prefix + 'RequiredTripProfit'] = [long][Math]::Ceiling($requiredTripProfit)

    if ($tripProfit -lt 0) {
        $state[$prefix + 'Status'] = 'UNPROFITABLE'
        $state[$prefix + 'Message'] = ('Trip is negative after travel cost: ${0:N0} at {1} slots' -f $tripProfit, $capacity)
        Clear-DepartureTiming -State $state -Prefix $prefix
    } elseif ($tripProfit -lt $requiredTripProfit -or $tripMargin -lt $minimumMarginPercent) {
        $state[$prefix + 'Status'] = 'LOW_MARGIN'
        $state[$prefix + 'Message'] = ('Trip net too low after travel cost: ${0:N0} · {1:N1}% at {2} slots' -f $tripProfit, $tripMargin, $capacity)
        Clear-DepartureTiming -State $state -Prefix $prefix
    }
}

Write-StateKvAtomic -Values $state -Path $StateKvFile
return
