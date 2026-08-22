$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceScript = Join-Path $ProjectRoot '@Resources\Scripts\MaintainObservationHistory.ps1'
if (-not (Test-Path -LiteralPath $sourceScript)) { throw 'MaintainObservationHistory.ps1 is missing.' }

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TravelAssistantHistoryTest-' + [Guid]::NewGuid().ToString('N'))
$scriptDir = Join-Path $tempRoot '@Resources\Scripts'
$configDir = Join-Path $tempRoot 'config'
$runtimeDir = Join-Path $tempRoot 'data\runtime'
New-Item -ItemType Directory -Force -Path $scriptDir,$configDir,$runtimeDir | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination (Join-Path $scriptDir 'MaintainObservationHistory.ps1')

$now = 1000000L
$retentionHours = 48
$observationCutoff = $now - ($retentionHours * 3600)
$cycleCutoff = $now - (90L * 86400)

$settings = [pscustomobject]@{
    schemaVersion = 1
    highResolutionRetentionHours = $retentionHours
    cycleRetentionDays = 90
}
$settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $configDir 'settings.example.json') -Encoding UTF8

$observedMarkets = [pscustomobject]@{}
$observedMarkets | Add-Member NoteProperty 'alpha:1' ([pscustomobject]@{ country='alpha'; itemId=1; providerName='Alpha Item'; lastStock=3; lastForeignPrice=100; source='fixture'; sourceTimestamp=999900; lastSeenAt=999900 })
$observedMarkets | Add-Member NoteProperty 'beta:2' ([pscustomobject]@{ country='beta'; itemId=2; providerName='Beta Item'; lastStock=7; lastForeignPrice=200; source='fixture'; sourceTimestamp=999901; lastSeenAt=999901 })
$observedMarkets | Add-Member NoteProperty 'gamma:3' ([pscustomobject]@{ country='gamma'; itemId=3; providerName='Gamma Item'; lastStock=9; lastForeignPrice=300; source='fixture'; sourceTimestamp=999902; lastSeenAt=999902 })
$engine = [pscustomobject]@{ schemaVersion=1; lastPruneAt=0; observedMarkets=$observedMarkets; destinations=[pscustomobject]@{}; resaleCache=[pscustomobject]@{} }
$engine | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runtimeDir 'engine-state.json') -Encoding UTF8

$observationFile = Join-Path $runtimeDir 'observations.jsonl'
@(
    [pscustomobject]@{schemaVersion=1;timestamp=100000;country='alpha';itemId=1;stock=5;foreignPrice=100;source='fixture';sourceTimestamp=100000},
    [pscustomobject]@{schemaVersion=1;timestamp=900000;country='alpha';itemId=1;stock=3;foreignPrice=100;source='fixture';sourceTimestamp=900000},
    [pscustomobject]@{schemaVersion=1;timestamp=200000;country='beta';itemId=2;stock=7;foreignPrice=200;source='fixture';sourceTimestamp=200000}
) | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $observationFile -Encoding UTF8

$cycleFile = Join-Path $runtimeDir 'cycles.jsonl'
@(
    [pscustomobject]@{schemaVersion=1;country='alpha';itemId=1;restockAt=1;soldOutAt=($cycleCutoff-1);availabilitySeconds=10;restockDelaySeconds=10},
    [pscustomobject]@{schemaVersion=1;country='alpha';itemId=1;restockAt=2;soldOutAt=($cycleCutoff+1);availabilitySeconds=10;restockDelaySeconds=10}
) | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -LiteralPath $cycleFile -Encoding UTF8

$testScript = Join-Path $scriptDir 'MaintainObservationHistory.ps1'
try {
    & $testScript -Phase PreUpdate -Now $now

    $rows = @(Get-Content -LiteralPath $observationFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    $alphaBaseline = @($rows | Where-Object { $_.country -eq 'alpha' -and [long]$_.timestamp -eq $observationCutoff -and $_.source -eq 'retention_baseline' })
    if ($alphaBaseline.Count -ne 1 -or [int]$alphaBaseline[0].stock -ne 5) { throw 'Alpha predecessor was not rolled to the retention boundary.' }
    $alphaRecent = @($rows | Where-Object { $_.country -eq 'alpha' -and [long]$_.timestamp -eq 900000 })
    if ($alphaRecent.Count -ne 1 -or [int]$alphaRecent[0].stock -ne 3) { throw 'Alpha in-window change was not retained.' }
    $betaBaseline = @($rows | Where-Object { $_.country -eq 'beta' -and [long]$_.timestamp -eq $observationCutoff -and $_.source -eq 'retention_baseline' })
    if ($betaBaseline.Count -ne 1 -or [int]$betaBaseline[0].stock -ne 7) { throw 'Beta unchanged state lost its retention baseline.' }

    $cycles = @(Get-Content -LiteralPath $cycleFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($cycles.Count -ne 1 -or [long]$cycles[0].soldOutAt -ne ($cycleCutoff+1)) { throw 'Cycle retention pruning changed unexpectedly.' }

    $engineAfterPre = Get-Content -LiteralPath (Join-Path $runtimeDir 'engine-state.json') -Raw | ConvertFrom-Json
    if ([long]$engineAfterPre.lastPruneAt -ne $now) { throw 'PreUpdate did not advance lastPruneAt to suppress the destructive legacy prune.' }

    & $testScript -Phase PostUpdate -Now $now
    $rowsAfterPost = @(Get-Content -LiteralPath $observationFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    $gamma = @($rowsAfterPost | Where-Object { $_.country -eq 'gamma' -and [int]$_.itemId -eq 3 })
    if ($gamma.Count -ne 1 -or $gamma[0].source -ne 'history_bootstrap' -or [int]$gamma[0].stock -ne 9 -or [long]$gamma[0].timestamp -ne 999902) {
        throw 'Missing-market current-state bootstrap was not written truthfully.'
    }

    & $testScript -Phase PostUpdate -Now $now
    $rowsAfterSecondPost = @(Get-Content -LiteralPath $observationFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    if (@($rowsAfterSecondPost | Where-Object { $_.country -eq 'gamma' -and [int]$_.itemId -eq 3 }).Count -ne 1) { throw 'PostUpdate bootstrap is not idempotent.' }

    Write-Host 'Change-only observation retention baseline and bootstrap tests passed.' -ForegroundColor Green
    exit 0
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
