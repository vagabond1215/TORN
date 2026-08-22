param(
    [ValidateRange(0,8)]
    [int]$Row = 0,
    [string]$MarketKey = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$hostScript = Join-Path $PSScriptRoot 'PopupHost.ps1'
if (-not (Test-Path -LiteralPath $hostScript)) { throw 'PopupHost.ps1 is missing.' }
if (-not [string]::IsNullOrWhiteSpace($MarketKey) -and $MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'MarketKey must be country:itemId.' }

$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}" -Popup ItemViewer -Row {1}' -f $hostScript,$Row
if (-not [string]::IsNullOrWhiteSpace($MarketKey)) { $arguments += (' -MarketKey "{0}"' -f $MarketKey) }
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
exit 0
