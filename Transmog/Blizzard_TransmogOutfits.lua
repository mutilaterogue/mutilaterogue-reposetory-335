-- Трансмогрификация: наряды (ретейл: TransmogOutfitCollectionMixin). Хранятся на сервере (server/transmog_outfits.cpp):
--   "TMOG_OUTFITS_GET" -> "TMOG_OUTFIT" : id : name : iconItem : "slot/item,..." : situations : location : movement : combat (x N)
--                      -> "TMOG_OUTFITS_END" : unlocked : max : nextSlotCost : activeId
--   "TMOG_OUTFIT_SAVE" : id(0 = new) : name : iconItem : slots   сохранить (платно за изменённые ячейки) и надеть
--   "TMOG_OUTFIT_EQUIP" : id                                      надеть сохранённый наряд (бесплатно)
--   "TMOG_OUTFIT_RENAME" : id : name : iconItem, "TMOG_OUTFIT_DEL" : id, "TMOG_OUTFIT_BUY"

local SLOTS, NUM_OUTFIT_BUTTONS = TransmogUI.SLOTS, TransmogUI.NUM_OUTFIT_BUTTONS;

TransmogOutfits = {};   -- { id, name, icon (itemId), slots = { [slotId] = itemId }, situations = { enabled, location, movement, combat } }
TransmogUI.outfitInfo = { unlocked = 0, max = 0, cost = 0, active = 0 };

local incoming;   -- наряды, пришедшие до TMOG_OUTFITS_END

function TransmogUI.CountSlots(outfit)
	local n = 0;
	for _ in pairs(outfit.slots) do
		n = n + 1;
	end
	return n;
end

function TransmogUI.GetOutfit(id)
	for _, outfit in ipairs(TransmogOutfits) do
		if outfit.id == id then
			return outfit;
		end
	end
end

function TransmogUI.UpdateOutfits(self)
	local info = TransmogUI.outfitInfo;
	local offset = self.outfitOffset or 0;
	for index, button in ipairs(self.outfitButtons) do
		local outfit = TransmogOutfits[index + offset];
		button.outfit = outfit;
		if outfit then
			button.Icon:SetTexture(outfit.icon and outfit.icon > 0 and TransmogUI.GetItemIcon(outfit.icon) or "Interface\\Icons\\INV_Chest_Cloth_17");
			button.Name:SetText(outfit.name);
			if outfit.id == info.active then
				button.Sub:SetText(GREEN_FONT_COLOR_CODE .. "Активен" .. FONT_COLOR_CODE_CLOSE);
			elseif outfit.situations.enabled then
				button.Sub:SetText(TRANSMOG_SITUATIONS_ENABLED);
			else
				button.Sub:SetText(("%d/%d"):format(TransmogUI.CountSlots(outfit), #SLOTS));
			end
			button.Selected:SetShown(self.selectedOutfit == outfit);
			button:Show();
		else
			button:Hide();
		end
	end

	-- ретейл: PurchaseOutfitButton, доступен пока не открыты все ячейки
	local purchase = self.OutfitCollection.PurchaseOutfitButton;
	local canBuy = info.max > 0 and info.unlocked < info.max;
	purchase:SetEnabled(canBuy);
	purchase.Text:SetFontObject(canBuy and GameFontNormal or GameFontDisable);
	purchase.Icon:SetDesaturated(not canBuy);

	self.EquippedActive:SetShown(next(self.applied) == nil and next(self.pending) == nil);
	if self.WardrobeCollection.TabContent.SituationsFrame:IsShown() then
		TransmogSituationsFrame_Refresh(self.WardrobeCollection.TabContent.SituationsFrame);
	end
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------
function TransmogFrame_SelectOutfit(outfit, equip)
	local frame = TransmogFrame;
	frame.selectedOutfit = outfit;
	if equip and outfit and Comm_Send then
		wipe(frame.pending);
		Comm_Send(TransmogUI.OP_OUTFIT_EQUIP, outfit.id);
		frame.applyElapsed = 0;
	end
	TransmogUI.UpdateOutfits(frame);
end

-- ретейл: SaveOutfitButton - сохранить показанный облик в выбранный наряд и надеть его; без выбранного - новый наряд
function TransmogFrame_SaveOutfitClick()
	local frame = TransmogFrame;
	if frame.selectedOutfit then
		TransmogUI.SendSaveOutfit(frame.selectedOutfit.id, "");
	elseif #TransmogOutfits < TransmogUI.outfitInfo.unlocked then
		StaticPopup_Show("TRANSMOG_OUTFIT_NAME");
	else
		UIErrorsFrame:AddMessage(TRANSMOG_PURCHASE_OUTFIT_SLOT, 1.0, 0.1, 0.1, 1.0);
	end
end

function TransmogFrame_SaveOutfit_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(TRANSMOG_SAVE_OUTFIT);
	GameTooltip:AddLine(TRANSMOG_SAVE_OUTFIT_TOOLTIP, 1, 1, 1, true);
	local cost = TransmogUI.GetCost(TransmogFrame);
	if cost > GetMoney() then
		GameTooltip:AddLine(TRANSMOG_SAVE_OUTFIT_CANNOT_AFFORD_TOOLTIP, 1, 0.1, 0.1, true);
	end
	GameTooltip:Show();
end

function TransmogUI.SendSaveOutfit(id, name)
	local frame = TransmogFrame;
	local looks = TransmogUI.DisplayedLooks(frame, false);
	local icon = 0;
	for _, info in ipairs(SLOTS) do
		if looks[info.id] then
			icon = looks[info.id];
			break;
		end
	end
	if Comm_Send then
		Comm_Send(TransmogUI.OP_OUTFIT_SAVE, id, name or "", icon, TransmogUI.FormatSlots(looks));
		frame.applyElapsed = 0;
	end
end

function TransmogFrame_PurchaseOutfitSlot()
	StaticPopup_Show("TRANSMOG_OUTFIT_BUY", nil, nil, TransmogUI.outfitInfo.cost);
end

function TransmogFrame_PurchaseOutfitSlot_OnEnter(self)
	local info = TransmogUI.outfitInfo;
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(TRANSMOG_PURCHASE_OUTFIT_SLOT);
	if info.unlocked >= info.max then
		GameTooltip:AddLine(TRANSMOG_PURCHASE_OUTFIT_SLOT_TOOLTIP_DISABLED:format(info.max), 1, 0.1, 0.1, true);
	else
		SetTooltipMoney(GameTooltip, info.cost);
	end
	GameTooltip:AddLine(("%d/%d"):format(#TransmogOutfits, info.unlocked), 0.5, 0.5, 0.5);
	GameTooltip:Show();
end

local function OpenOutfitMenu(button)
	local outfit = button.outfit;
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(button, function(owner, rootDescription)
			rootDescription:CreateTitle(outfit.name);
			rootDescription:CreateButton(TRANSMOG_EDIT_OUTFIT_SLOT, function()
				StaticPopup_Show("TRANSMOG_OUTFIT_NAME", nil, nil, outfit);
			end);
			rootDescription:CreateButton(TRANSMOG_SAVE_OUTFIT, function()
				TransmogUI.SendSaveOutfit(outfit.id, "");
			end);
			rootDescription:CreateButton(TRANSMOG_OUTFIT_DELETE, function()
				StaticPopup_Show("TRANSMOG_OUTFIT_DELETE", outfit.name, nil, outfit);
			end);
		end);
	else
		StaticPopup_Show("TRANSMOG_OUTFIT_DELETE", outfit.name, nil, outfit);
	end
end

-- ЛКМ - надеть наряд (бесплатно), ПКМ - меню: название, сохранить, удалить
function TransmogOutfitEntry_OnClick(self, mouseButton)
	if not self.outfit then
		return;
	end
	if mouseButton == "RightButton" then
		OpenOutfitMenu(self);
		return;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogFrame_SelectOutfit(self.outfit, true);
end

function TransmogOutfitEntry_OnEnter(self)
	local outfit = self.outfit;
	if not outfit then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(outfit.name);
	for _, info in ipairs(SLOTS) do
		local itemId = outfit.slots[info.id];
		if itemId then
			local name, _, quality = GetItemInfo(itemId);
			local color = ITEM_QUALITY_COLORS[quality or 1];
			GameTooltip:AddDoubleLine(info.name, name or ("item:" .. itemId), 0.6, 0.6, 0.6, color.r, color.g, color.b);
		end
	end
	GameTooltip:Show();
end

function TransmogOutfitList_OnMouseWheel(self, delta)
	local frame = TransmogFrame;
	local maxOffset = math.max(0, #TransmogOutfits - NUM_OUTFIT_BUTTONS);
	frame.outfitOffset = math.max(0, math.min(maxOffset, (frame.outfitOffset or 0) - delta));
	TransmogUI.UpdateOutfits(frame);
end

---------------------------------------------------------------------------
-- popups
---------------------------------------------------------------------------
-- data: наряд для переименования, nil - новый наряд
StaticPopupDialogs["TRANSMOG_OUTFIT_NAME"] = {
	text = TRANSMOG_OUTFIT_SLOT_POPUP_TEXT,
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 16,
	OnShow = function(self)
		local data = self.data;
		self.editBox:SetText(data and data.name or TRANSMOG_OUTFIT_NAME_DEFAULT);
		self.editBox:HighlightText();
		self.editBox:SetFocus();
	end,
	OnAccept = function(self, data)
		local name = self.editBox:GetText();
		if not name or name == "" then
			return;
		end
		if data then
			Comm_Send(TransmogUI.OP_OUTFIT_RENAME, data.id, name, 0);
		else
			TransmogUI.SendSaveOutfit(0, name);
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent();
		StaticPopupDialogs["TRANSMOG_OUTFIT_NAME"].OnAccept(parent, parent.data);
		parent:Hide();
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

StaticPopupDialogs["TRANSMOG_OUTFIT_DELETE"] = {
	text = TRANSMOG_OUTFIT_CONFIRM_DELETE,
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		if TransmogFrame.selectedOutfit == data then
			TransmogFrame.selectedOutfit = nil;
		end
		Comm_Send(TransmogUI.OP_OUTFIT_DEL, data.id);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	showAlert = 1,
};

StaticPopupDialogs["TRANSMOG_OUTFIT_BUY"] = {
	text = TRANSMOG_PURCHASE_OUTFIT_SLOT .. "?",
	button1 = PURCHASE or ACCEPT,
	button2 = CANCEL,
	hasMoneyFrame = 1,
	OnShow = function(self)
		MoneyFrame_Update(self.moneyFrame:GetName(), TransmogUI.outfitInfo.cost);
	end,
	OnAccept = function()
		if TransmogUI.outfitInfo.cost > GetMoney() then
			UIErrorsFrame:AddMessage(ERR_TRANSMOG_OUTFIT_SLOT_CANNOT_AFFORD, 1.0, 0.1, 0.1, 1.0);
			return;
		end
		Comm_Send(TransmogUI.OP_OUTFIT_BUY);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

---------------------------------------------------------------------------
-- server messages
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register(TransmogUI.OP_OUTFIT, function(id, name, icon, slots, enabled, location, movement, combat)
		incoming = incoming or {};
		table.insert(incoming, {
			id = tonumber(id) or 0,
			name = name or "",
			icon = tonumber(icon) or 0,
			slots = TransmogUI.ParseSlots(slots),
			situations = {
				enabled = enabled == "1",
				location = tonumber(location) or 0,
				movement = tonumber(movement) or 0,
				combat = tonumber(combat) or 0,
			},
		});
	end);

	Comm_Register(TransmogUI.OP_OUTFITS_END, function(unlocked, max, cost, active)
		local frame = TransmogFrame;
		local selectedId = frame.selectedOutfit and frame.selectedOutfit.id;
		TransmogOutfits = incoming or {};
		incoming = nil;
		table.sort(TransmogOutfits, function(a, b) return a.id < b.id; end);
		local info = TransmogUI.outfitInfo;
		info.unlocked, info.max, info.cost, info.active = tonumber(unlocked) or 0, tonumber(max) or 0, tonumber(cost) or 0, tonumber(active) or 0;
		frame.selectedOutfit = TransmogUI.GetOutfit(selectedId or info.active);
		frame.applyElapsed = nil;
		TransmogUI.UpdateOutfits(frame);
	end);

	-- ситуация на сервере надела другой наряд
	Comm_Register(TransmogUI.OP_OUTFIT_ACTIVE, function(id)
		TransmogUI.outfitInfo.active = tonumber(id) or 0;
		if TransmogFrame:IsShown() then
			TransmogUI.UpdateOutfits(TransmogFrame);
		end
	end);
end
