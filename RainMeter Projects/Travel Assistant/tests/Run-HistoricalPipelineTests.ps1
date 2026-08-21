$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Builder = Join-Path $ProjectRoot 'tools\Build-CyclesFromObservations.ps1'
$Fixture = Join-Path $PSScriptRoot 'fixtures\normalized-observations.sample.jsonl'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TravelAssistant-HistoryTest-' + [Guid]::NewGuid().ToString('N'))
$tempCycles = Join-Path $tempRoot 'cycles.jsonl'

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    & $Builder -InputPath $Fixture -OutputPath $tempCycles
    if ($LASTEXITCODE -ne 0) { throw "Cycle builder exited with code $LASTEXITCODE." }

    $cycles = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content -LiteralPath $tempCycles) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $cycles.Add(($line | ConvertFrom-Json))
    }

    Assert-Equal 'Completed cycle count' $cycles.Count 2
    Assert-Equal 'First restock timestamp' ([long]$cycles[0].restockAt) 1787000100
    Assert-Equal 'First actual sellout timestamp' ([long]$cycles[0].soldOutAt) 1787000300
    Assert-Equal 'First availability duration' ([long]$cycles[0].availabilitySeconds) 200
    Assert-Equal 'First cycle has no prior restock delay evidence' ([long]$cycles[0].restockDelaySeconds) 0

    Assert-Equal 'Second previous actual sellout' ([long]$cycles[1].previousSoldOutAt) 1787000300
    Assert-Equal 'Second restock timestamp' ([long]$cycles[1].restockAt) 1787001200
    Assert-Equal 'Second restock delay' ([long]$cycles[1].restockDelaySeconds) 900
    Assert-Equal 'Second actual sellout timestamp' ([long]$cycles[1].soldOutAt) 1787001500
    Assert-Equal 'Second availability duration' ([long]$cycles[1].availabilitySeconds) 300
    Assert-Equal 'Second cycle preserves restock foreign price' ([long]$cycles[1].foreignPrice) 742000

    Write-Host 'Historical observation -> completed-cycle pipeline passed.' -ForegroundColor Green
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
