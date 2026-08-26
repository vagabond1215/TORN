$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$helperPath = Join-Path $ProjectRoot '@Resources\Scripts\AtomicFile.ps1'
$projectionPath = Join-Path $ProjectRoot '@Resources\Scripts\ProjectCollectedState.ps1'
$finalizerPath = Join-Path $ProjectRoot '@Resources\Scripts\FinalizeState.ps1'
$runUpdatePath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($assetPath in @($helperPath,$projectionPath,$finalizerPath,$runUpdatePath)) {
    if (-not (Test-Path -LiteralPath $assetPath)) { Fail "Missing atomic-state asset: $assetPath" }
}

if ($errors.Count -eq 0) {
    foreach ($assetPath in @($helperPath,$projectionPath,$finalizerPath,$runUpdatePath)) {
        $tokens=$null; $parseErrors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($assetPath,[ref]$tokens,[ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) { Fail "$([System.IO.Path]::GetFileName($assetPath)) parse error: $($parseError.Message)" }
    }

    $helper = Get-Content -LiteralPath $helperPath -Raw
    $projection = Get-Content -LiteralPath $projectionPath -Raw
    $finalizer = Get-Content -LiteralPath $finalizerPath -Raw
    $runUpdate = Get-Content -LiteralPath $runUpdatePath -Raw

    foreach ($token in @(
        'Get-TravelAssistantAtomicMutexName',
        'New-TravelAssistantAtomicTempPath',
        'New-TravelAssistantAtomicBackupPath',
        'Test-TravelAssistantAtomicRetryableException',
        'Publish-TravelAssistantAtomicTempFile',
        'Write-TravelAssistantAtomicText',
        'Write-TravelAssistantAtomicLines',
        '[Guid]::NewGuid()',
        'System.Threading.Mutex',
        '[System.IO.File]::Replace',
        '[System.IO.File]::Move',
        'RetryCount = 40',
        'InnerException',
        'AbandonedMutexException'
    )) {
        if (-not $helper.Contains($token)) { Fail "AtomicFile.ps1 missing '$token'." }
    }
    if ($helper.Contains('$Path + ''.tmp''')) { Fail 'AtomicFile.ps1 must not use a shared fixed destination.tmp file.' }
    if ($helper.Contains('[System.IO.File]::Replace($TempPath, $Path, $null')) { Fail 'AtomicFile.ps1 must not pass a null backup path to File.Replace.' }
    if ($helper.Contains('[System.IO.File]::Replace($TempPath, $Path, $backupPath, $true)')) { Fail 'AtomicFile.ps1 must not use the runtime-sensitive four-argument File.Replace overload.' }
    if (-not $helper.Contains('[System.IO.File]::Replace($TempPath, $Path, $backupPath)')) { Fail 'AtomicFile.ps1 must use the portable three-argument File.Replace overload.' }
    if (-not $helper.Contains('Atomic backup path generation returned an empty path.')) { Fail 'AtomicFile.ps1 must explicitly guard against an empty generated backup path.' }
    if (-not $helper.Contains('$current = $current.InnerException')) { Fail 'AtomicFile.ps1 must walk wrapped InnerException values when classifying retryable Windows file locks.' }

    foreach ($pair in @(
        [pscustomobject]@{name='ProjectCollectedState.ps1'; text=$projection},
        [pscustomobject]@{name='FinalizeState.ps1'; text=$finalizer}
    )) {
        if (-not $pair.text.Contains(". (Join-Path `$PSScriptRoot 'AtomicFile.ps1')")) { Fail "$($pair.name) must load AtomicFile.ps1." }
        if (-not $pair.text.Contains('Write-TravelAssistantAtomicLines')) { Fail "$($pair.name) must publish state through the shared atomic writer." }
        if ($pair.text.Contains("Move-Item -LiteralPath `$tmp -Destination `$Path -Force")) { Fail "$($pair.name) must not retain the fixed-temp Move-Item publication path." }
    }

    if (-not $runUpdate.Contains("`$AtomicFileScript = Join-Path `$PSScriptRoot 'AtomicFile.ps1'")) { Fail 'RunUpdate.ps1 must resolve AtomicFile.ps1 for heartbeat publication.' }
    if (-not $runUpdate.Contains('Write-TravelAssistantAtomicText -Path $HeartbeatFile -Text $epoch')) { Fail 'RunUpdate.ps1 heartbeat must use the shared atomic writer.' }
    if ($runUpdate.Contains("`$tmp = `$HeartbeatFile + '.tmp'")) { Fail 'RunUpdate.ps1 must not retain the fixed heartbeat .tmp publication path.' }

    # Exercise the helper locally. This catches Windows PowerShell 5.1 and PowerShell 7
    # runtime differences and confirms repeated replacement leaves one complete destination.
    try {
        . $helperPath
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ('TravelAssistantAtomicTest_' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        try {
            $target = Join-Path $work 'state.kv'
            for ($i=1; $i -le 25; $i++) {
                Write-TravelAssistantAtomicLines -Path $target -Lines @('Generation=' + [string]$i, 'Complete=1')
            }
            $actual = Get-Content -LiteralPath $target -Raw
            if (-not $actual.Contains('Generation=25') -or -not $actual.Contains('Complete=1')) { Fail 'Atomic helper did not publish the final complete generation.' }

            # On Windows, deliberately hold the destination without FileShare.Delete.
            # File.Replace then throws a MethodInvocationException wrapping IOException.
            # The helper must recognize that wrapped sharing violation, retry, and
            # publish successfully after the short lock is released.
            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and (Get-Command Start-Job -ErrorAction SilentlyContinue)) {
                $ready = Join-Path $work 'lock.ready'
                $lockJob = Start-Job -ArgumentList $target,$ready -ScriptBlock {
                    param($lockedTarget,$readyPath)
                    $stream = [System.IO.File]::Open(
                        $lockedTarget,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::Read
                    )
                    try {
                        [System.IO.File]::WriteAllText($readyPath,'ready')
                        Start-Sleep -Milliseconds 800
                    } finally {
                        $stream.Dispose()
                    }
                }
                try {
                    $deadline = [DateTime]::UtcNow.AddSeconds(10)
                    while (-not (Test-Path -LiteralPath $ready) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
                    if (-not (Test-Path -LiteralPath $ready)) {
                        Fail 'Atomic lock-contention test could not establish the child-process file lock.'
                    } else {
                        Write-TravelAssistantAtomicLines -Path $target -Lines @('Generation=after-lock','Complete=1') -RetryCount 40 -RetryDelayMilliseconds 50
                        $afterLock = Get-Content -LiteralPath $target -Raw
                        if (-not $afterLock.Contains('Generation=after-lock') -or -not $afterLock.Contains('Complete=1')) {
                            Fail 'Atomic helper did not recover from a transient wrapped sharing violation.'
                        }
                    }
                } finally {
                    if ($null -ne $lockJob) {
                        Wait-Job -Job $lockJob -Timeout 5 -ErrorAction SilentlyContinue | Out-Null
                        Stop-Job -Job $lockJob -ErrorAction SilentlyContinue
                        Remove-Job -Job $lockJob -Force -ErrorAction SilentlyContinue
                    }
                    Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
                }
            }

            $tempOrphans = @(Get-ChildItem -LiteralPath $work -Filter '*.tmp' -Force -ErrorAction SilentlyContinue)
            $backupOrphans = @(Get-ChildItem -LiteralPath $work -Filter '*.bak' -Force -ErrorAction SilentlyContinue)
            if ($tempOrphans.Count -gt 0) { Fail 'Atomic helper left orphan temporary files after successful writes.' }
            if ($backupOrphans.Count -gt 0) { Fail 'Atomic helper left orphan backup files after successful writes.' }
        } finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { Fail ('Atomic helper runtime test failed: ' + $_.Exception.Message) }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "FAIL: $validationError" -ForegroundColor Red }
    Write-Host "Atomic state-write validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Atomic state-write validation passed.' -ForegroundColor Green
Write-Host 'Critical state and heartbeat publishers use unique temporary files, legal unique backup paths, per-destination cross-process mutexes, portable File.Replace/File.Move publication, and wrapped sharing-violation retries.'
exit 0
