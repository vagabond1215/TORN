$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

$luaNames = @(
    'CardPresenter.lua',
    'CardTweaks.lua',
    'WindowTooltipTweaks.lua',
    'TravelStateWindowTweaks.lua',
    'GraphHover.lua'
)

foreach ($name in $luaNames) {
    $path = Join-Path $ProjectRoot ('@Resources\Scripts\' + $name)
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing Rainmeter presentation script $name."; continue }
    $text = Get-Content -LiteralPath $path -Raw
    if ($text -match "setOption\([^\r\n]*'ToolTipHidden'") {
        Fail "$name must keep tooltip visibility on explicit meter show/hide rather than dynamic ToolTipHidden writes."
    }
}

$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
if (-not (Test-Path -LiteralPath $stateReaderPath)) {
    Fail 'Missing StateReader.lua.'
} else {
    $stateReader = Get-Content -LiteralPath $stateReaderPath -Raw
    $singleReturn = "return (value:gsub('[\r\n]', ' '))"
    $multiReturn = "return value:gsub('[\r\n]', ' ')"
    if (-not $stateReader.Contains($singleReturn)) {
        Fail 'StateReader safeText must parenthesize string.gsub so it returns exactly one Lua value.'
    }
    if ($stateReader.Contains($multiReturn)) {
        Fail 'StateReader safeText leaks string.gsub substitutionCount as a second Lua return value.'
    }
    foreach ($directSafeTextBang in @(
        "SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Gross', 'FontColor', safeText(",
        "SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Window', 'Text', safeText("
    )) {
        if (-not $stateReader.Contains($directSafeTextBang)) {
            Fail "StateReader expected direct safeText SetOption contract missing '$directSafeTextBang'."
        }
    }
}

$tweaksPath = Join-Path $ProjectRoot '@Resources\Scripts\CardTweaks.lua'
if (Test-Path -LiteralPath $tweaksPath) {
    $tweaks = Get-Content -LiteralPath $tweaksPath -Raw
    foreach ($forbidden in @(
        "setOption(info,'ImageAlpha',show and 255 or 0)",
        "setOption(prefix..'Window','W',0)"
    )) {
        if ($tweaks.Contains($forbidden)) { Fail "CardTweaks.lua retains retired visibility mutation '$forbidden'." }
    }
    foreach ($required in @(
        "SKIN:Bang('!ShowMeter',info)",
        "SKIN:Bang('!HideMeter',info)",
        "setOption(prefix..'Window','W',1)"
    )) {
        if (-not $tweaks.Contains($required)) { Fail "CardTweaks.lua missing explicit visibility contract '$required'." }
    }
}

$graphPath = Join-Path $ProjectRoot '@Resources\Scripts\GraphHover.lua'
if (Test-Path -LiteralPath $graphPath) {
    $graph = Get-Content -LiteralPath $graphPath -Raw
    if (-not $graph.Contains("if tip=='' then SKIN:Bang('!HideMeter',name) else SKIN:Bang('!ShowMeter',name) end")) {
        Fail 'GraphHover.lua must use explicit meter visibility for empty hover bands.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Rainmeter bang safety validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Rainmeter bang safety validation passed.' -ForegroundColor Green
Write-Host 'StateReader collapses string.gsub multi-returns before direct SetOption bangs, so substitution counts cannot become accidental Config arguments.' -ForegroundColor Green
exit 0
