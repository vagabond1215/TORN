# Faction Ledger Codex Documentation

This directory separates **current execution instructions** from **architecture/history** so a new Codex session does not accidentally rerun an obsolete prompt.

## Read order

For any Codex change under `Faction Ledger/`:

1. [`../AGENTS.md`](../AGENTS.md) — always read first. It contains subtree safety rules, development-mode branch policy, and non-negotiable data-integrity invariants.
2. [`NEXT_CODEX_RUN.md`](./NEXT_CODEX_RUN.md) — read next when its status is **ACTIVE**. It is the authoritative current implementation scope and handoff checklist.
3. [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md) — architecture, completed migration plan, historical handoffs, and prior validation evidence.
4. GitHub issue **#2** and current PR/review discussion — use for current review/status when GitHub access is available.

## Instruction precedence

If documentation disagrees:

- `AGENTS.md` safety/data invariants and current branch policy always apply.
- An **ACTIVE** `NEXT_CODEX_RUN.md` controls the current implementation scope.
- `CODEX_MULTI_TENANCY_RUN.md` supplies architectural context and history; an older embedded prompt there must not override the active next-run handoff.
- `README.md` is a human/project overview and entry point, not a substitute for the task files above.

## Lifecycle

`NEXT_CODEX_RUN.md` is a rolling handoff:

- **ACTIVE** — there is a concrete follow-up Codex run to execute.
- **COMPLETED** — the listed blockers were implemented and behaviorally validated; the dated result section should identify the final SHA and tests.
- If review finds another blocker, update the actionable scope and return the status to **ACTIVE** rather than creating scattered competing prompts.

Preserve historical migration/test evidence in `CODEX_MULTI_TENANCY_RUN.md`. Do not delete old handoffs merely because a newer run supersedes them.

## Development branch policy

Faction Ledger is currently pre-production and not in active service.

Steady-state policy after the current bridge is merged:

```text
main   ← Codex works here directly during pre-production development
```

The current transition is the only exception:

```text
codex/faction-ledger-multitenancy   (PR #3 / final bridge)
                 ↓
                main
```

PR #3 now targets `main` directly. The old `agent/fix-faction-ledger-sync-safety` / PR #1 integration layer is superseded.

The ACTIVE next-run handoff requires Codex to reconcile current `origin/main` into the Codex branch, finish the narrow remaining blockers, validate, and hand PR #3 back for a one-time merge. After that merge, future Codex sessions start from and push to `main` directly until a human declares the application actively used.

When actual use begins, restore branch/PR/CI protection before further production-affecting development.

Direct-to-`main` development never authorizes deployment, production D1 access/migration, force-pushes, or arbitrary-faction production enablement.
