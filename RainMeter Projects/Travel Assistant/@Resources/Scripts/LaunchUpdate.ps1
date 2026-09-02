param(
    [ValidateSet('Update','CycleTravelMode')]
    [string]$Action = 'Update',
    [ValidateRange(0,300)]
    [int]$MutexWaitSeconds = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$runner = Join-Path $PSScriptRoot 'RunUpdate.ps1'
$runtimeLog = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $runtimeLog) { . $runtimeLog }

try {
    if (-not (Test-Path -LiteralPath $runner)) { throw 'RunUpdate.ps1 is missing.' }
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) { throw 'pwsh.exe is required for the Travel Assistant updater.' }

    # Keep the Rainmeter-owned launcher strictly spawn-only. It must never perform
    # preference normalization, state publication, provider work, or any other file I/O
    # that can be delayed by OneDrive/AV/filter drivers. All real update work belongs to
    # the detached RunUpdate worker, whose named mutex prevents overlapping workers.
    # Return rather than exit so popup helpers can reuse this launcher safely.
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -MutexWaitSeconds {2}' -f $runner,$Action,$MutexWaitSeconds
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pwsh.Source
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) { throw 'Failed to start detached RunUpdate worker.' }
    $process.Dispose()
    return
} catch {
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component 'update-launcher' -Message (Format-TravelAssistantErrorRecord $_)
    }
    throw
}
