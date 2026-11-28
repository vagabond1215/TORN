# Account transaction boundary (P1 cross-tab consistency gate)

Repository vagabond1215/TORN, branch main, docs only. Isolated prototype; no production activation.

## Why this is necessary

Codex's [native validation](native-validation-2026-11-27.md) recorded 11 sibling-revision failures in 20 trials. Exclusive Web Locks serialized cooperating callbacks but did not establish a reliable cross-agent Web Storage handoff. Rechecking localStorage alone is insufficient.

## Candidate design

- Separate IndexedDB database `torn-city-guide:account-state`, schema 1, one record per owner. Do not mix with personal Log archive, API caches or credentials.
- Record: schema version, playerId, monotonically increasing generation, full allowlisted account bundle with exact raw revision manifest and calendar lineage, registry records and observed deletion markers. No timestamp winner.
- Explicit reviewed initialization accepts only a complete, verified existing tracked calendar and ledger with valid lineage. Refuse pending journals, omitted/invalid sections, held/active training and protected deletion markers. Existing localStorage is read-only and remains untouched. No automatic bootstrap or cutover.
- Prepare domain candidate outside the IDB transaction (including asynchronous Web Crypto and ancestry validation). In one readwrite transaction compare both generation and exact full reviewed record, then commit the complete next state. A stale candidate is rejected; never retry automatically. Only resolve committed after transaction completion. If epoch invalidates after commit, distinguish committed from current; do not misreport rollback. Close/abortPending on lifecycle changes.
- Initial capability: one allowlisted ordinary preference edit with exact before/after, a fresh revision, retained ancestry and deletion markers. Preserve every other record/revision and exact lineage bytes. No arbitrary after-bundle, journal mutation, financial authority, session activation, reset or downgrade.
- Read returns a verified point-in-time snapshot, not a guarantee that no other tab has subsequently advanced it.

## Migration and compatibility are not solved by CAS alone

IDB transactions serialize IDB access, not old localStorage writers. The prototype only copies reviewed state and does not authorize production use. Before cutover define a durable activation/migration state, retained original archive, exact validated migration and an explicit reconciliation procedure for legacy divergence. A migrated owner must not silently revert to localStorage when IDB is unavailable or erased. Old deployed code cannot be made to honor a new lock retroactively. Do not mirror mutable protected bytes back into old storage or assume an old tab is harmless; fence off its data and surface divergence. Never delete an outstanding V1–V8 journal, lineage, ledger or training hold as part of migration. Browser database loss still requires external portable backup and explicit recovery. Local IDB is not encrypted or an independent backup.

## Native acceptance sequence

1. Run node docs/run-regression.cjs. The new contract test exercises schema, raw bytes, ancestry, owner, deletion/recreation, held and journal states and stale source/epoch. Adapted harness pass is not native.
2. Run the existing failing localStorage probe for reference, then the candidate probe using the same installed Playwright Core/Chrome setup:
   `node docs/tests/manual/account-transaction-tabs.cjs 20`
   Repeat 100 trials for stress acceptance. Each uses distinct same-origin tabs, simultaneous initialization and competing edits from the same generation, exact-byte stale rejection, old-source divergence, owner separation, stale guard, reopening, deletion markers and protected bytes. Zero duplicate successful generation transitions; both tabs read same acknowledged winner. Probe uses synthetic source snapshots and actual IDB, not a production migration or V6 acceptance test.
3. Extend with real IDB quota/exhaustion, transaction abort/failure, epoch rotation while pending, versionchange, browser termination/restart and protected writer/recovery tests. Document injected vs actual failures.
4. Implement isolated scheduler policy adapter P1.4d.5 independently. Then integrate domain-specific V4–V8 transition builders into the transactional boundary, design durable migration/hold/backup recovery and repeat all native tests. No generic caller-supplied protected state update.
5. Only after all migration, writer, expense, session, recovery UI and V3 routing gates pass consider controlled activation.

## Status

Implementation 221957d, adapted pure contract fixture passed, new native two-tab probe syntax checked only. Native browser execution remains outstanding for this candidate. Existing Codex baseline remains valid for its tested commit, not a pass for this new module.
