$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SourceFinalizer = Join-Path $ProjectRoot '@Resources\Scripts\FinalizeState.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TravelAssistant-RestockDisplay-' + [Guid]::NewGuid().ToString('N'))
$scriptDir = Join-Path $tempRoot '@Resources\Scripts'
$configDir = Join-Path $tempRoot 'config'
$runtimeDir = Join-Path $tempRoot 'data\runtime'
$seedDir = Join-Path $tempRoot 'data\seed'
$generatedDir = Join-Path $tempRoot '@Resources\Generated'
$finalizer = Join-Path $scriptDir 'FinalizeState.ps1'

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

function Write-JsonNoBom {
    param([string]$Path, [object]$Value)
    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Write-JsonLinesNoBom {
    param([string]$Path, [object[]]$Rows)
    $writer = New-Object System.IO.StreamWriter($Path, $false, [System.Text.UTF8Encoding]::new($false))
    try { foreach ($row in $Rows) { $writer.WriteLine(($row | ConvertTo-Json -Compress -Depth 10)) } }
    finally { $writer.Dispose() }
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

New-Item -ItemType Directory -Force -Path $scriptDir, $configDir, $runtimeDir, $seedDir, $generatedDir | Out-Null
try {
    Copy-Item -LiteralPath $SourceFinalizer -Destination $finalizer
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\settings.example.json') -Destination (Join-Path $configDir 'settings.example.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\items.json') -Destination (Join-Path $configDir 'items.json')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'config\countries.json') -Destination (Join-Path $configDir 'countries.json')
    [System.IO.File]::WriteAllText((Join-Path $seedDir 'cycles.jsonl'), '', [System.Text.UTF8Encoding]::new($false))

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $lastSellOutAt = $now - 300
    $delays = @(7000, 7100, 7200, 7300, 7400)
    $cycles = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $delays.Count; $i++) {
        $restockAt = $now - 20000 - ($i * 2000)
        $soldOutAt = $restockAt + 600
        $cycles.Add([pscustomobject]@{
            schemaVersion = 1
            country = 'united_kingdom'
            itemId = 206
            foreignPrice = 900000
            restockAt = $restockAt
            restockQuantity = 2500
            soldOutAt = $soldOutAt
            availabilitySeconds = 600
            previousSoldOutAt = $restockAt - [long]$delays[$i]
            restockDelaySeconds = [long]$delays[$i]
            source = 'synthetic-restock-display'
        })
    }
    Write-JsonLinesNoBom -Path (Join-Path $runtimeDir 'cycles.jsonl') -Rows $cycles.ToArray()

    $engine = [pscustomobject]@{
        schemaVersion = 1
        lastPruneAt = 0
        destinations = [pscustomobject]@{
            'united_kingdom:206' = [pscustomobject]@{
                lastStock = 0
                lastForeignPrice = 900000
                lastSourceTimestamp = $now
                lastSellOutAt = $lastSellOutAt
                activeCycle = $null
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
                price = 950000
                lowest = 950000
                average = 950000
                fetchedAt = $now
                source = 'synthetic-restock-display'
            }
        }
    }
    Write-JsonNoBom -Path (Join-Path $runtimeDir 'engine-state.json') -Value $engine

    Write-StateKv -Values @{
        TravelMode = 'airstrip'
        TravelModeLabel = 'Airstrip'
        UpdatedText = 'test'
        UKTravelSeconds = 6360
        UKStock = 0
        UKForeignPrice = 900000
        UKLastSoldOutAt = $lastSellOutAt
        UKRestockEstimateAt = 0
        UKWindowOpenAt = 0
        UKWindowCloseAt = 0
        UKBestDepartureAt = 0
        UKHitRate = 0
        UKStatus = 'LOW_MARGIN'
        UKMessage = 'No departure recommendation'
        JPTravelSeconds = 8940
        JPStock = 0
        JPForeignPrice = 0
        JPLastSoldOutAt = 0
        JPRestockEstimateAt = 0
        JPWindowOpenAt = 0
        JPWindowCloseAt = 0
        JPBestDepartureAt = 0
        JPHitRate = 0
        JPStatus = 'INSUFFICIENT_HISTORY'
        JPMessage = 'learning'
    }

    & $finalizer
    if (-not $?) { throw 'FinalizeState.ps1 reported a PowerShell execution failure.' }
    $result = Read-StateKv

    Assert-Equal 'LOW_MARGIN remains the travel recommendation status' $result.UKStatus 'LOW_MARGIN'
    Assert-Equal 'Median restock delay is applied despite LOW_MARGIN' ([long]$result.UKRestockEstimateAt) ($lastSellOutAt + 7200)
    Assert-Equal 'Restock sample count retained' ([int]$result.UKRestockSampleCount) 5
    Assert-Equal 'Restock minimum delay retained' ([long]$result.UKRestockMinDelay) 7000
    Assert-Equal 'Restock maximum delay retained' ([long]$result.UKRestockMaxDelay) 7400
    Assert-Equal 'LOW_MARGIN exposes no safe-window close' ([long]$result.UKWindowCloseAt) 0

    Write-Host 'Independent restock display tests passed.' -ForegroundColor Green
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
