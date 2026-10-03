-- Great Vault raid row (server/mythic_plus.cpp): raid bosses killed per week, best difficulty per boss

CREATE TABLE IF NOT EXISTS `character_vault_raid` (
  `guid` INT UNSIGNED NOT NULL,
  `week` INT UNSIGNED NOT NULL,
  `entry` INT UNSIGNED NOT NULL COMMENT 'boss creature entry',
  `map_id` INT UNSIGNED NOT NULL,
  `difficulty` TINYINT UNSIGNED NOT NULL COMMENT '0 10N, 1 25N, 2 10H, 3 25H',
  PRIMARY KEY (`guid`, `week`, `entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
