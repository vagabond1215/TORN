$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\TravelProfile.ps1')

function Read-Json([string]$Relative) { return (Get-Content -LiteralPath (Join-Path $ProjectRoot $Relative) -Raw | ConvertFrom-Json) }
function Assert-Equal { param([string]$Name, $Actual, $Expected) if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }; Write-Host "PASS $Name" -ForegroundColor DarkGreen }
function Assert-True { param([string]$Name, [bool]$Condition) if (-not $Condition) { throw "$Name - condition was false." }; Write-Host "PASS $Name" -ForegroundColor DarkGreen }

$perks = Read-Json 'config\travel-perks.json'
$modes = Read-Json 'config\travel-modes.json'
$countries = Read-Json 'config\countries.json'
$items = Read-Json 'config\items.json'
$baseSettings = Read-Json 'config\settings.example.json'
$item = @($items.items | Where-Object { [int]$_.itemId -eq 206 } | Select-Object -First 1)[0]
$uk = @($countries.countries | Where-Object { [string]$_.id -eq 'united_kingdom' } | Select-Object -First 1)[0]

$none = [pscustomobject]@{ companyType='none'; companyStars=0; factionExcursionLevel=0; factionTravelCostLevel=0 }
$effects = Get-TravelProfileEffects -Profile $none -PerksConfig $perks -Item $item
Assert-Equal 'No-profile capacity bonus' $effects.totalCapacityBonus 0
Assert-True 'Business hidden without free travel' ((Get-AvailableTravelModeIds -TravelModes $modes -Effects $effects) -notcontains 'business')

$lingerie3 = [pscustomobject]@{ companyType='lingerie_store'; companyStars=3; factionExcursionLevel=0; factionTravelCostLevel=0 }
$effects = Get-TravelProfileEffects -Profile $lingerie3 -PerksConfig $perks -Item $item
Assert-Equal '3-star Lingerie adds two general slots' $effects.generalCapacityBonus 2
Assert-Equal '3-star Lingerie does not unlock Business' $effects.freeBusinessClass $false

$lingerie10 = [pscustomobject]@{ companyType='lingerie_store'; companyStars=10; factionExcursionLevel=10; factionTravelCostLevel=5 }
$effects = Get-TravelProfileEffects -Profile $lingerie10 -PerksConfig $perks -Item $item
Assert-Equal '10-star Lingerie keeps +2 capacity' $effects.generalCapacityBonus 2
Assert-Equal 'Faction Excursion level 10 adds ten slots' $effects.factionCapacityBonus 10
Assert-Equal 'Faction travel-cost level 5 reduces fees 75 percent' $effects.travelCostReductionPercent 75
Assert-True '10-star Lingerie unlocks Business' ([bool]$effects.freeBusinessClass)
Assert-True 'Business becomes available in settings' ((Get-AvailableTravelModeIds -TravelModes $modes -Effects $effects) -contains 'business')
$airEconomics = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'airstrip' -Effects $effects
Assert-Equal 'Airstrip capacity includes company and faction bonuses' $airEconomics.capacity 27
$standardEconomics = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'standard' -Effects $effects
Assert-Equal 'Standard capacity includes company and faction bonuses' $standardEconomics.capacity 22
Assert-Equal 'Faction travel-cost reduction applies to Standard fare' $standardEconomics.travelCost 4500
$businessEconomics = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'business' -Effects $effects
Assert-Equal 'Free Business travel has known zero travel cost' $businessEconomics.travelCost 0
Assert-True 'Free Business travel economics are known' ([bool]$businessEconomics.travelCostKnown)
Assert-Equal 'Business capacity includes company and faction bonuses' $businessEconomics.capacity 27

$cruise10 = [pscustomobject]@{ companyType='cruise_line'; companyStars=10; factionExcursionLevel=0; factionTravelCostLevel=0 }
$effects = Get-TravelProfileEffects -Profile $cruise10 -PerksConfig $perks -Item $item
Assert-Equal '10-star Cruise Line stacks +2 and +3 capacity' $effects.generalCapacityBonus 5

$flower10 = [pscustomobject]@{ companyType='flower_shop'; companyStars=10; factionExcursionLevel=0; factionTravelCostLevel=0 }
$effects = Get-TravelProfileEffects -Profile $flower10 -PerksConfig $perks -Item $item
Assert-Equal 'Flower Shop does not increase Xanax capacity' $effects.itemCapacityBonus 0
$toy10 = [pscustomobject]@{ companyType='toy_shop'; companyStars=10; factionExcursionLevel=0; factionTravelCostLevel=0 }
$effects = Get-TravelProfileEffects -Profile $toy10 -PerksConfig $perks -Item $item
Assert-Equal 'Toy Shop does not increase Xanax capacity' $effects.itemCapacityBonus 0
$businessBlocked = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'business' -Effects (Get-TravelProfileEffects -Profile $none -PerksConfig $perks -Item $item)
Assert-Equal 'Business without free travel remains unknown-cost' $businessBlocked.travelCostKnown $false

$warLocal = [pscustomobject]@{ travelProfile = [pscustomobject]@{
    companyType='none'; companyStars=0; factionState='war'; factionExcursionLevel=9; factionTravelCostLevel=4
    factionPeaceExcursionLevel=10; factionPeaceTravelCostLevel=5; factionWarExcursionLevel=0; factionWarTravelCostLevel=0
} }
$warProfile = Get-TravelProfile -BaseSettings $baseSettings -LocalSettings $warLocal
Assert-Equal 'War state is retained' ([string]$warProfile.factionState) 'war'
Assert-Equal 'War state derives active capacity from War loadout' ([int]$warProfile.factionExcursionLevel) 0
Assert-Equal 'War state derives active cost from War loadout' ([int]$warProfile.factionTravelCostLevel) 0
Assert-Equal 'Peace capacity remains stored while War is active' ([int]$warProfile.factionPeaceExcursionLevel) 10

$peaceLocal = [pscustomobject]@{ travelProfile = [pscustomobject]@{
    companyType='none'; companyStars=0; factionState='peace'; factionExcursionLevel=0; factionTravelCostLevel=0
    factionPeaceExcursionLevel=10; factionPeaceTravelCostLevel=5; factionWarExcursionLevel=2; factionWarTravelCostLevel=1
} }
$peaceProfile = Get-TravelProfile -BaseSettings $baseSettings -LocalSettings $peaceLocal
Assert-Equal 'Peace state derives active capacity from Peace loadout' ([int]$peaceProfile.factionExcursionLevel) 10
Assert-Equal 'Peace state derives active cost from Peace loadout' ([int]$peaceProfile.factionTravelCostLevel) 5
$peaceEffects = Get-TravelProfileEffects -Profile $peaceProfile -PerksConfig $perks -Item $item
Assert-Equal 'Peace loadout produces +10 effective faction capacity' ([int]$peaceEffects.factionCapacityBonus) 10
Assert-Equal 'Peace loadout produces -75 percent travel cost' ([int]$peaceEffects.travelCostReductionPercent) 75

$manualLocal = [pscustomobject]@{ travelProfile = [pscustomobject]@{ companyType='none'; companyStars=0; factionState='manual'; factionExcursionLevel=7; factionTravelCostLevel=2 } }
$manualProfile = Get-TravelProfile -BaseSettings $baseSettings -LocalSettings $manualLocal
Assert-Equal 'Manual state preserves legacy active capacity' ([int]$manualProfile.factionExcursionLevel) 7
Assert-Equal 'Manual state preserves legacy active cost' ([int]$manualProfile.factionTravelCostLevel) 2

Write-Host 'Travel profile economics tests passed.' -ForegroundColor Green
exit 0
