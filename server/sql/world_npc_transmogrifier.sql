-- world DB: transmogrifier (example, put your own entry/model)
SET @ENTRY := 190010;
DELETE FROM `creature_template` WHERE `entry` = @ENTRY;
INSERT INTO `creature_template` (`entry`, `modelid1`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `unit_class`, `ScriptName`)
VALUES (@ENTRY, 19646, 'Трансмогрификатор', 'Внешний вид', 80, 80, 35, 1, 1, 'npc_transmogrifier');
