$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$filterStatePath = Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1'
$projectorPath = Join-Path $ProjectRoot '@Resources\Scripts\ProjectCollectedState.ps1'
$countriesPath = Join-Path $ProjectRoot 'config\countries.json'

foreach ($path in @($filterStatePath,$projectorPath,$countriesPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing presentation projection fixture: $path" }
}

$tokens=$null; $parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($filterStatePath,[ref]$tokens,[ref]$parseErrors)
if (@($parseErrors).Count -gt 0) { throw ('FilterState.ps1 parse error: ' + $parseErrors[0].Message) }
$tokens=$null; $parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($projectorPath,[ref]$tokens,[ref]$parseErrors)
if (@($parseErrors).Count -gt 0) { throw ('ProjectCollectedState.ps1 parse error: ' + $parseErrors[0].Message) }

$projector = Get-Content -LiteralPath $projectorPath -Raw
if ($projector -notmatch '\$countries\.countries\s*\|\s*Where-Object\s*\{\s*\$_\.collect\s*-eq\s*\$true\s*\}') {
    throw 'ProjectCollectedState must project travel fields for every collect=true country.'
}

. $filterStatePath -SkipMain

$itemMetadata = [pscustomobject]@{}
$itemMetadata | Add-Member NoteProperty '206' ([pscustomobject]@{ name='Xanax'; category='Drug' })
$observedMarkets = [pscustomobject]@{}
$observedMarkets | Add-Member NoteProperty 'canada:206' ([pscustomobject]@{ providerName='Provider Xanax' })
$engine = [pscustomobject]@{ itemMetadata=$itemMetadata; observedMarkets=$observedMarkets }

$state = @{ Opportunity1Key='canada:206'; Opportunity1Name='' }
$name = Resolve-OpportunityPresentationName -State $state -Engine $engine -Index 1
if ($name -ne 'Xanax') { throw "Blank opportunity name did not prefer local metadata; got '$name'." }

$placeholderState = @{ Opportunity1Key='canada:206'; Opportunity1Name='Item 206' }
$name = Resolve-OpportunityPresentationName -State $placeholderState -Engine $engine -Index 1
if ($name -ne 'Xanax') { throw "Generic Item <id> placeholder did not yield to local metadata; got '$name'." }

$engineProviderOnly = [pscustomobject]@{ itemMetadata=[pscustomobject]@{}; observedMarkets=$observedMarkets }
$name = Resolve-OpportunityPresentationName -State $state -Engine $engineProviderOnly -Index 1
if ($name -ne 'Provider Xanax') { throw "Blank opportunity name did not fall back to provider label; got '$name'." }

$emptyMarket = [pscustomobject]@{}
$emptyMarket | Add-Member NoteProperty 'canada:206' ([pscustomobject]@{ providerName='' })
$engineIdOnly = [pscustomobject]@{ itemMetadata=[pscustomobject]@{}; observedMarkets=$emptyMarket }
$name = Resolve-OpportunityPresentationName -State $state -Engine $engineIdOnly -Index 1
if ($name -ne 'Item 206') { throw "Blank opportunity name did not retain explicit item-id fallback; got '$name'." }

$poolState = @{ OpportunityCount='12'; Opportunity12Key='canada:206'; Opportunity12Name='Item 206' }
Repair-OpportunityPresentationNames -State $poolState -Engine $engine
if ($poolState['Opportunity12Name'] -ne 'Xanax') { throw 'Presentation repair did not extend beyond the eight visible cards.' }

$countries = Get-Content -LiteralPath $countriesPath -Raw | ConvertFrom-Json
$travelState = @{}
$prefs = [pscustomobject]@{ travelMode='airstrip' }
Project-AllCollectedTravelSeconds -State $travelState -Countries $countries -Preferences $prefs
foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true })) {
    $prefix = Get-FilterStateCountryPrefix ([string]$country.id)
    $key = $prefix + 'TravelSeconds'
    if (-not $travelState.ContainsKey($key) -or [long]$travelState[$key] -le 0) {
        throw "Missing positive flag-tooltip travel projection for $($country.id) ($key)."
    }
}

Write-Host 'Full-pool opportunity name fallback and all-country flag travel-time projection tests passed.' -ForegroundColor Green
exit 0