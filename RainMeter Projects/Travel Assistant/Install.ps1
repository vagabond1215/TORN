param(
    [string]$SkinRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path $PSScriptRoot).Path
$SkinPath = Join-Path $SkinRoot 'Travel Assistant'
$localSettings = Join-Path $ProjectRoot 'config\settings.local.json'
$settingsTemplate = Join-Path $ProjectRoot 'config\settings.local.example.json'

New-Item -ItemType Directory -Force -Path $SkinRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot 'data\runtime') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot '@Resources\Generated') | Out-Null

if (-not (Test-Path -LiteralPath $localSettings) -and (Test-Path -LiteralPath $settingsTemplate)) {
    Copy-Item -LiteralPath $settingsTemplate -Destination $localSettings
    Write-Host 'Created ignored config/settings.local.json from the example template.' -ForegroundColor Green
}

if (Test-Path -LiteralPath $SkinPath) {
    $item = Get-Item -LiteralPath $SkinPath -Force
    $target = $null
    if ($item.PSObject.Properties['Target']) { $target = @($item.Target) | Select-Object -First 1 }
    if ($item.LinkType -eq 'Junction' -and $null -ne $target -and (Resolve-Path $target).Path -eq $ProjectRoot) {
        Write-Host "Rainmeter junction already points to $ProjectRoot" -ForegroundColor Green
    } else {
        throw "Rainmeter skin path already exists and was not created by this installer: $SkinPath`nMove/remove it manually before rerunning; this script will not delete user files."
    }
} else {
    New-Item -ItemType Junction -Path $SkinPath -Target $ProjectRoot | Out-Null
    Write-Host "Linked Rainmeter skin:`n  $SkinPath`n-> $ProjectRoot" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '1. Put a Torn API key in config\settings.local.json (or set TORN_API_KEY) to enable profitability-gated recommendations.'
Write-Host '2. Open/refresh Rainmeter, then load Travel Assistant\TravelAssistant.ini.'
Write-Host '3. The tracker starts with local learning until enough actual restock/sellout cycles exist or a verified seed is added.'
