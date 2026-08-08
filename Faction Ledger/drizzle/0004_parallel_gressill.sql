CREATE TABLE `active_war` (
	`war_id` integer PRIMARY KEY NOT NULL,
	`faction_id` integer NOT NULL,
	`opponent_name` text NOT NULL,
	`started_at` integer NOT NULL,
	`target` integer DEFAULT 0 NOT NULL,
	`our_score` integer DEFAULT 0 NOT NULL,
	`their_score` integer DEFAULT 0 NOT NULL,
	`our_chain` integer DEFAULT 0 NOT NULL,
	`their_chain` integer DEFAULT 0 NOT NULL,
	`members_json` text DEFAULT '[]' NOT NULL,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE TABLE `pending_wars` (
	`war_id` integer PRIMARY KEY NOT NULL,
	`faction_id` integer NOT NULL,
	`opponent_name` text NOT NULL,
	`started_at` integer NOT NULL,
	`ended_at` integer NOT NULL,
	`won` integer DEFAULT 0 NOT NULL,
	`gross_estimate` integer DEFAULT 0 NOT NULL,
	`reviewed_value` integer,
	`status` text DEFAULT 'pending' NOT NULL,
	`rewards_json` text DEFAULT '[]' NOT NULL,
	`members_json` text DEFAULT '[]' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	CONSTRAINT "pending_wars_status" CHECK("pending_wars"."status" IN ('pending', 'recorded', 'dismissed'))
);
--> statement-breakpoint
CREATE INDEX `idx_pending_wars_status_end` ON `pending_wars` (`status`,`ended_at`);--> statement-breakpoint
CREATE TABLE `war_member_baselines` (
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
	PRIMARY KEY(`war_id`, `user_id`)
);
