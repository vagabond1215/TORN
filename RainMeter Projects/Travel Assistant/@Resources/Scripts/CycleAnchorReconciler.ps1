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
$RuntimePendingObservationFile = Join-Path $RuntimeDir 'observations.pending.jsonl'
$SeedObservationFile = Join-Path $SeedDir 'observations.jsonl'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
$CycleForecastFilterScript = Join-Path $PSScriptRoot 'CycleForecastFilter.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared anchor IO.' }
if (-not (Test-Path -LiteralPath $CycleForecastFilterScript)) { throw 'CycleForecastFilter.ps1 is required for boundary-quality reconciliation.' }
. $AtomicFileScript
. $CycleForecastFilterScript

function Read-AnchorJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-AnchorJsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth = 30)
    Write-TravelAssistantAtomicJson -Path $Path -Value $Value -Depth $Depth
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
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while (($line=$reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $row = $line | ConvertFrom-Json } catch { continue }
            $country = [string](Get-AnchorProperty $row 'country')
            $itemId = [int](Get-AnchorProperty $row 'itemId')
            $timestamp = [long](Get-AnchorProperty $row 'timestamp')
            $sourceTimestamp = [long](Get-AnchorProperty $row 'sourceTimestamp')
            $evidenceTimestamp = if ($sourceTimestamp -gt 0) { $sourceTimestamp } else { $timestamp }
            if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0 -or $evidenceTimestamp -le 0) { continue }
            $key = $country + ':' + [string]$itemId
            if (-not $Wanted.ContainsKey($key)) { continue }
            $source = [string](Get-AnchorProperty $row 'source')
            if ($source -in @('history_bootstrap','history_repair_baseline')) { continue }
            if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.Generic.List[object] }
            $map[$key].Add([pscustomobject]@{
                timestamp = [long]$evidenceTimestamp
                stock = [long](Get-AnchorProperty $row 'stock')
                previousFreshSourceTimestamp = [long](Get-AnchorProperty $row 'previousFreshSourceTimestamp')
                transitionGapSeconds = [long](Get-AnchorProperty $row 'transitionGapSeconds')
                transitionBoundaryQuality = [string](Get-AnchorProperty $row 'transitionBoundaryQuality')
                source = $source
            })
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return $map
}

function Test-AnchorBoundaryQuality {
    param([string]$Quality)
    return (([string]$Quality).Trim().ToLowerInvariant() -in @('observed','bounded','recovered'))
}

function Get-AnchorTransitions {
    param([object[]]$Rows,[object]$BoundaryPolicy)
    if ($null -eq $BoundaryPolicy) { $BoundaryPolicy=Get-CycleBoundaryPolicy -Cycles @() -ExpectedPollIntervalSeconds 60 }

    $lastRestockAt = 0L
    $lastSellOutAt = 0L
    $lastRestockQuality = ''
    $lastSellOutQuality = ''
    $lastUnknownBoundaryAt = 0L
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

        $phase = if ([long]$previousStock -le 0 -and $stock -gt 0) { 'restock' } elseif ([long]$previousStock -gt 0 -and $stock -le 0) { 'sellout' } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($phase)) {
            $quality = ([string]$row.transitionBoundaryQuality).Trim().ToLowerInvariant()
            $gap = [long]$row.transitionGapSeconds
            if ($gap -le 0) {
                $freshBefore=[long]$row.previousFreshSourceTimestamp
                $gap = if ($freshBefore -gt 0 -and $timestamp -gt $freshBefore) { $timestamp-$freshBefore } else { [Math]::Max(0L,$timestamp-$previousTimestamp) }
            }
            if ([string]::IsNullOrWhiteSpace($quality)) {
                $quality = Get-CycleBoundaryQuality -GapSeconds $gap -Policy $BoundaryPolicy -Phase $phase
            }

            if (Test-AnchorBoundaryQuality -Quality $quality) {
                if ($phase -eq 'restock') { $lastRestockAt=$timestamp; $lastRestockQuality=$quality }
                else { $lastSellOutAt=$timestamp; $lastSellOutQuality=$quality }
            } else {
                if ($phase -eq 'restock') { $lastRestockAt=0L; $lastRestockQuality=$quality }
                else { $lastSellOutAt=0L; $lastSellOutQuality=$quality }
                $lastUnknownBoundaryAt=$timestamp
            }
        }
        $previousStock = $stock
        $previousTimestamp = $timestamp
    }
    return [pscustomobject]@{
        lastRestockAt = $lastRestockAt
        lastSellOutAt = $lastSellOutAt
        lastRestockQuality = $lastRestockQuality
        lastSellOutQuality = $lastSellOutQuality
        lastUnknownBoundaryAt = $lastUnknownBoundaryAt
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
$pendingRuntimeMap = Read-AnchorObservationMap -Path $RuntimePendingObservationFile -Wanted $wanted
$seedMap = Read-AnchorObservationMap -Path $SeedObservationFile -Wanted $wanted
$changed = $false

foreach ($key in @($wanted.Keys)) {
    $rows = @()
    if ($runtimeMap.ContainsKey($key) -and $runtimeMap[$key].Count -gt 0) { $rows += @($runtimeMap[$key].ToArray()) }
    if ($pendingRuntimeMap.ContainsKey($key) -and $pendingRuntimeMap[$key].Count -gt 0) { $rows += @($pendingRuntimeMap[$key].ToArray()) }
    if ($rows.Count -eq 0 -and $seedMap.ContainsKey($key) -and $seedMap[$key].Count -gt 0) { $rows = @($seedMap[$key].ToArray()) }
    if ($rows.Count -lt 2) { continue }

    $market = $engine.observedMarkets.PSObject.Properties[$key].Value
    if ($null -eq $market) { continue }
    $stock = [long](Get-AnchorProperty $market 'lastStock')
    $destination = Get-AnchorDestination -Engine $engine -Key $key
    $boundaryPolicy = Get-AnchorProperty $destination 'boundaryPolicy'
    if ($null -eq $boundaryPolicy) { $boundaryPolicy=Get-CycleBoundaryPolicy -Cycles @() -ExpectedPollIntervalSeconds 60 }
    $transition = Get-AnchorTransitions -Rows $rows -BoundaryPolicy $boundaryPolicy
    $continuityInvalidatedAt = [long](Get-AnchorProperty $destination 'continuityInvalidatedAt')
    if ([long]$transition.lastUnknownBoundaryAt -gt $continuityInvalidatedAt) {
        $continuityInvalidatedAt=[long]$transition.lastUnknownBoundaryAt
        Set-AnchorProperty -Object $destination -Name 'continuityInvalidatedAt' -Value $continuityInvalidatedAt
        $changed=$true
    }

    if ($stock -gt 0 -and [long]$transition.lastRestockAt -gt $continuityInvalidatedAt) {
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
        Set-AnchorProperty -Object $activeCycle -Name 'restockBoundaryQuality' -Value ([string]$transition.lastRestockQuality)
        Set-AnchorProperty -Object $activeCycle -Name 'anchorSource' -Value 'observations'
        Set-AnchorProperty -Object $activeCycle -Name 'anchorObservedAt' -Value ([long]$transition.latestTimestamp)
    } elseif ($stock -gt 0 -and $continuityInvalidatedAt -gt 0) {
        $activeCycle=Get-AnchorProperty $destination 'activeCycle'
        if ($null -ne $activeCycle -and [long](Get-AnchorProperty $activeCycle 'restockAt') -le $continuityInvalidatedAt) {
            Set-AnchorProperty -Object $destination -Name 'activeCycle' -Value $null
            $changed=$true
        }
    } elseif ($stock -le 0 -and [long]$transition.lastSellOutAt -gt $continuityInvalidatedAt) {
        $before = [long](Get-AnchorProperty $destination 'lastSellOutAt')
        if ($before -ne [long]$transition.lastSellOutAt) {
            Set-AnchorProperty -Object $destination -Name 'lastSellOutAt' -Value ([long]$transition.lastSellOutAt)
            $changed = $true
        }
        Set-AnchorProperty -Object $destination -Name 'lastSellOutBoundaryQuality' -Value ([string]$transition.lastSellOutQuality)
        Set-AnchorProperty -Object $destination -Name 'anchorSource' -Value 'observations'
        Set-AnchorProperty -Object $destination -Name 'anchorObservedAt' -Value ([long]$transition.latestTimestamp)
    } elseif ($stock -le 0 -and $continuityInvalidatedAt -gt 0) {
        if ([long](Get-AnchorProperty $destination 'lastSellOutAt') -le $continuityInvalidatedAt) {
            Set-AnchorProperty -Object $destination -Name 'lastSellOutAt' -Value 0L
            Set-AnchorProperty -Object $destination -Name 'lastSellOutBoundaryQuality' -Value 'unknown_gap'
            $changed=$true
        }
    }
}

if ($changed) { Write-AnchorJsonAtomic -Path $EngineStateFile -Value $engine }
return
