# Next Codex Run: Travel Assistant v1 Foundation

**Status: ACTIVE**

This is the authoritative current implementation scope for `RainMeter Projects/Travel Assistant/`. The filename is historical: this run is **connector-first**, and Codex/local execution is required only for capabilities the connector cannot perform, especially Windows/Rainmeter runtime validation.

Read [`../AGENTS.md`](../AGENTS.md), [`README.md`](./README.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md), and [`IMPLEMENTATION_STATUS.md`](./IMPLEMENTATION_STATUS.md) before editing.

## Goal

Complete and validate the first usable Travel Assistant implementation for **Xanax in the United Kingdom and Japan** with a lightweight Rainmeter UI and a generic underlying travel-opportunity engine.

The implementation must prefer conservative/no recommendations over false precision. It is structurally ready for more items and destinations later, but v1 UI scope remains UK/Japan Xanax.

The connector-side repository implementation is substantially built. The largest remaining acceptance boundary is executing the authored tests and the installed skin on the target Windows/Rainmeter environment, then feeding any defects back into the repository.

## Repository / local scope

Repository subtree:

```text
RainMeter Projects/Travel Assistant/
```

Expected local source location:

```text
C:\Codex\TORN\RainMeter Projects\Travel Assistant\
```

Do not modify other TORN project subtrees.

## Start

From the repository root:

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git status -sb
git rev-parse HEAD
git rev-parse origin/main
```

If the worktree is dirty or local/remote `main` diverge, stop and inspect rather than resetting, rebasing, or force-pushing automatically.

---

# Phase 1 — Project skeleton and contracts

Maintain the compact durable structure already established while preserving the logical separation defined in `ARCHITECTURE.md`.

Current direction:

```text
Travel Assistant/
  Readme.md
  AGENTS.md
  .gitignore
  TravelAssistant.ini
  Install.ps1
  config/
    settings.example.json
    settings.local.example.json
    items.json
    countries.json
    travel-modes.json
    providers.json
  data/
    seed/
      metadata.json
      observations.jsonl
      cycles.jsonl
      README.md
    runtime/                 # ignored
  @Resources/
    Scripts/
      RunUpdate.ps1
      UpdateTracker.ps1
      FinalizeState.ps1
      StateReader.lua
  tools/
  tests/
  docs/
```

Requirements:

- default travel mode: `airstrip`;
- configured modes: `standard`, `airstrip`, `wlt`, `business`;
- currently enabled selector modes: `standard`, `airstrip`, `wlt`;
- `business` remains configured but disabled until Business Class Ticket opportunity cost or an explicit free-Business company-perk branch is modeled safely;
- configured item: Xanax (`itemId` 206) enabled for v1;
- configured destinations: United Kingdom and Japan enabled for v1;
- use generic item/country/travel-mode/provider structures;
- persistent JSON/JSONL contracts use `schemaVersion: 1`;
- runtime observations/cache/logs/local credentials/generated graph artifacts remain ignored;
- committed examples/templates exist for local-only configuration.

Do not hard-code item/country logic into names like `UKXanaxPredictor`.

---

# Phase 2 — Provider discovery and bounded historical bootstrap

Keep historical-source discovery bounded and provider-specific.

Current production choices:

- live foreign stock / foreign purchase price: structured YATA travel export;
- resale reference: Torn v2 Item Market with a local API key;
- external human verification: Weav3r Travel Stock;
- historical seed: intentionally empty until a specific structured source/deployment is verified for bounded use.

Do **not** implement a browser-render/scrape loop or excessive automated requester.

The repository now contains:

- `tools/Probe-DroqsDb.ps1` for bounded live contract discovery;
- `tools/Import-TravelPlannerHistory.ps1` for an explicitly supplied deployment compatible with a documented read-only YATA-snapshot history contract;
- `tools/Build-CyclesFromObservations.ps1` to derive observed restock/sellout cycles;
- `tools/Import-SeedHistory.ps1` for provenance-aware immutable seed import;
- `tools/Analyze-History.ps1` for descriptive analysis after enough real cycles exist.

### Seed objective

A compact seed is desirable only when the source can establish actual historical observation truth:

- source timestamp;
- stock quantity;
- foreign purchase price;
- country/item identity;
- observed transitions from which actual restocks/sellouts can be derived.

Do not import provider forecasts as historical facts. If reliable backfill is not available, keep the valid empty bootstrap and let runtime learning establish the model.

Do not continuously commit runtime observations back into Git.

---

# Phase 3 — Normalized observations and runtime persistence

Maintain the normalized observation contract:

```json
{
  "schemaVersion": 1,
  "timestamp": 1787168400,
  "country": "united_kingdom",
  "itemId": 206,
  "stock": 1438,
  "foreignPrice": 742000,
  "source": "provider-name",
  "sourceTimestamp": 1787168372
}
```

Requirements:

- explicit timestamp normalization;
- stable country identifiers;
- generic item IDs;
- source/provenance retained;
- `sourceTimestamp` explicitly present in normalized observation/seed contracts;
- local runtime persistence bounded;
- atomic-enough state writes that interruption does not corrupt the whole history/state file;
- append/compact JSONL rather than rewriting a giant monolithic observation array on every poll;
- immutable seed history merges into reads without being copied into mutable runtime state.

---

# Phase 4 — Restock/sellout cycle engine

Detect and summarize completed cycles.

A cycle preserves at least:

```text
country
itemId
foreignPrice
restockAt
restockQuantity
soldOutAt
availabilitySeconds
previousSoldOutAt
restockDelaySeconds
source/provenance
```

Requirements:

- `Last Sold Out` is derived from an actual observed/historical transition;
- observed `0 -> positive` is a restock;
- observed `positive -> 0` is an actual sellout;
- restock/sellout detection tolerates normal polling gaps;
- completed cycles remain useful after raw samples are pruned;
- old high-resolution observations prune without destroying completed-cycle history;
- restock timing remains informationally usable even when profitability suppresses departure advice.

---

# Phase 5 — Price-aware depletion analytics

Foreign price must materially affect comparable-cycle selection.

Use evidence in this priority order:

1. current-cycle observed depletion;
2. same/similar-price historical cycles;
3. nearby-price cycles with decreasing weight;
4. broad destination/item history only as a lower-confidence fallback.

Do not use a universal Xanax sellout duration.

The model must behave sensibly across regimes where low prices can sell out in minutes while sufficiently high prices may remain in stock far longer.

If the current price lies outside useful historical support, return `PRICE_REGIME_UNVERIFIED` rather than extrapolating confidently.

The current v1 implementation uses a bounded near-price cohort. More sophisticated continuous weighting or time-of-day segmentation should be promoted into production only after real history demonstrates a useful, sufficiently sampled pattern.

---

# Phase 6 — Restock variance and departure simulation

For each `country + item`, learn the distribution of time from prior actual sellout to next actual restock.

At minimum derive robust central timing and variation suitable for departure evaluation.

For the active travel mode:

```text
arrival = departure + configuredTravelTime(country, travelMode)
```

Evaluate candidate departure offsets against comparable historical cycles to estimate whether arrival would have occurred while stock was available.

## Informational restock timing

Restock display is independent from the profitability gate.

- while an observed active restock is live, retain that exact observed restock timestamp and display elapsed live time;
- otherwise, if enough completed restock-delay samples exist, a median previous-sellout-to-restock interval may populate the informational restock estimate;
- a low-margin/unprofitable trip may still show restock information while displaying no leave/window advice.

## Conservative safe window

When qualifying comparable historical cycles contain a meaningful common overlap after travel-time conversion, expose:

```text
SAFE_WINDOW
Window opens in: ...
Leave before: ...
```

Do not call a range safe merely because an average says it is likely.

Current-cycle depletion may shorten a historical safe window; it must not extend safety beyond historical evidence.

## Best-odds departure

When restock variation exceeds the reliable availability duration and no conservative overlap exists, find the highest-probability departure point/narrow interval and expose:

```text
BEST_ODDS
Leave in: HH:MM:SS
Estimated hit rate / confidence where useful
```

If the useful interval is effectively a point for UI purposes, do not label it as a window.

---

# Phase 7 — Profitability and trip-economics gate

Before any departure recommendation, determine whether the opportunity supports the configured minimum economics.

Current v1 configuration supports:

- Item Market resale reference;
- Item Market selling fee;
- resale-reference freshness;
- minimum net profit per Xanax;
- minimum net percentage margin;
- minimum total-trip profit;
- conservative base carrying capacity by travel mode;
- optional local `capacityOverride`;
- destination/mode travel cash cost.

The update pipeline is intentionally two-stage:

```text
UpdateTracker.ps1
  - live data/history/model
  - early per-item profitability gate
      ↓
FinalizeState.ps1
  - informational restock finalization
  - resale-cache freshness guard
  - trip-level capacity + travel-cost economics
```

Trip economics use:

```text
netResalePrice = grossResaleReference × (1 - sellingFee)
netProfitPerItem = netResalePrice - foreignPrice
tripNet = (netProfitPerItem × usableCapacity) - travelModeCost
requiredTripProfit = max(minimumTotalTripProfit,
                         minimumProfitPerItem × usableCapacity)
```

When a gate fails, expose `LOW_MARGIN`, `UNPROFITABLE`, or `CHECK_EXTERNAL` as appropriate and clear all departure timing while continuing to collect/use stock, actual sellout, restock, and depletion history.

A stale resale reference must not keep a money-sensitive departure countdown alive indefinitely.

Business remains disabled until its travel cost can be resolved safely as either the current Business Class Ticket opportunity cost or explicit free company travel.

---

# Phase 8 — Confidence and fallback behavior

Recommendation confidence must account for at least:

- stock-source freshness;
- resale-reference freshness for timing advice;
- comparable sample count;
- price-regime similarity;
- restock variability;
- current depletion agreement with history;
- source disagreement when cross-check data exists;
- extrapolation outside observed ranges;
- unresolved travel economics.

Support clear machine-readable states including:

```text
SAFE_WINDOW
BEST_ODDS
TOO_EARLY
WINDOW_CLOSED
INSUFFICIENT_HISTORY
PRICE_REGIME_UNVERIFIED
SOURCE_DISAGREEMENT
LOW_MARGIN
UNPROFITABLE
STALE_DATA
CHECK_EXTERNAL
```

If timing appears relevant but the model cannot verify the opportunity confidently, expose a prominent `CHECK WEAV3R` / external verification state. Make it clickable from Rainmeter to open the Weav3r Travel Stock page in the default browser.

Do not let a stale cached recommendation continue counting down as though it were current.

---

# Phase 9 — Rainmeter UI

Maintain the dark/charcoal skin suitable for a solid-black desktop.

Use vertically aligned destination panels with matching graph widths.

Required information per destination:

```text
COUNTRY
Travel: ...            | Leave / Window: ...
Restock: ...           | Last Sold Out: ...
Stock: ...             | Price: ...
[24-hour stock graph]
Recommendation / confidence state
```

Requirements:

- UK above Japan;
- no displayed clock required;
- use relative timers (`Leave in`, `Window opens in`, `Leave before`);
- observed live restocks may display elapsed time such as `live +04:12`;
- Airstrip default;
- single-skin selector/cycle currently enables Standard/Airstrip/WLT;
- Business stays hidden/disabled until its trip economics are resolved safely;
- no unsupported Windows Clock alarm automation in this pass;
- do not clone Weav3r styling; prioritize dark readability and compactness;
- low-confidence/stale/check-external warning overlays remain clickable verification affordances.

The graph shows useful stock history and event markers without representing every sample as an expensive individual Rainmeter meter.

---

# Phase 10 — Resource limits and retention

The continuously loaded system must remain lightweight.

Design/verify:

- one-second Rainmeter updates perform local Lua state/countdown/string work only;
- provider polling is conservative, normally around 60–120 seconds unless evidence supports another bounded interval;
- expensive analytics run on data/event changes or a low-frequency schedule, not every second;
- one serialized updater/finalizer pipeline is preferred over many independent processes;
- the finalizer makes no additional web request;
- no persistent browser;
- high-resolution runtime history is pruned around 24–48 hours by default;
- completed cycle history is bounded around 60–90 days initially;
- long-term learning uses compact aggregates where appropriate;
- logs/caches/generated graph/probe/import-analysis artifacts are bounded or runtime-only;
- runtime paths are ignored by Git.

Record an approximate observed idle/refresh resource profile during local validation. Do not claim exact CPU/RAM targets without measuring them.

---

# Phase 11 — Fixtures, replay validation, and shadow mode

The repository contains deterministic/scriptable validation that does not require live providers.

Current validation layers include:

- project/config/PowerShell/static Rainmeter validation;
- historical tooling/seed contract validation;
- normalized observation -> completed-cycle replay;
- isolated seed importer/dedup/provenance tests;
- production-function recommendation replay through PowerShell AST extraction;
- isolated final-state/restock/trip-economics guard tests.

At minimum cover scenarios equivalent to:

1. low foreign price + fast depletion + no conservative window → `BEST_ODDS`;
2. longer availability than restock variance → `SAFE_WINDOW`;
3. current price outside trained range → confidence downgrade;
4. high/low profitability thresholds suppress timing correctly;
5. stale stock data suppresses timing;
6. stale resale reference suppresses timing;
7. actual last sellout remains historical, not predicted;
8. travel-mode change alters departure timing without altering the observed cycle;
9. Standard cash travel cost can downgrade a borderline trip;
10. Airstrip/WLT zero travel cost is preserved;
11. capacity override / total-trip floor are applied;
12. unresolved Business economics suppress timing;
13. actual/estimated restock information survives profitability suppression;
14. old raw samples prune while cycle summaries remain;
15. provider failure preserves cached display but marks it stale/offline;
16. first run with inadequate seed history enters learning/check-external behavior rather than inventing a window.

Before treating the recommendation model as established, run it in shadow/observation mode against live subsequent restocks/sellouts and record where recommendations would have succeeded/failed. Use that evidence to calibrate confidence, price cohorts, and safe-window conservatism.

---

# Phase 12 — Windows / Rainmeter validation boundary

Follow [`WINDOWS_VALIDATION.md`](./WINDOWS_VALIDATION.md).

Minimum local sequence:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-LiveEnvironment.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Then load:

```text
Travel Assistant\TravelAssistant.ini
```

and inspect Rainmeter rendering/log behavior.

Do not claim the authored deterministic tests pass until they actually execute on Windows. Do not claim local provider/resource behavior from connector-side inspection.

Feed runtime defects back through the GitHub connector where practical. Escalate to broader Codex/local debugging only for a concrete capability the connector cannot provide.

---

# Acceptance criteria for this ACTIVE run

The run may be marked `COMPLETED` only when:

- a working Rainmeter-facing v1 exists for UK/Japan Xanax and has been loaded successfully on the target Windows/Rainmeter environment;
- Airstrip works as default and enabled travel modes can be changed without duplicating the analytics engine;
- Standard/Airstrip/WLT work through the single selector; Business may remain intentionally gated until its unresolved economics are implemented;
- current stock and foreign price are displayed inline;
- travel and departure/window timing are displayed inline;
- restock timing and last actual sellout are displayed inline;
- low-margin/unprofitable opportunities retain informational restock/history while receiving no departure recommendation;
- both 24-hour graphs are vertically aligned and render successfully;
- observations/cycles are generic and schema-versioned;
- price materially affects depletion/comparable-cycle logic;
- unprofitable/low-margin/stale-resale/unresolved-economics opportunities receive no departure recommendation;
- mode travel cost and carrying capacity participate in the final trip-level gate;
- the model distinguishes conservative safe windows from probabilistic best-odds timing;
- low-confidence/stale/unsupported regimes fail visibly and conservatively;
- historical seed data is imported only if a suitable bounded source is verified; otherwise the documented low-confidence first-run behavior remains correct;
- runtime storage is ignored and bounded;
- provider polling/model recomputation do not run at one-second UI frequency;
- future item/country expansion can be achieved without rewriting persistence/model contracts;
- deterministic/static tests execute successfully and results are recorded;
- live YATA/Torn/Rainmeter behavior is checked on the target machine;
- approximate resource/disk behavior is recorded without overstating attribution;
- project documentation matches actual implementation;
- `git diff --check` passes in the local checkout used for validation;
- no unrelated TORN subtree changes are included.

---

# Validation / completion record

**Not yet completed.**

Repository-side implementation and deterministic test harnesses are substantially present, but the target Windows/Rainmeter execution evidence has not yet been collected.

When implementation/validation finishes, replace this section with:

- starting `main` SHA;
- exact local implementation/documentation SHA tested;
- providers/endpoints actually used and relevant limitations;
- seed-data provenance and coverage;
- exact validation commands and results;
- Rainmeter load/log result;
- observed retention/resource behavior;
- known model limitations;
- shadow-mode findings if available;
- explicitly deferred items (including Business economics if still gated);
- final status changed to **COMPLETED** only after the acceptance criteria above are satisfied.
