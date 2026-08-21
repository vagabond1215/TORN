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

Travel Assistant v1 is implemented for **Xanax in the United Kingdom and Japan**. YATA is the live foreign stock/price source. Torn Item Market is the resale reference when a local API key is configured. The Rainmeter UI, history/cycle engine, price-aware recommendation model, profitability/trip-economics guards, generated graphs, installer, historical tooling, and deterministic tests are present.

Business remains configured but intentionally disabled until its ticket/free-company economics are explicitly modeled. The committed historical seed remains intentionally empty until a trustworthy structured source is verified.

### Deterministic Windows validation — PASS

The target Windows machine ran the deterministic suite from commit `368562c9257d8defef9b3c55f44bbf34e5e2ea4a` with all previously documented checks passing. Do not rerun that broad suite unless a later functional source/config change specifically requires it.

### Bounded live environment validation — PASS

The target machine completed the bounded YATA/updater/graph/storage validation from commit `03d02f045ef97aafffa5855620abf39dea709489`. Do not repeat that broad live pass unless a later defect specifically requires it.

### Installation — PASS

`Install.ps1` created ignored local settings and successfully linked the Rainmeter skin directory to the repository source. No reinstall is required; the installed skin is a junction.

### Torn Item Market / local API key — PASS

A local Torn API key is configured in ignored `config/settings.local.json`.

Observed:

- Torn Item Market returned HTTP `200` through `curl.exe`;
- Windows PowerShell `Invoke-RestMethod` hung specifically against `api.torn.com` on this target machine;
- production Torn Item Market requests were rerouted through bounded `curl.exe` while YATA stayed unchanged;
- production updater/finalizer exits `0` and writes a fresh `torn_itemmarket` resale cache;
- Rainmeter consumes profitability-aware state instead of the no-key fallback.

### Rainmeter rendering / polling — PASS

Direct target-machine evidence confirms:

- UK renders above Japan;
- both graphs render and align;
- live stock and foreign prices render;
- encoding/mojibake is fixed;
- sparse history remains conservative with no invented departure timing;
- observed sellout history persists and renders;
- Japan retained its observed `Last Sold Out` around `01:06`;
- UK subsequently observed a real live restock and sellout transition;
- the visible header shows last successful update plus next-poll countdown and reports stale state if polling stops;
- manual updater/heartbeat output is correct;
- the initial Rainmeter polling failure was isolated to incorrect RunCommand measure declaration (`Measure=RunCommand`);
- both measures now use documented `Measure=Plugin` / `Plugin=RunCommand` configuration;
- `tests/Validate-RainmeterSkin.ps1` passes on the target machine;
- after the fix, Rainmeter completes automatic production polls without manual PowerShell and advances the heartbeat/live state.

### Rainmeter log / resource sanity — PASS

Historical log entries before the RunCommand fix showed invalid-measure and missing-`MeasureUpdate` errors. After the corrected skin was refreshed at approximately `10:55:42` and `10:56:49`, no new Travel Assistant warnings/errors were observed while automatic polling continued through at least `10:59:54`.

A between-polls process/storage snapshot confirmed:

- no continuously running Travel Assistant PowerShell process;
- runtime plus generated storage: `7` files / `6,835` bytes total;
- generated directory contains only `uk-stock.png`, `jp-stock.png`, `state.kv`, and `last-update.txt`;
- generated graph/output files update in place instead of accumulating.

Do not wait for additional real restock/sellout cycles merely to complete acceptance.

## Immediate next task

Do **not** rerun broad deterministic/live validation. Only two direct interaction checks remain:

1. Click the mode selector repeatedly and confirm the visible sequence is `Airstrip -> WLT -> Standard -> Airstrip`; Business must never appear.
2. Click a timing/status/external-verification area and confirm Weav3r Travel Stock opens.

If both pass, mark this run `COMPLETED` and update the status/handoff documents. No further local tests are required unless one of those interactions exposes a defect.

## Defect handling

If either final interaction fails, capture only the exact visible behavior or relevant new Rainmeter log line and fix repository code through the GitHub connector. Rerun only the narrowest check for that defect.

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

Mark this run `COMPLETED` only after the remaining selector and external-link checks above are truthfully observed.

Historical backfill, further real-cycle learning, longer-term profitability calibration, and Business economics may remain follow-up work after v1 operational acceptance.
