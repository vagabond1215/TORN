param([switch]$SkipMain)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$CountriesFile = Join-Path $ConfigDir 'countries.json'

function Read-FilterStateKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $line.Substring(0,$i).Trim([char]0xFEFF).Trim()
        $values[$key] = $line.Substring($i + 1).Trim()
    }
    return $values
}

function Read-FilterStateJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-FilterStateKvAtomic {
    param([hashtable]$Values, [string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines.Add("$key=$value")
    }
    [System.IO.File]::WriteAllLines($tmp,$lines.ToArray(),[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-FilterStateProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-FilterStateItemText {
    param([object]$Preferences)
    if ([bool]$Preferences.itemFilterAll) { return 'All' }
    $count = @($Preferences.selectedItemIds).Count
    if ($count -eq 0) { return 'None' }
    if ($count -eq 1) { return '1 item' }
    return ('{0} items' -f $count)
}

function Get-FilterStateCategoryText {
    param([object]$Preferences)
    if ([bool]$Preferences.categoryFilterAll) { return 'All' }
    $count = @($Preferences.selectedCategories).Count
    if ($count -eq 0) { return 'None' }
    if ($count -eq 1) { return [string]$Preferences.selectedCategories[0] }
    return ('{0} cats' -f $count)
}

function Get-ActiveMarketSourceRange {
    param([object]$Engine)
    $oldest = 0L
    $freshest = 0L
    if ($null -eq $Engine -or -not $Engine.PSObject.Properties['observedMarkets']) {
        return [pscustomobject]@{ oldest=0L; freshest=0L }
    }
    foreach ($property in @($Engine.observedMarkets.PSObject.Properties)) {
        $market = $property.Value
        if ($null -eq $market) { continue }
        if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or
            ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }
        if (-not $market.PSObject.Properties['sourceTimestamp']) { continue }
        $timestamp = [long]$market.sourceTimestamp
        if ($timestamp -le 0) { continue }
        if ($oldest -le 0 -or $timestamp -lt $oldest) { $oldest = $timestamp }
        if ($timestamp -gt $freshest) { $freshest = $timestamp }
    }
    return [pscustomobject]@{ oldest=$oldest; freshest=$freshest }
}

function Get-FilterStateCountryPrefix {
    param([string]$CountryId)
    if ($CountryId -eq 'united_kingdom') { return 'UK' }
    if ($CountryId -eq 'japan') { return 'JP' }
    return $CountryId.ToUpperInvariant()
}

function Project-AllCollectedTravelSeconds {
    param([hashtable]$State,[object]$Countries,[object]$Preferences)
    if ($null -eq $Countries -or -not $Countries.PSObject.Properties['countries']) { return }
    $mode = [string]$Preferences.travelMode
    if ([string]::IsNullOrWhiteSpace($mode) -and $State.ContainsKey('TravelMode')) { $mode = [string]$State['TravelMode'] }
    if ([string]::IsNullOrWhiteSpace($mode)) { return }

    foreach ($country in @($Countries.countries | Where-Object { $_.collect -eq $true })) {
        $countryId = [string](Get-FilterStateProperty $country 'id')
        if ([string]::IsNullOrWhiteSpace($countryId) -or -not $country.PSObject.Properties['travelSeconds']) { continue }
        $travelProperty = $country.travelSeconds.PSObject.Properties[$mode]
        if ($null -eq $travelProperty) { continue }
        $State[(Get-FilterStateCountryPrefix $countryId) + 'TravelSeconds'] = [long]$travelProperty.Value
    }
}

function Test-OpportunityPlaceholderName {
    param([string]$Name)
    $value = ([string]$Name).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $true }
    if ($value -eq 'Unknown item') { return $true }
    return ($value -match '^Item\s+[1-9][0-9]*$')
}

function Resolve-OpportunityPresentationName {
    param([hashtable]$State,[object]$Engine,[int]$Index)
    $nameKey = 'Opportunity' + $Index + 'Name'
    $current = ''
    if ($State.ContainsKey($nameKey)) {
        $current = ([string]$State[$nameKey]).Trim()
        if (-not (Test-OpportunityPlaceholderName $current)) { return $current }
    }

    $keyKey = 'Opportunity' + $Index + 'Key'
    if (-not $State.ContainsKey($keyKey)) { return $current }
    $marketKey = ([string]$State[$keyKey]).Trim().ToLowerInvariant()
    if ($marketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { return $current }
    $parts = $marketKey.Split(':')
    $itemId = 0
    if (-not [int]::TryParse($parts[$parts.Count-1],[ref]$itemId) -or $itemId -le 0) { return $current }

    if ($null -ne $Engine -and $Engine.PSObject.Properties['itemMetadata']) {
        $metadata = Get-FilterStateProperty $Engine.itemMetadata ([string]$itemId)
        if ($null -ne $metadata -and $metadata.PSObject.Properties['name']) {
            $name = ([string]$metadata.name).Trim()
            if (-not (Test-OpportunityPlaceholderName $name)) { return $name }
        }
    }

    if ($null -ne $Engine -and $Engine.PSObject.Properties['observedMarkets']) {
        $market = Get-FilterStateProperty $Engine.observedMarkets $marketKey
        if ($null -ne $market -and $market.PSObject.Properties['providerName']) {
            $providerName = ([string]$market.providerName).Trim()
            if (-not [string]::IsNullOrWhiteSpace($providerName)) { return $providerName }
        }
    }

    return ('Item {0}' -f $itemId)
}

function Repair-OpportunityPresentationNames {
    param([hashtable]$State,[object]$Engine)
    $count = 8
    if ($State.ContainsKey('OpportunityCount')) {
        $projected = 0
        if ([int]::TryParse([string]$State['OpportunityCount'],[ref]$projected)) { $count = [Math]::Min(256,[Math]::Max(0,$projected)) }
    }
    for ($i=1; $i -le $count; $i++) {
        $key = 'Opportunity' + $i + 'Key'
        if (-not $State.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$State[$key])) { continue }
        $name = Resolve-OpportunityPresentationName -State $State -Engine $Engine -Index $i
        if (-not [string]::IsNullOrWhiteSpace($name)) { $State['Opportunity' + $i + 'Name'] = $name }
    }
}

if ($SkipMain) { return }

$state = Read-FilterStateKv $StateKvFile
if ($state.Count -eq 0) { return }
$prefs = Read-UiPreferences
$engine = Read-FilterStateJson $EngineStateFile
$countries = Read-FilterStateJson $CountriesFile
$sourceRange = Get-ActiveMarketSourceRange -Engine $engine
$displayBands = @($prefs.displayTripBands)

$state['UIItemFilterAll'] = if ([bool]$prefs.itemFilterAll) { 1 } else { 0 }
$state['UISelectedItemIds'] = (@($prefs.selectedItemIds | ForEach-Object { [string][int]$_ }) -join ',')
$state['UISelectedTripBands'] = (@($displayBands | ForEach-Object { ([string]$_).ToLowerInvariant() }) -join ',')
$state['UISelectedCountryIds'] = (@($prefs.selectedCountryIds | ForEach-Object { [string]$_ }) -join ',')
$state['UICategoryFilterAll'] = if ([bool]$prefs.categoryFilterAll) { 1 } else { 0 }
$state['UISelectedCategories'] = (@($prefs.selectedCategories | ForEach-Object { [string]$_ }) -join '|')
$state['UIShowProfitableOnly'] = if ([bool]$prefs.showProfitableOnly) { 1 } else { 0 }
$state['UIIgnoredItemIds'] = (@($prefs.ignoredItemIds | ForEach-Object { [string][int]$_ }) -join ',')

$state['UIOldestMarketSourceTimestamp'] = [long]$sourceRange.oldest
$state['UIOldestActiveMarketSourceTimestamp'] = [long]$sourceRange.oldest
$state['UIFreshestMarketSourceTimestamp'] = [long]$sourceRange.freshest

Project-AllCollectedTravelSeconds -State $state -Countries $countries -Preferences $prefs
Repair-OpportunityPresentationNames -State $state -Engine $engine

[void]$state.Remove('UIPinnedMarket')

$state['UIItemFilterText'] = Get-FilterStateItemText -Preferences $prefs
$state['UICategoryFilterText'] = Get-FilterStateCategoryText -Preferences $prefs
$state['UITripShortOn'] = if (@($displayBands) -contains 'short') { 1 } else { 0 }
$state['UITripMediumOn'] = if (@($displayBands) -contains 'medium') { 1 } else { 0 }
$state['UITripLongOn'] = if (@($displayBands) -contains 'long') { 1 } else { 0 }

Write-FilterStateKvAtomic -Values $state -Path $StateKvFile