-- The retail aura frames in Edit Mode: "Buff frame" (BuffFrame) and "Debuff frame" (DebuffFrameRetail).
-- The stock 3.3.5 code anchors the buffs to ConsolidatedBuffs / TemporaryEnchantFrame (fixed at the top right of the
-- screen), not to BuffFrame: moving BuffFrame moved nothing. Here every icon is placed on a grid from its frame's
-- corner, by the retail AuraFrame settings (EditModeSettingDisplayInfo.lua, Enum.EditModeAuraFrameSetting):
-- orientation, icon wrap, icon direction, icons per row (icon limit), icon size, icon padding.
-- The buffs: the consolidated buffs icon, the weapon enchants, then the buffs; the debuffs on their own grid.
-- Loaded by EditModeCore.xml after EditModeCore.lua.

local ICON_SIZE = 30;
local TIME_HEIGHT = 12;		-- the duration under the icon: a row is that much taller

local ORIENTATION_HORIZONTAL, ORIENTATION_VERTICAL = 0, 1;
-- wrap (the next row) and direction (the next icon in a row)
local DIRECTION_LEFT, DIRECTION_RIGHT, DIRECTION_DOWN, DIRECTION_UP = 0, 1, 2, 3;

local function Label(text, fallback)
	return text or fallback;
end

-- the debuffs' own frame (retail DebuffFrame): under the buffs by default
local debuffFrame = CreateFrame("Frame", "DebuffFrameRetail", UIParent);
debuffFrame:SetFrameStrata("LOW");
debuffFrame:SetWidth(ICON_SIZE);
debuffFrame:SetHeight(ICON_SIZE);
debuffFrame:SetPoint("TOPRIGHT", BuffFrame, "BOTTOMRIGHT", 0, -20);

local DEFAULTS = {
	orientation = ORIENTATION_HORIZONTAL, iconWrap = DIRECTION_DOWN, iconDirection = DIRECTION_LEFT,
	iconLimit = 8, iconSize = 1, iconPadding = 5,
};

local function SettingsOf(frame)
	frame.editModeSettings = frame.editModeSettings or CopyTable(DEFAULTS);
	return frame.editModeSettings;
end

-- the icons on the frame's grid; the frame sized to a full row (so its Edit Mode selection shows where they go)
local function PlaceIcons(frame, icons)
	local settings = SettingsOf(frame);
	local horizontal = settings.orientation == ORIENTATION_HORIZONTAL;
	local scale = settings.iconSize;
	local limit = math.max(1, settings.iconLimit);
	local size = ICON_SIZE * scale;
	local alongStep = size + settings.iconPadding;
	local acrossStep = size + settings.iconPadding + (horizontal and TIME_HEIGHT or 0);
	if not horizontal then
		alongStep = alongStep + TIME_HEIGHT;
	end

	-- the corner the grid starts from: the direction the icons go and the way the rows wrap
	local direction, wrap = settings.iconDirection, settings.iconWrap;
	local alongX, alongY, acrossX, acrossY = 0, 0, 0, 0;
	if horizontal then
		alongX = direction == DIRECTION_RIGHT and 1 or -1;
		acrossY = wrap == DIRECTION_UP and 1 or -1;
	else
		alongY = direction == DIRECTION_UP and 1 or -1;
		acrossX = wrap == DIRECTION_RIGHT and 1 or -1;
	end
	local vertical = (alongY > 0 or acrossY > 0) and "BOTTOM" or "TOP";
	local side = (alongX > 0 or acrossX > 0) and "LEFT" or "RIGHT";
	local corner = vertical .. side;

	for index, icon in ipairs(icons) do
		local i = index - 1;
		local along, across = i % limit, math.floor(i / limit);
		local x = along * alongStep * alongX + across * acrossStep * acrossX;
		local y = along * alongStep * alongY + across * acrossStep * acrossY;
		icon:SetScale(scale);
		icon:ClearAllPoints();
		-- (the offsets in the icon's own, scaled units)
		icon:SetPoint(corner, frame, corner, x / scale, y / scale);
	end

	-- the frame: a row of the icon limit
	local long = limit * alongStep - settings.iconPadding;
	local short = size;
	if horizontal then
		frame:SetWidth(long);
		frame:SetHeight(short);
	else
		frame:SetWidth(short);
		frame:SetHeight(long);
	end
end

local function UpdateBuffs()
	local icons = {};
	if BuffFrame.numConsolidated and BuffFrame.numConsolidated > 0 and ConsolidatedBuffs:IsShown() then
		table.insert(icons, ConsolidatedBuffs);
	end
	for i = 1, 3 do
		local enchant = _G["TempEnchant" .. i];
		if enchant and enchant:IsShown() then
			table.insert(icons, enchant);
		end
	end
	for i = 1, BUFF_ACTUAL_DISPLAY or 0 do
		local buff = _G["BuffButton" .. i];
		if buff and not buff.consolidated and buff:IsShown() then
			table.insert(icons, buff);
		end
	end
	PlaceIcons(BuffFrame, icons);
end

local function UpdateDebuffs()
	local icons = {};
	for i = 1, DEBUFF_ACTUAL_DISPLAY or 0 do
		local debuff = _G["DebuffButton" .. i];
		if debuff and debuff:IsShown() then
			table.insert(icons, debuff);
		end
	end
	PlaceIcons(debuffFrame, icons);
end

-- after the stock code placed them
hooksecurefunc("BuffFrame_UpdateAllBuffAnchors", function()
	UpdateBuffs();
	UpdateDebuffs();
end);
hooksecurefunc("DebuffButton_UpdateAnchors", function(buttonName)
	if buttonName == "DebuffButton" then
		UpdateDebuffs();
	end
end);

---------------------------------------------------------------------------
-- the settings
---------------------------------------------------------------------------
local function Setting(update)
	return function(key)
		return function(frame, value)
			SettingsOf(frame)[key] = value;
			update();
		end
	end
end

local function AuraSettings(update)
	local apply = Setting(update);
	return {
		{
			key = "orientation", type = "dropdown", default = DEFAULTS.orientation,
			label = Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ORIENTATION, "Ориентация"),
			options = {
				{ ORIENTATION_HORIZONTAL, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ORIENTATION_HORIZONTAL, "Горизонтально") },
				{ ORIENTATION_VERTICAL, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ORIENTATION_VERTICAL, "Вертикально") },
			},
			apply = apply("orientation"),
		},
		{
			key = "iconWrap", type = "dropdown", default = DEFAULTS.iconWrap,
			label = Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_WRAP, "Направление значков"),
			options = {
				{ DIRECTION_DOWN, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_WRAP_DOWN, "Вниз") },
				{ DIRECTION_UP, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_WRAP_UP, "Вверх") },
				{ DIRECTION_LEFT, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_WRAP_LEFT, "Слева") },
				{ DIRECTION_RIGHT, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_WRAP_RIGHT, "Справа") },
			},
			apply = apply("iconWrap"),
		},
		{
			key = "iconDirection", type = "dropdown", default = DEFAULTS.iconDirection,
			label = Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION, "Выравнивание значков"),
			options = {
				{ DIRECTION_LEFT, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_LEFT, "Влево") },
				{ DIRECTION_RIGHT, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_RIGHT, "Вправо") },
				{ DIRECTION_DOWN, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_DOWN, "Вниз") },
				{ DIRECTION_UP, Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_UP, "Вверх") },
			},
			apply = apply("iconDirection"),
		},
		{
			key = "iconLimit", type = "slider", min = 2, max = 16, step = 1, default = DEFAULTS.iconLimit,
			label = Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_LIMIT, "Количество значков"),
			apply = apply("iconLimit"),
		},
		{
			key = "iconSize", type = "slider", min = 0.5, max = 2, step = 0.1, default = DEFAULTS.iconSize,
			label = Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_SIZE, "Размер значков"),
			format = function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)); end,
			apply = apply("iconSize"),
		},
		{
			key = "iconPadding", type = "slider", min = 0, max = 15, step = 1, default = DEFAULTS.iconPadding,
			label = Label(HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_PADDING, "Отступ между значками"),
			apply = apply("iconPadding"),
		},
	};
end

local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_LOGIN");
loader:SetScript("OnEvent", function()
	-- the buffs started at ConsolidatedBuffs' place (it is anchored to the screen): BuffFrame there now - and not to
	-- ConsolidatedBuffs itself, that icon is placed on BuffFrame's grid
	local point, _, relativePoint, x, y = ConsolidatedBuffs:GetPoint(1);
	if point then
		BuffFrame:ClearAllPoints();
		BuffFrame:SetPoint(point, UIParent, relativePoint, x, y);
	end
	EditModeCore:RegisterSystem("BuffFrame", BuffFrame, Label(HUD_EDIT_MODE_BUFF_FRAME_LABEL, "Рамка эффекта+"),
		AuraSettings(UpdateBuffs), { category = "combat", noScale = true });
	EditModeCore:RegisterSystem("DebuffFrameRetail", debuffFrame, Label(HUD_EDIT_MODE_DEBUFF_FRAME_LABEL, "Рамка эффекта-"),
		AuraSettings(UpdateDebuffs), { category = "combat", noScale = true });
	UpdateBuffs();
	UpdateDebuffs();
end);
