-- Toys tab (ToyBox) for 3.3.5.
-- The list of all toys and the learned ones come from the server
-- (server\toy_collection.cpp) through AddonComm:
--   CMSG.REQUEST_TOYS      -> SMSG.TOY_LIST "ids" : "ownedId/remainingMs/durationMs,..."
--   CMSG.USE_TOY id        -> the server casts the toy's spell, answers SMSG.TOY_COOLDOWN
--   SMSG.TOY_ADDED id      (learned a new toy)
--   SMSG.TOY_COOLDOWN id : remainingMs : durationMs
-- Names and icons: GetItemInfo; unknown items are requested through a hidden tooltip.

local COLUMNS, ROWS = 3, 6;
local PER_PAGE = COLUMNS * ROWS;
local BUTTON_WIDTH, BUTTON_HEIGHT = 208, 50;
local BUTTON_PADDING_Y = 16;

-- opcodes come from Server.lua (CMSG / SMSG); they must match AddonComm.h on the server
CMSG = CMSG or {};
SMSG = SMSG or {};
CMSG.REQUEST_TOYS = CMSG.REQUEST_TOYS or 6;
CMSG.USE_TOY = CMSG.USE_TOY or 7;
SMSG.TOY_LIST = SMSG.TOY_LIST or 6;
SMSG.TOY_ADDED = SMSG.TOY_ADDED or 7;
SMSG.TOY_COOLDOWN = SMSG.TOY_COOLDOWN or 8;

local allToys = {};         -- item ids
local toySet = {};          -- [itemId] = true
local owned = {};           -- [itemId] = true
local cooldowns = {};       -- [itemId] = { start = GetTime(), duration = seconds }

local itemQueryTooltip = CreateFrame("GameTooltip", "ToyBoxQueryTooltip", UIParent, "GameTooltipTemplate");

local function RequestItem(itemId)
	itemQueryTooltip:SetOwner(UIParent, "ANCHOR_NONE");
	itemQueryTooltip:SetHyperlink("item:" .. itemId);
	itemQueryTooltip:Hide();
end

local function SetCooldown(itemId, remainingMs, durationMs)
	remainingMs, durationMs = tonumber(remainingMs) or 0, tonumber(durationMs) or 0;
	if remainingMs > 0 and durationMs > 0 then
		cooldowns[itemId] = { start = GetTime() - (durationMs - remainingMs) / 1000, duration = durationMs / 1000 };
	else
		cooldowns[itemId] = nil;
	end
end

function ToyBox_IsToy(itemId)
	return toySet[itemId] == true;
end

function ToyBox_HasToy(itemId)
	return owned[itemId] == true;
end

---------------------------------------------------------------------------
-- list / filters
---------------------------------------------------------------------------
local function BuildList(self)
	local list = {};
	local search = (self.searchText or ""):lower();
	local filters = self.filters;
	local waiting = false;

	for _, itemId in ipairs(allToys) do
		local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId);
		if not name then
			RequestItem(itemId);
			waiting = true;
			name = "...";
		end

		local isOwned = owned[itemId] == true;
		if (isOwned and filters.collected or not isOwned and filters.notCollected)
			and (search == "" or name:lower():find(search, 1, true)) then
			table.insert(list, { itemId = itemId, name = name, icon = icon, owned = isOwned });
		end
	end

	table.sort(list, function(a, b)
		if a.owned ~= b.owned then
			return a.owned;
		end
		return a.name < b.name;
	end);

	self.list = list;
	return waiting;
end

local function UpdateCooldown(button)
	local entry = button.entry;
	local cd = entry and cooldowns[entry.itemId];
	if cd and cd.start + cd.duration > GetTime() then
		CooldownFrame_SetTimer(button.cooldown, cd.start, cd.duration, 1);
	else
		button.cooldown:Hide();
	end
end

local function UpdateButtons(self)
	local page = self.page or 1;
	local maxPages = math.max(1, math.ceil(#self.list / PER_PAGE));
	if page > maxPages then
		page = maxPages;
		self.page = page;
	end

	for index, button in ipairs(self.buttons) do
		local entry = self.list[(page - 1) * PER_PAGE + index];
		button.entry = entry;
		if entry then
			button.iconTexture:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark");
			button.iconTexture:SetDesaturated(not entry.owned);
			button.iconTexture:SetAlpha(entry.owned and 1 or 0.18);
			button.slotFrameCollected:SetShown(entry.owned);
			button.slotFrameUncollected:SetShown(not entry.owned);
			button.slotFrameUncollectedInnerGlow:SetShown(not entry.owned);
			button.name:SetText(entry.name);
			if entry.owned then
				button.name:SetTextColor(1, 0.82, 0);
			else
				button.name:SetTextColor(0.33, 0.27, 0.2);
			end
			UpdateCooldown(button);
			button:Show();
		else
			button:Hide();
		end
	end

	if not self.EmptyText then
		self.EmptyText = self.IconsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
		self.EmptyText:SetPoint("CENTER", self.Inset, "CENTER", 0, 20);
	end
	if #allToys == 0 then
		self.EmptyText:SetText(self.requested and "Сервер не прислал список игрушек" or "Загрузка...");
		self.EmptyText:Show();
	else
		self.EmptyText:Hide();
	end

	local paging = self.PagingFrame;
	paging.PageText:SetFormattedText("Стр. %d/%d", page, maxPages);
	paging.PrevPageButton:SetEnabled(page > 1);
	paging.NextPageButton:SetEnabled(page < maxPages);

	local numOwned = 0;
	for _ in pairs(owned) do
		numOwned = numOwned + 1;
	end
	self.ProgressBar:SetMinMaxValues(0, math.max(1, #allToys));
	self.ProgressBar:SetValue(numOwned);
	local progressText = self.ProgressBar.Text or self.ProgressBar.text;
	if progressText then
		progressText:SetFormattedText("%d/%d", numOwned, #allToys);
	end
end

function ToyBox_Refresh(self)
	self = self or ToyBox;
	local waiting = BuildList(self);
	UpdateButtons(self);

	if waiting and not self.refreshScheduled then
		self.refreshScheduled = true;
		self.refreshElapsed = 0;
	end
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
function ToyBox_OnLoad(self)
	self.filters = { collected = true, notCollected = true };
	self.page = 1;

	self.buttons = {};
	for index = 1, PER_PAGE do
		local button = CreateFrame("Button", "ToyBoxButton" .. index, self.IconsFrame, "ToyBoxButtonTemplate");
		local column = (index - 1) % COLUMNS;
		local row = math.floor((index - 1) / COLUMNS);
		button:SetPoint("TOPLEFT", self.IconsFrame, "TOPLEFT", 40 + column * BUTTON_WIDTH, -30 - row * (BUTTON_HEIGHT + BUTTON_PADDING_Y));
		self.buttons[index] = button;
	end

	local function SetPage(page)
		self.page = page;
		UpdateButtons(self);
		PlaySound("igAbiliityPageTurn");
	end
	self.PagingFrame.PrevPageButton:SetScript("OnClick", function() SetPage((self.page or 1) - 1); end);
	self.PagingFrame.NextPageButton:SetScript("OnClick", function() SetPage((self.page or 1) + 1); end);
	self.IconsFrame:SetScript("OnMouseWheel", function(_, delta)
		local maxPages = math.max(1, math.ceil(#self.list / PER_PAGE));
		local page = math.max(1, math.min(maxPages, (self.page or 1) - delta));
		if page ~= self.page then
			SetPage(page);
		end
	end);

	self.SearchBox:HookScript("OnTextChanged", function(searchBox)
		local text = searchBox:GetText() or "";
		if text == (SEARCH or "") then
			text = "";
		end
		self.searchText = text;
		self.page = 1;
		ToyBox_Refresh(self);
	end);

	local filter = self.FilterDropdown;
	filter:SetIsDefaultCallback(function()
		return self.filters.collected and self.filters.notCollected;
	end);
	filter:SetDefaultCallback(function()
		self.filters.collected, self.filters.notCollected = true, true;
	end);
	filter:SetUpdateCallback(function() ToyBox_Refresh(self); end);
	filter:SetupMenu(function(dropdown, rootDescription)
		for _, info in ipairs({ { "collected", COLLECTED or "Полученные" }, { "notCollected", "Не полученные" } }) do
			local key = info[1];
			rootDescription:CreateCheckbox(info[2], function()
				return self.filters[key];
			end, function()
				self.filters[key] = not self.filters[key];
				filter:ValidateResetState();
				ToyBox_Refresh(self);
			end);
		end
	end);

	self:SetScript("OnUpdate", function(frame, elapsed)
		if frame.requestElapsed then
			frame.requestElapsed = frame.requestElapsed + elapsed;
			if frame.requestElapsed > 3 then
				frame.requestElapsed = nil;
				frame.requested = true;
				UpdateButtons(frame);
			end
		end
		if not frame.refreshScheduled then
			return;
		end
		frame.refreshElapsed = frame.refreshElapsed + elapsed;
		if frame.refreshElapsed > 1 then
			frame.refreshScheduled = false;
			ToyBox_Refresh(frame);
		end
	end);

	self.list = {};
end

function ToyBox_OnShow(self)
	if Comm_Send then
		Comm_Send(CMSG.REQUEST_TOYS);
		self.requested = nil;
		self.requestElapsed = 0;
	end
	ToyBox_Refresh(self);
end

---------------------------------------------------------------------------
-- buttons
---------------------------------------------------------------------------
function ToyBox_UseToy(itemId)
	if not owned[itemId] then
		return;
	end
	local cd = cooldowns[itemId];
	if cd and cd.start + cd.duration > GetTime() then
		UIErrorsFrame:AddMessage(ERR_ITEM_COOLDOWN or "Предмет еще не готов.", 1.0, 0.1, 0.1, 1.0);
		return;
	end
	if Comm_Send then
		Comm_Send(CMSG.USE_TOY, itemId);
	end
end

function ToyBoxButton_OnClick(self, mouseButton)
	local entry = self.entry;
	if not entry then
		return;
	end
	if IsModifiedClick("CHATLINK") then
		local _, link = GetItemInfo(entry.itemId);
		if link then
			ChatEdit_InsertLink(link);
		end
		return;
	end
	ToyBox_UseToy(entry.itemId);
end

function ToyBoxButton_OnEnter(self)
	if not self.entry then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink("item:" .. self.entry.itemId);
	GameTooltip:AddLine(" ");
	if self.entry.owned then
		GameTooltip:AddLine("Щелчок - использовать игрушку.", 0.1, 1, 0.1, true);
	else
		GameTooltip:AddLine("Не получено. Получите этот предмет, чтобы добавить его в коллекцию.", 1, 0.1, 0.1, true);
	end
	GameTooltip:Show();
end

-- подпись «Игрушка» в подсказке предмета (сумки, чат, добыча)
GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
	local _, link = tooltip:GetItem();
	local itemId = link and tonumber(link:match("item:(%d+)"));
	if itemId and toySet[itemId] then
		if owned[itemId] then
			tooltip:AddLine("Игрушка (уже в коллекции)", 0.53, 0.67, 1);
		else
			tooltip:AddLine("Игрушка: получите, чтобы добавить в коллекцию", 0.53, 0.67, 1);
		end
		tooltip:Show();
	end
end);

---------------------------------------------------------------------------
-- server messages
---------------------------------------------------------------------------
local function RefreshIfShown()
	if ToyBox:IsShown() then
		ToyBox_Refresh(ToyBox);
	end
end

if Comm_Register then
	Comm_Register(SMSG.TOY_LIST, function(allText, ownedText)
		ToyBox.requestElapsed = nil;
		local newList, newSet = {}, {};
		for id in (allText or ""):gmatch("(%d+)") do
			id = tonumber(id);
			table.insert(newList, id);
			newSet[id] = true;
		end
		allToys, toySet = newList, newSet;
		owned = {};
		for id, remaining, duration in (ownedText or ""):gmatch("(%d+)/(%d+)/(%d+)") do
			id = tonumber(id);
			owned[id] = true;
			SetCooldown(id, remaining, duration);
		end
		RefreshIfShown();
	end);

	Comm_Register(SMSG.TOY_ADDED, function(itemId)
		itemId = tonumber(itemId);
		if itemId then
			owned[itemId] = true;
			if not toySet[itemId] then
				toySet[itemId] = true;
				table.insert(allToys, itemId);
			end
			local _, link = GetItemInfo(itemId);
			DEFAULT_CHAT_FRAME:AddMessage(("Новая игрушка в коллекции: %s"):format(link or ("item:" .. itemId)), 0.53, 0.67, 1);
			RefreshIfShown();
		end
	end);

	Comm_Register(SMSG.TOY_COOLDOWN, function(itemId, remaining, duration)
		itemId = tonumber(itemId);
		if itemId then
			SetCooldown(itemId, remaining, duration);
			if ToyBox:IsShown() then
				for _, button in ipairs(ToyBox.buttons) do
					if button.entry and button.entry.itemId == itemId then
						UpdateCooldown(button);
					end
				end
			end
		end
	end);
end

-- список нужен и для подсказок в сумках: спросим сервер после входа
local loginFrame = CreateFrame("Frame");
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
loginFrame:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents();
	if Comm_Send then
		Comm_Send(CMSG.REQUEST_TOYS);
	end
end);
