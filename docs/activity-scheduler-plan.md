# Shared activity scheduler: implementation plan

Scope: `vagabond1215/TORN`, `docs/` only. Energy remains the current-action and confirmation interface. Calendar is a separate projection and commitment editor. All timestamps stored as UTC milliseconds and displayed as TCT. Read-only Torn API, no gameplay automation.

## 1. Core contract
- Scheduler owns future fixed commitments, blocking windows, rehab proposals, and optional cash reservations. Training sequencer owns stat optimization. Energy session owns immutable confirmed actions and execution detection.
- Events have stable IDs, kind, start/end, source, blocking flag and detail. Distinguish API data, calculated deadlines, manual entries and proposals. Never equate a scheduled time with a confirmed action.
- Use ranked war API start and status, with manual TCT entries for events whose API source is absent. No guessed war end. Unknown/stale data remains explicit.
- Recompute on refresh, changed commitment, confirmed action and crossed deadline. Do not perform game actions or start trips.

## 2. War
- Training cutoff = war start - (4 × configured Xanax cooldown + clearance buffer). Defaults 8h and 120min; migrate historical default 2min.
- Pass the earliest blocking deadline to Optimal Budget. Cap final training action and drug clearance at cutoff; retain ordinary and premium consumable restrictions. Partial cycle is bounded by remaining time and budget.
- If an active session conflicts, stop presenting unsafe future actions; refresh/reconcile first, archive confirmed prefix, release unconfirmed suffix, replan from live state. Use conservative full-cycle cost reservation when actual partial cash spend cannot be established. Never infer consumption or refund.
- During stacking, use live energy, cooldown, verified stock and addiction restrictions; do not recommend another dose that cannot clear by the buffer. Active war reserves gym energy until a confirmed end. Replan after return to normal.
- Late announcement or overdose: flag infeasibility and preserve available energy; do not promise 1,000 E.

## 3. Addiction / rehab
- Visible addiction-related battle-stat penalty is not exact addiction points. Unknown/stale icons are not zero. Defaults preferred 2%, recommended 3%, restriction 5%, pre-war target 0%; editable.
- Retain education and OD restrictions. Travel requires verified eligibility; conservative standard travel by default, user may select Airstrip, WLT, business class. Use 3% flight allowance plus configurable stop/return time. $250k per rehab session estimate, actual sessions and discounts unknown; standard fare conservatively reserve $54k round trip.
- Suggest a trip fitting a gap between planned actions or current cooldown before next hard deadline. A critical case may require pausing training. No automatic acceptance; user creates a blocking rehab reservation. After return, refresh actual bars/cooldowns/icons and replan. Rehab does not clear drug cooldown.
- Optional budget mode reserves configured war and rehab cash; separate budgets default. Actual war/rehab spending ledger and automatic rehab confirmation are subsequent extensions.

## 4. Calendar UI
- Home tile: Agenda, Timeline, Week. Full Calendar page: Agenda, Timeline, Week, Month; manual event creation/removal, date/time in TCT, explicit blocking checkbox. Keep Energy Steps.
- Initial automatic sources: planned training actions, ranked war milestones, existing TCT timer entries (education, travel, organized crime, bank, daily resets/cooldowns). Manual chain, racing, events, commitments supported immediately. No guessed event time.
- Settings popup: travel mode, thresholds, rehab allowance/session estimate, optional budget reserves. Gear and refresh standardized. 
- Future automatic sources: verified faction chain/racing schedule, seasonal events, travel completion, rehab log confirmation, war attacks and spend ledger. Do not treat calendar suggestions as confirmed.

## 5. Validation
- Synthetic fixed-clock tests: 34h cutoff; deadline/clearance boundary; late start, drug restrictions and no stock; confirmed prefix preservation; war end; rehab fits/doesn't fit, active war blocks trip, budget reserve and unknown addiction; manual blocking events; render all views; existing full-cycle charts unchanged.
- Verify source syntax, run controlled simulator tests, verify deployed asset versions. Live authenticated game/browser validation remains manual.
- Source references: https://wiki.torn.com/wiki/Switzerland ; https://wiki.torn.com/wiki/Drug ; https://wiki.torn.com/wiki/Cooldown ; https://wiki.torn.com/wiki/Traveling .

## Follow-up: live Energy and activity sources
1. Live stack normalization: HJ/99k retain tiers and skip held doses, bounded gym spending, explicit zero/full/live standalone starts. Optimal and Optimal Budget use a common live baseline. Preserve custom templates.
2. Rehab confirmation: fresh count increase plus returned status; snapshot prior to reservation; record fee delta exactly once if present; missing permission or shape leaves reservation unconfirmed.
3. Add current faction chain, own race schedule, official event calendar and personal time slot. Never manufacture future chain schedules or race end times.
4. Actual expense ledger: rehab counter delta and manual war/rehab cash entries; deduct only in shared-budget mode.
5. Active war: opt-in recent outgoing ranked-war attack read, explicit truncated-history label; no automated attacks.
6. Test live API shapes, permissions, current-energy combinations, return from rehab, and mobile/browser interactions. Source: https://www.torn.com/swagger.php and https://wiki.torn.com/wiki/Calendar.
