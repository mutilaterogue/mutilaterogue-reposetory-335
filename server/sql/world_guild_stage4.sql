-- Guild system, stage 4 (world database): guild challenges, guild achievements (guild_achievements.cpp),
-- the guild rewards' achievement requirement (guild_rewards.cpp).
SET NAMES utf8mb4;

-- type: 1 dungeon, 2 mythic+, 3 raid, 4 battleground; count: a week; xp: guild experience; gold: copper, into the guild bank
CREATE TABLE IF NOT EXISTS `guild_challenges` (
  `type` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL DEFAULT '',
  `count` INT UNSIGNED NOT NULL DEFAULT 0,
  `xp` INT UNSIGNED NOT NULL DEFAULT 0,
  `gold` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Cataclysm's counts (dungeon 7, raid 1, rated battleground 3) and its rewards' order of size
REPLACE INTO `guild_challenges` (`type`, `name`, `count`, `xp`, `gold`) VALUES
(1, 'Подземелье', 7, 300000, 1250000),
(2, 'Эпохальный+', 3, 500000, 2500000),
(3, 'Рейд', 1, 3000000, 5000000),
(4, 'Поле боя', 3, 1500000, 4000000);

-- type (criteria): 1 guild level (value: the level), 2 boss kills (value: a creature entry, 0 any; count),
-- 3 quests (count), 4 challenges (value: a challenge type, 0 any; count), 5 members (count),
-- 6 epics looted (count), 7 epics crafted (count), 8 battlegrounds won by a guild group (count)
CREATE TABLE IF NOT EXISTS `guild_achievements` (
  `id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `description` VARCHAR(255) NOT NULL DEFAULT '',
  `points` INT UNSIGNED NOT NULL DEFAULT 10,
  `icon` VARCHAR(100) NOT NULL DEFAULT 'Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend',
  `type` TINYINT UNSIGNED NOT NULL,
  `value` INT UNSIGNED NOT NULL DEFAULT 0,
  `count` INT UNSIGNED NOT NULL DEFAULT 1,
  `sort` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Examples (Cataclysm's guild achievements' themes on WotLK content); change freely
REPLACE INTO `guild_achievements` (`id`, `name`, `description`, `points`, `icon`, `type`, `value`, `count`, `sort`) VALUES
(1,  'Уровень 5',               'Гильдия достигла 5-го уровня.',                    10, 'Interface\\Icons\\Achievement_Level_10',               1, 5,  1, 10),
(2,  'Уровень 10',              'Гильдия достигла 10-го уровня.',                   10, 'Interface\\Icons\\Achievement_Level_20',               1, 10, 1, 11),
(3,  'Уровень 15',              'Гильдия достигла 15-го уровня.',                   10, 'Interface\\Icons\\Achievement_Level_40',               1, 15, 1, 12),
(4,  'Уровень 20',              'Гильдия достигла 20-го уровня.',                   10, 'Interface\\Icons\\Achievement_Level_60',               1, 20, 1, 13),
(5,  'Уровень 25',              'Гильдия достигла 25-го уровня.',                   25, 'Interface\\Icons\\Achievement_Level_80',               1, 25, 1, 14),
(10, 'Растущая гильдия',        'В гильдии 50 участников.',                         10, 'Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend', 5, 0, 50, 20),
(11, 'Большая семья',           'В гильдии 200 участников.',                        25, 'Interface\\Icons\\Achievement_GuildPerk_MrPopularity',  5, 0, 200, 21),
(20, 'Мастера заданий',         'Участники гильдии выполнили 1000 заданий.',        10, 'Interface\\Icons\\Achievement_Quests_Completed_06',    3, 0, 1000, 30),
(21, 'Неутомимые',              'Участники гильдии выполнили 10000 заданий.',       25, 'Interface\\Icons\\Achievement_Quests_Completed_08',    3, 0, 10000, 31),
(30, 'Охотники на боссов',      'Гильдейские группы победили 100 боссов.',          10, 'Interface\\Icons\\Achievement_Boss_Bazil_Akumai',      2, 0, 100, 40),
(31, 'Падение Короля-лича',     'Гильдейская группа победила Короля-лича.',         25, 'Interface\\Icons\\Achievement_Boss_LichKing',          2, 36597, 1, 41),
(40, 'Испытанные',              'Гильдия выполнила 25 испытаний гильдии.',          10, 'Interface\\Icons\\Achievement_Dungeon_Heroic_GloryoftheRaider', 4, 0, 25, 50),
(41, 'Покорители подземелий',   'Гильдия выполнила 50 испытаний «Подземелье».',     10, 'Interface\\Icons\\Achievement_Dungeon_Gundrak_Heroic', 4, 1, 50, 51),
(50, 'Эпические трофеи',        'Участники гильдии получили 100 эпических трофеев.', 10, 'Interface\\Icons\\INV_Misc_Bag_10_Black',             6, 0, 100, 60),
(51, 'Мастера ремёсел',         'Участники гильдии создали 25 эпических изделий.',  10, 'Interface\\Icons\\Trade_BlackSmithing',                7, 0, 25, 61),
(60, 'Гильдия воинов',          'Гильдейские группы выиграли 50 полей боя.',        10, 'Interface\\Icons\\Achievement_BG_winWSG',              8, 0, 50, 70);

-- the guild rewards may need a guild achievement (0: none)
SET @col := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'guild_rewards' AND COLUMN_NAME = 'achievement');
SET @sql := IF(@col = 0, 'ALTER TABLE `guild_rewards` ADD COLUMN `achievement` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `guild_level`', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
