# Travel Assistant Tools

These scripts support **bounded provider discovery, seed-data preparation, and local validation**. They are not part of the one-second Rainmeter UI path.

## `Probe-DroqsDb.ps1`

Queries the documented DroqsDB public metadata/current-snapshot endpoints and reports the live contract that the machine can actually reach. It does not alter committed seed data.

Typical use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Probe-DroqsDb.ps1
```

Optional runtime-only capture:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Probe-DroqsDb.ps1 -SaveProbe
```

Saved probe output goes under `data/runtime/provider-probes/` and is ignored by Git.

The probe deliberately does **not** assume that a documented historical endpoint is live. It first asks `/api/public/v1/meta` for the provider's current advertised endpoint/history metadata and reports what it finds.

## `Import-TravelPlannerHistory.ps1`

A bounded adapter for a verified deployment exposing the read-only history contract documented by the open-source `shab00m/torn-travel-planner` project:

```text
GET /api/history/:country/:itemId?hours=...
```

Usage requires an explicit deployment base URL; the repository does not assume or scrape one:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Import-TravelPlannerHistory.ps1 `
  -BaseUrl https://verified.example `
  -Hours 168
```

The default is **preview only**. It makes two bounded history requests (UK Xanax and Japan Xanax), normalizes the returned `yata_ts / quantity / cost` points, writes candidate files under ignored `data/runtime/historical-imports/`, and derives cycles from observed transitions.

Only after reviewing the host/usage expectations and runtime-only candidate files should the explicit import switch be used:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Import-TravelPlannerHistory.ps1 `
  -BaseUrl https://verified.example `
  -Hours 168 `
  -ImportToSeed
```

The command intentionally caps history requests at 720 hours. It never imports the provider's safe-window predictions as historical facts.

## `Build-CyclesFromObservations.ps1`

Takes normalized observation JSONL and derives completed cycles only from observed transitions:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-CyclesFromObservations.ps1 `
  -InputPath .\candidate-observations.jsonl `
  -OutputPath .\candidate-cycles.jsonl
```

The script recognizes:

- `0 -> positive` as an observed restock;
- `positive -> 0` as an observed sellout;
- previous observed sellout -> next observed restock as the restock delay.

It does not turn provider forecasts into historical events.

## `Import-SeedHistory.ps1`

Validates and merges already-normalized observations/cycles into `data/seed/` with deduplication and provenance metadata.

Example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Import-SeedHistory.ps1 `
  -ObservationPath .\candidate-observations.jsonl `
  -CyclePath .\candidate-cycles.jsonl `
  -SourceName droqsdb `
  -SourceUrl https://droqsdb.com/api-docs `
  -Notes "Bounded UK/Japan Xanax bootstrap after live contract verification"
```

The importer rejects files under `tests/` and source names containing `synthetic`, `fixture`, or `test` unless `-AllowSynthetic` is explicitly supplied. **Do not use `-AllowSynthetic` for committed production seed data.**

## `Validate-LiveEnvironment.ps1`

Runs a deliberately bounded local environment pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-LiveEnvironment.ps1
```

It:

- runs the deterministic/static test suite unless `-SkipTests` is used;
- performs one YATA live-stock request;
- performs one Torn Item Market request when a local API key is configured;
- runs one serialized production updater pass unless `-SkipUpdater` is used;
- reports runtime/generated directory size before/after the updater;
- checks the expected Rainmeter skin path/junction;
- reports whole-Rainmeter-process working-set memory when Rainmeter is running.

It intentionally does **not** loop provider requests or claim Travel Assistant-only RAM attribution. Use it to get the first real Windows/runtime evidence without turning validation into another persistent process.

## Tests

The shortest deterministic validation entry point is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

See `../tests/README.md` for individual validation layers.

## Validation boundary

The GitHub connector can create/review these scripts, but running them against live providers and Windows PowerShell is a local validation task. Record live results in `docs/IMPLEMENTATION_STATUS.md` or the active run handoff before treating a historical source, Rainmeter behavior, or resource profile as trusted.
