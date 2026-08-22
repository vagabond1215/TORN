# Travel Assistant Documentation

This directory separates durable architecture from the active implementation handoff so later runs do not follow obsolete conversation state.

## Read order

1. [`../AGENTS.md`](../AGENTS.md) — subtree invariants and product boundaries.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — authoritative active implementation/validation scope when **ACTIVE**.
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md) — durable collection/catalog/MV/capacity/opportunity structure.
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

The active **0.6.0 candidate** restores the opportunity list as the primary surface and makes optimizer intelligence an ordering layer rather than a replacement UI.

Current primary behavior:

- up to eight evidence-backed country/item opportunities;
- persistent Item/Trip/Country/Category filters;
- `OPTIMAL`, `UPCOMING`, `PROFIT`, and `TIME` orderings;
- no separate Chance sort;
- `OPTIMAL` = probability-weighted gross trip profit per total elapsed hour;
- global optimal row stays marked while another ordering is selected;
- current/future window timing plus leave timing, likelihood, elapsed time, gross profit, foreign price and MV in each row;
- Energy/Nerve waste constraints for new outbound opportunities;
- stable `country:itemId` graph actions;
- 8-hour on-demand graphs with hourly markers and left-edge carry-forward;
- background route optimizer retained for compatibility and MV-priority work.

This 0.6 candidate is pending target-Windows/Rainmeter acceptance. See `NEXT_CODEX_RUN.md` for the exact focused acceptance commands.
