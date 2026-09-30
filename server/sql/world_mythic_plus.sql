-- Mythic+ (server/mythic_plus.cpp): dungeons, affixes, weekly rotation, enemy forces, keystone item,
-- Font of Power and the completion chest.

-- ---------------------------------------------------------------- dungeons
DROP TABLE IF EXISTS `mythic_plus_dungeon`;
CREATE TABLE `mythic_plus_dungeon` (
  `map_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `time_limit` INT UNSIGNED NOT NULL DEFAULT 1800 COMMENT 'seconds',
  `forces_required` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 - 90% of the counted creatures',
  PRIMARY KEY (`map_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `mythic_plus_dungeon` (`map_id`, `name`, `time_limit`, `forces_required`) VALUES
(574, 'Крепость Утгард', 1800, 0),
(575, 'Вершина Утгард', 1920, 0),
(576, 'Нексус', 1800, 0),
(578, 'Окулус', 2100, 0),
(595, 'Очищение Стратхольма', 1920, 0),
(599, 'Чертоги Камня', 1920, 0),
(600, 'Крепость Драк''Тарон', 1800, 0),
(601, 'Азжол-Неруб', 1500, 0),
(602, 'Чертоги Молний', 1920, 0),
(604, 'Гундрак', 1920, 0),
(608, 'Аметистовая крепость', 1920, 0),
(619, 'Ан''кахет: Старое Королевство', 1920, 0),
(632, 'Кузня Душ', 1500, 0),
(650, 'Испытание чемпиона', 1800, 0),
(658, 'Яма Сарона', 1920, 0),
(668, 'Залы Отражений', 1800, 0);

-- ---------------------------------------------------------------- affixes (retail ids)
DROP TABLE IF EXISTS `mythic_plus_affix`;
CREATE TABLE `mythic_plus_affix` (
  `id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(50) NOT NULL,
  `icon` VARCHAR(100) NOT NULL,
  `description` VARCHAR(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `mythic_plus_affix` (`id`, `name`, `icon`, `description`) VALUES
(10, 'Укрепленный', 'Interface\\Icons\\Ability_Toughness', 'Обычные противники получают на 20% больше здоровья и наносят на 30% больше урона.'),
(9, 'Тиранический', 'Interface\\Icons\\Achievement_Boss_Archaedas', 'Боссы получают на 30% больше здоровья и наносят на 15% больше урона.'),
(6, 'Бушующий', 'Interface\\Icons\\Ability_Warrior_FocusedRage', 'Обычные противники приходят в ярость при 30% здоровья и наносят на 50% больше урона.'),
(7, 'Усиливающий', 'Interface\\Icons\\Ability_Warrior_BattleShout', 'Когда обычный противник погибает, союзники в радиусе 30 м получают на 20% больше здоровья и урона.'),
(8, 'Кровавый', 'Interface\\Icons\\Spell_Shadow_BloodBoil', 'Погибшие противники оставляют лужу крови, которая исцеляет их союзников и наносит урон игрокам.'),
(11, 'Взрывной', 'Interface\\Icons\\Ability_Creature_Disease_02', 'Гибель обычного противника наносит всем игрокам урон 2% здоровья в секунду в течение 4 сек. Эффект суммируется.'),
(12, 'Мучительный', 'Interface\\Icons\\Ability_BackStab', 'Игроки с уровнем здоровья ниже 90% получают периодический урон, который усиливается, пока здоровье не восстановится.'),
(4, 'Некротический', 'Interface\\Icons\\Spell_DeathKnight_NecroticPlague', 'Атаки противников в ближнем бою накладывают эффект, снижающий получаемое исцеление на 2% за каждый уровень.');

-- ---------------------------------------------------------------- weekly rotation: affix1 from +2, affix2 from +4, affix3 from +7
DROP TABLE IF EXISTS `mythic_plus_affix_rotation`;
CREATE TABLE `mythic_plus_affix_rotation` (
  `week` INT UNSIGNED NOT NULL,
  `affix1` INT UNSIGNED NOT NULL,
  `affix2` INT UNSIGNED NOT NULL,
  `affix3` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `mythic_plus_affix_rotation` (`week`, `affix1`, `affix2`, `affix3`) VALUES
(0, 10, 6, 12),
(1, 9, 7, 4),
(2, 10, 8, 11),
(3, 9, 6, 12),
(4, 10, 7, 4),
(5, 9, 8, 11),
(6, 10, 11, 12),
(7, 9, 6, 4),
(8, 10, 7, 12),
(9, 9, 8, 4);

-- ---------------------------------------------------------------- enemy forces overrides (default 1 per hostile non-boss creature)
DROP TABLE IF EXISTS `mythic_plus_forces`;
CREATE TABLE `mythic_plus_forces` (
  `entry` INT UNSIGNED NOT NULL,
  `count` INT UNSIGNED NOT NULL DEFAULT 1 COMMENT '0 - does not count',
  PRIMARY KEY (`entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------- keystone item
DELETE FROM `item_template` WHERE `entry` = 190100;
INSERT INTO `item_template` (`entry`, `class`, `subclass`, `SoundOverrideSubclass`, `name`, `displayid`, `Quality`, `Flags`, `BuyCount`,
  `BuyPrice`, `SellPrice`, `InventoryType`, `ItemLevel`, `RequiredLevel`, `maxcount`, `stackable`, `bonding`, `description`, `Material`, `VerifiedBuild`) VALUES
(190100, 12, 0, -1, 'Эпохальный ключ', 6418, 4, 0, 1, 0, 0, 0, 1, 0, 1, 1, 1, '', -1, 0);

-- ---------------------------------------------------------------- Font of Power (goober) and completion chest
SET @FONT_DISPLAY := 7898;   -- font model: put the display you want here
SET @CHEST_DISPLAY := (SELECT `displayId` FROM `gameobject_template` WHERE `entry` = 190663 LIMIT 1);  -- Dark Runed Chest

DELETE FROM `gameobject_template` WHERE `entry` IN (190110, 190111);
INSERT INTO `gameobject_template` (`entry`, `type`, `displayId`, `name`, `IconName`, `castBarCaption`, `unk1`, `size`,
  `Data0`, `Data1`, `Data2`, `Data3`, `Data4`, `Data5`, `Data6`, `Data7`, `Data8`, `Data9`, `Data10`, `Data11`, `Data12`,
  `Data13`, `Data14`, `Data15`, `Data16`, `Data17`, `Data18`, `Data19`, `Data20`, `Data21`, `Data22`, `Data23`, `AIName`, `ScriptName`, `VerifiedBuild`) VALUES
(190110, 10, @FONT_DISPLAY, 'Купель силы', '', '', '', 1.5,
  0, 0, 0, 3000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '', 'go_mythic_plus_font', 0),
(190111, 3, IFNULL(@CHEST_DISPLAY, 259), 'Сундук претендента', '', '', '', 1.5,
  0, 190111, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '', '', 0);

-- chest loot: gameobject_loot_template entry 190111 (fill with the rewards)
DELETE FROM `gameobject_loot_template` WHERE `Entry` = 190111;

-- ---------------------------------------------------------------- Font of Power spawns
-- inside each dungeon, in the mythic difficulty (GM in the mythic instance: .gobject add 190110 - spawnMask 4),
-- or here: spawnMask 4 = DUNGEON_DIFFICULTY_EPIC.
-- INSERT INTO `gameobject` (`id`, `map`, `spawnMask`, `phaseMask`, `position_x`, `position_y`, `position_z`, `orientation`,
--   `rotation0`, `rotation1`, `rotation2`, `rotation3`, `spawntimesecs`, `animprogress`, `state`) VALUES
-- (190110, 574, 4, 1, X, Y, Z, O, 0, 0, 0, 1, 0, 0, 1);
