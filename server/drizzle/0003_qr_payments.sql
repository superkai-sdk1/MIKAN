CREATE TABLE `qr_payments` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`provider` text NOT NULL,
	`external_id` text NOT NULL,
	`payload` text NOT NULL,
	`amount` integer NOT NULL,
	`status` text NOT NULL,
	`sale_input_json` text NOT NULL,
	`sale_id` integer,
	`error` text,
	`employee_id` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`checked_at` integer,
	`paid_at` integer,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`sale_id`) REFERENCES `sales`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `qr_payments_external_id_unique` ON `qr_payments` (`external_id`);--> statement-breakpoint
CREATE INDEX `qr_payments_status_idx` ON `qr_payments` (`status`,`expires_at`);--> statement-breakpoint
ALTER TABLE `sales` ADD `pay_qr` integer DEFAULT 0 NOT NULL;