$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$TestRoot = (Resolve-Path $PSScriptRoot).Path
$tests = @(
    'Validate-TravelAssistant.ps1',
    'Validate-RainmeterSkin.ps1',
    'Validate-GraphWindow.ps1',
    'Validate-ShadowCollection.ps1',
    'Validate-ItemMetadata.ps1',
    'Validate-LocalCatalog.ps1',
    'Validate-ResaleQueue.ps1',
    'Validate-VisibleItems.ps1',
    'Validate-Filters.ps1',
    'Validate-TravelContext.ps1',
    'Validate-Distribution.ps1',
    'Validate-HistoricalTools.ps1',
    'Run-HistoricalPipelineTests.ps1',
    'Run-SeedImporterTests.ps1',
    'Run-ModelTests.ps1',
    'Run-LiveProviderTests.ps1',
    'Run-ShadowCollectionTests.ps1',
    'Run-ItemMetadataTests.ps1',
    'Run-LocalCatalogTests.ps1',
    'Run-ResaleQueueTests.ps1',
    'Run-VisibleItemsTests.ps1',
    'Run-FilterPreferenceTests.ps1',
    'Run-TravelContextTests.ps1',
    'Run-TravelProfileTests.ps1',
    'Run-TornProfileSyncTests.ps1',
    'Run-CurrentCapacityTests.ps1',
    'Run-FinalizeStateTests.ps1',
    'Run-RestockDisplayTests.ps1'
)

foreach ($name in $tests) {
    $path = Join-Path $TestRoot $name
    Write-Host ''
    Write-Host ("=== {0} ===" -f $name) -ForegroundColor Cyan
    & $path
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("FAILED: {0}" -f $name) -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ''
Write-Host 'All connector-authored Travel Assistant PowerShell validations passed.' -ForegroundColor Green
Write-Host 'This still does not replace live Rainmeter/provider/resource validation.' -ForegroundColor Yellow
exit 0
