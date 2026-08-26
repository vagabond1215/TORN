$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message){$script:errors.Add($Message)}

$files=@{
 Preferences=Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
 Popup=Join-Path $ProjectRoot '@Resources\Scripts\OpenFilterPopup.ps1'
 Launcher=Join-Path $ProjectRoot '@Resources\Scripts\LaunchFilterPopup.ps1'
 State=Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1'
 Opportunities=Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
 Settings=Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
 StateReader=Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
 Ini=Join-Path $ProjectRoot 'TravelAssistant.ini'
 Countries=Join-Path $ProjectRoot 'config\countries.json'
}
foreach($entry in $files.GetEnumerator()){if(-not(Test-Path -LiteralPath $entry.Value)){Fail "Missing $($entry.Key): $($entry.Value)"}}

foreach($path in @($files.Preferences,$files.Popup,$files.Launcher,$files.State,$files.Opportunities,$files.Settings)){
 if(-not(Test-Path -LiteralPath $path)){continue}
 $tokens=$null;$parseErrors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
 foreach($parseError in @($parseErrors)){Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)"}
}

if(Test-Path -LiteralPath $files.Preferences){
 $text=Get-Content -LiteralPath $files.Preferences -Raw
 foreach($token in @(
  'schemaVersion = 7','selectedItemIds','selectedTripBands','displayTripBands','selectedCountryIds','selectedCategories',
  'showProfitableOnly','ignoredItemIds','use95PercentMarketValue','energyWastePolicy','nerveWastePolicy',
  "sortMode = 'upcoming'",'Normalize-SortMode',"@('name','upcoming','gross','profit_per_hour')",'SetSortMode',
  'Set-FilterStateKvValuesAtomic','UISelectedTripBands','UITripShortOn','UITripMediumOn','UITripLongOn',
  '$countries.Count -eq 0','Write-FilterJsonAtomic -Path $PreferenceFile -Value $normalized','Start-FilterProjectionRefresh','LaunchUpdate.ps1','$Action -eq ''ResetFilters'''
 )){if(-not$text.Contains($token)){Fail "FilterPreferences.ps1 missing '$token'."}}
 if($text -notmatch '(?s)if \(\$Action -eq ''ToggleTripBand''\).*?Save-UiPreferences.*?Set-FilterStateKvValuesAtomic') { Fail 'Trip-band persistence must remain a tiny preference/state write.' }

 . $files.Preferences -SkipMain
 $available=@(Get-FilterAvailableCountryIds)
 $legacy=[pscustomobject]@{schemaVersion=6;selectedCountryIds=[string[]]@()}
 $legacyNormalized=Normalize-UiPreferences -Preferences $legacy
 if(@($legacyNormalized.selectedCountryIds).Count -ne $available.Count){Fail "Legacy empty country selection should normalize to all $($available.Count) collected countries."}
 $current=[pscustomobject]@{schemaVersion=7;selectedCountryIds=[string[]]@()}
 $currentNormalized=Normalize-UiPreferences -Preferences $current
 if(@($currentNormalized.selectedCountryIds).Count -ne $available.Count){Fail 'Schema 7 empty country selection must default to all countries on startup/refresh.'}
 $subset=@($available | Select-Object -First 2)
 $selected=[pscustomobject]@{schemaVersion=7;selectedCountryIds=[string[]]$subset}
 $selectedNormalized=Normalize-UiPreferences -Preferences $selected
 if(@($selectedNormalized.selectedCountryIds).Count -ne $subset.Count){Fail 'A nonempty saved country selection must remain persistent.'}
 $nullBands=[pscustomobject]@{schemaVersion=6;selectedTripBands=[string[]]@('short','medium','long');displayTripBands=$null;displayTripBandsMigrated=$true}
 $nullBandsNormalized=Normalize-UiPreferences -Preferences $nullBands
 if(@($nullBandsNormalized.displayTripBands).Count -ne 3){Fail 'A null migrated displayTripBands value must recover all legacy trip bands.'}
 $explicitEmptyBands=[pscustomobject]@{schemaVersion=7;displayTripBands=[string[]]@()}
 $explicitEmptyBandsNormalized=Normalize-UiPreferences -Preferences $explicitEmptyBands
 if(@($explicitEmptyBandsNormalized.displayTripBands).Count -ne 0){Fail 'An explicit empty displayTripBands array must remain a valid user selection.'}
}

if(Test-Path -LiteralPath $files.Popup){
 $text=Get-Content -LiteralPath $files.Popup -Raw
 foreach($token in @("'Item'","'Country'","'Category'","'Ignore'",'observedMarkets','Start-FilterProjectionRefresh','RuntimeLog.ps1','Read-OptionalPopupJson','$engine=Read-OptionalPopupJson $EngineStateFile','$bands=New-StringSet @($prefs.displayTripBands)')){if(-not$text.Contains($token)){Fail "Filter popup missing '$token'."}}
 if($text.Contains('$bands=New-StringSet @($prefs.selectedTripBands)')){Fail 'Country popup must scope rows from displayTripBands, not the always-on candidate trip bands.'}
 $legacyPartial="foreach(`$scriptName in @('OptimalRoute.ps1','OpportunityState.ps1','FilterState.ps1'))"
 if($text.Contains($legacyPartial)){Fail 'Filter popup must not mutate private build state through an ad-hoc partial projection chain.'}
 if($text -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest'){Fail 'Filter popup must remain local-only.'}
}

if(Test-Path -LiteralPath $files.Launcher){
 $text=Get-Content -LiteralPath $files.Launcher -Raw
 foreach($token in @('PopupHost.ps1','-Popup Filter','-WindowStyle Hidden','-STA','System.Diagnostics.ProcessStartInfo','return')){if(-not$text.Contains($token)){Fail "Filter launcher missing '$token'."}}
 if($text.Contains('exit 0')){Fail 'Filter launcher must return after spawning so nested settings popups remain alive.'}
}

if(Test-Path -LiteralPath $files.Settings){
 $text=Get-Content -LiteralPath $files.Settings -Raw
 foreach($token in @('LaunchFilterPopup.ps1','LaunchSettings.ps1','LaunchUpdate.ps1','& $UpdateLauncher -Action Update')){if(-not$text.Contains($token)){Fail "OpenOptimizerSettings.ps1 missing '$token'."}}
 if($text.Contains("Join-Path `$PSScriptRoot 'RunUpdate.ps1'")){Fail 'Optimizer Settings must not bypass LaunchUpdate.ps1.'}
}

if(Test-Path -LiteralPath $files.State){
 $text=Get-Content -LiteralPath $files.State -Raw
 foreach($token in @(
  'UIItemFilterAll','UISelectedTripBands','UISelectedCountryIds','UICategoryFilterAll','UIShowProfitableOnly','$prefs.displayTripBands',
  'Get-ActiveMarketSourceRange','UIOldestMarketSourceTimestamp','UIOldestActiveMarketSourceTimestamp','UIFreshestMarketSourceTimestamp',
  '$state[''UIOldestMarketSourceTimestamp''] = [long]$sourceRange.freshest','observedMarkets','sourceTimestamp'
 )){if(-not$text.Contains($token)){Fail "FilterState.ps1 missing '$token'."}}
}

if(Test-Path -LiteralPath $files.Opportunities){
 $text=Get-Content -LiteralPath $files.Opportunities -Raw
 foreach($token in @(
  'Get-OpportunityNextWindow','Get-OpportunityProbabilityAtAge','Get-OpportunityNextRecurringWindow','grossProfit','profitPerHour','elapsedSeconds','probabilityKnown',
  "'LEARNING'",'$availableQuantity = $stock',"sortMode -eq 'name'","sortMode -eq 'gross'","sortMode -eq 'profit_per_hour'",
  '$maxProjectedRows = 256',"'TripBand'",'tripBand=$tripBand','OpportunityCount'
 )){if(-not$text.Contains($token)){Fail "OpportunityState.ps1 missing '$token'."}}
 foreach($retired in @('expectedGross=','optimalScore=')){if($text.Contains($retired)){Fail "OpportunityState.ps1 retains retired hidden-ranking token '$retired'."}}
}

if(Test-Path -LiteralPath $files.StateReader){
 $text=Get-Content -LiteralPath $files.StateReader -Raw
 foreach($token in @(
  'function OpenFilter(filterName)','function ToggleTripBand(band)','function ResetFilters()','function SetSortMode(mode)',
  'currentOpportunityRows','sortOpportunityRows','locallyFilteredSortedProjection','pendingTripBands','activeTripBands','projectedTripBands',
  'maxCandidateRows = 256','TripBand','collapseInlineGraph','MeasureInlineGraph','MeasureItemViewer','safeLeaveText','UIOldestMarketSourceTimestamp',
  'resolvedItemName',"name:match('^Item%s+%d+$')","combinedPrice = 'BUY ' .. price .. '/ea'","combinedPrice = combinedPrice .. ' | '","return name .. ' - ' .. country"
 )){if(-not$text.Contains($token)){Fail "StateReader.lua missing '$token'."}}
 if($text.Contains("runViewerMeasure('inline_'")){Fail 'Sort/filter UI must not route inline history through the popup Viewer.'}
}

if(Test-Path -LiteralPath $files.Ini){
 $ini=Get-Content -LiteralPath $files.Ini -Raw
 foreach($section in @('MeasureFilterPopup','MeasurePreferenceAction','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterSortName','MeterSortUpcoming','MeterSortGross','MeterSortProfitHour')){if($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')){Fail "TravelAssistant.ini missing [$section]."}}
 foreach($retired in @('MeterSortOptimal','MeterSortTime','MeterSortLabel')){if($ini -match ('(?m)^\['+$retired+'\]\s*$')){Fail "Retired sort meter [$retired] returned."}}
}

if(Test-Path -LiteralPath $files.Countries){
 $countries=Get-Content -LiteralPath $files.Countries -Raw|ConvertFrom-Json
 $collect=@($countries.countries|Where-Object{$_.collect -eq $true})
 if($collect.Count -ne 11){Fail "Expected 11 collect=true destinations; found $($collect.Count)."}
}

if($errors.Count -gt 0){foreach($message in $errors){Write-Host "FAIL: $message" -ForegroundColor Red};Write-Host "Opportunity filter/sort/settings validation failed with $($errors.Count) error(s)." -ForegroundColor Red;exit 1}
Write-Host 'Opportunity filters, visible-band country popup scope, persistent startup country defaults, finalized republish, popup fallback, instant trip-band/sort controls, and explicit card detail validation passed.' -ForegroundColor Green
exit 0
