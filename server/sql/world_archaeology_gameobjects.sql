-- world DB: объекты археологии (archaeology.cpp). Модели Cata (телескоп, находки) нужно перенести в клиент 3.3.5
-- и прописать их GameObjectDisplayInfo ID ниже; пока стоят модели-заглушки - поменяйте на свои.
SET @DISPLAY_SURVEY := 259;   -- телескоп (Cata: Survey Tool)
SET @DISPLAY_FIND   := 259;   -- находка (Cata: Dwarf/Troll/Fossil Archaeology Find)

DELETE FROM `gameobject_template` WHERE `entry` IN (207000, 207001, 207002, 207003);
INSERT INTO `gameobject_template` (`entry`, `type`, `displayId`, `name`, `IconName`, `castBarCaption`, `unk1`, `size`, `AIName`, `ScriptName`) VALUES
(207000, 5,  @DISPLAY_SURVEY, 'Инструмент для исследований (далеко)', '', '', '', 1.0, '', ''),
(207001, 5,  @DISPLAY_SURVEY, 'Инструмент для исследований (близко)', '', '', '', 1.0, '', ''),
(207002, 5,  @DISPLAY_SURVEY, 'Инструмент для исследований (рядом)', '', '', '', 1.0, '', ''),
(207003, 10, @DISPLAY_FIND,   'Археологическая находка', 'Interact', '', '', 1.0, '', 'go_archaeology_find');
