-- world DB: archaeology objects (archaeology.cpp). Cata models (telescope, finds) have to be added to the 3.3.5 client
-- and their GameObjectDisplayInfo IDs set below; placeholder models for now - replace with your own.
SET @DISPLAY_SURVEY := 259;   -- telescope (Cata: Survey Tool)
SET @DISPLAY_FIND   := 259;   -- find (Cata: Dwarf/Troll/Fossil Archaeology Find)

DELETE FROM `gameobject_template` WHERE `entry` IN (207000, 207001, 207002, 207003);
INSERT INTO `gameobject_template` (`entry`, `type`, `displayId`, `name`, `IconName`, `castBarCaption`, `unk1`, `size`, `AIName`, `ScriptName`) VALUES
(207000, 5,  @DISPLAY_SURVEY, 'Инструмент для исследований (далеко)', '', '', '', 1.0, '', ''),
(207001, 5,  @DISPLAY_SURVEY, 'Инструмент для исследований (близко)', '', '', '', 1.0, '', ''),
(207002, 5,  @DISPLAY_SURVEY, 'Инструмент для исследований (рядом)', '', '', '', 1.0, '', ''),
(207003, 10, @DISPLAY_FIND,   'Археологическая находка', 'Interact', '', '', 1.0, '', 'go_archaeology_find');
