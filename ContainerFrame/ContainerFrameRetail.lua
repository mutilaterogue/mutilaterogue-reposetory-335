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
if UIPARENT_MANAGED_FRAME_POSITIONS and UIPARENT_MANAGED_FRAME_POSITIONS["CONTAINER_OFFSET_X"] then
	UIPARENT_MANAGED_FRAME_POSITIONS["CONTAINER_OFFSET_X"].baseX = OFFSET_LEFT;
end
CONTAINER_OFFSET_X = math.max(CONTAINER_OFFSET_X or 0, OFFSET_LEFT);

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
	-- the stock close button keeps working (it closes the bag the stock way): in the retail one's place
	retail.CloseButton:Hide();
	local close = _G[name .. "CloseButton"];
	if close then
		close:ClearAllPoints();
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 5, 5);
		close:SetFrameLevel(retail:GetFrameLevel() + 10);
	end
	frame.RetailFrame = retail;

	-- the sort button (retail BagItemAutoSortButton): sorts the backpack and the bags (ContainerFrameCombined.lua)
	local sort = CreateFrame("Button", name .. "SortButton", frame);
	sort:SetWidth(SORT_WIDTH);
	sort:SetHeight(26);
	sort:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING_SIDE + 2, -36);
	sort:SetFrameLevel(retail:GetFrameLevel() + 10);
	sort:SetNormalAtlas("bags-button-autosort-up");
	sort:SetPushedAtlas("bags-button-autosort-down");
	sort:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	sort:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOn");
		if ContainerFrameCombinedBags_SortBags then
			ContainerFrameCombinedBags_SortBags();
		end
	end);
	sort:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT");
		GameTooltip:SetText(BAG_CLEANUP_BAGS or "Сортировать сумки", 1, 1, 1);
		GameTooltip:AddLine(BAG_CLEANUP_BAGS_DESCRIPTION or "Упорядочивает предметы в рюкзаке и сумках.", nil, nil, nil, true);
		GameTooltip:Show();
	end);
	sort:SetScript("OnLeave", GameTooltip_Hide);
	frame.SortButton = sort;

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
local function Layout(frame, size, id)
	local retail = Skin(frame);
	local name = frame:GetName();
	local isBackpack = id == 0;
	frame.retailSize, frame.retailID = size, id;
	if isBackpack then
		frame.SortButton:Show();
	else
		frame.SortButton:Hide();
	end

	retail:SetTitle(_G[name .. "Name"]:GetText() or "");
	if isBackpack then
		retail:SetPortraitToAsset("Interface\\Buttons\\Button-Backpack-Up");
	else
		retail:SetPortraitToBag(id);
	end

	local rows = math.max(1, math.ceil(size / COLUMNS));
	local top = isBackpack and PADDING_TOP_SEARCH or PADDING_TOP;
	local bottom = isBackpack and PADDING_BOTTOM_MONEY or PADDING_BOTTOM;
	local step = BUTTON_SIZE + SPACING;
	frame:SetWidth(FRAME_WIDTH);
	frame:SetHeight(rows * BUTTON_SIZE + (rows - 1) * SPACING + top + bottom);

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
		money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 9);
	end
end

hooksecurefunc("ContainerFrame_GenerateFrame", Layout);

-- every update: the size again (something puts the backpack's stock height back after the generate), the search box
hooksecurefunc("ContainerFrame_Update", function(frame)
	if frame.RetailFrame and frame.retailSize and frame:GetID() == frame.retailID then
		local isBackpack = frame.retailID == 0;
		local rows = math.max(1, math.ceil(frame.retailSize / COLUMNS));
		local height = rows * BUTTON_SIZE + (rows - 1) * SPACING
			+ (isBackpack and PADDING_TOP_SEARCH or PADDING_TOP) + (isBackpack and PADDING_BOTTOM_MONEY or PADDING_BOTTOM);
		if math.abs(frame:GetHeight() - height) > 0.5 then
			frame:SetHeight(height);
			updateContainerFrameAnchors();
		end
	end
	PlaceSearchBox(frame);
end);
