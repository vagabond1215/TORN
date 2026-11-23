# API Efficiency, External Sources, and Torn Companion

**Project boundary:** Only `vagabond1215/TORN/docs/`. This is a static site hosted from GitHub Pages. No server or proxy is installed.

## Request model

The guide no longer calls every Torn API selection at login, on every page load, or at each quarter-hour. Logging in verifies `user/basic` once. On navigation it only asks for **stale selections associated with that page**. The header Refresh button forces only the active page's selections, not every page.

| Route | On-demand selections | Typical TTL |
| --- | --- | --- |
| Home | Bars, cooldowns, money, battle stats, gym membership, job, property, education, merits, merit catalog | 2 min bars/cooldowns; 15 min money/stats; 30 min gym membership; 6-12 h career/education/merits; 30 days merit catalog |
| Stats | Bars, cooldowns, battle stats, gym membership, perks, global gym catalog | 2-60 min for character information; **90 days** for the immutable gym catalog |
| Crime | Bars only | 2 min |
| Checklist | Bars, merits, merit catalog, job | 2 min bars; 6 h merits/job; 30 days catalog |
| Money | Money, stocks, stock catalog | 15 min money; 1 h stock holdings; 7 days stock catalog |
| Inventory | **No requests on entry.** Only categories explicitly opened (Candy, Drug, Alcohol, Tool, Enhancer, Booster, Energy Drink, Medical). | 15 min per requested category |
| Racing, Faction, War, Attacking, Tools | No automatic Torn API calls | n/a |

When 2+ user selections are due, try a **single v2** `/user?selections=...` request. The application splits the response back into existing per-selection data shapes. If Torn rejects the composite or changes its shape, retry individual selections and avoid composite requests for the rest of that session.

Request concurrency is limited to 3. Failed selections are not retried automatically for 10 minutes. A load in progress is reused, and a change to a different route queues only one follow-up. The 15-minute timer at :00, :15, :30, :45 calls the **same freshness checks**; it does not force data reloads. Browser resume also checks freshness. Manual refresh bypasses the TTL for the active page only. Data and last-fetch timestamps persist between visits only when **Stay logged in** is enabled.

### Gym rules

The **player's selected gym** is a small, sometimes-changing selection and receives a 30-minute TTL. The **gym effectiveness catalog** is separate, changes very rarely, and has a 90-day TTL. Changing your active gym never automatically re-downloads the full catalog. A manual Stats refresh can force the catalog if a new one is suspected.

### What the current site can and cannot know

Normal webpages cannot inspect arbitrary other open tabs from a different origin due to the browser same-origin policy. An unfocused Torn tab is **not** permission to scrape it. Torn's current rules allow extracting data only from the manually opened page you are **actively viewing**, and prohibit additional non-API page requests, unfocused scraping, and bypassing CAPTCHAs.

The optional userscript follows these rules:

1. Install the publicly reviewable `torn-companion.user.js` in Tampermonkey (Chrome/Firefox extension).
2. Manually open Torn and actively view your character's sidebar.
3. Click the script's **Share bars with Torn Guide** button on that **focused Torn page**.
4. Switch to the guide within 90 seconds. Tampermonkey transfers only your player ID, capture time, and the four numeric status bar values (Energy, Nerve, Happy, Life) using `GM_setValue` and `GM_addValueChangeListener` in the same installed userscript.
5. The guide accepts the snapshot **only if the player ID matches the connected account and the timestamp is recent**. Fresh manually captured bars avoid redundant `user/bars` API calls. Other fields still use the official API when needed.

This userscript does **not** observe page changes, read other Torn pages, click gameplay controls, make requests, capture messages, export cookies/passwords/API keys, or run unattended in a Torn tab. Its only effect outside Torn is supplying its user-approved, short-lived status snapshot to the guide.

Installation: [Torn Guide companion userscript](https://vagabond1215.github.io/TORN/torn-companion.user.js). Source: `docs/torn-companion.user.js`. The guide's client-side receiver is `docs/local-bridge.js`.

### Trusted outside services

External services should supply noncritical, historical or derived metrics *only after their data access is independently authorized*. Torn API is the authority for live account resources. TornStats documents an API at `https://www.tornstats.com/api`, but its endpoints embed a key in the URL, and some endpoints have side effects or update the stored key. The guide therefore **does not automatically transmit a Torn Full Access key to TornStats** or assert that cross-origin fetching is supported. Torn Report is currently integrated as links to its authenticated reporting pages, not as a backend data feed.

A future live third-party adapter needs a provider-scoped separate credential, verified browser CORS, explicit enable/disable controls, an endpoint-specific TTL, and a narrow schema. In the meantime the guide displays their report links and labels these services as **not connected**.

## Privacy & testing

- No API keys are committed to GitHub or sent to the userscript.
- No Torn game requests are performed by the userscript.
- Local cache can be cleared by disabling Stay logged in or disconnecting.
- Browser-local cached balances can be stale; per-field timestamps govern requests.
- Tested with mocked successful combined selections, combined-request fallback, cache restores, page transitions, and per-category inventory fetches.
- Live authenticated Torn API composite behavior, user-script DOM extraction on the live Torn UI, and actual GitHub Pages deployment still require user-side testing.

Sources:

- [Torn API](https://www.torn.com/api.html) and [Torn API v2 Swagger](https://www.torn.com/swagger.php)
- [Torn staff clarification of scripting rules](https://www.torn.com/forums.php?t=16534470)
- [Tampermonkey documentation](https://www.tampermonkey.net/documentation.php)
- [TornStats API docs](https://www.tornstats.com/api)
