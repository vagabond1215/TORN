param(
    [int]$PriorityBackoffSeconds = 300,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'

function Read-PriorityJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-PriorityJsonAtomic {
    param([string]$Path, [object]$Value)
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-PriorityProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-PriorityProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

function Ensure-PriorityAttempt {
    param([object]$Attempts, [int]$ItemId)
    $key = [string]$ItemId
    $attempt = Get-PriorityProperty $Attempts $key
    if ($null -eq $attempt) {
        $attempt = [pscustomobject]@{
            lastAttemptAt = 0
            lastSuccessAt = 0
            lastErrorAt = 0
            attemptCount = 0
            successCount = 0
            lastError = ''
        }
        Set-PriorityProperty $Attempts $key $attempt
    }
    return $attempt
}

if ($PriorityBackoffSeconds -lt 60) { $PriorityBackoffSeconds = 60 }
if ($PriorityBackoffSeconds -gt 1800) { $PriorityBackoffSeconds = 1800 }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$engine = Read-PriorityJson $EngineStateFile
$items = Read-PriorityJson (Join-Path $ConfigDir 'items.json')
if ($null -eq $engine -or $null -eq $items -or -not $engine.PSObject.Properties['resaleQueue']) { return }
if (-not $engine.resaleQueue.PSObject.Properties['attempts']) { return }

$preferences = Read-PriorityJson $PreferenceFile
$ignoredIds = New-Object 'System.Collections.Generic.HashSet[int]'
if ($null -ne $preferences -and $preferences.PSObject.Properties['ignoredItemIds']) {
    foreach ($id in @($preferences.ignoredItemIds)) {
        $itemId = 0
        if ([int]::TryParse([string]$id, [ref]$itemId) -and $itemId -gt 0) { [void]$ignoredIds.Add($itemId) }
    }
}

# Ignored items are deliberately parked outside the normal queue horizon. This
# changes only per-item Torn Item Market work; country-level stock collection is
# still shared and continues normally.
$ignoreHoldSeconds = 315360000L
foreach ($itemId in @($ignoredIds)) {
    $attempt = Ensure-PriorityAttempt -Attempts $engine.resaleQueue.attempts -ItemId $itemId
    $attempt.lastAttemptAt = $Now + $ignoreHoldSeconds
    $attempt.lastErrorAt = $attempt.lastAttemptAt
    $attempt.lastError = 'ignored_by_user'
}

# If an item was unignored, remove the synthetic hold immediately.
foreach ($property in @($engine.resaleQueue.attempts.PSObject.Properties)) {
    $itemId = 0
    if (-not [int]::TryParse([string]$property.Name, [ref]$itemId)) { continue }
    $attempt = $property.Value
    if ($ignoredIds.Contains($itemId)) { continue }
    if ($null -ne $attempt -and $attempt.PSObject.Properties['lastError'] -and [string]$attempt.lastError -eq 'ignored_by_user') {
        $attempt.lastAttemptAt = 0
        $attempt.lastErrorAt = 0
        $attempt.lastError = ''
    }
}

$priorityIds = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($item in @($items.items)) {
    if ($null -eq $item -or -not $item.PSObject.Properties['itemId']) { continue }
    $itemId = [int]$item.itemId
    if ($ignoredIds.Contains($itemId)) { continue }
    if ($item.PSObject.Properties['visible'] -and $item.visible -eq $true) { [void]$priorityIds.Add($itemId) }
}

$pinnedItemId = 0
if ($null -ne $preferences -and $preferences.PSObject.Properties['pinnedMarket']) {
    $pinned = [string]$preferences.pinnedMarket
    if ($pinned -match '^[a-z0-9_]+:([1-9][0-9]*)$') {
        $pinnedItemId = [int]$Matches[1]
        if (-not $ignoredIds.Contains($pinnedItemId)) { [void]$priorityIds.Add($pinnedItemId) }
    }
}

$resetCount = 0
foreach ($itemId in @($priorityIds)) {
    $attempt = Get-PriorityProperty $engine.resaleQueue.attempts ([string]$itemId)
    if ($null -eq $attempt) { continue }
    $lastAttemptAt = if ($attempt.PSObject.Properties['lastAttemptAt']) { [long]$attempt.lastAttemptAt } else { 0L }
    $lastSuccessAt = if ($attempt.PSObject.Properties['lastSuccessAt']) { [long]$attempt.lastSuccessAt } else { 0L }
    $lastErrorAt = if ($attempt.PSObject.Properties['lastErrorAt']) { [long]$attempt.lastErrorAt } else { 0L }
    if ($lastAttemptAt -le 0 -or $lastErrorAt -le $lastSuccessAt) { continue }
    if (($Now - $lastAttemptAt) -lt $PriorityBackoffSeconds) { continue }

    # ResaleQueue already prioritizes visible IDs. Clearing only the failed
    # attempt timestamp makes that existing candidate eligible again without
    # adding a second request path or weakening hidden-catalog backoff.
    $attempt.lastAttemptAt = 0
    $resetCount++
}

foreach ($pair in @(
    @('priorityVisibleItems',[int]$priorityIds.Count),
    @('pinnedItemId',[int]$pinnedItemId),
    @('ignoredItems',[int]$ignoredIds.Count),
    @('priorityBackoffSeconds',[int]$PriorityBackoffSeconds),
    @('priorityRetryResetAt',[long]$Now),
    @('priorityRetryResetCount',[int]$resetCount)
)) {
    $property = $engine.resaleQueue.PSObject.Properties[$pair[0]]
    if ($null -eq $property) { $engine.resaleQueue | Add-Member NoteProperty $pair[0] $pair[1] }
    else { $property.Value = $pair[1] }
}

Write-PriorityJsonAtomic -Path $EngineStateFile -Value $engine
