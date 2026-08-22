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
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "TravelContext.ps1 parse error: $($parseError.Message)" }

    foreach ($fn in @('Resolve-TravelCountryId','Convert-TornUserBar','Convert-TornTravelContext','Invoke-TornTravelCurl','Set-ProjectedBar','Project-TravelContextToState')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($fn) + '\s*\{')) { Fail "Missing $fn." }
    }
    foreach ($token in @(
        'https://api.torn.com/v2/user?selections=travel,basic,bars',
        "`$psi.Arguments = '-q --config -'",
        'Authorization: ApiKey {0}',
        'destinationCountryId',
        'filterActive',
        "Set-ProjectedBar -State `$state -Prefix 'Energy'",
        "Set-ProjectedBar -State `$state -Prefix 'Nerve'",
        'TravelDestinationCountryId',
        'TravelFilterActive',
        'TravelArrivalAt',
        'TravelTimeLeft',
        'Preserve the last successful foreign destination and bars on transient failures.'
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
    $travel = $wrapper.IndexOf('Invoke-FailSoftScript -Path $TravelContext')
    $optimal = $wrapper.IndexOf('Invoke-FailSoftScript -Path $OptimalRoute')
    $opportunity = $wrapper.IndexOf('Invoke-FailSoftScript -Path $OpportunityState')
    $filterState = $wrapper.IndexOf('& $FilterState')
    if (@($finalizer,$travel,$optimal,$opportunity,$filterState) -contains -1 -or -not ($finalizer -lt $travel -and $travel -lt $optimal -and $optimal -lt $opportunity -and $opportunity -lt $filterState)) {
        Fail 'Runtime order must keep FinalizeState -> TravelContext -> OptimalRoute -> OpportunityState -> FilterState.'
    }
    if ($wrapper -notmatch '(?m)^\s*\[bool\]\$ClearErrorOnSuccess\s*=\s*\$true') { Fail 'Fail-soft helper must expose explicit error-file clearing policy.' }
    if ($wrapper -notmatch '(?m)Invoke-FailSoftScript -Path \$TravelContext -ErrorPath \$TravelContextErrorFile -ClearErrorOnSuccess \$false') { Fail 'TravelContext must retain ownership of its diagnostic file after internally caught API failures.' }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Travel context validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Travel context configuration validation passed.' -ForegroundColor Green
Write-Host 'One bounded user request supplies destination plus Energy/Nerve bars; transient failures preserve the last successful context and diagnostics before opportunity ranking.'
exit 0
