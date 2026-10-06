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

-- a frame the Edit Mode layout places itself (ActionBarsEditMode.lua): not moved here
local function Placed(name)
	return EditModeCore and EditModeCore.HasPosition and EditModeCore:HasPosition(name);
end

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
		if not Placed(name) then
			bar:ClearAllPoints();
			bar:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, BAR_SPACING);
			if bar:IsShown() then
				below = bar;
			end
		end
	end

	-- the stance bar (StanceBar): small buttons over the top bottom bar, at its left
	if not Placed("ShapeshiftBarFrame") then
		ShapeshiftBarFrame:ClearAllPoints();
		ShapeshiftBarFrame:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, BAR_SPACING);
	end

	-- the pet bar: right over the top bottom bar (its buttons stand on PetActionBarRetail, see PetBarRetail_Setup)
	if not Placed("PetActionBarRetail") then
		PetActionBarRetail:ClearAllPoints();
		PetActionBarRetail:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, BAR_SPACING);
	end

	-- the totem bar: where the stance bar is (a shaman has no stances). It slides from MainMenuBar's top left
	-- (MultiCastActionBarFrame.lua): give the slide that place
	local left, top = below:GetLeft(), below:GetTop();
	if left and top and MainMenuBar:GetLeft() and MultiCastActionBarFrame then
		MULTICASTACTIONBAR_XPOS = left - MainMenuBar:GetLeft();
		MULTICASTACTIONBAR_YPOS = top + BAR_SPACING - MainMenuBar:GetTop();
		MultiCastActionBarFrame:ClearAllPoints();
		MultiCastActionBarFrame:SetPoint("BOTTOMLEFT", MainMenuBar, "TOPLEFT", MULTICASTACTIONBAR_XPOS, MULTICASTACTIONBAR_YPOS);
	end

	-- right bars: at the right edge, centered, MultiBarLeft left of MultiBarRight
	-- centered on the screen's height, but never over the minimap (a big UI scale leaves little height)
	if not Placed("MultiBarRight") then
		MultiBarRight:ClearAllPoints();
		local screenHeight = UIParent:GetHeight();
		local minimapBottom = MinimapCluster and MinimapCluster:GetBottom();
		local length = MultiBarRight:GetHeight();
		if minimapBottom and (screenHeight + length) / 2 > minimapBottom - BAR_SPACING then
			MultiBarRight:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -5, minimapBottom - BAR_SPACING - screenHeight);
		else
			MultiBarRight:SetPoint("RIGHT", UIParent, "RIGHT", -5, 0);
		end
	end
	if not Placed("MultiBarLeft") then
		MultiBarLeft:ClearAllPoints();
		MultiBarLeft:SetPoint("TOPRIGHT", MultiBarRight, "TOPLEFT", -BAR_SPACING, 0);
	end
end

local function MultiActionBarsRetail_Setup()
	-- UIParent_ManageFramePositions would put the stock places back
	if UIPARENT_MANAGED_FRAME_POSITIONS then
		UIPARENT_MANAGED_FRAME_POSITIONS["MultiBarBottomLeft"] = nil;
		UIPARENT_MANAGED_FRAME_POSITIONS["MultiBarRight"] = nil;
		UIPARENT_MANAGED_FRAME_POSITIONS["ShapeshiftBarFrame"] = nil;
		UIPARENT_MANAGED_FRAME_POSITIONS["MultiCastActionBarFrame"] = nil;
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
			-- the right bars open their flyouts to the left (MultiBar3 / 4 ButtonTemplate)
			if not info.horizontal then
				button:SetAttribute("flyoutDirection", "LEFT");
				ActionButton_UpdateFlyout(button);
			end
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
	PetBarRetail_Setup();
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
	-- UIParent_ManageFramePositions sizes the stance buttons' frames (50 / 64) each time it runs:
	-- the frame keeps the small retail size, the stock calls do nothing
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local normal = _G["ShapeshiftButton" .. i .. "NormalTexture"];
		normal:SetWidth(31.6);
		normal:SetHeight(30.9);
		normal.SetWidth = function() end;
		normal.SetHeight = function() end;
	end
	-- ShapeshiftBar_Update moves the first button for a single form: put it back
	hooksecurefunc("ShapeshiftBar_Update", StanceBarRetail_LayoutButtons);
	StanceBarRetail_LayoutButtons();
end

---------------------------------------------------------------------------
-- the pet bar (PetActionBarFrame): retail PetActionBar.xml, small buttons, no bar art.
-- The stock frame keeps sliding (PetActionBarFrame.lua) and showing / hiding its buttons; the buttons themselves
-- stand on PetActionBarRetail (a plain frame), so the slide does not move them.
---------------------------------------------------------------------------

local petAnchor = CreateFrame("Frame", "PetActionBarRetail", UIParent);
petAnchor:SetWidth(NUM_PET_ACTION_SLOTS * (SMALL_SIZE + BUTTON_PADDING) - BUTTON_PADDING);
petAnchor:SetHeight(SMALL_SIZE);

function PetBarRetail_Setup()
	PetActionBarFrame:EnableMouse(false);	-- the stock frame stays at the old place: no dead mouse area there
	for i = 1, NUM_PET_ACTION_SLOTS do
		local button = _G["PetActionButton" .. i];
		ActionButtonRetail_ApplySmall(button);
		button:ClearAllPoints();
		button:SetPoint("TOPLEFT", petAnchor, "TOPLEFT", (i - 1) * (SMALL_SIZE + BUTTON_PADDING), 0);
	end
	-- PetActionBar_Update puts UI-Quickslot back as the frame
	hooksecurefunc("PetActionBar_Update", function()
		for i = 1, NUM_PET_ACTION_SLOTS do
			ActionButtonRetail_UpdateNormal(_G["PetActionButton" .. i]);
		end
	end);
end

MultiActionBarsRetail_Setup();

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
eventFrame:RegisterEvent("UI_SCALE_CHANGED");
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED");
eventFrame:SetScript("OnEvent", function(self, event)
	if event ~= "PLAYER_REGEN_ENABLED" or layoutPending then
		StanceBarRetail_LayoutButtons();
		MultiActionBarsRetail_Layout();
	end
end);
