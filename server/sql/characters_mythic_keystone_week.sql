-- characters DB: the keystone lives one week (mythic_plus.cpp): the week it was given; at the weekly reset
-- (Wednesday 07:00 UTC, WEEK_EPOCH) the key and its item are gone.
ALTER TABLE `character_mythic_keystone` ADD COLUMN `week` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `level`;
