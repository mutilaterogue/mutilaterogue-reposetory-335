-- Кнопка-шестерёнка с меню (ретейловый DamageMeterSettingsDropdownButton).

-- кнопка выбора сегмента в шапке
DamageMeterHeaderButtonMixin = CreateFromMixins(DropdownButtonMixin);

function DamageMeterHeaderButtonMixin:OnButtonStateChanged()
	local atlas = "common-dropdown-a-button-shadowless";

	if not self:IsEnabled() then
		atlas = "common-dropdown-a-button-disabled-shadowless";
	elseif self:IsDownOver() then
		atlas = "common-dropdown-a-button-pressedhover-shadowless";
	elseif self:IsOver() then
		atlas = "common-dropdown-a-button-hover-shadowless";
	elseif self:IsDown() then
		atlas = "common-dropdown-a-button-pressed-shadowless";
	elseif self:IsMenuOpen() then
		atlas = "common-dropdown-a-button-open-shadowless";
	end

	self.Icon:SetAtlas(atlas, false);
end

DamageMeterSettingsDropdownButtonMixin = CreateFromMixins(DropdownButtonMixin);

function DamageMeterSettingsDropdownButtonMixin:GetIcon()
	return self.Icon;
end

function DamageMeterSettingsDropdownButtonMixin:GetIconAtlas()
	if not self:IsEnabled() then
		return self.disabled;
	elseif self:IsDownOver() then
		return self.hoverPressed;
	elseif self:IsOver() then
		return self.hover;
	elseif self:IsDown() then
		return self.pressed;
	elseif self:IsMenuOpen() then
		return self.open;
	end
	return self.normal;
end

function DamageMeterSettingsDropdownButtonMixin:OnButtonStateChanged()
	local atlas = self:GetIconAtlas();
	if atlas then
		-- без useAtlasSize: размер берём из шаблона, иначе кнопки налезают
		self:GetIcon():SetAtlas(atlas, false);
	end
end

function DamageMeterSettingsDropdownButtonMixin:OnLoad()
	DropdownButtonMixin.OnLoad(self);

	self:SetMenuAnchor({ point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = -2 });

	self:SetupMenu(function(dropdown, rootDescription)
		rootDescription:CreateTitle(DAMAGE_METER_LABEL);

		rootDescription:CreateCheckbox(DAMAGE_METER_CLASS_COLORS or "Цвета классов",
			function() return GetCVar("damageMeterClassColors") ~= "0"; end,
			function(_, value)
				SetCVar("damageMeterClassColors", value and "1" or "0");
				DamageMeterSessionWindow:ApplyOptions();
				return MenuResponse.Refresh;
			end);

		rootDescription:CreateCheckbox(DAMAGE_METER_SHOW_ICONS or "Показывать иконки",
			function() return GetCVar("damageMeterShowIcons") ~= "0"; end,
			function(_, value)
				SetCVar("damageMeterShowIcons", value and "1" or "0");
				DamageMeterSessionWindow:ApplyOptions();
				return MenuResponse.Refresh;
			end);

		rootDescription:CreateCheckbox(DAMAGE_METER_GROUP_ONLY or "Только своя группа и рейд",
			function() return GetCVar("damageMeterGroupOnly") ~= "0"; end,
			function(_, value)
				SetCVar("damageMeterGroupOnly", value and "1" or "0");
				DamageMeterSessionWindow:Refresh();
				return MenuResponse.Refresh;
			end);

		rootDescription:CreateCheckbox(AUTO_RESET_DAMAGE_METER,
			function() return GetCVar("damageMeterAutoReset") ~= "0"; end,
			function(_, value)
				SetCVar("damageMeterAutoReset", value and "1" or "0");
				return MenuResponse.Refresh;
			end);

		rootDescription:CreateDivider();

		rootDescription:CreateButton(DAMAGE_METER_OPEN_SETTINGS, function()
			InterfaceOptionsFrame_OpenToCategory(DamageMeterOptionsPanel);
			InterfaceOptionsFrame_OpenToCategory(DamageMeterOptionsPanel);
		end);

		rootDescription:CreateButton(DAMAGE_METER_RESET_ALL_SESSIONS, function()
			C_DamageMeter.ResetAllCombatSessions();
		end);

		rootDescription:CreateButton(DAMAGE_METER_HIDE_WINDOW, function()
			DamageMeterSessionWindow.userShown = false;
			DamageMeterSessionWindow:Hide();
		end);
	end);
end
