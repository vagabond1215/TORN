$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$TestRoot = (Resolve-Path $PSScriptRoot).Path
$tests = @(
    'Validate-TravelAssistant.ps1',
    'Validate-HistoricalTools.ps1',
    'Run-HistoricalPipelineTests.ps1',
    'Run-ModelTests.ps1'
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
