# Native Guide validation, 2026-11-27

GitHub fetch and permitted native Chrome execution succeeded from the Windows checkout. The full Node suite and all five existing browser fixtures passed. **Account persistence remains blocked on cross-tab commit consistency.** The separate durable Log path passed the exercised browser transaction tests. IndexedDB quota and authenticated collector validation are still open.

## Environment and commands

- Windows 11 Home 10.0.26200, Node.js 24.14.1, Git 2.54.0.windows.1, npm 11.11.0, Chrome 158.0.8127.37, Playwright Core 1.65.1. The isolated Chrome contexts used an ephemeral loopback HTTP origin with a secure Web Crypto context and normal browser sandboxing. Playwright was installed in a temporary prefix for validation.
- `git pull --ff-only origin main` advanced the clean checkout to `143e78032f5d9e3bf4659cffbdaa099cc33ffa12`. Revalidated the runtime after the calculator fix in `f9259065257e3611cc44ba7ec3fd55d2d34d4388`. The persistence and archive modules were byte-identical across these commits.
- `node docs/run-regression.cjs` passed before and after the fix. Each run completed 41 of 41 syntax checks and 39 of 39 CJS/MJS fixtures with zero failures or skips. The fixed sequencer fixture includes 15 cases, up from 14. The Node fixtures exercised native Web Crypto for the portable backup, V6 rehab and V8 bootstrap.
- The temporary Playwright runner served `docs/` and ran `node run.cjs fixtures`, `node run.cjs tabs`, `node run.cjs collector-tabs` and `node run.cjs interface` from the checkout. The repository probe below independently reproduces the capture defect. `node --check docs/tests/manual/account-cross-tab.cjs` passed.

## Browser results

| Fixture | Result |
| --- | --- |
| `account-rehab-journal.browser.html` | PASS. Native Web Crypto, localStorage and Web Locks. Competing handles, interrupted destination writes, explicit rollback and finish, and unknown rehab cost. Destination failures were injected. |
| `account-guarded-capture.browser.html` | PASS. Native crypto and locks, ordinary tombstone, protected digest drift rejection, journal hold and epoch invalidation. |
| `disclosure-state.browser.html` | PASS. Real summary clicks, MutationObserver, scoped rebuild and storage restoration of open and closed states. |
| `log-archive.browser.html` | PASS. Real IndexedDB commit, pagination, isolation, conflict, abort, reload, purge, retention and version change. Retention was exercised with a seeded checkpoint. |
| `log-collector.browser.html` | PASS. Real IndexedDB and Web Locks with intercepted API behavior, pause/purge, visibility, rotation and invalid continuation. |

## Independent tabs and failure boundaries

- Two distinct Chrome pages shared one origin and browser context. A queued capture waited on the other tab's exclusive recovery lock. On clean trials, one capture advanced the manifest and the other returned the same revision. An older-tab change to valid calendar or ledger bytes during asynchronous digest work was rejected and the manifest remained byte-identical. The same result held for simulated account switch and connection epoch invalidation. Stale calendar preview, pending journal and active/held session key guards rejected writes. The second synthetic owner had no access to the first owner's records or journal through its owner-specific view.
- An explicit V4 calendar deletion preserved the parent revision and bound the deletion tombstone to the new revision. Reusing the deleted ID was rejected. V1–V3 browser round trips used native AES-GCM and PBKDF2-SHA256 (600,000 iterations). V3 preserved both manifest and lineage, and rejected tampering, metadata downgrade, foreign ownership and legacy decoding.
- Repeated two-tab contention exposed a real race. **The standalone probe reproduced two successful sibling revisions in 11 of 20 trials.** The two calls returned different revision IDs for the same parent and digest. In the diagnostic run, both tabs eventually agreed on the second revision, leaving the other acknowledged revision absent. The broader two-tab stress run passed 5 of 8 times, with two sibling-revision failures and one unexpected immediate cross-tab V6 journal state. This supports treating cross-tab storage visibility as a safety requirement at handoff between lock holders. The recovery anomaly is less characterized than the capture race. The HTML standard leaves cross-agent-cluster Web Storage interactions unspecified. [HTML Web Storage](https://html.spec.whatwg.org/multipage/webstorage.html#introduction)
- On clean runs, two V6 writers starting from the same review posted exactly one synthetic expense and rejected the stale writer. A second tab rolled back exact prior state after an injected destination failure, and finalized a fully written journal after an injected finalization failure. The pending journal blocked capture and was hidden from the other synthetic account. These were fault injections against real storage. Abrupt browser or OS termination was outside these checks.
- Real localStorage exhaustion returned Chromium's `QuotaExceededError` at initial protected journal creation. The mutation preserved the calendar, ledger, manifest and lineage, and left no pending journal. The IndexedDB quota override attempt did not produce quota exhaustion. Actual IndexedDB quota rollback remains unverified.
- The two-tab archive tests rejected an old commit after purge, preserved the other owner's partition, and closed both existing connections on a real IndexedDB version change. A separate two-tab collector test held a synthetic API response across purge and observed `archive-changed` without recreating rows.

### Reproduce the capture contention

Run the optional probe with installed Chrome and Playwright Core 1.65.1 available to Node. It creates fresh same-origin tabs, a synthetic storage namespace and a local server, then closes everything. Its exit status is nonzero when it observes a violation. Keep this stress probe separate from the deterministic Node regression suite.

```powershell
$probeTools = Join-Path ([IO.Path]::GetTempPath()) "torn-probe-tools"
npm install --prefix $probeTools --no-save --no-package-lock --ignore-scripts playwright-core@1.65.1
$env:NODE_PATH = Join-Path $probeTools "node_modules"
node docs/tests/manual/account-cross-tab.cjs 20
```

## Interface checks and correction

- Local checkout and published Pages guest routes passed at 1440 and 390 CSS pixels in Chrome. Checked navigation, Calendar Timeline duration and Week view, duration persistence after reload, training Plan template recalculation, Log search/reset and disabled sync as guest, backup gating, and settings disclosure open/closed persistence after reload. Published guest checks preceded publication of the calculator correction. [Published Guide](https://vagabond1215.github.io/TORN/)
- Local synthetic connected UI passed Home recommendations, Energy and Home Timeline, sidebar, Nice planner and STR HOLD, a distinct Landlord recommendation card, targeted Nice refresh, backup dialog and inactive recovery sections, and Unified Log opt-in. The actual coordinator invalidated the previous verified owner handle on same-player rotation using intercepted `user/basic`; no request was sent to Torn. Real player data, authenticated API permissions and connected-device behavior remain unverified.
- Corrected a standalone planner helper crash before the Theoretical pane first rendered. The helper now supplies its calculator context explicitly and the sequencer restores its prior context. The new regression calls it before rendering. Chrome rechecked both simulations and the ordinary Plan controls. Updated both affected script cache tags.

## Gates and next task

- Satisfied in this environment: native checkout and Node baseline, existing browser fixture execution, browser crypto and backup round trips, native localStorage write-ahead quota rejection, disclosure behavior and guest interface smoke tests. The isolated Log archive/collector passed the tested concurrency, purge and version-change paths.
- Open: protected account storage consistency between tabs, explicit migration-state/old-tab downgrade protection, active-session compatibility, expense writer, recovery UI dispatch and V3 backup routing. Durable Log still needs IndexedDB quota evidence, authorized own-account payload/permission validation and L3 consent, retention, lifecycle and wiring. This validation leaves both isolated writer paths disabled.
- P1.4d.5 can proceed as isolated scheduler policy and immutable review work. Before wiring a mutation, design and test an authoritative cross-tab commit boundary that can compare and advance a per-account generation, such as an IndexedDB transaction. Preserve existing journal, lineage and ledger bytes through migration and recovery. Repeat the native contention probe plus V6 interruption, old-tab drift and stale-preview cases against the candidate boundary before activation review.

## Transactional account follow-up — 2026-11-28

Fast-forwarded clean `main` to `6fb0323755981173bbd16a02fe6a4e2be63e9bf1`, which includes the isolated account store from `221957d`. Used Windows 11 Home build 26200, Node 24.14.1, Git 2.54.0.windows.1, npm 11.11.0, Chrome 158.0.8127.37 and Playwright Core 1.65.1. The probes used separate Chrome tabs at a temporary loopback origin, disposable browser contexts and synthetic account data. No live Guide wiring, real account data or API access.

| Check | Result |
| --- | --- |
| `node docs/run-regression.cjs` | 42 of 42 syntax checks and 40 of 40 Node fixtures passed with zero failures or skips at baseline and after the read fix. |
| `node docs/tests/manual/account-cross-tab.cjs 20` | Legacy reference reproduced two sibling-revision violations. 18 of 20 clean trials. |
| `node docs/tests/manual/account-transaction-tabs.cjs 20` | 20 of 20 passed before and after the fix. |
| `node docs/tests/manual/account-transaction-tabs.cjs 100` | 100 of 100 passed before and after the fix. Exactly one initialization and one competing preference edit committed per trial. Both tabs read the same winning generation. Exact-byte staleness, old-source divergence, owner partitioning, reopened reads, preference deletion markers and protected bytes were checked. |
| `node docs/tests/manual/account-transaction-tabs.cjs --lifecycle` | A controlled epoch rotation after native request success but before transaction completion aborted the write and preserved the exact prior record. Rotation at completion returned `committed` with `current: false`, and the other tab saw the commit. Upgrade closed both connections and version 1 reopening refused the upgraded database. |
| `node docs/tests/manual/account-transaction-tabs.cjs --restart` | The exact acknowledged generation survived a full clean Chrome close and relaunch with the same disposable on-disk profile. Abrupt browser or OS termination remains unverified. |
| `node docs/tests/manual/account-transaction-tabs.cjs --quota` | Chrome returned native `QuotaExceededError` under a 4 KiB DevTools quota override. The other tab read the exact prior record and a manual retry committed after the override was cleared. Real disk exhaustion was not induced. The probe waits for Chromium's prior quota calculation to expire. [Chromium quota cache](https://chromium.googlesource.com/chromium/src/+/c0811f657d5ae8c42a9fb827e7e36e7e58a16bab/content/browser/indexed_db/instance/bucket_context.h) |

The lifecycle probe initially failed because a read whose IndexedDB transaction had completed could return a verified record after its connection closed during asynchronous digest verification. Commit `65eed96f64eb6a1008468007e4b3b34a7fd0a878` checks the connection and epoch again after verification and adds the repeatable lifecycle, restart and quota probes. The lifecycle assertion failed on the original implementation and passed after the fix.

The candidate passes native contention and lifecycle acceptance for reviewed initialization and ordinary preference commits. It has no protected transition or recovery entry point. The probe verified that protected calendar edits are rejected and that calendar and ledger bytes and revisions survive preference commits. Native V4–V8 protected writes and recovery against IndexedDB, durable migration and downgrade fencing, active-session compatibility, the expense writer, recovery UI and V3 backup routing remain release gates. Preserve legacy state until those gates pass. Scheduler decision adapter work remains independent.

## Transactional rehabilitation planning acceptance

On 2026-11-28, clean main fast-forwarded to `5e420d570f17e4c0dd15b309605be9497657b7ec`. This tested the policy from `7c2881b`, IndexedDB writer from `ed57abe` and Nice changes from `47f8617`. Windows Chrome 158.0.8127.37 and Playwright Core 1.65.1 used isolated synthetic accounts on loopback. Node v24.14.1 passed all 43 syntax checks and 41 isolated fixtures via `node docs/run-regression.cjs`. All five existing browser HTML fixtures passed.

- **Reservation and cancellation.** The supplied `node docs/tests/manual/account-transaction-tabs.cjs --rehab` stage passed. The expanded stage starts two distinct reservations from the same reviewed generation. Exactly one commits, the other returns stale, and both tabs read the same record. The probe checks exact calendar and lineage bytes for the winning reservation and its cancellation, preserves a nonempty historical expense ledger, checks the tombstone and rejects reuse of the cancelled ID.
- **Interruption.** After native put request success and before transaction completion, the fixture separately introduced a training hold, rotated the synthetic epoch and closed the writer connection. Each cancellation rejected and the other tab read the entire prior record byte-for-byte. These are controlled interruptions of real IndexedDB transactions.
- **Storage pressure.** With an active one-byte DevTools origin quota and 31 seconds for the prior allowance to expire, Chrome raised native `QuotaExceededError`. The other tab verified the prior record after rejection. Removing the ceiling allowed a fresh explicit attempt. Physical disk exhaustion and abrupt OS termination remain untested.
- **Nice planner.** A connected local Guide with intercepted synthetic responses advanced Happiness from 4,400 to 4,405 on its actual one-second UI timer. The header and table updated, sidebar gym/train rows agreed with the corresponding table rows, STR retained HOLD at zero trains, and the focused precision input survived. The tick issued zero API requests. A controlled over-cap quarter-hour transition suppressed the route and sidebar advice pending refresh. The native solver fixtures also passed the matched-pattern swap cases.
- **Durable Log.** Under a one-byte DevTools quota, a native 100-row synthetic archive commit rejected with `QuotaExceededError`. The second tab saw zero rows and the exact prior sync state. Clearing the ceiling allowed the same 100-row page to commit, visible to both tabs. A separate late collector response after cross-tab purge returned `archive-changed`. An exploratory zero-byte override with a single row did not trigger a failure. Authorized own-account payload and permission checks remain open.

The additional cases required probe changes only. Production activation remains disabled. Other protected transitions, migration and downgrade fencing, recovery routing, and authenticated API acceptance retain their separate gates.
