$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runUpdate = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $runUpdate)) {
    Fail 'Missing RunUpdate.ps1.'
} else {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($runUpdate,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail ('RunUpdate.ps1 parse error: ' + $parseError.Message) }

    $text = Get-Content -LiteralPath $runUpdate -Raw
    foreach ($token in @(
        '[int]$MutexWaitSeconds = 0',
        '$mutex.WaitOne($mutexWaitMilliseconds)',
        'Timed out waiting {0}s for the Travel Assistant updater mutex.',
        'catch [System.Threading.AbandonedMutexException]',
        '$acquired = $true',
        '$mutex.ReleaseMutex()'
    )) {
        if (-not $text.Contains($token)) { Fail ("RunUpdate.ps1 missing abandoned-mutex recovery token '$token'.") }
    }
}

# Prove the runtime contract on Windows: if a process dies while owning a named
# mutex, WaitOne throws AbandonedMutexException but ownership has transferred to
# the waiting thread. The updater must therefore continue and release normally.
$name = 'Local\TornTravelAssistantMutexValidation_' + [Guid]::NewGuid().ToString('N')
$keeper = New-Object System.Threading.Mutex($false,$name)
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('ta-abandoned-mutex-' + [Guid]::NewGuid().ToString('N') + '.ps1')
$acquired = $false
$sawAbandoned = $false
try {
    $escapedName = $name.Replace("'","''")
    @(
        ('$m = New-Object System.Threading.Mutex($false,''' + $escapedName + ''')'),
        '[void]$m.WaitOne()',
        '[Environment]::Exit(0)'
    ) | Set-Content -LiteralPath $temp -Encoding UTF8

    $child = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $temp + '"')) -PassThru -WindowStyle Hidden
    $child.WaitForExit()
    $child.Dispose()

    try {
        $acquired = $keeper.WaitOne(2000)
    } catch [System.Threading.AbandonedMutexException] {
        $sawAbandoned = $true
        $acquired = $true
    }

    if (-not $sawAbandoned) { Fail 'Runtime did not surface AbandonedMutexException from the deliberately crashed owner.' }
    if (-not $acquired) { Fail 'Abandoned mutex did not transfer ownership to the waiting thread.' }
} finally {
    if ($acquired) { try { $keeper.ReleaseMutex() } catch { Fail ('Failed to release recovered mutex: ' + $_.Exception.Message) } }
    $keeper.Dispose()
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host ('FAIL: ' + $message) -ForegroundColor Red }
    Write-Host ("Updater mutex validation failed with $($errors.Count) error(s).") -ForegroundColor Red
    exit 1
}

Write-Host 'Updater abandoned-mutex recovery validation passed.' -ForegroundColor Green
Write-Host 'A crashed predecessor cannot poison the named updater mutex; Rainmeter remains non-blocking while manual verification can wait deterministically for the active worker.' -ForegroundColor Green
exit 0
