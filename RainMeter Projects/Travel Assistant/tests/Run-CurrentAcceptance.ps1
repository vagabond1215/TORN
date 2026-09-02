$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$TestRoot = (Resolve-Path $PSScriptRoot).Path
$tests = @(
    'Validate-TravelAssistant.ps1',
    'Validate-RainmeterSkin.ps1',
    'Validate-UpdaterRuntime.ps1',
    'Validate-UpdaterMutex.ps1',
    'Validate-StatePublicationArchitecture.ps1',
    'Validate-CardPresenter.ps1',
    'Validate-CardDetailLayout.ps1',
    'Validate-CurrentTweaks.ps1',
    'Validate-RainmeterBangSafety.ps1',
    'Validate-GraphWindow.ps1',
    'Validate-FreshnessGuard.ps1',
    'Validate-AtomicStateWrites.ps1',
    'Validate-TravelStateWindows.ps1',
    'Validate-FinalCardPolish.ps1',
    'Validate-RuntimeDiagnostics.ps1',
    'Validate-Filters.ps1',
    'Validate-FilterReset.ps1',
    'Run-PresentationProjectionTests.ps1',
    'Run-PowerShell51CompatibilityTests.ps1',
    'Run-ProviderFreshnessTests.ps1',
    'Run-ObservationHistoryTests.ps1',
    'Validate-CensorAwareTools.ps1',
    'Run-CycleAnchorReconcilerTests.ps1',
    'Validate-CycleAnalytics.ps1',
    'Run-CycleAnalyticsTests.ps1',
    'Validate-TrendForecast.ps1',
    'Run-TrendForecastTests.ps1',
    'Run-PriceVariationRefinerTests.ps1',
    'Validate-TravelContext.ps1',
    'Run-TravelContextTests.ps1',
    'Run-CurrentCapacityTests.ps1',
    'Validate-OptimalRoute.ps1',
    'Run-OptimalRouteTests.ps1',
    'Run-OpportunityStateTests.ps1',
    'Run-WindowPlanTests.ps1',
    'Run-WindowRefinerTests.ps1',
    'Validate-LegacyWindowAuthority.ps1',
    'Run-StochasticForecastTests.ps1',
    'Run-MultiCycleChanceBridgeTests.ps1',
    'Run-StochasticCalibrationTests.ps1',
    'Validate-ResaleQueue.ps1',
    'Run-ResalePriorityTests.ps1',
    'Run-FinalizeStateTests.ps1'
)

foreach ($name in $tests) {
    $path = Join-Path $TestRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "FAILED: missing focused acceptance test $name" -ForegroundColor Red
        exit 1
    }
    Write-Host ''
    Write-Host ("=== {0} ===" -f $name) -ForegroundColor Cyan
    & $path
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("FAILED: {0}" -f $name) -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ''
Write-Host 'Focused Travel Assistant 0.6 compact opportunity candidate validations passed.' -ForegroundColor Green
Write-Host 'Next: run one production update and refresh Rainmeter. Verify final UI publication stays error-free, only flag/window text expose tooltips, active-window tooltips do not advertise past departures, graph transition ticks sit below the X axis, flags fill behind the rounded border, abroad rows avoid departure language, returning respects home availability, and fixed-price items remain white.' -ForegroundColor Yellow
exit 0
