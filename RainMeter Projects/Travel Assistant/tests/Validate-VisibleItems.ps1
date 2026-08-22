$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\VisibleItems.ps1'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$itemsPath = Join-Path $ProjectRoot 'config\items.json'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $scriptPath)) {
    Fail 'Missing VisibleItems.ps1.'
} else {
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "VisibleItems.ps1 parse error: $($parseError.Message)" }

    foreach ($fn in @('Get-VisibleSecondaryItem','Get-VisibleItemsResaleSnapshot','Get-VisibleItemGraphRows','Write-VisibleItemStockGraph','Get-VisibleSecondaryPresentation','Set-VisibleSecondaryState')) {
        if ($text -notmatch ('(?m)^function\s+'+[regex]::Escape($fn)+'\s*\{')) { Fail "Missing $fn." }
    }
    foreach ($networkToken in @('Invoke-RestMethod','Invoke-WebRequest','curl.exe','https://','http://')) {
        if ($text.Contains($networkToken)) { Fail "VisibleItems.ps1 must remain local-only; found '$networkToken'." }
    }
    foreach ($token in @('SecondaryMarketValue','SecondaryPriceClass','SecondaryGraphName','Get-TravelProfileEffects','Get-EffectiveTravelEconomics','catalogActive','legacy_removed','sourceTimestamp','observations.jsonl')) {
        if (-not $text.Contains($token)) { Fail "Visible presentation contract missing '$token'." }
    }
}

$items = Get-Content -LiteralPath $itemsPath -Raw | ConvertFrom-Json
$nessie = @($items.items | Where-Object { [int]$_.itemId -eq 266 } | Select-Object -First 1)
$cherry = @($items.items | Where-Object { [int]$_.itemId -eq 277 } | Select-Object -First 1)
if ($nessie.Count -ne 1 -or $nessie[0].visible -ne $true -or $nessie[0].enabled -ne $false) { Fail 'Nessie must be visible but remain outside the primary enabled model path.' }
if ($cherry.Count -ne 1 -or $cherry[0].visible -ne $true -or $cherry[0].enabled -ne $false) { Fail 'Cherry Blossom must be visible but remain outside the primary enabled model path.' }

$wrapper = Get-Content -LiteralPath $wrapperPath -Raw
$finalizer = $wrapper.IndexOf('& $Finalizer')
$travel = $wrapper.IndexOf('& $TravelContext')
$visible = $wrapper.IndexOf('& $VisibleItems')
$filterState = $wrapper.IndexOf('& $FilterState')
$heartbeat = $wrapper.LastIndexOf('Write-UpdateHeartbeat')
$priority = $wrapper.IndexOf('& $ResalePriority')
$resale = $wrapper.IndexOf('& $ResaleQueue')
if (@($finalizer,$travel,$visible,$filterState,$heartbeat,$priority,$resale) -contains -1 -or -not ($finalizer -lt $travel -and $travel -lt $visible -and $visible -lt $filterState -and $filterState -lt $heartbeat -and $heartbeat -lt $priority -and $priority -lt $resale)) {
    Fail 'Runtime order must remain FinalizeState -> TravelContext -> VisibleItems -> FilterState -> heartbeat -> ResalePriority -> ResaleQueue.'
}

$ini = Get-Content -LiteralPath $iniPath -Raw
foreach ($section in @('MeterUKCard','MeterUKSecondaryCard','MeterJPCard','MeterJPSecondaryCard','MeterUKSecondaryFlag','MeterJPSecondaryFlag','MeterUKSecondaryGraph','MeterJPSecondaryGraph','MeterUKSecondaryExpand','MeterJPSecondaryExpand')) {
    if ($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "Missing independent item-card meter [$section]." }
}
foreach ($token in @('#UKMarketValueText#','#JPMarketValueText#','#UKSecondaryMarketValueText#','#JPSecondaryMarketValueText#')) {
    if (-not $ini.Contains($token)) { Fail "Skin is missing market-value variable $token." }
}
if ($ini -notmatch '(?m)^Version=0\.4\.0\s*$') { Fail 'Current filtered independent-card release should report skin version 0.4.0.' }
if ($ini -notmatch '(?m)^MaxExpandedCards=2\s*$') { Fail 'Default expanded-card cap must remain two.' }
if ($ini -notmatch '(?m)^MaxExpandedCards=#MaxExpandedCards#\s*$') { Fail 'MeasureState must pass the expanded-card cap into StateReader.lua.' }
if ($ini -notmatch '(?m)^ImageName=#@#Generated\\#UKSecondaryGraphName#\s*$') { Fail 'UK secondary card must own its graph image.' }
if ($ini -notmatch '(?m)^ImageName=#@#Generated\\#JPSecondaryGraphName#\s*$') { Fail 'JP secondary card must own its graph image.' }

if (-not (Test-Path -LiteralPath $stateReaderPath)) {
    Fail 'Missing StateReader.lua.'
} else {
    $stateReader = Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        'local maxExpandedCards = 2',
        'local function countExpandedCards()',
        'local function collapseForRequestedCard(requested)',
        'local function applyCardLayout()',
        'function ToggleCard(cardKey)',
        'function TogglePin(cardKey)',
        "return '★'",
        "UKSecondary='united_kingdom:266'",
        "JPSecondary='japan:277'",
        'if pinKey==cardKey then return true end',
        "travelFilterCountryId~='' and cardCountry[cardKey]~=travelFilterCountryId"
    )) {
        if (-not $stateReader.Contains($token)) { Fail "StateReader.lua is missing independent-card contract: $token" }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Visible-item validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Visible-item configuration validation passed.' -ForegroundColor Green
Write-Host 'Nessie and Cherry remain independent cards; one card may be pinned/top/expanded while travel and local filters control relevance.'
exit 0
