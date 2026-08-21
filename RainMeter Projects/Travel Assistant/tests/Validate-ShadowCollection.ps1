$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

$itemsPath = Join-Path $ProjectRoot 'config\items.json'
$countriesPath = Join-Path $ProjectRoot 'config\countries.json'
$overridePath = Join-Path $ProjectRoot 'config\foreign-market-overrides.json'
$collectorPath = Join-Path $ProjectRoot '@Resources\Scripts\ShadowCollector.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'

$items = Get-Content -LiteralPath $itemsPath -Raw | ConvertFrom-Json
$countries = Get-Content -LiteralPath $countriesPath -Raw | ConvertFrom-Json
$overrides = if (Test-Path -LiteralPath $overridePath) { Get-Content -LiteralPath $overridePath -Raw | ConvertFrom-Json } else { $null }

$expectedCodes = [ordered]@{
    mexico = 'mex'
    cayman_islands = 'cay'
    canada = 'can'
    hawaii = 'haw'
    united_kingdom = 'uni'
    argentina = 'arg'
    switzerland = 'swi'
    japan = 'jap'
    china = 'chi'
    united_arab_emirates = 'uae'
    south_africa = 'sou'
}

$collectionRows = @($countries.countries | Where-Object { $_.PSObject.Properties['collect'] -and $_.collect -eq $true })
if ($collectionRows.Count -ne $expectedCodes.Count) {
    Fail "Expected $($expectedCodes.Count) shadow-collection countries, found $($collectionRows.Count)."
}

foreach ($countryId in $expectedCodes.Keys) {
    $row = @($countries.countries | Where-Object { [string]$_.id -eq $countryId } | Select-Object -First 1)
    if ($row.Count -ne 1) {
        Fail "Missing collection country '$countryId'."
        continue
    }
    if (-not $row[0].PSObject.Properties['collect'] -or $row[0].collect -ne $true) {
        Fail "$countryId must be enabled for shadow collection."
    }
    $expectedCode = [string]$expectedCodes[$countryId]
    foreach ($provider in @('prometheus','yata')) {
        $codeProp = $row[0].providerCodes.PSObject.Properties[$provider]
        if ($null -eq $codeProp -or [string]$codeProp.Value -ne $expectedCode) {
            Fail "$countryId $provider code must be '$expectedCode'."
        }
    }
}

foreach ($visibleCountry in @('united_kingdom','japan')) {
    $row = @($countries.countries | Where-Object { [string]$_.id -eq $visibleCountry } | Select-Object -First 1)
    if ($row.Count -ne 1 -or $row[0].enabled -ne $true) { Fail "$visibleCountry must remain enabled for the current UI." }
}
foreach ($shadowOnlyCountry in @('mexico','cayman_islands','canada','hawaii','argentina','switzerland','china','united_arab_emirates','south_africa')) {
    $row = @($countries.countries | Where-Object { [string]$_.id -eq $shadowOnlyCountry } | Select-Object -First 1)
    if ($row.Count -ne 1 -or $row[0].enabled -ne $false) { Fail "$shadowOnlyCountry must remain shadow-only for this release." }
}

$enabledItems = @($items.items | Where-Object { $_.enabled -eq $true })
if ($enabledItems.Count -ne 1 -or [int]$enabledItems[0].itemId -ne 206) {
    Fail 'Xanax item 206 must remain the only enabled primary item during shadow collection.'
}

$itemExpectations = @(
    [pscustomobject]@{ itemId = 206; name = 'Xanax'; category = 'Drug'; country = $null; visible = $true; optimizerEligible = $true },
    [pscustomobject]@{ itemId = 266; name = 'Nessie Plushie'; category = 'Plushie'; country = 'united_kingdom'; visible = $false; optimizerEligible = $false },
    [pscustomobject]@{ itemId = 277; name = 'Cherry Blossom'; category = 'Flower'; country = 'japan'; visible = $false; optimizerEligible = $false }
)
foreach ($expected in $itemExpectations) {
    $row = @($items.items | Where-Object { [int]$_.itemId -eq [int]$expected.itemId } | Select-Object -First 1)
    if ($row.Count -ne 1) {
        Fail "Missing item $($expected.itemId) $($expected.name)."
        continue
    }
    if ([string]$row[0].name -ne [string]$expected.name) { Fail "Item $($expected.itemId) name mismatch." }
    if ([string]$row[0].category -ne [string]$expected.category) { Fail "Item $($expected.itemId) category mismatch." }
    if (-not $row[0].PSObject.Properties['collect'] -or $row[0].collect -ne $true) { Fail "Item $($expected.itemId) must remain collectable." }
    if (-not $row[0].PSObject.Properties['visible'] -or $row[0].visible -ne $expected.visible) { Fail "Item $($expected.itemId) visible flag mismatch." }
    if (-not $row[0].PSObject.Properties['optimizerEligible'] -or $row[0].optimizerEligible -ne $expected.optimizerEligible) { Fail "Item $($expected.itemId) optimizer eligibility mismatch." }
    if ($null -ne $expected.country -and @($row[0].countries | Where-Object { [string]$_ -eq [string]$expected.country }).Count -ne 1) {
        Fail "Item $($expected.itemId) must include country '$($expected.country)'."
    }
}

if ($null -eq $overrides -or -not $overrides.PSObject.Properties['marketOverrides']) {
    Fail 'Verified foreign-market overrides must be present.'
} else {
    foreach ($key in @('mexico:21','mexico:232','mexico:327','united_arab_emirates:383','united_arab_emirates:440')) {
        $prop = $overrides.marketOverrides.PSObject.Properties[$key]
        if ($null -eq $prop) { Fail "Missing inactive legacy market '$key'."; continue }
        if ([bool]$prop.Value.active -ne $false) { Fail "Legacy market '$key' must be inactive." }
    }
}

if (-not (Test-Path -LiteralPath $collectorPath)) {
    Fail 'ShadowCollector.ps1 is missing.'
} else {
    $collector = Get-Content -LiteralPath $collectorPath -Raw
    if ($collector -notmatch '(?m)^\s*\[int\]\$MinimumPollIntervalSeconds\s*=\s*120') {
        Fail 'Shadow collector default interval must remain 120 seconds for the initial rollout.'
    }
    foreach ($token in @('observedMarkets','providerName','itemName','Test-IsPrimaryMarket','Get-LiveStockObservationsForCountry','Get-InactiveMarketIndex','foreign-market-overrides.json','legacyMarketsSeen')) {
        if (-not $collector.Contains($token)) { Fail "Shadow collector contract is missing '$token'." }
    }
    if ($collector -notmatch '(?s)Update-ObservedMarketMetadata.+?\$marketsSeen\+\+.+?\$inactiveMarketIndex\.ContainsKey\(\$key\).+?continue') {
        Fail 'Shadow collector must retain legacy provider rows in observedMarkets while suppressing them before history/cycle writes.'
    }
}

if (-not (Test-Path -LiteralPath $wrapperPath)) {
    Fail 'RunUpdate.ps1 is missing.'
} else {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    if (-not $wrapper.Contains('ShadowCollector.ps1')) { Fail 'RunUpdate.ps1 must invoke ShadowCollector.ps1.' }
    if (-not $wrapper.Contains('Write-ShadowFailure')) { Fail 'RunUpdate.ps1 must keep unexpected shadow failures fail-soft and diagnosable.' }
    if ($wrapper.IndexOf('& $Updater -Action $Action') -gt $wrapper.IndexOf('& $ShadowCollector')) {
        Fail 'Primary updater must run before shadow collection.'
    }
    if ($wrapper.IndexOf('& $ShadowCollector') -gt $wrapper.IndexOf('& $Finalizer')) {
        Fail 'Shadow collection should complete before finalization while sharing serialized engine state.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL $message" -ForegroundColor Red }
    exit 1
}

Write-Host 'Shadow collection configuration validation passed.' -ForegroundColor Green
Write-Host '11 countries remain observable; five verified legacy provider markets are excluded from new history while current visible scope stays UK/Japan Xanax.' -ForegroundColor DarkGreen
exit 0
