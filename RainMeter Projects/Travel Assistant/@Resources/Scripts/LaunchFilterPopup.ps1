param(
    [ValidateSet('Item','Country','Category','Ignore')]
    [string]$Filter = 'Item'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$target = Join-Path $PSScriptRoot 'OpenFilterPopup.ps1'
if (-not (Test-Path -LiteralPath $target)) { throw 'OpenFilterPopup.ps1 is missing.' }

# Start-Process joins ArgumentList into a Windows command line. The script path
# must contain literal quote characters because the project path contains spaces;
# do not prefix those quotes with backslashes in PowerShell single-quoted text.
$quotedTarget = '"' + $target + '"'
$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-STA',
    '-File',$quotedTarget,
    '-Filter',$Filter
)
Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Normal | Out-Null
