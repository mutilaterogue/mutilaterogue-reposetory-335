-- characters DB: бонус к уровню экземпляра предмета (server/item_scaling.cpp)
CREATE TABLE IF NOT EXISTS `item_scaling` (
  `item_guid` INT UNSIGNED NOT NULL,
  `bonus` INT NOT NULL DEFAULT 0,             -- уровни предмета сверх item_template.ItemLevel
  PRIMARY KEY (`item_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
