# Beginner Roadmap, Jobs, and Tools (November 2026)

**Repository boundary:** this change affects only `vagabond1215/TORN/docs/` and does not modify faction-ledger or travel-assistant projects.

## Sources and editorial decisions

The authenticated faction forum thread **New Player Guide** (faction forum, thread 16565029, read November 23 2026) was examined directly in the user's open Torn tab. The most useful themes were retained and paraphrased, not copied verbatim:

- Keep training Energy and Nerve active, protect cash and avoid unnecessary retaliation; use faction support and equipment.
- Start an education course and a job immediately, but evaluate company work-stat training and beneficial specials before locking into an NPC career.
- Consider **The Affronted** interviewer honor early.
- Rent a practical Happy-improving property, level to 15, buy the stock ticker, establish safe travel income, and plan PI with airstrip/pilot and eventual suitcase.
- Build income to pay for training rather than paying for unnecessary equipment or vanity purchases.
- Prioritize education and bank merits over time; plan the permanent Principal/Brain Surgeon/Federal Judge city-career perks.
- Select a gameplay direction (trade, mugging, business, war, reviving, crime, racing or training) instead of pursuing every expensive strategy simultaneously.
- Include a daily routine and conditional war, travel, happy-jump and training practices.

The faction guide presented both early NPC-job progression and a later revision encouraging player-company working-stat training first. The new UI treats those as **conditional alternatives**, not contradictory universal commands. A low-wage company with consistent daily training and relevant stars can be preferable to an NPC career; city jobs are faster once working stats meet promotion requirements. Rent/property/bank/stock choices should be based on current cost, safety and account income, not fixed market assumptions.

## Combined checklist

`docs/roadmap.js` provides five sequenced core stages:

1. The first session
2. First days
3. Reach level 15
4. Compound account upgrades
5. Establish a sustainable midgame

Gameplay styles: Balanced (core only), Training, Trade, Mug, Business, War, Revive, Crime, and Racing. The user can enable several styles. Each adds its own optional milestones without changing core tasks.

Important: **existing completion keys are retained** (`quickstart:<id>` under each profile). The daily task keys also remain `task:<name>`. Adding jobs, styles or new tasks does not remove prior work.

Some milestones are marked **Verified by API** only where the existing cached API can confirm them, such as level 15, ongoing education, improved property/Private Island, bank deposits, stock-ticker access, and previously supported merit milestones. No new requests are required solely for these checks. Permanent job passives are not automatically marked complete without a reliable data source; they remain manually checkable.

## Jobs

`docs/job-guide.js` adds a separate Jobs page. On entering it, the API coordinator requests only `user/job`, `user/workstats`, and `user/perks` when stale. Browsing the catalog makes **no additional API calls**.

There are six city careers: Army, Grocer, Casino, Education, Medical and Law.

- **Education / Principal**: permanent 10% future course-time reduction; top position requires roughly 1,500 MAN / 5,000 INT / 1,500 END.
- **Medical / Brain Surgeon**: access to Energy-cost reviving; top position 2,600 MAN / 10,000 INT / 4,000 END.
- **Law / Federal Judge**: current +5% Crime Experience and Crime Skill gain; top position 6,000 MAN / 9,000 INT / 15,000 END.
- The Affronted honors pathway is highlighted before committing to careers.

`docs/company-catalog.js` contains **39 player-owned company types**, with **195 star specials** and their star threshold, job-point cost (or passive), and effect, transcribed from the official company list as of November 23, 2026. Playstyle tags are independent editorial labels. Featured examples:

| Playstyle | Example companies | What matters |
| --- | --- | --- |
| Early happy-jump support | Adult Novelties | 3-star eDVD for 20 JP, 10-star double DVD Happy |
| Trading | Toy Shop, Flower Shop, Lingerie Store | Extra travel items, air travel, maintenance reductions |
| Mug protection | Clothing Store | 7-star +75% mug protection |
| Defense gym gains | Ladies Strip Club | 7-star +10% Defense gym gains |
| Dexterity gym gains | Gents Strip Club | 7-star +10% Dexterity gym gains |
| General raw training | Fitness Center | 3-star less Happy loss, 10-star +3% gym gains |
| Faster gym unlocks | Music Store | Gym experience, not raw battle stat gains |
| Revivers / Energy | Farm | 10-star 7 Energy per job point |
| Racing | Car Dealership, Mechanic Shop | Racing points and upgrade savings |
| Crime | Law Firm | Crime and organized-crime utility |
| Consumable efficiency | Grocery Store, Restaurant | Consumable boost or cooldown support |

The company catalog filters by gameplay style, searchable perk text and curated highlights. The last selected roadmap style informs the initial Jobs filter while users may independently change it.

## Tools

`docs/tools-guide.js` lists **24 tools** with device filters for Desktop, Phone, Tablet and All. Includes TornTools desktop extension, Torn PDA iOS/Android app, Torn Report, TornStats, YATA, TornW3B, Torn Travel Planner, Torn Exchange, CAT Script, FFScouter, Torn Intel, calculators, and API references. Tool usage and permission implications are stated without automatically connecting external services.

TornTools (browser extension) and Torn PDA (mobile app with its own userscript support) are **not interchangeable**. Desktop extensions cannot be assumed to work in iPad browsers or inside Torn PDA; specific device/browser compatibility remains a user-side decision. Dedicated setup walkthroughs or popups can be added later without changing this catalog.

## References

- [Official company list](https://wiki.torn.com/wiki/Company/Company_List)
- [Company specials list](https://wiki.torn.com/wiki/Company/Special_List)
- [Official city job ranks](https://wiki.torn.com/wiki/Joblist)
- [Getting started guide index](https://tornindex.com/topics/getting-started/)
- [Torn beginner guide 2026](https://www.torn.com/forums.php?p=threads&t=16582732)
- [Company categorization guide](https://www.torn.com/forums.php?p=threads&t=16551478)
- [TornTools official repository](https://github.com/Mephiles/torntools_extension)
- [Torn PDA](https://tornpda.com/)
- [The Affronted forum guide](https://www.torn.com/forums.php?p=threads&f=61&t=15925001)

## Verification performed

- JavaScript syntax for all guide modules
- All major navigation routes and live job rendering in a simulated browser
- 39 companies, 195 star specials, six city careers and 24 external tools
- Automatic filtering of Jobs by selected roadmap style
- Roadmap style persistence, optional milestones, prior completion keys, and single delegated event listener
- Jobs API request isolation and no static-catalog polling

The live GitHub Pages deployment and actual authenticated job response fields still need user-side browser testing. No Full Access API key or private Torn page content was committed.


## Quick Access launchers (November 23, 2026)

The user had TornW3B, Torn Travel Planner, Torn Exchange, Torn Report, Torn Intel, Clairvoyant, Torn Training Gains Calculator, CAT Script and FFScouter open. The extension directly read the first seven; host permissions blocked reading CAT Script, FFScouter and Torn Report pages, so their capabilities were cross-checked from public materials where possible.

The site adds a **single compact Quick Access bar below the header**, visible across routes. It always links to Torn, plus **up to four pinned external tools**. On first use it suggests three or four destinations based on saved gameplay style:

- Balanced: TornW3B Travel Stock, Torn Exchange and Torn Report
- Trade: stock availability, multi-flight planning, trading and history
- War: Torn Intel, CAT Script and FFScouter
- Mug: scouting, intel and trading
- Business: Clairvoyant, Torn Exchange and Torn Report
- Training: historical reports and an independent gym-calculator cross-check
- Crime, Revive and Racing: a smaller set without filler

Pin controls are on the Tools page. Preferences are only allowlisted tool names, stored in browser localStorage under a new key. No API key is stored or sent as a consequence of pinning. Restore suggested shortcuts removes the manual override. External links open in new tabs without an opener or referrer.

Contextual compact external-link rows appear only on relevant pages (Money to Clairvoyant/Exchange; War to CAT/Intel/FFScouter; Attacking to FFScouter; Stats to external calculator/report; Inventory to Exchange). A link already pinned to the bar is suppressed from the page's contextual row.

The Tools directory retains 24 resources but prioritizes frequently used ones and collapses specialized tools, installers and references behind More specialized tools. Search shows all matching results directly.

### What deliberately stays external

- TornW3B handles real-time abroad stock and item margins. Torn Travel Planner handles multiple-flight optimization. Torn Intel overlaps with both and adds war intelligence and alerts; this guide does not reconcile competing live forecasts.
- Torn Exchange manages trade price lists and receipts, not this guide.
- Torn Report supplies history, not a parallel polling and analytics pipeline.
- Clairvoyant stock-benefit comparison is linked from Money rather than duplicated.
- CAT Script coordinates live war calls, while FFScouter estimates combat strength, which may already be supported in TornTools.
- Torn PDA and TornTools are install/setup tools, not default launch buttons for every visit.
- External credentials and live data are not shared among unrelated services.

Validation covers script syntax and load order, gameplay-style defaults, pin/unpin, limit and persistence, contextual deduplication, and zero Torn API calls from loading or using the launcher. Live GitHub Pages deployment and provider authentication were not tested.


## Compact top bar and UI preferences (November 23, 2026)

The guide now uses a compact Torn favicon at upper left, directly linking to Torn. The Torn icon appears only there, not duplicated in Quick Access. The centered refresh control contains a circular-arrow icon and an elapsed clock since the last successful Torn API sync (MM:SS; HH:MM:SS after one hour). This counter updates locally once per second and does not poll Torn. Its tooltip announces the exact last sync, formatted using the chosen display time zone.

At upper right, connected player Name [#ID] appears immediately before an unframed three-dot Settings button. The duplicate player identity and Last refreshed card on Home was removed.

The settings menu offers:
- Sign out, identical to the account disconnect: clears saved API credentials and account cache but preserves UI settings and checklist progress.
- Theme: Dark (default), Light or Follow system.
- Time zone: Browser local (default), TCT/UTC or selected common international zones. The TCT clock remains UTC regardless.
- External link destination: New tab (default) or request a separate popup window. Browser behavior and popup blockers can override this preference.
- Contextual Quick Access: Off by default. When enabled, only tools mapped to the current guide page appear in the icon row.

Quick Access now includes all 11 launchable external sites by default, one representative URL per site, each as an icon-only link with a native hover tooltip and accessible label. The permanent Torn icon in the brand is not duplicated in the launcher. The Tools page lets users Hide or Show any eligible site, without the former four-pin limit; Show all launchable sites clears hidden choices. Contextual filtering happens after hidden-site preferences, so hidden sites do not reappear on other routes. Installers, wiki references and duplicate pages stay in the full Tools directory.

Settings persist under localStorage key torn-city-guide:interface:v1. Hidden sites use torn-city-guide:quick-links:hidden:v2. The older four-pin storage value is ignored rather than imposing a legacy cap. Neither new key contains Torn API credentials.

By default, external HTTP(S) links open in new tabs across the guide. If new-window mode is selected, the guide requests a separate window in response to the click. Internal hash navigation intentionally stays in the same guide tab so checklists, Stats Calc/Compare and other pages retain their state.

Simulated integration checks covered script order and syntax, zero additional API calls for UI preference changes, all 11 unique domains, icon visibility, contextual mappings, link behavior, timezone formatting, signed-in name/ID, elapsed sync age, and sign-out. Live GitHub Pages rendering and actual popup behavior have not been independently tested.


## Compact Home and account connection indicator (November 2026)

The upper-right username and player ID now include a small **green check** when the connected Torn API's requested selections are healthy. Any API selection error, inventory error, or failed connection becomes a **red X** with detailed error messages in a native hover tooltip and accessible label. Disconnected without an error is neutral, not a false red warning. A later successful request clears resolved errors; the guide does not expose API keys in tooltips.

Home now follows the compact shape of Torn's in-game Information sidebar: Energy (green), Nerve (red-orange), Happy (yellow) and Life (blue) progress bars with actual API numbers; Money, Level, Points and Merits; and minimal two-column key/value lists for Battle and Working stats. A reported time-to-full is shown only if a supported API field is present; it is a snapshot, not a fabricated local timer. Level experience and chain bars are omitted until a dependable data source exists.

The Home header no longer repeats the username and timestamp, and the redundant Explore Guide/Account grid is hidden while logged in on Home. The account controls remain accessible from the top bar. The home data refresh now includes workstats under its six-hour TTL; other page-specific requests and freshness rules stay unchanged. Cooldowns, account progression, actionable links, and the existing report-launch buttons remain available in compact sections. Detailed reports and data-source diagnostics are tucked behind expandable headings, except API errors which are expanded for visibility.

The Jobs page's current job and three working stats also use minimalist side-by-side lists. The Stats Calc/Compare page retains its four Battle stats horizontally across the top, scrolling horizontally instead of breaking into a two-column grid at tablet widths.

Racing now avoids purchasing a near-duplicate NSX Short Tarmac T2 build; see RACING_GUIDE.md for the two-car Short Turbo 3 tarmac/dirt setup and track-specific caveats.

No new API polling was added for status or progress bars; Home adds only the cached workstats selection while viewing Home.


## Home live bars and activity panel (November 24, 2026)

Home Energy, Nerve and Happy bars now advance locally at the regeneration tick predicted from the API's v2 tick timing fields, without additional API polling; Life is also projected. Over-cap special Happy values are not automatically reset when perk status is unclear. The static API snapshot disclaimer was removed.

A compact Bank, virus, travel & racing panel shows the cached investment value, profit and maturity. Update activity manually fetches only stale virus, travel, personal racing records, and race history selections. Home and the TCT dropdown reuse cached bank and flight deadlines, and the virus completion uses its absolute until timestamp. Last fetch times are visible. A legacy personalstats category error is corrected and removed from restored cache without suppressing other API errors.


## Site favicons in Quick Access (November 24, 2026)

Quick Access now shows the websites' own favicon images instead of the previous generic hand-drawn symbols. Each of the eleven curated services loads a direct HTTPS favicon from its corresponding site origin, with the site name kept as a native hover tooltip and accessible link label. If a site moves or blocks its favicon, the browser tries a cached copy of that site's favicon and finally reveals the original SVG fallback. External icons use no-referrer image requests. No Torn API requests or user credentials are involved.

All prior visibility and contextual filtering preferences remain unchanged. The toolbar preserves the current route when hiding or showing an icon. Browser-based integration tests covered all eleven direct favicon URLs, inaccessible-image fallback behavior, tooltip and label preservation, contextual filtering, hide/reset functionality, and absence of additional API requests. Origin favicon availability and pixel-perfect visual appearance still depend on the live provider websites.
