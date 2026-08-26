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

Earlier runtime errors showed Windows sharing/replacement failures on `state.kv`. The current atomic writer now retries wrapped sharing violations, but a subsequent live probe still showed the generated state and heartbeat more than an hour behind the collection clocks.

The next diagnostic step is to identify the process holding `@Resources/Generated/state.kv` open rather than increasing retry duration further.

Use:

```powershell
.\tools\Find-FileLock.ps1
```

or include the heartbeat file:

```powershell
.\tools\Find-FileLock.ps1 -IncludeHeartbeat
```

The tool uses the Windows Restart Manager API and is read-only; it does not terminate any process or modify the files.

## Reader audit

The primary Rainmeter Lua readers inspected so far (`StateReader.lua` and `CardPresenter.lua`) explicitly close their `io.open(...)` handles after reading. This reduces the likelihood of a simple leaked Lua handle and raises the possibility of a sharing-mode incompatibility or another process such as Rainmeter, synchronization/indexing software, antivirus, or a separate PowerShell worker.

If the lock owner is Rainmeter and the lock is recurrent rather than leaked, the preferred architectural fix is to stop replacing the same pathname that Rainmeter reads continuously. A generation/immutable-publication scheme should then be used instead of progressively longer retries.
