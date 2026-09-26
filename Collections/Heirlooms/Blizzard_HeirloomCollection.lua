-- Heirlooms tab (HeirloomsJournal) for 3.3.5.
-- The list of all heirlooms and the learned ones come from the server
-- (server\heirloom_collection.cpp) through AddonComm:
--   CMSG.REQUEST_HEIRLOOMS    -> SMSG.HEIRLOOM_LIST "all,ids" : "owned,ids"
--   CMSG.CREATE_HEIRLOOM id   -> item appears in the bags
--   SMSG.HEIRLOOM_ADDED id    (learned a new heirloom)
-- Names and icons: GetItemInfo; unknown items are requested through a hidden tooltip.

local COLUMNS, ROWS = 3, 6;
local PER_PAGE = COLUMNS * ROWS;
local BUTTON_WIDTH, BUTTON_HEIGHT = 208, 50;
local BUTTON_PADDING_Y = 16;

-- opcodes come from Server.lua (CMSG / SMSG); they must match AddonComm.h on the server
CMSG = CMSG or {};
SMSG = SMSG or {};

local allHeirlooms = {};    -- item ids
local classMasks = {};      -- [itemId] = AllowableClass mask (0 = all classes)

-- 3.3.5 class ids (AllowableClass bit = classId - 1)
local CLASS_IDS = {
	WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6,
	SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
};

local function IsForClass(itemId, classFile)
	if not classFile then
		return true;
	end
	local mask = classMasks[itemId] or 0;
	if mask == 0 then
		return true;
	end
	local bit = 2 ^ (CLASS_IDS[classFile] - 1);
	return math.floor(mask / bit) % 2 == 1;
end
local owned = {};           -- [itemId] = true

local itemQueryTooltip = CreateFrame("GameTooltip", "HeirloomsJournalQueryTooltip", UIParent, "GameTooltipTemplate");

-- 3.3.5: GetItemInfo is nil until the item is cached; an item hyperlink in a tooltip asks the server
local function RequestItem(itemId)
	itemQueryTooltip:SetOwner(UIParent, "ANCHOR_NONE");
	itemQueryTooltip:SetHyperlink("item:" .. itemId);
	itemQueryTooltip:Hide();
end

local function SplitIds(text)
	local ids = {};
	for id in (text or ""):gmatch("(%d+)") do
		table.insert(ids, tonumber(id));
	end
	return ids;
end

---------------------------------------------------------------------------
-- list / filters
---------------------------------------------------------------------------
local function BuildList(self)
	local list = {};
	local search = (self.searchText or ""):lower();
	local filters = self.filters;
	local waiting = false;

	for _, itemId in ipairs(allHeirlooms) do
		local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemId);
		if not name then
			RequestItem(itemId);
			waiting = true;
			name = "...";
		end

		local isOwned = owned[itemId] == true;
		if IsForClass(itemId, self.classFilter)
			and (isOwned and filters.collected or not isOwned and filters.notCollected)
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
			button:Show();
		else
			button:Hide();
		end
	end

	if not self.EmptyText then
		self.EmptyText = self.IconsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
		self.EmptyText:SetPoint("CENTER", self.Inset, "CENTER", 0, 20);
	end
	if #allHeirlooms == 0 then
		self.EmptyText:SetText(self.requested and "Сервер не прислал список наследуемых предметов" or "Загрузка...");
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
	self.ProgressBar:SetMinMaxValues(0, math.max(1, #allHeirlooms));
	self.ProgressBar:SetValue(numOwned);
	local progressText = self.ProgressBar.Text or self.ProgressBar.text;
	if progressText then
		progressText:SetFormattedText("%d/%d", numOwned, #allHeirlooms);
	end
end

function HeirloomsJournal_Refresh(self)
	self = self or HeirloomsJournal;
	local waiting = BuildList(self);
	UpdateButtons(self);

	-- names of just requested items arrive a moment later
	if waiting and not self.refreshScheduled then
		self.refreshScheduled = true;
		self.refreshElapsed = 0;
	end
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
function HeirloomsJournal_OnLoad(self)
	-- class filter: player's class by default, like retail
	local _, playerClass = UnitClass("player");
	self.classFilter = playerClass;
	local classOrder = CLASS_SORT_ORDER or { "WARRIOR", "DEATHKNIGHT", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER" };
	local function ClassLabel(classFile)
		if not classFile then
			return ALL_CLASSES or "Все классы";
		end
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or classFile;
		local color = RAID_CLASS_COLORS[classFile];
		if color then
			return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name);
		end
		return name;
	end
	local classDropdown = self.ClassDropdown;
	classDropdown:SetupMenu(function(dropdown, rootDescription)
		local function IsSelected(classFile)
			return self.classFilter == classFile;
		end
		local function SetSelected(classFile)
			self.classFilter = classFile;
			self.page = 1;
			HeirloomsJournal_Refresh(self);
		end
		rootDescription:CreateRadio(ClassLabel(nil), function() return self.classFilter == nil; end, function()
			SetSelected(nil);
		end);
		for _, classFile in ipairs(classOrder) do
			if CLASS_IDS[classFile] then
				rootDescription:CreateRadio(ClassLabel(classFile), IsSelected, SetSelected, classFile);
			end
		end
	end);
	if classDropdown.SetText then
		classDropdown:SetText(ClassLabel(playerClass));
	end

	self.filters = { collected = true, notCollected = true };
	self.page = 1;

	self.buttons = {};
	for index = 1, PER_PAGE do
		local button = CreateFrame("Button", "HeirloomsJournalButton" .. index, self.IconsFrame, "HeirloomsJournalButtonTemplate");
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
		HeirloomsJournal_Refresh(self);
	end);

	local filter = self.FilterDropdown;
	filter:SetIsDefaultCallback(function()
		return self.filters.collected and self.filters.notCollected;
	end);
	filter:SetDefaultCallback(function()
		self.filters.collected, self.filters.notCollected = true, true;
	end);
	filter:SetUpdateCallback(function() HeirloomsJournal_Refresh(self); end);
	filter:SetupMenu(function(dropdown, rootDescription)
		for _, info in ipairs({ { "collected", COLLECTED or "Полученные" }, { "notCollected", "Не полученные" } }) do
			local key = info[1];
			rootDescription:CreateCheckbox(info[2], function()
				return self.filters[key];
			end, function()
				self.filters[key] = not self.filters[key];
				filter:ValidateResetState();
				HeirloomsJournal_Refresh(self);
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
			HeirloomsJournal_Refresh(frame);
		end
	end);

	self.list = {};
end

function HeirloomsJournal_OnShow(self)
	if Comm_Send and CMSG.REQUEST_HEIRLOOMS then
		Comm_Send(CMSG.REQUEST_HEIRLOOMS);
		-- no answer in 3 s -> say so instead of "Загрузка..."
		self.requested = nil;
		self.requestElapsed = 0;
	end
	HeirloomsJournal_Refresh(self);
end

---------------------------------------------------------------------------
-- buttons
---------------------------------------------------------------------------
function HeirloomsJournalButton_OnClick(self, mouseButton)
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
	if mouseButton == "LeftButton" and entry.owned then
		HeirloomsJournal_CreateHeirloom(entry.itemId);
	end
end

---------------------------------------------------------------------------
-- creating an heirloom: confirmation if one already exists, then a short "cast"
---------------------------------------------------------------------------
local CREATE_CAST_TIME = 1.5;

local creator = CreateFrame("Frame");
creator:Hide();
creator:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = self.elapsed + elapsed;
	if self.elapsed >= CREATE_CAST_TIME then
		self:Hide();
		if Comm_Send and CMSG.CREATE_HEIRLOOM then
			Comm_Send(CMSG.CREATE_HEIRLOOM, self.itemId);
		end
		self.itemId = nil;
	end
end);

local function StartCreate(itemId)
	if creator:IsShown() then
		return;   -- one at a time
	end
	creator.itemId, creator.elapsed = itemId, 0;
	creator:Show();

	-- show the "cast" on the button: cooldown swipe for the cast time
	for _, button in ipairs(HeirloomsJournal.buttons or {}) do
		if button.entry and button.entry.itemId == itemId and button.cooldown then
			CooldownFrame_SetTimer(button.cooldown, GetTime(), CREATE_CAST_TIME, 1);
		end
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
end

StaticPopupDialogs["HEIRLOOM_CREATE_ANOTHER"] = {
	text = "У вас уже есть %s.\nСоздать ещё один?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, itemId)
		StartCreate(itemId);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

function HeirloomsJournal_CreateHeirloom(itemId)
	if GetItemCount(itemId, true) > 0 then
		local _, link = GetItemInfo(itemId);
		local dialog = StaticPopup_Show("HEIRLOOM_CREATE_ANOTHER", link or ("item:" .. itemId));
		if dialog then
			dialog.data = itemId;
		end
		return;
	end
	StartCreate(itemId);
end

function HeirloomsJournalButton_OnEnter(self)
	if not self.entry then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink("item:" .. self.entry.itemId);
	GameTooltip:AddLine(" ");
	if self.entry.owned then
		GameTooltip:AddLine("Щелчок - создать предмет в сумке.", 0.1, 1, 0.1, true);
	else
		GameTooltip:AddLine("Не получено. Получите этот предмет, чтобы добавить его в коллекцию.", 1, 0.1, 0.1, true);
	end
	GameTooltip:Show();
end

---------------------------------------------------------------------------
-- server messages
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register(SMSG.HEIRLOOM_LIST, function(allText, ownedText)
		HeirloomsJournal.requestElapsed = nil;
		local newList, newMasks = {}, {};
		for itemId, mask in (allText or ""):gmatch("(%d+)/(%d+)") do
			itemId = tonumber(itemId);
			table.insert(newList, itemId);
			newMasks[itemId] = tonumber(mask);
		end
		-- not a list (e.g. a single item id from HEIRLOOM_ADDED sent under the same opcode):
		-- never wipe the journal with it
		if #newList == 0 then
			local itemId = tonumber(allText);
			if itemId then
				owned[itemId] = true;
				if HeirloomsJournal:IsShown() then
					HeirloomsJournal_Refresh(HeirloomsJournal);
				end
			end
			return;
		end
		allHeirlooms, classMasks = newList, newMasks;
		owned = {};
		for _, id in ipairs(SplitIds(ownedText)) do
			owned[id] = true;
		end
		if HeirloomsJournal:IsShown() then
			HeirloomsJournal_Refresh(HeirloomsJournal);
		end
	end);

	Comm_Register(SMSG.HEIRLOOM_ADDED, function(itemId)
		itemId = tonumber(itemId);
		if itemId then
			owned[itemId] = true;
			if HeirloomsJournal:IsShown() then
				HeirloomsJournal_Refresh(HeirloomsJournal);
			end
		end
	end);
end
