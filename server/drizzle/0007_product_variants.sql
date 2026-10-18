-- Product sizes (variants): stock, movements and sold items move from the product to one of its sizes.
-- Every existing product becomes a product with one size that has the same id, its old `size` text as the name and
-- its whole stock, so movements and sale items are linked by `variant_id = product_id`.
CREATE TABLE `product_services` (
	`product_id` integer NOT NULL,
	`service_id` integer NOT NULL,
	PRIMARY KEY(`product_id`, `service_id`),
	FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`service_id`) REFERENCES `services`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `product_services_service_idx` ON `product_services` (`service_id`);--> statement-breakpoint
CREATE TABLE `product_variants` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`product_id` integer NOT NULL,
	`name` text DEFAULT '' NOT NULL,
	`sku` text,
	`price` integer,
	`cost` integer,
	`quantity` integer DEFAULT 0 NOT NULL,
	`min_quantity` integer DEFAULT 0 NOT NULL,
	`archived` integer DEFAULT false NOT NULL,
	`position` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "product_variants_quantity_non_negative" CHECK("product_variants"."quantity" >= 0)
);
--> statement-breakpoint
CREATE INDEX `product_variants_product_idx` ON `product_variants` (`product_id`,`position`);--> statement-breakpoint
INSERT INTO `product_variants` (`id`, `product_id`, `name`, `quantity`, `min_quantity`, `position`, `created_at`, `updated_at`)
SELECT `id`, `id`, coalesce(trim(`size`), ''), max(`quantity`, 0), max(`min_quantity`, 0), 0, `created_at`, `updated_at`
FROM `products`;--> statement-breakpoint
ALTER TABLE `products` ADD `thread_type` text;--> statement-breakpoint
ALTER TABLE `products` ADD `thickness_mm` real;--> statement-breakpoint
ALTER TABLE `products` ADD `color` text;--> statement-breakpoint
ALTER TABLE `products` ADD `stone` text;--> statement-breakpoint
ALTER TABLE `products` ADD `supplier` text;--> statement-breakpoint
ALTER TABLE `products` ADD `photos_json` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
UPDATE `products` SET `photos_json` = json_array(`photo_url`) WHERE trim(coalesce(`photo_url`, '')) <> '';--> statement-breakpoint
ALTER TABLE `products` DROP COLUMN `size`;--> statement-breakpoint
ALTER TABLE `products` DROP COLUMN `quantity`;--> statement-breakpoint
ALTER TABLE `products` DROP COLUMN `min_quantity`;--> statement-breakpoint
-- Items sold before sizes existed keep `variant_name` NULL: the size at the moment of sale is unknown.
ALTER TABLE `sale_items` ADD `variant_id` integer REFERENCES product_variants(id);--> statement-breakpoint
ALTER TABLE `sale_items` ADD `variant_name` text;--> statement-breakpoint
UPDATE `sale_items` SET `variant_id` = `product_id` WHERE `type` = 'product' AND `product_id` IS NOT NULL;--> statement-breakpoint
-- stock_movements gets a required `variant_id`, which SQLite can only add by rebuilding the table. Nothing references
-- stock_movements, so the rebuild is safe with foreign keys on (the migrator runs inside a transaction).
CREATE TABLE `__new_stock_movements` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`product_id` integer NOT NULL,
	`variant_id` integer NOT NULL,
	`delta` integer NOT NULL,
	`quantity_after` integer NOT NULL,
	`type` text NOT NULL,
	`note` text,
	`sale_id` integer,
	`appointment_id` integer,
	`employee_id` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`variant_id`) REFERENCES `product_variants`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`sale_id`) REFERENCES `sales`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`appointment_id`) REFERENCES `appointments`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
INSERT INTO `__new_stock_movements`("id", "product_id", "variant_id", "delta", "quantity_after", "type", "note", "sale_id", "appointment_id", "employee_id", "created_at") SELECT "id", "product_id", "product_id", "delta", "quantity_after", "type", "note", "sale_id", "appointment_id", "employee_id", "created_at" FROM `stock_movements`;--> statement-breakpoint
DROP TABLE `stock_movements`;--> statement-breakpoint
ALTER TABLE `__new_stock_movements` RENAME TO `stock_movements`;--> statement-breakpoint
CREATE INDEX `stock_movements_product_idx` ON `stock_movements` (`product_id`,`id`);--> statement-breakpoint
CREATE INDEX `stock_movements_variant_idx` ON `stock_movements` (`variant_id`,`id`);--> statement-breakpoint
CREATE INDEX `stock_movements_type_idx` ON `stock_movements` (`type`);
