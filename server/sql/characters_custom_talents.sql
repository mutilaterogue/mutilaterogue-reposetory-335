-- characters DB: retail style talents (server/talent_custom.cpp), per talent group (spec 0 / 1)
CREATE TABLE IF NOT EXISTS `character_custom_talent` (
  `guid` INT UNSIGNED NOT NULL,
  `spec` TINYINT UNSIGNED NOT NULL,
  `node_id` INT UNSIGNED NOT NULL,
  `rank` TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`, `spec`, `node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_hero_talent` (
  `guid` INT UNSIGNED NOT NULL,
  `spec` TINYINT UNSIGNED NOT NULL,
  `tree_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`, `spec`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
