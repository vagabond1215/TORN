param(
    [ValidateRange(1,1000)]
    [int]$Last = 60
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PerformanceFile = Join-Path $ProjectRoot 'data\runtime\update-performance.log'
$LogFile = Join-Path $ProjectRoot 'data\runtime\logs\travel-assistant.log'

function Get-PerformancePercentile {
    param([double[]]$Values,[double]$Percentile)
    if ($null -eq $Values -or $Values.Count -eq 0) { return 0.0 }
    $sorted = [double[]]@($Values | Sort-Object)
    $rank = [Math]::Ceiling($Percentile * $sorted.Count) - 1
    $index = [Math]::Max(0,[Math]::Min($sorted.Count - 1,[int]$rank))
    return [double]$sorted[$index]
}

$sources = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $PerformanceFile) {
    [void]$sources.Add([pscustomobject]@{
        Path = $PerformanceFile
        Pattern = '^\S+\s+outcome=(\S+)\s+total_cpu_ms=(\d+)\s+total_wall_ms=(\d+)\s+stages=(.*)$'
    })
}
if (Test-Path -LiteralPath $LogFile) {
    [void]$sources.Add([pscustomobject]@{
        Path = $LogFile
        Pattern = '\[performance\]\s+outcome=(\S+)\s+total_cpu_ms=(\d+)\s+total_wall_ms=(\d+)\s+stages=(.*)$'
    })
}
if ($sources.Count -eq 0) {
    Write-Host 'No updater performance or runtime log files are present yet.' -ForegroundColor Yellow
    exit 2
}

$updates = New-Object System.Collections.Generic.List[object]
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($source in @($sources)) {
    foreach ($line in [System.IO.File]::ReadLines([string]$source.Path)) {
        $match = [regex]::Match($line,[string]$source.Pattern)
        if (-not $match.Success) { continue }

        $stageRows = New-Object System.Collections.Generic.List[object]
        $stageText = [string]$match.Groups[4].Value
        foreach ($part in @($stageText -split ',')) {
            $stageMatch = [regex]::Match($part.Trim(),'^([^:]+):(\d+)cpu/(\d+)wall$')
            if (-not $stageMatch.Success) { continue }
            [void]$stageRows.Add([pscustomobject]@{
                Stage = [string]$stageMatch.Groups[1].Value
                CpuMs = [double]$stageMatch.Groups[2].Value
                WallMs = [double]$stageMatch.Groups[3].Value
            })
        }

        $fingerprint = ('{0}|{1}|{2}|{3}' -f
            [string]$match.Groups[1].Value,
            [string]$match.Groups[2].Value,
            [string]$match.Groups[3].Value,
            $stageText)
        if (-not $seen.Add($fingerprint)) { continue }

        [void]$updates.Add([pscustomobject]@{
            Outcome = [string]$match.Groups[1].Value
            TotalCpuMs = [double]$match.Groups[2].Value
            TotalWallMs = [double]$match.Groups[3].Value
            Stages = $stageRows.ToArray()
        })
    }
}

if ($updates.Count -eq 0) {
    Write-Host 'No updater performance samples are present yet. Complete one deterministic or normal update after pulling the telemetry fix.' -ForegroundColor Yellow
    exit 2
}

$selected = @($updates | Select-Object -Last $Last)
$successful = @($selected | Where-Object { $_.Outcome -eq 'success' })
if ($successful.Count -eq 0) {
    Write-Host "Found $($selected.Count) performance sample(s), but none completed successfully." -ForegroundColor Yellow
    exit 2
}

$totalCpuValues = [double[]]@($successful | ForEach-Object { [double]$_.TotalCpuMs })
$totalWallValues = [double[]]@($successful | ForEach-Object { [double]$_.TotalWallMs })
$avgCpu = [double](($totalCpuValues | Measure-Object -Average).Average)
$avgWall = [double](($totalWallValues | Measure-Object -Average).Average)
$p95Cpu = Get-PerformancePercentile -Values $totalCpuValues -Percentile 0.95
$p95Wall = Get-PerformancePercentile -Values $totalWallValues -Percentile 0.95
$logicalProcessors = [Math]::Max(1,[Environment]::ProcessorCount)
$coreEquivalent = 100.0 * $avgCpu / 60000.0
$machineEquivalent = $coreEquivalent / $logicalProcessors

Write-Host ''
Write-Host ('Updater performance - last {0} successful sample(s)' -f $successful.Count) -ForegroundColor Cyan
Write-Host ('Average pwsh CPU: {0:N0} ms/update | p95: {1:N0} ms' -f $avgCpu,$p95Cpu)
Write-Host ('Average wall time: {0:N0} ms/update | p95: {1:N0} ms' -f $avgWall,$p95Wall)
Write-Host ('At a 60s cadence: {0:N2}% of one CPU core, about {1:N3}% of this {2}-logical-processor machine (pwsh process only).' -f $coreEquivalent,$machineEquivalent,$logicalProcessors)
Write-Host ''

$allStages = New-Object System.Collections.Generic.List[object]
foreach ($update in $successful) {
    foreach ($stage in @($update.Stages)) { [void]$allStages.Add($stage) }
}

$totalSuccessfulCpu = [Math]::Max(1.0,[double](($totalCpuValues | Measure-Object -Sum).Sum))
$summary = foreach ($group in @($allStages | Group-Object Stage)) {
    $cpu = [double[]]@($group.Group | ForEach-Object { [double]$_.CpuMs })
    $wall = [double[]]@($group.Group | ForEach-Object { [double]$_.WallMs })
    $cpuSum = [double](($cpu | Measure-Object -Sum).Sum)
    [pscustomobject]@{
        Stage = [string]$group.Name
        Runs = [int]$group.Count
        AvgCpuMs = [Math]::Round([double](($cpu | Measure-Object -Average).Average),1)
        P95CpuMs = [Math]::Round((Get-PerformancePercentile -Values $cpu -Percentile 0.95),1)
        MaxCpuMs = [Math]::Round([double](($cpu | Measure-Object -Maximum).Maximum),1)
        AvgWallMs = [Math]::Round([double](($wall | Measure-Object -Average).Average),1)
        P95WallMs = [Math]::Round((Get-PerformancePercentile -Values $wall -Percentile 0.95),1)
        CpuSharePct = [Math]::Round((100.0 * $cpuSum / $totalSuccessfulCpu),1)
    }
}

$summary |
    Sort-Object @{Expression='AvgCpuMs';Descending=$true}, @{Expression='P95CpuMs';Descending=$true} |
    Format-Table Stage,Runs,AvgCpuMs,P95CpuMs,MaxCpuMs,AvgWallMs,P95WallMs,CpuSharePct -AutoSize

Write-Host ''
Write-Host 'CPU time is the pwsh updater process only; network wait can inflate wall time without inflating CPU time.' -ForegroundColor DarkGray
Write-Host 'Use the highest AvgCpuMs / P95CpuMs stages as the next optimization targets.' -ForegroundColor DarkGray
exit 0
