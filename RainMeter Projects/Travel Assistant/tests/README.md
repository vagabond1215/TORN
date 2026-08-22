# Travel Assistant Tests and Fixtures

Synthetic fixtures/tests are validation data only. They are not historical evidence and must never be copied into `data/seed/`.

## Run all deterministic/static tests

From `RainMeter Projects/Travel Assistant/` on Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

The aggregate runner currently includes static/config validation plus deterministic fixture tests for:

- project/Rainmeter structure;
- graph window/retention contracts;
- shadow collection;
- offline item metadata/catalog;
- broad resale queue;
- independent visible item cards;
- persistent filters / pin / Ignore List contracts;
- travel-context normalization;
- historical pipeline and seed importer;
- recommendation model;
- provider normalization;
- travel profile/current capacity;
- final state/economics;
- restock display.

No deterministic test should require a live web provider.

## Current 0.4.0 focused tests

### Filter/pin/settings static contract

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-Filters.ps1
```

Checks:

- persistent preference fields;
- detached Item/Country/Category/Ignore popup infrastructure;
- full-catalog Ignore List source;
- local-only filter projection;
- pin stored directly in local preferences rather than stale `state.kv` projection;
- Ignore List broad-resale suppression policy;
- profitable-only Settings control;
- Settings merge behavior;
- Short/Medium/Long country taxonomy;
- 0.4.0 filter-bar meters/actions.

### Filter preference behavior

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FilterPreferenceTests.ps1
```

Checks defaults, persistence normalization, explicit empty country selection, independent trip-band toggles, reset semantics, pin/ignore preservation, and invalid-value cleanup without touching the real runtime preference file.

### Travel context

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelContext.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelContextTests.ps1
```

Checks bounded Authorization-header transport plus deterministic normalization for outbound, abroad, returning, known aliases, and unknown destinations.

### Independent visible cards

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-VisibleItems.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-VisibleItemsTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Checks independent card identity, item-specific secondary graphs, smaller/muted market values, expansion cap, pin/filter hooks, and the production runtime ordering.

## Other important focused suites

Broad resale:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ResaleQueue.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ResaleQueueTests.ps1
```

Category/current capacity:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-CurrentCapacityTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelProfileTests.ps1
```

Shadow collection/catalog:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ShadowCollection.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ShadowCollectionTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-LocalCatalog.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-LocalCatalogTests.ps1
```

Historical pipeline/model:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-HistoricalPipelineTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-SeedImporterTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ModelTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FinalizeStateTests.ps1
```

## Runtime validation boundary

Static/deterministic tests do not establish:

- actual Rainmeter layout/reflow/click behavior;
- detached WinForms popup behavior on the target desktop;
- right-click pin persistence through real Rainmeter updates;
- live Torn travel-context response compatibility;
- live provider/resale transport;
- `System.Drawing` behavior on the target PowerShell runtime;
- CPU/RAM/disk behavior over time;
- `.rmskin` installation behavior.

Those claims require the target Windows/Rainmeter host. See `../docs/NEXT_CODEX_RUN.md` and `../docs/WINDOWS_VALIDATION.md`.
