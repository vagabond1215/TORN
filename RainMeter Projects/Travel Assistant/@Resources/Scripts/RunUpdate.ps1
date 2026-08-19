param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Updater = Join-Path $PSScriptRoot 'UpdateTracker.ps1'
$mutex = New-Object System.Threading.Mutex($false, 'Local\TornTravelAssistantUpdater')
$acquired = $false

try {
    # Rainmeter can fire an initial refresh and a scheduled poll close together.
    # Skip a redundant overlapping run instead of creating concurrent network,
    # history, state, or graph writes.
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 0 }

    # UpdateTracker.ps1 uses terminating errors under ErrorActionPreference=Stop.
    # If it returns normally, the run succeeded; avoid relying on LASTEXITCODE,
    # which is only meaningful after native-process execution.
    & $Updater -Action $Action
    exit 0
} finally {
    if ($acquired) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    $mutex.Dispose()
}
