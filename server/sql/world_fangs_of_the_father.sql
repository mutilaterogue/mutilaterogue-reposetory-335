-- world DB: Fangs of the Father (spell_rogue.cpp: spell_rog_fangs_of_the_father, spell_rog_fury_of_the_destroyer)
DELETE FROM `spell_script_names` WHERE `spell_id` IN (109939, 109949);
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
(109939, 'spell_rog_fangs_of_the_father'),
(109949, 'spell_rog_fury_of_the_destroyer');

-- 109939: melee auto attacks and abilities (0x4 | 0x10), on hit. Chance 0 - chance from Spell.dbc (ProcChance)
-- 109949: rogue abilities (SpellFamilyName 8), melee damage and non-damaging abilities (Fan of Knives): 0x10 | 0x400
DELETE FROM `spell_proc` WHERE `SpellId` IN (109939, 109949);
INSERT INTO `spell_proc` (`SpellId`, `SchoolMask`, `SpellFamilyName`, `SpellFamilyMask0`, `SpellFamilyMask1`, `SpellFamilyMask2`, `ProcFlags`, `SpellTypeMask`, `SpellPhaseMask`, `HitMask`, `AttributesMask`, `DisableEffectsMask`, `ProcsPerMinute`, `Chance`, `Cooldown`, `Charges`) VALUES
(109939, 0, 0, 0, 0, 0, 0x14,  0x1, 0x2, 0, 0, 0, 0, 0, 0, 0),
(109949, 0, 8, 0, 0, 0, 0x410, 0x7, 0x2, 0, 0, 0, 0, 100, 0, 0);
