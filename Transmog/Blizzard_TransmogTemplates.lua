-- Трансмогрификация: шаблоны (ретейл: Blizzard_TransmogTemplates) - модели обликов, кнопки слотов, элементы оформления.

local OP_GET_STATE, OP_STATE, OP_APPLY, OP_RESULT, OP_OPEN, OP_CLOSE, OP_GET_PAGE, OP_PAGE, GRID_COLUMNS, GRID_ROWS, MODEL_WIDTH, MODEL_HEIGHT, MODEL_SPACE_X, MODEL_SPACE_Y, LEFT_X1, LEFT_X2, CENTER_X1, CENTER_X2, RIGHT_X1, RIGHT_X2, PANEL_TOP, PANEL_BOTTOM, SLOTS, SLOT_UNASSIGNED_ATLAS, SLOT_BY_ID, CLASS_IDS, NUM_OUTFIT_BUTTONS, MAX_OUTFITS =
	TransmogUI.OP_GET_STATE, TransmogUI.OP_STATE, TransmogUI.OP_APPLY, TransmogUI.OP_RESULT, TransmogUI.OP_OPEN, TransmogUI.OP_CLOSE, TransmogUI.OP_GET_PAGE, TransmogUI.OP_PAGE, TransmogUI.GRID_COLUMNS, TransmogUI.GRID_ROWS, TransmogUI.MODEL_WIDTH, TransmogUI.MODEL_HEIGHT, TransmogUI.MODEL_SPACE_X, TransmogUI.MODEL_SPACE_Y, TransmogUI.LEFT_X1, TransmogUI.LEFT_X2, TransmogUI.CENTER_X1, TransmogUI.CENTER_X2, TransmogUI.RIGHT_X1, TransmogUI.RIGHT_X2, TransmogUI.PANEL_TOP, TransmogUI.PANEL_BOTTOM, TransmogUI.SLOTS, TransmogUI.SLOT_UNASSIGNED_ATLAS, TransmogUI.SLOT_BY_ID, TransmogUI.CLASS_IDS, TransmogUI.NUM_OUTFIT_BUTTONS, TransmogUI.MAX_OUTFITS;

function TransmogUI.ApplyCamera(model)
	local entry = model.entry;
	if not entry or not WardrobeGetCamera then
		return;
	end
	local cam = WardrobeGetCamera(TransmogFrame.category, entry.itemId);
	model:SetPosition(cam[1], cam[2], cam[3]);
	model:SetFacing(cam[4] or 0);
end

function TransmogUI.DressGridModel(model)
	local entry = model.entry;
	if not entry then
		return;
	end
	if not model.unitSet then
		model:SetUnit("player");
		model.unitSet = true;
	end
	model:Undress();
	model:TryOn("item:" .. entry.itemId);
	TransmogUI.ApplyCamera(model);
end

function TransmogItemModel_OnLoad(self)
	local border = CreateFrame("Frame", nil, self:GetParent());
	border:SetPoint("TOPLEFT", self, "TOPLEFT", -5, 5);
	border:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 5, -5);
	border:SetFrameLevel(self:GetFrameLevel() + 2);
	border.Card = border:CreateTexture(nil, "OVERLAY");
	border.Card:SetAllPoints();
	border.Card:SetAtlas("transmog-itemCard-default");
	border.Hover = border:CreateTexture(nil, "OVERLAY", nil, 1);
	border.Hover:SetAllPoints();
	border.Hover:SetAtlas("transmog-itemCard-hover");
	border.Hover:Hide();
	border:Hide();
	self.Border = border;

	self:SetScript("OnUpdate", function(model, elapsed)
		model.Border.Hover:SetShown(model:IsMouseOver());
		if model.entry then
			TransmogUI.ApplyCamera(model);
		end
		if model.redressTime then
			model.redressTime = model.redressTime - elapsed;
			if model.redressTime <= 0 then
				TransmogUI.DressGridModel(model);
				local delays = { 0.3, 0.6, 1.0, 2.0 };
				model.redressIndex = (model.redressIndex or 1) + 1;
				model.redressTime = delays[model.redressIndex - 1];
			end
		end
	end);
end

function TransmogItemModel_OnMouseDown(self, button)
	local frame = TransmogFrame;
	local entry = self.entry;
	if not entry or not frame.selectedSlot then
		return;
	end
	local _, link = GetItemInfo(entry.itemId);
	if IsModifiedClick("CHATLINK") and link then
		ChatEdit_InsertLink(link);
		return;
	end
	if not entry.collected then
		UIErrorsFrame:AddMessage("Этот облик ещё не собран.", 1.0, 0.1, 0.1, 1.0);
		return;
	end
	local slotId = frame.selectedSlot;
	if entry.itemId == GetInventoryItemID("player", slotId) and not frame.applied[slotId] then
		frame.pending[slotId] = nil;   -- выбран собственный облик предмета
	elseif entry.itemId == frame.applied[slotId] then
		frame.pending[slotId] = nil;
	else
		frame.pending[slotId] = entry.itemId;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogUI.UpdateSlots(frame);
	TransmogUI.UpdatePreview(frame);
	TransmogUI.UpdateGrid(frame);
end

function TransmogItemModel_OnEnter(self)
	local entry = self.entry;
	if not entry then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink("item:" .. entry.itemId);
	GameTooltip:AddLine(" ");
	if entry.collected then
		GameTooltip:AddLine("Щелчок - применить этот облик к слоту.", 0.1, 1, 0.1, true);
	else
		GameTooltip:AddLine("Облик не собран.", 1, 0.1, 0.1, true);
	end
	GameTooltip:Show();
end

---------------------------------------------------------------------------
-- slot buttons
---------------------------------------------------------------------------
function TransmogSlotButton_OnClick(self, button)
	local frame = TransmogFrame;
	local slotId = self.info.id;
	if button == "RightButton" then
		if frame.pending[slotId] ~= nil then
			frame.pending[slotId] = nil;        -- отменить изменение
		elseif frame.applied[slotId] then
			frame.pending[slotId] = 0;          -- вернуть исходный облик предмета
		end
		PlaySound("igMainMenuOptionCheckBoxOff");
		TransmogUI.UpdateSlots(frame);
		TransmogUI.UpdatePreview(frame);
		TransmogUI.UpdateGrid(frame);
		return;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogFrame_SelectSlot(frame, slotId);
end

function TransmogSlotButton_OnEnter(self)
	local frame = TransmogFrame;
	local slotId = self.info.id;
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	local link = GetInventoryItemLink("player", slotId);
	if not link then
		GameTooltip:SetText(self.info.name);
		GameTooltip:AddLine("Нет надетого предмета.", 0.6, 0.6, 0.6);
		GameTooltip:Show();
		return;
	end
	GameTooltip:SetInventoryItem("player", slotId);
	local itemId, changed = TransmogUI.GetDisplayedItem(frame, slotId);
	local shown = itemId and GetItemInfo(itemId);
	if frame.pending[slotId] == 0 then
		GameTooltip:AddLine("Будет возвращён исходный облик.", 1, 0.82, 0);
	elseif shown and (changed or frame.applied[slotId]) then
		GameTooltip:AddLine((changed and "Новый облик: " or "Облик: ") .. shown, 1, 0.5, 1);
	end
	GameTooltip:AddLine("ЛКМ - выбрать слот, ПКМ - отменить изменение / вернуть облик.", 0.5, 0.5, 0.5, true);
	GameTooltip:Show();
end

function TransmogUI.CreatePanel(parent, x1, x2, atlas)
	local panel = CreateFrame("Frame", nil, parent);
	panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, PANEL_TOP);
	panel:SetPoint("BOTTOMRIGHT", parent, "TOPLEFT", x2, PANEL_BOTTOM);
	local bg = panel:CreateTexture(nil, "BACKGROUND");
	bg:SetAllPoints();
	bg:SetAtlas(atlas);
	panel.Bg = bg;
	return panel;
end

function TransmogUI.CreateIconButton(parent, texture, size, tooltip, onClick)
	local button = CreateFrame("Button", nil, parent);
	button:SetSize(size, size);
	local normal = button:CreateTexture(nil, "ARTWORK");
	normal:SetAllPoints();
	if texture:find("\\") then
		normal:SetTexture(texture);
	else
		normal:SetAtlas(texture);   -- атлас ретейла
	end
	button.Icon = normal;
	local highlight = button:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAllPoints();
	if texture:find("\\") then
		highlight:SetTexture(texture);
	else
		highlight:SetAtlas(texture);
	end
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.5);
	button:SetScript("OnClick", onClick);
	button:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT");
		GameTooltip:SetText(tooltip);
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", GameTooltip_Hide);
	return button;
end

function TransmogUI.CreateBorder(frame, r, g, b)
	local border = CreateFrame("Frame", nil, frame);
	border:SetPoint("TOPLEFT", -3, 3);
	border:SetPoint("BOTTOMRIGHT", 3, -3);
	border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 });
	border:SetBackdropBorderColor(r, g, b, 1);
	return border;
end

-- вкладки коллекции: «Предметы» работает, остальные - заглушки до серверной части
function TransmogUI.CreateStubTab(parent, text)
	local frame = CreateFrame("Frame", nil, parent);
	frame:SetAllPoints();
	local label = TransmogUI.CreateLabel(frame, "GameFontNormalHuge", "В скором времени");
	label:SetPoint("CENTER", 0, 20);
	local desc = TransmogUI.CreateLabel(frame, "GameFontHighlight", text);
	desc:SetPoint("TOP", label, "BOTTOM", 0, -10);
	desc:SetWidth(380);
	frame:Hide();
	return frame;
end
