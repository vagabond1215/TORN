param(
    [int]$MaximumProviderAgeSeconds = 300,
    [int]$RequestTimeoutSeconds = 8
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$CountriesFile = Join-Path $ConfigDir 'countries.json'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$HeartbeatFile = Join-Path $GeneratedDir 'last-update.txt'

if ($MaximumProviderAgeSeconds -lt 60) { $MaximumProviderAgeSeconds = 60 }
if ($RequestTimeoutSeconds -lt 2) { $RequestTimeoutSeconds = 2 }
if ($RequestTimeoutSeconds -gt 30) { $RequestTimeoutSeconds = 30 }

function Read-ProbeJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-ProbeProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-ProbeStateKv {
    param([string]$Path)
    $state=@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $state }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $eq=$line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $state[$line.Substring(0,$eq).Trim([char]0xFEFF).Trim()]=$line.Substring($eq+1).Trim()
    }
    return $state
}

function Get-ProbeAge {
    param([long]$Timestamp,[long]$Now)
    if ($Timestamp -le 0) { return [long]::MaxValue }
    return [Math]::Max(0L,$Now-$Timestamp)
}

function Format-ProbeAge {
    param([long]$Seconds)
    if ($Seconds -eq [long]::MaxValue) { return '?' }
    if ($Seconds -lt 60) { return ([string]$Seconds + 's') }
    $hours=[Math]::Floor($Seconds/3600)
    $minutes=[Math]::Floor(($Seconds%3600)/60)
    if ($hours -gt 0) { return ('{0}h {1}m' -f $hours,$minutes) }
    return ('{0}m' -f $minutes)
}

function Invoke-ProbeJson {
    param([string]$Name,[string]$Uri)
    $started=[DateTimeOffset]::UtcNow
    try {
        $payload=Invoke-RestMethod -Method Get -Uri $Uri -Headers @{Accept='application/json'} -TimeoutSec $RequestTimeoutSeconds
        $elapsed=[long]([DateTimeOffset]::UtcNow-$started).TotalMilliseconds
        return [pscustomobject]@{ name=$Name; uri=$Uri; ok=$true; elapsedMs=$elapsed; payload=$payload; error='' }
    } catch {
        $elapsed=[long]([DateTimeOffset]::UtcNow-$started).TotalMilliseconds
        return [pscustomobject]@{ name=$Name; uri=$Uri; ok=$false; elapsedMs=$elapsed; payload=$null; error=$_.Exception.Message }
    }
}

function Get-ProbeCountryCode {
    param([object]$Country,[string]$Provider)
    if ($null -eq $Country -or -not $Country.PSObject.Properties['providerCodes']) { return '' }
    $property=$Country.providerCodes.PSObject.Properties[$Provider]
    if ($null -eq $property -and $Provider -eq 'prometheus') { $property=$Country.providerCodes.PSObject.Properties['yata'] }
    if ($null -eq $property) { return '' }
    return [string]$property.Value
}

function Get-ProbeYataStyleCountry {
    param([object]$Payload,[object]$Country,[string]$Provider,[long]$Now)
    $code=Get-ProbeCountryCode -Country $Country -Provider $Provider
    if ([string]::IsNullOrWhiteSpace($code) -or $null -eq $Payload -or -not $Payload.PSObject.Properties['stocks']) {
        return [pscustomobject]@{available=$false; timestamp=0L; age=[long]::MaxValue; fresh=$false; itemCount=0}
    }
    $countryProperty=$Payload.stocks.PSObject.Properties[$code]
    if ($null -eq $countryProperty -or $null -eq $countryProperty.Value) {
        return [pscustomobject]@{available=$false; timestamp=0L; age=[long]::MaxValue; fresh=$false; itemCount=0}
    }
    $countryObject=$countryProperty.Value
    $timestamp=0L
    if ($countryObject.PSObject.Properties['update']) { try { $timestamp=[long]$countryObject.update } catch { $timestamp=0L } }
    $age=Get-ProbeAge -Timestamp $timestamp -Now $Now
    $count=0
    if ($countryObject.PSObject.Properties['stocks'] -and $null -ne $countryObject.stocks) { $count=@($countryObject.stocks).Count }
    return [pscustomobject]@{available=$true; timestamp=$timestamp; age=$age; fresh=($timestamp -gt 0 -and $age -le $MaximumProviderAgeSeconds); itemCount=$count}
}

$countries=Read-ProbeJson $CountriesFile
if ($null -eq $countries) { throw 'config/countries.json is missing or invalid.' }
$collectionCountries=@($countries.countries | Where-Object { $_.collect -eq $true })
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Host ''
Write-Host '=== Local pipeline clocks ===' -ForegroundColor Cyan
$engine=Read-ProbeJson $EngineStateFile
$state=Read-ProbeStateKv $StateKvFile
$collectionAt=0L
$engineFreshest=0L
if ($null -ne $engine -and $engine.PSObject.Properties['shadowCollection']) {
    $collectionAt=[long](Get-ProbeProperty $engine.shadowCollection 'lastPollAt')
}
if ($null -ne $engine -and $engine.PSObject.Properties['observedMarkets']) {
    foreach ($property in @($engine.observedMarkets.PSObject.Properties)) {
        $market=$property.Value
        if ($null -eq $market -or -not $market.PSObject.Properties['sourceTimestamp']) { continue }
        $ts=[long]$market.sourceTimestamp
        if ($ts -gt $engineFreshest) { $engineFreshest=$ts }
    }
}
$projectedFreshest=0L
if ($state.ContainsKey('UIFreshestMarketSourceTimestamp')) { [void][long]::TryParse([string]$state['UIFreshestMarketSourceTimestamp'],[ref]$projectedFreshest) }
$heartbeat=0L
if (Test-Path -LiteralPath $HeartbeatFile) { [void][long]::TryParse((Get-Content -LiteralPath $HeartbeatFile -Raw).Trim(),[ref]$heartbeat) }

[pscustomobject]@{Clock='engine collection';Timestamp=$collectionAt;Age=(Format-ProbeAge (Get-ProbeAge $collectionAt $now))},
[pscustomobject]@{Clock='engine freshest source';Timestamp=$engineFreshest;Age=(Format-ProbeAge (Get-ProbeAge $engineFreshest $now))},
[pscustomobject]@{Clock='state.kv freshest source';Timestamp=$projectedFreshest;Age=(Format-ProbeAge (Get-ProbeAge $projectedFreshest $now))},
[pscustomobject]@{Clock='UI heartbeat';Timestamp=$heartbeat;Age=(Format-ProbeAge (Get-ProbeAge $heartbeat $now))} |
    Format-Table -AutoSize

Write-Host ''
Write-Host '=== Structured live stock providers ===' -ForegroundColor Cyan
$prometheus=Invoke-ProbeJson -Name 'prometheus' -Uri 'https://api.prombot.co.uk/api/travel'
$yata=Invoke-ProbeJson -Name 'yata' -Uri 'https://yata.yt/api/v1/travel/export/'

foreach ($provider in @($prometheus,$yata)) {
    $status=if ($provider.ok) { 'HTTP/JSON OK' } else { 'FAILED' }
    Write-Host ('{0,-11} {1,-12} {2,5} ms  {3}' -f $provider.name,$status,$provider.elapsedMs,$provider.error)
}

$rows=New-Object System.Collections.Generic.List[object]
foreach ($country in $collectionCountries) {
    $p=if ($prometheus.ok) { Get-ProbeYataStyleCountry -Payload $prometheus.payload -Country $country -Provider 'prometheus' -Now $now } else { $null }
    $y=if ($yata.ok) { Get-ProbeYataStyleCountry -Payload $yata.payload -Country $country -Provider 'yata' -Now $now } else { $null }
    $rows.Add([pscustomobject]@{
        Country=[string]$country.name
        Prometheus=if ($null -eq $p -or -not $p.available) { 'missing' } elseif ($p.fresh) { 'fresh '+(Format-ProbeAge $p.age) } else { 'STALE '+(Format-ProbeAge $p.age) }
        YATA=if ($null -eq $y -or -not $y.available) { 'missing' } elseif ($y.fresh) { 'fresh '+(Format-ProbeAge $y.age) } else { 'STALE '+(Format-ProbeAge $y.age) }
    })
}
$rows.ToArray() | Format-Table -AutoSize

Write-Host ''
Write-Host '=== Additional provider/interface probes ===' -ForegroundColor Cyan
$droqs=Invoke-ProbeJson -Name 'droqsdb' -Uri 'https://droqsdb.com/api/public/v1/export'
$weav3r=Invoke-ProbeJson -Name 'weav3r-market' -Uri 'https://weav3r.dev/api/marketplace'
Write-Host ('DroqsDB export:   {0} ({1} ms) {2}' -f $(if ($droqs.ok) {'JSON OK'} else {'FAILED'}),$droqs.elapsedMs,$droqs.error)
Write-Host ('Weav3r marketplace: {0} ({1} ms) {2}' -f $(if ($weav3r.ok) {'JSON OK'} else {'FAILED'}),$weav3r.elapsedMs,$weav3r.error)
Write-Host 'Note: Weav3r /api/marketplace is verified for Torn-side market/catalog pricing, not overseas stock quantities.' -ForegroundColor Yellow
Write-Host 'No structured Weav3r travel-stock quantity endpoint is assumed by this probe.' -ForegroundColor Yellow

$bothUnavailable=(-not $prometheus.ok -and -not $yata.ok)
if ($bothUnavailable) {
    Write-Host ''
    Write-Host 'FAIL: both production structured stock providers were unreachable.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Provider probe completed. Compare engine/source ages with state.kv/heartbeat ages to distinguish acquisition failures from local publication failures.' -ForegroundColor Green
exit 0
