-- Вкладка "Транспорт" (MountJournal): маунты-компаньоны 3.3.5 + база всей коллекции (MountJournalData.lua).

MOUNT_JOURNAL_SUMMON_RANDOM_FAVORITE_SPELL_ID = 150544;

function MountJournal_OnLoad(self)
	self:Init("MOUNT", {
		total = "Всего:",
		summon = "Призвать",
		dismiss = "Спешиться",
		summoned = "Вы верхом",
		empty = "У вас нет транспорта",
		sourceLabel = "",
		randomFavoriteIcon = "Interface\\Icons\\Ability_Mount_RidingHorse",
		macroName = "RandomMount",
		rowHint = "ПКМ - в избранное, двойной щелчок - призвать, перетащите на панель команд.",
		showTypes = true,
	});

	self:WatchRandomFavoriteSpell(MOUNT_JOURNAL_SUMMON_RANDOM_FAVORITE_SPELL_ID);
end

-- кнопка "Случайное избранное средство передвижения" - общая логика в Blizzard_CompanionJournal.lua
MountJournalSummonRandomFavoriteSpellFrameMixin = CreateFromMixins(CollectionsRandomFavoriteSpellFrameMixin);
