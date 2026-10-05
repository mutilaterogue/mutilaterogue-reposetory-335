-- The separate bags (ContainerFrame1..N: backpack, bags, bank bags, keyring) with the retail (12.1.5) look
-- (Blizzard_UIPanels_Game\ContainerFrame.xml ContainerFrameTemplate: PortraitFrameFlatTemplate):
-- the retail portrait frame (RetailPortraitFrameTemplate) instead of the 3.3.5 bag art, the slots drawn by the buttons
-- (bags-item-slot64), 4 columns of 37 px with 5 px between, the search box and the money in the retail places.
-- The stock frames and their logic (ContainerFrame.lua) stay. Load after ContainerFrame.xml and
-- SharedXML\Utils\PortraitFrameTemplates.xml (end of FrameXML.toc).

local COLUMNS = 4;
local BUTTON_SIZE = 37;
local SPACING = 5;
local PADDING_SIDE = 10;		-- from the frame's sides to the columns
local PADDING_TOP = 44;			-- title bar and the portrait
local PADDING_TOP_SEARCH = 72;	-- title bar + search row (backpack)
local PADDING_BOTTOM = 10;
local PADDING_BOTTOM_MONEY = 34;	-- money row (backpack)
local PORTRAIT_SIZE = 40;		-- the bag's portrait, inside the small ring of HeldBagLayout

local SORT_WIDTH = 28;			-- the sort button right of the search box (backpack)
local FRAME_WIDTH = COLUMNS * BUTTON_SIZE + (COLUMNS - 1) * SPACING + 2 * PADDING_SIDE + 1;

-- updateContainerFrameAnchors: between two stacked bags (stock 3 / 0; retail 8, and the ring stands over the frame's
-- top), between two columns (CONTAINER_WIDTH is the column step), the first bag further left of the screen's edge
CONTAINER_SPACING = 14;
VISIBLE_CONTAINER_SPACING = 14;
CONTAINER_WIDTH = FRAME_WIDTH + 12;
local OFFSET_LEFT = 20;

-- the bags' distance from the right: past the right action bars when they show (retail
-- GetInitialContainerFrameOffsetX), else from the screen's edge
function ContainerFrameRetail_GetEdgeOffset()
	local left;
	for _, bar in ipairs({ MultiBarLeft, MultiBarRight }) do
		if bar and bar:IsShown() and bar:GetLeft() then
			left = math.min(left or bar:GetLeft(), bar:GetLeft());
		end
	end
	local screenRight = UIParent:GetRight() or GetScreenWidth();
	return OFFSET_LEFT + (left and (screenRight - left) or 0);
end

-- the stock UIParent_ManageFramePositions would set its own offset (for the stock bar sizes): this one instead,
-- and past the combined window when it shows (ContainerFrameCombined.lua)
if UIPARENT_MANAGED_FRAME_POSITIONS then
	UIPARENT_MANAGED_FRAME_POSITIONS["CONTAINER_OFFSET_X"] = nil;
end
local stockUpdateAnchors = updateContainerFrameAnchors;
function updateContainerFrameAnchors()
	local offset = ContainerFrameRetail_GetEdgeOffset();
	local combined = ContainerFrameCombinedBags;
	if combined and combined:IsShown() then
		offset = offset + combined:GetWidth() + 12;
	end
	CONTAINER_OFFSET_X = offset;
	stockUpdateAnchors();
end

-- the currencies' row under the money (when currencies show on the backpack)
local TOKEN_ROW = 20;
local MAX_TOKENS = MAX_WATCHED_TOKENS or 3;

function ContainerFrameRetail_TokenRowHeight()
	if not (BackpackTokenFrame and BackpackTokenFrame:IsShown()) then
		return 0;
	end
	for i = 1, MAX_TOKENS do
		local token = _G["BackpackTokenFrameToken" .. i];
		if token and token:IsShown() then
			return TOKEN_ROW;
		end
	end
	return 0;
end

local STOCK_ART = { "BackgroundTop", "BackgroundMiddle1", "BackgroundMiddle2", "BackgroundBottom", "Background1Slot",
	"Portrait", "Name" };

local function Skin(frame)
	if frame.RetailFrame then
		return frame.RetailFrame;
	end
	local name = frame:GetName();

	-- the retail frame under the items (the stock frame's level: the items are one over it)
	local retail = CreateFrame("Frame", name .. "Retail", frame, "RetailPortraitFrameTemplate");
	retail:SetAllPoints(frame);
	retail:SetFrameLevel(frame:GetFrameLevel());
	retail:EnableMouse(false);
	-- retail ContainerFrameTemplate: layoutType HeldBagLayout (the small portrait ring)
	retail:SetBorder("HeldBagLayout");
	-- the portrait inside that ring, the title next to it
	local portrait = retail:GetPortrait();
	portrait:SetWidth(PORTRAIT_SIZE);
	portrait:SetHeight(PORTRAIT_SIZE);
	portrait:ClearAllPoints();
	portrait:SetPoint("TOPLEFT", retail, "TOPLEFT", -6, 2);
	retail:SetTitleOffsets(PORTRAIT_SIZE, -24);
	-- the retail close button (over the raised border; the stock one ends up under it), closing the bag the stock way
	local close = _G[name .. "CloseButton"];
	if close then
		close:Hide();
		close:SetAlpha(0);
		-- the stock close: ToggleBag of the bag's id
		retail.CloseButton:SetScript("OnClick", function()
			ToggleBag(frame:GetID());
		end);
	end
	frame.RetailFrame = retail;

	-- the retail height wins: the stock code sets its own (BACKPACK_HEIGHT and the bag art heights) where this file
	-- cannot follow it, so any SetHeight of the bag gives the retail one
	local setHeight = frame.SetHeight;
	frame.SetHeight = function(self, height)
		setHeight(self, self.retailHeight or height);
	end

	-- the sort button (retail BagItemAutoSortButton): sorts the backpack and the bags (ContainerFrameRetail_SortBags)
	local sort = CreateFrame("Button", name .. "SortButton", frame);
	sort:SetWidth(SORT_WIDTH);
	sort:SetHeight(26);
	sort:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING_SIDE + 2, -36);
	sort:SetFrameLevel(retail:GetFrameLevel() + 10);
	local normal = sort:CreateTexture(nil, "ARTWORK");
	normal:SetAtlas("bags-button-autosort-up");
	normal:SetAllPoints(sort);
	sort:SetNormalTexture(normal);
	local pushed = sort:CreateTexture(nil, "ARTWORK");
	pushed:SetAtlas("bags-button-autosort-down");
	pushed:SetAllPoints(sort);
	sort:SetPushedTexture(pushed);
	local highlight = sort:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square");
	highlight:SetBlendMode("ADD");
	highlight:SetAllPoints(sort);
	sort:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOn");
		ContainerFrameRetail_SortBags();
	end);
	sort:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT");
		GameTooltip:SetText(BAG_CLEANUP_BAGS or "Сортировать сумки", 1, 1, 1);
		GameTooltip:AddLine(BAG_CLEANUP_BAGS_DESCRIPTION or "Упорядочивает предметы в рюкзаке и сумках.", nil, nil, nil, true);
		GameTooltip:Show();
	end);
	sort:SetScript("OnLeave", GameTooltip_Hide);
	frame.SortButton = sort;

	-- right click on the backpack's portrait: back to the combined bags (ContainerFrameCombined.lua), as in retail
	local portraitButton = _G[name .. "PortraitButton"];
	if portraitButton then
		portraitButton:RegisterForClicks("LeftButtonUp", "RightButtonUp");
		portraitButton:HookScript("OnClick", function(self, button)
			if button == "RightButton" and frame:GetID() == 0 and ContainerFrameCombinedBags_ToggleMode then
				ContainerFrameCombinedBags_ToggleMode();
			end
		end);
	end

	-- the stock bag art: the stock code shows it again on every open, so alpha 0
	for _, key in ipairs(STOCK_ART) do
		local region = _G[name .. key];
		if region then
			region:SetAlpha(0);
		end
	end
	for i = 3, MAX_BG_TEXTURES or 2 do
		local region = _G[name .. "BackgroundMiddle" .. i];
		if region then
			region:SetAlpha(0);
		end
	end

	-- the empty slot of every item button (retail emptyBackgroundAtlas)
	local i = 1;
	while _G[name .. "Item" .. i] do
		local button = _G[name .. "Item" .. i];
		local slot = button:CreateTexture(nil, "BACKGROUND");
		slot:SetDrawLayer("BACKGROUND", -1);
		slot:SetAtlas("bags-item-slot64");
		slot:SetAllPoints(button);
		i = i + 1;
	end
	return retail;
end

-- the search box (the stock places it in ContainerFrame_Update): under the title, over the slots
local function PlaceSearchBox(frame)
	if frame:GetID() == 0 and frame.RetailFrame and BagItemSearchBox.anchorBag == frame then
		BagItemSearchBox:ClearAllPoints();
		BagItemSearchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING_SIDE + 6, -40);
		BagItemSearchBox:SetPoint("RIGHT", frame, "RIGHT", -PADDING_SIDE - SORT_WIDTH - 4, 0);
	end
end

-- after the stock layout (textures, size, item places): the retail frame, size and places
function ContainerFrameRetail_Layout(frame, size, id)
	local retail = Skin(frame);
	local name = frame:GetName();
	local isBackpack = id == 0;
	frame.retailSize, frame.retailID = size, id;
	if frame.SortButton then
		if isBackpack then
			frame.SortButton:Show();
		else
			frame.SortButton:Hide();
		end
	end

	retail:SetTitle(_G[name .. "Name"]:GetText() or "");
	if isBackpack then
		retail:SetPortraitToAsset("Interface\\Buttons\\Button-Backpack-Up");
	else
		retail:SetPortraitToBag(id);
	end

	local rows = math.max(1, math.ceil(size / COLUMNS));
	local top = isBackpack and PADDING_TOP_SEARCH or PADDING_TOP;
	local tokenRow = isBackpack and ContainerFrameRetail_TokenRowHeight() or 0;
	local bottom = isBackpack and (PADDING_BOTTOM_MONEY + tokenRow) or PADDING_BOTTOM;
	local step = BUTTON_SIZE + SPACING;
	frame:SetWidth(FRAME_WIDTH);
	frame.retailHeight = rows * BUTTON_SIZE + (rows - 1) * SPACING + top + bottom;
	frame:SetHeight(frame.retailHeight);

	-- the stock order: Item1 at the bottom right is the last slot
	for i = 1, size do
		local button = _G[name .. "Item" .. i];
		local column = (i - 1) % COLUMNS;
		local row = math.floor((i - 1) / COLUMNS);
		button:ClearAllPoints();
		button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING_SIDE - column * step, bottom + row * step);
	end

	PlaceSearchBox(frame);
	-- the stock code placed the bags with the stock sizes (before this): again with these
	updateContainerFrameAnchors();

	local money = _G[name .. "MoneyFrame"];
	if money then
		money:ClearAllPoints();
		money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 9 + tokenRow);
	end
end

hooksecurefunc("ContainerFrame_GenerateFrame", function(...)
	ContainerFrameRetail_Layout(...);
end);

-- every update: the search box in its place
hooksecurefunc("ContainerFrame_Update", PlaceSearchBox);

---------------------------------------------------------------------------
-- sorting (as in ContainerFrameCombined.lua, here so it works without the combined bags):
-- one swap per step, waiting for the server to unlock the items
---------------------------------------------------------------------------
local FIRST_BAG, LAST_BAG = 0, NUM_BAG_SLOTS;
local SORT_STEP_DELAY = 0.1;
local SORT_MAX_STEPS = 400;

local function ItemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)"));
end

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
	if not from or from == "wait" or self.steps >= SORT_MAX_STEPS then
		self:Hide();
		return;
	end
	PickupContainerItem(from.bag, from.slot);
	PickupContainerItem(to.bag, to.slot);
	if CursorHasItem() then
		ClearCursor();
	end
end);

function ContainerFrameRetail_SortBags()
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Нельзя в бою", 1, 0.1, 0.1);
		return;
	end
	sorter.steps = 0;
	sorter.delay = 0;
	sorter:Show();
end

---------------------------------------------------------------------------
-- the currencies shown on the backpack (Blizzard_TokenUI ManageBackpackTokenFrame): in the bottom row, left of the
-- money (retail ContainerFrameTokenWatcher); the bags keep their height (their SetHeight above)
---------------------------------------------------------------------------
-- a retail coin box (common-coinbox left / center / right) from one region's left to another's right
local function CoinBox(parent)
	local box = {};
	box.left = parent:CreateTexture(nil, "BACKGROUND");
	box.left:SetAtlas("common-coinbox-left");
	box.left:SetWidth(8);
	box.left:SetHeight(17);
	box.right = parent:CreateTexture(nil, "BACKGROUND");
	box.right:SetAtlas("common-coinbox-right");
	box.right:SetWidth(8);
	box.right:SetHeight(17);
	box.middle = parent:CreateTexture(nil, "BACKGROUND");
	box.middle:SetAtlas("_common-coinbox-center");
	box.middle:SetPoint("TOPLEFT", box.left, "TOPRIGHT");
	box.middle:SetPoint("BOTTOMRIGHT", box.right, "BOTTOMLEFT");
	return box;
end

local function PlaceTokenFrame()
	local tokens = BackpackTokenFrame;
	if not (tokens and tokens:IsShown()) then
		return;
	end
	local backpack = tokens:GetParent();
	if not (backpack and (backpack.RetailFrame or backpack == ContainerFrameCombinedBags)) then
		return;
	end

	-- no 3.3.5 token frame art: only the tokens, in a coin box like the money's
	if not tokens.retailBox then
		for _, region in ipairs({ tokens:GetRegions() }) do
			if region:IsObjectType("Texture") then
				region:SetAlpha(0);
			end
		end
		tokens.retailBox = CoinBox(tokens);
	end
	tokens:ClearAllPoints();
	tokens:SetAllPoints(backpack);
	tokens:SetFrameLevel(backpack:GetFrameLevel() + 5);
	tokens:EnableMouse(false);

	local shown = {};
	for i = 1, MAX_TOKENS do
		local token = _G["BackpackTokenFrameToken" .. i];
		if token and token:IsShown() then
			shown[#shown + 1] = token;
		end
	end
	local box = tokens.retailBox;
	if #shown == 0 then
		box.left:Hide();
		box.middle:Hide();
		box.right:Hide();
		return;
	end

	-- a row of its own under the money, the whole width, the currencies at its right (as the money above)
	box.left:ClearAllPoints();
	box.left:SetPoint("LEFT", backpack, "BOTTOMLEFT", 8, 16);
	box.right:ClearAllPoints();
	box.right:SetPoint("RIGHT", backpack, "BOTTOMRIGHT", -8, 16);
	for index, token in ipairs(shown) do
		token:ClearAllPoints();
		if index == 1 then
			token:SetPoint("RIGHT", box.right, "LEFT", -4, 0);
		else
			token:SetPoint("RIGHT", shown[index - 1], "LEFT", -6, 0);
		end
	end
	box.left:Show();
	box.middle:Show();
	box.right:Show();
end

-- the row appears / goes: the bag's size and the money's place again
local lastTokenRow = 0;
local function UpdateTokens()
	local row = ContainerFrameRetail_TokenRowHeight();
	if BackpackTokenFrame and BackpackTokenFrame.retailBox and row == 0 then
		local box = BackpackTokenFrame.retailBox;
		box.left:Hide();
		box.middle:Hide();
		box.right:Hide();
	end
	PlaceTokenFrame();
	if row ~= lastTokenRow then
		lastTokenRow = row;
		local combined = ContainerFrameCombinedBags;
		if combined and combined:IsShown() and ContainerFrameCombinedBags_UpdateLayout then
			ContainerFrameCombinedBags_UpdateLayout();
		end
		for i = 1, NUM_CONTAINER_FRAMES or 13 do
			local frame = _G["ContainerFrame" .. i];
			if frame and frame:IsShown() and frame.RetailFrame and frame.retailID == 0 then
				ContainerFrameRetail_Layout(frame, frame.retailSize, 0);
			end
		end
	end
end

local function HookTokenUI()
	if ManageBackpackTokenFrame and BackpackTokenFrame and not BackpackTokenFrame.retailHooked then
		BackpackTokenFrame.retailHooked = true;
		hooksecurefunc("ManageBackpackTokenFrame", UpdateTokens);
		if BackpackTokenFrame_Update then
			hooksecurefunc("BackpackTokenFrame_Update", UpdateTokens);
		end
		UpdateTokens();
	end
end

local tokenWatcher = CreateFrame("Frame");
tokenWatcher:RegisterEvent("ADDON_LOADED");
tokenWatcher:SetScript("OnEvent", function(self, event, addon)
	if addon == "Blizzard_TokenUI" then
		HookTokenUI();
	end
end);
if BackpackTokenFrame then
	HookTokenUI();
end
