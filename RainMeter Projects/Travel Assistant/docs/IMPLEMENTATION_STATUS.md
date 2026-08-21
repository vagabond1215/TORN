# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** `NEXT_CODEX_RUN.md` remains **ACTIVE** pending final Rainmeter interaction validation for Settings / Sync from Torn.

## Stable operational baseline

The target Windows machine has already validated the core Travel Assistant path:

- Rainmeter junction installation, UK/Japan panels, graphs, encoding fixes, and conservative sparse-history states;
- Torn v2 Item Market through bounded `curl.exe` with the local ignored API key;
- corrected Rainmeter `RunCommand` declarations;
- automatic one-minute polling, heartbeat/stale detection, persisted sellout history, and real restock/sellout collection;
- clean post-fix Rainmeter log, no persistent Travel Assistant PowerShell process, and bounded runtime/generated storage.

Do not repeat those checks unless a later source change directly affects them.

## Live-stock providers

YATA returned provider-side HTTP 502 from both PowerShell and curl. Prometheus (`https://api.prombot.co.uk/api/travel`) was therefore added as preferred live-stock source with YATA fallback:

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
- production updater exited `0` in **1.16 s**;
- `LiveProvider=prometheus`;
- UK source timestamp `1787327669`, stock `0`, price `$767,135`;
- Japan source timestamp `1787327663`, stock `0`, price `$678,528`;
- both destinations remained `INSUFFICIENT_HISTORY`, not stale-provider fallback.

The Rainmeter header shows provider name/source age so provider latency can be distinguished from local scheduler latency.

## Settings / travel profile

The main-skin mode cycler has been replaced by `SETTINGS >`. The Windows Forms dialog:

- keeps the Torn API key masked by default;
- exposes Standard / Airstrip / WLT, company, company stars, faction Excursion, and faction Travel Cost;
- exposes Business only when free Business Class is established;
- writes only ignored local settings/preferences;
- launches a hidden asynchronous update after Save;
- logs dialog failures to ignored `data/runtime/settings-error.txt`.

A layout overlap on the Excursion label was corrected so it no longer paints over the numeric control.

### Travel-profile economics

The final economics layer supports:

- Lingerie Store: +2 capacity at 3-star; free Business Class at 10-star;
- Cruise Line: +2 capacity at 3-star and +3 additional at 10-star;
- Flower/Toy item-specific capacity without incorrectly increasing Xanax capacity;
- Logistics/Theater informational travel effects;
- faction Excursion +1 capacity per level through 10;
- faction Travel Cost -15% fees per level through 5 / -75%.

Unknown ticket-funded Business economics remain unresolved and suppress timing.

## Torn profile auto-detection

The saved high-access local key successfully reached all required Torn v2 endpoints through the redacted probe:

- BASIC: profile returned successfully;
- JOB: starter Education job (`Substitute Teacher`), so no company travel bonus;
- PERKS: accessible; no travel-related job/faction perk strings matched;
- FACTION UPGRADES: accessible; no travel-capacity/travel-cost upgrades were present.

`Sync from Torn` is now implemented as a **populate-only** Settings action. It does not save until the user explicitly clicks Save. Unknown company types remain unresolved rather than guessed.

Target-Windows sync validation on commit `2367874fedea5f9beea215baea4265e92e7c39d4`:

- `Validate-TravelAssistant.ps1` passed;
- `Run-TornProfileSyncTests.ps1` passed all starter-job, known/unknown company mapping, rating preservation, and faction Travel capacity / Travel cost parsing cases.

For the currently probed user, Sync from Torn should populate:

```text
Company: None / Other
Company stars: 0
Faction Excursion: 0
Faction Travel Cost: 0
```

## Remaining completion boundary

Directly validate in Rainmeter:

1. Settings opens and the Excursion layout artifact is gone.
2. `Sync from Torn` populates the current Education profile as None / 0-star / faction 0 / 0 and does not save automatically.
3. Manual Lingerie Store 10-star exposes Business; unqualified profiles do not.
4. Clicking Save closes promptly and the hidden update applies the profile/mode.
5. A subsequent normal automatic poll remains healthy with Prometheus source/freshness shown.
6. No new material Rainmeter/PowerShell/resource errors appear.

Only after these interaction checks pass should the active run be marked **COMPLETED**.
