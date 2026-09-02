$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message){$script:errors.Add($Message)}

$files=@{
 Preferences=Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
 LegacyPopup=Join-Path $ProjectRoot '@Resources\Scripts\OpenFilterPopup.ps1'
 UnifiedPopup=Join-Path $ProjectRoot '@Resources\Scripts\OpenUnifiedFilterPopup.ps1'
 Launcher=Join-Path $ProjectRoot '@Resources\Scripts\LaunchFilterPopup.ps1'
 PopupHost=Join-Path $ProjectRoot '@Resources\Scripts\PopupHost.ps1'
 HeaderLayout=Join-Path $ProjectRoot '@Resources\Scripts\HeaderLayout.lua'
 FilterIcon=Join-Path $ProjectRoot '@Resources\Images\UI\filter.png'
 SettingsIcon=Join-Path $ProjectRoot '@Resources\Images\UI\settings.png'
 State=Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1'
 Opportunities=Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
 Settings=Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
 StateReader=Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
 Ini=Join-Path $ProjectRoot 'TravelAssistant.ini'
 Countries=Join-Path $ProjectRoot 'config\countries.json'
}
foreach($entry in $files.GetEnumerator()){if(-not(Test-Path -LiteralPath $entry.Value)){Fail "Missing $($entry.Key): $($entry.Value)"}}

foreach($path in @($files.Preferences,$files.LegacyPopup,$files.UnifiedPopup,$files.Launcher,$files.PopupHost,$files.State,$files.Opportunities,$files.Settings)){
 if(-not(Test-Path -LiteralPath $path)){continue}
 $tokens=$null;$parseErrors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
 foreach($parseError in @($parseErrors)){Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)"}
}

if(Test-Path -LiteralPath $files.Preferences){
 $text=Get-Content -LiteralPath $files.Preferences -Raw
 foreach($token in @(
  'schemaVersion = 8','selectedItemIds','selectedTripBands','displayTripBands','selectedCountryIds','selectedCategories',
  'showProfitableOnly','ignoredItemIds','itemMarketFeePercent','Normalize-ItemMarketFeePercent','energyWastePolicy','nerveWastePolicy',
  "sortMode = 'upcoming'",'Normalize-SortMode',"@('upcoming','gross','profit_per_hour')",'SetSortMode',
  'Set-FilterStateKvValuesAtomic','UISelectedTripBands','UITripShortOn','UITripMediumOn','UITripLongOn',
  '$countries.Count -eq 0','Write-FilterJsonAtomic -Path $PreferenceFile -Value $normalized','Start-FilterProjectionRefresh','LaunchUpdate.ps1','RefreshFilters','Start-FilterProjectionRefresh -Action RefreshFilters'
 )){if(-not$text.Contains($token)){Fail "FilterPreferences.ps1 missing '$token'."}}
 if($text -notmatch '(?s)if \(\$Action -eq ''ToggleTripBand''\).*?Save-UiPreferences.*?Set-FilterStateKvValuesAtomic') { Fail 'Legacy trip-band persistence must remain a tiny preference/state write for compatibility.' }

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

if(Test-Path -LiteralPath $files.UnifiedPopup){
 $text=Get-Content -LiteralPath $files.UnifiedPopup -Raw
 if(-not$text.Contains('$ColorAccent=[System.Drawing.Color]::FromArgb(126,190,73)')){Fail 'Unified filter popup accent must use Torn lime.'}
 foreach($token in @(
  'COUNTRIES','CATEGORIES','ITEMS',"@('short','medium','long')","short='S';medium='M';long='L'",
  'Get-CountryFlagImage','@Resources\Images\Flags','CheckedListBox','TextChanged','Set-BandSelection','Set-AllCountries','Set-AllCategories',
  'Get-ScopedCatalogRows','Test-ItemInCurrentScope','countryIds',"New-ActionLink 'ON'","New-ActionLink 'OFF'",
  "Set-FilterProperty `$current 'displayTripBands'","Set-FilterProperty `$current 'selectedCountryIds'","Set-FilterProperty `$current 'selectedCategories'","Set-FilterProperty `$current 'selectedItemIds'",
  'Start-FilterProjectionRefresh -Action RefreshFilters','RuntimeLog.ps1','Read-OptionalPopupJson','$engine=Read-OptionalPopupJson $EngineStateFile','$script:resetProfitable=$true'
 )){if(-not$text.Contains($token)){Fail "Unified filter popup missing '$token'."}}
 if($text.Contains("`$title.Text='TRIP & FILTERS'")){Fail 'Unified filter popup must not render the retired title.'}
 if($text -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest'){Fail 'Unified filter popup must remain local-only.'}
 if($text.Contains('RunUpdate.ps1')){Fail 'Unified filter popup must republish through Start-FilterProjectionRefresh, not invoke RunUpdate.ps1 directly.'}
 foreach($badConstructor in @('Point(0,$y+2)','Size(0,$y+8)')){if($text.Contains($badConstructor)){Fail "Unified filter popup contains an ungrouped arithmetic constructor that PowerShell treats as three arguments: '$badConstructor'."}}
 foreach($constructor in @('[System.Drawing.Point]::new(0,($y+2))','[System.Drawing.Size]::new(0,($y+8))')){if(-not$text.Contains($constructor)){Fail "Unified filter popup missing the PowerShell-safe dynamic constructor '$constructor'."}}
 foreach($token in @(
  'New-CountryFlagChip',"New-Chip -Text '' -Width 53",'System.Drawing.Size(53,36)','System.Drawing.Bitmap($source,49,32)',
  '$chip.BackgroundImage=$Image','$chip.BackgroundImageLayout=[System.Windows.Forms.ImageLayout]::Center','$script:countryToolTip.SetToolTip($chip,$Name)',
  "New-SectionHeader 'COUNTRIES'","New-ActionLink 'ON' 306","New-ActionLink 'OFF' 348",
  '$categoryColumnCount=4','-Width 93',"'Miscellaneous'){'Misc'}","System.Drawing.Font('Segoe UI Semibold',9.5)",
  '$itemHeader.Size=New-Object System.Drawing.Size(48,22)','$search.BringToFront()'
 )){if(-not$text.Contains($token)){Fail "Unified filter popup missing requested compact layout contract '$token'."}}
}

if(Test-Path -LiteralPath $files.LegacyPopup){
 $text=Get-Content -LiteralPath $files.LegacyPopup -Raw
 foreach($token in @("'Ignore'",'Read-OptionalPopupJson','Start-FilterProjectionRefresh')){if(-not$text.Contains($token)){Fail "Legacy/Ignore popup missing '$token'."}}
 if($text -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest'){Fail 'Legacy/Ignore popup must remain local-only.'}
}

if(Test-Path -LiteralPath $files.Launcher){
 $text=Get-Content -LiteralPath $files.Launcher -Raw
 foreach($token in @("'Filters'",'PopupHost.ps1','-Popup Filter','-WindowStyle Hidden','-STA','System.Diagnostics.ProcessStartInfo','return')){if(-not$text.Contains($token)){Fail "Filter launcher missing '$token'."}}
 if($text.Contains('exit 0')){Fail 'Filter launcher must return after spawning so nested settings popups remain alive.'}
}

if(Test-Path -LiteralPath $files.PopupHost){
 $text=Get-Content -LiteralPath $files.PopupHost -Raw
 foreach($token in @("'Filters'",'OpenUnifiedFilterPopup.ps1',"if (`$Filter -eq 'Ignore')",'OpenFilterPopup.ps1')){if(-not$text.Contains($token)){Fail "PopupHost unified routing missing '$token'."}}
 foreach($retired in @("'ItemViewer'",'OpenItemViewer.ps1','MarketKey','[ValidateRange(0,8)]')){if($text.Contains($retired)){Fail "PopupHost retains retired Viewer token '$retired'."}}
}

if(Test-Path -LiteralPath $files.Settings){
 $text=Get-Content -LiteralPath $files.Settings -Raw
 foreach($token in @('LaunchFilterPopup.ps1','LaunchSettings.ps1','Start-FilterProjectionRefresh -Action RefreshFilters',"& `$FilterLauncher -Filter 'Ignore'")){if(-not$text.Contains($token)){Fail "OpenOptimizerSettings.ps1 missing '$token'."}}
 foreach($token in @('Tax / trader rate','itemMarketFeePercent','foreach($rate in 0..5)','marketTax.SelectedIndex')){if(-not$text.Contains($token)){Fail "OpenOptimizerSettings.ps1 missing '$token'."}}
 if(-not$text.Contains('$save.BackColor=[System.Drawing.Color]::FromArgb(126,190,73)')){Fail 'OpenOptimizerSettings.ps1 Save accent must use Torn lime.'}
 foreach($retired in @('Use 95% MV profit calculation','use95PercentMarketValue')){if($text.Contains($retired)){Fail "OpenOptimizerSettings.ps1 retains retired MV-basis token '$retired'."}}
 foreach($retiredText in @('OPPORTUNITY SETTINGS','Main sort choices are UPCOMING')){if($text.Contains($retiredText)){Fail "OpenOptimizerSettings.ps1 retains unnecessary settings copy '$retiredText'."}}
 if($text.Contains("Join-Path `$PSScriptRoot 'RunUpdate.ps1'")){Fail 'Optimizer Settings must not bypass LaunchUpdate.ps1.'}
}

if(Test-Path -LiteralPath $files.HeaderLayout){
 $text=Get-Content -LiteralPath $files.HeaderLayout -Raw
 foreach($token in @('compactOffset = 32',"meterY('MeterOpportunity1Card')",'firstY<120','PanelHeight',"'Y'")){if(-not$text.Contains($token)){Fail "HeaderLayout.lua missing '$token'."}}
 foreach($forbidden in @("'X'","'W'","'H'","'Text'","'FontColor'","'Shape'","ImageName")){if($text.Contains("!SetOption',name,$forbidden")){Fail "HeaderLayout.lua must not mutate protected card option $forbidden."}}
 if($text -match '(?i)https?://|RunCommand|CommandMeasure|MeasureUpdate'){Fail 'HeaderLayout.lua must remain geometry-only and local.'}
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
  'Get-OpportunityNextWindow','Get-OpportunityProbabilityAtAge','Get-OpportunityNextRecurringWindow','Get-OpportunityEconomics','Get-OpportunityRoundTripProfitPerHour','grossProfit','profitPerHour','elapsedSeconds','probabilityKnown',
  'itemMarketFeePercent','MarketFeePercent','GrossSaleValue','MarketTaxValue','MakeValue','PurchaseCostValue','TotalCostValue','makePerHour',
  "'LEARNING'",'$availableQuantity = $stock','hasKnownSortData','effectiveSortMode',"sortMode -eq 'gross'","sortMode -eq 'profit_per_hour'",
  '$maxProjectedRows = 256',"'TripBand'",'tripBand=$tripBand','OpportunityCount'
 )){if(-not$text.Contains($token)){Fail "OpportunityState.ps1 missing '$token'."}}
 foreach($retired in @('expectedGross=','optimalScore=')){if($text.Contains($retired)){Fail "OpportunityState.ps1 retains retired hidden-ranking token '$retired'."}}
 if([regex]::Matches($text,'if \(\$OpportunityStateSkipMain\) \{ return \}').Count -ne 1){Fail 'OpportunityState.ps1 must contain exactly one executable main boundary.'}
 if($text -match '(?m)^\) \{

if(Test-Path -LiteralPath $files.StateReader){
 $text=Get-Content -LiteralPath $files.StateReader -Raw
 foreach($token in @(
  'function OpenFilter(filterName)','function ToggleTripBand(band)','function ResetFilters()','function SetSortMode(mode)',
  'currentOpportunityRows','sortOpportunityRows','locallyFilteredSortedProjection','pendingTripBands','activeTripBands','projectedTripBands',
  'maxCandidateRows = 256','TripBand','collapseInlineGraph','MeasureInlineGraph','effectiveSortMode','OpportunitySortEffectiveMode','safeLeaveText','UIOldestMarketSourceTimestamp',
  'resolvedItemName',"name:match('^Item%s+%d+$')","combinedPrice = 'BUY ' .. price .. '/ea'","combinedPrice = combinedPrice .. ' | '","return name .. ' - ' .. country"
 )){if(-not$text.Contains($token)){Fail "StateReader.lua missing '$token'."}}
 foreach($retired in @('OpenViewer','ViewerMarketKey','MeasureItemViewer')){if($text.Contains($retired)){Fail "StateReader retains retired Viewer token '$retired'."}}
}

if(Test-Path -LiteralPath $files.Ini){
 $ini=Get-Content -LiteralPath $files.Ini -Raw
 foreach($section in @('MeasureFilterPopup','MeasurePreferenceAction','MeasureHeaderLayout','MeterFilterIcon','MeterSettingsIcon','MeterSortUpcomingButton','MeterSortGrossButton','MeterSortProfitHourButton','MeterSortUpcoming','MeterSortGross','MeterSortProfitHour')){if($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')){Fail "TravelAssistant.ini missing [$section]."}}
 foreach($retired in @('MeterItemFilter','MeterTripLabel','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine','MeterSettings','MeterSortNameButton','MeterSortName','MeterViewer','MeasureItemViewer','MeterSortOptimal','MeterSortTime','MeterSortLabel')){if($ini -match ('(?m)^\['+[regex]::Escape($retired)+'\]\s*$')){Fail "Retired main-UI meter [$retired] returned."}}
 foreach($token in @('FilterRequest=Filters',"OpenFilter('Filters')",'ScriptFile=#@#Scripts\HeaderLayout.lua','PanelHeight=160','Y=67','StringAlign=CenterCenter','ImageName=#@#Images\UI\filter.png','ImageName=#@#Images\UI\settings.png')){if(-not$ini.Contains($token)){Fail "TravelAssistant.ini compact-header token missing '$token'."}}
 foreach($section in @('MeterFilterIcon','MeterSettingsIcon')) {
  $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($section)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
  if($body -notmatch '(?im)^Meter=Image\s*$' -or $body -notmatch '(?im)^W=24\s*$' -or $body -notmatch '(?im)^H=24\s*$'){Fail "$section must remain a compact 24x24 image meter."}
 }
 foreach($section in @('MeterSortUpcomingButton','MeterSortGrossButton','MeterSortProfitHourButton')) {
  $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($section)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
  foreach($token in @('W=92','H=23','Shape=Rectangle 0,0,92,23,4 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#')){if(-not$body.Contains($token)){Fail "$section must remain a standard 92x23 rounded sort button surface."}}
 }
 foreach($retiredSeparator in @('MeterHeaderBottomLine','MeterSortBottomLine')){if($ini -match ('(?m)^\['+[regex]::Escape($retiredSeparator)+'\]\s*$')){Fail "Retired separator [$retiredSeparator] returned."}}
 if($ini.Contains('Text=SETTINGS  >')){Fail 'Main header must use the settings gear image, not SETTINGS > text.'}
}

if(Test-Path -LiteralPath $files.Countries){
 $countriesJson=Get-Content -LiteralPath $files.Countries -Raw|ConvertFrom-Json
 $collect=@($countriesJson.countries|Where-Object{$_.collect -eq $true})
 if($collect.Count -ne 11){Fail "Expected 11 collect=true destinations; found $($collect.Count)."}
 $short=@($collect|Where-Object{$_.tripBand -eq 'short'});$medium=@($collect|Where-Object{$_.tripBand -eq 'medium'});$long=@($collect|Where-Object{$_.tripBand -eq 'long'})
 if($short.Count -ne 3 -or $medium.Count -ne 4 -or $long.Count -ne 4){Fail "Trip subdivisions must remain 3 short / 4 medium / 4 long; found $($short.Count)/$($medium.Count)/$($long.Count)."}
}

if($errors.Count -gt 0){foreach($message in $errors){Write-Host "FAIL: $message" -ForegroundColor Red};Write-Host "Unified opportunity filter/header validation failed with $($errors.Count) error(s)." -ForegroundColor Red;exit 1}
Write-Host 'Unified trip/country/category/item filter panel and compact image-icon header validation passed.' -ForegroundColor Green
Write-Host 'Legacy main filter meters are retired, Ignore List remains separate, and HeaderLayout can only shift the existing card stack upward.' -ForegroundColor Green
exit 0
){Fail 'OpportunityState.ps1 retains the malformed duplicated legacy-cleanup tail.'}
}

if(Test-Path -LiteralPath $files.StateReader){
 $text=Get-Content -LiteralPath $files.StateReader -Raw
 foreach($token in @(
  'function OpenFilter(filterName)','function ToggleTripBand(band)','function ResetFilters()','function SetSortMode(mode)',
  'currentOpportunityRows','sortOpportunityRows','locallyFilteredSortedProjection','pendingTripBands','activeTripBands','projectedTripBands',
  'maxCandidateRows = 256','TripBand','collapseInlineGraph','MeasureInlineGraph','effectiveSortMode','OpportunitySortEffectiveMode','safeLeaveText','UIOldestMarketSourceTimestamp',
  'resolvedItemName',"name:match('^Item%s+%d+$')","combinedPrice = 'BUY ' .. price .. '/ea'","combinedPrice = combinedPrice .. ' | '","return name .. ' - ' .. country"
 )){if(-not$text.Contains($token)){Fail "StateReader.lua missing '$token'."}}
 foreach($retired in @('OpenViewer','ViewerMarketKey','MeasureItemViewer')){if($text.Contains($retired)){Fail "StateReader retains retired Viewer token '$retired'."}}
}

if(Test-Path -LiteralPath $files.Ini){
 $ini=Get-Content -LiteralPath $files.Ini -Raw
 foreach($section in @('MeasureFilterPopup','MeasurePreferenceAction','MeasureHeaderLayout','MeterFilterIcon','MeterSettingsIcon','MeterSortUpcomingButton','MeterSortGrossButton','MeterSortProfitHourButton','MeterSortUpcoming','MeterSortGross','MeterSortProfitHour')){if($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')){Fail "TravelAssistant.ini missing [$section]."}}
 foreach($retired in @('MeterItemFilter','MeterTripLabel','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine','MeterSettings','MeterSortNameButton','MeterSortName','MeterViewer','MeasureItemViewer','MeterSortOptimal','MeterSortTime','MeterSortLabel')){if($ini -match ('(?m)^\['+[regex]::Escape($retired)+'\]\s*$')){Fail "Retired main-UI meter [$retired] returned."}}
 foreach($token in @('FilterRequest=Filters',"OpenFilter('Filters')",'ScriptFile=#@#Scripts\HeaderLayout.lua','PanelHeight=160','Y=67','StringAlign=CenterCenter','ImageName=#@#Images\UI\filter.png','ImageName=#@#Images\UI\settings.png')){if(-not$ini.Contains($token)){Fail "TravelAssistant.ini compact-header token missing '$token'."}}
 foreach($section in @('MeterFilterIcon','MeterSettingsIcon')) {
  $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($section)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
  if($body -notmatch '(?im)^Meter=Image\s*$' -or $body -notmatch '(?im)^W=24\s*$' -or $body -notmatch '(?im)^H=24\s*$'){Fail "$section must remain a compact 24x24 image meter."}
 }
 foreach($section in @('MeterSortUpcomingButton','MeterSortGrossButton','MeterSortProfitHourButton')) {
  $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($section)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
  foreach($token in @('W=92','H=23','Shape=Rectangle 0,0,92,23,4 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#')){if(-not$body.Contains($token)){Fail "$section must remain a standard 92x23 rounded sort button surface."}}
 }
 foreach($retiredSeparator in @('MeterHeaderBottomLine','MeterSortBottomLine')){if($ini -match ('(?m)^\['+[regex]::Escape($retiredSeparator)+'\]\s*$')){Fail "Retired separator [$retiredSeparator] returned."}}
 if($ini.Contains('Text=SETTINGS  >')){Fail 'Main header must use the settings gear image, not SETTINGS > text.'}
}

if(Test-Path -LiteralPath $files.Countries){
 $countriesJson=Get-Content -LiteralPath $files.Countries -Raw|ConvertFrom-Json
 $collect=@($countriesJson.countries|Where-Object{$_.collect -eq $true})
 if($collect.Count -ne 11){Fail "Expected 11 collect=true destinations; found $($collect.Count)."}
 $short=@($collect|Where-Object{$_.tripBand -eq 'short'});$medium=@($collect|Where-Object{$_.tripBand -eq 'medium'});$long=@($collect|Where-Object{$_.tripBand -eq 'long'})
 if($short.Count -ne 3 -or $medium.Count -ne 4 -or $long.Count -ne 4){Fail "Trip subdivisions must remain 3 short / 4 medium / 4 long; found $($short.Count)/$($medium.Count)/$($long.Count)."}
}

if($errors.Count -gt 0){foreach($message in $errors){Write-Host "FAIL: $message" -ForegroundColor Red};Write-Host "Unified opportunity filter/header validation failed with $($errors.Count) error(s)." -ForegroundColor Red;exit 1}
Write-Host 'Unified trip/country/category/item filter panel and compact image-icon header validation passed.' -ForegroundColor Green
Write-Host 'Legacy main filter meters are retired, Ignore List remains separate, and HeaderLayout can only shift the existing card stack upward.' -ForegroundColor Green
exit 0
