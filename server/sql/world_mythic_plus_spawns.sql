-- Mythic+ spawns: everything spawned in heroic (spawnMask 2) of the 5-man dungeons also spawns in mythic
-- (DUNGEON_DIFFICULTY_EPIC = spawnMask 4). Maps = mythic_plus_dungeon.
UPDATE `creature` SET `spawnMask` = `spawnMask` | 4
WHERE `map` IN (SELECT `map_id` FROM `mythic_plus_dungeon`) AND (`spawnMask` & 2) <> 0;

UPDATE `gameobject` SET `spawnMask` = `spawnMask` | 4
WHERE `map` IN (SELECT `map_id` FROM `mythic_plus_dungeon`) AND (`spawnMask` & 2) <> 0;
