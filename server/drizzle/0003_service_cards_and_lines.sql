CREATE TABLE `appointment_services` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`appointment_id` integer NOT NULL,
	`service_id` integer,
	`name` text NOT NULL,
	`price` integer NOT NULL,
	`duration_min` integer,
	`position` integer NOT NULL,
	FOREIGN KEY (`appointment_id`) REFERENCES `appointments`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`service_id`) REFERENCES `services`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `appointment_services_appointment_idx` ON `appointment_services` (`appointment_id`,`position`);--> statement-breakpoint
CREATE INDEX `appointment_services_service_idx` ON `appointment_services` (`service_id`);--> statement-breakpoint
ALTER TABLE `services` ADD `group_name` text;--> statement-breakpoint
ALTER TABLE `services` ADD `price_max` integer;--> statement-breakpoint
ALTER TABLE `services` ADD `image_url` text;--> statement-breakpoint
ALTER TABLE `services` ADD `image_prompt` text;--> statement-breakpoint
ALTER TABLE `services` ADD `photos_json` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
ALTER TABLE `services` ADD `variants_json` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
-- Existing single-service appointments become one service line each (price = the appointment price).
INSERT INTO `appointment_services` (`appointment_id`, `service_id`, `name`, `price`, `duration_min`, `position`)
SELECT a.`id`, a.`service_id`, s.`name`, a.`price`, s.`duration_min`, 0
FROM `appointments` a JOIN `services` s ON s.`id` = a.`service_id`;
