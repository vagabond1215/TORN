param(
    [string]$ObservationPath = '',
    [string]$CyclePath = '',

    [Parameter(Mandatory = $true)]
    [string]$SourceName,

    [Parameter(Mandatory = $true)]
    [string]$SourceUrl,

    [string]$Notes = '',
    [switch]$AllowSynthetic
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$SeedObservationPath = Join-Path $SeedDir 'observations.jsonl'
$SeedCyclePath = Join-Path $SeedDir 'cycles.jsonl'
$MetadataPath = Join-Path $SeedDir 'metadata.json'
$CountriesPath = Join-Path $ProjectRoot 'config\countries.json'
$ItemsPath = Join-Path $ProjectRoot 'config\items.json'

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 20)
    $tmp = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tmp, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Write-JsonLinesAtomic {
    param([string]$Path, [object[]]$Rows)
    $tmp = $Path + '.tmp'
    $writer = New-Object System.IO.StreamWriter($tmp, $false, [System.Text.UTF8Encoding]::new($false))
    try {
        foreach ($row in $Rows) { $writer.WriteLine(($row | ConvertTo-Json -Compress -Depth 12)) }
    } finally { $writer.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-JsonLines {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return @() }
    $rows = New-Object System.Collections.Generic.List[object]
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $rows.Add(($line | ConvertFrom-Json)) }
        catch { throw "Invalid JSONL in '$Path' line ${lineNumber}: $($_.Exception.Message)" }
    }
    return $rows.ToArray()
}

function Assert-NotSynthetic {
    param([string]$Path, [string]$Source)
    if ($AllowSynthetic) { return }
    $combined = (($Path + ' ' + $Source).ToLowerInvariant())
    if ($combined -match '(synthetic|fixture|\\tests\\|/tests/|test-data|sample-fixture)') {
        throw 'Refusing synthetic/test/fixture data for production seed import. -AllowSynthetic is for isolated local tooling tests only.'
    }
}

function Validate-Observation {
    param([object]$Row, [System.Collections.Generic.HashSet[string]]$KnownCountries, [System.Collections.Generic.HashSet[int]]$KnownItems)
    foreach ($name in @('schemaVersion','timestamp','country','itemId','stock','foreignPrice','source','sourceTimestamp')) {
        if (-not $Row.PSObject.Properties[$name]) { throw "Observation is missing '$name'." }
    }
    if ([int]$Row.schemaVersion -notin @(1,2)) { throw 'Unsupported observation schemaVersion.' }
    if ([long]$Row.timestamp -le 0) { throw 'Observation timestamp must be positive.' }
    if ([long]$Row.sourceTimestamp -lt 0) { throw 'Observation sourceTimestamp cannot be negative.' }
    if ([int]$Row.stock -lt 0) { throw 'Observation stock cannot be negative.' }
    if ([long]$Row.foreignPrice -lt 0) { throw 'Observation foreignPrice cannot be negative.' }
    if (-not $KnownCountries.Contains([string]$Row.country)) { throw "Unknown configured country '$($Row.country)'." }
    if (-not $KnownItems.Contains([int]$Row.itemId)) { throw "Unknown configured itemId '$($Row.itemId)'." }
    if ([string]::IsNullOrWhiteSpace([string]$Row.source)) { throw 'Observation source cannot be empty.' }
}

function Validate-Cycle {
    param([object]$Row, [System.Collections.Generic.HashSet[string]]$KnownCountries, [System.Collections.Generic.HashSet[int]]$KnownItems)
    foreach ($name in @('schemaVersion','country','itemId','foreignPrice','restockAt','restockQuantity','soldOutAt','availabilitySeconds','source')) {
        if (-not $Row.PSObject.Properties[$name]) { throw "Cycle is missing '$name'." }
    }
    $schema=[int]$Row.schemaVersion
    if ($schema -notin @(1,2)) { throw 'Unsupported cycle schemaVersion.' }
    if (-not $KnownCountries.Contains([string]$Row.country)) { throw "Unknown configured country '$($Row.country)'." }
    if (-not $KnownItems.Contains([int]$Row.itemId)) { throw "Unknown configured itemId '$($Row.itemId)'." }
    if ([int]$Row.restockQuantity -le 0) { throw 'Cycle restockQuantity must be positive.' }
    if ([string]::IsNullOrWhiteSpace([string]$Row.source)) { throw 'Cycle source cannot be empty.' }

    if ($schema -eq 1) {
        if ([long]$Row.restockAt -le 0 -or [long]$Row.soldOutAt -le [long]$Row.restockAt) { throw 'Cycle restock/sellout timestamps are invalid.' }
        if ([long]$Row.availabilitySeconds -ne ([long]$Row.soldOutAt - [long]$Row.restockAt)) { throw 'Cycle availabilitySeconds does not match soldOutAt - restockAt.' }
        return
    }

    foreach ($name in @(
        'restockLowerBoundAt','restockUpperBoundAt','restockBoundaryQuality',
        'soldOutLowerBoundAt','soldOutUpperBoundAt','soldOutBoundaryQuality',
        'availabilityMinimumSeconds','availabilityMaximumSeconds','availabilityEligible',
        'previousSoldOutLowerBoundAt','previousSoldOutUpperBoundAt','previousSellOutBoundaryQuality',
        'restockDelayMinimumSeconds','restockDelayMaximumSeconds','restockDelayEligible',
        'forecastEligible','evidenceQuality'
    )) {
        if (-not $Row.PSObject.Properties[$name]) { throw "Schema-v2 cycle is missing '$name'." }
    }
    $restockLower=[long]$Row.restockLowerBoundAt
    $restockUpper=[long]$Row.restockUpperBoundAt
    $selloutLower=[long]$Row.soldOutLowerBoundAt
    $selloutUpper=[long]$Row.soldOutUpperBoundAt
    if ($restockLower -lt 0 -or $restockUpper -lt 0 -or ($restockLower -gt 0 -and $restockUpper -lt $restockLower)) { throw 'Schema-v2 restock bounds are invalid.' }
    if ($selloutLower -lt 0 -or $selloutUpper -le 0 -or ($selloutLower -gt 0 -and $selloutUpper -lt $selloutLower)) { throw 'Schema-v2 sellout bounds are invalid.' }
    $availabilityMinimum=[long]$Row.availabilityMinimumSeconds
    $availabilityMaximum=[long]$Row.availabilityMaximumSeconds
    if ($availabilityMinimum -lt 0 -or $availabilityMaximum -lt 0 -or ($availabilityMaximum -gt 0 -and $availabilityMaximum -lt $availabilityMinimum)) { throw 'Schema-v2 availability bounds are invalid.' }
    $delayMinimum=[long]$Row.restockDelayMinimumSeconds
    $delayMaximum=[long]$Row.restockDelayMaximumSeconds
    if ($delayMinimum -lt 0 -or $delayMaximum -lt 0 -or ($delayMaximum -gt 0 -and $delayMaximum -lt $delayMinimum)) { throw 'Schema-v2 restock-delay bounds are invalid.' }
    if ([bool]$Row.forecastEligible) {
        if ([long]$Row.restockAt -le 0 -or [long]$Row.soldOutAt -le [long]$Row.restockAt) { throw 'Forecast-eligible schema-v2 cycle needs usable representative restock/sellout times.' }
        if ([long]$Row.availabilityMinimumSeconds -le 0 -or [long]$Row.restockDelayMaximumSeconds -le 0) { throw 'Forecast-eligible schema-v2 cycle needs positive duration evidence.' }
    }
}

if ([string]::IsNullOrWhiteSpace($ObservationPath) -and [string]::IsNullOrWhiteSpace($CyclePath)) {
    throw 'Provide -ObservationPath and/or -CyclePath.'
}
if (-not [string]::IsNullOrWhiteSpace($ObservationPath)) { Assert-NotSynthetic -Path $ObservationPath -Source $SourceName }
if (-not [string]::IsNullOrWhiteSpace($CyclePath)) { Assert-NotSynthetic -Path $CyclePath -Source $SourceName }

$countriesConfig = Read-JsonFile $CountriesPath
$itemsConfig = Read-JsonFile $ItemsPath
if ($null -eq $countriesConfig -or $null -eq $itemsConfig) { throw 'Travel Assistant item/country configuration is missing.' }

$knownCountries = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($row in @($countriesConfig.countries)) { [void]$knownCountries.Add([string]$row.id) }
$knownItems = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($row in @($itemsConfig.items)) { [void]$knownItems.Add([int]$row.itemId) }

$existingObservations = @(Read-JsonLines -Path $SeedObservationPath)
$incomingObservations = @(Read-JsonLines -Path $ObservationPath)
$existingCycles = @(Read-JsonLines -Path $SeedCyclePath)
$incomingCycles = @(Read-JsonLines -Path $CyclePath)

foreach ($row in $incomingObservations) { Validate-Observation -Row $row -KnownCountries $knownCountries -KnownItems $knownItems }
foreach ($row in $incomingCycles) { Validate-Cycle -Row $row -KnownCountries $knownCountries -KnownItems $knownItems }

$observationSeen = New-Object 'System.Collections.Generic.HashSet[string]'
$mergedObservations = New-Object System.Collections.Generic.List[object]
foreach ($row in @($existingObservations + $incomingObservations | Sort-Object country, itemId, timestamp)) {
    Validate-Observation -Row $row -KnownCountries $knownCountries -KnownItems $knownItems
    $key = ('{0}|{1}|{2}|{3}|{4}|{5}' -f [string]$row.country, [int]$row.itemId, [long]$row.timestamp, [int]$row.stock, [long]$row.foreignPrice, [string]$row.source)
    if ($observationSeen.Add($key)) { $mergedObservations.Add($row) }
}

$cycleSeen = New-Object 'System.Collections.Generic.HashSet[string]'
$mergedCycles = New-Object System.Collections.Generic.List[object]
foreach ($row in @($existingCycles + $incomingCycles | Sort-Object country, itemId, restockAt, soldOutAt)) {
    Validate-Cycle -Row $row -KnownCountries $knownCountries -KnownItems $knownItems
    $restockIdentity=[long]$row.restockAt
    $selloutIdentity=[long]$row.soldOutAt
    if ([int]$row.schemaVersion -ge 2) {
        if ($row.PSObject.Properties['restockUpperBoundAt']) { $restockIdentity=[long]$row.restockUpperBoundAt }
        if ($row.PSObject.Properties['soldOutUpperBoundAt']) { $selloutIdentity=[long]$row.soldOutUpperBoundAt }
    }
    $key = ('{0}|{1}|{2}|{3}|{4}' -f [string]$row.country, [int]$row.itemId, $restockIdentity, $selloutIdentity, [long]$row.foreignPrice)
    if ($cycleSeen.Add($key)) { $mergedCycles.Add($row) }
}

Write-JsonLinesAtomic -Path $SeedObservationPath -Rows $mergedObservations.ToArray()
Write-JsonLinesAtomic -Path $SeedCyclePath -Rows $mergedCycles.ToArray()

$metadata = Read-JsonFile $MetadataPath
if ($null -eq $metadata) { $metadata = [pscustomobject]@{ schemaVersion = 1; sources = @(); notes = @() } }

$sourceRecord = [pscustomobject]@{
    name = $SourceName
    url = $SourceUrl
    importedAt = [DateTimeOffset]::UtcNow.ToString('o')
    observationCountAdded = $incomingObservations.Count
    cycleCountAdded = $incomingCycles.Count
    notes = $Notes
}
$metadata.sources = @($metadata.sources) + @($sourceRecord)
$metadata.generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
$metadata.status = if ($mergedObservations.Count -gt 0 -or $mergedCycles.Count -gt 0) { 'seeded' } else { 'empty-bootstrap' }
$metadata.items = @((@($mergedObservations | ForEach-Object { [int]$_.itemId }) + @($mergedCycles | ForEach-Object { [int]$_.itemId })) | Sort-Object -Unique)
$metadata.countries = @((@($mergedObservations | ForEach-Object { [string]$_.country }) + @($mergedCycles | ForEach-Object { [string]$_.country })) | Sort-Object -Unique)
$metadata.coverage = [pscustomobject]@{
    observationCount = $mergedObservations.Count
    cycleCount = $mergedCycles.Count
}
$metadata.notes = @($metadata.notes) + @("Seed import from $SourceName completed at $([DateTimeOffset]::UtcNow.ToString('o')).")
Write-JsonAtomic -Path $MetadataPath -Value $metadata

Write-Host ("Seed observations: {0} total ({1} input records before dedup)." -f $mergedObservations.Count, $incomingObservations.Count) -ForegroundColor Green
Write-Host ("Seed cycles: {0} total ({1} input records before dedup)." -f $mergedCycles.Count, $incomingCycles.Count) -ForegroundColor Green
Write-Host 'Review data/seed/metadata.json and run validators before committing imported history.' -ForegroundColor Yellow
exit 0
