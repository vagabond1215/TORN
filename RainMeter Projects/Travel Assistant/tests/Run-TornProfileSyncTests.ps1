$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\TornProfileSync.ps1')

$perks = Get-Content -LiteralPath (Join-Path $ProjectRoot 'config\travel-perks.json') -Raw | ConvertFrom-Json
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

$starter = [pscustomobject]@{ job = [pscustomobject]@{ type = 'education'; name = 'Education'; position = 'Substitute Teacher' } }
$starterProfile = Get-TornCompanyTravelProfile -JobPayload $starter -PerksConfig $perks
Assert-True 'Starter job resolves safely' ([bool]$starterProfile.Resolved)
Assert-Equal 'Starter job maps to no travel company' ([string]$starterProfile.CompanyType) 'none'
Assert-Equal 'Starter job maps to zero company stars' ([int]$starterProfile.CompanyStars) 0

$lingerie = [pscustomobject]@{ job = [pscustomobject]@{ type = 'company'; type_id = 32; rating = 10; name = 'Synthetic company' } }
$lingerieProfile = Get-TornCompanyTravelProfile -JobPayload $lingerie -PerksConfig $perks
Assert-True 'Known Torn company type resolves' ([bool]$lingerieProfile.Resolved)
Assert-Equal 'Torn type 32 maps to Lingerie Store' ([string]$lingerieProfile.CompanyType) 'lingerie_store'
Assert-Equal 'Company rating is preserved' ([int]$lingerieProfile.CompanyStars) 10

$unknownCompany = [pscustomobject]@{ job = [pscustomobject]@{ type = 'company'; type_id = 999; rating = 7; name = 'Unknown synthetic company' } }
$unknownProfile = Get-TornCompanyTravelProfile -JobPayload $unknownCompany -PerksConfig $perks
Assert-True 'Unknown company type remains unresolved' (-not [bool]$unknownProfile.Resolved)

$factionPayload = [pscustomobject]@{
    state = 'war'
    upgrades = [pscustomobject]@{
        core = [pscustomobject]@{ upgrades = @() }
        peace = @([pscustomobject]@{
            name = 'Excursion'
            upgrades = @(
                [pscustomobject]@{ name = 'Travel capacity'; level = 10; ability = 'Increases maximum traveling capacity by 10' },
                [pscustomobject]@{ name = 'Travel cost'; level = 5; ability = 'Reduces traveling fees by 75%' }
            )
        })
        war = @([pscustomobject]@{ name = 'War branch'; upgrades = @() })
    }
}
$factionProfile = Get-TornFactionTravelProfile -FactionPayload $factionPayload
Assert-True 'War-mode faction profile resolves' ([bool]$factionProfile.Resolved)
Assert-Equal 'Top-level faction state parses as war' ([string]$factionProfile.State) 'war'
Assert-Equal 'War active Travel capacity is zero' ([int]$factionProfile.ExcursionLevel) 0
Assert-Equal 'War active Travel cost is zero' ([int]$factionProfile.TravelCostLevel) 0
Assert-Equal 'Inactive Peace Travel capacity is preserved' ([int]$factionProfile.PeaceExcursionLevel) 10
Assert-Equal 'Inactive Peace Travel cost is preserved' ([int]$factionProfile.PeaceTravelCostLevel) 5
Assert-Equal 'War loadout Travel capacity is preserved separately' ([int]$factionProfile.WarExcursionLevel) 0

$peacePayload = [pscustomobject]@{
    state = 'peace'
    upgrades = [pscustomobject]@{
        core = [pscustomobject]@{ upgrades = @() }
        peace = $factionPayload.upgrades.peace
        war = @([pscustomobject]@{
            name = 'War branch'
            upgrades = @([pscustomobject]@{ name = 'Travel capacity'; level = 2; ability = 'Increases maximum traveling capacity by 2' })
        })
    }
}
$peaceProfile = Get-TornFactionTravelProfile -FactionPayload $peacePayload
Assert-Equal 'Peace active Travel capacity uses Peace branch' ([int]$peaceProfile.ExcursionLevel) 10
Assert-Equal 'Peace active Travel cost uses Peace branch' ([int]$peaceProfile.TravelCostLevel) 5
Assert-Equal 'Inactive War Travel capacity remains visible' ([int]$peaceProfile.WarExcursionLevel) 2

$legacyNestedState = [pscustomobject]@{
    upgrades = [pscustomobject]@{
        state = 'war'
        core = [pscustomobject]@{ upgrades = @() }
        peace = $factionPayload.upgrades.peace
        war = @()
    }
}
$legacyProfile = Get-TornFactionTravelProfile -FactionPayload $legacyNestedState
Assert-Equal 'Legacy nested faction state remains readable' ([string]$legacyProfile.State) 'war'

$unknownState = [pscustomobject]@{
    upgrades = [pscustomobject]@{
        core = [pscustomobject]@{ upgrades = @() }
        peace = $factionPayload.upgrades.peace
        war = @()
    }
}
$unknownStateProfile = Get-TornFactionTravelProfile -FactionPayload $unknownState
Assert-True 'Missing faction state does not claim an active loadout' (-not [bool]$unknownStateProfile.Resolved)
Assert-Equal 'Unknown faction state still preserves Peace loadout' ([int]$unknownStateProfile.PeaceExcursionLevel) 10

foreach ($name in $passes) { Write-Host "PASS $name" -ForegroundColor DarkGreen }
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'Torn profile sync tests passed.' -ForegroundColor Green
exit 0
