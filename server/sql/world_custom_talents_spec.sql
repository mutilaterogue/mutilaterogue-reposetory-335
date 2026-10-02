-- world DB: hero trees bound to the primary talent tree (specialization tab, spec_primary.cpp).
-- spec_mask: 1 - the first 3.3.5 tree, 2 - the second, 4 - the third (sum for several); 0 - any.
-- Rogue: 1 Assassination, 2 Combat, 4 Subtlety. Deathstalker = 1 + 4 = 5, Fatebound = 1 + 2 = 3, Trickster = 2 + 4 = 6.
ALTER TABLE `custom_talent_tree` ADD COLUMN `spec_mask` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `sort`;
