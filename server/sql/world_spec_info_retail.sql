-- world DB: custom_spec_info (world_spec_info.sql) from the retail TalentTab.db2 (12.1.0): the role (RoleMask 2 tank,
-- 4 healer, 8 damage) and the description of each tree. $Gmale:female; is resolved by the client by the character's sex.
-- The db2 has no Warrior, Paladin, Mage, Druid rows. INSERT IGNORE keeps the rows already there (the Rogue ones of
-- world_spec_info.sql): delete them first to take these.
INSERT IGNORE INTO `custom_spec_info` (`class_mask`, `tab`, `role`, `description`) VALUES
(4, 1, 'DAMAGER', 'A master of the wild who can tame a wide variety of beasts to assist $Ghim:her; in combat.'),
(4, 2, 'DAMAGER', 'A master archer or sharpshooter who excels in bringing down enemies from afar.'),
(4, 3, 'DAMAGER', 'A rugged tracker who favors using animal venom, explosives and traps as deadly weapons.'),
(8, 1, 'DAMAGER', 'A deadly master of poisons who dispatches victims with vicious dagger strikes.'),
(8, 2, 'DAMAGER', 'A swashbuckler who uses agility and guile to stand toe-to-toe with enemies.'),
(8, 3, 'DAMAGER', 'A dark stalker who leaps from the shadows to ambush $Ghis:her; unsuspecting prey.'),
(16, 1, 'HEALER', 'Uses magic to shield allies from taking damage as well as heal their wounds.'),
(16, 2, 'HEALER', 'A versatile healer who can reverse damage on individuals or groups and even heal from beyond the grave.'),
(16, 3, 'DAMAGER', 'Uses sinister Shadow magic, especially damage-over-time spells, to eradicate enemies.'),
(32, 1, 'TANK', 'A dark guardian who manipulates and corrupts life energy to sustain $Ghim:her;self in the face of an enemy onslaught.'),
(32, 2, 'DAMAGER', 'An icy harbinger of doom, channeling runic power and delivering rapid weapon strikes.'),
(32, 3, 'DAMAGER', 'A master of death and decay, spreading infection and controlling undead minions to do $Ghis:her; bidding.'),
(64, 1, 'DAMAGER', 'A spellcaster who harnesses the destructive forces of nature and the elements.'),
(64, 2, 'DAMAGER', 'A totemic warrior who strikes foes with weapons imbued with elemental power.'),
(64, 3, 'HEALER', 'A healer who calls upon ancestral spirits and the cleansing power of water to mend allies'' wounds.'),
(256, 1, 'DAMAGER', 'A master of Shadow magic who specializes in fear, drains and damage-over-time spells.'),
(256, 2, 'DAMAGER', 'A master of demonic magic who transforms into a demon and compels demonic powers to aid him.'),
(256, 3, 'DAMAGER', 'A master of burst damage who calls down fire to burn and demolish enemies.');
