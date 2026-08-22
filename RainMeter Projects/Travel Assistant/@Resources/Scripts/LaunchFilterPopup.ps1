param(
    [ValidateSet('Item','Country','Category','Ignore')]
    [string]$Filter = 'Item'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$target = Join-Path $PSScriptRoot 'OpenFilterPopup.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw 'OpenFilterPopup.ps1 is missing.' }

$quotedTarget = '"' + $target.Replace('"','\"') + '"'
$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-File',$quotedTarget,
    '-Filter',$Filter
)
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Normal | Out-Null
