param(
    [ValidateRange(0,8)]
    [int]$Row = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$target = Join-Path $PSScriptRoot 'OpenItemViewer.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw 'OpenItemViewer.ps1 is missing.' }

$escaped = $target.Replace('"','\"')
$arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Row {1}' -f $escaped, $Row
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Normal | Out-Null
