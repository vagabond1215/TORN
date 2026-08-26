param(
    [ValidateSet('Item','Country','Category','Ignore')]
    [string]$Filter = 'Item'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$hostScript = Join-Path $PSScriptRoot 'PopupHost.ps1'
$runtimeLog = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $runtimeLog) { . $runtimeLog }

try {
    if (-not (Test-Path -LiteralPath $hostScript)) { throw 'PopupHost.ps1 is missing.' }

    # Rainmeter owns only this short launcher. The detached STA host owns the dialog.
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}" -Popup Filter -Filter "{1}"' -f $hostScript,$Filter
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    exit 0
} catch {
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component ('popup-launcher-filter-' + $Filter.ToLowerInvariant()) -Message (Format-TravelAssistantErrorRecord $_)
    }
    throw
}
