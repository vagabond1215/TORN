$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

function Fail([string]$Message) { $script:errors.Add($Message) }
function Note([string]$Message) { $script:notes.Add($Message) }

$required = @(
    'TravelAssistant.ini',
    'AGENTS.md',
    'Readme.md',
    'Install.ps1',
    'config\items.json',
    'config\countries.json',
    'config\travel-modes.json',
    'config\settings.example.json',
    'config\settings.local.example.json',
    'config\providers.json',
    'data\seed\metadata.json',
    'data\seed\observations.jsonl',
    'data\seed\cycles.jsonl',
    '@Resources\Scripts\RunUpdate.ps1',
    '@Resources\Scripts\UpdateTracker.ps1',
    '@Resources\Scripts\FinalizeState.ps1',
    '@Resources\Scripts\StateReader.lua',
    'tests\Run-ModelTests.ps1',
    'tests\Run-FinalizeStateTests.ps1',
    'tests\Run-RestockDisplayTests.ps1'
)

foreach ($relative in $required) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing required file: $relative" }
}

$configFiles = @(
    'config\items.json',
    'config\countries.json',
    'config\travel-modes.json',
    'config\settings.example.json',
    'config\settings.local.example.json',
    'config\providers.json',
    'data\seed\metadata.json'
)

$config = @{}
foreach ($relative in $configFiles) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }
    try {
        $obj = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $config[$relative] = $obj
        if (-not $obj.PSObject.Properties['schemaVersion'] -or [int]$obj.schemaVersion -ne 1) {
            Fail "$relative does not declare schemaVersion 1"
        }
    } catch {
        Fail "Invalid JSON in ${relative}: $($_.Exception.Message)"
    }
}

$items = $config['config\items.json']
if ($null -ne $items) {
    $xanax = @($items.items | Where-Object { [int]$_.itemId -eq 206 -and $_.enabled -eq $true })
    if ($xanax.Count -ne 1) { Fail 'Exactly one enabled Xanax itemId 206 entry is required for v1.' }
}

$settings = $config['config\settings.example.json']
if ($null -ne $settings) {
    if (-not $settings.PSObject.Properties['profitability'] -or $null -eq $settings.profitability) {
        Fail 'settings.example.json must contain profitability settings.'
    } else {
        foreach ($requiredProfitField in @('sellTarget','itemMarketFeePercent','minimumProfitPerItem','minimumMarginPercent','minimumTotalTripProfit','capacityOverride','resaleStaleAfterSeconds')) {
            if (-not $settings.profitability.PSObject.Properties[$requiredProfitField]) {
                Fail "settings.example.json profitability is missing '$requiredProfitField'."
            }
        }
        if ($settings.profitability.PSObject.Properties['capacityOverride'] -and [int]$settings.profitability.capacityOverride -lt 0) {
            Fail 'capacityOverride cannot be negative.'
        }
        if ($settings.profitability.PSObject.Properties['resaleStaleAfterSeconds'] -and [long]$settings.profitability.resaleStaleAfterSeconds -lt 60) {
            Fail 'resaleStaleAfterSeconds must be at least 60 seconds.'
        }
    }
}

$modes = $config['config\travel-modes.json']
$countries = $config['config\countries.json']
if ($null -ne $modes -and $null -ne $countries) {
    $allModeIds = @($modes.modes | ForEach-Object { [string]$_.id })
    $enabledModeIds = @($modes.modes | Where-Object { $_.enabled -eq $true } | ForEach-Object { [string]$_.id })

    foreach ($requiredMode in @('standard','airstrip','wlt','business')) {
        if ($allModeIds -notcontains $requiredMode) { Fail "Missing configured travel mode: $requiredMode" }
    }
    foreach ($requiredEnabledMode in @('standard','airstrip','wlt')) {
        if ($enabledModeIds -notcontains $requiredEnabledMode) { Fail "Missing enabled travel mode: $requiredEnabledMode" }
    }
    if ([string]$modes.defaultMode -ne 'airstrip') { Fail 'Default travel mode must be airstrip.' }

    $business = @($modes.modes | Where-Object { [string]$_.id -eq 'business' } | Select-Object -First 1)
    if ($business.Count -eq 1 -and $business[0].enabled -ne $true) {
        if (-not $business[0].PSObject.Properties['disabledReason'] -or [string]::IsNullOrWhiteSpace([string]$business[0].disabledReason)) {
            Fail 'Disabled Business mode must explain why it is gated.'
        } else {
            Note 'Business mode is configured but intentionally disabled until Business Class Ticket/free-Lingerie trip economics are included in profitability gating.'
        }
    }

    foreach ($countryId in @('united_kingdom','japan')) {
        $row = @($countries.countries | Where-Object { [string]$_.id -eq $countryId -and $_.enabled -eq $true })
        if ($row.Count -ne 1) { Fail "Missing enabled country: $countryId"; continue }

        foreach ($modeId in $allModeIds) {
            $timeProp = $row[0].travelSeconds.PSObject.Properties[$modeId]
            if ($null -eq $timeProp -or [long]$timeProp.Value -le 0) { Fail "$countryId has no positive travelSeconds for $modeId" }

            $capacityProp = $row[0].baseTravelCapacity.PSObject.Properties[$modeId]
            if ($null -eq $capacityProp -or [int]$capacityProp.Value -le 0) { Fail "$countryId has no positive baseTravelCapacity for $modeId" }
        }

        foreach ($freeMode in @('airstrip','wlt')) {
            $costProp = $row[0].travelCosts.PSObject.Properties[$freeMode]
            if ($null -eq $costProp -or [long]$costProp.Value -ne 0) { Fail "$countryId $freeMode travel cost must be explicitly zero." }
        }
        $standardCost = $row[0].travelCosts.PSObject.Properties['standard']
        if ($null -eq $standardCost -or [long]$standardCost.Value -le 0) { Fail "$countryId standard travel cost must be positive." }
    }
}

foreach ($relative in @('data\seed\observations.jsonl','data\seed\cycles.jsonl','tests\fixtures\cycles-safe.jsonl','tests\fixtures\cycles-fast.jsonl','tests\fixtures\normalized-observations.sample.jsonl')) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $path) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $null = $line | ConvertFrom-Json }
        catch { Fail "Invalid JSONL in $relative line ${lineNumber}: $($_.Exception.Message)" }
    }
}

$scriptFiles = @(
    '@Resources\Scripts\RunUpdate.ps1',
    '@Resources\Scripts\UpdateTracker.ps1',
    '@Resources\Scripts\FinalizeState.ps1',
    'tests\Validate-TravelAssistant.ps1',
    'tests\Validate-HistoricalTools.ps1',
    'tests\Run-HistoricalPipelineTests.ps1',
    'tests\Run-SeedImporterTests.ps1',
    'tests\Run-ModelTests.ps1',
    'tests\Run-FinalizeStateTests.ps1',
    'tests\Run-RestockDisplayTests.ps1',
    'tests\Run-All.ps1',
    'Install.ps1'
)
foreach ($relative in $scriptFiles) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in ${relative}: $($parseError.Message)" }
}

$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
if (Test-Path -LiteralPath $wrapperPath) {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    if (-not $wrapper.Contains('FinalizeState.ps1')) { Fail 'RunUpdate.ps1 does not invoke FinalizeState.ps1.' }
}

$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
if (Test-Path -LiteralPath $iniPath) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    foreach ($section in @('[Rainmeter]','[MeasureUpdate]','[MeasureCycleMode]','[MeasureState]','[MeterUKGraph]','[MeterJPGraph]')) {
        if (-not $ini.Contains($section)) { Fail "Rainmeter skin missing expected section $section" }
    }
    if (-not $ini.Contains('@#Scripts\RunUpdate.ps1') -and -not $ini.Contains('#@#Scripts\RunUpdate.ps1')) {
        Fail 'Rainmeter skin does not route updater calls through RunUpdate.ps1.'
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $git) {
    Push-Location $ProjectRoot
    try {
        $ignoredRuntime = & git check-ignore 'data/runtime/probe.tmp' 2>$null
        if ([string]::IsNullOrWhiteSpace(($ignoredRuntime | Out-String))) { Fail 'data/runtime is not ignored by Git.' }
        $ignoredGenerated = & git check-ignore '@Resources/Generated/probe.tmp' 2>$null
        if ([string]::IsNullOrWhiteSpace(($ignoredGenerated | Out-String))) { Fail '@Resources/Generated is not ignored by Git.' }
    } finally { Pop-Location }
} else {
    Note 'Git executable not available; ignore-rule checks skipped.'
}

foreach ($note in $notes) { Write-Host "NOTE: $note" -ForegroundColor Yellow }
if ($errors.Count -gt 0) {
    foreach ($err in $errors) { Write-Host "FAIL: $err" -ForegroundColor Red }
    Write-Host "Validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Travel Assistant static validation passed.' -ForegroundColor Green
exit 0
