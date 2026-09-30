-- characters DB: item level bonus of an item instance (server/item_scaling.cpp)
CREATE TABLE IF NOT EXISTS `item_scaling` (
  `item_guid` INT UNSIGNED NOT NULL,
  `bonus` INT NOT NULL DEFAULT 0,             -- item levels above item_template.ItemLevel
  PRIMARY KEY (`item_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
