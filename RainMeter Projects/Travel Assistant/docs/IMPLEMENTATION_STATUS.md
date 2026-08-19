# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-19

**Active run:** [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) remains **ACTIVE**. This file records progress only; it does not replace the active scope or `AGENTS.md` invariants.

## Connector-first checkpoint

Starting implementation SHA:

```text
bb1ed84bd81a6021beaae7ed2c048e9974b71cab
```

First substantial Rainmeter implementation commit:

```text
2303b82bdd417af9934d29dbb5df9367dc882962
```

Profitability/live-depletion hardening commit:

```text
e59855c4a3508db14adb259c0efa120f799eff12
```

README checkpoint commit:

```text
c0ea3088c8434e23c858ff97fb478c7ebb079111
```

All implementation changes in this checkpoint are confined to `RainMeter Projects/Travel Assistant/`.

## Implemented

### Configuration / expansion foundation

- schema-versioned generic item configuration;
- Xanax item ID 206 enabled for v1;
- schema-versioned UK/Japan destination configuration;
- Standard, Airstrip, WLT, Business travel modes with Airstrip default;
- provider registry;
- local settings template;
- Item Market sell-target fee and profitability thresholds are configurable;
- runtime/generated state and secrets are ignored by Git.

### Live collection / persistence

- YATA structured travel-export adapter for stock and foreign price;
- normalized generic observation records;
- append-only runtime observation JSONL with duplicate source/value suppression;
- observed zero → positive restock detection;
- observed positive → zero actual sellout detection;
- compact completed-cycle JSONL records;
- cached destination state retained for display when the live stock request fails;
- automatic pruning of high-resolution observations and completed cycles.

### Profitability

- optional Torn v2 Item Market resale lookup via local API key or `TORN_API_KEY`;
- resale cache rather than one-second market requests;
- Item Market resale reference reduced by configured selling fee before net profit/margin checks;
- `UNPROFITABLE` and `LOW_MARGIN` suppress departure advice while observation collection continues.

### Recommendation engine

- completed-cycle restock-delay history;
- near-price comparable-cycle selection;
- price-regime confidence downgrade;
- conservative all-cycle overlap for `SAFE_WINDOW`;
- candidate-departure historical hit testing for `BEST_ODDS`;
- exact last observed sellout retained separately from estimates;
- when a restock is currently live, exact observed restock time is used;
- current live depletion can shorten a conservative availability limit but never extend it beyond historical safety evidence;
- live-stock arrival odds may downgrade a current trip to best-odds or window-closed.

### Rainmeter UI

- single dark/charcoal skin;
- UK above Japan;
- equal graph width and vertical alignment;
- inline Travel / Leave-or-window row;
- inline Restock / Last Sold Out row;
- inline Stock / Foreign Price row;
- relative countdowns updated through a lightweight Lua measure;
- clickable travel-mode cycle;
- clickable timing/status field opens Weav3r Travel Stock for verification;
- generated 24-hour step graphs with restock/sellout markers.

### Tooling

- non-destructive `Install.ps1` junction installer;
- synthetic YATA/provider fixture;
- synthetic safe-window and fast-depletion cycle fixtures;
- `tests/Validate-TravelAssistant.ps1` for JSON/JSONL/schema/PowerShell-parser/basic skin/static ignore checks;
- provider discovery documentation.

## Historical bootstrap

The committed seed is intentionally empty. DroqsDB documentation currently advertises historical series and useful travel endpoints, but this implementation pass has not verified a stable live historical-query contract strongly enough to treat returned data as training evidence. Weav3r remains an external verification page and is not scraped in a loop.

Do not replace the empty bootstrap with synthetic test fixtures.

## Known implementation gaps / next work

1. **Windows runtime validation is still required.** Connector work has not run Rainmeter, Windows PowerShell, `System.Drawing`, the installer junction, or live YATA/Torn requests on the user's machine.
2. **Seed ingestion needs wiring before a non-empty bootstrap is useful.** The current live engine learns from runtime observations/cycles; `data/seed/` is not yet merged into graph/model reads.
3. **Fixture injection/replay should exercise production recommendation functions.** Current fixtures and static validator are present, but the updater is not yet factored for deterministic offline recommendation replay without a live request.
4. **Price similarity is currently a bounded cohort, not a continuously weighted regression.** This is intentionally simple until real observations can calibrate more sophisticated weighting.
5. **Time-of-day/day-of-week pattern detection is not yet active.** Add only after enough data exists to avoid overfitting.
6. **Cross-provider disagreement logic has statuses/contracts but no enabled secondary live provider yet.**
7. **First launch in the middle of an already-live restock cannot know that cycle's exact restock timestamp.** Live-cycle depletion behavior becomes strongest after the tracker has observed its own 0 → positive transition.
8. **Resource limits are designed but not measured.** CPU/RAM/disk measurements require a real Windows/Rainmeter pass.
9. **No Windows Clock alarm integration.** This remains intentionally deferred because reliable programmatic alarm creation has not been established.

## Next connector-first tasks

1. Wire `data/seed/observations.jsonl` and `data/seed/cycles.jsonl` into graph/model reads without copying them into mutable runtime state.
2. Refactor just enough recommendation/provider logic to allow deterministic fixture-backed replay of the actual production functions.
3. Add model tests for:
   - high-price long-stock `SAFE_WINDOW`;
   - low-price fast-stock `BEST_ODDS`;
   - fee-adjusted `LOW_MARGIN`/`UNPROFITABLE`;
   - stale source suppression;
   - travel-mode timing changes;
   - active-cycle depletion shortening a recommendation.
4. Continue bounded historical-provider discovery. Only commit real seed data with provenance if the source contract can be verified.
5. Update `docs/NEXT_CODEX_RUN.md` with validation evidence as implementation progresses.
6. Escalate to local/Codex only when the remaining work specifically requires Windows/Rainmeter execution or another connector-unavailable capability.
