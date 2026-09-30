-- Mythic+ Great Vault (server/mythic_plus.cpp): completed keystones of every week and the rolled options

CREATE TABLE IF NOT EXISTS `character_mythic_plus_weekly` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `guid` INT UNSIGNED NOT NULL,
  `week` INT UNSIGNED NOT NULL,
  `map_id` INT UNSIGNED NOT NULL,
  `level` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  KEY `guid_week` (`guid`, `week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_mythic_plus_vault` (
  `guid` INT UNSIGNED NOT NULL,
  `week` INT UNSIGNED NOT NULL COMMENT 'week of the runs the options come from',
  `slot` TINYINT UNSIGNED NOT NULL COMMENT '1 - 1 run, 2 - 4 runs, 3 - 8 runs',
  `item_id` INT UNSIGNED NOT NULL,
  `level` INT UNSIGNED NOT NULL COMMENT 'keystone level of the option (item level bonus)',
  `claimed` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `week`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
