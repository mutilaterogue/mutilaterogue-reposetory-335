-- world DB: тренер археологии (archaeology.cpp: npc_archaeology_trainer)
-- Ранги навыка 794 выдаёт скрипт через диалог, отдельные заклинания рангов в Spell.dbc не нужны.
-- Вместе с первым рангом учится «Исследовать» (80451). Поставить NPC: .npc add 190020
SET @ENTRY   := 190020;
SET @DISPLAY := 26353;   -- модель Бранна Бронзоборода (есть в 3.3.5), поменяйте на свою

DELETE FROM `creature_template` WHERE `entry` = @ENTRY;
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `unit_class`, `unit_flags`, `type`, `ScriptName`) VALUES
(@ENTRY, 'Тренер археологии', 'Археология', 80, 80, 35, 1, 1, 0, 7, 'npc_archaeology_trainer');

DELETE FROM `creature_template_model` WHERE `CreatureID` = @ENTRY;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`) VALUES
(@ENTRY, 0, @DISPLAY, 1, 1);

-- «Исследовать» (80451): скрипт проверки места раскопок и телескопа
DELETE FROM `spell_script_names` WHERE `spell_id` = 80451;
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES (80451, 'spell_archaeology_survey');
