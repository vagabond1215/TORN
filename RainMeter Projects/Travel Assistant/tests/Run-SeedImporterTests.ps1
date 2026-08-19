$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SourceImporter = Join-Path $ProjectRoot 'tools\Import-SeedHistory.ps1'
$SourceItems = Join-Path $ProjectRoot 'config\items.json'
$SourceCountries = Join-Path $ProjectRoot 'config\countries.json'
$Fixture = Join-Path $PSScriptRoot 'fixtures\normalized-observations.sample.jsonl'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TravelAssistant-SeedImport-' + [Guid]::NewGuid().ToString('N'))

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name — expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

function Read-JsonLines {
    param([string]$Path)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $rows.Add(($line | ConvertFrom-Json))
    }
    return @($rows)
}

New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'tools'), (Join-Path $tempRoot 'config'), (Join-Path $tempRoot 'data\seed'), (Join-Path $tempRoot 'candidate') | Out-Null
try {
    Copy-Item -LiteralPath $SourceImporter -Destination (Join-Path $tempRoot 'tools\Import-SeedHistory.ps1')
    Copy-Item -LiteralPath $SourceItems -Destination (Join-Path $tempRoot 'config\items.json')
    Copy-Item -LiteralPath $SourceCountries -Destination (Join-Path $tempRoot 'config\countries.json')

    $metadata = [pscustomobject]@{
        schemaVersion = 1
        status = 'empty-bootstrap'
        generatedAt = $null
        sources = @()
        items = @()
        countries = @()
        coverage = [pscustomobject]@{ observationCount = 0; cycleCount = 0 }
        notes = @()
    }
    $metadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempRoot 'data\seed\metadata.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tempRoot 'data\seed\observations.jsonl') -Value '' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tempRoot 'data\seed\cycles.jsonl') -Value '' -Encoding UTF8

    $candidateObsPath = Join-Path $tempRoot 'candidate\observations.jsonl'
    $writer = New-Object System.IO.StreamWriter($candidateObsPath, $false, [System.Text.UTF8Encoding]::new($false))
    try {
        foreach ($row in (Read-JsonLines -Path $Fixture)) {
            $row.source = 'provider-sample'
            $writer.WriteLine(($row | ConvertTo-Json -Compress -Depth 10))
        }
    } finally { $writer.Dispose() }

    $candidateCyclesPath = Join-Path $tempRoot 'candidate\cycles.jsonl'
    $cycles = @(
        [pscustomobject]@{
            schemaVersion = 1; country = 'united_kingdom'; itemId = 206; foreignPrice = 728000;
            restockAt = 1787000100; restockQuantity = 2500; soldOutAt = 1787000300;
            availabilitySeconds = 200; previousSoldOutAt = 0; restockDelaySeconds = 0; source = 'provider-sample'
        },
        [pscustomobject]@{
            schemaVersion = 1; country = 'united_kingdom'; itemId = 206; foreignPrice = 742000;
            restockAt = 1787001200; restockQuantity = 2600; soldOutAt = 1787001500;
            availabilitySeconds = 300; previousSoldOutAt = 1787000300; restockDelaySeconds = 900; source = 'provider-sample'
        }
    )
    $writer = New-Object System.IO.StreamWriter($candidateCyclesPath, $false, [System.Text.UTF8Encoding]::new($false))
    try { foreach ($row in $cycles) { $writer.WriteLine(($row | ConvertTo-Json -Compress -Depth 10)) } }
    finally { $writer.Dispose() }

    $importer = Join-Path $tempRoot 'tools\Import-SeedHistory.ps1'
    & $importer -ObservationPath $candidateObsPath -CyclePath $candidateCyclesPath -SourceName 'provider-sample' -SourceUrl 'https://example.invalid/history' -Notes 'isolated deterministic importer test'
    if ($LASTEXITCODE -ne 0) { throw "Seed importer exited with code $LASTEXITCODE." }

    $seedObs = @(Read-JsonLines -Path (Join-Path $tempRoot 'data\seed\observations.jsonl'))
    $seedCycles = @(Read-JsonLines -Path (Join-Path $tempRoot 'data\seed\cycles.jsonl'))
    $seedMetadata = Get-Content -LiteralPath (Join-Path $tempRoot 'data\seed\metadata.json') -Raw | ConvertFrom-Json

    Assert-Equal 'Seed importer observation count' $seedObs.Count 8
    Assert-Equal 'Seed importer cycle count' $seedCycles.Count 2
    Assert-Equal 'Seed metadata observation coverage' ([int]$seedMetadata.coverage.observationCount) 8
    Assert-Equal 'Seed metadata cycle coverage' ([int]$seedMetadata.coverage.cycleCount) 2
    Assert-Equal 'Seed metadata status' ([string]$seedMetadata.status) 'seeded'
    Assert-Equal 'Seed provenance source name' ([string]$seedMetadata.sources[0].name) 'provider-sample'

    # Re-importing identical data must not duplicate observations/cycles.
    & $importer -ObservationPath $candidateObsPath -CyclePath $candidateCyclesPath -SourceName 'provider-sample' -SourceUrl 'https://example.invalid/history' -Notes 'dedup replay'
    if ($LASTEXITCODE -ne 0) { throw "Seed importer dedup replay exited with code $LASTEXITCODE." }
    Assert-Equal 'Seed observation deduplication' (@(Read-JsonLines -Path (Join-Path $tempRoot 'data\seed\observations.jsonl')).Count) 8
    Assert-Equal 'Seed cycle deduplication' (@(Read-JsonLines -Path (Join-Path $tempRoot 'data\seed\cycles.jsonl')).Count) 2

    # Synthetic/test provenance must be rejected by default and must not mutate seed truth.
    $rejected = $false
    try {
        & $importer -ObservationPath $candidateObsPath -SourceName 'synthetic-test' -SourceUrl 'https://example.invalid/synthetic'
    } catch {
        $rejected = $true
    }
    Assert-Equal 'Synthetic seed import rejected by default' $rejected $true
    Assert-Equal 'Rejected import leaves observation count unchanged' (@(Read-JsonLines -Path (Join-Path $tempRoot 'data\seed\observations.jsonl')).Count) 8

    Write-Host 'Isolated seed importer tests passed.' -ForegroundColor Green
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
