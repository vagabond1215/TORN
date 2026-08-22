$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1') -SkipMain

function Assert-Equal {
    param([string]$Name,$Actual,$Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}
function Assert-True {
    param([string]$Name,[bool]$Condition)
    if (-not $Condition) { throw "$Name - condition was false." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}
function Assert-Sequence {
    param([string]$Name,[object[]]$Actual,[object[]]$Expected)
    $a = @($Actual | ForEach-Object { [string]$_ }) -join '|'
    $e = @($Expected | ForEach-Object { [string]$_ }) -join '|'
    Assert-Equal -Name $Name -Actual $a -Expected $e
}

$defaults = New-DefaultUiPreferences
Assert-True 'Default item filter is All' ([bool]$defaults.itemFilterAll)
Assert-Sequence 'Default trip bands include all three' @($defaults.selectedTripBands) @('short','medium','long')
Assert-Equal 'Default countries include all 11 destinations' @($defaults.selectedCountryIds).Count 11
Assert-True 'Default category filter is All' ([bool]$defaults.categoryFilterAll)
Assert-True 'Default profitable-only is off' (-not [bool]$defaults.showProfitableOnly)
Assert-Equal 'Default ignore list is empty' @($defaults.ignoredItemIds).Count 0

$custom = [pscustomobject]@{
    schemaVersion = 1
    travelMode = 'airstrip'
    pinnedMarket = 'united_kingdom:266'
    itemFilterAll = $false
    selectedItemIds = @(266)
    selectedTripBands = @('medium')
    selectedCountryIds = @()
    categoryFilterAll = $false
    selectedCategories = @('Plushie')
    showProfitableOnly = $true
    ignoredItemIds = @(277)
}
$normalized = Normalize-UiPreferences -Preferences $custom
Assert-Equal 'Preference schema upgrades to two' ([int]$normalized.schemaVersion) 2
Assert-Equal 'Pin survives normalization' ([string]$normalized.pinnedMarket) 'united_kingdom:266'
Assert-Equal 'Explicit empty country selection stays empty' @($normalized.selectedCountryIds).Count 0
Assert-True 'Profitable-only survives normalization' ([bool]$normalized.showProfitableOnly)
Assert-Sequence 'Ignore list survives normalization' @($normalized.ignoredItemIds) @('277')

$toggled = Toggle-TripBandPreference -Preferences $normalized -Band medium
Assert-Equal 'Toggling only enabled trip band can leave no bands selected' @($toggled.selectedTripBands).Count 0
$toggled = Toggle-TripBandPreference -Preferences $toggled -Band short
Assert-Sequence 'Trip band can be re-enabled independently' @($toggled.selectedTripBands) @('short')
Assert-Equal 'Trip-band toggle preserves pin' ([string]$toggled.pinnedMarket) 'united_kingdom:266'
Assert-Sequence 'Trip-band toggle preserves ignore list' @($toggled.ignoredItemIds) @('277')

$reset = Reset-UiFilterPreferences -Preferences $normalized
Assert-True 'Reset restores item All' ([bool]$reset.itemFilterAll)
Assert-Sequence 'Reset restores all trip bands' @($reset.selectedTripBands) @('short','medium','long')
Assert-Equal 'Reset restores all countries' @($reset.selectedCountryIds).Count 11
Assert-True 'Reset restores category All' ([bool]$reset.categoryFilterAll)
Assert-True 'Reset clears profitable-only presentation filter' (-not [bool]$reset.showProfitableOnly)
Assert-Equal 'Reset preserves pin' ([string]$reset.pinnedMarket) 'united_kingdom:266'
Assert-Sequence 'Reset preserves Ignore List' @($reset.ignoredItemIds) @('277')
Assert-Equal 'Reset preserves travel mode' ([string]$reset.travelMode) 'airstrip'

$bad = [pscustomobject]@{ travelMode='nonsense'; pinnedMarket='bad pin'; selectedTripBands=@('short','warp'); selectedCountryIds=@('united_kingdom','nowhere'); ignoredItemIds=@('277','oops') }
$fixed = Normalize-UiPreferences -Preferences $bad
Assert-Equal 'Invalid travel mode falls back safely' ([string]$fixed.travelMode) 'airstrip'
Assert-Equal 'Invalid pin is cleared' ([string]$fixed.pinnedMarket) ''
Assert-Sequence 'Invalid trip bands are removed' @($fixed.selectedTripBands) @('short')
Assert-Sequence 'Unknown countries are removed' @($fixed.selectedCountryIds) @('united_kingdom')
Assert-Sequence 'Invalid ignored IDs are removed' @($fixed.ignoredItemIds) @('277')

Write-Host 'Filter preference tests passed.' -ForegroundColor Green
exit 0
