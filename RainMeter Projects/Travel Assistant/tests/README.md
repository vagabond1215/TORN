# Travel Assistant Tests and Fixtures

These fixtures are **synthetic validation data**, not historical evidence and not seed/training data.

They exist so the provider normalization, cycle engine, profitability gate, and recommendation model can eventually be replayed without depending exclusively on live web services.

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

Runtime/model replay tests should be expanded once the updater is split enough to inject fixtures without duplicating production logic.
