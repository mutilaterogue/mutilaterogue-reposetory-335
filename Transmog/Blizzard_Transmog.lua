-- Transmogrification window (retail 12.x TransmogFrame, simplified) for 3.3.5.
-- Left: outfits, center: the character with slot buttons, right: collected appearances of the slot.
-- The interface works on its own; the server part comes later. Opcodes (names; requests differ
-- from answers, the client also receives its own addon whisper):
--   "TMOG_GET_STATE"            -> "TMOG_STATE" : "slot/itemId,..."        current transmogs
--   "TMOG_APPLY" : "slot/itemId,..." (itemId 0 = restore) -> "TMOG_RESULT" : ok(1/0) : error string name : itemId
--   "TMOG_OPEN" / "TMOG_CLOSE"  server opens/closes the window (NPC transmogrifier)
--   "APPEAR_GET_PAGE" ... : "T" -> "APPEAR_PAGE" ... : "T"   appearances (appearance_collection.cpp)
-- Without the server: /transmog opens the window, "Apply" says the server does not answer.

-- масштаб окна (ретейловское окно 1618x883)
local TRANSMOG_FRAME_SCALE = 0.75

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
				model.Border.Card:SetAtlas("transmog-itemCard-current", true);
			elseif entry.itemId == (self.selectedSlot and self.applied[self.selectedSlot]) then
				model.Border.Card:SetAtlas("transmog-itemCard-transmogrified", true);
			else
				model.Border.Card:SetAtlas("transmog-itemCard-default", true);
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
	paging.Text:SetFormattedText(PAGE_NUMBER_WITH_MAX or "Стр. %d/%d", self.page or 1, self.numPages or 1);
	paging.Prev:SetEnabled((self.page or 1) > 1);
	paging.Next:SetEnabled((self.page or 1) < (self.numPages or 1));

	if not self.selectedSlot then
		self.GridMessage:SetText("Выберите слот на персонаже");
		self.GridMessage:Show();
	elseif not self.category then
		self.GridMessage:SetText(TRANSMOG_SLOT_WARNING_INVALID_EQUIPPED_DESTINATION_ITEM);
		self.GridMessage:Show();
	elseif #self.entries == 0 then
		self.GridMessage:SetText(self.waiting and (self.noAnswer and "Сервер не ответил" or SEARCH_LOADING_TEXT or "Загрузка...") or TRANSMOGRIFY_STYLE_UNCOLLECTED);
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

---------------------------------------------------------------------------
-- XML handlers (разметка - Blizzard_Transmog.xml)
---------------------------------------------------------------------------
function TransmogPreview_Zoom(delta)
	local model = TransmogFramePreview;
	model.zoom = math.max(0, math.min(2.5, (model.zoom or 0) + delta * 0.3));
	model:SetPosition(model.zoom, 0, 0);
end

function TransmogPreview_Reset()
	local model = TransmogFramePreview;
	model.zoom, model.facing = 0, 0;
	model:SetPosition(0, 0, 0);
	model:SetFacing(0);
end

function TransmogPreview_OnMouseDown(self, button)
	if button == "LeftButton" then
		self.rotating = true;
		self.rotateX = GetCursorPosition();
	end
end

function TransmogPreview_OnMouseUp(self)
	self.rotating = nil;
end

function TransmogPreview_OnMouseWheel(self, delta)
	TransmogPreview_Zoom(delta);
end

function TransmogPreview_OnUpdate(self, elapsed)
	if self.rotating then
		local x = GetCursorPosition();
		self.facing = (self.facing or 0) + (x - self.rotateX) * 0.02;
		self.rotateX = x;
		self:SetFacing(self.facing);
	elseif self.spin then
		self.facing = (self.facing or 0) + self.spin * elapsed * 2;
		self:SetFacing(self.facing);
	end
end

-- ретейл: ShowEquippedGearSpellFrame - убрать все трансмогрификации (в очередь изменений)
function TransmogFrame_ToggleShowEquipped()
	local frame = TransmogFrame;
	wipe(frame.pending);
	for slotId in pairs(frame.applied) do
		frame.pending[slotId] = 0;
	end
	frame.selectedOutfit = nil;
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogUI.UpdateOutfits(frame);
	TransmogUI.UpdateSlots(frame);
	TransmogUI.UpdatePreview(frame);
	TransmogUI.UpdateGrid(frame);
end

function TransmogFrame_ToggleWeapons()
	local frame = TransmogFrame;
	local model = frame.Preview;
	frame.hideWeapons = not frame.hideWeapons;
	if frame.hideWeapons and model.UndressSlot then
		model:UndressSlot(16);
		model:UndressSlot(17);
		model:UndressSlot(18);
	else
		TransmogUI.UpdatePreview(frame);
	end
end

local function RefreshAll(frame)
	TransmogUI.UpdateSlots(frame);
	TransmogUI.UpdatePreview(frame);
	TransmogUI.UpdateGrid(frame);
end

function TransmogFrame_ClearAllPending()
	wipe(TransmogFrame.pending);
	PlaySound("igMainMenuOptionCheckBoxOff");
	RefreshAll(TransmogFrame);
end

-- DisplayTypes: «Не назначено» - убрать изменение слота, «Надетая экипировка» - вернуть облик предмета
function TransmogFrame_ClearSlotPending()
	local frame = TransmogFrame;
	if frame.selectedSlot then
		frame.pending[frame.selectedSlot] = nil;
		RefreshAll(frame);
	end
end

function TransmogFrame_RestoreSlot()
	local frame = TransmogFrame;
	local slotId = frame.selectedSlot;
	if slotId then
		frame.pending[slotId] = frame.applied[slotId] and 0 or nil;
		RefreshAll(frame);
	end
end

function TransmogFrame_SetPage(self, page)
	if page < 1 or page > (self.numPages or 1) or page == self.page then
		return;
	end
	self.page = page;
	PlaySound("igAbiliityPageTurn");
	TransmogUI.RequestPage(self);
end

-- FilterButton - как во «Внешнем виде»; источники пока без функций
local SOURCES = { TRANSMOG_SOURCE_1, TRANSMOG_SOURCE_2, TRANSMOG_SOURCE_3, TRANSMOG_SOURCE_4, TRANSMOG_SOURCE_5, TRANSMOG_SOURCE_6 };

local function SetupFilter(self, filter)
	self.sourceFilters = {};
	for i in ipairs(SOURCES) do
		self.sourceFilters[i] = true;
	end
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
		for i in ipairs(SOURCES) do
			self.sourceFilters[i] = true;
		end
		self.page = 1;
		TransmogUI.RequestPage(self);
	end);
	filter:SetupMenu(function(dropdown, rootDescription)
		rootDescription:CreateCheckbox(TRANSMOG_COLLECTED, function() return true; end, function() end);
		rootDescription:CreateCheckbox(TRANSMOG_NOT_COLLECTED, function() return self.showUncollected; end, function()
			self.showUncollected = not self.showUncollected;
			filter:ValidateResetState();
			self.page = 1;
			TransmogUI.RequestPage(self);
		end);
		rootDescription:CreateDivider();
		rootDescription:CreateTitle(SOURCES_LABEL or "Источники");
		for i, name in ipairs(SOURCES) do
			rootDescription:CreateCheckbox(name, function() return self.sourceFilters[i]; end, function()
				self.sourceFilters[i] = not self.sourceFilters[i];
				filter:ValidateResetState();
			end);
		end
	end);
end

local function SetupTabs(wardrobe)
	local content = wardrobe.TabContent;
	local tabs = wardrobe.TabHeaders;
	if not tabs.tabPool then
		tabs.tabPool = CreateFramePool("BUTTON", tabs, tabs.tabTemplate or "TabSystemTopButtonTemplate");
	end
	TabSystemOwnerMixin.OnLoad(wardrobe);
	wardrobe:SetTabSystem(tabs);
	tabs:SetFrameLevel(content:GetFrameLevel() + 5);
	local itemsTab = wardrobe:AddNamedTab(TRANSMOG_TAB_ITEMS, content.ItemsFrame);
	wardrobe:AddNamedTab(TRANSMOG_TAB_SETS, content.SetsFrame);
	wardrobe:AddNamedTab(TRANSMOG_TAB_CUSTOM_SETS, content.CustomSetsFrame);
	wardrobe:AddNamedTab(TRANSMOG_TAB_SITUATIONS, content.SituationsFrame);
	wardrobe:SetTab(itemsTab);
end

function TransmogFrame_OnLoad(self)
	self.pending = {};
	self.applied = {};
	self.entries = {};
	tinsert(UISpecialFrames, self:GetName());
	self:RegisterForDrag("LeftButton");
	-- ретейловское окно 1618x883: масштаб как у PlayerSpellsFrame
	self:SetScale(TRANSMOG_FRAME_SCALE);

	if self.TitleContainer and self.TitleContainer.TitleText then
		self.TitleContainer.TitleText:SetText(TRANSMOGRIFY);
	end
	if self.PortraitContainer and self.PortraitContainer.portrait then
		SetPortraitToTexture(self.PortraitContainer.portrait, "Interface\\Icons\\INV_Arcane_Orb");
	end
	if self.SetFrameLevelsFromBaseLevel then
		self:SetFrameLevelsFromBaseLevel(self:GetFrameLevel());
	end

	-- OutfitCollection
	local outfits = self.OutfitCollection;
	self.EquippedActive = outfits.ShowEquippedGear.Active;
	self.MoneyFrame = TransmogFrameMoneyFrame;
	self.outfitButtons = {};
	for index = 1, NUM_OUTFIT_BUTTONS do
		self.outfitButtons[index] = _G[outfits.OutfitList:GetName() .. "Entry" .. index];
	end
	outfits.PurchaseOutfitButton:SetScript("OnClick", TransmogFrame_PurchaseOutfitSlot);
	outfits.PurchaseOutfitButton:SetScript("OnEnter", TransmogFrame_PurchaseOutfitSlot_OnEnter);
	outfits.PurchaseOutfitButton:SetScript("OnLeave", GameTooltip_Hide);
	outfits.PurchaseOutfitButton:SetMotionScriptsWhileDisabled(true);
	outfits.SaveOutfitButton:SetScript("OnEnter", TransmogFrame_SaveOutfit_OnEnter);
	outfits.SaveOutfitButton:SetScript("OnLeave", GameTooltip_Hide);

	-- CharacterPreview
	local preview = self.CharacterPreview;
	local _, raceFile = UnitRace("player");
	preview.Background:SetAtlas("transmog-background-race-" .. strlower(raceFile or "human"));
	TransmogUI.FlipAtlasHorizontal(preview.GradientRight, "transmog-outfit-darkBG-gradient");
	self.Preview = TransmogFramePreview;
	self.ApplyButton = preview.ApplyButton;
	self.ClearButton = preview.ClearAllPendingButton;
	self.slotButtons = {};
	for _, info in ipairs(SLOTS) do
		local button = _G[preview:GetName() .. info.slot];
		button.info = info;
		table.insert(self.slotButtons, button);
	end
	-- всё, что над моделью, - выше неё
	local overLevel = self.Preview:GetFrameLevel() + 5;
	for _, child in ipairs({ preview:GetChildren() }) do
		if child ~= self.Preview then
			child:SetFrameLevel(overLevel);
		end
	end

	-- WardrobeCollection
	local wardrobe = self.WardrobeCollection;
	local items = wardrobe.TabContent.ItemsFrame;
	SetupTabs(wardrobe);
	self.SlotTitle = items.SlotTitle;
	self.GridMessage = items.GridMessageFrame.Text;
	local paging = items.PagingControls;
	paging.Prev, paging.Next = paging.PrevPageButton, paging.NextPageButton;
	self.Paging = paging;
	self.gridModels = {};
	for index = 1, GRID_COLUMNS * GRID_ROWS do
		self.gridModels[index] = _G[items:GetName() .. "Model" .. index];
	end

	SetupFilter(self, items.FilterButton);
	items.SearchBox:HookScript("OnTextChanged", function(box)
		local text = box:GetText() or "";
		if text == (SEARCH or "") then
			text = "";
		end
		if text ~= (self.searchText or "") then
			self.searchText = text;
			self.searchDelay = 0.4;
		end
	end);

	self:RegisterEvent("UNIT_INVENTORY_CHANGED");
end

function TransmogFrame_OnUpdate(self, elapsed)
	if self.searchDelay then
		self.searchDelay = self.searchDelay - elapsed;
		if self.searchDelay <= 0 then
			self.searchDelay = nil;
			self.page = 1;
			TransmogUI.RequestPage(self);
		end
	end
	if self.requestElapsed then
		self.requestElapsed = self.requestElapsed + elapsed;
		if self.requestElapsed > 3 then
			self.requestElapsed = nil;
			if self.waiting then
				self.noAnswer = true;
				TransmogUI.UpdateGrid(self);
			end
		end
	end
	if self.applyElapsed then
		self.applyElapsed = self.applyElapsed + elapsed;
		if self.applyElapsed > 3 then
			self.applyElapsed = nil;
			UIErrorsFrame:AddMessage("Сервер не ответил.", 1.0, 0.1, 0.1, 1.0);
		end
	end
end

function TransmogFrame_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	wipe(self.pending);
	if Comm_Send then
		Comm_Send(OP_GET_STATE);
		Comm_Send(TransmogUI.OP_OUTFITS_GET);
	end
	TransmogUI.setsStale = true;
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
	StaticPopup_Hide("TRANSMOG_OUTFIT_DELETE");
	StaticPopup_Hide("TRANSMOG_OUTFIT_BUY");
	StaticPopup_Hide("TRANSMOG_CUSTOM_SET_NAME");
	StaticPopup_Hide("TRANSMOG_CUSTOM_SET_DELETE");
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
		UIErrorsFrame:AddMessage(ERR_TRANSMOG_OUTFIT_SLOT_CANNOT_AFFORD, 1.0, 0.1, 0.1, 1.0);
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
			TransmogUI.UpdateOutfits(TransmogFrame);
		end
	end);

	-- ok : имя строки ошибки (ERR_TRANSMOGRIFY_* ...) : itemId для "%s"
	Comm_Register(OP_RESULT, function(ok, errorName, errorItem)
		local frame = TransmogFrame;
		frame.applyElapsed = nil;
		if ok == "1" then
			for slotId, itemId in pairs(frame.pending) do
				frame.applied[slotId] = (itemId ~= 0) and itemId or nil;
			end
			wipe(frame.pending);
			PlaySound("igQuestListComplete");
		end
		local message = TransmogUI.GetErrorText(errorName, errorItem);
		if message then
			if ok == "1" then
				UIErrorsFrame:AddMessage(message, 1.0, 0.82, 0.0, 1.0);   -- сохранено, но с предупреждением
			else
				UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0);
			end
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
