PRAGMA foreign_keys=OFF;
--> statement-breakpoint
CREATE TABLE `factions` (
  `faction_id` integer PRIMARY KEY NOT NULL,
  `name` text NOT NULL,
  `slug` text NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `factions_slug_unique` ON `factions` (`slug`);
--> statement-breakpoint
INSERT INTO `factions` (`faction_id`, `name`, `slug`) VALUES (52984, 'Blood Coven', 'blood-coven');
--> statement-breakpoint
CREATE TABLE `faction_members` (
  `faction_id` integer NOT NULL,
  `member_id` integer NOT NULL,
  `member_name` text NOT NULL,
  `last_verified_at` text NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`, `member_id`)
);
--> statement-breakpoint
CREATE INDEX `idx_faction_members_name` ON `faction_members` (`faction_id`,`member_name`);
--> statement-breakpoint

ALTER TABLE `accounts` ADD `faction_id` integer DEFAULT 52984 NOT NULL;
--> statement-breakpoint
CREATE UNIQUE INDEX `accounts_faction_name_unique` ON `accounts` (`faction_id`,`name`);
--> statement-breakpoint
CREATE INDEX `idx_accounts_faction` ON `accounts` (`faction_id`,`id`);
--> statement-breakpoint
DROP INDEX IF EXISTS `idx_transactions_created_at`;
--> statement-breakpoint
ALTER TABLE `transactions` ADD `faction_id` integer DEFAULT 52984 NOT NULL;
--> statement-breakpoint
CREATE INDEX `idx_transactions_faction_created_at` ON `transactions` (`faction_id`,`created_at`,`id`);
--> statement-breakpoint

CREATE TABLE `__new_policies` (
  `faction_id` integer NOT NULL,
  `source_key` text NOT NULL,
  `label` text NOT NULL,
  `tax_bps` integer DEFAULT 0 NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`, `source_key`),
  CONSTRAINT `policies_tax_range` CHECK(`tax_bps` BETWEEN 0 AND 10000)
);
--> statement-breakpoint
INSERT INTO `__new_policies` (`faction_id`,`source_key`,`label`,`tax_bps`,`created_at`,`updated_at`)
  SELECT 52984,`source_key`,`label`,`tax_bps`,`created_at`,`updated_at` FROM `policies`;
--> statement-breakpoint
DROP TABLE `policies`;
--> statement-breakpoint
ALTER TABLE `__new_policies` RENAME TO `policies`;
--> statement-breakpoint

CREATE TABLE `__new_pending_wars` (
  `faction_id` integer NOT NULL,
  `war_id` integer NOT NULL,
  `opponent_name` text NOT NULL,
  `started_at` integer NOT NULL,
  `ended_at` integer NOT NULL,
  `won` integer DEFAULT 0 NOT NULL,
  `gross_estimate` integer DEFAULT 0 NOT NULL,
  `reviewed_value` integer,
  `reviewed_tax_bps` integer DEFAULT 2000 NOT NULL,
  `status` text DEFAULT 'pending' NOT NULL,
  `rewards_json` text DEFAULT '[]' NOT NULL,
  `members_json` text DEFAULT '[]' NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`, `war_id`),
  CONSTRAINT `pending_wars_status` CHECK(`status` IN ('pending','recorded','dismissed')),
  CONSTRAINT `pending_wars_tax_range` CHECK(`reviewed_tax_bps` BETWEEN 0 AND 10000)
);
--> statement-breakpoint
INSERT INTO `__new_pending_wars` SELECT COALESCE(`faction_id`,52984),`war_id`,`opponent_name`,`started_at`,`ended_at`,`won`,`gross_estimate`,`reviewed_value`,`reviewed_tax_bps`,`status`,`rewards_json`,`members_json`,`created_at`,`updated_at` FROM `pending_wars`;
--> statement-breakpoint
DROP TABLE `pending_wars`;
--> statement-breakpoint
ALTER TABLE `__new_pending_wars` RENAME TO `pending_wars`;
--> statement-breakpoint
CREATE INDEX `idx_pending_wars_faction_status_end` ON `pending_wars` (`faction_id`,`status`,`ended_at`);
--> statement-breakpoint

CREATE TABLE `__new_active_war` (
  `faction_id` integer NOT NULL,
  `war_id` integer NOT NULL,
  `opponent_name` text NOT NULL,
  `started_at` integer NOT NULL,
  `target` integer DEFAULT 0 NOT NULL,
  `our_score` integer DEFAULT 0 NOT NULL,
  `their_score` integer DEFAULT 0 NOT NULL,
  `our_chain` integer DEFAULT 0 NOT NULL,
  `their_chain` integer DEFAULT 0 NOT NULL,
  `members_json` text DEFAULT '[]' NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`, `war_id`)
);
--> statement-breakpoint
INSERT INTO `__new_active_war` SELECT COALESCE(`faction_id`,52984),`war_id`,`opponent_name`,`started_at`,`target`,`our_score`,`their_score`,`our_chain`,`their_chain`,`members_json`,`updated_at` FROM `active_war`;
--> statement-breakpoint
DROP TABLE `active_war`;
--> statement-breakpoint
ALTER TABLE `__new_active_war` RENAME TO `active_war`;
--> statement-breakpoint

CREATE TABLE `__new_war_member_baselines` (
  `faction_id` integer NOT NULL,
  `war_id` integer NOT NULL,
  `user_id` integer NOT NULL,
  `name` text NOT NULL,
  `base_hits` integer DEFAULT 0 NOT NULL,
  `base_xanax` integer DEFAULT 0 NOT NULL,
  `base_refills` integer DEFAULT 0 NOT NULL,
  `current_hits` integer DEFAULT 0 NOT NULL,
  `current_xanax` integer DEFAULT 0 NOT NULL,
  `current_refills` integer DEFAULT 0 NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`war_id`,`user_id`)
);
--> statement-breakpoint
INSERT INTO `__new_war_member_baselines` (`faction_id`,`war_id`,`user_id`,`name`,`base_hits`,`base_xanax`,`base_refills`,`current_hits`,`current_xanax`,`current_refills`,`updated_at`)
  SELECT 52984,`war_id`,`user_id`,`name`,`base_hits`,`base_xanax`,`base_refills`,`current_hits`,`current_xanax`,`current_refills`,`updated_at` FROM `war_member_baselines`;
--> statement-breakpoint
DROP TABLE `war_member_baselines`;
--> statement-breakpoint
ALTER TABLE `__new_war_member_baselines` RENAME TO `war_member_baselines`;
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `treasury_leaders` (
  `email` text PRIMARY KEY NOT NULL COLLATE NOCASE,
  `display_name` text DEFAULT '' NOT NULL,
  `added_by` text DEFAULT '' NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `__new_treasury_leaders` (
  `faction_id` integer NOT NULL,
  `email` text NOT NULL COLLATE NOCASE,
  `display_name` text DEFAULT '' NOT NULL,
  `added_by` text DEFAULT '' NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`email`)
);
--> statement-breakpoint
INSERT INTO `__new_treasury_leaders` SELECT 52984,`email`,`display_name`,`added_by`,`created_at` FROM `treasury_leaders`;
--> statement-breakpoint
DROP TABLE `treasury_leaders`;
--> statement-breakpoint
ALTER TABLE `__new_treasury_leaders` RENAME TO `treasury_leaders`;
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `member_balances` (
  `member_name` text PRIMARY KEY NOT NULL COLLATE NOCASE,
  `member_id` integer,
  `balance` integer DEFAULT 0 NOT NULL,
  `earned_total` integer DEFAULT 0 NOT NULL,
  `paid_total` integer DEFAULT 0 NOT NULL,
  `observed_at` text,
  `observed_priority` integer DEFAULT 0 NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `__new_member_balances` (
  `id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  `faction_id` integer NOT NULL,
  `member_id` integer,
  `member_name` text NOT NULL COLLATE NOCASE,
  `balance` integer DEFAULT 0 NOT NULL,
  `earned_total` integer DEFAULT 0 NOT NULL,
  `paid_total` integer DEFAULT 0 NOT NULL,
  `observed_at` text,
  `observed_priority` integer DEFAULT 0 NOT NULL,
  `resolution_status` text DEFAULT 'unresolved' NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT `member_balances_nonnegative` CHECK(`balance` >= 0 AND `earned_total` >= 0 AND `paid_total` >= 0)
);
--> statement-breakpoint
INSERT INTO `__new_member_balances` (`faction_id`,`member_id`,`member_name`,`balance`,`earned_total`,`paid_total`,`observed_at`,`observed_priority`,`resolution_status`,`updated_at`)
SELECT 52984,
  CASE WHEN `member_id` IS NOT NULL AND (SELECT COUNT(*) FROM `member_balances` AS duplicate WHERE duplicate.`member_id` = source.`member_id`) = 1 THEN `member_id` ELSE NULL END,
  `member_name`,`balance`,`earned_total`,`paid_total`,`observed_at`,`observed_priority`,
  CASE WHEN `member_id` IS NOT NULL AND (SELECT COUNT(*) FROM `member_balances` AS duplicate WHERE duplicate.`member_id` = source.`member_id`) = 1 THEN 'verified' ELSE 'unresolved' END,
  `updated_at`
FROM `member_balances` AS source;
--> statement-breakpoint
DROP TABLE `member_balances`;
--> statement-breakpoint
ALTER TABLE `__new_member_balances` RENAME TO `member_balances`;
--> statement-breakpoint
CREATE UNIQUE INDEX `member_balances_faction_member_unique` ON `member_balances` (`faction_id`,`member_id`) WHERE `member_id` IS NOT NULL;
--> statement-breakpoint
CREATE INDEX `idx_member_balances_faction_name` ON `member_balances` (`faction_id`,`member_name`);
--> statement-breakpoint
INSERT OR IGNORE INTO `faction_members` (`faction_id`,`member_id`,`member_name`,`last_verified_at`)
  SELECT 52984,`member_id`,`member_name`,COALESCE(`observed_at`,`updated_at`) FROM `member_balances` WHERE `member_id` IS NOT NULL;
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `member_balance_entries` (
  `event_key` text PRIMARY KEY NOT NULL,
  `member_id` integer,
  `member_name` text NOT NULL COLLATE NOCASE,
  `amount` integer NOT NULL,
  `kind` text NOT NULL,
  `source` text NOT NULL,
  `summary` text DEFAULT '' NOT NULL,
  `occurred_at` text,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `__new_member_balance_entries` (
  `faction_id` integer NOT NULL,
  `event_key` text NOT NULL,
  `member_id` integer,
  `member_name` text NOT NULL COLLATE NOCASE,
  `amount` integer NOT NULL,
  `kind` text NOT NULL,
  `source` text NOT NULL,
  `summary` text DEFAULT '' NOT NULL,
  `occurred_at` text,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`event_key`)
);
--> statement-breakpoint
INSERT INTO `__new_member_balance_entries` SELECT 52984,`event_key`,`member_id`,`member_name`,`amount`,`kind`,`source`,`summary`,`occurred_at`,`created_at` FROM `member_balance_entries`;
--> statement-breakpoint
DROP TABLE `member_balance_entries`;
--> statement-breakpoint
ALTER TABLE `__new_member_balance_entries` RENAME TO `member_balance_entries`;
--> statement-breakpoint
CREATE INDEX `idx_member_entries_faction_created` ON `member_balance_entries` (`faction_id`,`created_at`);
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `member_balance_observations` (
  `event_key` text PRIMARY KEY NOT NULL,
  `member_id` integer,
  `member_name` text NOT NULL COLLATE NOCASE,
  `old_balance` integer NOT NULL,
  `new_balance` integer NOT NULL,
  `delta` integer NOT NULL,
  `direction` text NOT NULL,
  `summary` text DEFAULT '' NOT NULL,
  `occurred_at` text,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `__new_member_balance_observations` (
  `faction_id` integer NOT NULL,
  `event_key` text NOT NULL,
  `member_id` integer,
  `member_name` text NOT NULL COLLATE NOCASE,
  `old_balance` integer NOT NULL,
  `new_balance` integer NOT NULL,
  `delta` integer NOT NULL,
  `direction` text NOT NULL,
  `summary` text DEFAULT '' NOT NULL,
  `occurred_at` text,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`event_key`)
);
--> statement-breakpoint
INSERT INTO `__new_member_balance_observations` SELECT 52984,`event_key`,`member_id`,`member_name`,`old_balance`,`new_balance`,`delta`,`direction`,`summary`,`occurred_at`,`created_at` FROM `member_balance_observations`;
--> statement-breakpoint
DROP TABLE `member_balance_observations`;
--> statement-breakpoint
ALTER TABLE `__new_member_balance_observations` RENAME TO `member_balance_observations`;
--> statement-breakpoint
CREATE INDEX `idx_member_observations_faction_created` ON `member_balance_observations` (`faction_id`,`created_at`);
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `payout_requests` (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `member_id` integer NOT NULL,
  `member_name` text NOT NULL COLLATE NOCASE,
  `amount` integer NOT NULL,
  `status` text DEFAULT 'pending' NOT NULL,
  `delivery_preference` text DEFAULT 'offline' NOT NULL,
  `note` text DEFAULT '' NOT NULL,
  `requested_by_user_id` text NOT NULL,
  `requested_by_email` text NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `__new_payout_requests` (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `faction_id` integer NOT NULL,
  `member_id` integer NOT NULL,
  `member_name` text NOT NULL COLLATE NOCASE,
  `amount` integer NOT NULL,
  `status` text DEFAULT 'pending' NOT NULL,
  `delivery_preference` text DEFAULT 'offline' NOT NULL,
  `note` text DEFAULT '' NOT NULL,
  `requested_by_user_id` text NOT NULL,
  `requested_by_email` text NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_payout_requests` (`id`,`faction_id`,`member_id`,`member_name`,`amount`,`status`,`delivery_preference`,`note`,`requested_by_user_id`,`requested_by_email`,`created_at`,`updated_at`)
  SELECT `id`,52984,`member_id`,`member_name`,`amount`,`status`,`delivery_preference`,`note`,`requested_by_user_id`,`requested_by_email`,`created_at`,`updated_at` FROM `payout_requests`;
--> statement-breakpoint
DROP TABLE `payout_requests`;
--> statement-breakpoint
ALTER TABLE `__new_payout_requests` RENAME TO `payout_requests`;
--> statement-breakpoint
CREATE INDEX `idx_payout_requests_faction_status` ON `payout_requests` (`faction_id`,`status`,`created_at`);
--> statement-breakpoint
CREATE INDEX `idx_payout_requests_faction_member` ON `payout_requests` (`faction_id`,`member_id`);
--> statement-breakpoint

CREATE TABLE `__new_oc_holdings` (
  `faction_id` integer NOT NULL,
  `event_key` text NOT NULL,
  `crime_name` text NOT NULL,
  `status` text DEFAULT 'held' NOT NULL,
  `cash_amount` integer DEFAULT 0 NOT NULL,
  `items_json` text DEFAULT '[]' NOT NULL,
  `summary` text DEFAULT '' NOT NULL,
  `occurred_at` text,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`event_key`)
);
--> statement-breakpoint
INSERT INTO `__new_oc_holdings` SELECT 52984,`event_key`,`crime_name`,`status`,`cash_amount`,`items_json`,`summary`,`occurred_at`,`created_at`,`updated_at` FROM `oc_holdings`;
--> statement-breakpoint
DROP TABLE `oc_holdings`;
--> statement-breakpoint
ALTER TABLE `__new_oc_holdings` RENAME TO `oc_holdings`;
--> statement-breakpoint
CREATE INDEX `idx_oc_holdings_faction_status_created` ON `oc_holdings` (`faction_id`,`status`,`created_at`);
--> statement-breakpoint

DROP TRIGGER IF EXISTS `apply_armory_item_effect`;
--> statement-breakpoint
CREATE TABLE `__new_armory_items` (
  `faction_id` integer NOT NULL,
  `item_name` text NOT NULL COLLATE NOCASE,
  `category` text DEFAULT 'other' NOT NULL,
  `quantity` integer DEFAULT 0 NOT NULL,
  `source` text DEFAULT 'activity' NOT NULL,
  `observed_at` text,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`item_name`)
);
--> statement-breakpoint
INSERT INTO `__new_armory_items` (`faction_id`,`item_name`,`category`,`quantity`,`source`,`observed_at`,`updated_at`)
  SELECT 52984,`item_name`,`category`,`quantity`,`source`,NULL,`updated_at` FROM `armory_items`;
--> statement-breakpoint
DROP TABLE `armory_items`;
--> statement-breakpoint
ALTER TABLE `__new_armory_items` RENAME TO `armory_items`;
--> statement-breakpoint
CREATE INDEX `idx_armory_items_faction_category_name` ON `armory_items` (`faction_id`,`category`,`item_name`);
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `armory_snapshot_state` (
  `category` text PRIMARY KEY NOT NULL,
  `event_key` text NOT NULL,
  `observed_at` text NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `__new_armory_snapshot_state` (
  `faction_id` integer NOT NULL,
  `category` text NOT NULL,
  `event_key` text NOT NULL,
  `observed_at` text NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`category`)
);
--> statement-breakpoint
INSERT INTO `__new_armory_snapshot_state` SELECT 52984,`category`,`event_key`,`observed_at`,`updated_at` FROM `armory_snapshot_state`;
--> statement-breakpoint
DROP TABLE `armory_snapshot_state`;
--> statement-breakpoint
ALTER TABLE `__new_armory_snapshot_state` RENAME TO `armory_snapshot_state`;
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `armory_item_effects` (
  `event_key` text NOT NULL,
  `item_name` text NOT NULL COLLATE NOCASE,
  `delta` integer DEFAULT 0 NOT NULL,
  `category` text DEFAULT 'other' NOT NULL,
  `source` text DEFAULT 'activity' NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`event_key`,`item_name`)
);
--> statement-breakpoint
CREATE TABLE `__new_armory_item_effects` (
  `faction_id` integer NOT NULL,
  `event_key` text NOT NULL,
  `item_name` text NOT NULL COLLATE NOCASE,
  `delta` integer DEFAULT 0 NOT NULL,
  `category` text DEFAULT 'other' NOT NULL,
  `source` text DEFAULT 'activity' NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`event_key`,`item_name`)
);
--> statement-breakpoint
INSERT INTO `__new_armory_item_effects` SELECT 52984,`event_key`,`item_name`,`delta`,`category`,`source`,`created_at` FROM `armory_item_effects`;
--> statement-breakpoint
DROP TABLE `armory_item_effects`;
--> statement-breakpoint
ALTER TABLE `__new_armory_item_effects` RENAME TO `armory_item_effects`;
--> statement-breakpoint
CREATE TRIGGER `apply_armory_item_effect` AFTER INSERT ON `armory_item_effects`
WHEN NEW.`delta` != 0 BEGIN
  INSERT INTO `armory_items` (`faction_id`,`item_name`,`category`,`quantity`,`source`)
  VALUES (NEW.`faction_id`,NEW.`item_name`,NEW.`category`,MAX(0,NEW.`delta`),NEW.`source`)
  ON CONFLICT(`faction_id`,`item_name`) DO UPDATE SET
    `quantity`=MAX(0,`armory_items`.`quantity`+NEW.`delta`),
    `category`=CASE WHEN NEW.`category`='other' THEN `armory_items`.`category` ELSE NEW.`category` END,
    `source`=NEW.`source`,`updated_at`=CURRENT_TIMESTAMP;
END;
--> statement-breakpoint

CREATE TABLE `__new_torn_browser_events` (
  `faction_id` integer NOT NULL,
  `event_key` text NOT NULL,
  `event_type` text NOT NULL,
  `category` text NOT NULL,
  `occurred_at` text,
  `summary` text NOT NULL,
  `source_url` text DEFAULT '' NOT NULL,
  `payload_json` text DEFAULT '{}' NOT NULL,
  `first_observed_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `last_observed_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`event_key`)
);
--> statement-breakpoint
INSERT INTO `__new_torn_browser_events` (`faction_id`,`event_key`,`event_type`,`category`,`occurred_at`,`summary`,`source_url`,`payload_json`,`first_observed_at`,`last_observed_at`,`created_at`)
  SELECT 52984,`event_key`,`event_type`,`category`,`occurred_at`,`summary`,`source_url`,`payload_json`,`created_at`,`created_at`,`created_at` FROM `torn_browser_events`;
--> statement-breakpoint
DROP TABLE `torn_browser_events`;
--> statement-breakpoint
ALTER TABLE `__new_torn_browser_events` RENAME TO `torn_browser_events`;
--> statement-breakpoint
CREATE INDEX `idx_torn_browser_events_faction_created` ON `torn_browser_events` (`faction_id`,`created_at`);
--> statement-breakpoint
CREATE TABLE `event_observers` (
  `faction_id` integer NOT NULL,
  `event_key` text NOT NULL,
  `observer_token_id` text NOT NULL,
  `observer_member_id` integer NOT NULL,
  `first_observed_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `last_observed_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`event_key`,`observer_token_id`)
);
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `torn_sync_cursors` (
  `source_key` text PRIMARY KEY NOT NULL,
  `next_offset` integer DEFAULT 0 NOT NULL,
  `complete` integer DEFAULT 0 NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `__new_torn_sync_cursors` (
  `faction_id` integer NOT NULL,
  `source_key` text NOT NULL,
  `next_offset` integer DEFAULT 0 NOT NULL,
  `complete` integer DEFAULT 0 NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`source_key`)
);
--> statement-breakpoint
INSERT INTO `__new_torn_sync_cursors` SELECT 52984,`source_key`,`next_offset`,`complete`,`updated_at` FROM `torn_sync_cursors`;
--> statement-breakpoint
DROP TABLE `torn_sync_cursors`;
--> statement-breakpoint
ALTER TABLE `__new_torn_sync_cursors` RENAME TO `torn_sync_cursors`;
--> statement-breakpoint

CREATE TABLE IF NOT EXISTS `script_sync_tokens` (
  `token_id` text PRIMARY KEY NOT NULL,
  `member_id` integer NOT NULL,
  `member_name` text NOT NULL COLLATE NOCASE,
  `faction_id` integer,
  `faction_name` text DEFAULT '' NOT NULL,
  `token_hash` text NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `last_used_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `last_verified_at` text,
  `expires_at` text,
  `revoked_at` text,
  `revoked_reason` text
);
--> statement-breakpoint
CREATE TABLE `__new_script_sync_tokens` (
  `token_id` text PRIMARY KEY NOT NULL,
  `member_id` integer NOT NULL,
  `member_name` text NOT NULL COLLATE NOCASE,
  `faction_id` integer NOT NULL,
  `faction_name` text DEFAULT '' NOT NULL,
  `token_hash` text NOT NULL,
  `created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `last_used_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  `last_verified_at` text,
  `expires_at` text,
  `revoked_at` text,
  `revoked_reason` text,
  `last_queue_depth` integer DEFAULT 0 NOT NULL,
  `last_direct_push_at` text
);
--> statement-breakpoint
INSERT INTO `__new_script_sync_tokens` (`token_id`,`member_id`,`member_name`,`faction_id`,`faction_name`,`token_hash`,`created_at`,`last_used_at`,`last_verified_at`,`expires_at`,`revoked_at`,`revoked_reason`)
  SELECT `token_id`,`member_id`,`member_name`,COALESCE(`faction_id`,52984),CASE WHEN `faction_name`='' THEN 'Blood Coven' ELSE `faction_name` END,`token_hash`,`created_at`,`last_used_at`,COALESCE(`last_verified_at`,`created_at`),`expires_at`,`revoked_at`,`revoked_reason` FROM `script_sync_tokens`;
--> statement-breakpoint
DROP TABLE `script_sync_tokens`;
--> statement-breakpoint
ALTER TABLE `__new_script_sync_tokens` RENAME TO `script_sync_tokens`;
--> statement-breakpoint
CREATE INDEX `idx_script_sync_faction_member` ON `script_sync_tokens` (`faction_id`,`member_id`,`revoked_at`,`last_used_at`);
--> statement-breakpoint

CREATE TABLE `sync_telemetry` (
  `faction_id` integer NOT NULL,
  `source_key` text NOT NULL,
  `last_success_at` text,
  `last_observation_at` text,
  `queue_depth` integer DEFAULT 0 NOT NULL,
  `details_json` text DEFAULT '{}' NOT NULL,
  `updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
  PRIMARY KEY(`faction_id`,`source_key`)
);
--> statement-breakpoint
PRAGMA foreign_keys=ON;
