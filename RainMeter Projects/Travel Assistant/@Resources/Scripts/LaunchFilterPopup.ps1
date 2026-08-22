param(
    [ValidateSet('Item','Country','Category','Ignore')]
    [string]$Filter = 'Item'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$hostScript = Join-Path $PSScriptRoot 'PopupHost.ps1'
if (-not (Test-Path -LiteralPath $hostScript)) { throw 'PopupHost.ps1 is missing.' }

# Match the existing Settings behavior: Rainmeter owns only this short launcher.
# The WinForms host runs detached with its console hidden, and exits when the dialog closes.
$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}" -Popup Filter -Filter "{1}"' -f $hostScript,$Filter
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
exit 0
