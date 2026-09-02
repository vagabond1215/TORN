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
Assert-Equal 'Default preference schema is eight' ([int]$defaults.schemaVersion) 8
Assert-True 'Default item filter is All' ([bool]$defaults.itemFilterAll)
Assert-Sequence 'Default trip bands include all three' @($defaults.selectedTripBands) @('short','medium','long')
Assert-Equal 'Default countries include all 11 destinations' @($defaults.selectedCountryIds).Count 11
Assert-True 'Default category filter is All' ([bool]$defaults.categoryFilterAll)
Assert-True 'Default profitable-only is off' (-not [bool]$defaults.showProfitableOnly)
Assert-Equal 'Default ignore list is empty' @($defaults.ignoredItemIds).Count 0
Assert-Equal 'Default market tax is zero percent' ([int]$defaults.itemMarketFeePercent) 0
Assert-Equal 'Default Energy waste policy is Allowed' ([string]$defaults.energyWastePolicy) 'allowed'
Assert-Equal 'Default Nerve waste policy is Allowed' ([string]$defaults.nerveWastePolicy) 'allowed'
Assert-Equal 'Default Energy loss limit is zero' ([int]$defaults.maxEnergyLoss) 0
Assert-Equal 'Default Nerve loss limit is zero' ([int]$defaults.maxNerveLoss) 0
Assert-Equal 'Default opportunity ordering is Upcoming' ([string]$defaults.sortMode) 'upcoming'

$custom = [pscustomobject]@{
    schemaVersion = 1
    travelMode = 'airstrip'
    pinnedMarket = 'united_kingdom:266'
    itemFilterAll = $false
    selectedItemIds = @(266)
    selectedTripBands = @('medium')
    displayTripBands = @('medium')
    selectedCountryIds = @()
    categoryFilterAll = $false
    selectedCategories = @('Plushie')
    showProfitableOnly = $true
    ignoredItemIds = @(277)
    itemMarketFeePercent = 5
    energyWastePolicy = 'LIMITED'
    maxEnergyLoss = 25
    nerveWastePolicy = 'forbidden'
    maxNerveLoss = 7
    sortMode = 'PROFIT'
}
$normalized = Normalize-UiPreferences -Preferences $custom
Assert-Equal 'Preference schema upgrades to eight' ([int]$normalized.schemaVersion) 8
Assert-True 'Retired pin is removed during preference normalization' ($null -eq $normalized.PSObject.Properties['pinnedMarket'])
Assert-Equal 'Empty country selection defaults to all countries' @($normalized.selectedCountryIds).Count 11
Assert-True 'Profitable-only survives normalization' ([bool]$normalized.showProfitableOnly)
Assert-Sequence 'Ignore list survives normalization' @($normalized.ignoredItemIds) @('277')
Assert-True 'Retired 95 percent MV property is removed during normalization' ($null -eq $normalized.PSObject.Properties['use95PercentMarketValue'])
Assert-Equal 'Five percent market tax survives normalization' ([int]$normalized.itemMarketFeePercent) 5
foreach($rate in 0..5){
    $ratePrefs=Normalize-UiPreferences -Preferences ([pscustomobject]@{itemMarketFeePercent=$rate})
    Assert-Equal ("Tax rate {0}% survives normalization" -f $rate) ([int]$ratePrefs.itemMarketFeePercent) $rate
}
Assert-Equal 'Energy policy normalizes case' ([string]$normalized.energyWastePolicy) 'limited'
Assert-Equal 'Energy loss limit survives' ([int]$normalized.maxEnergyLoss) 25
Assert-Equal 'Nerve policy survives' ([string]$normalized.nerveWastePolicy) 'forbidden'
Assert-Equal 'Nerve loss limit survives' ([int]$normalized.maxNerveLoss) 7
Assert-Equal 'Legacy profit sort migrates to gross' ([string]$normalized.sortMode) 'gross'

$toggled = Toggle-TripBandPreference -Preferences $normalized -Band medium
Assert-Equal 'Candidate trip bands remain all three' @($toggled.selectedTripBands).Count 3
Assert-Equal 'Toggling only displayed trip band can leave no bands selected' @($toggled.displayTripBands).Count 0
$toggled = Toggle-TripBandPreference -Preferences $toggled -Band short
Assert-Sequence 'Trip band can be re-enabled independently' @($toggled.displayTripBands) @('short')
Assert-Sequence 'Trip-band toggle preserves Ignore List' @($toggled.ignoredItemIds) @('277')
Assert-Equal 'Trip-band toggle preserves Energy policy' ([string]$toggled.energyWastePolicy) 'limited'
Assert-Equal 'Trip-band toggle preserves Nerve policy' ([string]$toggled.nerveWastePolicy) 'forbidden'
Assert-Equal 'Trip-band toggle preserves market tax' ([int]$toggled.itemMarketFeePercent) 5
Assert-Equal 'Trip-band toggle preserves sort mode' ([string]$toggled.sortMode) 'gross'

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
Assert-Equal 'Reset preserves market tax' ([int]$reset.itemMarketFeePercent) 5
Assert-Equal 'Reset preserves selected ordering' ([string]$reset.sortMode) 'gross'

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
    itemMarketFeePercent=3
    use95PercentMarketValue=$true
    sortMode='chance'
}
$fixed = Normalize-UiPreferences -Preferences $bad
Assert-Equal 'Invalid travel mode falls back safely' ([string]$fixed.travelMode) 'airstrip'
Assert-True 'Retired pin is removed even from invalid legacy preferences' ($null -eq $fixed.PSObject.Properties['pinnedMarket'])
Assert-Sequence 'Candidate trip bands normalize to all three' @($fixed.selectedTripBands) @('short','medium','long')
Assert-Sequence 'Legacy display trip bands are migrated' @($fixed.displayTripBands) @('short')
Assert-Sequence 'Unknown countries are removed' @($fixed.selectedCountryIds) @('united_kingdom')
Assert-Sequence 'Invalid ignored IDs are removed' @($fixed.ignoredItemIds) @('277')
Assert-Equal 'Invalid Energy policy falls back to Allowed' ([string]$fixed.energyWastePolicy) 'allowed'
Assert-Equal 'Invalid Nerve policy falls back to Allowed' ([string]$fixed.nerveWastePolicy) 'allowed'
Assert-Equal 'Energy limit clamps to maximum' ([int]$fixed.maxEnergyLoss) 1000
Assert-Equal 'Nerve limit clamps to zero' ([int]$fixed.maxNerveLoss) 0
Assert-Equal 'Three-percent trader tax survives normalization' ([int]$fixed.itemMarketFeePercent) 3
Assert-True 'Retired 95 percent MV property is stripped from legacy preferences' ($null -eq $fixed.PSObject.Properties['use95PercentMarketValue'])
Assert-Equal 'No separate chance sort is exposed' ([string]$fixed.sortMode) 'upcoming'

$legacyNameSort = Normalize-UiPreferences -Preferences ([pscustomobject]@{ sortMode='name' })
Assert-Equal 'Legacy Name sort migrates to Upcoming because Name is fallback-only' ([string]$legacyNameSort.sortMode) 'upcoming'

$nullDisplay = Normalize-UiPreferences -Preferences ([pscustomobject]@{
    schemaVersion=6
    selectedTripBands=[string[]]@('short','medium','long')
    displayTripBands=$null
    displayTripBandsMigrated=$true
})
Assert-Sequence 'Null migrated display bands recover legacy selection' @($nullDisplay.displayTripBands) @('long','medium','short')

Write-Host 'Opportunity filter/preference tests passed.' -ForegroundColor Green
exit 0
