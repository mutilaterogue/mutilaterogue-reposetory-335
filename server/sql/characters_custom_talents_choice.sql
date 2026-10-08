-- characters DB: the chosen option of a choice node (talent_custom.cpp): 1 - spells, 2 - choice_spells.
ALTER TABLE `character_custom_talent` ADD COLUMN `choice` TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER `rank`;
