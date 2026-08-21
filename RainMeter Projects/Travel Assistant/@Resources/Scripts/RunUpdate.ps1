param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Updater = Join-Path $PSScriptRoot 'UpdateTracker.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
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
    $psi.Arguments = '--config -'
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
                $value = [string]$Headers[$name]
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

# Windows PowerShell 5.1 on the target machine can hang in Invoke-RestMethod
# specifically against api.torn.com even though curl.exe completes immediately.
# Keep YATA and any other requests on the native cmdlet, but route only Torn
# Item Market calls through a bounded curl transport. The API key is supplied
# over curl stdin rather than on its process command line.
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

    return Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters
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

    exit 0
} finally {
    if ($acquired) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    $mutex.Dispose()
}
