-- characters DB: collected appearances (items) per account (appearance_collection.cpp)
CREATE TABLE IF NOT EXISTS `account_appearances` (
  `accountId` INT UNSIGNED NOT NULL,
  `itemId` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`accountId`, `itemId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
