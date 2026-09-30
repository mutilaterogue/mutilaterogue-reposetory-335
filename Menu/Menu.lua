-- Менеджер меню: одно открытое меню за раз.
Menu = Menu or {};
MenuUtil = MenuUtil or {};

local ELEMENT_HEIGHT = 20;
local DIVIDER_HEIGHT = 13;
-- запас вокруг пунктов: фон меню (common-dropdown-bg) рисуется с выносом, и при
-- маленьком запасе галочки и текст вылезали за край
local MENU_PADDING_X = 24;
local MENU_PADDING_Y = 14;
local MIN_MENU_WIDTH = 100;

---------------------------------------------------------------------------
-- менеджер меню: одно открытое меню за раз
---------------------------------------------------------------------------
local manager = {};
local menuFrame;
local submenuFrame;

local function ReleaseButtons(frame)
	for _, button in ipairs(frame.buttons) do
		button:Hide();
	end
	frame.usedButtons = 0;
end

local function AcquireButton(frame)
	frame.usedButtons = frame.usedButtons + 1;

	local button = frame.buttons[frame.usedButtons];
	if not button then
		button = CreateFrame("Button", nil, frame, "MenuElementTemplate");
		frame.buttons[frame.usedButtons] = button;
	end

	button:Show();
	return button;
end

local function InitButton(button, description, menu)
	button.description = description;

	local elementType = description:GetElementType();
	button.Text:SetText(description.text or "");
	button.Text:SetTextColor(1, 1, 1);
	button.Highlight:Hide();
	button.Divider:Hide();
	button.Tick:Hide();
	button.Check:Hide();
	button.Arrow:Hide();
	button:SetHeight(ELEMENT_HEIGHT);
	button:Enable();

	if elementType == "divider" then
		button.Divider:Show();
		button:SetHeight(DIVIDER_HEIGHT);
		button:Disable();
	elseif elementType == "spacer" then
		button:SetHeight(description.extent);
		button:Disable();
	elseif elementType == "title" then
		local color = description.color or NORMAL_FONT_COLOR;
		button.Text:SetTextColor(color.r, color.g, color.b);
		button:Disable();
	elseif elementType == "submenu" then
		button.Arrow:Show();
	elseif elementType == "checkbox" or elementType == "radio" then
		local isRadio = elementType == "radio";
		button.Tick:SetAtlas(isRadio and "common-dropdown-tickradial" or "common-dropdown-ticksquare", true);
		button.Tick:Show();

		if description:IsSelected() then
			button.Check:SetAtlas(isRadio and "common-dropdown-icon-radialtick-yellow" or "common-dropdown-icon-checkmark-yellow", true);
			button.Check:Show();
		end
	end

	-- отступ слева под галочку или переключатель
	local hasTick = elementType == "checkbox" or elementType == "radio";
	button.Text:ClearAllPoints();
	button.Text:SetPoint("LEFT", hasTick and 24 or 6, 0);
	button.Text:SetPoint("RIGHT", -6, 0);

	if description.initializer then
		description.initializer(button, description, menu);
	end
end

local function GetMenuWidth(description, minimumWidth)
	local width = minimumWidth or MIN_MENU_WIDTH;

	menuFrame.measure:SetText("");
	for _, child in description:EnumerateElementDescriptions() do
		if child.text then
			menuFrame.measure:SetText(child.text);
			local textWidth = menuFrame.measure:GetStringWidth() + 46 + MENU_PADDING_X;
			width = math.max(width, textWidth);
		end
	end

	return width;
end

function Menu.GetManager()
	return manager;
end

function manager:CloseMenus(reason)
	Menu.CloseSubmenu();

	if menuFrame then
		menuFrame:Hide();

		if menuFrame.closedCallback then
			local callback = menuFrame.closedCallback;
			menuFrame.closedCallback = nil;
			callback(menuFrame, reason or MenuCloseReason.Unspecified);
		end

		menuFrame.owner = nil;
	end
end

-- вложенное меню строится тем же кодом, но в своём фрейме
local function BuildMenu(frame, description)
	ReleaseButtons(frame);

	local width = GetMenuWidth(description, description:GetMinimumWidth());
	local offset = MENU_PADDING_Y;

	for _, child in description:EnumerateElementDescriptions() do
		local button = AcquireButton(frame);
		InitButton(button, child, frame);
		button:SetWidth(width - MENU_PADDING_X);
		button:ClearAllPoints();
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", MENU_PADDING_X / 2, -offset);
		offset = offset + button:GetHeight();
	end

	frame:SetSize(width, offset + MENU_PADDING_Y);
end

function Menu.CloseSubmenu()
	if submenuFrame then
		submenuFrame:Hide();
		submenuFrame.description = nil;
	end
end

function Menu.OpenSubmenu(button, description)
	if not submenuFrame then
		submenuFrame = CreateFrame("Frame", "MenuSubmenuFrame", UIParent, "MenuTemplate");
		submenuFrame.buttons = {};
		submenuFrame.usedButtons = 0;
		submenuFrame.measure = submenuFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		submenuFrame.measure:Hide();
		-- подменю всегда поверх основного, иначе оно затемнено и не ловит клики
		submenuFrame:SetFrameStrata("TOOLTIP");
		Menu.ApplyBackgroundLayout(submenuFrame);
	end

	if submenuFrame:IsShown() and submenuFrame.description == description then
		return;
	end

	submenuFrame.description = description;
	submenuFrame:SetFrameLevel((menuFrame and menuFrame:GetFrameLevel() or 100) + 10);
	BuildMenu(submenuFrame, description);

	submenuFrame:ClearAllPoints();
	submenuFrame:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, 6);
	submenuFrame:Show();
end

local function OpenMenuInternal(owner, description, anchorFunc)
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "MenuFrame", UIParent, "MenuTemplate");
		Menu.ApplyBackgroundLayout(menuFrame);
		menuFrame.buttons = {};
		menuFrame.usedButtons = 0;
		menuFrame.measure = menuFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		menuFrame.measure:Hide();
	end

	-- повторный клик по той же кнопке закрывает меню
	if menuFrame:IsShown() and menuFrame.owner == owner then
		manager:CloseMenus();
		return nil;
	end

	manager:CloseMenus();

	menuFrame.owner = owner;
	menuFrame.description = description;

	BuildMenu(menuFrame, description);
	anchorFunc(menuFrame);
	menuFrame:Show();

	return menuFrame;
end

function manager:OpenMenu(owner, description, anchor)
	return OpenMenuInternal(owner, description, function(frame)
		frame:ClearAllPoints();
		if anchor then
			frame:SetPoint(anchor.point, owner, anchor.relativePoint, anchor.x or 0, anchor.y or 0);
		else
			frame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2);
		end
	end);
end

function manager:OpenContextMenu(owner, description)
	return OpenMenuInternal(owner, description, function(frame)
		local x, y = GetCursorPosition();
		local scale = frame:GetEffectiveScale();
		frame:ClearAllPoints();
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale);
	end);
end

function MenuUtil.CreateContextMenu(owner, generator, ...)
	local description = MenuUtil.CreateRootMenuDescription();
	Menu.PopulateDescription(generator, owner or UIParent, description, ...);
	return manager:OpenContextMenu(owner or UIParent, description);
end

---------------------------------------------------------------------------
-- обработка кликов по элементам
---------------------------------------------------------------------------
function MenuElement_OnClick(self)
	local description = self.description;
	if not description then
		return;
	end

	local response = MenuResponse.Close;
	local elementType = description:GetElementType();

	if elementType == "submenu" then
		Menu.OpenSubmenu(self, description);
		return;
	end

	if elementType == "checkbox" or elementType == "radio" then
		description:SetSelected(not description:IsSelected());
		response = elementType == "radio" and MenuResponse.Close or MenuResponse.Refresh;
		PlaySound(description:IsSelected() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff");
	elseif elementType == "button" then
		if description.callback then
			local result = description.callback(description.data);
			if result then
				response = result;
			end
		end
		PlaySound("igMainMenuOptionCheckBoxOn");
	else
		return;
	end

	local owner = menuFrame.owner;

	if response == MenuResponse.Refresh then
		-- перерисовать и основное меню, и подменю, в котором был клик
		-- (раньше обновлялось только основное: галочки в подменю "Источники" не менялись)
		local frames = { menuFrame };
		local clickedFrame = self:GetParent();
		if clickedFrame and clickedFrame ~= menuFrame and clickedFrame.buttons then
			table.insert(frames, clickedFrame);
		end
		for _, frame in ipairs(frames) do
			for _, button in ipairs(frame.buttons) do
				if button:IsShown() and button.description then
					InitButton(button, button.description, frame);
				end
			end
		end
	elseif response ~= MenuResponse.Open then
		Menu.GetManager():CloseMenus();
	end

	if owner and owner.SignalUpdate then
		owner:SignalUpdate();
	end
end

function MenuElement_OnEnter(self)
	if self:IsEnabled() then
		self.Highlight:Show();
	end

	-- подменю раскрывается по наведению, как в ретейле
	if self.description and self.description:HasSubmenu() then
		Menu.OpenSubmenu(self, self.description);
	elseif self:GetParent() == MenuFrame then
		Menu.CloseSubmenu();
	end

	local description = self.description;
	if description and description.tooltipInitializer then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		description.tooltipInitializer(GameTooltip, description);
		GameTooltip:Show();
	end
end

function MenuElement_OnLeave(self)
	self.Highlight:Hide();
	GameTooltip:Hide();
end

-- клик мимо меню закрывает его
local closer = CreateFrame("Frame");
closer:SetScript("OnUpdate", function()
	if not menuFrame or not menuFrame:IsShown() then
		return;
	end

	-- owner hidden (frame closed, tab switched): the menu goes with it
	local owner = menuFrame.owner;
	if owner and owner ~= UIParent and owner.IsVisible and not owner:IsVisible() then
		Menu.GetManager():CloseMenus();
		return;
	end

	local overSubmenu = submenuFrame and submenuFrame:IsShown() and submenuFrame:IsMouseOver();

	if IsMouseButtonDown("LeftButton") and not menuFrame:IsMouseOver() and not overSubmenu
		and not (menuFrame.owner and menuFrame.owner.IsMouseOver and menuFrame.owner:IsMouseOver()) then
		Menu.GetManager():CloseMenus();
	end
end);
