$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cardPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$travelPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }
function Assert-True([string]$Message,[bool]$Condition) { if (-not $Condition) { Fail $Message } }

foreach ($path in @($cardPath,$travelPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing required file: {0}" -f $path) }
}

if ($errors.Count -eq 0) {
    $card = Get-Content -LiteralPath $cardPath -Raw
    $travel = Get-Content -LiteralPath $travelPath -Raw

    Assert-True 'CardPresenter must normalize exact In stock and Stock holding labels to the shared safe-leave wording.' (
        $card.Contains("if normalizedAction=='in stock' or normalizedAction=='stock holding' then actionText='In Stock - Safe to Leave' end")
    )
    Assert-True 'TravelStateWindowTweaks must define the same exact-status normalization.' (
        $travel.Contains("if normalized=='in stock' or normalized=='stock holding' then return 'In Stock - Safe to Leave' end")
    )
    Assert-True 'Traveling rows must normalize outbound status before rendering.' (
        $travel.Contains("setOption(prefix..'Leave','Text',safeStockStatus(outboundStatus(row,state,now)))")
    )
    Assert-True 'Abroad rows must normalize current-cycle status before rendering.' (
        $travel.Contains("setOption(prefix..'Leave','Text',safeStockStatus(status))")
    )

    # Timing-bearing labels are intentionally distinct and must retain their details.
    Assert-True 'Sellout countdown status must remain intact.' $travel.Contains("return 'Sells out in '..formatDuration")
    Assert-True 'In-stock duration status must remain intact.' $travel.Contains("return 'In stock for '..formatDuration")
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host ("FAIL: {0}" -f $validationError) -ForegroundColor Red }
    Write-Host ("Stock status wording validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Stock status wording validation passed.' -ForegroundColor Green
Write-Host 'Exact In stock and Stock holding states render as In Stock - Safe to Leave without flattening timing-bearing statuses.' -ForegroundColor Green
exit 0
