# Travel Assistant Documentation

This directory separates **durable architecture** from the **current implementation handoff** so later connector/GPT/Codex runs do not accidentally follow an obsolete conversation or plan.

## Read order

For any change under `RainMeter Projects/Travel Assistant/`:

1. [`../AGENTS.md`](../AGENTS.md) — always first. Subtree scope, safety, data/recommendation invariants, performance/storage bounds, and workflow rules.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — when marked **ACTIVE**, the authoritative current implementation scope and acceptance criteria. The filename is historical; it also governs connector-first work.
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md) — durable provider, data, analytics, recommendation, retention, and expansion design.
4. [`IMPLEMENTATION_STATUS.md`](./IMPLEMENTATION_STATUS.md) — current connector-first implementation checkpoint, completed pieces, and remaining local/runtime boundaries.
5. [`PROVIDER_DISCOVERY.md`](./PROVIDER_DISCOVERY.md) — current live/provider choices and endpoint boundaries.
6. [`HISTORICAL_BOOTSTRAP.md`](./HISTORICAL_BOOTSTRAP.md) — historical-source discovery, seed-truth rules, and bounded import workflow.
7. [`../Readme.md`](../Readme.md) — human-facing project overview.

## Instruction precedence

If documents disagree:

- `AGENTS.md` invariants and safety boundaries always apply.
- An **ACTIVE** `NEXT_CODEX_RUN.md` controls the current implementation scope.
- `ARCHITECTURE.md` controls durable structural intent unless an active run explicitly includes an approved architecture change; if architecture changes, update `ARCHITECTURE.md` in the same pass.
- provider/bootstrap documents record source-specific facts and workflows but do not override safety/architecture rules;
- `IMPLEMENTATION_STATUS.md` records progress/evidence and known gaps but does not replace the active run;
- `Readme.md` is the project entry point and should summarize current behavior, not override implementation instructions;
- historical conversation/context is useful background but must not silently override current repository instructions.

## Document lifecycle

### `NEXT_CODEX_RUN.md`

Rolling handoff with explicit status:

- **ACTIVE** — there is a concrete implementation pass to execute.
- **COMPLETED** — the defined scope has been implemented/validated and the result section records evidence and remaining risks.

When new work is requested after a completed run, update/rewrite the actionable scope and set the status back to **ACTIVE** instead of creating competing task documents.

### `ARCHITECTURE.md`

Durable technical decisions and expansion strategy. Update it whenever persistent data contracts, provider boundaries, recommendation semantics, retention rules, or core module responsibilities change.

### `IMPLEMENTATION_STATUS.md`

Rolling implementation checkpoint. Use it to record connector-safe progress, local validation still required, known limitations, and concrete next tasks without falsely marking the active implementation run complete.

### `PROVIDER_DISCOVERY.md`

Provider-specific implementation record. Update it when the live stock, resale-price, historical bootstrap, or cross-check provider contract changes.

### `HISTORICAL_BOOTSTRAP.md`

Historical-data truth/provenance rules and the current bounded bootstrap procedure. Keep it synchronized with `data/seed/README.md` and the tools under `tools/`.

### `Readme.md`

Human-readable summary: what the tool is, current scope, major behavior, repository location, installation/testing entry points, and how to navigate the docs.

## Project state

Travel Assistant is currently pre-use and under active implementation. The repository contains an initial Rainmeter skin, configuration contracts, live-stock updater, local history/cycle engine, price/profitability-aware recommendation model, provider registry, installer, synthetic fixtures, production-function replay tests, bounded seed/bootstrap tooling, and static validators. Version 1 remains focused on UK/Japan Xanax while retaining generic internal item/country/provider abstractions for future expansion.
