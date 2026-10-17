-- clients: optional last name and a Telegram username typed by staff; existing rows keep NULL in both.
ALTER TABLE `clients` ADD `last_name` text;--> statement-breakpoint
ALTER TABLE `clients` ADD `telegram_nick` text;