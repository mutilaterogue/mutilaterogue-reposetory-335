-- Общая логика вкладок "Транспорт" и "Питомцы".
-- Данные - компаньоны 3.3.5: GetCompanionInfo(type, i) -> creatureID, name, spellID, icon, isSummoned.
-- Клиент 3.3.5 знает только изученных компаньонов.
-- Избранное - файл персонажа через WriteCustomFile (новые CVar'ы этот клиент роняют).

local NUM_ROWS = 10;
local ROW_HEIGHT = 46;
local ROW_LEFT = 50;     -- строка правее иконки (иконка - слева от строки, как в ретейле)

---------------------------------------------------------------------------
-- избранное (общее для маунтов и питомцев: ключ - spellID)
---------------------------------------------------------------------------
local favorites;

local function FavoritesFileName()
	return ((("Collections335_%s_%s"):format(GetRealmName() or "?", UnitName("player") or "?")):gsub("[<>:\"/\\|%?%*]", "_"));
end

local function LoadFavorites()
	if favorites then
		return favorites;
	end
	favorites = {};
	if ReadCustomFile and CustomFileExists then
		local okExists, exists = pcall(CustomFileExists, FavoritesFileName());
		local okRead, content = false, nil;
		if okExists and exists then
			okRead, content = pcall(ReadCustomFile, FavoritesFileName());
		end
		if okRead and type(content) == "string" then
			for spellID in content:gmatch("(%d+)") do
				favorites[tonumber(spellID)] = true;
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
-- описание заклинания (в 3.3.5 у маунтов/питомцев нет "источника" и "лора" -
-- берём текст из подсказки заклинания)
---------------------------------------------------------------------------
local scanTooltip = CreateFrame("GameTooltip", "CollectionsScanTooltip", UIParent, "GameTooltipTemplate");
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE");

local function GetSpellDescription(spellID)
	scanTooltip:SetOwner(UIParent, "ANCHOR_NONE");
	scanTooltip:ClearLines();
	scanTooltip:SetHyperlink("spell:" .. spellID);
	local lines = {};
	for i = 2, scanTooltip:NumLines() do
		local left = _G["CollectionsScanTooltipTextLeft" .. i];
		local text = left and left:GetText();
		-- строки вида "Spell ID: ..." добавляет патч подсказок (TOOLTIPID) - в описании они лишние
		if text and text ~= "" and not text:find("ID:", 1, true) then
			table.insert(lines, text);
		end
	end
	scanTooltip:Hide();
	return table.concat(lines, "\n");
end

---------------------------------------------------------------------------
-- Модели неполученных.
-- SetCreature(entry) в 3.3.5 рисует существо, только если оно уже есть в кэше клиента
-- (Cache\WDB\ruRU\creaturecache.wdb), и САМ его у сервера не запрашивает (проверено в игре).
-- Поэтому клиент просит сервер прислать данные существ: аддон-сообщение самому себе
-- с префиксом CJCACHE и списком entry через запятую. Серверный скрипт
-- (server\collections_creature_cache.cpp) отвечает на каждый entry обычным
-- SMSG_CREATURE_QUERY_RESPONSE - клиент кладёт его в кэш навсегда.
-- Выбранную модель повторно ставим несколько секунд, пока ответ не придёт.
---------------------------------------------------------------------------
local CACHE_PREFIX = "CJCACHE";
local MAX_MESSAGE_LENGTH = 240;
local SEND_INTERVAL = 0.2;

-- Существа, которые уже запрашивались у сервера В ЭТОЙ СЕССИИ.
-- (Сохранять список между сессиями нельзя: если ответ тогда не пришёл - сервер не был готов,
--  кэш клиента удалён - существо навсегда осталось бы без модели.)
local requested = {};
local sendQueue = {};

local function LoadRequested()
	return requested;
end

local function SaveRequested()
end

local sender = CreateFrame("Frame");
sender.elapsed = 0;
sender:Hide();
sender:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = self.elapsed + elapsed;
	if self.elapsed < SEND_INTERVAL then
		return;
	end
	self.elapsed = 0;

	local ids = {};
	local length = 0;
	while #sendQueue > 0 do
		local text = tostring(sendQueue[#sendQueue]);
		if length + #text + 1 > MAX_MESSAGE_LENGTH then
			break;
		end
		table.remove(sendQueue);
		table.insert(ids, text);
		length = length + #text + 1;
	end
	if #ids > 0 then
		if Comm_Send and CMSG then
			CMSG.REQUEST_CREATURE_CACHE = CMSG.REQUEST_CREATURE_CACHE or 2;
			Comm_Send(CMSG.REQUEST_CREATURE_CACHE, table.concat(ids, ","));
		else
			SendAddonMessage(CACHE_PREFIX, table.concat(ids, ","), "WHISPER", UnitName("player"));
		end
	end
	if #sendQueue == 0 then
		self:Hide();
		SaveRequested();
	end
end);

-- true, если существо только что поставлено в очередь (его ещё нет в кэше клиента)
function CollectionsUtil_RequestCreatures(creatureIDs)
	local set = LoadRequested();
	local queued = false;
	for _, creatureID in ipairs(creatureIDs) do
		if creatureID and creatureID > 0 and not set[creatureID] then
			set[creatureID] = true;
			queued = true;
			table.insert(sendQueue, creatureID);
		end
	end
	if #sendQueue > 0 then
		sender:Show();
	end
	return queued;
end

function CollectionsUtil_PrefetchCreatures(database)
	local ids = {};
	for _, data in pairs(database) do
		table.insert(ids, data.creatureID);
	end
	CollectionsUtil_RequestCreatures(ids);
end

-- Модель ставится один раз. Только если существо запрошено прямо сейчас (его не было
-- в кэше), модель ставится ещё раз - через секунду, когда ответ сервера уже пришёл.
local REAPPLY_DELAY = 1;

function CollectionsUtil_SetCreatureWhenCached(model, creatureID)
	model:SetCreature(creatureID);
	model.reapplyCreatureID = nil;

	local justRequested = CollectionsUtil_RequestCreatures({ creatureID });
	local pending = justRequested or (sendQueue[1] ~= nil and tContains and tContains(sendQueue, creatureID));
	if not pending then
		return;
	end

	model.reapplyCreatureID = creatureID;
	model.reapplyElapsed = 0;
	if not model.reapplyHooked then
		model.reapplyHooked = true;
		model:HookScript("OnUpdate", function(self, elapsed)
			if not self.reapplyCreatureID then
				return;
			end
			self.reapplyElapsed = self.reapplyElapsed + elapsed;
			if self.reapplyElapsed >= REAPPLY_DELAY then
				self:SetCreature(self.reapplyCreatureID);
				self:SetFacing(self.rotation or 0);
				self.reapplyCreatureID = nil;
			end
		end);
	end
end

---------------------------------------------------------------------------
CollectionsCompanionJournalMixin = {};

-- вызывается из OnLoad экземпляра (Mounts\, Pets\)
function CollectionsCompanionJournalMixin:Init(companionType, texts)
	self.companionType = companionType;
	self.texts = texts;
	self.filterConfig = { showTypes = texts.showTypes };

	self.Count.Label:SetText(texts.total);
	self.Display.EmptyText:SetText(texts.empty);
	self.Display.Background:SetTexture("Interface\\PetBattles\\MountJournal-BG");
	self.Display.Background:SetTexCoord(0, 0.78125, 0, 1);

	-- строки списка из шаблона CollectionsCompanionListButtonTemplate
	self.rows = {};
	for index = 1, NUM_ROWS do
		-- у строки есть имя: регионы шаблона привязаны друг к другу через $parent-имена
		local row = CreateFrame("Button", self:GetName() .. "Row" .. index, self.ListFrame, "CollectionsCompanionListButtonTemplate");
		row:SetPoint("TOPLEFT", self.ListFrame, "TOPLEFT", ROW_LEFT, -((index - 1) * ROW_HEIGHT) - 2);
		row:SetWidth(self.ListFrame:GetWidth() > 0 and (self.ListFrame:GetWidth() - ROW_LEFT - 2) or 180);
		row.summoned:SetText(texts.summoned);
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp");
		row:RegisterForDrag("LeftButton");
		row:SetScript("OnClick", function(button, mouseButton) self:OnRowClick(button, mouseButton); end);
		row:SetScript("OnDoubleClick", function(button) self:ToggleSummon(button.entry); end);
		row:SetScript("OnDragStart", function(button)
			if button.entry and button.entry.index then
				PickupCompanion(self.companionType, button.entry.index);
			end
		end);
		row:SetScript("OnEnter", function(button) self:OnRowEnter(button); end);
		row:SetScript("OnLeave", GameTooltip_Hide);
		self.rows[index] = row;
	end

	-- прокрутка
	self.ListScrollFrame:SetScript("OnVerticalScroll", function(scrollFrame, offset)
		FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, ROW_HEIGHT, function() self:UpdateList(); end);
	end);
	self.ListFrame:SetScript("OnMouseWheel", function(_, delta)
		local scrollBar = _G[self.ListScrollFrame:GetName() .. "ScrollBar"];
		scrollBar:SetValue(scrollBar:GetValue() - delta * ROW_HEIGHT * 3);
	end);
	self.ListFrame:SetScript("OnSizeChanged", function(frame, width)
		for _, row in ipairs(self.rows) do
			row:SetWidth(width - ROW_LEFT - 2);
		end
	end);

	-- поиск
	self.SearchBox:HookScript("OnTextChanged", function(searchBox)
		local text = searchBox:GetText() or "";
		if text == (SEARCH or "") then
			text = "";
		end
		self.searchText = text:lower();
		self:Refresh();
	end);

	-- фильтр (как в ретейле: полученные / не полученные / невозможно использовать, тип, источники)
	self:ResetFilters();
	local filter = self.FilterDropdown;
	filter:SetIsDefaultCallback(function() return self:IsUsingDefaultFilters(); end);
	filter:SetDefaultCallback(function() self:ResetFilters(); end);
	filter:SetUpdateCallback(function() self:Refresh(); end);
	filter:SetupMenu(function(dropdown, rootDescription)
		self:BuildFilterMenu(rootDescription);
	end);

	-- модель: поворот мышью, колесо - приближение
	local model = self.Display.Model;
	model.rotation, model.zoom = 0.61, 0;
	model:SetScript("OnMouseDown", function(m, button)
		if button == "LeftButton" then
			m.dragging, m.cursorX = true, GetCursorPosition();
		end
	end);
	model:SetScript("OnMouseUp", function(m) m.dragging = nil; end);
	model:SetScript("OnUpdate", function(m)
		if m.dragging then
			local x = GetCursorPosition();
			m.rotation = m.rotation + (x - (m.cursorX or x)) * 0.02;
			m.cursorX = x;
			m:SetFacing(m.rotation);
		end
	end);
	model:SetScript("OnMouseWheel", function(m, delta)
		m.zoom = math.max(-0.5, math.min(1.5, m.zoom + delta * 0.1));
		m:SetPosition(m.zoom, 0, 0);
	end);

	self.SummonButton:SetScript("OnClick", function() self:ToggleSummon(); end);
	self:RegisterEvent("COMPANION_LEARNED");
	self:RegisterEvent("COMPANION_UNLEARNED");
	self:RegisterEvent("COMPANION_UPDATE");
end

function CollectionsCompanionJournalMixin:OnEvent()
	if self:IsShown() then
		self:Refresh();
	end
end

---------------------------------------------------------------------------
-- данные
---------------------------------------------------------------------------
-- База всей коллекции (генерируется из DBC, см. tools\generate_collections_data.py):
-- COLLECTIONS_COMPANION_DATA.MOUNT / .CRITTER = { [spellID] = { creatureID, flags, faction, source } }
-- Без базы в списке только изученные (их клиент 3.3.5 знает сам).
function CollectionsCompanionJournalMixin:GetDatabase()
	return COLLECTIONS_COMPANION_DATA and COLLECTIONS_COMPANION_DATA[self.companionType] or {};
end

local PLAYER_FACTION_INDEX = { Horde = 0, Alliance = 1 };

function CollectionsCompanionJournalMixin:BuildList()
	local list = {};
	local favoritesSet = LoadFavorites();
	local database = self:GetDatabase();
	local playerFaction = PLAYER_FACTION_INDEX[UnitFactionGroup("player") or ""];
	local seen = {};

	local function AddEntry(entry)
		local data = database[entry.spellID];
		if data then
			if data.hidden and not entry.isCollected then
				return;
			end
			entry.flags = data.flags or 0;
			entry.source = data.source;
			entry.sourceText = data.sourceText;
			entry.lore = data.lore;
			entry.faction = data.faction;
			entry.isUnusable = (data.faction ~= nil and playerFaction ~= nil and data.faction ~= playerFaction)
				or (data.isUsableFunc ~= nil and not data.isUsableFunc());
			entry.creatureID = entry.creatureID or data.creatureID;
		else
			entry.flags = 0;
		end
		if self:PassesFilters(entry) then
			table.insert(list, entry);
		end
	end

	-- изученные
	for index = 1, GetNumCompanions(self.companionType) do
		local creatureID, name, spellID, icon, isSummoned = GetCompanionInfo(self.companionType, index);
		if name then
			seen[spellID] = true;
			AddEntry({
				index = index, creatureID = creatureID, name = name, spellID = spellID, icon = icon,
				isCollected = true, isSummoned = isSummoned and true or false,
				isFavorite = favoritesSet[spellID] == true,
			});
		end
	end

	-- не изученные - из базы
	for spellID, data in pairs(database) do
		if not seen[spellID] then
			local name, _, icon = GetSpellInfo(spellID);
			name = name or data.name;
			if name then
				AddEntry({
					creatureID = data.creatureID, name = name, spellID = spellID, icon = icon,
					isCollected = false, isSummoned = false, isFavorite = false,
				});
			end
		end
	end

	-- избранное, затем полученные, затем по имени (как в ретейле)
	table.sort(list, function(a, b)
		if a.isFavorite ~= b.isFavorite then
			return a.isFavorite;
		end
		if a.isCollected ~= b.isCollected then
			return a.isCollected;
		end
		return a.name < b.name;
	end);
	self.list = list;
end

---------------------------------------------------------------------------
-- фильтры
---------------------------------------------------------------------------
-- источники - в порядке ретейлового меню
COLLECTIONS_SOURCE_NAMES = {
	"Добыча", "Задание", "Торговец", "Профессия", "Питомец в дикой природе", "Достижение",
	"Игровое событие", "Промоакция", "Коллекционная карточная игра", "Внутриигровой магазин",
	"Находка", "Торговая лавка",
};
local PET_ONLY_SOURCES = { [5] = true };

-- тип транспорта по флагам (Enum.MountTypeFlag ретейла)
local MOUNT_TYPES = {
	{ key = "ground", label = "Наземный транспорт" },
	{ key = "flying", label = "Летающий транспорт", flag = 1 },
	{ key = "aquatic", label = "Водный транспорт", flag = 2, hidden = true },
	{ key = "rideAlong", label = "Совместная поездка", flag = 8 },
};

local function HasFlag(flags, flag)
	return flag and (math.floor((flags or 0) / flag) % 2) == 1;
end

local function GetMountTypeKey(flags)
	for index = #MOUNT_TYPES, 2, -1 do
		if HasFlag(flags, MOUNT_TYPES[index].flag) then
			return MOUNT_TYPES[index].key;
		end
	end
	return "ground";
end

function CollectionsCompanionJournalMixin:ResetFilters()
	self.filters = { collected = true, notCollected = true, unusable = true, favoritesOnly = false, types = {}, sources = {},
		factions = { horde = true, alliance = true, neutral = true } };
	for _, info in ipairs(MOUNT_TYPES) do
		self.filters.types[info.key] = true;
	end
	for index in ipairs(COLLECTIONS_SOURCE_NAMES) do
		self.filters.sources[index] = true;
	end
end

function CollectionsCompanionJournalMixin:IsUsingDefaultFilters()
	local filters = self.filters;
	if not (filters.collected and filters.notCollected and filters.unusable) or filters.favoritesOnly then
		return false;
	end
	for _, value in pairs(filters.types) do
		if not value then return false; end
	end
	for _, value in pairs(filters.factions) do
		if not value then return false; end
	end
	for _, value in pairs(filters.sources) do
		if not value then return false; end
	end
	return true;
end

function CollectionsCompanionJournalMixin:PassesFilters(entry)
	local filters = self.filters;
	local search = self.searchText or "";

	if search ~= "" and not entry.name:lower():find(search, 1, true) then
		return false;
	end
	if entry.isCollected and not filters.collected then
		return false;
	end
	if not entry.isCollected and not filters.notCollected then
		return false;
	end
	if entry.isUnusable and not filters.unusable then
		return false;
	end
	if filters.favoritesOnly and not entry.isFavorite then
		return false;
	end
	if self.filterConfig.showTypes and not filters.types[GetMountTypeKey(entry.flags)] then
		return false;
	end
	if self.filterConfig.showTypes then
		local factionKey = entry.faction == 0 and "horde" or entry.faction == 1 and "alliance" or "neutral";
		if not filters.factions[factionKey] then
			return false;
		end
	end
	-- у записей без известного источника фильтр по источнику не применяется
	if entry.source and filters.sources[entry.source] == false then
		return false;
	end
	return true;
end

function CollectionsCompanionJournalMixin:BuildFilterMenu(rootDescription)
	local filters = self.filters;
	local function Toggle(key)
		return function()
			filters[key] = not filters[key];
			self.FilterDropdown:ValidateResetState();
			self:Refresh();
		end
	end
	local function Getter(key)
		return function() return filters[key]; end
	end

	rootDescription:CreateCheckbox(COLLECTED or "Полученные", Getter("collected"), Toggle("collected"));
	rootDescription:CreateCheckbox("Не полученные", Getter("notCollected"), Toggle("notCollected"));
	rootDescription:CreateCheckbox("Только избранное", Getter("favoritesOnly"), Toggle("favoritesOnly"));

	if self.filterConfig.showTypes then
		rootDescription:CreateTitle(TYPE or "Тип");
		for _, info in ipairs(MOUNT_TYPES) do
			if not info.hidden then
			rootDescription:CreateCheckbox(info.label, function()
				return filters.types[info.key];
			end, function()
				filters.types[info.key] = not filters.types[info.key];
				self.FilterDropdown:ValidateResetState();
				self:Refresh();
			end);
			end
		end
	end

	-- фракция (только у транспорта: у питомцев в базе фракций нет)
	if self.filterConfig.showTypes then
		rootDescription:CreateTitle(FACTION or "Фракция");
		for _, info in ipairs({
			{ "alliance", FACTION_ALLIANCE or "Альянс" },
			{ "horde", FACTION_HORDE or "Орда" },
			{ "neutral", "Обе фракции" },
		}) do
			local key = info[1];
			rootDescription:CreateCheckbox(info[2], function()
				return filters.factions[key];
			end, function()
				filters.factions[key] = not filters.factions[key];
				self.FilterDropdown:ValidateResetState();
				self:Refresh();
			end);
		end
	end

	local sourceMenu = rootDescription.CreateSubmenu and rootDescription:CreateSubmenu("Источники") or rootDescription:CreateButton("Источники");
	local function SetAllSources(value)
		for index in ipairs(COLLECTIONS_SOURCE_NAMES) do
			filters.sources[index] = value;
		end
		self.FilterDropdown:ValidateResetState();
		self:Refresh();
		return MenuResponse and MenuResponse.Refresh;
	end
	sourceMenu:CreateButton("Выделить все", function() return SetAllSources(true); end);
	sourceMenu:CreateButton("Снять выделение", function() return SetAllSources(false); end);
	-- только источники, которые реально встречаются в базе этой вкладки
	local available = {};
	for _, data in pairs(self:GetDatabase()) do
		if data.source then
			available[data.source] = true;
		end
	end

	for index, label in ipairs(COLLECTIONS_SOURCE_NAMES) do
		if available[index] and (self.companionType == "CRITTER" or not PET_ONLY_SOURCES[index]) then
		sourceMenu:CreateCheckbox(label, function()
			return filters.sources[index];
		end, function()
			filters.sources[index] = not filters.sources[index];
			self.FilterDropdown:ValidateResetState();
			self:Refresh();
		end);
		end
	end
end

function CollectionsCompanionJournalMixin:GetSelected()
	for _, entry in ipairs(self.list or {}) do
		if entry.spellID == self.selectedSpellID then
			return entry;
		end
	end
	return nil;
end

function CollectionsCompanionJournalMixin:Refresh()
	if not self.rows then
		return;
	end
	if not self.prefetched then
		self.prefetched = true;
		CollectionsUtil_PrefetchCreatures(self:GetDatabase());
	end
	self:BuildList();
	if not self:GetSelected() then
		self.selectedSpellID = self.list[1] and self.list[1].spellID or nil;
	end
	self.Count.Value:SetText(GetNumCompanions(self.companionType));
	self:UpdateList();
	self:UpdateDisplay();
end

---------------------------------------------------------------------------
-- отображение
---------------------------------------------------------------------------
function CollectionsCompanionJournalMixin:UpdateList()
	local list = self.list or {};
	local offset = FauxScrollFrame_GetOffset(self.ListScrollFrame);
	FauxScrollFrame_Update(self.ListScrollFrame, #list, NUM_ROWS, ROW_HEIGHT);

	for rowIndex, row in ipairs(self.rows) do
		local entry = list[offset + rowIndex];
		row.entry = entry;
		if entry then
			row.icon:SetTexture(entry.icon);
			row.icon:SetDesaturated(not entry.isCollected);
			row.name:SetText(entry.name);
			if not entry.isCollected then
				row.name:SetTextColor(0.5, 0.5, 0.5);
			elseif entry.isUnusable then
				row.name:SetTextColor(1, 0.1, 0.1);
			else
				row.name:SetTextColor(1, 1, 1);
			end
			row.favorite:SetShown(entry.isFavorite);
			row.summoned:SetShown(entry.isSummoned);
			row.selectedTexture:SetShown(entry.spellID == self.selectedSpellID);
			row:Show();
		else
			row:Hide();
		end
	end
end

function CollectionsCompanionJournalMixin:UpdateDisplay()
	local entry = self:GetSelected();
	local display = self.Display;
	local hasEntry = entry ~= nil;

	display.EmptyText:SetShown(not hasEntry);
	display.Icon:SetShown(hasEntry);
	display.Name:SetShown(hasEntry);
	display.Source:SetShown(hasEntry);
	display.Lore:SetShown(hasEntry);
	display.Model:SetShown(hasEntry);
	display.RotateHint:SetShown(hasEntry);

	if not hasEntry then
		self.SummonButton:Disable();
		self.SummonButton:SetText(self.texts.summon);
		return;
	end

	display.Icon:SetTexture(entry.icon);
	display.Name:SetText(entry.name);
	display.Source:SetText(entry.sourceText or "");
	display.Lore:SetText(entry.lore or GetSpellDescription(entry.spellID));

	local model = display.Model;
	if model.creatureID ~= entry.creatureID then
		model.creatureID = entry.creatureID;
		model:ClearModel();
		model.rotation, model.zoom = 0.61, 0;
		CollectionsUtil_SetCreatureWhenCached(model, entry.creatureID);
		model:SetFacing(model.rotation);
		model:SetPosition(0, 0, 0);
	end

	self.SummonButton:SetText(entry.isSummoned and self.texts.dismiss or self.texts.summon);
	self.SummonButton:SetEnabled(entry.isCollected and not entry.isUnusable);
end

---------------------------------------------------------------------------
-- действия
---------------------------------------------------------------------------
function CollectionsCompanionJournalMixin:OnRowClick(row, mouseButton)
	local entry = row.entry;
	if not entry then
		return;
	end
	if mouseButton == "RightButton" then
		if not entry.isCollected then
			return;
		end
		local set = LoadFavorites();
		set[entry.spellID] = not set[entry.spellID] or nil;
		SaveFavorites();
		self:Refresh();
	elseif IsModifiedClick("CHATLINK") then
		local link = GetSpellLink(entry.spellID);
		if link then
			ChatEdit_InsertLink(link);
		end
	else
		self.selectedSpellID = entry.spellID;
		self:UpdateList();
		self:UpdateDisplay();
	end
end

function CollectionsCompanionJournalMixin:OnRowEnter(row)
	if not row.entry then
		return;
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink("spell:" .. row.entry.spellID);
	GameTooltip:AddLine(" ");
	GameTooltip:AddLine(self.texts.rowHint, 0.5, 0.5, 0.5, true);
	GameTooltip:Show();
end

function CollectionsCompanionJournalMixin:ToggleSummon(entry)
	entry = entry or self:GetSelected();
	if not entry or not entry.index then
		return;
	end
	if entry.isSummoned then
		DismissCompanion(self.companionType);
	else
		CallCompanion(self.companionType, entry.index);
	end
end

-- макрос "случайное избранное": создаётся один раз (общий для аккаунта), дальше только берётся на курсор.
-- Имя латиницей: длина имени макроса в 3.3.5 ограничена 16 байтами, кириллица не влезает.
function CollectionsCompanionJournalMixin:PickupRandomFavoriteMacro()
	if InCombatLockdown() then
		return;
	end

	local macroName = self.texts.macroName;
	local body = "/run " .. self:GetName() .. ":SummonRandomFavorite()";

	local index = GetMacroIndexByName(macroName);
	if index == 0 then
		local numAccountMacros = GetNumMacros();
		if numAccountMacros >= (MAX_ACCOUNT_MACROS or 36) then
			UIErrorsFrame:AddMessage("Нет места для нового макроса (общие макросы заполнены).", 1, 0.1, 0.1);
			return;
		end
		-- иконка: номер в списке иконок макросов; ищем иконку кнопки, иначе первая
		local iconIndex = 1;
		for i = 1, GetNumMacroIcons() do
			local texture = GetMacroIconInfo(i);
			if texture and self.texts.randomFavoriteIcon and texture:lower() == self.texts.randomFavoriteIcon:lower() then
				iconIndex = i;
				break;
			end
		end
		index = CreateMacro(macroName, iconIndex, body, nil);
	end

	if index and index > 0 then
		PickupMacro(index);
	end
end

function CollectionsCompanionJournalMixin:SummonRandomFavorite()
	local favoritesSet = LoadFavorites();
	local candidates = {};
	for index = 1, GetNumCompanions(self.companionType) do
		local _, _, spellID = GetCompanionInfo(self.companionType, index);
		if favoritesSet[spellID] then
			table.insert(candidates, index);
		end
	end
	if #candidates == 0 then
		-- как в ретейле: без избранного - любой из коллекции
		for index = 1, GetNumCompanions(self.companionType) do
			table.insert(candidates, index);
		end
	end
	if #candidates > 0 then
		CallCompanion(self.companionType, candidates[math.random(#candidates)]);
	end
end

---------------------------------------------------------------------------
-- Кнопка-заклинание "случайное избранное" (UIPanelSpellButtonFrameTemplate ретейла).
-- Заклинание на сервере - пустышка; призыв делает клиент (избранное хранится у клиента).
-- Родитель кнопки - вкладка (MountJournal / PetJournal).
---------------------------------------------------------------------------

-- выучено ли заклинание: ищем по имени в книге заклинаний
-- (IsUsableSpell не годится: он пустой и для выученного, если сейчас его нельзя применить)
function CollectionsUtil_IsSpellKnown(spellID)
	local name = GetSpellInfo(spellID);   -- nil, если заклинания нет в клиентском Spell.dbc
	if not name then
		return false;
	end
	local index = 1;
	while true do
		local bookName = GetSpellName(index, BOOKTYPE_SPELL);
		if not bookName then
			return false;
		end
		if bookName == name then
			return true;
		end
		index = index + 1;
	end
end

CollectionsRandomFavoriteSpellFrameMixin = CreateFromMixins(UIPanelSpellButtonFrameMixin);

-- клик: выучено - применяем заклинание, иначе сразу призываем случайного избранного
function CollectionsRandomFavoriteSpellFrameMixin:OnIconClick()
	if CollectionsUtil_IsSpellKnown(self.spellID) then
		CastSpellByName(GetSpellInfo(self.spellID));
	else
		self:GetParent():SummonRandomFavorite();
	end
end

-- на панель команд: выучено - заклинание, иначе макрос
function CollectionsRandomFavoriteSpellFrameMixin:OnIconDragStart()
	if CollectionsUtil_IsSpellKnown(self.spellID) then
		PickupSpell(GetSpellInfo(self.spellID));
	else
		self:GetParent():PickupRandomFavoriteMacro();
	end
end

function CollectionsRandomFavoriteSpellFrameMixin:IsAvailable()
	-- кнопка создаётся (и вызывает это из своего OnLoad) раньше, чем вкладка
	-- получает companionType в OnLoad - до этого считаем кнопку доступной
	local companionType = self:GetParent().companionType;
	if not companionType then
		return true;
	end
	return GetNumCompanions(companionType) > 0;
end

-- после применения заклинания (в т.ч. с панели команд) - призыв случайного избранного
function CollectionsCompanionJournalMixin:WatchRandomFavoriteSpell(spellID)
	self.randomFavoriteSpellID = spellID;
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");
	local baseOnEvent = self:GetScript("OnEvent");
	self:SetScript("OnEvent", function(frame, event, unit, spellName, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if unit == "player" and spellName == GetSpellInfo(frame.randomFavoriteSpellID) then
				frame:SummonRandomFavorite();
			end
			return;
		end
		baseOnEvent(frame, event, unit, spellName, ...);
	end);
end
