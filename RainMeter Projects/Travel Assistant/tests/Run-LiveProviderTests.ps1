$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$UpdaterPath = Join-Path $ProjectRoot '@Resources\Scripts\UpdateTracker.ps1'

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($UpdaterPath, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw ('UpdateTracker.ps1 has parser errors: ' + ((@($parseErrors) | ForEach-Object { $_.Message }) -join '; '))
}

$wanted = @('Get-DynamicProperty','Get-LiveStockObservation','Get-YataObservation')
$definitions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
}, $true))

foreach ($name in $wanted) {
    $definition = @($definitions | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
    if ($definition.Count -ne 1) { throw "Could not locate production function '$name'." }
    $source = [string]$definition[0].Extent.Text
    $scoped = $source -replace ('^function\s+' + [regex]::Escape($name)), ('function script:' + $name)
    Invoke-Expression $scoped
}

$payload = [pscustomobject]@{
    stocks = [pscustomobject]@{
        uni = [pscustomobject]@{
            update = 1787327048
            stocks = @(
                [pscustomobject]@{ id = 206; quantity = 123; cost = 767000 }
            )
        }
    }
}
$country = [pscustomobject]@{
    id = 'united_kingdom'
    providerCodes = [pscustomobject]@{
        prometheus = 'uni'
        yata = 'uni'
    }
}
$item = [pscustomobject]@{ itemId = 206 }

$prometheus = Get-LiveStockObservation -Payload $payload -Country $country -Item $item -Now 1787327100 -Source 'prometheus'
Assert-Equal 'Prometheus source provenance' $prometheus.source 'prometheus'
Assert-Equal 'Prometheus stock normalization' ([int]$prometheus.stock) 123
Assert-Equal 'Prometheus price normalization' ([long]$prometheus.foreignPrice) 767000
Assert-Equal 'Prometheus timestamp normalization' ([long]$prometheus.sourceTimestamp) 1787327048

$yata = Get-YataObservation -Payload $payload -Country $country -Item $item -Now 1787327100
Assert-Equal 'YATA source provenance' $yata.source 'yata'
Assert-Equal 'YATA compatibility normalization' ([int]$yata.stock) 123

Write-Host 'Live provider normalization tests passed.' -ForegroundColor Green
exit 0
