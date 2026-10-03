-- Mythic+ battle res charges (server/mythic_plus.cpp spell_mythic_plus_battle_res):
-- Rebirth (all ranks) and Raise Ally use a charge of the keystone run (1 at the start, +1 every 10 minutes).
DELETE FROM `spell_script_names` WHERE `ScriptName` = 'spell_mythic_plus_battle_res';
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
(20484, 'spell_mythic_plus_battle_res'),
(20739, 'spell_mythic_plus_battle_res'),
(20742, 'spell_mythic_plus_battle_res'),
(20747, 'spell_mythic_plus_battle_res'),
(20748, 'spell_mythic_plus_battle_res'),
(26994, 'spell_mythic_plus_battle_res'),
(48477, 'spell_mythic_plus_battle_res'),
(61999, 'spell_mythic_plus_battle_res');
