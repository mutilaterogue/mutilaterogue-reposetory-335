-- world DB: the specialization tab (spec_primary.cpp): the role and the description of each 3.3.5 talent tree.
-- class_mask: 1 Warrior, 2 Paladin, 4 Hunter, 8 Rogue, 16 Priest, 32 Death Knight, 64 Shaman, 128 Mage, 256 Warlock, 1024 Druid
-- tab: 1..3 - the tree in the order of the talent frame
-- role: TANK, HEALER, DAMAGER
-- description: free text, \n - a new line (retail: the text, "Preferred Weapon: ...", "Primary Stat: ...")
CREATE TABLE IF NOT EXISTS `custom_spec_info` (
  `class_mask` INT UNSIGNED NOT NULL,
  `tab` TINYINT UNSIGNED NOT NULL,
  `role` VARCHAR(10) NOT NULL DEFAULT 'DAMAGER',
  `description` VARCHAR(1000) NOT NULL DEFAULT '',
  PRIMARY KEY (`class_mask`, `tab`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `custom_spec_info` VALUES
(8, 1, 'DAMAGER', 'Смертоносный мастер ядов, расправляющийся с жертвами при помощи отравленных кинжалов.\nПредпочитаемое оружие: кинжалы\nОсновная характеристика: ловкость'),
(8, 2, 'DAMAGER', 'Безжалостный боец, полагающийся на ловкость и грубую силу.\nПредпочитаемое оружие: мечи, топоры, булавы, кистевое оружие\nОсновная характеристика: ловкость'),
(8, 3, 'DAMAGER', 'Мастер теней, наносящий удары из засады.\nПредпочитаемое оружие: кинжалы\nОсновная характеристика: ловкость');
