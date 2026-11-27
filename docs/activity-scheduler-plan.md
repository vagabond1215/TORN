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

## Phase 1 shared live context
Stats → Plan → Live now delegates to the same training recommendation entrypoint as Home, Calendar and Restock. Theoretical remains separate. New plans require current projected bars and known paid-program cooldowns; today's unknown refill is conservatively excluded. See next-segment-upgrade-plan.md for pending source normalization and numerical/browser/API gates.

## Unified timeline presentation (2026-11-26)
Replaces category lanes with one shared seven-day TCT scale on Home and Calendar. Minimum canvas 240 px/day, horizontal scrolling on narrow screens, existing theme colors, up to three internal duration bands based on actual overlap (not category), narrow/overflow spans represented by pins, deterministic 48 px bucket clusters with alternating annotation sides and exact time anchors. No minimum-duration inflation; every eligible event is represented as a span or marker/cluster with full details via persistent tap/click inspector and hover/focus tooltip preview. Agenda remains accessible below for manual removal; other views unchanged. Display-only war preparation derives from the existing reservation; unknown war/race ends remain markers; stale/recovered warnings retained. No new network requests, persisted settings or gameplay actions.
Validation: affected JS compiled; existing activity-scheduler and new unified-timeline CJS fixture bodies passed the adapted JS harness (not native Node CLI). Direct repository checkout unavailable (DNS); actual desktop/mobile, tooltip/keyboard and light/dark browser testing still required. Next: browser validation and refine cluster density/label fit; optional time zoom/date navigation separately without changing scheduler semantics.

### Timeline flags and drug cooldown intervals
Instantaneous events now use transparent underlined flags with exact left-edge posts; near the right edge the post moves to the right. Compact flags reserve space before growing labels; clusters retain separate anchors and short/overflow durations use a range identifier. Only duration bars are filled. Drug actions remain instantaneous. Timeline-only projected drug intervals use the locked session's same timing, the simulator's post-action cooldown, or the war planner's configured dose interval. A recent API cooldown snapshot adds a remaining interval from the current view time (not an inferred dose time). No new API calls, persistence changes, budget effects, or training-blocking rules. Cooldown intervals are estimates/observations, not confirmed consumption. Tested geometry, edge/collision cases, forecast vs observed intervals, and existing scheduler/live stack fixtures in adapted JS harness; native browser and Node tests remain open.

Short cooldown follow-up: cooldown ranges use an 8 px minimum interactive width at the existing 10 px/hour scale; below that, a compact range flag preserves the exact interval rather than exaggerating its length.

### Standalone Home timeline
Placed directly below recommendation toggles, outside the masonry grid, within the bounded center workspace. Always visible independently of the Calendar tile. Home Calendar offers Agenda and Week only; full Calendar retains all four views. Home panels share a single schedule snapshot. Standalone timeline omits duplicate Agenda. No persisted setting migration; an existing Timeline preference falls back to Agenda on Home only. Native browser validation pending.

### Week daily item values
Package buttons on each Week tile support hover/focus and persistent tap details, showing forecast item quantities and full replacement value (owned items included), not cash purchases or confirmed consumption. Prices use shared fresh item/points market logic; unknown prices or unspecified locked-session candy remain unknown, with known subtotal disclosed. Forecast candy breakdown is transient simulator metadata, not persisted session schema. War doses are valued as planned Xanax; cooldowns, manual spans and generic events do not manufacture item use. UTC day boundaries; sum all scheduled entries, not just eight visible labels. No added API calls or storage migration. Native browser/Node verification remains open.

### Timeline time-window modes (2026-11-26)
Home standalone and full Calendar Timeline now share Today (UTC midnight to next midnight), 2 Days (today + tomorrow), and 24hrs (rolling current UTC minute to +24h). Default Today; selection is session-local and account-scoped, with no persisted schema migration. Minimum canvas 720 px/day, 3-hour ticks, existing horizontal scroll. A timestamped schedule snapshot is held separately from viewport time. The existing UI timer checks the minute; fixed-day mode moves only NOW, rebuilds on midnight, rolling mode rebuilds only timeline content once per minute. Hidden tabs skip updates and catch up on resume. Current cooldown expiry and future action timestamps remain anchored to source data; no API calls, schedule recomputation or optimizer invocation from the minute tick. Preserve scroll and selected event where the exact event/cluster survives; reset scroll on mode switch/day rollover. Already-elapsed projections are not confirmed history; unavailable earlier events are not invented. Native browser performance, responsive and interaction validation remain open.

### Compact Timeline tile
Home Timeline uses an account-scoped recommendation toggle and collapsible tile with centered range controls, activity settings and manual Calendar refresh. Existing accounts receive a one-time enabled/open migration via tracked recommendation records. Full Calendar retains Timeline mode controls. Removed duplicate API drug/booster/medical timer flags and war-clear/status flags from the visualization only; Xanax actions remain. Cooldowns always use true-width duration bands (an extra fourth band if necessary). Removed range/snapshot heading, legend and persistent inspector; click/tap opens a viewport-clamped details popup (outside pointer, Escape, scrolling or same trigger). Week package behavior unchanged. Minute redraw preserves an open popup when its event survives. No added API polling. Native browser validation pending.

### Independent duration and Scroll controls
Replaces Today/2 Days/24hrs mode with 12h, 24h, 36h and 48h plus a separate Scroll toggle, default 24h/off. When on, NOW is the left edge and the timestamped viewport advances each minute, resetting internal horizontal scroll to the left; event times and cooldown expiries do not change. Off, fixed 24/36/48-hour ranges anchor to TCT midnight and advance only at midnight; NOW moves across them each minute. Fixed 12h anchors to the current TCT half-day (midnight/noon), preventing NOW from leaving the range in the afternoon. Green active Scroll accent, muted inactive, same account-scoped session preference across Home/full Calendar, controls wrap on narrow screens. Existing local tick and schedule snapshots only, no additional API calls or optimizer invocation. Native browser interaction/performance validation remains open.
