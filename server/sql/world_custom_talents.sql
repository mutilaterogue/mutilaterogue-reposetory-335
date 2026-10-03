-- world DB: retail style talents (server/talent_custom.cpp): the class tree (left), hero trees (middle, one of 2-3).
-- The points are the 3.3.5 talent points (core/Player_custom_talents.patch counts the spent ones).

-- trees. kind: 0 - class tree (left column), 1 - hero tree (middle column, the player picks one)
-- class_mask: 1 Warrior, 2 Paladin, 4 Hunter, 8 Rogue, 16 Priest, 32 Death Knight, 64 Shaman, 128 Mage, 256 Warlock, 1024 Druid
CREATE TABLE IF NOT EXISTS `custom_talent_tree` (
  `id` INT UNSIGNED NOT NULL,
  `class_mask` INT UNSIGNED NOT NULL,
  `kind` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `icon` VARCHAR(255) NOT NULL DEFAULT '' COMMENT 'Interface\\Icons\\... (hero tree choice)',
  `description` VARCHAR(500) NOT NULL DEFAULT '',
  `min_level` TINYINT UNSIGNED NOT NULL DEFAULT 10 COMMENT 'hero trees: the level they open at',
  `sort` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- nodes. row / col: the grid of the column (row 0 at the top, col 0 at the left; up to ~7 columns)
-- spells: one spell per rank, '1234,1235,1236' (max_rank = their number)
-- requires: node ids, '' - none; the node opens when ANY of them has the max rank (retail edges)
-- min_points: points spent in this tree before the node opens (retail gates)
CREATE TABLE IF NOT EXISTS `custom_talent_node` (
  `id` INT UNSIGNED NOT NULL,
  `tree_id` INT UNSIGNED NOT NULL,
  `row` TINYINT UNSIGNED NOT NULL,
  `col` TINYINT UNSIGNED NOT NULL,
  `spells` VARCHAR(255) NOT NULL,
  `requires` VARCHAR(255) NOT NULL DEFAULT '',
  `min_points` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `tree` (`tree_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- example (Rogue): a class tree with 3 nodes and two hero trees - replace with your own
-- INSERT INTO `custom_talent_tree` VALUES
-- (1, 8, 0, 'Разбойник', '', '', 10, 0),
-- (2, 8, 1, 'Мастер обмана', 'Interface\\Icons\\Ability_Stealth', 'Скрытность и внезапные удары.', 71, 1),
-- (3, 8, 1, 'Смертоносец', 'Interface\\Icons\\Ability_Rogue_Eviscerate', 'Яды и кровотечения.', 71, 2);
-- INSERT INTO `custom_talent_node` VALUES
-- (1, 1, 0, 3, '14161', '', 0),
-- (2, 1, 1, 2, '13743,13875', '1', 0),
-- (3, 1, 1, 4, '31208,31209', '1', 0);
