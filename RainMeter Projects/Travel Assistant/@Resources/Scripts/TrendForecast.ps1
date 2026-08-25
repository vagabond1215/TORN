param(
    [Alias('SkipMain')]
    [switch]$TrendForecastSkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$EngineStateFile = Join-Path $ProjectRoot 'data\runtime\engine-state.json'

function Get-TFProperty {
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

function Set-TFProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    if ($null -eq $Object) { return }
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name]=$Value
        return
    }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value=$Value }
}

function Read-TFJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-TFJsonAtomic {
    param([string]$Path,[object]$Value)
    $tmp=$Path+'.tmp'
    $json=$Value | ConvertTo-Json -Depth 40
    [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-TFMedian {
    param([double[]]$Values)
    $sorted=[double[]]@($Values | Where-Object { $_ -gt 0 } | Sort-Object)
    if ($sorted.Count -eq 0) { return 0.0 }
    $mid=[int][Math]::Floor($sorted.Count/2.0)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$mid] }
    return ([double]$sorted[$mid-1]+[double]$sorted[$mid])/2.0
}

function Get-TFLinearTrend {
    param(
        [object[]]$Samples,
        [string]$Property,
        [int]$MinimumSamples=4,
        [double]$MinimumAbsoluteSlope=1.0,
        [double]$MinimumRelativeSlope=0.01,
        [double]$MinimumR2=0.35
    )
    $values=New-Object System.Collections.Generic.List[double]
    foreach ($sample in @($Samples)) {
        if ($null -eq $sample) { continue }
        $rawValue=Get-TFProperty -Object $sample -Name $Property
        if ($null -eq $rawValue) { continue }
        $value=[double]$rawValue
        if ($value -gt 0) { $values.Add($value) }
    }
    $n=$values.Count
    if ($n -lt $MinimumSamples) {
        return [pscustomobject]@{ sampleCount=$n; direction='insufficient'; slopePerCycle=0.0; rSquared=0.0; consistency=0.0; forecast=0.0; boundedForecast=0.0; recentMedian=(Get-TFMedian -Values $values.ToArray()); recentMin=0.0; recentMax=0.0 }
    }

    $meanX=($n-1)/2.0
    $meanY=($values | Measure-Object -Average).Average
    $sxx=0.0; $sxy=0.0; $sst=0.0
    for ($i=0; $i -lt $n; $i++) {
        $dx=[double]$i-$meanX
        $dy=[double]$values[$i]-[double]$meanY
        $sxx += $dx*$dx
        $sxy += $dx*$dy
        $sst += $dy*$dy
    }
    $slope=if ($sxx -gt 0) { $sxy/$sxx } else { 0.0 }
    $intercept=[double]$meanY-($slope*$meanX)
    $sse=0.0
    for ($i=0; $i -lt $n; $i++) {
        $pred=$intercept+($slope*$i)
        $err=[double]$values[$i]-$pred
        $sse += $err*$err
    }
    $r2=if ($sst -gt 0) { [Math]::Max(0.0,[Math]::Min(1.0,1.0-($sse/$sst))) } else { 1.0 }

    $same=0; $usableDelta=0
    for ($i=1; $i -lt $n; $i++) {
        $delta=[double]$values[$i]-[double]$values[$i-1]
        if ([Math]::Abs($delta) -lt 0.000001) { continue }
        $usableDelta++
        if (($slope -gt 0 -and $delta -gt 0) -or ($slope -lt 0 -and $delta -lt 0)) { $same++ }
    }
    $consistency=if ($usableDelta -gt 0) { $same/[double]$usableDelta } else { 1.0 }
    $median=Get-TFMedian -Values $values.ToArray()
    $threshold=[Math]::Max($MinimumAbsoluteSlope,[Math]::Abs($median)*$MinimumRelativeSlope)
    $direction='neutral'
    if ($r2 -ge $MinimumR2 -and $consistency -ge 0.60 -and [Math]::Abs($slope) -ge $threshold) {
        $direction=if ($slope -gt 0) { 'growing' } else { 'shortening' }
    }

    $rawForecast=$intercept+($slope*$n)
    $minimum=[double]($values | Measure-Object -Minimum).Minimum
    $maximum=[double]($values | Measure-Object -Maximum).Maximum
    $extension=[Math]::Max([Math]::Abs($median)*0.25,[Math]::Abs($slope)*2.0)
    $bounded=[Math]::Max(1.0,[Math]::Min($maximum+$extension,[Math]::Max($minimum-$extension,$rawForecast)))
    if ($direction -eq 'neutral') { $bounded=[double]$values[$n-1] }

    return [pscustomobject]@{
        sampleCount=$n
        direction=$direction
        slopePerCycle=[Math]::Round($slope,3)
        rSquared=[Math]::Round($r2,4)
        consistency=[Math]::Round($consistency,4)
        forecast=[Math]::Round($rawForecast,2)
        boundedForecast=[Math]::Round($bounded,2)
        recentMedian=[Math]::Round($median,2)
        recentMin=[Math]::Round($minimum,2)
        recentMax=[Math]::Round($maximum,2)
    }
}

function Get-TFCorrelation {
    param([object[]]$Samples,[string]$XProperty,[string]$YProperty,[int]$MinimumSamples=4)
    $pairs=New-Object System.Collections.Generic.List[object]
    foreach ($sample in @($Samples)) {
        if ($null -eq $sample) { continue }
        $xRaw=Get-TFProperty -Object $sample -Name $XProperty
        $yRaw=Get-TFProperty -Object $sample -Name $YProperty
        if ($null -eq $xRaw -or $null -eq $yRaw) { continue }
        $x=[double]$xRaw; $y=[double]$yRaw
        if ($x -gt 0 -and $y -gt 0) { $pairs.Add([pscustomobject]@{x=$x;y=$y}) }
    }
    if ($pairs.Count -lt $MinimumSamples) { return 0.0 }
    $mx=($pairs | ForEach-Object {$_.x} | Measure-Object -Average).Average
    $my=($pairs | ForEach-Object {$_.y} | Measure-Object -Average).Average
    $sumXY=0.0; $sumXX=0.0; $sumYY=0.0
    foreach ($pair in $pairs) {
        $dx=[double]$pair.x-[double]$mx; $dy=[double]$pair.y-[double]$my
        $sumXY += $dx*$dy; $sumXX += $dx*$dx; $sumYY += $dy*$dy
    }
    if ($sumXX -le 0 -or $sumYY -le 0) { return 0.0 }
    return [Math]::Round($sumXY/[Math]::Sqrt($sumXX*$sumYY),4)
}

function New-TFAccuracy {
    return [pscustomobject]@{ count=0; availabilityMaeSeconds=0.0; restockDelayMaeSeconds=0.0 }
}

function Update-TFAccuracy {
    param([object]$Accuracy,[object]$Pending,[object]$Actual)
    if ($null -eq $Accuracy) { $Accuracy=New-TFAccuracy }
    if ($null -eq $Pending -or $null -eq $Actual) { return $Accuracy }
    $basedOn=[long](Get-TFProperty $Pending 'basedOnCycleAt')
    $actualAt=[long](Get-TFProperty $Actual 'soldOutAt')
    if ($basedOn -le 0 -or $actualAt -le $basedOn) { return $Accuracy }
    $predAvail=[double](Get-TFProperty $Pending 'availabilitySeconds')
    $predDelay=[double](Get-TFProperty $Pending 'restockDelaySeconds')
    $actualAvail=[double](Get-TFProperty $Actual 'availabilitySeconds')
    $actualDelay=[double](Get-TFProperty $Actual 'restockDelaySeconds')
    $count=[int](Get-TFProperty $Accuracy 'count')
    $next=$count+1
    if ($predAvail -gt 0 -and $actualAvail -gt 0) {
        $old=[double](Get-TFProperty $Accuracy 'availabilityMaeSeconds')
        $Accuracy.availabilityMaeSeconds=(($old*$count)+[Math]::Abs($predAvail-$actualAvail))/$next
    }
    if ($predDelay -gt 0 -and $actualDelay -gt 0) {
        $old=[double](Get-TFProperty $Accuracy 'restockDelayMaeSeconds')
        $Accuracy.restockDelayMaeSeconds=(($old*$count)+[Math]::Abs($predDelay-$actualDelay))/$next
    }
    $Accuracy.count=$next
    return $Accuracy
}

function Get-TFRecentSamples {
    param([object]$Market,[int]$Maximum=8)
    $samples=@(Get-TFProperty $Market 'recentSamples')
    $usable=@($samples | Where-Object { $null -ne $_ -and [long](Get-TFProperty $_ 'soldOutAt') -gt 0 } | Sort-Object soldOutAt)
    if ($usable.Count -gt $Maximum) { return @($usable | Select-Object -Last $Maximum) }
    return $usable
}

function Update-TFMarket {
    param([object]$Market,[long]$NowEpoch)
    $samples=@(Get-TFRecentSamples -Market $Market -Maximum 8)
    if ($samples.Count -lt 1) { return $false }
    $latest=$samples[-1]
    $existing=Get-TFProperty $Market 'trendForecast'
    $accuracy=if ($null -ne $existing -and $null -ne (Get-TFProperty $existing 'accuracy')) { Get-TFProperty $existing 'accuracy' } else { New-TFAccuracy }
    $pending=if ($null -ne $existing) { Get-TFProperty $existing 'pending' } else { $null }
    $accuracy=Update-TFAccuracy -Accuracy $accuracy -Pending $pending -Actual $latest

    $availability=Get-TFLinearTrend -Samples $samples -Property 'availabilitySeconds' -MinimumAbsoluteSlope 30 -MinimumRelativeSlope 0.02
    $restock=Get-TFLinearTrend -Samples $samples -Property 'restockDelaySeconds' -MinimumAbsoluteSlope 30 -MinimumRelativeSlope 0.02
    $price=Get-TFLinearTrend -Samples $samples -Property 'foreignPrice' -MinimumAbsoluteSlope 1 -MinimumRelativeSlope 0.005
    $ratio=Get-TFLinearTrend -Samples $samples -Property 'priceToMvRatioBps' -MinimumAbsoluteSlope 25 -MinimumRelativeSlope 0.005
    $priceCorr=Get-TFCorrelation -Samples $samples -XProperty 'foreignPrice' -YProperty 'availabilitySeconds'
    $ratioCorr=Get-TFCorrelation -Samples $samples -XProperty 'priceToMvRatioBps' -YProperty 'availabilitySeconds'

    $supportsAvailability=$false
    if ($availability.direction -ne 'neutral' -and $availability.direction -ne 'insufficient') {
        if ([Math]::Abs($priceCorr) -ge 0.40 -or [Math]::Abs($ratioCorr) -ge 0.40) { $supportsAvailability=$true }
    }
    $eligible=($samples.Count -ge 6 -and $availability.direction -ne 'insufficient' -and $restock.direction -ne 'insufficient' -and $availability.rSquared -ge 0.45 -and $restock.rSquared -ge 0.35)

    $pendingNext=[pscustomobject]@{
        basedOnCycleAt=[long](Get-TFProperty $latest 'soldOutAt')
        availabilitySeconds=[long][Math]::Round([double]$availability.boundedForecast)
        restockDelaySeconds=[long][Math]::Round([double]$restock.boundedForecast)
        foreignPrice=[long][Math]::Round([double]$price.boundedForecast)
        priceToMvRatioBps=[int][Math]::Round([double]$ratio.boundedForecast)
    }
    $forecast=[pscustomobject]@{
        schemaVersion=1
        updatedAt=$NowEpoch
        mode='shadow'
        eligibleForLive=[bool]$eligible
        sampleCount=$samples.Count
        availability=$availability
        restockDelay=$restock
        foreignPrice=$price
        priceToMvRatioBps=$ratio
        availabilityVsPriceCorrelation=$priceCorr
        availabilityVsRatioCorrelation=$ratioCorr
        priceSignalSupportsAvailability=[bool]$supportsAvailability
        accuracy=$accuracy
        pending=$pendingNext
    }
    Set-TFProperty -Object $Market -Name 'trendForecast' -Value $forecast
    return $true
}

if ($TrendForecastSkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$engine=Read-TFJson $EngineStateFile
if ($null -eq $engine) { return }
$root=Get-TFProperty $engine 'cycleAnalytics'
$markets=Get-TFProperty $root 'markets'
if ($null -eq $markets) { return }
$changed=$false
foreach ($property in @($markets.PSObject.Properties)) {
    if (Update-TFMarket -Market $property.Value -NowEpoch $Now) { $changed=$true }
}
if ($changed) { Write-TFJsonAtomic -Path $EngineStateFile -Value $engine }
