-- было NamePlateSetupOptions: это имя занимают ретейловые неймплейты (NamePlates\NamePlateFrameOptions.lua)
ClassNameplateBarSetupOptions = ClassNameplateBarSetupOptions or {
	width = 120,
	healthBarHeight = 12,
	powerBarHeight = 5,
	spacing = 1,
	heightOffset = -1.5,
	classResourceScale = 0.8,
	classResourceSpacing = -2,
	showName = false,
	healthTextMode = "none",	-- none | percent | value | both
	fadeTime = 0.2,
	visibility = "always",		-- always | combat | instance | raid | arena | pvp | never
};

local POWER_BAR_ATLAS = {
	MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
	RAGE = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
	ENERGY = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
	FOCUS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus",
	RUNIC_POWER = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower",
};

local HEALTH_BAR_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health";

local POWER_TOKENS = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [6] = "RUNIC_POWER" };

-- UnitPowerType follows the druid forms itself (the form index of GetShapeshiftForm shifts with the forms known)
local function GetPlayerPowerType()
	local powerType, powerToken = UnitPowerType("player");
	powerType = powerType or 0;
	return powerType, powerToken or POWER_TOKENS[powerType] or "MANA";
end

local enabled = true;

local function IsEnabled()
	if GetCVar and GetCVar("nameplateShowSelf") then
		return GetCVar("nameplateShowSelf") ~= "0";
	end
	return enabled;
end

-- режим показа из настроек
local function MatchesVisibility()
	local mode = ClassNameplateBarSetupOptions.visibility or "always";

	if mode == "never" then
		return false;
	elseif mode == "always" then
		return true;
	elseif mode == "combat" then
		return UnitAffectingCombat("player");
	end

	local inInstance, instanceType = IsInInstance();

	if mode == "instance" then
		return inInstance and (instanceType == "party" or instanceType == "raid");
	elseif mode == "raid" then
		return inInstance and instanceType == "raid";
	elseif mode == "arena" then
		return inInstance and instanceType == "arena";
	elseif mode == "pvp" then
		return inInstance and (instanceType == "arena" or instanceType == "pvp");
	end

	return true;
end

function ClassNameplateBar_SetEnabled(value)
	enabled = value;
	if SetCVar and GetCVar and GetCVar("nameplateShowSelf") then
		SetCVar("nameplateShowSelf", value and "1" or "0");
	end
	ClassNameplateBarFrame:UpdateVisibility();
end

---------------------------------------------------------------------------
-- классовый ресурс под полосками
---------------------------------------------------------------------------
local function GetClassResourceFrame()
	local _, class = UnitClass("player");

	if class == "ROGUE" or class == "DRUID" then
		return ComboFrame;
	elseif class == "DEATHKNIGHT" then
		return RuneFrame;
	end
end

local function AttachClassResource(self)
	local frame = GetClassResourceFrame();
	if not frame then
		return;
	end

	if not frame.nameplateOriginalPoint then
		frame.nameplateOriginalPoint = { frame:GetPoint(1) };
		frame.nameplateOriginalParent = frame:GetParent();
		frame.nameplateOriginalScale = frame:GetScale();
	end

	if frame:GetParent() ~= self then
		frame:SetParent(self);
	end

	frame:ClearAllPoints();
	frame:SetPoint("TOP", self.PowerBar, "BOTTOM", 0, ClassNameplateBarSetupOptions.classResourceSpacing);
	frame:SetScale(ClassNameplateBarSetupOptions.classResourceScale);

	self.classResource = frame;
end

local function DetachClassResource(self)
	local frame = self.classResource;
	if not frame or not frame.nameplateOriginalPoint then
		return;
	end

	frame:SetParent(frame.nameplateOriginalParent);
	frame:ClearAllPoints();
	frame:SetPoint(unpack(frame.nameplateOriginalPoint));
	frame:SetScale(frame.nameplateOriginalScale or 1);

	self.classResource = nil;
end

---------------------------------------------------------------------------
-- фрейм
---------------------------------------------------------------------------
ClassNameplateBarFrameMixin = {};

function ClassNameplateBarFrameMixin:OnLoad()
	self:ApplyOptions();

	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("UNIT_HEALTH");
	self:RegisterEvent("UNIT_MAXHEALTH");
	self:RegisterEvent("UNIT_POWER");
	self:RegisterEvent("UNIT_MAXPOWER");
	self:RegisterEvent("UNIT_DISPLAYPOWER");
	self:RegisterEvent("UNIT_NAME_UPDATE");
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM");
	-- собственное событие DLL: входящее лечение
	self:RegisterEvent("UNIT_HEAL_PREDICTION");
	-- для режимов показа
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA");

	if ClassNameplateBar_LoadOptions then
		ClassNameplateBar_LoadOptions();
	end

	self:SetScript("OnUpdate", self.OnUpdate);

	self:UpdatePowerColor();
	self:UpdateAll();
end

function ClassNameplateBarFrameMixin:ApplyOptions()
	local options = ClassNameplateBarSetupOptions;

	-- текст живёт на полоске: фрейм-полоска рисуется поверх слоёв родителя
	if not self.HealthBar.PercentText then
		self.HealthBar.PercentText = self.HealthBar:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall");
		self.HealthBar.PercentText:SetPoint("LEFT", self.HealthBar, "LEFT", 3, 0);
		self.HealthBar.PercentText:SetJustifyH("LEFT");

		self.HealthBar.ValueText = self.HealthBar:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall");
		self.HealthBar.ValueText:SetPoint("RIGHT", self.HealthBar, "RIGHT", -3, 0);
		self.HealthBar.ValueText:SetJustifyH("RIGHT");

		self.HealthBar.CenterText = self.HealthBar:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall");
		self.HealthBar.CenterText:SetPoint("CENTER", self.HealthBar, "CENTER");
	end
	self.PowerBar:ClearAllPoints();
	self.PowerBar:SetPoint("TOPLEFT", self.HealthBar, "BOTTOMLEFT", 0, -options.spacing);
	self.PowerBar:SetPoint("TOPRIGHT", self.HealthBar, "BOTTOMRIGHT", 0, -options.spacing);

	self:SetWidth(options.width);
	self:SetHeight(options.healthBarHeight + options.powerBarHeight + options.spacing * 3);

	self.HealthBar:SetHeight(options.healthBarHeight);

	-- StatusBar 3.3.5 сам переписывает текс-координаты заливки при каждом SetValue,
	-- из-за этого атлас "съезжал" на соседний кусок листа (мана вместо энергии, белый).
	-- Заливку рисует атласная обёртка из CastingBar\CastingBarCompat.lua.
	CastingBar_InitAtlasStatusBar(self.HealthBar);
	CastingBar_InitAtlasStatusBar(self.PowerBar);

	self.HealthBar:SetStatusBarTexture(HEALTH_BAR_ATLAS);
	self.HealthBar:SetStatusBarColor(1, 1, 1);
	self:UpdatePowerColor();

	self.HealPrediction:SetHeight(options.healthBarHeight);

	self.PowerBar:SetHeight(options.powerBarHeight);

	self.Name:SetShown(options.showName);

	-- режим текста здоровья
	local mode = options.healthTextMode or "none";
	self.HealthBar.PercentText:SetShown(mode == "percent" or mode == "both");
	self.HealthBar.ValueText:SetShown(mode == "value" or mode == "both");
	self.HealthBar.CenterText:SetShown(false);

	-- один показатель выводим по центру, два — по краям
	if mode == "percent" or mode == "value" then
		self.HealthBar.PercentText:Hide();
		self.HealthBar.ValueText:Hide();
		self.HealthBar.CenterText:Show();
	end

	if self.HealthText then
		self.HealthText:Hide();
	end
end

function ClassNameplateBarFrameMixin:OnEvent(event, unit)
	if event == "PLAYER_ENTERING_WORLD" then
		self:UpdatePowerColor();
		AttachClassResource(self);
	end
	
	if event == "UPDATE_SHAPESHIFT_FORM" then
		self:UpdatePowerColor();
		AttachClassResource(self);
	end

	if unit and unit ~= "player" then
		return;
	end

	if event == "UNIT_DISPLAYPOWER" then
		self:UpdatePowerColor();
		AttachClassResource(self);
	end

	self:UpdateAll();
	self:UpdateVisibility();
end

function ClassNameplateBarFrameMixin:UpdatePowerColor()
	local powerType, powerToken = GetPlayerPowerType();
	self.powerType = powerType;
	local atlas = POWER_BAR_ATLAS[powerToken];

	if atlas and C_Texture.GetAtlasInfo(atlas) then
		self.PowerBar:SetStatusBarTexture(atlas);
		self.PowerBar:SetStatusBarColor(1, 1, 1);
	else
		local color = PowerBarColor[powerToken] or PowerBarColor["MANA"];
		self.PowerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
		self.PowerBar:SetStatusBarColor(color.r, color.g, color.b);
	end
end

function ClassNameplateBarFrameMixin:UpdateAll()
	local health, maxHealth = UnitHealth("player"), UnitHealthMax("player");
	maxHealth = maxHealth > 0 and maxHealth or 1;

	self.HealthBar:SetMinMaxValues(0, maxHealth);
	self.HealthBar:SetValue(health);

	local powerType = GetPlayerPowerType();
	-- at login the client may say mana before the real power is known: the colour follows any change
	if powerType ~= self.powerType then
		self:UpdatePowerColor();
	end
	local power, maxPower = UnitPower("player", powerType), UnitPowerMax("player", powerType);
	self.PowerBar:SetMinMaxValues(0, maxPower > 0 and maxPower or 1);
	self.PowerBar:SetValue(power);

	local mode = ClassNameplateBarSetupOptions.healthTextMode or "none";
	if mode ~= "none" then
		local percent = format("%d%%", math.floor(health / maxHealth * 100 + 0.5));
		local value = AbbreviateLargeNumbers and AbbreviateLargeNumbers(health) or tostring(health);

		if mode == "both" then
			self.HealthBar.PercentText:SetText(percent);
			self.HealthBar.ValueText:SetText(value);
		else
			self.HealthBar.CenterText:SetText(mode == "percent" and percent or value);
		end
	end

	if ClassNameplateBarSetupOptions.showName then
		self.Name:SetText(UnitName("player"));
	end

	self:UpdateHealPrediction(health, maxHealth);
end

function ClassNameplateBarFrameMixin:UpdateHealPrediction(health, maxHealth)
	if not UnitGetIncomingHeals then
		self.HealPrediction:Hide();
		return;
	end

	local incoming = UnitGetIncomingHeals("player") or 0;
	if incoming <= 0 then
		self.HealPrediction:Hide();
		return;
	end

	local barWidth = self.HealthBar:GetWidth();
	local healthWidth = barWidth * (health / maxHealth);
	local predictionWidth = math.min(barWidth * (incoming / maxHealth), barWidth - healthWidth);

	if predictionWidth <= 0 then
		self.HealPrediction:Hide();
		return;
	end

	self.HealPrediction:ClearAllPoints();
	self.HealPrediction:SetPoint("TOPLEFT", self.HealthBar, "TOPLEFT", healthWidth, 0);
	self.HealPrediction:SetWidth(predictionWidth);
	self.HealPrediction:Show();
end

function ClassNameplateBarFrameMixin:ShouldShow()
	return IsEnabled() and MatchesVisibility() and not UnitIsDeadOrGhost("player");
end

function ClassNameplateBarFrameMixin:UpdateVisibility()
	local shouldShow = self:ShouldShow();

	if shouldShow and not self:IsShown() then
		AttachClassResource(self);
		self:Show();
		UIFrameFadeIn(self, ClassNameplateBarSetupOptions.fadeTime);
	elseif not shouldShow and self:IsShown() then
		DetachClassResource(self);
		self:Hide();
	end
end

function ClassNameplateBarFrameMixin:UpdatePosition()
	if not GetUnitWorldPosition or not ConvertCoordsToScreenSpace then
		return false;
	end

	local x, y, z = GetUnitWorldPosition("player");
	if not x then
		return false;
	end

	local screenX, screenY = ConvertCoordsToScreenSpace(x, y, z + ClassNameplateBarSetupOptions.heightOffset);
	if not screenX or screenX ~= screenX then		-- nan: точку спроецировать нельзя
		return false;
	end

	local scale = self:GetEffectiveScale();

	-- якорь сверху: полоски висят ПОД точкой привязки, то есть под персонажем
	self:ClearAllPoints();
	self:SetPoint("TOP", UIParent, "BOTTOMLEFT", screenX / scale, screenY / scale);

	return true;
end

function ClassNameplateBarFrameMixin:OnUpdate()
	if not self:ShouldShow() then
		self:Hide();
		return;
	end

	if not self:UpdatePosition() then
		self:SetAlpha(0);
		return;
	end

	self:SetAlpha(1);
	if self.classResource and self.classResource:GetParent() ~= self then
		AttachClassResource(self);
	end
	self:UpdateAll();
end