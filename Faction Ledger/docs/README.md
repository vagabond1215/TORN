# Faction Ledger Codex Documentation

This directory separates **current execution instructions** from **architecture/history** so a new Codex session does not accidentally rerun an obsolete prompt.

## Read order

For any Codex change under `Faction Ledger/`:

1. [`../AGENTS.md`](../AGENTS.md) — always read first. It contains the subtree safety rules and non-negotiable data-integrity invariants.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — read next when its status is **ACTIVE**. It is the authoritative current implementation scope and handoff checklist.
3. [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md) — architecture, completed migration plan, historical handoffs, and prior validation evidence.
4. GitHub issue **#2** and draft PR **#3** — use for current review discussion/status when GitHub access is available.

## Instruction precedence

If documentation disagrees:

- `AGENTS.md` safety/data invariants always apply.
- An **ACTIVE** `NEXT_CODEX_RUN.md` controls the current implementation scope.
- `CODEX_MULTI_TENANCY_RUN.md` supplies architectural context and history; an older embedded prompt there must not override the active next-run handoff.
- `README.md` is a human/project overview and entry point, not a substitute for the task files above.

## Lifecycle

`NEXT_CODEX_RUN.md` should be maintained as a rolling handoff:

- **ACTIVE** — there is a concrete follow-up Codex run to execute.
- **COMPLETED** — the listed blockers were implemented and behaviorally validated; the dated result section should identify the final SHA and tests.
- If review finds another blocker, update the actionable scope and return the status to **ACTIVE** rather than creating scattered competing prompts.

Preserve historical migration/test evidence in `CODEX_MULTI_TENANCY_RUN.md`. Do not delete old handoffs merely because a newer run supersedes them.

## Current branch flow

```text
main
  ↑
agent/fix-faction-ledger-sync-safety      (integration / PR #1)
  ↑
codex/faction-ledger-multitenancy         (current Codex work / PR #3)
```

Codex works on `codex/faction-ledger-multitenancy`. Do not deploy, merge, force-push, or point local migration/test commands at production D1.
