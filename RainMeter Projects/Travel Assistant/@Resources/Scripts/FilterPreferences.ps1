param(
    [ValidateSet('None','ToggleTripBand','ResetFilters','SetSortMode')]
    [string]$Action = 'None',
    [string]$Value = '',
    [Alias('SkipMain')]
    [switch]$FilterPreferencesSkipMain
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$RuntimeLogScript = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $RuntimeLogScript) { . $RuntimeLogScript }

function Read-FilterJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-FilterJsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 20)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Set-FilterProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

function Set-FilterStateKvValuesAtomic {
    param([hashtable]$Updates)
    $values = @{}
    if (Test-Path -LiteralPath $StateKvFile) {
        foreach ($line in Get-Content -LiteralPath $StateKvFile) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $index = $line.IndexOf('=')
            if ($index -lt 1) { continue }
            $key = $line.Substring(0,$index).Trim([char]0xFEFF).Trim()
            $values[$key] = $line.Substring($index+1).Trim()
        }
    }
    foreach ($key in @($Updates.Keys)) { $values[[string]$key] = [string]$Updates[$key] }
    New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
    $tmp = $StateKvFile + '.preference.tmp'
    $lines = @()
    foreach ($key in @($values.Keys | Sort-Object)) {
        $safe = ([string]$values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines += ($key + '=' + $safe)
    }
    [System.IO.File]::WriteAllLines($tmp,[string[]]$lines,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $StateKvFile -Force
}

function Set-FilterStateKvValueAtomic {
    param([string]$Name,[string]$Value)
    Set-FilterStateKvValuesAtomic -Updates @{ $Name = $Value }
}

function Get-FilterAvailableCountryIds {
    $countries = Read-FilterJson (Join-Path $ConfigDir 'countries.json')
    if ($null -eq $countries) { return @() }
    return @($countries.countries | Where-Object { $_.collect -eq $true } | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
}

function Get-FilterVisibleItemIds {
    $items = Read-FilterJson (Join-Path $ConfigDir 'items.json')
    if ($null -eq $items) { return @() }
    return @($items.items | Where-Object { $_.visible -eq $true } | ForEach-Object { [int]$_.itemId } | Sort-Object -Unique)
}

function Get-FilterVisibleCategories {
    $items = Read-FilterJson (Join-Path $ConfigDir 'items.json')
    if ($null -eq $items) { return @() }
    return @($items.items | Where-Object { $_.visible -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$_.category) } | ForEach-Object { [string]$_.category } | Sort-Object -Unique)
}

function New-DefaultUiPreferences {
    return [pscustomobject]@{
        schemaVersion = 7
        travelMode = 'airstrip'
        pinnedMarket = ''
        itemFilterAll = $true
        selectedItemIds = [int[]]@(Get-FilterVisibleItemIds)
        # Candidate projection always retains all bands. displayTripBands is the
        # local presentation filter used by the instant Rainmeter controls.
        selectedTripBands = [string[]]@('short','medium','long')
        displayTripBands = [string[]]@('short','medium','long')
        selectedCountryIds = [string[]]@(Get-FilterAvailableCountryIds)
        categoryFilterAll = $true
        selectedCategories = [string[]]@(Get-FilterVisibleCategories)
        showProfitableOnly = $false
        ignoredItemIds = [int[]]@()
        use95PercentMarketValue = $false
        energyWastePolicy = 'allowed'
        maxEnergyLoss = 0
        nerveWastePolicy = 'allowed'
        maxNerveLoss = 0
        sortMode = 'upcoming'
    }
}

function Normalize-WastePolicy {
    param([object]$Value)
    $policy = ([string]$Value).Trim().ToLowerInvariant()
    if ($policy -notin @('allowed','forbidden','limited')) { return 'allowed' }
    return $policy
}

function Normalize-SortMode {
    param([object]$Value)
    $mode = ([string]$Value).Trim().ToLowerInvariant()
    if ($mode -eq 'optimal') { return 'profit_per_hour' }
    if ($mode -eq 'profit') { return 'gross' }
    if ($mode -eq 'time') { return 'upcoming' }
    if ($mode -notin @('name','upcoming','gross','profit_per_hour')) { return 'upcoming' }
    return $mode
}

function Normalize-TripBands {
    param([object[]]$Values)
    $bands = @()
    foreach ($band in @($Values)) {
        $value = ([string]$band).ToLowerInvariant()
        if ($value -in @('short','medium','long')) { $bands += $value }
    }
    return [string[]]@($bands | Sort-Object -Unique)
}

function Normalize-UiPreferences {
    param([object]$Preferences)
    $defaults = New-DefaultUiPreferences
    if ($null -eq $Preferences) { $Preferences = [pscustomobject]@{} }

    $sourceSchemaVersion = 0
    if ($Preferences.PSObject.Properties['schemaVersion']) {
        [void][int]::TryParse([string]$Preferences.schemaVersion,[ref]$sourceSchemaVersion)
    }

    # Migrate the old selectedTripBands UI state into displayTripBands once.
    $legacyDisplayBands = @('short','medium','long')
    if (-not $Preferences.PSObject.Properties['displayTripBands'] -and $Preferences.PSObject.Properties['selectedTripBands']) {
        $legacyDisplayBands = @(Normalize-TripBands @($Preferences.selectedTripBands))
    }

    foreach ($property in @($defaults.PSObject.Properties)) {
        if (-not $Preferences.PSObject.Properties[$property.Name]) { $Preferences | Add-Member NoteProperty ([string]$property.Name) $property.Value }
    }
    Set-FilterProperty $Preferences 'schemaVersion' 7

    if ($legacyDisplayBands.Count -ge 0 -and -not $Preferences.PSObject.Properties['displayTripBandsMigrated']) {
        Set-FilterProperty $Preferences 'displayTripBands' ([string[]]$legacyDisplayBands)
        Set-FilterProperty $Preferences 'displayTripBandsMigrated' $true
    }

    $mode = [string]$Preferences.travelMode
    if ($mode -notin @('standard','airstrip','wlt','business')) { Set-FilterProperty $Preferences 'travelMode' 'airstrip' }
    $pin = [string]$Preferences.pinnedMarket
    if (-not [string]::IsNullOrWhiteSpace($pin) -and $pin -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { Set-FilterProperty $Preferences 'pinnedMarket' '' }

    $itemIds = @()
    foreach ($id in @($Preferences.selectedItemIds)) {
        $n = 0
        if ([int]::TryParse([string]$id, [ref]$n) -and $n -gt 0) { $itemIds += $n }
    }
    Set-FilterProperty $Preferences 'selectedItemIds' ([int[]]@($itemIds | Sort-Object -Unique))

    # Do not let presentation toggles prune the candidate projection. All three
    # bands remain available locally so OFF -> ON is immediate even after polls.
    Set-FilterProperty $Preferences 'selectedTripBands' ([string[]]@('short','medium','long'))
    Set-FilterProperty $Preferences 'displayTripBands' (Normalize-TripBands @($Preferences.displayTripBands))

    $availableCountries = [string[]]@(Get-FilterAvailableCountryIds)
    $countries = @()
    foreach ($id in @($Preferences.selectedCountryIds)) {
        $value = [string]$id
        if ($availableCountries -contains $value) { $countries += $value }
    }
    # Schema <=6 could persist an accidental empty country set, leaving the entire
    # opportunity surface blank with no visible country-filter indicator. Repair that
    # legacy state once; schema 7 still permits an intentional empty set afterward.
    if ($sourceSchemaVersion -lt 7 -and $countries.Count -eq 0 -and $availableCountries.Count -gt 0) {
        $countries = [string[]]@($availableCountries)
    }
    Set-FilterProperty $Preferences 'selectedCountryIds' ([string[]]@($countries | Sort-Object -Unique))

    $categories = @()
    foreach ($category in @($Preferences.selectedCategories)) {
        $value = [string]$category
        if (-not [string]::IsNullOrWhiteSpace($value)) { $categories += $value }
    }
    Set-FilterProperty $Preferences 'selectedCategories' ([string[]]@($categories | Sort-Object -Unique))

    $ignored = @()
    foreach ($id in @($Preferences.ignoredItemIds)) {
        $n = 0
        if ([int]::TryParse([string]$id, [ref]$n) -and $n -gt 0) { $ignored += $n }
    }
    Set-FilterProperty $Preferences 'ignoredItemIds' ([int[]]@($ignored | Sort-Object -Unique))
    Set-FilterProperty $Preferences 'itemFilterAll' ([bool]$Preferences.itemFilterAll)
    Set-FilterProperty $Preferences 'categoryFilterAll' ([bool]$Preferences.categoryFilterAll)
    Set-FilterProperty $Preferences 'showProfitableOnly' ([bool]$Preferences.showProfitableOnly)
    Set-FilterProperty $Preferences 'use95PercentMarketValue' ([bool]$Preferences.use95PercentMarketValue)
    Set-FilterProperty $Preferences 'energyWastePolicy' (Normalize-WastePolicy $Preferences.energyWastePolicy)
    Set-FilterProperty $Preferences 'nerveWastePolicy' (Normalize-WastePolicy $Preferences.nerveWastePolicy)
    Set-FilterProperty $Preferences 'maxEnergyLoss' ([Math]::Max(0, [Math]::Min(1000, [int]$Preferences.maxEnergyLoss)))
    Set-FilterProperty $Preferences 'maxNerveLoss' ([Math]::Max(0, [Math]::Min(32767, [int]$Preferences.maxNerveLoss)))
    Set-FilterProperty $Preferences 'sortMode' (Normalize-SortMode $Preferences.sortMode)
    return $Preferences
}

function Read-UiPreferences {
    $prefs = Read-FilterJson $PreferenceFile
    return (Normalize-UiPreferences -Preferences $prefs)
}

function Save-UiPreferences {
    param([object]$Preferences)
    $normalized = Normalize-UiPreferences -Preferences $Preferences
    Write-FilterJsonAtomic -Path $PreferenceFile -Value $normalized
    return $normalized
}

function Start-FilterProjectionRefresh {
    $runner = Join-Path $PSScriptRoot 'RunUpdate.ps1'
    if (-not (Test-Path -LiteralPath $runner)) { throw 'RunUpdate.ps1 is required to republish filter changes.' }
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) { throw 'pwsh.exe is required to republish filter changes.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Update' -f $runner
    Start-Process -FilePath $pwsh.Source -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}

function Toggle-TripBandPreference {
    param([object]$Preferences, [string]$Band)
    $normalized = Normalize-UiPreferences -Preferences $Preferences
    $bandName = $Band.ToLowerInvariant()
    if ($bandName -notin @('short','medium','long')) { throw 'Trip band must be short, medium, or long.' }
    $bands = [string[]]@($normalized.displayTripBands)
    if ($bands -contains $bandName) {
        $bands = [string[]]@($bands | Where-Object { $_ -ne $bandName })
    } else {
        $bands = [string[]]@($bands + $bandName)
    }
    Set-FilterProperty $normalized 'displayTripBands' ([string[]]@($bands | Sort-Object -Unique))
    return $normalized
}

function Reset-UiFilterPreferences {
    param([object]$Preferences)
    $normalized = Normalize-UiPreferences -Preferences $Preferences
    $defaults = New-DefaultUiPreferences
    foreach ($name in @('itemFilterAll','selectedItemIds','displayTripBands','selectedCountryIds','categoryFilterAll','selectedCategories','showProfitableOnly')) {
        Set-FilterProperty $normalized $name $defaults.PSObject.Properties[$name].Value
    }
    Set-FilterProperty $normalized 'selectedTripBands' ([string[]]@('short','medium','long'))
    return $normalized
}

if ($FilterPreferencesSkipMain) { return }

$prefs = Read-UiPreferences
$changed = $false
if ($Action -eq 'ToggleTripBand') {
    $prefs = Toggle-TripBandPreference -Preferences $prefs -Band $Value
    [void](Save-UiPreferences -Preferences $prefs)
    $bands = [string[]]@($prefs.displayTripBands)
    try {
        Set-FilterStateKvValuesAtomic -Updates @{
            UISelectedTripBands = ($bands -join ',')
            UITripShortOn = if ($bands -contains 'short') { '1' } else { '0' }
            UITripMediumOn = if ($bands -contains 'medium') { '1' } else { '0' }
            UITripLongOn = if ($bands -contains 'long') { '1' } else { '0' }
        }
    } catch {
        if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
            Write-TravelAssistantLog -Level ERROR -Component 'preference-action' -Message ('Persist trip-band UI state: ' + $_.Exception.ToString())
        }
    }
    $changed = $true
} elseif ($Action -eq 'ResetFilters') {
    $prefs = Reset-UiFilterPreferences -Preferences $prefs
    [void](Save-UiPreferences -Preferences $prefs)
    $changed = $true
} elseif ($Action -eq 'SetSortMode') {
    $sortMode = Normalize-SortMode $Value
    Set-FilterProperty $prefs 'sortMode' $sortMode
    [void](Save-UiPreferences -Preferences $prefs)
    try { Set-FilterStateKvValueAtomic -Name 'OpportunitySortMode' -Value $sortMode }
    catch {
        if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
            Write-TravelAssistantLog -Level ERROR -Component 'preference-action' -Message ('Persist OpportunitySortMode: ' + $_.Exception.ToString())
        }
    }
    $changed = $true
}

# Sort and trip-band clicks are presentation-only. Their visible result is applied
# in Lua immediately, so persistence must not launch any projection work. Reset is a
# model-affecting change and must flow through the PS7 main updater so the finalized
# ui-state.kv generation is republished rather than mutating only private build state.
if ($changed -and $Action -eq 'ResetFilters') {
    try { Start-FilterProjectionRefresh }
    catch {
        if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
            Write-TravelAssistantLog -Level ERROR -Component 'preference-action' -Message ('Republish reset filters: ' + $_.Exception.ToString())
        }
    }
}
