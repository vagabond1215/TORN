param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$RuntimeObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$SeedObservationFile = Join-Path $SeedDir 'observations.jsonl'

function Read-AnchorJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-AnchorJsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth = 30)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-AnchorProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-AnchorProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    if ($null -eq $Object) { return }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

function Read-AnchorObservationMap {
    param([string]$Path,[hashtable]$Wanted)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $row = $line | ConvertFrom-Json } catch { continue }
        $country = [string](Get-AnchorProperty $row 'country')
        $itemId = [int](Get-AnchorProperty $row 'itemId')
        $timestamp = [long](Get-AnchorProperty $row 'timestamp')
        if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0 -or $timestamp -le 0) { continue }
        $key = $country + ':' + [string]$itemId
        if (-not $Wanted.ContainsKey($key)) { continue }
        $source = [string](Get-AnchorProperty $row 'source')
        if ($source -in @('history_bootstrap','history_repair_baseline')) { continue }
        if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.Generic.List[object] }
        $map[$key].Add([pscustomobject]@{
            timestamp = $timestamp
            stock = [long](Get-AnchorProperty $row 'stock')
        })
    }
    return $map
}

function Get-AnchorTransitions {
    param([object[]]$Rows)
    $lastRestockAt = 0L
    $lastSellOutAt = 0L
    $previousStock = $null
    $previousTimestamp = 0L
    foreach ($row in @($Rows | Sort-Object timestamp)) {
        $timestamp = [long]$row.timestamp
        $stock = [long]$row.stock
        if ($timestamp -le 0) { continue }
        if ($null -eq $previousStock) {
            $previousStock = $stock
            $previousTimestamp = $timestamp
            continue
        }
        if ([long]$previousStock -eq $stock) {
            $previousTimestamp = $timestamp
            continue
        }
        if ([long]$previousStock -le 0 -and $stock -gt 0) { $lastRestockAt = $timestamp }
        elseif ([long]$previousStock -gt 0 -and $stock -le 0) { $lastSellOutAt = $timestamp }
        $previousStock = $stock
        $previousTimestamp = $timestamp
    }
    return [pscustomobject]@{
        lastRestockAt = $lastRestockAt
        lastSellOutAt = $lastSellOutAt
        latestTimestamp = $previousTimestamp
    }
}

function Get-AnchorDestination {
    param([object]$Engine,[string]$Key)
    if (-not $Engine.PSObject.Properties['destinations'] -or $null -eq $Engine.destinations) {
        $Engine | Add-Member NoteProperty destinations ([pscustomobject]@{})
    }
    $property = $Engine.destinations.PSObject.Properties[$Key]
    if ($null -eq $property) {
        $destination = [pscustomobject]@{}
        $Engine.destinations | Add-Member NoteProperty $Key $destination
        return $destination
    }
    if ($null -eq $property.Value) {
        $property.Value = [pscustomobject]@{}
    }
    return $property.Value
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$engine = Read-AnchorJson $EngineStateFile
if ($null -eq $engine -or -not $engine.PSObject.Properties['observedMarkets'] -or $null -eq $engine.observedMarkets) { return }

$wanted = @{}
foreach ($property in @($engine.observedMarkets.PSObject.Properties)) {
    if ($null -eq $property.Value) { continue }
    $key = [string]$property.Name
    if ($key -match '^[a-z0-9_]+:[1-9][0-9]*$') { $wanted[$key] = $true }
}
if ($wanted.Count -eq 0) { return }

# Runtime observations are authoritative, matching the inline graph. Seed rows are
# used only when a market has no retained real runtime observations.
$runtimeMap = Read-AnchorObservationMap -Path $RuntimeObservationFile -Wanted $wanted
$seedMap = Read-AnchorObservationMap -Path $SeedObservationFile -Wanted $wanted
$changed = $false

foreach ($key in @($wanted.Keys)) {
    $rows = @()
    if ($runtimeMap.ContainsKey($key) -and $runtimeMap[$key].Count -gt 0) { $rows = @($runtimeMap[$key].ToArray()) }
    elseif ($seedMap.ContainsKey($key) -and $seedMap[$key].Count -gt 0) { $rows = @($seedMap[$key].ToArray()) }
    if ($rows.Count -lt 2) { continue }

    $transition = Get-AnchorTransitions -Rows $rows
    $market = $engine.observedMarkets.PSObject.Properties[$key].Value
    if ($null -eq $market) { continue }
    $stock = [long](Get-AnchorProperty $market 'lastStock')
    $destination = Get-AnchorDestination -Engine $engine -Key $key

    if ($stock -gt 0 -and [long]$transition.lastRestockAt -gt 0) {
        $activeCycle = Get-AnchorProperty $destination 'activeCycle'
        if ($null -eq $activeCycle) {
            $activeCycle = [pscustomobject]@{}
            Set-AnchorProperty -Object $destination -Name 'activeCycle' -Value $activeCycle
        }
        $before = [long](Get-AnchorProperty $activeCycle 'restockAt')
        if ($before -ne [long]$transition.lastRestockAt) {
            Set-AnchorProperty -Object $activeCycle -Name 'restockAt' -Value ([long]$transition.lastRestockAt)
            $changed = $true
        }
        Set-AnchorProperty -Object $activeCycle -Name 'anchorSource' -Value 'observations'
        Set-AnchorProperty -Object $activeCycle -Name 'anchorObservedAt' -Value ([long]$transition.latestTimestamp)
    } elseif ($stock -le 0 -and [long]$transition.lastSellOutAt -gt 0) {
        $before = [long](Get-AnchorProperty $destination 'lastSellOutAt')
        if ($before -ne [long]$transition.lastSellOutAt) {
            Set-AnchorProperty -Object $destination -Name 'lastSellOutAt' -Value ([long]$transition.lastSellOutAt)
            $changed = $true
        }
        Set-AnchorProperty -Object $destination -Name 'anchorSource' -Value 'observations'
        Set-AnchorProperty -Object $destination -Name 'anchorObservedAt' -Value ([long]$transition.latestTimestamp)
    }
}

if ($changed) { Write-AnchorJsonAtomic -Path $EngineStateFile -Value $engine }
exit 0
