# Stale Publication Incident — 2026-08-26

This note records live Windows evidence gathered while the Travel Assistant UI remained stale and the publication architecture adopted from that evidence.

## Confirmed clock split

An early `tools/Probe-LiveStockProviders.ps1` run reported approximately:

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

Earlier runtime errors showed Windows sharing/replacement failures on `state.kv`. The atomic writer retries wrapped sharing violations, but repeated live probes still showed generated state and heartbeat lagging behind collection.

## Confirmed lock owner

Repeated Windows Restart Manager sampling caught a process holding `@Resources/Generated/state.kv` open:

```text
ProcessName     : powershell
ParentName      : Rainmeter.exe
CommandLine     : powershell.exe -NoProfile -ExecutionPolicy Bypass -File "...\Travel Assistant\@Resources\Scripts\RunUpdate.ps1" -Action Update
ApplicationType : RmConsole
```

The lock was transient rather than persistent: it appeared in one sample and disappeared in subsequent 250 ms samples. `last-update.txt` did not show the same lock owner.

The shared atomic helper was subsequently hardened so updater-owned state reads use:

```text
FileShare.ReadWrite | FileShare.Delete
```

`ProjectCollectedState.ps1` and `FinalizeState.ps1` adopted those shared readers, and runtime validation covered both delete-sharing readers and a temporary external lock that denies delete sharing.

## PowerShell runtime A/B

With Rainmeter unloaded, running the entire update manually under PowerShell 7.6.5 produced a healthy one-shot result:

```text
engine collection          38s
engine freshest source     40s
state.kv freshest source   40s
UI heartbeat               10s
```

This justified a controlled migration of only Rainmeter's main `[MeasureUpdate]` process to `pwsh.exe`. Popup, filter, Viewer, inline-graph and preference helper measures remained on Windows PowerShell 5.1.

That runtime migration improved the isolated test but did **not** solve normal Rainmeter publication. With Rainmeter active, a later production sample showed:

```text
engine collection          30s
engine freshest source     30s
state.kv freshest source   3m
UI heartbeat               2m
```

and the runtime error again contained:

```text
System.Management.Automation.MethodInvocationException
Exception calling "Replace" with "3" argument(s):
"The process cannot access the file because it is being used by another process."
```

Therefore the incident crossed the decision boundary established for this investigation: do not keep increasing `File.Replace` retry duration and do not treat PowerShell 5.1 as the sole remaining cause.

## Structural publication redesign

The generated-state roles are now separated:

```text
@Resources/Generated/state.kv                    = private/build state
@Resources/Generated/ui-state-<epoch>-<id>.kv    = immutable finalized state
@Resources/Generated/last-update.txt              = heartbeat + active-generation manifest
@Resources/Generated/ui-state.kv                  = legacy startup fallback
```

Intermediate PowerShell stages continue to mutate `state.kv` sequentially during the update chain. Rainmeter no longer reads that hot pathname.

After `FilterState.ps1` completes, `RunUpdate.ps1` validates that the build state contains the expected opportunity and UI freshness projection, writes one new immutable generation at a unique pathname, and then atomically switches `last-update.txt` to `epoch|generation`. Rainmeter readers cache the complete named generation until that small manifest changes.

This changes the failure mode intentionally:

- a failed intermediate or final publication cannot expose a partially-mutated generation to Rainmeter;
- the previous complete immutable generation remains cached and visible;
- the heartbeat cannot claim freshness unless final UI publication succeeded;
- the frequently-mutated build pathname is no longer also the continuously-read UI pathname.

The existing bounded atomic writer is retained only for the tiny manifest switch. The large state artifact is never replaced while Rainmeter is reading it, and the retry window was **not** lengthened.

`AtomicFile.ps1` also retains an optional `TORN_TRAVEL_STATE_KV` build-path override for controlled tests or later private-generation routing, while the default build artifact remains `state.kv`.

## Validation

After pulling the redesign:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1

pwsh.exe -NoProfile -File .\tools\Probe-LiveStockProviders.ps1
```

The probe now distinguishes both build and UI clocks:

```text
engine collection
engine freshest source
build state freshest source
UI state freshest source
UI heartbeat
```

For normal Rainmeter operation, the expected steady-state relationship is that build and UI state continue advancing across repeated polling cycles, with UI state/heartbeat usually no more than roughly one completed update behind the newest collection while a new cycle is in flight.

The immutable-generation/manifest design is the escalation triggered by repeated live `ui-state.kv` sharing violations. Do not regress to replacing the hot Rainmeter pathname or extending replacement retry duration.
