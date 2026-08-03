ALTER TABLE `pending_wars` ADD `reviewed_tax_bps` integer DEFAULT 2000 NOT NULL CHECK (`reviewed_tax_bps` BETWEEN 0 AND 10000);
