# Travel Assistant Tests and Fixtures

These fixtures are **synthetic validation data**, not historical evidence and not seed/training data.

They exist so provider normalization, history deduplication, profitability gating, and recommendation behavior can be replayed without depending exclusively on live web services.

## Fixtures

- `fixtures/yata-export.sample.json` — representative YATA-style UK/Japan Xanax stock payload.
- `fixtures/cycles-safe.jsonl` — synthetic high-price/long-availability UK cycles with a conservative Airstrip overlap.
- `fixtures/cycles-fast.jsonl` — synthetic low-price/fast-depletion UK cycles designed to have no conservative overlap and require best-odds timing.

Do **not** copy these fixture cycles into `data/seed/` or runtime history.

## Static validation

From `RainMeter Projects/Travel Assistant/` on Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelAssistant.ps1
```

This checks JSON contracts, JSONL parseability, required project files, travel-mode configuration, PowerShell parser errors, and basic Rainmeter skin structure. It does not prove that Rainmeter can load/run the skin or that live provider calls succeed.

## Production-model fixture tests

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ModelTests.ps1
```

`Run-ModelTests.ps1` parses the actual production `UpdateTracker.ps1`, extracts the named production functions through PowerShell's AST, and executes those exact function bodies against synthetic fixture data. It deliberately does **not** copy a second recommendation implementation into the test suite.

Current scenarios cover:

- YATA observation normalization;
- seed/runtime completed-cycle deduplication;
- high-price/long-stock `SAFE_WINDOW` behavior;
- low-price/fast-stock `BEST_ODDS` behavior;
- fee-adjusted `LOW_MARGIN` and `UNPROFITABLE` suppression;
- stale-source suppression;
- travel-mode-dependent departure timing;
- current-cycle fast depletion closing an otherwise historically safe live opportunity.

These tests are deterministic and make no network calls. They still require a local PowerShell execution pass before their results can be recorded as passing.

## Runtime validation boundary

A release-quality validation pass still needs Windows/Rainmeter because connector-only work cannot establish:

- that Rainmeter loads the `.ini` without log errors;
- RunCommand/Lua interaction on the installed Rainmeter build;
- `System.Drawing` graph generation under the local PowerShell runtime;
- live YATA and Torn API behavior from the user's machine;
- junction installation behavior;
- actual CPU/RAM/disk usage over time.
