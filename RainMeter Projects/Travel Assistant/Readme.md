# Travel Assistant

Rainmeter-based Torn travel decision assistant.

Version 1 focuses on **Xanax in the United Kingdom and Japan**, while the data model and analysis engine remain generic so additional foreign items and destinations can be added later without rewriting the project.

## Current status

**Initial implementation is in the repository; Windows/Rainmeter runtime validation is still required.**

Implemented so far:

- dark, vertically stacked UK/Japan Rainmeter skin;
- default Airstrip travel mode with a clickable Standard → Airstrip → WLT → Business mode cycle;
- structured live stock/foreign-price adapter using YATA;
- generic observation and completed-cycle persistence;
- actual restock/sellout transition detection;
- price-aware comparable-cycle selection;
- conservative safe-window vs. best-odds departure logic;
- current-cycle depletion estimate that may shorten, but never extend, a conservative historical window;
- Torn Item Market resale lookup when a local API key is supplied;
- profitability gating using configurable Item Market fee, minimum net profit per item, and minimum margin;
- cached local fallback when the live stock provider fails;
- 24-hour generated stock graphs with restock/sellout markers;
- bounded runtime retention and ignored local/runtime state;
- synthetic fixtures, production-function replay tests, historical-pipeline tests, and static validators;
- non-destructive Rainmeter junction installer;
- bounded historical-provider probe, normalized-observation cycle builder, and provenance-aware seed importer.

The current implementation remains in learning mode until it has sufficient actual restock/sellout history or a verified historical seed is added. The committed seed is intentionally empty rather than fabricated.

The active implementation scope is in [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md). Read [`AGENTS.md`](./AGENTS.md) before changing anything in this subtree.

## Primary goal

At a glance, answer:

> Is the current foreign Xanax opportunity worth taking, and if so, when should I leave with my selected travel mode to maximize the chance that stock is still available when I arrive?

The assistant must prefer **no recommendation** over a confident-looking recommendation built from stale, incomparable, low-confidence, or unprofitable data.

## Version 1 scope

- United Kingdom — Xanax
- Japan — Xanax
- Airstrip travel mode by default
- Runtime-selectable Standard, Airstrip, WLT, Business travel modes
- Vertically stacked destination panels and graphs
- 24-hour stock history graph per destination
- Inline status rows:
  - `Travel | Leave / Window`
  - `Restock | Last Sold Out`
  - `Stock | Foreign Price`
- Last **actual** sellout, not predicted sellout, in the primary status row
- Price-aware depletion analysis
- Historical restock variance analysis
- Conservative safe-departure windows when historical overlap supports one
- Best-odds exact departure timing when no conservative window exists
- Profitability gating: unprofitable or low-margin opportunities do not receive departure recommendations
- Low-confidence and stale-data warnings
- Clickable Weav3r fallback for external verification
- Bounded CPU, memory, network, and disk usage

## Display concept

```text
TRAVEL ASSISTANT                              AIRSTRIP ›

UNITED KINGDOM · XANAX
Travel: 1:46:00       | Leave in: 00:11:24
Restock: ~1:xx        | Last Sold Out: 12:41
Stock: 2,143          | Price: $728,000
[                24-HOUR STOCK GRAPH                ]
SAFE WINDOW           | Leave before: 00:08:36

JAPAN · XANAX
Travel: 2:29:00       | Leave in: 00:07:13
Restock: ~2:xx        | Last Sold Out: 11:52
Stock: 0              | Price: $742,000
[                24-HOUR STOCK GRAPH                ]
BEST ODDS             | historical hit rate shown when useful
```

The exact labels are state-driven. The skin does not display a clock; relative countdowns are preferred.

## Install from the repository clone

Expected source location:

```text
C:\Codex\TORN\RainMeter Projects\Travel Assistant\
```

From that directory in Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

The installer:

1. creates ignored runtime/generated directories;
2. creates `config/settings.local.json` from the local example if needed;
3. creates a non-destructive junction under the current user's Rainmeter `Skins` directory pointing back to the repository source.

It will **not** delete or replace an unrelated existing `Travel Assistant` skin directory.

After installation, refresh Rainmeter and load:

```text
Travel Assistant\TravelAssistant.ini
```

## Local API key

The live foreign stock feed does not require a Torn key, so the tracker can begin learning immediately.

Profitability-gated departure recommendations currently require a Torn API key for the resale reference. Put it in ignored:

```text
config\settings.local.json
```

or define the environment variable:

```text
TORN_API_KEY
```

Do not commit limited/full-authority keys. Public keys are sufficient for public Item Market data; local configuration remains the default so the repository does not need a committed credential.

## Profitability behavior

The initial sell target is the Torn Item Market. The calculation uses the configured Item Market selling fee before determining net profit.

Torn's official Item Market documentation currently specifies a regular 5% sales tax. Bazaar sales do not use that regular Item Market fee, so a future Bazaar sell target must be an explicit mode with its own price source/fee behavior rather than silently sharing Item Market assumptions.

Default settings are configurable in `config/settings.example.json`; personal overrides belong in ignored `config/settings.local.json`.

An unprofitable or below-threshold trip still contributes useful stock/restock/depletion history, but receives **no departure timing recommendation**.

## Decision order

The recommendation engine evaluates conditions in this order:

1. Is source data current enough to use?
2. Is the trip sufficiently profitable under configured thresholds?
3. Is the current foreign-price/depletion regime comparable to useful history?
4. Is there enough reliable history to recommend anything?
5. If stock is currently live, does current depletion still support arrival?
6. Is there a conservative departure interval supported by comparable cycles?
7. If not, is there a useful best-odds departure point?
8. Otherwise, show no departure recommendation and direct the user to external verification when appropriate.

Primary reason/status codes remain machine-readable, including:

- `SAFE_WINDOW`
- `BEST_ODDS`
- `TOO_EARLY`
- `WINDOW_CLOSED`
- `INSUFFICIENT_HISTORY`
- `PRICE_REGIME_UNVERIFIED`
- `SOURCE_DISAGREEMENT`
- `LOW_MARGIN`
- `UNPROFITABLE`
- `STALE_DATA`
- `CHECK_EXTERNAL`

Rainmeter translates these into concise user-facing text.

## Architecture

Keep Rainmeter thin. Data collection, history normalization, cycle detection, statistical analysis, profitability, and recommendation generation belong outside the `.ini` presentation layer.

```text
Providers
   ↓
Normalized observations
   ↓
History / cycle engine
   ↓
Restock + price-aware depletion analytics
   ↓
Profitability + opportunity engine
   ↓
Compact generated state
   ↓
Rainmeter UI
```

Provider-specific logic is isolated so the live source or historical bootstrap can change without rewriting the model or skin.

See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) for the durable data model, [`docs/PROVIDER_DISCOVERY.md`](./docs/PROVIDER_DISCOVERY.md) for current provider choices, and [`docs/HISTORICAL_BOOTSTRAP.md`](./docs/HISTORICAL_BOOTSTRAP.md) for seed/backfill rules.

## Historical data and learning

The project distinguishes **seed data** from **runtime data**.

- `data/seed/` is reserved for a compact, provenance-documented historical bootstrap committed to Git.
- `data/runtime/` is local, bounded, automatically pruned/compacted, and ignored by Git.
- High-resolution runtime observations default to roughly 48 hours.
- Completed cycle summaries default to roughly 90 days.
- Long-term learning should eventually favor compact aggregates over permanent minute-by-minute logs.

The initial historical seed is empty because no bounded historical source has yet been validated strongly enough to commit as training evidence. The tracker therefore starts conservatively and learns from live observations.

The repository now includes:

```text
tools\Probe-DroqsDb.ps1
tools\Build-CyclesFromObservations.ps1
tools\Import-SeedHistory.ps1
```

so a future verified structured backfill can be inspected, normalized, converted to **observed** completed cycles, provenance-checked, and merged into the immutable seed without changing the runtime model.

## Price-aware behavior

Foreign price is first-class. Sellout behavior at a very low foreign price is not treated as interchangeable with behavior at a high foreign price.

For a current opportunity, evidence is intended to be weighted in this order:

1. current observed depletion when a restock is already live;
2. comparable same/near-price historical cycles;
3. broader destination/item history only at reduced confidence.

The current v1 engine selects a bounded near-price cohort. Further continuous price weighting/pattern detection can be added after real history exists to calibrate against.

## Performance boundary

The skin is designed to remain lightweight on a continuously running Windows desktop.

- One-second UI updates perform local countdown/string work through a Lua measure.
- Network/history/model updates default to once per minute.
- Overlapping updater runs are serialized rather than allowed to race.
- Torn resale pricing is cached and is not queried every second.
- No persistent browser is used.
- Graphs are two small generated PNGs rather than thousands of Rainmeter meters.
- Runtime observations/cycles are pruned.
- Runtime state, generated graphs, logs, provider probes, and credentials are ignored by Git.

Actual CPU/RAM/disk measurements still require a Windows/Rainmeter runtime pass before the project should be called stable.

## Validation

Run all connector-authored deterministic/static PowerShell checks with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

For the first bounded live Windows/provider/resource pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-LiveEnvironment.ps1
```

This deliberately performs only a small number of live requests and one production updater pass; it is not a stress loop.

Synthetic fixtures under `tests/fixtures/` are not historical/training data.

Connector-side repository work must not claim that Windows PowerShell, Rainmeter rendering, live provider access, or resource usage has been validated locally when it has not.

## Documentation routing

Read in this order before implementation work:

1. [`AGENTS.md`](./AGENTS.md) — subtree rules and invariants.
2. [`docs/README.md`](./docs/README.md) — documentation map and precedence.
3. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md) — authoritative active implementation pass.
4. [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — durable architecture and expansion design.
5. [`docs/IMPLEMENTATION_STATUS.md`](./docs/IMPLEMENTATION_STATUS.md) — current checkpoint and runtime boundary.
6. [`docs/PROVIDER_DISCOVERY.md`](./docs/PROVIDER_DISCOVERY.md) — provider-specific decisions and unresolved discovery.
7. [`docs/HISTORICAL_BOOTSTRAP.md`](./docs/HISTORICAL_BOOTSTRAP.md) — historical seed/provenance workflow.

Keep these documents synchronized when architecture or execution policy changes.
