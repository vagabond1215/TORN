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
    'Validate-ObservationPlausibility.ps1',
    'Run-ObservationPlausibilityTests.ps1',
    'Validate-HistoryRecovery.ps1',
    'Run-HistoryRecoveryTests.ps1',
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
    'Run-ChanceHistoryTests.ps1',
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
Write-Host 'Next: run one production update and refresh Rainmeter. Verify final UI publication stays error-free, graph hover regions remain stable without one-second blinking, event-history tooltips are centralized on the bottom-center circled info control instead of duplicating OoS/restock/variance/hindsight hover regions, raw resolved forecasts remain intact while the visible accuracy overlay is coalesced into sparse 15-minute representatives, cyan chance is continuous without 50% suppression and current in-stock chance uses live depletion or survival conditioned on the latest positive observation, periwinkle appears only as flight-shifted historical departure windows, actual transition ticks sit below the X axis, each restock-window bracket pair is anchored to the preceding orange OoS tick using average delay +/- variance and the later blue restock tick is free to land outside that forecast, the info tooltip shows stable summary statistics plus a newest-first maximum-four-cycle 8h event timeline, the compact H/%/W/S header toggles immediately persist and rerender Hindsight/Chance/restock-window/stock-transition overlays, warm-cache filter saves avoid a redundant second opportunity/window/refiner pass, an otherwise non-informative fresh in-stock card may show STOCK HOLDING only when a far sellout or 15-minute low-depletion stress runway clears max(6h,2x arrival) after primary current-cycle/Safe-Best/multi-cycle guidance fails, with no fabricated percentage, and an otherwise unavailable sold-out next-cycle may show AVG LEAVE IN / AVG LEAVE NOW / AVG RESTOCK LATE from the verified last OoS plus average delay only after Safe/Best and multi-cycle guidance fail, with no fabricated percentage and WAIT DATA after the longest historical delay, a configured approved Torn Intel recovery key may post-publication check one passed W-window per minute for a missed micro-restock and append only externally observed recovered points/cycles while no proof means no synthetic transition, pending observation/cycle journals remain immediately usable by current-card forecasting and observation-reconciled active cycles retain their restock quantity for live depletion, isolated positive->0->positive provider dropouts and tiny one-poll 0->positive->0 blips are retained raw but excluded from anchors/cycles/windows/stochastic/calibration unless recovered history proves them, the graph info tooltip reports ignored spurious phase transitions, and any later observed restock permanently supersedes a preceding OoS countdown/fallback even after that positive snapshot becomes FORECAST ONLY, stale stock disables live-current-stock claims but may still use a verified phase anchor for recurring forecast geometry, Chance to Hit renders as its own horizontally centered second-line field, In stock is sentence case, and approximate restock guidance renders only as Restocks in ~X without a redundant RESTOCK ESTIMATE prefix, flags fill behind the rounded border, abroad rows avoid departure language, returning respects home availability, and fixed-price items remain white.' -ForegroundColor Yellow
exit 0
