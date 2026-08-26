$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $iniPath)) {
    Fail "Missing TravelAssistant.ini: $iniPath"
} else {
    $ini = Get-Content -LiteralPath $iniPath -Raw

    function Get-SectionBody([string]$Name) {
        return [regex]::Match(
            $ini,
            ('(?ms)^\[' + [regex]::Escape($Name) + '\]\s*(.*?)(?=^\[|\z)')
        ).Groups[1].Value
    }

    $updateBody = Get-SectionBody 'MeasureUpdate'
    if ([string]::IsNullOrWhiteSpace($updateBody)) {
        Fail 'Missing [MeasureUpdate] body.'
    } else {
        if ($updateBody -notmatch '(?im)^Program=pwsh\.exe\s*$') {
            Fail 'MeasureUpdate must launch PowerShell 7 via Program=pwsh.exe.'
        }
        if ($updateBody -match '(?im)^Program=powershell\.exe\s*$') {
            Fail 'MeasureUpdate must not launch Windows PowerShell 5.1.'
        }
        $expectedParameter = 'Parameter=-NoProfile -ExecutionPolicy Bypass -File "#@#Scripts\RunUpdate.ps1" -Action Update'
        if (-not $updateBody.Contains($expectedParameter)) {
            Fail 'MeasureUpdate must retain the RunUpdate.ps1 -Action Update command contract.'
        }
    }

    $pwshCount = ([regex]::Matches($ini, '(?im)^Program=pwsh\.exe\s*$')).Count
    if ($pwshCount -ne 1) {
        Fail "Exactly one Rainmeter RunCommand measure should use pwsh.exe during this controlled migration; found $pwshCount."
    }

    foreach ($section in @(
        'MeasureSettings',
        'MeasureFilterPopup',
        'MeasureItemViewer',
        'MeasureInlineGraph',
        'MeasurePreferenceAction'
    )) {
        $body = Get-SectionBody $section
        if ([string]::IsNullOrWhiteSpace($body)) {
            Fail "Missing [$section] body."
            continue
        }
        if ($body -notmatch '(?im)^Program=powershell\.exe\s*$') {
            Fail "$section must remain on Windows PowerShell during the updater-only runtime migration."
        }
        if ($body -match '(?im)^Program=pwsh\.exe\s*$') {
            Fail "$section was migrated to pwsh.exe prematurely; only MeasureUpdate is in scope."
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) {
        Write-Host "FAIL: $message" -ForegroundColor Red
    }
    Write-Host "Updater runtime validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Rainmeter updater runtime contract passed.' -ForegroundColor Green
Write-Host 'MeasureUpdate uses pwsh.exe; popup/filter/inline/preference helper measures remain on powershell.exe.' -ForegroundColor Green
exit 0
