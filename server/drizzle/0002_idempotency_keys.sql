CREATE TABLE `idempotency_keys` (
	`key` text NOT NULL,
	`employee_id` integer NOT NULL,
	`endpoint` text NOT NULL,
	`request_hash` text NOT NULL,
	`response_json` text NOT NULL,
	`created_at` integer NOT NULL,
	PRIMARY KEY(`employee_id`, `key`)
);
--> statement-breakpoint
CREATE INDEX `idempotency_keys_created_idx` ON `idempotency_keys` (`created_at`);