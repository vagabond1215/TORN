param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Updater = Join-Path $PSScriptRoot 'UpdateTracker.ps1'
$CollectedState = Join-Path $PSScriptRoot 'ProjectCollectedState.ps1'
$ObservationHistory = Join-Path $PSScriptRoot 'MaintainObservationHistory.ps1'
$ShadowCollector = Join-Path $PSScriptRoot 'ShadowCollector.ps1'
$LocalCatalog = Join-Path $PSScriptRoot 'LocalCatalog.ps1'
$EngineStateSchema = Join-Path $PSScriptRoot 'EnsureEngineStateSchema.ps1'
$TravelContext = Join-Path $PSScriptRoot 'TravelContext.ps1'
$OptimalRoute = Join-Path $PSScriptRoot 'OptimalRoute.ps1'
$OpportunityState = Join-Path $PSScriptRoot 'OpportunityState.ps1'
$FilterState = Join-Path $PSScriptRoot 'FilterState.ps1'
$CycleAnalytics = Join-Path $PSScriptRoot 'CycleAnalytics.ps1'
$ResalePriority = Join-Path $PSScriptRoot 'ResalePriority.ps1'
$ResaleQueue = Join-Path $PSScriptRoot 'ResaleQueue.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
$RuntimeLogScript = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$HistoryErrorFile = Join-Path $RuntimeDir 'history-maintenance-error.txt'
$ShadowErrorFile = Join-Path $RuntimeDir 'shadow-collection-error.txt'
$CollectedStateErrorFile = Join-Path $RuntimeDir 'collected-state-error.txt'
$LocalCatalogErrorFile = Join-Path $RuntimeDir 'local-catalog-error.txt'
$EngineStateSchemaErrorFile = Join-Path $RuntimeDir 'engine-state-schema-error.txt'
$TravelContextErrorFile = Join-Path $RuntimeDir 'travel-context-error.txt'
$OptimalRouteErrorFile = Join-Path $RuntimeDir 'optimal-route-error.txt'
$OpportunityStateErrorFile = Join-Path $RuntimeDir 'opportunity-state-error.txt'
$FilterStateErrorFile = Join-Path $RuntimeDir 'filter-state-error.txt'
$CycleAnalyticsErrorFile = Join-Path $RuntimeDir 'cycle-analytics-error.txt'
$ResaleQueueErrorFile = Join-Path $RuntimeDir 'resale-queue-error.txt'
$GeneratedDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Generated'
$HeartbeatFile = Join-Path $GeneratedDir 'last-update.txt'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$mutex = New-Object System.Threading.Mutex($false, 'Local\TornTravelAssistantUpdater')
$acquired = $false

if (Test-Path -LiteralPath $RuntimeLogScript) { . $RuntimeLogScript }

function Get-UpdateFailureComponent {
    param([string]$Path)
    $name = [System.IO.Path]::GetFileNameWithoutExtension([string]$Path)
    return ($name -replace '-error$','')
}

function Invoke-TornJsonWithCurl {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 15
    )
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for Torn Item Market requests on this Windows environment.' }
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
        if (-not $process.WaitForExit($waitMs)) { try { $process.Kill() } catch { }; throw ('curl.exe exceeded the {0}s Torn request timeout.' -f $TimeoutSec) }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) { if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr = 'curl.exe returned a non-zero exit code.' }; throw ('Torn request failed: {0}' -f $stderr.Trim()) }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn request returned an empty response.' }
        return ($stdout | ConvertFrom-Json)
    } finally { $process.Dispose() }
}

function Invoke-YataJsonNative {
    param([Parameter(Mandatory = $true)][string]$Uri, [hashtable]$Headers, [int]$TimeoutSec = 15)
    $attemptTimeout = [Math]::Min([Math]::Max($TimeoutSec, 1), 6)
    $lastError = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try { return Microsoft.PowerShell.Utility\Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -TimeoutSec $attemptTimeout }
        catch { $lastError = $_; if ($attempt -lt 2) { Start-Sleep -Milliseconds 500 } }
    }
    if ($null -ne $lastError) { throw $lastError }
    throw 'YATA live-stock request failed.'
}

function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Uri, [string]$Method = 'Get', [hashtable]$Headers, [int]$TimeoutSec = 15)
    if ($Method -eq 'Get' -and $Uri -like 'https://api.torn.com/v2/market/*/itemmarket*') { return Invoke-TornJsonWithCurl -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec }
    if ($Method -eq 'Get' -and $Uri -eq 'https://yata.yt/api/v1/travel/export/') { return Invoke-YataJsonNative -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec }
    return Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters
}

function Write-UpdateHeartbeat {
    New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
    $tmp = $HeartbeatFile + '.tmp'
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [System.IO.File]::WriteAllText($tmp, $epoch, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $HeartbeatFile -Force
}

function Write-CompactFailure {
    param([string]$Path, [string]$Message)
    $component = Get-UpdateFailureComponent $Path
    try {
        New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        $clean = ([string]$Message).Replace("`r", ' ').Replace("`n", ' ').Trim()
        if ($clean.Length -gt 600) { $clean = $clean.Substring(0, 600) }
        [System.IO.File]::WriteAllText($Path, $clean, [System.Text.UTF8Encoding]::new($false))
    } catch { }
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component $component -Message $Message
    }
}

function Clear-CompactFailure {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
    if (Get-Command Clear-TravelAssistantLatestError -ErrorAction SilentlyContinue) {
        Clear-TravelAssistantLatestError -Component (Get-UpdateFailureComponent $Path)
    }
}

function Mirror-ChildOwnedFailure {
    param([string]$ErrorPath)
    if (-not (Test-Path -LiteralPath $ErrorPath)) {
        if (Get-Command Clear-TravelAssistantLatestError -ErrorAction SilentlyContinue) {
            Clear-TravelAssistantLatestError -Component (Get-UpdateFailureComponent $ErrorPath)
        }
        return
    }
    try {
        $message = Get-Content -LiteralPath $ErrorPath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($message) -and (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue)) {
            Write-TravelAssistantLog -Level ERROR -Component (Get-UpdateFailureComponent $ErrorPath) -Message $message
        }
    } catch { }
}

function Invoke-FailSoftScript {
    param(
        [string]$Path,
        [string]$ErrorPath,
        [bool]$ClearErrorOnSuccess = $true
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        & $Path
        if ($ClearErrorOnSuccess) { Clear-CompactFailure -Path $ErrorPath }
        else { Mirror-ChildOwnedFailure -ErrorPath $ErrorPath }
    } catch { Write-CompactFailure -Path $ErrorPath -Message $_.Exception.ToString() }
}

function Invoke-HistoryMaintenance {
    param([string]$Phase)
    if (-not (Test-Path -LiteralPath $ObservationHistory)) { return }
    try {
        & $ObservationHistory -Phase $Phase
        Clear-CompactFailure -Path $HistoryErrorFile
    } catch {
        Write-CompactFailure -Path $HistoryErrorFile -Message $_.Exception.ToString()
    }
}

try {
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 0 }

    # Preserve one predecessor per market before any legacy maintenance can prune
    # the shared high-resolution evidence store.
    Invoke-HistoryMaintenance -Phase 'PreUpdate'

    if ($Action -eq 'Update') {
        # ShadowCollector is the sole live foreign-stock request on the main path
        # and owns stock-transition history for every active market.
        Invoke-FailSoftScript -Path $ShadowCollector -ErrorPath $ShadowErrorFile -ClearErrorOnSuccess $false

        # The legacy UK/JP state keys are still useful to compatibility readers,
        # but they are projected locally from the collector state. Do not issue a
        # second provider request or a second history write through UpdateTracker.
        Invoke-FailSoftScript -Path $CollectedState -ErrorPath $CollectedStateErrorFile
    } else {
        # Retain the explicit legacy action only for callers that still cycle its
        # travel-mode preference. It is not part of the normal one-minute heartbeat.
        & $Updater -Action $Action
        if (-not $?) { throw 'UpdateTracker returned failure.' }
        Invoke-FailSoftScript -Path $ShadowCollector -ErrorPath $ShadowErrorFile -ClearErrorOnSuccess $false
    }

    # Bootstrap truthful current snapshots for active markets whose older baseline
    # was already lost by previous retention pruning. Deleted history is not invented.
    Invoke-HistoryMaintenance -Phase 'PostUpdate'

    Invoke-FailSoftScript -Path $LocalCatalog -ErrorPath $LocalCatalogErrorFile

    # Persist engine-state schema normalization even when collection failed and the
    # UI is temporarily operating from the last known state.
    Invoke-FailSoftScript -Path $EngineStateSchema -ErrorPath $EngineStateSchemaErrorFile

    & $Finalizer
    if (-not $?) { throw 'FinalizeState returned failure.' }

    # TravelContext owns its diagnostic file because it catches transient API failures
    # internally while preserving the last successful destination/bar context.
    if ($Action -eq 'Update') { Invoke-FailSoftScript -Path $TravelContext -ErrorPath $TravelContextErrorFile -ClearErrorOnSuccess $false }

    # Keep the route optimizer as a background decision/pricing-priority model.
    Invoke-FailSoftScript -Path $OptimalRoute -ErrorPath $OptimalRouteErrorFile

    # Primary presentation is the sortable opportunity surface.
    Invoke-FailSoftScript -Path $OpportunityState -ErrorPath $OpportunityStateErrorFile

    # OpportunityState must always leave an explicit projection, even when the
    # correct result is zero rows. Detect silent early-return states immediately.
    $hasOpportunityProjection = $false
    try {
        if (Test-Path -LiteralPath $StateKvFile) {
            $hasOpportunityProjection = [bool](Select-String -LiteralPath $StateKvFile -Pattern '^OpportunityCount=' -Quiet)
        }
    } catch { $hasOpportunityProjection = $false }
    if (-not $hasOpportunityProjection) {
        Write-CompactFailure -Path $OpportunityStateErrorFile -Message 'OpportunityState completed without writing OpportunityCount to state.kv.'
    }

    if (Test-Path -LiteralPath $FilterState) {
        try { & $FilterState; Clear-CompactFailure -Path $FilterStateErrorFile }
        catch { Write-CompactFailure -Path $FilterStateErrorFile -Message $_.Exception.ToString() }
    }

    # Heartbeat marks completion of the current stock/context/opportunity projection.
    # Local analytics and resale pricing run afterward and cannot make the visible
    # opportunity list falsely stale.
    Write-UpdateHeartbeat

    if ($Action -eq 'Update') {
        Invoke-FailSoftScript -Path $CycleAnalytics -ErrorPath $CycleAnalyticsErrorFile
    }

    if ($Action -eq 'Update' -and (Test-Path -LiteralPath $ResaleQueue)) {
        try {
            if (Test-Path -LiteralPath $ResalePriority) { & $ResalePriority }
            & $ResaleQueue
            if (Test-Path -LiteralPath $ResaleQueueErrorFile) {
                try {
                    $queueState = Get-Content -LiteralPath (Join-Path $RuntimeDir 'engine-state.json') -Raw | ConvertFrom-Json
                    if ($queueState.PSObject.Properties['resaleQueue'] -and [string]$queueState.resaleQueue.status -ne 'ERROR') { Clear-CompactFailure -Path $ResaleQueueErrorFile }
                } catch { }
            } else { Clear-CompactFailure -Path $ResaleQueueErrorFile }
        } catch { Write-CompactFailure -Path $ResaleQueueErrorFile -Message $_.Exception.ToString() }
    }

    if (Get-Command Clear-TravelAssistantLatestError -ErrorAction SilentlyContinue) { Clear-TravelAssistantLatestError -Component 'run-update' }
    exit 0
} catch {
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component 'run-update' -Message $_.Exception.ToString()
    }
    throw
} finally {
    if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
    $mutex.Dispose()
}
