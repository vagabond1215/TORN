$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$ObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'

# OpportunityState preserves and extends state.kv, so guarantee that it has a
# minimal local bootstrap record even before another projector has populated it.
New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
$stateKvNeedsBootstrap = $true
if (Test-Path -LiteralPath $StateKvFile) {
    try {
        $stateKvNeedsBootstrap = [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $StateKvFile -Raw -ErrorAction Stop))
    } catch { $stateKvNeedsBootstrap = $true }
}
if ($stateKvNeedsBootstrap) {
    $tmpState = $StateKvFile + '.tmp'
    [System.IO.File]::WriteAllText($tmpState, "OpportunityBootstrap=1`r`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmpState -Destination $StateKvFile -Force
}

if (-not (Test-Path -LiteralPath $EngineStateFile)) { return }
$raw = Get-Content -LiteralPath $EngineStateFile -Raw -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($raw)) { return }
$state = $raw | ConvertFrom-Json
$changed = $false

function Ensure-StateProperty {
    param([object]$Object,[string]$Name,[object]$DefaultValue)
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member NoteProperty $Name $DefaultValue
        $script:changed = $true
    }
}

function Get-StateProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-StateProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

Ensure-StateProperty -Object $state -Name 'destinations' -DefaultValue ([pscustomobject]@{})
Ensure-StateProperty -Object $state -Name 'resaleCache' -DefaultValue ([pscustomobject]@{})
Ensure-StateProperty -Object $state -Name 'observedMarkets' -DefaultValue ([pscustomobject]@{})
Ensure-StateProperty -Object $state -Name 'shadowCollection' -DefaultValue ([pscustomobject]@{
    lastPollAt = 0
    lastProvider = ''
    countriesSeen = 0
    marketsSeen = 0
    legacyMarketsSeen = 0
    observationsWritten = 0
    cyclesCompleted = 0
    lastErrorAt = 0
    lastError = ''
})

foreach ($name in @('lastPollAt','lastProvider','countriesSeen','marketsSeen','legacyMarketsSeen','observationsWritten','cyclesCompleted','lastErrorAt','lastError')) {
    $default = if ($name -in @('lastProvider','lastError')) { '' } else { 0 }
    Ensure-StateProperty -Object $state.shadowCollection -Name $name -DefaultValue $default
}

# Migration/self-heal: a state file can be inherited while an item is already in
# stock, leaving destinations.<market>.activeCycle null even though retained real
# observations contain a later 0 -> positive transition. This is an exceptional
# repair path, not normal heartbeat work: identify repair candidates first so the
# steady-state updater never scans the full observation JSONL unnecessarily.
$activeCycleRepairKeys = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($property in @($state.observedMarkets.PSObject.Properties)) {
    $key = ([string]$property.Name).ToLowerInvariant()
    $market = $property.Value
    if ($null -eq $market -or [long](Get-StateProperty $market 'lastStock') -le 0) { continue }
    $destProperty = $state.destinations.PSObject.Properties[$key]
    if ($null -eq $destProperty -or $null -eq $destProperty.Value) { continue }
    if ($null -ne (Get-StateProperty $destProperty.Value 'activeCycle')) { continue }
    [void]$activeCycleRepairKeys.Add($key)
}

if ($activeCycleRepairKeys.Count -gt 0 -and (Test-Path -LiteralPath $ObservationFile)) {
    $previousStock = @{}
    $latestRestock = @{}
    foreach ($line in [System.IO.File]::ReadLines($ObservationFile)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $row = $line | ConvertFrom-Json } catch { continue }
        $country = [string](Get-StateProperty $row 'country')
        $itemId = [int](Get-StateProperty $row 'itemId')
        $timestamp = [long](Get-StateProperty $row 'timestamp')
        $stock = [long](Get-StateProperty $row 'stock')
        if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0 -or $timestamp -le 0) { continue }
        $key = ($country + ':' + $itemId).ToLowerInvariant()
        if (-not $activeCycleRepairKeys.Contains($key)) { continue }
        if ($previousStock.ContainsKey($key) -and [long]$previousStock[$key] -eq 0 -and $stock -gt 0) {
            $latestRestock[$key] = $row
        }
        $previousStock[$key] = $stock
    }

    foreach ($key in @($activeCycleRepairKeys)) {
        if (-not $latestRestock.ContainsKey($key)) { continue }
        $destProperty = $state.destinations.PSObject.Properties[$key]
        if ($null -eq $destProperty -or $null -eq $destProperty.Value) { continue }
        $dest = $destProperty.Value
        if ($null -ne (Get-StateProperty $dest 'activeCycle')) { continue }

        $restock = $latestRestock[$key]
        $restockAt = [long](Get-StateProperty $restock 'timestamp')
        if ($restockAt -le 0) { continue }
        $previousSoldOutAt = [long](Get-StateProperty $dest 'lastSellOutAt')
        if ($previousSoldOutAt -ge $restockAt) { $previousSoldOutAt = 0L }
        $dest.activeCycle = [pscustomobject]@{
            previousSoldOutAt = $previousSoldOutAt
            restockAt = $restockAt
            restockQuantity = [long](Get-StateProperty $restock 'stock')
            foreignPrice = [long](Get-StateProperty $restock 'foreignPrice')
            source = [string](Get-StateProperty $restock 'source')
        }
        $changed = $true
    }
}

if (-not $changed) { return }
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
$tmp = $EngineStateFile + '.tmp'
$state | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $tmp -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $EngineStateFile -Force