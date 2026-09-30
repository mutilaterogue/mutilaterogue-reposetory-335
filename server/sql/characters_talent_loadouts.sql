-- characters DB: talent loadouts (server/talent_loadouts.cpp)
CREATE TABLE IF NOT EXISTS `character_talent_loadouts` (
  `guid` INT UNSIGNED NOT NULL,
  `spec` TINYINT UNSIGNED NOT NULL,           -- talent group 0/1 (dual specialization)
  `id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `talents` TEXT NOT NULL,                    -- "talentId/rank,..."
  `active` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `spec`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
