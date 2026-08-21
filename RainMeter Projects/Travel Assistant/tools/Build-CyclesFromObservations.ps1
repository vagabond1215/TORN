param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Read-ObservationJsonl {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Input file not found: $Path" }

    $rows = New-Object System.Collections.Generic.List[object]
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $row = $line | ConvertFrom-Json }
        catch { throw "Invalid JSON at line ${lineNumber}: $($_.Exception.Message)" }

        foreach ($name in @('schemaVersion','timestamp','country','itemId','stock','foreignPrice','source','sourceTimestamp')) {
            if (-not $row.PSObject.Properties[$name]) { throw "Observation line $lineNumber is missing '$name'." }
        }
        if ([int]$row.schemaVersion -ne 1) { throw "Observation line $lineNumber has unsupported schemaVersion." }
        if ([long]$row.timestamp -le 0) { throw "Observation line $lineNumber has invalid timestamp." }
        if ([long]$row.sourceTimestamp -lt 0) { throw "Observation line $lineNumber has invalid sourceTimestamp." }
        if ([int]$row.itemId -le 0) { throw "Observation line $lineNumber has invalid itemId." }
        if ([int]$row.stock -lt 0) { throw "Observation line $lineNumber has negative stock." }
        if ([long]$row.foreignPrice -lt 0) { throw "Observation line $lineNumber has negative foreignPrice." }
        if ([string]::IsNullOrWhiteSpace([string]$row.country)) { throw "Observation line $lineNumber has empty country." }
        if ([string]::IsNullOrWhiteSpace([string]$row.source)) { throw "Observation line $lineNumber has empty source." }
        $rows.Add($row)
    }
    return $rows.ToArray()
}

function Write-JsonLinesAtomic {
    param([string]$Path, [object[]]$Rows)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $tmp = $Path + '.tmp'
    $writer = New-Object System.IO.StreamWriter($tmp, $false, [System.Text.UTF8Encoding]::new($false))
    try {
        foreach ($row in $Rows) {
            $writer.WriteLine(($row | ConvertTo-Json -Compress -Depth 10))
        }
    } finally {
        $writer.Dispose()
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

$observations = @(Read-ObservationJsonl -Path $InputPath)
$cycles = New-Object System.Collections.Generic.List[object]

$groups = $observations | Group-Object { ('{0}|{1}' -f [string]$_.country, [int]$_.itemId) }
foreach ($group in $groups) {
    $rows = @($group.Group | Sort-Object @{ Expression = { [long]$_.timestamp } }, @{ Expression = { [long]$_.sourceTimestamp } })
    $previousStock = $null
    $lastSoldOutAt = 0L
    $active = $null

    foreach ($row in $rows) {
        $stock = [int]$row.stock
        $ts = [long]$row.timestamp

        if ($null -ne $previousStock) {
            if ([int]$previousStock -eq 0 -and $stock -gt 0) {
                $active = [pscustomobject]@{
                    previousSoldOutAt = $lastSoldOutAt
                    restockAt = $ts
                    restockQuantity = $stock
                    foreignPrice = [long]$row.foreignPrice
                    source = [string]$row.source
                }
            } elseif ([int]$previousStock -gt 0 -and $stock -eq 0) {
                $lastSoldOutAt = $ts
                if ($null -ne $active -and $ts -gt [long]$active.restockAt) {
                    $delay = 0L
                    if ([long]$active.previousSoldOutAt -gt 0 -and [long]$active.restockAt -gt [long]$active.previousSoldOutAt) {
                        $delay = [long]$active.restockAt - [long]$active.previousSoldOutAt
                    }
                    $cycles.Add([pscustomobject]@{
                        schemaVersion = 1
                        country = [string]$row.country
                        itemId = [int]$row.itemId
                        foreignPrice = [long]$active.foreignPrice
                        restockAt = [long]$active.restockAt
                        restockQuantity = [int]$active.restockQuantity
                        soldOutAt = $ts
                        availabilitySeconds = [long]($ts - [long]$active.restockAt)
                        previousSoldOutAt = [long]$active.previousSoldOutAt
                        restockDelaySeconds = $delay
                        source = [string]$active.source
                    })
                }
                $active = $null
            }
        }

        $previousStock = $stock
    }
}

$dedup = New-Object System.Collections.Generic.List[object]
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($cycle in @($cycles | Sort-Object country, itemId, restockAt, soldOutAt)) {
    $key = ('{0}|{1}|{2}|{3}|{4}' -f [string]$cycle.country, [int]$cycle.itemId, [long]$cycle.restockAt, [long]$cycle.soldOutAt, [long]$cycle.foreignPrice)
    if ($seen.Add($key)) { $dedup.Add($cycle) }
}

Write-JsonLinesAtomic -Path $OutputPath -Rows $dedup.ToArray()
Write-Host ("Built {0} completed cycle(s) from {1} observation(s)." -f $dedup.Count, $observations.Count) -ForegroundColor Green
Write-Host ("Output: {0}" -f (Resolve-Path -LiteralPath $OutputPath).Path)
exit 0
