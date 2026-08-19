param(
    [switch]$SkipTests,
    [switch]$SkipUpdater
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$Updater = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$RunAllTests = Join-Path $ProjectRoot 'tests\Run-All.ps1'

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-DirectoryBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0L }
    $sum = 0L
    foreach ($file in Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue) { $sum += [long]$file.Length }
    return $sum
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GiB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MiB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KiB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

Write-Host 'Travel Assistant live environment validation' -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

if (-not $SkipTests) {
    Write-Host ''
    Write-Host 'Running deterministic/static test suite...' -ForegroundColor Cyan
    & $RunAllTests
    if ($LASTEXITCODE -ne 0) { throw "Test suite failed with exit code $LASTEXITCODE." }
}

Write-Host ''
Write-Host 'Single YATA live-stock request...' -ForegroundColor Cyan
$yataUrl = 'https://yata.yt/api/v1/travel/export/'
try {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $yata = Invoke-RestMethod -Method Get -Uri $yataUrl -Headers @{ Accept = 'application/json' } -TimeoutSec 20
    $watch.Stop()
    foreach ($pair in @(@('uni','United Kingdom'), @('jap','Japan'))) {
        $code = $pair[0]
        $label = $pair[1]
        $countryProp = $yata.stocks.PSObject.Properties[$code]
        if ($null -eq $countryProp) { Write-Host "  $label: missing country payload" -ForegroundColor Yellow; continue }
        $country = $countryProp.Value
        $xanax = @($country.stocks | Where-Object { [int]$_.id -eq 206 } | Select-Object -First 1)
        if ($xanax.Count -eq 0) { Write-Host "  $label: Xanax row missing" -ForegroundColor Yellow; continue }
        Write-Host ("  {0}: stock {1:N0}, buy {2:C0}, source timestamp {3}" -f $label, [int]$xanax[0].quantity, [long]$xanax[0].cost, [long]$country.update) -ForegroundColor Green
    }
    Write-Host ("  request elapsed: {0:N0} ms" -f $watch.Elapsed.TotalMilliseconds)
} catch {
    Write-Host ("  YATA request failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

$localSettings = Read-JsonFile (Join-Path $ConfigDir 'settings.local.json')
$apiKey = ''
if ($null -ne $localSettings -and $localSettings.PSObject.Properties['tornApiKey']) { $apiKey = [string]$localSettings.tornApiKey }
if ([string]::IsNullOrWhiteSpace($apiKey) -and -not [string]::IsNullOrWhiteSpace($env:TORN_API_KEY)) { $apiKey = [string]$env:TORN_API_KEY }

Write-Host ''
Write-Host 'Single Torn Item Market request...' -ForegroundColor Cyan
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Host '  skipped: no local Torn API key configured' -ForegroundColor Yellow
} else {
    try {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $market = Invoke-RestMethod -Method Get -Uri 'https://api.torn.com/v2/market/206/itemmarket?limit=1' -Headers @{ Accept = 'application/json'; Authorization = "ApiKey $apiKey" } -TimeoutSec 20
        $watch.Stop()
        $average = 0L
        $lowest = 0L
        if ($market.itemmarket -and $market.itemmarket.item -and $market.itemmarket.item.PSObject.Properties['average_price']) { $average = [long]$market.itemmarket.item.average_price }
        if ($market.itemmarket -and $market.itemmarket.listings -and @($market.itemmarket.listings).Count -gt 0 -and $market.itemmarket.listings[0].PSObject.Properties['price']) { $lowest = [long]$market.itemmarket.listings[0].price }
        Write-Host ("  lowest {0:C0}; API average {1:C0}; request {2:N0} ms" -f $lowest, $average, $watch.Elapsed.TotalMilliseconds) -ForegroundColor Green
    } catch {
        Write-Host ("  Torn Item Market request failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

if (-not $SkipUpdater) {
    Write-Host ''
    Write-Host 'Running one serialized production updater pass...' -ForegroundColor Cyan
    $beforeRuntime = Get-DirectoryBytes $RuntimeDir
    $beforeGenerated = Get-DirectoryBytes $GeneratedDir
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    & $Updater -Action Update
    $updaterExit = $LASTEXITCODE
    $watch.Stop()
    $afterRuntime = Get-DirectoryBytes $RuntimeDir
    $afterGenerated = Get-DirectoryBytes $GeneratedDir
    Write-Host ("  updater exit: {0}; elapsed: {1:N0} ms" -f $updaterExit, $watch.Elapsed.TotalMilliseconds)
    Write-Host ("  runtime data: {0} -> {1}" -f (Format-Bytes $beforeRuntime), (Format-Bytes $afterRuntime))
    Write-Host ("  generated data: {0} -> {1}" -f (Format-Bytes $beforeGenerated), (Format-Bytes $afterGenerated))
    if ($updaterExit -ne 0) { Write-Host '  updater reported a failure; inspect PowerShell/Rainmeter logs before relying on recommendations.' -ForegroundColor Yellow }
}

Write-Host ''
Write-Host 'Rainmeter installation check...' -ForegroundColor Cyan
$skinRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins'
$skinPath = Join-Path $skinRoot 'Travel Assistant'
if (Test-Path -LiteralPath $skinPath) {
    $skin = Get-Item -LiteralPath $skinPath -Force
    $target = $null
    if ($skin.PSObject.Properties['Target']) { $target = @($skin.Target) | Select-Object -First 1 }
    Write-Host ("  skin path exists: {0}" -f $skinPath) -ForegroundColor Green
    if ($skin.LinkType) { Write-Host ("  link type: {0}; target: {1}" -f $skin.LinkType, $target) }
} else {
    Write-Host '  Travel Assistant skin path not installed yet; run Install.ps1.' -ForegroundColor Yellow
}

$rainmeter = @(Get-Process Rainmeter -ErrorAction SilentlyContinue)
if ($rainmeter.Count -gt 0) {
    $workingSet = ($rainmeter | Measure-Object WorkingSet64 -Sum).Sum
    Write-Host ("  Rainmeter running; current total Rainmeter working set: {0}" -f (Format-Bytes ([long]$workingSet))) -ForegroundColor Green
    Write-Host '  This is whole-process memory, not Travel Assistant-only attribution.' -ForegroundColor DarkYellow
} else {
    Write-Host '  Rainmeter process not currently detected.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Live environment check complete. Record defects/measurements in docs/IMPLEMENTATION_STATUS.md before marking the active run complete.' -ForegroundColor Green
exit 0
