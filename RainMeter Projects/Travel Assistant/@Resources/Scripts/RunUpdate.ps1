param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Updater = Join-Path $PSScriptRoot 'UpdateTracker.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
$mutex = New-Object System.Threading.Mutex($false, 'Local\TornTravelAssistantUpdater')
$acquired = $false

try {
    # Rainmeter can fire an initial refresh and a scheduled poll close together.
    # Skip a redundant overlapping run instead of creating concurrent network,
    # history, state, graph, or finalized-display writes.
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 0 }

    # UpdateTracker.ps1 owns live collection/history/model generation.
    # FinalizeState.ps1 then applies independent restock-display, resale-freshness,
    # and trip-economics guards without making another network request.
    & $Updater -Action $Action
    if (-not $?) { exit 1 }

    & $Finalizer
    if (-not $?) { exit 1 }

    exit 0
} finally {
    if ($acquired) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    $mutex.Dispose()
}
