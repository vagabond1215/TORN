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
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (Test-Path -LiteralPath $RuntimeLogScript) { . $RuntimeLogScript }
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for safe filter preference persistence.' }
. $AtomicFileScript

function Read-FilterJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-FilterJsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 20)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $json = $Value | ConvertTo-Json -Depth $Depth
    Write-TravelAssistantAtomicText -Path $Path -Text $json
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
        $stateText = Read-TravelAssistantSharedText -Path $StateKvFile
        foreach ($line in @($stateText -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $index = $line.IndexOf('=')
            if ($index -lt 1) { continue }
            $key = $line.Substring(0,$index).Trim([char]0xFEFF).Trim()
            $values[$key] = $line.Substring($index+1).Trim()
        }
    }
    foreach ($key in @($Updates.Keys)) { $values[[string]$key] = [string]$Updates[$key] }
    New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
    $lines = @()
    foreach ($key in @($values.Keys | Sort-Object)) {
        $safe = ([string]$values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines += ($key + '=' + $safe)
    }
    $text = ([string[]]$lines) -join [Environment]::NewLine
    Write-TravelAssistantAtomicText -Path $StateKvFile -Text $text
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
        schemaVersion = 8
        travelMode = 'airstrip'
        itemFilterAll = $true
        selectedItemIds = [int[]]@(Get-FilterVisibleItemIds)
        selectedTripBands = [string[]]@('short','medium','long')
        displayTripBands = [string[]]@('short','medium','long')
        selectedCountryIds = [string[]]@(Get-FilterAvailableCountryIds)
        categoryFilterAll = $true
        selectedCategories = [string[]]@(Get-FilterVisibleCategories)
        showProfitableOnly = $false
        ignoredItemIds = [int[]]@()
        use95PercentMarketValue = $false
        itemMarketFeePercent = 0
        energyWastePolicy = 'allowed'
        maxEnergyLoss = 0
        nerveWastePolicy = 'allowed'
        maxNerveLoss = 0
        sortMode = 'upcoming'
    }
}

function Normalize-ItemMarketFeePercent {
    param([object]$Value)
    $percent=0.0
    if (-not [double]::TryParse([string]$Value,[ref]$percent)) { return 0 }
    if ([Math]::Abs($percent-5.0) -lt 0.001) { return 5 }
    return 0
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
    if ($mode -notin @('upcoming','gross','profit_per_hour')) { return 'upcoming' }
    return $mode
}

function Normalize-TripBands {
    param([object[]]$Values)
    $bands = @()
    foreach ($band in @($Values)) {
        $value = ([string]$band).ToLowerInvariant()
        if ($value -in @('short','medium','long')) { $bands += $value }
    }
    # Preserve an intentional empty selection as an empty string array on Windows
    # PowerShell 5.1; returning it normally collapses the value to $null.
    return ,([string[]]@($bands | Sort-Object -Unique))
}

function Normalize-UiPreferences {
    param([object]$Preferences)
    $defaults = New-DefaultUiPreferences
    if ($null -eq $Preferences) { $Preferences = [pscustomobject]@{} }

    $sourceSchema = 0
    if ($Preferences.PSObject.Properties['schemaVersion']) { [void][int]::TryParse([string]$Preferences.schemaVersion,[ref]$sourceSchema) }
    $hasUsableDisplayBands = $Preferences.PSObject.Properties['displayTripBands'] -and $null -ne $Preferences.displayTripBands
    $legacyDisplayBands = @('short','medium','long')
    if (-not $hasUsableDisplayBands -and $sourceSchema -lt 7 -and $Preferences.PSObject.Properties['selectedTripBands']) {
        $legacyDisplayBands = [string[]](Normalize-TripBands @($Preferences.selectedTripBands))
    }

    foreach ($property in @($defaults.PSObject.Properties)) {
        if (-not $Preferences.PSObject.Properties[$property.Name]) { $Preferences | Add-Member NoteProperty ([string]$property.Name) $property.Value }
    }
    Set-FilterProperty $Preferences 'schemaVersion' 8
    # Card pinning was retired with the old independent-card surface. Strip the
    # legacy property in memory so the next normal preference save removes it.
    if ($null -ne $Preferences.PSObject.Properties['pinnedMarket']) {
        [void]$Preferences.PSObject.Properties.Remove('pinnedMarket')
    }

    $mode = [string]$Preferences.travelMode
    if ($mode -notin @('standard','airstrip','wlt','business')) { Set-FilterProperty $Preferences 'travelMode' 'airstrip' }
    $itemIds = @()
    foreach ($id in @($Preferences.selectedItemIds)) {
        $n = 0
        if ([int]::TryParse([string]$id, [ref]$n) -and $n -gt 0) { $itemIds += $n }
    }
    Set-FilterProperty $Preferences 'selectedItemIds' ([int[]]@($itemIds | Sort-Object -Unique))

    Set-FilterProperty $Preferences 'selectedTripBands' ([string[]]@('short','medium','long'))
    if ($hasUsableDisplayBands) {
        Set-FilterProperty $Preferences 'displayTripBands' (Normalize-TripBands @($Preferences.displayTripBands))
    } else {
        # A JSON null is an incomplete migration, not an intentional "all bands off"
        # selection. Recover legacy bands (or current defaults) in memory without
        # turning startup reads into preference writes.
        Set-FilterProperty $Preferences 'displayTripBands' ([string[]]$legacyDisplayBands)
    }
    Set-FilterProperty $Preferences 'displayTripBandsMigrated' $true

    $availableCountries = [string[]]@(Get-FilterAvailableCountryIds)
    $countries = @()
    foreach ($id in @($Preferences.selectedCountryIds)) {
        $value = [string]$id
        if ($availableCountries -contains $value) { $countries += $value }
    }
    # Empty/missing/invalid country state is never a useful startup selection. Keep
    # any real saved selection, otherwise use all collected countries in memory.
    # Reads remain side-effect free; explicit user saves/reset persist preferences.
    if ($countries.Count -eq 0 -and $availableCountries.Count -gt 0) {
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
    Set-FilterProperty $Preferences 'itemMarketFeePercent' (Normalize-ItemMarketFeePercent $Preferences.itemMarketFeePercent)
    Set-FilterProperty $Preferences 'energyWastePolicy' (Normalize-WastePolicy $Preferences.energyWastePolicy)
    Set-FilterProperty $Preferences 'nerveWastePolicy' (Normalize-WastePolicy $Preferences.nerveWastePolicy)
    Set-FilterProperty $Preferences 'maxEnergyLoss' ([Math]::Max(0, [Math]::Min(1000, [int]$Preferences.maxEnergyLoss)))
    Set-FilterProperty $Preferences 'maxNerveLoss' ([Math]::Max(0, [Math]::Min(32767, [int]$Preferences.maxNerveLoss)))
    Set-FilterProperty $Preferences 'sortMode' (Normalize-SortMode $Preferences.sortMode)
    return $Preferences
}

function Read-UiPreferences {
    # Read paths must be side-effect free. In particular, startup and popup opening
    # must never block on an atomic preference write merely to repair defaults.
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
    $launcher = Join-Path $PSScriptRoot 'LaunchUpdate.ps1'
    if (-not (Test-Path -LiteralPath $launcher)) { throw 'LaunchUpdate.ps1 is required to republish filter changes.' }
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) { throw 'pwsh.exe is required to republish filter changes.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Update' -f $launcher
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
    $availableCountries = [string[]]@(Get-FilterAvailableCountryIds)
    $visibleItems = [int[]]@(Get-FilterVisibleItemIds)
    $visibleCategories = [string[]]@(Get-FilterVisibleCategories)

    if ($availableCountries.Count -eq 0) { throw 'Cannot reset filters because no collected countries are available.' }
    if ($visibleItems.Count -eq 0) { throw 'Cannot reset filters because no visible items are available.' }

    Set-FilterProperty $normalized 'schemaVersion' 8
    Set-FilterProperty $normalized 'itemFilterAll' $true
    Set-FilterProperty $normalized 'selectedItemIds' ([int[]]@($visibleItems))
    Set-FilterProperty $normalized 'selectedTripBands' ([string[]]@('short','medium','long'))
    Set-FilterProperty $normalized 'displayTripBands' ([string[]]@('short','medium','long'))
    Set-FilterProperty $normalized 'selectedCountryIds' ([string[]]@($availableCountries))
    Set-FilterProperty $normalized 'categoryFilterAll' $true
    Set-FilterProperty $normalized 'selectedCategories' ([string[]]@($visibleCategories))
    Set-FilterProperty $normalized 'showProfitableOnly' $false
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

if ($changed -and $Action -eq 'ResetFilters') {
    try { Start-FilterProjectionRefresh }
    catch {
        if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
            Write-TravelAssistantLog -Level ERROR -Component 'preference-action' -Message ('Republish reset filters: ' + $_.Exception.ToString())
        }
    }
}
