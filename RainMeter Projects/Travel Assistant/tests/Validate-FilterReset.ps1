$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$preferencesPath = Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
$legacyPopupPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenFilterPopup.ps1'
$unifiedPopupPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenUnifiedFilterPopup.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach($path in @($preferencesPath,$legacyPopupPath,$unifiedPopupPath)) {
    if(-not(Test-Path -LiteralPath $path)) { Fail ('Missing filter file: ' + $path) }
    else {
        $tokens=$null; $parseErrors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
        foreach($parseError in @($parseErrors)) { Fail ((Split-Path $path -Leaf) + ' parse error: ' + $parseError.Message) }
    }
}

if(Test-Path -LiteralPath $preferencesPath) {
    . $preferencesPath -SkipMain
    $prefs = [pscustomobject]@{
        schemaVersion=7
        selectedCountryIds=[string[]]@()
        selectedItemIds=[int[]]@()
        selectedCategories=[string[]]@()
        displayTripBands=[string[]]@()
    }
    $reset = Reset-UiFilterPreferences -Preferences $prefs
    $countries = @($reset.selectedCountryIds)
    $availableCountries = @(Get-FilterAvailableCountryIds)
    if($availableCountries.Count -ne 11) { Fail "Expected 11 available countries; found $($availableCountries.Count)." }
    if($countries.Count -ne $availableCountries.Count) { Fail "RESET must select all available countries; selected $($countries.Count) of $($availableCountries.Count)." }
    foreach($id in $availableCountries) { if($countries -notcontains $id) { Fail "RESET omitted country '$id'." } }
    if(-not [bool]$reset.itemFilterAll) { Fail 'RESET must restore itemFilterAll=true.' }
    if(-not [bool]$reset.categoryFilterAll) { Fail 'RESET must restore categoryFilterAll=true.' }
    if(@($reset.displayTripBands).Count -ne 3) { Fail 'RESET must restore all three display trip bands.' }
    if([int]$reset.schemaVersion -ne 8) { Fail 'RESET must persist schemaVersion=8.' }

    $emptyNormalized = Normalize-UiPreferences -Preferences ([pscustomobject]@{schemaVersion=7;selectedCountryIds=[string[]]@()})
    if(@($emptyNormalized.selectedCountryIds).Count -ne $availableCountries.Count) { Fail 'Empty startup country selection must normalize to all collected countries.' }
    $subset = @($availableCountries | Select-Object -First 2)
    $subsetNormalized = Normalize-UiPreferences -Preferences ([pscustomobject]@{schemaVersion=7;selectedCountryIds=[string[]]$subset})
    if(@($subsetNormalized.selectedCountryIds).Count -ne $subset.Count) { Fail 'Nonempty saved country selection must remain persistent.' }

    $text=Get-Content -LiteralPath $preferencesPath -Raw
    foreach($token in @('Write-TravelAssistantAtomicText','Read-TravelAssistantSharedText','Cannot reset filters because no collected countries are available.','Read paths must be side-effect free.')) {
        if(-not $text.Contains($token)) { Fail "FilterPreferences.ps1 missing '$token'." }
    }
    $readBody=[regex]::Match($text,'(?ms)^function Read-UiPreferences\s*\{(.*?)(?=^function Save-UiPreferences)').Groups[1].Value
    if([string]::IsNullOrWhiteSpace($readBody)) { Fail 'Unable to locate Read-UiPreferences body.' }
    elseif($readBody -match 'Write-FilterJsonAtomic|Write-TravelAssistantAtomic') { Fail 'Read-UiPreferences must not write preferences during startup/popup reads.' }
}

if(Test-Path -LiteralPath $legacyPopupPath) {
    $text=Get-Content -LiteralPath $legacyPopupPath -Raw
    foreach($token in @('Read-FilterJson -Path $Path','[int]::TryParse','New-IntSet','New-StringSet','Read-OptionalPopupJson',"`$titleText='Ignore List'")) {
        if(-not $text.Contains($token)) { Fail "OpenFilterPopup.ps1 missing Ignore/legacy robustness token '$token'." }
    }
}

if(Test-Path -LiteralPath $unifiedPopupPath) {
    $text=Get-Content -LiteralPath $unifiedPopupPath -Raw
    foreach($token in @(
        'Read-OptionalPopupJson','No active item catalog rows are available for the unified filter panel.',
        'Set-AllCountries $true','Set-AllCategories $true','$script:resetProfitable=$true',
        "Set-FilterProperty `$current 'selectedTripBands' ([string[]]@('short','medium','long'))",
        "Set-FilterProperty `$current 'displayTripBands' ([string[]]@(`$selectedBands))",
        "Set-FilterProperty `$current 'selectedCountryIds'","Set-FilterProperty `$current 'categoryFilterAll'","Set-FilterProperty `$current 'itemFilterAll'",
        "Set-FilterProperty `$current 'showProfitableOnly' `$false",'Start-FilterProjectionRefresh'
    )) {
        if(-not $text.Contains($token)) { Fail "OpenUnifiedFilterPopup.ps1 missing reset/save contract '$token'." }
    }
}

if($errors.Count -gt 0) {
    foreach($message in $errors) { Write-Host ('FAIL: ' + $message) -ForegroundColor Red }
    Write-Host ("Filter reset/popup validation failed with $($errors.Count) error(s).") -ForegroundColor Red
    exit 1
}

Write-Host 'Filter reset/popup validation passed.' -ForegroundColor Green
Write-Host 'RESET restores all countries/items/bands and clears profitable-only; unified Save stages one coherent country-band/category/item preference write before one normal republish.' -ForegroundColor Green
exit 0
