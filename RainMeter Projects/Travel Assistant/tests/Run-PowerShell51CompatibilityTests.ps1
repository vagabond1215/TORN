$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Scripts = Join-Path $ProjectRoot '@Resources\Scripts'

. (Join-Path $Scripts 'FilterPreferences.ps1') -SkipMain
$prefs = Read-UiPreferences
if ($null -eq $prefs) { throw 'Read-UiPreferences returned null.' }
if ([string]$prefs.sortMode -notin @('optimal','upcoming','profit','time')) { throw 'Normalized sort mode is invalid.' }
if ($null -eq $prefs.selectedTripBands) { throw 'Normalized trip bands are missing.' }
if ($null -eq $prefs.selectedCountryIds) { throw 'Normalized country selection is missing.' }

. (Join-Path $Scripts 'OptimalRoute.ps1') -SkipMain
$evidence = Get-OptimalEvidence
if ($null -eq $evidence) { throw 'Get-OptimalEvidence returned null.' }
if ($null -eq $evidence.cycles -or $null -eq $evidence.observations -or $null -eq $evidence.restockStock) { throw 'Evidence maps are incomplete.' }

# Force enumeration of each retained collection because Windows PowerShell 5.1
# can fail here even when parser/static tests are green.
foreach ($map in @($evidence.cycles,$evidence.observations,$evidence.restockStock)) {
    foreach ($key in @($map.Keys)) {
        $count = @($map[$key]).Count
        if ($count -lt 0) { throw 'Impossible collection count.' }
    }
}

Write-Host 'Windows PowerShell preference and retained-evidence enumeration compatibility passed.' -ForegroundColor Green
exit 0
