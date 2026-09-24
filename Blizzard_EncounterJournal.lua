-- Blizzard_EncounterJournal (retail) for 3.3.5. Data: EncounterJournalData.lua + EncounterJournalAPI.lua,
-- retail API: Blizzard_EncounterJournal_Compat335.lua, boss models: EncounterJournalModel.lua.
--
-- Stage 1: tabs Dungeons / Raids, tier (expansion) dropdown, instance grid, navigation bar.
-- Stage 2: the book - boss list on the left page; on the right page the instance lore or the boss
--          tabs (overview / abilities / loot / model), difficulty, loot filters; search.

local INSTANCE_BUTTON_WIDTH, INSTANCE_BUTTON_HEIGHT = 174, 96;
local INSTANCE_PADDING_X, INSTANCE_PADDING_Y = 15, 15;
local INSTANCE_COLUMNS = 4;
local INSTANCE_ROWS = 3;	-- visible rows: 3*96 + 2*15 = 318 fits the grid (~367), 4 rows (429) overflow the frame

local BOSS_ROWS, BOSS_ROW_HEIGHT = 5, 63;		-- boss buttons are 55 high
local LOOT_ROWS, LOOT_ROW_HEIGHT = 7, 46;		-- loot rows are 45 high
local SEARCH_ROWS, SEARCH_ROW_HEIGHT = 6, 48;	-- full search rows are 46 high
local SEARCH_PREVIEW_ROWS, SEARCH_PREVIEW_HEIGHT = 5, 27;
local MAX_CREATURES = 9;
local HEADER_HEIGHT, HEADER_SPACING, HEADER_INDENT = 29, 4, 15;
local EJ_MIN_CHARACTER_SEARCH = 3;

local EJ_STYPE_ITEM = 0;
local EJ_STYPE_ENCOUNTER = 1;
local EJ_STYPE_CREATURE = 2;
local EJ_STYPE_SECTION = 3;
local EJ_STYPE_INSTANCE = 4;

local GENERIC_CREATURE_ICON = "Interface\\EncounterJournal\\UI-EJ-GenericSearchCreature";
local DEFAULT_BOSS_IMAGE = "Interface\\EncounterJournal\\UI-EJ-BOSS-Default";

-- retail tier backgrounds (EJ_TIER_DATA)
local TIER_BACKGROUNDS = {
	[0] = "Interface\\EncounterJournal\\UI-EJ-Classic",
	[1] = "Interface\\EncounterJournal\\UI-EJ-BurningCrusade",
	[2] = "Interface\\EncounterJournal\\UI-EJ-WrathoftheLichKing",
};

-- retail difficultyIDs (Blizzard_EncounterJournal_Compat335.lua maps them onto the data)
local DIFFICULTIES = {
	{ id = 1, text = PLAYER_DIFFICULTY1 or "Обычный" },
	{ id = 2, text = PLAYER_DIFFICULTY2 or "Героический" },
	{ id = 3, text = RAID_DIFFICULTY1 or "10 игроков" },
	{ id = 4, text = RAID_DIFFICULTY2 or "25 игроков" },
	{ id = 5, text = RAID_DIFFICULTY3 or "10 игроков (героич.)" },
	{ id = 6, text = RAID_DIFFICULTY4 or "25 игроков (героич.)" },
};

-- Enum.ItemSlotFilterType (C_EncounterJournal.SetSlotFilter)
local SLOT_FILTER_NO_FILTER = 15;
local SLOT_FILTERS = {
	{ id = 0, text = INVTYPE_HEAD },
	{ id = 1, text = INVTYPE_NECK },
	{ id = 2, text = INVTYPE_SHOULDER },
	{ id = 3, text = INVTYPE_CLOAK },
	{ id = 4, text = INVTYPE_CHEST },
	{ id = 5, text = INVTYPE_WRIST },
	{ id = 6, text = INVTYPE_HAND },
	{ id = 7, text = INVTYPE_WAIST },
	{ id = 8, text = INVTYPE_LEGS },
	{ id = 9, text = INVTYPE_FEET },
	{ id = 10, text = WEAPON or "Оружие" },
	{ id = 11, text = INVTYPE_WEAPONOFFHAND },
	{ id = 12, text = INVTYPE_FINGER },
	{ id = 13, text = INVTYPE_TRINKET },
	{ id = 14, text = OTHER or "Другое" },
};

-- side tabs of the right page; icons are in UI-EncounterJournalTextures (no atlases in 3.3.5)
local TAB_TEXTURE = "Interface\\EncounterJournal\\UI-EncounterJournalTextures";
local INFO_TABS = {
	{ key = "overview", button = "overviewTab", tooltip = OVERVIEW or "Обзор",
	  selected = { 0.90234375, 0.99609375, 0.26953125, 0.31152344 },
	  unselected = { 0.85546875, 0.94921875, 0.52441406, 0.56640625 } },
	{ key = "abilities", button = "abilitiesTab", tooltip = ABILITIES or "Способности",
	  selected = { 0.806640625, 0.8984375, 0.70703125, 0.748046875 },
	  unselected = { 0.904296875, 0.99609375, 0.70703125, 0.748046875 } },
	{ key = "loot", button = "lootTab", tooltip = LOOT or "Добыча",
	  selected = { 0.63281250, 0.72656250, 0.61816406, 0.66015625 },
	  unselected = { 0.73046875, 0.82421875, 0.61816406, 0.66015625 } },
	{ key = "model", button = "modelTab", tooltip = MODEL or "Модель",
	  selected = { 0.8046875, 0.900390625, 0.662109375, 0.705078125 },
	  unselected = { 0.90234375, 1, 0.662109375, 0.705078125 } },
};

EJ_TABS = { DUNGEONS = 1, RAIDS = 2 };

local sectionOpen = {};		-- [sectionID] = expanded
local infoHeaders = {};		-- pool of EncounterInfoTemplate frames
local lootClassIndex = 0;	-- EJ_GetAvailableClasses() order, 0 = all classes

local function SetShown(region, shown)
	if shown then
		region:Show();
	else
		region:Hide();
	end
end

local function ScrollBarOf(scrollFrame)
	return _G[scrollFrame:GetName() .. "ScrollBar"];
end

local function SetupFauxScroll(scrollFrame, wheelFrame, rowHeight, updateFunc)
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, updateFunc);
	end);
	wheelFrame:SetScript("OnMouseWheel", function(_, delta)
		local scrollBar = ScrollBarOf(scrollFrame);
		scrollBar:SetValue(scrollBar:GetValue() - delta * rowHeight);
	end);
end

local function ResetFauxScroll(scrollFrame)
	FauxScrollFrame_SetOffset(scrollFrame, 0);
	ScrollBarOf(scrollFrame):SetValue(0);
end

-- UTF-8 aware length: the search minimum is in letters, Cyrillic letters are two bytes
local function TextLength(text)
	return strlen((text:gsub("[\128-\191]", "")));
end

-- boss images (UI-EJ-BOSS-*) are 128x64 with the creature in the middle
local function SetCreatureIcon(texture, icon)
	if icon and icon ~= "" then
		texture:SetTexture(icon);
		texture:SetTexCoord(0.25, 0.75, 0, 1);
	else
		texture:SetTexture(GENERIC_CREATURE_ICON);
		texture:SetTexCoord(0, 1, 0, 1);
	end
end

local creatureIconByDisplay;
local function CreatureIconForDisplayID(displayID)
	if not creatureIconByDisplay then
		creatureIconByDisplay = {};
		for _, creature in pairs(EJ_DATA.creatures) do
			if creature.modelID and creature.icon and creature.icon ~= "" then
				creatureIconByDisplay[creature.modelID] = creature.icon;
			end
		end
	end
	return creatureIconByDisplay[displayID];
end

local function GetItemLink(itemID)
	local _, link = GetItemInfo(itemID);
	if link then
		return link;
	end
	local name, quality = GetItemInfoCached(itemID);
	if not name then
		return nil;
	end
	local color = ITEM_QUALITY_COLORS[quality or 1];
	return (color and color.hex or "|cffffffff") .. "|Hitem:" .. itemID .. ":0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r";
end

---------------------------------------------------------------------------
-- load / show
---------------------------------------------------------------------------
function EncounterJournal_OnLoad(self)
	if ButtonFrameTemplate_HideButtonBar then
		ButtonFrameTemplate_HideButtonBar(self);
	end
	if self.SetTitle then
		self:SetTitle(ADVENTURE_JOURNAL or "Путеводитель по приключениям");
	end
	if self.SetPortraitToAsset then
		self:SetPortraitToAsset("Interface\\EncounterJournal\\UI-EJ-PortraitIcon");
	end
	if self.SetFrameLevelsFromBaseLevel then
		self:SetFrameLevelsFromBaseLevel(self:GetFrameLevel());
	end

	-- EJ_SetDifficulty of EncounterJournalAPI.lua calls the OnEvent script directly
	self:SetScript("OnEvent", EncounterJournal_OnEvent);

	-- navigation bar: "Home" goes back to the instance grid
	local homeData = {
		name = HOME or "Главная",
		OnClick = function() EncounterJournal_ShowInstanceSelect(); end,
	};
	NavBar_Initialize(self.navBar, "NavButtonTemplate", homeData, self.navBar.home, self.navBar.overflow);

	-- tabs (TabSystem): both show the instance grid, filtered by dungeon / raid
	Mixin(self, TabSystemOwnerMixin);
	TabSystemOwnerMixin.OnLoad(self);
	self:SetTabSystem(self.TabSystem);
	self.TabSystem:SetFrameLevel(self:GetFrameLevel() + 25);

	self.dungeonsTabID = self:AddNamedTab(DUNGEONS or "Подземелья");
	self.raidsTabID = self:AddNamedTab(RAIDS or "Рейды");
	self:SetTabCallback(self.dungeonsTabID, function() EncounterJournal_SetListRaids(false); end);
	self:SetTabCallback(self.raidsTabID, function() EncounterJournal_SetListRaids(true); end);

	-- instance grid
	local select = self.instanceSelect;
	select.buttons = {};
	for index = 1, INSTANCE_COLUMNS * INSTANCE_ROWS do
		local button = CreateFrame("Button", "EncounterJournalInstanceButton" .. index, select.Grid, "EncounterInstanceButtonTemplate");
		local column = (index - 1) % INSTANCE_COLUMNS;
		local row = math.floor((index - 1) / INSTANCE_COLUMNS);
		button:SetPoint("TOPLEFT", select.Grid, "TOPLEFT",
			column * (INSTANCE_BUTTON_WIDTH + INSTANCE_PADDING_X),
			-row * (INSTANCE_BUTTON_HEIGHT + INSTANCE_PADDING_Y));
		select.buttons[index] = button;
	end
	SetupFauxScroll(select.ScrollFrame, select.Grid, INSTANCE_BUTTON_HEIGHT + INSTANCE_PADDING_Y, EncounterJournal_UpdateInstanceButtons);

	-- expansion (tier) dropdown
	select.ExpansionDropdown:SetupMenu(function(dropdown, rootDescription)
		for tierIndex = 1, EJ_GetNumTiers() do
			local name = EJ_GetTierInfo(tierIndex);
			rootDescription:CreateRadio(name, function(index)
				return EJ_GetCurrentTier() == index;
			end, function(index)
				EncounterJournal_TierDropdown_Select(index);
			end, tierIndex);
		end
	end);

	EncounterJournal_InitEncounterFrame(self);
	EncounterJournal_InitSearch(self);

	self.listRaids = false;
	self.infoTab = "overview";
end

function EncounterJournal_InitEncounterFrame(self)
	local encounter = self.encounter;
	local info = encounter.info;

	-- left page: boss buttons
	local left = encounter.leftPage;
	left.buttons = {};
	for index = 1, BOSS_ROWS do
		local button = CreateFrame("Button", "EncounterJournalBossButton" .. index, left.bossList, "EncounterBossButtonTemplate");
		button:SetPoint("TOPLEFT", left.bossList, "TOPLEFT", 0, -(index - 1) * BOSS_ROW_HEIGHT);
		left.buttons[index] = button;
	end
	SetupFauxScroll(left.bossScroll, left.bossList, BOSS_ROW_HEIGHT, EncounterJournal_UpdateBossButtons);

	-- side tabs: under the frame border, like retail
	for _, data in ipairs(INFO_TABS) do
		local tab = self[data.button];
		tab.tabKey = data.key;
		tab.tooltip = data.tooltip;
		tab.icon:SetTexture(TAB_TEXTURE);
		tab:SetFrameLevel(self:GetFrameLevel() + 1);
	end

	-- difficulty
	info.difficulty:SetupMenu(function(dropdown, rootDescription)
		for _, difficulty in ipairs(DIFFICULTIES) do
			if EJ_IsValidInstanceDifficulty(difficulty.id) then
				rootDescription:CreateRadio(difficulty.text, function(id)
					return EJ_GetDifficulty() == id;
				end, function(id)
					EJ_SetDifficulty(id);
					EncounterJournal_Refresh();
				end, difficulty.id);
			end
		end
	end);

	-- loot rows + filters
	local loot = info.loot;
	loot.buttons = {};
	for index = 1, LOOT_ROWS do
		local button = CreateFrame("Button", "EncounterJournalLootButton" .. index, loot.list, "EncounterItemTemplate");
		button:SetPoint("TOPLEFT", loot.list, "TOPLEFT", 0, -(index - 1) * LOOT_ROW_HEIGHT);
		loot.buttons[index] = button;
	end
	SetupFauxScroll(loot.scroll, loot.list, LOOT_ROW_HEIGHT, EncounterJournal_LootUpdate);

	loot.classFilter:SetupMenu(function(dropdown, rootDescription)
		rootDescription:CreateRadio(ALL_CLASSES or "Все классы", function(index)
			return lootClassIndex == index;
		end, function(index)
			EncounterJournal_SetClassFilter(index);
		end, 0);
		local classes = { EJ_GetAvailableClasses() };
		for index = 1, #classes / 2 do
			local name, token = classes[index * 2 - 1], classes[index * 2];
			local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token];
			if color then
				name = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name);
			end
			rootDescription:CreateRadio(name, function(classIndex)
				return lootClassIndex == classIndex;
			end, function(classIndex)
				EncounterJournal_SetClassFilter(classIndex);
			end, index);
		end
	end);

	loot.slotFilter:SetupMenu(function(dropdown, rootDescription)
		rootDescription:CreateRadio(ALL_INVENTORY_SLOTS or "Все ячейки", function(id)
			return C_EncounterJournal.GetSlotFilter() == id;
		end, function(id)
			EncounterJournal_SetSlotFilter(id);
		end, SLOT_FILTER_NO_FILTER);
		for _, slot in ipairs(SLOT_FILTERS) do
			rootDescription:CreateRadio(slot.text, function(id)
				return C_EncounterJournal.GetSlotFilter() == id;
			end, function(id)
				EncounterJournal_SetSlotFilter(id);
			end, slot.id);
		end
	end);
	EncounterJournal_UpdateLootFilterText();

	-- model: creature buttons on the left edge, above the model
	local model = info.model;
	model.creatureButtons = {};
	for index = 1, MAX_CREATURES do
		local button = CreateFrame("Button", "EncounterJournalCreatureButton" .. index, model, "EncounterCreatureButtonTemplate");
		button:SetPoint("TOPLEFT", model, "TOPLEFT", 4, -4 - (index - 1) * 42);
		button:SetFrameLevel(model.modelFrame:GetFrameLevel() + 2);
		model.creatureButtons[index] = button;
	end
	model.titleFrame:SetFrameLevel(model.modelFrame:GetFrameLevel() + 1);
end

function EncounterJournal_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	C_EncounterJournal.OnOpen();

	if not self.tierInitialized then
		self.tierInitialized = true;
		C_EncounterJournal.InitalizeSelectedTier();
		self:SetTab(self.listRaids and self.raidsTabID or self.dungeonsTabID);
	end

	EncounterJournal_UpdateTierText();
	if UpdateMicroButtons then
		UpdateMicroButtons();
	end
end

function EncounterJournal_OnHide(self)
	PlaySound("igCharacterInfoClose");
	C_EncounterJournal.OnClose();
	EncounterJournal_HideSearchPreview();
	if UpdateMicroButtons then
		UpdateMicroButtons();
	end
end

function EncounterJournal_OnEvent(self, event, ...)
	if event == "EJ_DIFFICULTY_UPDATE" and not self.suppressRefresh then
		EncounterJournal_Refresh();
	end
end

---------------------------------------------------------------------------
-- tiers
---------------------------------------------------------------------------
function EncounterJournal_UpdateTierText()
	local dropdown = EncounterJournal.instanceSelect.ExpansionDropdown;
	local name = EJ_GetTierInfo(EJ_GetCurrentTier());
	if dropdown.SetText and name then
		dropdown:SetText(name);
	end
end

function EncounterJournal_TierDropdown_Select(tierIndex)
	EJ_SelectTier(tierIndex);
	EncounterJournal_UpdateTierText();
	EncounterJournal_ListInstances();
end

---------------------------------------------------------------------------
-- instance grid
---------------------------------------------------------------------------
function EncounterJournal_SetListRaids(listRaids)
	EncounterJournal.listRaids = listRaids;
	EncounterJournal_ShowInstanceSelect();
end

function EncounterJournal_ShowInstanceSelect()
	local journal = EncounterJournal;
	NavBar_Reset(journal.navBar);
	journal.encounter:Hide();
	journal.searchResults:Hide();
	for _, data in ipairs(INFO_TABS) do
		journal[data.button]:Hide();
	end
	journal.instanceID = nil;
	journal.encounterID = nil;
	journal.instanceSelect:Show();
	EncounterJournal_ListInstances();
end

function EncounterJournal_ListInstances()
	local journal = EncounterJournal;
	local select = journal.instanceSelect;

	local expansion = EJ_GetExpansion and EJ_GetExpansion() or 2;
	select.bg:SetTexture(TIER_BACKGROUNDS[expansion] or "Interface\\EncounterJournal\\UI-EJ-Cataclysm");

	local list = {};
	local index = 1;
	while true do
		local instanceID, name, _, _, buttonImage, _, _, _, link = EJ_GetInstanceByIndex(index, journal.listRaids);
		if not instanceID then
			break;
		end
		table.insert(list, { instanceID = instanceID, name = name, buttonImage = buttonImage, link = link });
		index = index + 1;
	end
	select.list = list;

	ResetFauxScroll(select.ScrollFrame);
	EncounterJournal_UpdateInstanceButtons();
end

function EncounterJournal_UpdateInstanceButtons()
	local select = EncounterJournal.instanceSelect;
	local list = select.list or {};
	local numRows = math.ceil(#list / INSTANCE_COLUMNS);
	local rowOffset = FauxScrollFrame_GetOffset(select.ScrollFrame);
	FauxScrollFrame_Update(select.ScrollFrame, numRows, INSTANCE_ROWS, INSTANCE_BUTTON_HEIGHT + INSTANCE_PADDING_Y);

	for index, button in ipairs(select.buttons) do
		local entry = list[rowOffset * INSTANCE_COLUMNS + index];
		if entry then
			button.instanceID = entry.instanceID;
			button.link = entry.link;
			button.name:SetText(entry.name);
			button.bgImage:SetTexture(entry.buttonImage);
			button:Show();
		else
			button:Hide();
		end
	end
end

---------------------------------------------------------------------------
-- difficulty
---------------------------------------------------------------------------
local function DifficultyText(difficultyID)
	for _, difficulty in ipairs(DIFFICULTIES) do
		if difficulty.id == difficultyID then
			return difficulty.text;
		end
	end
	return "";
end

-- Keeps the selected difficulty valid for the current instance. Always sets it: after a raid the
-- data can still hold a raid difficulty that EJ_GetDifficulty() reports as "normal" in a dungeon.
local function FixDifficulty()
	local chosen = EJ_GetDifficulty();
	if not EJ_IsValidInstanceDifficulty(chosen) then
		chosen = nil;
		for _, difficulty in ipairs(DIFFICULTIES) do
			if EJ_IsValidInstanceDifficulty(difficulty.id) then
				chosen = difficulty.id;
				break;
			end
		end
	end
	if chosen then
		EncounterJournal.suppressRefresh = true;
		EJ_SetDifficulty(chosen);
		EncounterJournal.suppressRefresh = nil;
	end
end

function EncounterJournal_UpdateDifficulty()
	local dropdown = EncounterJournal.encounter.info.difficulty;
	local numValid = 0;
	for _, difficulty in ipairs(DIFFICULTIES) do
		if EJ_IsValidInstanceDifficulty(difficulty.id) then
			numValid = numValid + 1;
		end
	end
	SetShown(dropdown, numValid > 1);
	dropdown:SetText(DifficultyText(EJ_GetDifficulty()));
end

function EncounterJournal_Refresh()
	local journal = EncounterJournal;
	if not journal.instanceID then
		return;
	end
	EncounterJournal_UpdateDifficulty();
	local info = journal.encounter.info;
	if info.loot:IsShown() then
		EncounterJournal_LootUpdate();
	end
	if info.detailsScroll:IsShown() then
		EncounterJournal_UpdateAbilities();
	end
end

---------------------------------------------------------------------------
-- instance page: boss list (left) + lore (right)
---------------------------------------------------------------------------
function EncounterJournal_DisplayInstance(instanceID, noButton)
	local journal = EncounterJournal;
	local name, description, bgImage, _, loreImage = EJ_GetInstanceInfo(instanceID);
	if not name then
		return;
	end

	journal.instanceID = instanceID;
	journal.encounterID = nil;
	journal.instanceName = name;
	journal.dungeonBG = bgImage;
	EJ_SelectInstance(instanceID);
	FixDifficulty();

	local encounter = journal.encounter;
	encounter.leftPage.instanceButton.title:SetText(name);

	-- lore
	local instance = encounter.instance;
	instance.title:SetText(name);
	if loreImage and loreImage ~= "" then
		instance.loreBG:SetTexture(loreImage);
	else
		instance.loreBG:SetTexture("Interface\\EncounterJournal\\UI-EJ-LOREBG-Default");
	end
	local loreChild = instance.loreScroll.child;
	loreChild.lore:SetText(description or "");
	loreChild:SetHeight(loreChild.lore:GetStringHeight() + 10);
	instance.loreScroll:UpdateScrollChildRect();
	ScrollBarOf(instance.loreScroll):SetValue(0);

	-- bosses
	local bosses = {};
	local index = 1;
	while true do
		local bossName, _, encounterID, _, link = EJ_GetEncounterInfoByIndex(index, instanceID);
		if not bossName then
			break;
		end
		local _, _, _, _, bossImage = EJ_GetCreatureInfo(1, encounterID);
		table.insert(bosses, { name = bossName, encounterID = encounterID, link = link, image = bossImage });
		index = index + 1;
	end
	journal.bosses = bosses;
	ResetFauxScroll(encounter.leftPage.bossScroll);
	EncounterJournal_UpdateBossButtons();

	journal.instanceSelect:Hide();
	journal.searchResults:Hide();
	encounter:Show();

	if not noButton then
		NavBar_Reset(journal.navBar);
		NavBar_AddButton(journal.navBar, {
			name = name,
			OnClick = function() EncounterJournal_DisplayInstance(instanceID, true); end,
		});
	end

	-- the instance itself has only lore and loot
	if journal.infoTab ~= "loot" then
		journal.infoTab = "overview";
	end
	EncounterJournal_UpdateInfo();
end

function EncounterJournal_UpdateBossButtons()
	local journal = EncounterJournal;
	local left = journal.encounter.leftPage;
	local bosses = journal.bosses or {};
	FauxScrollFrame_Update(left.bossScroll, #bosses, BOSS_ROWS, BOSS_ROW_HEIGHT);
	local offset = FauxScrollFrame_GetOffset(left.bossScroll);

	for index, button in ipairs(left.buttons) do
		local boss = bosses[offset + index];
		if boss then
			button.encounterID = boss.encounterID;
			button.link = boss.link;
			button.text:SetText(boss.name);
			button.creature:SetTexture(boss.image or DEFAULT_BOSS_IMAGE);
			if boss.encounterID == journal.encounterID then
				button:LockHighlight();
			else
				button:UnlockHighlight();
			end
			button:Show();
		else
			button:Hide();
		end
	end
end

function EncounterJournalBossButton_OnClick(self)
	if IsModifiedClick("CHATLINK") and self.link then
		ChatEdit_InsertLink(self.link);
		return;
	end
	EncounterJournal_DisplayEncounter(self.encounterID);
	PlaySound("igAbiliityPageTurn");
end

---------------------------------------------------------------------------
-- encounter page
---------------------------------------------------------------------------
function EncounterJournal_DisplayEncounter(encounterID, noButton)
	local journal = EncounterJournal;
	local name, description, _, rootSectionID = EJ_GetEncounterInfo(encounterID);
	if not name then
		return;
	end

	-- opened from outside (world map, link, search): show its instance first
	local data = EJ_DATA.encounters[encounterID];
	if data and journal.instanceID ~= data.instanceID then
		EncounterJournal_DisplayInstance(data.instanceID);
	end

	journal.encounterID = encounterID;
	journal.encounterName = name;
	journal.encounterDescription = description;
	journal.rootSectionID = rootSectionID;
	EJ_SelectEncounter(encounterID);

	EncounterJournal_UpdateCreatures();
	EncounterJournal_UpdateBossButtons();

	if not noButton then
		NavBar_Reset(journal.navBar);
		local instanceID = journal.instanceID;
		NavBar_AddButton(journal.navBar, {
			name = journal.instanceName,
			OnClick = function() EncounterJournal_DisplayInstance(instanceID, true); end,
		});
		NavBar_AddButton(journal.navBar, {
			name = name,
			OnClick = function() EncounterJournal_DisplayEncounter(encounterID, true); end,
		});
	end

	EncounterJournal_UpdateInfo();
end

-- which content the right page shows: lore / overview / abilities / loot / model
function EncounterJournal_UpdateInfo()
	local journal = EncounterJournal;
	local encounter = journal.encounter;
	local info = encounter.info;
	local isEncounter = journal.encounterID ~= nil;

	local enabled = {
		overview = true,
		loot = true,
		abilities = isEncounter and journal.rootSectionID ~= nil and journal.rootSectionID ~= 0,
		model = isEncounter and (journal.numCreatures or 0) > 0,
	};
	if not enabled[journal.infoTab] then
		journal.infoTab = "overview";
	end
	local tab = journal.infoTab;

	for _, data in ipairs(INFO_TABS) do
		local button = journal[data.button];
		local isSelected = data.key == tab;
		SetShown(button.selected, isSelected);
		SetShown(button.unselected, not isSelected);
		button.icon:SetTexCoord(unpack(isSelected and data.selected or data.unselected));
		if enabled[data.key] then
			button:Enable();
			button.icon:SetDesaturated(false);
			button.icon:SetAlpha(1);
		else
			button:Disable();
			button.icon:SetDesaturated(true);
			button.icon:SetAlpha(0.5);
		end
		button:Show();
	end

	info.overviewScroll:Hide();
	info.detailsScroll:Hide();
	info.loot:Hide();
	info.model:Hide();

	if not isEncounter and tab == "overview" then
		info:Hide();
		encounter.instance:Show();
		return;
	end

	encounter.instance:Hide();
	info:Show();
	info.encounterTitle:SetText(isEncounter and journal.encounterName or journal.instanceName);
	EncounterJournal_UpdateDifficulty();

	if tab == "overview" then
		info.overviewScroll:Show();
		EncounterJournal_UpdateOverview();
	elseif tab == "abilities" then
		info.detailsScroll:Show();
		EncounterJournal_UpdateAbilities();
	elseif tab == "loot" then
		info.loot:Show();
		ResetFauxScroll(info.loot.scroll);
		EncounterJournal_LootUpdate();
	elseif tab == "model" then
		info.model:Show();
		EncounterJournal_ShowModel();
	end
end

function EncounterJournal_SetInfoTab(tabKey)
	EncounterJournal.infoTab = tabKey;
	EncounterJournal_UpdateInfo();
end

---------------------------------------------------------------------------
-- overview
---------------------------------------------------------------------------
function EncounterJournal_UpdateOverview()
	local journal = EncounterJournal;
	local scroll = journal.encounter.info.overviewScroll;
	local child = scroll.child;

	child.headerText:SetText(OVERVIEW or "Обзор");
	child.description:SetText(journal.encounterDescription or "");

	local names = {};
	for _, creature in ipairs(journal.creatures or {}) do
		table.insert(names, creature.name);
	end
	if #names > 1 then
		child.creatures:SetText("Участники боя: " .. table.concat(names, ", "));
	else
		child.creatures:SetText("");
	end

	child:SetHeight(30 + 10 + child.description:GetStringHeight() + 14 + child.creatures:GetStringHeight() + 10);
	scroll:UpdateScrollChildRect();
	ScrollBarOf(scroll):SetValue(0);
end

---------------------------------------------------------------------------
-- abilities: section tree, expanded state kept per section
---------------------------------------------------------------------------
function EncounterJournal_SetFlagIcon(texture, index)
	local iconSize = 32;
	local columns = 256 / iconSize;
	local rows = 64 / iconSize;
	local l = mod(index, columns) / columns;
	local r = l + (1 / columns);
	local t = floor(index / columns) / rows;
	local b = t + (1 / rows);
	texture:SetTexCoord(l, r, t, b);
end

local function AcquireHeader(index, parent)
	local header = infoHeaders[index];
	if not header then
		header = CreateFrame("Frame", "EncounterJournalInfoHeader" .. index, parent, "EncounterInfoTemplate");
		infoHeaders[index] = header;
	end
	return header;
end

local function SetupHeader(header, sectionID, depth, title, description, abilityIcon, displayInfo, hasChildren, link, flags)
	local button = header.button;
	header.sectionID = sectionID;
	header.hasContent = (description ~= nil and description ~= "") or hasChildren;
	button.link = link;

	local expanded = sectionOpen[sectionID];
	if not header.hasContent then
		button.expandedIcon:SetText("");
	elseif expanded then
		button.expandedIcon:SetText("-");
	else
		button.expandedIcon:SetText("+");
	end

	-- icon: the ability icon, or the creature for add sections
	local icon = abilityIcon;
	if not icon and displayInfo and displayInfo > 0 then
		icon = CreatureIconForDisplayID(displayInfo) or GENERIC_CREATURE_ICON;
	end
	local textLeft = button.expandedIcon;
	if icon then
		button.abilityIcon:SetTexture(icon);
		if abilityIcon then
			button.abilityIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
		elseif icon ~= GENERIC_CREATURE_ICON then
			button.abilityIcon:SetTexCoord(0.25, 0.75, 0, 1);
		else
			button.abilityIcon:SetTexCoord(0, 1, 0, 1);
		end
		button.abilityIcon:Show();
		button.abilityIconBorder:Show();
		textLeft = button.abilityIcon;
	else
		button.abilityIcon:Hide();
		button.abilityIconBorder:Hide();
	end

	-- flags (tank / healer / heroic / magic ...), right to left: icon4 is the rightmost
	local numFlags = #flags;
	local textRight;
	for i = 1, 4 do
		local flagFrame = button["icon" .. (4 - numFlags + i)];
		local flag = flags[i];
		if flagFrame and flag then
			EncounterJournal_SetFlagIcon(flagFrame.icon, flag);
			flagFrame.tooltipTitle = _G["ENCOUNTER_JOURNAL_SECTION_FLAG" .. flag];
			flagFrame.tooltipText = _G["ENCOUNTER_JOURNAL_SECTION_FLAG_DESCRIPTION" .. flag];
			flagFrame:Show();
			textRight = textRight or flagFrame;
		end
	end
	for i = 1, 4 - numFlags do
		button["icon" .. i]:Hide();
	end

	button.title:SetFontObject(depth == 0 and GameFontNormalMed3 or GameFontNormal);
	button.title:SetText(title);
	button.title:ClearAllPoints();
	button.title:SetPoint("LEFT", textLeft, "RIGHT", 5, 0);
	if textRight then
		button.title:SetPoint("RIGHT", textRight, "LEFT", -5, 0);
	else
		button.title:SetPoint("RIGHT", button, "RIGHT", -8, 0);
	end
end

function EncounterJournal_UpdateAbilities()
	local journal = EncounterJournal;
	local scroll = journal.encounter.info.detailsScroll;
	local child = scroll.child;
	local width = child:GetWidth();
	local count, y = 0, 0;

	local function AddSections(sectionID, depth, guard)
		while sectionID and guard < 500 do
			local title, description, _, abilityIcon, displayInfo, siblingID, childID, filtered, link, startsOpen,
				f1, f2, f3, f4 = EJ_GetSectionInfo(sectionID);
			if not title then
				break;
			end
			if not filtered then
				if sectionOpen[sectionID] == nil then
					sectionOpen[sectionID] = startsOpen and true or false;
				end

				count = count + 1;
				local header = AcquireHeader(count, child);
				local indent = depth * HEADER_INDENT;
				header:ClearAllPoints();
				header:SetPoint("TOPLEFT", child, "TOPLEFT", indent, -y);
				header:SetWidth(width - indent);
				SetupHeader(header, sectionID, depth, title, description, abilityIcon, displayInfo, childID ~= nil, link,
					{ f1, f2, f3, f4 });
				header.y = y;
				header:Show();

				local height = HEADER_HEIGHT;
				if sectionOpen[sectionID] and description and description ~= "" then
					header.description:SetWidth(width - indent - 20);
					header.description:SetText(description);
					header.description:Show();
					height = height + 6 + header.description:GetStringHeight() + 6;
				else
					header.description:Hide();
				end
				header:SetHeight(height);
				y = y + height + HEADER_SPACING;

				if sectionOpen[sectionID] and childID then
					AddSections(childID, depth + 1, guard + 1);
				end
			end
			sectionID = siblingID;
			guard = guard + 1;
		end
	end

	if journal.rootSectionID and journal.rootSectionID ~= 0 then
		AddSections(journal.rootSectionID, 0, 0);
	end

	for index = count + 1, #infoHeaders do
		infoHeaders[index]:Hide();
		infoHeaders[index].sectionID = nil;
	end

	child:SetHeight(math.max(y + 10, 10));
	scroll:UpdateScrollChildRect();
end

function EncounterJournalSectionButton_OnClick(self)
	local header = self:GetParent();
	if IsModifiedClick("CHATLINK") and self.link then
		ChatEdit_InsertLink(self.link);
		return;
	end
	if not header.hasContent then
		return;
	end
	sectionOpen[header.sectionID] = not sectionOpen[header.sectionID];
	EncounterJournal_UpdateAbilities();
	PlaySound(sectionOpen[header.sectionID] and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff");
end

-- opens the path to a section and scrolls to it (search results, links)
function EncounterJournal_FocusSection(sectionID)
	local journal = EncounterJournal;
	local scroll = journal.encounter.info.detailsScroll;
	for _, header in ipairs(infoHeaders) do
		if header:IsShown() and header.sectionID == sectionID then
			local scrollBar = ScrollBarOf(scroll);
			local _, maxValue = scrollBar:GetMinMaxValues();
			scrollBar:SetValue(math.min(header.y, maxValue or header.y));
			return;
		end
	end
end

---------------------------------------------------------------------------
-- loot
---------------------------------------------------------------------------
function EncounterJournal_LootUpdate()
	local journal = EncounterJournal;
	local loot = journal.encounter.info.loot;
	local numLoot = EJ_GetNumLoot();
	FauxScrollFrame_Update(loot.scroll, numLoot, LOOT_ROWS, LOOT_ROW_HEIGHT);
	local offset = FauxScrollFrame_GetOffset(loot.scroll);

	for i, button in ipairs(loot.buttons) do
		local index = offset + i;
		if index <= numLoot then
			local name, icon, slot, armorType, itemID, _, encounterID, quality = EJ_GetLootInfoByIndex(index);
			button.itemID = itemID;
			button.encounterID = encounterID;
			button.name:SetText(name or RETRIEVING_ITEM_INFO or "...");
			local color = quality and ITEM_QUALITY_COLORS[quality];
			if color then
				button.name:SetTextColor(color.r, color.g, color.b);
			else
				button.name:SetTextColor(1, 0.82, 0);
			end
			button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark");
			button.slot:SetText(slot or "");
			button.armorType:SetText(armorType or "");
			local bossName = not journal.encounterID and encounterID and EJ_GetEncounterInfo(encounterID);
			if bossName then
				button.boss:SetFormattedText(BOSS_INFO_STRING or "Босс: %s", bossName);
			else
				button.boss:SetText("");
			end
			button:Show();
			if GameTooltip:IsOwned(button) then
				EncounterJournalLootButton_OnEnter(button);
			end
		else
			button.itemID = nil;
			button:Hide();
		end
	end

	if numLoot == 0 then
		loot.empty.text:SetText("Нет добычи для выбранных фильтров");
		loot.empty:Show();
	else
		loot.empty:Hide();
	end
end

function EncounterJournal_UpdateLootFilterText()
	local loot = EncounterJournal.encounter.info.loot;

	local className = ALL_CLASSES or "Все классы";
	if lootClassIndex > 0 then
		local classes = { EJ_GetAvailableClasses() };
		className = classes[lootClassIndex * 2 - 1] or className;
	end
	loot.classFilter:SetText(className);

	local slotName = ALL_INVENTORY_SLOTS or "Все ячейки";
	local slotFilter = C_EncounterJournal.GetSlotFilter();
	for _, slot in ipairs(SLOT_FILTERS) do
		if slot.id == slotFilter then
			slotName = slot.text;
		end
	end
	loot.slotFilter:SetText(slotName);
end

function EncounterJournal_SetClassFilter(classIndex)
	lootClassIndex = classIndex or 0;
	EJ_SetClassLootFilter(lootClassIndex);
	EncounterJournal_UpdateLootFilterText();
	ResetFauxScroll(EncounterJournal.encounter.info.loot.scroll);
	EncounterJournal_LootUpdate();
end

function EncounterJournal_SetSlotFilter(slotFilter)
	C_EncounterJournal.SetSlotFilter(slotFilter);
	EncounterJournal_UpdateLootFilterText();
	ResetFauxScroll(EncounterJournal.encounter.info.loot.scroll);
	EncounterJournal_LootUpdate();
end

function EncounterJournalLootButton_OnEnter(self)
	if not self.itemID then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink("item:" .. self.itemID);
	GameTooltip:Show();
end

function EncounterJournalLootButton_OnUpdate(self)
	if not GameTooltip:IsOwned(self) then
		return;
	end
	if IsModifiedClick("COMPAREITEMS") or GetCVarBool("alwaysCompareItems") then
		GameTooltip_ShowCompareItem();
	else
		ShoppingTooltip1:Hide();
		ShoppingTooltip2:Hide();
		if ShoppingTooltip3 then
			ShoppingTooltip3:Hide();
		end
	end
	if IsModifiedClick("DRESSUP") then
		ShowInspectCursor();
	else
		ResetCursor();
	end
end

function EncounterJournalLootButton_OnClick(self, button)
	if not self.itemID then
		return;
	end
	local link = GetItemLink(self.itemID);
	if link and HandleModifiedItemClick(link) then
		return;
	end
	-- instance loot: a click opens the boss that drops it
	if not EncounterJournal.encounterID and self.encounterID then
		EncounterJournal_DisplayEncounter(self.encounterID);
	end
end

---------------------------------------------------------------------------
-- model: SetCreature through the creature cache (EncounterJournalModel.lua)
---------------------------------------------------------------------------
function EncounterJournal_UpdateCreatures()
	local journal = EncounterJournal;
	local model = journal.encounter.info.model;
	local creatures = {};
	local displayIDs = {};

	for index = 1, MAX_CREATURES do
		local id, name, _, displayInfo, icon = EJ_GetCreatureInfo(index, journal.encounterID);
		if not id then
			break;
		end
		table.insert(creatures, { id = id, name = name, displayInfo = displayInfo, icon = icon });
		if displayInfo and displayInfo > 0 then
			table.insert(displayIDs, displayInfo);
		end
	end
	journal.creatures = creatures;
	journal.numCreatures = #creatures;

	-- ask the server for every creature of the boss at once
	if EncounterJournal_PrefetchDisplayIDs then
		EncounterJournal_PrefetchDisplayIDs(displayIDs);
	end

	for index, button in ipairs(model.creatureButtons) do
		local creature = creatures[index];
		if creature and #creatures > 1 then
			button.id = creature.id;
			button.name = creature.name;
			button.displayInfo = creature.displayInfo;
			SetCreatureIcon(button.creature, creature.icon);
			button:Show();
		else
			button:Hide();
		end
	end

	model.shownCreature = nil;
	model.shownCreatureIndex = 1;
end

-- called when the model tab is shown: a model set while hidden is not drawn in 3.3.5
function EncounterJournal_ShowModel()
	local journal = EncounterJournal;
	local model = journal.encounter.info.model;
	if journal.dungeonBG and journal.dungeonBG ~= "" then
		model.dungeonBG:SetTexture(journal.dungeonBG);
	else
		model.dungeonBG:SetTexture(0, 0, 0, 0.6);
	end
	model.displayedID = nil;
	local creature = (journal.creatures or {})[model.shownCreatureIndex or 1] or (journal.creatures or {})[1];
	if creature then
		EncounterJournal_DisplayCreatureData(creature, model.shownCreatureIndex or 1);
	end
end

function EncounterJournal_DisplayCreatureData(creature, index)
	local model = EncounterJournal.encounter.info.model;
	model.shownCreatureIndex = index;
	model.titleFrame.imageTitle:SetText(creature.name or "");

	if creature.displayInfo and creature.displayInfo > 0 and model.displayedID ~= creature.displayInfo then
		model.displayedID = creature.displayInfo;
		if EncounterJournal_SetModelByDisplayID then
			EncounterJournal_SetModelByDisplayID(model.modelFrame, creature.displayInfo);
		end
	end

	for buttonIndex, button in ipairs(model.creatureButtons) do
		if buttonIndex == index then
			button:LockHighlight();
		else
			button:UnlockHighlight();
		end
	end
end

-- creature button click
function EncounterJournal_DisplayCreature(button)
	local creatures = EncounterJournal.creatures or {};
	for index, creature in ipairs(creatures) do
		if creature.id == button.id then
			EncounterJournal_DisplayCreatureData(creature, index);
			return;
		end
	end
end

---------------------------------------------------------------------------
-- search
---------------------------------------------------------------------------
function EncounterJournal_InitSearch(self)
	local searchBox = self.searchBox;
	searchBox.clearFunc = EncounterJournal_ClearSearch;
	searchBox:HookScript("OnEditFocusLost", function()
		-- hide a moment later so a click on a preview row still lands
		self.searchPreview.hideTimer = 0.25;
	end);
	searchBox:HookScript("OnEditFocusGained", function(box)
		self.searchPreview.hideTimer = nil;
		EncounterJournal_OnSearchTextChanged(box);
	end);

	local preview = self.searchPreview;
	preview.buttons = {};
	for index = 1, SEARCH_PREVIEW_ROWS do
		local button = CreateFrame("Button", "EncounterJournalSearchPreviewButton" .. index, preview, "EncounterSearchSMTemplate");
		button:SetPoint("TOPLEFT", preview, "TOPLEFT", 5, -5 - (index - 1) * SEARCH_PREVIEW_HEIGHT);
		preview.buttons[index] = button;
	end
	preview:SetScript("OnUpdate", function(frame, elapsed)
		if frame.hideTimer then
			frame.hideTimer = frame.hideTimer - elapsed;
			if frame.hideTimer <= 0 then
				frame.hideTimer = nil;
				frame:Hide();
			end
		end
	end);

	local results = self.searchResults;
	results:SetFrameLevel(self:GetFrameLevel() + 30);
	results.buttons = {};
	for index = 1, SEARCH_ROWS do
		local button = CreateFrame("Button", "EncounterJournalSearchResult" .. index, results.list, "EncounterSearchLGTemplate");
		button:SetPoint("TOPLEFT", results.list, "TOPLEFT", 0, -(index - 1) * SEARCH_ROW_HEIGHT);
		results.buttons[index] = button;
	end
	SetupFauxScroll(results.scroll, results.list, SEARCH_ROW_HEIGHT, EncounterJournal_SearchUpdate);
end

local function InstanceName(instanceID)
	local inst = instanceID and EJ_DATA.instances[instanceID];
	return inst and inst.name or "";
end

local function EncounterName(encounterID)
	local enc = encounterID and EJ_DATA.encounters[encounterID];
	return enc and enc.name or "";
end

-- name, icon, path, typeText, itemID, stype, texCoords
function EncounterJournal_GetSearchDisplay(index)
	local id, stype, _, instanceID, encounterID = EJ_GetSearchResult(index);
	local name, icon, path, typeText, itemID, coords;
	local bossPath = InstanceName(instanceID) .. " | " .. EncounterName(encounterID);

	if stype == EJ_STYPE_INSTANCE then
		local _, _, _, buttonImage = EJ_GetInstanceInfo(id);
		name = InstanceName(id);
		icon = buttonImage;
		coords = { 0.16796875, 0.51171875, 0.03125, 0.71875 };
		typeText = ENCOUNTER_JOURNAL_INSTANCE;
		path = "";
	elseif stype == EJ_STYPE_ENCOUNTER then
		local _, _, _, _, bossImage = EJ_GetCreatureInfo(1, id);
		name = EncounterName(id);
		icon = bossImage;
		typeText = ENCOUNTER_JOURNAL_ENCOUNTER;
		path = InstanceName(instanceID);
	elseif stype == EJ_STYPE_SECTION then
		local title, _, _, abilityIcon, displayInfo = EJ_GetSectionInfo(id);
		name = title;
		if displayInfo and displayInfo > 0 then
			icon = CreatureIconForDisplayID(displayInfo);
			typeText = ENCOUNTER_JOURNAL_ENCOUNTER_ADD;
		else
			icon = abilityIcon;
			coords = { 0, 1, 0, 1 };
			typeText = ENCOUNTER_JOURNAL_ABILITY;
		end
		path = bossPath;
	elseif stype == EJ_STYPE_ITEM then
		local itemName, _, _, _, _, itemIcon = GetItemInfoCached(id);
		name = itemName;
		icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark";
		coords = { 0, 1, 0, 1 };
		itemID = id;
		typeText = ENCOUNTER_JOURNAL_ITEM;
		path = bossPath;
	elseif stype == EJ_STYPE_CREATURE then
		local creature = EJ_DATA.creatures[id];
		name = creature and creature.name;
		icon = creature and creature.icon;
		typeText = ENCOUNTER_JOURNAL_ENCOUNTER;
		path = bossPath;
	end

	return name or "", icon, path or "", typeText or "", itemID, stype, coords;
end

local function SetSearchButton(button, index)
	local name, icon, path, typeText, itemID, _, coords = EncounterJournal_GetSearchDisplay(index);
	button.index = index;
	button.itemID = itemID;
	button.name:SetText(name);
	if coords then
		button.icon:SetTexture(icon);
		button.icon:SetTexCoord(unpack(coords));
	else
		SetCreatureIcon(button.icon, icon);
	end
	if button.path then
		button.path:SetText(path);
		button.resultType:SetText(typeText);
	end
	button:Show();
end

function EncounterJournalSearchButton_OnEnter(self)
	if self.itemID then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("item:" .. self.itemID);
		GameTooltip:Show();
	end
end

function EncounterJournal_OnSearchTextChanged(self)
	local text = self:GetText() or "";
	if text == SEARCH or TextLength(text) < EJ_MIN_CHARACTER_SEARCH then
		EJ_ClearSearch();
		EncounterJournal_HideSearchPreview();
		EncounterJournal.searchResults:Hide();
		return;
	end

	EJ_SetSearch(text);
	if EncounterJournal.searchResults:IsShown() then
		EncounterJournal_ShowFullSearch();
	elseif self:HasFocus() then
		EncounterJournal_ShowSearchPreview();
	end
end

function EncounterJournal_ShowSearchPreview()
	local preview = EncounterJournal.searchPreview;
	local numResults = EJ_GetNumSearchResults();
	if numResults == 0 then
		preview:Hide();
		return;
	end

	local shown = math.min(numResults, SEARCH_PREVIEW_ROWS);
	for index, button in ipairs(preview.buttons) do
		if index <= shown then
			SetSearchButton(button, index);
		else
			button:Hide();
		end
	end

	local height = 10 + shown * SEARCH_PREVIEW_HEIGHT;
	preview.showAll:ClearAllPoints();
	preview.showAll:SetPoint("TOPLEFT", preview, "TOPLEFT", 5, -5 - shown * SEARCH_PREVIEW_HEIGHT);
	if numResults > SEARCH_PREVIEW_ROWS then
		preview.showAll.text:SetFormattedText(ENCOUNTER_JOURNAL_SHOW_SEARCH_RESULTS or "Показать все результаты: %d", numResults);
		preview.showAll:Show();
		height = height + 22;
	else
		preview.showAll:Hide();
	end
	preview:SetHeight(height);
	preview.hideTimer = nil;
	preview:Show();
end

function EncounterJournal_HideSearchPreview()
	local preview = EncounterJournal.searchPreview;
	preview.hideTimer = nil;
	preview:Hide();
end

function EncounterJournal_ShowFullSearch()
	local journal = EncounterJournal;
	local numResults = EJ_GetNumSearchResults();
	EncounterJournal_HideSearchPreview();
	journal.searchBox:ClearFocus();
	if numResults == 0 then
		journal.searchResults:Hide();
		return;
	end

	local results = journal.searchResults;
	results.TitleText:SetFormattedText(ENCOUNTER_JOURNAL_SEARCH_RESULTS or "Результаты поиска для \"%s\" (%d)",
		journal.searchBox:GetText(), numResults);
	results:Show();
	ResetFauxScroll(results.scroll);
	EncounterJournal_SearchUpdate();
end

function EncounterJournal_SearchUpdate()
	local results = EncounterJournal.searchResults;
	local numResults = EJ_GetNumSearchResults();
	FauxScrollFrame_Update(results.scroll, numResults, SEARCH_ROWS, SEARCH_ROW_HEIGHT);
	local offset = FauxScrollFrame_GetOffset(results.scroll);

	for i, button in ipairs(results.buttons) do
		local index = offset + i;
		if index <= numResults then
			SetSearchButton(button, index);
		else
			button:Hide();
		end
	end
end

function EncounterJournal_ClearSearch()
	EJ_ClearSearch();
	EncounterJournal_HideSearchPreview();
	EncounterJournal.searchResults:Hide();
end

function EncounterJournal_SelectSearch(index)
	local id, stype, _, instanceID, encounterID = EJ_GetSearchResult(index);
	if not id then
		return;
	end
	local sectionID, creatureID, itemID;
	if stype == EJ_STYPE_INSTANCE then
		instanceID = id;
		encounterID = nil;
	elseif stype == EJ_STYPE_SECTION then
		sectionID = id;
	elseif stype == EJ_STYPE_ITEM then
		itemID = id;
	elseif stype == EJ_STYPE_CREATURE then
		creatureID = id;
	end

	EncounterJournal_HideSearchPreview();
	EncounterJournal.searchResults:Hide();
	EncounterJournal.searchBox:ClearFocus();
	EncounterJournal_OpenJournal(nil, instanceID, encounterID, sectionID, creatureID, itemID);
	PlaySound("igMainMenuOptionCheckBoxOn");
end

---------------------------------------------------------------------------
-- opening from outside (micro button, links, world map, search)
---------------------------------------------------------------------------
function EncounterJournal_OpenJournal(difficultyID, instanceID, encounterID, sectionID, creatureID, itemID)
	local journal = EncounterJournal;
	ShowUIPanel(journal);

	local inst = instanceID and EJ_DATA.instances[instanceID];
	if not inst then
		if not journal.instanceSelect:IsShown() then
			EncounterJournal_ShowInstanceSelect();
		end
		return;
	end

	-- the grid under "Home" follows the opened instance
	local expansion = inst.expansion or 0;
	if EJ_GetExpansion() ~= expansion then
		EJ_SetExpansion(expansion);
		EncounterJournal_UpdateTierText();
	end
	local tabID = inst.isRaid and journal.raidsTabID or journal.dungeonsTabID;
	if journal:GetTab() ~= tabID then
		journal:SetTab(tabID);
	else
		journal.listRaids = inst.isRaid and true or false;
		EncounterJournal_ListInstances();
	end

	EncounterJournal_DisplayInstance(instanceID);
	if difficultyID and EJ_IsValidInstanceDifficulty(difficultyID) then
		EJ_SetDifficulty(difficultyID);
	end

	if encounterID then
		if sectionID then
			for _, pathID in ipairs({ EJ_GetSectionPath(sectionID) }) do
				sectionOpen[pathID] = true;
			end
			journal.infoTab = "abilities";
		elseif itemID then
			journal.infoTab = "loot";
		elseif creatureID then
			journal.infoTab = "model";
		end

		EncounterJournal_DisplayEncounter(encounterID);

		if creatureID then
			for index, creature in ipairs(journal.creatures or {}) do
				if creature.id == creatureID then
					EncounterJournal_DisplayCreatureData(creature, index);
				end
			end
		end
		if sectionID then
			EncounterJournal_FocusSection(sectionID);
		end
	elseif itemID then
		EncounterJournal_SetInfoTab("loot");
	end
end

-- |Hjournal:type:id:difficulty|h (ItemRef.lua). The difficulty in the link is ignored: links from
-- the 4.3.4 API carry its context index, not the retail difficultyID.
function EncounterJournal_OpenJournalLink(tag, jtype, id, difficulty)
	local instanceID, encounterID, sectionID = EJ_HandleLinkPath(tonumber(jtype), id);
	EncounterJournal_OpenJournal(nil, instanceID, encounterID, sectionID);
end
