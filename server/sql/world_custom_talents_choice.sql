-- world DB: retail choice nodes (talent_custom.cpp): the player takes one of two. spells - the first option,
-- choice_spells - the second one (one spell per rank, as spells); '' - an ordinary node.
ALTER TABLE `custom_talent_node` ADD COLUMN `choice_spells` VARCHAR(255) NOT NULL DEFAULT '' AFTER `spells`;
