-- The retail action bars and the other HUD frames in Edit Mode (EditMode\EditModeCore.lua):
--   action bars 1-5 (MainActionBar, MultiBarBottomLeft / BottomRight / Right / Left), the stance bar, the pet bar,
--   the status bars (experience / reputation), the pet frame and the boss frames (the buffs: EditMode\AuraFramesEditMode.lua).
-- Bars 2-5 get the retail action bar settings (EditModeSettingDisplayInfo.lua): orientation, rows, number of icons,
-- icon size, icon padding, when the bar is shown. Their own auto layout (MultiActionBarsRetail_Layout) leaves alone
-- a bar the layout places (EditModeCore:HasPosition).
-- Loaded by MainActionBar.xml after MultiActionBarsRetail.lua.

local BUTTON_SIZE = 45;
local NUM_BUTTONS = 12;

-- out of the way for the icons over the chosen number (secure buttons: reparented, not hidden)
local hiddenButtons = CreateFrame("Frame");
hiddenButtons:Hide();

local ORIENTATION_HORIZONTAL, ORIENTATION_VERTICAL = 0, 1;
local VISIBLE_ALWAYS, VISIBLE_IN_COMBAT, VISIBLE_OUT_OF_COMBAT, VISIBLE_HIDDEN = 0, 1, 2, 3;

local function Label(text, fallback)
	return text or fallback;
end

---------------------------------------------------------------------------
-- a bar's buttons by its settings
---------------------------------------------------------------------------
local pendingBars = {};

local function LayoutBar(bar)
	-- secure buttons: never in combat, done when it ends
	if InCombatLockdown() then
		pendingBars[bar] = true;
		return;
	end
	pendingBars[bar] = nil;

	local settings = bar.editModeSettings;
	local count = settings.numIcons;
	local lines = math.max(1, math.min(settings.rows, count));
	local perLine = math.ceil(count / lines);
	local scale = settings.iconSize;
	local step = BUTTON_SIZE * scale + settings.iconPadding;
	local horizontal = settings.orientation == ORIENTATION_HORIZONTAL;

	for i = 1, NUM_BUTTONS do
		local button = _G[bar:GetName() .. "Button" .. i];
		if i <= count then
			if button:GetParent() ~= bar then
				button:SetParent(bar);
			end
			local index = i - 1;
			local along, across = index % perLine, math.floor(index / perLine);
			local x, y;
			if horizontal then
				x, y = along * step, -across * step;
			else
				x, y = across * step, -along * step;
			end
			button:SetScale(scale);
			-- (the flyout arrow over the retail frame again: the layer order got lost with the re-layout)
			if button.FlyoutArrow then
				button.FlyoutArrow:SetDrawLayer("OVERLAY", 3);
			end
			button:ClearAllPoints();
			-- the offsets are in the button's own (scaled) units
			button:SetPoint("TOPLEFT", bar, "TOPLEFT", x / scale, y / scale);
		else
			button:SetParent(hiddenButtons);
		end
	end

	local long = perLine * step - settings.iconPadding;
	local short = lines * step - settings.iconPadding;
	if horizontal then
		bar:SetWidth(long);
		bar:SetHeight(short);
	else
		bar:SetWidth(short);
		bar:SetHeight(long);
	end

	-- when the bar is shown (retail "Show bar"): a state driver; "always" - the stock interface option decides
	if settings.visibility == VISIBLE_ALWAYS then
		if bar.editModeDriver then
			UnregisterStateDriver(bar, "visibility");
			bar.editModeDriver = nil;
			if MultiActionBar_Update then
				MultiActionBar_Update();
			end
		end
	else
		local state = settings.visibility == VISIBLE_IN_COMBAT and "[combat] show; hide"
			or settings.visibility == VISIBLE_OUT_OF_COMBAT and "[combat] hide; show"
			or "hide";
		RegisterStateDriver(bar, "visibility", state);
		bar.editModeDriver = true;
	end

	if MultiActionBarsRetail_Layout then
		MultiActionBarsRetail_Layout();
	end
end

local function BarSetting(key, defaultValue)
	return function(frame, value)
		frame.editModeSettings = frame.editModeSettings or {};
		frame.editModeSettings[key] = value;
		-- all the settings applied (the layout sets them one by one): lay the bar out once they are there
		if frame.editModeSettingsReady then
			LayoutBar(frame);
		end
	end
end

-- the retail action bar settings (EditModeSettingDisplayInfo.lua, Enum.EditModeActionBarSetting)
local function ActionBarSettings(defaultOrientation)
	return {
		{
			key = "orientation", type = "dropdown", default = defaultOrientation,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ORIENTATION, "Ориентация"),
			options = {
				{ ORIENTATION_HORIZONTAL, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ORIENTATION_HORIZONTAL, "Горизонтально") },
				{ ORIENTATION_VERTICAL, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ORIENTATION_VERTICAL, "Вертикально") },
			},
			apply = BarSetting("orientation"),
		},
		{
			key = "rows", type = "slider", min = 1, max = 4, step = 1, default = 1,
			label = defaultOrientation == ORIENTATION_VERTICAL and Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_NUM_COLUMNS, "Столбцы: #")
				or Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_NUM_ROWS, "Ряды: #"),
			apply = BarSetting("rows"),
		},
		{
			key = "numIcons", type = "slider", min = 6, max = 12, step = 1, default = 12,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_NUM_ICONS, "Значки: #"),
			apply = BarSetting("numIcons"),
		},
		{
			key = "iconSize", type = "slider", min = 0.5, max = 2, step = 0.1, default = 1,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_SIZE, "Размер значков"),
			format = function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)); end,
			apply = BarSetting("iconSize"),
		},
		{
			key = "iconPadding", type = "slider", min = 2, max = 10, step = 1, default = 2,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_PADDING, "Отступ между значками"),
			apply = BarSetting("iconPadding"),
		},
		{
			key = "visibility", type = "dropdown", default = VISIBLE_ALWAYS,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING, "Показать панель"),
			options = {
				{ VISIBLE_ALWAYS, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_ALWAYS, "Всегда показывать") },
				{ VISIBLE_IN_COMBAT, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_IN_COMBAT, "В бою") },
				{ VISIBLE_OUT_OF_COMBAT, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_OUT_OF_COMBAT, "Не в бою") },
				{ VISIBLE_HIDDEN, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_HIDDEN, "Скрыть") },
			},
			apply = BarSetting("visibility"),
		},
	};
end

-- the stance / pet bar: retail orientation, rows, icon size, icon padding (small buttons, MultiActionBarsRetail.lua)
local function SmallBarSettings(relayout, maxRows)
	local function apply(key)
		return function(frame, value)
			frame.editModeSettings = frame.editModeSettings or {};
			frame.editModeSettings[key] = value;
			relayout();
		end
	end
	return {
		{
			key = "orientation", type = "dropdown", default = ORIENTATION_HORIZONTAL,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ORIENTATION, "Ориентация"),
			options = {
				{ ORIENTATION_HORIZONTAL, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ORIENTATION_HORIZONTAL, "Горизонтально") },
				{ ORIENTATION_VERTICAL, Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ORIENTATION_VERTICAL, "Вертикально") },
			},
			apply = apply("orientation"),
		},
		{
			key = "rows", type = "slider", min = 1, max = maxRows, step = 1, default = 1,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_NUM_ROWS, "Ряды: #"),
			apply = apply("rows"),
		},
		{
			key = "iconSize", type = "slider", min = 0.5, max = 2, step = 0.1, default = 1,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_SIZE, "Размер значков"),
			format = function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)); end,
			apply = apply("iconSize"),
		},
		{
			key = "iconPadding", type = "slider", min = 2, max = 10, step = 1, default = 2,
			label = Label(HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_PADDING, "Отступ между значками"),
			apply = apply("iconPadding"),
		},
	};
end

---------------------------------------------------------------------------
-- registration
---------------------------------------------------------------------------
local BAR_FORMAT = HUD_EDIT_MODE_ACTION_BAR_LABEL or "Панель команд %d";

local function Register()
	if not EditModeCore or not EditModeCore.RegisterSystem then
		return;
	end

	EditModeCore:RegisterSystem("MainActionBar", MainActionBar, string.format(BAR_FORMAT, 1), nil, { category = "combat" });

	-- bars 2-5 as in retail: 2 / 3 at the bottom, 4 / 5 at the right
	local bars = {
		{ "MultiBarBottomLeft", 2, ORIENTATION_HORIZONTAL },
		{ "MultiBarBottomRight", 3, ORIENTATION_HORIZONTAL },
		{ "MultiBarRight", 4, ORIENTATION_VERTICAL },
		{ "MultiBarLeft", 5, ORIENTATION_VERTICAL },
	};
	for _, info in ipairs(bars) do
		local bar = _G[info[1]];
		if bar then
			bar.editModeSettings = {};
			local settings = ActionBarSettings(info[3]);
			for _, setting in ipairs(settings) do
				bar.editModeSettings[setting.key] = setting.default;
			end
			bar.editModeSettingsReady = true;
			EditModeCore:RegisterSystem(info[1], bar, string.format(BAR_FORMAT, info[2]), settings, { category = "combat", noScale = true });
			LayoutBar(bar);
		end
	end

	EditModeCore:RegisterSystem("ShapeshiftBarFrame", ShapeshiftBarFrame, Label(HUD_EDIT_MODE_STANCE_BAR_LABEL, "Индикатор стойки"),
		SmallBarSettings(StanceBarRetail_LayoutButtons, 4), { category = "combat", noScale = true });
	if PetActionBarRetail then
		EditModeCore:RegisterSystem("PetActionBarRetail", PetActionBarRetail, Label(HUD_EDIT_MODE_PET_ACTION_BAR_LABEL, "Панель питомца"),
			SmallBarSettings(PetBarRetail_LayoutButtons, 2), { category = "combat", noScale = true });
	end
	-- the totem bar slides from MainMenuBar (MultiCastActionBarFrame.lua sets its point while it slides):
	-- the layout's place kept (keepPosition)
	if MultiCastActionBarFrame then
		EditModeCore:RegisterSystem("MultiCastActionBarFrame", MultiCastActionBarFrame, Label(HUD_EDIT_MODE_TOTEM_ACTION_BAR_LABEL, "Панель тотемов"),
			nil, { category = "combat", keepPosition = true });
	end
	if StatusTrackingBarRetailManager then
		EditModeCore:RegisterSystem("StatusTrackingBarRetailManager", StatusTrackingBarRetailManager, Label(HUD_EDIT_MODE_EXPERIENCE_BAR_LABEL, "Индикатор опыта"), nil, { category = "misc" });
	end
	if PetFrame then
		EditModeCore:RegisterSystem("PetFrame", PetFrame, Label(HUD_EDIT_MODE_PET_FRAME_LABEL, "Рамка питомца"));
	end
	if Boss1TargetFrame then
		EditModeCore:RegisterSystem("Boss1TargetFrame", Boss1TargetFrame, Label(HUD_EDIT_MODE_BOSS_FRAMES_LABEL, "Рамки боссов"));
	end

	if EditModeManagerFrame and EditModeManagerFrame.RefreshFrameList then
		EditModeManagerFrame:RefreshFrameList();
	end
end

-- the stock flyout update shows the arrow again: over the frame
if ActionButton_UpdateFlyout then
	hooksecurefunc("ActionButton_UpdateFlyout", function(button)
		if button.FlyoutArrow then
			button.FlyoutArrow:SetDrawLayer("OVERLAY", 3);
		end
	end);
end

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("PLAYER_LOGIN");
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
eventFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		Register();
		return;
	end
	for bar in pairs(pendingBars) do
		LayoutBar(bar);
	end
end);
