$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$analyticsPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleAnalytics.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$settingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$errors = @()
function Fail([string]$Message) { $script:errors += $Message }

foreach ($path in @($analyticsPath,$wrapperPath,$settingsPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing cycle analytics dependency: $path" }
}
if (Test-Path -LiteralPath $analyticsPath) {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($analyticsPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "CycleAnalytics.ps1 parse error: $($parseError.Message)" }
    $text = Get-Content -LiteralPath $analyticsPath -Raw
    foreach ($token in @(
        'cycleAnalytics','restockDelay','selloutDuration','priceToMvRatioBps','recentSamples','regimes','priceEvents',
        'significantPriceChangePercent','significantSelloutChangePercent','significantSelloutChangeSeconds',
        'sourceLength','Read-CycleLinesFromOffset','Update-CycleRunningStats','stdDev','priceEventAnchor','Get-CycleAnalyticsActiveMarketScope','StateKvFile','WantedKeys',"'sleeping_oos'"
    )) {
        if (-not $text.Contains($token)) { Fail "CycleAnalytics.ps1 missing '$token'." }
    }
    if ($text -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe|api\.torn\.com|prombot|yata\.yt') {
        Fail 'Cycle analytics must remain local-only.'
    }
}
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if (-not $settings.PSObject.Properties['cycleAnalytics']) { Fail 'settings.example.json missing cycleAnalytics configuration.' }
    else {
        if ([double]$settings.cycleAnalytics.significantPriceChangePercent -ne 5.0) { Fail 'Default significant price change threshold must be 5%.' }
        if ([double]$settings.cycleAnalytics.significantSelloutChangePercent -ne 15.0) { Fail 'Default significant sellout change threshold must be 15%.' }
        if ([int]$settings.cycleAnalytics.significantSelloutChangeSeconds -ne 300) { Fail 'Default absolute significant sellout change threshold must be 300 seconds.' }
    }
}
if (Test-Path -LiteralPath $wrapperPath) {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    foreach ($token in @('$CycleAnalytics =','cycle-analytics-error.txt','Invoke-FailSoftScript -Path $CycleAnalytics')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate.ps1 missing cycle analytics token '$token'." }
    }
    $heartbeat = $wrapper.LastIndexOf('Write-UpdateHeartbeat')
    $analytics = $wrapper.IndexOf('Invoke-FailSoftScript -Path $CycleAnalytics')
    $resale = $wrapper.IndexOf('& $ResaleQueue')
    if ($heartbeat -lt 0 -or $analytics -lt 0 -or $resale -lt 0 -or -not ($heartbeat -lt $analytics -and $analytics -lt $resale)) {
        Fail 'Cycle analytics must run after the visible heartbeat and before low-priority resale refresh.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Cycle analytics validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Cycle analytics runtime contract validation passed.' -ForegroundColor Green
Write-Host 'Completed-cycle analytics remain global retained evidence; transient current-market snapshots are scoped to awake projected markets.'
exit 0
