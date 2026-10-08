-- DropdownButton: кнопка, открывающая меню. В ретейле это intrinsic-тип,
-- здесь обычная кнопка с тем же API (SetupMenu, GenerateMenu, IsMenuOpen).

DropdownButtonMixin = CreateFromMixins(ButtonStateBehaviorMixin);

function DropdownButtonMixin:OnLoad()
	ButtonStateBehaviorMixin.OnLoad(self);
end

function DropdownButtonMixin:SetupMenu(generator)
	self.menuGenerator = generator;

	if self:IsShown() then
		self:GenerateMenu();
	end
end

function DropdownButtonMixin:GenerateMenu()
	if not self.menuGenerator then
		return;
	end

	local rootDescription = MenuUtil.CreateRootMenuDescription();
	-- меню не уже кнопки: +10, чтобы край фона не упирался в край кнопки
	rootDescription:SetMinimumWidth(self:GetWidth() + 10);
	Menu.PopulateDescription(self.menuGenerator, self, rootDescription);

	self.menuDescription = rootDescription;
	self:UpdateToMenuSelections(rootDescription);
end

function DropdownButtonMixin:GetMenuDescription()
	return self.menuDescription;
end

function DropdownButtonMixin:HasElements()
	return self.menuDescription and self.menuDescription:HasElements() or false;
end

function DropdownButtonMixin:IsMenuOpen()
	return self.menuOpen == true;
end

function DropdownButtonMixin:SetMenuAnchor(anchor)
	self.menuAnchor = anchor;
end

function DropdownButtonMixin:OpenMenu()
	if not self:IsEnabled() then
		return;
	end

	-- меню всегда пересобирается: иначе в нём остаются устаревшие отметки
	self:GenerateMenu();

	if not self.menuDescription then
		return;
	end

	local menu = Menu.GetManager():OpenMenu(self, self.menuDescription, self.menuAnchor);
	self.menuOpen = menu ~= nil;

	if menu then
		menu.closedCallback = function(_, reason)
			self.menuOpen = false;
			self:OnMenuClosed(menu, reason);
		end;
		self:OnMenuOpened(menu);
	end

	self:OnButtonStateChanged();
end

function DropdownButtonMixin:CloseMenu()
	Menu.GetManager():CloseMenus();
	self.menuOpen = false;
	self:OnButtonStateChanged();
end

function DropdownButtonMixin:SetMenuOpen(open)
	if open then
		self:OpenMenu();
	else
		self:CloseMenu();
	end
end

function DropdownButtonMixin:OnClick()
	self:SetMenuOpen(not self:IsMenuOpen());
end

function DropdownButtonMixin:OnMenuOpened(menu)
end

function DropdownButtonMixin:OnMenuClosed(menu, reason)
end

function DropdownButtonMixin:SignalUpdate()
	self:UpdateToMenuSelections(self:GetMenuDescription());
end

function DropdownButtonMixin:UpdateToMenuSelections(menuDescription)
	-- переопределяется наследниками, которым нужно показывать выбранное
end

---------------------------------------------------------------------------
-- WowStyle1ArrowDropdown: одна стрелка, без текста
---------------------------------------------------------------------------
WowStyle1ArrowDropdownMixin = CreateFromMixins(DropdownButtonMixin);

function WowStyle1ArrowDropdownMixin:OnButtonStateChanged()
	self.Arrow:SetAtlas(GetWowStyle1ArrowButtonState(self), false);
end

---------------------------------------------------------------------------
-- WowStyle1Dropdown: кнопка с текстом и стрелкой (ретейловый вид)
---------------------------------------------------------------------------
function GetWowStyle1ArrowButtonState(button)
	if button:IsEnabled() then
		if button:IsDownOver() then
			return "common-dropdown-a-button-pressedhover";
		elseif button:IsOver() then
			return "common-dropdown-a-button-hover";
		elseif button:IsDown() then
			return "common-dropdown-a-button-pressed";
		elseif button:IsMenuOpen() then
			return "common-dropdown-a-button-open";
		end
		return "common-dropdown-a-button";
	end
	return "common-dropdown-a-button-disabled";
end

function GetWowStyle1ArrowButtonShadowlessState(button)
	local atlas = GetWowStyle1ArrowButtonState(button);
	return atlas.."-shadowless";
end

WowStyle1DropdownMixin = CreateFromMixins(DropdownButtonMixin);

-- common-dropdown-textholder is a 3-slice atlas in retail (slice: 16 left, 19 right, 54x41).
-- 3.3.5 has no texture slicing: build it from three textures so the edges are not stretched.
local TEXTHOLDER_LEFT, TEXTHOLDER_RIGHT = 16, 19;

function WowStyle1Dropdown_SetupTextHolder(self)
	local info = C_Texture.GetAtlasInfo("common-dropdown-textholder");
	local background = self.Background;
	if not (info and background) then
		return;
	end

	local atlasWidth = info.width or 54;
	local uPerPixel = (info.right - info.left) / atlasWidth;
	local uLeft = info.left + TEXTHOLDER_LEFT * uPerPixel;
	local uRight = info.right - TEXTHOLDER_RIGHT * uPerPixel;

	background:SetTexture(info.file);
	background:SetTexCoord(uLeft, uRight, info.top, info.bottom);
	background:ClearAllPoints();
	background:SetPoint("TOPLEFT", self, "TOPLEFT", -8 + TEXTHOLDER_LEFT, 7);
	background:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 8 - TEXTHOLDER_RIGHT, -9);

	local left = self.BackgroundLeft or self:CreateTexture(nil, "BACKGROUND");
	left:SetTexture(info.file);
	left:SetTexCoord(info.left, uLeft, info.top, info.bottom);
	left:SetWidth(TEXTHOLDER_LEFT);
	left:ClearAllPoints();
	left:SetPoint("TOPRIGHT", background, "TOPLEFT");
	left:SetPoint("BOTTOMRIGHT", background, "BOTTOMLEFT");
	self.BackgroundLeft = left;

	local right = self.BackgroundRight or self:CreateTexture(nil, "BACKGROUND");
	right:SetTexture(info.file);
	right:SetTexCoord(uRight, info.right, info.top, info.bottom);
	right:SetWidth(TEXTHOLDER_RIGHT);
	right:ClearAllPoints();
	right:SetPoint("TOPLEFT", background, "TOPRIGHT");
	right:SetPoint("BOTTOMLEFT", background, "BOTTOMRIGHT");
	self.BackgroundRight = right;
end

function WowStyle1DropdownMixin:OnLoad()
	DropdownButtonMixin.OnLoad(self);

	-- как в ретейле: фон - "поле для текста" common-dropdown-textholder, справа кнопка-стрелка.
	-- Атласы ставим кодом (атлас из XML-атрибута в 3.3.5 может лечь без координат).
	WowStyle1Dropdown_SetupTextHolder(self);
	self:OnButtonStateChanged();

	self:SetDefaultText(self.defaultText or "");
end

function WowStyle1DropdownMixin:OnButtonStateChanged()
	-- размер стрелки задан в шаблоне, атлас его не переопределяет
	self.Arrow:SetAtlas(self:GetArrowAtlas(), false);
end

function WowStyle1DropdownMixin:GetArrowAtlas()
	return GetWowStyle1ArrowButtonState(self);
end

function WowStyle1DropdownMixin:SetDefaultText(text)
	self.defaultText = text;
	if not self.selectionText then
		self.Text:SetText(text);
	end
end

function WowStyle1DropdownMixin:SetText(text)
	self.selectionText = text;
	self.Text:SetText(text or self.defaultText or "");
end

function WowStyle1DropdownMixin:GetText()
	return self.Text:GetText();
end

-- показываем выбранный вариант в самой кнопке, как в ретейле
function WowStyle1DropdownMixin:UpdateToMenuSelections(menuDescription)
	if not menuDescription then
		return;
	end

	local selections = MenuUtil.GetSelections(menuDescription);
	if #selections == 1 then
		self:SetText(MenuUtil.GetElementText(selections[1]));
	elseif #selections > 1 then
		self:SetText(format("%s (%d)", self.defaultText or "", #selections));
	else
		self:SetText(nil);
	end
end


---------------------------------------------------------------------------
-- WowStyle1FilterDropdownTemplate: кнопка "Фильтр" ретейла (коллекции, игрушки, гардероб...).
-- Фон common-dropdown-b-button (+ hover/pressed), текст "Фильтр" со стрелкой вправо,
-- красный крестик "сбросить" в правом верхнем углу, пока фильтры не по умолчанию.
--   SetIsDefaultCallback(func) -> true, если фильтры по умолчанию (крестик скрыт)
--   SetDefaultCallback(func)   -> сброс фильтров по крестику
--   SetUpdateCallback(func)    -> вызывается после любого изменения фильтров
---------------------------------------------------------------------------
WowStyle1FilterDropdownMixin = CreateFromMixins(DropdownButtonMixin);

function WowStyle1FilterDropdownMixin:OnLoad()
	DropdownButtonMixin.OnLoad(self);

	-- стрелка вправо уже нарисована в самом фоне common-dropdown-b-button - отдельной иконки нет
	self.Text:SetText(self.text or FILTER or "Фильтр");
	if self.ResetButton then
		if self.ResetButton.Texture and C_Texture.GetAtlasInfo("common-icon-redx") then
			self.ResetButton.Texture:SetAtlas("common-icon-redx");
		end
		self.ResetButton:SetScript("OnClick", function()
			if self.defaultCallback then
				self.defaultCallback();
			end
			self:ValidateResetState();
			if self.updateCallback then
				self.updateCallback();
			end
			PlaySound("igMainMenuOptionCheckBoxOn");
		end);
	end

	self:OnButtonStateChanged();
end

function WowStyle1FilterDropdownMixin:OnShow()
	DropdownButtonMixin.OnShow(self);
	self:ValidateResetState();
end

function WowStyle1FilterDropdownMixin:OnButtonStateChanged()
	local atlas = "common-dropdown-b-button";
	if self:IsEnabled() then
		if self:IsDown() or self:IsMenuOpen() then
			atlas = "common-dropdown-b-button-pressed";
		elseif self:IsOver() then
			atlas = "common-dropdown-b-button-hover";
		end
	end
	if C_Texture.GetAtlasInfo(atlas) then
		self.Background:SetAtlas(atlas);
	end

	-- при нажатии текст чуть сдвигается, как у ретейловой кнопки
	local offset = (self:IsEnabled() and self:IsDown()) and -1 or 0;
	self.Text:ClearAllPoints();
	self.Text:SetPoint("CENTER", self, "CENTER", -6 - offset, offset);

	if self:IsEnabled() then
		self.Text:SetFontObject(self.baseFontObject or GameFontNormal);
	else
		self.Text:SetFontObject(self.disableFontObject or GameFontDisable);
	end
end

function WowStyle1FilterDropdownMixin:SetIsDefaultCallback(callback)
	self.isDefaultCallback = callback;
	self:ValidateResetState();
end

function WowStyle1FilterDropdownMixin:SetDefaultCallback(callback)
	self.defaultCallback = callback;
end

function WowStyle1FilterDropdownMixin:SetUpdateCallback(callback)
	self.updateCallback = callback;
end

function WowStyle1FilterDropdownMixin:ValidateResetState()
	if self.ResetButton then
		local isDefault = not self.isDefaultCallback or self.isDefaultCallback();
		self.ResetButton:SetShown(not isDefault);
	end
end

-- любое изменение в меню: обновить крестик и сообщить владельцу
function WowStyle1FilterDropdownMixin:SignalUpdate()
	DropdownButtonMixin.SignalUpdate(self);
	self:ValidateResetState();
	if self.updateCallback then
		self.updateCallback();
	end
end

-- текст у кнопки фильтра всегда "Фильтр", выбранные пункты в нём не показываются
function WowStyle1FilterDropdownMixin:UpdateToMenuSelections()
end
