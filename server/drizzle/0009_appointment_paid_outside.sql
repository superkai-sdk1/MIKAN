-- appointments.paid_outside: a visit paid before MIKAN (carried over from YCLIENTS) — counts as paid, has no sale.
ALTER TABLE `appointments` ADD `paid_outside` integer DEFAULT false NOT NULL;