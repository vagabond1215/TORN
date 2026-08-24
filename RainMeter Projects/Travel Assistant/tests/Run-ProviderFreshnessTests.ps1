$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$scriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path '@Resources\Scripts\ShadowCollector.ps1'
. $scriptPath -SkipMain

$failures = New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }

$now = 200000L
$freshPayload = [pscustomobject]@{
    stocks = [pscustomobject]@{
        uni = [pscustomobject]@{ update = $now - 30; stocks = @() }
        can = [pscustomobject]@{ update = $now - 90; stocks = @() }
    }
}
$freshness = Get-LivePayloadFreshness -Payload $freshPayload -NowEpoch $now
Assert-Equal ([int]$freshness.timestampCount) 2 'Freshness reader should count country timestamps.'
Assert-Equal ([long]$freshness.freshest) ($now-30) 'Freshness reader should select the newest country update.'
Assert-Equal ([long]$freshness.oldest) ($now-90) 'Freshness reader should retain the oldest country update diagnostically.'
Assert-Equal ([long]$freshness.freshestAgeSeconds) 30L 'Freshest age should be measured from current epoch.'

try {
    $accepted = Assert-LivePayloadFresh -Payload $freshPayload -NowEpoch $now -MaximumAgeSeconds 300 -ProviderName 'fixture'
    Assert-True ($null -ne $accepted) 'A provider with a fresh country sample should be accepted.'
} catch {
    $failures.Add('Fresh provider fixture was rejected: ' + $_.Exception.Message)
}

$stalePayload = [pscustomobject]@{
    stocks = [pscustomobject]@{
        uni = [pscustomobject]@{ update = $now - 3600; stocks = @() }
        can = [pscustomobject]@{ update = $now - 7200; stocks = @() }
    }
}
$staleRejected = $false
try { [void](Assert-LivePayloadFresh -Payload $stalePayload -NowEpoch $now -MaximumAgeSeconds 300 -ProviderName 'stale-fixture') }
catch { $staleRejected = $_.Exception.Message -like '*response is stale*' }
Assert-True $staleRejected 'A structurally valid but hours-old provider payload must be rejected so fallback can run.'

$missingTimestampPayload = [pscustomobject]@{ stocks = [pscustomobject]@{ uni = [pscustomobject]@{ stocks = @() } } }
$missingRejected = $false
try { [void](Assert-LivePayloadFresh -Payload $missingTimestampPayload -NowEpoch $now -MaximumAgeSeconds 300 -ProviderName 'missing-fixture') }
catch { $missingRejected = $_.Exception.Message -like '*no usable country update timestamps*' }
Assert-True $missingRejected 'A provider without usable update timestamps must not be treated as fresh evidence.'

# A globally fresh primary payload can still contain a stale individual country.
# Country selection must therefore fall back independently rather than allowing
# fresh Canada to mask stale Mexico/Cayman data in the same Prometheus response.
$mexico = [pscustomobject]@{ id='mexico'; providerCodes=[pscustomobject]@{ prometheus='mex'; yata='mex' } }
$canada = [pscustomobject]@{ id='canada'; providerCodes=[pscustomobject]@{ prometheus='can'; yata='can' } }
$prometheusMixed = [pscustomobject]@{
    stocks = [pscustomobject]@{
        can = [pscustomobject]@{ update=$now-30; stocks=@([pscustomobject]@{id=1;quantity=1;cost=1}) }
        mex = [pscustomobject]@{ update=$now-1200; stocks=@([pscustomobject]@{id=2;quantity=2;cost=2}) }
    }
}
$yataFresh = [pscustomobject]@{
    stocks = [pscustomobject]@{
        can = [pscustomobject]@{ update=$now-60; stocks=@([pscustomobject]@{id=1;quantity=1;cost=1}) }
        mex = [pscustomobject]@{ update=$now-45; stocks=@([pscustomobject]@{id=2;quantity=2;cost=2}) }
    }
}
$providerSet = [pscustomobject]@{
    snapshots = @{
        prometheus = [pscustomobject]@{ source='prometheus'; payload=$prometheusMixed; error='' }
        yata = [pscustomobject]@{ source='yata'; payload=$yataFresh; error='' }
    }
    errors = [string[]]@()
}
$mexSelection = Select-LiveCountryProvider -ProviderSet $providerSet -Country $mexico -NowEpoch $now -MaximumAgeSeconds 300
$canSelection = Select-LiveCountryProvider -ProviderSet $providerSet -Country $canada -NowEpoch $now -MaximumAgeSeconds 300
Assert-Equal ([string]$mexSelection.source) 'yata' 'Stale Mexico on Prometheus should use fresh YATA Mexico.'
Assert-Equal ([string]$canSelection.source) 'prometheus' 'Fresh Canada should remain on the fresher Prometheus country sample.'
Assert-True ([bool](Get-CountryPayloadStatus -Payload $prometheusMixed -Country $mexico -Source 'prometheus' -NowEpoch $now -MaximumAgeSeconds 300).fresh -eq $false) 'Country freshness must be evaluated independently.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "Provider freshness tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Provider freshness validation passed.' -ForegroundColor Green
Write-Host 'Freshness is country-specific: stale/missing primary countries can fall back to YATA without discarding fresh Prometheus countries.'
exit 0
