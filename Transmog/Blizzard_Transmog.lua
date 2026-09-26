-- Transmogrification window (retail 12.x TransmogFrame, simplified) for 3.3.5.
-- Left: outfits, center: the character with slot buttons, right: collected appearances of the slot.
-- The interface works on its own; the server part comes later. Opcodes (names; requests differ
-- from answers, the client also receives its own addon whisper):
--   "TMOG_GET_STATE"            -> "TMOG_STATE" : "slot/itemId,..."        current transmogs
--   "TMOG_APPLY" : "slot/itemId,..." (itemId 0 = restore) -> "TMOG_RESULT" : ok(1/0) : message
--   "TMOG_OPEN" / "TMOG_CLOSE"  server opens/closes the window (NPC transmogrifier)
--   "APPEAR_GET_PAGE" ... : "T" -> "APPEAR_PAGE" ... : "T"   appearances (appearance_collection.cpp)
-- Without the server: /transmog opens the window, "Apply" says the server does not answer.

local OP_GET_STATE, OP_STATE, OP_APPLY, OP_RESULT, OP_OPEN, OP_CLOSE, OP_GET_PAGE, OP_PAGE, GRID_COLUMNS, GRID_ROWS, MODEL_WIDTH, MODEL_HEIGHT, MODEL_SPACE_X, MODEL_SPACE_Y, LEFT_X1, LEFT_X2, CENTER_X1, CENTER_X2, RIGHT_X1, RIGHT_X2, PANEL_TOP, PANEL_BOTTOM, SLOTS, SLOT_UNASSIGNED_ATLAS, SLOT_BY_ID, CLASS_IDS, NUM_OUTFIT_BUTTONS, MAX_OUTFITS =
	TransmogUI.OP_GET_STATE, TransmogUI.OP_STATE, TransmogUI.OP_APPLY, TransmogUI.OP_RESULT, TransmogUI.OP_OPEN, TransmogUI.OP_CLOSE, TransmogUI.OP_GET_PAGE, TransmogUI.OP_PAGE, TransmogUI.GRID_COLUMNS, TransmogUI.GRID_ROWS, TransmogUI.MODEL_WIDTH, TransmogUI.MODEL_HEIGHT, TransmogUI.MODEL_SPACE_X, TransmogUI.MODEL_SPACE_Y, TransmogUI.LEFT_X1, TransmogUI.LEFT_X2, TransmogUI.CENTER_X1, TransmogUI.CENTER_X2, TransmogUI.RIGHT_X1, TransmogUI.RIGHT_X2, TransmogUI.PANEL_TOP, TransmogUI.PANEL_BOTTOM, TransmogUI.SLOTS, TransmogUI.SLOT_UNASSIGNED_ATLAS, TransmogUI.SLOT_BY_ID, TransmogUI.CLASS_IDS, TransmogUI.NUM_OUTFIT_BUTTONS, TransmogUI.MAX_OUTFITS;

function TransmogUI.GetDisplayedItem(self, slotId)
	-- what the slot shows: pending change > current transmog > equipped item
	local pending = self.pending[slotId];
	if pending ~= nil then
		if pending == 0 then
			return GetInventoryItemID and GetInventoryItemID("player", slotId), true;
		end
		return pending, true;
	end
	if self.applied[slotId] then
		return self.applied[slotId], false;
	end
	return GetInventoryItemID and GetInventoryItemID("player", slotId), false;
end

function TransmogUI.HasPending(self)
	return next(self.pending) ~= nil;
end

function TransmogUI.GetCost(self)
	local cost = 0;
	for slotId in pairs(self.pending) do
		local link = GetInventoryItemLink("player", slotId);
		if link then
			local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link);
			cost = cost + math.max(sellPrice or 0, 10000 / 100);   -- как у трансмогрификаторов 3.3.5: цена продажи, минимум 1 серебро
		end
	end
	return cost;
end

---------------------------------------------------------------------------
-- character preview
---------------------------------------------------------------------------
function TransmogUI.UpdatePreview(self)
	local model = self.Preview;
	model:SetUnit("player");
	model:SetPosition(model.zoom or 0, 0, 0);
	model:SetFacing(model.facing or 0);
	if self.showEquipped then
		return;   -- «Показать надетую экипировку»: только то, что надето сейчас
	end
	for _, info in ipairs(SLOTS) do
		local itemId, changed = TransmogUI.GetDisplayedItem(self, info.id);
		if itemId and (changed or self.applied[info.id]) then
			model:TryOn("item:" .. itemId);
		end
	end
end

function TransmogUI.UpdateSlotButton(self, button)
	local info = button.info;
	local slotId = info.id;
	local equipped = GetInventoryItemLink("player", slotId);
	local itemId, changed = TransmogUI.GetDisplayedItem(self, slotId);

	if equipped and itemId then
		button.Icon:SetTexture(TransmogUI.GetItemIcon(itemId));
		button.Icon:SetDesaturated(false);
		button.Background:SetAtlas("transmog-gearSlot-default");
		button:Enable();
	else
		button.Icon:SetAtlas("transmog-gearSlot-unassigned-" .. SLOT_UNASSIGNED_ATLAS[slotId]);
		button.Icon:SetDesaturated(false);
		button.Background:SetAtlas("transmog-gearSlot-disabled");
		button:Disable();
	end
	button.Pending:SetShown(changed);
	button.Selected:SetShown(self.selectedSlot == slotId);
	button.Transmogged:SetShown(self.applied[slotId] ~= nil and self.pending[slotId] ~= 0);
end

function TransmogUI.UpdateSlots(self)
	for _, button in ipairs(self.slotButtons) do
		TransmogUI.UpdateSlotButton(self, button);
	end

	local cost = TransmogUI.GetCost(self);
	MoneyFrame_Update(self.MoneyFrame:GetName(), cost);
	self.ApplyButton:SetEnabled(TransmogUI.HasPending(self));
	self.ClearButton:SetEnabled(TransmogUI.HasPending(self));
end

---------------------------------------------------------------------------
-- appearance grid (right)
---------------------------------------------------------------------------
function TransmogUI.UpdateGrid(self)
	local selectedItem = self.selectedSlot and TransmogUI.GetDisplayedItem(self, self.selectedSlot);
	for index, model in ipairs(self.gridModels) do
		local entry = self.entries[index];
		model.entry = entry;
		if entry then
			model:Show();
			model.Border:Show();
			if entry.itemId == selectedItem then
				model.Border.Card:SetAtlas("transmog-itemCard-current");
			elseif entry.itemId == (self.selectedSlot and self.applied[self.selectedSlot]) then
				model.Border.Card:SetAtlas("transmog-itemCard-transmogrified");
			else
				model.Border.Card:SetAtlas("transmog-itemCard-default");
			end
			model.Border.Card:SetDesaturated(not entry.collected);
			model:SetAlpha(entry.collected and 1 or 0.6);
			TransmogUI.DressGridModel(model);
			model.redressIndex, model.redressTime = 1, 0.1;
		else
			model:Hide();
			model.Border:Hide();
		end
	end

	local paging = self.Paging;
	paging.Text:SetFormattedText("Стр. %d/%d", self.page or 1, self.numPages or 1);
	paging.Prev:SetEnabled((self.page or 1) > 1);
	paging.Next:SetEnabled((self.page or 1) < (self.numPages or 1));

	if not self.selectedSlot then
		self.GridMessage:SetText("Выберите слот на персонаже");
		self.GridMessage:Show();
	elseif not self.category then
		self.GridMessage:SetText("Этот предмет нельзя трансмогрифицировать");
		self.GridMessage:Show();
	elseif #self.entries == 0 then
		self.GridMessage:SetText(self.waiting and (self.noAnswer and "Сервер не ответил" or "Загрузка...") or "Нет обликов");
		self.GridMessage:Show();
	else
		self.GridMessage:Hide();
	end
end

function TransmogUI.RequestPage(self)
	self.entries = {};
	if not self.selectedSlot or not self.category or not Comm_Send then
		TransmogUI.UpdateGrid(self);
		return;
	end
	local _, playerClass = UnitClass("player");
	local flags = self.showUncollected and 3 or 1;
	local search = (self.searchText or ""):gsub(":", " ");
	self.waiting, self.noAnswer, self.requestElapsed = true, nil, 0;
	Comm_Send(OP_GET_PAGE, self.category, CLASS_IDS[playerClass] or 0, flags, self.page or 1, search, "T", GRID_COLUMNS * GRID_ROWS);
	TransmogUI.UpdateGrid(self);
end

function TransmogFrame_SelectSlot(self, slotId)
	local info = SLOT_BY_ID[slotId];
	local link = GetInventoryItemLink("player", slotId);
	if not info or not link then
		return;
	end
	self.selectedSlot = slotId;
	self.category = TransmogUI.GetItemCategory(info, link);
	self.page = 1;
	self.SlotTitle:SetText(info.name);
	TransmogUI.UpdateSlots(self);
	TransmogUI.RequestPage(self);
end

function TransmogFrame_OnLoad(self)
	self.pending = {};
	self.applied = {};
	self.entries = {};
	tinsert(UISpecialFrames, self:GetName());
	-- окно 1200x720 не влезает на экран при обычном масштабе интерфейса - уменьшаем, как PlayerSpellsFrame
	self:SetScale(TRANSMOG_FRAME_SCALE or 0.8);
	self:RegisterForDrag("LeftButton");

	if self.TitleContainer and self.TitleContainer.TitleText then
		self.TitleContainer.TitleText:SetText("Трансмогрификация");
	end
	if self.PortraitContainer and self.PortraitContainer.portrait then
		SetPortraitToTexture(self.PortraitContainer.portrait, "Interface\\Icons\\INV_Arcane_Orb");
	end
	if self.SetFrameLevelsFromBaseLevel then
		self:SetFrameLevelsFromBaseLevel(self:GetFrameLevel());
	end

	-------------------------------------------------------------------
	-- left: outfits
	-------------------------------------------------------------------
	local left = TransmogUI.CreatePanel(self, LEFT_X1, LEFT_X2, "transmog-outfit-darkBG");
	local gradientTop = left:CreateTexture(nil, "BACKGROUND", nil, 1);
	gradientTop:SetAtlas("transmog-outfit-toptexture", true);
	gradientTop:SetPoint("TOP");
	local gradientBottom = left:CreateTexture(nil, "BACKGROUND", nil, 1);
	gradientBottom:SetAtlas("transmog-outfit-bottomtexture", true);
	gradientBottom:SetPoint("BOTTOM");
	local divider = left:CreateTexture(nil, "BACKGROUND", nil, 2);
	divider:SetAtlas("transmog-outfit-darkBG-cornerLine");
	divider:SetWidth(6);
	divider:SetPoint("TOPRIGHT", 2, 0);
	divider:SetPoint("BOTTOMRIGHT", 2, 0);

	-- «Показать надетую экипировку» (ретейл: ShowEquippedGearSpellFrame)
	local equipped = CreateFrame("Button", nil, left);
	equipped:SetSize(244, 40);
	equipped:SetPoint("TOPLEFT", 8, -34);
	equipped.Icon = equipped:CreateTexture(nil, "ARTWORK");
	equipped.Icon:SetSize(34, 34);
	equipped.Icon:SetPoint("LEFT", 2, 0);
	equipped.Icon:SetTexture("Interface\\Icons\\INV_Chest_Chain_15");
	local spellFrame = equipped:CreateTexture(nil, "OVERLAY");
	spellFrame:SetAtlas("transmog-outfit-spellFrame");
	spellFrame:SetPoint("TOPLEFT", equipped.Icon, "TOPLEFT", -4, 4);
	spellFrame:SetPoint("BOTTOMRIGHT", equipped.Icon, "BOTTOMRIGHT", 4, -4);
	local equippedText = TransmogUI.CreateLabel(equipped, "GameFontNormal", "Показать надетую экипировку");
	equippedText:SetPoint("LEFT", equipped.Icon, "RIGHT", 8, 0);
	equipped:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue", "ADD");
	equipped:SetScript("OnClick", function()
		self.showEquipped = not self.showEquipped;
		self.selectedOutfit = nil;
		PlaySound("igMainMenuOptionCheckBoxOn");
		TransmogUI.UpdateOutfits(self);
		TransmogUI.UpdatePreview(self);
	end);

	self.outfitButtons = {};
	for index = 1, NUM_OUTFIT_BUTTONS do
		local button = CreateFrame("Button", nil, left);
		button:SetSize(226, 36);
		button:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -84 - (index - 1) * 38);
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
		local bg = button:CreateTexture(nil, "BACKGROUND");
		bg:SetAllPoints();
		bg:SetAtlas("transmog-outfit-card");
		button.Icon = button:CreateTexture(nil, "ARTWORK");
		button.Icon:SetSize(32, 32);
		button.Icon:SetPoint("LEFT", 2, 0);
		button.Name = TransmogUI.CreateLabel(button, "GameFontNormal", "");
		button.Name:SetPoint("TOPLEFT", button.Icon, "TOPRIGHT", 8, -2);
		button.Name:SetPoint("RIGHT", -4, 0);
		button.Name:SetJustifyH("LEFT");
		button.Sub = TransmogUI.CreateLabel(button, "GameFontDisableSmall", "");
		button.Sub:SetPoint("BOTTOMLEFT", button.Icon, "BOTTOMRIGHT", 8, 2);
		button.Selected = button:CreateTexture(nil, "OVERLAY");
		button.Selected:SetAllPoints();
		button.Selected:SetAtlas("transmog-outfit-card-selected");
		button.Selected:Hide();
		button:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue", "ADD");
		button:SetScript("OnClick", function(btn, mouseButton)
			if not btn.outfit then
				return;
			end
			if mouseButton == "RightButton" then
				for i, outfit in ipairs(TransmogOutfits) do
					if outfit == btn.outfit then
						table.remove(TransmogOutfits, i);
						break;
					end
				end
				if self.selectedOutfit == btn.outfit then
					self.selectedOutfit = nil;
				end
				TransmogUI.UpdateOutfits(self);
			else
				PlaySound("igMainMenuOptionCheckBoxOn");
				TransmogUI.LoadOutfit(self, btn.outfit);
				TransmogUI.UpdateOutfits(self);
			end
		end);
		button:SetScript("OnEnter", function(btn)
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT");
			GameTooltip:SetText(btn.outfit and btn.outfit.name or "");
			GameTooltip:AddLine("ЛКМ - примерить образ, ПКМ - удалить.", 0.5, 0.5, 0.5, true);
			GameTooltip:Show();
		end);
		button:SetScript("OnLeave", GameTooltip_Hide);
		self.outfitButtons[index] = button;
	end

	-- прокрутка списка образов
	local function ScrollOutfits(delta)
		local maxOffset = math.max(0, #TransmogOutfits - NUM_OUTFIT_BUTTONS);
		self.outfitOffset = math.max(0, math.min(maxOffset, (self.outfitOffset or 0) - delta));
		TransmogUI.UpdateOutfits(self);
	end
	left:EnableMouseWheel(true);
	left:SetScript("OnMouseWheel", function(_, delta) ScrollOutfits(delta); end);
	self.OutfitScrollUp = TransmogUI.CreateIconButton(left, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up", 20, "Вверх", function() ScrollOutfits(1); end);
	self.OutfitScrollUp:SetPoint("TOPRIGHT", left, "TOPRIGHT", -2, -84);
	self.OutfitScrollDown = TransmogUI.CreateIconButton(left, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up", 20, "Вниз", function() ScrollOutfits(-1); end);
	self.OutfitScrollDown:SetPoint("TOPRIGHT", left, "TOPRIGHT", -2, -84 - NUM_OUTFIT_BUTTONS * 38 + 22);

	-- «Купить ячейку образа» (ретейл) - пока недоступно
	local purchase = CreateFrame("Button", nil, left, "UIPanelButtonTemplate");
	purchase:SetSize(244, 24);
	purchase:SetPoint("BOTTOMLEFT", 8, 44);
	purchase:SetText("|cff20ff20+|r Купить ячейку образа");
	purchase:Disable();

	local saveOutfit = CreateFrame("Button", nil, left, "UIPanelButtonTemplate");
	saveOutfit:SetSize(110, 24);
	saveOutfit:SetPoint("BOTTOMLEFT", 8, 12);
	saveOutfit:SetText("|cffff5050Сохранить образ|r");
	saveOutfit:SetScript("OnClick", function()
		StaticPopup_Show("TRANSMOG_OUTFIT_NAME");
	end);

	local money = CreateFrame("Frame", "TransmogFrameMoneyFrame", left, "SmallMoneyFrameTemplate");
	money:SetPoint("LEFT", saveOutfit, "RIGHT", 10, 0);
	self.MoneyFrame = money;

	-------------------------------------------------------------------
	-- center: character
	-------------------------------------------------------------------
	local center = TransmogUI.CreatePanel(self, CENTER_X1, CENTER_X2, "transmog-locationBG");
	-- фон по расе, как в ретейле (transmog-background-race-*)
	local _, raceFile = UnitRace("player");
	local raceBg = center:CreateTexture(nil, "BACKGROUND", nil, 1);
	raceBg:SetAllPoints();
	raceBg:SetAtlas("transmog-background-race-" .. strlower(raceFile or "human"));
	local glow = center:CreateTexture(nil, "BACKGROUND", nil, 2);
	glow:SetAtlas("transmog-locationBG-glow");
	glow:SetAllPoints();

	local preview = CreateFrame("DressUpModel", "TransmogFramePreview", center);
	preview:SetPoint("TOPLEFT", 70, -50);
	preview:SetPoint("BOTTOMRIGHT", -70, 90);
	preview:EnableMouse(true);
	preview:EnableMouseWheel(true);
	preview:SetScript("OnMouseDown", function(model, button)
		if button == "LeftButton" then
			model.rotating = true;
			model.rotateX = GetCursorPosition();
		end
	end);
	preview:SetScript("OnMouseUp", function(model)
		model.rotating = nil;
	end);
	preview:SetScript("OnUpdate", function(model, elapsed)
		if model.rotating then
			local x = GetCursorPosition();
			model.facing = (model.facing or 0) + (x - model.rotateX) * 0.02;
			model.rotateX = x;
			model:SetFacing(model.facing);
		elseif model.spin then
			model.facing = (model.facing or 0) + model.spin * elapsed * 2;
			model:SetFacing(model.facing);
		end
	end);
	local function Zoom(delta)
		preview.zoom = math.max(0, math.min(2.5, (preview.zoom or 0) + delta * 0.3));
		preview:SetPosition(preview.zoom, 0, 0);
	end
	preview:SetScript("OnMouseWheel", function(_, delta) Zoom(delta); end);
	self.Preview = preview;

	-- панель управления моделью (ретейл: ModelSceneControlFrame)
	local controls = CreateFrame("Frame", nil, center);
	controls:SetSize(5 * 26, 24);
	controls:SetPoint("TOP", center, "TOP", 0, -14);
	local function Control(index, texture, tooltip, onClick, onDown, onUp)
		local button = TransmogUI.CreateIconButton(controls, texture, 22, tooltip, onClick);
		button:SetPoint("LEFT", controls, "LEFT", (index - 1) * 26, 0);
		if onDown then
			button:SetScript("OnMouseDown", onDown);
			button:SetScript("OnMouseUp", onUp);
		end
	end
	Control(1, "common-icon-zoomin", "Приблизить", function() Zoom(1); end);
	Control(2, "common-icon-zoomout", "Отдалить", function() Zoom(-1); end);
	Control(3, "common-icon-rotateleft", "Повернуть влево", nil,
		function() preview.spin = -1; end, function() preview.spin = nil; end);
	Control(4, "common-icon-rotateright", "Повернуть вправо", nil,
		function() preview.spin = 1; end, function() preview.spin = nil; end);
	Control(5, "common-icon-undo", "Сбросить вид", function()
		preview.zoom, preview.facing = 0, 0;
		preview:SetPosition(0, 0, 0);
		preview:SetFacing(0);
	end);

	-- справа сверху: убрать оружие в ножны / отменить все изменения
	local sheathe = TransmogUI.CreateIconButton(center, "Interface\\Icons\\INV_Sword_04", 26, "Показать/убрать оружие", function()
		self.hideWeapons = not self.hideWeapons;
		if self.hideWeapons and preview.UndressSlot then
			preview:UndressSlot(16);
			preview:UndressSlot(17);
			preview:UndressSlot(18);
		else
			TransmogUI.UpdatePreview(self);
		end
	end);
	sheathe:SetPoint("TOPRIGHT", center, "TOPRIGHT", -46, -50);
	local undoAll = TransmogUI.CreateIconButton(center, "transmog-icon-revert", 26, "Отменить все изменения", function()
		wipe(self.pending);
		PlaySound("igMainMenuOptionCheckBoxOff");
		TransmogUI.UpdateSlots(self);
		TransmogUI.UpdatePreview(self);
		TransmogUI.UpdateGrid(self);
	end);
	undoAll:SetPoint("LEFT", sheathe, "RIGHT", 6, 0);
	self.ClearButton = undoAll;

	-- слоты вокруг персонажа
	self.slotButtons = {};
	local leftIndex, rightIndex, bottomIndex = 0, 0, 0;
	for _, info in ipairs(SLOTS) do
		local button = CreateFrame("Button", nil, center, "TransmogSlotButtonTemplate");
		button.info = info;
		if info.side == "LEFT" then
			button:SetPoint("TOPLEFT", center, "TOPLEFT", 30, -100 - leftIndex * 52);
			leftIndex = leftIndex + 1;
		elseif info.side == "RIGHT" then
			button:SetPoint("TOPRIGHT", center, "TOPRIGHT", -30, -230 - rightIndex * 52);
			rightIndex = rightIndex + 1;
		else
			button:SetPoint("BOTTOM", center, "BOTTOM", (bottomIndex - 1) * 56, 70);
			bottomIndex = bottomIndex + 1;
		end
		table.insert(self.slotButtons, button);
	end

	-- иллюзии оружия (в 3.3.5 нет) - как в ретейле, перечёркнутые ячейки под оружием
	for index = 1, 2 do
		local illusion = CreateFrame("Frame", nil, center);
		illusion:SetSize(28, 28);
		illusion:SetPoint("BOTTOM", center, "BOTTOM", (index - 2) * 56, 36);
		local frame = illusion:CreateTexture(nil, "BACKGROUND");
		frame:SetAllPoints();
		frame:SetAtlas("transmog-gearSlot-disabled-small");
		local icon = illusion:CreateTexture(nil, "ARTWORK");
		icon:SetSize(16, 16);
		icon:SetPoint("CENTER");
		icon:SetAtlas("transmog-icon-disabled-small");
	end

	local apply = CreateFrame("Button", nil, center, "UIPanelButtonTemplate");
	apply:SetSize(150, 26);
	apply:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -12, 12);
	apply:SetText("Применить");
	apply:SetScript("OnClick", function() TransmogFrame_Apply(self); end);
	self.ApplyButton = apply;

	-------------------------------------------------------------------
	-- right: wardrobe collection with tabs
	-------------------------------------------------------------------
	local right = TransmogUI.CreatePanel(self, RIGHT_X1, RIGHT_X2, "transmog-outfit-darkBG");
	self.Wardrobe = right;

	local content = CreateFrame("Frame", "TransmogFrameWardrobeContent", right, "CollectionsBackgroundTemplate");
	content:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -40);
	content:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -6, 6);
	-- ретейл: TabContent - transmog-tabs-frame-BG + рамка transmog-tabs-frame
	local tabsBg = content:CreateTexture(nil, "BACKGROUND", nil, 3);
	tabsBg:SetAllPoints();
	tabsBg:SetAtlas("transmog-tabs-frame-BG");
	local tabsFrame = content:CreateTexture(nil, "BORDER");
	tabsFrame:SetAllPoints();   -- рамка внутри панели, не вылезает за окно
	tabsFrame:SetAtlas("transmog-tabs-frame");

	-- TabSystem сверху (TabSystemTopButtonTemplate)
	Mixin(right, TabSystemOwnerMixin);
	TabSystemOwnerMixin.OnLoad(right);
	local tabs = CreateFrame("Frame", nil, right, "TabSystemTemplate");
	tabs.tabTemplate = "TabSystemTopButtonTemplate";
	tabs.tabPool = CreateFramePool("BUTTON", tabs, "TabSystemTopButtonTemplate");
	tabs.minTabWidth, tabs.maxTabWidth = 90, 150;
	tabs:SetPoint("BOTTOMLEFT", content, "TOPLEFT", 16, -2);
	right:SetTabSystem(tabs);

	local items = CreateFrame("Frame", nil, content);
	items:SetAllPoints();
	local itemsTab = right:AddNamedTab("Предметы", items);
	right:AddNamedTab("Наборы", TransmogUI.CreateStubTab(content, "Комплекты для трансмогрификации появятся вместе с серверной частью."));
	right:AddNamedTab("Свои наборы", TransmogUI.CreateStubTab(content, "Свои наборы появятся вместе с серверной частью."));
	right:AddNamedTab("Ситуации", TransmogUI.CreateStubTab(content, "Смена образа по ситуациям (бой, верховая езда...) появится позже."));
	right:SetTab(itemsTab);

	self.SlotTitle = TransmogUI.CreateLabel(items, "GameFontNormalHuge", "");
	self.SlotTitle:SetPoint("TOPLEFT", 16, -14);

	local searchBox = CreateFrame("EditBox", "TransmogFrameSearchBox", items, "SearchBoxTemplate");
	searchBox:SetSize(140, 20);
	searchBox:SetPoint("TOPRIGHT", items, "TOPRIGHT", -110, -14);
	searchBox:HookScript("OnTextChanged", function(box)
		local text = box:GetText() or "";
		if text == (SEARCH or "") then
			text = "";
		end
		if text ~= (self.searchText or "") then
			self.searchText = text;
			self.searchDelay = 0.4;
		end
	end);

	-- фильтр - такой же, как во «Внешнем виде» коллекций; источники пока без функций (сервер позже)
	local SOURCES = { "Добыча с боссов", "Задание", "Торговец", "Мировая добыча", "Достижение", "Профессия" };
	self.sourceFilters = {};
	for index in ipairs(SOURCES) do
		self.sourceFilters[index] = true;
	end
	local filter = CreateFrame("Button", "TransmogFrameFilterDropdown", items, "WowStyle1FilterDropdownTemplate");
	filter:SetPoint("LEFT", searchBox, "RIGHT", 8, 0);
	filter:SetIsDefaultCallback(function()
		if self.showUncollected then
			return false;
		end
		for _, on in pairs(self.sourceFilters) do
			if not on then
				return false;
			end
		end
		return true;
	end);
	filter:SetDefaultCallback(function()
		self.showUncollected = false;
		for index in ipairs(SOURCES) do
			self.sourceFilters[index] = true;
		end
		self.page = 1;
		TransmogUI.RequestPage(self);
	end);
	filter:SetupMenu(function(dropdown, rootDescription)
		rootDescription:CreateCheckbox("Собранные", function() return true; end, function() end);
		rootDescription:CreateCheckbox("Не собранные", function() return self.showUncollected; end, function()
			self.showUncollected = not self.showUncollected;
			filter:ValidateResetState();
			self.page = 1;
			TransmogUI.RequestPage(self);
		end);
		local sources = rootDescription:CreateSubmenu("Источники");
		for index, name in ipairs(SOURCES) do
			sources:CreateCheckbox(name, function() return self.sourceFilters[index]; end, function()
				self.sourceFilters[index] = not self.sourceFilters[index];
				filter:ValidateResetState();
			end);
		end
	end);

	-- «Не назначено» / «Показать надетую экипировку» для выбранного слота
	local function DisplayTypeButton(text, icon, onClick)
		local button = CreateFrame("Button", nil, items);
		button:SetSize(170, 28);
		local bg = button:CreateTexture(nil, "BACKGROUND");
		bg:SetAllPoints();
		bg:SetAtlas("transmog-outfit-card");
		local tex = button:CreateTexture(nil, "ARTWORK");
		tex:SetSize(22, 22);
		tex:SetPoint("LEFT", 4, 0);
		if icon:find("\\") then
			tex:SetTexture(icon);
		else
			tex:SetAtlas(icon);
		end
		local label = TransmogUI.CreateLabel(button, "GameFontNormal", text);
		label:SetPoint("LEFT", tex, "RIGHT", 6, 0);
		button:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD");
		button:SetScript("OnClick", onClick);
		return button;
	end
	local unassigned = DisplayTypeButton("Не назначено", "transmog-icon-disabled", function()
		if self.selectedSlot then
			self.pending[self.selectedSlot] = nil;     -- слот не меняется
			TransmogUI.UpdateSlots(self);
			TransmogUI.UpdatePreview(self);
			TransmogUI.UpdateGrid(self);
		end
	end);
	unassigned:SetPoint("TOPLEFT", items, "TOPLEFT", 16, -52);
	local showEquipped = DisplayTypeButton("Надетая экипировка", "Interface\\Icons\\INV_Chest_Chain_15", function()
		local slotId = self.selectedSlot;
		if slotId then
			self.pending[slotId] = self.applied[slotId] and 0 or nil;   -- собственный облик предмета
			TransmogUI.UpdateSlots(self);
			TransmogUI.UpdatePreview(self);
			TransmogUI.UpdateGrid(self);
		end
	end);
	showEquipped:SetPoint("LEFT", unassigned, "RIGHT", 12, 0);

	-- сетка обликов 6x4
	self.gridModels = {};
	local gridWidth = GRID_COLUMNS * MODEL_WIDTH + (GRID_COLUMNS - 1) * MODEL_SPACE_X;
	local startX = ((RIGHT_X2 - RIGHT_X1 - 12) - gridWidth) / 2;
	for row = 1, GRID_ROWS do
		for column = 1, GRID_COLUMNS do
			local model = CreateFrame("DressUpModel", nil, items, "TransmogItemModelTemplate");
			model:SetPoint("TOPLEFT", items, "TOPLEFT", startX + (column - 1) * (MODEL_WIDTH + MODEL_SPACE_X), -96 - (row - 1) * (MODEL_HEIGHT + MODEL_SPACE_Y));
			model:Hide();
			table.insert(self.gridModels, model);
		end
	end

	self.GridMessage = TransmogUI.CreateLabel(items, "GameFontHighlightLarge", "");
	self.GridMessage:SetPoint("CENTER", items, "CENTER", 0, 20);

	local paging = CreateFrame("Frame", nil, items);
	paging:SetSize(160, 32);
	paging:SetPoint("BOTTOM", items, "BOTTOM", 20, 14);
	paging.Text = TransmogUI.CreateLabel(paging, "GameFontHighlight", "");
	paging.Text:SetPoint("RIGHT", paging, "RIGHT", -72, 0);
	local function PageButton(prev)
		local button = CreateFrame("Button", nil, paging);
		button:SetSize(32, 32);
		local base = prev and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-";
		button:SetNormalTexture(base .. "Up");
		button:SetPushedTexture(base .. "Down");
		button:SetDisabledTexture(base .. "Disabled");
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
		return button;
	end
	paging.Prev = PageButton(true);
	paging.Prev:SetPoint("RIGHT", paging, "RIGHT", -34, 0);
	paging.Next = PageButton(false);
	paging.Next:SetPoint("RIGHT", paging, "RIGHT", 0, 0);
	local function SetPage(page)
		if page < 1 or page > (self.numPages or 1) or page == self.page then
			return;
		end
		self.page = page;
		PlaySound("igAbiliityPageTurn");
		TransmogUI.RequestPage(self);
	end
	paging.Prev:SetScript("OnClick", function() SetPage((self.page or 1) - 1); end);
	paging.Next:SetScript("OnClick", function() SetPage((self.page or 1) + 1); end);
	items:EnableMouseWheel(true);
	items:SetScript("OnMouseWheel", function(_, delta) SetPage((self.page or 1) - delta); end);
	self.Paging = paging;

	self:SetScript("OnUpdate", function(frame, elapsed)
		if frame.searchDelay then
			frame.searchDelay = frame.searchDelay - elapsed;
			if frame.searchDelay <= 0 then
				frame.searchDelay = nil;
				frame.page = 1;
				TransmogUI.RequestPage(frame);
			end
		end
		if frame.requestElapsed then
			frame.requestElapsed = frame.requestElapsed + elapsed;
			if frame.requestElapsed > 3 then
				frame.requestElapsed = nil;
				if frame.waiting then
					frame.noAnswer = true;
					TransmogUI.UpdateGrid(frame);
				end
			end
		end
		if frame.applyElapsed then
			frame.applyElapsed = frame.applyElapsed + elapsed;
			if frame.applyElapsed > 3 then
				frame.applyElapsed = nil;
				UIErrorsFrame:AddMessage("Сервер пока не поддерживает трансмогрификацию.", 1.0, 0.1, 0.1, 1.0);
			end
		end
	end);

	self:RegisterEvent("UNIT_INVENTORY_CHANGED");
end

function TransmogFrame_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	wipe(self.pending);
	if Comm_Send then
		Comm_Send(OP_GET_STATE);
	end
	TransmogUI.UpdateOutfits(self);
	TransmogUI.UpdateSlots(self);
	TransmogUI.UpdatePreview(self);
	if not self.selectedSlot then
		for _, info in ipairs(SLOTS) do
			if GetInventoryItemLink("player", info.id) then
				TransmogFrame_SelectSlot(self, info.id);
				break;
			end
		end
	else
		TransmogUI.RequestPage(self);
	end
end

function TransmogFrame_OnHide(self)
	PlaySound("igCharacterInfoClose");
	StaticPopup_Hide("TRANSMOG_OUTFIT_NAME");
end

function TransmogFrame_OnEvent(self, event, unit)
	if event == "UNIT_INVENTORY_CHANGED" and unit == "player" and self:IsShown() then
		TransmogUI.UpdateSlots(self);
		TransmogUI.UpdatePreview(self);
	end
end

function TransmogFrame_Apply(self)
	if not TransmogUI.HasPending(self) then
		return;
	end
	local cost = TransmogUI.GetCost(self);
	if cost > GetMoney() then
		UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or "Недостаточно денег.", 1.0, 0.1, 0.1, 1.0);
		return;
	end
	local list = {};
	for slotId, itemId in pairs(self.pending) do
		table.insert(list, slotId .. "/" .. itemId);
	end
	if Comm_Send then
		Comm_Send(OP_APPLY, table.concat(list, ","));
	end
	self.applyElapsed = 0;
end

---------------------------------------------------------------------------
-- server messages
---------------------------------------------------------------------------
function TransmogUI.ParseSlots(text)
	local slots = {};
	for slotId, itemId in (text or ""):gmatch("(%d+)/(%d+)") do
		itemId = tonumber(itemId);
		if itemId and itemId > 0 then
			slots[tonumber(slotId)] = itemId;
		end
	end
	return slots;
end

if Comm_Register then
	Comm_Register(OP_STATE, function(text)
		TransmogFrame.applied = TransmogUI.ParseSlots(text);
		if TransmogFrame:IsShown() then
			TransmogUI.UpdateSlots(TransmogFrame);
			TransmogUI.UpdatePreview(TransmogFrame);
		end
	end);

	Comm_Register(OP_RESULT, function(ok, message)
		local frame = TransmogFrame;
		frame.applyElapsed = nil;
		if ok == "1" then
			for slotId, itemId in pairs(frame.pending) do
				frame.applied[slotId] = (itemId ~= 0) and itemId or nil;
			end
			wipe(frame.pending);
			PlaySound("igQuestListComplete");
		elseif message and message ~= "" then
			UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0);
		end
		if frame:IsShown() then
			TransmogUI.UpdateSlots(frame);
			TransmogUI.UpdatePreview(frame);
			TransmogUI.UpdateGrid(frame);
		end
	end);

	Comm_Register(OP_OPEN, function()
		TransmogFrame:Show();
	end);

	Comm_Register(OP_CLOSE, function()
		TransmogFrame:Hide();
	end);

	Comm_Register(OP_PAGE, function(category, page, numPages, collected, total, entriesText, tag)
		if tag ~= "T" then
			return;
		end
		local frame = TransmogFrame;
		if tonumber(category) ~= frame.category then
			return;
		end
		frame.waiting, frame.noAnswer, frame.requestElapsed = false, nil, nil;
		frame.page = tonumber(page) or 1;
		frame.numPages = tonumber(numPages) or 1;
		frame.entries = {};
		for displayId, itemId, isCollected in (entriesText or ""):gmatch("(%d+)/(%d+)/(%d)") do
			table.insert(frame.entries, { displayId = tonumber(displayId), itemId = tonumber(itemId), collected = isCollected == "1" });
		end
		if frame:IsShown() then
			TransmogUI.UpdateGrid(frame);
		end
	end);
end

-- без сервера окно открывается так (у NPC его откроет сервер)
SLASH_TRANSMOG1 = "/transmog";
SlashCmdList["TRANSMOG"] = function()
	if TransmogFrame:IsShown() then
		TransmogFrame:Hide();
	else
		TransmogFrame:Show();
	end
end
