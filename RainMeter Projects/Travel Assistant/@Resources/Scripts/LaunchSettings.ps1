$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$dialogPath = Join-Path $PSScriptRoot 'OpenSettings.ps1'
if (-not (Test-Path -LiteralPath $dialogPath)) { exit 1 }

# Rainmeter RunCommand should own only this short launcher process. The actual
# WinForms dialog is detached so RunCommand does not report "Program still
# running" for the entire time a user keeps Settings open.
$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}"' -f $dialogPath.Replace('"', '\"')
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
exit 0
