# Windows / Rainmeter Validation

This is the smallest local pass required before Travel Assistant v1 can be called operationally validated.

Connector-only work can inspect/write the repository and create deterministic fixtures, but it cannot prove that the user's installed Rainmeter, Windows PowerShell, `System.Drawing`, filesystem junctions, or live provider calls behave correctly on the target PC.

## Preconditions

- Windows PowerShell 5.1 or compatible PowerShell capable of running the repository scripts.
- Rainmeter installed.
- Repository cloned at the expected source path:

```text
C:\Codex\TORN\RainMeter Projects\Travel Assistant\
```

- Local repository synchronized with current `origin/main` without discarding unrelated work.

From `C:\Codex\TORN`:

```powershell
git fetch origin
git switch main
git pull --ff-only origin main
git status -sb
```

Do not reset/rebase/force-push merely to make the validation pass clean.

## 1. Deterministic/static suite

From the Travel Assistant directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

This must complete successfully before trusting a live recommendation.

The suite currently covers:

- project/config/schema validation;
- travel-mode/economics configuration;
- historical-tool parser/seed checks;
- normalized observation -> completed-cycle replay;
- isolated seed-import/dedup/provenance behavior;
- production-function YATA normalization;
- production safe-window/best-odds behavior;
- stale stock-data suppression;
- fee-adjusted low-margin/unprofitable suppression;
- travel-mode timing changes;
- live depletion shortening/closing historical safety;
- final-state resale-cache freshness suppression;
- final-state Standard travel cost/base-capacity trip-profit gating;
- zero-cost Airstrip preservation of a healthy timing recommendation;
- independent restock display while an opportunity is low-margin;
- unresolved Business economics suppressing timing if Business is manually forced.

If this fails, stop and preserve the complete console output.

## 2. Local settings / Torn key

`Install.ps1` creates ignored `config/settings.local.json` from the example if it does not already exist.

For full profitability validation, put a suitable local Torn API key in that ignored file or define `TORN_API_KEY` in the environment.

Do **not** paste a limited/full-authority key into an issue, chat log, committed file, diagnostic report, or screenshot.

The live YATA stock collection itself does not need a Torn key.

Useful optional local profitability fields include:

```json
{
  "profitability": {
    "minimumTotalTripProfit": 0,
    "capacityOverride": 0,
    "resaleStaleAfterSeconds": 600
  }
}
```

`capacityOverride = 0` means use the conservative configured base capacity. If the user knows their actual travel capacity, a positive override makes the trip-level profitability gate use that value instead.

## 3. Bounded live environment pass

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-LiveEnvironment.ps1
```

This intentionally performs a small bounded amount of work:

- the deterministic/static suite;
- one YATA live request;
- one Torn Item Market request when a key is configured;
- one serialized production updater + final-state guard pass;
- runtime/generated disk-size comparison;
- Rainmeter installation-path check;
- whole-Rainmeter-process memory observation when Rainmeter is already running.

It is **not** a polling/stress loop.

Record:

- YATA success/failure;
- Torn Item Market success/failure or intentional skip;
- updater/finalizer exit code and elapsed time;
- runtime/generated directory size before/after;
- any PowerShell exceptions.

## 4. Install the development skin

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Expected behavior:

- local runtime/generated directories exist;
- local settings template exists if previously absent;
- `Documents\Rainmeter\Skins\Travel Assistant` becomes a junction to the repository source;
- an unrelated existing Travel Assistant directory is **not** overwritten.

Then refresh Rainmeter and load:

```text
Travel Assistant\TravelAssistant.ini
```

## 5. Visual / interaction checks

Verify all of the following:

- dark charcoal panel is distinguishable from a pure-black desktop;
- UK appears above Japan;
- graph widths/alignment match;
- each destination shows the inline pairs:
  - `Travel | Leave / Window`
  - `Restock | Last Sold Out`
  - `Stock | Foreign Price`
- `Last Sold Out` is blank/unknown until an actual historical sellout exists; it must not show a predicted sellout;
- graphs render instead of showing broken-image placeholders;
- low-confidence/stale/check-external overlays remain readable;
- clicking timing/status opens Weav3r Travel Stock;
- mode click cycles only through currently enabled `Standard -> Airstrip -> WLT` modes;
- Airstrip remains the default on a clean local preference state;
- Business is not offered yet, by design, until Business Class Ticket/free-company travel economics are represented safely.

## 6. Live-value checks

With the skin running for several minutes:

- confirm UK/Japan current stock changes plausibly with the live source;
- confirm foreign purchase price is present when supplied by YATA;
- confirm the source does not become stale merely because Rainmeter's one-second UI refresh is faster than the provider polling cadence;
- when local history is insufficient, confirm the skin shows learning/check-external behavior rather than inventing a departure window;
- if a valid Torn key is configured, confirm low-margin/unprofitable states suppress **departure timing** while stock and actual/estimated restock information remain available;
- if an actual restock is observed while the skin is running, confirm the Restock field changes to an elapsed live-restock display such as `live +04:12` rather than treating that observed timestamp as a future estimate;
- confirm an old cached resale value cannot keep a safe/best-odds countdown active after `resaleStaleAfterSeconds` is exceeded.

Do not wait for or manufacture a restock/sellout just to finish validation. Actual-cycle behavior can remain a shadow-mode/live-observation follow-up.

## 7. Rainmeter log

Open Rainmeter's log/diagnostic view after loading/refreshing the skin and check for:

- Lua errors;
- RunCommand errors/timeouts;
- missing file/image errors;
- unsupported meter/measure options;
- repeated PowerShell launch failures;
- errors from `UpdateTracker.ps1` or `FinalizeState.ps1`.

If there is a defect, capture the relevant log lines and the output of the failing repository validation command. Do not include API keys.

## 8. Resource sanity check

Travel Assistant is intentionally designed so the one-second path does not spawn PowerShell or access the network. During normal idle operation, the short-lived updater/finalizer should appear only around the configured minute-scale poll.

Check for:

- no permanently running browser spawned by the skin;
- no continuously running Travel Assistant PowerShell process;
- `data/runtime/` and `@Resources/Generated/` remain small;
- generated graphs remain two small PNG files rather than an accumulating image archive;
- Rainmeter responsiveness remains normal.

`Validate-LiveEnvironment.ps1` reports whole-Rainmeter working-set memory if available, but that is **not** Travel Assistant-only memory attribution. A longer sampling profiler can be added only if the first pass indicates a resource problem.

## 9. Optional history inspection

After enough actual completed cycles exist:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Analyze-History.ps1
```

This is descriptive only. It can show whether price bands or UTC-hour cohorts have enough evidence to justify later production-model refinements.

## 10. Validation record

Do not mark `docs/NEXT_CODEX_RUN.md` **COMPLETED** from connector-side inspection alone.

After the local pass, record in `docs/IMPLEMENTATION_STATUS.md` / the active run:

- local commit SHA tested;
- deterministic test results;
- live provider results;
- Rainmeter rendering/log outcome;
- mode-cycle outcome;
- approximate disk/runtime observations;
- any defects found;
- anything still intentionally deferred.
