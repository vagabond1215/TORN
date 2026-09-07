$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$freshnessPath = Join-Path $ProjectRoot '@Resources\Scripts\FreshnessGuard.lua'
$polishPath = Join-Path $ProjectRoot '@Resources\Scripts\FinalCardPolish.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }
function Assert-True([string]$Message,[bool]$Condition) { if (-not $Condition) { Fail $Message } }

foreach ($path in @($freshnessPath,$polishPath,$infoPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing required file: {0}" -f $path) }
}

if ($errors.Count -eq 0) {
    $freshness = Get-Content -LiteralPath $freshnessPath -Raw
    $polish = Get-Content -LiteralPath $polishPath -Raw
    $info = Get-Content -LiteralPath $infoPath -Raw

    Assert-True 'FreshnessGuard must capture the StateReader-owned panel height before the travel presentation pass.' ($freshness.Contains("setVariable('AuthoritativePanelHeight',math.floor(value))"))
    $freshModeAt = $freshness.IndexOf("setVariable('StockFreshnessMode','fresh')")
    $freshCaptureAt = $freshness.IndexOf('captureAuthoritativePanelHeight()', $freshModeAt)
    Assert-True 'Fresh mode must capture authoritative panel height before its early return.' ($freshModeAt -ge 0 -and $freshCaptureAt -gt $freshModeAt)
    Assert-True 'FreshnessGuard must also capture the final degraded/hard-stale height.' ($freshness.Contains("captureAuthoritativePanelHeight()`n`n    -- Display-only fence"))

    Assert-True 'Final polish must restore the captured panel height after travel-state presentation.' ($polish.Contains("SKIN:Bang('!SetVariable','PanelHeight',tostring(math.floor(authoritativePanelHeight)))"))
    Assert-True 'Final polish must identify physical rows so duplicate retained slots cannot render twice.' ($polish.Contains('local function rowIdentity(prefix)'))
    Assert-True 'Final polish must suppress duplicate row identities.' ($polish.Contains('seenRows[identity]==true'))
    Assert-True 'Final polish must reject chance meters positioned below the authoritative panel body.' ($polish.Contains('chanceOutsideAuthoritativePanel(prefix,authoritativePanelHeight)'))
    Assert-True 'Out-of-panel detection must use the current Rainmeter meter Y position.' ($polish.Contains('meter:GetY()'))
    Assert-True 'Stale physical slots must actively clear and hide Chance.' ($polish.Contains('if stalePhysicalSlot then') -and $polish.Contains('suppressChance(prefix)'))

    $freshIndex = $info.IndexOf('[MeasureFreshnessGuard]')
    $travelIndex = $info.IndexOf('[MeasureTravelStateWindowTweaks]')
    $polishIndex = $info.IndexOf('[MeasureFinalCardPolish]')
    Assert-True 'FreshnessGuard must execute before TravelStateWindowTweaks.' ($freshIndex -ge 0 -and $travelIndex -gt $freshIndex)
    Assert-True 'FinalCardPolish must execute after TravelStateWindowTweaks.' ($polishIndex -gt $travelIndex)
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host ("FAIL: {0}" -f $validationError) -ForegroundColor Red }
    Write-Host ("Stale opportunity-meter reflow validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Stale opportunity-meter reflow validation passed.' -ForegroundColor Green
Write-Host 'The final presentation restores StateReader geometry and fences orphan Chance meters from retained hidden row slots.' -ForegroundColor Green
exit 0
