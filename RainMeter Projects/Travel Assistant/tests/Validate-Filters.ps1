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
 foreach($token in @('schemaVersion = 5','selectedItemIds','selectedTripBands','selectedCountryIds','selectedCategories','showProfitableOnly','ignoredItemIds','use95PercentMarketValue','energyWastePolicy','nerveWastePolicy',"sortMode = 'upcoming'",'Normalize-SortMode',"@('name','upcoming','gross','profit_per_hour')",'SetSortMode')){if(-not$text.Contains($token)){Fail "FilterPreferences.ps1 missing '$token'."}}
}

if(Test-Path -LiteralPath $files.Popup){
 $text=Get-Content -LiteralPath $files.Popup -Raw
 foreach($token in @("'Item'","'Country'","'Category'","'Ignore'",'observedMarkets','OpportunityState.ps1','RuntimeLog.ps1')){if(-not$text.Contains($token)){Fail "Filter popup missing '$token'."}}
 if($text -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest'){Fail 'Filter popup must remain local-only.'}
}

if(Test-Path -LiteralPath $files.Launcher){
 $text=Get-Content -LiteralPath $files.Launcher -Raw
 foreach($token in @('PopupHost.ps1','-Popup Filter','-WindowStyle Hidden','-STA')){if(-not$text.Contains($token)){Fail "Filter launcher missing '$token'."}}
}

if(Test-Path -LiteralPath $files.State){
 $text=Get-Content -LiteralPath $files.State -Raw
 foreach($token in @('UIItemFilterAll','UISelectedTripBands','UISelectedCountryIds','UICategoryFilterAll','UIShowProfitableOnly','UIOldestMarketSourceTimestamp','observedMarkets','sourceTimestamp')){if(-not$text.Contains($token)){Fail "FilterState.ps1 missing '$token'."}}
}

if(Test-Path -LiteralPath $files.Opportunities){
 $text=Get-Content -LiteralPath $files.Opportunities -Raw
 foreach($token in @('Get-OpportunityNextWindow','Get-OpportunityProbabilityAtAge','grossProfit','profitPerHour','elapsedSeconds','probabilityKnown',"'LEARNING'",'$availableQuantity = $stock',"sortMode -eq 'name'","sortMode -eq 'gross'","sortMode -eq 'profit_per_hour'")){if(-not$text.Contains($token)){Fail "OpportunityState.ps1 missing '$token'."}}
 foreach($retired in @('expectedGross=','optimalScore=')){if($text.Contains($retired)){Fail "OpportunityState.ps1 retains retired hidden-ranking token '$retired'."}}
}

if(Test-Path -LiteralPath $files.StateReader){
 $text=Get-Content -LiteralPath $files.StateReader -Raw
 foreach($token in @('function OpenFilter(filterName)','function ToggleTripBand(band)','function ResetFilters()','function SetSortMode(mode)','currentOpportunityRows','sortOpportunityRows','locallySortedProjection','collapseInlineGraph','MeasureInlineGraph','MeasureItemViewer','safeLeaveText')){if(-not$text.Contains($token)){Fail "StateReader.lua missing '$token'."}}
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
Write-Host 'Opportunity filters, NAME/UPCOMING/GROSS PROFIT/PROFIT-HR local sorts, sort-collapse behavior, and hidden popup contracts passed.' -ForegroundColor Green
exit 0
