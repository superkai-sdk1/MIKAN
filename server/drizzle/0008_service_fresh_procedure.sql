-- services.fresh_procedure («Свежий прокол» / «Свежее тату»): aftercare memos are sent only for such services.
-- Services with their own aftercare template are the procedures that leave a fresh wound (piercings, tattoos,
-- corrections); extras without one (jewelry change, cleaning, consultations) stop sending memos.
ALTER TABLE `services` ADD `fresh_procedure` integer DEFAULT false NOT NULL;--> statement-breakpoint
UPDATE `services` SET `fresh_procedure` = 1 WHERE `aftercare_template_id` IS NOT NULL;
