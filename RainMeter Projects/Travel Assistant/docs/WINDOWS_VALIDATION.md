# Windows / Rainmeter Validation

This checklist covers target-machine behavior that connector-only work cannot prove: Windows PowerShell 5.1, Rainmeter rendering, local settings, UI interaction, filesystem writes, and runtime timing.

## Preconditions

- Windows PowerShell 5.1 or compatible.
- Rainmeter installed.
- Repository cloned at approximately:

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

## Focused acceptance

Run:

```powershell
cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1
```

Stop at the first failure and capture only that failure block plus the runtime log tail when relevant.

The focused suite covers parser/static architecture plus deterministic travel context, route economics, opportunity ordering, PowerShell 5.1 collection compatibility, observation-history retention, resale priority and final-state behavior.

## One production update

After the focused suite is green:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update

Select-String .\@Resources\Generated\state.kv `
  -Pattern '^Opportunity(Count|Message|SortMode|1(Key|Name|Country|ChanceText|TimeText|GrossText|QuantityText|ProfitHourText))='
```

At minimum, `OpportunityCount`, `OpportunityMessage`, and `OpportunitySortMode` must exist even when zero rows are currently eligible.

## Main Rainmeter surface

Refresh the skin and verify the visible sort row is exactly:

```text
[UPCOMING] [GROSS PROFIT] [PROFIT/HR]
```

There must be no visible `NAME`, `OPTIMAL`, Chance, or shortest-Time sort.

For visible opportunity rows verify:

- item and country are readable;
- gross trip profit is accompanied by modeled quantity (`xN`);
- window timing is present;
- leave timing is present;
- modeled hit likelihood is a separate percentage;
- total elapsed time is visible;
- foreign price and Torn MV are visible;
- `GRAPH` is clickable.

Hover the gross value and verify its tooltip explains approximately:

```text
unit spread × quantity = trip gross
```

`PROFIT/HR` must mean:

```text
after-tax trip net / configured round-trip flight hours
```

Hit likelihood must not be multiplied into that value.

## Poll stability

Leave the skin visible through at least two automatic polling cycles.

Confirm:

- opportunity rows do **not** disappear to `Learning opportunities...` for the duration of a poll;
- header update time advances;
- countdown resets normally;
- selected sort remains selected after refresh/poll;
- a click immediately changes the selected sort highlight;
- rows reorder after the local projection completes;
- buttons do not require repeated pixel-perfect clicking.

If the list still flashes blank during a poll, capture the approximate duration and whether it happened immediately after a manual Rainmeter Refresh or during an ordinary automatic poll.

## Filter controls

Verify:

- ITEM opens and is populated;
- country selector opens and is populated;
- CAT opens and is populated;
- SHORT / MED / LONG toggle reliably;
- RESET restores default filters;
- filter changes remain after the next automatic update.

## Settings

Click `SETTINGS >` and verify **Travel Assistant Settings** opens without a visible PowerShell console.

Settings must retain:

- profitable-only toggle;
- 95% MV toggle;
- Energy Waste policy / maximum loss;
- Nerve Waste policy / maximum loss;
- Ignore List;
- Profile / API.

The explanatory text should state that the main sorts are UPCOMING, GROSS PROFIT, and PROFIT/HR and that hit likelihood remains separate.

## Inline graph validation

Open one row's chart button.

Confirm:

- the chart button visibly highlights while expanded;
- the graph is embedded in that exact card and the lower rows reflow;
- graph identity follows the exact `country:itemId` market through local sorting;
- graph spans 8 hours with 60-minute markers;
- unchanged stock carries across the left edge when a retained predecessor exists;
- observed restock/sellout transitions are drawn when present;
- opening another chart collapses the prior one;
- graph rendering and hover telemetry perform no provider/Torn request.

Also open the `# Windows / Rainmeter Validation

This checklist covers target-machine behavior that connector-only work cannot prove: Windows PowerShell 5.1, Rainmeter rendering, local settings, UI interaction, filesystem writes, and runtime timing.

## Preconditions

- Windows PowerShell 5.1 or compatible.
- Rainmeter installed.
- Repository cloned at approximately:

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

## Focused acceptance

Run:

```powershell
cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1
```

Stop at the first failure and capture only that failure block plus the runtime log tail when relevant.

The focused suite covers parser/static architecture plus deterministic travel context, route economics, opportunity ordering, PowerShell 5.1 collection compatibility, observation-history retention, resale priority and final-state behavior.

## One production update

After the focused suite is green:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update

Select-String .\@Resources\Generated\state.kv `
  -Pattern '^Opportunity(Count|Message|SortMode|1(Key|Name|Country|ChanceText|TimeText|GrossText|QuantityText|ProfitHourText))='
```

At minimum, `OpportunityCount`, `OpportunityMessage`, and `OpportunitySortMode` must exist even when zero rows are currently eligible.

## Main Rainmeter surface

Refresh the skin and verify the visible sort row is exactly:

```text
[UPCOMING] [GROSS PROFIT] [PROFIT/HR]
```

There must be no visible `NAME`, `OPTIMAL`, Chance, or shortest-Time sort.

For visible opportunity rows verify:

- item and country are readable;
- gross trip profit is accompanied by modeled quantity (`xN`);
- window timing is present;
- leave timing is present;
- modeled hit likelihood is a separate percentage;
- total elapsed time is visible;
- foreign price and Torn MV are visible;
- `GRAPH` is clickable.

Hover the gross value and verify its tooltip explains approximately:

```text
unit spread × quantity = trip gross
```

`PROFIT/HR` must mean:

```text
after-tax trip net / configured round-trip flight hours
```

Hit likelihood must not be multiplied into that value.

## Poll stability

Leave the skin visible through at least two automatic polling cycles.

Confirm:

- opportunity rows do **not** disappear to `Learning opportunities...` for the duration of a poll;
- header update time advances;
- countdown resets normally;
- selected sort remains selected after refresh/poll;
- a click immediately changes the selected sort highlight;
- rows reorder after the local projection completes;
- buttons do not require repeated pixel-perfect clicking.

If the list still flashes blank during a poll, capture the approximate duration and whether it happened immediately after a manual Rainmeter Refresh or during an ordinary automatic poll.

## Filter controls

Verify:

- ITEM opens and is populated;
- country selector opens and is populated;
- CAT opens and is populated;
- SHORT / MED / LONG toggle reliably;
- RESET restores default filters;
- filter changes remain after the next automatic update.

## Settings

Click `SETTINGS >` and verify **Travel Assistant Settings** opens without a visible PowerShell console.

Settings must retain:

- profitable-only toggle;
- 95% MV toggle;
- Energy Waste policy / maximum loss;
- Nerve Waste policy / maximum loss;
- Ignore List;
- Profile / API.

The explanatory text should state that the main sorts are UPCOMING, GROSS PROFIT, and PROFIT/HR and that hit likelihood remains separate.

## Inline graph validation

Open one row's chart button.

Confirm:

- the chart button visibly highlights while expanded;
- the graph is embedded in that exact card and the lower rows reflow;
- graph identity follows the exact `country:itemId` market through local sorting;
- graph spans 8 hours with 60-minute markers;
- unchanged stock carries across the left edge when a retained predecessor exists;
- observed restock/sellout transitions are drawn when present;
- opening another chart collapses the prior one;
- graph rendering and hover telemetry perform no provider/Torn request.

 button and verify the fixed two-row economics strip appears above the card body. MV is top-left; top-right shows `$/hr` under UPCOMING/PROFIT and Net under PROFIT/HR. Unit/total Price is bottom-left and Tax is bottom-right when nonzero. The large primary metric must swap in the opposite direction. Set Tax / trader rate to 0%, Save, and confirm Tax disappears without collapsing the second row.

The historical retention invariant is:

```text
48h high-resolution change-only history + one boundary baseline/market
90d completed cycles
8h display window
```

## Popup / process behavior

Settings, filters, Ignore List, and Profile/API should display only their WinForms window. The launcher console must remain hidden and close immediately after handing off to the hidden STA popup host.

While all popups are closed and the updater is idle:

```powershell
Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -eq 'powershell.exe' -and
    $_.CommandLine -like '*Travel Assistant*'
  } |
  Select-Object ProcessId, Name, CommandLine
```

Expected: no permanent Travel Assistant PowerShell process.

A PowerShell host is expected while an actual WinForms popup is open.

## Runtime log

All current component/popup failures should be available in:

```text
data\runtime\logs\travel-assistant.log
```

When something fails, collect:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 40
```

Do not paste API keys or full local settings.

## Completion

0.6 may be marked operationally accepted only after:

- `Run-CurrentAcceptance.ps1` is green;
- one production update writes a valid opportunity projection;
- the three sorts work and persist;
- the list remains visible through ordinary polling;
- Settings/filters actions work without visible console windows; inline graph expansion remains local inside Rainmeter;
- gross quantity arithmetic is clear;
- 8-hour inline graph behavior is correct;
- current runtime log is clean after successful operations;
- a final Rainmeter screenshot passes layout review.

Browser notifications remain a separate follow-up after this acceptance boundary.
