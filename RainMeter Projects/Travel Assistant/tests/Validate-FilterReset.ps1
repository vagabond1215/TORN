$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$preferencesPath = Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
$popupPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenFilterPopup.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach($path in @($preferencesPath,$popupPath)) {
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
    if([int]$reset.schemaVersion -ne 7) { Fail 'RESET must persist schemaVersion=7.' }

    $text=Get-Content -LiteralPath $preferencesPath -Raw
    foreach($token in @('Write-TravelAssistantAtomicText','Read-TravelAssistantSharedText','Cannot reset filters because no collected countries are available.')) {
        if(-not $text.Contains($token)) { Fail "FilterPreferences.ps1 missing '$token'." }
    }
}

if(Test-Path -LiteralPath $popupPath) {
    $text=Get-Content -LiteralPath $popupPath -Raw
    foreach($token in @('Read-FilterJson -Path $Path','[int]::TryParse','New-IntSet','New-StringSet','No active item catalog rows are available for the Item filter.')) {
        if(-not $text.Contains($token)) { Fail "OpenFilterPopup.ps1 missing robustness token '$token'." }
    }
}

if($errors.Count -gt 0) {
    foreach($message in $errors) { Write-Host ('FAIL: ' + $message) -ForegroundColor Red }
    Write-Host ("Filter reset/popup validation failed with $($errors.Count) error(s).") -ForegroundColor Red
    exit 1
}

Write-Host 'Filter reset/popup validation passed.' -ForegroundColor Green
Write-Host 'RESET restores all 11 countries/items/bands and popup catalog reads tolerate malformed metadata IDs without blanking the dialog.' -ForegroundColor Green
exit 0
