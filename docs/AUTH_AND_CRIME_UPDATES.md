# Torn Guide: authentication, cache, refresh, and Crimes 2.0

This applies only to the interactive website in `docs/` within `vagabond1215/TORN`.

## Stay logged in

The login form offers **Stay logged in on this device**, off by default. When off, API credentials exist in JavaScript memory for the current page only. When enabled, the validated 16-character Torn API key and a per-character snapshot are stored in this browser's `localStorage`, under:

- `torn-city-guide:api:v2:remember`: versioned key and minimal player identity
- `torn-city-guide:api:v2:cache:<player-id>`: versioned account snapshot, last successful refresh time, inventory and API errors

The stored API key is **not encrypted**. This is a browser-only static GitHub Pages site; encryption without another user secret would not protect a key from JavaScript executing in the same origin or from somebody with access to this browser profile. Avoid enabling it on a shared device, especially with a Full Access key. A narrower Torn API key should be preferred where possible.

Switching account and Disconnect explicitly clear the saved key and its matching cache. Disabling Stay logged in while connected clears the saved key and cache without terminating the current in-memory session. Browser-managed removal of site data can also clear everything.

No API key is published to GitHub, sent to any third-party proxy, included in an API URL, or logged intentionally. Torn API requests use the Authorization header to `https://api.torn.com/v2/`.

## Refresh and caching

The Refresh button in the center of the header and the existing account Refresh button use the same API refresh routine and refuse overlapping requests. When connected, automatic refreshes are scheduled for the next absolute quarter hour: **:00, :15, :30, :45**, with minute boundaries evaluated using `Date.now()` (UTC-independent). The schedule continues only while the page is open.

Browsers may throttle or suspend timers in background tabs. When the page becomes visible or focused, a stale snapshot (last update >= 15 minutes ago) triggers an immediate catch-up refresh. Opening a remembered session shows the cached data immediately and only refreshes if stale. A normal session has no persistent data cache.

The Dashboard labels restored cache versus live Torn API data. Per-selection errors are retained and shown in API diagnostics. A temporary API failure doesn't revoke the key automatically.

## Crimes 2.0

The new Crime page includes a concise overview of hidden account-wide Crime Experience (CE), per-crime Skill (CS), Natural Nerve Bar (NNB), the current total nerve bar, red critical-failure penalties, a 13-crime relative-difficulty table, and a flexible completion order. It intentionally distinguishes the natural nerve cap from faction/merit/company nerve bonuses.

References:
- https://wiki.torn.com/wiki/Crimes_2.0
- https://wiki.torn.com/wiki/Nerve
- https://www.torn.com/forums.php?p=threads&t=16385729

Current on November 23, 2026.
