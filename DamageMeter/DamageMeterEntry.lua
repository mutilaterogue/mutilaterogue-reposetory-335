-- Полоска участника и строка заклинания.

DamageMeterEntryMixin = {};

-- Настройка строки: делается при первом Init, потому что OnLoad шаблона
-- в 3.3.5 через mixin-метод вызывается не всегда.
local function EnsureSetup(self)
	if self.isSetUp then
		return;
	end
	self.isSetUp = true;

	self.Rank = self.Rank or self.Bar.Rank;
	self.Name = self.Name or self.Bar.Name;
	self.Amount = self.Amount or self.Bar.Amount;
	self.Icon = self.Icon or self.Bar.Icon;

	self.Bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");

	local texture = self.Bar:GetStatusBarTexture();
	if texture and texture.SetAtlas then
		texture:SetAtlas("UI-HUD-CoolDownManager-Bar");
	end

	if self.EnableMouse then
		self:EnableMouse(true);
	end
	if self.RegisterForClicks then
		self:RegisterForClicks("AnyUp");
	end

	-- method="..." in the template is not reliable on 3.3.5 frames made by ScrollBox: the scripts by hand.
	-- ScrollBox may make the row a plain Frame (no OnClick): then the click is OnMouseUp
	if self:HasScript("OnClick") then
		self:SetScript("OnClick", function(frame, ...) DamageMeterEntryMixin.OnClick(frame, ...); end);
	else
		self:SetScript("OnMouseUp", function(frame, ...) DamageMeterEntryMixin.OnClick(frame, ...); end);
	end
	self:SetScript("OnEnter", function(frame) DamageMeterEntryMixin.OnEnter(frame); end);
	self:SetScript("OnLeave", function(frame) DamageMeterEntryMixin.OnLeave(frame); end);
end

local function GetRegions(self)
	-- строки и иконка лежат на полоске; в 3.3.5 OnLoad шаблона может отработать позже инициализатора
	self.Rank = self.Rank or self.Bar.Rank;
	self.Name = self.Name or self.Bar.Name;
	self.Amount = self.Amount or self.Bar.Amount;
	self.Icon = self.Icon or self.Bar.Icon;
end

function DamageMeterEntryMixin:OnLoad()
	EnsureSetup(self);
end

function DamageMeterEntryMixin:SetBarHeight(height)
	self:SetHeight(height);
end

function DamageMeterEntryMixin:SetTextScale(scale)
	EnsureSetup(self);

	-- у FontString в 3.3.5 нет SetScale, поэтому масштабируем размер шрифта
	for _, fontString in ipairs({ self.Rank, self.Name, self.Amount }) do
		if not fontString.baseFontSize then
			local _, size = fontString:GetFont();
			fontString.baseFontSize = size or 10;
		end

		local file, _, flags = fontString:GetFont();
		if file then
			fontString:SetFont(file, fontString.baseFontSize * scale, flags);
		end
	end
end

function DamageMeterEntryMixin:SetUseClassColor(useClassColor)
	self.useClassColor = useClassColor;
end

function DamageMeterEntryMixin:SetShowBarIcons(showBarIcons)
	self.showBarIcons = showBarIcons;
end

function DamageMeterEntryMixin:SetBackgroundAlpha(alpha)
	EnsureSetup(self);
	self.ShadowBG:SetAlpha(alpha);
end

function DamageMeterEntryMixin:Init(data)
	EnsureSetup(self);

	self.data = data;
	if not self.Bar then
		return;
	end
	if not data then
		return;
	end

	local color = self.useClassColor ~= false and data.classFilename and RAID_CLASS_COLORS[data.classFilename];
	if color then
		self.Bar:SetStatusBarColor(color.r, color.g, color.b);
	else
		self.Bar:SetStatusBarColor(0.45, 0.45, 0.5);
	end

	local maxAmount = data.maxAmount or data.totalAmount or 1;
	self.Bar:SetMinMaxValues(0, maxAmount > 0 and maxAmount or 1);
	self.Bar:SetValue(data.totalAmount or 0);

	self.Rank:SetText(data.index and (data.index..".") or "");
	self.Name:SetText(data.name or UNKNOWN);

	local primary, secondary;
	if data.showsValuePerSecondAsPrimary then
		primary, secondary = data.amountPerSecond, data.totalAmount;
	else
		primary, secondary = data.totalAmount, data.amountPerSecond;
	end
	self.Amount:SetFormattedText("%s (%s)", DamageMeter_FormatAmount(primary), DamageMeter_FormatAmount(secondary));

	-- иконка: у заклинания своя, у участника иконка класса
	local icon, coords = data.icon, nil;
	if not icon and data.classFilename and CLASS_ICON_TCOORDS[data.classFilename] then
		icon = "Interface\\TargetingFrame\\UI-Classes-Circles";
		coords = CLASS_ICON_TCOORDS[data.classFilename];
	end

	-- класс чужого игрока становится известен не сразу: просим окно обновиться
	if not icon and data.sourceGUID and not data.classFilename then
		DamageMeterSessionWindow.needsIconRefresh = true;
	end

	if icon and self.showBarIcons ~= false then
		self.Icon:SetTexture(icon);
		self.Icon:SetTexCoord(unpack(coords or { 0, 1, 0, 1 }));
		self.Icon:Show();
		self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 4, 0);
	else
		self.Icon:Hide();
		self.Name:SetPoint("LEFT", self.Rank, "RIGHT", 4, 0);
	end
end

function DamageMeterEntryMixin:OnClick()
	local data = self.data;
	if not data or not (data.sourceGUID or data.sourceCreatureID) then
		return;		-- строка заклинания, разбивать дальше нечего
	end

	local window = DamageMeterSourceWindow;

	if window:IsShown() and window.sourceGUID == data.sourceGUID then
		window:Hide();
		return;
	end

	window:SetSource(data);
	window:Show();
	window:Refresh();
end

function DamageMeterEntryMixin:OnEnter()
	self.Highlight:Show();
end

function DamageMeterEntryMixin:OnLeave()
	self.Highlight:Hide();
end
