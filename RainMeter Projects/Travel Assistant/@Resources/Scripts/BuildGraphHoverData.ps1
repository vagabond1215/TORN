param(
    [Parameter(Mandatory=$true)]
    [string]$MarketKey
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

if ($MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'MarketKey must be country:itemId.' }

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir=Join-Path $ProjectRoot 'data\runtime'
$SeedDir=Join-Path $ProjectRoot 'data\seed'
$GeneratedDir=Join-Path $ProjectRoot '@Resources\Generated'
$RuntimeObservationFile=Join-Path $RuntimeDir 'observations.jsonl'
$SeedObservationFile=Join-Path $SeedDir 'observations.jsonl'
$BandCount=48

function Get-HoverProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-HoverKv {
    param([string]$Path)
    $values=@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $eq=$line.IndexOf('=')
        if ($eq -le 0) { continue }
        $values[$line.Substring(0,$eq)]=$line.Substring($eq+1)
    }
    return $values
}

function Write-HoverKvAtomic {
    param([string]$Path,[hashtable]$Values)
    $tmp=$Path+'.tmp'
    $lines=@()
    foreach ($key in @($Values.Keys | Sort-Object)) {
        $value=([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines += ($key+'='+$value)
    }
    [System.IO.File]::WriteAllLines($tmp,[string[]]$lines,(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-HoverHistory {
    param([string]$Path,[string]$Country,[int]$ItemId)
    $rows=@()
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
    $countryNeedle='"country":"'+$Country+'"'
    $itemPattern='"itemId"\s*:\s*'+[regex]::Escape([string]$ItemId)+'(?=\s*[,}])'
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.IndexOf($countryNeedle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        if ($line -notmatch $itemPattern) { continue }
        try {
            $row=$line | ConvertFrom-Json
            $timestamp=[long](Get-HoverProperty $row 'timestamp')
            if ($timestamp -le 0) { continue }
            $source=[string](Get-HoverProperty $row 'source')
            if ($source -in @('history_bootstrap','history_repair_baseline')) { continue }
            $rows += [pscustomobject]@{ timestamp=$timestamp; stock=[long](Get-HoverProperty $row 'stock') }
        } catch { }
    }
    return $rows
}

function Compress-HoverHistory {
    param([object[]]$Rows)
    $out=@(); $previous=$null
    foreach ($row in @($Rows | Sort-Object timestamp)) {
        $stock=[long](Get-HoverProperty $row 'stock')
        if ($null -eq $previous -or [long]$previous -ne $stock) {
            $out += [pscustomobject]@{ timestamp=[long](Get-HoverProperty $row 'timestamp'); stock=$stock }
            $previous=$stock
        }
    }
    return @($out)
}

function Get-HoverStockAt {
    param([object[]]$Rows,[long]$Timestamp)
    $known=$false; $stock=0L
    foreach ($row in @($Rows)) {
        $at=[long](Get-HoverProperty $row 'timestamp')
        if ($at -gt $Timestamp) { break }
        $stock=[long](Get-HoverProperty $row 'stock')
        $known=$true
    }
    return [pscustomobject]@{ known=$known; stock=$stock }
}

$parts=$MarketKey.Split(':')
$country=[string]$parts[0]
$itemId=[int]$parts[1]
$safeName=($MarketKey -replace '[^a-zA-Z0-9_-]','_')
$specPath=Join-Path $GeneratedDir ('inline-graph-'+$safeName+'.kv')
$spec=Read-HoverKv $specPath
if (-not $spec.ContainsKey('MarketKey') -or [string]$spec.MarketKey -ne $MarketKey) { exit 0 }

$cutoff=0L; $now=0L
[void][long]::TryParse([string]$spec.WindowStartTimestamp,[ref]$cutoff)
[void][long]::TryParse([string]$spec.UpdatedAt,[ref]$now)
if ($cutoff -le 0 -or $now -le $cutoff) { exit 0 }

$allRows=@(Read-HoverHistory -Path $RuntimeObservationFile -Country $country -ItemId $itemId)
if ($allRows.Count -eq 0) { $allRows=@(Read-HoverHistory -Path $SeedObservationFile -Country $country -ItemId $itemId) }
$allRows=@(Compress-HoverHistory -Rows $allRows)

$rows=@()
$predecessor=@($allRows | Where-Object { [long]$_.timestamp -lt $cutoff } | Select-Object -Last 1)
if ($predecessor.Count -gt 0) { $rows += [pscustomobject]@{ timestamp=$cutoff; stock=[long]$predecessor[0].stock } }
$rows += @($allRows | Where-Object { [long]$_.timestamp -ge $cutoff -and [long]$_.timestamp -le ($now+60) })
$rows=@(Compress-HoverHistory -Rows $rows)

$currentStock=0L; $latestTimestamp=$now
[void][long]::TryParse([string]$spec.CurrentStock,[ref]$currentStock)
if ($spec.ContainsKey('LatestTimestamp')) { [void][long]::TryParse([string]$spec.LatestTimestamp,[ref]$latestTimestamp) }
if ($latestTimestamp -le 0 -or $latestTimestamp -gt ($now+60)) { $latestTimestamp=$now }
$rows += [pscustomobject]@{ timestamp=$latestTimestamp; stock=$currentStock }
$rows=@(Compress-HoverHistory -Rows $rows)

$windowSeconds=$now-$cutoff
$spec['HoverCount']=$BandCount
for ($i=1; $i -le $BandCount; $i++) {
    $fraction=([double]$i-0.5)/[double]$BandCount
    $timestamp=$cutoff+[long][Math]::Round($windowSeconds*$fraction)
    $sample=Get-HoverStockAt -Rows $rows -Timestamp $timestamp
    $known=if ([bool]$sample.known) { 1 } else { 0 }
    $stock=if ([bool]$sample.known) { [long]$sample.stock } else { 0L }
    $spec[('Hover{0:D2}' -f $i)]=('{0}|{1}|{2}' -f $timestamp,$stock,$known)
}
Write-HoverKvAtomic -Path $specPath -Values $spec
exit 0
