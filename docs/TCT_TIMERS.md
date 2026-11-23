# Torn City Time and Countdown Panel

This is part of \`vagabond1215/TORN/docs/\` only.

## Top bar

The top bar shows **TCT (Torn City Time, UTC)** as HH:MM:SS. It reads the browser's UTC system clock, so a visibly incorrect computer clock will also make the displayed TCT incorrect. The TCT clock does **not** poll any Torn endpoint.

Click TCT to open a compact countdown panel. It shows local countdowns to:

| Event | Torn time | Precision |
| --- | --- | --- |
| Daily limits, points refill and job-point spending limits | 00:00 TCT daily | Scheduled reset |
| Virus coding processing run | Approximately 03:25 TCT daily | Approximate processing run; distinct from a specific virus's completion timestamp |
| Natural addiction decay | Approximately 03:31 TCT daily | Approximate processing run, not a prediction of addiction points removed |
| Job points, work-stat daily gains and pay | Approximately 18:00 TCT daily | Approximate processing window; actual company calculations can finish later |
| Company star recalculation | Sunday at about 18:00 TCT | Approximate weekly review |
| Personal drug / medical / booster cooldowns | Based on cached \`user/cooldowns\` | Countdown from the fetched snapshot; not fresh status until explicitly updated |
| Education course | \`user/education\` when a supported completion field exists | No invented timestamp if API omits the value |
| Active virus coding | \`user/virus\` when a supported completion field exists | No invented timestamp if API omits the value |
| Organized crime | \`user/organizedcrime\`, when its completion/start is exposed | No invented value |
| Ranked war | \`faction/rankedwars\` when scheduled start/end is exposed | Manual override available if no reliable result |

Scheduled daily and weekly events are informational, not individually retrieved from Torn.

## API budget and permissions

**Opening the countdown dropdown makes zero API requests.** Click **Load personal & ranked-war timers** to request only stale timer selections, using the existing page-scoped coordinator and caching:

- \`user/education\` (6-hour TTL)
- \`user/virus\` (15-minute TTL)
- \`user/cooldowns\` (2-minute TTL)
- \`user/organizedcrime\` (10-minute TTL)
- \`faction/rankedwars\` (15-minute TTL)

The four user selections are combined in one request when the current Torn API supports multiselection, and ranked-war information is a separate faction request. On unsupported combined requests, the coordinator falls back to separate selections. Missing, unauthorized or unsuccessful API selections are never replaced with imaginary countdown times.

The dropdown has a **Manual RW start (TCT / UTC)** field. The value is interpreted as UTC regardless of the viewer's local time zone, saved only in this browser (separate storage key per Torn player ID), and labeled as manual rather than API-confirmed. Clearing the field clears the saved manual date. No timer is remotely scheduled, and the guide never enrolls in a war or starts a game action.

Browser timers update the visible countdown locally every second. No background Torn scraping or added API polling is performed to animate the clock. The usual page-scoped 15-minute freshness check is not extended to these timer selections merely because TCT is displayed.

## References

- [Torn API v2 Swagger](https://www.torn.com/swagger.php)
- [Torn Company processing](https://wiki.torn.com/wiki/Company)
- [Torn community schedule of TCT resets](https://www.torn.com/forums.php?p=threads&t=16204780)

Timing and field compatibility checked against available documentation November 23, 2026; direct live authenticated API validation is still required.
