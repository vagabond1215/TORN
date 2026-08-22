# Travel Assistant Documentation

This directory separates durable architecture from the active implementation handoff so later connector/GPT/Codex runs do not follow obsolete conversation state.

## Read order

For any change under `RainMeter Projects/Travel Assistant/`:

1. [`../AGENTS.md`](../AGENTS.md) — subtree invariants, safety, collection/visibility separation, runtime/performance rules.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — authoritative active implementation/validation scope when marked **ACTIVE**.
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md) — durable provider, history, economics, filters, travel-context, presentation, and optimizer structure.
4. [`IMPLEMENTATION_STATUS.md`](./IMPLEMENTATION_STATUS.md) — factual implementation checkpoint and pending Windows boundary.
5. [`PROVIDER_DISCOVERY.md`](./PROVIDER_DISCOVERY.md) — provider/endpoint-specific notes.
6. [`HISTORICAL_BOOTSTRAP.md`](./HISTORICAL_BOOTSTRAP.md) — historical truth/provenance and bounded import rules.
7. [`WINDOWS_VALIDATION.md`](./WINDOWS_VALIDATION.md) — target Windows/Rainmeter validation procedure.
8. [`../Readme.md`](../Readme.md) — human-facing project summary.

## Instruction precedence

If documents disagree:

- `AGENTS.md` invariants/safety always apply;
- an **ACTIVE** `NEXT_CODEX_RUN.md` controls current implementation scope;
- `ARCHITECTURE.md` controls durable structural intent unless the active run intentionally changes it and updates architecture in the same pass;
- `IMPLEMENTATION_STATUS.md` records evidence/progress, not authority over active scope;
- provider/bootstrap docs do not override architecture/safety;
- `Readme.md` is a summary only;
- historical conversation is background, not a replacement for repository instructions.

## Document lifecycle

### `NEXT_CODEX_RUN.md`

Rolling handoff:

- **ACTIVE** — implementation or validation still in progress;
- **COMPLETED** — defined scope implemented and accepted with evidence recorded.

### `ARCHITECTURE.md`

Durable boundaries: provider adapters, market identity/validity, observation/cycle truth, resale, category capacity/economics, local preferences, travel context, presentation filters, and future route scheduling.

### `IMPLEMENTATION_STATUS.md`

Factual checkpoint: what exists in the repository, what actually ran on Windows/Rainmeter, known limitations, and the next validation boundary.

## Project state

Travel Assistant is pre-use and under active expansion.

Accepted data foundation:

```text
11 foreign countries observed
232 provider country-item rows at last live check
227 active market relationships
202 distinct observed item IDs
202 locally resolved categories
5 verified legacy market relationships suppressed from new learning/resale/display
```

Accepted presentation foundation:

```text
UK Xanax
UK Nessie Plushie
Japan Xanax
Japan Cherry Blossom
```

Those are independent item cards with a two-expanded-card cap and market-value references.

The current committed **0.4.0 candidate** adds:

- Item / Short-Medium-Long / Country / Category presentation filters;
- one persistent pinned/favorite market;
- travel-destination card suppression;
- profitable-only view;
- full-catalog Ignore List;
- five-minute retry eligibility for failed visible/pinned resale values;
- ignored-item suppression from broad per-item resale requests.

These 0.4.0 controls are pending target-Windows/Rainmeter acceptance. See `NEXT_CODEX_RUN.md` for the focused commands and interaction checks.
