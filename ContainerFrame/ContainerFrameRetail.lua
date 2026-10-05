-- The separate bags (ContainerFrame1..N: backpack, bags, bank bags, keyring) with the retail (12.1.5) look
-- (Blizzard_UIPanels_Game\ContainerFrame.xml ContainerFrameTemplate: PortraitFrameFlatTemplate):
-- the retail portrait frame (RetailPortraitFrameTemplate) instead of the 3.3.5 bag art, the slots drawn by the buttons
-- (bags-item-slot64), 4 columns of 37 px with 5 px between, the search box and the money in the retail places.
-- The stock frames and their logic (ContainerFrame.lua) stay. Load after ContainerFrame.xml and
-- SharedXML\Utils\PortraitFrameTemplates.xml (end of FrameXML.toc).

local COLUMNS = 4;
local BUTTON_SIZE = 37;
local SPACING = 5;
local PADDING_SIDE = 7;			-- from the frame's right edge to the first column
local PADDING_TOP = 32;			-- title bar
local PADDING_TOP_SEARCH = 62;	-- title bar + search row (backpack)
local PADDING_BOTTOM = 8;
local PADDING_BOTTOM_MONEY = 32;	-- money row (backpack)

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
	-- the stock close button keeps working (it closes the bag the stock way): in the retail one's place
	retail.CloseButton:Hide();
	local close = _G[name .. "CloseButton"];
	if close then
		close:ClearAllPoints();
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 5, 5);
		close:SetFrameLevel(retail:GetFrameLevel() + 10);
	end
	frame.RetailFrame = retail;

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

-- after the stock layout (textures, size, item places): the retail frame, size and places
local function Layout(frame, size, id)
	local retail = Skin(frame);
	local name = frame:GetName();
	local isBackpack = id == 0;

	retail:SetTitle(_G[name .. "Name"]:GetText() or "");
	retail:SetPortraitToBag(id);

	local rows = math.max(1, math.ceil(size / COLUMNS));
	local top = isBackpack and PADDING_TOP_SEARCH or PADDING_TOP;
	local bottom = isBackpack and PADDING_BOTTOM_MONEY or PADDING_BOTTOM;
	local step = BUTTON_SIZE + SPACING;
	frame:SetWidth(COLUMNS * BUTTON_SIZE + (COLUMNS - 1) * SPACING + 2 * PADDING_SIDE + 1);
	frame:SetHeight(rows * BUTTON_SIZE + (rows - 1) * SPACING + top + bottom);

	-- the stock order: Item1 at the bottom right is the last slot
	for i = 1, size do
		local button = _G[name .. "Item" .. i];
		local column = (i - 1) % COLUMNS;
		local row = math.floor((i - 1) / COLUMNS);
		button:ClearAllPoints();
		button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING_SIDE - column * step, bottom + row * step);
	end

	local money = _G[name .. "MoneyFrame"];
	if money then
		money:ClearAllPoints();
		money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 9);
	end
end

hooksecurefunc("ContainerFrame_GenerateFrame", Layout);

-- the search box (ContainerFrame_Update puts it at the stock place): under the title, as in retail
hooksecurefunc("ContainerFrame_Update", function(frame)
	if frame:GetID() == 0 and frame.RetailFrame and BagItemSearchBox.anchorBag == frame then
		BagItemSearchBox:ClearAllPoints();
		BagItemSearchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -32);
		BagItemSearchBox:SetPoint("RIGHT", frame, "RIGHT", -10, 0);
	end
end);
