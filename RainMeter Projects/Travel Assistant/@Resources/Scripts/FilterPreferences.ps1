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
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'
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
        schemaVersion = 5
        travelMode = 'airstrip'
        pinnedMarket = ''
        itemFilterAll = $true
        selectedItemIds = [int[]]@(Get-FilterVisibleItemIds)
        selectedTripBands = [string[]]@('short','medium','long')
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
    # Migrate 0.6 pre-change sort values without losing the user's intent.
    if ($mode -eq 'optimal') { return 'profit_per_hour' }
    if ($mode -eq 'profit') { return 'gross' }
    if ($mode -eq 'time') { return 'upcoming' }
    if ($mode -notin @('upcoming','gross','profit_per_hour')) { return 'upcoming' }
    return $mode
}

function Normalize-UiPreferences {
    param([object]$Preferences)
    $defaults = New-DefaultUiPreferences
    if ($null -eq $Preferences) { $Preferences = [pscustomobject]@{} }

    foreach ($property in @($defaults.PSObject.Properties)) {
        if (-not $Preferences.PSObject.Properties[$property.Name]) { $Preferences | Add-Member NoteProperty ([string]$property.Name) $property.Value }
    }
    Set-FilterProperty $Preferences 'schemaVersion' 5

    $mode = [string]$Preferences.travelMode
    if ($mode -notin @('standard','airstrip','wlt','business')) { Set-FilterProperty $Preferences 'travelMode' 'airstrip' }
    $pin = [string]$Preferences.pinnedMarket
    if (-not [string]::IsNullOrWhiteSpace($pin) -and $pin -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { Set-FilterProperty $Preferences 'pinnedMarket' '' }

    # Windows PowerShell 5.1 can throw PSEnumerableBinder "Argument types do not match"
    # when a generic HashSet/List is fed through @(...). Preference collections are
    # small, so use ordinary PowerShell arrays plus Sort-Object -Unique here.
    $itemIds = @()
    foreach ($id in @($Preferences.selectedItemIds)) {
        $n = 0
        if ([int]::TryParse([string]$id, [ref]$n) -and $n -gt 0) { $itemIds += $n }
    }
    Set-FilterProperty $Preferences 'selectedItemIds' ([int[]]@($itemIds | Sort-Object -Unique))

    $bands = @()
    foreach ($band in @($Preferences.selectedTripBands)) {
        $value = ([string]$band).ToLowerInvariant()
        if ($value -in @('short','medium','long')) { $bands += $value }
    }
    Set-FilterProperty $Preferences 'selectedTripBands' ([string[]]@($bands | Sort-Object -Unique))

    $availableCountries = [string[]]@(Get-FilterAvailableCountryIds)
    $countries = @()
    foreach ($id in @($Preferences.selectedCountryIds)) {
        $value = [string]$id
        if ($availableCountries -contains $value) { $countries += $value }
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

function Toggle-TripBandPreference {
    param([object]$Preferences, [string]$Band)
    $normalized = Normalize-UiPreferences -Preferences $Preferences
    $bandName = $Band.ToLowerInvariant()
    if ($bandName -notin @('short','medium','long')) { throw 'Trip band must be short, medium, or long.' }
    $bands = [string[]]@($normalized.selectedTripBands)
    if ($bands -contains $bandName) {
        $bands = [string[]]@($bands | Where-Object { $_ -ne $bandName })
    } else {
        $bands = [string[]]@($bands + $bandName)
    }
    Set-FilterProperty $normalized 'selectedTripBands' ([string[]]@($bands | Sort-Object -Unique))
    return $normalized
}

function Reset-UiFilterPreferences {
    param([object]$Preferences)
    $normalized = Normalize-UiPreferences -Preferences $Preferences
    $defaults = New-DefaultUiPreferences
    foreach ($name in @('itemFilterAll','selectedItemIds','selectedTripBands','selectedCountryIds','categoryFilterAll','selectedCategories','showProfitableOnly')) {
        Set-FilterProperty $normalized $name $defaults.PSObject.Properties[$name].Value
    }
    return $normalized
}

if ($FilterPreferencesSkipMain) { return }

$prefs = Read-UiPreferences
$changed = $false
if ($Action -eq 'ToggleTripBand') {
    $prefs = Toggle-TripBandPreference -Preferences $prefs -Band $Value
    [void](Save-UiPreferences -Preferences $prefs)
    $changed = $true
} elseif ($Action -eq 'ResetFilters') {
    $prefs = Reset-UiFilterPreferences -Preferences $prefs
    [void](Save-UiPreferences -Preferences $prefs)
    $changed = $true
} elseif ($Action -eq 'SetSortMode') {
    Set-FilterProperty $prefs 'sortMode' (Normalize-SortMode $Value)
    [void](Save-UiPreferences -Preferences $prefs)
    $changed = $true
}

if ($changed) {
    # A pure sort change does not alter filters, collection, or route economics.
    # Reproject the opportunity order directly so the shared Rainmeter RunCommand
    # measure is released as quickly as possible.
    if ($Action -ne 'SetSortMode') {
        $filterState = Join-Path $PSScriptRoot 'FilterState.ps1'
        if (Test-Path -LiteralPath $filterState) {
            try { & $filterState }
            catch {
                if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
                    Write-TravelAssistantLog -Level ERROR -Component 'preference-action' -Message ('FilterState.ps1: ' + $_.Exception.ToString())
                }
            }
        }
    }

    $opportunities = Join-Path $PSScriptRoot 'OpportunityState.ps1'
    if (Test-Path -LiteralPath $opportunities) {
        try { & $opportunities }
        catch {
            if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
                Write-TravelAssistantLog -Level ERROR -Component 'preference-action' -Message ('OpportunityState.ps1: ' + $_.Exception.ToString())
            }
        }
    }
}
