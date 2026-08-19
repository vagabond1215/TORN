# Travel Assistant Tests and Fixtures

These fixtures are **synthetic validation data**, not historical evidence and not seed/training data.

They exist so provider normalization, history deduplication, profitability gating, recommendation behavior, seed import behavior, final display/economics guards, and historical tooling can be checked without depending exclusively on live web services.

## Fixtures

- `fixtures/yata-export.sample.json` — representative YATA-style UK/Japan Xanax stock payload.
- `fixtures/cycles-safe.jsonl` — synthetic high-price/long-availability UK cycles with a conservative Airstrip overlap.
- `fixtures/cycles-fast.jsonl` — synthetic low-price/fast-depletion UK cycles designed to have no conservative overlap and require best-odds timing.
- `fixtures/normalized-observations.sample.jsonl` — normalized UK Xanax observations containing two observed restock/sellout cycles for the historical pipeline tests.

Do **not** copy fixture data into `data/seed/` or runtime history.

## Run all deterministic/static tests

From `RainMeter Projects/Travel Assistant/` on Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

The runner currently executes:

1. `Validate-TravelAssistant.ps1`
2. `Validate-HistoricalTools.ps1`
3. `Run-HistoricalPipelineTests.ps1`
4. `Run-SeedImporterTests.ps1`
5. `Run-ModelTests.ps1`
6. `Run-FinalizeStateTests.ps1`

No test in this sequence is intended to require a live web provider.

## Static validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelAssistant.ps1
```

This checks JSON contracts, JSONL parseability, required project files, travel-mode/economics configuration, finalizer settings, PowerShell parser errors, basic Rainmeter skin structure, serialized updater/finalizer routing, and runtime/generated Git ignore rules. It does not prove that Rainmeter can load/run the skin or that live provider calls succeed.

## Historical observation pipeline

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-HistoricalPipelineTests.ps1
```

This executes the production `tools/Build-CyclesFromObservations.ps1` against a normalized synthetic observation history in an isolated temporary directory and verifies that:

- observed `0 -> positive` becomes a restock;
- observed `positive -> 0` becomes an actual sellout;
- availability duration uses observed timestamps;
- the next completed cycle carries the previous actual sellout -> restock delay;
- the foreign purchase price from the restock observation is retained.

## Seed importer tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-SeedImporterTests.ps1
```

This copies the production seed importer plus item/country config into a temporary isolated project tree. It verifies:

- normalized observations/cycles import successfully;
- metadata coverage matches the imported files;
- repeated identical imports do not duplicate seed observations/cycles;
- synthetic/test provenance is rejected by default;
- a rejected import does not mutate the isolated seed truth.

It does **not** modify the repository's real `data/seed/` directory.

## Production-model fixture tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ModelTests.ps1
```

`Run-ModelTests.ps1` parses the actual production `UpdateTracker.ps1`, extracts the named production functions through PowerShell's AST, and executes those exact function bodies against synthetic fixture data. It deliberately does **not** copy a second recommendation implementation into the test suite.

Current scenarios cover:

- YATA observation normalization;
- seed/runtime completed-cycle deduplication;
- high-price/long-stock `SAFE_WINDOW` behavior;
- low-price/fast-stock `BEST_ODDS` behavior;
- fee-adjusted `LOW_MARGIN` and `UNPROFITABLE` suppression;
- stale-source suppression;
- travel-mode-dependent departure timing;
- current-cycle fast depletion closing an otherwise historically safe live opportunity.

## Final state / trip-economics guard tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FinalizeStateTests.ps1
```

This runs the production `FinalizeState.ps1` in an isolated temporary project tree. It verifies that the post-processing layer:

- preserves an observed live-restock timestamp even when profitability is `LOW_MARGIN`;
- suppresses timing when the cached resale reference is stale;
- applies UK Standard cash travel cost and base capacity to total-trip profitability;
- can downgrade a borderline Standard opportunity that passed the original per-item threshold;
- leaves a healthy zero-cost Airstrip timing recommendation intact;
- suppresses timing if Business mode is manually forced before its ticket/free-company economics are resolved.

This layer is deliberately independent from live provider calls so its economics and display guards are deterministic.

## Historical-tool validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-HistoricalTools.ps1
```

This checks:

- PowerShell parsing for historical/bootstrap/analysis/local-validation tools;
- seed JSON/JSONL parseability;
- required normalized observation `sourceTimestamp` semantics;
- seed metadata coverage counts against the actual committed files;
- completed-cycle timestamp/availability consistency;
- that committed seed provenance does not identify synthetic/test sources.

Historical-provider **network** probing is separate and explicitly opt-in:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Probe-DroqsDb.ps1
```

Use `-SaveProbe` only when a runtime-only capture under `data/runtime/provider-probes/` is useful for debugging. Probe output is ignored by Git and must not be treated as seed history by itself.

## Runtime validation boundary

These tests are deterministic/static assets authored through the connector. Their results must not be described as passing until they have actually executed under Windows PowerShell.

A release-quality validation pass additionally needs Windows/Rainmeter because connector-only work cannot establish:

- that Rainmeter loads the `.ini` without log errors;
- RunCommand/Lua interaction on the installed Rainmeter build;
- `System.Drawing` graph generation under the local PowerShell runtime;
- live YATA and Torn API behavior from the user's machine;
- live historical-provider endpoint behavior from the user's network;
- junction installation behavior;
- actual CPU/RAM/disk usage over time.

See `../docs/WINDOWS_VALIDATION.md` for the smallest required local pass.
