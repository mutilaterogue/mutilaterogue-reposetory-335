-- ContainerFrameCombinedBags (retail) for 3.3.5: the backpack and bags 1-4 in one window.
--
-- The global bag functions (ToggleBackpack, ToggleBag, OpenAllBags, ...) are wrapped: bags 0-4 go
-- to the combined window while it is enabled, bank bags and the keyring keep the 3.3.5 frames.
-- Right click on the portrait switches between the combined window and separate bags.
--
-- 3.3.5 has no C_Container.SortBags or C_NewItems: sorting moves items one swap at a time, new
-- items are tracked here. The textures are the retail bag atlases (AtlasInfo.lua / SetAtlas).

local COLUMNS = 10;
local BUTTON_SIZE = 37;
local SPACING = 5;
local PADDING_WIDTH = 15;
local PADDING_TOP = 62;			-- title bar + search row
local PADDING_BOTTOM = 32;		-- money row
local FIRST_BAG, LAST_BAG = 0, NUM_BAG_SLOTS;	-- backpack .. bag 4

local SEARCH_ALPHA = 0.4;
local SORT_STEP_DELAY = 0.1;
local SORT_MAX_STEPS = 400;

local useCombined = true;

-- retail NEW_ITEM_ATLAS_BY_QUALITY
local NEW_ITEM_ATLAS_BY_QUALITY = {
	[0] = "bags-glow-white",
	[1] = "bags-glow-white",
	[2] = "bags-glow-green",
	[3] = "bags-glow-blue",
	[4] = "bags-glow-purple",
	[5] = "bags-glow-orange",
	[6] = "bags-glow-artifact",
	[7] = "bags-glow-heirloom",
};

-- original 3.3.5 functions: bank bags, keyring and the "separate bags" mode use them
local orig = {
	ToggleBackpack = ToggleBackpack,
	ToggleBag = ToggleBag,
	OpenBag = OpenBag,
	CloseBag = CloseBag,
	OpenBackpack = OpenBackpack,
	CloseBackpack = CloseBackpack,
	IsBagOpen = IsBagOpen,
	OpenAllBags = OpenAllBags,
	CloseAllBags = CloseAllBags,
	GetBackpackFrame = GetBackpackFrame,
	UpdateItemSearchResults = UpdateItemSearchResults,
};

local function IsCombinedBag(id)
	return useCombined and id and id >= FIRST_BAG and id <= LAST_BAG;
end

---------------------------------------------------------------------------
-- new items: 3.3.5 has no C_NewItems, remember what was in the bags when they were last seen
---------------------------------------------------------------------------
local knownItems;		-- [itemID] = true, everything seen in the bags
local newSlots = {};	-- ["bag:slot"] = true

local function ItemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)"));
end

local function ScanKnownItems()
	knownItems = {};
	newSlots = {};
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, GetContainerNumSlots(bag) do
			local itemID = ItemIDFromLink(GetContainerItemLink(bag, slot));
			if itemID then
				knownItems[itemID] = true;
			end
		end
	end
end

local function CheckNewItem(bag, slot, link)
	local key = bag .. ":" .. slot;
	local itemID = ItemIDFromLink(link);
	if not itemID then
		newSlots[key] = nil;
		return false;
	end
	if knownItems and not knownItems[itemID] then
		knownItems[itemID] = true;
		newSlots[key] = true;
	end
	return newSlots[key] == true;
end

local function ClearNewItem(bag, slot)
	newSlots[bag .. ":" .. slot] = nil;
end

---------------------------------------------------------------------------
-- search (same rules as ItemSearch.lua, which only knows ContainerFrame1..13)
---------------------------------------------------------------------------
local function ItemMatchesSearch(link)
	local search = ITEM_SEARCH_TEXT or "";
	if search == "" then
		return true;
	end
	if not link then
		return false;
	end
	local name, _, quality, iLevel, _, itemType, itemSubType, _, equipSlot = GetItemInfo(link);
	if not name then
		return false;
	end
	local function has(text)
		return text and text ~= "" and strfind(strlower(text), search, 1, true) ~= nil;
	end
	return has(name) or has(itemType) or has(itemSubType)
		or (equipSlot and equipSlot ~= "" and has(_G[equipSlot]))
		or (quality and has(_G["ITEM_QUALITY" .. quality .. "_DESC"]))
		or (iLevel and has(tostring(iLevel)));
end

---------------------------------------------------------------------------
-- item buttons
---------------------------------------------------------------------------
local function DecorateButton(button)
	-- empty slot background (retail emptyBackgroundAtlas)
	local slotBG = button:CreateTexture(nil, "BACKGROUND");
	slotBG:SetAtlas("bags-item-slot64");
	slotBG:SetAllPoints();
	button.slotBG = slotBG;

	-- new item: quality glow pulsing (newitemglowAnim) and a white flash when it arrives
	local glow = button:CreateTexture(nil, "OVERLAY");
	glow:SetAtlas("bags-glow-white", true);
	glow:SetBlendMode("ADD");
	glow:SetPoint("CENTER");
	glow:Hide();
	button.NewItemTexture = glow;
	local anim = button:CreateAnimationGroup();
	anim:SetLooping("BOUNCE");
	local alpha = anim:CreateAnimation("Alpha");
	alpha:SetChange(-0.8);
	alpha:SetDuration(0.5);
	button.newItemAnim = anim;

	local flash = button:CreateTexture(nil, "OVERLAY");
	flash:SetAtlas("bags-glow-flash", true);
	flash:SetBlendMode("ADD");
	flash:SetPoint("CENTER");
	flash:Hide();
	button.flash = flash;
	local flashAnim = flash:CreateAnimationGroup();
	local fade = flashAnim:CreateAnimation("Alpha");
	fade:SetChange(-1);
	fade:SetDuration(0.6);
	flashAnim:SetScript("OnFinished", function() flash:Hide(); end);
	button.flashAnim = flashAnim;

	-- junk coin
	local junk = button:CreateTexture(nil, "OVERLAY");
	junk:SetAtlas("bags-junkcoin", true);
	junk:SetPoint("TOPLEFT", 1, 0);
	junk:Hide();
	button.JunkIcon = junk;

	-- bag highlight while the bag button of the main bar is hovered
	local indicator = button:CreateTexture(nil, "OVERLAY");
	indicator:SetTexture("Interface\\Store\\store-item-highlight");
	indicator:SetPoint("CENTER");
	indicator:Hide();
	button.BagIndicator = indicator;

	-- the new item mark goes away once the item was looked at
	button:HookScript("OnEnter", function(self)
		if self.isNew then
			ClearNewItem(self:GetParent():GetID(), self:GetID());
			self.isNew = nil;
			self.newItemAnim:Stop();
			self.NewItemTexture:Hide();
		end
	end);
end

local function UpdateButton(button, bag, slot, tooltipOwner)
	local texture, itemCount, locked, quality, readable = GetContainerItemInfo(bag, slot);
	local link = GetContainerItemLink(bag, slot);
	if link and (not quality or quality < 0) then
		quality = select(3, GetItemInfo(link));
	end

	SetItemButtonTexture(button, texture);
	SetItemButtonCount(button, itemCount);
	SetItemButtonDesaturated(button, locked, 0.5, 0.5, 0.5);
	if SetItemButtonQuality then
		SetItemButtonQuality(button, texture and quality or nil);
	end

	-- quest items
	local questTexture = _G[button:GetName() .. "IconQuestTexture"];
	local isQuestItem, questID, isActive = GetContainerItemQuestInfo(bag, slot);
	if questID and not isActive then
		questTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG);
		questTexture:Show();
	elseif questID or isQuestItem then
		questTexture:SetTexture(TEXTURE_ITEM_QUEST_BORDER);
		questTexture:Show();
	else
		questTexture:Hide();
	end

	-- junk: grey items that sell
	local sellPrice = link and select(11, GetItemInfo(link));
	if texture and quality == 0 and (sellPrice == nil or sellPrice > 0) then
		button.JunkIcon:Show();
	else
		button.JunkIcon:Hide();
	end

	-- new item
	local isNew = CheckNewItem(bag, slot, link);
	button.isNew = isNew or nil;
	if isNew then
		button.NewItemTexture:SetAtlas(NEW_ITEM_ATLAS_BY_QUALITY[quality or 1] or "bags-glow-white", true);
		button.NewItemTexture:Show();
		if not button.newItemAnim:IsPlaying() then
			button.newItemAnim:Play();
			button.flash:Show();
			button.flashAnim:Play();
		end
	else
		button.newItemAnim:Stop();
		button.NewItemTexture:Hide();
	end

	if texture then
		ContainerFrame_UpdateCooldown(bag, button);
		button.hasItem = 1;
	else
		_G[button:GetName() .. "Cooldown"]:Hide();
		button.hasItem = nil;
	end
	button.readable = readable;

	-- search
	if ItemMatchesSearch(link) then
		button:SetAlpha(1);
	else
		button:SetAlpha(SEARCH_ALPHA);
		if texture then
			SetItemButtonDesaturated(button, 1);
		end
	end

	if button == tooltipOwner and button.UpdateTooltip then
		button.UpdateTooltip(button);
	end
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
local frame;

local function AcquireButton(bag, slot)
	local holder = frame.holders[bag];
	local button = holder.buttons[slot];
	if not button then
		button = CreateFrame("Button", holder:GetName() .. "Item" .. slot, holder, "ContainerFrameItemButtonTemplate");
		button:SetID(slot);
		DecorateButton(button);
		holder.buttons[slot] = button;
	end
	return button;
end

-- retail order: bag 4 .. backpack, last slot first, laid out from the bottom right
function ContainerFrameCombinedBags_UpdateLayout()
	local items = {};
	for bag = LAST_BAG, FIRST_BAG, -1 do
		local size = GetContainerNumSlots(bag);
		local holder = frame.holders[bag];
		holder.size = size;
		for i = 1, size do
			table.insert(items, AcquireButton(bag, size - i + 1));
		end
		for slot = size + 1, #holder.buttons do
			holder.buttons[slot]:Hide();
		end
	end

	local rows = math.max(1, math.ceil(#items / COLUMNS));
	local step = BUTTON_SIZE + SPACING;
	frame:SetWidth(COLUMNS * BUTTON_SIZE + (COLUMNS - 1) * SPACING + PADDING_WIDTH);
	frame:SetHeight(rows * BUTTON_SIZE + (rows - 1) * SPACING + PADDING_TOP + PADDING_BOTTOM);

	for index, button in ipairs(items) do
		local column = (index - 1) % COLUMNS;
		local row = math.floor((index - 1) / COLUMNS);
		button:ClearAllPoints();
		button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7 - column * step, PADDING_BOTTOM + row * step);
		button:Show();
	end
	frame.numItems = #items;
end

function ContainerFrameCombinedBags_Update()
	if not frame:IsShown() then
		return;
	end
	local tooltipOwner = GameTooltip:GetOwner();
	for bag = FIRST_BAG, LAST_BAG do
		local holder = frame.holders[bag];
		for slot = 1, holder.size or 0 do
			UpdateButton(holder.buttons[slot], bag, slot, tooltipOwner);
		end
	end
end

local function UpdateBag(bag)
	local holder = frame.holders[bag];
	if not holder then
		return;
	end
	if GetContainerNumSlots(bag) ~= (holder.size or 0) then
		ContainerFrameCombinedBags_UpdateLayout();
		ContainerFrameCombinedBags_Update();
		UpdateContainerFramePlacement();
		return;
	end
	local tooltipOwner = GameTooltip:GetOwner();
	for slot = 1, holder.size or 0 do
		UpdateButton(holder.buttons[slot], bag, slot, tooltipOwner);
	end
end

local function UpdateBagButtons(checked)
	MainMenuBarBackpackButton:SetChecked(checked and 1 or 0);
	for i = 0, NUM_BAG_SLOTS - 1 do
		local button = _G["CharacterBag" .. i .. "Slot"];
		if button then
			button:SetChecked(checked and 1 or 0);
		end
	end
end

-- the separate 3.3.5 bags (bank, keyring) stand to the left of the combined window
function UpdateContainerFramePlacement()
	if frame:IsShown() then
		if not frame.userPlaced then
			frame:ClearAllPoints();
			frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -4, CONTAINER_OFFSET_Y);
		end
		CONTAINER_OFFSET_X = frame:GetWidth() + 4;
	else
		CONTAINER_OFFSET_X = 0;
	end
	updateContainerFrameAnchors();
end

function ContainerFrameCombinedBags_OnLoad(self)
	frame = self;
	self.TitleText:SetText(COMBINED_BAG_TITLE or "Сумки");
	SetPortraitToTexture(self.portrait, "Interface\\Icons\\INV_Misc_Bag_08");

	-- retail atlases for the sort button, the portrait highlight and the money box
	local sort = self.SortButton;
	sort:GetNormalTexture():SetAtlas("bags-button-autosort-up");
	sort:GetPushedTexture():SetAtlas("bags-button-autosort-down");
	sort:GetNormalTexture():SetTexCoord(0, 1, 0, 1);
	sort:GetPushedTexture():SetTexCoord(0, 1, 0, 1);
	self.PortraitButton:GetHighlightTexture():SetAtlas("bags-roundhighlight");

	local money = self.MoneyFrame;
	local left = money:CreateTexture(nil, "BACKGROUND");
	left:SetAtlas("common-coinbox-left");
	left:SetWidth(8);
	left:SetHeight(17);
	left:SetPoint("LEFT", self, "BOTTOMLEFT", 8, 16);
	local right = money:CreateTexture(nil, "BACKGROUND");
	right:SetAtlas("common-coinbox-right");
	right:SetWidth(8);
	right:SetHeight(17);
	right:SetPoint("RIGHT", self, "BOTTOMRIGHT", -8, 16);
	local middle = money:CreateTexture(nil, "BACKGROUND");
	middle:SetAtlas("_common-coinbox-center");
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT");
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT");

	self.holders = {};
	for bag = FIRST_BAG, LAST_BAG do
		local holder = CreateFrame("Frame", "ContainerFrameCombinedBagsBag" .. bag, self);
		holder:SetID(bag);
		holder:SetAllPoints();
		holder.buttons = {};
		self.holders[bag] = holder;
	end

	-- close button closes every bag, like retail
	_G[self:GetName() .. "CloseButton"]:SetScript("OnClick", function()
		CloseAllBags();
	end);

	-- the moved window keeps its place until the UI reloads
	self:HookScript("OnMouseUp", function()
		self.userPlaced = true;
	end);

	table.insert(UISpecialFrames, self:GetName());

	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("BAG_UPDATE");
	self:RegisterEvent("ITEM_LOCK_CHANGED");
	self:RegisterEvent("BAG_UPDATE_COOLDOWN");
	self:RegisterEvent("QUEST_ACCEPTED");
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED");
	self:RegisterEvent("DISPLAY_SIZE_CHANGED");

	-- hovering a bag button of the main bar highlights its slots
	local function HookBagButton(button, bag)
		if not button then
			return;
		end
		button:HookScript("OnEnter", function()
			if frame:IsShown() then
				for _, itemButton in ipairs(frame.holders[bag].buttons) do
					itemButton.BagIndicator:Show();
				end
			end
		end);
		button:HookScript("OnLeave", function()
			for _, itemButton in ipairs(frame.holders[bag].buttons) do
				itemButton.BagIndicator:Hide();
			end
		end);
	end
	HookBagButton(MainMenuBarBackpackButton, 0);
	for i = 0, NUM_BAG_SLOTS - 1 do
		HookBagButton(_G["CharacterBag" .. i .. "Slot"], i + 1);
	end
end

function ContainerFrameCombinedBags_OnEvent(self, event, ...)
	local arg1, arg2 = ...;
	if event == "PLAYER_ENTERING_WORLD" then
		-- right after login the bags can still be empty: the first real scan is the first opening
		return;
	end
	if not self:IsShown() then
		-- remember what arrives while the bags are closed, as new items
		if event == "BAG_UPDATE" and knownItems and arg1 and arg1 >= FIRST_BAG and arg1 <= LAST_BAG then
			for slot = 1, GetContainerNumSlots(arg1) do
				CheckNewItem(arg1, slot, GetContainerItemLink(arg1, slot));
			end
		end
		return;
	end
	if event == "BAG_UPDATE" then
		UpdateBag(arg1);
	elseif event == "ITEM_LOCK_CHANGED" then
		local bag, slot = arg1, arg2;
		local holder = bag and frame.holders[bag];
		local button = holder and slot and holder.buttons[slot];
		if button then
			local _, _, locked = GetContainerItemInfo(bag, slot);
			SetItemButtonDesaturated(button, locked, 0.5, 0.5, 0.5);
		end
	elseif event == "BAG_UPDATE_COOLDOWN" then
		for bag = FIRST_BAG, LAST_BAG do
			local holder = frame.holders[bag];
			for slot = 1, holder.size or 0 do
				local button = holder.buttons[slot];
				if button.hasItem then
					ContainerFrame_UpdateCooldown(bag, button);
				end
			end
		end
	elseif event == "DISPLAY_SIZE_CHANGED" then
		UpdateContainerFramePlacement();
	else
		ContainerFrameCombinedBags_Update();
	end
end

function ContainerFrameCombinedBags_OnShow(self)
	if not knownItems then
		ScanKnownItems();
	end
	ContainerFrameCombinedBags_UpdateLayout();
	ContainerFrameCombinedBags_Update();

	BagItemSearchBox:SetParent(self);
	BagItemSearchBox:ClearAllPoints();
	BagItemSearchBox:SetPoint("TOPLEFT", self, "TOPLEFT", 62, -32);
	BagItemSearchBox:SetWidth(self:GetWidth() - 110);
	BagItemSearchBox.anchorBag = self;
	BagItemSearchBox:Show();

	UpdateBagButtons(true);
	UpdateContainerFramePlacement();
	PlaySound("igBackPackOpen");
end

function ContainerFrameCombinedBags_OnHide(self)
	if BagItemSearchBox.anchorBag == self then
		BagItemSearchBox:ClearAllPoints();
		BagItemSearchBox:Hide();
		BagItemSearchBox.anchorBag = nil;
	end
	-- items seen once the bags were open are no longer new
	wipe(newSlots);
	UpdateBagButtons(false);
	UpdateContainerFramePlacement();
	PlaySound("igBackPackClose");
end

function ContainerFrameCombinedBags_PortraitOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT");
	GameTooltip:SetText(BACKPACK_TOOLTIP or "Рюкзак", 1, 1, 1);
	local binding = GetBindingKey("TOGGLEBACKPACK");
	if binding then
		GameTooltip:AppendText(" " .. NORMAL_FONT_COLOR_CODE .. "(" .. binding .. ")" .. FONT_COLOR_CODE_CLOSE);
	end
	GameTooltip:AddLine("Правый клик: отдельные сумки", 0.7, 0.7, 0.7);
	GameTooltip:Show();
end

-- right click on the portrait (separate bags: on the backpack portrait)
function ContainerFrameCombinedBags_ToggleMode()
	local wasOpen = frame:IsShown() or orig.IsBagOpen(0);
	CloseAllBags();
	useCombined = not useCombined;
	if wasOpen then
		OpenAllBags(true);
	end
end

---------------------------------------------------------------------------
-- global bag functions
---------------------------------------------------------------------------
function ToggleBackpack()
	if not useCombined then
		return orig.ToggleBackpack();
	end
	if IsOptionFrameOpen() then
		return;
	end
	if frame:IsShown() then
		frame:Hide();
	else
		frame:Show();
	end
end

function ToggleBag(id)
	if IsCombinedBag(id) then
		return ToggleBackpack();
	end
	return orig.ToggleBag(id);
end

function OpenBag(id)
	if IsCombinedBag(id) then
		if not frame:IsShown() and CanOpenPanels() then
			frame:Show();
		end
		return;
	end
	return orig.OpenBag(id);
end

function CloseBag(id)
	if IsCombinedBag(id) then
		frame:Hide();
		return;
	end
	return orig.CloseBag(id);
end

function OpenBackpack()
	if not useCombined then
		return orig.OpenBackpack();
	end
	if frame:IsShown() then
		ContainerFrame1.backpackWasOpen = 1;
		return 1;
	end
	ContainerFrame1.backpackWasOpen = nil;
	if CanOpenPanels() then
		frame:Show();
	end
	return nil;
end

function CloseBackpack()
	if not useCombined then
		return orig.CloseBackpack();
	end
	if ContainerFrame1.backpackWasOpen == nil then
		frame:Hide();
	end
end

-- keeps the 3.3.5 contract for bank bags / keyring; bags 0-4 are "open" with the combined window
function IsBagOpen(id)
	if IsCombinedBag(id) then
		return frame:IsShown() and id or nil;
	end
	return orig.IsBagOpen(id);
end

function OpenAllBags(forceOpen)
	if not useCombined then
		return orig.OpenAllBags(forceOpen);
	end
	if not UIParent:IsShown() then
		return;
	end
	if frame:IsShown() and not forceOpen then
		CloseAllBags();
		return;
	end
	frame:Show();
	if BankFrame and BankFrame:IsShown() then
		for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
			if not orig.IsBagOpen(bag) then
				orig.ToggleBag(bag);
			end
		end
	end
end

function CloseAllBags()
	if frame then
		frame:Hide();
	end
	return orig.CloseAllBags();
end

function GetBackpackFrame()
	if useCombined then
		return frame:IsShown() and frame or nil;
	end
	return orig.GetBackpackFrame();
end

-- search box text changes (ItemSearch.lua) reach the combined window too
function UpdateItemSearchResults()
	orig.UpdateItemSearchResults();
	ContainerFrameCombinedBags_Update();
end

---------------------------------------------------------------------------
-- sorting: one swap per step, waiting for the server to unlock the items
---------------------------------------------------------------------------
-- retail order: equipment by slot, consumables, trade goods, ..., junk last; inside a group
-- higher quality, higher item level, name. Special bags (soul shards, quiver, profession
-- bags) keep their items.
local CLASS_ORDER = {
	[2] = 1, [4] = 2,					-- weapons, armor
	[0] = 3,							-- consumables
	[12] = 4,							-- quest items
	[3] = 5, [7] = 6, [5] = 7, [9] = 8,	-- gems, trade goods, reagents, recipes
	[1] = 9, [11] = 10, [6] = 11,		-- containers, quivers, projectiles
	[15] = 12, [13] = 13, [16] = 14,	-- miscellaneous, keys, glyphs
};

local sorter = CreateFrame("Frame");
sorter:Hide();

local function SortKey(link)
	if not link then
		return nil;
	end
	local name, _, quality, iLevel, _, _, _, _, equipLoc = GetItemInfo(link);
	local itemID = ItemIDFromLink(link) or 0;
	if not name then
		return ("9|%08d"):format(itemID);
	end
	local itemClass = select(6, GetItemInfo(link));
	-- 3.3.5 GetItemInfo has no classID: map the localized class name through GetAuctionItemClasses
	local classOrder = 20;
	if not sorter.classByName then
		sorter.classByName = {};
		-- 3.3.5 auction classes: weapon, armor, container, consumable, glyph, trade goods,
		-- projectile, quiver, recipe, gem, miscellaneous, quest
		local ids = { 2, 4, 1, 0, 16, 7, 6, 11, 9, 3, 15, 12 };
		for index, className in ipairs({ GetAuctionItemClasses() }) do
			sorter.classByName[className] = ids[index];
		end
	end
	local classID = sorter.classByName[itemClass];
	if quality == 0 then
		classOrder = 99;		-- junk last
	elseif classID and CLASS_ORDER[classID] then
		classOrder = CLASS_ORDER[classID];
	end
	return ("%02d|%s|%d|%04d|%s|%08d"):format(classOrder, equipLoc or "", 9 - (quality or 0),
		9999 - (iLevel or 0), name, itemID);
end

local function SortableSlots()
	local slots = {};
	for bag = FIRST_BAG, LAST_BAG do
		local _, bagType = GetContainerNumFreeSlots(bag);
		if bag == 0 or bagType == 0 then
			for slot = 1, GetContainerNumSlots(bag) do
				table.insert(slots, { bag = bag, slot = slot });
			end
		end
	end
	return slots;
end

-- next swap to do: first slot whose item is not the wanted one, and where the wanted one is
local function NextSwap()
	local slots = SortableSlots();
	local keys, wanted = {}, {};
	for index, pos in ipairs(slots) do
		local _, _, locked = GetContainerItemInfo(pos.bag, pos.slot);
		if locked then
			return "wait";
		end
		keys[index] = SortKey(GetContainerItemLink(pos.bag, pos.slot));
		if keys[index] then
			table.insert(wanted, keys[index]);
		end
	end
	table.sort(wanted);

	-- identical items (same key) count as equal: swapping them would only merge stacks
	for index = 1, #slots do
		local want = wanted[index];
		if keys[index] ~= want then
			for from = index + 1, #slots do
				if keys[from] == want then
					return slots[from], slots[index];
				end
			end
			return nil;
		end
	end
	return nil;
end

sorter:SetScript("OnUpdate", function(self, elapsed)
	self.delay = (self.delay or 0) - elapsed;
	if self.delay > 0 then
		return;
	end
	self.delay = SORT_STEP_DELAY;

	if InCombatLockdown() or CursorHasItem() then
		return;
	end
	self.steps = self.steps + 1;
	local from, to = NextSwap();
	if from == "wait" and self.steps < SORT_MAX_STEPS then
		return;
	end
	if not from or self.steps >= SORT_MAX_STEPS then
		self:Hide();
		return;
	end
	PickupContainerItem(from.bag, from.slot);
	PickupContainerItem(to.bag, to.slot);
	if CursorHasItem() then
		ClearCursor();
	end
end);

function ContainerFrameCombinedBags_SortBags()
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Нельзя в бою", 1, 0.1, 0.1);
		return;
	end
	sorter.steps = 0;
	sorter.delay = 0;
	sorter:Show();
end
