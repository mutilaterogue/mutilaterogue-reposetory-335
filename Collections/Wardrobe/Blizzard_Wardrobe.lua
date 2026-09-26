-- Appearances tab (WardrobeCollectionFrame, retail "Items" view) for 3.3.5.
-- Data comes from the server (server\appearance_collection.cpp) through AddonComm, opcode names:
--   "APPEAR_PAGE"    -> category : classId : flags : page : search
--                    <- category : page : numPages : collected : total : "displayId/itemId/c,..."
--   "APPEAR_SOURCES" -> category : displayId
--                    <- category : displayId : "itemId/c,..."
--   "APPEAR_ADDED"   <- itemId
-- Every cell is a DressUpModel with the undressed player trying the item on.

ERR_LEARN_TRANSMOG_S = ERR_LEARN_TRANSMOG_S or "Модель %s добавлена в вашу коллекцию.";

local OP_PAGE, OP_SOURCES, OP_ADDED = "APPEAR_PAGE", "APPEAR_SOURCES", "APPEAR_ADDED";
-- запросы называются иначе, чем ответы: аддон-шёпот самому себе приходит и клиенту тоже
local OP_GET_PAGE, OP_GET_SOURCES = "APPEAR_GET_PAGE", "APPEAR_GET_SOURCES";
local NUM_MODELS = 18;

-- categories: same numbers as on the server
local ARMOR_SLOTS = {
	{ category = 1,  slot = "HeadSlot",      atlas = "transmog-nav-slot-head",     name = "Голова" },
	{ category = 2,  slot = "ShoulderSlot",  atlas = "transmog-nav-slot-shoulder", name = "Плечи" },
	{ category = 3,  slot = "BackSlot",      atlas = "transmog-nav-slot-back",     name = "Спина" },
	{ category = 4,  slot = "ChestSlot",     atlas = "transmog-nav-slot-chest",    name = "Грудь" },
	{ category = 5,  slot = "ShirtSlot",     atlas = "transmog-nav-slot-shirt",    name = "Рубашка" },
	{ category = 6,  slot = "TabardSlot",    atlas = "transmog-nav-slot-tabard",   name = "Гербовая накидка" },
	{ category = 7,  slot = "WristSlot",     atlas = "transmog-nav-slot-wrist",    name = "Запястья" },
	{ category = 8,  slot = "HandsSlot",     atlas = "transmog-nav-slot-hands",    name = "Кисти рук" },
	{ category = 9,  slot = "WaistSlot",     atlas = "transmog-nav-slot-waist",    name = "Пояс" },
	{ category = 10, slot = "LegsSlot",      atlas = "transmog-nav-slot-legs",     name = "Ноги" },
	{ category = 11, slot = "FeetSlot",      atlas = "transmog-nav-slot-feet",     name = "Ступни" },
};

local WEAPON_SLOTS = {
	{ key = "MAINHAND", slot = "MainHandSlot",      atlas = "transmog-nav-slot-mainhand",      name = "Правая рука",
		categories = { { 20, "Одноручные топоры" }, { 24, "Одноручное дробящее" }, { 27, "Одноручные мечи" }, { 35, "Кинжалы" }, { 33, "Кистевое оружие" },
		               { 21, "Двуручные топоры" }, { 25, "Двуручное дробящее" }, { 28, "Двуручные мечи" }, { 26, "Древковое оружие" }, { 30, "Посохи" } } },
	{ key = "OFFHAND",  slot = "SecondaryHandSlot", atlas = "transmog-nav-slot-secondaryhand", name = "Левая рука",
		categories = { { 40, "Щиты" }, { 41, "Левая рука" } } },
	{ key = "RANGED",   slot = "RangedSlot",        atlas = nil,                               name = "Дальний бой",
		categories = { { 22, "Луки" }, { 23, "Ружья" }, { 38, "Арбалеты" }, { 39, "Жезлы" }, { 36, "Метательное оружие" } } },
};

-- camera per category: SetPosition(zoom, x, height), facing (radians). Tune in game: /wardcam zoom x z [facing]
WARDROBE_CAMERAS = WARDROBE_CAMERAS or {
	[1]  = { 2.3, 0, -0.85, 0 },    -- head
	[2]  = { 1.9, 0, -0.65, 0.3 },  -- shoulder
	[3]  = { 1.0, 0, -0.15, math.pi }, -- back: from behind
	[4]  = { 1.4, 0, -0.35, 0 },    -- chest
	[5]  = { 1.4, 0, -0.35, 0 },    -- shirt
	[6]  = { 1.4, 0, -0.35, 0 },    -- tabard
	[7]  = { 1.7, 0, -0.05, 0.6 },  -- wrist
	[8]  = { 1.7, 0, -0.05, 0.6 },  -- hands
	[9]  = { 1.8, 0, -0.05, 0 },    -- waist
	[10] = { 1.1, 0, 0.35, 0 },     -- legs
	[11] = { 1.6, 0, 0.75, 0 },     -- feet
	weapon = { 0.6, 0, 0, 0.6 },
};

local CLASS_IDS = {
	WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6,
	SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
};

local function SetAtlasSafe(texture, atlas, useSize)
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas, useSize);
		return true;
	end
	return false;
end

local itemQueryTooltip = CreateFrame("GameTooltip", "WardrobeQueryTooltip", UIParent, "GameTooltipTemplate");
local function RequestItem(itemId)
	itemQueryTooltip:SetOwner(UIParent, "ANCHOR_NONE");
	itemQueryTooltip:SetHyperlink("item:" .. itemId);
	itemQueryTooltip:Hide();
end

-- оружие на персонаже: { приближение, x, высота, поворот }; подгонка - /wardcam в игре
WARDROBE_WEAPON_CAMERAS = WARDROBE_WEAPON_CAMERAS or {
	default = { 0.6, 0, -0.05, 0.6 },
	[21] = { 0.3, 0, 0, 0.6 }, [25] = { 0.3, 0, 0, 0.6 }, [28] = { 0.3, 0, 0, 0.6 },   -- двуручные
	[26] = { 0.2, 0, 0, 0.6 }, [30] = { 0.2, 0, 0, 0.6 },                            -- древковое, посохи
	[22] = { 0.4, 0, 0, 0.6 }, [23] = { 0.4, 0, 0, 0.6 }, [38] = { 0.4, 0, 0, 0.6 },   -- луки, ружья, арбалеты
	[40] = { 0.6, 0, -0.05, -0.6 }, [41] = { 0.6, 0, -0.05, -0.6 },                  -- щит, левая рука
};

-- тип слота по категории - если GetItemInfo ещё не знает предмет
local CATEGORY_INVTYPE = {
	[1] = "INVTYPE_HEAD", [2] = "INVTYPE_SHOULDER", [3] = "INVTYPE_CLOAK", [4] = "INVTYPE_CHEST", [5] = "INVTYPE_BODY",
	[6] = "INVTYPE_TABARD", [7] = "INVTYPE_WRIST", [8] = "INVTYPE_HAND", [9] = "INVTYPE_WAIST", [10] = "INVTYPE_LEGS",
	[11] = "INVTYPE_FEET", [40] = "INVTYPE_SHIELD", [41] = "INVTYPE_HOLDABLE",
	[21] = "INVTYPE_2HWEAPON", [25] = "INVTYPE_2HWEAPON", [28] = "INVTYPE_2HWEAPON", [26] = "INVTYPE_2HWEAPON", [30] = "INVTYPE_2HWEAPON",
	[22] = "INVTYPE_RANGED", [23] = "INVTYPE_RANGED", [38] = "INVTYPE_RANGED", [39] = "INVTYPE_RANGEDRIGHT", [36] = "INVTYPE_THROWN",
};

-- камера WCollections (WardrobeCameras.lua) по расе/полу/типу предмета; /wardcam может её переопределить
local function GetCamera(category, itemId)
	return WardrobeGetCamera(category, itemId);
end

-- общая функция камеры (её использует и окно трансмогрификации)
function WardrobeGetCamera(category, itemId)
	local custom = WARDROBE_CAMERAS[category];
	if custom and custom.user then
		return custom;
	end
	-- оружие: камеры WCollections рассчитаны на модель одного предмета, а у нас персонаж с оружием в руке
	if category >= 20 then
		return WARDROBE_WEAPON_CAMERAS[category] or WARDROBE_WEAPON_CAMERAS.default;
	end
	if WCollections and WCollections.Cameras then
		local invType = itemId and select(9, GetItemInfo(itemId));
		if not invType or invType == "" then
			invType = CATEGORY_INVTYPE[category] or "INVTYPE_WEAPON";
		end
		local id;
		if category >= 20 and category < 40 then
			id = WCollections:GetWeaponCameraID(invType, category - 20);
		elseif category >= 40 then
			id = WCollections:GetWeaponCameraID(invType);
		else
			id = WCollections:GetCharacterCameraID(invType);
		end
		local cam = id and WCollections.Cameras[id];
		if cam then
			return cam;
		end
	end
	return custom or WARDROBE_CAMERAS.weapon;
end

---------------------------------------------------------------------------
-- models
---------------------------------------------------------------------------
local function ApplyCamera(model)
	local cam = GetCamera(WardrobeCollectionFrame.category, model.entry and model.entry.itemId);
	model.camera = cam;
	model:SetPosition(cam[1], cam[2], cam[3]);
	model:SetFacing(cam[4] or 0);
end

local function DressModel(model)
	local entry = model.entry;
	if not entry then
		return;
	end
	-- SetUnit только один раз: повторный SetUnit на уже загруженной модели в 3.3.5
	-- сбрасывает её в обычную позу/камеру, и SetPosition больше не действует
	if not model.unitSet then
		model:SetUnit("player");
		model.unitSet = true;
	end
	model:Undress();
	model:TryOn("item:" .. entry.itemId);
	ApplyCamera(model);
end

local function UpdateModel(model)
	local entry = model.entry;
	if not entry then
		model:Hide();
		model.BorderFrame:Hide();
		return;
	end
	model:Show();
	model.BorderFrame:Show();
	if entry.collected then
		model.BorderFrame:SetBackdropBorderColor(1, 0.82, 0, 1);
		model:SetAlpha(1);
	else
		model.BorderFrame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1);
		model:SetAlpha(0.8);
	end
	DressModel(model);
	-- 3.3.5: the unit model is sometimes not ready on the same frame - dress again a bit later
	-- модель персонажа и предмет в 3.3.5 догружаются не сразу (оружие - особенно):
	-- переодеваем ещё несколько раз, пока всё не подгрузится
	model.redressIndex = 1;
	model.redressTime = 0.1;
end

function WardrobeItemsModel_OnLoad(self)
	-- рамка: атласы transmog-wardrobe-border-* в клиенте без текстур, поэтому обычная рамка поверх модели
	local border = CreateFrame("Frame", nil, self:GetParent());
	border:SetPoint("TOPLEFT", self, "TOPLEFT", -5, 5);
	border:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 5, -5);
	border:SetFrameLevel(self:GetFrameLevel() + 2);
	border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 } });
	border:Hide();
	self.BorderFrame = border;
	SetAtlasSafe(self.Highlight, "transmog-wardrobe-border-highlighted", true);
	SetAtlasSafe(self.Selected, "transmog-wardrobe-border-selected", true);
	self:SetScript("OnUpdate", function(model, elapsed)
		-- 3.3.5 сбрасывает позицию, пока догружаются модель и предмет: ставим камеру каждый кадр
		if model.entry then
			ApplyCamera(model);
		end
		if model.redressTime then
			model.redressTime = model.redressTime - elapsed;
			if model.redressTime <= 0 then
				DressModel(model);
				local delays = { 0.3, 0.6, 1.0, 2.0 };
				model.redressIndex = (model.redressIndex or 1) + 1;
				model.redressTime = delays[model.redressIndex - 1];
			end
		end
	end);
end

function WardrobeItemsModel_OnMouseDown(self, button)
	local entry = self.entry;
	if not entry then
		return;
	end
	local itemId = WardrobeCollectionFrame.tooltipItemId or entry.itemId;
	local _, link = GetItemInfo(itemId);
	if IsModifiedClick("CHATLINK") and link then
		ChatEdit_InsertLink(link);
	elseif IsModifiedClick("DRESSUP") and link then
		DressUpItemLink(link);
	end
end

---------------------------------------------------------------------------
-- tooltip: header item + "other items with this appearance", Tab cycles
---------------------------------------------------------------------------
local sourcesCache = {};   -- ["category:displayId"] = { {itemId, collected}, ... }

local function ItemNameAndColor(itemId)
	local name, _, quality = GetItemInfo(itemId);
	if not name then
		RequestItem(itemId);
		return RETRIEVING_ITEM_INFO or "Загрузка...", RED_FONT_COLOR;
	end
	return name, ITEM_QUALITY_COLORS[quality or 1] or HIGHLIGHT_FONT_COLOR;
end

local function ShowAppearanceTooltip(model)
	local frame = WardrobeCollectionFrame;
	local entry = model.entry;
	if not entry then
		return;
	end
	local sources = sourcesCache[frame.category .. ":" .. entry.displayId] or { { itemId = entry.itemId, collected = entry.collected } };
	local index = ((frame.tooltipIndex or 1) - 1) % #sources + 1;
	local header = sources[index];
	frame.tooltipItemId = header.itemId;

	GameTooltip:SetOwner(model, "ANCHOR_RIGHT", -15, 0);
	local name, color = ItemNameAndColor(header.itemId);
	GameTooltip:SetText(name, color.r, color.g, color.b);
	if header.collected then
		GameTooltip:AddLine("Собрано", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b);
	else
		GameTooltip:AddLine("Не собрано", 0.6, 0.6, 0.6);
	end

	if #sources > 1 then
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine("Другие предметы с этим обликом:", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
		for i, source in ipairs(sources) do
			local itemName, itemColor = ItemNameAndColor(source.itemId);
			local prefix = (i == index) and "|TInterface\\Common\\Indicator-Yellow:0|t " or "   ";
			local state = source.collected and "Собрано" or "";
			GameTooltip:AddDoubleLine(prefix .. itemName, state, itemColor.r, itemColor.g, itemColor.b, 0.1, 1, 0.1);
		end
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine("Нажмите Tab, чтобы переключать предметы.", 0.5, 0.5, 0.5);
	end
	GameTooltip:Show();
end

function WardrobeItemsModel_OnEnter(self)
	local frame = WardrobeCollectionFrame;
	frame.tooltipModel = self;
	frame.tooltipIndex = 1;
	local entry = self.entry;
	if entry then
		local key = frame.category .. ":" .. entry.displayId;
		if not sourcesCache[key] and Comm_Send then
			Comm_Send(OP_GET_SOURCES, frame.category, entry.displayId);
		end
	end
	ShowAppearanceTooltip(self);
	-- Tab cycles items while the mouse is over a model (3.3.5 can't pass other keys through,
	-- so the keyboard is taken only while hovering)
	frame:EnableKeyboard(true);
end

function WardrobeItemsModel_OnLeave(self)
	local frame = WardrobeCollectionFrame;
	frame.tooltipModel = nil;
	frame.tooltipItemId = nil;
	frame:EnableKeyboard(false);
	GameTooltip:Hide();
end

---------------------------------------------------------------------------
-- slots / weapons
---------------------------------------------------------------------------

local function GetWeaponInfo(key)
	for _, info in ipairs(WEAPON_SLOTS) do
		if info.key == key then
			return info;
		end
	end
end

local function GetCategoryName(category)
	for _, info in ipairs(ARMOR_SLOTS) do
		if info.category == category then
			return info.name;
		end
	end
	for _, info in ipairs(WEAPON_SLOTS) do
		for _, cat in ipairs(info.categories) do
			if cat[1] == category then
				return cat[2];
			end
		end
	end
	return "";
end

function WardrobeCollectionFrame_SetCategory(self, category)
	self.category = category;
	self.page = 1;
	self.CategoryText:SetText(GetCategoryName(category));
	self.FilterDropdown:ValidateResetState();
	WardrobeCollectionFrame_Request(self);
end

---------------------------------------------------------------------------
-- server requests
---------------------------------------------------------------------------
function WardrobeCollectionFrame_Request(self)
	self = self or WardrobeCollectionFrame;
	if not Comm_Send then
		return;
	end
	local flags = (self.filters.collected and 1 or 0) + (self.filters.notCollected and 2 or 0);
	local search = (self.searchText or ""):gsub(":", " ");
	self.waiting = true;
	self.requestElapsed = 0;
	Comm_Send(OP_GET_PAGE, self.category, self.classId or 0, flags, self.page or 1, search, "W");
end

local function UpdatePage(self)
	for index, model in ipairs(self.models) do
		model.entry = self.entries[index];
		UpdateModel(model);
	end

	local paging = self.ItemsCollectionFrame.PagingFrame;
	paging.PageText:SetFormattedText("Стр. %d/%d", self.page or 1, self.numPages or 1);
	paging.PrevPageButton:SetEnabled((self.page or 1) > 1);
	paging.NextPageButton:SetEnabled((self.page or 1) < (self.numPages or 1));

	self.ProgressBar:SetMinMaxValues(0, math.max(1, self.total or 0));
	self.ProgressBar:SetValue(self.collected or 0);
	self.ProgressBar.Text:SetFormattedText("%d/%d", self.collected or 0, self.total or 0);

	if not self.EmptyText then
		self.EmptyText = self.ItemsCollectionFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
		self.EmptyText:SetPoint("CENTER", 0, 10);
	end
	if #self.entries == 0 then
		if self.waiting then
			self.EmptyText:SetText(self.noAnswer and "Сервер не ответил на запрос обликов" or "Загрузка...");
		else
			self.EmptyText:SetText("Ничего не найдено");
		end
		self.EmptyText:Show();
	else
		self.EmptyText:Hide();
	end
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
function WardrobeCollectionFrame_OnLoad(self)
	self.entries = {};
	self.filters = { collected = true, notCollected = true };
	self.lastWeaponCategory = {};
	self.category = 1;
	self.page = 1;

	local _, playerClass = UnitClass("player");
	self.classId = CLASS_IDS[playerClass];

	-- models
	self.models = {};
	for row = 1, 3 do
		for column = 1, 6 do
			table.insert(self.models, _G[self.ItemsCollectionFrame:GetName() .. "ModelR" .. row .. "C" .. column]);
		end
	end

	-- название выбранного слота над сеткой (слот выбирается в «Фильтре»)
	self.CategoryText = self.ItemsCollectionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	self.CategoryText:SetPoint("TOP", self.ItemsCollectionFrame, "TOP", 0, -40);
	self.CategoryText:SetText(GetCategoryName(self.category));
	self.ItemsCollectionFrame.SlotsFrame:Hide();
	self.ItemsCollectionFrame.WeaponDropdown:Hide();

	-- class dropdown
	local classOrder = CLASS_SORT_ORDER or { "WARRIOR", "DEATHKNIGHT", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER" };
	local function ClassLabel(classFile)
		if not classFile then
			return ALL_CLASSES or "Все классы";
		end
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or classFile;
		local color = RAID_CLASS_COLORS[classFile];
		if color then
			return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name);
		end
		return name;
	end
	local classDropdown = self.ClassDropdown;
	classDropdown:SetupMenu(function(dropdown, rootDescription)
		local function SetClass(classFile)
			self.classId = classFile and CLASS_IDS[classFile] or nil;
			self.page = 1;
			WardrobeCollectionFrame_Request(self);
		end
		rootDescription:CreateRadio(ClassLabel(nil), function() return self.classId == nil; end, function() SetClass(nil); end);
		for _, classFile in ipairs(classOrder) do
			if CLASS_IDS[classFile] then
				rootDescription:CreateRadio(ClassLabel(classFile), function() return self.classId == CLASS_IDS[classFile]; end, SetClass, classFile);
			end
		end
	end);
	if classDropdown.SetText then
		classDropdown:SetText(ClassLabel(playerClass));
	end
	classDropdown:Hide();

	-- filter
	local filter = self.FilterDropdown;
	filter:SetIsDefaultCallback(function()
		return self.filters.collected and self.filters.notCollected and self.category == 1;
	end);
	filter:SetDefaultCallback(function()
		self.filters.collected, self.filters.notCollected = true, true;
		self.category = 1;
		self.CategoryText:SetText(GetCategoryName(1));
	end);
	filter:SetUpdateCallback(function() self.page = 1; WardrobeCollectionFrame_Request(self); end);
	filter:SetupMenu(function(dropdown, rootDescription)
		for _, info in ipairs({ { "collected", "Собранные" }, { "notCollected", "Не собранные" } }) do
			local key = info[1];
			rootDescription:CreateCheckbox(info[2], function()
				return self.filters[key];
			end, function()
				self.filters[key] = not self.filters[key];
				filter:ValidateResetState();
				self.page = 1;
				WardrobeCollectionFrame_Request(self);
			end);
		end

		local function IsCategory(category)
			return self.category == category;
		end
		local function SetCategory(category)
			WardrobeCollectionFrame_SetCategory(self, category);
		end
		-- класс (место выпадающего списка заняли вкладки «Предметы» / «Наборы»)
		rootDescription:CreateDivider();
		local classMenu = rootDescription:CreateSubmenu(CLASS or "Класс");
		local function IsClass(classFile)
			return (classFile and CLASS_IDS[classFile] or nil) == self.classId;
		end
		local function SetClassFilter(classFile)
			self.classId = classFile and CLASS_IDS[classFile] or nil;
			self.page = 1;
			WardrobeCollectionFrame_Request(self);
		end
		classMenu:CreateRadio(ClassLabel(nil), function() return self.classId == nil; end, function() SetClassFilter(nil); end);
		for _, classFile in ipairs(classOrder) do
			if CLASS_IDS[classFile] then
				classMenu:CreateRadio(ClassLabel(classFile), IsClass, SetClassFilter, classFile);
			end
		end

		-- категории - подменю: раскрываются по одной при наведении
		rootDescription:CreateDivider();
		local armor = rootDescription:CreateSubmenu("Броня");
		for _, info in ipairs(ARMOR_SLOTS) do
			armor:CreateRadio(info.name, IsCategory, SetCategory, info.category);
		end
		for _, info in ipairs(WEAPON_SLOTS) do
			local submenu = rootDescription:CreateSubmenu(info.name);
			for _, cat in ipairs(info.categories) do
				submenu:CreateRadio(cat[2], IsCategory, SetCategory, cat[1]);
			end
		end
	end);

	-- search: ask the server after a short pause in typing
	self.SearchBox:HookScript("OnTextChanged", function(searchBox)
		local text = searchBox:GetText() or "";
		if text == (SEARCH or "") then
			text = "";
		end
		if self.setsMode then
			WardrobeSets_SetSearch(text);
			return;
		end
		if text ~= (self.searchText or "") then
			self.searchText = text;
			self.searchDelay = 0.4;
		end
	end);

	-- paging
	local function SetPage(page)
		if page < 1 or page > (self.numPages or 1) or page == self.page then
			return;
		end
		self.page = page;
		PlaySound("igAbiliityPageTurn");
		WardrobeCollectionFrame_Request(self);
	end
	local paging = self.ItemsCollectionFrame.PagingFrame;
	paging.PrevPageButton:SetScript("OnClick", function() SetPage((self.page or 1) - 1); end);
	paging.NextPageButton:SetScript("OnClick", function() SetPage((self.page or 1) + 1); end);
	self.ItemsCollectionFrame:SetScript("OnMouseWheel", function(_, delta)
		SetPage((self.page or 1) - delta);
	end);

	self:SetScript("OnKeyDown", function(frame, key)
		if key == "TAB" and frame.tooltipModel then
			frame.tooltipIndex = (frame.tooltipIndex or 1) + (IsShiftKeyDown() and -1 or 1);
			ShowAppearanceTooltip(frame.tooltipModel);
		else
			frame:EnableKeyboard(false);
		end
	end);

	self:SetScript("OnUpdate", function(frame, elapsed)
		if frame.searchDelay then
			frame.searchDelay = frame.searchDelay - elapsed;
			if frame.searchDelay <= 0 then
				frame.searchDelay = nil;
				frame.page = 1;
				WardrobeCollectionFrame_Request(frame);
			end
		end
		if frame.requestElapsed then
			frame.requestElapsed = frame.requestElapsed + elapsed;
			if frame.requestElapsed > 3 then
				frame.requestElapsed = nil;
				if frame.waiting then
					frame.noAnswer = true;
					UpdatePage(frame);
				end
			end
		end
	end);

end

function WardrobeCollectionFrame_OnShow(self)
	WardrobeSets_Init(self);
	if self.setsMode then
		WardrobeSets_Show(self);
		return;
	end
	self.noAnswer = nil;
	WardrobeCollectionFrame_Request(self);
	UpdatePage(self);
end

function WardrobeCollectionFrame_OnHide(self)
	self:EnableKeyboard(false);
end

---------------------------------------------------------------------------
-- server messages
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register(OP_PAGE, function(category, page, numPages, collected, total, entriesText, tag)
		if tag and tag ~= "" and tag ~= "W" then
			return;   -- ответ для окна трансмогрификации
		end
		local frame = WardrobeCollectionFrame;
		if WARDROBE_DEBUG then
			DEFAULT_CHAT_FRAME:AddMessage(("APPEAR_PAGE cat=%s page=%s/%s collected=%s total=%s entries=%d"):format(
				tostring(category), tostring(page), tostring(numPages), tostring(collected), tostring(total), select(2, (entriesText or ""):gsub("%d+/%d+/%d", "")) ));
		end
		category = tonumber(category);
		if category ~= frame.category then
			return;   -- answer for an old request
		end
		frame.waiting = false;
		frame.noAnswer = nil;
		frame.requestElapsed = nil;
		frame.page = tonumber(page) or 1;
		frame.numPages = tonumber(numPages) or 1;
		frame.collected = tonumber(collected) or 0;
		frame.total = tonumber(total) or 0;
		frame.entries = {};
		for displayId, itemId, isCollected in (entriesText or ""):gmatch("(%d+)/(%d+)/(%d)") do
			table.insert(frame.entries, { displayId = tonumber(displayId), itemId = tonumber(itemId), collected = isCollected == "1" });
		end
		if frame:IsShown() then
			UpdatePage(frame);
		end
	end);

	Comm_Register(OP_SOURCES, function(category, displayId, listText)
		local list = {};
		for itemId, isCollected in (listText or ""):gmatch("(%d+)/(%d)") do
			table.insert(list, { itemId = tonumber(itemId), collected = isCollected == "1" });
		end
		table.sort(list, function(a, b)
			if a.collected ~= b.collected then
				return a.collected;
			end
			return a.itemId < b.itemId;
		end);
		sourcesCache[category .. ":" .. displayId] = list;
		local frame = WardrobeCollectionFrame;
		local model = frame.tooltipModel;
		if model and model.entry and tostring(model.entry.displayId) == displayId then
			ShowAppearanceTooltip(model);
		end
	end);

	Comm_Register(OP_ADDED, function(itemId)
		itemId = tonumber(itemId);
		if not itemId then
			return;
		end
		sourcesCache = {};
		if TransmogUI then
			TransmogUI.setsStale = true;   -- прогресс комплектов
		end
		local _, link = GetItemInfo(itemId);
		-- ретейл: ERR_LEARN_TRANSMOG_S системным сообщением
		local info = ChatTypeInfo["SYSTEM"];
		DEFAULT_CHAT_FRAME:AddMessage(ERR_LEARN_TRANSMOG_S:format(link or ("item:" .. itemId)), info.r, info.g, info.b, info.id);
		if WardrobeCollectionFrame:IsShown() then
			WardrobeCollectionFrame_Request(WardrobeCollectionFrame);
		end
	end);
end

-- /wardcam zoom x z [facing] - tune the camera of the current category, prints the line for WARDROBE_CAMERAS
SLASH_WARDCAM1 = "/wardcam";
SlashCmdList["WARDCAM"] = function(msg)
	local frame = WardrobeCollectionFrame;
	local zoom, x, z, facing = strsplit(" ", msg or "");
	zoom, x, z, facing = tonumber(zoom), tonumber(x), tonumber(z), tonumber(facing);
	local base = frame.models[1] and frame.models[1].camera or GetCamera(frame.category);
	local cam = { base[1], base[2], base[3], base[4] or 0, user = true };
	if zoom then
		cam[1], cam[2], cam[3] = zoom, x or cam[2], z or cam[3];
		if facing then
			cam[4] = facing;
		end
		WARDROBE_CAMERAS[frame.category] = cam;
	end
	DEFAULT_CHAT_FRAME:AddMessage(("category %d: { %.2f, %.2f, %.2f, %.2f }"):format(frame.category, cam[1], cam[2], cam[3], cam[4] or 0));
end

-- /wardebug - печатать ответы сервера (проверка, что страница пришла целиком)
SLASH_WARDEBUG1 = "/wardebug";
SlashCmdList["WARDEBUG"] = function()
	WARDROBE_DEBUG = not WARDROBE_DEBUG;
	DEFAULT_CHAT_FRAME:AddMessage("Wardrobe debug: " .. (WARDROBE_DEBUG and "on" or "off"));
end
