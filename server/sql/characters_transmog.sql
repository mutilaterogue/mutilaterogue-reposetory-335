-- characters DB: трансмогрификация (transmog.cpp). Облик хранится на предмете (guid), как в ретейле.
CREATE TABLE IF NOT EXISTS `character_transmog` (
  `item_guid` INT UNSIGNED NOT NULL,
  `owner` INT UNSIGNED NOT NULL,
  `fake_entry` INT UNSIGNED NOT NULL DEFAULT 0,
  `illusion` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`item_guid`),
  KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
