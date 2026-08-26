# Travel Assistant Data Gathering Findings

**Status:** immediate incident analysis and provider roadmap  
**Recorded:** 2026-08-25

## Executive finding

The observed long-stale / blank-card incident was **not primarily caused by the live stock provider failing to return data**.

The supplied runtime archive showed fresh Prometheus observations and a healthy `shadowCollection` state near the end of the archive, while the update pipeline repeatedly failed to publish generated state files.

The critical repeated errors were Windows file replacement failures similar to:

```text
System.IO.IOException: Cannot create a file when that file already exists.
... FileInfo.MoveTo(...)
... MoveFileInfoItem(...)
```

They appeared in both:

- `run-update-error.txt`;
- `collected-state-error.txt`.

The skin lives under a OneDrive-synchronized Rainmeter directory, while Rainmeter continuously reads generated state. Multiple scripts also publish the same state file. The previous pattern used a shared fixed temp filename followed by `Move-Item -Force`:

```text
state.kv.tmp -> state.kv
```

That is vulnerable to stale temp files, separate UI/action processes, transient sync/file locks, and Windows replacement semantics.

### Consequence

The failure chain was:

```text
fresh live provider response
    -> engine state updated
    -> collected-state projection fails to replace state.kv
    -> later finalizer also fails to replace state.kv
    -> RunUpdate aborts
    -> OpportunityState / WindowPlan / heartbeat do not complete
    -> Rainmeter keeps old generated state
    -> stale guard retries repeatedly
    -> UI appears to have stopped receiving stock
```

This is a **publication failure masquerading as a polling failure**.

## Immediate fix implemented

A shared helper now exists at:

```text
@Resources/Scripts/AtomicFile.ps1
```

It publishes generated files using:

- a unique sibling temp file for every write;
- a cross-process mutex derived from the destination path;
- `System.IO.File.Replace` when the destination exists;
- `System.IO.File.Move` when it does not;
- bounded retry/backoff for transient IO/access locks;
- cleanup of orphan unique temp files.

The two critical writers observed in the runtime failure have been migrated first:

```text
ProjectCollectedState.ps1
FinalizeState.ps1
```

Validation:

```text
tests/Validate-AtomicStateWrites.ps1
```

The validator is included in focused acceptance.

## Current live stock provider architecture

Current collector behavior is more advanced than the older provider-discovery documentation implied.

### Prometheus

Primary live provider:

```text
https://api.prombot.co.uk/api/travel
```

### YATA

Fallback live provider:

```text
https://yata.yt/api/v1/travel/export/
```

The collector evaluates freshness **per country**, not only once for the whole response. Prometheus can remain primary for a fresh country while YATA supplies another country whose Prometheus timestamp is stale/missing.

The default live acceptance threshold is currently five minutes. This threshold should remain strict for claims about **current stock**.

Historical cycles may continue to support forecast-only timing after live evidence ages, but stale `lastStock` must never be treated as current inventory.

## What the runtime archive says about the provider

Near the end of the supplied archive, `engine-state.json` reported:

```text
lastProvider = prometheus
countriesSeen = 11
marketsSeen = 232
lastError = empty
staleCountries = empty
```

and recent observations carried Prometheus source timestamps close to collection time.

Therefore a UI header that later says stock is tens of minutes old does **not** prove the provider had been stale for that duration. It may mean the latest successfully collected engine state was never published through the rest of the UI pipeline.

Future diagnostics should display these clocks separately:

```text
provider/source age
last successful collection age
last successful state publication age
last successful opportunity projection age
```

This prevents a local publication error from being reported simply as `Prometheus N minutes old`.

## Weav3r investigation

Weav3r's Travel Stock page is clearly live and currently renders overseas quantities across all countries. It is useful as an independent visual cross-check.

Verified public interface:

```text
https://weav3r.dev/api/marketplace
```

This is a marketplace/catalog price endpoint used publicly by third-party scripts. It is appropriate for Torn-side market pricing/reference data, **not verified as the source of overseas stock quantities**.

Weav3r also publishes API documentation through:

```text
https://weav3r.dev/api-docs.html
```

However, as of this investigation, no documented structured **travel-stock quantity endpoint** has been verified from the public API docs/searchable material.

### Policy for integration

Do **not** add a brittle HTML scrape of `weav3r.dev/travel-stock` merely because the rendered page is current.

A Weav3r stock adapter should be added only when one of these is verified:

1. a documented public structured travel-stock endpoint;
2. explicit permission/contract from Weav3r for programmatic stock access;
3. another stable structured interface exposed for this use.

If verified, it should become a third per-country candidate in the same adapter/freshness framework as Prometheus and YATA, not a special case in the prediction model.

## Why Weav3r may look more reliable even without being our raw-stock source

A web service can hide source instability behind its own server-side polling/cache/retry layer. The fact that its page stays populated does not imply that the raw underlying source never goes stale.

Travel Assistant should adopt the same resilience principles locally:

- poll multiple independent sources where contracts are verified;
- retain the last valid observation for display/audit;
- keep provider freshness separate from UI publication freshness;
- never blank the entire interface merely because one provider timestamp crosses a short live threshold;
- retry provider acquisition independently from local rendering;
- prevent a local file-write failure from discarding otherwise valid collected data.

## DroqsDB investigation

DroqsDB documents a public bulk endpoint:

```text
https://droqsdb.com/api/public/v1/export
```

with country/item snapshot fields and stock update timestamps. Public documentation exists, and third-party Torn scripts reference the export endpoint.

However, the currently crawler-visible live examples in DroqsDB's own API documentation report 404/non-JSON failures. Therefore it should **not** be promoted to production fallback solely from documentation.

Next step is a local bounded probe from the same Windows host as Rainmeter. If the actual endpoint returns valid JSON consistently and exposes source timestamps, it can be added as a third stock candidate before relying on any undocumented Weav3r stock interface.

## Provider-selection improvements

The desired live algorithm is:

```text
for each country:
    collect available structured providers
    reject missing/malformed snapshots
    reject source timestamps older than live threshold
    detect conflicting zero-vs-positive stock state where possible
    choose the freshest acceptable provider
    retain provider identity + source timestamp with every observation
```

Do not select a provider globally if country timestamps differ.

Do not average contradictory current stock counts into false precision.

## Retry behavior

A 15-second retry is useful for transient network problems, but it becomes harmful when the failure is deterministic local IO.

After the atomic-state fix, monitor whether retries recover normally. If a future local publication error survives the bounded atomic retry, the freshness layer should avoid immediately spawning endless 15-second full update attempts. A later improvement should classify failures as:

```text
network/provider
provider stale
provider malformed
local state publication
model/projection
```

and apply different retry/backoff policies.

## Recommended immediate validation

After pulling the atomic writer changes:

1. run `Validate-AtomicStateWrites.ps1`;
2. run one manual production `RunUpdate.ps1 -Action Update`;
3. inspect `data/runtime/logs/run-update-error.txt` and `collected-state-error.txt`;
4. confirm `@Resources/Generated/last-update.txt` advances;
5. confirm `state.kv` source timestamps advance;
6. confirm opportunity cards render;
7. then observe for several normal one-minute polls.

If the live provider itself is stale after state publication is repaired, capture the new `engine-state.json` `shadowCollection` object and the latest provider error log. That will isolate an actual acquisition problem from the publication failure already identified.

## Follow-up engineering tasks

- migrate remaining high-frequency `state.kv` writers to `AtomicFile.ps1` so all independent UI/update processes share the same destination mutex;
- make heartbeat publication use the same helper;
- add explicit collection-vs-publication freshness fields to `state.kv` and the header;
- add a provider health/probe validator for Prometheus, YATA, and any future DroqsDB/Weav3r adapter;
- verify a structured Weav3r travel-stock contract before integrating it;
- keep forecasting/data-quality work separate from source-acquisition health.
