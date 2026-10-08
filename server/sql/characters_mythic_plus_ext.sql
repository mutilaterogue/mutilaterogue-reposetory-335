-- characters DB: Mythic+ extensions (server/mythic_plus.cpp)

-- best run per dungeon per season (rating, leaderboard)
CREATE TABLE IF NOT EXISTS `character_mythic_plus_season_best` (
  `guid` INT UNSIGNED NOT NULL,
  `season` INT UNSIGNED NOT NULL,
  `map_id` INT UNSIGNED NOT NULL,
  `level` INT UNSIGNED NOT NULL,
  `time_ms` INT UNSIGNED NOT NULL,
  `timed` TINYINT UNSIGNED NOT NULL,
  `score` INT UNSIGNED NOT NULL,
  `date` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `season`, `map_id`),
  KEY `season_map_score` (`season`, `map_id`, `score`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- season rewards already given
CREATE TABLE IF NOT EXISTS `character_mythic_plus_season_reward` (
  `guid` INT UNSIGNED NOT NULL,
  `season` INT UNSIGNED NOT NULL,
  `rating` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`, `season`, `rating`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- key rerolls (once a week)
CREATE TABLE IF NOT EXISTS `character_mythic_plus_reroll` (
  `guid` INT UNSIGNED NOT NULL,
  `week` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- the runs made before the seasons: into season 1 (the current rating stays)
INSERT IGNORE INTO `character_mythic_plus_season_best` (`guid`, `season`, `map_id`, `level`, `time_ms`, `timed`, `score`, `date`)
SELECT `guid`, 1, `map_id`, `level`, `time_ms`, `timed`, `score`, `date` FROM `character_mythic_plus_best`;
