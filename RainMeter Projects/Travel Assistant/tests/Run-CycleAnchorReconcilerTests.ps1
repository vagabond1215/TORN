$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1') -SkipMain

$failures = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]
function Assert-Equal([string]$Name,$Actual,$Expected) {
    if ($Actual -ne $Expected) { $script:failures.Add("$Name - expected '$Expected', got '$Actual'") }
    else { $script:passes.Add($Name) }
}
function Assert-True([string]$Name,[bool]$Condition) {
    if (-not $Condition) { $script:failures.Add($Name) } else { $script:passes.Add($Name) }
}

$rows = @(
    [pscustomobject]@{ timestamp=100L; stock=0L },
    [pscustomobject]@{ timestamp=110L; stock=0L },
    [pscustomobject]@{ timestamp=120L; stock=50L },
    [pscustomobject]@{ timestamp=130L; stock=20L },
    [pscustomobject]@{ timestamp=140L; stock=0L },
    [pscustomobject]@{ timestamp=150L; stock=40L }
)
$transition = Get-AnchorTransitions -Rows $rows
Assert-Equal 'Latest real restock transition is used' ([long]$transition.lastRestockAt) 150L
Assert-Equal 'Latest real sellout transition is retained' ([long]$transition.lastSellOutAt) 140L
Assert-Equal 'Latest observation timestamp is retained' ([long]$transition.latestTimestamp) 150L

$gapPolicy=[pscustomobject]@{expectedPollSeconds=60;selloutSafeGapSeconds=180;restockSafeGapSeconds=180;selloutHardGapSeconds=600;restockHardGapSeconds=600}
$unknownRows=@(
    [pscustomobject]@{timestamp=1000L;stock=100L;transitionGapSeconds=60L;transitionBoundaryQuality='observed'},
    [pscustomobject]@{timestamp=2000L;stock=0L;previousFreshSourceTimestamp=1100L;transitionGapSeconds=900L;transitionBoundaryQuality='unknown_gap'}
)
$unknownTransition=Get-AnchorTransitions -Rows $unknownRows -BoundaryPolicy $gapPolicy
Assert-Equal 'Anchor repair does not fabricate sellout across unknown collection gap' ([long]$unknownTransition.lastSellOutAt) 0L
Assert-Equal 'Unknown transition records continuity invalidation timestamp' ([long]$unknownTransition.lastUnknownBoundaryAt) 2000L

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('travel-anchor-' + [guid]::NewGuid().ToString('N') + '.jsonl')
try {
    @(
        '{"country":"canada","itemId":206,"timestamp":200,"stock":999,"source":"history_bootstrap"}',
        '{"country":"canada","itemId":206,"timestamp":205,"sourceTimestamp":150,"stock":0,"source":"retention_baseline"}',
        '{"country":"canada","itemId":206,"timestamp":210,"sourceTimestamp":210,"stock":0,"source":"prometheus"}',
        '{"country":"canada","itemId":206,"timestamp":220,"sourceTimestamp":220,"stock":500,"source":"prometheus","previousFreshSourceTimestamp":210,"transitionGapSeconds":10,"transitionBoundaryQuality":"observed"}',
        '{"country":"canada","itemId":206,"timestamp":230,"stock":999,"source":"history_repair_baseline"}'
    ) | Set-Content -LiteralPath $temp -Encoding UTF8
    $wanted = @{ 'canada:206'=$true }
    $map = Read-AnchorObservationMap -Path $temp -Wanted $wanted
    Assert-True 'Wanted market is loaded from retained observation evidence' ($map.ContainsKey('canada:206'))
    Assert-Equal 'Synthetic migration rows are excluded while retention predecessor remains available' $map['canada:206'].Count 3
    $filtered = Get-AnchorTransitions -Rows @($map['canada:206'].ToArray())
    Assert-Equal 'Filtered real 0-to-stock transition anchors restock' ([long]$filtered.lastRestockAt) 220L
} finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}

foreach ($name in $passes) { Write-Host "PASS $name" -ForegroundColor DarkGreen }
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'Observation-derived cycle anchor tests passed.' -ForegroundColor Green
exit 0
