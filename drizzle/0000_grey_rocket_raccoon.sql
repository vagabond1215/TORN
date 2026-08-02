CREATE TABLE `accounts` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`allocation_bps` integer DEFAULT 0 NOT NULL,
	`balance` integer DEFAULT 0 NOT NULL,
	`color` text DEFAULT 'lime' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	CONSTRAINT "accounts_allocation_range" CHECK("accounts"."allocation_bps" BETWEEN 0 AND 10000),
	CONSTRAINT "accounts_balance_nonnegative" CHECK("accounts"."balance" >= 0)
);
--> statement-breakpoint
CREATE TABLE `transactions` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`type` text NOT NULL,
	`amount` integer DEFAULT 0 NOT NULL,
	`from_account_id` integer,
	`from_account_name` text,
	`to_account_id` integer,
	`to_account_name` text,
	`note` text DEFAULT '' NOT NULL,
	`details` text DEFAULT '{}' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
