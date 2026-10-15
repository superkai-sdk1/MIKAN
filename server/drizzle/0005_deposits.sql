-- qr_payments: prepayment codes (kind 'deposit', linked to an appointment, no cart) next to checkout codes.
-- The migrator runs inside a transaction, where the PRAGMAs below are no-ops: the rebuild is safe only because no
-- table references qr_payments yet (deposit_operations is created after it).
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_qr_payments` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`kind` text DEFAULT 'sale' NOT NULL,
	`appointment_id` integer,
	`provider` text NOT NULL,
	`external_id` text NOT NULL,
	`payload` text NOT NULL,
	`amount` integer NOT NULL,
	`status` text NOT NULL,
	`sale_input_json` text,
	`sale_id` integer,
	`error` text,
	`employee_id` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`checked_at` integer,
	`paid_at` integer,
	`sent_at` integer,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`appointment_id`) REFERENCES `appointments`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`sale_id`) REFERENCES `sales`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
INSERT INTO `__new_qr_payments`("id", "provider", "external_id", "payload", "amount", "status", "sale_input_json", "sale_id", "error", "employee_id", "expires_at", "checked_at", "paid_at", "created_at", "updated_at") SELECT "id", "provider", "external_id", "payload", "amount", "status", "sale_input_json", "sale_id", "error", "employee_id", "expires_at", "checked_at", "paid_at", "created_at", "updated_at" FROM `qr_payments`;--> statement-breakpoint
DROP TABLE `qr_payments`;--> statement-breakpoint
ALTER TABLE `__new_qr_payments` RENAME TO `qr_payments`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `qr_payments_external_id_unique` ON `qr_payments` (`external_id`);--> statement-breakpoint
CREATE INDEX `qr_payments_status_idx` ON `qr_payments` (`status`,`expires_at`);--> statement-breakpoint
CREATE INDEX `qr_payments_appointment_idx` ON `qr_payments` (`appointment_id`);--> statement-breakpoint
CREATE TABLE `deposit_operations` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`appointment_id` integer NOT NULL,
	`type` text NOT NULL,
	`amount` integer NOT NULL,
	`method` text,
	`shift_id` integer,
	`sale_id` integer,
	`qr_payment_id` integer,
	`note` text,
	`employee_id` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`appointment_id`) REFERENCES `appointments`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`shift_id`) REFERENCES `cash_shifts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`sale_id`) REFERENCES `sales`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`qr_payment_id`) REFERENCES `qr_payments`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "deposit_operations_amount_positive" CHECK("amount" > 0)
);
--> statement-breakpoint
CREATE INDEX `deposit_operations_appointment_idx` ON `deposit_operations` (`appointment_id`,`id`);--> statement-breakpoint
CREATE INDEX `deposit_operations_shift_idx` ON `deposit_operations` (`shift_id`);--> statement-breakpoint
CREATE INDEX `deposit_operations_created_idx` ON `deposit_operations` (`created_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `deposit_operations_qr_receive_unique` ON `deposit_operations` (`qr_payment_id`) WHERE type = 'receive';--> statement-breakpoint
CREATE UNIQUE INDEX `deposit_operations_sale_type_unique` ON `deposit_operations` (`sale_id`,`type`) WHERE sale_id is not null;--> statement-breakpoint
ALTER TABLE `appointments` ADD `deposit_required` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `sales` ADD `pay_deposit` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `services` ADD `deposit_amount` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
-- The legacy `appointments.deposit` meant «prepayment already received» (the app moved it into «перевод» at checkout).
-- Appointments that still await payment keep it as held money: a `receive` by transfer dated at the last edit (the
-- closest known moment the studio recorded it). Paid appointments already counted it in their sale; for cancelled /
-- no-show ones the old app had no way to record what became of it, so it stays only as `deposit_required`.
INSERT INTO `deposit_operations` (`appointment_id`, `type`, `amount`, `method`, `note`, `created_at`)
SELECT `id`, 'receive', `deposit`, 'transfer', 'Предоплата из прежней версии приложения', `updated_at`
FROM `appointments`
WHERE `deposit` > 0 AND `sale_id` IS NULL AND `status` IN ('scheduled', 'confirmed', 'completed');--> statement-breakpoint
UPDATE `appointments` SET `deposit_required` = `deposit` WHERE `deposit` > 0;--> statement-breakpoint
ALTER TABLE `appointments` DROP COLUMN `deposit`;
