-- Run against a local export/copy of the legacy database before applying 0008.
-- Results require manual resolution; this file intentionally performs no writes.
SELECT
  'accounts_faction_name_unique' AS conflict,
  name AS keyValue,
  COUNT(*) AS rowCount
FROM accounts
GROUP BY name
HAVING COUNT(*) > 1;
--> statement-breakpoint
SELECT
  'member_balances_faction_member_unique' AS conflict,
  CAST(member_id AS TEXT) AS keyValue,
  COUNT(*) AS rowCount
FROM member_balances
WHERE member_id IS NOT NULL
GROUP BY member_id
HAVING COUNT(*) > 1;
