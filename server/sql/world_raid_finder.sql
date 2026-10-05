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
