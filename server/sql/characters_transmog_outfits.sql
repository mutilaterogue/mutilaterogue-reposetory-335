-- characters DB: transmog outfits (transmog_outfits.cpp)
CREATE TABLE IF NOT EXISTS `character_transmog_outfits` (
  `guid` INT UNSIGNED NOT NULL,
  `id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `icon` INT UNSIGNED NOT NULL DEFAULT 0,
  `slots` TEXT NOT NULL,
  `sit_enabled` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `sit_location` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `sit_movement` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `sit_combat` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- bought outfit slots and the current outfit
CREATE TABLE IF NOT EXISTS `character_transmog_outfit_slots` (
  `guid` INT UNSIGNED NOT NULL,
  `unlocked` INT UNSIGNED NOT NULL DEFAULT 5,
  `active` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- custom sets (per account)
CREATE TABLE IF NOT EXISTS `account_transmog_custom_sets` (
  `accountId` INT UNSIGNED NOT NULL,
  `id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `slots` TEXT NOT NULL,
  PRIMARY KEY (`accountId`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- weapon illusions in an outfit (transmog_illusions.cpp): "slot/enchantId,..." - for an already created table
ALTER TABLE `character_transmog_outfits` ADD COLUMN `illusions` TEXT NULL AFTER `sit_combat`;
