# Next Codex Run: Travel Assistant Settings / Travel-Profile Validation

**Status: ACTIVE**

This is the authoritative current execution handoff for `RainMeter Projects/Travel Assistant/`. Work remains **connector-first**; use the target Windows/Rainmeter environment only for behavior that cannot be established from the repository.

## Stable baseline already validated

Do **not** restart the project or repeat earlier debugging.

Before the Settings extension, target-machine evidence had already established:

- deterministic model/history/finalizer tests passed on the earlier validated implementation;
- bounded YATA live validation passed;
- Rainmeter junction installation passed;
- UK/Japan panels and equal-width graphs rendered;
- encoding/mojibake issues were fixed;
- local Torn API key worked against Torn v2 Item Market;
- the target machine required bounded `curl.exe` for Torn because Windows PowerShell `Invoke-RestMethod` hung specifically against `api.torn.com`;
- production updater/finalizer exited `0` and consumed a fresh `torn_itemmarket` resale cache;
- Rainmeter automatic one-minute polling was fixed and verified;
- heartbeat/stale-update UI was verified;
- Japan observed sellout history persisted;
- a real UK restock then sellout transition was observed and recorded;
- the corrected RunCommand configuration produced no new material Rainmeter log errors;
- no persistent Travel Assistant PowerShell process was present between polls;
- runtime/generated data remained only a few KiB with no graph-file accumulation.

Those are retained acceptance results. Do not wait for or manufacture additional stock cycles.

## New user-requested extension

The user reported that the old main-skin travel-mode click took roughly 3–5 seconds. That was expected from the old implementation because a mode click invoked the full network/updater/finalizer pipeline, but it is not desirable UI behavior.

The new design therefore:

- replaces the top-right mode cycler with **SETTINGS**;
- moves travel-mode selection into a short-lived local Windows Forms dialog;
- lets the user enter/edit the Torn API key there (masked by default);
- adds travel-related company + star-rating inputs;
- adds faction Excursion capacity and Travel Cost inputs;
- previews derived travel effects;
- saves only ignored local configuration/preferences;
- leaves the proven minute-scale polling/history path unchanged.

## Travel-profile economics implemented

Committed `config/travel-perks.json` models:

- Lingerie Store: 3-star +2 general travel capacity; 10-star free Business Class;
- Cruise Line: 3-star +2 general capacity; 7-star stock-analysis information; 10-star +3 additional capacity;
- Flower Shop: 7-star +5 **flowers only**; 10-star stock-analysis information;
- Toy Shop: 7-star +5 **plushies only**; 10-star stock-analysis information;
- Logistics Management: hospitalized return-to-Torn informational effect;
- Theater: hidden traveling status/destination informational effect;
- Faction Excursion capacity: +1 per level through 10;
- Faction Travel Cost: -15% fees per level through 5 / -75%.

`TravelProfile.ps1` derives the effective profile. `FinalizeState.ps1` applies it only to final capacity/cost economics; observed history remains unchanged.

A positive manual `capacityOverride` remains authoritative. Otherwise usable capacity is base mode capacity plus qualifying company/item/faction capacity.

Flower/Toy item-specific capacity must **not** increase Xanax capacity.

## Business safety branch

Business is now `settingsOnly` rather than a normal mode.

It appears in Settings only when free Business Class is established by the local profile (currently modeled as 10-star Lingerie Store).

- Qualified free Business: travel cost is explicitly known as `$0` and normal final economics apply.
- Ticket-funded or manually forced unqualified Business: economics remain unresolved, timing is suppressed, and unknown cost is never treated as zero.

## Repository changes in this extension

Key files:

```text
TravelAssistant.ini
config/travel-modes.json
config/travel-perks.json
config/settings.example.json
config/settings.local.example.json
@Resources/Scripts/OpenSettings.ps1
@Resources/Scripts/TravelProfile.ps1
@Resources/Scripts/FinalizeState.ps1
tests/Validate-RainmeterSkin.ps1
tests/Validate-TravelAssistant.ps1
tests/Run-TravelProfileTests.ps1
tests/Run-FinalizeStateTests.ps1
tests/Run-All.ps1
```

The local user's existing ignored `config/settings.local.json` must not be overwritten.

## Immediate target-Windows validation

Because this is a functional source/config change, validate the changed boundary before calling it complete. Start with the narrow checks rather than rerunning unrelated provider/history probes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelAssistant.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelProfileTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FinalizeStateTests.ps1
```

If those pass, refresh Rainmeter and validate the new UI:

1. Top-right control says `SETTINGS >` rather than cycling the mode.
2. Clicking it opens the local Settings window without a long-running background process.
3. Existing API key is present but masked by default; do not expose it in screenshots/logs/chat.
4. Normal mode choices are Standard / Airstrip / WLT.
5. Company choices include Lingerie, Cruise, Flower, Toy, Logistics, Theater, plus None/Other.
6. Star rating is editable from 0–10.
7. Faction Excursion capacity level is editable 0–10.
8. Faction Travel Cost level is editable 0–5.
9. Business is absent for an unqualified profile.
10. Selecting Lingerie Store at 10 stars makes Business available and previewed as free.
11. Flower/Toy profile does not show a Xanax-specific capacity increase.
12. Save completes promptly and closes; the next normal poll applies the selected mode/profile.
13. Existing YATA/Torn polling, heartbeat, graphs, sellout history, and conservative status behavior remain intact.
14. No new material Rainmeter/PowerShell errors appear.

Do not paste or log the API key.

## Optional future work, not required for this pass

The Torn API exposes suitable user/faction data areas that may support a later **Sync from Torn** button for automatic company/perk detection. Do not implement automatic detection by guessing response fields or requiring broader key authority. Validate endpoint response contracts and permissions first; manual local inputs are the safe current contract.

## Completion criteria

Mark this run `COMPLETED` only after:

- the four narrow PowerShell validations pass on the target machine;
- the Settings dialog actually opens from Rainmeter;
- local save/mode/profile behavior is observed;
- 10-star Lingerie Business gating behaves as designed;
- a subsequent automatic poll remains healthy;
- no new material errors/resource regressions appear.

If a defect appears, fix only the narrow affected layer and preserve all prior validated polling/history behavior.
