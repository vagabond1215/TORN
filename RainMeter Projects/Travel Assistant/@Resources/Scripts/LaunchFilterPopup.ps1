param(
    [ValidateSet('Filters','Item','Country','Category','Ignore')]
    [string]$Filter = 'Filters'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$hostScript = Join-Path $PSScriptRoot 'PopupHost.ps1'
$runtimeLog = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $runtimeLog) { . $runtimeLog }

try {
    if (-not (Test-Path -LiteralPath $hostScript)) { throw 'PopupHost.ps1 is missing.' }

    # Rainmeter owns only this short launcher. Use the .NET process API so the
    # launcher cannot remain attached to the WinForms host; PopupHost owns the STA
    # dialog and logs any model/UI failure itself. Use return rather than exit so
    # Settings can invoke this launcher without terminating its own popup host.
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}" -Popup Filter -Filter "{1}"' -f $hostScript,$Filter
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) { throw 'Failed to start filter popup host.' }
    $process.Dispose()
    return
} catch {
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component ('popup-launcher-filter-' + $Filter.ToLowerInvariant()) -Message (Format-TravelAssistantErrorRecord $_)
    }
    throw
}
