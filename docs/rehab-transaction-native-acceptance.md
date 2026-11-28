# Native acceptance: isolated V6-style account completion

Scope: vagabond1215/TORN main, docs/ only. Implementation 9aefaff. Baseline 96e7fbf has accepted V7 planning, Nice and Log quota checks. Do not repeat unchanged native acceptance unnecessarily except the full regression suite.

## Codex work order

Read AGENTS.md, development-handoff.md, account-transaction-boundary-plan.md and this file. Execute the full native regression suite. Extend the existing manual account-transaction-tabs.cjs with a separate --rehab-completion stage, without changing existing accepted test assertions. Load account-rehab-transition.js and account-rehab-transaction.js in the synthetic pages. Use two actual independent tabs, real IndexedDB and crypto, and a disposable profile. Seed a reviewed tracked legacy source with a pending blocking rehab reservation and its valid pre-start counter baseline, nonempty ledger with a manual- historical expense older than 90 days, unrelated preference, manifest and calendar lineage. Use synthetic account data only; no actual Torn requests. Initialize both from the same review.

## Cases

- Known cost: one explicit reviewed completion commits. Verify exact completed event, one appended rehab-ID expense, original historic expense bytes and value retained, immediate descendant revisions for calendar and ledger, unchanged unrelated revisions, lineage verification, exactly one generation advance.
- Competing independent tabs review the same completion. Only one commits, the other stale; both read the same full record. Replay with current snapshot gives review and no charge. Do not automatically retry stale actions.
- Unknown cost: explicit null cost, completion and calendar lineage advance; exact raw ledger value and ledger revision unchanged.
- Refusal: altered reviewed cost, foreign observation, stale profile/stats, expired reservation, missing/ambiguous counter evidence, existing evidence ID, 500-row ledger, held/active training, pending journal, stale context. Verify no state change. Controlled tests may be used for evidence policy; actual CAS must use native IDB.
- Interruption after put success before transaction completion: rotate epoch, change observation, introduce hold, close connection independently. Verify exact prior record from second tab. Test native quota override and manual fresh retry. Test completed/old epoch distinction and clean browser restart persistence. Distinguish clean restart from abrupt termination and browser quota override from actual disk exhaustion.
- Preserve existing V7, preference and Log probes; no production activation or automatic expense posting.

Record actual commands, native results, test commit, limitations and verified fixes in native-validation-2026-11-27.md and relevant handoff/plan. Commit and push within docs/, without force. No work on unrelated repositories. ChatGPT owns independent V4/V5 calendar transaction and migration design; avoid overlapping changes beyond verified defects.

The existing counter evidence is an inference, not a verified individual API transaction. This acceptance does not grant production activation or prove real account API permissions.
