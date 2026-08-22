param(
    [ValidateSet('None','ToggleTripBand','ResetFilters')]
    [string]$Action = 'None',
    [string]$Value = '',
    [switch]$SkipMain
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'

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
        schemaVersion = 3
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
    }
}

function Normalize-WastePolicy {
    param([object]$Value)
    $policy = ([string]$Value).Trim().ToLowerInvariant()
    if ($policy -notin @('allowed','forbidden','limited')) { return 'allowed' }
    return $policy
}

function Normalize-UiPreferences {
    param([object]$Preferences)

    $defaults = New-DefaultUiPreferences
    if ($null -eq $Preferences) { $Preferences = [pscustomobject]@{} }

    foreach ($property in @($defaults.PSObject.Properties)) {
        if (-not $Preferences.PSObject.Properties[$property.Name]) {
            $Preferences | Add-Member NoteProperty ([string]$property.Name) $property.Value
        }
    }

    Set-FilterProperty $Preferences 'schemaVersion' 3

    $mode = [string]$Preferences.travelMode
    if ($mode -notin @('standard','airstrip','wlt','business')) { Set-FilterProperty $Preferences 'travelMode' 'airstrip' }

    $pin = [string]$Preferences.pinnedMarket
    if (-not [string]::IsNullOrWhiteSpace($pin) -and $pin -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { Set-FilterProperty $Preferences 'pinnedMarket' '' }

    $itemIds = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($id in @($Preferences.selectedItemIds)) {
        $n = 0
        if ([int]::TryParse([string]$id, [ref]$n) -and $n -gt 0) { [void]$itemIds.Add($n) }
    }
    Set-FilterProperty $Preferences 'selectedItemIds' ([int[]]@($itemIds | Sort-Object))

    $bands = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($band in @($Preferences.selectedTripBands)) {
        $b = ([string]$band).ToLowerInvariant()
        if ($b -in @('short','medium','long')) { [void]$bands.Add($b) }
    }
    Set-FilterProperty $Preferences 'selectedTripBands' ([string[]]@($bands | Sort-Object))

    $availableCountries = [string[]]@(Get-FilterAvailableCountryIds)
    $availableCountrySet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in $availableCountries) { [void]$availableCountrySet.Add($id) }
    $countries = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in @($Preferences.selectedCountryIds)) {
        $c = [string]$id
        if ($availableCountrySet.Contains($c)) { [void]$countries.Add($c) }
    }
    Set-FilterProperty $Preferences 'selectedCountryIds' ([string[]]@($countries | Sort-Object))

    $categories = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($category in @($Preferences.selectedCategories)) {
        $value = [string]$category
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$categories.Add($value) }
    }
    Set-FilterProperty $Preferences 'selectedCategories' ([string[]]@($categories | Sort-Object))

    $ignored = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($id in @($Preferences.ignoredItemIds)) {
        $n = 0
        if ([int]::TryParse([string]$id, [ref]$n) -and $n -gt 0) { [void]$ignored.Add($n) }
    }
    Set-FilterProperty $Preferences 'ignoredItemIds' ([int[]]@($ignored | Sort-Object))
    Set-FilterProperty $Preferences 'itemFilterAll' ([bool]$Preferences.itemFilterAll)
    Set-FilterProperty $Preferences 'categoryFilterAll' ([bool]$Preferences.categoryFilterAll)
    Set-FilterProperty $Preferences 'showProfitableOnly' ([bool]$Preferences.showProfitableOnly)
    Set-FilterProperty $Preferences 'use95PercentMarketValue' ([bool]$Preferences.use95PercentMarketValue)
    Set-FilterProperty $Preferences 'energyWastePolicy' (Normalize-WastePolicy $Preferences.energyWastePolicy)
    Set-FilterProperty $Preferences 'nerveWastePolicy' (Normalize-WastePolicy $Preferences.nerveWastePolicy)
    Set-FilterProperty $Preferences 'maxEnergyLoss' ([Math]::Max(0,[Math]::Min(1000,[int]$Preferences.maxEnergyLoss)))
    Set-FilterProperty $Preferences 'maxNerveLoss' ([Math]::Max(0,[Math]::Min(32767,[int]$Preferences.maxNerveLoss)))

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
    $band = $Band.ToLowerInvariant()
    if ($band -notin @('short','medium','long')) { throw 'Trip band must be short, medium, or long.' }
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($value in @($normalized.selectedTripBands)) { [void]$set.Add([string]$value) }
    if ($set.Contains($band)) { [void]$set.Remove($band) } else { [void]$set.Add($band) }
    Set-FilterProperty $normalized 'selectedTripBands' ([string[]]@($set | Sort-Object))
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

if ($SkipMain) { return }

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
}

if ($changed) {
    $filterState = Join-Path $PSScriptRoot 'FilterState.ps1'
    if (Test-Path -LiteralPath $filterState) {
        try { & $filterState } catch { }
    }
}
