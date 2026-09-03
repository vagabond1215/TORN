$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$presenterPath=Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$cardTweaksPath=Join-Path $ProjectRoot '@Resources\Scripts\CardTweaks.lua'
$travelTweaksPath=Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'
$iniPath=Join-Path $ProjectRoot 'TravelAssistant.ini'
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message){$script:errors.Add($Message)}

foreach($path in @($presenterPath,$cardTweaksPath,$travelTweaksPath,$iniPath)){
    if(-not(Test-Path -LiteralPath $path)){Fail "Missing Chance-meter contract file: $path"}
}

if($errors.Count -eq 0){
    $presenter=Get-Content -LiteralPath $presenterPath -Raw
    $cardTweaks=Get-Content -LiteralPath $cardTweaksPath -Raw
    $travelTweaks=Get-Content -LiteralPath $travelTweaksPath -Raw
    $ini=Get-Content -LiteralPath $iniPath -Raw

    foreach($token in @(
        "setOption(prefix..'Chance','X',276)",
        "setOption(prefix..'Chance','W',72)",
        "setOption(prefix..'Chance','StringAlign','CenterTop')",
        "setOption(prefix..'Chance','Text',chance)",
        "SKIN:Bang('!ShowMeter',prefix..'Chance')",
        "SKIN:Bang('!HideMeter',prefix..'Chance')",
        "setCenteredChance(prefix,certainty)",
        "return 'Chance to hit:',chancePercent(probability)"
    )){
        if(-not$presenter.Contains($token)){Fail "CardPresenter Chance-meter contract missing '$token'."}
    }

    if($cardTweaks.Contains("MeterOpportunity'..i..'Chance")){
        Fail 'CardTweaks must not hide the live Chance meter after CardPresenter renders it.'
    }
    if(-not$cardTweaks.Contains("MeterOpportunity'..i..'Window")){
        Fail 'CardTweaks should continue retiring only the legacy Window meter.'
    }
    if(-not$cardTweaks.Contains('Chance is now a live dedicated')){
        Fail 'CardTweaks should document that Chance is no longer a retired meter.'
    }

    foreach($token in @(
        "setOption(prefix..'Chance','Text',chance)",
        "SKIN:Bang('!ShowMeter',prefix..'Chance')",
        "SKIN:Bang('!HideMeter',prefix..'Chance')",
        'setTravelChance(prefix,arrivalChanceText(row))'
    )){
        if(-not$travelTweaks.Contains($token)){Fail "Travel-state Chance-meter contract missing '$token'."}
    }

    $presenterAt=$ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    $tweaksAt=$ini.IndexOf('[MeasureCardTweaks]',[System.StringComparison]::Ordinal)
    if($presenterAt -lt 0 -or $tweaksAt -le $presenterAt){
        Fail 'MeasureCardTweaks is expected after CardPresenter, so it must remain non-destructive to Chance visibility.'
    }
}

if($errors.Count -gt 0){
    foreach($failure in $errors){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Chance meter visibility validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Centered Chance meter visibility contract passed.' -ForegroundColor Green
exit 0
