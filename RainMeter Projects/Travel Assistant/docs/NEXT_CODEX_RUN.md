# Next Codex Run: Travel Assistant v1 Rainmeter Acceptance

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

The target Windows machine has executed the complete deterministic/static suite successfully from commit:

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

The target Windows machine also executed the bounded live environment validation from repository commit:

```text
03d02f045ef97aafffa5855620abf39dea709489
```

Command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-LiveEnvironment.ps1 -SkipTests
```

Observed result: **PASS for the required bounded live/provider/updater checks**.

Evidence captured locally:

- YATA request succeeded in about 3.5 seconds;
- United Kingdom Xanax: stock `0`, foreign price `$763,144`, source timestamp `1787286888`;
- Japan Xanax: stock `9`, foreign price `$679,492`, source timestamp `1787286887`;
- Torn Item Market lookup intentionally skipped because no local API key was configured; this is permitted and is not a live-validation failure;
- serialized production updater/finalizer exited `0` in about 1.7 seconds;
- runtime storage grew from `0 B` to `1.37 KiB`;
- generated storage grew from `0 B` to `1.96 KiB`, confirming graph generation produced bounded output;
- Rainmeter was running with about `38.58 MiB` total process working set; this is whole-process memory, not Travel Assistant-only attribution;
- the Travel Assistant skin path was not installed yet, which is the expected remaining boundary before `Install.ps1` is run.

No repository defect was identified by this live pass. Do not repeat it unless a later code change or Rainmeter defect specifically requires another updater/provider check.

## Immediate next task

Install the development skin on the target Windows machine:

```powershell
cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Capture the complete installer output.

Expected behavior:

- local runtime/generated directories remain available;
- ignored `config/settings.local.json` is created from the template only if absent;
- `Documents\Rainmeter\Skins\Travel Assistant` becomes a junction to the repository source;
- an unrelated existing directory is not overwritten.

After a successful install, refresh Rainmeter and load:

```text
Travel Assistant\TravelAssistant.ini
```

Then validate the remaining acceptance criteria in [`WINDOWS_VALIDATION.md`](./WINDOWS_VALIDATION.md), especially:

- UK above Japan;
- graphs render and align;
- current stock and foreign prices appear plausibly;
- `Last Sold Out` reflects only observed history;
- insufficient history shows learning/check-external behavior rather than invented timing;
- Standard/Airstrip/WLT mode cycling works, with Airstrip default;
- Business remains disabled;
- clicking external verification opens Weav3r Travel Stock;
- no Lua, RunCommand, missing-image, PowerShell, or unsupported-option errors appear in Rainmeter logs;
- no continuously running Travel Assistant PowerShell process or abnormal storage growth appears;
- Rainmeter remains responsive under normal idle use.

Do not wait for or manufacture an actual restock/sellout merely to complete validation. Actual-cycle observation may remain a shadow-mode follow-up.

## Defect handling

When a Rainmeter/local defect appears:

1. capture the exact installer/console output or relevant Rainmeter log lines;
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
- profitability defaults remain provisional until live use provides calibration evidence;
- without a local Torn API key, live Item Market profitability calibration remains unavailable, but the system must still remain conservative rather than inventing economics.

## Completion criteria for this ACTIVE run

Mark this run `COMPLETED` only after all of the following are truthfully observed on the target machine:

- bounded live environment validation has succeeded — **satisfied on tested SHA `03d02f045ef97aafffa5855620abf39dea709489`**;
- the skin installs and loads in Rainmeter;
- both UK/Japan panels render correctly;
- graphs render successfully;
- Standard/Airstrip/WLT selector behavior works with Airstrip default;
- live stock/foreign-price values behave plausibly;
- low-confidence states do not invent departure timing;
- Rainmeter logs contain no material Travel Assistant errors;
- runtime/generated storage remains small and bounded;
- observed resource behavior is acceptable for continuous desktop use.

Historical backfill, Torn Item Market validation with a locally configured key, actual restock/sellout shadow observation, and longer-term calibration may remain follow-up work after v1 is operationally validated, provided the model remains conservative while evidence is sparse.
