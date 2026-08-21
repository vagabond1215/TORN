# Windows / Rainmeter Validation

This checklist covers target-machine behavior that connector-only work cannot prove: Windows PowerShell, Rainmeter, local credentials/settings, UI interaction, filesystem writes, and resource behavior.

## Preconditions

- Windows PowerShell 5.1 or compatible.
- Rainmeter installed.
- Repository cloned at:

```text
C:\Codex\TORN\RainMeter Projects\Travel Assistant\
```

Synchronize safely:

```powershell
cd C:\Codex\TORN
git pull --ff-only origin main
git status -sb
```

Do not reset/rebase/force-push to manufacture a clean result.

## Previously validated baseline

The target machine has already demonstrated:

- installation/junction creation;
- YATA live stock/foreign-price requests;
- Torn Item Market access through a local API key and bounded `curl.exe` transport;
- production updater/finalizer exit 0;
- UK/Japan rendering and generated graphs;
- automatic one-minute Rainmeter polling;
- heartbeat/stale-update display;
- observed sellout persistence and a real UK restock/sellout transition;
- clean post-fix Rainmeter log;
- no persistent Travel Assistant PowerShell process between polls;
- bounded runtime/generated storage.

Do not repeat the old broad live-provider investigation unless a new defect specifically points there.

## Settings / travel-profile extension: deterministic checks

For the current extension, run the changed-boundary checks first:

```powershell
cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelAssistant.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelProfileTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FinalizeStateTests.ps1
```

Expected: all four exit 0.

These specifically cover:

- Settings/profile config and script syntax;
- ignored local credential path;
- correct Rainmeter RunCommand declaration and Settings action structure;
- Lingerie/Cruise/faction capacity math;
- Flower/Toy not increasing Xanax capacity;
- faction fee reduction;
- unqualified Business remaining unresolved;
- 10-star Lingerie establishing known free Business economics;
- final timing suppression/preservation rules.

If one fails, stop and capture that test's full output before running broader suites.

## Settings UI validation

Refresh Rainmeter after pulling current main. The installed skin is a junction, so no reinstall is normally required.

Confirm the top-right main-skin control is:

```text
SETTINGS >
```

Click it and verify a short-lived **Travel Assistant Settings** window opens.

### API key

Confirm:

- existing local key is preserved;
- it is masked by default;
- Show toggles visibility;
- no key appears in the Rainmeter action text, log, or console output;
- never paste the key into validation notes/chat.

### Travel mode

For an ordinary profile, Settings should offer:

```text
Standard
Airstrip
WLT
```

Airstrip remains the default for a clean local profile.

The old main-skin mode cycler should be absent.

### Company / stars

Confirm the company list includes:

```text
None / Other
Lingerie Store
Cruise Line
Flower Shop
Toy Shop
Logistics Management
Theater
```

Confirm company stars accept 0–10.

Expected profile behavior:

- Lingerie 3-star: preview shows +2 general capacity.
- Lingerie below 10-star: Business absent/locked.
- Lingerie 10-star: Business appears and preview says free/available.
- Cruise 10-star: preview derives +5 general capacity (+2 +3).
- Flower/Toy: Xanax-specific capacity remains 0.

### Faction

Confirm:

- Excursion capacity level accepts 0–10 and preview reflects +1 capacity per level.
- Travel Cost level accepts 0–5 and preview reflects -15% per level through -75%.

### Save behavior

Change a harmless setting, click Save, and confirm:

- dialog saves/closes promptly;
- no full updater/network wait blocks the click;
- ignored `config/settings.local.json` remains valid JSON;
- `data/runtime/preferences.json` records the selected travel mode;
- the next normal one-minute poll applies the selected mode/profile to generated state;
- normal polling/heartbeat continues afterward.

Do not delete or replace the user's existing API key while testing.

## Business guard validation

Normal path:

1. Choose a non-Lingerie profile or Lingerie below 10-star.
2. Business must not be selectable in Settings.

Qualified path:

1. Choose Lingerie Store.
2. Set stars to 10.
3. Business becomes selectable.
4. Save Business.
5. After the next poll, generated economics should treat Business travel cost as known zero and use base Business capacity plus qualifying general/faction capacity.

After testing, return to the user's desired normal profile/mode.

Do not test ticket-funded Business by assuming a ticket value of zero. That branch remains unresolved.

## Polling / UI regression check

After saving Settings, leave the skin alone through at least one full countdown.

Confirm:

- header update time advances;
- countdown resets;
- `state.kv` and `last-update.txt` advance without manual PowerShell;
- UK/Japan graphs remain rendered;
- actual `Last Sold Out` history remains present;
- sparse-history states still do not invent timing;
- no new mojibake appears.

## Log check

Open **Rainmeter → About → Log** after opening/saving Settings and after a subsequent automatic poll.

No new material entries should appear for:

- Travel Assistant Lua errors;
- RunCommand errors/timeouts;
- missing script/image/file errors;
- unsupported options;
- repeated PowerShell failures;
- updater/finalizer errors.

Historical log entries from already-fixed builds do not count as current defects if no new errors appear after the current refresh timestamp.

## Resource/storage sanity

While Settings is closed and the skin is idle between polls:

```powershell
Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -eq 'powershell.exe' -and
    $_.CommandLine -like '*Travel Assistant*'
  } |
  Select-Object ProcessId, Name, CommandLine

Get-ChildItem .\data\runtime, .\@Resources\Generated -File -Recurse |
  Measure-Object Length -Sum |
  Select-Object Count, Sum

Get-ChildItem .\@Resources\Generated -File |
  Select-Object Name, Length, LastWriteTime
```

Expected:

- no persistent Travel Assistant PowerShell process while Settings is closed and updater is idle;
- only small bounded runtime/generated state;
- generated files update in place rather than accumulating graph images;
- Rainmeter remains responsive.

A PowerShell process is expected **while the Settings window itself is open** because the dialog is intentionally hosted by a short-lived local PowerShell/WinForms process.

## Completion

The Settings/travel-profile extension can be marked operationally validated only after:

- the four narrow tests pass;
- the Settings window opens from Rainmeter;
- API/mode/company/faction fields render correctly;
- save/poll behavior works;
- Business gating is observed;
- post-change log/resource checks are clean.

Automatic future company/faction detection from Torn API data is separate follow-up work and is not required for this validation pass.
