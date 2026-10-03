-- characters DB: transmogrification (transmog.cpp). The look is stored on the item (guid), like in retail.
CREATE TABLE IF NOT EXISTS `character_transmog` (
  `item_guid` INT UNSIGNED NOT NULL,
  `owner` INT UNSIGNED NOT NULL,
  `fake_entry` INT UNSIGNED NOT NULL DEFAULT 0,
  `illusion` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`item_guid`),
  KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
