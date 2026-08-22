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
Assert-Equal 'Default preference schema is four' ([int]$defaults.schemaVersion) 4
Assert-True 'Default item filter is All' ([bool]$defaults.itemFilterAll)
Assert-Sequence 'Default trip bands include all three' @($defaults.selectedTripBands) @('short','medium','long')
Assert-Equal 'Default countries include all 11 destinations' @($defaults.selectedCountryIds).Count 11
Assert-True 'Default category filter is All' ([bool]$defaults.categoryFilterAll)
Assert-True 'Default profitable-only is off' (-not [bool]$defaults.showProfitableOnly)
Assert-Equal 'Default ignore list is empty' @($defaults.ignoredItemIds).Count 0
Assert-True 'Default MV basis remains 100 percent' (-not [bool]$defaults.use95PercentMarketValue)
Assert-Equal 'Default Energy waste policy is Allowed' ([string]$defaults.energyWastePolicy) 'allowed'
Assert-Equal 'Default Nerve waste policy is Allowed' ([string]$defaults.nerveWastePolicy) 'allowed'
Assert-Equal 'Default Energy loss limit is zero' ([int]$defaults.maxEnergyLoss) 0
Assert-Equal 'Default Nerve loss limit is zero' ([int]$defaults.maxNerveLoss) 0
Assert-Equal 'Default opportunity ordering is Optimal' ([string]$defaults.sortMode) 'optimal'

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
    use95PercentMarketValue = $true
    energyWastePolicy = 'LIMITED'
    maxEnergyLoss = 25
    nerveWastePolicy = 'forbidden'
    maxNerveLoss = 7
    sortMode = 'PROFIT'
}
$normalized = Normalize-UiPreferences -Preferences $custom
Assert-Equal 'Preference schema upgrades to four' ([int]$normalized.schemaVersion) 4
Assert-Equal 'Legacy pin remains preserved as harmless local preference' ([string]$normalized.pinnedMarket) 'united_kingdom:266'
Assert-Equal 'Explicit empty country selection stays empty' @($normalized.selectedCountryIds).Count 0
Assert-True 'Profitable-only survives normalization' ([bool]$normalized.showProfitableOnly)
Assert-Sequence 'Ignore list survives normalization' @($normalized.ignoredItemIds) @('277')
Assert-True '95 percent MV basis survives normalization' ([bool]$normalized.use95PercentMarketValue)
Assert-Equal 'Energy policy normalizes case' ([string]$normalized.energyWastePolicy) 'limited'
Assert-Equal 'Energy loss limit survives' ([int]$normalized.maxEnergyLoss) 25
Assert-Equal 'Nerve policy survives' ([string]$normalized.nerveWastePolicy) 'forbidden'
Assert-Equal 'Nerve loss limit survives' ([int]$normalized.maxNerveLoss) 7
Assert-Equal 'Opportunity sort normalizes case' ([string]$normalized.sortMode) 'profit'

$toggled = Toggle-TripBandPreference -Preferences $normalized -Band medium
Assert-Equal 'Toggling only enabled trip band can leave no bands selected' @($toggled.selectedTripBands).Count 0
$toggled = Toggle-TripBandPreference -Preferences $toggled -Band short
Assert-Sequence 'Trip band can be re-enabled independently' @($toggled.selectedTripBands) @('short')
Assert-Sequence 'Trip-band toggle preserves Ignore List' @($toggled.ignoredItemIds) @('277')
Assert-Equal 'Trip-band toggle preserves Energy policy' ([string]$toggled.energyWastePolicy) 'limited'
Assert-Equal 'Trip-band toggle preserves Nerve policy' ([string]$toggled.nerveWastePolicy) 'forbidden'
Assert-True 'Trip-band toggle preserves 95 percent MV preference' ([bool]$toggled.use95PercentMarketValue)
Assert-Equal 'Trip-band toggle preserves sort mode' ([string]$toggled.sortMode) 'profit'

$reset = Reset-UiFilterPreferences -Preferences $normalized
Assert-True 'Reset restores item All' ([bool]$reset.itemFilterAll)
Assert-Sequence 'Reset restores all trip bands' @($reset.selectedTripBands) @('short','medium','long')
Assert-Equal 'Reset restores all countries' @($reset.selectedCountryIds).Count 11
Assert-True 'Reset restores category All' ([bool]$reset.categoryFilterAll)
Assert-True 'Reset clears profitable-only opportunity filter' (-not [bool]$reset.showProfitableOnly)
Assert-Sequence 'Reset preserves Ignore List' @($reset.ignoredItemIds) @('277')
Assert-Equal 'Reset preserves travel mode' ([string]$reset.travelMode) 'airstrip'
Assert-Equal 'Reset preserves Energy policy' ([string]$reset.energyWastePolicy) 'limited'
Assert-Equal 'Reset preserves Energy limit' ([int]$reset.maxEnergyLoss) 25
Assert-Equal 'Reset preserves Nerve policy' ([string]$reset.nerveWastePolicy) 'forbidden'
Assert-Equal 'Reset preserves Nerve limit' ([int]$reset.maxNerveLoss) 7
Assert-True 'Reset preserves 95 percent MV basis' ([bool]$reset.use95PercentMarketValue)
Assert-Equal 'Reset preserves selected ordering' ([string]$reset.sortMode) 'profit'

$bad = [pscustomobject]@{
    travelMode='nonsense'
    pinnedMarket='bad pin'
    selectedTripBands=@('short','warp')
    selectedCountryIds=@('united_kingdom','nowhere')
    ignoredItemIds=@('277','oops')
    energyWastePolicy='maybe'
    nerveWastePolicy='sometimes'
    maxEnergyLoss=5000
    maxNerveLoss=-10
    sortMode='chance'
}
$fixed = Normalize-UiPreferences -Preferences $bad
Assert-Equal 'Invalid travel mode falls back safely' ([string]$fixed.travelMode) 'airstrip'
Assert-Equal 'Invalid legacy pin is cleared' ([string]$fixed.pinnedMarket) ''
Assert-Sequence 'Invalid trip bands are removed' @($fixed.selectedTripBands) @('short')
Assert-Sequence 'Unknown countries are removed' @($fixed.selectedCountryIds) @('united_kingdom')
Assert-Sequence 'Invalid ignored IDs are removed' @($fixed.ignoredItemIds) @('277')
Assert-Equal 'Invalid Energy policy falls back to Allowed' ([string]$fixed.energyWastePolicy) 'allowed'
Assert-Equal 'Invalid Nerve policy falls back to Allowed' ([string]$fixed.nerveWastePolicy) 'allowed'
Assert-Equal 'Energy limit clamps to maximum' ([int]$fixed.maxEnergyLoss) 1000
Assert-Equal 'Nerve limit clamps to zero' ([int]$fixed.maxNerveLoss) 0
Assert-Equal 'No separate chance sort is exposed' ([string]$fixed.sortMode) 'optimal'

Write-Host 'Opportunity filter/preference tests passed.' -ForegroundColor Green
exit 0
