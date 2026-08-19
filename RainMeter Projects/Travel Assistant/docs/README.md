# Travel Assistant Documentation

This directory separates **durable architecture** from the **current implementation handoff** so later connector/GPT/Codex runs do not accidentally follow an obsolete conversation or plan.

## Read order

For any change under `RainMeter Projects/Travel Assistant/`:

1. [`../AGENTS.md`](../AGENTS.md) — always first. Subtree scope, safety, data/recommendation invariants, performance/storage bounds, and workflow rules.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — when marked **ACTIVE**, the authoritative current implementation scope and acceptance criteria. The filename is historical; it also governs connector-first work.
3. [`ARCHITECTURE.md`](./ARCHITECTURE.md) — durable provider, data, analytics, recommendation, retention, and expansion design.
4. [`PROVIDER_DISCOVERY.md`](./PROVIDER_DISCOVERY.md) — current provider choices, endpoint boundaries, bootstrap status, and unresolved provider validation.
5. [`../Readme.md`](../Readme.md) — human-facing project overview.

## Instruction precedence

If documents disagree:

- `AGENTS.md` invariants and safety boundaries always apply.
- An **ACTIVE** `NEXT_CODEX_RUN.md` controls the current implementation scope.
- `ARCHITECTURE.md` controls durable structural intent unless an active run explicitly includes an approved architecture change; if architecture changes, update `ARCHITECTURE.md` in the same pass.
- `PROVIDER_DISCOVERY.md` records provider-specific facts and implementation choices but does not override safety/architecture rules.
- `Readme.md` is the project entry point and should summarize current behavior, not override implementation instructions.
- Historical conversation/context is useful background but must not silently override current repository instructions.

## Document lifecycle

### `NEXT_CODEX_RUN.md`

Rolling handoff with explicit status:

- **ACTIVE** — there is a concrete implementation pass to execute.
- **COMPLETED** — the defined scope has been implemented/validated and the result section records evidence and remaining risks.

When new work is requested after a completed run, update/rewrite the actionable scope and set the status back to **ACTIVE** instead of creating competing task documents.

### `ARCHITECTURE.md`

Durable technical decisions and expansion strategy. Update it whenever persistent data contracts, provider boundaries, recommendation semantics, retention rules, or core module responsibilities change.

### `PROVIDER_DISCOVERY.md`

Provider-specific implementation record. Update it when the live stock, resale-price, historical bootstrap, or cross-check provider contract changes.

### `Readme.md`

Human-readable summary: what the tool is, current scope, major behavior, repository location, installation/testing entry points, and how to navigate the docs.

## Project state

Travel Assistant is currently pre-use and under active implementation. The repository now contains an initial Rainmeter skin, configuration contracts, live-stock updater, local history/cycle engine, recommendation model, provider registry, installer, synthetic fixtures, and static validation tooling. Version 1 remains focused on UK/Japan Xanax while retaining generic internal item/country/provider abstractions for future expansion.
