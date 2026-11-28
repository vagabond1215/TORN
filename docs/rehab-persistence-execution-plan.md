# Rehabilitation, persistence and log execution plan
Updated 2026-11-27. Baseline 7a8675e15c784a98ce504756d6b4954ee56f692c. Canonical repo vagabond1215/TORN, main, docs/ only. Read root AGENTS.md, development-handoff.md, development-roadmap.md, persistence-implementation-plan.md and log-archive-implementation-plan.md. Refines existing gates, does not replace their contracts.

## Objectives and constraints
- Preserve live Guide, Home, Energy, unified Timeline/Log and legacy backups; no competing polling, automatic gameplay, credentials, guessed transactions or cross-project edits.
- Distinguish cumulative inference, exact log evidence, estimates and manual confirmations. Never treat retrieval time as action time. Preserve earlier ledger rows and tombstones; no silent eviction.
- Verified owner/epoch, shared recovery lock and explicit user decisions. Journal before protected multi-key writes; localStorage is recoverable, not physically atomic. Old readers fail closed on new versions. New writers unloaded until native gates pass.
- Small non-force commits to main, expected HEAD check, checkpoint and actual test environment.

## Work packages and acceptance
| ID | Work / files | Acceptance / status |
| --- | --- | --- |
| P1.4b.1 | account-rehab-transition.js + test: expire reservation end + 24h; baseline within 30m before start, no later; reject overlapping completed evidence even with lower count. | Implemented isolated candidate; adapted fixture passed. Conservative policy matching polling window, not proof of action time. Native retest pending. |
| P1.4c.1 | Isolated versioned rehab journal: calendar, activity-spend, lineage, manifest, exact before/after, immutable evidence and decision time; unknown price leaves ledger unchanged. | Recompute under shared exclusive lock, verified epoch, reject stale preview, pending journal, invalid ledger, session hold, revision/lineage conflict; fixed destinations, no live integration. |
| P1.4c.2 | Recovery/interruption fixtures: journal and each write, finalization, reverse rollback, foreign account, tampered evidence, concurrent writes, stale epoch, unknown cost, duplicate IDs and capacity. | Finalize fully matched only; rollback known before/after only; retain conflict; validate both manifests, lineage and exact paired delta. Native browser/crypto/Web Locks required. |
| P1.4d | Explicit reserve/cancel, first-account bootstrap, capture coordination and active-session compatibility, scheduler observation adapter, version dispatch/recovery UI, V3 backup import/export. | Never activate held session or discard lineage; test old tab, refresh, account switch/key rotation, legacy backup. Gate live activation. |
| P1.5 | Read-only protected ledger/history comparison; stable IDs, ancestry, corrections and held states. | No automatic merge/post or timestamp winner; separate actual/inferred/estimated, review collisions and unknown amounts. |
| R0/L2 | Native regression, log-archive and log-collector browser fixtures, real independent-tab IDB/Web Locks, quota, versionchange, late purge/account rotation, authorized own-account API shape. | node docs/run-regression.cjs and permitted HTTP(S) synthetic fixtures; log actual results. Do not bypass browser policy or claim mock tests as native. Independent of P1.4c. |
| L3 | Exclusive durable idle collector, opt-in consent/pause, retention, clear, indexed unified table, source coverage/status. | One idle slot, no volatile fallback, no source dedup without verified IDs. Native gates first. |
| L4/F1 | Versioned typed log interpreters with stable evidence IDs, ledger/activity adapters. | Verify exact documented types and permitted payloads; unknown money stays unknown; idempotent replay, explicit corrections. |
| R1/R2 | Optimizer parity and remaining guide roadmap. | End-to-end freshness, active sessions, reserves, missing permissions; no numerical claims before parity. |

## Native gate checklist
- Node syntax and dynamically discovered CJS/MJS tests.
- Actual browser storage, crypto, concurrency and rollback using synthetic data, no API key.
- Authenticated API shape/permissions in authorized user environment, not exported in fixtures.
- Deployed regression, touch/keyboard/layout, old/current backups, account switch/disconnect and explicit restore/hold behavior.
- Gate live changes; isolated source/tests/plans can land earlier.

## Next executable task
P1.4c.1 isolated journal. Reuse section registry, revision verify/observe, calendar lineage and shared recovery lock. Store bounded four-destination before/after values, exact evidence and decision time. Explicit lineage bootstrap and tracked complete snapshot; verify unchanged unrelated sections. Re-derive from immutable evidence for recovery rather than accepting arbitrary edits. Unknown cost does not add ledger entry. Preserve V3-V5 journal and live scheduler. If native testing unavailable, do not switch writers or activate protected application.

### P1.4c.1 isolated V6 rehab completion journal (2026-11-27)
Baseline `d1c33d7`. New account-rehab-journal.js and deterministic fixture. V6 shares per-account recovery lock and journal hold; fixed calendar, activity-spend, lineage and manifest destinations. Requires explicit reviewed event/cost/evidence, synchronous current nonsecret observation reader and verified epoch guard; re-derives exact effects under lock and validates freshness before writing. Unknown price leaves ledger unchanged; known price requires an already tracked ledger, first-ledger bootstrap remains a separate gate. Exact before/after, fresh revisions, lineage verification and bounded journal; recovery re-derives original decision at its recorded time, never new attribution. Fully matched finish only, reverse rollback of known states, retain conflicts. Adapted fixture passed (mock storage/lock/fs/assert/digest), including journal and all four destination write failures, unknown cost, wrong/stale state, duplicate, tamper, finish/rollback, epoch interruption. No index wiring, scheduler changes, live account writes, API calls or native browser tests. Next P1.4c.2 independent native crypto/browser/concurrency tests and review; explicit reserve/cancel, first-ledger/calendar bootstrap and active-session coordination before writer integration. Do not claim localStorage physical atomicity.
