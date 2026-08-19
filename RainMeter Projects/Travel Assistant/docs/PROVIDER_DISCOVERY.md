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

Network polling is intentionally conservative. The default is 60 seconds, and duplicate source/value observations are not appended to local history.

## Current resale reference: Torn Item Market API

Profitability gating is designed to use Torn API v2 item-market data for the current resale reference:

```text
https://api.torn.com/v2/market/{itemId}/itemmarket?limit=1
```

A local API key is required. It may be supplied through ignored `config/settings.local.json` or the `TORN_API_KEY` environment variable. No API key should be committed merely to make the project runnable.

The implementation caches resale observations and should not request the item market on every one-second Rainmeter update.

### Selling-fee note

The Torn Item Market currently charges a regular 5% sales tax. Profitability calculations that use an Item Market resale target should ultimately use the **net** sell value after the configured market fee, not the gross listing price. This is a required correctness item before recommendations are treated as production-ready. Bazaar/trader sell targets can be added later as explicit alternatives instead of silently assuming the same fee.

Reference: https://wiki.torn.com/wiki/Item_Market

## Weav3r

Weav3r remains the user-facing external verification page:

```text
https://weav3r.dev/travel-stock
```

The Travel Assistant does **not** use a browser-render/scrape loop. If Weav3r later exposes a suitable structured endpoint that can be used appropriately and economically, it may be added as a provider adapter or bounded historical-bootstrap source.

The Rainmeter timing/status field is clickable so low-confidence situations can be checked on Weav3r quickly.

## DroqsDB

DroqsDB public documentation advertises country/item snapshots, market/bazaar pricing, restock guidance, forecasts, exports, and historical series:

```text
https://droqsdb.com/api-docs
```

The provider registry keeps DroqsDB disabled for now because the exact live endpoint/history contract has not yet been validated in this implementation pass. Do not seed Git with inferred or manufactured history merely because the documentation describes a historical endpoint.

DroqsDB is a good candidate for a future bounded bootstrap/cross-check pass if the live API contract is verified.

## Historical bootstrap status

`data/seed/` is currently a valid **empty bootstrap**. This is deliberate.

The tracker starts collecting structured live observations locally and will derive actual restocks/sellouts as transitions are observed. Historical data may be committed later only when:

1. the source and query contract are verified;
2. acquisition is bounded and appropriate;
3. foreign price, timestamps, and country/item identity are sufficiently reliable;
4. provenance is written to `data/seed/metadata.json`;
5. the data improves first-run recommendations rather than merely adding volume.

Until then, the correct first-run behavior is `INSUFFICIENT_HISTORY` / `CHECK_EXTERNAL`, not a fabricated departure window.

## Provider failure policy

- Keep the last valid local observation available for display where possible.
- Mark stale/failed source state explicitly.
- Do not let a cached recommendation continue counting down as if it were current.
- Do not average materially disagreeing sources into false confidence.
- Do not allow provider-specific response fields to become the persistent core schema.
