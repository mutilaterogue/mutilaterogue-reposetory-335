CollectionsJournal_OnLoad(CollectionsJournal);

-- Порядок вкладок - как в ретейле (без Warband-сцен).
CollectionsJournal_RegisterTab(COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS, MountJournal, "Транспорт", "Interface\\Icons\\Ability_Mount_RidingHorse");
CollectionsJournal_RegisterTab(COLLECTIONS_JOURNAL_TAB_INDEX_PETS, PetJournal, "Питомцы", "Interface\\Icons\\INV_Box_PetCarrier_01");
CollectionsJournal_RegisterTab(COLLECTIONS_JOURNAL_TAB_INDEX_TOYS, ToyBox, "Игрушки", "Interface\\Icons\\Trade_Archaeology_ChestofTinyGlassAnimals");
CollectionsJournal_RegisterTab(COLLECTIONS_JOURNAL_TAB_INDEX_HEIRLOOMS, HeirloomsJournal, "Наследуемые", "Interface\\Icons\\INV_Misc_EngGizmos_19");
CollectionsJournal_RegisterTab(COLLECTIONS_JOURNAL_TAB_INDEX_APPEARANCES, WardrobeCollectionFrame, "Внешний вид", "Interface\\Icons\\INV_Chest_Cloth_17");
CollectionsJournal_SetTab(CollectionsJournal, COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS);
