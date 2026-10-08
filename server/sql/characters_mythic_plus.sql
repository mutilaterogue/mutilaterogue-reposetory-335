-- Mythic+ (server/mythic_plus.cpp): the character's keystone and best runs

CREATE TABLE IF NOT EXISTS `character_mythic_keystone` (
  `guid` INT UNSIGNED NOT NULL,
  `map_id` INT UNSIGNED NOT NULL,
  `level` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_mythic_plus_best` (
  `guid` INT UNSIGNED NOT NULL,
  `map_id` INT UNSIGNED NOT NULL,
  `level` INT UNSIGNED NOT NULL,
  `time_ms` INT UNSIGNED NOT NULL,
  `timed` TINYINT UNSIGNED NOT NULL,
  `affixes` VARCHAR(32) NOT NULL DEFAULT '',
  `score` INT UNSIGNED NOT NULL,
  `date` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `map_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
