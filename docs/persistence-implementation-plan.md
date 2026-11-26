# Persistence implementation sequence

Repository: `vagabond1215/TORN`, branch main, scope /docs/. Read root AGENTS.md before edits.

## 1P.1 — registry and storage audit
- Existing account keys: `torn-city-guide:v1:profile:<id>:` (notes, tasks, quickstart, Focus, selection, draft); `build:<id>`, `plan-view:<id>`, comparison mode, recommendation state, restock settings, OC bands, energy-war, activity settings/events, crime observations, manual RW. These are durable settings. 
- Critical records: training-session, training-spend, activity-training-history, activity-spend-ledger; must not be blindly copied. Session actions include checkpoints, recovery and projected financial data; rehab events may include baseline/completion evidence. Implement full typed adapters, stable IDs and tombstones before merging. Current first registry supports simple manual events only; unsupported existing records reported, not silently transformed.
- Device-global: interface:v1, sidebar, report pins, quick links, right rail, home activity visibility; separate explicit device-preference scope later. Guest data never attributed automatically to a player.
- Exclude auth remember, API cache, equipment, Weav3r buyers, RW price caches and request state. Market archive IndexedDB and companion log/market archive are separate export domains; do not duplicate.
- Implement explicit logical section registry, bounded validation, snapshot omission report, non-destructive restore into empty account only, rollback on write error. Tests for unknown keys, invalid values, conflicting account, quota, rollback, stale account guard. 
- Do not migrate original keys yet. No runtime feature until portable envelope and verified owner gate.

## 1P.2 — portable encrypted recovery
- Versioned envelope with account ID, creation date, format version, KDF parameters, random salt, unique random IV, ciphertext. AES-GCM authenticated metadata; PBKDF2-SHA256 fixed versioned iteration count. Independent passphrase, never an API credential. File size limits before decode; validate exact envelope, inner identity and record schema. Fresh own-account API verification before export and restore; capture account epoch and reject account switch. Do not persist passphrase. 
- Explicit Settings controls, file chooser, clear coverage and omission warnings, confirmation, account matching. Reload on successful import to reset module-local owners; session-only users must reconnect. Empty-only limitation protects against resurrecting deletions, overwriting live state, or applying stale competing backups. Do not claim full-account backup. Do not auto-restore yet.
- Test encryption/decryption, tamper, wrong password, owner mismatch, schema, malformed file, no secrets, quota and epoch; browser round trip required before release-grade validation.

## 1P.3 — complete durable state adapters and merge
- Inventory exact session, history, ledger and rehab event schemas. Preserve confirmed prefixes and stable IDs; add per-section revisions, deletion tombstones, immutable transaction IDs, conflict staging and journal with recoverable previous generation. Migrate legacy records conservatively; never invent actual spend from estimated cycle cost. Device/global settings separately scoped. Verify same-account data merge across stale backup, concurrent tabs, account rotation and crash; hold uncertain sessions.
- Make account recovery available before default writes or advice generation. Verify no cache or auth resurrection. Extend fixtures and real browser cases.

## 1P.4 — companion vault
- Enroll with explicit consent; encrypted payload only through existing page bridge, no API key or plaintext backups. Treat DOM messages as untrusted: prevent wrong-owner disclosure through encrypted storage, protect against ciphertext overwrite/rollback and bound quota; require companion-side trusted authorization for enrollment and writes or independent secret and verified integrity. Keep previous generation, acknowledgements and honest status. No arbitrary requests by player ID. Test site clear with extension intact, spoofed messages, tampering, missing/old companion, account switching and deletion.

## 1P.5 — authorized directory backup and archive migration
- Feature-detect browser picker APIs, require user directory grant, only look for recognized envelope files, match owner and validate contents; handle permission loss, browser clear, unsupported browser and file corruption. Standard portable file fallback. Atomic/previous generation where possible, throttle writes, explicit last success and failure. Separate chunked market/log archive migration with deduplication and size limits.

## 1B.3 — ledger and liquidity
- Separate replacement value, purchase forecast, owned stock, cash available, reserved funds, pending vs verified actual expenditure, rolling weekly budget. Record confirmed expenses with immutable IDs; never treat a log action without price as exact purchase. Reconcile partial sessions and historical estimated debits; retain source/quality and avoid duplicates. Live wallet constraints are immediate liquidity, not full-week budget.
- Independently test paid and natural plan parity, war/rehab reserves, owned points, unknown prices, partial cycle and account restore. Then 1C parity, 1D browser/API validation, and subsequent execution recovery.

## Checkpoint
1P.1 registry implemented for bounded subset; 1P.2 depends on fresh own-account check and encrypted file implementation. Existing session/history, spend ledgers, rehab-enriched events and archive data not yet backed up by registry. No automatic restoration, extension or directory mirroring in this commit. 

### 1P.2 implementation checkpoint
Encrypted portable export/import added for the explicit 1P.1 registry subset. Fresh own-account verification captures connection epoch; file identity and metadata are authenticated with AES-GCM; PBKDF2-SHA256 600,000 iterations, random salt and IV; no credential/passphrase persistence. Settings dialog requires explicit recovery and rejects populated supported account data or existing session/history. Download status is a request, not proof of file persistence. Native Web Crypto regression fixture added; the connector harness lacks Web Crypto, so native execution and browser round-trip remain outstanding. Registry fixture passed. Critical-state coverage, revisioned merge, durable journals and auto recovery remain next; this is not full account backup.
