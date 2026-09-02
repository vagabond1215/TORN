$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$UpdaterPath = Join-Path $ProjectRoot '@Resources\Scripts\UpdateTracker.ps1'
$FixtureDir = Join-Path $PSScriptRoot 'fixtures'
$failures = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) {
        $script:failures.Add("$Name - expected '$Expected', got '$Actual'")
    } else {
        $script:passes.Add($Name)
    }
}

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        $suffix = if ([string]::IsNullOrWhiteSpace($Details)) { '' } else { " - $Details" }
        $script:failures.Add("$Name$suffix")
    } else {
        $script:passes.Add($Name)
    }
}

function Import-ProductionFunctions {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($UpdaterPath, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw ('UpdateTracker.ps1 has parser errors: ' + ((@($parseErrors) | ForEach-Object { $_.Message }) -join '; '))
    }

    $wanted = @(
        'Get-DynamicProperty',
        'Get-Median',
        'Get-LiveStockObservation',
        'Get-YataObservation',
        'Load-Cycles',
        'Get-LiveStockoutEstimate',
        'Get-Recommendation'
    )

    $definitions = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
    }, $true))

    foreach ($name in $wanted) {
        $definition = @($definitions | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
        if ($definition.Count -ne 1) { throw "Could not locate production function '$name' in UpdateTracker.ps1" }
        $source = [string]$definition[0].Extent.Text
        $scoped = $source -replace ('^function\s+' + [regex]::Escape($name)), ('function script:' + $name)
        Invoke-Expression $scoped
    }
}

function New-Settings {
    return [pscustomobject]@{
        staleAfterSeconds = 300
        cycleRetentionDays = 90
        profitability = [pscustomobject]@{
            sellTarget = 'item_market'
            itemMarketFeePercent = 5.0
            minimumProfitPerItem = 50000
            minimumMarginPercent = 5.0
        }
        recommendation = [pscustomobject]@{
            minimumComparableCycles = 5
            minimumSafeCycles = 8
            arrivalBufferSeconds = 60
            candidateStepSeconds = 30
        }
    }
}

function New-Country {
    param(
        [long]$Standard = 9060,
        [long]$Airstrip = 6360,
        [long]$Wlt = 4560,
        [long]$Business = 2700
    )
    return [pscustomobject]@{
        id = 'united_kingdom'
        providerCodes = [pscustomobject]@{ yata = 'uni' }
        travelSeconds = [pscustomobject]@{
            standard = $Standard
            airstrip = $Airstrip
            wlt = $Wlt
            business = $Business
        }
    }
}

function New-Observation {
    param(
        [long]$Now,
        [long]$Price,
        [int]$Stock = 0,
        [long]$SourceTimestamp = 0
    )
    if ($SourceTimestamp -le 0) { $SourceTimestamp = $Now }
    return [pscustomobject]@{
        schemaVersion = 1
        timestamp = $SourceTimestamp
        country = 'united_kingdom'
        itemId = 206
        stock = $Stock
        foreignPrice = $Price
        source = 'synthetic-test'
        sourceTimestamp = $SourceTimestamp
    }
}

function New-DestinationState {
    param([long]$LastSoldOutAt, $ActiveCycle = $null)
    return [pscustomobject]@{
        lastStock = 0
        lastForeignPrice = 0
        lastSourceTimestamp = 0
        lastSellOutAt = $LastSoldOutAt
        activeCycle = $ActiveCycle
    }
}

Import-ProductionFunctions

$SeedCycleFile = Join-Path $FixtureDir 'cycles-safe.jsonl'
$CycleFile = Join-Path $FixtureDir 'cycles-safe.jsonl'

$now = 1787168500
$settings = New-Settings
$country = New-Country

$yata = Get-Content -LiteralPath (Join-Path $FixtureDir 'yata-export.sample.json') -Raw | ConvertFrom-Json
$yataObs = Get-YataObservation -Payload $yata -Country $country -Item ([pscustomobject]@{ itemId = 206 }) -Now $now
Assert-Equal 'YATA UK Xanax quantity normalization' ([int]$yataObs.stock) 1834
Assert-Equal 'YATA UK Xanax foreign-price normalization' ([long]$yataObs.foreignPrice) 728000
Assert-Equal 'YATA source timestamp normalization' ([long]$yataObs.sourceTimestamp) 1787168400

$dedupCycles = @(Load-Cycles -Country 'united_kingdom' -ItemId 206 -Cutoff ($now - 8640000))
Assert-Equal 'Seed/runtime cycle deduplication' $dedupCycles.Count 8

$CycleFile = Join-Path $FixtureDir 'cycles-safe.jsonl'
$SeedCycleFile = Join-Path $FixtureDir '__empty__.jsonl'
$safeObs = New-Observation -Now $now -Price 822000
$safeState = New-DestinationState -LastSoldOutAt ($now - 3000)
$safeRec = Get-Recommendation -Settings $settings -Country $country -Observation $safeObs -DestState $safeState -ResalePrice 1000000 -TravelMode 'airstrip' -Now $now -RecentObservations @()
Assert-Equal 'High-price long-stock scenario selects SAFE_WINDOW' $safeRec.Status 'SAFE_WINDOW'
Assert-True 'Safe window close remains in the future' ([long]$safeRec.WindowCloseAt -gt $now)

$CycleFile = Join-Path $FixtureDir 'cycles-fast.jsonl'
$fastObs = New-Observation -Now $now -Price 722000
$fastState = New-DestinationState -LastSoldOutAt ($now - 500)
$fastRec = Get-Recommendation -Settings $settings -Country $country -Observation $fastObs -DestState $fastState -ResalePrice 950000 -TravelMode 'airstrip' -Now $now -RecentObservations @()
Assert-Equal 'Low-price fast-depletion scenario selects BEST_ODDS' $fastRec.Status 'BEST_ODDS'
Assert-True 'Best-odds departure is current/future' ([long]$fastRec.BestDepartureAt -ge ($now - 60))
Assert-True 'Best-odds hit rate is probabilistic' ([double]$fastRec.HitRate -gt 0 -and [double]$fastRec.HitRate -lt 1)

$CycleFile = Join-Path $FixtureDir 'cycles-safe.jsonl'
$lowMarginObs = New-Observation -Now $now -Price 742000
$lowMarginState = New-DestinationState -LastSoldOutAt ($now - 3000)
$lowMargin = Get-Recommendation -Settings $settings -Country $country -Observation $lowMarginObs -DestState $lowMarginState -ResalePrice 830000 -TravelMode 'airstrip' -Now $now -RecentObservations @()
Assert-Equal 'Fee-adjusted low margin suppresses recommendation' $lowMargin.Status 'LOW_MARGIN'
Assert-Equal 'Low-margin result exposes no best departure' ([long]$lowMargin.BestDepartureAt) 0
Assert-Equal 'Low-margin result exposes no safe close' ([long]$lowMargin.WindowCloseAt) 0

$unprofitable = Get-Recommendation -Settings $settings -Country $country -Observation $lowMarginObs -DestState $lowMarginState -ResalePrice 760000 -TravelMode 'airstrip' -Now $now -RecentObservations @()
Assert-Equal 'Fee-adjusted negative spread is UNPROFITABLE' $unprofitable.Status 'UNPROFITABLE'

$staleObs = New-Observation -Now $now -Price 742000 -SourceTimestamp ($now - 301)
$stale = Get-Recommendation -Settings $settings -Country $country -Observation $staleObs -DestState $lowMarginState -ResalePrice 1000000 -TravelMode 'airstrip' -Now $now -RecentObservations @()
Assert-Equal 'Stale source suppresses recommendation' $stale.Status 'STALE_DATA'

$airRec = Get-Recommendation -Settings $settings -Country $country -Observation $safeObs -DestState $safeState -ResalePrice 1000000 -TravelMode 'airstrip' -Now $now -RecentObservations @()
$wltRec = Get-Recommendation -Settings $settings -Country $country -Observation $safeObs -DestState $safeState -ResalePrice 1000000 -TravelMode 'wlt' -Now $now -RecentObservations @()
Assert-Equal 'WLT scenario remains safe with same cycles' $wltRec.Status 'SAFE_WINDOW'
Assert-True 'Travel mode changes safe-window timing' ([long]$airRec.WindowCloseAt -ne [long]$wltRec.WindowCloseAt)

$shortCountry = New-Country -Standard 900 -Airstrip 600 -Wlt 450 -Business 300
$activeRestockAt = $now - 240
$activeCycle = [pscustomobject]@{
    previousSoldOutAt = $now - 7500
    restockAt = $activeRestockAt
    restockQuantity = 2500
    foreignPrice = 822000
    source = 'synthetic-test'
}
$activeState = New-DestinationState -LastSoldOutAt ($now - 7500) -ActiveCycle $activeCycle
$activeObs = New-Observation -Now $now -Price 822000 -Stock 100

$twoSamples = @(
    [pscustomobject]@{ timestamp = $activeRestockAt; stock = 2500 },
    [pscustomobject]@{ timestamp = $now; stock = 100 }
)
$historicalLive = Get-Recommendation -Settings $settings -Country $shortCountry -Observation $activeObs -DestState $activeState -ResalePrice 1000000 -TravelMode 'airstrip' -Now $now -RecentObservations $twoSamples
Assert-Equal 'Live cycle without enough slope evidence retains historical SAFE_WINDOW' $historicalLive.Status 'SAFE_WINDOW'
$historicalClose = [long]$historicalLive.WindowCloseAt

$fastLiveSamples = @(
    [pscustomobject]@{ timestamp = $activeRestockAt; stock = 2500 },
    [pscustomobject]@{ timestamp = $activeRestockAt + 120; stock = 1000 },
    [pscustomobject]@{ timestamp = $activeRestockAt + 240; stock = 100 }
)
$depletingLive = Get-Recommendation -Settings $settings -Country $shortCountry -Observation $activeObs -DestState $activeState -ResalePrice 1000000 -TravelMode 'airstrip' -Now $now -RecentObservations $fastLiveSamples
Assert-Equal 'Fast current depletion closes unsafe live arrival' $depletingLive.Status 'WINDOW_CLOSED'
Assert-True 'Live depletion never extends historical safe close' ([long]$depletingLive.WindowCloseAt -le $historicalClose)

Write-Host "Passed: $($passes.Count)" -ForegroundColor Green
foreach ($name in $passes) { Write-Host "  PASS $name" -ForegroundColor DarkGreen }

if ($failures.Count -gt 0) {
    Write-Host "Failed: $($failures.Count)" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  FAIL $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Travel Assistant production-model fixture tests passed.' -ForegroundColor Green
exit 0
