# Travel Assistant Seed Data

`data/seed/` contains **immutable, provenance-documented bootstrap history** that may be committed to Git so a new Travel Assistant installation can begin with useful historical context.

It is intentionally separate from `data/runtime/`, which is local, mutable, bounded, and ignored by Git.

## Files

- `observations.jsonl` — normalized historical stock observations.
- `cycles.jsonl` — completed restock/sellout cycles derived only from observed transitions.
- `metadata.json` — provenance and coverage for committed seed data.

The current seed may remain empty until a structured historical source is verified. Never fill it with synthetic test fixtures.

## Observation contract

One JSON object per line:

```json
{"schemaVersion":1,"timestamp":1787168400,"country":"united_kingdom","itemId":206,"stock":1438,"foreignPrice":742000,"source":"provider-name","sourceTimestamp":1787168372}
```

Required semantics:

- `timestamp` is an epoch-second observation/source timestamp, not import time;
- `country` is the stable Travel Assistant country ID;
- `itemId` is the Torn item ID;
- `stock` is observed foreign-shop stock;
- `foreignPrice` is the observed foreign purchase price;
- `source` identifies the provider sufficiently for provenance/debugging;
- `sourceTimestamp` is the provider's timestamp when available, otherwise `0` only when the original provider does not expose one.

## Completed-cycle contract

One JSON object per line:

```json
{"schemaVersion":1,"country":"united_kingdom","itemId":206,"foreignPrice":742000,"restockAt":1787168400,"restockQuantity":2630,"soldOutAt":1787169000,"availabilitySeconds":600,"previousSoldOutAt":1787161000,"restockDelaySeconds":7400,"source":"provider-name"}
```

A completed cycle must be based on observed stock transitions. Predicted restock/stockout timestamps must not be converted into historical facts.

## Import rules

Before committing seed history:

1. verify the provider's current endpoint/usage contract;
2. retain enough provider/source information in `metadata.json` to reproduce or audit the import;
3. normalize timestamps, country IDs, item IDs, stock, and foreign price;
4. deduplicate records;
5. derive cycles from observations when possible instead of trusting provider forecasts;
6. keep the bootstrap intentionally compact rather than archiving an unbounded third-party dataset;
7. run the project validators and model replay tests.

See `../../tools/README.md` for the connector/local seed tooling and `../../docs/HISTORICAL_BOOTSTRAP.md` for the current provider-discovery status.
