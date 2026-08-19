param(
    [switch]$SaveProbe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RuntimeProbeDir = Join-Path $ProjectRoot 'data\runtime\provider-probes'
$BaseUrl = 'https://droqsdb.com'
$Headers = @{ Accept = 'application/json' }

function Invoke-JsonGet {
    param([string]$Url)
    $started = [DateTimeOffset]::UtcNow
    try {
        $payload = Invoke-RestMethod -Method Get -Uri $Url -Headers $Headers -TimeoutSec 20
        return [pscustomobject]@{
            ok = $true
            url = $Url
            fetchedAt = [DateTimeOffset]::UtcNow.ToString('o')
            elapsedMs = [long]([DateTimeOffset]::UtcNow - $started).TotalMilliseconds
            payload = $payload
            error = $null
        }
    } catch {
        return [pscustomobject]@{
            ok = $false
            url = $Url
            fetchedAt = [DateTimeOffset]::UtcNow.ToString('o')
            elapsedMs = [long]([DateTimeOffset]::UtcNow - $started).TotalMilliseconds
            payload = $null
            error = $_.Exception.Message
        }
    }
}

function Get-PropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

$targets = [ordered]@{
    meta = "$BaseUrl/api/public/v1/meta"
    xanax = "$BaseUrl/api/public/v1/item/Xanax"
    japan = "$BaseUrl/api/public/v1/country/Japan"
    unitedKingdom = "$BaseUrl/api/public/v1/country/United%20Kingdom"
}

$results = [ordered]@{}
foreach ($entry in $targets.GetEnumerator()) {
    Write-Host ("Probing {0}: {1}" -f $entry.Key, $entry.Value) -ForegroundColor Cyan
    $results[$entry.Key] = Invoke-JsonGet -Url $entry.Value
    if ($results[$entry.Key].ok) {
        Write-Host '  OK' -ForegroundColor Green
    } else {
        Write-Host ("  FAIL: {0}" -f $results[$entry.Key].error) -ForegroundColor Yellow
    }
}

$metaPayload = $null
if ($results.meta.ok) { $metaPayload = $results.meta.payload }
$api = Get-PropertyValue $metaPayload 'api'
$advertisedEndpoints = Get-PropertyValue $api 'endpoints'
$historyMetrics = Get-PropertyValue $api 'historyMetrics'

Write-Host ''
Write-Host 'Advertised endpoint metadata' -ForegroundColor Cyan
if ($null -ne $advertisedEndpoints) {
    @($advertisedEndpoints) | ForEach-Object { Write-Host ("  {0}" -f $_) }
} else {
    Write-Host '  No api.endpoints field was returned.' -ForegroundColor Yellow
}

Write-Host 'Advertised history metrics' -ForegroundColor Cyan
if ($null -ne $historyMetrics) {
    @($historyMetrics) | ForEach-Object { Write-Host ("  {0}" -f $_) }
} else {
    Write-Host '  No api.historyMetrics field was returned.' -ForegroundColor Yellow
}

$historyCandidates = New-Object System.Collections.Generic.List[string]
foreach ($endpoint in @($advertisedEndpoints)) {
    $text = [string]$endpoint
    if ($text -match '(?i)history') { $historyCandidates.Add($text) }
}

if ($historyCandidates.Count -gt 0) {
    Write-Host 'History-looking endpoints were advertised, but are NOT called automatically:' -ForegroundColor Cyan
    foreach ($candidate in $historyCandidates) { Write-Host ("  {0}" -f $candidate) }
    Write-Host 'Inspect required parameters/contract before enabling a bootstrap importer.' -ForegroundColor Yellow
} else {
    Write-Host 'No live history endpoint was established by this probe.' -ForegroundColor Yellow
}

$report = [pscustomobject]@{
    schemaVersion = 1
    provider = 'droqsdb'
    probedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseUrl = $BaseUrl
    results = [pscustomobject]$results
    advertisedEndpoints = @($advertisedEndpoints)
    historyMetrics = @($historyMetrics)
    historyCandidates = @($historyCandidates)
}

if ($SaveProbe) {
    New-Item -ItemType Directory -Force -Path $RuntimeProbeDir | Out-Null
    $stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $path = Join-Path $RuntimeProbeDir ("droqsdb-$stamp.json")
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host ("Saved runtime-only probe: {0}" -f $path) -ForegroundColor Green
}

if (-not $results.meta.ok) {
    Write-Host 'DroqsDB meta could not be verified. Keep the provider disabled for training/seed use.' -ForegroundColor Yellow
    exit 2
}

Write-Host 'DroqsDB metadata probe completed. This does not by itself authorize or validate historical seed ingestion.' -ForegroundColor Green
exit 0
