-- Вкладки "Транспорт" (MountJournal) и "Питомцы" (PetJournal).
-- Раскладка как у ретейлового журнала: слева поиск, счётчик и список (фон/подсветка/выделение -
-- атласы PetList-*), справа большая модель с фоном MountJournal-BG, имя и кнопка "Призвать".
--
-- Данные - компаньоны 3.3.5: GetCompanionInfo(type, i) -> creatureID, name, spellID, icon, isSummoned.
-- В 3.3.5 клиент знает только ИЗУЧЕННЫХ компаньонов, поэтому "не собрано" пока не показывается.
--
-- Избранное хранится в файле персонажа (WriteCustomFile из WotLKExtensions): новые CVar'ы
-- в этом клиенте роняют его при входе в мир.

local ROW_HEIGHT = 46;
local NUM_ROWS = 10;           -- столько строк целиком влезает в левую вставку
local LIST_WIDTH = 300;
local ICON_SIZE = 40;
local ICON_GAP = 4;
local SCROLLBAR_WIDTH = 28;
local ROW_LEFT = 8 + ICON_SIZE + ICON_GAP;                        -- строка начинается правее иконки
local ROW_WIDTH = LIST_WIDTH - ROW_LEFT - SCROLLBAR_WIDTH - 4;    -- и заканчивается до полосы прокрутки

---------------------------------------------------------------------------
-- избранное
---------------------------------------------------------------------------
local favorites;   -- [spellID] = true

local function FavoritesFileName()
	local name = UnitName("player") or "unknown";
	local realm = GetRealmName() or "unknown";
	return ((("Collections335_%s_%s"):format(realm, name)):gsub("[<>:\"/\\|%?%*]", "_"));
end

local function LoadFavorites()
	if favorites then
		return favorites;
	end
	favorites = {};
	if ReadCustomFile and CustomFileExists then
		local okExists, exists = pcall(CustomFileExists, FavoritesFileName());
		if okExists and exists then
			local okRead, content = pcall(ReadCustomFile, FavoritesFileName());
			if okRead and type(content) == "string" then
				for spellID in content:gmatch("(%d+)") do
					favorites[tonumber(spellID)] = true;
				end
			end
		end
	end
	return favorites;
end

local function SaveFavorites()
	if not (favorites and WriteCustomFile) then
		return;
	end
	local ids = {};
	for spellID in pairs(favorites) do
		table.insert(ids, spellID);
	end
	table.sort(ids);
	pcall(WriteCustomFile, FavoritesFileName(), table.concat(ids, ","));
end

---------------------------------------------------------------------------
-- журнал компаньонов
---------------------------------------------------------------------------
local CompanionJournalMixin = {};

-- список с учётом поиска: избранное сверху, дальше по имени
function CompanionJournalMixin:BuildList()
	local list = {};
	local search = self.searchText and self.searchText:lower() or "";
	local favoritesSet = LoadFavorites();

	for index = 1, GetNumCompanions(self.companionType) do
		local creatureID, name, spellID, icon, isSummoned = GetCompanionInfo(self.companionType, index);
		if name and (search == "" or name:lower():find(search, 1, true)) then
			table.insert(list, {
				index = index,
				creatureID = creatureID,
				name = name,
				spellID = spellID,
				icon = icon,
				isSummoned = isSummoned and true or false,
				isFavorite = favoritesSet[spellID] == true,
			});
		end
	end

	table.sort(list, function(a, b)
		if a.isFavorite ~= b.isFavorite then
			return a.isFavorite;
		end
		return a.name < b.name;
	end);

	self.list = list;
	return list;
end

function CompanionJournalMixin:GetSelected()
	if not self.selectedSpellID then
		return nil;
	end
	for _, entry in ipairs(self.list or {}) do
		if entry.spellID == self.selectedSpellID then
			return entry;
		end
	end
	return nil;
end

function CompanionJournalMixin:Select(entry)
	self.selectedSpellID = entry and entry.spellID or nil;
	self:UpdateList();
	self:UpdateDisplay();
end

function CompanionJournalMixin:Refresh()
	self:BuildList();
	if not self:GetSelected() then
		self.selectedSpellID = self.list[1] and self.list[1].spellID or nil;
	end
	self.CountText:SetFormattedText("%s: |cffffffff%d|r", TOTAL or "Всего", GetNumCompanions(self.companionType));
	self:UpdateList();
	self:UpdateDisplay();
end

function CompanionJournalMixin:UpdateList()
	local list = self.list or {};
	local offset = FauxScrollFrame_GetOffset(self.ScrollFrame);
	FauxScrollFrame_Update(self.ScrollFrame, #list, NUM_ROWS, ROW_HEIGHT);

	for rowIndex = 1, NUM_ROWS do
		local row = self.rows[rowIndex];
		local entry = list[offset + rowIndex];
		row.entry = entry;
		if entry then
			row.Icon:SetTexture(entry.icon);
			row.Name:SetText(entry.name);

			row.Name:SetTextColor(1, 1, 1);

			row.Favorite:SetShown(entry.isFavorite);
			row.Summoned:SetShown(entry.isSummoned);
			row.Selected:SetShown(entry.spellID == self.selectedSpellID);
			row:Show();
		else
			row:Hide();
		end
	end
end

function CompanionJournalMixin:UpdateDisplay()
	local entry = self:GetSelected();
	local display = self.Display;

	if not entry then
		display.Model:Hide();
		display.Name:SetText("");
		display.Icon:Hide();
		display.EmptyText:Show();
		self.SummonButton:Disable();
		return;
	end

	display.EmptyText:Hide();
	display.Icon:SetTexture(entry.icon);
	display.Icon:Show();
	display.Name:SetText(entry.name);

	if display.Model.creatureID ~= entry.creatureID then
		display.Model.creatureID = entry.creatureID;
		display.Model:ClearModel();
		display.Model:SetCreature(entry.creatureID);
		display.Model.rotation = 0.61;
		display.Model:SetFacing(display.Model.rotation);
	end
	display.Model:Show();

	self.SummonButton:SetText(entry.isSummoned and (self.dismissText) or (self.summonText));
	-- можно ли призвать здесь (полёт, бой, помещение) решает клиент при CallCompanion
	self.SummonButton:Enable();
end

function CompanionJournalMixin:ToggleSummon(entry)
	entry = entry or self:GetSelected();
	if not entry then
		return;
	end
	if entry.isSummoned then
		DismissCompanion(self.companionType);
	else
		CallCompanion(self.companionType, entry.index);
	end
end

function CompanionJournalMixin:ToggleFavorite(entry)
	if not entry then
		return;
	end
	local set = LoadFavorites();
	set[entry.spellID] = not set[entry.spellID] or nil;
	SaveFavorites();
	self:Refresh();
end

function CompanionJournalMixin:OnEvent(event)
	if self:IsShown() then
		self:Refresh();
	end
end

---------------------------------------------------------------------------
-- строка списка
---------------------------------------------------------------------------
local function SetAtlasOr(texture, atlas, file)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas);
	elseif file then
		texture:SetTexture(file);
	end
end

local function CreateRow(journalFrame, parent, index)
	local row = CreateFrame("Button", nil, parent);
	row:SetWidth(ROW_WIDTH);
	row:SetHeight(ROW_HEIGHT);
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	row:RegisterForDrag("LeftButton");

	local background = row:CreateTexture(nil, "BACKGROUND");
	background:SetAllPoints(row);
	SetAtlasOr(background, "PetList-ButtonBackground", "Interface\\Buttons\\UI-Listbox-Highlight2");
	row.Background = background;

	local highlight = row:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAllPoints(row);
	SetAtlasOr(highlight, "PetList-ButtonHighlight", "Interface\\Buttons\\UI-Listbox-Highlight");
	highlight:SetBlendMode("ADD");

	local selected = row:CreateTexture(nil, "ARTWORK", nil);
	selected:SetAllPoints(row);
	SetAtlasOr(selected, "PetList-ButtonSelect", "Interface\\Buttons\\UI-Listbox-Highlight");
	selected:Hide();
	row.Selected = selected;

	-- иконка слева от строки, как в ретейле; кликается и тащится вместе со строкой
	-- (область нажатия строки расширена влево на иконку)
	local icon = row:CreateTexture(nil, "OVERLAY");
	icon:SetWidth(ICON_SIZE);
	icon:SetHeight(ICON_SIZE);
	icon:SetPoint("RIGHT", row, "LEFT", -ICON_GAP, 0);
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
	row.Icon = icon;

	local iconBorder = row:CreateTexture(nil, "OVERLAY", nil);
	iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame");
	iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1);
	iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1);
	iconBorder:SetVertexColor(0.55, 0.55, 0.55);

	local iconHighlight = row:CreateTexture(nil, "HIGHLIGHT");
	iconHighlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square");
	iconHighlight:SetBlendMode("ADD");
	iconHighlight:SetAllPoints(icon);

	row:SetHitRectInsets(-(ICON_SIZE + ICON_GAP), 0, 0, 0);

	local favorite = row:CreateTexture(nil, "OVERLAY");
	favorite:SetWidth(25);
	favorite:SetHeight(25);
	favorite:SetPoint("TOPLEFT", icon, "TOPLEFT", -6, 6);
	SetAtlasOr(favorite, "collections-icon-favorites", "Interface\\Common\\ReputationStar");
	favorite:Hide();
	row.Favorite = favorite;

	local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	name:SetPoint("LEFT", row, "LEFT", 10, 0);
	name:SetPoint("RIGHT", row, "RIGHT", -10, 0);
	name:SetJustifyH("LEFT");
	name:SetHeight(ROW_HEIGHT - 6);
	row.Name = name;

	local summoned = row:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall");
	summoned:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 4);
	summoned:SetText(journalFrame.summonedText);
	summoned:Hide();
	row.Summoned = summoned;

	row:SetScript("OnClick", function(self, button)
		if not self.entry then
			return;
		end
		if button == "RightButton" then
			journalFrame:ToggleFavorite(self.entry);
		elseif IsModifiedClick("CHATLINK") then
			local link = GetSpellLink(self.entry.spellID);
			if link then
				ChatEdit_InsertLink(link);
			end
		else
			journalFrame:Select(self.entry);
		end
	end);
	row:SetScript("OnDoubleClick", function(self)
		journalFrame:ToggleSummon(self.entry);
	end);
	row:SetScript("OnDragStart", function(self)
		if self.entry then
			PickupCompanion(journalFrame.companionType, self.entry.index);
		end
	end);
	row:SetScript("OnEnter", function(self)
		if not self.entry then
			return;
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("spell:" .. self.entry.spellID);
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine(journalFrame.tooltipHint, 0.5, 0.5, 0.5, true);
		GameTooltip:Show();
	end);
	row:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);

	-- иконка слева от строки, как в ретейле; строка сдвинута вправо под неё
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_LEFT, -((index - 1) * ROW_HEIGHT) - 2);
	return row;
end

---------------------------------------------------------------------------
-- сборка вкладки
---------------------------------------------------------------------------
local function CreateInset(parent)
	local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate");
	return inset;
end

local function CreateCompanionJournal(frameName, companionType, texts)
	local panel = CreateFrame("Frame", frameName, CollectionsJournal);
	Mixin(panel, CompanionJournalMixin);
	panel.companionType = companionType;
	panel.summonText = texts.summon;
	panel.dismissText = texts.dismiss;
	panel.summonedText = texts.summoned;
	panel.tooltipHint = texts.hint;
	panel:SetPoint("TOPLEFT", CollectionsJournal, "TOPLEFT", 0, -60);
	panel:SetPoint("BOTTOMRIGHT", CollectionsJournal, "BOTTOMRIGHT", 0, 0);
	panel:Hide();

	-- левая часть: поиск, счётчик, список
	local leftInset = CreateInset(panel);
	leftInset:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, 0);
	leftInset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 26);
	leftInset:SetWidth(LIST_WIDTH);
	panel.LeftInset = leftInset;

	local search = CreateFrame("EditBox", frameName .. "SearchBox", panel, "SearchBoxTemplate");
	search:SetWidth(145);
	search:SetHeight(20);
	search:SetPoint("TOPLEFT", leftInset, "TOPLEFT", 15, -9);
	search:HookScript("OnTextChanged", function(self)
		local text = self:GetText();
		if text == (SEARCH or "") then
			text = "";
		end
		panel.searchText = text;
		panel:Refresh();
	end);
	panel.SearchBox = search;

	local count = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	count:SetPoint("LEFT", search, "RIGHT", 10, 0);
	panel.CountText = count;

	local scrollFrame = CreateFrame("ScrollFrame", frameName .. "ScrollFrame", leftInset, "FauxScrollFrameTemplate");
	scrollFrame:SetPoint("TOPLEFT", leftInset, "TOPLEFT", 0, -38);
	scrollFrame:SetPoint("BOTTOMRIGHT", leftInset, "BOTTOMRIGHT", -SCROLLBAR_WIDTH, 4);
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
			panel:UpdateList();
		end);
	end);
	panel.ScrollFrame = scrollFrame;

	local listHolder = CreateFrame("Frame", nil, leftInset);
	listHolder:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0);
	listHolder:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0);
	listHolder:EnableMouseWheel(true);
	listHolder:SetScript("OnMouseWheel", function(_, delta)
		local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"];
		scrollBar:SetValue(scrollBar:GetValue() - delta * ROW_HEIGHT * 3);
	end);

	panel.rows = {};
	for index = 1, NUM_ROWS do
		panel.rows[index] = CreateRow(panel, listHolder, index);
	end

	-- правая часть: модель
	local rightInset = CreateInset(panel);
	rightInset:SetPoint("TOPLEFT", leftInset, "TOPRIGHT", 23, 0);
	rightInset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 26);

	local display = CreateFrame("Frame", nil, rightInset);
	display:SetPoint("TOPLEFT", rightInset, "TOPLEFT", 3, -3);
	display:SetPoint("BOTTOMRIGHT", rightInset, "BOTTOMRIGHT", -3, 3);
	panel.Display = display;

	local background = display:CreateTexture(nil, "BACKGROUND");
	background:SetAllPoints(display);
	background:SetTexture(texts.background);
	background:SetTexCoord(0, 0.78, 0, 1);

	local model = CreateFrame("DressUpModel", nil, display);
	model:SetPoint("TOPLEFT", display, "TOPLEFT", 0, -40);
	model:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 0, 40);
	model:EnableMouse(true);
	model:EnableMouseWheel(true);
	model.rotation = 0.61;
	model.zoom = 0;
	model:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			self.dragging = true;
			self.cursorX = GetCursorPosition();
		end
	end);
	model:SetScript("OnMouseUp", function(self)
		self.dragging = nil;
	end);
	model:SetScript("OnUpdate", function(self)
		if self.dragging then
			local x = GetCursorPosition();
			self.rotation = self.rotation + (x - (self.cursorX or x)) * 0.02;
			self.cursorX = x;
			self:SetFacing(self.rotation);
		end
	end);
	model:SetScript("OnMouseWheel", function(self, delta)
		self.zoom = math.max(-0.5, math.min(1.5, self.zoom + delta * 0.1));
		self:SetPosition(self.zoom, 0, 0);
	end);
	display.Model = model;

	local icon = display:CreateTexture(nil, "OVERLAY");
	icon:SetWidth(38);
	icon:SetHeight(38);
	icon:SetPoint("TOPLEFT", display, "TOPLEFT", 12, -10);
	display.Icon = icon;

	local name = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
	name:SetPoint("LEFT", icon, "RIGHT", 10, 0);
	name:SetPoint("RIGHT", display, "RIGHT", -12, 0);
	name:SetJustifyH("LEFT");
	display.Name = name;

	local empty = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
	empty:SetPoint("CENTER");
	empty:SetText(texts.empty);
	empty:Hide();
	display.EmptyText = empty;

	local rotateHint = display:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
	rotateHint:SetPoint("BOTTOM", display, "BOTTOM", 0, 12);
	rotateHint:SetText("Потяните мышью, чтобы повернуть; колесо - приблизить");

	-- кнопка призыва
	local summon = CreateFrame("Button", frameName .. "SummonButton", panel, "MagicButtonTemplate");
	summon:SetWidth(140);
	summon:SetHeight(22);
	summon:SetPoint("BOTTOM", rightInset, "BOTTOM", 0, -24);
	summon:SetText(texts.summon);
	summon:SetScript("OnClick", function()
		panel:ToggleSummon();
	end);
	panel.SummonButton = summon;

	panel:RegisterEvent("COMPANION_LEARNED");
	panel:RegisterEvent("COMPANION_UNLEARNED");
	panel:RegisterEvent("COMPANION_UPDATE");
	panel:SetScript("OnEvent", panel.OnEvent);
	panel:SetScript("OnShow", panel.Refresh);

	return panel;
end

local mountJournal = CreateCompanionJournal("MountJournal", "MOUNT", {
	summon = MOUNT or "Призвать",
	dismiss = BINDING_NAME_DISMOUNT or "Спешиться",
	summoned = "Вы верхом",
	empty = "Нет изученного транспорта",
	hint = "ПКМ - в избранное, двойной щелчок - призвать, перетащите на панель команд.",
	background = "Interface\\PetBattles\\MountJournal-BG",
});

local petJournal = CreateCompanionJournal("PetJournal", "CRITTER", {
	summon = PET_ACTION_SUMMON or "Призвать",
	dismiss = PET_DISMISS or "Отпустить",
	summoned = "Призван",
	empty = "Нет изученных питомцев",
	hint = "ПКМ - в избранное, двойной щелчок - призвать, перетащите на панель команд.",
	background = "Interface\\PetBattles\\MountJournal-BG",
});

CollectionsJournal_RegisterTab(COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS, mountJournal);
CollectionsJournal_RegisterTab(COLLECTIONS_JOURNAL_TAB_INDEX_PETS, petJournal);
CollectionsJournal_SetTab(CollectionsJournal, COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS);
