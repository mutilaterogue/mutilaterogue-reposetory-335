-- Guild progression (server/guild_progression.cpp)

-- the experience from a guild level to the next (Cataclysm: 16 580 000, then +1 660 000 a level)
CREATE TABLE IF NOT EXISTS `guild_xp_for_level` (
  `lvl` TINYINT UNSIGNED NOT NULL,
  `xp_for_next_level` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`lvl`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
DELETE FROM `guild_xp_for_level`;
INSERT INTO `guild_xp_for_level` (`lvl`, `xp_for_next_level`) VALUES
(1, 16580000),
(2, 18240000),
(3, 19900000),
(4, 21560000),
(5, 23220000),
(6, 24880000),
(7, 26540000),
(8, 28200000),
(9, 29860000),
(10, 31520000),
(11, 33180000),
(12, 34840000),
(13, 36500000),
(14, 38160000),
(15, 39820000),
(16, 41480000),
(17, 43140000),
(18, 44800000),
(19, 46460000),
(20, 48120000),
(21, 49780000),
(22, 51440000),
(23, 53100000),
(24, 54760000);

-- the guild perks (GuildPerkSpells.dbc): the spell the members know from this guild level
CREATE TABLE IF NOT EXISTS `guild_perk_spells` (
  `guild_level` TINYINT UNSIGNED NOT NULL,
  `spell` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`spell`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
DELETE FROM `guild_perk_spells`;
INSERT INTO `guild_perk_spells` (`guild_level`, `spell`) VALUES
(2, 78631),
(3, 78633),
(4, 78634),
(5, 83940),
(6, 78632),
(7, 83942),
(8, 83944),
(9, 83943),
(10, 83945),
(11, 83958),
(12, 78635),
(13, 83959),
(14, 83949),
(15, 83950),
(16, 83941),
(17, 83951),
(18, 83953),
(19, 83960),
(20, 83963),
(21, 83967),
(22, 83961),
(23, 83966),
(24, 83964),
(25, 83968);
