-- items from the Mythic+ chest: the keystone level they dropped from (item level via item_scaling, tooltip "Эпохальный +N")
CREATE TABLE IF NOT EXISTS `item_mythic` (
  `item_guid` INT UNSIGNED NOT NULL,
  `level` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`item_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
