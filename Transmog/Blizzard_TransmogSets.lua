-- Трансмогрификация: вкладка «Наборы» (ретейл: TransmogWardrobeSetsMixin) и карточки комплектов (TransmogSetBaseModelMixin).
-- Комплекты - ItemSet.dbc (item_template.itemset) для класса персонажа, с сервера (server/transmog_sets.cpp):
--   "TMOG_SETS_GET" -> "TMOG_SET" : setId : "itemId/collected,..." (x N), "TMOG_SETS_END" : count
-- Название комплекта берётся из подсказки предмета («Название (0/5)»).

local SLOTS = TransmogUI.SLOTS;
local CARDS_PER_PAGE = 9;

TransmogUI.sets = nil;         -- { id, items = { { id, collected } }, numCollected }
TransmogUI.setsStale = true;   -- перезапросить при следующем показе вкладки
local incomingSets;

---------------------------------------------------------------------------
-- set cards (TransmogSetBaseModelTemplate): model.looks = { itemId, ... }
---------------------------------------------------------------------------
function TransmogUI.DressSetModel(model)
	if not model.unitSet then
		model:SetUnit("player");
		model.unitSet = true;
	end
	model:Undress();
	for _, itemId in ipairs(model.looks or {}) do
		model:TryOn("item:" .. itemId);
	end
	model:SetPosition(0, 0, 0);
	model:SetFacing(0);
end

function TransmogUI.ShowSetCard(model, looks, name, progress, complete)
	model.looks = looks;
	model.Overlay.Name:SetText(name or "");
	model.Overlay.Progress:SetText(progress or "");
	model.Overlay.IncompleteOverlay:SetShown(not complete);
	model:Show();
	TransmogUI.DressSetModel(model);
	model.redressIndex, model.redressTime = 1, TransmogUI.REDRESS_DELAYS[1];
end

function TransmogSetModel_OnLoad(self)
	self.Overlay:SetFrameLevel(self:GetFrameLevel() + 2);
end

function TransmogSetModel_OnUpdate(self, elapsed)
	if self.redressTime then
		self.redressTime = self.redressTime - elapsed;
		if self.redressTime <= 0 then
			TransmogUI.DressSetModel(self);
			self.redressIndex = (self.redressIndex or 1) + 1;
			self.redressTime = TransmogUI.REDRESS_DELAYS[self.redressIndex];
		end
	end
end

function TransmogSetModel_OnEnter(self)
	self.Overlay.Highlight:Show();
	if self.onEnter then
		self.onEnter(self);
	end
end

function TransmogSetModel_OnLeave(self)
	self.Overlay.Highlight:Hide();
	GameTooltip_Hide();
end

-- облики комплекта по ячейкам; одноручное оружие - сначала в правую руку, второе - в левую
function TransmogUI.LooksBySlot(itemIds)
	local looks = {};
	for _, itemId in ipairs(itemIds) do
		local slotId = TransmogUI.GetItemSlot(itemId);
		if slotId == 16 and looks[16] then
			local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId);
			if equipLoc == "INVTYPE_WEAPON" then
				slotId = 17;
			end
		end
		if slotId and not looks[slotId] then
			looks[slotId] = itemId;
		end
	end
	return looks;
end

---------------------------------------------------------------------------
-- sets tab
---------------------------------------------------------------------------
local function SetName(set)
	return set.items[1] and TransmogUI.GetSetName(set.id, set.items[1].id);
end

local function GetFilteredSets(self)
	local list = {};
	local search = strlower(self.searchText or "");
	for _, set in ipairs(TransmogUI.sets or {}) do
		local complete = set.numCollected == #set.items;
		if (complete and self.showComplete) or (not complete and self.showIncomplete) then
			local name = SetName(set);
			if search == "" or (name and strlower(name):find(search, 1, true)) then
				table.insert(list, set);
			end
		end
	end
	return list;
end

function TransmogSetsFrame_Refresh(self)
	local list = GetFilteredSets(self);
	self.numPages = math.max(1, math.ceil(#list / CARDS_PER_PAGE));
	self.page = math.min(self.page or 1, self.numPages);
	self.missingNames = false;

	for index, card in ipairs(self.cards) do
		local set = list[(self.page - 1) * CARDS_PER_PAGE + index];
		card.set = set;
		if set then
			local looks = {};
			for _, item in ipairs(set.items) do
				table.insert(looks, item.id);
			end
			local name = SetName(set);
			self.missingNames = self.missingNames or not name;
			TransmogUI.ShowSetCard(card, looks, name or SEARCH_LOADING_TEXT or "...",
				TRANSMOG_SET_COMPLETION_FORMAT:format(set.numCollected, #set.items), set.numCollected == #set.items);
		else
			card:Hide();
		end
	end

	local paging = self.PagingControls;
	paging.Text:SetFormattedText(PAGE_NUMBER_WITH_MAX or "Стр. %d/%d", self.page, self.numPages);
	paging.PrevPageButton:SetEnabled(self.page > 1);
	paging.NextPageButton:SetEnabled(self.page < self.numPages);
	paging:SetShown(TransmogUI.sets ~= nil);

	if not TransmogUI.sets then
		self.NoEntriesText:SetText(SEARCH_LOADING_TEXT or "Загрузка...");
		self.NoEntriesText:Show();
	else
		self.NoEntriesText:SetText(TRANSMOG_SETS_NONE);
		self.NoEntriesText:SetShown(#list == 0);
	end
end

function TransmogSetsFrame_ChangePage(self, delta)
	local page = (self.page or 1) + delta;
	if page < 1 or page > (self.numPages or 1) then
		return;
	end
	self.page = page;
	PlaySound("igAbiliityPageTurn");
	TransmogSetsFrame_Refresh(self);
end

function TransmogSetsFrame_OnLoad(self)
	self.page = 1;
	self.showComplete, self.showIncomplete = true, true;
	self.cards = {};
	for index = 1, CARDS_PER_PAGE do
		local card = _G[self:GetName() .. "Set" .. index];
		card.onEnter = TransmogSetCard_OnEnter;
		self.cards[index] = card;
	end

	local filter = self.FilterButton;
	filter:SetIsDefaultCallback(function()
		return self.showComplete and self.showIncomplete;
	end);
	filter:SetDefaultCallback(function()
		self.showComplete, self.showIncomplete = true, true;
		self.page = 1;
		TransmogSetsFrame_Refresh(self);
	end);
	filter:SetupMenu(function(dropdown, rootDescription)
		rootDescription:CreateCheckbox(TRANSMOG_SET_COMPLETE, function() return self.showComplete; end, function()
			self.showComplete = not self.showComplete;
			self.page = 1;
			TransmogSetsFrame_Refresh(self);
		end);
		rootDescription:CreateCheckbox(TRANSMOG_SET_INCOMPLETE, function() return self.showIncomplete; end, function()
			self.showIncomplete = not self.showIncomplete;
			self.page = 1;
			TransmogSetsFrame_Refresh(self);
		end);
	end);

	self.SearchBox:HookScript("OnTextChanged", function(box)
		local text = box:GetText() or "";
		if text == (SEARCH or "") then
			text = "";
		end
		if text ~= (self.searchText or "") then
			self.searchText = text;
			self.page = 1;
			TransmogSetsFrame_Refresh(self);
		end
	end);

	-- названия комплектов приходят вместе с данными предметов
	self:SetScript("OnUpdate", function(frame, elapsed)
		frame.nameTimer = (frame.nameTimer or 0) + elapsed;
		if frame.nameTimer > 0.5 then
			frame.nameTimer = 0;
			if frame.missingNames then
				frame.missingNames = false;
				for _, card in ipairs(frame.cards) do
					if card.set and card:IsShown() then
						local name = SetName(card.set);
						frame.missingNames = frame.missingNames or not name;
						card.Overlay.Name:SetText(name or SEARCH_LOADING_TEXT or "...");
					end
				end
			end
		end
	end);
end

function TransmogSetsFrame_OnShow(self)
	if (TransmogUI.setsStale or not TransmogUI.sets) and Comm_Send then
		TransmogUI.setsStale = false;
		Comm_Send(TransmogUI.OP_SETS_GET);
	end
	TransmogSetsFrame_Refresh(self);
end

function TransmogSetCard_OnEnter(self)
	local set = self.set;
	if not set then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(SetName(set) or "");
	GameTooltip:AddLine(set.numCollected == #set.items and TRANSMOG_SET_COMPLETE or TRANSMOG_SET_INCOMPLETE, 1, 0.82, 0);
	for _, item in ipairs(set.items) do
		local name, _, quality = GetItemInfo(item.id);
		if item.collected then
			local color = ITEM_QUALITY_COLORS[quality or 1];
			GameTooltip:AddLine(name or ("item:" .. item.id), color.r, color.g, color.b);
		else
			GameTooltip:AddLine((name or ("item:" .. item.id)) .. " - " .. TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN, 0.5, 0.5, 0.5);
		end
	end
	GameTooltip:Show();
end

-- ретейл: TransmogSetModelMixin:OnMouseUp - примерить собранные облики комплекта
function TransmogSetModel_OnMouseUp(self, button)
	local set = self.set;
	if not set or button ~= "LeftButton" then
		return;
	end
	local collected = {};
	for _, item in ipairs(set.items) do
		if item.collected then
			table.insert(collected, item.id);
		end
	end
	if #collected == 0 then
		UIErrorsFrame:AddMessage(TRANSMOGRIFY_STYLE_UNCOLLECTED, 1.0, 0.1, 0.1, 1.0);
		return;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogFrame.selectedOutfit = nil;
	TransmogUI.LoadLooks(TransmogFrame, TransmogUI.LooksBySlot(collected), false);
	TransmogUI.UpdateOutfits(TransmogFrame);
end

---------------------------------------------------------------------------
-- server messages
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register(TransmogUI.OP_SET, function(setId, itemsText)
		incomingSets = incomingSets or {};
		local set = { id = tonumber(setId) or 0, items = {}, numCollected = 0 };
		for itemId, collected in (itemsText or ""):gmatch("(%d+)/(%d)") do
			local isCollected = collected == "1";
			table.insert(set.items, { id = tonumber(itemId), collected = isCollected });
			if isCollected then
				set.numCollected = set.numCollected + 1;
			end
		end
		table.insert(incomingSets, set);
	end);

	Comm_Register(TransmogUI.OP_SETS_END, function()
		local sets = incomingSets or {};
		incomingSets = nil;
		-- сначала почти собранные, затем новые
		table.sort(sets, function(a, b)
			local ra, rb = a.numCollected / #a.items, b.numCollected / #b.items;
			if ra ~= rb then
				return ra > rb;
			end
			return a.id > b.id;
		end);
		TransmogUI.sets = sets;
		local frame = TransmogFrame.WardrobeCollection.TabContent.SetsFrame;
		if frame:IsVisible() then
			TransmogSetsFrame_Refresh(frame);
		end
		if WardrobeSets_OnSetsLoaded then
			WardrobeSets_OnSetsLoaded();   -- «Внешний вид» в коллекциях
		end
	end);
end
