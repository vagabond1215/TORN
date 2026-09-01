$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$TestRoot = (Resolve-Path $PSScriptRoot).Path
$excludedAggregates = @('Run-All.ps1','Run-CurrentAcceptance.ps1')
$discovered = @(Get-ChildItem -LiteralPath $TestRoot -Filter '*.ps1' -File |
    Where-Object { $_.Name -notin $excludedAggregates })

# Keep the architecture/syntax gate first, then run every leaf validator and
# deterministic test in a stable order. Discovery prevents newly added regression
# tests from silently falling outside the default first-validation path.
$tests = New-Object System.Collections.Generic.List[string]
if (@($discovered.Name) -contains 'Validate-TravelAssistant.ps1') {
    $tests.Add('Validate-TravelAssistant.ps1')
}
foreach ($file in @($discovered | Where-Object { $_.Name -like 'Validate-*.ps1' -and $_.Name -ne 'Validate-TravelAssistant.ps1' } | Sort-Object Name)) {
    $tests.Add($file.Name)
}
foreach ($file in @($discovered | Where-Object { $_.Name -like 'Run-*.ps1' } | Sort-Object Name)) {
    $tests.Add($file.Name)
}

$expectedLeafCount = $discovered.Count
if ($tests.Count -ne $expectedLeafCount) {
    Write-Host ("FAILED: discovered {0} leaf test scripts but scheduled {1}." -f $expectedLeafCount,$tests.Count) -ForegroundColor Red
    exit 1
}

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
Write-Host ("All Travel Assistant 0.6 deterministic/static validations passed ({0} leaf scripts)." -f $tests.Count) -ForegroundColor Green
Write-Host 'This still does not replace live Rainmeter/provider/API validation on Windows.' -ForegroundColor Yellow
exit 0
