-- world DB: свои иллюзии оружия сверх «Наложения чар» и рунной ковки (server/transmog_illusions.cpp)
--   enchant_id - SpellItemEnchantment.dbc с ItemVisual (свечение), именно его сервер ставит на оружие
--   spell_id   - заклинание для названия и иконки в клиенте (можно 0 - тогда в списке будет «?»)
-- Иллюзия открывается, когда у персонажа есть оружие с этими чарами (или он знает spell_id).
CREATE TABLE IF NOT EXISTS `transmog_illusion_extra` (
  `enchant_id` INT UNSIGNED NOT NULL,
  `spell_id` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`enchant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- пример: INSERT INTO `transmog_illusion_extra` (`enchant_id`, `spell_id`) VALUES (803, 13898);
