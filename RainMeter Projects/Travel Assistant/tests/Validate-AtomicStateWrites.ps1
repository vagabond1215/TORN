$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$helperPath = Join-Path $ProjectRoot '@Resources\Scripts\AtomicFile.ps1'
$projectionPath = Join-Path $ProjectRoot '@Resources\Scripts\ProjectCollectedState.ps1'
$finalizerPath = Join-Path $ProjectRoot '@Resources\Scripts\FinalizeState.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($helperPath,$projectionPath,$finalizerPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing atomic-state asset: $path" }
}

if ($errors.Count -eq 0) {
    foreach ($path in @($helperPath,$projectionPath,$finalizerPath)) {
        $tokens=$null; $parseErrors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) { Fail "$([System.IO.Path]::GetFileName($path)) parse error: $($parseError.Message)" }
    }

    $helper = Get-Content -LiteralPath $helperPath -Raw
    $projection = Get-Content -LiteralPath $projectionPath -Raw
    $finalizer = Get-Content -LiteralPath $finalizerPath -Raw

    foreach ($token in @(
        'Get-TravelAssistantAtomicMutexName',
        'New-TravelAssistantAtomicTempPath',
        'Publish-TravelAssistantAtomicTempFile',
        'Write-TravelAssistantAtomicText',
        'Write-TravelAssistantAtomicLines',
        '[Guid]::NewGuid()',
        'System.Threading.Mutex',
        '[System.IO.File]::Replace',
        '[System.IO.File]::Move',
        'RetryCount = 20',
        'AbandonedMutexException'
    )) {
        if (-not $helper.Contains($token)) { Fail "AtomicFile.ps1 missing '$token'." }
    }
    if ($helper.Contains("$Path + '.tmp'")) { Fail 'AtomicFile.ps1 must not use a shared fixed destination.tmp file.' }

    foreach ($pair in @(
        [pscustomobject]@{name='ProjectCollectedState.ps1'; text=$projection},
        [pscustomobject]@{name='FinalizeState.ps1'; text=$finalizer}
    )) {
        if (-not $pair.text.Contains(". (Join-Path `$PSScriptRoot 'AtomicFile.ps1')")) { Fail "$($pair.name) must load AtomicFile.ps1." }
        if (-not $pair.text.Contains('Write-TravelAssistantAtomicLines')) { Fail "$($pair.name) must publish state through the shared atomic writer." }
        if ($pair.text.Contains("Move-Item -LiteralPath `$tmp -Destination `$Path -Force")) { Fail "$($pair.name) must not retain the fixed-temp Move-Item publication path." }
    }

    # Exercise the helper locally. This catches PowerShell 5.1/.NET compatibility
    # issues and confirms repeated replacement leaves one complete destination.
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
            $orphans = @(Get-ChildItem -LiteralPath $work -Filter '*.tmp' -Force -ErrorAction SilentlyContinue)
            if ($orphans.Count -gt 0) { Fail 'Atomic helper left orphan temporary files after successful writes.' }
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
Write-Host 'Critical state publishers use unique temporary files, per-destination cross-process mutexes, File.Replace/File.Move, and bounded retry instead of fixed .tmp + Move-Item publication.'
exit 0
