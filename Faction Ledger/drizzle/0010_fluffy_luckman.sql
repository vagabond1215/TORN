ALTER TABLE `member_balance_entries` ADD `payout_request_id` integer;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `apply_member_balance_entry`;
--> statement-breakpoint
CREATE TRIGGER `apply_member_balance_entry`
AFTER INSERT ON `member_balance_entries`
BEGIN
  SELECT CASE WHEN NEW.`member_id` IS NULL AND (
    SELECT COUNT(*) FROM `member_balances`
    WHERE `faction_id` = NEW.`faction_id` AND `member_id` IS NULL AND `member_name` = NEW.`member_name` COLLATE NOCASE
  ) > 1 THEN RAISE(ABORT, 'ambiguous member balance identity') END;

  UPDATE `member_balances` SET
    `member_id` = NEW.`member_id`,
    `member_name` = NEW.`member_name`,
    `resolution_status` = 'verified',
    `updated_at` = CURRENT_TIMESTAMP
  WHERE NEW.`member_id` IS NOT NULL
    AND `id` = (
      SELECT MIN(`id`) FROM `member_balances`
      WHERE `faction_id` = NEW.`faction_id` AND `member_id` IS NULL AND `member_name` = NEW.`member_name` COLLATE NOCASE
      HAVING COUNT(*) = 1
    )
    AND NOT EXISTS (
      SELECT 1 FROM `member_balances` WHERE `faction_id` = NEW.`faction_id` AND `member_id` = NEW.`member_id`
    );

  INSERT INTO `member_balances`
    (`faction_id`, `member_id`, `member_name`, `balance`, `earned_total`, `paid_total`, `resolution_status`)
  SELECT NEW.`faction_id`, NEW.`member_id`, NEW.`member_name`, 0, 0, 0, 'verified'
  WHERE NEW.`member_id` IS NOT NULL
  ON CONFLICT(`faction_id`, `member_id`) WHERE `member_id` IS NOT NULL DO UPDATE SET
    `member_name` = excluded.`member_name`,
    `resolution_status` = 'verified',
    `updated_at` = CURRENT_TIMESTAMP;

  INSERT INTO `member_balances`
    (`faction_id`, `member_id`, `member_name`, `balance`, `earned_total`, `paid_total`, `resolution_status`)
  SELECT NEW.`faction_id`, NULL, NEW.`member_name`, 0, 0, 0, 'unresolved'
  WHERE NEW.`member_id` IS NULL AND NOT EXISTS (
    SELECT 1 FROM `member_balances`
    WHERE `faction_id` = NEW.`faction_id` AND `member_id` IS NULL AND `member_name` = NEW.`member_name` COLLATE NOCASE
  );

  UPDATE `member_balances` SET
    `member_name` = NEW.`member_name`,
    `balance` = CASE WHEN
      `observed_at` IS NULL
      OR julianday(COALESCE(NEW.`occurred_at`, CURRENT_TIMESTAMP)) > julianday(`observed_at`)
      OR (
        julianday(COALESCE(NEW.`occurred_at`, CURRENT_TIMESTAMP)) = julianday(`observed_at`)
        AND CASE WHEN NEW.`explicit_balance` IS NULL THEN 1 ELSE 2 END >= `observed_priority`
      )
    THEN CASE
      WHEN NEW.`kind` = 'credit' AND NEW.`explicit_balance` IS NOT NULL THEN MAX(0, NEW.`explicit_balance`)
      WHEN NEW.`kind` = 'credit' THEN MAX(0, `balance` + NEW.`amount`)
      ELSE MAX(0, `balance` - NEW.`amount`)
    END ELSE `balance` END,
    `earned_total` = `earned_total` + CASE WHEN NEW.`kind` = 'credit' THEN NEW.`amount` ELSE 0 END,
    `paid_total` = `paid_total` + CASE WHEN NEW.`kind` = 'payout' THEN NEW.`amount` ELSE 0 END,
    `observed_at` = CASE WHEN
      `observed_at` IS NULL
      OR julianday(COALESCE(NEW.`occurred_at`, CURRENT_TIMESTAMP)) > julianday(`observed_at`)
      OR (
        julianday(COALESCE(NEW.`occurred_at`, CURRENT_TIMESTAMP)) = julianday(`observed_at`)
        AND CASE WHEN NEW.`explicit_balance` IS NULL THEN 1 ELSE 2 END >= `observed_priority`
      )
    THEN COALESCE(NEW.`occurred_at`, CURRENT_TIMESTAMP) ELSE `observed_at` END,
    `observed_priority` = CASE WHEN
      `observed_at` IS NULL
      OR julianday(COALESCE(NEW.`occurred_at`, CURRENT_TIMESTAMP)) > julianday(`observed_at`)
      OR (
        julianday(COALESCE(NEW.`occurred_at`, CURRENT_TIMESTAMP)) = julianday(`observed_at`)
        AND CASE WHEN NEW.`explicit_balance` IS NULL THEN 1 ELSE 2 END >= `observed_priority`
      )
    THEN CASE WHEN NEW.`explicit_balance` IS NULL THEN 1 ELSE 2 END ELSE `observed_priority` END,
    `resolution_status` = CASE WHEN NEW.`member_id` IS NULL THEN `resolution_status` ELSE 'verified' END,
    `updated_at` = CURRENT_TIMESTAMP
  WHERE `faction_id` = NEW.`faction_id` AND (
    (NEW.`member_id` IS NOT NULL AND `member_id` = NEW.`member_id`)
    OR (NEW.`member_id` IS NULL AND `member_id` IS NULL AND `member_name` = NEW.`member_name` COLLATE NOCASE)
  );

  SELECT CASE WHEN NEW.`payout_request_id` IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM `payout_requests`
    WHERE `faction_id` = NEW.`faction_id`
      AND `id` = NEW.`payout_request_id`
      AND `member_id` = NEW.`member_id`
      AND `status` IN ('pending', 'approved')
  ) THEN RAISE(ABORT, 'payout request settlement failed') END;

  UPDATE `payout_requests` SET
    `status` = 'paid',
    `updated_at` = CURRENT_TIMESTAMP
  WHERE NEW.`kind` = 'payout'
    AND NEW.`payout_request_id` IS NOT NULL
    AND `faction_id` = NEW.`faction_id`
    AND `id` = NEW.`payout_request_id`
    AND `member_id` = NEW.`member_id`
    AND `status` IN ('pending', 'approved');
END;
