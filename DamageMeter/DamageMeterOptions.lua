-- Настройки счётчика: раздел в настройках интерфейса, значения в CVar'ах,
-- по одному на настройку (как у личного нейм-плейта).

DamageMeterSliders = {
	{ cvar = "damageMeterBarHeight", default = 20, min = 12, max = 40, step = 1, label = "Высота полоски" },
	{ cvar = "damageMeterBarSpacing", default = 2, min = 0, max = 10, step = 1, label = "Интервал между полосками" },
	{ cvar = "damageMeterTextSize", default = 100, min = 60, max = 140, step = 5, label = "Размер текста" },
	{ cvar = "damageMeterTransparency", default = 100, min = 20, max = 100, step = 5, label = "Непрозрачность фона" },
};

DamageMeterToggles = {
	{ cvar = "damageMeterClassColors", default = "1", label = "Цвета классов" },
	{ cvar = "damageMeterShowIcons", default = "1", label = "Показывать иконки" },
	{ cvar = "damageMeterGroupOnly", default = "1", label = "Только своя группа и рейд" },
	{ cvar = "damageMeterAutoReset", default = "1", label = AUTO_RESET_DAMAGE_METER },
};

DamageMeterVisibilityModes = {
	{ value = "always", label = "Всегда" },
	{ value = "combat", label = "Только в бою" },
	{ value = "group", label = "Только в группе и рейде" },
	{ value = "hidden", label = "Никогда" },
};

function DamageMeterOptionsPanel_OnLoad(self)
	self.name = DAMAGE_METER_LABEL;

	self.okay = function() end;
	self.cancel = function() DamageMeterOptionsPanel_Refresh(self); end;
	self.default = function()
		for _, info in ipairs(DamageMeterSliders) do
			SetCVar(info.cvar, tostring(info.default));
		end
		for _, info in ipairs(DamageMeterToggles) do
			SetCVar(info.cvar, info.default);
		end
		SetCVar("damageMeterVisibility", "always");
		DamageMeterSessionWindow:ApplyOptions();
		DamageMeterOptionsPanel_Refresh(self);
	end;
	self.refresh = function() DamageMeterOptionsPanel_Refresh(self); end;

	InterfaceOptions_AddCategory(self);
end

function DamageMeterOptionsPanel_OnShow(self)
	DamageMeterOptionsPanel_Build(self);
	DamageMeterOptionsPanel_Refresh(self);
end

function DamageMeterOptionsPanel_Build(self)
	if self.built then
		return;
	end
	self.built = true;

	local name = self:GetName();

	-- режим показа
	local dropDown = CreateFrame("Frame", name.."Visibility", self, "UIDropDownMenuTemplate");
	dropDown:SetPoint("TOPLEFT", 4, -60);
	UIDropDownMenu_SetWidth(dropDown, 220);
	UIDropDownMenu_Initialize(dropDown, function()
		for _, mode in ipairs(DamageMeterVisibilityModes) do
			local info = UIDropDownMenu_CreateInfo();
			info.text = mode.label;
			info.value = mode.value;
			info.checked = GetCVar("damageMeterVisibility") == mode.value;
			info.func = function(button)
				SetCVar("damageMeterVisibility", button.value);
				UIDropDownMenu_SetText(dropDown, button:GetText());
				DamageMeterSessionWindow:UpdateVisibility();
			end;
			UIDropDownMenu_AddButton(info);
		end
	end);
	self.Visibility = dropDown;

	local label = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
	label:SetPoint("BOTTOMLEFT", dropDown, "TOPLEFT", 16, 2);
	label:SetText("Когда показывать");

	-- галочки
	local anchor = dropDown;
	self.toggles = {};
	for index, info in ipairs(DamageMeterToggles) do
		local check = CreateFrame("CheckButton", name.."Toggle"..index, self, "InterfaceOptionsCheckButtonTemplate");
		check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", index == 1 and 12 or 0, -8);
		_G[check:GetName().."Text"]:SetText(info.label);
		check.info = info;
		check:SetScript("OnClick", function(button)
			SetCVar(button.info.cvar, button:GetChecked() and "1" or "0");
			DamageMeterSessionWindow:ApplyOptions();
		end);
		self.toggles[index] = check;
		anchor = check;
	end

	-- ползунки
	self.sliders = {};
	for index, info in ipairs(DamageMeterSliders) do
		local slider = CreateFrame("Slider", name.."Slider"..index, self, "OptionsSliderTemplate");
		slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", index == 1 and 4 or 0, -32);
		slider:SetMinMaxValues(info.min, info.max);
		slider:SetValueStep(info.step);
		slider:SetWidth(220);
		slider.info = info;

		_G[slider:GetName().."Low"]:SetText(info.min);
		_G[slider:GetName().."High"]:SetText(info.max);

		slider:SetScript("OnValueChanged", function(bar, value)
			value = math.floor(value / info.step + 0.5) * info.step;
			SetCVar(info.cvar, tostring(value));
			_G[bar:GetName().."Text"]:SetText(info.label..": "..value);
			DamageMeterSessionWindow:ApplyOptions();
		end);

		self.sliders[index] = slider;
		anchor = slider;
	end
end

function DamageMeterOptionsPanel_Refresh(self)
	if not self.built then
		return;
	end

	local mode = GetCVar("damageMeterVisibility") or "always";
	for _, entry in ipairs(DamageMeterVisibilityModes) do
		if entry.value == mode then
			UIDropDownMenu_SetText(self.Visibility, entry.label);
		end
	end

	for _, check in ipairs(self.toggles) do
		check:SetChecked((GetCVar(check.info.cvar) or check.info.default) ~= "0");
	end

	for _, slider in ipairs(self.sliders) do
		local value = tonumber(GetCVar(slider.info.cvar)) or slider.info.default;
		slider:SetValue(value);
		_G[slider:GetName().."Text"]:SetText(slider.info.label..": "..value);
	end
end
