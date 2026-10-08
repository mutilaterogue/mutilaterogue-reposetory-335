-- Guild system, stage 3 (characters database): guild reputation (guild_progression.cpp), guild news (guild_news.cpp)

CREATE TABLE IF NOT EXISTS `guild_member_reputation` (
  `guid` INT UNSIGNED NOT NULL,
  `guildid` INT UNSIGNED NOT NULL,
  `reputation` INT UNSIGNED NOT NULL DEFAULT 0,
  `weekly` INT UNSIGNED NOT NULL DEFAULT 0,
  `week` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`),
  KEY `guildid` (`guildid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `guild_news` (
  `guildid` INT UNSIGNED NOT NULL,
  `id` INT UNSIGNED NOT NULL,
  `type` TINYINT UNSIGNED NOT NULL,
  `timestamp` INT UNSIGNED NOT NULL,
  `player` INT UNSIGNED NOT NULL DEFAULT 0,
  `value` INT UNSIGNED NOT NULL DEFAULT 0,
  `text` VARCHAR(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`guildid`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
