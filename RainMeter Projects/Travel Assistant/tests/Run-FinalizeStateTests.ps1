$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SourceFinalizer = Join-Path $ProjectRoot '@Resources\Scripts\FinalizeState.ps1'
$SourceTravelProfile = Join-Path $ProjectRoot '@Resources\Scripts\TravelProfile.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TravelAssistant-Finalize-' + [Guid]::NewGuid().ToString('N'))
$scriptDir = Join-Path $tempRoot '@Resources\Scripts'
$configDir = Join-Path $tempRoot 'config'
$runtimeDir = Join-Path $tempRoot 'data\runtime'
$seedDir = Join-Path $tempRoot 'data\seed'
$generatedDir = Join-Path $tempRoot '@Resources\Generated'
$finalizer = Join-Path $scriptDir 'FinalizeState.ps1'
$travelProfileScript = Join-Path $scriptDir 'TravelProfile.ps1'
$localSettingsPath = Join-Path $configDir 'settings.local.json'

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "$Name - condition was false." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

function Write-JsonNoBom {
    param([string]$Path, [object]$Value)
    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Write-LocalProfitabilitySettings {
    param([int]$CapacityOverride = 0,[long]$ResaleStaleAfterSeconds = 21600)
    Write-JsonNoBom -Path $localSettingsPath -Value ([pscustomobject]@{
        schemaVersion = 1
        profitability = [pscustomobject]@{
            capacityOverride = $CapacityOverride
            resaleStaleAfterSeconds = $ResaleStaleAfterSeconds
            minimumProfitPerItem = 999999999
            minimumMarginPercent = 99
            minimumTotalTripProfit = 999999999
            itemMarketFeePercent = 50
        }
    })
}

function Write-LocalTravelProfileSettings {
    param([string]$CompanyType = 'none',[int]$CompanyStars = 0,[int]$FactionExcursionLevel = 0,[int]$FactionTravelCostLevel = 0)
    Write-JsonNoBom -Path $localSettingsPath -Value ([pscustomobject]@{
        schemaVersion = 1
        travelProfile = [pscustomobject]@{
            companyType = $CompanyType
            companyStars = $CompanyStars
            factionExcursionLevel = $FactionExcursionLevel
            factionTravelCostLevel = $FactionTravelCostLevel
        }
    })
}

function Clear-LocalSettings { if (Test-Path -LiteralPath $localSettingsPath) { Remove-Item -LiteralPath $localSettingsPath -Force } }

function Write-StateKv {
    param([hashtable]$Values)
    $lines = foreach ($key in ($Values.Keys | Sort-Object)) { "$key=$($Values[$key])" }
    [System.IO.File]::WriteAllLines((Join-Path $generatedDir 'state.kv'), @($lines), [System.Text.UTF8Encoding]::new($false))
}

function Read-StateKv {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $generatedDir 'state.kv')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $values[$line.Substring(0, $i)] = $line.Substring($i + 1)
    }
    return $values
}

function New-BaseState {
    param([string]$Mode='airstrip',[string]$UKStatus='SAFE_WINDOW',[long]$UKForeignPrice=700000,[int]$UKStock=0,[long]$Now=0)
    if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    return @{
        TravelMode=$Mode; TravelModeLabel=$Mode; UpdatedText='test'
        UKTravelSeconds=6360; UKStock=$UKStock; UKForeignPrice=$UKForeignPrice; UKLastSoldOutAt=$Now-300
        UKRestockEstimateAt=$Now+7200; UKWindowOpenAt=$Now+300; UKWindowCloseAt=$Now+1200; UKBestDepartureAt=0; UKHitRate=1
        UKStatus=$UKStatus; UKMessage='timing survives economics'
        JPTravelSeconds=8940; JPStock=0; JPForeignPrice=700000; JPLastSoldOutAt=0; JPRestockEstimateAt=0
        JPWindowOpenAt=0; JPWindowCloseAt=0; JPBestDepartureAt=0; JPHitRate=0; JPStatus='INSUFFICIENT_HISTORY'; JPMessage='learning'
    }
}

function Write-EngineState {
    param([long]$Lowest,[long]$Average,[long]$FetchedAt,[long]$UKLastSellOutAt,$UKActiveCycle=$null)
    $engine=[pscustomobject]@{
        schemaVersion=1
        destinations=[pscustomobject]@{
            'united_kingdom:206'=[pscustomobject]@{lastStock=0;lastForeignPrice=0;lastSourceTimestamp=0;lastSellOutAt=$UKLastSellOutAt;activeCycle=$UKActiveCycle}
            'japan:206'=[pscustomobject]@{lastStock=0;lastForeignPrice=0;lastSourceTimestamp=0;lastSellOutAt=0;activeCycle=$null}
        }
        resaleCache=[pscustomobject]@{
            '206'=[pscustomobject]@{price=$Lowest;lowest=$Lowest;average=$Average;fetchedAt=$FetchedAt;source='test'}
        }
    }
    Write-JsonNoBom -Path (Join-Path $runtimeDir 'engine-state.json') -Value $engine
}

function Invoke-Finalizer {
    & $finalizer
    if (-not $?) { throw 'FinalizeState.ps1 reported a PowerShell execution failure.' }
    return Read-StateKv
}

New-Item -ItemType Directory -Force -Path $scriptDir,$configDir,$runtimeDir,$seedDir,$generatedDir | Out-Null
try {
    Copy-Item -LiteralPath $SourceFinalizer -Destination $finalizer
    Copy-Item -LiteralPath $SourceTravelProfile -Destination $travelProfileScript
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\settings.example.json') -Destination (Join-Path $configDir 'settings.example.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\items.json') -Destination (Join-Path $configDir 'items.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\countries.json') -Destination (Join-Path $configDir 'countries.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\travel-perks.json') -Destination (Join-Path $configDir 'travel-perks.json')
    [System.IO.File]::WriteAllText((Join-Path $seedDir 'cycles.jsonl'),'', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $runtimeDir 'cycles.jsonl'),'', [System.Text.UTF8Encoding]::new($false))

    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    Clear-LocalSettings
    $activeRestock=$now-120
    $activeCycle=[pscustomobject]@{previousSoldOutAt=$now-7200;restockAt=$activeRestock;restockQuantity=2500;foreignPrice=900000;source='test'}
    Write-StateKv -Values (New-BaseState -UKStatus 'SAFE_WINDOW' -UKForeignPrice 900000 -UKStock 1000 -Now $now)
    Write-EngineState -Lowest 850000 -Average 950000 -FetchedAt $now -UKLastSellOutAt ($now-7200) -UKActiveCycle $activeCycle
    $result=Invoke-Finalizer
    Assert-Equal 'Timing status survives negative/low compatibility economics' $result.UKStatus 'SAFE_WINDOW'
    Assert-True 'Timing window survives economics' ([long]$result.UKWindowCloseAt -gt $now)
    Assert-Equal 'Observed live restock retained independently of value' ([long]$result.UKRestockEstimateAt) $activeRestock
    Assert-Equal 'Observed live restock marked live' $result.UKRestockSampleCount 'live'
    Assert-Equal 'Compatibility economics use Torn average MV, not lowest listing' ([long]$result.UKMarketValue) 950000
    Assert-Equal '100 percent MV basis retained in compatibility field' ([long]$result.UKNetResalePrice) 950000

    Clear-LocalSettings
    Write-StateKv -Values (New-BaseState -UKStatus 'SAFE_WINDOW' -UKForeignPrice 700000 -Now $now)
    Write-EngineState -Lowest 800000 -Average 1000000 -FetchedAt ($now-21601) -UKLastSellOutAt ($now-300)
    $result=Invoke-Finalizer
    Assert-Equal 'Stale MV no longer downgrades timing' $result.UKStatus 'SAFE_WINDOW'
    Assert-True 'Stale MV no longer clears timing' ([long]$result.UKWindowCloseAt -gt $now)
    Assert-Equal 'Stale MV remains exposed informationally' ([int]$result.UKResaleFresh) 0

    Write-LocalProfitabilitySettings -CapacityOverride 0
    $standard=New-BaseState -Mode 'standard' -UKStatus 'SAFE_WINDOW' -UKForeignPrice 900000 -Now $now
    $standard.UKTravelSeconds=9060
    Write-StateKv -Values $standard
    Write-EngineState -Lowest 800000 -Average 850000 -FetchedAt $now -UKLastSellOutAt ($now-300)
    $result=Invoke-Finalizer
    Assert-Equal 'Legacy minimum-profit settings do not close timing' $result.UKStatus 'SAFE_WINDOW'
    Assert-True 'Legacy minimum-profit settings leave window intact' ([long]$result.UKWindowCloseAt -gt $now)
    Assert-Equal 'Standard UK travel cost remains informational' ([long]$result.UKTravelCost) 18000
    Assert-Equal 'Standard UK base capacity remains modeled' ([int]$result.UKCapacity) 10
    Assert-Equal 'Negative trip profit remains informational' ([long]$result.UKTripProfit) -518000
    Assert-Equal 'Required trip profit is retired as a timing gate' ([long]$result.UKRequiredTripProfit) 0

    Clear-LocalSettings
    $business=New-BaseState -Mode 'business' -UKStatus 'BEST_ODDS' -UKForeignPrice 700000 -Now $now
    $business.UKTravelSeconds=2700; $business.UKBestDepartureAt=$now+300
    Write-StateKv -Values $business
    Write-EngineState -Lowest 900000 -Average 1000000 -FetchedAt $now -UKLastSellOutAt ($now-300)
    $result=Invoke-Finalizer
    Assert-Equal 'Unresolved Business cost no longer suppresses timing' $result.UKStatus 'BEST_ODDS'
    Assert-True 'Unresolved Business leaves best departure intact' ([long]$result.UKBestDepartureAt -gt $now)
    Assert-Equal 'Unresolved Business cost remains explicit' ([long]$result.UKTravelCost) -1

    Write-LocalTravelProfileSettings -CompanyType 'lingerie_store' -CompanyStars 10 -FactionExcursionLevel 10 -FactionTravelCostLevel 5
    Write-StateKv -Values $business
    Write-EngineState -Lowest 900000 -Average 1000000 -FetchedAt $now -UKLastSellOutAt ($now-300)
    $result=Invoke-Finalizer
    Assert-Equal '10-star Lingerie makes Business cost known' ([long]$result.UKTravelCost) 0
    Assert-Equal 'Company and faction capacity remains modeled' ([int]$result.UKCapacity) 27
    Assert-Equal 'BEST_ODDS remains untouched by compatibility economics' $result.UKStatus 'BEST_ODDS'

    Write-LocalProfitabilitySettings -CapacityOverride 30
    Write-StateKv -Values (New-BaseState -Mode 'airstrip' -UKStatus 'SAFE_WINDOW' -UKForeignPrice 700000 -Now $now)
    Write-EngineState -Lowest 750000 -Average 800000 -FetchedAt $now -UKLastSellOutAt ($now-300)
    $result=Invoke-Finalizer
    Assert-Equal 'Capacity override remains authoritative' ([int]$result.UKCapacity) 30
    Assert-Equal 'Capacity override scales informational trip value' ([long]$result.UKTripProfit) 3000000
    Assert-Equal 'Capacity override cannot suppress timing' $result.UKStatus 'SAFE_WINDOW'

    Clear-LocalSettings
    Write-Host 'FinalizeState informational economics/restock tests passed.' -ForegroundColor Green
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
