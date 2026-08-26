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
        Fail "$name must not dynamically mutate ToolTipHidden; target Rainmeter interpreted numeric visibility values as config names."
    }
}

$tweaksPath = Join-Path $ProjectRoot '@Resources\Scripts\CardTweaks.lua'
if (Test-Path -LiteralPath $tweaksPath) {
    $tweaks = Get-Content -LiteralPath $tweaksPath -Raw
    foreach ($forbidden in @(
        "setOption(info,'ImageAlpha',show and 255 or 0)",
        "setOption(prefix..'Window','W',0)"
    )) {
        if ($tweaks.Contains($forbidden)) { Fail "CardTweaks.lua contains target-host unsafe zero-valued bang '$forbidden'." }
    }
    foreach ($required in @(
        "SKIN:Bang('!ShowMeter',info)",
        "SKIN:Bang('!HideMeter',info)",
        "setOption(prefix..'Window','W',1)"
    )) {
        if (-not $tweaks.Contains($required)) { Fail "CardTweaks.lua missing bang-safe visibility contract '$required'." }
    }
}

$graphPath = Join-Path $ProjectRoot '@Resources\Scripts\GraphHover.lua'
if (Test-Path -LiteralPath $graphPath) {
    $graph = Get-Content -LiteralPath $graphPath -Raw
    if (-not $graph.Contains("if tip=='' then SKIN:Bang('!HideMeter',name) else SKIN:Bang('!ShowMeter',name) end")) {
        Fail 'GraphHover.lua must use meter visibility instead of ToolTipHidden 0/1 writes.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Rainmeter bang safety validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Rainmeter bang safety validation passed.' -ForegroundColor Green
Write-Host 'Presentation scripts avoid dynamic ToolTipHidden and zero-valued visibility options that produced Skin "0" errors on the target host.' -ForegroundColor Green
exit 0
