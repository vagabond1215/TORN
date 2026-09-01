param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update',
    [ValidateRange(0,300)]
    [int]$MutexWaitSeconds = 0
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
$CurrentCapacityRefresh = Join-Path $PSScriptRoot 'CurrentCapacityRefresh.ps1'
$CycleAnchorReconciler = Join-Path $PSScriptRoot 'CycleAnchorReconciler.ps1'
$OpportunityState = Join-Path $PSScriptRoot 'OpportunityState.ps1'
$WindowPlan = Join-Path $PSScriptRoot 'WindowPlan.ps1'
$PriceVariationRefiner = Join-Path $PSScriptRoot 'PriceVariationRefiner.ps1'
$FilterState = Join-Path $PSScriptRoot 'FilterState.ps1'
$CycleAnalytics = Join-Path $PSScriptRoot 'CycleAnalytics.ps1'
$TrendForecast = Join-Path $PSScriptRoot 'TrendForecast.ps1'
$ResalePriority = Join-Path $PSScriptRoot 'ResalePriority.ps1'
$ResaleQueue = Join-Path $PSScriptRoot 'ResaleQueue.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
$RuntimeLogScript = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$UpdatePerformanceFile = Join-Path $RuntimeDir 'update-performance.log'
$UpdatePerformanceErrorFile = Join-Path $RuntimeDir 'update-performance-error.txt'
$HistoryErrorFile = Join-Path $RuntimeDir 'history-maintenance-error.txt'
$ShadowErrorFile = Join-Path $RuntimeDir 'shadow-collection-error.txt'
$CollectedStateErrorFile = Join-Path $RuntimeDir 'collected-state-error.txt'
$LocalCatalogErrorFile = Join-Path $RuntimeDir 'local-catalog-error.txt'
$EngineStateSchemaErrorFile = Join-Path $RuntimeDir 'engine-state-schema-error.txt'
$TravelContextErrorFile = Join-Path $RuntimeDir 'travel-context-error.txt'
$CurrentCapacityRefreshErrorFile = Join-Path $RuntimeDir 'current-capacity-refresh-error.txt'
$CycleAnchorReconcilerErrorFile = Join-Path $RuntimeDir 'cycle-anchor-reconciler-error.txt'
$OpportunityStateErrorFile = Join-Path $RuntimeDir 'opportunity-state-error.txt'
$WindowPlanErrorFile = Join-Path $RuntimeDir 'window-plan-error.txt'
$PriceVariationRefinerErrorFile = Join-Path $RuntimeDir 'price-variation-refiner-error.txt'
$FilterStateErrorFile = Join-Path $RuntimeDir 'filter-state-error.txt'
$CycleAnalyticsErrorFile = Join-Path $RuntimeDir 'cycle-analytics-error.txt'
$TrendForecastErrorFile = Join-Path $RuntimeDir 'trend-forecast-error.txt'
$ResaleQueueErrorFile = Join-Path $RuntimeDir 'resale-queue-error.txt'
$GeneratedDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Generated'
$HeartbeatFile = Join-Path $GeneratedDir 'last-update.txt'
# state.kv is the private/build artifact mutated by intermediate pipeline stages.
# Rainmeter reads immutable snapshots selected by the small heartbeat manifest.
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$PendingUiGeneration = $null
$mutex = New-Object System.Threading.Mutex($false, 'Local\TornTravelAssistantUpdater')
$acquired = $false
$UpdatePerformanceRows = New-Object System.Collections.Generic.List[object]
$UpdatePerformanceProcess = [System.Diagnostics.Process]::GetCurrentProcess()
$UpdatePerformanceWall = [System.Diagnostics.Stopwatch]::StartNew()
$UpdatePerformanceCpuStart = [double]$UpdatePerformanceProcess.TotalProcessorTime.TotalMilliseconds
$UpdatePerformanceActive = $false
$UpdatePerformanceOutcome = 'not-started'

if (Test-Path -LiteralPath $RuntimeLogScript) { . $RuntimeLogScript }
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for safe Travel Assistant state publication.' }
. $AtomicFileScript

function Get-UpdateFailureComponent {
    param([string]$Path)
    $name = [System.IO.Path]::GetFileNameWithoutExtension([string]$Path)
    return ($name -replace '-error$','')
}

function Get-UpdateCpuMilliseconds {
    try {
        $script:UpdatePerformanceProcess.Refresh()
        return [double]$script:UpdatePerformanceProcess.TotalProcessorTime.TotalMilliseconds
    } catch { return 0.0 }
}

function New-UpdateStageTimer {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [pscustomobject]@{
        Name = $Name
        Wall = [System.Diagnostics.Stopwatch]::StartNew()
        CpuStart = Get-UpdateCpuMilliseconds
    }
}

function Complete-UpdateStageTimer {
    param([object]$Timer)
    if ($null -eq $Timer) { return }
    try {
        $Timer.Wall.Stop()
        $cpuEnd = Get-UpdateCpuMilliseconds
        [void]$script:UpdatePerformanceRows.Add([pscustomobject]@{
            Name = [string]$Timer.Name
            WallMs = [double]$Timer.Wall.Elapsed.TotalMilliseconds
            CpuMs = [Math]::Max(0.0, [double]$cpuEnd - [double]$Timer.CpuStart)
        })
    } catch { }
}

function Write-UpdatePerformanceRecord {
    param([Parameter(Mandatory = $true)][string]$Line)

    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    $payload = $Line + [Environment]::NewLine
    [System.IO.File]::AppendAllText(
        $UpdatePerformanceFile,
        $payload,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Write-UpdatePerformanceSummary {
    if (-not $script:UpdatePerformanceActive) {
        throw 'Updater performance telemetry was not activated after mutex acquisition.'
    }

    $script:UpdatePerformanceWall.Stop()
    $totalCpu = [Math]::Max(0.0, (Get-UpdateCpuMilliseconds) - [double]$script:UpdatePerformanceCpuStart)
    $stageParts = New-Object System.Collections.Generic.List[string]
    foreach ($row in $script:UpdatePerformanceRows) {
        [void]$stageParts.Add(('{0}:{1}cpu/{2}wall' -f
            [string]$row.Name,
            [long][Math]::Round([double]$row.CpuMs),
            [long][Math]::Round([double]$row.WallMs)))
    }
    $message = ('outcome={0} total_cpu_ms={1} total_wall_ms={2} stages={3}' -f
        [string]$script:UpdatePerformanceOutcome,
        [long][Math]::Round($totalCpu),
        [long][Math]::Round([double]$script:UpdatePerformanceWall.Elapsed.TotalMilliseconds),
        ($stageParts.ToArray() -join ','))
    $record = ('{0} {1}' -f
        [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ',[System.Globalization.CultureInfo]::InvariantCulture),
        $message)

    Write-UpdatePerformanceRecord -Line $record
    if (-not (Test-Path -LiteralPath $UpdatePerformanceFile)) {
        throw ('Performance telemetry record was not created: ' + $UpdatePerformanceFile)
    }

    if (Test-Path -LiteralPath $UpdatePerformanceErrorFile) {
        Remove-Item -LiteralPath $UpdatePerformanceErrorFile -Force -ErrorAction SilentlyContinue
    }

    # Main runtime-log copy is convenience-only.
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level INFO -Component 'performance' -Message $message
    }
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

function Publish-UpdateUiState {
    if (-not (Test-Path -LiteralPath $StateKvFile)) { throw 'Build state.kv is missing; refusing UI publication.' }
    $text = Read-TravelAssistantSharedText -Path $StateKvFile
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Build state.kv is empty; refusing UI publication.' }
    if ($text -notmatch '(?m)^OpportunityCount=' -or $text -notmatch '(?m)^UIFreshestMarketSourceTimestamp=') {
        throw 'Build state.kv is incomplete after FilterState; refusing UI publication.'
    }
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $name = 'ui-state-{0}-{1}.kv' -f $epoch, [Guid]::NewGuid().ToString('N')
    $text = ($text.TrimEnd() + "`nUIGeneration=" + $name + "`n")
    Write-TravelAssistantAtomicText -Path (Join-Path $GeneratedDir $name) -Text $text
    $script:PendingUiGeneration = $epoch + '|' + $name
}

function Write-UpdateHeartbeat {
    New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
    if ([string]::IsNullOrWhiteSpace($script:PendingUiGeneration)) { throw 'No complete UI generation is ready to publish.' }
    Write-TravelAssistantAtomicText -Path $HeartbeatFile -Text $script:PendingUiGeneration
}

function Remove-OldUiStateGenerations {
    # Only disposable generated snapshots, never observations/cycles or the legacy
    # fallback. Keep recent generations so an in-flight reader can finish safely.
    try {
        $currentName = ($script:PendingUiGeneration -split '\|',2)[1]
        $cutoff = [DateTime]::UtcNow.AddMinutes(-10)
        $files = @(Get-ChildItem -LiteralPath $GeneratedDir -File | Where-Object {
            $_.Name -match '^ui-state-\d+-[a-f0-9]{32}\.kv$'
        } | Sort-Object LastWriteTimeUtc -Descending)
        foreach ($file in @($files | Select-Object -Skip 8)) {
            if ($file.Name -ne $currentName -and $file.LastWriteTimeUtc -lt $cutoff) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { } # Cleanup must never prevent collection or price refresh.
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
    $timer = New-UpdateStageTimer -Name (Get-UpdateFailureComponent $ErrorPath)
    try {
        & $Path
        if ($ClearErrorOnSuccess) { Clear-CompactFailure -Path $ErrorPath }
        else { Mirror-ChildOwnedFailure -ErrorPath $ErrorPath }
    } catch { Write-CompactFailure -Path $ErrorPath -Message $_.Exception.ToString() }
    finally { Complete-UpdateStageTimer -Timer $timer }
}

function Invoke-HistoryMaintenance {
    param([string]$Phase)
    if (-not (Test-Path -LiteralPath $ObservationHistory)) { return }
    $timer = New-UpdateStageTimer -Name ('history-' + ([string]$Phase).ToLowerInvariant())
    try {
        & $ObservationHistory -Phase $Phase
        Clear-CompactFailure -Path $HistoryErrorFile
    } catch {
        Write-CompactFailure -Path $HistoryErrorFile -Message $_.Exception.ToString()
    } finally { Complete-UpdateStageTimer -Timer $timer }
}

try {
    $mutexWaitMilliseconds = [int]([Math]::Min(300000,[Math]::Max(0,$MutexWaitSeconds * 1000)))
    try {
        $acquired = $mutex.WaitOne($mutexWaitMilliseconds)
    } catch [System.Threading.AbandonedMutexException] {
        # WaitOne transfers ownership to this thread before throwing for an abandoned mutex.
        # Treat it as acquired so a crashed predecessor cannot poison subsequent updates.
        $acquired = $true
    }
    if (-not $acquired) {
        if ($MutexWaitSeconds -gt 0) {
            throw ('Timed out waiting {0}s for the Travel Assistant updater mutex.' -f $MutexWaitSeconds)
        }
        exit 0
    }
    $UpdatePerformanceActive = $true
    $UpdatePerformanceOutcome = 'running'

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

    # PreUpdate already performs the one-time history cleanup and the hourly prune.
    # The legacy PostUpdate path now returns without additional work, so avoid a
    # second script launch and state/settings parse on every one-minute heartbeat.

    # Canonical catalog maintenance is intentionally NOT part of this heartbeat;
    # LocalCatalog only projects committed/provider metadata already on disk.
    Invoke-FailSoftScript -Path $LocalCatalog -ErrorPath $LocalCatalogErrorFile

    # Persist engine-state schema normalization even when collection failed and the
    # UI is temporarily operating from the last known state.
    Invoke-FailSoftScript -Path $EngineStateSchema -ErrorPath $EngineStateSchemaErrorFile

    $finalizerTimer = New-UpdateStageTimer -Name 'finalize-state'
    try {
        & $Finalizer
        if (-not $?) { throw 'FinalizeState returned failure.' }
    } finally { Complete-UpdateStageTimer -Timer $finalizerTimer }

    # TravelContext owns its diagnostic file because it catches transient API failures
    # internally while preserving the last successful destination/bar context.
    if ($Action -eq 'Update') { Invoke-FailSoftScript -Path $TravelContext -ErrorPath $TravelContextErrorFile -ClearErrorOnSuccess $false }

    # Current perks are active-state evidence. Refresh the persisted local capacity
    # profile before opportunity economics so peace/war faction loadout changes do
    # not leave the inventory quantity stuck on an older synced value.
    if ($Action -eq 'Update') { Invoke-FailSoftScript -Path $CurrentCapacityRefresh -ErrorPath $CurrentCapacityRefreshErrorFile }

    # Use the same retained real observation stream as the inline graph to align the
    # active restock/sellout phase before recurring Safe/Best windows are calculated.
    Invoke-FailSoftScript -Path $CycleAnchorReconciler -ErrorPath $CycleAnchorReconcilerErrorFile

    # Keep the route optimizer as a background decision/pricing-priority model.

    # Primary presentation is the sortable opportunity surface.
    Invoke-FailSoftScript -Path $OpportunityState -ErrorPath $OpportunityStateErrorFile

    # Refine every projected candidate with conservative safe-window bounds and
    # empirical best-hit segments. This stage is local-only and writes absolute
    # times so Rainmeter can update leave/countdown guidance every second.
    Invoke-FailSoftScript -Path $WindowPlan -ErrorPath $WindowPlanErrorFile

    # Classify price variability from recent recurring evidence rather than one old
    # anomaly. This controls card cost coloring and whether Take gets a 5% buffer.
    Invoke-FailSoftScript -Path $PriceVariationRefiner -ErrorPath $PriceVariationRefinerErrorFile

    # OpportunityState must always leave an explicit projection, even when the
    # correct result is zero rows. Detect silent early-return states immediately.
    $hasOpportunityProjection = $false
    try {
        if (Test-Path -LiteralPath $StateKvFile) {
            $hasOpportunityProjection = [bool](Select-String -LiteralPath $StateKvFile -Pattern '^OpportunityCount=' -Quiet)
        }
    } catch { $hasOpportunityProjection = $false }
    if (-not $hasOpportunityProjection) {
        Write-CompactFailure -Path $OpportunityStateErrorFile -Message 'OpportunityState completed without writing OpportunityCount to build state.kv.'
    }

    if (Test-Path -LiteralPath $FilterState) {
        $filterTimer = New-UpdateStageTimer -Name 'filter-state'
        try { & $FilterState; Clear-CompactFailure -Path $FilterStateErrorFile }
        catch { Write-CompactFailure -Path $FilterStateErrorFile -Message $_.Exception.ToString() }
        finally { Complete-UpdateStageTimer -Timer $filterTimer }
    }

    # state.kv is a private build artifact. Only this final publication touches the
    # Rainmeter-consumed UI state. A failed final publish leaves the previous complete
    # UI generation visible rather than exposing a partial/intermediate projection.
    $publishTimer = New-UpdateStageTimer -Name 'publish-ui'
    try { Publish-UpdateUiState }
    finally { Complete-UpdateStageTimer -Timer $publishTimer }

    # Heartbeat represents successful final UI publication, not merely collection or
    # an intermediate stage. Analytics and resale work below cannot make UI look fresh
    # unless the complete immutable snapshot was successfully selected first.
    $heartbeatTimer = New-UpdateStageTimer -Name 'publish-heartbeat'
    try { Write-UpdateHeartbeat }
    finally { Complete-UpdateStageTimer -Timer $heartbeatTimer }

    $cleanupTimer = New-UpdateStageTimer -Name 'generation-cleanup'
    try { Remove-OldUiStateGenerations }
    finally { Complete-UpdateStageTimer -Timer $cleanupTimer }

    if ($Action -eq 'Update') {
        Invoke-FailSoftScript -Path $CycleAnalytics -ErrorPath $CycleAnalyticsErrorFile
        # Shadow forecast only: measure recent direction/correlation and score the
        # next-cycle prediction. It does not alter WindowPlan or current card timing.
        Invoke-FailSoftScript -Path $TrendForecast -ErrorPath $TrendForecastErrorFile
    }

    if ($Action -eq 'Update' -and (Test-Path -LiteralPath $ResaleQueue)) {
        try {
            if (Test-Path -LiteralPath $ResalePriority) {
                $resalePriorityTimer = New-UpdateStageTimer -Name 'resale-priority'
                try { & $ResalePriority }
                finally { Complete-UpdateStageTimer -Timer $resalePriorityTimer }
            }
            $resaleQueueTimer = New-UpdateStageTimer -Name 'resale-queue'
            try { & $ResaleQueue }
            finally { Complete-UpdateStageTimer -Timer $resaleQueueTimer }
            if (Test-Path -LiteralPath $ResaleQueueErrorFile) {
                try {
                    $queueState = Get-Content -LiteralPath (Join-Path $RuntimeDir 'engine-state.json') -Raw | ConvertFrom-Json
                    if ($queueState.PSObject.Properties['resaleQueue'] -and [string]$queueState.resaleQueue.status -ne 'ERROR') { Clear-CompactFailure -Path $ResaleQueueErrorFile }
                } catch { }
            } else { Clear-CompactFailure -Path $ResaleQueueErrorFile }
        } catch { Write-CompactFailure -Path $ResaleQueueErrorFile -Message $_.Exception.ToString() }
    }

    if (Get-Command Clear-TravelAssistantLatestError -ErrorAction SilentlyContinue) { Clear-TravelAssistantLatestError -Component 'run-update' }
    $UpdatePerformanceOutcome = 'success'
    # Do not call exit here. The finally block owns performance telemetry, process
    # disposal, and explicit mutex release; falling through returns success naturally.
} catch {
    $UpdatePerformanceOutcome = 'error'
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component 'run-update' -Message (Format-TravelAssistantErrorRecord $_)
    }
    throw
} finally {
    if ($acquired) {
        try {
            Write-UpdatePerformanceSummary
        } catch {
            try {
                New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
                $performanceError = $_.Exception.ToString()
                [System.IO.File]::WriteAllText(
                    $UpdatePerformanceErrorFile,
                    $performanceError,
                    [System.Text.UTF8Encoding]::new($false)
                )
                if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
                    Write-TravelAssistantLog -Level WARN -Component 'performance' -Message $performanceError
                }
            } catch { }
        }
    }
    if ($null -ne $UpdatePerformanceProcess) { try { $UpdatePerformanceProcess.Dispose() } catch { } }
    if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
    $mutex.Dispose()
}
