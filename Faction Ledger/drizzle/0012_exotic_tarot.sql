ALTER TABLE `armory_snapshot_state` ADD `items_json` text;--> statement-breakpoint
DROP TRIGGER IF EXISTS `apply_armory_item_effect`;--> statement-breakpoint
CREATE TRIGGER `apply_armory_item_effect`
AFTER INSERT ON `armory_item_effects`
WHEN NEW.`delta` != 0 AND (
  NOT EXISTS (
    SELECT 1 FROM `armory_snapshot_state`
    WHERE `faction_id` = NEW.`faction_id` AND `category` = NEW.`category`
  )
  OR (
    (SELECT `items_json` FROM `armory_snapshot_state`
      WHERE `faction_id` = NEW.`faction_id` AND `category` = NEW.`category`) IS NULL
    AND NEW.`occurred_at` IS NOT NULL
    AND julianday(NEW.`occurred_at`) > julianday((
      SELECT `observed_at` FROM `armory_snapshot_state`
      WHERE `faction_id` = NEW.`faction_id` AND `category` = NEW.`category`
    ))
  )
)
BEGIN
  INSERT INTO `armory_items` (`faction_id`, `item_name`, `category`, `quantity`, `source`, `observed_at`)
  VALUES (NEW.`faction_id`, NEW.`item_name`, NEW.`category`, MAX(0, NEW.`delta`), NEW.`source`, NEW.`occurred_at`)
  ON CONFLICT(`faction_id`, `item_name`) DO UPDATE SET
    `quantity` = MAX(0, `armory_items`.`quantity` + NEW.`delta`),
    `category` = CASE WHEN NEW.`category` = 'other' THEN `armory_items`.`category` ELSE NEW.`category` END,
    `source` = NEW.`source`,
    `observed_at` = COALESCE(NEW.`occurred_at`, `armory_items`.`observed_at`),
    `updated_at` = CURRENT_TIMESTAMP;
END;
