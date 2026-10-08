-- Guild system, stage 4 (characters database): guild challenges, guild achievements (guild_achievements.cpp)

CREATE TABLE IF NOT EXISTS `guild_challenge_progress` (
  `guildid` INT UNSIGNED NOT NULL,
  `type` TINYINT UNSIGNED NOT NULL,
  `done` INT UNSIGNED NOT NULL DEFAULT 0,
  `week` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guildid`, `type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `guild_achievement_criteria` (
  `guildid` INT UNSIGNED NOT NULL,
  `type` TINYINT UNSIGNED NOT NULL,
  `value` INT UNSIGNED NOT NULL DEFAULT 0,
  `counter` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guildid`, `type`, `value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `guild_achievement_done` (
  `guildid` INT UNSIGNED NOT NULL,
  `achievement` INT UNSIGNED NOT NULL,
  `date` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guildid`, `achievement`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
