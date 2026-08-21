param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Updater = Join-Path $PSScriptRoot 'UpdateTracker.ps1'
$ShadowCollector = Join-Path $PSScriptRoot 'ShadowCollector.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$ShadowErrorFile = Join-Path $RuntimeDir 'shadow-collection-error.txt'
$GeneratedDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Generated'
$HeartbeatFile = Join-Path $GeneratedDir 'last-update.txt'
$mutex = New-Object System.Threading.Mutex($false, 'Local\TornTravelAssistantUpdater')
$acquired = $false

function Invoke-TornJsonWithCurl {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 15
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) {
        throw 'curl.exe is required for Torn Item Market requests on this Windows environment.'
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
            throw ('curl.exe exceeded the {0}s Torn request timeout.' -f $TimeoutSec)
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr = 'curl.exe returned a non-zero exit code.' }
            throw ('Torn request failed: {0}' -f $stderr.Trim())
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn request returned an empty response.' }

        return ($stdout | ConvertFrom-Json)
    } finally {
        $process.Dispose()
    }
}

function Invoke-YataJsonNative {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 15
    )

    # Native Invoke-RestMethod has repeatedly succeeded against YATA on the
    # target Windows machine. Keep the curl workaround scoped to api.torn.com.
    # A single short retry covers transient YATA/network misses without turning
    # the normal one-minute scheduler into a high-frequency polling loop.
    $attemptTimeout = [Math]::Min([Math]::Max($TimeoutSec, 1), 6)
    $lastError = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            return Microsoft.PowerShell.Utility\Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -TimeoutSec $attemptTimeout
        } catch {
            $lastError = $_
            if ($attempt -lt 2) { Start-Sleep -Milliseconds 500 }
        }
    }
    if ($null -ne $lastError) { throw $lastError }
    throw 'YATA live-stock request failed.'
}

# Windows PowerShell 5.1 on the target machine can hang specifically against
# api.torn.com even though curl.exe completes immediately. Keep that workaround
# provider-specific. YATA stays on the native transport that has been validated
# successfully on this host, with one bounded retry.
function Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Method = 'Get',
        [hashtable]$Headers,
        [int]$TimeoutSec = 15
    )

    if ($Method -eq 'Get' -and $Uri -like 'https://api.torn.com/v2/market/*/itemmarket*') {
        return Invoke-TornJsonWithCurl -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec
    }
    if ($Method -eq 'Get' -and $Uri -eq 'https://yata.yt/api/v1/travel/export/') {
        return Invoke-YataJsonNative -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec
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

function Write-ShadowFailure {
    param([string]$Message)
    try {
        New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        $clean = ([string]$Message).Replace("`r", ' ').Replace("`n", ' ').Trim()
        if ($clean.Length -gt 600) { $clean = $clean.Substring(0, 600) }
        [System.IO.File]::WriteAllText($ShadowErrorFile, $clean, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

try {
    # Rainmeter can fire an initial refresh and a scheduled poll close together.
    # Skip a redundant overlapping run instead of creating concurrent network,
    # history, state, graph, or finalized-display writes.
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 0 }

    # UpdateTracker.ps1 owns the existing visible Xanax collection/history/model
    # generation. Keep that stable path first.
    & $Updater -Action $Action
    if (-not $?) { exit 1 }

    # Shadow collection is deliberately fail-soft. It starts the history clock
    # for every observed foreign-market row across all configured collection
    # countries, but it must never block the established Xanax UI/finalizer.
    if (Test-Path -LiteralPath $ShadowCollector) {
        try { & $ShadowCollector }
        catch { Write-ShadowFailure -Message $_.Exception.Message }
    }

    # FinalizeState.ps1 applies independent restock-display, resale-freshness,
    # and trip-economics guards without making another network request.
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
