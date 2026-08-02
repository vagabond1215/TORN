CREATE TABLE `policies` (
	`source_key` text PRIMARY KEY NOT NULL,
	`label` text NOT NULL,
	`tax_bps` integer DEFAULT 0 NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	`updated_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL,
	CONSTRAINT "policies_tax_range" CHECK("policies"."tax_bps" BETWEEN 0 AND 10000)
);
