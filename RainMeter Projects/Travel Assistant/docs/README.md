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
- an **ACTIVE** `NEXT_CODEX_RUN.md` controls current implementation/acceptance scope.
- `ARCHITECTURE.md` controls durable structure unless the active run intentionally changes and updates it.
- `IMPLEMENTATION_STATUS.md` records evidence, not future authority.
- provider/bootstrap docs do not override architecture/safety.
- conversation history is background, not a replacement for repository instructions.

## Current project state

Recorded data foundation at the last target-Windows check:

```text
11 foreign countries
232 provider country-item rows
227 active market relationships
202 distinct item IDs
202 resolved categories
5 verified legacy relationships
```

The active **0.6.0 candidate** is now a compact opportunity-card surface:

- `UPCOMING`, `GROSS PROFIT`, and `PROFIT/HR` are the selectable local/immediate sorts; Name is fallback-only when timing/profit inputs are unavailable;
- no user-facing OPTIMAL score or row place numbers;
- fresh current in-stock rows stay visible even when likelihood is `LEARNING`;
- each card uses a destination flag rail with a white elapsed-time strip;
- country name/code and duplicate elapsed time are removed from the card body;
- gross is displayed as a bare dollar amount, while quantity remains available in tooltip/internal projection;
- each row has a highlighted chart button for a one-at-a-time **inline 8-hour graph**;
- the inline graph is local-only and uses retained observation truth;
- 48h raw / 90d completed-cycle retention remains independent of the 8h display;
- background `OptimalRoute.ps1` remains compatibility/MV-priority infrastructure only.

This candidate is pending target-Windows/Rainmeter acceptance. See `NEXT_CODEX_RUN.md` for the focused acceptance commands and current visual checklist.
