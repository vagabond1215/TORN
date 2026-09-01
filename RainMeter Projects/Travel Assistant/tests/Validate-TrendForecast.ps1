$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$trendPath=Join-Path $ProjectRoot '@Resources\Scripts\TrendForecast.ps1'
$pricePath=Join-Path $ProjectRoot '@Resources\Scripts\PriceVariationRefiner.ps1'
$runPath=Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$windowPath=Join-Path $ProjectRoot '@Resources\Scripts\WindowPlan.ps1'
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($trendPath,$pricePath,$runPath,$windowPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing trend/price file: $path" }
}
if ($errors.Count -eq 0) {
    $trend=Get-Content -LiteralPath $trendPath -Raw
    $price=Get-Content -LiteralPath $pricePath -Raw
    $run=Get-Content -LiteralPath $runPath -Raw
    $window=Get-Content -LiteralPath $windowPath -Raw

    foreach ($path in @($trendPath,$pricePath)) {
        $tokens=$null; $parseErrors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) { Fail "$([IO.Path]::GetFileName($path)) parse error: $($parseError.Message)" }
    }

    foreach ($token in @('mode=''shadow''','Get-TFLinearTrend','Get-TFCorrelation','availabilityVsPriceCorrelation','availabilityVsRatioCorrelation','Update-TFAccuracy','pending=$pendingNext','CycleForecastFilter.ps1','Select-CadenceAwareForecastCycles','trendForecastSourceLength','trendForecastSourceLastWriteUtcTicks','trendForecastSchemaVersion','Get-TFActiveMarketScope','trendForecastScopeSignature',"'sleeping_oos'",'$scope.keys.ContainsKey($key)')) {
        if (-not $trend.Contains($token)) { Fail "TrendForecast.ps1 missing '$token'." }
    }
    if ($trend -match '(?i)Invoke-RestMethod|Invoke-WebRequest|https?://|curl\.exe') { Fail 'TrendForecast.ps1 must remain local-only.' }

    foreach ($token in @('Test-PVRecentVariation','current-vs-recent','recurring-levels','recent-fixed','Set-PVEnvelope','OpportunityCount','PriceVariationReason',"'ForecastMode'", "'sleeping_oos'")) {
        if (-not $price.Contains($token)) { Fail "PriceVariationRefiner.ps1 missing '$token'." }
    }
    if ($price.Contains("reason='recent-transition'")) { Fail 'PriceVariationRefiner.ps1 must not reintroduce single-transition variable classification.' }
    if ($price -match '(?i)Invoke-RestMethod|Invoke-WebRequest|https?://|curl\.exe') { Fail 'PriceVariationRefiner.ps1 must remain local-only.' }

    foreach ($token in @('$PriceVariationRefiner','$TrendForecast','$PriceVariationRefinerErrorFile','$TrendForecastErrorFile')) {
        if (-not $run.Contains($token)) { Fail "RunUpdate.ps1 missing '$token'." }
    }
    $windowAt=$run.IndexOf('Invoke-FailSoftScript -Path $WindowPlan',[StringComparison]::Ordinal)
    $priceAt=$run.IndexOf('Invoke-FailSoftScript -Path $PriceVariationRefiner',[StringComparison]::Ordinal)
    $filterAt=$run.IndexOf('if (Test-Path -LiteralPath $FilterState)',[StringComparison]::Ordinal)
    $heartbeatAt=$run.IndexOf('Write-UpdateHeartbeat',[StringComparison]::Ordinal)
    $analyticsAt=$run.LastIndexOf('Invoke-FailSoftScript -Path $CycleAnalytics',[StringComparison]::Ordinal)
    $trendAt=$run.IndexOf('Invoke-FailSoftScript -Path $TrendForecast',[StringComparison]::Ordinal)
    if ($windowAt -lt 0 -or $priceAt -le $windowAt -or $filterAt -le $priceAt) { Fail 'Recent price classification must run after WindowPlan and before FilterState.' }
    if ($heartbeatAt -lt 0 -or $analyticsAt -le $heartbeatAt -or $trendAt -le $analyticsAt) { Fail 'Trend forecast must run after heartbeat and after CycleAnalytics.' }
    if ($window.Contains('trendForecast') -or $window.Contains('TrendForecast')) { Fail 'WindowPlan.ps1 must not consume shadow trend forecasts yet.' }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "FAIL: $validationError" -ForegroundColor Red }
    Write-Host "Shadow trend forecast validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Shadow trend forecast and recent price classification validation passed.' -ForegroundColor Green
Write-Host 'Trend forecasts are shadow-only and scoped to awake projected markets; sleeping/filtered rows avoid derived work while collection history remains global.'
exit 0
