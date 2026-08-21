# Next Codex Run: Travel Assistant v1 Live Validation

**Status: ACTIVE**

This is the authoritative current execution handoff for `RainMeter Projects/Travel Assistant/`. The filename is historical: work remains **connector-first**. Use Codex/local execution only for concrete Windows/Rainmeter actions the connector cannot perform.

Read in this order before editing:

1. [`../AGENTS.md`](../AGENTS.md)
2. [`README.md`](./README.md)
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md)
4. [`IMPLEMENTATION_STATUS.md`](./IMPLEMENTATION_STATUS.md)
5. [`WINDOWS_VALIDATION.md`](./WINDOWS_VALIDATION.md)

## Current checkpoint

Travel Assistant v1 is implemented for **Xanax in the United Kingdom and Japan** with generic item/country/provider internals, YATA live stock and foreign-price collection, Torn Item Market resale support, price-aware historical recommendations, profitability gating, restock/sellout history, generated stock graphs, and a Rainmeter UI.

The target Windows machine has now executed the complete deterministic/static suite successfully from commit:

```text
368562c9257d8defef9b3c55f44bbf34e5e2ea4a
```

The following all passed locally:

- `Validate-TravelAssistant.ps1`;
- `Validate-HistoricalTools.ps1` — 11 checks;
- `Run-HistoricalPipelineTests.ps1`;
- `Run-SeedImporterTests.ps1`;
- `Run-ModelTests.ps1` — 19 production-model checks;
- `Run-FinalizeStateTests.ps1`;
- `Run-RestockDisplayTests.ps1`.

Do not rerun or redesign those tests unless a subsequent code change requires it.

## Immediate next task

The next required evidence is the bounded live Windows/provider pass.

From the repository root, synchronize first:

```powershell
cd C:\Codex\TORN
git pull --ff-only origin main
git rev-parse --short HEAD
```

Then:

```powershell
cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-LiveEnvironment.ps1 -SkipTests
```

This should perform only a bounded amount of work:

- one YATA request for UK/Japan Xanax stock and foreign price;
- one Torn Item Market request if a local API key is configured;
- one serialized production updater/finalizer pass;
- graph generation through `System.Drawing`;
- runtime/generated storage-size reporting;
- Rainmeter install/process checks.

If no Torn API key is configured, the Item Market check may be skipped without treating the whole live pass as failed. Do not expose or commit API keys.

## After the live environment pass

If the live updater/provider pass succeeds, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Then refresh Rainmeter and load:

```text
Travel Assistant\TravelAssistant.ini
```

Verify the items in [`WINDOWS_VALIDATION.md`](./WINDOWS_VALIDATION.md), especially:

- UK above Japan;
- graphs render and align;
- current stock and foreign prices appear;
- `Last Sold Out` reflects only observed history;
- insufficient history shows learning/check-external behavior rather than invented timing;
- Standard/Airstrip/WLT mode cycling works, with Airstrip default;
- Business remains disabled;
- clicking external verification opens Weav3r Travel Stock;
- no Lua, RunCommand, missing-image, PowerShell, or unsupported-option errors appear in Rainmeter logs;
- no continuously running Travel Assistant PowerShell process or abnormal storage growth appears.

## Defect handling

When a live/local defect appears:

1. capture the exact console output or relevant Rainmeter log lines;
2. do not include API keys or other secrets;
3. fix repository code through the GitHub connector where practical;
4. rerun only the narrowest relevant local validation;
5. use broader Codex/local debugging only if the connector cannot perform the necessary repository work or the defect requires direct machine inspection.

## Important invariants

Preserve all `AGENTS.md` requirements. In particular:

- no recommendation is better than a weak/unsafe recommendation;
- actual sellouts/restocks must remain distinct from forecasts;
- foreign price must materially affect depletion evidence;
- low-margin/unprofitable states suppress departure timing but may retain informational restock/history;
- stale stock or resale data must suppress timing;
- current live depletion may shorten safety, never extend it beyond supporting history;
- runtime data, generated graphs, caches, and credentials remain local/ignored;
- v1 UI remains UK/Japan Xanax only;
- Business remains disabled until its economics are explicitly modeled.

## Known intentional limitations

- committed historical seed remains empty until a trustworthy structured history source/deployment is verified;
- current production price similarity uses bounded near-price cohorts rather than a fully continuous weighted model;
- time-of-day/day-of-week cohorts are descriptive only until enough real data supports promotion;
- secondary live-provider disagreement checking is not enabled yet;
- first launch during an already-live restock cannot know the exact restock start until Travel Assistant observes its own transition;
- Windows Clock alarm integration remains deferred;
- profitability defaults remain provisional until live use provides calibration evidence.

## Completion criteria for this ACTIVE run

Mark this run `COMPLETED` only after all of the following are truthfully observed on the target machine:

- bounded live environment validation succeeds or any defects are resolved;
- the skin installs and loads in Rainmeter;
- both UK/Japan panels render correctly;
- graphs render successfully;
- Standard/Airstrip/WLT selector behavior works with Airstrip default;
- live stock/foreign-price values behave plausibly;
- low-confidence states do not invent departure timing;
- Rainmeter logs contain no material Travel Assistant errors;
- runtime/generated storage remains small and bounded;
- observed resource behavior is acceptable for continuous desktop use.

Historical backfill and longer-term shadow calibration may remain follow-up work after v1 is operationally validated, provided the model remains conservative while evidence is sparse.
