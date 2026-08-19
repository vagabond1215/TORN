# Provider Discovery — Travel Assistant v1

**Last reviewed:** 2026-08-19

This document records the provider choices and boundaries used by the first Travel Assistant implementation. Provider-specific formats must stay behind adapters; the core observation/cycle contracts remain generic.

## Live foreign stock: YATA

Initial live stock collection uses the structured YATA travel export:

```text
https://yata.yt/api/v1/travel/export/
```

The adapter expects a response shaped around a top-level `stocks` object, country codes such as `uni` (United Kingdom) and `jap` (Japan), a per-country `update` timestamp, and item rows containing `id`, `quantity`, and `cost`.

For v1, Xanax is Torn item ID `206`.

The normalized internal observation is:

```json
{
  "schemaVersion": 1,
  "timestamp": 1787168400,
  "country": "united_kingdom",
  "itemId": 206,
  "stock": 1438,
  "foreignPrice": 742000,
  "source": "yata",
  "sourceTimestamp": 1787168372
}
```

Network polling is intentionally conservative. The default is 60 seconds, duplicate source/value observations are not appended to local history, and a serialized updater wrapper prevents overlapping Rainmeter refresh/poll executions from racing on history/state/graph files.

## Current resale reference: Torn Item Market API

Profitability gating uses Torn API v2 item-market data for the current resale reference:

```text
https://api.torn.com/v2/market/{itemId}/itemmarket?limit=1
```

A local API key is required. It may be supplied through ignored `config/settings.local.json` or the `TORN_API_KEY` environment variable. No API key should be committed merely to make the project runnable.

The implementation caches resale observations and does not request the item market on every one-second Rainmeter update.

### Selling-fee note

The Torn Item Market regular sales tax is currently 5%. The v1 Item Market profitability gate therefore uses the **net** sell value after the configured fee rather than the gross listing reference.

Bazaar is intentionally not silently treated as equivalent: Torn's official wiki notes that Bazaar sales do not incur the regular Item Market 5% sales fee. If a future user-selectable Bazaar resale target is added, it should have its own price source and fee behavior rather than reusing Item Market assumptions.

Reference: https://wiki.torn.com/wiki/Item_Market

## Weav3r

Weav3r remains the user-facing external verification page:

```text
https://weav3r.dev/travel-stock
```

The Travel Assistant does **not** use a browser-render/scrape loop. If Weav3r later exposes a suitable structured endpoint that can be used appropriately and economically, it may be added as a provider adapter or bounded historical-bootstrap source.

The Rainmeter timing/status field and low-confidence overlays are clickable so uncertain situations can be checked on Weav3r quickly.

## DroqsDB

DroqsDB public documentation currently advertises:

```text
https://droqsdb.com/api-docs
```

including:

- `/api/public/v1/meta` metadata;
- country/item/export current snapshots;
- `api.historyMetrics` metadata referring to historical chart support;
- a daily forecast endpoint with predicted fly-out/restock/stockout context.

The crawler-visible docs currently show failed/404 live example responses, so Travel Assistant does not treat the documentation by itself as a verified live historical contract.

The provider registry keeps DroqsDB disabled for training/cross-check use until local verification. `tools/Probe-DroqsDb.ps1` probes only the documented metadata/current endpoints and reports history-looking endpoints advertised by the live metadata response. It does not automatically call guessed historical URLs.

Provider forecasts may later be useful as a **comparison** signal, but forecast restock/stockout timestamps are not actual historical events and must never populate completed-cycle truth records or `Last Sold Out`.

See [`HISTORICAL_BOOTSTRAP.md`](./HISTORICAL_BOOTSTRAP.md) for the bounded bootstrap procedure.

## Historical bootstrap status

`data/seed/` is currently a valid **empty bootstrap**. This is deliberate.

The tracker starts collecting structured live observations locally and derives actual restocks/sellouts as transitions are observed. Historical data may be committed later only when:

1. the source and query contract are verified;
2. acquisition is bounded and appropriate;
3. foreign price, timestamps, and country/item identity are sufficiently reliable;
4. provenance is written to `data/seed/metadata.json`;
5. observed transitions can be distinguished from predictions;
6. the data improves first-run recommendations rather than merely adding volume.

The repository now includes generic tools to build cycles from normalized observations and merge verified history into the immutable seed with deduplication/provenance checks.

Until a verified backfill is available, the correct first-run behavior is `INSUFFICIENT_HISTORY` / `CHECK_EXTERNAL`, not a fabricated departure window.

## Provider failure policy

- Keep the last valid local observation available for display where possible.
- Mark stale/failed source state explicitly.
- Do not let a cached recommendation continue counting down as if it were current.
- Do not average materially disagreeing sources into false confidence.
- Do not allow provider-specific response fields to become the persistent core schema.
