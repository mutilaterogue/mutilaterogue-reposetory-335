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
	-- the icon shares ARTWORK with the bar fill and goes under it on long bars: above it
	self.Icon:SetDrawLayer("OVERLAY");

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

local function Amount(value)
	return DamageMeter_FormatAmount(value or 0);
end

-- retail spell tooltip: hits, average, crits, the biggest hit, the share, overkill / overheal; a death: its recap
local function ShowSpellTooltip(self, data)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:AddLine(data.name or UNKNOWN, 1, 1, 1);

	if data.death then
		local deathTime = data.death.time or GetTime();
		for _, event in ipairs(data.death.events or {}) do
			local seconds = string.format("%.1f", (event.time or deathTime) - deathTime);
			local text = (event.amount < 0 and "-" or "+") .. Amount(math.abs(event.amount));
			local r, g, b = 1, 0.2, 0.2;
			if event.amount > 0 then
				r, g, b = 0.2, 1, 0.2;
			end
			GameTooltip:AddDoubleLine(seconds .. "  " .. event.spell .. " (" .. event.source .. ")", text, 1, 1, 1, r, g, b);
		end
		GameTooltip:Show();
		return;
	end

	local hits = data.hitCount or 0;
	local Line = function(label, value)
		GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, 1, 1, 1);
	end
	Line("Всего", Amount(data.totalAmount) .. string.format(" (%.1f%%)", data.percent or 0));
	if data.amountPerSecond then
		Line("В секунду", Amount(data.amountPerSecond));
	end
	if hits > 0 then
		Line("Срабатываний", hits);
		Line("В среднем", Amount((data.totalAmount or 0) / hits));
		Line("Наибольшее", Amount(data.maxHit));
		Line("Критических", string.format("%d (%.1f%%)", data.critCount or 0, (data.critCount or 0) / hits * 100));
	end
	if (data.overAmount or 0) > 0 then
		local label = data.meterType == Enum.DamageMeterType.HealingDone and "Избыточное исцеление" or "Избыточный урон";
		Line(label, Amount(data.overAmount));
	end
	GameTooltip:Show();
end

function DamageMeterEntryMixin:OnEnter()
	self.Highlight:Show();
	local data = self.data;
	-- a spell line (no source to open): its details
	if data and not (data.sourceGUID or data.sourceCreatureID) and (data.hitCount or data.death) then
		ShowSpellTooltip(self, data);
	end
end

function DamageMeterEntryMixin:OnLeave()
	self.Highlight:Hide();
	GameTooltip:Hide();
end
