# Weav3r buyer lookup

Audit date: November 24, 2026. Test item: Torn City Times (886).

| Surface | Meaning and fields |
| --- | --- |
| `GET /api/marketplace/{itemId}/traders?limit=10&sort=price` | Public calculated **merchant buy prices**. Returns `item_id`, `item_name`, `total_count`, `generated_at` (Unix seconds) and `traders`. Each row includes public Torn player ID and name, price, internal pricelist ID, rating, and nullable last Torn action, trade and pricelist-update timestamps. A sponsored row can precede organic results. No real-time online flag, requested quantity, or bulk terms are supplied. |
| `GET /api/pricelist/{playerId}` | Public array of item entries with `itemId`, `name`, `buyPrice`, `bulkThreshold` and `bulkBuyPrice`. Thresholds specify when bulk pricing applies. They do not indicate purchase capacity. The top trader's item 886 row had both bulk fields set to null, while other items in the same list had bulk terms. |
| `GET /api/marketplace` and `GET /api/marketplace/{itemId}` | Documented market and bazaar **selling** data. Listing quantities describe sellers’ stock. Item 886's filler response contained only seller price and quantity pairs. |
| Marketplace dashboard | Explicit anonymous buy orders are a separate section. The signed-in page loaded site-owned `/api/marketplace-orders` and `/api/marketplace-deals` requests. Neither appears in the public OpenAPI contract. Use the [manual item listing](https://weav3r.dev/dashboard?tab=marketplace&intent=sell&item=886) to inspect anonymous orders and any quantities displayed there. Weav3r controls identity disclosure and matching. |

The public trader route documents eligibility based on an active public pricelist, recent Torn activity, trades or an availability ping, and rating. The dashboard displayed a 24-hour label and requested `limit=40&sort=price&tradedWithinHours=24`. The OpenAPI description says values from 12 through 168 use its 12-hour floor. The dashboard also displayed some merchants absent from the ten-row API sample. Treat the ranking and eligibility as those of the returned API data.

## Live evidence

- The marketplace UI showed zero anonymous buyers for 886 and a highest advertised merchant price of **$4,700 per copy**. Both the guide’s ten-row request and the dashboard’s observed 40-row trader request returned **$4,700** as their maximum. Both returned 79 as `total_count`.
- Anonymous GETs to the trader and trader-pricelist routes returned HTTP 200 JSON with `Access-Control-Allow-Origin: *` when sent `Origin: https://vagabond1215.github.io`. The guide uses a simple credential-free GET with no custom headers, so it does not require a preflight. One request carrying a deliberately invalid placeholder key returned HTTP 401 and `{"error":"Invalid API key"}`.
- The public trader row included a Torn player ID, but it supplied no direct URLs. The dashboard's pricelist links use `https://weav3r.dev/pricelist/{player_id}`. The public pricelist for the top result exposed `https://www.torn.com/trade.php#step=start&userID={player_id}`. The audit verified the displayed URL without opening it or initiating a trade.
- The official OpenAPI rate-limit overview gives 60 anonymous requests per minute per IP for limits 1–10, 30 for 11–25, and 15 for 26–100. The item listings and traders routes share this counter. Registered-key limits shown in the overview are twice those values. The listing filler has its own limit. The guide uses the anonymous 1–10 tier. The audit did not exhaust the live shared budget. Automated tests simulate HTTP 429 with and without a readable `Retry-After`.

Example trader data, shortened with public identities and IDs replaced:

```json
{
  "item_id": 886,
  "item_name": "Torn City Times",
  "total_count": 79,
  "generated_at": 1795561736,
  "traders": [
    {"player_id": 123456, "player_name": "Example Trader", "price": 4700,
     "rating": {"upvotes": 7, "downvotes": 0, "total": 7}, "pricelist_id": 123,
     "last_trade": 1795557753, "last_action": 1795561548, "pricelist_updated": 1795545249}
  ]
}
```

The matching public pricelist row:

```json
{"itemId":886,"name":"Torn City Times","buyPrice":4700,"bulkThreshold":null,"bulkBuyPrice":null}
```

## Guide behavior and verification

- One explicit click checks one item. The guide sorts returned public prices, including any sponsored entry, and deduplicates by player ID. The green dollar link signals a recent nonempty result. The last check time is shown, and the guide marks results stale after five minutes when rendered or reopened. A failed refresh preserves the previous result.
- The optional stack estimate is the highest advertised unit price times the local quantity, contingent on the trader accepting the whole stack. The guide does not send the stack quantity or Torn key, and does not fetch every trader’s full pricelist. Follow the linked pricelist to confirm bulk terms.
- A 429 applies an in-page cooldown using the readable retry header or a one-minute fallback. Authentication, browser/network failures, and invalid responses show an error while the manual listing link remains available.
- Run `node --test docs/tests/weav3r-buyers.test.mjs`. Tests exercise the on-demand inventory control, payload sorting, cached and stale results, unavailable quantities, empty lists, authentication and throttling responses, and browser-style request rejection.

[Official API docs](https://weav3r.dev/docs) · [OpenAPI specification](https://weav3r.dev/openapi-spec.json) · [Weav3r terms](https://weav3r.dev/terms-of-service)
