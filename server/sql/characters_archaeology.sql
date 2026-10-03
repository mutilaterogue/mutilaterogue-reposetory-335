-- characters DB: archaeology (archaeology.cpp)
CREATE TABLE IF NOT EXISTS `character_archaeology` (
  `guid` INT UNSIGNED NOT NULL,
  `branch` INT UNSIGNED NOT NULL,              -- ResearchBranch.ID
  `fragments` INT UNSIGNED NOT NULL DEFAULT 0,
  `project` INT UNSIGNED NOT NULL DEFAULT 0,   -- current ResearchProject.ID of the race
  PRIMARY KEY (`guid`, `branch`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_archaeology_history` (
  `guid` INT UNSIGNED NOT NULL,
  `project` INT UNSIGNED NOT NULL,
  `count` INT UNSIGNED NOT NULL DEFAULT 0,
  `first_time` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `project`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_archaeology_digsite` (
  `guid` INT UNSIGNED NOT NULL,
  `map` INT UNSIGNED NOT NULL,
  `site` INT UNSIGNED NOT NULL,                -- ResearchSite.ID
  `finds` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `site`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
