param(
    [ValidateRange(0,8)]
    [int]$Row = 0,
    [string]$MarketKey = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$target = Join-Path $PSScriptRoot 'OpenItemViewer.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw 'OpenItemViewer.ps1 is missing.' }
if (-not [string]::IsNullOrWhiteSpace($MarketKey) -and $MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'MarketKey must be country:itemId.' }

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-File',$target,
    '-Row',[string]$Row,
    '-MarketKey',$MarketKey
)
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Normal | Out-Null
