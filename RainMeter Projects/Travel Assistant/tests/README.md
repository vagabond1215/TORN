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
- compact opportunity-card presentation;
- persistent filters / Ignore List contracts;
- travel-context normalization;
- historical pipeline and seed importer;
- recommendation model;
- provider normalization;
- travel profile/current capacity;
- final state/economics;
- restock display.

No deterministic test should require a live web provider.

## Current 0.6.0 focused tests

### Filter/settings static contract

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-Filters.ps1
```

Checks:

- persistent preference fields;
- detached Item/Country/Category/Ignore popup infrastructure;
- full-catalog Ignore List source;
- local-only filter projection;
- Ignore List broad-resale suppression policy;
- profitable-only Settings control;
- Settings merge behavior;
- Short/Medium/Long country taxonomy;
- compact unified filter/header meters/actions.

### Filter preference behavior

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FilterPreferenceTests.ps1
```

Checks defaults, persistence normalization, explicit empty country selection, independent trip-band toggles, reset semantics, Ignore List preservation, retired-pin cleanup, and invalid-value cleanup without touching the real runtime preference file.

### Travel context

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelContext.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelContextTests.ps1
```

Checks bounded Authorization-header transport plus deterministic normalization for outbound, abroad, returning, known aliases, and unknown destinations.

### Compact opportunity cards

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-CardPresenter.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-CardDetailLayout.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Checks the 48px square item-art cell with 44px transparent art, large signed total Net, two-line Each/Total MV-Net-Tax economics, signed displayed-profit sorting, black card fill with gray borders/separators, inset lime end-cap controls, full-bleed dynamically rounded flag end caps, black/lime graph palette with cobalt/pumpkin event ticks below the X axis, flag/window-only tooltip ownership, future-only actionable departure tooltip times, low window guidance, compact footer reflow, fallback-only Name ordering, and the current Rainmeter card contract.

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
- live Torn travel-context response compatibility;
- live provider/resale transport;
- `System.Drawing` behavior on the target PowerShell runtime;
- CPU/RAM/disk behavior over time;
- `.rmskin` installation behavior.

Those claims require the target Windows/Rainmeter host. See `../docs/NEXT_CODEX_RUN.md` and `../docs/WINDOWS_VALIDATION.md`.
