# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** `NEXT_CODEX_RUN.md` remains **ACTIVE** because the newly requested Settings/travel-profile extension still needs narrow target-Windows validation.

## Stable baseline — previously validated

Before the Settings extension, the target machine had already validated the important operational path:

- deterministic model/history/finalizer suite passed on the earlier baseline;
- bounded YATA live request and production updater pass succeeded;
- Rainmeter junction installation succeeded;
- UK/Japan panels and both generated graphs rendered;
- live stock/foreign prices rendered plausibly;
- mojibake/encoding defects were fixed;
- local Torn API key was configured in ignored settings;
- direct Torn v2 Item Market `curl.exe` returned HTTP 200;
- Windows PowerShell `Invoke-RestMethod` against `api.torn.com` hung on this target, so production Torn requests were safely moved to bounded `curl.exe` while YATA stayed unchanged;
- production updater/finalizer consumed a fresh `torn_itemmarket` cache;
- Rainmeter RunCommand declarations were corrected to `Measure=Plugin` / `Plugin=RunCommand`;
- one-minute automatic polling and heartbeat/stale detection were directly observed working;
- Japan sellout history persisted;
- a real UK restock followed by sellout was observed and recorded;
- post-fix Rainmeter log showed no new material Travel Assistant errors;
- no continuously running Travel Assistant PowerShell process was present between polls;
- runtime/generated data remained only a few KiB and graph files did not accumulate.

Those results remain valid and should not be discarded or needlessly repeated.

## Current extension — implemented in repository, local validation pending

The user requested that the laggy main-skin travel-mode click be replaced with a Settings interface and that user travel perks be represented.

### Main-skin change

`TravelAssistant.ini` now:

- keeps the proven `MeasureUpdate` polling path unchanged;
- removes the main `MeasureCycleMode` interaction;
- replaces the top-right mode selector with `SETTINGS >`;
- launches `@Resources/Scripts/OpenSettings.ps1` as a short-lived local Windows Forms dialog.

This removes the old UX where a simple mode click waited on a full network/updater/finalizer pass.

### Settings interface

`OpenSettings.ps1` exposes:

- Torn API key, masked by default;
- Standard / Airstrip / WLT mode selection;
- travel-related company selection;
- company stars 0–10;
- faction Excursion capacity level 0–10;
- faction Travel Cost level 0–5;
- derived travel-perk preview;
- Business only when the selected profile establishes free Business Class.

Save writes only ignored/local state:

```text
config/settings.local.json
data/runtime/preferences.json
```

The key is not embedded in the Rainmeter `.ini` or action command line.

### Travel-profile model

New `config/travel-perks.json` + `TravelProfile.ps1` model:

- Lingerie Store 3-star +2 general travel items;
- Lingerie Store 10-star free Business Class;
- Cruise Line 3-star +2 and 10-star +3 additional general travel capacity;
- Cruise 7-star stock-analysis effect as informational;
- Flower Shop 7-star +5 flowers only;
- Toy Shop 7-star +5 plushies only;
- Logistics Management 5-star return-while-hospitalized effect as informational;
- Theater 10-star hidden travel status/destination as informational;
- faction Excursion +1 capacity per level, max +10;
- faction Travel Cost -15% fees per level, max -75%.

Flower/Toy item-specific capacity is category-gated and therefore does **not** increase Xanax capacity.

### Final economics integration

`FinalizeState.ps1` now applies the travel profile only at the final economics layer. It does not modify observations or cycle history.

Capacity precedence:

```text
if capacityOverride > 0:
    use override
else:
    base mode capacity
    + qualifying general company capacity
    + qualifying item-specific capacity
    + faction Excursion capacity
```

Effective positive travel fees may be reduced by the configured faction Travel Cost level.

Business handling:

- normal Business ticket opportunity cost remains unresolved;
- Business is settings-only;
- 10-star Lingerie establishes a known zero-cost Business branch;
- unqualified/manually forced Business remains unresolved and final timing is suppressed.

This preserves the invariant that unknown economics are not treated as zero-cost economics.

## Regression coverage added/updated

- `tests/Run-TravelProfileTests.ps1` — pure profile/economics tests.
- `tests/Run-FinalizeStateTests.ps1` — final integration including qualified/unqualified Business and faction/company capacity/cost.
- `tests/Validate-RainmeterSkin.ps1` — Settings-button structure and RunCommand guard.
- `tests/Validate-TravelAssistant.ps1` — new config/scripts/profile contract and ignored local settings.
- `tests/Run-All.ps1` — now includes travel-profile tests.

These tests have been authored connector-side but the new versions have **not yet been claimed as passing on the target Windows machine**.

## Immediate validation boundary

Run only the changed-boundary checks first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelAssistant.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelProfileTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FinalizeStateTests.ps1
```

Then refresh Rainmeter and directly validate:

- `SETTINGS >` appears;
- Settings launches and closes normally;
- API key remains masked/preserved;
- normal mode choices are Standard/Airstrip/WLT;
- company/star/faction controls render;
- Business is hidden for unqualified profiles;
- Lingerie Store 10-star exposes free Business;
- Flower/Toy do not increase Xanax-specific capacity;
- saving applies on the next normal poll;
- automatic polling/heartbeat/history remain healthy;
- no new Rainmeter/PowerShell/resource regression appears.

## Known follow-up / not part of current completion gate

- committed historical bootstrap remains intentionally empty;
- price similarity is still a bounded cohort rather than continuous weighting;
- no enabled secondary live-provider cross-check;
- first launch during an already-live restock cannot reconstruct an unseen restock start;
- profitability thresholds remain provisional calibration inputs;
- ticket-funded Business economics are still unresolved;
- a future `Sync from Torn` settings action may auto-detect user/company/faction perks, but endpoint response/permission behavior must be validated first rather than guessed.
