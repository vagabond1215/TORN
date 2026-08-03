CREATE TABLE `armory_items` (
	`item_name` text PRIMARY KEY NOT NULL,
	`category` text DEFAULT 'other' NOT NULL,
	`quantity` integer DEFAULT 0 NOT NULL,
	`source` text DEFAULT 'activity' NOT NULL,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_armory_items_category_name` ON `armory_items` (`category`,`item_name`);
--> statement-breakpoint
CREATE TABLE `oc_holdings` (
	`event_key` text PRIMARY KEY NOT NULL,
	`crime_name` text NOT NULL,
	`status` text DEFAULT 'held' NOT NULL,
	`cash_amount` integer DEFAULT 0 NOT NULL,
	`items_json` text DEFAULT '[]' NOT NULL,
	`summary` text DEFAULT '' NOT NULL,
	`occurred_at` text,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_oc_holdings_status_created` ON `oc_holdings` (`status`,`created_at`);
--> statement-breakpoint
ALTER TABLE `payout_requests` ADD `delivery_preference` text DEFAULT 'offline' NOT NULL;
