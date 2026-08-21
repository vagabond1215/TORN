$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\CurrentCapacity.ps1')

$failures = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { $script:failures.Add("$Name - expected '$Expected', got '$Actual'") }
    else { $script:passes.Add($Name) }
}
function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { $script:failures.Add($Name) } else { $script:passes.Add($Name) }
}

Assert-Equal 'Standard base capacity is 10' (Get-TornTravelModeBaseCapacity -TravelMode 'standard') 10
Assert-Equal 'Airstrip base capacity is 15' (Get-TornTravelModeBaseCapacity -TravelMode 'airstrip') 15
Assert-Equal 'WLT base capacity is 15' (Get-TornTravelModeBaseCapacity -TravelMode 'wlt') 15
Assert-Equal 'Business base capacity is 15' (Get-TornTravelModeBaseCapacity -TravelMode 'business') 15

$perks = [pscustomobject]@{
    perks = [pscustomobject]@{
        faction = @('Increases maximum traveling capacity by 10')
        job = @('Increases travel item capacity by 2', 'Able to carry 5 additional flowers when traveling')
        book = @('Increases travel items by 10 for 31 days')
        enhancer = @('Increases travel capacity by +1', 'Increases travel capacity by +3')
        property = @('Provides access to an airstrip and pilot')
        stock = @('50% decrease in flight times and +10 carrying capacity')
        education = @(); merit = @()
    }
}

$suitcase = Get-TornSuitcaseCapacityFromPerks -PerksPayload $perks
Assert-True 'Enhancer suitcase lookup resolves' ([bool]$suitcase.Resolved)
Assert-Equal 'Only largest active suitcase bonus is used' ([int]$suitcase.Bonus) 3

$active = Get-TornActiveTravelCapacityPerks -PerksPayload $perks
Assert-True 'Known current travel perk strings resolve' ([bool]$active.Resolved)
Assert-Equal 'Faction company and book capacity stack' ([int]$active.Bonus) 22
Assert-Equal 'Only general Xanax-applicable additive perks are counted' @($active.Recognized).Count 3
Assert-Equal 'Flower-specific company perk is excluded' @($active.Unparsed).Count 0

$capacity = Get-TornEffectiveXanaxCapacity -TravelMode 'airstrip' -PerksPayload $perks
Assert-True 'Effective capacity resolves with known current perks' ([bool]$capacity.Resolved)
Assert-Equal 'Airstrip effective capacity combines base suitcase and active perks' ([int]$capacity.Capacity) 40
Assert-Equal 'Stock/property method perks are not double counted' ([int]$capacity.ActivePerkBonus) 22
Assert-Equal 'Suitcase is exposed separately from additive perks' ([int]$capacity.SuitcaseBonus) 3

$unknownPerks = [pscustomobject]@{
    perks = [pscustomobject]@{
        faction = @('Travel capacity has been improved dramatically')
        job = @(); book = @(); enhancer = @(); property = @(); stock = @(); education = @(); merit = @()
    }
}
$unknown = Get-TornActiveTravelCapacityPerks -PerksPayload $unknownPerks
Assert-True 'Unrecognized current capacity string stays unresolved' (-not [bool]$unknown.Resolved)
Assert-Equal 'Unrecognized current capacity string is surfaced' @($unknown.Unparsed).Count 1

$unknownEnhancer = [pscustomobject]@{
    perks = [pscustomobject]@{
        faction = @(); job = @(); book = @(); enhancer = @('Travel carrying capacity improved by suitcase magic'); property = @(); stock = @(); education = @(); merit = @()
    }
}
$unknownSuitcase = Get-TornSuitcaseCapacityFromPerks -PerksPayload $unknownEnhancer
Assert-True 'Unparsed enhancer capacity remains unresolved' (-not [bool]$unknownSuitcase.Resolved)
Assert-Equal 'Unparsed enhancer capacity is surfaced' @($unknownSuitcase.Unparsed).Count 1

foreach ($name in $passes) { Write-Host "PASS $name" -ForegroundColor DarkGreen }
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'Current effective travel capacity tests passed.' -ForegroundColor Green
exit 0
