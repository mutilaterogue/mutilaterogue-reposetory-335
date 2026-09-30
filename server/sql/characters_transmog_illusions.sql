-- characters DB: weapon illusions unlocked on the account (server/transmog_illusions.cpp)
-- the illusion on an item itself - character_transmog.illusion (characters_transmog.sql)
CREATE TABLE IF NOT EXISTS `account_illusions` (
  `accountId` INT UNSIGNED NOT NULL,
  `enchantId` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`accountId`, `enchantId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
