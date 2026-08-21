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
$nessie = @($items.items | Where-Object { [int]$_.itemId -eq 266 } | Select-Object -First 1)[0]
$cherry = @($items.items | Where-Object { [int]$_.itemId -eq 277 } | Select-Object -First 1)[0]
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
Assert-True 'Airstrip capacity is known' ([bool]$airEconomics.capacityKnown)
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
$flowerEffects = Get-TravelProfileEffects -Profile $flower10 -PerksConfig $perks -Item $cherry
Assert-Equal 'Flower Shop adds five slots only to Flower items' ([int]$flowerEffects.itemCapacityBonus) 5
Assert-Equal 'Legacy Airstrip Flower capacity is twenty' ([int](Get-EffectiveTravelEconomics -Country $uk -TravelMode 'airstrip' -Effects $flowerEffects).capacity) 20

$toy10 = [pscustomobject]@{ companyType='toy_shop'; companyStars=10; factionExcursionLevel=0; factionTravelCostLevel=0 }
$effects = Get-TravelProfileEffects -Profile $toy10 -PerksConfig $perks -Item $item
Assert-Equal 'Toy Shop does not increase Xanax capacity' $effects.itemCapacityBonus 0
$toyEffects = Get-TravelProfileEffects -Profile $toy10 -PerksConfig $perks -Item $nessie
Assert-Equal 'Toy Shop adds five slots only to Plushie items' ([int]$toyEffects.itemCapacityBonus) 5
Assert-Equal 'Legacy Airstrip Plushie capacity is twenty' ([int](Get-EffectiveTravelEconomics -Country $uk -TravelMode 'airstrip' -Effects $toyEffects).capacity) 20

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

$currentLocal = [pscustomobject]@{ travelProfile = [pscustomobject]@{
    companyType='lingerie_store'; companyStars=10
    currentCapacityKnown=$true; currentCapacityMode='airstrip'; currentCapacity=18; currentCapacityBonus=3; currentCapacitySyncedAt=1234567890
    factionState='peace'; factionExcursionLevel=10; factionTravelCostLevel=5
    factionPeaceExcursionLevel=10; factionPeaceTravelCostLevel=5; factionWarExcursionLevel=0; factionWarTravelCostLevel=0
} }
$currentProfile = Get-TravelProfile -BaseSettings $baseSettings -LocalSettings $currentLocal
Assert-True 'Synced current capacity is retained' ([bool]$currentProfile.currentCapacityKnown)
Assert-Equal 'Synced current capacity bonus is retained' ([int]$currentProfile.currentCapacityBonus) 3
$currentEffects = Get-TravelProfileEffects -Profile $currentProfile -PerksConfig $perks -Item $item
Assert-Equal 'Current capacity replaces inferred general company and faction slots' ([int]$currentEffects.totalCapacityBonus) 3
Assert-Equal 'Current capacity does not double count faction slots' ([int]$currentEffects.factionCapacityBonus) 0
Assert-Equal 'Current capacity uses conservative zero faction fee reduction' ([int]$currentEffects.travelCostReductionPercent) 0
Assert-True 'Current capacity still preserves 10-star Lingerie Business unlock' ([bool]$currentEffects.freeBusinessClass)
$currentAir = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'airstrip' -Effects $currentEffects
Assert-Equal 'Current +3 bonus produces 18 Airstrip Xanax capacity' ([int]$currentAir.capacity) 18
$currentStandard = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'standard' -Effects $currentEffects
Assert-Equal 'Current +3 bonus produces 13 Standard Xanax capacity' ([int]$currentStandard.capacity) 13
$currentBusiness = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'business' -Effects $currentEffects
Assert-Equal 'Current +3 bonus produces 18 Business Xanax capacity' ([int]$currentBusiness.capacity) 18

$currentFlowerProfile = Get-TravelProfile -BaseSettings $baseSettings -LocalSettings ([pscustomobject]@{ travelProfile = [pscustomobject]@{
    companyType='flower_shop'; companyStars=7
    currentCapacityKnown=$true; currentCapacityMode='airstrip'; currentCapacity=18; currentCapacityBonus=3; currentCapacitySyncedAt=1234567890
} })
$currentFlowerXanaxEffects = Get-TravelProfileEffects -Profile $currentFlowerProfile -PerksConfig $perks -Item $item
Assert-Equal 'Synced Flower Shop profile still leaves Xanax at general +3 only' ([int]$currentFlowerXanaxEffects.totalCapacityBonus) 3
$currentFlowerEffects = Get-TravelProfileEffects -Profile $currentFlowerProfile -PerksConfig $perks -Item $cherry
Assert-Equal 'Synced Flower Shop adds category +5 on top of general current capacity' ([int]$currentFlowerEffects.itemCapacityBonus) 5
Assert-Equal 'Synced Flower Shop Airstrip Flower capacity is 23' ([int](Get-EffectiveTravelEconomics -Country $uk -TravelMode 'airstrip' -Effects $currentFlowerEffects).capacity) 23
Assert-Equal 'Synced Flower Shop Standard Flower capacity is 18' ([int](Get-EffectiveTravelEconomics -Country $uk -TravelMode 'standard' -Effects $currentFlowerEffects).capacity) 18

$currentToyProfile = Get-TravelProfile -BaseSettings $baseSettings -LocalSettings ([pscustomobject]@{ travelProfile = [pscustomobject]@{
    companyType='toy_shop'; companyStars=7
    currentCapacityKnown=$true; currentCapacityMode='airstrip'; currentCapacity=18; currentCapacityBonus=3; currentCapacitySyncedAt=1234567890
} })
$currentToyXanaxEffects = Get-TravelProfileEffects -Profile $currentToyProfile -PerksConfig $perks -Item $item
Assert-Equal 'Synced Toy Shop profile still leaves Xanax at general +3 only' ([int]$currentToyXanaxEffects.totalCapacityBonus) 3
$currentToyEffects = Get-TravelProfileEffects -Profile $currentToyProfile -PerksConfig $perks -Item $nessie
Assert-Equal 'Synced Toy Shop adds category +5 on top of general current capacity' ([int]$currentToyEffects.itemCapacityBonus) 5
Assert-Equal 'Synced Toy Shop Airstrip Plushie capacity is 23' ([int](Get-EffectiveTravelEconomics -Country $uk -TravelMode 'airstrip' -Effects $currentToyEffects).capacity) 23

$overrideEffects = [pscustomobject]@{ totalCapacityBonus=999; travelCostReductionPercent=0; freeBusinessClass=$false; capacityKnown=$false }
$overrideEconomics = Get-EffectiveTravelEconomics -Country $uk -TravelMode 'airstrip' -Effects $overrideEffects -CapacityOverride 42
Assert-True 'Explicit positive capacity override remains authoritative even if modeled capacity is unresolved' ([bool]$overrideEconomics.capacityKnown)
Assert-Equal 'Explicit positive capacity override remains exact' ([int]$overrideEconomics.capacity) 42

Write-Host 'Travel profile economics tests passed.' -ForegroundColor Green
exit 0
