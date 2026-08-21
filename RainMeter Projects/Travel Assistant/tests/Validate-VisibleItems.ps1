$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\VisibleItems.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$itemsPath = Join-Path $ProjectRoot 'config\items.json'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $scriptPath)) {
    Fail 'Missing VisibleItems.ps1.'
} else {
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "VisibleItems.ps1 parse error: $($parseError.Message)" }
    foreach ($fn in @('Get-VisibleSecondaryItem','Get-VisibleItemsResaleSnapshot','Get-VisibleSecondaryPresentation','Set-VisibleSecondaryState')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($fn) + '\s*\{')) { Fail "Missing $fn." }
    }
    foreach ($networkToken in @('Invoke-RestMethod','Invoke-WebRequest','curl.exe','https://','http://')) {
        if ($text.Contains($networkToken)) { Fail "VisibleItems.ps1 must remain local-only; found '$networkToken'." }
    }
    foreach ($token in @('SecondaryMarketValue','SecondaryPriceClass','Get-TravelProfileEffects','Get-EffectiveTravelEconomics','catalogActive','legacy_removed')) {
        if (-not $text.Contains($token)) { Fail "Visible presentation contract missing '$token'." }
    }
}

$items = Get-Content -LiteralPath $itemsPath -Raw | ConvertFrom-Json
$nessie = @($items.items | Where-Object { [int]$_.itemId -eq 266 } | Select-Object -First 1)
$cherry = @($items.items | Where-Object { [int]$_.itemId -eq 277 } | Select-Object -First 1)
if ($nessie.Count -ne 1 -or $nessie[0].visible -ne $true -or $nessie[0].enabled -ne $false) { Fail 'Nessie must be visible but remain outside the primary enabled model path.' }
if ($cherry.Count -ne 1 -or $cherry[0].visible -ne $true -or $cherry[0].enabled -ne $false) { Fail 'Cherry Blossom must be visible but remain outside the primary enabled model path.' }

$wrapper = Get-Content -LiteralPath $wrapperPath -Raw
$finalizerCall = $wrapper.IndexOf('& $Finalizer')
$visibleCall = $wrapper.IndexOf('& $VisibleItems')
$heartbeatCall = $wrapper.LastIndexOf('Write-UpdateHeartbeat')
$resaleCall = $wrapper.IndexOf('& $ResaleQueue')
if ($finalizerCall -lt 0 -or $visibleCall -lt 0 -or $heartbeatCall -lt 0 -or $resaleCall -lt 0 -or -not ($finalizerCall -lt $visibleCall -and $visibleCall -lt $heartbeatCall -and $heartbeatCall -lt $resaleCall)) {
    Fail 'Runtime order must remain FinalizeState -> VisibleItems -> heartbeat -> ResaleQueue.'
}

$ini = Get-Content -LiteralPath $iniPath -Raw
foreach ($section in @('MeterUKSecondaryTitle','MeterUKSecondaryPrice','MeterUKSecondaryStockHeader','MeterJPSecondaryTitle','MeterJPSecondaryPrice','MeterJPSecondaryStockHeader')) {
    if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($section) + '\]\s*$')) { Fail "Missing [$section]." }
}
foreach ($token in @('#UKMarketValueText#','#JPMarketValueText#','#UKSecondaryMarketValueText#','#JPSecondaryMarketValueText#')) {
    if (-not $ini.Contains($token)) { Fail "Skin is missing market-value variable $token." }
}
if ($ini -notmatch '(?m)^Version=0\.3\.0\s*$') { Fail 'Multi-item release should report skin version 0.3.0.' }

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Visible-item validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Visible-item configuration validation passed.' -ForegroundColor Green
Write-Host 'Nessie and Cherry are presentation-only secondary rows; market values come from local resaleCache and VisibleItems performs no network work.'
exit 0
