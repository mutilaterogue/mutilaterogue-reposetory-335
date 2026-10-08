-- Вкладка "Питомцы" (PetJournal): питомцы-компаньоны 3.3.5 + база (PetJournalData.lua).

PET_JOURNAL_SUMMON_RANDOM_FAVORITE_SPELL_ID = 243819;

function PetJournal_OnLoad(self)
	self:Init("CRITTER", {
		total = "Всего:",
		summon = "Призвать",
		dismiss = "Отпустить",
		summoned = "Призван",
		empty = "У вас нет питомцев",
		sourceLabel = "",
		randomFavoriteIcon = "Interface\\Icons\\INV_Box_PetCarrier_01",
		macroName = "RandomPet",
		rowHint = "ПКМ - в избранное, двойной щелчок - призвать, перетащите на панель команд.",
		showTypes = false,
	});

	self:WatchRandomFavoriteSpell(PET_JOURNAL_SUMMON_RANDOM_FAVORITE_SPELL_ID);
end

-- кнопка "Призвать случайного избранного питомца" - общая логика в Blizzard_CompanionJournal.lua
PetJournalSummonRandomPetSpellFrameMixin = CreateFromMixins(CollectionsRandomFavoriteSpellFrameMixin);
