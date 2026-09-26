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

-- Разметка по ретейлу 12.x (Blizzard_Transmog.xml): окно 1618x883,
-- OutfitCollection 312 | CharacterPreview 658 | WardrobeCollection 644, высота панелей 860.
local function Tex(parent, layer, atlas, useSize, subLevel)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel or 0);
	texture:SetAtlas(atlas, useSize);
	return texture;
end

local function AtlasButton(parent, width, height, normal, pushed, disabled)
	local button = CreateFrame("Button", nil, parent);
	button:SetSize(width, height);
	local n = Tex(button, "BACKGROUND", normal);
	n:SetAllPoints();
	button.NormalTex = n;
	local h = Tex(button, "HIGHLIGHT", normal);
	h:SetAllPoints();
	h:SetBlendMode("ADD");
	button:SetScript("OnMouseDown", function(btn) if pushed and btn:IsEnabled() == 1 then n:SetAtlas(pushed); end end);
	button:SetScript("OnMouseUp", function() n:SetAtlas(normal); end);
	button.SetAtlasEnabled = function(btn, enabled)
		btn:SetEnabled(enabled);
		n:SetAtlas(enabled and normal or (disabled or normal));
	end;
	return button;
end

local function Tooltip(frame, text)
	frame:SetScript("OnEnter", function(owner)
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT");
		GameTooltip:SetText(text);
		GameTooltip:Show();
	end);
	frame:SetScript("OnLeave", GameTooltip_Hide);
end

function TransmogFrame_OnLoad(self)
	self.pending = {};
	self.applied = {};
	self.entries = {};
	tinsert(UISpecialFrames, self:GetName());
	self:RegisterForDrag("LeftButton");
	-- ретейловское окно 1618x883: масштаб как у PlayerSpellsFrame
	self:SetScale(TRANSMOG_FRAME_SCALE or 0.62);

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
	-- OutfitCollection
	-------------------------------------------------------------------
	local outfits = CreateFrame("Frame", nil, self);
	outfits:SetSize(312, 860);
	outfits:SetPoint("TOPLEFT", 2, -21);
	Tex(outfits, "BACKGROUND", "transmog-outfit-darkBG"):SetAllPoints();
	Tex(outfits, "BACKGROUND", "transmog-outfit-toptexture", true, 1):SetPoint("TOP");
	Tex(outfits, "BACKGROUND", "transmog-outfit-bottomtexture", true, 1):SetPoint("BOTTOM");
	local dividerBar = Tex(outfits, "BACKGROUND", "transmog-outfit-darkBG-cornerLine", false, 2);
	dividerBar:SetSize(6, 860);
	dividerBar:SetPoint("TOPRIGHT", 2, 0);

	-- ShowEquippedGearSpellFrame (280x45 at 14,-44)
	local equipped = CreateFrame("Button", nil, outfits);
	equipped:SetSize(280, 45);
	equipped:SetPoint("TOPLEFT", 14, -44);
	local eqIcon = equipped:CreateTexture(nil, "ARTWORK");
	eqIcon:SetSize(36, 36);
	eqIcon:SetPoint("LEFT", 5, 0);
	eqIcon:SetTexture("Interface\\Icons\\INV_Chest_Chain_15");
	local eqBorder = Tex(equipped, "OVERLAY", "transmog-outfit-spellFrame", true);
	eqBorder:SetPoint("CENTER", eqIcon);
	self.EquippedActive = Tex(equipped, "OVERLAY", "transmog-outfit-spellFrame-active", true, 1);
	self.EquippedActive:SetPoint("CENTER", eqIcon);
	self.EquippedActive:Hide();
	local eqText = TransmogUI.CreateLabel(equipped, "GameFontNormal", "Показать надетую экипировку");
	eqText:SetPoint("LEFT", eqIcon, "RIGHT", 12, 0);
	equipped:SetScript("OnClick", function()
		self.showEquipped = not self.showEquipped;
		self.selectedOutfit = nil;
		self.EquippedActive:SetShown(self.showEquipped);
		PlaySound("igMainMenuOptionCheckBoxOn");
		TransmogUI.UpdateOutfits(self);
		TransmogUI.UpdatePreview(self);
	end);

	-- OutfitList (300x650 at 5,-102)
	local list = CreateFrame("Frame", nil, outfits);
	list:SetSize(300, 650);
	list:SetPoint("TOPLEFT", 5, -102);
	Tex(list, "ARTWORK", "transmog-outfit-dividerLine", true):SetPoint("TOP");
	Tex(list, "ARTWORK", "transmog-outfit-dividerLine", true):SetPoint("BOTTOM");

	-- TransmogOutfitEntryTemplate: иконка 45x45 в spellframe + карточка 208x43
	self.outfitButtons = {};
	for index = 1, NUM_OUTFIT_BUTTONS do
		local entry = CreateFrame("Button", nil, list);
		entry:SetSize(260, 45);
		entry:SetPoint("TOPLEFT", list, "TOPLEFT", 5, -4 - (index - 1) * 48);
		entry:RegisterForClicks("LeftButtonUp", "RightButtonUp");
		entry.Icon = entry:CreateTexture(nil, "ARTWORK");
		entry.Icon:SetSize(36, 36);
		entry.Icon:SetPoint("LEFT", 5 + 4, 0);
		Tex(entry, "OVERLAY", "transmog-outfit-spellFrame", true):SetPoint("CENTER", entry.Icon);
		local card = Tex(entry, "BACKGROUND", "transmog-outfit-card");
		card:SetSize(208, 43);
		card:SetPoint("LEFT", entry.Icon, "RIGHT", 7, 0);
		entry.Selected = Tex(entry, "BORDER", "transmog-outfit-card-selected");
		entry.Selected:SetAllPoints(card);
		entry.Selected:Hide();
		local highlight = Tex(entry, "HIGHLIGHT", "transmog-outfit-card");
		highlight:SetAllPoints(card);
		highlight:SetBlendMode("ADD");
		entry.Name = TransmogUI.CreateLabel(entry, "GameFontNormal", "");
		entry.Name:SetPoint("LEFT", card, "LEFT", 10, 6);
		entry.Name:SetPoint("RIGHT", card, "RIGHT", -8, 6);
		entry.Name:SetJustifyH("LEFT");
		entry.Sub = TransmogUI.CreateLabel(entry, "GameFontDisableSmall", "");
		entry.Sub:SetPoint("TOPLEFT", entry.Name, "BOTTOMLEFT", 0, -1);
		entry:SetScript("OnClick", function(btn, mouseButton)
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
				self.EquippedActive:Hide();
				TransmogUI.LoadOutfit(self, btn.outfit);
				TransmogUI.UpdateOutfits(self);
			end
		end);
		entry:SetScript("OnEnter", function(btn)
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT");
			GameTooltip:SetText(btn.outfit and btn.outfit.name or "");
			GameTooltip:AddLine("ЛКМ - примерить образ, ПКМ - удалить.", 0.5, 0.5, 0.5, true);
			GameTooltip:Show();
		end);
		entry:SetScript("OnLeave", GameTooltip_Hide);
		self.outfitButtons[index] = entry;
	end
	list:EnableMouseWheel(true);
	list:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #TransmogOutfits - NUM_OUTFIT_BUTTONS);
		self.outfitOffset = math.max(0, math.min(maxOffset, (self.outfitOffset or 0) - delta));
		TransmogUI.UpdateOutfits(self);
	end);

	-- PurchaseOutfitButton (287x41 под списком) - пока недоступно
	local purchase = AtlasButton(outfits, 287, 41, "common-button-tertiary-normal", "common-button-tertiary-pressed", "common-button-tertiary-disabled");
	purchase:SetPoint("TOP", list, "BOTTOM", -3, -10);
	Tex(purchase, "ARTWORK", "transmog-icon-add", true):SetPoint("LEFT", 14, 0);
	local purchaseText = TransmogUI.CreateLabel(purchase, "GameFontNormal", "Купить ячейку образа");
	purchaseText:SetPoint("LEFT", 42, 1);
	purchase:SetAtlasEnabled(false);
	purchaseText:SetTextColor(0.5, 0.5, 0.5);

	-- SaveOutfitButton (128x28 at 9,14) + MoneyFrame (152x24)
	local saveOutfit = CreateFrame("Button", nil, outfits, "UIPanelButtonTemplate");
	saveOutfit:SetSize(128, 28);
	saveOutfit:SetPoint("BOTTOMLEFT", 9, 14);
	saveOutfit:SetText("Сохранить образ");
	saveOutfit:SetScript("OnClick", function()
		StaticPopup_Show("TRANSMOG_OUTFIT_NAME");
	end);
	local moneyBox = CreateFrame("Frame", nil, outfits);
	moneyBox:SetSize(152, 24);
	moneyBox:SetPoint("BOTTOMLEFT", saveOutfit, "BOTTOMRIGHT", 9, 2);
	Tex(moneyBox, "BACKGROUND", "common-currencybox-a"):SetAllPoints();
	local money = CreateFrame("Frame", "TransmogFrameMoneyFrame", moneyBox, "SmallMoneyFrameTemplate");
	money:SetSize(141, 15);
	money:SetPoint("BOTTOMRIGHT", 9, 6);
	self.MoneyFrame = money;

	-------------------------------------------------------------------
	-- CharacterPreview
	-------------------------------------------------------------------
	local preview = CreateFrame("Frame", nil, self);
	preview:SetSize(658, 860);
	preview:SetPoint("TOPLEFT", outfits, "TOPRIGHT");
	local _, raceFile = UnitRace("player");
	local background = Tex(preview, "BACKGROUND", "transmog-background-race-" .. strlower(raceFile or "human"));
	background:SetAllPoints();
	Tex(preview, "BACKGROUND", "transmog-locationBG-glow", true, 1):SetPoint("BOTTOM");
	local gradientLeft = Tex(preview, "BACKGROUND", "transmog-outfit-darkBG-gradient", false, 2);
	gradientLeft:SetSize(123, 860);
	gradientLeft:SetPoint("LEFT");
	local gradientRight = Tex(preview, "BACKGROUND", "transmog-outfit-darkBG-gradient", false, 2);
	gradientRight:SetSize(123, 860);
	gradientRight:SetPoint("RIGHT");
	local l, r, t, b = gradientRight:GetTexCoord();
	gradientRight:SetTexCoord(r, l, t, b);   -- rotation="180" в ретейле

	local model = CreateFrame("DressUpModel", "TransmogFramePreview", preview);
	model:SetAllPoints();
	model:EnableMouse(true);
	model:EnableMouseWheel(true);
	model:SetScript("OnMouseDown", function(m, button)
		if button == "LeftButton" then
			m.rotating = true;
			m.rotateX = GetCursorPosition();
		end
	end);
	model:SetScript("OnMouseUp", function(m)
		m.rotating = nil;
	end);
	model:SetScript("OnUpdate", function(m, elapsed)
		if m.rotating then
			local x = GetCursorPosition();
			m.facing = (m.facing or 0) + (x - m.rotateX) * 0.02;
			m.rotateX = x;
			m:SetFacing(m.facing);
		elseif m.spin then
			m.facing = (m.facing or 0) + m.spin * elapsed * 2;
			m:SetFacing(m.facing);
		end
	end);
	local function Zoom(delta)
		model.zoom = math.max(0, math.min(2.5, (model.zoom or 0) + delta * 0.3));
		model:SetPosition(model.zoom, 0, 0);
	end
	model:SetScript("OnMouseWheel", function(_, delta) Zoom(delta); end);
	self.Preview = model;

	-- ControlFrame (TOP, y=-18)
	local controls = CreateFrame("Frame", nil, preview);
	controls:SetSize(5 * 30, 26);
	controls:SetPoint("TOP", 0, -18);
	controls:SetFrameLevel(model:GetFrameLevel() + 5);
	local function Control(index, atlas, tooltip, onClick, spin)
		local button = CreateFrame("Button", nil, controls);
		button:SetSize(26, 26);
		button:SetPoint("LEFT", (index - 1) * 30, 0);
		Tex(button, "ARTWORK", atlas):SetAllPoints();
		local hl = Tex(button, "HIGHLIGHT", atlas);
		hl:SetAllPoints();
		hl:SetBlendMode("ADD");
		if spin then
			button:SetScript("OnMouseDown", function() model.spin = spin; end);
			button:SetScript("OnMouseUp", function() model.spin = nil; end);
		else
			button:SetScript("OnClick", onClick);
		end
		Tooltip(button, tooltip);
	end
	Control(1, "common-icon-zoomin", "Приблизить", function() Zoom(1); end);
	Control(2, "common-icon-zoomout", "Отдалить", function() Zoom(-1); end);
	Control(3, "common-icon-rotateleft", "Повернуть влево", nil, -1);
	Control(4, "common-icon-rotateright", "Повернуть вправо", nil, 1);
	Control(5, "common-icon-undo", "Сбросить вид", function()
		model.zoom, model.facing = 0, 0;
		model:SetPosition(0, 0, 0);
		model:SetFacing(0);
	end);

	-- ToggleOptions + ClearAllPendingButton (36x36, TOPRIGHT -21,-134)
	local function SquareButton(atlas, tooltip, onClick)
		local button = AtlasButton(preview, 36, 36, "common-button-tertiary-square-normal", "common-button-tertiary-square-pressed");
		button:SetFrameLevel(model:GetFrameLevel() + 5);
		local icon = Tex(button, "ARTWORK", atlas);
		icon:SetSize(18, 18);
		icon:SetPoint("CENTER");
		button:SetScript("OnClick", onClick);
		Tooltip(button, tooltip);
		return button;
	end
	local sheathe = SquareButton("transmog-icon-hidden", "Показать/убрать оружие", function()
		self.hideWeapons = not self.hideWeapons;
		if self.hideWeapons and model.UndressSlot then
			model:UndressSlot(16);
			model:UndressSlot(17);
			model:UndressSlot(18);
		else
			TransmogUI.UpdatePreview(self);
		end
	end);
	sheathe:SetPoint("TOPRIGHT", -21, -94);
	local clearAll = SquareButton("common-icon-undo", "Отменить все изменения", function()
		wipe(self.pending);
		PlaySound("igMainMenuOptionCheckBoxOff");
		TransmogUI.UpdateSlots(self);
		TransmogUI.UpdatePreview(self);
		TransmogUI.UpdateGrid(self);
	end);
	clearAll:SetPoint("TOPRIGHT", -21, -134);
	self.ClearButton = clearAll;

	-- LeftSlots (LEFT x=28), RightSlots (RIGHT x=-28), BottomSlots (BOTTOM) - слоты 59x59, отступ 5
	local SLOT_SIZE, SLOT_SPACING = 59, 5;
	local counts = { LEFT = 0, RIGHT = 0, BOTTOM = 0 };
	for _, info in ipairs(SLOTS) do
		counts[info.side] = counts[info.side] + 1;
	end
	local index = { LEFT = 0, RIGHT = 0, BOTTOM = 0 };
	self.slotButtons = {};
	for _, info in ipairs(SLOTS) do
		local button = CreateFrame("Button", nil, preview, "TransmogSlotButtonTemplate");
		button:SetFrameLevel(model:GetFrameLevel() + 5);
		button.info = info;
		local side = info.side;
		local n = counts[side];
		local i = index[side];
		local total = n * SLOT_SIZE + (n - 1) * SLOT_SPACING;
		if side == "LEFT" or side == "RIGHT" then
			local y = total / 2 - SLOT_SIZE / 2 - i * (SLOT_SIZE + SLOT_SPACING);
			button:SetPoint(side, preview, side, side == "LEFT" and 28 or -28, y);
		else
			local x = -total / 2 + SLOT_SIZE / 2 + i * (SLOT_SIZE + SLOT_SPACING);
			button:SetPoint("BOTTOM", preview, "BOTTOM", x, 48 + 42 + 4);
			if info.id == 16 or info.id == 17 then
				-- TransmogIllusionSlotTemplate (42x42): иллюзий в 3.3.5 нет
				local illusion = CreateFrame("Frame", nil, preview);
				illusion:SetSize(42, 42);
				illusion:SetFrameLevel(model:GetFrameLevel() + 5);
				illusion:SetPoint("TOP", button, "BOTTOM", 0, -4);
				Tex(illusion, "BORDER", "transmog-gearSlot-default-small", true):SetPoint("CENTER");
				Tex(illusion, "ARTWORK", "transmog-gearSlot-unassigned-enchant", true):SetPoint("CENTER");
				Tex(illusion, "OVERLAY", "transmog-icon-disabled-small", true):SetPoint("CENTER");
			end
		end
		index[side] = i + 1;
		table.insert(self.slotButtons, button);
	end

	local apply = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate");
	apply:SetSize(150, 28);
	apply:SetFrameLevel(model:GetFrameLevel() + 5);
	apply:SetPoint("BOTTOMRIGHT", -21, 14);
	apply:SetText("Применить");
	apply:SetScript("OnClick", function() TransmogFrame_Apply(self); end);
	self.ApplyButton = apply;

	-------------------------------------------------------------------
	-- WardrobeCollection (644x860) + TabHeaders + TabContent (644x823 at 0,-35)
	-------------------------------------------------------------------
	local wardrobe = CreateFrame("Frame", nil, self);
	wardrobe:SetSize(644, 860);
	wardrobe:SetPoint("TOPLEFT", preview, "TOPRIGHT");
	Tex(wardrobe, "BACKGROUND", "transmog-outfit-darkBG"):SetAllPoints();

	local content = CreateFrame("Frame", nil, wardrobe);
	content:SetSize(644, 823);
	content:SetPoint("TOPLEFT", 0, -35);
	content:SetFrameLevel(wardrobe:GetFrameLevel() + 2);
	Tex(content, "BACKGROUND", "transmog-tabs-frame-BG", true):SetPoint("TOPLEFT", 4, -4);
	local border = Tex(content, "BACKGROUND", "transmog-tabs-frame", false, 1);
	border:SetSize(661, 841);
	border:SetPoint("TOPLEFT", -11, 12);

	Mixin(wardrobe, TabSystemOwnerMixin);
	TabSystemOwnerMixin.OnLoad(wardrobe);
	local tabs = CreateFrame("Frame", nil, wardrobe, "TabSystemTemplate");
	tabs.tabTemplate = "TabSystemTopButtonTemplate";
	tabs.tabPool = CreateFramePool("BUTTON", tabs, "TabSystemTopButtonTemplate");
	tabs.minTabWidth, tabs.maxTabWidth = 95, 170;
	tabs:SetPoint("TOPLEFT", 32, -12);
	tabs:SetFrameLevel(content:GetFrameLevel() + 5);
	wardrobe:SetTabSystem(tabs);

	local items = CreateFrame("Frame", nil, content);
	items:SetAllPoints();
	local itemsTab = wardrobe:AddNamedTab("Предметы", items);
	wardrobe:AddNamedTab("Наборы", TransmogUI.CreateStubTab(content, "Комплекты для трансмогрификации появятся вместе с серверной частью."));
	wardrobe:AddNamedTab("Свои наборы", TransmogUI.CreateStubTab(content, "Свои наборы появятся вместе с серверной частью."));
	wardrobe:AddNamedTab("Ситуации", TransmogUI.CreateStubTab(content, "Смена образа по ситуациям (бой, верховая езда...) появится позже."));
	wardrobe:SetTab(itemsTab);

	-- ActiveSlotTitle (23,-58) + Divider
	self.SlotTitle = TransmogUI.CreateLabel(items, "GameFontHighlightHuge", "");
	self.SlotTitle:SetPoint("TOPLEFT", 23, -58);
	local divider = Tex(items, "ARTWORK", "transmog-tabs-header-line", true);
	divider:SetAlpha(0.1);
	divider:SetPoint("TOPLEFT", self.SlotTitle, "BOTTOMLEFT", 0, -2);

	-- FilterButton (TOPRIGHT -29,-24) - как во «Внешнем виде»; источники пока без функций
	local SOURCES = { "Добыча с боссов", "Задание", "Торговец", "Мировая добыча", "Достижение", "Профессия" };
	self.sourceFilters = {};
	for i in ipairs(SOURCES) do
		self.sourceFilters[i] = true;
	end
	local filter = CreateFrame("Button", "TransmogFrameFilterDropdown", items, "WowStyle1FilterDropdownTemplate");
	filter:SetPoint("TOPRIGHT", -29, -24);
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
		rootDescription:CreateCheckbox("Собранные", function() return true; end, function() end);
		rootDescription:CreateCheckbox("Не собранные", function() return self.showUncollected; end, function()
			self.showUncollected = not self.showUncollected;
			filter:ValidateResetState();
			self.page = 1;
			TransmogUI.RequestPage(self);
		end);
		local sources = rootDescription:CreateSubmenu("Источники");
		for i, name in ipairs(SOURCES) do
			sources:CreateCheckbox(name, function() return self.sourceFilters[i]; end, function()
				self.sourceFilters[i] = not self.sourceFilters[i];
				filter:ValidateResetState();
			end);
		end
	end);

	-- SearchBox (слева от фильтра, -10)
	local searchBox = CreateFrame("EditBox", "TransmogFrameSearchBox", items, "SearchBoxTemplate");
	searchBox:SetSize(150, 20);
	searchBox:SetPoint("TOPRIGHT", filter, "TOPLEFT", -10, 1);
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

	-- DisplayTypes (от заголовка 16,-21, отступ 25): кнопки 188x36
	local function DisplayTypeButton(text, icon, iconIsAtlas, onClick)
		local button = AtlasButton(items, 188, 36, "common-button-tertiary-normal", "common-button-tertiary-pressed");
		local tex = button:CreateTexture(nil, "ARTWORK");
		tex:SetSize(24, 24);
		tex:SetPoint("LEFT", 8, 0);
		if iconIsAtlas then
			tex:SetAtlas(icon);
		else
			tex:SetTexture(icon);
		end
		local label = TransmogUI.CreateLabel(button, "GameFontNormal", text);
		label:SetPoint("LEFT", tex, "RIGHT", 6, 0);
		button:SetScript("OnClick", onClick);
		return button;
	end
	local unassigned = DisplayTypeButton("Не назначено", "transmog-icon-disabled", true, function()
		if self.selectedSlot then
			self.pending[self.selectedSlot] = nil;
			TransmogUI.UpdateSlots(self);
			TransmogUI.UpdatePreview(self);
			TransmogUI.UpdateGrid(self);
		end
	end);
	unassigned:SetPoint("TOPLEFT", self.SlotTitle, "BOTTOMLEFT", 16, -21);
	local showEquipped = DisplayTypeButton("Надетая экипировка", "Interface\\Icons\\INV_Chest_Chain_15", false, function()
		local slotId = self.selectedSlot;
		if slotId then
			self.pending[slotId] = self.applied[slotId] and 0 or nil;
			TransmogUI.UpdateSlots(self);
			TransmogUI.UpdatePreview(self);
			TransmogUI.UpdateGrid(self);
		end
	end);
	showEquipped:SetPoint("LEFT", unassigned, "RIGHT", 25, 0);

	-- PagedContent (TOPLEFT 30,-163; отступы 20): сетка 5x4 моделей 100x132
	self.gridModels = {};
	for row = 1, GRID_ROWS do
		for column = 1, GRID_COLUMNS do
			local cell = CreateFrame("DressUpModel", nil, items, "TransmogItemModelTemplate");
			cell:SetPoint("TOPLEFT", items, "TOPLEFT", 30 + (column - 1) * (MODEL_WIDTH + MODEL_SPACE_X), -163 - (row - 1) * (MODEL_HEIGHT + MODEL_SPACE_Y));
			cell:Hide();
			table.insert(self.gridModels, cell);
		end
	end

	self.GridMessage = TransmogUI.CreateLabel(items, "GameFontHighlightLarge", "");
	self.GridMessage:SetPoint("CENTER", items, "CENTER", 0, -40);

	-- PagingControls (BOTTOM, y=5 от области сетки)
	local paging = CreateFrame("Frame", nil, items);
	paging:SetSize(160, 32);
	paging:SetPoint("BOTTOM", items, "BOTTOM", 20, 16);
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
