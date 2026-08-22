$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$optimizerPath = Join-Path $PSScriptRoot 'OptimalRoute.ps1'
if (-not (Test-Path -LiteralPath $optimizerPath)) { throw 'OptimalRoute.ps1 is missing.' }

. $optimizerPath -SkipMain

$engine = Read-OptimalJson $EngineStateFile
$travelState = 'unknown'
if ($null -ne $engine -and $engine.PSObject.Properties['travelContext']) {
    $travelState = [string](Get-OptimalProperty $engine.travelContext 'state')
}

if ($travelState -in @('traveling_unknown','abroad_unknown')) {
    $settings = Read-OptimalJson (Join-Path $ConfigDir 'settings.example.json')
    $preferences = Read-UiPreferences
    $basisPercent = 100
    if ([bool]$preferences.use95PercentMarketValue) { $basisPercent = 95 }
    $state = Read-OptimalStateKv $StateKvFile
    if ($state.Count -gt 0) {
        Write-OptimalProjection -State $state -Route $null -Message 'Foreign destination unresolved - route optimizer paused until Torn reports a recognized destination' -BasisPercent $basisPercent -TravelState $travelState
        Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
    }
    if ($null -ne $engine) {
        if (-not $engine.PSObject.Properties['optimizer']) { $engine | Add-Member NoteProperty optimizer ([pscustomobject]@{}) }
        Set-OptimalProperty $engine.optimizer 'lastRunAt' ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        Set-OptimalProperty $engine.optimizer 'blockedTravelState' $travelState
        Set-OptimalProperty $engine.optimizer 'selectedCountryId' ''
        Set-OptimalProperty $engine.optimizer 'selectedQuantity' 0
        Set-OptimalProperty $engine.optimizer 'selectedCapacity' 0
        Set-OptimalProperty $engine.optimizer 'selectedExpectedTripProfit' 0L
        Write-OptimalJsonAtomic -Path $EngineStateFile -Value $engine
    }
    return
}

& $optimizerPath
