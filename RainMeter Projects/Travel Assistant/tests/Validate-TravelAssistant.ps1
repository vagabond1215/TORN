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
    'config\providers.json',
    'data\seed\metadata.json',
    'data\seed\observations.jsonl',
    'data\seed\cycles.jsonl',
    '@Resources\Scripts\RunUpdate.ps1',
    '@Resources\Scripts\UpdateTracker.ps1',
    '@Resources\Scripts\StateReader.lua',
    'tests\Run-ModelTests.ps1'
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

$modes = $config['config\travel-modes.json']
$countries = $config['config\countries.json']
if ($null -ne $modes -and $null -ne $countries) {
    $modeIds = @($modes.modes | Where-Object { $_.enabled -eq $true } | ForEach-Object { [string]$_.id })
    foreach ($requiredMode in @('standard','airstrip','wlt','business')) {
        if ($modeIds -notcontains $requiredMode) { Fail "Missing enabled travel mode: $requiredMode" }
    }
    if ([string]$modes.defaultMode -ne 'airstrip') { Fail 'Default travel mode must be airstrip.' }

    foreach ($countryId in @('united_kingdom','japan')) {
        $row = @($countries.countries | Where-Object { [string]$_.id -eq $countryId -and $_.enabled -eq $true })
        if ($row.Count -ne 1) { Fail "Missing enabled country: $countryId"; continue }
        foreach ($modeId in $modeIds) {
            $prop = $row[0].travelSeconds.PSObject.Properties[$modeId]
            if ($null -eq $prop -or [long]$prop.Value -le 0) { Fail "$countryId has no positive travelSeconds for $modeId" }
        }
    }
}

foreach ($relative in @('data\seed\observations.jsonl','data\seed\cycles.jsonl','tests\fixtures\cycles-safe.jsonl','tests\fixtures\cycles-fast.jsonl')) {
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
    'tests\Validate-TravelAssistant.ps1',
    'tests\Run-ModelTests.ps1',
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
