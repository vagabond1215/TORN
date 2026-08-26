$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$dialogPath = Join-Path $PSScriptRoot 'OpenSettings.ps1'
$runtimeLog = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $runtimeLog) { . $runtimeLog }

try {
    if (-not (Test-Path -LiteralPath $dialogPath)) { throw 'OpenSettings.ps1 is missing.' }

    # Avoid opening duplicate Profile/API dialogs. The command line contains only
    # the local script path; the Torn API key stays in ignored local settings.
    $existing = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
        [string]$_.CommandLine -like '*OpenSettings.ps1*'
    })
    if ($existing.Count -gt 0) { return }

    # Use the same detached process contract as the other popup launchers. Return
    # rather than exit so this script is safe when invoked from Optimizer Settings.
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}"' -f $dialogPath
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) { throw 'Failed to start Profile/API settings dialog.' }
    $process.Dispose()
    return
} catch {
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component 'popup-launcher-profile' -Message (Format-TravelAssistantErrorRecord $_)
    }
    throw
}
