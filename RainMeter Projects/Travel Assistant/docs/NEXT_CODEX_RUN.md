# Next Codex Run: Travel Assistant Settings / Torn Sync Validation

**Status: ACTIVE**

This is the authoritative execution handoff for `RainMeter Projects/Travel Assistant/`.

## Do not repeat the stable baseline

Already validated on the target Windows/Rainmeter machine:

- installation/junction, UK/Japan render, equal-width graphs, encoding fixes;
- Torn Item Market via bounded curl and ignored local API key;
- automatic one-minute Rainmeter polling, heartbeat/stale detection, real restock/sellout history collection;
- clean post-fix Rainmeter log, no persistent Travel Assistant PowerShell process, bounded generated/runtime storage;
- final economics/history/model tests from the stable baseline.

## Current live-stock path

YATA later returned provider-side HTTP 502 from both native PowerShell and curl. Prometheus was probed successfully and is now preferred:

```text
Prometheus
   ↓ unavailable
YATA
   ↓ unavailable
cached state + STALE_DATA
```

Validated production pass: `EXIT=0`, ~1.16 s, `LiveProvider=prometheus`, with near-current UK/Japan source timestamps and populated Xanax stock/prices.

## Settings extension

The top-right main-skin mode click is replaced by `SETTINGS >`.

Settings now supports:

- masked Torn API key;
- Standard / Airstrip / WLT;
- travel company + star rating;
- faction Excursion capacity;
- faction Travel Cost;
- derived travel-perk preview;
- settings-only Business when free Business Class is established;
- hidden asynchronous update after explicit Save;
- ignored `settings-error.txt` diagnostics.

The Excursion-label overlap artifact has been fixed.

## Travel-profile economics

Implemented and already target-tested:

- Lingerie 3-star +2 capacity, 10-star free Business;
- Cruise Line +2 at 3-star and +3 more at 10-star;
- Flower/Toy item-specific capacity does not increase Xanax capacity;
- faction Excursion +1 per level to 10;
- faction Travel Cost -15% per level to 5;
- unknown ticket-funded Business economics remain suppressed.

`Run-TravelProfileTests.ps1` and profile-integrated `Run-FinalizeStateTests.ps1` passed previously.

## Torn profile sync

A redacted local probe using the saved API key successfully reached:

- `/user/basic`;
- `/user/job`;
- `/user/perks`;
- `/faction/upgrades`.

Current probed state:

```text
Job: Education starter job / Substitute Teacher
Travel company: none
Company stars: 0
Faction Travel capacity: 0
Faction Travel cost: 0
```

`Sync from Torn` is implemented as **populate-only**: it changes the form controls but does not persist until Save. Unknown company types are left unresolved rather than guessed.

Target-Windows tests already passed on `2367874fedea5f9beea215baea4265e92e7c39d4`:

- `Validate-TravelAssistant.ps1`;
- `Run-TornProfileSyncTests.ps1` including starter job, known/unknown company mappings, rating preservation, and faction travel upgrade parsing.

## Immediate remaining validation

Do not add more code unless one of these checks fails.

1. Reopen Settings from Rainmeter and confirm the Excursion control no longer has the label-overlap artifact.
2. Click **Sync from Torn**. Expected current values:
   - Company: `None / Other`
   - Company stars: `0`
   - Faction Excursion: `0`
   - Faction Travel Cost: `0`
   The sync status should identify the Education starter-job result.
3. Confirm Sync does **not** save by itself: Cancel/reopen should retain the previously saved values.
4. Manually choose Lingerie Store + 10 stars and confirm Business appears; switch back to an unqualified profile and confirm Business disappears.
5. Click Save and confirm the dialog closes promptly and the hidden update applies the selected mode/profile.
6. Allow a normal automatic poll afterward and confirm Prometheus/freshness remains healthy.
7. Check for any new material Rainmeter/PowerShell errors or persistent background processes only if behavior suggests a regression.

## Completion criteria

Mark **COMPLETED** only when the live Settings sync/save/Business-gating checks above pass and the next normal automatic poll remains healthy.
