# Next Codex Run: Travel Assistant v1 Rainmeter Acceptance

**Status: ACTIVE**

This is the authoritative current execution handoff for `RainMeter Projects/Travel Assistant/`. Work remains **connector-first**. Use local/Codex execution only for Windows/Rainmeter behavior the GitHub connector cannot establish.

Before changing code, read:

1. `../AGENTS.md`
2. `README.md`
3. this file
4. `ARCHITECTURE.md`
5. `IMPLEMENTATION_STATUS.md`
6. `WINDOWS_VALIDATION.md`

## Current checkpoint

Travel Assistant v1 is implemented for **Xanax in the United Kingdom and Japan**. YATA is the live foreign stock/price source. Torn Item Market is the optional resale reference when a local API key is configured. The Rainmeter UI, history/cycle engine, price-aware recommendation model, profitability/trip-economics guards, generated graphs, installer, historical tooling, and deterministic tests are present.

Business remains configured but intentionally disabled until its ticket/free-company economics are explicitly modeled. The committed historical seed remains intentionally empty until a trustworthy structured source is verified.

### Deterministic Windows validation — PASS

The target Windows machine ran:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

from commit `368562c9257d8defef9b3c55f44bbf34e5e2ea4a` with all deterministic/static tests passing, including historical tooling/cycle reconstruction, seed importer/provenance tests, 19 production recommendation-model checks, final profitability/restock guards, and independent restock-display checks.

Do not rerun that suite unless a later functional source/config change requires it.

### Bounded live environment validation — PASS

The target Windows machine ran:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-LiveEnvironment.ps1 -SkipTests
```

from commit `03d02f045ef97aafffa5855620abf39dea709489`.

Observed evidence:

- YATA succeeded in about 3.5 seconds;
- UK Xanax: stock `0`, foreign price `$763,144`, source timestamp `1787286888`;
- Japan Xanax: stock `9`, foreign price `$679,492`, source timestamp `1787286887`;
- Torn Item Market intentionally skipped because no local API key was configured; this is permitted;
- serialized production updater/finalizer exited `0` in about 1.7 seconds;
- runtime storage grew from `0 B` to `1.37 KiB`;
- generated storage grew from `0 B` to `1.96 KiB`, confirming production graph generation;
- Rainmeter was running at about `38.58 MiB` whole-process working set.

Do not repeat this live pass unless a later defect specifically requires another provider/updater check.

### Installation — PASS

The target Windows machine pulled repository head `80c4711` and ran:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Observed evidence:

- ignored `config/settings.local.json` was created from the example template;
- `C:\Users\vagab\OneDrive\Documents\Rainmeter\Skins\Travel Assistant` was successfully linked to `C:\Codex\TORN\RainMeter Projects\Travel Assistant`;
- installer completed normally.

The installer exposed one cosmetic Windows PowerShell encoding issue: its Unicode arrow rendered as `â†’`. The connector replaced that output literal with ASCII `->` in commit `3585d0995a302855cee68939a5437977e2fbc739`. This did not affect junction creation or runtime behavior.

## Immediate next task

Pull current `main`, then refresh Rainmeter and load:

```text
Travel Assistant\TravelAssistant.ini
```

No reinstall is required because the installed skin is a junction to the repository source.

Validate only the remaining Rainmeter acceptance criteria:

- UK above Japan;
- both graphs render and align;
- live stock and foreign prices appear plausibly;
- `Last Sold Out` contains only observed history;
- sparse history produces learning/check-external behavior rather than invented departure timing;
- travel mode cycles `Standard -> Airstrip -> WLT`, with Airstrip default on a clean preference state;
- Business is not offered;
- external verification opens Weav3r Travel Stock;
- Rainmeter log is free of material Travel Assistant Lua, RunCommand, missing-image, PowerShell, or unsupported-option errors;
- no continuously running Travel Assistant PowerShell process or abnormal runtime/generated storage growth is observed;
- Rainmeter remains responsive.

Do not wait for or manufacture an actual restock/sellout to complete this run. Actual-cycle observation may remain follow-up work.

## Defect handling

When a local/Rainmeter defect appears, capture exact console output or relevant Rainmeter log lines without secrets. Fix repository code through the GitHub connector where practical and rerun only the narrowest relevant local check.

## Safety/model invariants

Preserve every invariant in `AGENTS.md`, especially:

- prefer no recommendation over a weak one;
- actual restocks/sellouts are observed history, not forecasts;
- foreign price is first-class depletion evidence;
- stale stock or resale data suppress timing;
- profitability suppresses departure advice but not useful restock/history information;
- current live depletion may shorten but never expand conservative safety;
- runtime/generated data and credentials remain local/ignored;
- Business remains disabled until economics are explicit.

## Completion criteria

Mark this run `COMPLETED` only after the installed skin is actually loaded in Rainmeter and the remaining rendering, selector, live-value, log, and resource checks above are truthfully observed.

Historical backfill, optional Torn Item Market validation with a local key, actual restock/sellout shadow observation, and longer-term calibration may remain follow-up work after v1 operational acceptance.
