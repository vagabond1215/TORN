param(
    [Alias('SkipMain')]
    [switch]$PriceVariationRefinerSkipMain
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$EngineStateFile=Join-Path $ProjectRoot 'data\runtime\engine-state.json'
$StateKvFile=Join-Path $ProjectRoot '@Resources\Generated\state.kv'

function Get-PVProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $p=$Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Read-PVJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Read-PVState {
    param([string]$Path)
    $state=@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $state }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $eq=$line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $state[$line.Substring(0,$eq).Trim([char]0xFEFF).Trim()]=$line.Substring($eq+1).Trim()
    }
    return $state
}

function Write-PVStateAtomic {
    param([hashtable]$State,[string]$Path)
    $tmp=$Path+'.tmp'
    $lines=New-Object System.Collections.Generic.List[string]
    foreach ($key in @($State.Keys | Sort-Object)) {
        $value=([string]$State[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines.Add("$key=$value")
    }
    [System.IO.File]::WriteAllLines($tmp,$lines.ToArray(),[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-PVMedian {
    param([long[]]$Values)
    $sorted=[long[]]@($Values | Where-Object { $_ -gt 0 } | Sort-Object)
    if ($sorted.Count -eq 0) { return 0L }
    $mid=[int][Math]::Floor($sorted.Count/2.0)
    if (($sorted.Count % 2) -eq 1) { return [long]$sorted[$mid] }
    return [long][Math]::Round(([double]$sorted[$mid-1]+[double]$sorted[$mid])/2.0)
}

function Test-PVMaterialDifference {
    param([long]$A,[long]$B,[double]$MinimumPercent=0.5)
    if ($A -le 0 -or $B -le 0) { return $false }
    $den=[Math]::Max([Math]::Abs([double]$A),[Math]::Abs([double]$B))
    if ($den -le 0) { return $false }
    return (100.0*[Math]::Abs([double]$A-[double]$B)/$den) -ge $MinimumPercent
}

function Get-PVRecentPrices {
    param([object]$Market,[int]$Maximum=12)
    $samples=@(Get-PVProperty $Market 'recentSamples')
    $prices=@($samples | Where-Object { $null -ne $_ -and [long](Get-PVProperty $_ 'foreignPrice') -gt 0 } | Sort-Object soldOutAt | Select-Object -Last $Maximum | ForEach-Object { [long](Get-PVProperty $_ 'foreignPrice') })
    return [long[]]$prices
}

function Test-PVRecentVariation {
    param([object]$Market)
    if ($null -eq $Market) { return [pscustomobject]@{ varies=$false; reason='no-market'; minimum=0L; maximum=0L } }
    $prices=[long[]]@(Get-PVRecentPrices -Market $Market)
    $current=[long](Get-PVProperty $Market 'currentForeignPrice')
    $positive=@($prices | Where-Object { $_ -gt 0 })
    $minimum=if ($positive.Count -gt 0) { [long](@($positive | Measure-Object -Minimum).Minimum) } else { 0L }
    $maximum=if ($positive.Count -gt 0) { [long](@($positive | Measure-Object -Maximum).Maximum) } else { 0L }
    if ($current -gt 0) {
        if ($minimum -le 0 -or $current -lt $minimum) { $minimum=$current }
        if ($current -gt $maximum) { $maximum=$current }
    }
    if ($positive.Count -eq 0) { return [pscustomobject]@{ varies=$false; reason='no-history'; minimum=$minimum; maximum=$maximum } }

    $median=Get-PVMedian -Values $prices
    if ($current -gt 0 -and $median -gt 0 -and (Test-PVMaterialDifference -A $current -B $median)) {
        return [pscustomobject]@{ varies=$true; reason='current-vs-recent'; minimum=$minimum; maximum=$maximum }
    }

    # A single anomalous sample followed by a return to the stable price is not
    # evidence of a variable shop price. Require recurring materially separated
    # levels before retained history can color an otherwise stable current price.
    $counts=@{}
    foreach ($price in $prices) {
        $key=[string]$price
        if (-not $counts.ContainsKey($key)) { $counts[$key]=0 }
        $counts[$key]=[int]$counts[$key]+1
    }
    $levels=@($counts.Keys | Where-Object { [int]$counts[$_] -ge 2 } | ForEach-Object { [long]$_ } | Sort-Object)
    if ($levels.Count -ge 2) {
        for ($i=0; $i -lt $levels.Count; $i++) {
            for ($j=$i+1; $j -lt $levels.Count; $j++) {
                if (Test-PVMaterialDifference -A $levels[$i] -B $levels[$j]) {
                    return [pscustomobject]@{ varies=$true; reason='recurring-levels'; minimum=$minimum; maximum=$maximum }
                }
            }
        }
    }
    return [pscustomobject]@{ varies=$false; reason='recent-fixed'; minimum=$minimum; maximum=$maximum }
}

function Set-PVEnvelope {
    param([string]$Text,[bool]$Varies)
    $flag=if ($Varies) { 'PV1#' } else { 'PV0#' }
    $value=[string]$Text
    if ($value -match '^WP2:') {
        if ($value -match '#PV[01]#') { return ($value -replace '#PV[01]#',('#'+$flag)) }
        $first=$value.IndexOf('#')
        if ($first -ge 0) { return $value.Substring(0,$first+1)+$flag+$value.Substring($first+1) }
        return $value
    }
    if ($value -match '^PV[01]#') { return ($value -replace '^PV[01]#',$flag) }
    return $flag+$value
}

if ($PriceVariationRefinerSkipMain) { return }
$engine=Read-PVJson $EngineStateFile
$state=Read-PVState $StateKvFile
if ($null -eq $engine -or $state.Count -eq 0) { return }
$root=Get-PVProperty $engine 'cycleAnalytics'
$markets=Get-PVProperty $root 'markets'
if ($null -eq $markets) { return }
$count=0
[void][int]::TryParse([string]$state['OpportunityCount'],[ref]$count)
$count=[Math]::Min(256,[Math]::Max(0,$count))
for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=[string]$state[$prefix+'Key']
    if ([string]::IsNullOrWhiteSpace($key)) { continue }
    if (([string]$state[$prefix+'ForecastMode']).Trim().ToLowerInvariant() -eq 'sleeping_oos') { continue }
    $p=$markets.PSObject.Properties[$key.ToLowerInvariant()]
    if ($null -eq $p) { continue }
    $classification=Test-PVRecentVariation -Market $p.Value
    $state[$prefix+'PriceVaries']=if ([bool]$classification.varies) { '1' } else { '0' }
    $state[$prefix+'PriceVariationReason']=[string]$classification.reason
    $state[$prefix+'MinObservedPrice']=[long]$classification.minimum
    $state[$prefix+'MaxObservedPrice']=[long]$classification.maximum
    if ($state.ContainsKey($prefix+'Tooltip')) {
        $state[$prefix+'Tooltip']=Set-PVEnvelope -Text ([string]$state[$prefix+'Tooltip']) -Varies ([bool]$classification.varies)
    }
}
Write-PVStateAtomic -State $state -Path $StateKvFile
