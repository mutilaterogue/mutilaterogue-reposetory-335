-- Окно коллекций (CollectionsJournal) в стиле ретейла для 3.3.5.
-- API ретейла (C_MountJournal, C_PetJournal) в клиенте нет, поэтому вкладки
-- работают на компаньонах 3.3.5: GetCompanionInfo / CallCompanion / PickupCompanion.
-- Имена - как в ретейле (CollectionsJournal, ToggleCollectionsJournal, индексы вкладок),
-- чтобы следующие вкладки (игрушки, наследуемые) встали на свои места.

COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS = 1;
COLLECTIONS_JOURNAL_TAB_INDEX_PETS = 2;
COLLECTIONS_JOURNAL_TAB_INDEX_TOYS = 3;
COLLECTIONS_JOURNAL_TAB_INDEX_HEIRLOOMS = 4;
COLLECTIONS_JOURNAL_TAB_INDEX_APPEARANCES = 5;

local TABS = {
	{ key = "MountJournal", title = "Транспорт", portrait = "Interface\\Icons\\Ability_Mount_RidingHorse" },
	{ key = "PetJournal", title = "Питомцы", portrait = "Interface\\Icons\\INV_Box_PetCarrier_01" },
	{ key = "ToyBox", title = "Игрушки", portrait = "Interface\\Icons\\Trade_Archaeology_ChestofTinyGlassAnimals" },
	{ key = "HeirloomsJournal", title = "Наследуемые", portrait = "Interface\\Icons\\INV_Misc_EngGizmos_19" },
	{ key = "WardrobeCollectionFrame", title = "Внешний вид", portrait = "Interface\\Icons\\INV_Chest_Cloth_17" },
};

local journal = CreateFrame("Frame", "CollectionsJournal", UIParent, "ButtonFrameTemplate");
journal:SetWidth(703);
journal:SetHeight(606);
journal:SetFrameStrata("MEDIUM");
journal:SetToplevel(true);
journal:EnableMouse(true);
journal:Hide();

-- позицию окна задаёт UIParent (панель слева, отступ 15)
UIPanelWindows["CollectionsJournal"] = { area = "left", pushable = 0, width = 703, whileDead = 1, xOffset = "15", yOffset = "0" };

if ButtonFrameTemplate_HideButtonBar then
	ButtonFrameTemplate_HideButtonBar(journal);
end
if journal.Inset then
	journal.Inset:Hide();   -- у каждой вкладки свои вставки, как в ретейле
end

local function SetTitle(text)
	if journal.SetTitle then
		journal:SetTitle(text);
	elseif journal.TitleText then
		journal.TitleText:SetText(text);
	end
end

local function SetPortrait(texture)
	if journal.SetPortraitToAsset then
		journal:SetPortraitToAsset(texture);
	elseif journal.portrait then
		SetPortraitToTexture(journal.portrait, texture);
	end
end

-- Вкладки внизу окна - твоя TabSystem (TabSystem\TabSystemTemplates.xml + TabSystemOwner.xml).
-- Окно - владелец вкладок (TabSystemOwnerMixin): вкладка показывает свою панель,
-- остальные прячет, и выставляет заголовок/портрет.
Mixin(journal, TabSystemOwnerMixin);
TabSystemOwnerMixin.OnLoad(journal);

local tabSystem = CreateFrame("Frame", nil, journal, "TabSystemTemplate");
tabSystem.minTabWidth = 110;   -- чтобы подписи вкладок не обрезались
tabSystem:SetPoint("TOPLEFT", journal, "BOTTOMLEFT", 22, 2);
journal.TabSystem = tabSystem;
journal:SetTabSystem(tabSystem);

journal.tabIDs = {};   -- индекс вкладки (COLLECTIONS_JOURNAL_TAB_INDEX_*) -> tabID системы вкладок

-- вызывается из файлов вкладок, когда их панель создана
function CollectionsJournal_RegisterTab(tabIndex, panel)
	local info = TABS[tabIndex];
	local tabID = journal:AddNamedTab(info.title, panel);
	journal.tabIDs[tabIndex] = tabID;
	journal:SetTabCallback(tabID, function()
		SetTitle(info.title);
		SetPortrait(info.portrait);
		journal.selectedTabIndex = tabIndex;
	end);
	return tabID;
end

function CollectionsJournal_GetTab(self)
	return journal.selectedTabIndex or COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS;
end

function CollectionsJournal_SetTab(self, tabIndex)
	local tabID = journal.tabIDs[tabIndex];
	if tabID then
		journal:SetTab(tabID);
	end
end

function CollectionsJournal_UpdateSelectedTab(self)
	CollectionsJournal_SetTab(self, CollectionsJournal_GetTab(self));
end

journal:SetScript("OnShow", function(self)
	PlaySound("igCharacterInfoOpen");
	CollectionsJournal_UpdateSelectedTab(self);
	if UpdateMicroButtons then
		UpdateMicroButtons();
	end
end);

journal:SetScript("OnHide", function()
	PlaySound("igCharacterInfoClose");
	if UpdateMicroButtons then
		UpdateMicroButtons();
	end
end);

function SetCollectionsJournalShown(shown, tabIndex)
	if shown then
		ShowUIPanel(journal);
		if tabIndex then
			CollectionsJournal_SetTab(journal, tabIndex);
		end
	else
		HideUIPanel(journal);
	end
end

function ToggleCollectionsJournal(tabIndex)
	local tabMatches = not tabIndex or tabIndex == CollectionsJournal_GetTab(journal);
	local isShown = journal:IsShown() and tabMatches;
	SetCollectionsJournalShown(not isShown, tabIndex);
end

-- в ретейле журнал грузится по требованию; здесь он всегда загружен
function CollectionsJournal_LoadUI()
	return true;
end

SLASH_COLLECTIONS1 = "/collections";
SLASH_COLLECTIONS2 = "/mounts";
SlashCmdList.COLLECTIONS = function()
	ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS);
end

SLASH_PETJOURNAL1 = "/pets";
SlashCmdList.PETJOURNAL = function()
	ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_PETS);
end
