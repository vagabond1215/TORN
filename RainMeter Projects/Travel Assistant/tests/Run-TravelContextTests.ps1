$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\TravelContext.ps1') -SkipMain

function Read-TestJson([string]$Relative) { return (Get-Content -LiteralPath (Join-Path $ProjectRoot $Relative) -Raw | ConvertFrom-Json) }
function Assert-Equal { param([string]$Name,$Actual,$Expected) if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }; Write-Host "PASS $Name" -ForegroundColor DarkGreen }
function Assert-True { param([string]$Name,[bool]$Condition) if (-not $Condition) { throw "$Name - condition was false." }; Write-Host "PASS $Name" -ForegroundColor DarkGreen }

$countries = Read-TestJson 'config\countries.json'
$now = 2000000000L

Assert-Equal 'London resolves to United Kingdom' (Resolve-TravelCountryId -DestinationText 'London' -CountriesConfig $countries) 'united_kingdom'
Assert-Equal 'Tokyo resolves to Japan' (Resolve-TravelCountryId -DestinationText 'Tokyo' -CountriesConfig $countries) 'japan'
Assert-Equal 'UK alias resolves' (Resolve-TravelCountryId -DestinationText 'UK' -CountriesConfig $countries) 'united_kingdom'
Assert-Equal 'Torn does not resolve to foreign country' (Resolve-TravelCountryId -DestinationText 'Torn' -CountriesConfig $countries) ''

$outbound = [pscustomobject]@{
    travel = [pscustomobject]@{
        destination = [pscustomobject]@{ name='Japan' }
        method = 'Airstrip'
        departed_at = $now - 120
        arrival_at = $now + 1000
        time_left = 1000
    }
    status = [pscustomobject]@{ state='Traveling' }
    bars = [pscustomobject]@{
        energy = [pscustomobject]@{ current=1000; maximum=150; increment=5; interval=600; tick_time=240; full_time=0 }
        nerve = [pscustomobject]@{ current=40; maximum=45; increment=1; interval=300; tick_time=120; full_time=1500 }
    }
}
$ctx = Convert-TornTravelContext -Payload $outbound -CountriesConfig $countries -NowEpoch $now
Assert-Equal 'Outbound destination country normalized' ([string]$ctx.destinationCountryId) 'japan'
Assert-Equal 'Outbound state is traveling' ([string]$ctx.state) 'traveling'
Assert-True 'Outbound foreign filter is active' ([bool]$ctx.filterActive)
Assert-Equal 'Outbound arrival retained' ([long]$ctx.arrivalAt) ($now + 1000)
Assert-Equal 'Outbound time left retained' ([long]$ctx.timeLeft) 1000
Assert-Equal 'Energy current is normalized' ([long]$ctx.energy.current) 1000
Assert-Equal 'Energy natural maximum is normalized separately from stacked current' ([long]$ctx.energy.maximum) 150
Assert-Equal 'Energy tick interval is normalized' ([long]$ctx.energy.interval) 600
Assert-Equal 'Nerve current is normalized' ([long]$ctx.nerve.current) 40
Assert-Equal 'Nerve maximum is normalized' ([long]$ctx.nerve.maximum) 45
Assert-Equal 'Nerve increment is normalized' ([long]$ctx.nerve.increment) 1

$abroad = [pscustomobject]@{
    travel = [pscustomobject]@{ destination='United Kingdom'; method='Airstrip'; departed_at=$now-7000; arrival_at=$now-100; time_left=0 }
    status = [pscustomobject]@{ state='Abroad' }
}
$ctx = Convert-TornTravelContext -Payload $abroad -CountriesConfig $countries -NowEpoch $now
Assert-Equal 'Abroad destination normalized' ([string]$ctx.destinationCountryId) 'united_kingdom'
Assert-Equal 'Abroad state is abroad' ([string]$ctx.state) 'abroad'
Assert-True 'Abroad foreign filter stays active' ([bool]$ctx.filterActive)
Assert-True 'Missing bars remain unresolved instead of invented' ($null -eq $ctx.energy -and $null -eq $ctx.nerve)

$returning = [pscustomobject]@{
    travel = [pscustomobject]@{ destination='Torn'; method='Airstrip'; arrival_at=$now+400; time_left=400 }
    status = [pscustomobject]@{ state='Traveling' }
}
$ctx = Convert-TornTravelContext -Payload $returning -CountriesConfig $countries -NowEpoch $now
Assert-Equal 'Return flight is identified' ([string]$ctx.state) 'returning'
Assert-True 'Return flight releases foreign destination filter' (-not [bool]$ctx.filterActive)
Assert-Equal 'Return destination country is empty' ([string]$ctx.destinationCountryId) ''

$unknown = [pscustomobject]@{
    travel = [pscustomobject]@{ destination='Somewhere New'; arrival_at=$now+500; time_left=500 }
    status = [pscustomobject]@{ state='Traveling' }
}
$ctx = Convert-TornTravelContext -Payload $unknown -CountriesConfig $countries -NowEpoch $now
Assert-Equal 'Unknown traveling destination is explicit' ([string]$ctx.state) 'traveling_unknown'
Assert-True 'Unknown destination does not force an unsafe country filter' (-not [bool]$ctx.filterActive)

Write-Host 'Travel context and bar normalization tests passed.' -ForegroundColor Green
exit 0
