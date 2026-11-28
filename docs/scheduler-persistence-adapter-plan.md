# Scheduler persistence adapter: implementation gates

Status: design and audit only. No production writer switched. Applies only to `vagabond1215/TORN/docs`.

## Existing paths requiring explicit conversion

| Current writer | Required boundary | Remaining issue |
| --- | --- | --- |
| activity-scheduler.saveEvent/removeEvent | V4 personal/general or V5 operational mutation | Exact before/after, preserve ID tombstones, refuse kind conversion; no rehabilitation through generic paths |
| crime-guide rehabilitation reserve | V7 planRehab | Review current travel eligibility, war cutoff, blocking commitments and counter baseline immediately before journal |
| crime-guide recommendation rendering -> reconcileRehab | V6 explicit reviewed completion | Remove write-on-render in protected mode; cumulative counter delta is inference, no silent financial posting |
| activity-scheduler.recordSpend | Separate explicit expense writer | Current filtered 90-day read and slice(-500) must not silently drop old ledger rows; no generic capture of financial drift |
| guide.js revisionQueue | Guarded capture | Explicit verified mode and owner epoch, shared lock; protected calendar/ledger cannot advance by observation |
| V1/V2 restore and preference merge | Version-aware recovery and backup policy | Refuse legacy overwrite/downgrade of installed lineage; separate V3 authenticated envelope and explicit bootstrap |

## P1.4d.5 proposed sequence

1. Add an isolated scheduler decision adapter that consumes immutable reviewed snapshots and a synchronous current context reader, with no API requests and no direct writes. Reuse existing pure warWindow and current activity policy rather than inventing a second cutoff. Reject stale owner/epoch, changed calendar/ledger/lineage/manifest, missing required profile/travel/war inputs, blocking conflicts and active/held training; validate start/end, future reservation, explicit approval, and baseline freshness. Require the *current* context to still match at journal boundary, including policy decisions that may change during digest work.
2. Define a nonsecret verified epoch handle from the existing API coordinator. verifyBackupOwner already closes over the secret and epoch and returns playerId/isCurrent after user/basic verification. A remembered identity alone is not proof. A same-player key rotation invalidates the handle. A live capture queue must obtain a verified session scope without a new identity request on every local write. Do not persist key, closure, or epoch token.
3. Specify activation and downgrade boundary: explicit protected mode after approved V8 bootstrap, never auto-select legacy just because lineage disappeared. Older direct writers and V1/V2 restore must be refused for a migrated account; old-tab detection must not rely solely on Web Locks. Persisted migration-state contract and its rollback/recovery semantics still need design; missing/corrupt marker is review, not automatic recreation.
4. Review active training and spend writers independently. Until there is a verified compatibility protocol, defer capture/transactions for active or held sessions; preserve all existing session, review and history records. No session activation or automatic reconciliation.
5. Prepare native test fixtures for actual independent tabs, storage failures, reload/rotation, journal recovery, old-tab interference and protected upgrade. Real Web Locks are cooperative; a noncooperating writer can race even after the last synchronous recheck. Never claim physical atomicity.

## Acceptance

- Isolated adapter tests prove exact before/after, stale policy and cutoff rejection, reservation overlap, approval and epoch checks, no unexpected calls or writes.
- Old-tab drift cannot be blessed as a valid protected revision by the new capture path.
- Existing active and held training cannot be resumed, altered, or silently dropped.
- Legacy behavior and current deployed Nice/merit/sidebar work remain unchanged until native validation and activation review.
- A successful guard is not evidence of a transaction occurring in-game.

## Next executable work

Implement the isolated scheduler decision adapter and test its policy/context-reader contract; then add the guarded journal commit-boundary callback and native fixture. Do not wire production mutation paths until native R0/L2/crypto and migration gates pass.
