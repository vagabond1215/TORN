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
