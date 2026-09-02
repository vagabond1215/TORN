$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Scripts = Join-Path $ProjectRoot '@Resources\Scripts'

. (Join-Path $Scripts 'FilterPreferences.ps1') -SkipMain
$prefs = Read-UiPreferences
if ($null -eq $prefs) { throw 'Read-UiPreferences returned null.' }
if ([string]$prefs.sortMode -notin @('name','upcoming','gross','profit_per_hour')) { throw 'Normalized sort mode is invalid.' }
if ($null -eq $prefs.selectedTripBands) { throw 'Normalized trip bands are missing.' }
if ($null -eq $prefs.selectedCountryIds) { throw 'Normalized country selection is missing.' }

. (Join-Path $Scripts 'OptimalRoute.ps1') -SkipMain
$evidence = Get-OptimalEvidence
if ($null -eq $evidence) { throw 'Get-OptimalEvidence returned null.' }
if ($null -eq $evidence.cycles -or $null -eq $evidence.observations -or $null -eq $evidence.restockStock) { throw 'Evidence maps are incomplete.' }

# Windows PowerShell 5.1 can throw "Argument types do not match" when a generic
# List<T>/HashSet<T> is wrapped directly in @(...). Production evidence values
# must therefore be ordinary PowerShell/.NET arrays. Inspect Count directly;
# deliberately do not reproduce the unsafe @($map[$key]) construct in this test.
foreach ($map in @($evidence.cycles,$evidence.observations,$evidence.restockStock)) {
    foreach ($key in @($map.Keys)) {
        $value = $map[$key]
        if ($null -eq $value) { continue }
        if (-not ($value -is [System.Array])) {
            throw ('Evidence value {0} is {1}; expected an array safe for Windows PowerShell 5.1.' -f $key,$value.GetType().FullName)
        }
        $count = $value.Count
        if ($count -lt 0) { throw 'Impossible collection count.' }
    }
}

. (Join-Path $Scripts 'StochasticCalibration.ps1') -SkipMain
$calibrationState = New-SCCalibrationState
$aggregate = Get-SCAggregate -State $calibrationState -ModelVersion 'compat-v1' -ScopeType 'market' -ScopeValue 'test:1'
if ($null -eq $aggregate) { throw 'Calibration aggregate creation returned null.' }
if (-not ($calibrationState.aggregates -is [System.Array])) {
    throw ('Calibration aggregate state is {0}; expected a PowerShell/.NET array safe for Windows PowerShell 5.1.' -f $calibrationState.aggregates.GetType().FullName)
}
if (-not ($aggregate.buckets -is [System.Array])) {
    throw ('Calibration reliability buckets are {0}; expected a concrete array.' -f $aggregate.buckets.GetType().FullName)
}
if ([string]$aggregate.scopeType -ne 'market' -or [string]$aggregate.scopeValue -ne 'test:1') {
    throw 'Calibration aggregate scope normalization failed.'
}

Write-Host 'Windows PowerShell preference and retained-evidence enumeration compatibility passed.' -ForegroundColor Green
exit 0
