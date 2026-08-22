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

if ($SkipMain) { return }

$state = Read-FilterStateKv $StateKvFile
if ($state.Count -eq 0) { return }
$prefs = Read-UiPreferences
$engine = Read-FilterStateJson $EngineStateFile
$sourceRange = Get-ActiveMarketSourceRange -Engine $engine

$state['UIItemFilterAll'] = if ([bool]$prefs.itemFilterAll) { 1 } else { 0 }
$state['UISelectedItemIds'] = (@($prefs.selectedItemIds | ForEach-Object { [string][int]$_ }) -join ',')
$state['UISelectedTripBands'] = (@($prefs.selectedTripBands | ForEach-Object { ([string]$_).ToLowerInvariant() }) -join ',')
$state['UISelectedCountryIds'] = (@($prefs.selectedCountryIds | ForEach-Object { [string]$_ }) -join ',')
$state['UICategoryFilterAll'] = if ([bool]$prefs.categoryFilterAll) { 1 } else { 0 }
$state['UISelectedCategories'] = (@($prefs.selectedCategories | ForEach-Object { [string]$_ }) -join '|')
$state['UIShowProfitableOnly'] = if ([bool]$prefs.showProfitableOnly) { 1 } else { 0 }
$state['UIIgnoredItemIds'] = (@($prefs.ignoredItemIds | ForEach-Object { [string][int]$_ }) -join ',')

# StateReader historically reads UIOldestMarketSourceTimestamp as the provider-age
# timestamp. Keep that key for compatibility, but feed it the newest active market
# sample so one lagging country cannot label the entire provider stale. Preserve the
# actual oldest sample separately for diagnostics.
$state['UIOldestMarketSourceTimestamp'] = [long]$sourceRange.freshest
$state['UIOldestActiveMarketSourceTimestamp'] = [long]$sourceRange.oldest
$state['UIFreshestMarketSourceTimestamp'] = [long]$sourceRange.freshest

# Pin state is intentionally not mirrored through state.kv. StateReader owns the
# live pin and persists it directly to ignored preferences.json. Projecting an
# older pin here can overwrite a just-clicked pin on the next one-second update.
[void]$state.Remove('UIPinnedMarket')

$state['UIItemFilterText'] = Get-FilterStateItemText -Preferences $prefs
$state['UICategoryFilterText'] = Get-FilterStateCategoryText -Preferences $prefs
$state['UITripShortOn'] = if (@($prefs.selectedTripBands) -contains 'short') { 1 } else { 0 }
$state['UITripMediumOn'] = if (@($prefs.selectedTripBands) -contains 'medium') { 1 } else { 0 }
$state['UITripLongOn'] = if (@($prefs.selectedTripBands) -contains 'long') { 1 } else { 0 }

Write-FilterStateKvAtomic -Values $state -Path $StateKvFile
