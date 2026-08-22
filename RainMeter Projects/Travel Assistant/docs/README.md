# Travel Assistant Documentation

This directory separates durable architecture from the active implementation handoff so later runs do not follow obsolete conversation state.

## Read order

1. [`../AGENTS.md`](../AGENTS.md) — subtree invariants and product boundaries.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — authoritative active implementation/validation scope when **ACTIVE**.
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md) — durable collection/catalog/MV/capacity/optimizer structure.
4. [`IMPLEMENTATION_STATUS.md`](./IMPLEMENTATION_STATUS.md) — factual implementation checkpoint and pending Windows boundary.
5. [`PROVIDER_DISCOVERY.md`](./PROVIDER_DISCOVERY.md) — provider notes.
6. [`HISTORICAL_BOOTSTRAP.md`](./HISTORICAL_BOOTSTRAP.md) — historical truth/provenance rules.
7. [`WINDOWS_VALIDATION.md`](./WINDOWS_VALIDATION.md) — target Windows/Rainmeter validation procedure.
8. [`../Readme.md`](../Readme.md) — human-facing summary.

## Instruction precedence

- `AGENTS.md` invariants/safety always apply.
- an **ACTIVE** `NEXT_CODEX_RUN.md` controls the current implementation/acceptance scope.
- `ARCHITECTURE.md` controls durable structure unless the active run intentionally changes and updates it.
- `IMPLEMENTATION_STATUS.md` records evidence, not future authority.
- provider/bootstrap docs do not override architecture/safety.
- conversation history is background, not a replacement for repository instructions.

## Current project state

Accepted data foundation at the last target-Windows check:

```text
11 foreign countries
232 provider country-item rows
227 active market relationships
202 distinct item IDs
202 resolved categories
5 verified legacy relationships
```

The previous four independent item cards/graphs were an intermediate UI proof. The current committed **0.5.0 candidate** replaces that surface with one minimalist, evidence-aware next-trip optimizer showing only the item(s) to purchase.

0.5 adds:

- all-11-country travel economics for route comparison;
- active-catalog Item/Category filters plus Trip/Country filters;
- full-catalog Ignore List;
- 100% Torn MV valuation by default and optional 95% MV;
- no minimum-profit/LOW_MARGIN timing gate in the main optimizer;
- independently configurable Energy/Nerve waste policies and maximum losses;
- Energy-over-natural-max stacking bypass only for Energy;
- current travel/bar context from one bounded `travel,basic,bars` call;
- category-aware mixed-capacity purchase plans;
- modeled arrival availability from retained cycles;
- optimizer-driven MV queue priority while preserving the one-request/update cap;
- compact aligned purchase rows with `$foreign ($MV)` formatting.

This 0.5 candidate is pending target-Windows/Rainmeter acceptance. It is a **next-trip planner**, not yet the future bounded multi-trip sequence scheduler.

See `NEXT_CODEX_RUN.md` for the exact focused acceptance commands.
