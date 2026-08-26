param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'AtomicFile.ps1')

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'

function Read-ProjectionJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Read-ProjectionKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $line.Substring(0,$i).Trim([char]0xFEFF).Trim()
        $values[$key] = $line.Substring($i+1).Trim()
    }
    return $values
}

function Write-ProjectionKvAtomic {
    param([hashtable]$Values,[string]$Path)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines.Add($key + '=' + $value)
    }
    Write-TravelAssistantAtomicLines -Path $Path -Lines $lines.ToArray()
}

function Get-ProjectionProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ProjectionTravelMode {
    param([object]$Settings,[object]$TravelModes,[object]$Preferences)
    $mode = [string](Get-ProjectionProperty $Settings 'travelMode')
    $preferred = [string](Get-ProjectionProperty $Preferences 'travelMode')
    if (-not [string]::IsNullOrWhiteSpace($preferred)) { $mode = $preferred }
    $valid = @($TravelModes.modes | Where-Object { $_.enabled -eq $true } | ForEach-Object { [string]$_.id })
    if ($valid -notcontains $mode) { $mode = [string]$TravelModes.defaultMode }
    return $mode
}

function Get-ProjectionPrefix {
    param([string]$CountryId)
    if ($CountryId -eq 'united_kingdom') { return 'UK' }
    if ($CountryId -eq 'japan') { return 'JP' }
    return $CountryId.ToUpperInvariant()
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$settings = Read-ProjectionJson (Join-Path $ConfigDir 'settings.example.json')
$countries = Read-ProjectionJson (Join-Path $ConfigDir 'countries.json')
$items = Read-ProjectionJson (Join-Path $ConfigDir 'items.json')
$travelModes = Read-ProjectionJson (Join-Path $ConfigDir 'travel-modes.json')
$preferences = Read-ProjectionJson $PreferenceFile
$engine = Read-ProjectionJson $EngineStateFile
if ($null -eq $settings -or $null -eq $countries -or $null -eq $items -or $null -eq $travelModes -or $null -eq $engine) { return }

$state = Read-ProjectionKv $StateKvFile
$travelMode = Get-ProjectionTravelMode -Settings $settings -TravelModes $travelModes -Preferences $preferences
$modeRow = @($travelModes.modes | Where-Object { [string]$_.id -eq $travelMode } | Select-Object -First 1)
$modeLabel = if ($modeRow.Count -gt 0) { [string]$modeRow[0].label } else { $travelMode }
$state['TravelMode'] = $travelMode
$state['TravelModeLabel'] = $modeLabel

$provider = ''
$lastPollAt = 0L
if ($engine.PSObject.Properties['shadowCollection']) {
    $provider = [string](Get-ProjectionProperty $engine.shadowCollection 'lastProvider')
    $lastPollAt = [long](Get-ProjectionProperty $engine.shadowCollection 'lastPollAt')
}
if ([string]::IsNullOrWhiteSpace($provider)) { $provider = 'none' }
$state['LiveProvider'] = $provider
$state['UpdatedText'] = if ($lastPollAt -gt 0) { ($provider + ' collected market state') } else { 'Waiting for collected market state' }

$enabledItem = @($items.items | Where-Object { $_.enabled -eq $true } | Select-Object -First 1)
$itemId = if ($enabledItem.Count -gt 0) { [int]$enabledItem[0].itemId } else { 0 }
$staleAfter = [Math]::Max(60L,[long](Get-ProjectionProperty $settings 'staleAfterSeconds'))

# Every collect=true country participates in the opportunity surface, even when
# it is not one of the legacy enabled compatibility destinations. Project travel
# time for all of them so flag tooltips never depend on UK/JP-only state.
foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true })) {
    $countryId = [string]$country.id
    $prefix = Get-ProjectionPrefix $countryId
    $travelSeconds = 0L
    if ($country.PSObject.Properties['travelSeconds']) {
        $travelProperty = $country.travelSeconds.PSObject.Properties[$travelMode]
        if ($null -ne $travelProperty) { $travelSeconds = [long]$travelProperty.Value }
    }
    $state[$prefix + 'TravelSeconds'] = $travelSeconds

    if ($itemId -le 0) { continue }
    $marketKey = $countryId + ':' + [string]$itemId
    $market = if ($engine.PSObject.Properties['observedMarkets']) { Get-ProjectionProperty $engine.observedMarkets $marketKey } else { $null }
    $dest = if ($engine.PSObject.Properties['destinations']) { Get-ProjectionProperty $engine.destinations $marketKey } else { $null }

    $stock = 0L
    $foreignPrice = 0L
    $sourceTimestamp = 0L
    if ($null -ne $market) {
        $stock = [Math]::Max(0L,[long](Get-ProjectionProperty $market 'lastStock'))
        $foreignPrice = [Math]::Max(0L,[long](Get-ProjectionProperty $market 'lastForeignPrice'))
        $sourceTimestamp = [Math]::Max(0L,[long](Get-ProjectionProperty $market 'sourceTimestamp'))
    } elseif ($null -ne $dest) {
        $stock = [Math]::Max(0L,[long](Get-ProjectionProperty $dest 'lastStock'))
        $foreignPrice = [Math]::Max(0L,[long](Get-ProjectionProperty $dest 'lastForeignPrice'))
        $sourceTimestamp = [Math]::Max(0L,[long](Get-ProjectionProperty $dest 'lastSourceTimestamp'))
    }

    $state[$prefix + 'Stock'] = $stock
    $state[$prefix + 'ForeignPrice'] = $foreignPrice
    $state[$prefix + 'SourceTimestamp'] = $sourceTimestamp
    $state[$prefix + 'LastSoldOutAt'] = if ($null -ne $dest) { [Math]::Max(0L,[long](Get-ProjectionProperty $dest 'lastSellOutAt')) } else { 0 }

    if ($sourceTimestamp -le 0 -or ($Now-$sourceTimestamp) -gt $staleAfter) {
        $state[$prefix + 'Status'] = 'STALE_DATA'
        $state[$prefix + 'Message'] = 'Collected foreign stock is stale'
    } elseif ($stock -gt 0) {
        $state[$prefix + 'Status'] = 'IN_STOCK'
        $state[$prefix + 'Message'] = 'Fresh collected stock is available'
    } else {
        $state[$prefix + 'Status'] = 'SOLD_OUT'
        $state[$prefix + 'Message'] = 'Fresh collected stock is sold out'
    }
}

Write-ProjectionKvAtomic -Values $state -Path $StateKvFile
exit 0