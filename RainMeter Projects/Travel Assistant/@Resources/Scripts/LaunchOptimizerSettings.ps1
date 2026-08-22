$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$target = Join-Path $PSScriptRoot 'OpenOptimizerSettings.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw 'OpenOptimizerSettings.ps1 is missing.' }

$quotedTarget = '"' + $target + '"'
$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-STA',
    '-File',$quotedTarget
)
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Normal | Out-Null
