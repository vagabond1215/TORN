# Travel Assistant

Rainmeter-based Torn travel decision assistant.

The initial version focuses on **Xanax in the United Kingdom and Japan**, but the data model and analysis engine are intentionally generic so additional foreign items and destinations can be added later without rewriting the project.

## Current status

**Planning / initial implementation.**

The first implementation pass is defined in [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md). Read [`AGENTS.md`](./AGENTS.md) before changing anything in this subtree.

## Primary goal

At a glance, answer:

> Is the current foreign Xanax opportunity worth taking, and if so, when should I leave with my selected travel mode to maximize the chance that stock is still available when I arrive?

The assistant must prefer **no recommendation** over a confident-looking recommendation built from stale, incomparable, low-confidence, or unprofitable data.

## Version 1 scope

- United Kingdom — Xanax
- Japan — Xanax
- Airstrip travel mode by default
- Runtime-selectable travel mode where practical: Standard, Airstrip, WLT, Business
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
- Clickable `CHECK WEAV3R` fallback when the timing appears relevant but the local model cannot verify it confidently
- Bounded CPU, memory, network, and disk usage

## Display concept

```text
TRAVEL ASSISTANT                              AIRSTRIP

UNITED KINGDOM
Travel: 1:xx:xx       | Leave in: 00:11:24
Restock: ~1:xx         | Last Sold Out: 12:41
Stock: 2,143           | Price: $728,000
[                24-HOUR STOCK GRAPH                ]
SAFE WINDOW OPEN       | Leave before: 00:08:36

JAPAN
Travel: 2:xx:xx       | Best Departure: 00:07:13
Restock: ~2:xx         | Last Sold Out: 11:52
Stock: 0               | Price: $742,000
[                24-HOUR STOCK GRAPH                ]
BEST ODDS              | Estimated hit rate: 63%
```

The exact labels are state-driven. The skin does not need to display a clock; relative countdowns are preferred.

## Decision order

The recommendation engine should evaluate conditions in this order:

1. Is source data current enough to use?
2. Is the trip sufficiently profitable under configured thresholds?
3. Is the current foreign-price / depletion regime comparable to useful history?
4. Is there enough reliable history to recommend anything?
5. Is there a conservative departure interval supported by comparable cycles?
6. If not, is there a useful best-odds departure point?
7. Otherwise, show no departure recommendation and direct the user to verify externally when appropriate.

Primary reason/status codes should remain machine-readable, for example:

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
Restock + depletion analytics
   ↓
Profitability + opportunity engine
   ↓
Compact computed state
   ↓
Rainmeter UI
```

Provider-specific logic must be isolated behind adapters so a provider can change without rewriting the model or skin.

See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) for the durable data model, retention rules, and expansion strategy.

## Historical data and learning

The project distinguishes **seed data** from **runtime data**.

- `data/seed/` may contain a compact, provenance-documented historical bootstrap committed to Git.
- `data/runtime/` is local, bounded, automatically pruned/compacted, and must not be committed.
- High-resolution observations should be short-lived (roughly 24–48 hours by default).
- Completed cycle summaries can be retained longer (roughly 60–90 days initially).
- Long-term learning should favor compact aggregates over permanent minute-by-minute logs.

Historical backfill should use a suitable provider endpoint when available. Do not build a high-frequency page scraper or an unbounded archive.

## Price-aware behavior

Foreign price is a first-class part of the model. Sellout behavior at a very low foreign price must not be treated as interchangeable with behavior at a high foreign price.

For a current cycle, evidence should be weighted roughly in this order:

1. current observed depletion;
2. comparable same-price historical cycles;
3. nearby-price cycles;
4. broader destination/item history.

Confidence must drop when the current price regime is outside the supported historical range.

## Profitability

Before displaying a departure recommendation, evaluate the opportunity against configurable thresholds such as:

- minimum profit per item;
- minimum percentage spread;
- later: carrying capacity and minimum total-trip profit.

An unprofitable trip may still be useful training data, so history collection continues even when departure advice is suppressed.

## Performance boundary

The skin should remain lightweight on a continuously running Windows desktop.

- One-second UI updates should perform local countdown/string work only.
- Network polling should be conservative (normally around 60–120 seconds unless provider behavior calls for something different).
- Recompute heavy statistics on meaningful data/event changes, not every second.
- Do not spawn persistent browser processes.
- Do not maintain thousands of Rainmeter meters for graph points.
- Do not create unbounded logs, databases, screenshots, or raw-response archives.

## Repository / local location

Repository subtree:

```text
RainMeter Projects/Travel Assistant/
```

Expected local clone location:

```text
C:\Codex\TORN\RainMeter Projects\Travel Assistant\
```

Runtime installation into Rainmeter may use a separate Rainmeter skin location; repository source should remain the development/source-of-truth copy.

## Documentation routing

Read in this order before implementation work:

1. [`AGENTS.md`](./AGENTS.md) — subtree rules and invariants.
2. [`docs/README.md`](./docs/README.md) — documentation map and precedence.
3. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md) — authoritative active implementation pass.
4. [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — durable architecture and expansion design.

Keep these documents synchronized when architecture or execution policy changes.
