# Travel Assistant

Rainmeter-based Torn travel decision assistant.

The main v1 display remains deliberately focused on **Xanax in the United Kingdom and Japan**. The underlying observation, history, travel-mode, profitability, and travel-profile code is generic enough to expand later without rewriting the core model.

## Current status

The core Windows/Rainmeter path has been validated on the target machine:

- skin installation/junction works;
- UK and Japan panels and graphs render;
- YATA live stock/foreign prices update automatically;
- Torn Item Market resale pricing works through the configured local API key;
- the one-minute updater/heartbeat works from Rainmeter;
- observed restock/sellout history persists;
- stale/low-confidence/profitability guards remain conservative;
- no persistent Travel Assistant PowerShell process or material storage growth was observed.

A new **Settings** interface is now being added and requires a narrow Windows/Rainmeter validation pass before this extension is called complete.

The active execution scope is in [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md). Read [`AGENTS.md`](./AGENTS.md) before changing anything in this subtree.

## What the assistant answers

At a glance:

> Is the current foreign Xanax opportunity worth taking, and if so, when should I leave with my selected travel mode to maximize the chance that stock remains available when I arrive?

The project deliberately prefers **no recommendation** over a recommendation built from stale, low-confidence, economically unresolved, or unprofitable data.

## Main UI

The Rainmeter skin displays:

- United Kingdom above Japan;
- travel time and departure/recommendation state;
- observed/estimated restock information and last **actual** sellout;
- current stock and foreign purchase price;
- equal-width 24-hour stock graphs;
- visible last-successful-update time and next-poll countdown;
- a top-right **SETTINGS** action;
- Weav3r Travel Stock as an external verification link for low-confidence/actionable states.

Travel mode is no longer cycled directly from the main skin. The old click had to run the full updater/finalizer and therefore could take several seconds. Mode selection now belongs in Settings and is applied by the next normal polling pass.

## Settings interface

The local Windows Settings dialog edits only ignored/local state. It currently exposes:

- Torn API key, masked by default;
- travel mode;
- travel-related company and star rating;
- faction Excursion travel-capacity level;
- faction Travel Cost level;
- a preview of effective capacity/cost/free-Business effects.

The API key is stored in ignored `config/settings.local.json`; it is not embedded in `TravelAssistant.ini`, Git history, or the Rainmeter action command line.

### Travel modes

Normal choices are:

- Standard;
- Airstrip (default);
- WLT.

Business is **settings-only** and appears only when the local travel profile establishes free Business Class. The currently modeled safe branch is a **10-star Lingerie Store**. Ticket-funded Business travel remains economically unresolved, so forcing Business without that free-travel condition still suppresses departure advice rather than treating a ticket as free.

## Travel-related company profile

`config/travel-perks.json` keeps these effects data-driven. Current settings choices include:

- **Lingerie Store** — 3 stars adds 2 general travel items; 10 stars provides free Business Class travel.
- **Cruise Line** — 3 stars adds 2 travel items; 7 stars provides a destination stock-analysis special; 10 stars adds 3 more travel items.
- **Flower Shop** — 7 stars adds 5 flowers abroad; 10 stars provides flower stock analysis.
- **Toy Shop** — 7 stars adds 5 plushies abroad; 10 stars provides plushie stock analysis.
- **Logistics Management** — 5 stars allows returning to Torn while hospitalized abroad.
- **Theater** — 10 stars hides traveling status/destination.

Only effects relevant to the currently enabled item alter economics. In particular, Flower Shop and Toy Shop capacity bonuses are item-specific and **do not increase Xanax capacity**.

## Faction travel profile

The Settings dialog also models the relevant Excursion faction upgrades:

- Travel capacity: +1 item per level, up to +10.
- Travel cost: -15% travel fees per level, up to -75%.

These local profile inputs affect only final travel economics. They never rewrite observed stock, restock, or sellout history.

A positive `profitability.capacityOverride` remains authoritative if the user intentionally supplies one. Otherwise usable capacity is derived from the selected mode's base capacity plus qualifying company/item/faction bonuses.

## Installation

Expected repository source:

```text
C:\Codex\TORN\RainMeter Projects\Travel Assistant\
```

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

The installer creates ignored local/runtime directories and a non-destructive junction under the current user's Rainmeter `Skins` directory. Because the installed skin is a junction to the repository source, later pulls normally require only a Rainmeter refresh, not reinstalling.

Load:

```text
Travel Assistant\TravelAssistant.ini
```

## API key and live sources

YATA supplies live foreign stock and foreign price without a Torn API key.

A Torn key enables the Item Market resale reference used by profitability gating. The Settings dialog is now the preferred way to enter it. The existing environment-variable fallback remains:

```text
TORN_API_KEY
```

On the validated Windows machine, native Windows PowerShell `Invoke-RestMethod` hung specifically against `api.torn.com`, while `curl.exe` returned immediately. Production Torn Item Market traffic is therefore routed through bounded `curl.exe`; YATA remains on the native request path.

Never commit a limited/full-authority key.

## Economics and safety

The primary model first considers per-item spread/margin. `FinalizeState.ps1` then applies cached resale freshness and final trip economics:

```text
net resale = resale reference after configured selling fee
net profit/item = net resale - foreign purchase price
trip net = (net profit/item × usable capacity) - travel cost
required trip profit = max(minimumTotalTripProfit,
                           minimumProfitPerItem × usable capacity)
```

Final economics can include:

- mode-specific travel cost;
- user capacity override;
- general company capacity bonuses;
- item-specific company capacity bonuses where relevant;
- faction Excursion capacity;
- faction travel-fee reduction;
- zero-cost Business only when free Business Class is explicitly established.

If an economics/freshness gate fails, Travel Assistant continues collecting useful history and can continue showing restock information, but it clears departure timing.

## Learning and history

The committed seed remains intentionally empty rather than fabricated. Runtime observations are bounded and ignored by Git.

The engine learns from actual stock transitions:

```text
0 -> positive stock = observed restock
positive stock -> 0 = observed sellout
```

Completed cycles retain foreign price, restock/sellout times, availability duration, restock delay, and provenance. Forecasts never populate historical truth fields.

Default targets are roughly:

- 48 hours of high-resolution runtime observations;
- 90 days of compact completed cycles.

## Performance boundary

- One-second Rainmeter work is local Lua/string/countdown logic only.
- Network/history/model work normally runs once per minute.
- Updater executions are serialized.
- Finalization adds no network request.
- Settings launches only a short-lived local Windows Forms process while open.
- Graphs are two small generated PNG files.
- Runtime/generated state stays ignored and bounded.

## Validation

The full deterministic suite is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

Travel-profile-specific checks include:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelProfileTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FinalizeStateTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Repository/static tests do not replace actual Windows/Rainmeter interaction validation. See [`docs/WINDOWS_VALIDATION.md`](./docs/WINDOWS_VALIDATION.md).

## Architecture and documentation

The high-level path is:

```text
YATA / Torn provider adapters
        ↓
normalized observations
        ↓
bounded history + observed cycle detection
        ↓
price-aware restock/depletion model
        ↓
primary opportunity/profitability gate
        ↓
travel-profile + final trip-economics guards
        ↓
compact generated state
        ↓
Rainmeter UI
```

Read:

1. [`AGENTS.md`](./AGENTS.md)
2. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md)
3. [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)
4. [`docs/IMPLEMENTATION_STATUS.md`](./docs/IMPLEMENTATION_STATUS.md)
5. [`docs/WINDOWS_VALIDATION.md`](./docs/WINDOWS_VALIDATION.md)
