# Next Codex Run: Travel Assistant Settings / Current Capacity Validation

**Status: ACTIVE**

This is the authoritative execution handoff for `RainMeter Projects/Travel Assistant/`.

## Do not repeat the stable baseline

Already validated on the target Windows/Rainmeter machine:

- installation/junction, UK/Japan render, equal-width graphs, encoding fixes;
- Torn Item Market via bounded curl and ignored local API key;
- automatic one-minute Rainmeter polling, heartbeat/stale detection, real restock/sellout history collection;
- clean post-fix Rainmeter log, no persistent Travel Assistant PowerShell process, bounded generated/runtime storage;
- Prometheus preferred live stock with YATA fallback;
- production Prometheus pass around 1.16 s with current stock/price/source timestamps.

## Current Settings design

The top-right main-skin control is `SETTINGS >`.

Settings now centers on:

- masked Torn API key;
- Standard / Airstrip / WLT;
- company + stars for non-capacity effects such as free Business Class;
- **Current Xanax capacity**;
- `Sync from Torn` as a populate-only action;
- explicit Save followed by a hidden asynchronous update.

Legacy faction/loadout fields remain readable for old local settings but are no longer the preferred user-facing capacity source.

## Current-capacity authority

Do not query faction upgrades to determine usable Xanax carrying capacity.

Use current `/user/perks` instead:

- mode supplies base capacity: Standard `10`; Airstrip/WLT/qualified Business `15`;
- `perks.enhancer` supplies the current non-stacking suitcase bonus;
- `perks.faction`, `perks.job`, and `perks.book` supply currently active additive general travel-capacity bonuses;
- property/stock method perks are excluded from additive capacity to avoid double-counting the selected 10/15 base;
- Flower/Toy item-specific bonuses do not increase Xanax capacity;
- unknown relevant perk text keeps the result unresolved rather than guessing.

A successfully synced current-capacity bonus is authoritative and replaces inferred company/faction capacity slots in economics.

### Live target validation

While the user was actively traveling, `Probe-TornTravelProfile.ps1` resolved:

```text
Mode: Airstrip
Base: 15
Large Suitcase/enhancer: +3
Other active perks: +0
Effective capacity: 18
```

`Run-CurrentCapacityTests.ps1` passed all current parser/enhancer/exclusion/unresolved cases.

`Run-TravelProfileTests.ps1` passed all existing economics tests plus:

- synced current capacity retained;
- current bonus retained;
- current capacity replaces inferred company/faction slots;
- no faction double-counting;
- conservative zero faction fee reduction when current capacity is authoritative;
- 10-star Lingerie Business unlock still preserved;
- current `+3` yields Airstrip `18`, Standard `13`, qualified Business `18`.

`Validate-TravelAssistant.ps1` also passed.

### Live generated-state economics pass

After saving Airstrip with the synced current `+3` bonus, the target Windows machine produced:

```text
JPCapacity=18
ProfileFactionCapacityBonus=0
ProfileGeneralCapacityBonus=3
TravelMode=airstrip
UKCapacity=18
```

This confirms the final generated state uses the current-capacity authority and does not add inferred faction capacity on top.

## Immediate remaining validation

Do not add more code unless one of these checks fails.

1. Confirm the simplified Settings UI shows **Current Xanax capacity** and no longer asks the user to manage faction Peace/War loadouts.
2. Click **Sync from Torn**. With the same active perks, expected Airstrip capacity is `18` (`15 + 3`).
3. Before saving, change Airstrip → Standard and confirm the displayed capacity recalculates to `13`; switch back to Airstrip and confirm `18`.
4. Confirm Sync is populate-only: Cancel/reopen should retain the previously saved values.
5. Manually choose Lingerie Store + 10 stars and confirm Business appears; switch back to an unqualified profile and confirm Business disappears.
6. Allow a normal automatic poll after the successful Save and confirm Prometheus/source freshness remains healthy.
7. Check for new material Rainmeter/PowerShell errors only if behavior suggests a regression.

The generated-state capacity/economics check has already passed and should not be repeated unless a later change touches that path.

## Completion criteria

Mark **COMPLETED** only when the live Settings sync/recalculation/Business-gating/populate-only checks above pass and the next normal automatic poll remains healthy.
