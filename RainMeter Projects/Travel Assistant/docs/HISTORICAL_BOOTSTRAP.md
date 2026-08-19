# Historical Bootstrap Strategy

**Last reviewed:** 2026-08-19

Travel Assistant can already consume immutable seed observations/cycles from `data/seed/`, but the committed seed remains intentionally empty until a historical source is verified strongly enough to use as training evidence.

## Current provider findings

### Weav3r

- The public Travel Stock page remains the desired human verification target.
- The project has not established a documented/stable structured historical endpoint suitable for automated bootstrap ingestion.
- Do not implement a rendered-page scraping loop.
- Continue using Weav3r as the clickable `CHECK_EXTERNAL` target unless a structured endpoint is later verified.

### YATA

- Travel Assistant currently uses the structured public travel export for live stock / foreign purchase-price observations.
- This is treated as a live observation source, not a historical archive.
- Runtime observations collected from it are sufficient to train the local model over time.

### Open-source travel-planner history API candidate

The public `shab00m/torn-travel-planner` repository documents a read-only endpoint:

```text
GET /api/history/:country/:itemId?hours=...
```

with snapshot points shaped as:

```json
{
  "yata_ts": 1783961506,
  "quantity": 781,
  "cost": 782617
}
```

This is a particularly good conceptual bootstrap fit because the fields map directly to Travel Assistant's normalized observation contract and the upstream project itself records YATA snapshots approximately once per minute, deduplicated by the YATA country update timestamp.

The repository also documents restock/depletion analytics and safe-window APIs, but Travel Assistant should prefer the **raw snapshot history** for seed truth and derive its own completed cycles. Provider safe-window/restock predictions must not be imported as observed facts.

No deployed host is assumed by this repository. `tools/Import-TravelPlannerHistory.ps1` requires an explicit verified `-BaseUrl`, caps the requested history window, performs only UK/Japan Xanax history requests, writes a preview under ignored runtime storage, and imports to seed only with an explicit `-ImportToSeed` switch.

Before using any deployment, verify that the host is actually intended to expose its public history endpoint for bounded external use.

### DroqsDB

The current public API documentation advertises:

- `/api/public/v1/meta` for endpoint/history metadata;
- current country/item/export endpoints;
- `api.historyMetrics` metadata referring to historical chart support;
- a daily forecast endpoint with predicted fly-out/restock/stockout context.

The crawler-visible documentation currently shows failed/404 live examples for those public endpoints, so Travel Assistant does **not** treat the documentation alone as proof that the live historical contract is available from the user's machine.

`tools/Probe-DroqsDb.ps1` therefore probes the documented metadata/current endpoints locally and reports any history-looking endpoint names advertised by the live metadata response without calling guessed historical URLs automatically.

DroqsDB forecast fields, if reachable, are predictions. They may be useful later as a comparison/reference signal, but predicted restock or stockout timestamps must not be imported as actual historical cycle events.

## Safe bootstrap workflow

1. Identify a structured historical source and verify the specific live host / usage expectations.
2. Retrieve only a bounded amount of UK/Japan Xanax snapshot history.
3. Normalize observations to the Travel Assistant schema.
4. Derive completed cycles with `tools/Build-CyclesFromObservations.ps1` so restock/sellout events come from observed stock transitions.
5. Review candidate files before they touch committed seed data.
6. Import the normalized observations/cycles with `tools/Import-SeedHistory.ps1` (or the explicit `-ImportToSeed` path of a verified adapter).
7. Review `data/seed/metadata.json` provenance/coverage.
8. Run static validation, historical-pipeline validation, and production-model replay tests before committing the seed.

For a travel-planner-compatible history endpoint, steps 2–6 are orchestrated by `tools/Import-TravelPlannerHistory.ps1`, with preview-only behavior by default.

## Bootstrap sufficiency

The goal is **not** to mirror a provider's entire archive. A useful first-run seed needs only enough recent comparable cycles to support conservative statements such as:

- the current price regime has comparable evidence;
- the previous-sellout-to-restock interval has a usable distribution;
- the current price regime's stockout duration is typically short or long enough to evaluate departure timing.

The new compatible importer defaults to one week (168 hours) and hard-caps a request at 720 hours. That is a tooling safety bound, not a claim that one week is always statistically sufficient.

If those conditions cannot be established reliably, keep the seed empty and use `INSUFFICIENT_HISTORY` / `CHECK_EXTERNAL` while runtime learning accumulates.

## Historical facts vs forecasts

Allowed as historical evidence:

- source timestamp;
- observed stock level;
- observed foreign price;
- observed `0 -> positive` transition;
- observed `positive -> 0` transition.

Not allowed to masquerade as historical facts:

- estimated restock timestamp;
- estimated sellout timestamp;
- forecast departure window;
- provider confidence prediction.

Those forecast values can be retained separately for model comparison later, but must never populate the `Last Sold Out` field or completed-cycle truth records.

## Profitability reference note

The default Item Market profitability calculation applies the regular Item Market sales tax configured for the project. Bazaar selling is a different future sell-target option and does not use the same regular Item Market fee; do not silently use Item Market net proceeds when a future user explicitly selects Bazaar as the resale route.
