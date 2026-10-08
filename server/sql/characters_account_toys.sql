-- characters DB: toys learned on the account (toy_collection.cpp)
CREATE TABLE IF NOT EXISTS `account_toys` (
  `accountId` INT UNSIGNED NOT NULL,
  `itemId` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`accountId`, `itemId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
