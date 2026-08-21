$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$dialogPath = Join-Path $PSScriptRoot 'OpenSettings.ps1'
if (-not (Test-Path -LiteralPath $dialogPath)) { exit 1 }

# Rainmeter RunCommand should own only this short launcher process. The actual
# WinForms dialog is detached so RunCommand does not report "Program still
# running" for the entire time a user keeps Settings open.
#
# Also avoid opening duplicates. The dialog command line contains only the local
# script path; the Torn API key is read from ignored local settings and is never
# present in the process command line.
$existing = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
    [string]$_.CommandLine -like '*OpenSettings.ps1*'
})
if ($existing.Count -gt 0) { exit 0 }

$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}"' -f $dialogPath.Replace('"', '\"')
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
exit 0
