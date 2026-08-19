# Next Codex Run: Travel Assistant v1 Foundation

**Status: ACTIVE**

This is the authoritative current implementation scope for `RainMeter Projects/Travel Assistant/`.

Read [`../AGENTS.md`](../AGENTS.md), [`README.md`](./README.md), and [`ARCHITECTURE.md`](./ARCHITECTURE.md) before editing.

## Goal

Build the first usable Travel Assistant implementation for **Xanax in the United Kingdom and Japan** with a lightweight Rainmeter UI and a generic underlying travel-opportunity engine.

The first implementation must prefer conservative/no recommendations over false precision. The result should already be structurally ready for more items and destinations later, but must not broaden the v1 UI beyond UK/Japan Xanax.

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

Create the minimum durable structure needed for implementation. Prefer a compact physical file layout, but preserve the logical separation defined in `ARCHITECTURE.md`.

Expected direction:

```text
Travel Assistant/
  Readme.md
  AGENTS.md
  .gitignore
  TravelAssistant.ini
  config/
    settings.example.json
    items.json
    countries.json
    travel-modes.json
  data/
    seed/
      metadata.json
      observations.jsonl
      cycles.jsonl
    runtime/                 # ignored
  @Resources/
    Scripts/
      UpdateTracker.ps1
      ...modules/helpers as justified...
  docs/
```

Requirements:

- default travel mode: `airstrip`;
- configured modes: `standard`, `airstrip`, `wlt`, `business`;
- configured items: Xanax (`itemId` 206) enabled for v1;
- configured destinations: United Kingdom and Japan enabled for v1;
- use generic item/country/travel-mode data structures;
- establish `schemaVersion: 1` for persistent JSON/JSONL contracts;
- ignore runtime observations/cache/logs/local credentials/generated transient graph artifacts as appropriate;
- provide committed examples/templates for local-only config if credentials are needed.

Do not hard-code item/country logic into names like `UKXanaxPredictor`.

---

# Phase 2 — Provider discovery and bounded historical bootstrap

Investigate the current structured data path used by Weav3r Travel Stock for UK/Japan Xanax.

Determine, with saved fixtures where possible:

- current stock field;
- foreign purchase price field;
- observation/source timestamp semantics;
- historical stock series availability;
- explicit or inferable restock events;
- explicit or inferable sellout events;
- provider rate/caching characteristics;
- whether the historical interface is sufficiently stable/suitable for a bounded bootstrap.

Do **not** implement a browser-render/scrape loop or excessive automated requester.

If Weav3r does not provide a suitable historical source, evaluate one suitable structured alternate source only as needed. Normalize all accepted source data to the same internal observation contract and retain provenance.

### Seed objective

Try to commit a compact seed dataset containing enough recent UK/Japan Xanax data to make first-run behavior useful:

- roughly 24–48 hours of useful high-resolution observations if obtainable economically;
- recent completed cycles where foreign price/restock/sellout can be established;
- provenance in `data/seed/metadata.json`.

If reliable backfill is not feasible, do not manufacture it. Commit empty/minimal valid seed structures, enter low-confidence mode, and let runtime learning establish the model.

Do not continuously commit runtime observations back into Git.

---

# Phase 3 — Normalized observations and runtime persistence

Implement a normalized observation contract conceptually equivalent to:

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
- local runtime persistence bounded;
- atomic-enough writes that interruption does not corrupt the entire history/state file;
- avoid loading/writing a giant monolithic JSON array on every poll if a simpler append/compact design is more efficient.

---

# Phase 4 — Restock/sellout cycle engine

Detect and summarize completed cycles.

A cycle should preserve at least:

```text
country
itemId
foreignPrice
restockAt
restockQuantity
soldOutAt
availabilitySeconds
source/provenance
```

Requirements:

- `Last Sold Out` is derived from an actual observed/historical transition;
- restock and sellout detection tolerate ordinary polling gaps;
- completed cycles are compact and independently useful after raw samples are pruned;
- within-cycle depletion may retain a compact curve/summary if it materially improves modeling;
- old high-resolution observations are pruned without destroying completed-cycle history.

---

# Phase 5 — Price-aware depletion analytics

Foreign price must materially affect comparable-cycle selection.

Use evidence in this priority order:

1. current-cycle observed depletion;
2. same/similar-price historical cycles;
3. nearby-price cycles with decreasing weight;
4. broad destination/item history only as a lower-confidence fallback.

Do not use fixed assumptions such as a universal Xanax sellout duration.

The model must behave sensibly across regimes where low prices can sell out in minutes while sufficiently high prices may remain in stock much longer.

If the current price lies outside useful historical support, return a lower-confidence / `PRICE_REGIME_UNVERIFIED` state rather than extrapolating confidently.

---

# Phase 6 — Restock variance and departure simulation

For each `country + item`, learn the distribution of time from prior actual sellout to next actual restock.

At minimum derive robust central timing and variation suitable for departure evaluation.

For the active travel mode:

```text
arrival = departure + configuredTravelTime(country, travelMode)
```

Evaluate candidate departure offsets against comparable historical cycles to estimate whether arrival would have occurred while stock was available.

## Conservative safe window

When qualifying historical cycles contain a meaningful common overlap after travel-time conversion, expose:

```text
SAFE_WINDOW
Window opens in: ...
Leave before: ...
```

Do not call a range safe merely because an average says it is likely.

## Best-odds departure

When restock variation exceeds the reliable availability duration and no conservative overlap exists, find the highest-probability departure point/narrow interval and expose:

```text
BEST_ODDS
Leave in: HH:MM:SS
Estimated hit rate / confidence where useful
```

If the useful interval is effectively a point for UI purposes, do not label it as a window.

---

# Phase 7 — Profitability gate

Before any departure recommendation, determine whether the foreign Xanax price supports the configured minimum opportunity.

Initial configuration should support at least:

- minimum profit per Xanax;
- minimum percentage margin.

Use an appropriate current resale reference from an available source; keep that source/provider isolated and explicit.

When the gate fails:

```text
LOW_MARGIN
```

or

```text
UNPROFITABLE
```

and suppress all leave/window advice while continuing to collect historical stock/depletion data.

Keep the design ready for later capacity / total-trip-profit evaluation without implementing unnecessary v1 UI.

---

# Phase 8 — Confidence and fallback behavior

Recommendation confidence must account for at least:

- freshness;
- comparable sample count;
- price-regime similarity;
- restock variability;
- current depletion agreement with history;
- source disagreement when cross-check data exists;
- extrapolation outside observed ranges.

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

If the last actual sellout places the user near a plausible departure point but the model cannot verify the opportunity confidently, expose a prominent `CHECK WEAV3R` / external verification state. Make it clickable from Rainmeter to open the Weav3r Travel Stock page in the default browser.

Do not let a stale cached recommendation continue counting down as though it were current.

---

# Phase 9 — Rainmeter UI

Build a dark/charcoal skin suitable for a solid-black desktop.

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
- default Airstrip;
- prefer a lightweight runtime selector/cycle for Standard/Airstrip/WLT/Business;
- if a reliable single-skin travel-mode control becomes disproportionately complex, document why before falling back to multiple skins;
- no unsupported Windows Clock alarm automation in this pass;
- do not clone Weav3r styling; prioritize dark readability and compactness.

The graph should show useful stock history and event markers without representing each sample as an expensive individual Rainmeter meter.

---

# Phase 10 — Resource limits and retention

The continuously loaded system must remain lightweight.

Design/verify:

- one-second Rainmeter updates perform local countdown/string work only;
- provider polling is conservative, normally around 60–120 seconds unless evidence supports another bounded interval;
- expensive analytics run on data/event changes or a low-frequency schedule, not every second;
- prefer one short-lived updater invocation over many independent processes;
- no persistent browser;
- high-resolution runtime history is pruned around 24–48 hours by default;
- completed cycle history is bounded around 60–90 days initially;
- long-term learning uses compact aggregates where appropriate;
- logs/caches/generated graph artifacts are bounded/pruned;
- runtime paths are ignored by Git.

Record an approximate observed idle/refresh resource profile if practical during local validation. Do not claim exact CPU/RAM targets without measuring them.

---

# Phase 11 — Fixtures, replay validation, and shadow mode

Add saved fixtures and automated or scriptable validation sufficient to exercise the model without depending exclusively on live provider responses.

At minimum cover scenarios equivalent to:

1. low foreign price + fast depletion + no conservative window → `BEST_ODDS`;
2. longer availability than restock variance → `SAFE_WINDOW`;
3. current price outside trained range → confidence downgrade;
4. high/low profitability thresholds suppress timing correctly;
5. stale data suppresses timing;
6. actual last sellout remains historical, not predicted;
7. travel-mode change alters departure timing without altering the underlying observed cycle;
8. old raw samples prune while cycle summaries remain;
9. provider failure preserves cached display but marks it stale/offline;
10. first run with inadequate seed history enters learning/check-external behavior rather than inventing a window.

Before treating the recommendation model as established, run it in a shadow/observation mode against live subsequent restocks/sellouts and record where recommendations would have succeeded/failed. Use that evidence to calibrate confidence and safe-window conservatism.

---

# Acceptance criteria for this ACTIVE run

The run may be marked `COMPLETED` only when:

- a working Rainmeter-facing v1 exists for UK/Japan Xanax;
- Airstrip works as default and travel mode can be changed without duplicating the analytics engine;
- current stock and foreign price are displayed inline;
- travel and departure/window timing are displayed inline;
- restock timing and last actual sellout are displayed inline;
- both 24-hour graphs are vertically aligned;
- observations/cycles are generic and schema-versioned;
- price materially affects depletion/comparable-cycle logic;
- unprofitable/low-margin opportunities receive no departure recommendation;
- the model distinguishes conservative safe windows from probabilistic best-odds timing;
- low-confidence/stale/unsupported regimes fail visibly and conservatively;
- historical seed data is imported if a suitable bounded source is available, otherwise the low-confidence first-run behavior is implemented/documented;
- runtime storage is ignored and bounded;
- provider polling/model recomputation do not run at one-second UI frequency;
- future item/country expansion can be achieved without rewriting persistence/model contracts;
- project documentation is updated to match actual implementation;
- validation commands and results are recorded below;
- `git diff --check` passes;
- no unrelated TORN subtree changes are included.

---

# Validation / completion record

**Not yet completed.**

When implementation finishes, replace this section with:

- starting `main` SHA;
- final implementation/documentation SHA(s);
- providers/endpoints actually used and any relevant limitations;
- seed-data provenance and coverage;
- exact validation commands and results;
- observed retention/resource behavior;
- known model limitations;
- shadow-mode findings if available;
- any explicitly deferred items;
- final status changed to **COMPLETED** only after the acceptance criteria above are satisfied.
