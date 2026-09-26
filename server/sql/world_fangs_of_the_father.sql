-- world DB: «Клыки Отца» (spell_rog_fangs_of_the_father.cpp)
DELETE FROM `spell_script_names` WHERE `spell_id` IN (109939, 109949);
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
(109939, 'spell_rog_fangs_of_the_father'),
(109949, 'spell_rog_fury_of_the_destroyer');

-- 109939: автоатаки и приёмы ближнего боя (0x4 | 0x10), при попадании. Chance 0 - шанс из Spell.dbc (ProcChance)
-- 109949: приёмы разбойника (SpellFamilyName 8), урон ближнего боя и приёмы без урона (Мясорубка): 0x10 | 0x400
DELETE FROM `spell_proc` WHERE `SpellId` IN (109939, 109949);
INSERT INTO `spell_proc` (`SpellId`, `SchoolMask`, `SpellFamilyName`, `SpellFamilyMask0`, `SpellFamilyMask1`, `SpellFamilyMask2`, `ProcFlags`, `SpellTypeMask`, `SpellPhaseMask`, `HitMask`, `AttributesMask`, `DisableEffectsMask`, `ProcsPerMinute`, `Chance`, `Cooldown`, `Charges`) VALUES
(109939, 0, 0, 0, 0, 0, 0x14,  0x1, 0x2, 0, 0, 0, 0, 0, 0, 0),
(109949, 0, 8, 0, 0, 0, 0x410, 0x7, 0x2, 0, 0, 0, 0, 100, 0, 0);
