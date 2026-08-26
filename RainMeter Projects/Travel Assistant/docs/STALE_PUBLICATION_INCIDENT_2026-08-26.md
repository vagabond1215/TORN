# Stale Publication Incident — 2026-08-26

This note records live Windows evidence gathered while the Travel Assistant UI remained stale.

## Confirmed clock split

A local `tools/Probe-LiveStockProviders.ps1` run reported approximately:

```text
engine collection          1m
engine freshest source     1m
state.kv freshest source   1h 24m
UI heartbeat               1h 24m
```

At the same time the structured providers were healthy for all collected countries:

- Prometheus: HTTP/JSON OK, country source ages roughly seconds to one minute.
- YATA: HTTP/JSON OK, country source ages roughly seconds to one minute.
- DroqsDB public export probe: HTTP 530 from this host.
- Weav3r `/api/marketplace`: JSON OK, but this endpoint is Torn-side market/catalog pricing and is not a verified overseas-stock quantity interface.

## Conclusion

This incident is not a Prometheus/YATA acquisition outage. Fresh provider data is reaching `engine-state.json`; generated UI publication is failing afterward.

Earlier runtime errors showed Windows sharing/replacement failures on `state.kv`. The current atomic writer retries wrapped sharing violations, but a subsequent live probe still showed the generated state and heartbeat more than an hour behind the collection clocks.

## Confirmed lock owner

Repeated Windows Restart Manager sampling caught the process holding `@Resources/Generated/state.kv` open:

```text
ProcessName     : powershell
ParentName      : Rainmeter.exe
CommandLine     : powershell.exe -NoProfile -ExecutionPolicy Bypass -File "...\Travel Assistant\@Resources\Scripts\RunUpdate.ps1" -Action Update
ApplicationType : RmConsole
```

The lock was transient rather than persistent: it appeared in one sample and disappeared in subsequent 250 ms samples. `last-update.txt` did not show the same lock owner.

This is important because it rules out a persistent Rainmeter Lua file-handle leak as the immediate owner in the captured incident. The process reading `state.kv` was the Rainmeter-launched Windows PowerShell updater itself.

## Root-cause correction

`File.Replace` requires delete/rename sharing on the destination. A PowerShell read handle that allows ordinary read/write sharing but omits `FileShare.Delete` can therefore block a later atomic replacement even when the read is legitimate and short-lived.

The shared atomic helper now exposes explicit state readers that open with:

```text
FileShare.ReadWrite | FileShare.Delete
```

The two stages that were directly observed failing in the supplied runtime archive now use that reader before publishing state:

```text
ProjectCollectedState.ps1
FinalizeState.ps1
```

They continue to publish with unique temporary files, a per-destination mutex, and atomic `File.Replace`/`File.Move` semantics.

`tests/Validate-AtomicStateWrites.ps1` now includes two separate runtime contention cases:

1. an in-process `state.kv` reader deliberately left open with `ReadWrite|Delete`; atomic replacement must succeed while that reader is still open;
2. an external-style reader that deliberately denies delete sharing for ~800 ms; replacement must retry and succeed after the lock is released.

This distinguishes safe updater reads from genuine external sharing violations.

## Reader audit

The primary Rainmeter Lua readers inspected (`StateReader.lua` and `CardPresenter.lua`) explicitly close their `io.open(...)` handles after reading. The captured Restart Manager evidence also identified the updater rather than `Rainmeter.exe` as the process owning `state.kv` at the sampled failure point.

The repository still contains older state-mutating stages that use fixed `.tmp` + `Move-Item` publication patterns. Those should be migrated incrementally after the confirmed critical path is stable, but they are not being treated as the original provider-freshness failure.

## Immediate validation

After pulling the shared-reader fix:

```powershell
.\tests\Validate-AtomicStateWrites.ps1
.\@Resources\Scripts\RunUpdate.ps1 -Action Update
.\tools\Probe-LiveStockProviders.ps1
```

The desired clock result is:

```text
engine collection          <1m
engine freshest source     <1m
state.kv freshest source   <1m
UI heartbeat               <1m
```

If `state.kv` still fails to advance, inspect the newest compact error files and capture the lock owner again. At that point the next step is to identify the exact later state-mutating stage or move the update chain to a single working-generation publication model rather than extending replacement retry duration further.
