-- Raid Finder (server/raid_finder.cpp): the raids of the queue.
-- difficulty: 0 10 normal, 1 25 normal, 2 10 heroic, 3 25 heroic. tanks + healers + damage = the raid size.
-- The entrance is the map's entrance areatrigger (areatrigger_teleport).

DROP TABLE IF EXISTS `raid_finder_dungeon`;
CREATE TABLE `raid_finder_dungeon` (
  `id` INT UNSIGNED NOT NULL,
  `map_id` INT UNSIGNED NOT NULL,
  `difficulty` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `name` VARCHAR(100) NOT NULL,
  `tanks` TINYINT UNSIGNED NOT NULL DEFAULT 2,
  `healers` TINYINT UNSIGNED NOT NULL DEFAULT 6,
  `damage` TINYINT UNSIGNED NOT NULL DEFAULT 17,
  `min_level` TINYINT UNSIGNED NOT NULL DEFAULT 80,
  `min_item_level` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 - no requirement',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `raid_finder_dungeon` (`id`, `map_id`, `difficulty`, `name`, `tanks`, `healers`, `damage`, `min_level`, `min_item_level`) VALUES
(1, 533, 1, 'Наксрамас', 2, 6, 17, 80, 0),
(2, 615, 1, 'Обсидиановое святилище', 2, 6, 17, 80, 0),
(3, 616, 1, 'Око Вечности', 2, 6, 17, 80, 0),
(4, 624, 1, 'Склеп Аркавона', 2, 6, 17, 80, 0),
(5, 603, 1, 'Ульдуар', 2, 6, 17, 80, 200),
(6, 649, 1, 'Испытание крестоносца', 2, 6, 17, 80, 213),
(7, 631, 1, 'Цитадель Ледяной Короны', 2, 6, 17, 80, 232),
(8, 724, 1, 'Рубиновое святилище', 2, 6, 17, 80, 245);

-- Boss rewards: to every member of the raid finder's raid on the map when a boss dies (once per boss and instance).
-- boss_entry 0 - every boss of the raid; money in copper; an item goes by mail when the bags are full.
DROP TABLE IF EXISTS `raid_finder_reward`;
CREATE TABLE `raid_finder_reward` (
  `raid_id` INT UNSIGNED NOT NULL,
  `boss_entry` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 - every boss',
  `money` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'copper',
  `item_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `item_count` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`raid_id`, `boss_entry`, `item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- every boss: 50 gold and an emblem (47241 Emblem of Triumph, 49426 Emblem of Frost)
INSERT INTO `raid_finder_reward` (`raid_id`, `boss_entry`, `money`, `item_id`, `item_count`) VALUES
(1, 0, 500000, 47241, 1),
(2, 0, 500000, 47241, 1),
(3, 0, 500000, 47241, 1),
(4, 0, 500000, 47241, 1),
(5, 0, 500000, 47241, 1),
(6, 0, 500000, 47241, 1),
(7, 0, 500000, 49426, 1),
(8, 0, 500000, 49426, 1);
