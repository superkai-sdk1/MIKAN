-- Warehouse reorganization: a registry of catalog categories (order, empty categories, rename / merge), goods,
-- consumables tracked as «есть / нет», consumption norms of services, stock counts (revisions) and staff chats.
CREATE TABLE `catalog_categories` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`section` text NOT NULL,
	`service_category` text DEFAULT '' NOT NULL,
	`name` text NOT NULL,
	`position` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `catalog_categories_name_unique` ON `catalog_categories` (`section`,`service_category`,`name`);--> statement-breakpoint
CREATE TABLE `service_consumables` (
	`service_id` integer NOT NULL,
	`product_id` integer NOT NULL,
	`quantity` integer DEFAULT 1 NOT NULL,
	PRIMARY KEY(`service_id`, `product_id`),
	FOREIGN KEY (`service_id`) REFERENCES `services`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `service_consumables_product_idx` ON `service_consumables` (`product_id`);--> statement-breakpoint
CREATE TABLE `stock_revisions` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`number` integer NOT NULL,
	`section` text,
	`note` text,
	`employee_id` integer,
	`counted` integer NOT NULL,
	`changed` integer NOT NULL,
	`surplus` integer NOT NULL,
	`shortage` integer NOT NULL,
	`surplus_cost` integer NOT NULL,
	`shortage_cost` integer NOT NULL,
	`presence_json` text DEFAULT '[]' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `stock_revisions_number_unique` ON `stock_revisions` (`number`);--> statement-breakpoint
ALTER TABLE `bot_chats` ADD `employee_id` integer REFERENCES employees(id);--> statement-breakpoint
ALTER TABLE `products` ADD `stock_mode` text DEFAULT 'quantity' NOT NULL;--> statement-breakpoint
ALTER TABLE `products` ADD `presence_status` text DEFAULT 'ok' NOT NULL;--> statement-breakpoint
ALTER TABLE `stock_movements` ADD `revision_id` integer REFERENCES stock_revisions(id);--> statement-breakpoint
-- Items keep linking to categories by name: trim the stored names, then register every category in use.
UPDATE `products` SET `category` = nullif(trim(`category`), '');--> statement-breakpoint
UPDATE `services` SET `group_name` = nullif(trim(`group_name`), '');--> statement-breakpoint
INSERT INTO `catalog_categories` (`section`, `service_category`, `name`, `position`, `created_at`, `updated_at`)
SELECT `kind`, '', `category`, row_number() OVER (PARTITION BY `kind` ORDER BY `category`) - 1, min(`created_at`), min(`created_at`)
FROM `products` WHERE `category` IS NOT NULL GROUP BY `kind`, `category`;--> statement-breakpoint
INSERT INTO `catalog_categories` (`section`, `service_category`, `name`, `position`, `created_at`, `updated_at`)
SELECT 'service', `category`, `group_name`, row_number() OVER (PARTITION BY `category` ORDER BY min(`sort`), `group_name`) - 1, min(`created_at`), min(`created_at`)
FROM `services` WHERE `group_name` IS NOT NULL GROUP BY `category`, `group_name`;
