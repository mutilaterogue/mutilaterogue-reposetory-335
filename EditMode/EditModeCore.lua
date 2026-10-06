-- Edit Mode для 3.3.5a (по мотивам Blizzard_EditMode ретейла):
--   * окно режима: макеты (новый/копия/переименовать/удалить), сетка + шаг, привязка,
--     список фреймов, "Отменить все изменения" / "Сохранить";
--   * клик по фрейму выделяет его и открывает окно его настроек (размер, сброс позиции,
--     отмена изменений) - как EditModeSystemSettingsDialog;
--   * перетаскивание с привязкой к сетке, позиции и настройки - в макете (C_EditMode).
--
-- Регистрация своих фреймов:
--   EditModeCore:RegisterSystem("Имя", фрейм, "Подпись", { доп. настройки })
-- доп. настройка: { key = "alpha", type = "slider", label = "...", min, max, step, default,
--                   format = function(v) end, apply = function(frame, v) end }
--             или { key = "x", type = "check", label = "...", default = 0/1, apply = ... }

EDIT_MODE_GRID_SPACING = 32;
EDIT_MODE_SNAP_DISTANCE = 12;

local L = {
	TITLE = HUD_EDIT_MODE_TITLE or "Настройка интерфейса",
	LAYOUT = HUD_EDIT_MODE_LAYOUT or "Макет",
	SHOW_GRID = HUD_EDIT_MODE_SHOW_GRID or "Сетка",
	GRID_SPACING = HUD_EDIT_MODE_GRID_SPACING or "Шаг сетки",
	ENABLE_SNAP = HUD_EDIT_MODE_ENABLE_SNAP or "Привязка элементов",
	FRAMES = HUD_EDIT_MODE_SETTINGS_CATEGORY_TITLE_FRAMES or "Фреймы",
	REVERT_ALL = HUD_EDIT_MODE_REVERT_ALL_CHANGES or "Отменить все изменения",
	SAVE = HUD_EDIT_MODE_SAVE_LAYOUT or "Сохранить",
	RESET_POSITION = HUD_EDIT_MODE_RESET_POSITION or "Сбросить позицию",
	REVERT_CHANGES = HUD_EDIT_MODE_REVERT_CHANGES or "Отменить изменения",
	NEW_LAYOUT = "+ Новый макет",
	COPY_LAYOUT = HUD_EDIT_MODE_COPY_LAYOUT or "Копировать макет",
	RENAME_LAYOUT = HUD_EDIT_MODE_RENAME_LAYOUT or "Переименовать макет",
	DELETE_LAYOUT = HUD_EDIT_MODE_DELETE_LAYOUT or "Удалить макет",
	NAME_LAYOUT = HUD_EDIT_MODE_NAME_LAYOUT_DIALOG_TITLE or "Название макета",
	SIZE = "Размер",
	CLICK_TO_EDIT = HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT or "Щелкните, чтобы изменить",
	EYE_SIZE = HUD_EDIT_MODE_SETTING_MICRO_MENU_EYE_SIZE or "Размер глаза",
};

EditModeCore = {
	systems = {},     -- [systemName] = { frame, displayName, settings, overlay, defaultPoints, defaultScale }
	order = {},       -- имена систем в порядке регистрации
	active = false,
	selected = nil,
};

-- настройки, которые есть у каждого фрейма
local COMMON_SETTINGS = {
	{
		key = "scale", type = "slider", label = L.SIZE, min = 0.5, max = 2, step = 0.05, default = 1,
		format = function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)); end,
		apply = function(frame, value) frame:SetScale(value); end,
	},
};

---------------------------------------------------------------------------
-- настройки аккаунта
---------------------------------------------------------------------------
local function GetAccountSetting(setting)
	for _, entry in ipairs(C_EditMode.GetAccountSettings()) do
		if entry.setting == setting then
			return entry.value;
		end
	end
	return nil;
end

local function SetAccountSetting(setting, value)
	C_EditMode.SetAccountSetting(setting, value);
end

local GRID_SPACING_SETTING = Enum.EditModeAccountSetting.GridSpacing;

---------------------------------------------------------------------------
-- сетка
---------------------------------------------------------------------------
local grid = CreateFrame("Frame", "EditModeGrid", UIParent);
grid:SetAllPoints(UIParent);
grid:SetFrameStrata("BACKGROUND");
grid:Hide();
grid.lines = {};

local function BuildGrid()
	for _, line in ipairs(grid.lines) do
		line:Hide();
	end

	local spacing = EDIT_MODE_GRID_SPACING;
	local width, height = UIParent:GetWidth(), UIParent:GetHeight();
	local centerX, centerY = width / 2, height / 2;
	local index = 0;

	local function GetLine()
		index = index + 1;
		local line = grid.lines[index];
		if not line then
			line = grid:CreateTexture(nil, "BACKGROUND");
			grid.lines[index] = line;
		end
		line:Show();
		return line;
	end

	-- как в ретейле: линии идут от центра экрана, центральные ярче
	for offset = 0, centerX, spacing do
		for _, sign in ipairs(offset == 0 and { 1 } or { 1, -1 }) do
			local line = GetLine();
			local x = centerX + offset * sign;
			line:ClearAllPoints();
			line:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0);
			line:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", x, 0);
			line:SetWidth(1);
			if offset == 0 then
				line:SetTexture(1, 0.2, 0.2, 0.6);
			else
				line:SetTexture(1, 1, 1, 0.12);
			end
		end
	end

	for offset = 0, centerY, spacing do
		for _, sign in ipairs(offset == 0 and { 1 } or { 1, -1 }) do
			local line = GetLine();
			local y = centerY + offset * sign;
			line:ClearAllPoints();
			line:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, y);
			line:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", 0, y);
			line:SetHeight(1);
			if offset == 0 then
				line:SetTexture(1, 0.2, 0.2, 0.6);
			else
				line:SetTexture(1, 1, 1, 0.12);
			end
		end
	end
end

local function UpdateGridShown()
	if EditModeCore.active and (GetAccountSetting(Enum.EditModeAccountSetting.ShowGrid) or 1) ~= 0 then
		BuildGrid();
		grid:Show();
	else
		grid:Hide();
	end
end

---------------------------------------------------------------------------
-- координаты: позиция хранится в координатах UIParent (левый нижний угол фрейма)
---------------------------------------------------------------------------
local function GetRelativeScale(frame)
	return frame:GetEffectiveScale() / UIParent:GetEffectiveScale();
end

local function SetFramePosition(frame, x, y)
	local scale = GetRelativeScale(frame);
	frame:ClearAllPoints();
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale);
end

local function GetFramePosition(frame)
	local left, bottom = frame:GetLeft(), frame:GetBottom();
	if not left or not bottom then
		return nil;
	end
	local scale = GetRelativeScale(frame);
	return left * scale, bottom * scale;
end

-- the saved place (retail style): the frame's point nearest to the screen's edges (corner, side or center),
-- the offset from that same point of UIParent. A frame at the right / top edge stays there when the UI scale
-- (UIParent's size in UI units) changes; from the bottom left corner it would drift.
local function GetAnchoredPosition(frame, defaultPoint)
	local left, bottom = GetFramePosition(frame);
	if not left then
		return nil;
	end
	local scale = GetRelativeScale(frame);
	local width, height = frame:GetWidth() * scale, frame:GetHeight() * scale;
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight();
	local centerX, centerY = left + width / 2, bottom + height / 2;

	-- by the nearest edge, not the center: a frame whose size follows the screen or its contents
	-- (the objective tracker's height, the micro menu's width) keeps that edge where it was
	local right, top = left + width, bottom + height;
	-- a frame near both edges (the objective tracker is almost the screen's height): the side of its default
	-- anchor, the one it grows from
	defaultPoint = defaultPoint or "";
	local h, x;
	if math.min(left, screenWidth - right) < screenWidth / 3 then
		local nearLeft = left <= screenWidth - right;
		if left < screenWidth / 3 and screenWidth - right < screenWidth / 3 then
			if defaultPoint:find("LEFT") then
				nearLeft = true;
			elseif defaultPoint:find("RIGHT") then
				nearLeft = false;
			end
		end
		if nearLeft then
			h, x = "LEFT", left;
		else
			h, x = "RIGHT", right - screenWidth;
		end
	else
		h, x = "", centerX - screenWidth / 2;
	end
	local v, y;
	if math.min(bottom, screenHeight - top) < screenHeight / 3 then
		local nearBottom = bottom <= screenHeight - top;
		if bottom < screenHeight / 3 and screenHeight - top < screenHeight / 3 then
			if defaultPoint:find("BOTTOM") then
				nearBottom = true;
			elseif defaultPoint:find("TOP") then
				nearBottom = false;
			end
		end
		if nearBottom then
			v, y = "BOTTOM", bottom;
		else
			v, y = "TOP", top - screenHeight;
		end
	else
		v, y = "", centerY - screenHeight / 2;
	end
	local point = v .. h;
	if point == "" then
		point = "CENTER";
	end
	return point, x, y;
end

local function SetAnchoredPosition(frame, point, x, y)
	local scale = GetRelativeScale(frame);
	frame:ClearAllPoints();
	frame:SetPoint(point, UIParent, point, x / scale, y / scale);
end

-- привязка к сетке: к линиям, которые идут от центра экрана
local function SnapValue(value, center, spacing)
	local snapped = center + math.floor((value - center) / spacing + 0.5) * spacing;
	return (math.abs(snapped - value) <= EDIT_MODE_SNAP_DISTANCE) and snapped or value;
end

local function SnapFrame(frame)
	if (GetAccountSetting(Enum.EditModeAccountSetting.EnableSnap) or 1) == 0 then
		return;
	end

	local x, y = GetFramePosition(frame);
	if not x then
		return;
	end

	local spacing = EDIT_MODE_GRID_SPACING;
	local snappedX = SnapValue(x, UIParent:GetWidth() / 2, spacing);
	local snappedY = SnapValue(y, UIParent:GetHeight() / 2, spacing);

	if snappedX ~= x or snappedY ~= y then
		SetFramePosition(frame, snappedX, snappedY);
	end
end

-- фрейм не должен уходить за край экрана
function EditModeCore:ClampToScreen(frame)
	local x, y = GetFramePosition(frame);
	if not x then
		return;
	end

	local scale = GetRelativeScale(frame);
	local maxX = UIParent:GetWidth() - frame:GetWidth() * scale;
	local maxY = UIParent:GetHeight() - frame:GetHeight() * scale;
	local clampedX = math.max(0, math.min(x, maxX));
	local clampedY = math.max(0, math.min(y, maxY));

	if clampedX ~= x or clampedY ~= y then
		SetFramePosition(frame, clampedX, clampedY);
	end
end

---------------------------------------------------------------------------
-- макеты
---------------------------------------------------------------------------
local function GetActiveLayout()
	local info = C_EditMode.GetLayouts();
	return info.layouts and info.layouts[info.activeLayout];
end

local function GetLayoutEntry(systemName, create)
	local layout = GetActiveLayout();
	if not layout then
		return nil;
	end

	layout.systems = layout.systems or {};
	for _, entry in ipairs(layout.systems) do
		if entry.name == systemName then
			entry.settings = entry.settings or {};
			return entry;
		end
	end

	if create then
		local entry = { name = systemName, settings = {} };
		table.insert(layout.systems, entry);
		return entry;
	end
	return nil;
end

function EditModeCore:SaveLayouts()
	local info = C_EditMode.GetLayouts();
	C_EditMode.SaveLayouts({ layouts = info.layouts, activeLayout = info.activeLayout });
end

---------------------------------------------------------------------------
-- системы
---------------------------------------------------------------------------
function EditModeCore:RegisterSystem(systemName, frame, displayName, extraSettings)
	if not frame or self.systems[systemName] then
		return;
	end

	-- исходная позиция и размер - для "Сбросить позицию" и макетов без записи об этом фрейме
	local defaultPoints = {};
	for i = 1, frame:GetNumPoints() do
		defaultPoints[i] = { frame:GetPoint(i) };
	end

	local settings = {};
	for _, setting in ipairs(COMMON_SETTINGS) do
		table.insert(settings, setting);
	end
	for _, setting in ipairs(extraSettings or {}) do
		table.insert(settings, setting);
	end

	self.systems[systemName] = {
		name = systemName,
		frame = frame,
		displayName = displayName or systemName,
		settings = settings,
		defaultPoints = defaultPoints,
		defaultScale = frame:GetScale(),
	};
	table.insert(self.order, systemName);

	self:ApplyLayoutToSystem(systemName);

	if EditModeManagerFrame and EditModeManagerFrame.RefreshFrameList then
		EditModeManagerFrame:RefreshFrameList();
	end
end

function EditModeCore:GetSystem(systemName)
	return self.systems[systemName];
end

function EditModeCore:GetSettingValue(systemName, setting)
	local entry = GetLayoutEntry(systemName, false);
	local value = entry and entry.settings[setting.key];
	if value == nil then
		if setting.key == "scale" then
			return self.systems[systemName].defaultScale or setting.default;
		end
		return setting.default;
	end
	return value;
end

function EditModeCore:SetSettingValue(systemName, key, value)
	local system = self.systems[systemName];
	local entry = GetLayoutEntry(systemName, true);
	if not system or not entry then
		return;
	end

	-- смена размера не должна сдвигать фрейм: держим левый нижний угол на месте
	local x, y = GetFramePosition(system.frame);
	entry.settings[key] = value;

	for _, setting in ipairs(system.settings) do
		if setting.key == key and setting.apply then
			setting.apply(system.frame, value);
		end
	end

	if key == "scale" and x then
		SetFramePosition(system.frame, x, y);
		self:ClampToScreen(system.frame);
		self:StoreSystemPosition(systemName);
	else
		self:SaveLayouts();
	end
end

function EditModeCore:StoreSystemPosition(systemName)
	local system = self.systems[systemName];
	local entry = GetLayoutEntry(systemName, true);
	if not system or not entry then
		return;
	end

	local point, x, y = GetAnchoredPosition(system.frame, system.defaultPoints[1] and system.defaultPoints[1][1]);
	if point then
		entry.point, entry.x, entry.y = point, x, y;
	end
	self:SaveLayouts();
end

local function RestoreDefaultPosition(system)
	local frame = system.frame;
	frame:SetScale(system.defaultScale or 1);
	if #system.defaultPoints > 0 then
		frame:ClearAllPoints();
		for _, point in ipairs(system.defaultPoints) do
			frame:SetPoint(unpack(point));
		end
	end
end

function EditModeCore:ApplyLayoutToSystem(systemName)
	local system = self.systems[systemName];
	if not system then
		return;
	end

	local entry = GetLayoutEntry(systemName, false);
	RestoreDefaultPosition(system);

	if not entry then
		return;
	end

	-- сначала настройки (размер влияет на координаты), потом позиция
	for _, setting in ipairs(system.settings) do
		local value = entry.settings[setting.key];
		if value ~= nil and setting.apply then
			setting.apply(system.frame, value);
		end
	end

	if entry.x and entry.y then
		-- a layout saved before the anchored places: x / y are from the bottom left corner
		if entry.point then
			SetAnchoredPosition(system.frame, entry.point, entry.x, entry.y);
		else
			SetFramePosition(system.frame, entry.x, entry.y);
			-- and from now on anchored (kept with the next save)
			local point, x, y = GetAnchoredPosition(system.frame, system.defaultPoints[1] and system.defaultPoints[1][1]);
			if point then
				entry.point, entry.x, entry.y = point, x, y;
			end
		end
		self:ClampToScreen(system.frame);
	end
end

function EditModeCore:ApplyLayout()
	for _, systemName in ipairs(self.order) do
		self:ApplyLayoutToSystem(systemName);
	end
	if self.selected then
		EditModeSystemSettingsDialog:Refresh();
	end
end

function EditModeCore:SetActiveLayout(index)
	C_EditMode.SetActiveLayout(index);
	self.snapshot = CopyTable(GetActiveLayout().systems or {});
	self:ApplyLayout();
end

-- "Сбросить позицию" выбранного фрейма: убрать его из макета
function EditModeCore:ResetSystem(systemName)
	local layout = GetActiveLayout();
	if not layout or not layout.systems then
		return;
	end
	for index, entry in ipairs(layout.systems) do
		if entry.name == systemName then
			table.remove(layout.systems, index);
			break;
		end
	end
	self:ApplyLayoutToSystem(systemName);
	self:SaveLayouts();
end

-- вернуть фрейму состояние на момент входа в режим
function EditModeCore:RevertSystem(systemName)
	local layout = GetActiveLayout();
	if not layout then
		return;
	end
	layout.systems = layout.systems or {};

	for index, entry in ipairs(layout.systems) do
		if entry.name == systemName then
			table.remove(layout.systems, index);
			break;
		end
	end
	for _, entry in ipairs(self.snapshot or {}) do
		if entry.name == systemName then
			table.insert(layout.systems, CopyTable(entry));
			break;
		end
	end

	self:ApplyLayoutToSystem(systemName);
	self:SaveLayouts();
end

function EditModeCore:RevertAll()
	local layout = GetActiveLayout();
	if not layout then
		return;
	end
	layout.systems = CopyTable(self.snapshot or {});
	self:SaveLayouts();
	self:ApplyLayout();
end

---------------------------------------------------------------------------
-- накладки поверх фреймов (подсветка / выделение)
---------------------------------------------------------------------------
-- retail EditModeSystemSelectionLayout (EditModeSystemTemplates.lua): editmode-actionbar-highlight / -selected nine slices
local SELECTION_LAYOUT = {
	["TopRightCorner"] = { atlas = "%s-nineslice-corner", mirrorLayout = true, x = 8, y = 8 },
	["TopLeftCorner"] = { atlas = "%s-nineslice-corner", mirrorLayout = true, x = -8, y = 8 },
	["BottomLeftCorner"] = { atlas = "%s-nineslice-corner", mirrorLayout = true, x = -8, y = -8 },
	["BottomRightCorner"] = { atlas = "%s-nineslice-corner", mirrorLayout = true, x = 8, y = -8 },
	["TopEdge"] = { atlas = "_%s-nineslice-edgetop" },
	["BottomEdge"] = { atlas = "_%s-nineslice-edgebottom" },
	["LeftEdge"] = { atlas = "!%s-nineslice-edgeleft" },
	["RightEdge"] = { atlas = "!%s-nineslice-edgeright" },
	["Center"] = { atlas = "%s-nineslice-center", x = -8, y = 8, x1 = 8, y1 = -8 },
};
local HIGHLIGHT_KIT = "editmode-actionbar-highlight";
local SELECTED_KIT = "editmode-actionbar-selected";
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" };

-- retail: the label shows the frame's name when selected, "click to edit" while the mouse is over it
local function UpdateOverlayLabel(overlay)
	if overlay.state == "selected" then
		overlay.Label:SetText(overlay.system.displayName);
		overlay.Label:Show();
	elseif overlay.hovered then
		overlay.Label:SetText(L.CLICK_TO_EDIT);
		overlay.Label:Show();
	else
		overlay.Label:Hide();
	end
end

local function SetOverlayState(overlay, state)
	if overlay.state ~= state then
		NineSliceUtil.ApplyLayout(overlay, SELECTION_LAYOUT, state == "selected" and SELECTED_KIT or HIGHLIGHT_KIT);
	end
	overlay.state = state;
	UpdateOverlayLabel(overlay);
end

local function CreateOverlay(system)
	local overlay = CreateFrame("Button", "EditModeOverlay" .. system.name, UIParent);
	overlay.system = system;
	overlay:SetFrameStrata("HIGH");
	overlay:SetToplevel(true);
	overlay:EnableMouse(true);
	overlay:RegisterForDrag("LeftButton");
	overlay:RegisterForClicks("LeftButtonUp");
	overlay:Hide();

	-- the mouse over: the highlight nine slice once more, added (retail MouseOverHighlight, alpha 0.4)
	overlay.MouseOverHighlight = CreateFrame("Frame", nil, overlay);
	overlay.MouseOverHighlight:SetAllPoints();
	overlay.MouseOverHighlight:SetAlpha(0.4);
	overlay.MouseOverHighlight:Hide();
	NineSliceUtil.ApplyLayout(overlay.MouseOverHighlight, SELECTION_LAYOUT, HIGHLIGHT_KIT);
	for _, piece in ipairs(PIECES) do
		if overlay.MouseOverHighlight[piece] then
			overlay.MouseOverHighlight[piece]:SetBlendMode("ADD");
		end
	end

	overlay.Label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
	overlay.Label:SetPoint("TOPLEFT", overlay, "TOPLEFT", 2, -2);
	overlay.Label:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -2, 2);
	overlay.Label:Hide();

	overlay:SetScript("OnEnter", function(self)
		self.hovered = true;
		self.MouseOverHighlight:Show();
		UpdateOverlayLabel(self);
		-- retail: the frame's name at the cursor while it is not selected
		if self.state ~= "selected" then
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR");
			GameTooltip:SetText(system.displayName);
			GameTooltip:Show();
		end
	end);
	overlay:SetScript("OnLeave", function(self)
		self.hovered = nil;
		self.MouseOverHighlight:Hide();
		UpdateOverlayLabel(self);
		GameTooltip:Hide();
	end);

	overlay:SetScript("OnClick", function()
		GameTooltip:Hide();
		EditModeCore:SelectSystem(system.name);
	end);

	overlay:SetScript("OnDragStart", function(self)
		EditModeCore:SelectSystem(system.name);
		local frame = system.frame;
		self.wasMovable = frame:IsMovable();
		frame:SetMovable(true);
		frame:StartMoving();
		self.moving = true;
	end);

	overlay:SetScript("OnDragStop", function(self)
		local frame = system.frame;
		frame:StopMovingOrSizing();
		frame:SetMovable(self.wasMovable and true or false);
		self.moving = false;

		SnapFrame(frame);
		EditModeCore:ClampToScreen(frame);
		EditModeCore:StoreSystemPosition(system.name);
	end);

	overlay:SetScript("OnUpdate", function(self)
		local frame = system.frame;
		self:ClearAllPoints();
		self:SetPoint("TOPLEFT", frame, "TOPLEFT");
		self:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT");
	end);

	SetOverlayState(overlay, "normal");
	return overlay;
end

local function IsSystemEditable(systemName)
	return GetAccountSetting("hide:" .. systemName) ~= 1;
end

function EditModeCore:UpdateOverlays()
	for _, systemName in ipairs(self.order) do
		local system = self.systems[systemName];
		if self.active and IsSystemEditable(systemName) then
			system.overlay = system.overlay or CreateOverlay(system);
			system.overlay:Show();
			SetOverlayState(system.overlay, self.selected == systemName and "selected" or "normal");
		elseif system.overlay then
			system.overlay:Hide();
		end
	end
end

---------------------------------------------------------------------------
-- выделение
---------------------------------------------------------------------------
function EditModeCore:SelectSystem(systemName)
	if not self.active or not self.systems[systemName] then
		return;
	end
	self.selected = systemName;
	self:UpdateOverlays();
	EditModeSystemSettingsDialog:AttachToSystem(self.systems[systemName]);
end

function EditModeCore:ClearSelection()
	self.selected = nil;
	EditModeSystemSettingsDialog:Hide();
	self:UpdateOverlays();
end

---------------------------------------------------------------------------
-- вход и выход
---------------------------------------------------------------------------
function EditModeCore:Enter()
	if self.active then
		return;
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Нельзя в бою", 1, 0.1, 0.1);
		return;
	end

	self.active = true;
	local layout = GetActiveLayout();
	self.snapshot = CopyTable(layout and layout.systems or {});

	UpdateGridShown();
	self:UpdateOverlays();

	EditModeManagerFrame:Show();
	EditModeManagerFrame:Refresh();
end

function EditModeCore:Exit()
	if not self.active then
		return;
	end

	self.active = false;
	self:ClearSelection();
	UpdateGridShown();
	self:UpdateOverlays();

	self:SaveLayouts();
	C_EditMode.OnEditModeExit();
	EditModeManagerFrame:Hide();
end

function EditModeCore:Toggle()
	if self.active then
		self:Exit();
	else
		self:Enter();
	end
end

-- совместимость со старым API
function EditModeCore:ResetLayout()
	self:RevertAll();
end

function EditModeCore:RefreshGrid()
	UpdateGridShown();
end

---------------------------------------------------------------------------
-- общие контролы
---------------------------------------------------------------------------
local controlCount = 0;
local function NextName(prefix)
	controlCount = controlCount + 1;
	return prefix .. controlCount;
end

local function CreateCheck(parent, label, onClick)
	local check = CreateFrame("CheckButton", NextName("EditModeCheck"), parent, "UICheckButtonTemplate");
	check:SetWidth(26);
	check:SetHeight(26);
	check.text = _G[check:GetName() .. "Text"];
	check.text:SetText(label);
	check.text:SetFontObject("GameFontHighlight");
	check:SetScript("OnClick", onClick);
	return check;
end

-- слайдер: подпись слева, значение справа
local function CreateSlider(parent, label, minValue, maxValue, step, format, onChange)
	local holder = CreateFrame("Frame", nil, parent);
	holder:SetHeight(32);

	holder.Label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	holder.Label:SetPoint("LEFT", holder, "LEFT", 0, 0);
	holder.Label:SetWidth(110);
	holder.Label:SetJustifyH("LEFT");
	holder.Label:SetText(label);

	local slider = CreateFrame("Slider", NextName("EditModeSlider"), holder, "OptionsSliderTemplate");
	slider:SetPoint("LEFT", holder.Label, "RIGHT", 6, 0);
	slider:SetWidth(150);
	slider:SetMinMaxValues(minValue, maxValue);
	slider:SetValueStep(step);
	_G[slider:GetName() .. "Text"]:SetText("");
	_G[slider:GetName() .. "Low"]:SetText("");
	_G[slider:GetName() .. "High"]:SetText("");
	holder.Slider = slider;

	holder.Value = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	holder.Value:SetPoint("LEFT", slider, "RIGHT", 10, 0);

	slider:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value / step + 0.5) * step;
		holder.Value:SetText(format(value));
		if not holder.refreshing then
			onChange(value);
		end
	end);

	holder.SetValueSilently = function(_, value)
		holder.refreshing = true;
		slider:SetValue(value);
		holder.refreshing = nil;
		holder.Value:SetText(format(value));
	end

	return holder;
end

local function CreateButton(parent, text, width, onClick)
	local button = CreateFrame("Button", NextName("EditModeButton"), parent, "UIPanelButtonTemplate");
	button:SetWidth(width);
	button:SetHeight(22);
	button:SetText(text);
	button:SetScript("OnClick", onClick);
	return button;
end

-- the texts of a dialog above its border: DialogBorderTranslucentTemplate is a child frame drawn over the
-- dialog's own regions, it dimmed the title and the labels
local function CreateContent(dialog)
	local content = CreateFrame("Frame", nil, dialog);
	content:SetAllPoints();
	content:SetFrameLevel(dialog:GetFrameLevel() + 5);
	return content;
end

---------------------------------------------------------------------------
-- окно режима
---------------------------------------------------------------------------
EditModeManagerMixin = {};

function EditModeManagerMixin:OnLoad()
	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", self.StartMoving);
	self:SetScript("OnDragStop", self.StopMovingOrSizing);
	tinsert(UISpecialFrames, self:GetName());
	self:SetScript("OnHide", function()
		EditModeCore:Exit();
	end);

	self.Content = CreateContent(self);
	-- retail: the title white and large, "Layout:" gold
	self.Title = self.Content:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge");
	self.Title:SetPoint("TOP", self, "TOP", 0, -15);
	self.Title:SetText(L.TITLE);

	-- макет
	self.LayoutLabel = self.Content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	self.LayoutLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 20, -48);
	self.LayoutLabel:SetText((L.LAYOUT:gsub(":$", "")) .. ":");

	self.LayoutDropdown = CreateFrame("Frame", "EditModeManagerFrameLayoutDropdown", self, "UIDropDownMenuTemplate");
	self.LayoutDropdown:SetPoint("LEFT", self.LayoutLabel, "RIGHT", -8, -2);
	UIDropDownMenu_SetWidth(self.LayoutDropdown, 230);
	UIDropDownMenu_Initialize(self.LayoutDropdown, function(dropdown, level)
		self:InitLayoutDropdown(level);
	end);

	-- сетка: галочка, под ней ползунок шага
	self.GridCheck = CreateCheck(self, L.SHOW_GRID, function(button)
		SetAccountSetting(Enum.EditModeAccountSetting.ShowGrid, button:GetChecked() and 1 or 0);
		UpdateGridShown();
	end);
	self.GridCheck:SetPoint("TOPLEFT", self, "TOPLEFT", 16, -80);

	self.SnapCheck = CreateCheck(self, L.ENABLE_SNAP, function(button)
		SetAccountSetting(Enum.EditModeAccountSetting.EnableSnap, button:GetChecked() and 1 or 0);
	end);
	self.SnapCheck:SetPoint("LEFT", self.GridCheck, "LEFT", 190, 0);

	self.GridSlider = CreateSlider(self, L.GRID_SPACING, 8, 128, 4, tostring, function(value)
		EDIT_MODE_GRID_SPACING = value;
		SetAccountSetting(GRID_SPACING_SETTING, value);
		UpdateGridShown();
	end);
	self.GridSlider:SetPoint("TOPLEFT", self.GridCheck, "BOTTOMLEFT", 6, -4);
	self.GridSlider:SetPoint("RIGHT", self, "RIGHT", -20, 0);

	-- фреймы: снятая галочка - фрейм не редактируется (накладки нет)
	self.FramesLabel = self.Content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	self.FramesLabel:SetPoint("TOPLEFT", self.GridSlider, "BOTTOMLEFT", -6, -10);
	self.FramesLabel:SetText(L.FRAMES);

	self.frameChecks = {};

	-- низ
	self.RevertButton = CreateButton(self, L.REVERT_ALL, 170, function()
		EditModeCore:RevertAll();
	end);
	self.RevertButton:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 16, 16);

	self.SaveButton = CreateButton(self, L.SAVE, 130, function()
		EditModeCore:Exit();
	end);
	self.SaveButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -16, 16);
end

function EditModeManagerMixin:InitLayoutDropdown(level)
	local info = C_EditMode.GetLayouts();

	for index, layout in ipairs(info.layouts) do
		local entry = UIDropDownMenu_CreateInfo();
		entry.text = layout.layoutName;
		entry.checked = (index == info.activeLayout);
		entry.func = function()
			EditModeCore:SetActiveLayout(index);
			self:Refresh();
		end;
		UIDropDownMenu_AddButton(entry, level);
	end

	local function AddAction(text, func, disabled)
		local entry = UIDropDownMenu_CreateInfo();
		entry.text = text;
		entry.notCheckable = true;
		entry.disabled = disabled;
		entry.func = func;
		UIDropDownMenu_AddButton(entry, level);
	end

	AddAction(L.NEW_LAYOUT, function()
		StaticPopup_Show("EDIT_MODE_NAME_LAYOUT", nil, nil, { mode = "new" });
	end);
	AddAction(L.COPY_LAYOUT, function()
		StaticPopup_Show("EDIT_MODE_NAME_LAYOUT", nil, nil, { mode = "copy" });
	end);
	AddAction(L.RENAME_LAYOUT, function()
		StaticPopup_Show("EDIT_MODE_NAME_LAYOUT", nil, nil, { mode = "rename" });
	end);
	AddAction(L.DELETE_LAYOUT, function()
		C_EditMode.DeleteLayout(C_EditMode.GetLayouts().activeLayout);
		EditModeCore:SetActiveLayout(C_EditMode.GetLayouts().activeLayout);
		self:Refresh();
	end, #info.layouts <= 1);
end

function EditModeManagerMixin:RefreshFrameList()
	local previous = self.FramesLabel;
	local column, row = 0, 0;

	for index, systemName in ipairs(EditModeCore.order) do
		local system = EditModeCore.systems[systemName];
		local check = self.frameChecks[index];
		if not check then
			check = CreateCheck(self, "", function(button)
				SetAccountSetting("hide:" .. button.systemName, (not button:GetChecked()) and 1 or 0);
				if not button:GetChecked() and EditModeCore.selected == button.systemName then
					EditModeCore:ClearSelection();
				end
				EditModeCore:UpdateOverlays();
			end);
			self.frameChecks[index] = check;
		end
		check.systemName = systemName;
		check.text:SetText(system.displayName);
		check.text:SetWidth(160);
		check.text:SetJustifyH("LEFT");

		check:ClearAllPoints();
		check:SetPoint("TOPLEFT", self.FramesLabel, "BOTTOMLEFT", column * 190, -4 - row * 24);
		column = column + 1;
		if column == 2 then
			column, row = 0, row + 1;
		end
	end

	local rows = math.ceil(#EditModeCore.order / 2);
	self:SetHeight(212 + rows * 24);
end

function EditModeManagerMixin:Refresh()
	local info = C_EditMode.GetLayouts();
	UIDropDownMenu_SetText(self.LayoutDropdown, info.layouts[info.activeLayout].layoutName);

	self.GridCheck:SetChecked((GetAccountSetting(Enum.EditModeAccountSetting.ShowGrid) or 1) ~= 0);
	self.SnapCheck:SetChecked((GetAccountSetting(Enum.EditModeAccountSetting.EnableSnap) or 1) ~= 0);
	self.GridSlider:SetValueSilently(EDIT_MODE_GRID_SPACING);

	self:RefreshFrameList();
	for _, check in ipairs(self.frameChecks) do
		check:SetChecked(IsSystemEditable(check.systemName));
	end
end

-- имя макета: новый / копия / переименование
StaticPopupDialogs["EDIT_MODE_NAME_LAYOUT"] = {
	text = L.NAME_LAYOUT,
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnShow = function(self, data)
		local editBox = _G[self:GetName() .. "EditBox"];
		local info = C_EditMode.GetLayouts();
		if data and data.mode == "rename" then
			editBox:SetText(info.layouts[info.activeLayout].layoutName);
		else
			editBox:SetText("");
		end
		editBox:SetFocus();
	end,
	OnAccept = function(self, data)
		local name = _G[self:GetName() .. "EditBox"]:GetText();
		if not C_EditMode.IsValidLayoutName(name) then
			return;
		end
		local info = C_EditMode.GetLayouts();
		if data.mode == "rename" then
			C_EditMode.RenameLayout(info.activeLayout, name);
		else
			C_EditMode.AddLayout(name, data.mode == "copy" and info.activeLayout or nil);
			EditModeCore:SetActiveLayout(C_EditMode.GetLayouts().activeLayout);
		end
		EditModeManagerFrame:Refresh();
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent();
		StaticPopupDialogs["EDIT_MODE_NAME_LAYOUT"].OnAccept(parent, parent.data);
		parent:Hide();
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

---------------------------------------------------------------------------
-- окно настроек выбранного фрейма
---------------------------------------------------------------------------
EditModeSystemSettingsDialogMixin = {};

function EditModeSystemSettingsDialogMixin:OnLoad()
	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", self.StartMoving);
	self:SetScript("OnDragStop", self.StopMovingOrSizing);

	self.Content = CreateContent(self);
	self.Title = self.Content:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge");
	self.Title:SetPoint("TOP", self, "TOP", 0, -15);

	self.controls = {};

	-- retail: the two buttons one under the other, the full width of the dialog
	self.RevertButton = CreateButton(self, L.REVERT_CHANGES, 1, function()
		EditModeCore:RevertSystem(self.system.name);
		self:Refresh();
	end);
	self.RevertButton:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 20, 16);
	self.RevertButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -20, 16);

	self.ResetPositionButton = CreateButton(self, L.RESET_POSITION, 1, function()
		EditModeCore:ResetSystem(self.system.name);
		self:Refresh();
	end);
	self.ResetPositionButton:SetPoint("BOTTOMLEFT", self.RevertButton, "TOPLEFT", 0, 4);
	self.ResetPositionButton:SetPoint("BOTTOMRIGHT", self.RevertButton, "TOPRIGHT", 0, 4);
end

function EditModeSystemSettingsDialogMixin:BuildControls(system)
	-- контролы создаются один раз на фрейм и дальше переиспользуются
	local controls = {};
	local anchor;
	for index, setting in ipairs(system.settings) do
		local control;
		if setting.type == "check" then
			control = CreateCheck(self, setting.label, function(button)
				EditModeCore:SetSettingValue(system.name, setting.key, button:GetChecked() and 1 or 0);
			end);
			control.Refresh = function()
				control:SetChecked(EditModeCore:GetSettingValue(system.name, setting) == 1);
			end
		else
			control = CreateSlider(self, setting.label, setting.min, setting.max, setting.step, setting.format or tostring, function(value)
				EditModeCore:SetSettingValue(system.name, setting.key, value);
			end);
			control:SetWidth(300);
			control.Refresh = function()
				control:SetValueSilently(EditModeCore:GetSettingValue(system.name, setting));
			end
		end

		if anchor then
			control:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6);
		else
			control:SetPoint("TOPLEFT", self, "TOPLEFT", 20, -44);
		end
		anchor = control;
		controls[index] = control;
	end
	return controls;
end

function EditModeSystemSettingsDialogMixin:AttachToSystem(system)
	if self.system and self.system.dialogControls then
		for _, control in ipairs(self.system.dialogControls) do
			control:Hide();
		end
	end

	self.system = system;
	self.Title:SetText(system.displayName);

	system.dialogControls = system.dialogControls or self:BuildControls(system);
	self.controls = system.dialogControls;
	for _, control in ipairs(self.controls) do
		control:Show();
	end

	self:SetHeight(44 + #system.settings * 38 + 82);
	self:Refresh();
	self:Show();
end

function EditModeSystemSettingsDialogMixin:Refresh()
	if not self.system then
		return;
	end
	for _, control in ipairs(self.controls) do
		if control.Refresh then
			control.Refresh();
		end
	end
end

---------------------------------------------------------------------------
-- запуск
---------------------------------------------------------------------------
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_LOGIN");
loader:RegisterEvent("PLAYER_REGEN_DISABLED");
loader:RegisterEvent("UI_SCALE_CHANGED");
loader:RegisterEvent("DISPLAY_SIZE_CHANGED");
loader:RegisterEvent("PLAYER_REGEN_ENABLED");
loader:SetScript("OnEvent", function(self, event)
	-- another UI scale / resolution: the screen's size in UI units changed, place the frames again
	-- (not in combat: some of them are protected; done when it ends)
	if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
		if not self.loaded then
			return;
		end
		if InCombatLockdown() then
			self.pending = true;
		elseif event ~= "PLAYER_REGEN_ENABLED" or self.pending then
			self.pending = nil;
			EditModeCore:ApplyLayout();
		end
		return;
	end
	if event == "PLAYER_REGEN_DISABLED" then
		-- как в ретейле: в бою режим закрывается
		EditModeCore:Exit();
		return;
	end

	EDIT_MODE_GRID_SPACING = GetAccountSetting(GRID_SPACING_SETTING) or EDIT_MODE_GRID_SPACING;

	-- системы по умолчанию: добавляйте свои через EditModeCore:RegisterSystem
	local defaults = {
		{ "PlayerFrame", PlayerFrame, HUD_EDIT_MODE_PLAYER_FRAME_LABEL },
		{ "TargetFrame", TargetFrame, HUD_EDIT_MODE_TARGET_FRAME_LABEL },
		{ "FocusFrame", FocusFrame, HUD_EDIT_MODE_FOCUS_FRAME_LABEL },
		{ "PartyMemberFrame1", PartyMemberFrame1, HUD_EDIT_MODE_PARTY_FRAMES_LABEL },
		{ "CompactRaidFrameContainer", CompactRaidFrameContainer, HUD_EDIT_MODE_RAID_FRAMES_LABEL },
		{ "MinimapCluster", MinimapCluster, HUD_EDIT_MODE_MINIMAP_LABEL },
		{ "ObjectiveTrackerFrame", ObjectiveTrackerFrame, HUD_EDIT_MODE_OBJECTIVE_TRACKER_LABEL },
		{ "CastingBarFrame", CastingBarFrame, HUD_EDIT_MODE_CAST_BAR_LABEL },
		-- retail: the queue eye is part of the micro menu - its size is a setting of the menu, not a system
		{ "MicroMenuFrame", MicroMenuFrame, HUD_EDIT_MODE_MICRO_MENU_LABEL, {
			{
				key = "eyeSize", type = "slider", label = L.EYE_SIZE, min = 0.5, max = 1.5, step = 0.05, default = 1,
				format = function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)); end,
				apply = function(frame, value)
					if QueueStatusButton then
						QueueStatusButton:SetScale(value);
					end
				end,
			},
		} },
		{ "BackpackFrame", BackpackFrame, HUD_EDIT_MODE_BAGS_LABEL },
		{ "ChatFrame1", ChatFrame1, HUD_EDIT_MODE_CHAT_FRAME_LABEL },
		{ "LossOfControlFrame", LossOfControlFrame, HUD_EDIT_MODE_LOSS_OF_CONTROL_LABEL },
	};

	for _, entry in ipairs(defaults) do
		EditModeCore:RegisterSystem(entry[1], entry[2], entry[3], entry[4]);
	end

	EditModeCore:ApplyLayout();
	self.loaded = true;
end);

SLASH_EDITMODE1 = "/editmode";
SLASH_EDITMODE2 = "/em";
SlashCmdList.EDITMODE = function()
	EditModeCore:Toggle();
end
