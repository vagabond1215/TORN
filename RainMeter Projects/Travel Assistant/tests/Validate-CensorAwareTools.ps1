$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$builderPath=Join-Path $ProjectRoot 'tools\Build-CyclesFromObservations.ps1'
$importPath=Join-Path $ProjectRoot 'tools\Import-SeedHistory.ps1'

foreach($path in @($builderPath,$importPath)){
    if(-not(Test-Path -LiteralPath $path)){throw ("Missing censor-aware history tool: "+$path)}
}

$builder=Get-Content -Raw -LiteralPath $builderPath
$import=Get-Content -Raw -LiteralPath $importPath

function Assert-Contains([string]$Text,[string]$Needle,[string]$Message){
    if(-not $Text.Contains($Needle)){throw $Message}
}
function Assert-NotContains([string]$Text,[string]$Needle,[string]$Message){
    if($Text.Contains($Needle)){throw $Message}
}

foreach($token in @(
    '$schema -notin @(1,2)',
    "schemaVersion = 2",
    "restockLowerBoundAt",
    "restockUpperBoundAt",
    "soldOutLowerBoundAt",
    "soldOutUpperBoundAt",
    "availabilityMinimumSeconds",
    "availabilityMaximumSeconds",
    "restockDelayMinimumSeconds",
    "restockDelayMaximumSeconds",
    "forecastEligible",
    "evidenceQuality",
    "selloutDepletionEvidence = 'sellout_censored'",
    "Get-ObservationEventAt",
    "sourceTimestamp",
    "Get-CycleBoundaryQuality"
)){
    Assert-Contains $builder $token ("Build-CyclesFromObservations.ps1 missing censor-aware contract token '"+$token+"'.")
}
Assert-NotContains $builder 'if ([int]$row.schemaVersion -ne 1)' 'Cycle builder must not reject runtime schema-v2 observations.'

foreach($token in @(
    'if ([int]$Row.schemaVersion -notin @(1,2))',
    '$schema -notin @(1,2)',
    "Schema-v2 cycle is missing",
    "restockUpperBoundAt",
    "soldOutUpperBoundAt",
    "forecastEligible",
    "availabilityMinimumSeconds",
    "restockDelayMaximumSeconds"
)){
    Assert-Contains $import $token ("Import-SeedHistory.ps1 missing schema-v2 contract token '"+$token+"'.")
}
Assert-NotContains $import "if ([int]$Row.schemaVersion -ne 1) { throw 'Unsupported cycle schemaVersion.' }" 'Seed importer must not reject censor-aware schema-v2 cycles.'

Write-Host 'Censor-aware offline history tooling contract passed.' -ForegroundColor Green
exit 0
