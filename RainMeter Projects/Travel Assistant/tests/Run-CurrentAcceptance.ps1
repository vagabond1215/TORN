$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$TestRoot = (Resolve-Path $PSScriptRoot).Path
$tests = @(
    'Validate-TravelAssistant.ps1',
    'Validate-RainmeterSkin.ps1',
    'Validate-CardPresenter.ps1',
    'Validate-CurrentTweaks.ps1',
    'Validate-ItemViewer.ps1',
    'Validate-RuntimeDiagnostics.ps1',
    'Validate-Filters.ps1',
    'Run-PresentationProjectionTests.ps1',
    'Run-PowerShell51CompatibilityTests.ps1',
    'Run-ProviderFreshnessTests.ps1',
    'Run-ObservationHistoryTests.ps1',
    'Validate-CycleAnalytics.ps1',
    'Run-CycleAnalyticsTests.ps1',
    'Validate-TravelContext.ps1',
    'Run-TravelContextTests.ps1',
    'Run-CurrentCapacityTests.ps1',
    'Validate-OptimalRoute.ps1',
    'Run-OptimalRouteTests.ps1',
    'Run-OpportunityStateTests.ps1',
    'Run-WindowPlanTests.ps1',
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
Write-Host 'Next: run one production update and refresh Rainmeter. Verify live active-perk capacity (including faction peace/war changes), observation-aligned Safe/Best timing, departure tooltip plus dedicated info glyph, qty in the title, Cost + MV + profit/item header, conditional Take cash buffer, provider freshness/fallback, instant filters/sorts, and the one-at-a-time 528x125 observed-only 8-hour graph.' -ForegroundColor Yellow
exit 0