$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]

function Pass([string]$Message) { $script:passes.Add($Message) }
function Fail([string]$Message) { $script:failures.Add($Message) }

$toolFiles = @(
    'tools\Probe-DroqsDb.ps1',
    'tools\Build-CyclesFromObservations.ps1',
    'tools\Import-SeedHistory.ps1'
)

foreach ($relative in $toolFiles) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing historical tool: $relative"; continue }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        foreach ($err in @($parseErrors)) { Fail "PowerShell parse error in ${relative}: $($err.Message)" }
    } else {
        Pass "PowerShell parser: $relative"
    }
}

$seedDir = Join-Path $ProjectRoot 'data\seed'
$metadataPath = Join-Path $seedDir 'metadata.json'
$observationPath = Join-Path $seedDir 'observations.jsonl'
$cyclePath = Join-Path $seedDir 'cycles.jsonl'

try { $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json }
catch { $metadata = $null; Fail "Invalid seed metadata JSON: $($_.Exception.Message)" }

function Read-JsonLines {
    param([string]$Path)
    $rows = New-Object System.Collections.Generic.List[object]
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $rows.Add(($line | ConvertFrom-Json)) }
        catch { Fail "Invalid JSONL in $Path line ${lineNumber}: $($_.Exception.Message)" }
    }
    return @($rows)
}

$observations = @(Read-JsonLines -Path $observationPath)
$cycles = @(Read-JsonLines -Path $cyclePath)

if ($null -ne $metadata) {
    if (-not $metadata.PSObject.Properties['schemaVersion'] -or [int]$metadata.schemaVersion -ne 1) {
        Fail 'Seed metadata must declare schemaVersion 1.'
    } else { Pass 'Seed metadata schemaVersion' }

    if (-not $metadata.PSObject.Properties['coverage']) {
        Fail 'Seed metadata has no coverage object.'
    } else {
        if ([int]$metadata.coverage.observationCount -ne $observations.Count) {
            Fail "Seed metadata observationCount does not match observations.jsonl ($($observations.Count))."
        } else { Pass 'Seed observation coverage matches metadata' }
        if ([int]$metadata.coverage.cycleCount -ne $cycles.Count) {
            Fail "Seed metadata cycleCount does not match cycles.jsonl ($($cycles.Count))."
        } else { Pass 'Seed cycle coverage matches metadata' }
    }

    foreach ($source in @($metadata.sources)) {
        $name = ''
        if ($source -is [string]) { $name = [string]$source }
        elseif ($source.PSObject.Properties['name']) { $name = [string]$source.name }
        if ($name.ToLowerInvariant() -match '(synthetic|fixture|test)') {
            Fail "Seed provenance contains a synthetic/test source: $name"
        }
    }
}

foreach ($row in $observations) {
    foreach ($required in @('schemaVersion','timestamp','country','itemId','stock','foreignPrice','source')) {
        if (-not $row.PSObject.Properties[$required]) { Fail "Seed observation missing '$required'." }
    }
    if ($row.PSObject.Properties['schemaVersion'] -and [int]$row.schemaVersion -ne 1) { Fail 'Seed observation has unsupported schemaVersion.' }
}
if ($observations.Count -ge 0) { Pass 'Seed observation contract scan completed' }

foreach ($row in $cycles) {
    foreach ($required in @('schemaVersion','country','itemId','foreignPrice','restockAt','restockQuantity','soldOutAt','availabilitySeconds','source')) {
        if (-not $row.PSObject.Properties[$required]) { Fail "Seed cycle missing '$required'." }
    }
    if ($row.PSObject.Properties['restockAt'] -and $row.PSObject.Properties['soldOutAt'] -and $row.PSObject.Properties['availabilitySeconds']) {
        if ([long]$row.availabilitySeconds -ne ([long]$row.soldOutAt - [long]$row.restockAt)) {
            Fail 'Seed cycle availabilitySeconds does not match observed timestamps.'
        }
    }
}
if ($cycles.Count -ge 0) { Pass 'Seed cycle contract scan completed' }

if ($failures.Count -gt 0) {
    Write-Host "Historical-tool validation failed: $($failures.Count)" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  FAIL $failure" -ForegroundColor Red }
    exit 1
}

Write-Host "Historical-tool validation passed: $($passes.Count) checks." -ForegroundColor Green
foreach ($pass in $passes) { Write-Host "  PASS $pass" -ForegroundColor DarkGreen }
exit 0
