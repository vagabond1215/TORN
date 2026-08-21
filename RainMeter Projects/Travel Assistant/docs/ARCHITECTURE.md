# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing decision system for Torn foreign-market travel opportunities.

The main v1 presentation remains **Xanax in the United Kingdom and Japan**, while provider, item, country, travel-mode, price, capacity, company/faction travel profile, and economics inputs remain data-driven.

The engine answers two separate questions:

1. **Availability:** when would a departure be likely to arrive while stock is available?
2. **Economics:** is that trip economically justified for this user's selected travel mode/profile?

Departure advice appears only when both are adequately supported.

## Layering

```text
Provider adapters
      ↓
Normalized observations
      ↓
Bounded history / observed cycle detection
      ↓
Restock + price-aware depletion analytics
      ↓
Primary opportunity / per-item profitability engine
      ↓
Local travel-profile + final trip-economics guards
      ↓
Compact generated state
      ↓
Rainmeter presentation
```

The Settings interface is a side input to the **local travel-profile/final-economics layer**. It does not write observations or historical cycles.

## Provider adapters

Current production roles:

- **YATA** — live foreign stock and foreign purchase price.
- **Torn v2 Item Market** — resale reference when a local API key is configured.
- **Weav3r Travel Stock** — external verification link.

Provider-specific response shapes are normalized at the adapter boundary and must not leak into history/model code.

On the validated Windows target, native Windows PowerShell `Invoke-RestMethod` hung specifically against `api.torn.com` while `curl.exe` returned normally. `RunUpdate.ps1` therefore routes only Torn Item Market requests through bounded `curl.exe`; YATA remains on the native request path.

## Observation and history model

Core observation identity:

```text
timestamp + country + itemId + stock + foreignPrice + source + sourceTimestamp
```

Observed transitions have strict semantics:

```text
0 -> positive stock = observed restock
positive stock -> 0 = observed sellout
```

A compact completed cycle retains:

```text
country
itemId
foreignPrice
restockAt
restockQuantity
soldOutAt
availabilitySeconds
previousSoldOutAt
restockDelaySeconds
source / provenance
```

Actual restock/sellout fields are historical truth only. Provider forecasts may be future comparison inputs but never populate these truth records.

Runtime storage is local/ignored and bounded. High-resolution observations target roughly 48 hours; completed cycles roughly 90 days initially.

## Availability model

The model uses foreign price as first-class evidence. Evidence priority is:

1. current live depletion, once enough observations exist;
2. comparable historical cycles at the same/near foreign price;
3. broader destination/item history only with reduced confidence.

The current implementation uses a bounded near-price cohort rather than heavyweight ML.

### Safe window

`SAFE_WINDOW` requires conservative overlap among enough comparable cycles after converting historical availability intervals through the selected travel time. Current live depletion may **shorten** that window; it may never extend it beyond historical evidence.

### Best odds

When no conservative overlap exists, a strongest empirical departure point may be presented as `BEST_ODDS`. Best odds is probabilistic and is not labeled safe.

Sparse, stale, incomparable, or unsupported evidence yields no departure timing.

## Travel mode and profile inputs

Durable country/mode inputs remain in `config/countries.json`:

```text
travelSeconds
travelCosts
baseTravelCapacity
```

Local user-specific travel inputs belong in ignored `config/settings.local.json`:

```text
travelMode
travelProfile.companyType
travelProfile.companyStars
travelProfile.factionExcursionLevel
travelProfile.factionTravelCostLevel
profitability.capacityOverride
```

Company/faction effect definitions live in committed `config/travel-perks.json` so the economics code does not hard-code company names.

`@Resources/Scripts/TravelProfile.ps1` converts those inputs into derived effects:

```text
generalCapacityBonus
itemCapacityBonus
factionCapacityBonus
travelCostReductionPercent
freeBusinessClass
```

### Company effects currently modeled

- Lingerie Store: general capacity at 3 stars; free Business Class at 10 stars.
- Cruise Line: general capacity at 3 and 10 stars; 7-star stock analysis is informational.
- Flower Shop: flower-only capacity at 7 stars; stock analysis informational.
- Toy Shop: plushie-only capacity at 7 stars; stock analysis informational.
- Logistics Management: hospitalized return-to-Torn effect is informational for the current model.
- Theater: hidden travel status/destination is informational for the current model.

Item-specific bonuses are matched against the enabled item's category. Flower/Toy bonuses therefore do not alter Xanax capacity.

### Faction effects currently modeled

Excursion inputs:

- travel capacity: +1 item per level, max +10;
- travel cost: -15% travel fees per level, max -75%.

These are final-economics inputs only. They never alter historical stock/cycle evidence.

### Capacity precedence

A positive local `capacityOverride` is authoritative. Otherwise:

```text
usableCapacity = baseModeCapacity
               + generalCompanyCapacity
               + qualifyingItemSpecificCapacity
               + factionExcursionCapacity
```

This avoids double-counting a user-provided actual capacity override.

## Business travel safety branch

Business time/base capacity remain configured in country data. The cash/opportunity cost of consuming a Business Class Ticket remains unresolved.

Therefore:

- Business is **settings-only**;
- it appears in Settings only when the local travel profile establishes free Business Class;
- the currently modeled known-free branch is 10-star Lingerie Store;
- in that branch Business travel cost is explicitly known as zero;
- manually forcing Business without free travel produces unresolved economics and suppresses departure timing.

Unknown ticket economics are never interpreted as zero cost.

## Profitability and finalization

The primary recommendation engine performs early per-item spread/margin checks. `FinalizeState.ps1` then enforces cached resale freshness and final trip economics without making another network request.

```text
netResalePrice = grossResaleReference × (1 - sellingFee)
netProfitPerItem = netResalePrice - foreignPrice
tripNet = (netProfitPerItem × usableCapacity) - effectiveTravelCost
requiredTripProfit = max(minimumTotalTripProfit,
                         minimumProfitPerItem × usableCapacity)
```

The effective travel cost may include the faction Travel Cost reduction. For known-free Lingerie Business, effective travel cost is zero.

Finalizer responsibilities include:

- preserve informational restock/history even when departure advice is suppressed;
- retain exact active-restock time while stock is live;
- derive restock timing from completed cycles only when enough samples exist;
- suppress timing if resale data is stale;
- suppress timing if travel economics are unresolved;
- apply travel profile capacity/cost effects;
- clear timing fields after a failed final gate without erasing observed history.

## Settings architecture

The main skin exposes a top-right **SETTINGS** action.

`OpenSettings.ps1` is a short-lived Windows Forms process. It edits only ignored local files:

```text
config/settings.local.json
data/runtime/preferences.json
```

It exposes:

- masked Torn API key;
- travel mode;
- company type and stars;
- faction Excursion capacity level;
- faction Travel Cost level;
- derived effect preview.

The API key is never embedded in the `.ini` or passed in the Rainmeter action command line.

Mode selection was intentionally moved out of the main skin. The old mode click invoked the entire network/updater/finalizer pipeline and therefore could visibly lag several seconds. Settings writes the local preference immediately; the next normal polling pass recomputes travel timing/economics.

The settings UI is presentation/configuration only. Core safety logic remains in `TravelProfile.ps1` / `FinalizeState.ps1`, so malformed/manual configuration cannot bypass final economics guards.

## Rainmeter runtime model

### Every second

Allowed:

- read compact generated state;
- calculate countdowns;
- update strings/colors;
- schedule the next minute-scale update.

Not allowed:

- web requests;
- history parsing;
- model computation;
- graph regeneration.

### Approximately every 60 seconds

`RunUpdate.ps1` serializes:

```text
UpdateTracker.ps1
      ↓
FinalizeState.ps1
      ↓
heartbeat write
```

This pass may:

- fetch YATA;
- refresh Torn resale cache when required;
- append changed observations;
- detect restock/sellout transitions;
- recompute recommendation state;
- apply travel-profile economics;
- regenerate the two small graph PNGs.

The heartbeat is written only after a successful complete pass, allowing the skin to show last-successful-update time and visibly flag stale polling.

## Rainmeter presentation invariants

Main layout remains:

```text
TRAVEL ASSISTANT                         SETTINGS >
last update / next poll

UNITED KINGDOM - XANAX
Travel | Leave / Window
Restock | Last Sold Out
Stock | Foreign Price
Graph
Status

JAPAN - XANAX
Travel | Leave / Window
Restock | Last Sold Out
Stock | Foreign Price
Graph
Status
```

Rules:

- UK above Japan;
- equal graph widths;
- charcoal theme;
- relative timing preferred;
- Airstrip default;
- Settings rather than a main-skin mode cycler;
- Business settings-only and free-profile-gated;
- external Weav3r verification available;
- low-confidence state must not fabricate timing.

## Historical bootstrap

The committed historical seed remains intentionally empty until a trustworthy bounded structured source is verified. Startup correctness does not depend on a seed: the model can begin in `INSUFFICIENT_HISTORY` and learn locally.

Provider forecasts cannot be imported as observed cycles.

## Expansion design

Future expansion remains configuration-driven:

```text
items.json
countries.json
travel-modes.json
travel-perks.json
providers.json
settings*.json
```

Core code should remain generic around `country + itemId + travelMode + travelProfile` rather than fixed UK/Xanax names.

Possible future settings work includes a **Sync from Torn** action using suitable Torn user/faction endpoints, but auto-detection must be permission-aware and validated against real response contracts before it can replace manual local profile inputs.

## Validation boundary

Repository/static tests include:

- model replay;
- finalizer guards;
- travel-profile effect math;
- unqualified vs. free-Lingerie Business behavior;
- Flower/Toy non-Xanax isolation;
- Rainmeter RunCommand/Settings structure;
- JSON/config parsing.

Actual Settings-window rendering, Rainmeter launch quoting, local save behavior, and post-save polling still require target-Windows validation; connector-only work must not claim those have passed.
