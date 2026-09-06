$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$travelTweaksPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'
$filterStatePath = Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }
function Assert-True([string]$Message,[bool]$Condition) { if (-not $Condition) { Fail $Message } }
function Assert-Equal([string]$Message,$Actual,$Expected) { if ($Actual -ne $Expected) { Fail ("{0}: expected '{1}', got '{2}'" -f $Message,$Expected,$Actual) } }

foreach ($path in @($travelTweaksPath,$filterStatePath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing required file: {0}" -f $path) }
}

if ($errors.Count -eq 0) {
    $travel = Get-Content -LiteralPath $travelTweaksPath -Raw
    Assert-True 'Travel presenter must not require a WP2/window plan before rendering direct stock evidence.' (-not $travel.Contains('if row==nil or row.plan==nil then'))
    Assert-True 'Travel presenter must retain a row-existence guard.' $travel.Contains('if row==nil then')
    Assert-True 'Travel presenter must still evaluate direct outbound status after the row-only guard.' $travel.Contains("setOption(prefix..'Leave','Text',safeStockStatus(outboundStatus(row,state,now)))")
    Assert-True 'Independently valid arrival probability must remain renderable without a window plan.' $travel.Contains('setTravelChance(prefix,arrivalChanceText(row))')
    Assert-True 'Outbound tooltip must remain able to explain unknown arrival stock when plan geometry is absent.' $travel.Contains("table.insert(lines,'Estimated Stock at arrival: ?')")

    . $filterStatePath -SkipMain
    $engine = [pscustomobject]@{
        observedMarkets = [pscustomobject]@{
            'alpha:1' = [pscustomobject]@{ sourceTimestamp = 100L; catalogActive = $true }
            'beta:2' = [pscustomobject]@{ sourceTimestamp = 250L; catalogActive = $true }
            'removed:3' = [pscustomobject]@{ sourceTimestamp = 50L; catalogStatus = 'legacy_removed' }
        }
    }
    $range = Get-ActiveMarketSourceRange -Engine $engine
    Assert-Equal 'Active source range oldest timestamp' ([long]$range.oldest) 100L
    Assert-Equal 'Active source range freshest timestamp' ([long]$range.freshest) 250L

    $filter = Get-Content -LiteralPath $filterStatePath -Raw
    Assert-True 'UIOldestMarketSourceTimestamp must publish sourceRange.oldest.' $filter.Contains("`$state['UIOldestMarketSourceTimestamp'] = [long]`$sourceRange.oldest")
    Assert-True 'UIOldestMarketSourceTimestamp must never alias sourceRange.freshest.' (-not $filter.Contains("`$state['UIOldestMarketSourceTimestamp'] = [long]`$sourceRange.freshest"))
    Assert-True 'UIFreshestMarketSourceTimestamp must continue publishing sourceRange.freshest.' $filter.Contains("`$state['UIFreshestMarketSourceTimestamp'] = [long]`$sourceRange.freshest")
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host ("FAIL: {0}" -f $validationError) -ForegroundColor Red }
    Write-Host ("Audit stock/freshness validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Audit stock/freshness validation passed.' -ForegroundColor Green
Write-Host 'Direct stock facts no longer require a window plan, and oldest/freshest source timestamps remain distinct.' -ForegroundColor Green
exit 0
