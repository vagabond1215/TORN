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
    param(
        [int]$CapacityOverride = 0,
        [long]$MinimumTotalTripProfit = 0,
        [long]$ResaleStaleAfterSeconds = 600
    )
    $local = [pscustomobject]@{
        schemaVersion = 1
        profitability = [pscustomobject]@{
            capacityOverride = $CapacityOverride
            minimumTotalTripProfit = $MinimumTotalTripProfit
            resaleStaleAfterSeconds = $ResaleStaleAfterSeconds
        }
    }
    Write-JsonNoBom -Path $localSettingsPath -Value $local
}

function Write-LocalTravelProfileSettings {
    param(
        [string]$CompanyType = 'none',
        [int]$CompanyStars = 0,
        [int]$FactionExcursionLevel = 0,
        [int]$FactionTravelCostLevel = 0
    )
    $local = [pscustomobject]@{
        schemaVersion = 1
        travelProfile = [pscustomobject]@{
            companyType = $CompanyType
            companyStars = $CompanyStars
            factionExcursionLevel = $FactionExcursionLevel
            factionTravelCostLevel = $FactionTravelCostLevel
        }
    }
    Write-JsonNoBom -Path $localSettingsPath -Value $local
}

function Clear-LocalSettings {
    if (Test-Path -LiteralPath $localSettingsPath) { Remove-Item -LiteralPath $localSettingsPath -Force }
}

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
    param(
        [string]$Mode = 'airstrip',
        [string]$UKStatus = 'SAFE_WINDOW',
        [long]$UKForeignPrice = 700000,
        [int]$UKStock = 0,
        [long]$Now = 0
    )
    if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    return @{
        TravelMode = $Mode
        TravelModeLabel = $Mode
        UpdatedText = 'test'
        UKTravelSeconds = 6360
        UKStock = $UKStock
        UKForeignPrice = $UKForeignPrice
        UKLastSoldOutAt = $Now - 300
        UKRestockEstimateAt = $Now + 7200
        UKWindowOpenAt = $Now + 300
        UKWindowCloseAt = $Now + 1200
        UKBestDepartureAt = 0
        UKHitRate = 0
        UKStatus = $UKStatus
        UKMessage = 'pre-finalizer'
        JPTravelSeconds = 8940
        JPStock = 0
        JPForeignPrice = 700000
        JPLastSoldOutAt = 0
        JPRestockEstimateAt = 0
        JPWindowOpenAt = 0
        JPWindowCloseAt = 0
        JPBestDepartureAt = 0
        JPHitRate = 0
        JPStatus = 'INSUFFICIENT_HISTORY'
        JPMessage = 'learning'
    }
}

function Write-EngineState {
    param(
        [long]$ResalePrice,
        [long]$FetchedAt,
        [long]$UKLastSellOutAt,
        $UKActiveCycle = $null
    )
    $engine = [pscustomobject]@{
        schemaVersion = 1
        lastPruneAt = 0
        destinations = [pscustomobject]@{
            'united_kingdom:206' = [pscustomobject]@{
                lastStock = 0
                lastForeignPrice = 0
                lastSourceTimestamp = 0
                lastSellOutAt = $UKLastSellOutAt
                activeCycle = $UKActiveCycle
            }
            'japan:206' = [pscustomobject]@{
                lastStock = 0
                lastForeignPrice = 0
                lastSourceTimestamp = 0
                lastSellOutAt = 0
                activeCycle = $null
            }
        }
        resaleCache = [pscustomobject]@{
            '206' = [pscustomobject]@{
                price = $ResalePrice
                lowest = $ResalePrice
                average = $ResalePrice
                fetchedAt = $FetchedAt
                source = 'test'
            }
        }
    }
    Write-JsonNoBom -Path (Join-Path $runtimeDir 'engine-state.json') -Value $engine
}

function Invoke-Finalizer {
    & $finalizer
    if (-not $?) { throw 'FinalizeState.ps1 reported a PowerShell execution failure.' }
    return Read-StateKv
}

New-Item -ItemType Directory -Force -Path $scriptDir, $configDir, $runtimeDir, $seedDir, $generatedDir | Out-Null
try {
    Copy-Item -LiteralPath $SourceFinalizer -Destination $finalizer
    Copy-Item -LiteralPath $SourceTravelProfile -Destination $travelProfileScript
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\settings.example.json') -Destination (Join-Path $configDir 'settings.example.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\items.json') -Destination (Join-Path $configDir 'items.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\countries.json') -Destination (Join-Path $configDir 'countries.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\travel-perks.json') -Destination (Join-Path $configDir 'travel-perks.json')
    [System.IO.File]::WriteAllText((Join-Path $seedDir 'cycles.jsonl'), '', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $runtimeDir 'cycles.jsonl'), '', [System.Text.UTF8Encoding]::new($false))

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    Clear-LocalSettings
    $activeRestock = $now - 120
    $activeCycle = [pscustomobject]@{
        previousSoldOutAt = $now - 7200
        restockAt = $activeRestock
        restockQuantity = 2500
        foreignPrice = 900000
        source = 'test'
    }
    Write-StateKv -Values (New-BaseState -UKStatus 'LOW_MARGIN' -UKForeignPrice 900000 -UKStock 1000 -Now $now)
    Write-EngineState -ResalePrice 950000 -FetchedAt $now -UKLastSellOutAt ($now - 7200) -UKActiveCycle $activeCycle
    $result = Invoke-Finalizer
    Assert-Equal 'LOW_MARGIN status retained' $result.UKStatus 'LOW_MARGIN'
    Assert-Equal 'Observed live restock retained independently of profitability' ([long]$result.UKRestockEstimateAt) $activeRestock
    Assert-Equal 'Observed live restock marked live' $result.UKRestockSampleCount 'live'

    Clear-LocalSettings
    Write-StateKv -Values (New-BaseState -UKStatus 'SAFE_WINDOW' -UKForeignPrice 700000 -Now $now)
    Write-EngineState -ResalePrice 1000000 -FetchedAt ($now - 601) -UKLastSellOutAt ($now - 300)
    $result = Invoke-Finalizer
    Assert-Equal 'Stale resale downgrades timing to CHECK_EXTERNAL' $result.UKStatus 'CHECK_EXTERNAL'
    Assert-Equal 'Stale resale clears safe-window open time' ([long]$result.UKWindowOpenAt) 0
    Assert-Equal 'Stale resale clears safe-window close time' ([long]$result.UKWindowCloseAt) 0

    Clear-LocalSettings
    $standardState = New-BaseState -Mode 'standard' -UKStatus 'SAFE_WINDOW' -UKForeignPrice 700000 -Now $now
    $standardState.UKTravelSeconds = 9060
    Write-StateKv -Values $standardState
    Write-EngineState -ResalePrice 791000 -FetchedAt $now -UKLastSellOutAt ($now - 300)
    $result = Invoke-Finalizer
    Assert-Equal 'Standard travel cost pushes borderline opportunity to LOW_MARGIN' $result.UKStatus 'LOW_MARGIN'
    Assert-Equal 'Standard UK travel cost applied' ([long]$result.UKTravelCost) 18000
    Assert-Equal 'Standard UK base capacity applied' ([int]$result.UKCapacity) 10
    Assert-Equal 'Standard trip profit includes travel cost' ([long]$result.UKTripProfit) 496500
    Assert-Equal 'Standard LOW_MARGIN clears departure timing' ([long]$result.UKWindowCloseAt) 0

    Clear-LocalSettings
    Write-StateKv -Values (New-BaseState -Mode 'airstrip' -UKStatus 'SAFE_WINDOW' -UKForeignPrice 700000 -Now $now)
    Write-EngineState -ResalePrice 791000 -FetchedAt $now -UKLastSellOutAt ($now - 300)
    $result = Invoke-Finalizer
    Assert-Equal 'Airstrip zero-cost opportunity remains SAFE_WINDOW' $result.UKStatus 'SAFE_WINDOW'
    Assert-Equal 'Airstrip travel cost is zero' ([long]$result.UKTravelCost) 0
    Assert-Equal 'Airstrip base capacity applied' ([int]$result.UKCapacity) 15
    Assert-True 'Airstrip safe-window timing remains present' ([long]$result.UKWindowCloseAt -gt $now)

    Clear-LocalSettings
    $businessState = New-BaseState -Mode 'business' -UKStatus 'BEST_ODDS' -UKForeignPrice 700000 -Now $now
    $businessState.UKTravelSeconds = 2700
    $businessState.UKBestDepartureAt = $now + 300
    Write-StateKv -Values $businessState
    Write-EngineState -ResalePrice 1000000 -FetchedAt $now -UKLastSellOutAt ($now - 300)
    $result = Invoke-Finalizer
    Assert-Equal 'Unresolved Business economics suppress timing' $result.UKStatus 'CHECK_EXTERNAL'
    Assert-Equal 'Unresolved Business economics clears best departure' ([long]$result.UKBestDepartureAt) 0
    Assert-Equal 'Unresolved Business cost exposed as unknown' ([long]$result.UKTravelCost) -1

    Write-LocalTravelProfileSettings -CompanyType 'lingerie_store' -CompanyStars 10 -FactionExcursionLevel 10 -FactionTravelCostLevel 5
    $businessState = New-BaseState -Mode 'business' -UKStatus 'BEST_ODDS' -UKForeignPrice 700000 -Now $now
    $businessState.UKTravelSeconds = 2700
    $businessState.UKBestDepartureAt = $now + 300
    Write-StateKv -Values $businessState
    Write-EngineState -ResalePrice 1000000 -FetchedAt $now -UKLastSellOutAt ($now - 300)
    $result = Invoke-Finalizer
    Assert-Equal '10-star Lingerie makes Business economics known' ([long]$result.UKTravelCost) 0
    Assert-Equal 'Company and faction bonuses increase Business capacity' ([int]$result.UKCapacity) 27
    Assert-Equal 'Profitable free Business preserves BEST_ODDS' $result.UKStatus 'BEST_ODDS'
    Assert-True 'Free Business preserves best departure timing' ([long]$result.UKBestDepartureAt -gt $now)

    Write-LocalTravelProfileSettings -CompanyType 'lingerie_store' -CompanyStars 10 -FactionExcursionLevel 10 -FactionTravelCostLevel 5
    $standardState = New-BaseState -Mode 'standard' -UKStatus 'SAFE_WINDOW' -UKForeignPrice 700000 -Now $now
    $standardState.UKTravelSeconds = 9060
    Write-StateKv -Values $standardState
    Write-EngineState -ResalePrice 1000000 -FetchedAt $now -UKLastSellOutAt ($now - 300)
    $result = Invoke-Finalizer
    Assert-Equal 'Profile bonuses increase Standard capacity' ([int]$result.UKCapacity) 22
    Assert-Equal 'Faction travel-cost perk reduces Standard fare' ([long]$result.UKTravelCost) 4500

    Write-LocalProfitabilitySettings -CapacityOverride 30 -MinimumTotalTripProfit 1600000
    Write-StateKv -Values (New-BaseState -Mode 'airstrip' -UKStatus 'SAFE_WINDOW' -UKForeignPrice 700000 -Now $now)
    Write-EngineState -ResalePrice 791000 -FetchedAt $now -UKLastSellOutAt ($now - 300)
    $result = Invoke-Finalizer
    Assert-Equal 'Local capacity override is applied' ([int]$result.UKCapacity) 30
    Assert-Equal 'Capacity override trip profit scales correctly' ([long]$result.UKTripProfit) 1543500
    Assert-Equal 'Explicit total-trip floor becomes required trip profit' ([long]$result.UKRequiredTripProfit) 1600000
    Assert-Equal 'Explicit total-trip floor can suppress timing' $result.UKStatus 'LOW_MARGIN'
    Assert-Equal 'Total-trip floor failure clears departure timing' ([long]$result.UKWindowCloseAt) 0

    Clear-LocalSettings
    Write-Host 'FinalizeState trip/restock/profile guard tests passed.' -ForegroundColor Green
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}