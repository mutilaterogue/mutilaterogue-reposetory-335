-- Трансмогрификация: вкладка «Свои комплекты» (ретейл: TransmogWardrobeCustomSetsMixin). Хранятся на аккаунт на сервере
-- (server/transmog_outfits.cpp):
--   "TMOG_CSETS_GET" -> "TMOG_CSET" : id : name : "slot/item,..." (x N), "TMOG_CSETS_END" : count : max
--   "TMOG_CSET_SAVE" : id(0 = new) : name : slots,  "TMOG_CSET_DEL" : id

local SLOTS = TransmogUI.SLOTS;
local CARDS_PER_PAGE = 9;

TransmogUI.customSets = nil;   -- { id, name, slots = { [slotId] = itemId } }
TransmogUI.customSetsMax = 0;
local incomingSets;

local function SetLooks(set)
	local looks = {};
	for _, info in ipairs(SLOTS) do
		if set.slots[info.id] then
			table.insert(looks, set.slots[info.id]);
		end
	end
	return looks;
end

function TransmogCustomSetsFrame_Refresh(self)
	local list = TransmogUI.customSets or {};
	self.numPages = math.max(1, math.ceil(#list / CARDS_PER_PAGE));
	self.page = math.min(self.page or 1, self.numPages);

	for index, card in ipairs(self.cards) do
		local set = list[(self.page - 1) * CARDS_PER_PAGE + index];
		card.set = set;
		if set then
			local looks = SetLooks(set);
			TransmogUI.ShowSetCard(card, looks, set.name, TRANSMOG_SET_COMPLETION_FORMAT:format(#looks, #SLOTS), true);
		else
			card:Hide();
		end
	end

	local paging = self.PagingControls;
	paging.Text:SetFormattedText(PAGE_NUMBER_WITH_MAX or "Стр. %d/%d", self.page, self.numPages);
	paging.PrevPageButton:SetEnabled(self.page > 1);
	paging.NextPageButton:SetEnabled(self.page < self.numPages);

	if not TransmogUI.customSets then
		self.NoEntriesText:SetText(SEARCH_LOADING_TEXT or "Загрузка...");
		self.NoEntriesText:Show();
	else
		self.NoEntriesText:SetText(TRANSMOG_CUSTOM_SETS_NONE);
		self.NoEntriesText:SetShown(#list == 0);
	end
	self.NewCustomSetButton:SetEnabled(TransmogUI.customSets ~= nil and #list < TransmogUI.customSetsMax);
end

function TransmogCustomSetsFrame_ChangePage(self, delta)
	local page = (self.page or 1) + delta;
	if page < 1 or page > (self.numPages or 1) then
		return;
	end
	self.page = page;
	PlaySound("igAbiliityPageTurn");
	TransmogCustomSetsFrame_Refresh(self);
end

function TransmogCustomSetsFrame_OnLoad(self)
	self.page = 1;
	self.cards = {};
	for index = 1, CARDS_PER_PAGE do
		local card = _G[self:GetName() .. "CustomSet" .. index];
		card.onEnter = TransmogCustomSetCard_OnEnter;
		self.cards[index] = card;
	end
	self.NewCustomSetButton:SetMotionScriptsWhileDisabled(true);
	self.NewCustomSetButton:SetScript("OnEnter", function(button)
		if button:IsEnabled() ~= 1 and TransmogUI.customSets then
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
			GameTooltip:SetText(TRANSMOG_CUSTOM_SET_NEW_TOOLTIP_DISABLED_MAX_COUNT, 1, 0.1, 0.1, 1, true);
			GameTooltip:Show();
		end
	end);
	self.NewCustomSetButton:SetScript("OnLeave", GameTooltip_Hide);
end

function TransmogCustomSetsFrame_OnShow(self)
	if Comm_Send then
		Comm_Send(TransmogUI.OP_CSETS_GET);
	end
	TransmogCustomSetsFrame_Refresh(self);
end

-- ретейл: NewCustomSetButton - сохранить облик, который сейчас на персонаже
function TransmogCustomSetsFrame_NewSet()
	StaticPopup_Show("TRANSMOG_CUSTOM_SET_NAME");
end

function TransmogUI.SaveCustomSet(id, name)
	if Comm_Send then
		Comm_Send(TransmogUI.OP_CSET_SAVE, id, name, TransmogUI.FormatSlots(TransmogUI.DisplayedLooks(TransmogFrame, true)));
	end
end

function TransmogCustomSetCard_OnEnter(self)
	local set = self.set;
	if not set then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(set.name);
	for _, info in ipairs(SLOTS) do
		local itemId = set.slots[info.id];
		if itemId then
			local name, _, quality = GetItemInfo(itemId);
			local color = ITEM_QUALITY_COLORS[quality or 1];
			GameTooltip:AddDoubleLine(info.name, name or ("item:" .. itemId), 0.6, 0.6, 0.6, color.r, color.g, color.b);
		end
	end
	GameTooltip:Show();
end

-- ЛКМ - примерить комплект, ПКМ - меню: переименовать, заменить текущим обликом, удалить
function TransmogCustomSetModel_OnMouseUp(self, button)
	local set = self.set;
	if not set then
		return;
	end
	if button == "RightButton" then
		if MenuUtil and MenuUtil.CreateContextMenu then
			MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
				rootDescription:CreateTitle(set.name);
				rootDescription:CreateButton(TRANSMOG_CUSTOM_SET_RENAME, function()
					StaticPopup_Show("TRANSMOG_CUSTOM_SET_NAME", nil, nil, set);
				end);
				rootDescription:CreateButton(TRANSMOG_CUSTOM_SET_REPLACE, function()
					TransmogUI.SaveCustomSet(set.id, set.name);
				end);
				rootDescription:CreateButton(TRANSMOG_CUSTOM_SET_DELETE, function()
					StaticPopup_Show("TRANSMOG_CUSTOM_SET_DELETE", set.name, nil, set);
				end);
			end);
		else
			StaticPopup_Show("TRANSMOG_CUSTOM_SET_DELETE", set.name, nil, set);
		end
		return;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogFrame.selectedOutfit = nil;
	TransmogUI.LoadLooks(TransmogFrame, set.slots, true);
	TransmogUI.UpdateOutfits(TransmogFrame);
end

-- data: комплект для переименования, nil - новый
StaticPopupDialogs["TRANSMOG_CUSTOM_SET_NAME"] = {
	text = TRANSMOG_CUSTOM_SET_NAME,
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 24,
	OnShow = function(self)
		self.editBox:SetText(self.data and self.data.name or TRANSMOG_CUSTOM_SET_NAME_DEFAULT);
		self.editBox:HighlightText();
		self.editBox:SetFocus();
	end,
	OnAccept = function(self, data)
		local name = self.editBox:GetText();
		if not name or name == "" then
			return;
		end
		if data then
			-- переименование: облики остаются прежними
			Comm_Send(TransmogUI.OP_CSET_SAVE, data.id, name, TransmogUI.FormatSlots(data.slots));
		else
			TransmogUI.SaveCustomSet(0, name);
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent();
		StaticPopupDialogs["TRANSMOG_CUSTOM_SET_NAME"].OnAccept(parent, parent.data);
		parent:Hide();
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

StaticPopupDialogs["TRANSMOG_CUSTOM_SET_DELETE"] = {
	text = TRANSMOG_CUSTOM_SET_CONFIRM_DELETE,
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		Comm_Send(TransmogUI.OP_CSET_DEL, data.id);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	showAlert = 1,
};

if Comm_Register then
	Comm_Register(TransmogUI.OP_CSET, function(id, name, slots)
		incomingSets = incomingSets or {};
		table.insert(incomingSets, { id = tonumber(id) or 0, name = name or "", slots = TransmogUI.ParseSlots(slots) });
	end);

	Comm_Register(TransmogUI.OP_CSETS_END, function(count, max)
		TransmogUI.customSets = incomingSets or {};
		TransmogUI.customSetsMax = tonumber(max) or 0;
		incomingSets = nil;
		local frame = TransmogFrame.WardrobeCollection.TabContent.CustomSetsFrame;
		if frame:IsVisible() then
			TransmogCustomSetsFrame_Refresh(frame);
		end
	end);
end
