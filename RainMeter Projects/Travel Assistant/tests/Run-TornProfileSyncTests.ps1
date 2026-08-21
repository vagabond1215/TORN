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
    if (-not $Condition) { $script:failures.Add($Name) }
    else { $script:passes.Add($Name) }
}

$starter = [pscustomobject]@{
    job = [pscustomobject]@{
        type = 'education'
        name = 'Education'
        position = 'Substitute Teacher'
    }
}
$starterProfile = Get-TornCompanyTravelProfile -JobPayload $starter -PerksConfig $perks
Assert-True 'Starter job resolves safely' ([bool]$starterProfile.Resolved)
Assert-Equal 'Starter job maps to no travel company' ([string]$starterProfile.CompanyType) 'none'
Assert-Equal 'Starter job maps to zero company stars' ([int]$starterProfile.CompanyStars) 0

$lingerie = [pscustomobject]@{
    job = [pscustomobject]@{
        type = 'company'
        type_id = 32
        rating = 10
        name = 'Synthetic company'
    }
}
$lingerieProfile = Get-TornCompanyTravelProfile -JobPayload $lingerie -PerksConfig $perks
Assert-True 'Known Torn company type resolves' ([bool]$lingerieProfile.Resolved)
Assert-Equal 'Torn type 32 maps to Lingerie Store' ([string]$lingerieProfile.CompanyType) 'lingerie_store'
Assert-Equal 'Company rating is preserved' ([int]$lingerieProfile.CompanyStars) 10

$unknownCompany = [pscustomobject]@{
    job = [pscustomobject]@{
        type = 'company'
        type_id = 999
        rating = 7
        name = 'Unknown synthetic company'
    }
}
$unknownProfile = Get-TornCompanyTravelProfile -JobPayload $unknownCompany -PerksConfig $perks
Assert-True 'Unknown company type remains unresolved' (-not [bool]$unknownProfile.Resolved)

$factionPayload = [pscustomobject]@{
    upgrades = [pscustomobject]@{
        core = [pscustomobject]@{ upgrades = @() }
        peace = @(
            [pscustomobject]@{
                name = 'Excursion'
                upgrades = @(
                    [pscustomobject]@{ name = 'Travel capacity'; level = 8; ability = 'Increases maximum traveling capacity by 8' },
                    [pscustomobject]@{ name = 'Travel cost'; level = 3; ability = 'Reduces traveling fees by 45%' }
                )
            }
        )
        war = @()
    }
}
$factionProfile = Get-TornFactionTravelProfile -FactionPayload $factionPayload
Assert-Equal 'Faction Travel capacity level parses' ([int]$factionProfile.ExcursionLevel) 8
Assert-Equal 'Faction Travel cost level parses' ([int]$factionProfile.TravelCostLevel) 3

$emptyFaction = [pscustomobject]@{
    upgrades = [pscustomobject]@{
        core = [pscustomobject]@{ upgrades = @() }
        peace = @()
        war = @()
    }
}
$emptyProfile = Get-TornFactionTravelProfile -FactionPayload $emptyFaction
Assert-Equal 'Successful faction response without Travel capacity resolves to zero' ([int]$emptyProfile.ExcursionLevel) 0
Assert-Equal 'Successful faction response without Travel cost resolves to zero' ([int]$emptyProfile.TravelCostLevel) 0

foreach ($name in $passes) { Write-Host "PASS $name" -ForegroundColor DarkGreen }
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'Torn profile sync tests passed.' -ForegroundColor Green
exit 0
