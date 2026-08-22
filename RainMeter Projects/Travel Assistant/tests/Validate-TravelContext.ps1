$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelContext.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $scriptPath)) {
    Fail 'Missing TravelContext.ps1.'
} else {
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "TravelContext.ps1 parse error: $($parseError.Message)" }

    foreach ($fn in @('Resolve-TravelCountryId','Convert-TornTravelContext','Invoke-TornTravelCurl','Project-TravelContextToState')) {
        if ($text -notmatch ('(?m)^function\s+'+[regex]::Escape($fn)+'\s*\{')) { Fail "Missing $fn." }
    }
    foreach ($token in @(
        'https://api.torn.com/v2/user?selections=travel,basic',
        "`$psi.Arguments = '-q --config -'",
        'Authorization: ApiKey {0}',
        'destinationCountryId',
        'filterActive',
        'TravelDestinationCountryId',
        'TravelFilterActive',
        'TravelArrivalAt',
        'TravelTimeLeft',
        'Preserve the last successful foreign'
    )) {
        if (-not $text.Contains($token)) { Fail "Travel context contract missing '$token'." }
    }
    if ($text -match '(?i)[?&](key|api_key|apikey)=') { Fail 'Travel context must not put API key in URL.' }
    if ($text -match '(?i)Arguments\s*=.*ApiKey') { Fail 'Travel context must not put API key in process arguments.' }
    if ($text -notmatch '(?m)^\s*\[int\]\$RequestTimeoutSeconds\s*=\s*5') { Fail 'Travel context default timeout must be five seconds.' }
}

if (-not (Test-Path -LiteralPath $wrapperPath)) {
    Fail 'Missing RunUpdate.ps1.'
} else {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    $finalizer = $wrapper.IndexOf('& $Finalizer')
    $travel = $wrapper.IndexOf('& $TravelContext')
    $visible = $wrapper.IndexOf('& $VisibleItems')
    if ($finalizer -lt 0 -or $travel -lt 0 -or $visible -lt 0 -or -not ($finalizer -lt $travel -and $travel -lt $visible)) {
        Fail 'Runtime order must keep FinalizeState -> TravelContext -> VisibleItems.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Travel context validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Travel context configuration validation passed.' -ForegroundColor Green
Write-Host 'Destination filtering uses one bounded fail-soft Torn user request and preserves the last successful foreign context on transient failures.'
exit 0
