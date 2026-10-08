-- characters DB: upgrade level of an item instance (server/item_upgrade.cpp); item level bonus itself - item_scaling
CREATE TABLE IF NOT EXISTS `item_upgrade` (
  `item_guid` INT UNSIGNED NOT NULL,
  `level` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`item_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
