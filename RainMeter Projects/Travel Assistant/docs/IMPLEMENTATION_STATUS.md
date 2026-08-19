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
65628cbf1d8cd9de66131fadf8945a92945c0537
```

All implementation changes in this checkpoint are confined to `RainMeter Projects/Travel Assistant/`.

## Implemented

### Configuration / expansion foundation

- schema-versioned generic item configuration;
- Xanax item ID 206 enabled for v1;
- schema-versioned UK/Japan destination configuration;
- Standard, Airstrip, WLT, and Business travel-time metadata with Airstrip default;
- Standard/Airstrip/WLT currently selectable; Business intentionally configured-but-disabled until Business Class Ticket/free-company travel economics are included in profitability gating;
- destination travel-economics metadata includes Standard cash cost, explicitly free Airstrip/WLT cost, and conservative base carrying capacity by mode;
- provider registry with enabled live/resale providers and disabled bootstrap/cross-check candidates;
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
- `UNPROFITABLE` and `LOW_MARGIN` suppress departure advice while observation collection continues;
- Business mode is gated instead of pretending the potentially large Business Class Ticket opportunity cost is zero.

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
- graph-area warning overlays for learning, stale, source-disagreement, unverified-price-regime, and check-external states;
- mode tooltip now states that Business is gated pending trip-economics support rather than implying it is safely selectable.

### Process/resource safety

- one-second Rainmeter path is limited to local Lua state parsing/countdown formatting;
- network/model/graph updater is scheduled at minute scale rather than one-second scale;
- `RunUpdate.ps1` serializes updater invocations with a local mutex so refresh/poll overlap cannot concurrently write observations, engine state, or graph files;
- generated graphs/runtime history are ignored and bounded;
- historical probes/import previews are written under ignored runtime storage rather than continuously committed.

### Historical/bootstrap tooling

- immutable seed contract and provenance rules documented in `data/seed/README.md`;
- `tools/Probe-DroqsDb.ps1` performs a bounded metadata/current-endpoint discovery pass without guessing history URLs or altering seed data;
- `tools/Build-CyclesFromObservations.ps1` converts normalized observation history to completed cycles using observed transitions only;
- `tools/Import-SeedHistory.ps1` validates, deduplicates, provenance-tags, and atomically merges verified history into `data/seed/`;
- `tools/Import-TravelPlannerHistory.ps1` supports a documented read-only `/api/history/:country/:itemId?hours=...` snapshot shape used by an open-source YATA-backed travel planner, but requires an explicit verified deployment host and is preview-only by default;
- the compatible history adapter caps each requested window at 720 hours and only targets UK/Japan Xanax in v1;
- provider safe-window/forecast outputs are deliberately not converted into historical truth.

### Tooling / validation assets

- non-destructive `Install.ps1` junction installer;
- synthetic YATA/provider fixture;
- synthetic safe-window and fast-depletion cycle fixtures;
- synthetic normalized-observation fixture for historical pipeline replay;
- `tests/Validate-TravelAssistant.ps1` checks JSON/JSONL/schema contracts, required files, travel modes/economics metadata, PowerShell parser status, basic skin structure, serialized-wrapper use, and Git ignore rules;
- `tests/Validate-HistoricalTools.ps1` checks historical/local tool parsing, seed metadata coverage, and seed-truth/provenance constraints;
- `tests/Run-HistoricalPipelineTests.ps1` executes the production cycle-builder against synthetic normalized observations and verifies observed transition timestamps/durations;
- `tests/Run-ModelTests.ps1` extracts the actual production functions from `UpdateTracker.ps1` through the PowerShell AST and runs deterministic synthetic model scenarios without duplicating the production recommendation implementation;
- `tests/Run-All.ps1` is the single deterministic/static validation entry point;
- `tools/Validate-LiveEnvironment.ps1` provides a bounded first Windows pass: deterministic tests, one YATA request, one optional Torn Item Market request, one serialized updater pass, disk-size reporting, Rainmeter install check, and whole-process Rainmeter memory observation.

## Historical bootstrap

The committed seed is intentionally empty.

A substantially better bootstrap candidate has now been identified at the **contract** level: the public `shab00m/torn-travel-planner` repository documents a read-only history API whose points contain YATA timestamp, quantity, and foreign cost. Those fields map directly to Travel Assistant's normalized observations, and a bounded compatible importer is now in the repository.

However, Travel Assistant does **not** assume a deployment URL or permission for an arbitrary deployment. Real seed history is still withheld until a specific live host and its external-use expectations are verified. DroqsDB also remains disabled for historical use until its live contract is verified from the user's machine.

The model and graphs already consume `data/seed/` alongside runtime history, so adding a verified real seed later does not require changing persistence/model contracts.

Do not replace the empty bootstrap with synthetic test fixtures or provider forecasts.

## Known implementation gaps / next work

1. **Windows runtime validation is still required.** Connector work has not run Rainmeter, Windows PowerShell, `System.Drawing`, the installer junction, or live YATA/Torn requests on the user's machine.
2. **The deterministic PowerShell validation scripts are written but not executed yet.** Do not record them as passing until a Windows PowerShell run confirms it.
3. **Price similarity is currently a bounded cohort, not a continuously weighted regression.** This is intentionally simple until real observations calibrate more sophisticated weighting; the present safe-window intersection remains conservative within its selected cohort.
4. **Time-of-day/day-of-week pattern detection is not active in Travel Assistant yet.** A candidate historical provider documents hour-of-day depletion analytics, which is useful design evidence, but Travel Assistant should learn its own pattern only when enough observed data exists.
5. **Cross-provider disagreement logic has statuses/contracts but no enabled secondary live provider yet.**
6. **First launch in the middle of an already-live restock cannot know that cycle's exact restock timestamp.** Live-cycle depletion behavior becomes strongest after the tracker has observed its own 0 → positive transition.
7. **Resource limits are designed but not measured.** CPU/RAM/disk measurements require a real Windows/Rainmeter pass.
8. **No Windows Clock alarm integration.** This remains intentionally deferred because reliable programmatic alarm creation has not been established.
9. **Initial profitability thresholds are provisional defaults.** The current 50k net profit/item and 5% net-margin floors should be calibrated to the user's actual preferred opportunity floor after live validation.
10. **Total-trip economics are not yet fully applied to Standard mode.** Standard cash travel costs are now stored in config, but v1 recommendation gating still uses per-item margin. The gap is small relative to the default Xanax per-item floor but should be closed before treating total-trip profit as authoritative.
11. **Business travel is intentionally disabled pending economics support.** To re-enable it safely, model either the current Business Class Ticket opportunity cost or an explicit user setting indicating that the 10* Lingerie perk makes Business travel free, and evaluate cost across carrying capacity.
12. **Historical provider bootstrap is contract-ready but live-host verification remains unresolved.** Continue bounded discovery, but preserve low-confidence startup rather than manufacturing data.

## Next connector-first tasks

1. Keep historical bootstrap discovery bounded. If a verified travel-planner-compatible deployment host is found, use preview-only import first, inspect the normalized candidate, then explicitly import only if source use is appropriate.
2. Add total-trip profitability using the newly stored travel cost/base-capacity metadata. Airstrip/WLT should remain zero-cost; Standard should subtract cash travel cost; Business should remain gated until ticket/free-company semantics are represented.
3. Harden price-regime selection after enough real/synthetic calibration evidence exists; avoid confidently pooling cycles whose price-driven depletion behavior is materially different.
4. Keep `docs/NEXT_CODEX_RUN.md` ACTIVE and append validation evidence as it becomes available.
5. When connector-side work reaches the runtime boundary, perform the smallest necessary Windows pass:
   - `tests\Run-All.ps1`;
   - `tools\Validate-LiveEnvironment.ps1`;
   - `Install.ps1`;
   - load/refresh the Rainmeter skin and inspect the log;
   - verify live provider/API behavior and travel-mode cycling;
   - measure approximate CPU/RAM/disk behavior.
6. Feed any runtime defects back through the GitHub connector where practical rather than broadening into a general Codex pass.
