# Distribution and Runtime Lifecycle

## Preferred distribution format

Use a Rainmeter `.rmskin` package for normal end users.

The recipient experience is:

1. install Rainmeter;
2. double-click `Travel Assistant-<version>.rmskin`;
3. click Install;
4. the package loads `Travel Assistant\TravelAssistant.ini`;
5. open `SETTINGS` and enter that user's own Torn API key if they want profitability/metadata features.

The package must never contain the developer's local `config/settings.local.json` or ignored runtime state.

## Secure package builder

`Build-Rmskin.ps1` creates a whitelist-based staging tree rather than copying the project directory wholesale.

The staged package contains only runtime-required committed source/config/seed files. It excludes:

- `config/settings.local.json`;
- `config/secrets.json`;
- `.env` files;
- `data/runtime/`;
- `@Resources/Generated/`;
- `@Resources/Cache/`;
- logs, local error files, generated graphs/state, and accumulated local history.

If the current local settings contain a Torn API key, the builder also scans staged text and stops if that exact key value appears anywhere in the package.

The committed `config/settings.local.example.json` must keep `tornApiKey` blank.

Package updates use:

```text
MergeSkins=1
```

so an existing recipient's un-packaged local settings can remain in place when a newer package is installed.

### Build staging only

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Build-Rmskin.ps1 -StageOnly
```

This creates ignored local staging under `dist\_rmskin-stage` and runs the package-safety checks without requiring any third-party packager.

### Build the `.rmskin`

The repository does not vendor a package-builder binary. Install the optional `rmskin-builder` CLI once on the development machine:

```powershell
py -m pip install --user rmskin-builder
```

Then:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Build-Rmskin.ps1
```

The `.rmskin` is emitted to ignored `dist\` output. Recipients do not need Python or the builder; they receive only the generated `.rmskin` file.

Focused validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-Distribution.ps1
```

## API-key behavior for recipients

A package recipient does not receive the developer's API key.

Without a local key:

- public Prometheus/YATA foreign-stock collection can still run;
- local observations/cycles can still accumulate;
- profitability-gated recommendations that require Torn resale data remain unavailable/conservative;
- Torn canonical item metadata enrichment remains unavailable until the recipient supplies a key.

After the recipient saves their own key in Settings, it is written only to that installation's local `config/settings.local.json`.

## Runtime lifecycle

Travel Assistant is not a Windows service and does not install a permanent background process.

The update scheduler lives inside the loaded Rainmeter skin:

```text
TravelAssistant.ini loaded
        ↓
StateReader.lua updates locally each second
        ↓
MeasureUpdate launches RunUpdate.ps1 about once/minute
        ↓
primary updater
shadow collector (internally throttled to ~120s)
metadata enrichment (internally throttled to ~6h)
finalizer
heartbeat
```

Therefore:

- **Rainmeter closed:** no collection.
- **Rainmeter open, Travel Assistant unloaded:** no collection.
- **Rainmeter open, Travel Assistant loaded:** collection runs on its configured schedule.
- **Skin refreshed:** an immediate updater run is requested, then normal scheduling resumes.
- **PC asleep/off:** no collection during that interval.
- **Rainmeter Game Mode or another action unloads the skin:** collection stops until the skin is loaded again.

The skin does not keep a permanent PowerShell process alive between polls. Each updater execution is short-lived and serialized.

## Future always-on option

If continuous collection while the skin is unloaded becomes important, implement it as a separate explicit Windows Scheduled Task or service mode rather than silently changing the Rainmeter lifecycle.

That mode should reuse the same collector/locking/state files and remain opt-in because it changes the resource and privacy expectations of the application.
