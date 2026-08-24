$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$TestRoot = (Resolve-Path $PSScriptRoot).Path
$tests = @(
    'Validate-TravelAssistant.ps1',
    'Validate-RainmeterSkin.ps1',
    'Validate-ItemViewer.ps1',
    'Validate-RuntimeDiagnostics.ps1',
    'Validate-Filters.ps1',
    'Run-PresentationProjectionTests.ps1',
    'Run-PowerShell51CompatibilityTests.ps1',
    'Run-ObservationHistoryTests.ps1',
    'Validate-TravelContext.ps1',
    'Run-TravelContextTests.ps1',
    'Validate-OptimalRoute.ps1',
    'Run-OptimalRouteTests.ps1',
    'Run-OpportunityStateTests.ps1',
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
Write-Host 'Next: run one production update and refresh Rainmeter. Verify item-country titles, BUY per-item price plus MV, instant SHORT/MED/LONG filtering including OFF->ON, instant NAME/UPCOMING/GROSS PROFIT/PROFIT-HR sorting, graph collapse on sort/trip changes, one-at-a-time observed-only 8-hour graphs, separate VIEWER popup, filters, and SETTINGS.' -ForegroundColor Yellow
exit 0
