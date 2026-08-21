# Travel Assistant Documentation

This directory separates **durable architecture** from the **current implementation handoff** so later connector/GPT/Codex runs do not accidentally follow an obsolete conversation or plan.

## Read order

For any change under `RainMeter Projects/Travel Assistant/`:

1. [`../AGENTS.md`](../AGENTS.md) — always first. Subtree scope, safety, collection/visibility/optimizer separation, performance/storage bounds, and workflow rules.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — when marked **ACTIVE**, the authoritative current implementation scope. The filename is historical; it also governs connector-first work.
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md) — durable provider, observation/cycle, economics, collection, presentation, travel-context, retention, and optimizer design.
4. [`IMPLEMENTATION_STATUS.md`](./IMPLEMENTATION_STATUS.md) — current implementation checkpoint and remaining live/Windows validation boundary.
5. [`PROVIDER_DISCOVERY.md`](./PROVIDER_DISCOVERY.md) — live/provider choices and endpoint boundaries.
6. [`HISTORICAL_BOOTSTRAP.md`](./HISTORICAL_BOOTSTRAP.md) — historical-source discovery, seed-truth rules, and bounded import workflow.
7. [`WINDOWS_VALIDATION.md`](./WINDOWS_VALIDATION.md) — target Windows/Rainmeter validation procedure.
8. [`../Readme.md`](../Readme.md) — human-facing project overview.

## Instruction precedence

If documents disagree:

- `AGENTS.md` invariants and safety boundaries always apply;
- an **ACTIVE** `NEXT_CODEX_RUN.md` controls the current implementation scope;
- `ARCHITECTURE.md` controls durable structural intent unless the active run explicitly changes architecture, in which case update it in the same pass;
- provider/bootstrap documents record source-specific facts but do not override safety/architecture rules;
- `IMPLEMENTATION_STATUS.md` records progress/evidence and known gaps but does not replace the active run;
- `WINDOWS_VALIDATION.md` defines local evidence gathering but does not relax model/provider safety;
- `Readme.md` summarizes current behavior and does not override implementation instructions;
- historical conversation is background only and must not silently override current repository instructions.

## Document lifecycle

### `NEXT_CODEX_RUN.md`

Rolling handoff with explicit status:

- **ACTIVE** — concrete implementation/validation pass in progress;
- **COMPLETED** — defined scope implemented and validated with evidence recorded.

When new work is requested after a completed or superseded run, update this rolling handoff rather than creating competing task documents.

### `ARCHITECTURE.md`

Durable technical decisions: provider boundaries, collection/visibility/optimizer separation, observation/cycle identity, travel economics, capacity, retention, UI/runtime responsibilities, and future route scheduling.

### `IMPLEMENTATION_STATUS.md`

Factual checkpoint: what exists in the connector-authored repository, what has actually run on Windows, known limitations, and next validation/implementation tasks.

### `PROVIDER_DISCOVERY.md`

Provider-specific record. Update when live stock, resale, historical bootstrap, travel-state, or cross-check contracts change.

### `HISTORICAL_BOOTSTRAP.md`

Historical truth/provenance rules and bounded bootstrap procedure. Keep synchronized with `data/seed/README.md` and tools under `tools/`.

### `WINDOWS_VALIDATION.md`

Operational validation checklist. Keep synchronized with focused tests, `tests/Run-All.ps1`, provider validation, installer behavior, and the current visible/collection scopes.

### `Readme.md`

Human-readable summary of current visible behavior, background expansion, installation/testing entry points, and documentation navigation.

## Project state

Travel Assistant is pre-use and under active expansion.

The **visible** Rainmeter UI still uses the established UK/Japan Xanax proof. The data layer now observes all 11 foreign countries, has locally resolved all 202 item categories in the current provider dataset, filters five verified legacy country-item rows out of new learning/economics work, and is beginning a one-request-at-a-time active-item Torn resale-price queue. New markets remain hidden and non-optimizer-eligible until category-specific capacity, generalized economics, filters, travel context and confidence rules are implemented and validated.
