$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$filterPath=Join-Path $ProjectRoot '@Resources\Scripts\CycleForecastFilter.ps1'
$anchorPath=Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1'
$windowPath=Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1'
$graphPath=Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$stochasticPath=Join-Path $ProjectRoot '@Resources\Scripts\StochasticForecast.ps1'
$calibrationPath=Join-Path $ProjectRoot '@Resources\Scripts\StochasticCalibration.ps1'
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message){$script:errors.Add($Message)}

foreach($path in @($filterPath,$anchorPath,$windowPath,$graphPath,$stochasticPath,$calibrationPath)){
    if(-not(Test-Path -LiteralPath $path)){Fail "Missing plausibility contract file: $path"}
}
if($errors.Count -eq 0){
    $filter=Get-Content -LiteralPath $filterPath -Raw
    $anchor=Get-Content -LiteralPath $anchorPath -Raw
    $window=Get-Content -LiteralPath $windowPath -Raw
    $graph=Get-Content -LiteralPath $graphPath -Raw
    $stochastic=Get-Content -LiteralPath $stochasticPath -Raw
    $calibration=Get-Content -LiteralPath $calibrationPath -Raw

    $tokens=$null;$parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($filterPath,[ref]$tokens,[ref]$parseErrors)
    foreach($parseError in @($parseErrors)){Fail ('CycleForecastFilter.ps1 parse error: '+$parseError.Message)}

    foreach($token in @(
        'Resolve-StockObservationPlausibility',
        'Get-PlausibilityFilteredStockObservations',
        "'spurious_zero'",
        "'spurious_zero_partner'",
        "'spurious_restock'",
        "'spurious_restock_partner'",
        '[double]$ContinuationToleranceFraction=0.05',
        '[double]$TinyRestockFraction=0.25',
        '[long]$AbsoluteTinyRestockUnits=10L',
        '$maximumTransientSeconds=[long][Math]::Max(150,(2*$poll)+30)',
        'Test-RecoveredStockObservation',
        'torn_intel_history_recovery',
        'Test-CycleSuppressedByObservationPlausibility',
        'spurious-transitions.json',
        'if (Test-CycleSuppressedByObservationPlausibility -Cycle $Cycle) { return $false }'
    )){
        if(-not$filter.Contains($token)){Fail "Plausibility filter contract missing '$token'."}
    }

    foreach($token in @(
        '$SpuriousTransitionFile = Join-Path $RuntimeDir ''spurious-transitions.json''',
        'Resolve-StockObservationPlausibility -Rows $rows',
        'transitionTimestamps=$transitionTimes',
        'calculationTimestamps=$calculationTimes',
        'Write-AnchorJsonAtomic -Path $SpuriousTransitionFile'
    )){
        if(-not$anchor.Contains($token)){Fail "Anchor plausibility integration missing '$token'."}
    }

    foreach($token in @(
        'Get-PlausibilityFilteredStockObservations -Rows @($observationMap[$observationKey].ToArray())',
        '$observationMap[$observationKey]=$list'
    )){
        if(-not$window.Contains($token)){Fail "Window plausibility integration missing '$token'."}
    }

    foreach($token in @(
        '$calculationRows=@(Get-PlausibilityFilteredStockObservations -Rows $allRows',
        'Get-InlineStockTransitions -Rows $calculationRows',
        'Get-FlightShiftedRealizedHistory -StockRows $calculationRows',
        'Ignored spurious phase transitions: '
    )){
        if(-not$graph.Contains($token)){Fail "Graph plausibility integration missing '$token'."}
    }

    if(-not$stochastic.Contains('$Observations=@(Get-PlausibilityFilteredStockObservations -Rows $Observations')){
        Fail 'Stochastic forecast must exclude spurious observation blips from depletion-shape evidence.'
    }
    foreach($token in @(
        '$CycleForecastFilterScript=Join-Path $PSScriptRoot ''CycleForecastFilter.ps1''',
        '$Observations=@(Get-PlausibilityFilteredStockObservations -Rows $Observations',
        '$Cycles=@($Cycles|Where-Object{Test-CycleForecastBoundaryEvidence -Cycle $_ -Purpose Forecast})'
    )){
        if(-not$calibration.Contains($token)){Fail "Calibration plausibility integration missing '$token'."}
    }

    foreach($forbidden in @(
        'MinimumOosDuration',
        'MinimumOutOfStockDuration',
        'delete spurious observation'
    )){
        if($filter.Contains($forbidden) -or $anchor.Contains($forbidden)){Fail "Plausibility filter must retain raw evidence and avoid blanket duration suppression: '$forbidden'."}
    }
}

if($errors.Count -gt 0){
    foreach($failure in $errors){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Observation plausibility validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Observation plausibility suppression contract validation passed.' -ForegroundColor Green
exit 0
