-- characters DB: иллюзии оружия, открытые на аккаунте (server/transmog_illusions.cpp)
-- сама иллюзия на предмете - character_transmog.illusion (characters_transmog.sql)
CREATE TABLE IF NOT EXISTS `account_illusions` (
  `accountId` INT UNSIGNED NOT NULL,
  `enchantId` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`accountId`, `enchantId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
