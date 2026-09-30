-- world DB: custom weapon illusions on top of Enchanting and Runeforging (server/transmog_illusions.cpp)
--   enchant_id - SpellItemEnchantment.dbc entry with ItemVisual (glow), the server puts exactly it on the weapon
--   spell_id   - spell for the name and icon in the client (0 allowed - the list shows "?")
-- The illusion is unlocked when the character has a weapon with this enchant (or knows spell_id).
CREATE TABLE IF NOT EXISTS `transmog_illusion_extra` (
  `enchant_id` INT UNSIGNED NOT NULL,
  `spell_id` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`enchant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- example: INSERT INTO `transmog_illusion_extra` (`enchant_id`, `spell_id`) VALUES (803, 13898);
