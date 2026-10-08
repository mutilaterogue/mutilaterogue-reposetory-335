-- Mythic+ spawns for Utgarde Keep (574): everything spawned in heroic (spawnMask 2) also spawns in mythic
-- (DUNGEON_DIFFICULTY_EPIC = spawnMask 4). Other dungeons: add their map ids to the IN list.
UPDATE `creature` SET `spawnMask` = `spawnMask` | 4 WHERE `map` IN (574) AND (`spawnMask` & 2) <> 0;
UPDATE `gameobject` SET `spawnMask` = `spawnMask` | 4 WHERE `map` IN (574) AND (`spawnMask` & 2) <> 0;
