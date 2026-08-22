$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$target = Join-Path $PSScriptRoot 'OpenOptimizerSettings.ps1'
if (-not (Test-Path -LiteralPath $target)) { exit 1 }
$arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $target.Replace('"','\"')
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Normal | Out-Null
