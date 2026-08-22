$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$target = Join-Path $PSScriptRoot 'OpenOptimizerSettings.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw 'OpenOptimizerSettings.ps1 is missing.' }

$quotedTarget = '"' + $target.Replace('"','\"') + '"'
$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-File',$quotedTarget
)
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Normal | Out-Null
