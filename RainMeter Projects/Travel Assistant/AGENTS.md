# Travel Assistant Agent Instructions

These instructions apply to the entire `RainMeter Projects/Travel Assistant/` subtree.

## Read order

Before changing code or data, read:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`

If an older plan conflicts with an **ACTIVE** `NEXT_CODEX_RUN.md`, follow the active run while preserving every invariant here.

## Connector-first execution

- Prefer GPT + the connected GitHub connector for inspection, source/config/doc edits, tests and commits.
- Use local Windows only for Rainmeter rendering, Windows PowerShell behavior, local provider/API behavior, performance/resource checks or OS-specific integration.
- Never claim Windows/Rainmeter/live-provider validation that did not run.
- Work only inside this subtree unless explicitly asked otherwise.
- Direct `main` edits remain allowed while the project is isolated/pre-use. Never force-push or rewrite unrelated work.

## Product direction

Travel Assistant is expanding from the UK/Japan Xanax proof into a generic Torn foreign-market assistant.

Keep these populations separate:

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

### Collection

- Observe every valid foreign-shop row returned by the live provider for every configured foreign country, irrespective of category.
- A provider row is evidence about the provider dataset, **not proof that the item is currently purchasable in that country**.
- Market identity is always `country + itemId`.
- Verified inactive/legacy markets remain observable for provenance but must not receive new learning/history/resale work or become visible/optimizer candidates.
- UI filters and current travel destination must never stop background learning for other active markets.

### Visibility

- The last target-Windows-validated UI baseline is UK/Japan Xanax.
- The current committed `0.3.0` release candidate adds Nessie Plushie under UK and Cherry Blossom under Japan and is pending target-Windows/Rainmeter acceptance.
- Nessie/Cherry are presentation-only in this release: `visible=true`, `enabled=false`, `optimizerEligible=false`.
- Current secondary rows do not inherit Xanax departure timing; existing graph/travel/restock/decision output remains Xanax-specific until deliberate per-item timing work is validated.
- Future country/category filters are presentation filters only.
- Future outbound travel presentation should show only the destination country's items and replace static flight duration with arrival countdown while keeping the plane icon.

### Optimizer

- `Optimal` is a future scheduling layer, not a sort by profit/item or profit/trip.
- Do not make a market optimizer-eligible until economics, capacity semantics, current availability, market validity and evidence quality are adequately modeled.
- It must eventually compare many short trips, fewer long trips and mixed-country sequences over a bounded planning horizon.

## Non-negotiable data/recommendation invariants

1. Prefer no recommendation over weak/unsafe advice.
2. `0 -> positive` is an observed restock; `positive -> 0` is an observed sellout. Forecasts never become historical truth.
3. Keep history/model state isolated by `country + itemId`.
4. Foreign price is first-class evidence; do not merge radically different price regimes as equivalent.
5. Current depletion may shorten safety but never expand it beyond supporting history.
6. `BEST_ODDS` is not `SAFE_WINDOW`.
7. Profitability gates timing, not learning.
8. Unknown economics are not zero economics. Ticket-funded Business remains unresolved unless a known-free branch exists.
9. Provider provenance is retained and normalized at the adapter boundary.
10. Collection/enrichment failures must fail visibly but gracefully and must not break the established visible Xanax path.
11. Runtime observations, cycles, caches, generated state/graphs, local settings, credentials and errors stay ignored/local.
12. Storage/compute remain bounded. The one-second Rainmeter loop must not perform network/model work.
13. Provider market membership may be stale. A verified inactive `country + itemId` override supersedes provider presence for learning, display, resale and optimization eligibility while preserving provenance/history.
14. Broad resale population must never create an API burst; missing/no-price responses remain unresolved rather than becoming zero economics.
15. Market/resale reference is not foreign price. Display them distinctly and never overwrite one with the other.

## Current background-collection contract

`ShadowCollector.ps1` is the active expansion bridge:

- visible updater runs first;
- shadow collector runs afterward;
- default shadow interval is 120 seconds;
- all 11 foreign destinations are observed;
- every valid provider row normalizes to the observation schema and updates `observedMarkets`;
- current primary visible markets are skipped by shadow writes;
- `config/foreign-market-overrides.json` supplies verified inactive market pairs;
- inactive provider rows remain in `observedMarkets` but are skipped before new observation/cycle writes;
- raw history writes only on stock/foreign-price changes for active markets;
- provider timestamp alone updates freshness without another raw observation;
- failures remain fail-soft.

Accepted target-Windows baseline on 2026-08-21:

```text
Prometheus
11 countries
232 observed country-item provider rows
232 / 232 rows with provider names
202 distinct item IDs
202 / 202 categories resolved
5 verified legacy rows
227 active country-item markets
no shadow error
```

Current verified legacy rows:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

Do not hard-code these live counts as timeless constants.

A later refactor may unify visible and shadow collection behind one provider fetch only after equivalent primary behavior is proven.

## Current item-metadata contract

Catalog metadata must **not** run inside the Rainmeter heartbeat path.

Target-Windows testing established that all attempted Torn catalog transports timed out before returning metadata:

```text
v2 specific-items | 150 IDs | 20s
v2 specific-items |  40 IDs | 30s
classic torn/items bulk      | 12s
```

Therefore:

- `RunUpdate.ps1` must not invoke `ItemMetadata.ps1`;
- `ItemMetadata.ps1` is explicit/manual maintenance only;
- do not keep increasing Torn catalog timeouts/batch sizes;
- full catalog metadata comes from committed/offline references refreshed outside the heartbeat.

`LocalCatalog.ps1` uses local precedence:

```text
richer manual Torn metadata
    > explicit config seed
    > verified item override
    > offline YATA-derived category snapshot
    > provider name + Unknown
```

Current committed offline metadata files:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

The 197-ID category snapshot plus five individually verified overrides resolve the current 202 observed item IDs without runtime Torn catalog access. The verified overrides also correct stale canonical names for item 327 (`Blank Casino Chips`) and item 383 (`Digital Organizer`).

`ItemMetadata.ps1` must seed committed `config/items.json` metadata before any optional network attempt. Seed rows use:

```text
source=config_seed
marketPrice=0
tradabilityKnown=false
```

Current committed seeds:

```text
206 Xanax          | Drug
266 Nessie Plushie | Plushie
277 Cherry Blossom | Flower
```

A later successful maintenance refresh may replace local rows with richer canonical metadata. Network failure must never erase known local metadata.

## Current resale-queue contract

`ResaleQueue.ps1` is the broad pricing bridge.

It must:

- run only for normal `Update` actions;
- run after the visible heartbeat;
- derive distinct item IDs only from active `observedMarkets` rows;
- skip `catalogActive=false` and defensively skip `catalogStatus=legacy_removed`;
- make at most one production Torn Item Market request per queue run path;
- default to a 60-second attempt cadence, six-hour broad cache target, one-hour failure backoff and six-second request timeout;
- prioritize configured `visible=true` items among otherwise eligible stale/unpriced items, without increasing request frequency;
- preserve a last successful cache row when a later refresh fails;
- use bounded `curl.exe --config -` with the API key supplied only via stdin Authorization header;
- never place a key in request URLs or process arguments;
- keep missing/zero-price outcomes unresolved.

Broad queue success rows use the existing shared cache schema:

```text
price
lowest
average
fetchedAt
source=torn_itemmarket
```

The current visible Xanax updater retains its independent/fresher resale behavior. Do not weaken current visible resale freshness just because broad population uses a six-hour reference cache.

Runtime queue health lives under:

```text
engine-state.json -> resaleQueue
```

and must remain ignored/local.

## Observation / cycle contracts

Normalized observation:

```text
schemaVersion
timestamp
country
itemId
stock
foreignPrice
source
sourceTimestamp
```

Completed cycle:

```text
schemaVersion
country
itemId
foreignPrice
restockAt
restockQuantity
soldOutAt
availabilitySeconds
previousSoldOutAt
restockDelaySeconds
source
```

Default retention:

- high-resolution observations: 48 hours;
- completed cycles: 90 days;
- visible graph window: 8 hours.

The live stale threshold is a safety guard, not history retention.

## Capacity / travel-profile authority

Prefer current `/user/perks` for carrying capacity rather than faction-upgrade permissions.

Current mode base:

- Standard: 10;
- Airstrip/WLT/qualified Business: 15.

A synced current-capacity bonus is authoritative for general capacity and replaces legacy inferred company/faction additions. Property/stock travel-method effects must not be double-counted.

Company/star modeling remains authoritative for category-specific bonuses excluded from the general/Xanax capacity sync and for non-capacity effects such as free Business Class.

Accepted category isolation:

- Flower Shop 7★ adds +5 only to Flower items;
- Toy Shop 7★ adds +5 only to Plushie items;
- neither may increase Xanax capacity.

Current accepted example:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
qualifying Airstrip Flower/Plushie = 23
qualifying Standard Flower/Plushie = 18
```

A positive explicit `profitability.capacityOverride` remains authoritative where supported.

## Provider / web-data policy

- Treat Prometheus, YATA, Torn, Weav3r, DroqsDB and other services as replaceable adapters.
- Prefer structured endpoints over scraping when practical.
- Live foreign stock is provider-observed/crowd-sourced; provider market membership may contain legacy rows and is not by itself current-shop authority.
- Static Wiki destination tables are also not sufficient alone as live-catalog authority; use item-specific/history evidence for verified exceptions.
- Do not create one stock request per item; a country payload must fan out locally.
- Full item names/categories come from the committed/offline catalog plus verified overrides.
- Resale pricing is separate and must be cached/staggered rather than hundreds of Torn market calls per minute.
- Source disagreement lowers confidence; do not silently average incompatible states.

## API keys / secrets

- API keys remain local and ignored; never commit them.
- Settings masks the key by default.
- Never ask the user to paste the full key into chat.
- Do not broaden permissions for convenience.
- Use bounded `curl.exe` only where required on the target Windows host.
- Never put a key in process arguments or request URLs when stdin/header transport is available.

## Performance budget

- one-second Rainmeter work: local string/countdown/visibility only;
- primary updater/model/finalizer: about once per minute;
- broad shadow collection: no more often than 120 seconds unless revalidated;
- visible-item enrichment: local-only, no network calls;
- broad resale queue: at most one lower-priority Torn market request per normal update, after the visible heartbeat;
- item catalog network maintenance: **not in the heartbeat**, explicit/manual only;
- no permanent background PowerShell/browser processes;
- updater executions stay serialized;
- graph generation remains compact.

## Current UI invariants

For the committed `0.3.0` release candidate, pending target-Windows/Rainmeter acceptance:

- dark charcoal theme;
- UK above Japan;
- local vector country flags, not claimed official Torn assets;
- UK shows Xanax then Nessie Plushie; Japan shows Xanax then Cherry Blossom;
- every visible item shows foreign shop price followed by `(Torn market reference)`;
- foreign price retains profitability color; the parenthesized market reference is smaller and muted;
- only literal `Out of Stock` is red;
- out-of-stock text is `Out of Stock for h:mm since HH:mm`;
- existing plane/restock/decision row remains Xanax-specific;
- existing equal 8-hour graphs with 60-minute divisions remain Xanax graphs;
- hidden timing/history remains in the Xanax tooltip;
- `Travel` header opens Torn travel;
- Settings remains top-right.

## Stable status codes

Keep logic keyed to codes, not display strings. Current vocabulary includes:

```text
SAFE_WINDOW
BEST_ODDS
TOO_EARLY
WINDOW_CLOSED
INSUFFICIENT_HISTORY
PRICE_REGIME_UNVERIFIED
SOURCE_DISAGREEMENT
LOW_MARGIN
UNPROFITABLE
STALE_DATA
CHECK_EXTERNAL
```

## Validation expectations

For collection/config/model changes:

- validate JSON;
- run PowerShell parser/static checks;
- exercise provider/metadata/resale/visible-item normalization from fixtures/synthetic payloads;
- prove country/item cycle isolation;
- prove primary markets are protected from duplicate shadow writes;
- prove verified inactive markets are retained as provider metadata but skipped before new shadow history/cycle/resale/display work;
- prove metadata network maintenance stays outside `RunUpdate.ps1`;
- prove visible-item enrichment is local-only;
- prove broad resale runs after the visible heartbeat and remains one-request bounded;
- verify retention and ignored-runtime boundaries;
- run focused tests before broad suites;
- never claim live/Rainmeter validation until it runs on Windows.

Current focused expansion checks:

```powershell
.\tests\Validate-ShadowCollection.ps1
.\tests\Run-ShadowCollectionTests.ps1
.\tests\Validate-LocalCatalog.ps1
.\tests\Run-LocalCatalogTests.ps1
.\tests\Validate-ResaleQueue.ps1
.\tests\Run-ResaleQueueTests.ps1
.\tests\Validate-VisibleItems.ps1
.\tests\Run-VisibleItemsTests.ps1
.\tests\Validate-RainmeterSkin.ps1
```

Use `tests/Run-All.ps1` only when a broad run is justified.

## Documentation / handoff

- Keep `docs/ARCHITECTURE.md` synchronized with durable decisions.
- Keep `docs/NEXT_CODEX_RUN.md` as the active rolling handoff.
- Keep `docs/IMPLEMENTATION_STATUS.md` factual about implemented vs validated behavior.
- Keep `Readme.md` human-readable/current.
- Update the rolling handoff rather than creating competing task documents.
