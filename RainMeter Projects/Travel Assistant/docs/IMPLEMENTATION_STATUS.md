# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** `NEXT_CODEX_RUN.md` remains **ACTIVE** because the Settings/travel-profile extension still needs final Rainmeter interaction validation.

## Stable baseline — previously validated

Before the Settings extension, the target machine had already validated the important operational path:

- deterministic model/history/finalizer suite passed on the earlier baseline;
- Rainmeter junction installation succeeded;
- UK/Japan panels and both generated graphs rendered;
- mojibake/encoding defects were fixed;
- local Torn API key was configured in ignored settings;
- direct Torn v2 Item Market `curl.exe` returned HTTP 200;
- Windows PowerShell `Invoke-RestMethod` against `api.torn.com` hung on this target, so production Torn requests use bounded `curl.exe` only for Torn Item Market;
- production updater/finalizer consumed a fresh `torn_itemmarket` cache;
- Rainmeter RunCommand declarations were corrected to `Measure=Plugin` / `Plugin=RunCommand`;
- one-minute automatic polling and heartbeat/stale detection were directly observed working;
- Japan sellout history persisted;
- a real UK restock followed by sellout was observed and recorded;
- post-fix Rainmeter log showed no new material Travel Assistant errors;
- no continuously running Travel Assistant PowerShell process was present between polls;
- runtime/generated data remained only a few KiB and graph files did not accumulate.

Those results remain valid and should not be discarded or needlessly repeated.

## Live-stock provider status

YATA later returned HTTP 502 from both native PowerShell and `curl.exe`, proving the failure was provider-side rather than Rainmeter/PowerShell transport.

Prometheus (`https://api.prombot.co.uk/api/travel`) was then probed directly on the target machine and returned valid structured UK/Japan Xanax data in about one second.

Production now uses:

```text
Prometheus
   ↓ unavailable
YATA
   ↓ unavailable
cached state + STALE_DATA
```

Provider provenance is retained in normalized observations.

Target-Windows validation on commit `eab8e25125509d70d992199199830fad6ef3874d`:

- `Validate-TravelAssistant.ps1` passed;
- `Validate-RainmeterSkin.ps1` passed;
- `Run-LiveProviderTests.ps1` passed all Prometheus/YATA normalization and provenance checks;
- one production updater pass exited `0` in **1.16 s**;
- generated state selected `LiveProvider=prometheus`;
- UK source timestamp `1787327669` and Japan source timestamp `1787327663` corresponded to approximately 11:54:29 and 11:54:23 local time, demonstrating near-current provider freshness during the validation;
- UK Xanax state: stock `0`, foreign price `$767,135`;
- Japan Xanax state: stock `0`, foreign price `$678,528`;
- both destinations correctly remained `INSUFFICIENT_HISTORY` rather than stale-provider fallback.

The Rainmeter header now includes provider name/source-age information so scheduler latency can be distinguished from provider latency.

## Settings / travel-profile extension

The laggy main-skin travel-mode click has been replaced by a top-right `SETTINGS >` control.

`OpenSettings.ps1` exposes:

- Torn API key, masked by default;
- Standard / Airstrip / WLT mode selection;
- travel-related company selection;
- company stars 0–10;
- faction Excursion capacity level 0–10;
- faction Travel Cost level 0–5;
- derived travel-perk preview;
- Business only when the selected profile establishes free Business Class.

The Rainmeter Settings launcher now uses a dedicated `RunCommand` measure instead of fragile nested command-line quoting. The PowerShell console is hidden. If the dialog script fails, it writes the exact error to ignored `data/runtime/settings-error.txt` and attempts to show a message box.

Saving settings writes only ignored/local state:

```text
config/settings.local.json
data/runtime/preferences.json
```

and starts a hidden asynchronous updater pass so mode/profile changes do not wait for the next one-minute poll.

### Travel-profile model

`config/travel-perks.json` + `TravelProfile.ps1` model:

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

`FinalizeState.ps1` applies the travel profile only at the final economics layer. It does not modify observations or cycle history.

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

## Validation already passed for the extension

On the target Windows machine:

- `Run-TravelProfileTests.ps1` passed all 19 profile/economics checks;
- `Run-FinalizeStateTests.ps1` passed all profile-integrated finalizer checks;
- `Validate-TravelAssistant.ps1` now passes after a validator-only parser defect was corrected;
- `Validate-RainmeterSkin.ps1` passes;
- `Run-LiveProviderTests.ps1` passes.

## Immediate remaining validation boundary

Refresh Rainmeter and directly validate:

- `SETTINGS >` appears;
- Settings launches without a transient console/error;
- API key remains masked/preserved;
- normal mode choices are Standard/Airstrip/WLT;
- company/star/faction controls render;
- Business is hidden for unqualified profiles;
- Lingerie Store 10-star exposes free Business;
- saving applies promptly through the hidden updater;
- automatic polling/heartbeat/history remain healthy after saving;
- no new Rainmeter/PowerShell/resource regression appears.

If Settings fails to open, inspect ignored `data/runtime/settings-error.txt` rather than trying to capture a disappearing console.

## Known follow-up / not part of current completion gate

- committed historical bootstrap remains intentionally empty;
- price similarity is still a bounded cohort rather than continuous weighting;
- first launch during an already-live restock cannot reconstruct an unseen restock start;
- profitability thresholds remain provisional calibration inputs;
- ticket-funded Business economics are still unresolved;
- a future `Sync from Torn` settings action may auto-detect user/company/faction perks, but endpoint response/permission behavior must be validated first rather than guessed.
