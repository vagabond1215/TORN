# Local-file archive and account backup extension

Scope: vagabond1215/TORN, docs/ only. Requested 2026-11-28. Design checkpoint, not a shipped file writer. Coordinate with log-archive-implementation-plan.md, account-transaction-boundary-plan.md and the existing encrypted account backup/recovery work.

## Current facts

The Log UI combines chronological rows but API session data and companion userscript data remain separate, with 2,000 newest records per source and potential eviction. The unwired durable API archive has initial limits of 20,000 records and 32 MiB estimated serialized size. Its capacity refusal preserves state. The current encrypted account backup excludes Log and market archives. Do not claim previously evicted rows can be recovered.

## Target

One account-scoped durable Log with source attribution. API IDs remain exact; companion observations have separate source-local identities/multiplicity and overlap flags. Do not infer equality solely from time/text. One browser-side retention policy with a bounded active working set; external local encrypted chunks extend retention without treating the 2,000 display/cache limit or 20,000 database limit as a total history limit. Include other supported account data (settings, notes, checklists, calendar, expenditure, training history) through the existing reviewed backup contract. Market history is an explicit separately selected bulk archive, not an account section. No credentials, cookies, arbitrary raw responses, game actions, or server uploads.

## File access

- Universal fallback: explicit encrypted download and file-input restore. Downloads alone cannot prove that a file was saved; verify a reselected file before acknowledging it as an eviction-safe backup.
- Optional user-selected external backup directory through feature-detected File System Access API, only after explicit consent and browser picker. Remember a directory handle where supported; check permission before use and require renewed user interaction if revoked. No fixed absolute paths, no automatic permission grants. Guide coordinates writes; companion hands off validated source data, not directory handles or passphrases. No always-running service or promise of background operation while closed.
- OPFS is quota-bound origin storage, not an independent external backup. Firefox, Safari, mobile and userscript managers require compatibility validation and manual export fallback. File picker may be unavailable even in secure contexts.
- Encrypted archive uses independent user-held passphrase (not API key), authenticated manifest and bounded chunks; reuse reviewed cryptographic primitives/parameters without widening existing account backup schema or silently changing its version. In-memory key material only while unlocked; pause automatic file operations when locked. Separate account, source, schema, generation, time range, count and content integrity. No plaintext sensitive data in filenames or diagnostic logs.

## Overflow and recovery contract

1. Integrate durable log collector with existing coordinator and opt-in lifecycle first, preserve currently collected session/companion rows with explicit partial import and provenance. Do not claim full history.
2. Build read-only bounded export preview over stable archive generation. Create immutable versioned files with unique names; encrypted manifest identifies chunk set, coverage, exact IDs, retention/purge metadata. Keep prior verified backup generation, never overwrite only good copy. Reopen and verify ciphertext authentication, exact owner, completeness, count and digest before acknowledgment. File save/cancel/quota/permission failures retain all source bytes; no silent trimming. Manual download cannot alone acknowledge save.
3. Under authoritative transactional boundary, compare exact reviewed generation and rows again, then mark only verified chunks as externalized and optionally prune their local copies. No pruning from stale acknowledgment or missing/moved file. File system and database are not one atomic transaction: use staged states and idempotent recovery (file saved but DB unacknowledged, DB acknowledged, interrupted prune); leave files untouched on ambiguous failures. Never advance API coverage past an unsaved page. If unable to persist incoming data, stop collection at a safe boundary, show the reason and offer backup/restore. Current legacy collectors still trim; do not represent this future behavior as live.
4. Restore/import is explicit, bounded, owner-verified, authenticated and previewed. Deduplicate exact source identities, retain conflict evidence, preserve known purges and lineage; never import stale preferences or deleted records automatically. Search archived history by reading authorized chunks or importing selected ranges, with visible coverage gaps. Never silently rebuild account data from a directory.
5. Backup account changes through the eventual authoritative account generation, preserve transaction lineage and held sessions. Keep account snapshots separate from bulk log chunks but discoverable in one backup UI. External backup is optional and independent of browser storage; backup failures must not erase current account data. Explicit retention controls and no deletion of user files without approval.

## Acceptance sequence

- L3 integration: native API permission/identity, opt-in durable collection, companion staging, same-second multiplicity, two-tab purge/late responses, reload and quota handling. No new polling loop.
- File codec and manifest: native crypto round trips; wrong passphrase, wrong owner, incomplete/tampered chunk, duplicate ID/conflict, oversized file, unsupported version, purge non-resurrection; no credential export.
- Directory adapter: test picker cancellation, unsupported platform, denied/revoked permission, locked backup, read-back mismatch, moved file, interruption, competing tab, write/quota failure. Only verified external chunks may be eligible for eviction. Test actual desktop and mobile/manual fallback; no policy bypass.
- Retention: synthetic >2,000 and >20,000 records, exact counts including multiplicity, backup then prune then query/restore, late collector responses, interrupted file/DB transitions, no loss of previous known-good backup. Capacity limits are engineering bounds, not claims about disk size.
- Account and market backup selection: preserve existing encrypted backup compatibility and transactional migration gates. Full native and browser tests before activation.

References: https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker ; https://developer.mozilla.org/en-US/docs/Web/API/FileSystemHandle/requestPermission ; https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system .
