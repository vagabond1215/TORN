$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$viewerPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenItemViewer.ps1'
$launcherPath = Join-Path $ProjectRoot '@Resources\Scripts\LaunchItemViewer.ps1'
$hostPath = Join-Path $ProjectRoot '@Resources\Scripts\PopupHost.ps1'
$settingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($viewerPath,$launcherPath,$hostPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing $path."; continue }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)" }
}

if (Test-Path -LiteralPath $launcherPath) {
    $launcher = Get-Content -LiteralPath $launcherPath -Raw
    foreach ($token in @('PopupHost.ps1','Start-Process','-WindowStyle Hidden','-STA','-Popup ItemViewer','-MarketKey','$MarketKey','IsNullOrWhiteSpace($MarketKey)')) {
        if (-not $launcher.Contains([string]$token)) { Fail "Viewer launcher missing '$token'." }
    }
    if (-not $launcher.Contains("MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$'")) { Fail 'Viewer launcher must validate stable country:itemId keys.' }
    if ($launcher.Contains('-WindowStyle Normal')) { Fail 'Viewer launcher must not expose a PowerShell console.' }
}

if (Test-Path -LiteralPath $hostPath) {
    $hostText = Get-Content -LiteralPath $hostPath -Raw
    foreach($token in @('OpenItemViewer.ps1','RuntimeLog.ps1','Write-TravelAssistantLog','ItemViewer')) {
        if(-not $hostText.Contains($token)){Fail "PopupHost viewer contract missing '$token'."}
    }
}

if (Test-Path -LiteralPath $viewerPath) {
    $viewer = Get-Content -LiteralPath $viewerPath -Raw
    foreach ($token in @(
        '[string]$MarketKey',
        'RuntimeObservationFile',
        'SeedObservationFile',
        'graphWindowHours',
        'use95PercentMarketValue',
        'observedMarkets',
        'resaleCache',
        'sourceTimestamp',
        'catalogStatus',
        'legacy_removed',
        '$baseline = @{}',
        "source = 'carry_forward'",
        'timestamp += 3600',
        "ToString('HH:mm')",
        'Green: observed restock',
        'Red: observed sellout',
        'Dropdown is sorted by known profit/item.',
        '[string]$sortedRows[$i].key -eq $MarketKey'
    )) {
        if (-not $viewer.Contains($token)) { Fail "Item viewer contract missing '$token'." }
    }
    if ($viewer -match '(?i)Invoke-RestMethod|curl\.exe|api\.torn\.com|prombot\.co\.uk|yata\.yt') { Fail 'Item viewer must remain local-only and must not make network requests.' }
}

if (-not (Test-Path -LiteralPath $settingsPath)) {
    Fail 'Missing settings.example.json.'
} else {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ([int]$settings.graphWindowHours -ne 8) { Fail 'On-demand stock viewer display must remain eight hours.' }
    if ([int]$settings.highResolutionRetentionHours -lt [int]$settings.graphWindowHours) { Fail 'Retained high-resolution history must cover the viewer window.' }
    if ([int]$settings.highResolutionRetentionHours -ne 48) { Fail 'High-resolution learning retention should remain 48 hours.' }
    if ([int]$settings.cycleRetentionDays -ne 90) { Fail 'Completed-cycle learning retention should remain 90 days.' }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Item viewer validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Stable-key hidden-host eight-hour item viewer static validation passed.' -ForegroundColor Green
Write-Host 'Viewer is local-only; retained 48h/90d learning remains independent of the 8h display.' -ForegroundColor DarkGreen
exit 0
