# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** `NEXT_CODEX_RUN.md` remains **ACTIVE** pending final Rainmeter Settings/current-capacity interaction validation.

## Stable operational baseline

Already validated on the target Windows/Rainmeter machine:

- Rainmeter junction installation, UK/Japan panels, equal-width graphs, encoding fixes, and conservative sparse-history states;
- Torn v2 Item Market through bounded `curl.exe` with the ignored local API key;
- corrected Rainmeter `RunCommand` declarations;
- automatic one-minute polling, heartbeat/stale detection, persisted sellout history, and real restock/sellout collection;
- clean post-fix Rainmeter log, no persistent Travel Assistant PowerShell process, and bounded runtime/generated storage.

Do not repeat these checks unless a later source change directly affects them.

## Live-stock providers

YATA returned provider-side HTTP 502 from both PowerShell and curl. Prometheus (`https://api.prombot.co.uk/api/travel`) is now the preferred live-stock source with YATA fallback:

```text
Prometheus
   ↓ unavailable
YATA
   ↓ unavailable
cached state + STALE_DATA
```

Provider provenance is retained in normalized observations.

Target-Windows validation:

- `Validate-TravelAssistant.ps1` passed;
- `Validate-RainmeterSkin.ps1` passed;
- `Run-LiveProviderTests.ps1` passed;
- production updater exited `0` in about **1.16 s**;
- `LiveProvider=prometheus` with current UK/Japan stock, price, and source timestamps.

The Rainmeter header shows provider name/source age so provider latency can be distinguished from local scheduler latency.

## Settings / current travel profile

The main-skin mode cycler has been replaced by `SETTINGS >`. The Windows Forms dialog:

- keeps the Torn API key masked by default;
- exposes Standard / Airstrip / WLT;
- exposes company + company stars for non-capacity effects such as 10-star Lingerie free Business Class;
- exposes **Current Xanax capacity** as the preferred capacity input;
- provides `Sync from Torn` as a populate-only action;
- writes only ignored local settings/preferences after explicit Save;
- launches a hidden asynchronous update after Save;
- logs dialog failures to ignored `data/runtime/settings-error.txt`.

Legacy faction/loadout fields remain readable for backward compatibility, but they are no longer the preferred user-facing capacity source.

## Current-capacity model

The preferred capacity authority is the player's **currently active** `/user/perks` response, not faction-upgrade configuration.

`CurrentCapacity.ps1` derives effective Xanax capacity from:

- selected travel mode base: Standard `10`; Airstrip/WLT/qualified Business `15`;
- the currently active suitcase/enhancer bonus from `perks.enhancer`;
- currently active general travel-capacity bonuses from `perks.faction`, `perks.job`, and `perks.book`;
- Flower/Toy item-specific bonuses are excluded for Xanax;
- property/stock travel-method perks are not double-counted because the selected mode already supplies the 10/15 base.

If an otherwise relevant current perk string cannot be parsed confidently, the calculated capacity remains non-authoritative rather than guessing.

### Live in-flight validation

While the user was actively traveling, the redacted capacity probe succeeded using `/user/perks` only:

```text
Selected mode: Airstrip
Base capacity: 15
Large Suitcase / enhancer: +3
Other active capacity perks: +0
Effective Xanax capacity: 18
```

This validates that current capacity remains available while traveling and does not require faction API permission.

## Economics integration

A successfully synced current-capacity bonus is authoritative for carrying capacity and **replaces inferred company/faction capacity slots**, preventing double-counting. The bonus is stored relative to the selected mode base, so the same current `+3` produces:

```text
Standard: 13
Airstrip: 18
WLT:      18
Business: 18 (only when Business itself is qualified)
```

Company/star data is still retained for non-capacity effects, especially 10-star Lingerie free Business Class. Ticket-funded Business remains unresolved and suppresses timing.

Target-Windows deterministic validation on current `main`:

- `Validate-TravelAssistant.ps1` passed;
- `Run-TravelProfileTests.ps1` passed, including current-capacity authority and no-double-counting cases;
- `Run-CurrentCapacityTests.ps1` passed all parser, enhancer, exclusion, and unresolved-string cases.

### Live generated-state integration

After saving Airstrip with the synced `+3` current bonus, the generated Rainmeter state showed:

```text
JPCapacity=18
ProfileFactionCapacityBonus=0
ProfileGeneralCapacityBonus=3
TravelMode=airstrip
UKCapacity=18
```

This is the required end-to-end proof that final profitability/economics uses the current-capacity authority without inferred faction-capacity double-counting.

## Remaining completion boundary

The generated-state economics check is complete. Remaining direct Rainmeter interaction checks are:

1. Confirm the simplified form shows **Current Xanax capacity** rather than faction Peace/War loadout controls.
2. Click `Sync from Torn`; while the same current perks remain active, expect Airstrip capacity `18` (`15 + 3`).
3. Without saving, change Airstrip → Standard and confirm capacity changes to `13`; switch back to Airstrip and confirm `18`.
4. Confirm Sync is populate-only: Cancel/reopen must retain the previously saved settings.
5. Confirm 10-star Lingerie still exposes Business and an unqualified company does not.
6. Allow a normal automatic poll afterward and confirm Prometheus/freshness remains healthy.
7. Confirm no new material Rainmeter/PowerShell errors appear if behavior suggests a regression.

Only after these interaction checks pass should the active run be marked **COMPLETED**.
