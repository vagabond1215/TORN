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


## Activity report previews

The Home page's existing nine **Activity and detailed reports** links are now explicit, allowlisted report-launch buttons. Clicking one opens a native in-page dialog with an iframe pointing to the matching Torn Report page, alongside **Open in new tab** and **Pop out window** controls. The external page is loaded **only on user interaction**, with a no-referrer policy, an iframe sandbox, and the iframe source removed when the dialog closes. It neither loads any report automatically nor sends the Torn Guide API key or cached Torn account data to the external provider.

**Compatibility constraint:** Third-party sites control whether iframe embedding is permitted. Torn Report might send X-Frame-Options/CSP frame-ancestor restrictions, and some logged-in pages fail under third-party-cookie restrictions. An iframe refusing to load cannot be reliably detected from the guide's separate origin. For that reason, the dialog always displays the fallback link and pop-out option; it does not try to bypass the restriction, scrape the page, or proxy the authenticated content. Live frame compatibility was not verified.


### Interface preferences and elapsed sync counter

The tornGuidePreferences module stores theme, time-zone, external-link and contextual Quick Access preferences separately from the opt-in Torn API credential. The top-bar sync age updates locally once per second from tornGuideApi.state.updated. It does not force any API selections or additional polling. The exact refresh timestamp stays in the refresh icon tooltip using the preferred display time zone. The redundant Home identity and Last refreshed summary were removed.


## November 24, 2026: live bar projection and Activity details

### Passive bar regeneration between API refreshes

Home now advances Energy, Nerve, Happy and Life locally from the last user/bars snapshot. The source fields are current, maximum, increment, interval, tick_time, and full_time. The guide records the bar selection fetch timestamp and projects the next +increment tick at its reported phase. The bar value, percentage and next-tick countdown update once per second without a Torn API request.

Default fallback intervals are +5 Energy every 10 minutes (150-cap Donator/Subscriber) or 15 minutes (100-cap standard), +1 Nerve every five minutes, +5 Happy every 15 minutes, and the API-provided Life interval/increment. When the API provides differing intervals or increments, those values take precedence. If a manually shared bar snapshot lacks tick_time, a UTC-aligned approximation is marked as estimated in the tooltip. Refreshing the source supersedes the local projection.

Passive projections cannot predict spending Energy or Nerve, consuming items, unexpected Happy changes, or special perks after the latest API pull. Over-cap Happy is left at its reported value until another snapshot instead of assuming that its quarter-hour reset is always active. The redundant static snapshot disclaimer was removed.

### Corrected personalstats API error

The old personalstats request lacked a required category. The endpoint now maps to user/personalstats?cat=popular, excluded from generic user multi-selection so the category parameter is retained. Home does not automatically request it. On cache restoration, legacy "Incorrect category" errors for personalstats are cleared while all unrelated failures remain visible.

### Activity API budget and field mapping

Bank: Home reuses cached user/money under its existing 15-minute TTL and displays city_bank amount, profit and until maturity without a separate bank request.

Virus, Travel and Racing: Home's explicit Update activity button checks stale selections only: user/virus (15-minute TTL), user/travel (15-minute TTL), user/racingrecords (6-hour TTL), user/races (30-minute TTL). The coordinator batches selections when possible or falls back safely. This does not extend the routine Home refresh.

Virus: the user/virus v2 response contains an item name and an absolute Unix until timestamp, which is now recognized by the TCT countdown panel.

Travel: flight countdowns are anchored to a known arrival timestamp or remaining time at the travel selection's fetch timestamp when supplied.

Racing: user/racingrecords gives track best-lap records, not the latest finishing position. User/races provides race history. A position is shown only when the most recent race includes a result with the current player's driver_id.

Bank maturity and flight arrival appear in the TCT dropdown using cached values with no additional request. Home displays Money and Activity last-fetch dates to indicate freshness, and failures in one selection do not erase independent sections.

### Source and access limitations

Connected browser tab context exposed only rendered Torn website/guide data, not the underlying last authenticated HTTP response bodies. No API key or private data was sent to a proxy or committed. The updated guide presents live cached selections after the user explicitly loads them; absence of a selection is labeled Not loaded.

Schema references:
- https://neon0404.github.io/torn-client/types/UserBar.html
- https://neon0404.github.io/torn-client/types/UserMoneyResponse.html
- https://neon0404.github.io/torn-client/types/UserVirus.html
- https://neon0404.github.io/torn-client/types/UserRacingRecordsResponse.html
- https://neon0404.github.io/torn-client/types/UserRacesResponse.html
- https://www.torn.com/swagger.php


## November 23, 2026: dedicated Net Worth response

Home now requests the API v2 **user/networth** selection under its own 60-minute TTL. Torn also caches net-worth calculations globally for approximately one hour, so re-requesting this on every Home view is unnecessary. The coordinator batches the selection with other stale Home selections when supported, otherwise handles it independently with the existing failure-backoff logic. No API key is exposed in the DOM or commit.

Unlike money.daily_networth (which is not a categorical breakdown), the v2 networth response supplies an authoritative server-calculated **total** and grouped breakdown:

- Money: wallet, city_bank, cayman_bank, vault, piggy_bank, bookie, pending, loans, unpaid_fees.
- Assets: stock_market, property, company.
- Items: inventory, display_case, bazaar, item_market, auction_house, enlisted_cars, trades.
- Points: monetary value reported by Torn, not points quantity.

The Home Net Worth panel displays Torn's **reported total** rather than reconstructing it from components. Each group has an expandable category breakdown and a clearly identified category subtotal. Loans and unpaid fees are displayed as negative contributions. Zero-valued categories are omitted to avoid visual clutter; an entirely empty group shows No recorded value. Missing selections or API errors are labeled unavailable rather than using an estimate from bank, stocks or inventories.

Source of truth:
- https://www.torn.com/swagger.php
- https://neon0404.github.io/torn-client/types/UserNetworthResponse.html
- https://tornapi.tornplayground.eu/user/networth

Tests use synthetic API responses, including a $9,999,999,999,999 total, nested assets/money/items data, debts, points value, hourly TTL, and no extra requests while re-rendering cached Home.


## Docked character overview: cached timers and property upkeep (November 24, 2026)

The guide now has a right-side panel below Quick Access on desktop. It is hidden until API-connected and while viewing Account/API. It displays cached data only:

- Countdown rows: virus, ranked war, flight arrival, investment maturity, education, organized crime, and drug/booster/medical cooldowns. Local countdown ticks share the existing one-second guide clock and do not request data.
- Net worth: the original hourly user/networth category breakdown, with only the calculated date/time in its footer. The comma following the four-digit year is removed.
- Current property: the user/property response has nested property.property.name and an upkeep object with numeric property and staff amounts. The guide sums the two for current daily upkeep, and separately lists both components. Missing cost values are not invented.
- Battle, working and job stats: reuse existing user/battlestats, user/workstats and user/job cached selections.

The rail's Update button calls the manual railTimers selection set only when clicked: education, virus, cooldowns, organizedcrime, factionRankedWars, travel and money. Existing stale-data TTL, combined user selections and failure backoff apply. Racing, net worth, stocks and inventory are not refreshed by this button. Repeated clicks inside the TTL make zero requests.

The Home Activity panel still offers its more detailed bank and racing information on manual refresh. No API keys or user values are written into the repository.

Property schema: https://neon0404.github.io/torn-client/types/UserPropertyBasicDetails.html


## Inventory details and manual Weav3r searches

Inventory uses the cached Torn item catalog (15-minute TTL) for descriptions, effects and market values. Expanding an item makes no request. Item matching prefers a matching catalog ID and name, then a unique exact name. Unresolved IDs disable marketplace controls.

**Query Buyers** sends one anonymous GET to Weav3r’s documented trader endpoint for the selected item. It sends only the item ID and result controls. Public pricelist quotes are cached locally with the check time and shown with unknown quantity. The manual marketplace link opens the item on Weav3r, where anonymous buy orders can be checked independently. See [the Weav3r audit](WEAV3R_INTEGRATION.md) for schemas, limits, and validation.


## On-demand individual equipment details

Inventory Details displays catalog metadata (weapon category, stealth, magazine, rate of fire, armor coverage and circulation) when supplied. Manual Load equipment details reads `user/equipment` for equipped gear, `torn/{uid}/itemdetails` for individual gear, and `user/itemmods` when attachment data is missing. UID matches are exact and unsafe numeric IDs are rejected. The itemdetails decoder accepts both documented single-object and array responses (array-only from January 2027). Results are session-local, account-epoch scoped, cached for 15 minutes, and concurrent identical requests are deduplicated. No extra Home requests or third-party key sharing. Mod IDs in the catalog indicate compatibility, not installed mods or available slots. Source: https://www.torn.com/swagger/openapi.json . Live authenticated testing pending.

### Opt-in idle personal log collection
Official v2 `user/log?limit=100` is standalone, requires full access or explicitly permitted custom log access, and uses `_metadata.nanostamp` as a string cursor without `to` (https://www.torn.com/swagger/openapi.json). The Log page enables a session-only worker across Guide routes while the tab is visible. All coordinator requests count active work and quiet time; foreground requests interrupt idle fetches, 15 seconds of quiet and at least 60 seconds between idle attempts, including failed/verification requests. Browser Web Locks and a per-player nonsecret last-attempt timestamp coordinate cooperating tabs; unsupported browsers fail closed. Restored credentials must reverify player ID before logs. Current key/epoch checked after each request; no pagination URL followed. Stops for permission/invalid key or daily read limit, backs off on transient/rate errors. Historical cursor pages alternate with newest catchup (five-minute refresh); 2,000 newest entries retained only in memory, separate from companion to avoid false deduplication. Only record ID, time, title/category, selected simple data fields; no raw params or credentials. Clear/pause controls; no backup/ledger promotion. External clients' usage cannot be observed; Torn rate limits remain authoritative. Native browser/Web Locks and authenticated endpoint tests pending.
