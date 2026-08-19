param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,

    [ValidateRange(1, 720)]
    [int]$Hours = 168,

    [string]$SourceName = 'travel-planner-history',
    [switch]$ImportToSeed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RuntimeImportDir = Join-Path $ProjectRoot 'data\runtime\historical-imports'
$CycleBuilder = Join-Path $PSScriptRoot 'Build-CyclesFromObservations.ps1'
$SeedImporter = Join-Path $PSScriptRoot 'Import-SeedHistory.ps1'

function Normalize-BaseUrl {
    param([string]$Url)
    $trimmed = $Url.Trim().TrimEnd('/')
    $uri = $null
    if (-not [Uri]::TryCreate($trimmed, [UriKind]::Absolute, [ref]$uri)) { throw "Invalid -BaseUrl: $Url" }
    if ($uri.Scheme -notin @('https','http')) { throw 'BaseUrl must use http or https.' }
    return $trimmed
}

function Get-History {
    param([string]$Base, [string]$CountryCode, [int]$ItemId, [int]$HoursBack)
    $url = "$Base/api/history/$CountryCode/$ItemId?hours=$HoursBack"
    Write-Host ("GET {0}" -f $url) -ForegroundColor Cyan
    try {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $payload = Invoke-RestMethod -Method Get -Uri $url -Headers @{ Accept = 'application/json' } -TimeoutSec 30
        $watch.Stop()
    } catch {
        throw "History request failed for ${CountryCode}: $($_.Exception.Message)"
    }
    if ($null -eq $payload -or -not $payload.PSObject.Properties['points']) { throw "History response for $CountryCode has no points array." }
    Write-Host ("  {0} points in {1:N0} ms" -f @($payload.points).Count, $watch.Elapsed.TotalMilliseconds) -ForegroundColor Green
    return $payload
}

function Write-JsonLinesAtomic {
    param([string]$Path, [object[]]$Rows)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tmp = $Path + '.tmp'
    $writer = New-Object System.IO.StreamWriter($tmp, $false, [System.Text.UTF8Encoding]::new($false))
    try {
        foreach ($row in $Rows) { $writer.WriteLine(($row | ConvertTo-Json -Compress -Depth 10)) }
    } finally { $writer.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

$base = Normalize-BaseUrl $BaseUrl
$requests = @(
    [pscustomobject]@{ countryCode = 'uni'; country = 'united_kingdom'; itemId = 206 },
    [pscustomobject]@{ countryCode = 'jap'; country = 'japan'; itemId = 206 }
)

$observations = New-Object System.Collections.Generic.List[object]
foreach ($request in $requests) {
    $history = Get-History -Base $base -CountryCode $request.countryCode -ItemId $request.itemId -HoursBack $Hours
    foreach ($point in @($history.points)) {
        foreach ($name in @('yata_ts','quantity','cost')) {
            if (-not $point.PSObject.Properties[$name]) { throw "History point for $($request.countryCode) is missing '$name'." }
        }
        $ts = [long]$point.yata_ts
        if ($ts -le 0) { continue }
        $observations.Add([pscustomobject]@{
            schemaVersion = 1
            timestamp = $ts
            country = [string]$request.country
            itemId = [int]$request.itemId
            stock = [int]$point.quantity
            foreignPrice = [long]$point.cost
            source = $SourceName
            sourceTimestamp = $ts
        })
    }
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$dedup = New-Object System.Collections.Generic.List[object]
foreach ($row in @($observations | Sort-Object country, itemId, timestamp)) {
    $key = ('{0}|{1}|{2}|{3}|{4}' -f [string]$row.country, [int]$row.itemId, [long]$row.timestamp, [int]$row.stock, [long]$row.foreignPrice)
    if ($seen.Add($key)) { $dedup.Add($row) }
}

if ($dedup.Count -eq 0) { throw 'The history endpoint returned no usable UK/Japan Xanax observations.' }

New-Item -ItemType Directory -Force -Path $RuntimeImportDir | Out-Null
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
$observationPath = Join-Path $RuntimeImportDir ("travel-planner-$stamp-observations.jsonl")
$cyclePath = Join-Path $RuntimeImportDir ("travel-planner-$stamp-cycles.jsonl")
Write-JsonLinesAtomic -Path $observationPath -Rows @($dedup)

& $CycleBuilder -InputPath $observationPath -OutputPath $cyclePath
if ($LASTEXITCODE -ne 0) { throw "Cycle builder failed with exit code $LASTEXITCODE." }

$cycleCount = 0
if (Test-Path -LiteralPath $cyclePath) {
    $cycleCount = @((Get-Content -LiteralPath $cyclePath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}

Write-Host ''
Write-Host ("Candidate bootstrap: {0} observations, {1} completed cycles." -f $dedup.Count, $cycleCount) -ForegroundColor Green
Write-Host ("Observations: {0}" -f $observationPath)
Write-Host ("Cycles:       {0}" -f $cyclePath)

if (-not $ImportToSeed) {
    Write-Host 'Preview only. Review the runtime-only files, provider ownership/usage expectations, and timestamps before importing to Git seed.' -ForegroundColor Yellow
    Write-Host 'Rerun with -ImportToSeed only after the endpoint is verified as appropriate for bounded bootstrap use.' -ForegroundColor Yellow
    exit 0
}

& $SeedImporter -ObservationPath $observationPath -CyclePath $cyclePath -SourceName $SourceName -SourceUrl $base -Notes ("Bounded $Hours-hour UK/Japan Xanax history import from a travel-planner-compatible public history API.")
if ($LASTEXITCODE -ne 0) { throw "Seed importer failed with exit code $LASTEXITCODE." }

Write-Host 'History merged into data/seed/. Review metadata and run tests before committing.' -ForegroundColor Green
exit 0
