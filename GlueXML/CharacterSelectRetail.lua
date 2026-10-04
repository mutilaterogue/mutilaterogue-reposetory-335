-- Retail character select (12.x Blizzard_GlueXML CharacterSelect*) on top of the 3.3.5 one: the 3.3.5 logic stays
-- (UpdateCharacterList, CharacterSelect_SelectCharacter, EnterWorld...), only the look changes:
--   the character list on the right as retail cards (realm header, card per character, "create" card),
--   the selected character's name plate over a big "Enter World", rotate buttons under it,
--   the top bar (glues-characterselect-tophud) with Change Realm / AddOns / Back.
-- GlueXML.toc: after CharacterSelect.xml.

CharacterSelectRetail = {};
local RS = CharacterSelectRetail;

local CARD_WIDTH, CARD_HEIGHT, CARD_SPACING = 330, 72, 4;
local PANEL_WIDTH = CARD_WIDTH + 30;

-- GetCharacterInfo gives localized race / class names only: the tokens by name (ruRU male / female, enUS)
local CLASS_TOKENS = {
	["Воин"] = "WARRIOR", ["Паладин"] = "PALADIN", ["Охотник"] = "HUNTER", ["Охотница"] = "HUNTER",
	["Разбойник"] = "ROGUE", ["Разбойница"] = "ROGUE", ["Жрец"] = "PRIEST", ["Жрица"] = "PRIEST",
	["Рыцарь смерти"] = "DEATHKNIGHT", ["Шаман"] = "SHAMAN", ["Шаманка"] = "SHAMAN", ["Маг"] = "MAGE",
	["Чернокнижник"] = "WARLOCK", ["Чернокнижница"] = "WARLOCK", ["Друид"] = "DRUID",
	["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER", ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST",
	["Death Knight"] = "DEATHKNIGHT", ["Shaman"] = "SHAMAN", ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK", ["Druid"] = "DRUID",
};
local CLASS_COLORS = {
	WARRIOR = "C79C6E", PALADIN = "F58CBA", HUNTER = "ABD473", ROGUE = "FFF569", PRIEST = "FFFFFF",
	DEATHKNIGHT = "C41F3B", SHAMAN = "0070DE", MAGE = "69CCF0", WARLOCK = "9482C9", DRUID = "FF7D0A",
};
local HORDE_RACES = {
	["Орк"] = true, ["Нежить"] = true, ["Таурен"] = true, ["Тролль"] = true, ["Эльф крови"] = true, ["Эльфийка крови"] = true,
	["Orc"] = true, ["Undead"] = true, ["Tauren"] = true, ["Troll"] = true, ["Blood Elf"] = true,
};

local function ClassText(class)
	local color = CLASS_COLORS[CLASS_TOKENS[class or ""] or ""];
	return color and ("|cff" .. color .. class .. "|r") or (class or "");
end

local function InfoText(level, class, ghost)
	local text = (LEVEL or "Уровень") .. " " .. (level or 0) .. " " .. ClassText(class);
	if ghost then
		text = text .. " |cff999999(" .. (DEAD or "мертв") .. ")|r";
	end
	return text;
end

-- the login screen widgets lack SetShown
local function Show(region, shown)
	if shown then
		region:Show();
	else
		region:Hide();
	end
end

local function HasAtlas(atlas)
	return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil;
end

local function SetAtlasOr(texture, atlas, r, g, b, a)
	if HasAtlas(atlas) then
		texture:SetAtlas(atlas);
		return true;
	end
	if r then
		texture:SetTexture(r, g, b, a);
	end
	return false;
end

---------------------------------------------------------------------------
-- cards
---------------------------------------------------------------------------
local function CreateCard(parent, index)
	local card = CreateFrame("Button", "CharacterSelectRetailCard" .. index, parent);
	card:SetWidth(CARD_WIDTH);
	card:SetHeight(CARD_HEIGHT);
	card:RegisterForClicks("LeftButtonUp");

	card.Background = card:CreateTexture(nil, "BACKGROUND");
	card.Background:SetAllPoints();
	SetAtlasOr(card.Background, "glues-characterselect-card-singles", 0, 0, 0, 0.6);
	card.Hover = card:CreateTexture(nil, "BORDER");
	card.Hover:SetAllPoints();
	SetAtlasOr(card.Hover, "glues-characterselect-card-singles-hover", 1, 1, 1, 0.08);
	card.Hover:Hide();
	card.Selected = card:CreateTexture(nil, "ARTWORK");
	card.Selected:SetAllPoints();
	SetAtlasOr(card.Selected, "glues-characterselect-card-selected", 1, 0.82, 0, 0.15);
	card.Selected:Hide();

	card.Faction = card:CreateTexture(nil, "OVERLAY");
	card.Faction:SetPoint("RIGHT", -16, 0);
	card.Faction:SetWidth(40);
	card.Faction:SetHeight(40);

	card.Name = card:CreateFontString(nil, "OVERLAY", "GlueFontNormalLarge");
	card.Name:SetPoint("TOPLEFT", 18, -12);
	card.Name:SetPoint("RIGHT", -12, 0);
	card.Name:SetJustifyH("LEFT");
	card.Info = card:CreateFontString(nil, "OVERLAY", "GlueFontHighlightSmall");
	card.Info:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -4);
	card.Info:SetPoint("RIGHT", -12, 0);
	card.Info:SetJustifyH("LEFT");
	card.Zone = card:CreateFontString(nil, "OVERLAY", "GlueFontDisableSmall");
	card.Zone:SetPoint("TOPLEFT", card.Info, "BOTTOMLEFT", 0, -3);
	card.Zone:SetPoint("RIGHT", -12, 0);
	card.Zone:SetJustifyH("LEFT");

	card:SetScript("OnEnter", function(self) self.Hover:Show(); end);
	card:SetScript("OnLeave", function(self) self.Hover:Hide(); end);
	card:SetScript("OnClick", function(self)
		if self.create then
			CharacterSelect_SelectCharacter(CharacterSelect.createIndex);
		elseif self.index ~= CharacterSelect.selectedIndex then
			CharacterSelect_SelectCharacter(self.index);
		end
	end);
	card:SetScript("OnDoubleClick", function(self)
		if not self.create then
			if self.index ~= CharacterSelect.selectedIndex then
				CharacterSelect_SelectCharacter(self.index);
			end
			CharacterSelect_EnterWorld();
		end
	end);
	return card;
end

function RS.UpdateList()
	if not RS.List then
		return;
	end
	local numChars = GetNumCharacters() or 0;
	local shown = 0;
	for i = 1, math.min(numChars, MAX_CHARACTERS_DISPLAYED) do
		local name, race, class, level, zone, sex, ghost = GetCharacterInfo(i);
		local card = RS.cards[i] or CreateCard(RS.List, i);
		RS.cards[i] = card;
		card.index, card.create = i, nil;
		SetAtlasOr(card.Background, "glues-characterselect-card-singles", 0, 0, 0, 0.6);
		card.Name:SetText(name or "");
		card.Name:SetTextColor(1, 0.82, 0);
		local info = ghost and CHARACTER_SELECT_INFO_GHOST or CHARACTER_SELECT_INFO;
		card.Info:SetText(InfoText(level, class, ghost));
		card.Zone:SetText(zone or "");
		card.horde = HORDE_RACES[race or ""] or false;
		card:ClearAllPoints();
		card:SetPoint("TOP", RS.List.Header, "BOTTOM", 0, -6 - (i - 1) * (CARD_HEIGHT + CARD_SPACING));
		card:Show();
		shown = i;
	end

	local nextIndex = shown + 1;
	-- "Create Character" under the list (3.3.5: CharacterSelect.createIndex, set by UpdateCharacterList)
	if (CharacterSelect.createIndex or 0) > 0 and IsConnectedToServer() then
		RS.CreateButton:Enable();
	else
		RS.CreateButton:Disable();
	end
	for i = nextIndex, #RS.cards do
		RS.cards[i]:Hide();
	end

	RS.List.Header.Text:SetText(GetServerName and GetServerName() or "");
	RS.UpdateSelection();
end

function RS.UpdateSelection()
	if not RS.List then
		return;
	end
	local selected = CharacterSelect.selectedIndex or 0;
	for _, card in ipairs(RS.cards) do
		local isSelected = card.index == selected;
		Show(card.Selected, isSelected);
		local faction = card.horde and "horde" or "alliance";
		SetAtlasOr(card.Faction, "glues-characterselect-icon-faction-" .. faction .. (isSelected and "-selected" or ""));
	end
	-- the name plate over Enter World
	local name, race, class, level, zone, sex, ghost = GetCharacterInfo(selected);
	if name and selected > 0 then
		RS.NamePlate.Name:SetText(name);
		RS.NamePlate.Context:SetText("");
		RS.NamePlate:Show();
	else
		RS.NamePlate:Hide();
	end
end

---------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------
local function HideRegion(region)
	if region then
		region:SetAlpha(0);
		if region.EnableMouse then
			region:EnableMouse(false);
		end
	end
end

function RS.Setup()
	if RS.List then
		return;
	end
	local ui = CharacterSelectUI;

	-- the 3.3.5 list: invisible (it still keeps the indices UpdateCharacterList works with)
	if CharacterSelectCharacterFrame.SetBackdrop then
		CharacterSelectCharacterFrame:SetBackdrop(nil);
	end
	for i = 1, MAX_CHARACTERS_DISPLAYED do
		HideRegion(_G["CharSelectCharacterButton" .. i]);
		HideRegion(_G["CharSelectCharacterCustomize" .. i]);
		HideRegion(_G["CharSelectRaceChange" .. i]);
		HideRegion(_G["CharSelectFactionChange" .. i]);
	end
	HideRegion(CharSelectCreateCharacterButton);
	HideRegion(CharSelectRealmName);
	HideRegion(CharSelectCharacterName);
	if CharacterSelectLogo then
		CharacterSelectLogo:Hide();
	end

	-- the list (retail CharacterSelectListTemplate: right side)
	-- one dark panel: the realm, the cards, the buttons under them (retail CharacterSelectListTemplate)
	local list = CreateFrame("Frame", "CharacterSelectRetailList", ui);
	list:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -14, -80);
	list:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", -14, 60);
	list:SetWidth(PANEL_WIDTH);
	list.Background = list:CreateTexture(nil, "BACKGROUND");
	list.Background:SetAllPoints();
	SetAtlasOr(list.Background, "glues-characterselect-card-all-bg", 0, 0, 0, 0.75);
	local header = CreateFrame("Frame", nil, list);
	header:SetPoint("TOP", 0, -14);
	header:SetWidth(CARD_WIDTH);
	header:SetHeight(34);
	header.Background = header:CreateTexture(nil, "BACKGROUND");
	header.Background:SetAllPoints();
	SetAtlasOr(header.Background, "glues-characterselect-listrealm-bg", 0, 0, 0, 0.6);
	header.Text = header:CreateFontString(nil, "OVERLAY", "GlueFontNormal");
	header.Text:SetPoint("CENTER");
	list.Header = header;
	RS.List = list;
	RS.cards = {};

	-- Create Character + Delete under the cards (retail: the red button and the trash icon)
	local create = CreateFrame("Button", "CharacterSelectRetailCreateButton", list, "GlueButtonTemplate");
	create:SetWidth(210);
	create:SetHeight(42);
	create:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 16, 14);
	create:SetText(CREATE_NEW_CHARACTER or "Создать персонажа");
	create:SetScript("OnClick", function()
		if (CharacterSelect.createIndex or 0) > 0 then
			CharacterSelect_SelectCharacter(CharacterSelect.createIndex);
		end
	end);
	RS.CreateButton = create;
	CharacterSelectDeleteButton:SetParent(list);
	CharacterSelectDeleteButton:ClearAllPoints();
	CharacterSelectDeleteButton:SetPoint("LEFT", create, "RIGHT", 6, 0);
	CharacterSelectDeleteButton:SetWidth(PANEL_WIDTH - 210 - 16 - 6 - 16);
	CharacterSelectDeleteButton:SetHeight(42);
	CharacterSelectDeleteButton:SetText(DELETE or "Удалить");

	-- the name over Enter World (retail CharacterSelectUI SelectedBackdrop / Name)
	local plate = CreateFrame("Frame", nil, ui);
	plate:SetWidth(420);
	plate:SetHeight(50);
	plate:SetPoint("BOTTOM", CharSelectEnterWorldButton, "TOP", 0, 4);
	plate.Background = plate:CreateTexture(nil, "BACKGROUND");
	plate.Background:SetAllPoints();
	SetAtlasOr(plate.Background, "glues-characterselect-namebg");
	plate.Name = plate:CreateFontString(nil, "OVERLAY", "GlueFontNormalHuge");
	plate.Name:SetPoint("BOTTOM", 0, 10);
	plate.Context = plate:CreateFontString(nil, "OVERLAY", "GlueFontHighlight");
	plate.Context:SetPoint("TOP", plate, "BOTTOM", 0, 0);
	RS.NamePlate = plate;

	-- Enter World: bottom center; rotate buttons over the model, at its feet (retail)
	CharSelectEnterWorldButton:ClearAllPoints();
	CharSelectEnterWorldButton:SetPoint("BOTTOM", ui, "BOTTOM", 0, 40);
	CharSelectEnterWorldButton:SetWidth(270);
	CharSelectEnterWorldButton:SetHeight(58);
	if CharacterSelectRotateLeft and CharacterSelectRotateRight then
		CharacterSelectRotateLeft:ClearAllPoints();
		CharacterSelectRotateLeft:SetPoint("BOTTOMRIGHT", plate, "TOP", -2, 150);
		CharacterSelectRotateRight:ClearAllPoints();
		CharacterSelectRotateRight:SetPoint("BOTTOMLEFT", plate, "TOP", 2, 150);
	end

	-- Back: bottom left (retail)
	CharacterSelectBackButton:SetParent(ui);
	CharacterSelectBackButton:ClearAllPoints();
	CharacterSelectBackButton:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", 50, 40);
	CharacterSelectBackButton:SetWidth(240);
	CharacterSelectBackButton:SetHeight(52);
	CharacterSelectBackButton:SetText("<  " .. (BACK or "Назад"));

	-- the top bar (retail CharacterSelectNavBar): text items between dividers, a gold line under them
	local bar = CreateFrame("Frame", "CharacterSelectRetailNavBar", ui);
	bar:SetPoint("TOP", ui, "TOP", 0, 0);
	bar:SetWidth(520);
	bar:SetHeight(56);
	bar.Background = bar:CreateTexture(nil, "BACKGROUND");
	bar.Background:SetAllPoints();
	SetAtlasOr(bar.Background, "glues-characterselect-tophud-middle-bg", 0, 0, 0, 0.6);
	local items = {};
	for _, button in ipairs({ CharacterSelectAddonsButton, CharSelectChangeRealmButton }) do
		if button then
			table.insert(items, button);
		end
	end
	local width = bar:GetWidth() / math.max(1, #items);
	for i, button in ipairs(items) do
		button:SetParent(bar);
		button:ClearAllPoints();
		button:SetPoint("CENTER", bar, "LEFT", (i - 0.5) * width, 4);
		button:SetWidth(width - 20);
		button:SetHeight(40);
		-- text only: the 3.3.5 button art off
		for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture() }) do
			texture:SetAlpha(0);
		end
		local highlight = button:GetHighlightTexture();
		if highlight then
			highlight:SetAlpha(0.25);
		end
		local text = button:GetFontString();
		if text then
			text:SetText(string.upper(text:GetText() or ""));
		end
		if i < #items then
			local divider = bar:CreateTexture(nil, "ARTWORK");
			divider:SetPoint("CENTER", bar, "LEFT", i * width, 4);
			divider:SetWidth(2);
			divider:SetHeight(30);
			SetAtlasOr(divider, "glues-characterselect-tophud-bg-divider", 1, 1, 1, 0.2);
		end
	end
	RS.NavBar = bar;
end

---------------------------------------------------------------------------
-- hooks into the 3.3.5 flow
---------------------------------------------------------------------------
-- wrapped by hand: the login screen may have no hooksecurefunc; the XML calls these by their global names
local function After(name, func)
	local original = _G[name];
	_G[name] = function(...)
		local a, b, c = original(...);
		func(...);
		return a, b, c;
	end
end

After("CharacterSelect_OnShow", function()
	RS.Setup();
	RS.UpdateList();
end);
After("UpdateCharacterList", function()
	RS.Setup();
	RS.UpdateList();
end);
After("UpdateCharacterSelection", function()
	RS.UpdateSelection();
end);
