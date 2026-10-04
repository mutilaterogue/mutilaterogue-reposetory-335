-- Retail character select (12.x Blizzard_GlueXML CharacterSelect*) on top of the 3.3.5 one: the 3.3.5 logic stays
-- (UpdateCharacterList, CharacterSelect_SelectCharacter, EnterWorld...), only the look changes:
--   the character list on the right as retail cards (realm header, card per character, "create" card),
--   the selected character's name plate over a big "Enter World", rotate buttons under it,
--   the top bar (glues-characterselect-tophud) with Change Realm / AddOns / Back.
-- GlueXML.toc: after CharacterSelect.xml.

CharacterSelectRetail = {};
local RS = CharacterSelectRetail;

local CARD_WIDTH, CARD_HEIGHT, CARD_SPACING = 300, 72, 4;

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
		card.Info:SetText(string.format(info or "%d %s", level or 0, class or ""));
		card.Zone:SetText(zone or "");
		card:ClearAllPoints();
		card:SetPoint("TOP", RS.List.Header, "BOTTOM", 0, -6 - (i - 1) * (CARD_HEIGHT + CARD_SPACING));
		card:Show();
		shown = i;
	end

	-- "create a character" card (3.3.5: CharacterSelect.createIndex, set by UpdateCharacterList)
	local nextIndex = shown + 1;
	if (CharacterSelect.createIndex or 0) > 0 and IsConnectedToServer() and nextIndex <= MAX_CHARACTERS_DISPLAYED then
		local card = RS.cards[nextIndex] or CreateCard(RS.List, nextIndex);
		RS.cards[nextIndex] = card;
		card.index, card.create = nil, true;
		SetAtlasOr(card.Background, "glues-characterselect-card-empty", 0, 0, 0, 0.4);
		card.Name:SetText("+  " .. (CREATE_NEW_CHARACTER or "Создать персонажа"));
		card.Name:SetTextColor(1, 1, 1);
		card.Info:SetText("");
		card.Zone:SetText("");
		card.Selected:Hide();
		card:ClearAllPoints();
		card:SetPoint("TOP", RS.List.Header, "BOTTOM", 0, -6 - (nextIndex - 1) * (CARD_HEIGHT + CARD_SPACING));
		card:Show();
		nextIndex = nextIndex + 1;
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
		Show(card.Selected, not card.create and card.index == selected);
	end
	-- the name plate over Enter World
	local name, race, class, level, zone, sex, ghost = GetCharacterInfo(selected);
	if name and selected > 0 then
		RS.NamePlate.Name:SetText(name);
		local info = ghost and CHARACTER_SELECT_INFO_GHOST or CHARACTER_SELECT_INFO;
		RS.NamePlate.Context:SetText(string.format(info or "%d %s", level or 0, class or "") .. ((zone and zone ~= "") and ("  |cff999999" .. zone .. "|r") or ""));
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
	local list = CreateFrame("Frame", "CharacterSelectRetailList", ui);
	list:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -24, -80);
	list:SetWidth(CARD_WIDTH + 20);
	list:SetHeight(MAX_CHARACTERS_DISPLAYED * (CARD_HEIGHT + CARD_SPACING) + 60);
	local header = CreateFrame("Frame", nil, list);
	header:SetPoint("TOP");
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

	-- the name plate (retail CharacterSelectUI SelectedBackdrop / Name / CharacterContext)
	local plate = CreateFrame("Frame", nil, ui);
	plate:SetWidth(420);
	plate:SetHeight(65);
	plate:SetPoint("BOTTOM", CharSelectEnterWorldButton, "TOP", 0, 10);
	plate.Background = plate:CreateTexture(nil, "BACKGROUND");
	plate.Background:SetAllPoints();
	SetAtlasOr(plate.Background, "glues-characterselect-namebg");
	plate.Context = plate:CreateFontString(nil, "OVERLAY", "GlueFontHighlight");
	plate.Context:SetPoint("BOTTOM", 0, 12);
	plate.Name = plate:CreateFontString(nil, "OVERLAY", "GlueFontNormalLarge");
	plate.Name:SetPoint("BOTTOM", plate.Context, "TOP", 0, 5);
	RS.NamePlate = plate;

	-- Enter World: big, bottom center; rotate buttons under it
	CharSelectEnterWorldButton:ClearAllPoints();
	CharSelectEnterWorldButton:SetPoint("BOTTOM", ui, "BOTTOM", 0, 45);
	CharSelectEnterWorldButton:SetWidth(250);
	CharSelectEnterWorldButton:SetHeight(64);
	if CharacterSelectRotateLeft and CharacterSelectRotateRight then
		CharacterSelectRotateLeft:ClearAllPoints();
		CharacterSelectRotateLeft:SetPoint("TOPRIGHT", CharSelectEnterWorldButton, "BOTTOM", -2, 6);
		CharacterSelectRotateRight:ClearAllPoints();
		CharacterSelectRotateRight:SetPoint("TOPLEFT", CharSelectEnterWorldButton, "BOTTOM", 2, 6);
	end

	-- delete: under the list, as the retail tool buttons
	CharacterSelectDeleteButton:ClearAllPoints();
	CharacterSelectDeleteButton:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", -24, 20);

	-- the top bar (retail CharacterSelectNavBar): change realm, addons, back
	local bar = CreateFrame("Frame", "CharacterSelectRetailNavBar", ui);
	bar:SetPoint("TOP", ui, "TOP", 0, 0);
	bar:SetWidth(640);
	bar:SetHeight(52);
	bar.Background = bar:CreateTexture(nil, "BACKGROUND");
	bar.Background:SetAllPoints();
	SetAtlasOr(bar.Background, "glues-characterselect-tophud-middle-bg", 0, 0, 0, 0.7);
	local buttons = { CharSelectChangeRealmButton, CharacterSelectAddonsButton, CharacterSelectBackButton };
	local shownButtons = {};
	for _, button in ipairs(buttons) do
		if button then
			button:SetParent(bar);
			table.insert(shownButtons, button);
		end
	end
	local width = 190;
	for i, button in ipairs(shownButtons) do
		button:ClearAllPoints();
		button:SetPoint("CENTER", bar, "CENTER", (i - (#shownButtons + 1) / 2) * width, 2);
		button:SetWidth(width - 14);
		if i < #shownButtons then
			local divider = bar:CreateTexture(nil, "ARTWORK");
			divider:SetPoint("CENTER", bar, "CENTER", (i - #shownButtons / 2) * width, 2);
			divider:SetWidth(2);
			divider:SetHeight(32);
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
