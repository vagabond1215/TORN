param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Updater = Join-Path $PSScriptRoot 'UpdateTracker.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
$GeneratedDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Generated'
$HeartbeatFile = Join-Path $GeneratedDir 'last-update.txt'
$mutex = New-Object System.Threading.Mutex($false, 'Local\TornTravelAssistantUpdater')
$acquired = $false

function Invoke-JsonWithCurl {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 15,
        [string]$RequestLabel = 'HTTP'
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) {
        throw 'curl.exe is required for Travel Assistant live requests on this Windows environment.'
    }

    if ($TimeoutSec -lt 1) { $TimeoutSec = 15 }
    $connectTimeout = [Math]::Min(5, $TimeoutSec)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curl.Source
    $psi.Arguments = '-q --config -'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    try {
        if (-not $process.Start()) { throw 'Failed to start curl.exe.' }

        $process.StandardInput.WriteLine('silent')
        $process.StandardInput.WriteLine('show-error')
        $process.StandardInput.WriteLine('fail')
        $process.StandardInput.WriteLine(('connect-timeout = {0}' -f $connectTimeout))
        $process.StandardInput.WriteLine(('max-time = {0}' -f $TimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $Uri.Replace('"', '\"')))

        if ($null -ne $Headers) {
            foreach ($name in $Headers.Keys) {
                $value = ([string]$Headers[$name]).Replace("`r", ' ').Replace("`n", ' ')
                $header = ('{0}: {1}' -f [string]$name, $value).Replace('"', '\"')
                $process.StandardInput.WriteLine(('header = "{0}"' -f $header))
            }
        }

        $process.StandardInput.Close()
        $waitMs = [Math]::Max(2000, ($TimeoutSec + 2) * 1000)
        if (-not $process.WaitForExit($waitMs)) {
            try { $process.Kill() } catch { }
            throw ('curl.exe exceeded the {0}s {1} request timeout.' -f $TimeoutSec, $RequestLabel)
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr = 'curl.exe returned a non-zero exit code.' }
            throw ('{0} request failed: {1}' -f $RequestLabel, $stderr.Trim())
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw ('{0} request returned an empty response.' -f $RequestLabel) }

        return ($stdout | ConvertFrom-Json)
    } finally {
        $process.Dispose()
    }
}

function Invoke-YataJsonWithCurl {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 15
    )

    # A live-stock miss can consume a meaningful part of a short foreign restock.
    # Keep normal polling at 60s, but make a single bounded transport retry before
    # returning cached/stale state. This is deliberately not an unbounded retry loop.
    $attemptTimeout = [Math]::Min([Math]::Max($TimeoutSec, 1), 7)
    $lastError = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            return Invoke-JsonWithCurl -Uri $Uri -Headers $Headers -TimeoutSec $attemptTimeout -RequestLabel 'YATA live-stock'
        } catch {
            $lastError = $_
            if ($attempt -lt 2) { Start-Sleep -Milliseconds 750 }
        }
    }
    if ($null -ne $lastError) { throw $lastError }
    throw 'YATA live-stock request failed.'
}

# Windows PowerShell 5.1 has shown unreliable native HTTP behavior on this
# target machine. Route both critical JSON providers through bounded curl.exe.
# The Torn API key is supplied over curl stdin rather than on its process
# command line. Non-provider requests can still use the native cmdlet.
function Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Method = 'Get',
        [hashtable]$Headers,
        [int]$TimeoutSec = 15
    )

    if ($Method -eq 'Get' -and $Uri -like 'https://api.torn.com/v2/market/*/itemmarket*') {
        return Invoke-JsonWithCurl -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec -RequestLabel 'Torn Item Market'
    }
    if ($Method -eq 'Get' -and $Uri -eq 'https://yata.yt/api/v1/travel/export/') {
        return Invoke-YataJsonWithCurl -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec
    }

    return Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters
}

function Write-UpdateHeartbeat {
    New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
    $tmp = $HeartbeatFile + '.tmp'
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [System.IO.File]::WriteAllText($tmp, $epoch, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $HeartbeatFile -Force
}

try {
    # Rainmeter can fire an initial refresh and a scheduled poll close together.
    # Skip a redundant overlapping run instead of creating concurrent network,
    # history, state, graph, or finalized-display writes.
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 0 }

    # UpdateTracker.ps1 owns live collection/history/model generation.
    # FinalizeState.ps1 then applies independent restock-display, resale-freshness,
    # and trip-economics guards without making another network request.
    & $Updater -Action $Action
    if (-not $?) { exit 1 }

    & $Finalizer
    if (-not $?) { exit 1 }

    # Write a tiny local heartbeat only after the serialized production pass
    # completes. Rainmeter uses this to make polling health visible.
    Write-UpdateHeartbeat

    exit 0
} finally {
    if ($acquired) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    $mutex.Dispose()
}
