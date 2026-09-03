$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\HistoryRecovery.ps1'
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:failures.Add($Message) }
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { Fail $Message } }
function Assert-Equal($Actual,$Expected,[string]$Message) {
    if ($Actual -ne $Expected) { Fail ("{0} Expected={1} Actual={2}" -f $Message,$Expected,$Actual) }
}

. $scriptPath -SkipMain

$cycles=@(
    [pscustomobject]@{restockDelaySeconds=7140L;soldOutAt=100L},
    [pscustomobject]@{restockDelaySeconds=7200L;soldOutAt=200L},
    [pscustomobject]@{restockDelaySeconds=7260L;soldOutAt=300L},
    [pscustomobject]@{restockDelaySeconds=7200L;soldOutAt=400L}
)
$summary=Get-RecoveryWindowSummary -Cycles $cycles
Assert-Equal ([int]$summary.sampleCount) 4 'Recovery summary should retain all four recent samples.'
Assert-Equal ([long]$summary.averageDelaySeconds) 7200L 'Recovery W-close trigger must use average restock delay.'
Assert-True ([long]$summary.varianceSeconds -ge 0L) 'Recovery variance must be non-negative.'

$iso=Convert-RecoveryTimestamp '2026-09-03T12:34:56Z'
Assert-True ($iso -gt 0) 'ISO history timestamps must parse to unix epoch.'
Assert-Equal (Convert-RecoveryTimestamp '1234567890') 1234567890L 'Numeric history timestamps must remain unchanged.'
Assert-Equal (Convert-RecoveryTimestamp 'not-a-time') 0L 'Invalid history timestamps must fail closed.'

$countries=[pscustomobject]@{countries=@(
    [pscustomobject]@{id='canada';providerCodes=[pscustomobject]@{prometheus='can';tornIntel='can'}},
    [pscustomobject]@{id='mexico';providerCodes=[pscustomobject]@{prometheus='mex'}}
)}
Assert-Equal (Get-RecoveryCountryCode -Countries $countries -CountryId 'canada') 'can' 'Explicit Torn Intel country code should be preferred.'
Assert-Equal (Get-RecoveryCountryCode -Countries $countries -CountryId 'mexico') 'mex' 'Prometheus code should remain a safe compatibility fallback.'
Assert-Equal (Get-RecoveryCountryCode -Countries $countries -CountryId 'missing') '' 'Unknown country must fail closed.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "History recovery unit tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'History recovery local trigger/timestamp tests passed.' -ForegroundColor Green
exit 0
