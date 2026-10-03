-- world DB: item upgrade tracks (server/item_upgrade.cpp)
-- A rare+ armor / weapon belongs to the track whose min..max_item_level contains its item_template.ItemLevel.
-- One upgrade level: +ilvl_per_level item levels, costs cost_count x cost_item (3.3.5 currencies are items) + cost_money (copper).
CREATE TABLE IF NOT EXISTS `item_upgrade_track` (
  `id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `min_item_level` INT UNSIGNED NOT NULL,
  `max_item_level` INT UNSIGNED NOT NULL,
  `max_level` INT UNSIGNED NOT NULL DEFAULT 8,
  `ilvl_per_level` INT UNSIGNED NOT NULL DEFAULT 3,
  `cost_item` INT UNSIGNED NOT NULL DEFAULT 0,
  `cost_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `cost_money` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- defaults for WotLK item levels (retail-like: 8 levels, hero / myth 6), emblems as currency
DELETE FROM `item_upgrade_track`;
INSERT INTO `item_upgrade_track` (`id`, `name`, `min_item_level`, `max_item_level`, `max_level`, `ilvl_per_level`, `cost_item`, `cost_count`, `cost_money`) VALUES
(1, 'Искатель приключений', 150, 199, 8, 3, 40752, 5,  50000),   -- Emblem of Heroism
(2, 'Ветеран',              200, 225, 8, 3, 40753, 5, 100000),   -- Emblem of Valor
(3, 'Чемпион',              226, 244, 8, 3, 45624, 5, 150000),   -- Emblem of Conquest
(4, 'Герой',                245, 263, 6, 3, 47241, 5, 200000),   -- Emblem of Triumph
(5, 'Миф',                  264, 999, 6, 3, 49426, 5, 250000);   -- Emblem of Frost

-- NPC (example entry / model - put your own), open with gossip
SET @ENTRY := 190030;
DELETE FROM `creature_template` WHERE `entry` = @ENTRY;
INSERT INTO `creature_template` (`entry`, `modelid1`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `unit_class`, `ScriptName`)
VALUES (@ENTRY, 28117, 'Мастер улучшения', 'Улучшение предметов', 80, 80, 35, 1, 1, 'npc_item_upgrade');
