-- «Внешний вид»: вкладки «Предметы» / «Наборы» (ретейл: WardrobeCollectionFrame.SetsCollectionFrame) для 3.3.5.
-- Комплекты те же, что во вкладке «Наборы» окна трансмогрификации (server/transmog_sets.cpp, TransmogUI.sets):
-- ItemSet.dbc для класса персонажа, карточки - TransmogSetModelTemplate (Transmog\Blizzard_TransmogTemplates.xml).
-- Щелчок по карточке - примерить комплект в «Примерочной».

local CARD_COLUMNS, CARD_ROWS = 3, 2;
local CARD_WIDTH, CARD_HEIGHT, CARD_SPACE_X, CARD_SPACE_Y = 178, 218, 40, 22;

local state = { page = 1, search = "" };

local function GetFrame()
	return WardrobeCollectionFrame;
end

local function SetName(set)
	return set.items[1] and TransmogUI.GetSetName(set.id, set.items[1].id);
end

local function GetFilteredSets()
	local list = {};
	local search = strlower(state.search or "");
	for _, set in ipairs(TransmogUI and TransmogUI.sets or {}) do
		local name = SetName(set);
		if search == "" or (name and strlower(name):find(search, 1, true)) then
			table.insert(list, set);
		end
	end
	return list;
end

function WardrobeSets_Refresh()
	local frame = GetFrame();
	local setsFrame = frame.SetsCollectionFrame;
	if not setsFrame:IsShown() or not setsFrame.cards then
		return;
	end
	local list = GetFilteredSets();
	local perPage = CARD_COLUMNS * CARD_ROWS;
	state.numPages = math.max(1, math.ceil(#list / perPage));
	state.page = math.min(state.page, state.numPages);
	setsFrame.missingNames = false;

	for index, card in ipairs(setsFrame.cards) do
		local set = list[(state.page - 1) * perPage + index];
		card.set = set;
		if set then
			local looks = {};
			for _, item in ipairs(set.items) do
				table.insert(looks, item.id);
			end
			local name = SetName(set);
			setsFrame.missingNames = setsFrame.missingNames or not name;
			TransmogUI.ShowSetCard(card, looks, name or SEARCH_LOADING_TEXT or "...",
				TRANSMOG_SET_COMPLETION_FORMAT:format(set.numCollected, #set.items), set.numCollected == #set.items);
		else
			card:Hide();
		end
	end

	local paging = setsFrame.PagingFrame;
	paging.PageText:SetFormattedText(PAGE_NUMBER_WITH_MAX or "Стр. %d/%d", state.page, state.numPages);
	paging.PrevPageButton:SetEnabled(state.page > 1);
	paging.NextPageButton:SetEnabled(state.page < state.numPages);

	if not TransmogUI.sets then
		setsFrame.NoEntriesText:SetText(SEARCH_LOADING_TEXT or "Загрузка...");
		setsFrame.NoEntriesText:Show();
	else
		setsFrame.NoEntriesText:SetText(TRANSMOG_SETS_NONE);
		setsFrame.NoEntriesText:SetShown(#list == 0);
	end

	-- полоса прогресса: собранные комплекты
	local complete = 0;
	for _, set in ipairs(TransmogUI.sets or {}) do
		if set.numCollected == #set.items then
			complete = complete + 1;
		end
	end
	local total = TransmogUI.sets and #TransmogUI.sets or 0;
	frame.ProgressBar:SetMinMaxValues(0, math.max(1, total));
	frame.ProgressBar:SetValue(complete);
	frame.ProgressBar.Text:SetFormattedText("%d/%d", complete, total);
end

function WardrobeSets_ChangePage(delta)
	local page = state.page + delta;
	if page < 1 or page > (state.numPages or 1) then
		return;
	end
	state.page = page;
	PlaySound("igAbiliityPageTurn");
	WardrobeSets_Refresh();
end

function WardrobeSets_SetSearch(text)
	if text ~= state.search then
		state.search = text;
		state.page = 1;
		WardrobeSets_Refresh();
	end
end

-- данные пришли с сервера (Transmog\Blizzard_TransmogSets.lua)
function WardrobeSets_OnSetsLoaded()
	if WardrobeCollectionFrame:IsVisible() then
		WardrobeSets_Refresh();
	end
end

local function Card_OnEnter(card)
	if TransmogSetCard_OnEnter then
		TransmogSetCard_OnEnter(card);
	end
end

-- «Примерочная»: весь комплект на персонаже
local function Card_OnMouseUp(card, button)
	local set = card.set;
	if not set or button ~= "LeftButton" then
		return;
	end
	if DressUpFrame and not DressUpFrame:IsShown() then
		ShowUIPanel(DressUpFrame);
	end
	if DressUpModel then
		DressUpModel:SetUnit("player");
		DressUpModel:Undress();
		for _, item in ipairs(set.items) do
			DressUpModel:TryOn("item:" .. item.id);
		end
	end
end

local function SelectTab(frame, sets)
	frame.setsMode = sets;
	PanelTemplates_SetTab(frame.tabHolder, sets and 2 or 1);
	frame.ItemsCollectionFrame:SetShown(not sets);
	frame.SetsCollectionFrame:SetShown(sets);
	frame.FilterDropdown:SetShown(not sets);
	frame.SearchBox:SetText(sets and state.search or (frame.searchText or ""));
	if sets then
		WardrobeSets_Show(frame);
	else
		WardrobeCollectionFrame_OnShow(frame);
	end
end

-- вкладки и карточки создаются при первом показе: шаблоны трансмогрификации загружаются после коллекций
function WardrobeSets_Init(frame)
	if frame.tabHolder or not TransmogUI or not TransmogUI.ShowSetCard then
		return;
	end

	local holder = CreateFrame("Frame", "WardrobeCollectionFrameTabs", frame);
	holder:SetSize(1, 1);
	holder.Tabs = {};
	local names = { TRANSMOG_TAB_ITEMS, TRANSMOG_TAB_SETS };
	for index, text in ipairs(names) do
		local tab = CreateFrame("Button", "WardrobeCollectionFrameTabsTab" .. index, holder, "TabButtonTemplate");
		tab:SetID(index);
		tab:SetText(text);
		PanelTemplates_TabResize(tab, 0);
		if index == 1 then
			tab:SetPoint("BOTTOMLEFT", frame.Inset, "TOPLEFT", 62, -2);
		else
			tab:SetPoint("LEFT", holder.Tabs[index - 1], "RIGHT", 0, 0);
		end
		tab:SetScript("OnClick", function(self)
			PlaySound("igCharacterInfoTab");
			SelectTab(frame, self:GetID() == 2);
		end);
		holder.Tabs[index] = tab;
	end
	holder.numTabs = #names;
	frame.tabHolder = holder;
	PanelTemplates_SetNumTabs(holder, #names);
	PanelTemplates_SetTab(holder, 1);

	local setsFrame = frame.SetsCollectionFrame;
	setsFrame.cards = {};
	for row = 1, CARD_ROWS do
		for column = 1, CARD_COLUMNS do
			local card = CreateFrame("DressUpModel", nil, setsFrame, "TransmogSetBaseModelTemplate");
			card:SetPoint("TOPLEFT", setsFrame, "TOPLEFT", 40 + (column - 1) * (CARD_WIDTH + CARD_SPACE_X), -20 - (row - 1) * (CARD_HEIGHT + CARD_SPACE_Y));
			card.onEnter = Card_OnEnter;
			card:SetScript("OnMouseUp", Card_OnMouseUp);
			card:Hide();
			table.insert(setsFrame.cards, card);
		end
	end

	setsFrame:SetScript("OnUpdate", function(self, elapsed)
		self.nameTimer = (self.nameTimer or 0) + elapsed;
		if self.nameTimer > 0.5 then
			self.nameTimer = 0;
			if self.missingNames then
				self.missingNames = false;
				for _, card in ipairs(self.cards) do
					if card.set and card:IsShown() then
						local name = SetName(card.set);
						self.missingNames = self.missingNames or not name;
						card.Overlay.Name:SetText(name or SEARCH_LOADING_TEXT or "...");
					end
				end
			end
		end
	end);
end

function WardrobeSets_Show(frame)
	if (not TransmogUI.sets or TransmogUI.setsStale) and Comm_Send then
		TransmogUI.setsStale = false;
		Comm_Send(TransmogUI.OP_SETS_GET);
	end
	WardrobeSets_Refresh();
end
