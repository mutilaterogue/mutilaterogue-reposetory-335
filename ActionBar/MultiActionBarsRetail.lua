-- (not MultiActionBars.lua: that is the stock file, which this one must not replace)
-- The extra bars (MultiBarBottomLeft / BottomRight / Right / Left) laid out as in 12.1.5: the retail buttons
-- without bar art (ActionButtonOverrides.lua: the "add row" frame and the slot background), the bottom bars stacked
-- over MainActionBar, the right bars standing at the screen's right edge.
-- The stance bar (ShapeshiftBarFrame) too: small retail buttons over the top bottom bar.
-- The stock bars, buttons and their logic (MultiActionBars.lua) stay; only the art and the places change.

local BUTTON_SIZE = 45;
local BUTTON_PADDING = 2;
local NUM_BUTTONS = 12;
local BAR_LENGTH = NUM_BUTTONS * BUTTON_SIZE + (NUM_BUTTONS - 1) * BUTTON_PADDING;
local BAR_SPACING = 8;		-- between two stacked bars (the main bar's frame art stands 4 px over it)

local BARS = {
	{ name = "MultiBarBottomLeft", horizontal = true },
	{ name = "MultiBarBottomRight", horizontal = true },
	{ name = "MultiBarRight" },
	{ name = "MultiBarLeft" },
};

local layoutPending;

function MultiActionBarsRetail_Layout()
	-- the bars hold secure buttons: no moving them in combat
	if InCombatLockdown() then
		layoutPending = true;
		return;
	end
	layoutPending = nil;

	-- bottom bars: each over the one under it
	local below = MainActionBar;
	for _, name in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight" }) do
		local bar = _G[name];
		bar:ClearAllPoints();
		bar:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, BAR_SPACING);
		if bar:IsShown() then
			below = bar;
		end
	end

	-- the stance bar (StanceBar): small buttons over the top bottom bar, at its left
	ShapeshiftBarFrame:ClearAllPoints();
	ShapeshiftBarFrame:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, BAR_SPACING);

	-- right bars: at the right edge, centered, MultiBarLeft left of MultiBarRight
	MultiBarRight:ClearAllPoints();
	MultiBarRight:SetPoint("RIGHT", UIParent, "RIGHT", -5, 0);
	MultiBarLeft:ClearAllPoints();
	MultiBarLeft:SetPoint("TOPRIGHT", MultiBarRight, "TOPLEFT", -BAR_SPACING, 0);
end

local function MultiActionBarsRetail_Setup()
	-- UIParent_ManageFramePositions would put the stock places back
	if UIPARENT_MANAGED_FRAME_POSITIONS then
		UIPARENT_MANAGED_FRAME_POSITIONS["MultiBarBottomLeft"] = nil;
		UIPARENT_MANAGED_FRAME_POSITIONS["MultiBarRight"] = nil;
		UIPARENT_MANAGED_FRAME_POSITIONS["ShapeshiftBarFrame"] = nil;
	end

	for _, info in ipairs(BARS) do
		local bar = _G[info.name];
		if info.horizontal then
			bar:SetWidth(BAR_LENGTH);
			bar:SetHeight(BUTTON_SIZE);
		else
			bar:SetWidth(BUTTON_SIZE);
			bar:SetHeight(BAR_LENGTH);
		end
		for i = 1, NUM_BUTTONS do
			local button = _G[info.name .. "Button" .. i];
			ActionButtonRetail_Apply(button, true);
			button:ClearAllPoints();
			if info.horizontal then
				button:SetPoint("TOPLEFT", bar, "TOPLEFT", (i - 1) * (BUTTON_SIZE + BUTTON_PADDING), 0);
			else
				button:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(i - 1) * (BUTTON_SIZE + BUTTON_PADDING));
			end
		end
		bar:HookScript("OnShow", MultiActionBarsRetail_Layout);
		bar:HookScript("OnHide", MultiActionBarsRetail_Layout);
	end

	StanceBarRetail_Setup();
	MultiActionBarsRetail_Layout();
end

---------------------------------------------------------------------------
-- the stance bar (ShapeshiftBarFrame): retail StanceBar.xml, SmallActionButtonTemplate buttons, no bar art
---------------------------------------------------------------------------

local SMALL_SIZE = 30;

function StanceBarRetail_LayoutButtons()
	if InCombatLockdown() then
		layoutPending = true;
		return;
	end
	local numForms = GetNumShapeshiftForms();
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local button = _G["ShapeshiftButton" .. i];
		button:ClearAllPoints();
		button:SetPoint("TOPLEFT", ShapeshiftBarFrame, "TOPLEFT", (i - 1) * (SMALL_SIZE + BUTTON_PADDING), 0);
	end
	ShapeshiftBarFrame:SetWidth(math.max(1, numForms) * (SMALL_SIZE + BUTTON_PADDING) - BUTTON_PADDING);
	ShapeshiftBarFrame:SetHeight(SMALL_SIZE);
end

function StanceBarRetail_Setup()
	-- the stock bar art: the stock code shows these again (ShapeshiftBar_Update, UIParent_ManageFramePositions), so alpha 0
	for _, name in ipairs({ "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
		"SlidingActionBarTexture0", "SlidingActionBarTexture1" }) do
		local texture = _G[name];
		if texture then
			texture:SetAlpha(0);
		end
	end
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		ActionButtonRetail_ApplySmall(_G["ShapeshiftButton" .. i]);
	end
	-- ShapeshiftBar_Update moves the first button for a single form: put it back
	hooksecurefunc("ShapeshiftBar_Update", StanceBarRetail_LayoutButtons);
	StanceBarRetail_LayoutButtons();
end

MultiActionBarsRetail_Setup();

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
eventFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" or layoutPending then
		StanceBarRetail_LayoutButtons();
		MultiActionBarsRetail_Layout();
	end
end);
