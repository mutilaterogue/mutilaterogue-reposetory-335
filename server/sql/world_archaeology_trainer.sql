-- world DB (NOT characters/auth): archaeology trainer (archaeology.cpp: npc_archaeology_trainer)
-- Ranks of skill 794 are given by the script through gossip, no rank spells in Spell.dbc are needed.
-- Survey (80451) is learned with the first rank. Spawn the NPC: .npc add 190020
SET @ENTRY   := 190020;
SET @DISPLAY := 26353;   -- Brann Bronzebeard model (exists in 3.3.5), replace with your own

DELETE FROM `creature_template` WHERE `entry` = @ENTRY;
INSERT INTO `creature_template` (`entry`, `modelid1`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `unit_class`, `unit_flags`, `type`, `ScriptName`) VALUES
(@ENTRY, @DISPLAY, 'Тренер археологии', 'Археология', 80, 80, 35, 1, 1, 0, 7, 'npc_archaeology_trainer');


-- Survey (80451): script that checks the dig site and places the telescope
DELETE FROM `spell_script_names` WHERE `spell_id` = 80451;
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES (80451, 'spell_archaeology_survey');
