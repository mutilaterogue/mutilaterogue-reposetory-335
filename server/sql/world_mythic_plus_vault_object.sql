-- Great Vault object (server/mythic_plus.cpp, go_mythic_plus_vault). displayId 9630 = GameObjectDisplayInfo
-- world\expansion11\doodads\playerhousing\12ph_leg_dragon_greatvault01. Spawn in game: .gobject add 700013

INSERT IGNORE INTO `gameobject_template`
  (`entry`, `type`, `displayId`, `name`, `IconName`, `castBarCaption`, `unk1`, `size`, `AIName`, `ScriptName`, `VerifiedBuild`)
VALUES
  (700013, 10, 9630, 'Great Vault', '', '', '', 1, '', 'go_mythic_plus_vault', 0);

INSERT IGNORE INTO `gameobject_template_locale` (`entry`, `locale`, `name`, `castBarCaption`, `VerifiedBuild`)
VALUES (700013, 'ruRU', 'Великое хранилище', '', 0);
