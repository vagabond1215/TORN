# Travel Assistant Tools

These scripts support **bounded provider discovery and seed-data preparation**. They are not part of the one-second Rainmeter UI path.

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

## Validation boundary

The GitHub connector can create/review these scripts, but running them against live providers and Windows PowerShell is a local validation task. Record live results in `docs/IMPLEMENTATION_STATUS.md` or the active run handoff before treating a historical source as trusted.
