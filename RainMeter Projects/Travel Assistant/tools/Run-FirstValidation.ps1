param(
    [switch]$InstallSkin,
    [switch]$SkipLiveProviderChecks
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RuntimeValidationDir = Join-Path $ProjectRoot 'data\runtime\validation'
$RunAllTests = Join-Path $ProjectRoot 'tests\Run-All.ps1'
$LiveValidator = Join-Path $PSScriptRoot 'Validate-LiveEnvironment.ps1'
$Installer = Join-Path $ProjectRoot 'Install.ps1'

New-Item -ItemType Directory -Force -Path $RuntimeValidationDir | Out-Null
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
$reportPath = Join-Path $RuntimeValidationDir ("first-validation-$stamp.txt")
$lines = New-Object System.Collections.Generic.List[string]

function Add-ReportLine {
    param([string]$Text)
    $script:lines.Add($Text)
    Write-Host $Text
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Add-ReportLine ''
    Add-ReportLine ("=== {0} ===" -f $Name)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        if (-not $?) { throw "$Name reported a PowerShell execution failure." }
        $watch.Stop()
        Add-ReportLine ("RESULT: PASS ({0:N0} ms)" -f $watch.Elapsed.TotalMilliseconds)
    } catch {
        $watch.Stop()
        Add-ReportLine ("RESULT: FAIL ({0:N0} ms)" -f $watch.Elapsed.TotalMilliseconds)
        Add-ReportLine ("ERROR: {0}" -f $_.Exception.Message)
        throw
    }
}

Add-ReportLine 'Travel Assistant first validation'
Add-ReportLine ("UTC: {0}" -f [DateTimeOffset]::UtcNow.ToString('o'))
Add-ReportLine ("Project: {0}" -f $ProjectRoot)
Add-ReportLine ("PowerShell: {0}" -f $PSVersionTable.PSVersion)
Add-ReportLine ("OS: {0}" -f [Environment]::OSVersion.VersionString)

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $git) {
    Push-Location $ProjectRoot
    try {
        $head = (& git rev-parse HEAD 2>$null | Select-Object -First 1)
        $branch = (& git branch --show-current 2>$null | Select-Object -First 1)
        $status = (& git status --short 2>$null | Out-String).Trim()
        Add-ReportLine ("Git branch: {0}" -f $branch)
        Add-ReportLine ("Git HEAD: {0}" -f $head)
        Add-ReportLine ("Worktree: {0}" -f $(if ([string]::IsNullOrWhiteSpace($status)) { 'clean' } else { 'dirty — inspect before committing validation fixes' }))
    } finally { Pop-Location }
} else {
    Add-ReportLine 'Git: unavailable in PATH'
}

try {
    Invoke-Step -Name 'Deterministic/static test suite' -Action {
        & $RunAllTests
        if ($LASTEXITCODE -ne 0) { throw "tests/Run-All.ps1 exited with code $LASTEXITCODE." }
    }

    if (-not $SkipLiveProviderChecks) {
        Invoke-Step -Name 'Bounded live provider/updater/environment check' -Action {
            & $LiveValidator -SkipTests
            if ($LASTEXITCODE -ne 0) { throw "Validate-LiveEnvironment.ps1 exited with code $LASTEXITCODE." }
        }
    } else {
        Add-ReportLine ''
        Add-ReportLine '=== Bounded live provider/updater/environment check ==='
        Add-ReportLine 'RESULT: SKIPPED by request'
    }

    if ($InstallSkin) {
        Invoke-Step -Name 'Non-destructive Rainmeter junction install' -Action {
            & $Installer
            if ($LASTEXITCODE -ne 0) { throw "Install.ps1 exited with code $LASTEXITCODE." }
        }
    } else {
        Add-ReportLine ''
        Add-ReportLine '=== Rainmeter junction install ==='
        Add-ReportLine 'RESULT: NOT RUN — rerun with -InstallSkin when ready'
    }

    Add-ReportLine ''
    Add-ReportLine 'Automated first-validation steps completed. Manual Rainmeter load/log/visual checks remain required.'
    Add-ReportLine 'See docs/WINDOWS_VALIDATION.md.'
} catch {
    Add-ReportLine ''
    Add-ReportLine 'Validation stopped at the first failing step. Preserve the report and console output; do not include API keys in defect reports.'
    [System.IO.File]::WriteAllLines($reportPath, @($lines), [System.Text.UTF8Encoding]::new($false))
    Write-Host ("Validation report: {0}" -f $reportPath) -ForegroundColor Yellow
    exit 1
}

[System.IO.File]::WriteAllLines($reportPath, @($lines), [System.Text.UTF8Encoding]::new($false))
Write-Host ("Validation report: {0}" -f $reportPath) -ForegroundColor Green
exit 0
