-- Blizzard_EncounterJournal (retail) for 3.3.5. Data: EncounterJournalData.lua + EncounterJournalAPI.lua,
-- retail API: Blizzard_EncounterJournal_Compat335.lua.
--
-- Stage 1: tabs Dungeons / Raids, tier (expansion) dropdown, instance grid, navigation bar,
-- instance lore page.

local INSTANCE_BUTTON_WIDTH, INSTANCE_BUTTON_HEIGHT = 174, 96;
local INSTANCE_PADDING_X, INSTANCE_PADDING_Y = 15, 15;
local INSTANCE_COLUMNS = 4;
local INSTANCE_ROWS = 3;	-- visible rows: 3*96 + 2*15 = 318 fits the grid (~367), 4 rows (429) overflow the frame

-- retail tier backgrounds (EJ_TIER_DATA)
local TIER_BACKGROUNDS = {
	[0] = "Interface\\EncounterJournal\\UI-EJ-Classic",
	[1] = "Interface\\EncounterJournal\\UI-EJ-BurningCrusade",
	[2] = "Interface\\EncounterJournal\\UI-EJ-WrathoftheLichKing",
};

EJ_TABS = { DUNGEONS = 1, RAIDS = 2 };

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

	local rowHeight = INSTANCE_BUTTON_HEIGHT + INSTANCE_PADDING_Y;
	select.ScrollFrame:SetScript("OnVerticalScroll", function(scrollFrame, offset)
		FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, rowHeight, EncounterJournal_UpdateInstanceButtons);
	end);
	select.Grid:SetScript("OnMouseWheel", function(_, delta)
		local scrollBar = _G[select.ScrollFrame:GetName() .. "ScrollBar"];
		scrollBar:SetValue(scrollBar:GetValue() - delta * rowHeight);
	end);

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

	self.listRaids = false;
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
	if UpdateMicroButtons then
		UpdateMicroButtons();
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
	journal.instanceFrame:Hide();
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

	FauxScrollFrame_SetOffset(select.ScrollFrame, 0);
	_G[select.ScrollFrame:GetName() .. "ScrollBar"]:SetValue(0);
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
-- instance page (stage 1: lore + list of bosses; encounter pages - stage 2)
---------------------------------------------------------------------------
function EncounterJournal_DisplayInstance(instanceID)
	local journal = EncounterJournal;
	EJ_SelectInstance(instanceID);

	local name, description, _, _, loreImage = EJ_GetInstanceInfo(instanceID);
	if not name then
		return;
	end

	local frame = journal.instanceFrame;
	frame.title:SetText(name);
	frame.description:SetText(description or "");
	if loreImage and loreImage ~= "" then
		frame.loreBG:SetTexture(loreImage);
	else
		frame.loreBG:SetTexture("Interface\\EncounterJournal\\UI-EJ-LOREBG-Default");
	end

	local bosses = {};
	local index = 1;
	while true do
		local bossName = EJ_GetEncounterInfoByIndex(index, instanceID);
		if not bossName then
			break;
		end
		table.insert(bosses, bossName);
		index = index + 1;
	end
	frame.encounterHint:SetText(#bosses > 0 and ("Боссы: " .. table.concat(bosses, ", ")) or "");

	journal.instanceSelect:Hide();
	frame:Show();

	NavBar_Reset(journal.navBar);
	NavBar_AddButton(journal.navBar, {
		name = name,
		OnClick = function() EncounterJournal_DisplayInstance(instanceID); end,
	});
end

---------------------------------------------------------------------------
-- opening from outside (micro button, links)
---------------------------------------------------------------------------
function EncounterJournal_OpenJournal(difficultyID, instanceID)
	ShowUIPanel(EncounterJournal);
	if instanceID then
		if difficultyID then
			EJ_SetDifficulty(difficultyID);
		end
		EncounterJournal_DisplayInstance(instanceID);
	end
end
