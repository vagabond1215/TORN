# Travel Assistant Agent Instructions

These instructions apply to the entire `RainMeter Projects/Travel Assistant/` subtree, regardless of whether work is performed through the GitHub connector, GPT, Codex, or a local development environment.

## Read order

Before changing code or data, read:

1. **This file (`AGENTS.md`)** — authoritative subtree rules and invariants.
2. [`docs/README.md`](./docs/README.md) — documentation routing and precedence.
3. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md) — when marked **ACTIVE**, the authoritative implementation scope. Despite the historical filename, it applies to connector-first implementation as well as Codex/local work.
4. [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — durable architecture, data model, retention, provider boundaries, economics, and expansion design.
5. [`docs/IMPLEMENTATION_STATUS.md`](./docs/IMPLEMENTATION_STATUS.md) — current implementation checkpoint and remaining validation boundary.
6. [`Readme.md`](./Readme.md) — human-facing project overview.

If an older plan conflicts with an **ACTIVE** `NEXT_CODEX_RUN.md`, follow the current run document while preserving every invariant in this file.

## Connector-first execution policy

The preferred implementation path for Travel Assistant is **GPT + the connected GitHub connector**. Codex/local execution is a fallback, not the default.

- Use the GitHub connector whenever it can safely inspect the repository, read files, create/update text source files, maintain documentation, inspect history, manage normal commits/branches/PRs, or otherwise perform the requested repository work.
- Do **not** invoke Codex or require a separate local coding pass merely because source code must be written. If the connector can create or update the required files safely, use it.
- External provider/API discovery may use normal web access where needed; repository changes should still be performed through the GitHub connector when practical.
- Use Codex/local execution only when there is a concrete requirement the connector cannot satisfy, such as running Rainmeter on Windows, executing PowerShell/Rainmeter behavior against the local machine, measuring local CPU/RAM/disk use, exercising OS-specific integrations, running local-only test tooling, or manipulating files/binaries the connector cannot safely create or validate.
- Before escalating to Codex/local execution, identify the specific missing capability or validation requirement. Keep any Codex/local scope as narrow as possible and return durable results/documentation to the repository afterward.
- Connector-only work must not claim local runtime validation that did not occur. Record repository/static/fixture validation separately from Windows/Rainmeter/local execution validation.
- A future implementation should remain maintainable from the connector wherever possible: favor text-based source/config, deterministic fixtures, scriptable tests, and provider adapters over opaque generated/binary state.

## Scope boundary

- Work only inside `RainMeter Projects/Travel Assistant/` unless the user explicitly requests a repository-wide change.
- Do not modify `Faction Ledger/`, faction assets/data, spreadsheets, guides, or other TORN projects as a side effect of Travel Assistant work.
- Version 1 is deliberately limited to **Xanax in the United Kingdom and Japan** in the UI.
- Internals must remain generic enough to add more items/destinations later without a rewrite.
- Do not add multi-item UI, broad country selection, or unrelated travel features until the v1 Xanax model is validated unless explicitly requested.

## Development branch policy

Travel Assistant is currently an isolated, pre-use project.

Until a human declares otherwise:

- normal development may update `main` directly within this subtree after appropriate validation;
- begin from current `origin/main` and inspect for conflicting work before editing;
- never force-push, rewrite shared history, or discard unrelated user work;
- if `origin/main` moves during a run, reconcile safely before pushing;
- when the project becomes relied on operationally, move to feature branches/PR review and appropriate automated validation before further high-impact changes.

Recommended start from the repository root:

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git status -sb
```

If local `main` is dirty or diverged, inspect rather than automatically resetting/rebasing/force-pushing.

## Non-negotiable data / recommendation invariants

1. **No recommendation beats a bad recommendation.** Suppress departure advice when stock data is stale, resale data is stale for a money-sensitive decision, confidence is inadequate, the price regime is unsupported, sources materially disagree, travel economics are unresolved, or profitability is below configured thresholds.
2. **Actual sellout means actual sellout.** The primary `Last Sold Out` field is historical/observed, not a predicted sellout timestamp.
3. **Restock information is not a profitability recommendation.** An observed or statistically supported restock time may remain visible even when `LOW_MARGIN`/`UNPROFITABLE` suppresses all departure advice.
4. **Foreign price is first-class data.** Do not pool radically different price/depletion regimes as if they were equivalent.
5. **Current depletion outranks stale averages.** Once a live cycle is underway, recent observed stock decay should meaningfully inform the model and may shorten safety; it must not expand a conservative window beyond supporting evidence.
6. **Safe-window language must be conservative.** A `SAFE_WINDOW` must be supported by qualifying comparable historical cycles; do not label a probabilistic narrow-drop estimate as safe.
7. **Best odds is not safe.** When no conservative overlap exists, report a best-departure point/window and confidence/historical hit rate without overstating certainty.
8. **Profitability gates timing.** Continue collecting useful history on low-margin/unprofitable cycles, but suppress departure recommendations. Final profitability must account for the configured selling fee and, where known, travel-mode cost and usable carrying capacity.
9. **Unknown economics are not zero-cost economics.** If a mode has unresolved cost semantics, suppress timing rather than assuming the cost is zero. This is why Business remains configured but disabled until its ticket/free-company branch is modeled.
10. **Provider provenance is retained.** Normalized observations and seed metadata must identify their source sufficiently for debugging and confidence logic.
11. **Provider-specific formats do not leak into the core model.** Convert provider responses to normalized observations at the adapter boundary.
12. **Runtime data is not Git history.** Continuously collected observations, caches, temporary graph output, analysis/probe output, logs, and local credentials belong in ignored runtime/local paths.
13. **Persistent data is schema-versioned.** Seed/history/config formats must carry a schema version or have an unambiguous versioned contract.
14. **Bound storage.** High-resolution history, cycle summaries, logs, generated artifacts, provider probes, and import previews must have explicit retention or size limits.
15. **Bound compute.** Do not run statistical analysis, spawn PowerShell, hit the network, or regenerate graphs every second merely because Rainmeter refreshes every second.
16. **No browser scraping loop.** Prefer documented/suitable data endpoints. Do not repeatedly launch/render/scrape provider webpages.
17. **Never trust provider availability forever.** Cache the last valid state, expose staleness, and fail visibly but gracefully.
18. **Forecasts are not historical truth.** Provider-predicted restock/stockout/window fields may be comparison inputs later, but must not populate actual sellout/restock cycle truth.

## Provider and web-data policy

- Treat Weav3r, YATA, DroqsDB, or other third-party providers as replaceable adapters, not as the application architecture.
- Before using a provider endpoint, inspect its current behavior and usage restrictions.
- Prefer a small number of efficient structured requests over page scraping.
- Historical bootstrap/backfill should be one-time or deliberately bounded, cached, and provenance-documented.
- Do not design a crawler that systematically archives an entire third-party service.
- If a provider cannot safely/stably supply historical data, allow the model to start in `INSUFFICIENT_HISTORY` / `CHECK_EXTERNAL` mode and learn locally.
- Multiple providers may be cross-checked, but disagreement must reduce confidence rather than being silently averaged away.
- Derive committed completed cycles from observed snapshot transitions whenever possible; do not seed provider forecasts as actual events.

## API keys and secrets

- Public Torn API keys that expose only public-facing information may be used as explicitly allowed by the user.
- Any limited/higher-authority key must remain local only and must never be committed.
- Prefer local ignored configuration for credentials and provide committed example/template files when needed.
- Never log full sensitive keys.
- Do not broaden a key's authority merely for convenience if a lower-authority/public source is sufficient.

## Performance / resource budget

Travel Assistant is intended to remain loaded on a Windows desktop for long periods.

Design toward these boundaries:

- Rainmeter may update countdown text every second, but this path should perform only inexpensive local calculations/string updates.
- Network polling should normally be on the order of **60–120 seconds**, subject to provider limits and usefulness.
- Recalculate expensive analytics primarily when new data materially changes the state (restock, sellout, meaningful depletion update, price change, or scheduled low-frequency analysis).
- The final state/economics pass should use cached/local state and must not add another network request each minute.
- Avoid a permanent background browser or heavyweight runtime.
- Prefer one serialized short-lived updater pipeline over many independent PowerShell process launches.
- Avoid thousands of individual Rainmeter meters for graph samples; use a compact graph-rendering approach.
- Keep high-resolution runtime observations roughly **24–48 hours** by default.
- Keep compact completed-cycle summaries roughly **60–90 days** initially unless evidence justifies another bounded retention period.
- Retain long-term learning as compact aggregates where possible.
- Logs, probe captures, analysis output, and candidate imports must rotate/prune or remain intentionally small/runtime-only.

These are design targets rather than guarantees; measure actual CPU/RAM/disk behavior before calling a release stable.

## UI invariants for v1

- Dark/charcoal theme that remains distinguishable on a pure-black desktop.
- Vertically stacked UK and Japan panels.
- Same graph width/alignment for both destinations.
- Three inline paired rows per destination:
  - `Travel | Leave / Window`
  - `Restock | Last Sold Out`
  - `Stock | Foreign Price`
- Relative timing (`Leave in`, `Window opens in`, `Leave before`, etc.) is preferred over a displayed clock.
- When an observed restock is live, an elapsed display such as `live +04:12` is acceptable and preferred over implying the observed timestamp is still a future estimate.
- Default travel mode is **Airstrip**.
- Current selector cycle is `Standard`, `Airstrip`, `WLT`.
- `Business` remains configured for future activation but must stay disabled while its Business Class Ticket/free-company cost branch is unresolved.
- A low-confidence actionable state may expose a clickable `CHECK WEAV3R` / external verification action.
- Do not add an unsupported Windows Clock alarm integration. An internal optional alert can be considered later if explicitly requested.

## Core status / reason codes

Use stable machine-readable statuses and let Rainmeter render them. Initial vocabulary should include at least:

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

Add codes deliberately and document semantics; do not key logic off human display strings.

## Data-model direction

Core observation identity is generic:

```text
timestamp + country + itemId + stock + foreignPrice + source + sourceTimestamp
```

Completed cycles should capture enough information to learn restock and depletion behavior without preserving every raw sample forever:

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
source / provenance
confidence / quality metadata as appropriate
```

Travel economics belong to configuration/state rather than Xanax-specific functions:

```text
country + travelMode -> travelSeconds + travelCost + baseTravelCapacity
local capacityOverride -> usableCapacity when positive
```

Do not name core engine functions/classes/data formats after `XanaxUK` or similar one-off combinations. Prefer generic concepts such as `TravelOpportunityEngine`, `Observation`, `Cycle`, `Provider`, `ItemConfig`, `CountryConfig`, and final recommendation-state/economics guards.

## Validation expectations

Until concrete test tooling exists, every implementation pass must at minimum:

- validate JSON/config syntax;
- run PowerShell parser/static checks applicable to changed scripts;
- exercise provider normalization against saved fixtures, not only live data;
- replay representative historical cycles through the recommendation model;
- verify low-margin/unprofitable suppression;
- verify stale stock and stale resale behavior;
- verify travel-mode changes recalculate recommendations;
- verify travel cost/capacity can affect final trip profitability;
- verify informational restock timing can remain visible when profitability suppresses timing;
- verify unresolved Business economics suppress timing if Business is forced;
- verify runtime retention/pruning is bounded;
- verify ignored local/runtime files are not accidentally staged;
- run `git diff --check` before handoff.

The repository now contains deterministic PowerShell tests and a Windows validation checklist. Do not claim those tests pass until they actually execute on the target/local Windows environment. Record exact commands/results in `docs/NEXT_CODEX_RUN.md` / `docs/IMPLEMENTATION_STATUS.md`.

## Documentation / handoff

- Keep `Readme.md` human-readable and current.
- Keep architecture and durable decisions in `docs/ARCHITECTURE.md` rather than duplicating them in transient prompts.
- Keep source-specific historical rules in `docs/HISTORICAL_BOOTSTRAP.md` / `docs/PROVIDER_DISCOVERY.md`.
- Keep the local runtime checklist in `docs/WINDOWS_VALIDATION.md`.
- Use `docs/NEXT_CODEX_RUN.md` as the rolling current execution handoff.
- When a run is completed, record what was actually implemented, validation performed, unresolved risks, and relevant commit SHAs before setting the run status to `COMPLETED`.
- If a new blocker/follow-up is discovered, update the rolling handoff back to `ACTIVE` rather than creating scattered competing instructions.
