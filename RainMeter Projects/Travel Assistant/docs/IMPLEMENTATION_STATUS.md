# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-19

**Active run:** [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) remains **ACTIVE**. This file records progress only; it does not replace the active scope or `AGENTS.md` invariants.

## Connector-first checkpoint

Starting implementation SHA:

```text
bb1ed84bd81a6021beaae7ed2c048e9974b71cab
```

Current implementation head at this checkpoint:

```text
ab846c9c0576c17bc881de5f7a321c609ed641a7
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
- automatic pruning of high-resolution observations and completed cycles;
- immutable `data/seed/` observations/cycles are merged into graph/model reads and deduplicated against runtime data without copying them into mutable runtime state.

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
- generated 24-hour step graphs with restock/sellout markers;
- state-aware status colors;
- graph-area warning overlays for learning, stale, source-disagreement, unverified-price-regime, and check-external states.

### Process/resource safety

- one-second Rainmeter path is limited to local Lua state parsing/countdown formatting;
- network/model/graph updater is scheduled at minute scale rather than one-second scale;
- `RunUpdate.ps1` serializes updater invocations with a local mutex so refresh/poll overlap cannot concurrently write observations, engine state, or graph files;
- generated graphs/runtime history are ignored and bounded.

### Tooling / validation assets

- non-destructive `Install.ps1` junction installer;
- synthetic YATA/provider fixture;
- synthetic safe-window and fast-depletion cycle fixtures;
- `tests/Validate-TravelAssistant.ps1` checks JSON/JSONL/schema contracts, required files, travel modes, PowerShell parser status, basic skin structure, serialized-wrapper use, and Git ignore rules;
- `tests/Run-ModelTests.ps1` extracts the actual production functions from `UpdateTracker.ps1` through the PowerShell AST and runs deterministic synthetic model scenarios without duplicating the production recommendation implementation;
- current model-test scenarios cover YATA normalization, seed/runtime cycle dedupe, `SAFE_WINDOW`, `BEST_ODDS`, fee-adjusted low-margin/unprofitable suppression, stale data, travel-mode timing changes, and live depletion closing an otherwise historically safe opportunity;
- provider discovery documentation.

## Historical bootstrap

The committed seed is intentionally empty. Current public-source discovery confirms that structured live foreign-stock tooling commonly uses the YATA export, but no bounded historical source has yet been verified strongly enough in this implementation pass to commit third-party observations as training evidence.

The model and graphs already consume `data/seed/` alongside runtime history, so adding a verified real seed later does not require changing persistence/model contracts.

Do not replace the empty bootstrap with synthetic test fixtures.

## Known implementation gaps / next work

1. **Windows runtime validation is still required.** Connector work has not run Rainmeter, Windows PowerShell, `System.Drawing`, the installer junction, or live YATA/Torn requests on the user's machine.
2. **The deterministic PowerShell validation scripts are written but not executed yet.** Do not record them as passing until a Windows PowerShell run confirms it.
3. **Price similarity is currently a bounded cohort, not a continuously weighted regression.** This is intentionally simple until real observations can calibrate more sophisticated weighting; the present safe-window intersection remains conservative within its selected cohort.
4. **Time-of-day/day-of-week pattern detection is not yet active.** Add only after enough data exists to avoid overfitting.
5. **Cross-provider disagreement logic has statuses/contracts but no enabled secondary live provider yet.**
6. **First launch in the middle of an already-live restock cannot know that cycle's exact restock timestamp.** Live-cycle depletion behavior becomes strongest after the tracker has observed its own 0 → positive transition.
7. **Resource limits are designed but not measured.** CPU/RAM/disk measurements require a real Windows/Rainmeter pass.
8. **No Windows Clock alarm integration.** This remains intentionally deferred because reliable programmatic alarm creation has not been established.
9. **Initial profitability thresholds are provisional defaults.** The current 50k net profit/item and 5% net-margin floors should be calibrated to the user's actual preferred opportunity floor after live validation.
10. **Historical provider bootstrap remains unresolved.** Continue bounded discovery, but preserve low-confidence startup rather than manufacturing data.

## Next connector-first tasks

1. Continue bounded historical-provider discovery and commit real seed data only if provenance/query semantics can be verified.
2. Harden price-regime selection after enough real/synthetic calibration evidence exists; avoid confidently pooling cycles whose price-driven depletion behavior is materially different.
3. Keep `docs/NEXT_CODEX_RUN.md` ACTIVE and append validation evidence as it becomes available.
4. When connector-side work reaches the runtime boundary, perform the smallest necessary Windows pass:
   - `tests\Validate-TravelAssistant.ps1`;
   - `tests\Run-ModelTests.ps1`;
   - `Install.ps1`;
   - load/refresh the Rainmeter skin and inspect the log;
   - verify live provider/API behavior and travel-mode cycling;
   - measure approximate CPU/RAM/disk behavior.
5. Feed any runtime defects back through the GitHub connector where practical rather than broadening into a general Codex pass.
