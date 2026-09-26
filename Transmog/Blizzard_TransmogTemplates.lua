-- Трансмогрификация: шаблоны (ретейл: Blizzard_TransmogTemplates) - модели обликов, кнопки слотов, элементы оформления.

local OP_GET_STATE, OP_STATE, OP_APPLY, OP_RESULT, OP_OPEN, OP_CLOSE, OP_GET_PAGE, OP_PAGE, GRID_COLUMNS, GRID_ROWS, MODEL_WIDTH, MODEL_HEIGHT, MODEL_SPACE_X, MODEL_SPACE_Y, LEFT_X1, LEFT_X2, CENTER_X1, CENTER_X2, RIGHT_X1, RIGHT_X2, PANEL_TOP, PANEL_BOTTOM, SLOTS, SLOT_UNASSIGNED_ATLAS, SLOT_BY_ID, CLASS_IDS, NUM_OUTFIT_BUTTONS, MAX_OUTFITS =
	TransmogUI.OP_GET_STATE, TransmogUI.OP_STATE, TransmogUI.OP_APPLY, TransmogUI.OP_RESULT, TransmogUI.OP_OPEN, TransmogUI.OP_CLOSE, TransmogUI.OP_GET_PAGE, TransmogUI.OP_PAGE, TransmogUI.GRID_COLUMNS, TransmogUI.GRID_ROWS, TransmogUI.MODEL_WIDTH, TransmogUI.MODEL_HEIGHT, TransmogUI.MODEL_SPACE_X, TransmogUI.MODEL_SPACE_Y, TransmogUI.LEFT_X1, TransmogUI.LEFT_X2, TransmogUI.CENTER_X1, TransmogUI.CENTER_X2, TransmogUI.RIGHT_X1, TransmogUI.RIGHT_X2, TransmogUI.PANEL_TOP, TransmogUI.PANEL_BOTTOM, TransmogUI.SLOTS, TransmogUI.SLOT_UNASSIGNED_ATLAS, TransmogUI.SLOT_BY_ID, TransmogUI.CLASS_IDS, TransmogUI.NUM_OUTFIT_BUTTONS, TransmogUI.MAX_OUTFITS;

function TransmogUI.ApplyCamera(model)
	local entry = model.entry;
	if not entry then
		return;
	end
	local cam = TransmogUI.GetCamera(TransmogFrame.category, entry.itemId);
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
	-- рамка-карточка (ретейл: Border atlas transmog-itemcard-default, useAtlasSize, по центру)
	local border = CreateFrame("Frame", nil, self:GetParent());
	border:SetAllPoints(self);
	border:SetFrameLevel(self:GetFrameLevel() + 2);
	border.Card = border:CreateTexture(nil, "OVERLAY");
	border.Card:SetAtlas("transmog-itemCard-default", true);
	border.Card:SetPoint("CENTER");
	border.Hover = border:CreateTexture(nil, "OVERLAY", nil, 1);
	border.Hover:SetAtlas("transmog-itemCard-hover", true);
	border.Hover:SetPoint("CENTER");
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

-- зеркально по горизонтали (ретейл: rotation="180"/flip) - по координатам атласа
function TransmogUI.FlipAtlasHorizontal(texture, atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas);
	if info then
		local left = info.leftTexCoord or info.left;
		local right = info.rightTexCoord or info.right;
		local top = info.topTexCoord or info.top;
		local bottom = info.bottomTexCoord or info.bottom;
		if left and right and top and bottom then
			texture:SetTexCoord(right, left, top, bottom);
		end
	end
end

function TransmogTooltipButton_OnEnter(self)
	if self.tooltipText then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(self.tooltipText);
		GameTooltip:Show();
	end
end

---------------------------------------------------------------------------
-- tertiary / square buttons
---------------------------------------------------------------------------
-- атлас на 3 части: края по SLICE_EDGE высоты атласа сохраняют пропорции, центр тянется
local SLICE_EDGE = 0.5;

local function SetSliced(left, center, right, atlas, height)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas);
	if not info then
		return false;
	end
	local l = info.leftTexCoord or info.left;
	local r = info.rightTexCoord or info.right;
	local t = info.topTexCoord or info.top;
	local b = info.bottomTexCoord or info.bottom;
	local w, h = info.width, info.height;
	if not (l and r and t and b and w and h) or h == 0 then
		return false;
	end
	local edge = math.min(h * SLICE_EDGE, w / 2);   -- ширина края в пикселях атласа
	local u = (r - l) * edge / w;                     -- та же ширина в координатах файла
	local edgeWidth = edge * height / h;              -- на кнопке
	for _, tex in ipairs({ left, center, right }) do
		tex:SetAtlas(atlas);
	end
	left:SetTexCoord(l, l + u, t, b);
	left:SetWidth(edgeWidth);
	right:SetTexCoord(r - u, r, t, b);
	right:SetWidth(edgeWidth);
	center:SetTexCoord(l + u, r - u, t, b);
	center:ClearAllPoints();
	center:SetPoint("TOPLEFT", left, "TOPRIGHT");
	center:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT");
	return true;
end

function TransmogUI.SetSlicedAtlas(button, atlas)
	local height = button:GetHeight();
	if not SetSliced(button.Left, button.Center, button.Right, atlas, height) and atlas ~= button.normalAtlas then
		SetSliced(button.Left, button.Center, button.Right, button.normalAtlas, height);   -- нет такого атласа - обычный
	end
end

function TransmogTertiaryButton_Update(self)
	local height = self:GetHeight();
	TransmogUI.SetSlicedAtlas(self, self:IsEnabled() == 1 and self.normalAtlas or self.disabledAtlas);
	if not SetSliced(self.HighlightLeft, self.HighlightCenter, self.HighlightRight, self.hoverAtlas, height) then
		SetSliced(self.HighlightLeft, self.HighlightCenter, self.HighlightRight, self.normalAtlas, height);
	end
end

function TransmogTertiaryButton_OnMouseDown(self)
	if self:IsEnabled() == 1 then
		TransmogUI.SetSlicedAtlas(self, self.pushedAtlas);
	end
end

function TransmogSquareButton_OnMouseDown(self)
	if self:IsEnabled() == 1 then
		self.NormalTex:SetAtlas(self.pushedAtlas);
	end
end

function TransmogSquareButton_OnMouseUp(self)
	self.NormalTex:SetAtlas(self.normalAtlas);
end

---------------------------------------------------------------------------
-- model control buttons
---------------------------------------------------------------------------
function TransmogControlButton_OnLoad(self)
	local atlas = self.iconAtlas;
	if not atlas then
		return;
	end
	self.Icon:SetAtlas(atlas);
	self.Highlight:SetAtlas(atlas);
	if self.mirror then
		TransmogUI.FlipAtlasHorizontal(self.Icon, atlas);
		TransmogUI.FlipAtlasHorizontal(self.Highlight, atlas);
	end
end

function TransmogControlButton_OnMouseDown(self)
	if self.spin then
		TransmogFramePreview.spin = self.spin;
	end
end

function TransmogControlButton_OnMouseUp(self)
	if self.spin then
		TransmogFramePreview.spin = nil;
	end
end

---------------------------------------------------------------------------
-- outfit entries
---------------------------------------------------------------------------
function TransmogOutfitEntry_OnClick(self, mouseButton)
	local frame = TransmogFrame;
	if not self.outfit then
		return;
	end
	if mouseButton == "RightButton" then
		for i, outfit in ipairs(TransmogOutfits) do
			if outfit == self.outfit then
				table.remove(TransmogOutfits, i);
				break;
			end
		end
		if frame.selectedOutfit == self.outfit then
			frame.selectedOutfit = nil;
		end
		TransmogUI.UpdateOutfits(frame);
	else
		PlaySound("igMainMenuOptionCheckBoxOn");
		frame.OutfitCollection.ShowEquippedGear.Active:Hide();
		TransmogUI.LoadOutfit(frame, self.outfit);
		TransmogUI.UpdateOutfits(frame);
	end
end

function TransmogOutfitEntry_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(self.outfit and self.outfit.name or "");
	GameTooltip:AddLine("ЛКМ - примерить образ, ПКМ - удалить.", 0.5, 0.5, 0.5, true);
	GameTooltip:Show();
end

function TransmogOutfitList_OnMouseWheel(self, delta)
	local frame = TransmogFrame;
	local maxOffset = math.max(0, #TransmogOutfits - NUM_OUTFIT_BUTTONS);
	frame.outfitOffset = math.max(0, math.min(maxOffset, (frame.outfitOffset or 0) - delta));
	TransmogUI.UpdateOutfits(frame);
end
