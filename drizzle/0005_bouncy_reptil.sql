CREATE TABLE `torn_browser_events` (
	`event_key` text PRIMARY KEY NOT NULL,
	`event_type` text NOT NULL,
	`category` text NOT NULL,
	`occurred_at` text,
	`summary` text NOT NULL,
	`source_url` text DEFAULT '' NOT NULL,
	`payload_json` text DEFAULT '{}' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_torn_browser_events_created` ON `torn_browser_events` (`created_at`);