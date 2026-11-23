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

Some milestones are marked **Verified by API** only where the existing cached API can confirm them, such as level 15 and previously supported merit milestones. Permanent job passives are not automatically marked complete without a reliable data source; they remain manually checkable.

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
