-- world DB: трансмогрификатор (пример, подставьте свой entry/модель)
SET @ENTRY := 190010;
DELETE FROM `creature_template` WHERE `entry` = @ENTRY;
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `unit_class`, `ScriptName`)
VALUES (@ENTRY, 'Трансмогрификатор', 'Внешний вид', 80, 80, 35, 1, 1, 'npc_transmogrifier');
DELETE FROM `creature_template_model` WHERE `CreatureID` = @ENTRY;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`) VALUES (@ENTRY, 0, 19646, 1, 1);
