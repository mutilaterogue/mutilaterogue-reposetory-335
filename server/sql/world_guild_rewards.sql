-- Guild rewards (guild_rewards.cpp), world database.
-- standing: 4 Neutral, 5 Friendly, 6 Honored, 7 Revered, 8 Exalted (the guild reputation)
-- race_mask: 0 all races (1 Human, 2 Orc, 4 Dwarf, 8 Night Elf, 16 Undead, 32 Tauren, 64 Gnome, 128 Troll,
--            512 Blood Elf, 1024 Draenei; Alliance 1101, Horde 690)
-- price: copper; guild_level: the guild's level it needs (Cataclysm: a guild achievement)

CREATE TABLE IF NOT EXISTS `guild_rewards` (
  `item` INT UNSIGNED NOT NULL,
  `standing` TINYINT UNSIGNED NOT NULL DEFAULT 4,
  `race_mask` INT UNSIGNED NOT NULL DEFAULT 0,
  `price` INT UNSIGNED NOT NULL DEFAULT 0,
  `guild_level` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Your items here, e.g. (Cataclysm's guild rewards are not in 3.3.5's Item.dbc; use your own):
-- INSERT INTO `guild_rewards` (`item`, `standing`, `race_mask`, `price`, `guild_level`) VALUES
-- (12345, 5, 0, 1500000, 5),     -- Friendly, guild level 5, 150 gold
-- (12346, 6, 0, 3000000, 10),    -- Honored, guild level 10, 300 gold
-- (12347, 8, 1101, 10000000, 25);  -- Exalted, guild level 25, Alliance, 1000 gold
-- (an `achievement` column: sql/world_guild_stage4.sql)
