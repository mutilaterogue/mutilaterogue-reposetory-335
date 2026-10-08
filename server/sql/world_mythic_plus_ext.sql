-- world DB: Mythic+ extensions (server/mythic_plus.cpp). New tables and new rows only.

-- ---------------------------------------------------------------- per-dungeon loot
-- chest_loot / vault_loot: gameobject_loot_template entries of this dungeon, 0 - the common 252665
CREATE TABLE IF NOT EXISTS `mythic_plus_dungeon_loot` (
  `map_id` INT UNSIGNED NOT NULL,
  `chest_loot` INT UNSIGNED NOT NULL DEFAULT 0,
  `vault_loot` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`map_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- e.g. Utgarde Keep: INSERT INTO `mythic_plus_dungeon_loot` VALUES (574, 900574, 900574);
-- and fill gameobject_loot_template entry 900574 like 252665

-- ---------------------------------------------------------------- seasons
-- the current season = the last one with start_time <= now; rating / best runs / leaderboard are per season
-- seasonal_affix: added from seasonal_affix_level on (0 - none)
CREATE TABLE IF NOT EXISTS `mythic_plus_season` (
  `id` INT UNSIGNED NOT NULL,
  `start_time` INT UNSIGNED NOT NULL COMMENT 'unix time',
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `seasonal_affix` INT UNSIGNED NOT NULL DEFAULT 0,
  `seasonal_affix_level` INT UNSIGNED NOT NULL DEFAULT 10,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT IGNORE INTO `mythic_plus_season` (`id`, `start_time`, `name`, `seasonal_affix`, `seasonal_affix_level`) VALUES
(1, 1704265200, 'Сезон 1', 13, 10);

-- rewards for reaching a rating in a season: title (CharTitles.dbc id), item (by mail), spell (e.g. a mount)
CREATE TABLE IF NOT EXISTS `mythic_plus_season_reward` (
  `season` INT UNSIGNED NOT NULL,
  `rating` INT UNSIGNED NOT NULL,
  `title_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `item_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `spell_id` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`season`, `rating`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- e.g.: INSERT INTO `mythic_plus_season_reward` VALUES (1, 1000, 0, 0, <mount spell>), (1, 2000, <title id>, 0, 0);

-- ---------------------------------------------------------------- new affixes (add them to mythic_plus_affix_rotation yourself)
INSERT IGNORE INTO `mythic_plus_affix` (`id`, `name`, `icon`, `description`) VALUES
(13, 'Взрывной', 'Interface\\Icons\\Spell_Fire_SelfDestruct', 'Во время боя рядом с противниками появляются взрывные сферы. Если сферу не уничтожить за 6 сек., она взрывается, нанося урон всем игрокам.'),
(14, 'Сотрясающий', 'Interface\\Icons\\Spell_Nature_Earthquake', 'Периодически земля сотрясается, прерывая заклинания и нанося урон игрокам и союзникам поблизости.'),
(122, 'Вдохновляющий', 'Interface\\Icons\\Spell_Holy_PrayerOfSpirit', 'Некоторые противники вдохновляют союзников поблизости, делая их невосприимчивыми к эффектам потери контроля.'),
(124, 'Штормовой', 'Interface\\Icons\\Spell_Nature_Cyclone', 'Во время боя противники периодически призывают смерчи, наносящие урон игрокам поблизости.'),
(132, 'Громовой', 'Interface\\Icons\\Spell_Nature_ThunderClap', 'Периодически двое игроков получают метку грозы. Они должны встретиться, иначе получат большой урон.');

-- ---------------------------------------------------------------- creatures
-- models: replace the display ids with your own if they do not fit
SET @ORB_DISPLAY     := 26753;
SET @STORM_DISPLAY   := 27393;
SET @KEYSTONE_DISPLAY := 26353;

-- Explosive orb (EXPLOSIVE_ENTRY): hostile, killable, does nothing
INSERT IGNORE INTO `creature_template` (`entry`, `modelid1`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `unit_class`, `unit_flags`, `type`, `ScriptName`) VALUES
(700020, @ORB_DISPLAY, 'Взрывная сфера', '', 80, 80, 14, 0, 1, 0, 10, ''),
-- Storming tornado (STORM_ENTRY): cannot be attacked
(700021, @STORM_DISPLAY, 'Смерч', '', 80, 80, 14, 0, 1, 33555202, 10, ''),
-- keystone NPC: .npc add 700022
(700022, @KEYSTONE_DISPLAY, 'Хранитель ключей', 'Эпохальные ключи', 80, 80, 35, 1, 1, 0, 7, 'npc_mythic_plus_keystone');
