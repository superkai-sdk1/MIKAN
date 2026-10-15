CREATE TABLE `aftercare_templates` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`category` text NOT NULL,
	`steps_json` text NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `ai_usage` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`chat_id` integer,
	`outcome` text NOT NULL,
	`input_tokens` integer DEFAULT 0 NOT NULL,
	`output_tokens` integer DEFAULT 0 NOT NULL,
	`cache_read_tokens` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `ai_usage_created_idx` ON `ai_usage` (`created_at`);--> statement-breakpoint
CREATE INDEX `ai_usage_chat_idx` ON `ai_usage` (`chat_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `appointments` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`client_id` integer NOT NULL,
	`master_id` integer NOT NULL,
	`service_id` integer,
	`title` text,
	`starts_at` integer NOT NULL,
	`ends_at` integer NOT NULL,
	`status` text NOT NULL,
	`price` integer DEFAULT 0 NOT NULL,
	`deposit` integer DEFAULT 0 NOT NULL,
	`notes` text,
	`sale_id` integer,
	`completed_at` integer,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`client_id`) REFERENCES `clients`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`master_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`service_id`) REFERENCES `services`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `appointments_starts_idx` ON `appointments` (`starts_at`);--> statement-breakpoint
CREATE INDEX `appointments_master_idx` ON `appointments` (`master_id`,`starts_at`);--> statement-breakpoint
CREATE INDEX `appointments_client_idx` ON `appointments` (`client_id`);--> statement-breakpoint
CREATE TABLE `booking_requests` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`chat_id` integer,
	`client_id` integer,
	`contact_name` text NOT NULL,
	`phone` text,
	`service_name` text,
	`preferred_time` text,
	`comment` text,
	`status` text NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`client_id`) REFERENCES `clients`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE TABLE `bot_chats` (
	`chat_id` integer PRIMARY KEY NOT NULL,
	`client_id` integer,
	`telegram_name` text,
	`username` text,
	`ai_paused` integer DEFAULT false NOT NULL,
	`needs_attention` integer DEFAULT false NOT NULL,
	`unread_count` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`client_id`) REFERENCES `clients`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE TABLE `bot_messages` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`chat_id` integer NOT NULL,
	`role` text NOT NULL,
	`text` text NOT NULL,
	`employee_id` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`chat_id`) REFERENCES `bot_chats`(`chat_id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `bot_messages_chat_idx` ON `bot_messages` (`chat_id`,`id`);--> statement-breakpoint
CREATE TABLE `cash_operations` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`shift_id` integer NOT NULL,
	`type` text NOT NULL,
	`amount` integer NOT NULL,
	`reason` text NOT NULL,
	`employee_id` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`shift_id`) REFERENCES `cash_shifts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `cash_operations_shift_idx` ON `cash_operations` (`shift_id`);--> statement-breakpoint
CREATE TABLE `cash_shifts` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`opened_at` integer NOT NULL,
	`opened_by_id` integer NOT NULL,
	`opening_cash` integer NOT NULL,
	`closed_at` integer,
	`closed_by_id` integer,
	`closing_cash` integer,
	`expected_cash` integer,
	`note` text,
	FOREIGN KEY (`opened_by_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`closed_by_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `cash_shifts_opened_idx` ON `cash_shifts` (`opened_at`);--> statement-breakpoint
CREATE TABLE `clients` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`name_sort` text NOT NULL,
	`phone` text,
	`instagram` text,
	`birthday` text,
	`notes` text,
	`source` text,
	`telegram_chat_id` integer,
	`telegram_username` text,
	`bot_enabled` integer DEFAULT true NOT NULL,
	`archived` integer DEFAULT false NOT NULL,
	`link_token` text,
	`search_text` text DEFAULT '' NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `clients_phone_unique` ON `clients` (`phone`);--> statement-breakpoint
CREATE UNIQUE INDEX `clients_telegram_chat_id_unique` ON `clients` (`telegram_chat_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `clients_link_token_unique` ON `clients` (`link_token`);--> statement-breakpoint
CREATE INDEX `clients_name_sort_idx` ON `clients` (`name_sort`);--> statement-breakpoint
CREATE INDEX `clients_created_idx` ON `clients` (`created_at`);--> statement-breakpoint
CREATE TABLE `employees` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`login` text NOT NULL,
	`password_hash` text NOT NULL,
	`phone` text,
	`color` text NOT NULL,
	`is_master` integer DEFAULT false NOT NULL,
	`active` integer DEFAULT true NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `employees_login_unique` ON `employees` (`login`);--> statement-breakpoint
CREATE TABLE `knowledge_entries` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`title` text NOT NULL,
	`content` text NOT NULL,
	`active` integer DEFAULT true NOT NULL,
	`sort` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `products` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`kind` text NOT NULL,
	`name` text NOT NULL,
	`name_sort` text NOT NULL,
	`sku` text,
	`category` text,
	`category_sort` text DEFAULT '' NOT NULL,
	`material` text,
	`size` text,
	`description` text,
	`price` integer NOT NULL,
	`cost` integer,
	`quantity` integer DEFAULT 0 NOT NULL,
	`min_quantity` integer DEFAULT 0 NOT NULL,
	`unit` text DEFAULT 'шт' NOT NULL,
	`photo_url` text,
	`active` integer DEFAULT true NOT NULL,
	`search_text` text DEFAULT '' NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `products_kind_idx` ON `products` (`kind`);--> statement-breakpoint
CREATE TABLE `sale_items` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`sale_id` integer NOT NULL,
	`type` text NOT NULL,
	`product_id` integer,
	`service_id` integer,
	`name` text NOT NULL,
	`quantity` integer NOT NULL,
	`price` integer NOT NULL,
	`total` integer NOT NULL,
	FOREIGN KEY (`sale_id`) REFERENCES `sales`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`service_id`) REFERENCES `services`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `sale_items_sale_idx` ON `sale_items` (`sale_id`);--> statement-breakpoint
CREATE TABLE `sales` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`number` integer NOT NULL,
	`client_id` integer,
	`employee_id` integer NOT NULL,
	`appointment_id` integer,
	`shift_id` integer,
	`subtotal` integer NOT NULL,
	`discount` integer DEFAULT 0 NOT NULL,
	`total` integer NOT NULL,
	`pay_cash` integer DEFAULT 0 NOT NULL,
	`pay_card` integer DEFAULT 0 NOT NULL,
	`pay_transfer` integer DEFAULT 0 NOT NULL,
	`status` text NOT NULL,
	`note` text,
	`refunded_at` integer,
	`refund_reason` text,
	`refund_shift_id` integer,
	`refunded_by_id` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`client_id`) REFERENCES `clients`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`appointment_id`) REFERENCES `appointments`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`shift_id`) REFERENCES `cash_shifts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`refund_shift_id`) REFERENCES `cash_shifts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`refunded_by_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `sales_number_unique` ON `sales` (`number`);--> statement-breakpoint
CREATE INDEX `sales_created_idx` ON `sales` (`created_at`);--> statement-breakpoint
CREATE INDEX `sales_client_idx` ON `sales` (`client_id`);--> statement-breakpoint
CREATE INDEX `sales_shift_idx` ON `sales` (`shift_id`);--> statement-breakpoint
CREATE INDEX `sales_refund_shift_idx` ON `sales` (`refund_shift_id`);--> statement-breakpoint
CREATE TABLE `scheduled_messages` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`chat_id` integer NOT NULL,
	`client_id` integer NOT NULL,
	`appointment_id` integer,
	`kind` text NOT NULL,
	`send_at` integer NOT NULL,
	`text` text NOT NULL,
	`status` text NOT NULL,
	`sent_at` integer,
	`error` text,
	`attempts` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`client_id`) REFERENCES `clients`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`appointment_id`) REFERENCES `appointments`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `scheduled_status_send_idx` ON `scheduled_messages` (`status`,`send_at`);--> statement-breakpoint
CREATE INDEX `scheduled_appointment_idx` ON `scheduled_messages` (`appointment_id`);--> statement-breakpoint
CREATE TABLE `services` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`category` text NOT NULL,
	`price` integer NOT NULL,
	`price_from` integer DEFAULT false NOT NULL,
	`duration_min` integer NOT NULL,
	`description` text,
	`aftercare_template_id` integer,
	`active` integer DEFAULT true NOT NULL,
	`sort` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`aftercare_template_id`) REFERENCES `aftercare_templates`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE TABLE `settings` (
	`key` text PRIMARY KEY NOT NULL,
	`value` text NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `stock_movements` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`product_id` integer NOT NULL,
	`delta` integer NOT NULL,
	`quantity_after` integer NOT NULL,
	`type` text NOT NULL,
	`note` text,
	`sale_id` integer,
	`appointment_id` integer,
	`employee_id` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`sale_id`) REFERENCES `sales`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`appointment_id`) REFERENCES `appointments`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `stock_movements_product_idx` ON `stock_movements` (`product_id`,`id`);--> statement-breakpoint
CREATE INDEX `stock_movements_type_idx` ON `stock_movements` (`type`);