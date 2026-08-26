param(
    [ValidateSet('Update','CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$runner = Join-Path $PSScriptRoot 'RunUpdate.ps1'
$preferences = Join-Path $PSScriptRoot 'FilterPreferences.ps1'
$runtimeLog = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $runtimeLog) { . $runtimeLog }

try {
    if (-not (Test-Path -LiteralPath $runner)) { throw 'RunUpdate.ps1 is missing.' }
    if (-not (Test-Path -LiteralPath $preferences)) { throw 'FilterPreferences.ps1 is missing.' }
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) { throw 'pwsh.exe is required for the Travel Assistant updater.' }

    # Repair only invalid/missing startup preference state before the long worker is
    # detached. Nonempty user selections remain persistent; an empty country set is
    # normalized and persisted to all collected countries before any projection runs.
    & $preferences -Action None
    if (-not $?) { throw 'Startup preference normalization failed.' }

    # Rainmeter owns only this short launcher. The real updater is detached so the
    # RunCommand plugin cannot terminate a healthy update merely because the full
    # collection/projection cycle takes longer than its launcher timeout. RunUpdate's
    # named mutex remains the authority that prevents overlapping update workers.
    # PowerShell does not use backslash as its quote escape; keep ordinary double
    # quotes inside this single-quoted format string so paths with spaces stay intact.
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1}' -f $runner,$Action
    $arguments = $arguments.Replace('\"','"')
    Start-Process -FilePath $pwsh.Source -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    exit 0
} catch {
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component 'update-launcher' -Message (Format-TravelAssistantErrorRecord $_)
    }
    throw
}
