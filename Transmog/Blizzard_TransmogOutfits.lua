-- Трансмогрификация: образы (ретейл: TransmogOutfitCollectionMixin). Хранение на сервере - позже.

local OP_GET_STATE, OP_STATE, OP_APPLY, OP_RESULT, OP_OPEN, OP_CLOSE, OP_GET_PAGE, OP_PAGE, GRID_COLUMNS, GRID_ROWS, MODEL_WIDTH, MODEL_HEIGHT, MODEL_SPACE_X, MODEL_SPACE_Y, LEFT_X1, LEFT_X2, CENTER_X1, CENTER_X2, RIGHT_X1, RIGHT_X2, PANEL_TOP, PANEL_BOTTOM, SLOTS, SLOT_UNASSIGNED_ATLAS, SLOT_BY_ID, CLASS_IDS, NUM_OUTFIT_BUTTONS, MAX_OUTFITS =
	TransmogUI.OP_GET_STATE, TransmogUI.OP_STATE, TransmogUI.OP_APPLY, TransmogUI.OP_RESULT, TransmogUI.OP_OPEN, TransmogUI.OP_CLOSE, TransmogUI.OP_GET_PAGE, TransmogUI.OP_PAGE, TransmogUI.GRID_COLUMNS, TransmogUI.GRID_ROWS, TransmogUI.MODEL_WIDTH, TransmogUI.MODEL_HEIGHT, TransmogUI.MODEL_SPACE_X, TransmogUI.MODEL_SPACE_Y, TransmogUI.LEFT_X1, TransmogUI.LEFT_X2, TransmogUI.CENTER_X1, TransmogUI.CENTER_X2, TransmogUI.RIGHT_X1, TransmogUI.RIGHT_X2, TransmogUI.PANEL_TOP, TransmogUI.PANEL_BOTTOM, TransmogUI.SLOTS, TransmogUI.SLOT_UNASSIGNED_ATLAS, TransmogUI.SLOT_BY_ID, TransmogUI.CLASS_IDS, TransmogUI.NUM_OUTFIT_BUTTONS, TransmogUI.MAX_OUTFITS;


function TransmogUI.CountSlots(outfit)
	local n = 0;
	for _ in pairs(outfit.slots) do
		n = n + 1;
	end
	return n;
end

function TransmogUI.UpdateOutfits(self)
	local offset = self.outfitOffset or 0;
	for index, button in ipairs(self.outfitButtons) do
		local outfit = TransmogOutfits[index + offset];
		button.outfit = outfit;
		if outfit then
			button.Icon:SetTexture(outfit.icon or "Interface\\Icons\\INV_Chest_Cloth_17");
			button.Name:SetText(outfit.name);
			button.Sub:SetText(("Слотов: %d"):format(TransmogUI.CountSlots(outfit)));
			button.Selected:SetShown(self.selectedOutfit == outfit);
			button:Show();
		else
			button:Hide();
		end
	end
	self.OutfitScrollUp:SetEnabled(offset > 0);
	self.OutfitScrollDown:SetEnabled(offset + NUM_OUTFIT_BUTTONS < #TransmogOutfits);
end

function TransmogUI.CurrentOutfitSlots(self)
	local slots = {};
	for _, info in ipairs(SLOTS) do
		local itemId, changed = TransmogUI.GetDisplayedItem(self, info.id);
		if itemId and (changed or self.applied[info.id]) and self.pending[info.id] ~= 0 then
			slots[info.id] = itemId;
		end
	end
	return slots;
end

StaticPopupDialogs["TRANSMOG_OUTFIT_NAME"] = {
	text = "Название образа:",
	button1 = SAVE or "Сохранить",
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 31,
	OnAccept = function(self)
		local name = self.editBox:GetText();
		if name and name ~= "" then
			TransmogFrame_SaveOutfit(name);
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent();
		local name = self:GetText();
		if name and name ~= "" then
			TransmogFrame_SaveOutfit(name);
		end
		parent:Hide();
	end,
	OnShow = function(self)
		self.editBox:SetFocus();
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

function TransmogFrame_SaveOutfit(name)
	local frame = TransmogFrame;
	local slots = TransmogUI.CurrentOutfitSlots(frame);
	if not next(slots) then
		UIErrorsFrame:AddMessage("Нет изменённых слотов для образа.", 1.0, 0.1, 0.1, 1.0);
		return;
	end
	local icon;
	for _, info in ipairs(SLOTS) do
		if slots[info.id] then
			icon = TransmogUI.GetItemIcon(slots[info.id]);
			break;
		end
	end
	for _, outfit in ipairs(TransmogOutfits) do
		if outfit.name == name then
			outfit.slots, outfit.icon = slots, icon;
			TransmogUI.UpdateOutfits(frame);
			return;
		end
	end
	if #TransmogOutfits >= MAX_OUTFITS then
		UIErrorsFrame:AddMessage("Слишком много образов.", 1.0, 0.1, 0.1, 1.0);
		return;
	end
	table.insert(TransmogOutfits, { name = name, icon = icon, slots = slots });
	TransmogUI.UpdateOutfits(frame);
end

function TransmogUI.LoadOutfit(self, outfit)
	self.selectedOutfit = outfit;
	self.showEquipped = false;
	wipe(self.pending);
	for _, info in ipairs(SLOTS) do
		local itemId = outfit.slots[info.id];
		if GetInventoryItemLink("player", info.id) then
			if itemId and itemId ~= self.applied[info.id] then
				self.pending[info.id] = itemId;
			elseif not itemId and self.applied[info.id] then
				self.pending[info.id] = 0;
			end
		end
	end
	TransmogUI.UpdateSlots(self);
	TransmogUI.UpdatePreview(self);
	TransmogUI.UpdateGrid(self);
end
