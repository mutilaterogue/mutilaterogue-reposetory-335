-- Панель настроек личного нейм-плейта (раздел "Боевой интерфейс" -> "Личный индикатор").
-- Все значения живут в CVar'ах, по одному на настройку: так они сохраняются сами
-- и их видно из любого места, без разбора строк.

-- CVar -> поле в ClassNameplateBarSetupOptions
ClassNameplateBarCVars = {
	{ cvar = "nameplateSelfWidth", key = "width", default = 120, min = 80, max = 250, step = 5, label = "Ширина" },
	{ cvar = "nameplateSelfHealthHeight", key = "healthBarHeight", default = 12, min = 4, max = 30, step = 1, label = "Высота полоски здоровья" },
	{ cvar = "nameplateSelfPowerHeight", key = "powerBarHeight", default = 5, min = 2, max = 20, step = 1, label = "Высота полоски ресурса" },
	{ cvar = "nameplateSelfOffset", key = "heightOffset", default = -1.5, min = -4, max = 4, step = 0.1, label = "Смещение по высоте" },
	{ cvar = "nameplateSelfResourceScale", key = "classResourceScale", default = 0.8, min = 0.4, max = 1.5, step = 0.05, label = "Масштаб классового ресурса" },
};

ClassNameplateBarToggles = {
	{ cvar = "nameplateSelfShowName", key = "showName", default = "0", label = "Показывать имя" },
};

-- режимы текста здоровья
ClassNameplateBarHealthText = {
	{ value = "none", label = "Не показывать" },
	{ value = "percent", label = "Проценты" },
	{ value = "value", label = "Числа" },
	{ value = "both", label = "Проценты слева, числа справа" },
};

-- режимы показа
ClassNameplateBarVisibility = {
	{ value = "always", label = "Всегда" },
	{ value = "combat", label = "Только в бою" },
	{ value = "instance", label = "Только в подземельях и рейдах" },
	{ value = "raid", label = "Только в рейдах" },
	{ value = "arena", label = "Только на аренах" },
	{ value = "pvp", label = "Только на полях боя и аренах" },
	{ value = "never", label = "Никогда" },
};

local function GetNumberCVar(cvar, default)
	local value = tonumber(GetCVar(cvar));
	if value == nil then
		return default;
	end
	return value;
end

-- перечитать все CVar'ы в ClassNameplateBarSetupOptions и применить
function ClassNameplateBar_LoadOptions()
	for _, info in ipairs(ClassNameplateBarCVars) do
		ClassNameplateBarSetupOptions[info.key] = GetNumberCVar(info.cvar, info.default);
	end

	for _, info in ipairs(ClassNameplateBarToggles) do
		ClassNameplateBarSetupOptions[info.key] = (GetCVar(info.cvar) or info.default) ~= "0";
	end

	ClassNameplateBarSetupOptions.visibility = GetCVar("nameplateSelfVisibility") or "always";
	ClassNameplateBarSetupOptions.healthTextMode = GetCVar("nameplateSelfHealthText") or "none";

	if ClassNameplateBarFrame then
		ClassNameplateBarFrame:ApplyOptions();
		ClassNameplateBarFrame:UpdateVisibility();
	end
end

---------------------------------------------------------------------------
-- панель
---------------------------------------------------------------------------
function ClassNameplateBarOptionsPanel_OnLoad(self)
	self.name = "Личный индикатор";
	-- без parent: раздел верхнего уровня, иначе он прячется под несуществующую категорию

	self.okay = function() end;
	self.cancel = function()
		ClassNameplateBar_LoadOptions();
		ClassNameplateBarOptionsPanel_Refresh(self);
	end;
	self.default = function()
		SetCVar("nameplateShowSelf", "1");
		SetCVar("nameplateSelfVisibility", "always");
		SetCVar("nameplateSelfHealthText", "none");
		for _, info in ipairs(ClassNameplateBarCVars) do
			SetCVar(info.cvar, tostring(info.default));
		end
		for _, info in ipairs(ClassNameplateBarToggles) do
			SetCVar(info.cvar, info.default);
		end
		ClassNameplateBar_LoadOptions();
		ClassNameplateBarOptionsPanel_Refresh(self);
	end;
	self.refresh = function()
		ClassNameplateBarOptionsPanel_Refresh(self);
	end;

	InterfaceOptions_AddCategory(self);
end

function ClassNameplateBarOptionsPanel_OnShow(self)
	ClassNameplateBarOptionsPanel_Build(self);
	ClassNameplateBarOptionsPanel_Refresh(self);
end

-- элементы создаются на месте: так их список задаётся одними таблицами выше
function ClassNameplateBarOptionsPanel_Build(self)
	if self.built then
		return;
	end
	self.built = true;

	local name = self:GetName();

	-- главная галочка
	local enable = CreateFrame("CheckButton", name.."Enable", self, "InterfaceOptionsCheckButtonTemplate");
	enable:SetPoint("TOPLEFT", 16, -60);
	_G[enable:GetName().."Text"]:SetText("Показывать личный индикатор");
	enable:SetScript("OnClick", function(button)
		SetCVar("nameplateShowSelf", button:GetChecked() and "1" or "0");
		ClassNameplateBarFrame:UpdateVisibility();
	end);
	self.Enable = enable;

	-- режим показа
	local dropDown = CreateFrame("Frame", name.."Visibility", self, "UIDropDownMenuTemplate");
	dropDown:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", -12, -24);
	UIDropDownMenu_SetWidth(dropDown, 220);
	UIDropDownMenu_Initialize(dropDown, function()
		for _, mode in ipairs(ClassNameplateBarVisibility) do
			local info = UIDropDownMenu_CreateInfo();
			info.text = mode.label;
			info.value = mode.value;
			info.checked = ClassNameplateBarSetupOptions.visibility == mode.value;
			info.func = function(button)
				SetCVar("nameplateSelfVisibility", button.value);
				ClassNameplateBarSetupOptions.visibility = button.value;
				UIDropDownMenu_SetText(dropDown, button:GetText());
				ClassNameplateBarFrame:UpdateVisibility();
			end;
			UIDropDownMenu_AddButton(info);
		end
	end);
	self.Visibility = dropDown;

	local label = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
	label:SetPoint("BOTTOMLEFT", dropDown, "TOPLEFT", 16, 2);
	label:SetText("Когда показывать");

	-- текст здоровья
	local healthText = CreateFrame("Frame", name.."HealthText", self, "UIDropDownMenuTemplate");
	healthText:SetPoint("TOPLEFT", dropDown, "BOTTOMLEFT", 0, -24);
	UIDropDownMenu_SetWidth(healthText, 220);
	UIDropDownMenu_Initialize(healthText, function()
		for _, mode in ipairs(ClassNameplateBarHealthText) do
			local info = UIDropDownMenu_CreateInfo();
			info.text = mode.label;
			info.value = mode.value;
			info.checked = ClassNameplateBarSetupOptions.healthTextMode == mode.value;
			info.func = function(button)
				SetCVar("nameplateSelfHealthText", button.value);
				ClassNameplateBarSetupOptions.healthTextMode = button.value;
				UIDropDownMenu_SetText(healthText, button:GetText());
				ClassNameplateBarFrame:ApplyOptions();
				ClassNameplateBarFrame:UpdateAll();
			end;
			UIDropDownMenu_AddButton(info);
		end
	end);
	self.HealthText = healthText;

	local healthTextLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
	healthTextLabel:SetPoint("BOTTOMLEFT", healthText, "TOPLEFT", 16, 2);
	healthTextLabel:SetText("Текст здоровья");

	-- галочки
	local anchor = healthText;
	self.toggles = {};
	for index, info in ipairs(ClassNameplateBarToggles) do
		local check = CreateFrame("CheckButton", name.."Toggle"..index, self, "InterfaceOptionsCheckButtonTemplate");
		check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", index == 1 and 12 or 0, -8);
		_G[check:GetName().."Text"]:SetText(info.label);
		check.info = info;
		check:SetScript("OnClick", function(button)
			SetCVar(button.info.cvar, button:GetChecked() and "1" or "0");
			ClassNameplateBarSetupOptions[button.info.key] = button:GetChecked() and true or false;
			ClassNameplateBarFrame:ApplyOptions();
		end);
		self.toggles[index] = check;
		anchor = check;
	end

	-- ползунки
	self.sliders = {};
	for index, info in ipairs(ClassNameplateBarCVars) do
		local slider = CreateFrame("Slider", name.."Slider"..index, self, "OptionsSliderTemplate");
		slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", index == 1 and 4 or 0, -32);
		slider:SetMinMaxValues(info.min, info.max);
		slider:SetValueStep(info.step);
		slider:SetWidth(220);
		slider.info = info;

		_G[slider:GetName().."Text"]:SetText(info.label);
		_G[slider:GetName().."Low"]:SetText(info.min);
		_G[slider:GetName().."High"]:SetText(info.max);

		slider:SetScript("OnValueChanged", function(bar, value)
			-- шаг может дать дробный мусор, округляем до шага
			value = math.floor(value / info.step + 0.5) * info.step;
			SetCVar(info.cvar, tostring(value));
			ClassNameplateBarSetupOptions[info.key] = value;
			_G[bar:GetName().."Text"]:SetText(info.label..": "..value);
			ClassNameplateBarFrame:ApplyOptions();
		end);

		self.sliders[index] = slider;
		anchor = slider;
	end
end

function ClassNameplateBarOptionsPanel_Refresh(self)
	if not self.built then
		return;
	end

	self.Enable:SetChecked(GetCVar("nameplateShowSelf") ~= "0");

	for _, mode in ipairs(ClassNameplateBarVisibility) do
		if mode.value == ClassNameplateBarSetupOptions.visibility then
			UIDropDownMenu_SetText(self.Visibility, mode.label);
		end
	end

	for _, mode in ipairs(ClassNameplateBarHealthText) do
		if mode.value == ClassNameplateBarSetupOptions.healthTextMode then
			UIDropDownMenu_SetText(self.HealthText, mode.label);
		end
	end

	for _, check in ipairs(self.toggles) do
		check:SetChecked(ClassNameplateBarSetupOptions[check.info.key]);
	end

	for _, slider in ipairs(self.sliders) do
		local value = ClassNameplateBarSetupOptions[slider.info.key];
		slider:SetValue(value);
		_G[slider:GetName().."Text"]:SetText(slider.info.label..": "..value);
	end
end