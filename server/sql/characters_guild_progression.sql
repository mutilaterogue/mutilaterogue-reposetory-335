-- Guild progression (server/guild_progression.cpp): level, experience, today's experience (the daily cap)
CREATE TABLE IF NOT EXISTS `guild_progression` (
  `guildid` INT UNSIGNED NOT NULL,
  `level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `experience` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `today_experience` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `reset_day` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guildid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
