-- Главное окно счётчика: список участников текущей или прошлой сессии.

DamageMeterSessionWindowMixin = {};

local function GetOption(cvar, default)
	local value = GetCVar and GetCVar(cvar);
	if value == nil or value == "" then
		return default;
	end
	return tonumber(value) or value;
end

function DamageMeterSessionWindowMixin:OnLoad()
	self.damageMeterType = Enum.DamageMeterType.DamageDone;
	self.sessionType = Enum.DamageMeterSessionType.Current;
	self.entries = {};

	self:RegisterForDrag("LeftButton");

	self.ScrollBar:SetPoint("TOPLEFT", self.ScrollBox, "TOPRIGHT", 2, 0);
	self.ScrollBar:SetPoint("BOTTOMLEFT", self.ScrollBox, "BOTTOMRIGHT", 2, 0);

	local view = CreateScrollBoxListLinearView();
	view:SetElementExtent(self:GetBarHeight());
	view:SetPadding(0, 0, 0, 0, self:GetBarSpacing());
	view:SetElementInitializer("DamageMeterEntryTemplate", function(frame, index)
		frame:SetUseClassColor(self:ShouldUseClassColor());
		frame:SetShowBarIcons(self:ShouldShowBarIcons());
		frame:SetBarHeight(self:GetBarHeight());
		frame:SetTextScale(self:GetTextScale());
		frame:SetBackgroundAlpha(self:GetBackgroundAlpha());
		frame:Init(self.entries[index]);
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);

	self:LayoutHeader();
	self:InitTypeDropDown();
	self:InitSessionDropDown();
	self:SetDamageMeterType(self.damageMeterType);
	self:SetSessionType(self.sessionType);
	self:InitResizeButton();

	C_DamageMeter.RegisterFrame(self, "DAMAGE_METER_CURRENT_SESSION_UPDATED");
	C_DamageMeter.RegisterFrame(self, "DAMAGE_METER_RESET");

	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:RegisterEvent("PARTY_MEMBERS_CHANGED");
	self:RegisterEvent("RAID_ROSTER_UPDATE");

	self:ApplyOptions();
	self:Refresh();
end

function DamageMeterSessionWindowMixin:LayoutHeader()
	self.SettingsButton:SetSize(24, 24);
	self.SettingsButton:ClearAllPoints();
	self.SettingsButton:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -2);

	self.SessionButton:SetSize(22, 22);
	self.SessionButton:ClearAllPoints();
	self.SessionButton:SetPoint("RIGHT", self.SettingsButton, "LEFT", 0, 0);

	self.TypeDropDown:SetSize(20, 20);
	self.TypeDropDown:ClearAllPoints();
	self.TypeDropDown:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -3);

	self.Title:ClearAllPoints();
	self.Title:SetPoint("LEFT", self.TypeDropDown, "RIGHT", 4, 0);
	self.Title:SetPoint("RIGHT", self.SessionButton, "LEFT", -4, 0);
end

function DamageMeterSessionWindowMixin:OnEvent()
	self:UpdateVisibility();
	self:Refresh();
end

---------------------------------------------------------------------------
-- настройки (CVar'ы, панель в настройках интерфейса)
---------------------------------------------------------------------------
function DamageMeterSessionWindowMixin:GetBarHeight()
	return GetOption("damageMeterBarHeight", DAMAGE_METER_DEFAULT_BAR_HEIGHT);
end

function DamageMeterSessionWindowMixin:GetBarSpacing()
	return GetOption("damageMeterBarSpacing", DAMAGE_METER_DEFAULT_BAR_SPACING);
end

function DamageMeterSessionWindowMixin:GetTextScale()
	return GetOption("damageMeterTextSize", 100) * DAMAGE_METER_TEXT_SIZE_TO_SCALE_MULTIPLIER;
end

function DamageMeterSessionWindowMixin:GetBackgroundAlpha()
	return GetOption("damageMeterTransparency", 100) * DAMAGE_METER_TRANSPARENCY_TO_ALPHA_MULTIPLIER;
end

function DamageMeterSessionWindowMixin:ShouldUseClassColor()
	return GetOption("damageMeterClassColors", 1) ~= 0;
end

function DamageMeterSessionWindowMixin:ShouldShowBarIcons()
	return GetOption("damageMeterShowIcons", 1) ~= 0;
end

function DamageMeterSessionWindowMixin:GetVisibilityMode()
	return GetOption("damageMeterVisibility", "always");
end

function DamageMeterSessionWindowMixin:ApplyOptions()
	local view = self.ScrollBox:GetView();
	if view then
		view:SetElementExtent(self:GetBarHeight());
		view:SetPadding(0, 0, 0, 0, self:GetBarSpacing());
	end

	self.Background:SetAlpha(self:GetBackgroundAlpha());
	self:Refresh();
	self:UpdateVisibility();
end

function DamageMeterSessionWindowMixin:UpdateVisibility()
	local mode = self:GetVisibilityMode();
	local show;

	if mode == "hidden" then
		show = false;
	elseif mode == "combat" then
		show = UnitAffectingCombat("player");
	elseif mode == "group" then
		show = GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0;
	else
		show = true;
	end

	self:SetShown(show and self.userShown ~= false);
end

---------------------------------------------------------------------------
-- выпадающие списки
---------------------------------------------------------------------------
function DamageMeterSessionWindowMixin:InitTypeDropDown()
	-- стрелка слева: категории с подменю, как в ретейле
	self.TypeDropDown:SetupMenu(function(dropdown, rootDescription)
		for _, category in ipairs(DamageMeterCategories) do
			local submenu = rootDescription:CreateSubmenu(category.label);

			for _, entry in ipairs(category.types) do
				submenu:CreateRadio(entry.label,
					function() return self.damageMeterType == entry.type; end,
					function()
						self:SetDamageMeterType(entry.type);
					end);
			end
		end
	end);
end

function DamageMeterSessionWindowMixin:InitSessionDropDown()
	-- кнопка справа: текущий сегмент или общий итог
	self.SessionButton:SetupMenu(function(dropdown, rootDescription)
		for _, session in ipairs(C_DamageMeter.GetAvailableCombatSessions()) do
			local sessionType = session.sessionType;
			rootDescription:CreateRadio(session.name,
				function() return self.sessionType == sessionType; end,
				function()
					self:SetSessionType(sessionType);
				end);
		end
	end);
end

function DamageMeterSessionWindowMixin:SetDamageMeterType(damageMeterType)
	self.damageMeterType = damageMeterType;
	self.Title:SetText(DamageMeter_GetTypeLabel(damageMeterType));
	self:Refresh();
end

function DamageMeterSessionWindowMixin:SetSessionType(sessionType)
	self.sessionType = sessionType;

	local _, short = DamageMeter_GetSessionLabel(sessionType);
	self.SessionButton.Text:SetText(short);

	self:Refresh();
end

---------------------------------------------------------------------------
-- изменение размера
---------------------------------------------------------------------------
function DamageMeterSessionWindowMixin:InitResizeButton()
	if self.SetResizable then
		self:SetResizable(true);
	end
	if self.SetMinResize then
		self:SetMinResize(200, 120);
	end
	if self.SetMaxResize then
		self:SetMaxResize(500, 600);
	end

	local resizeButton = self.ResizeButton;
	resizeButton:SetAlpha(0);

	resizeButton:SetScript("OnMouseDown", function(button)
		self:StartSizing("BOTTOMRIGHT");
		self.isResizing = true;
	end);

	resizeButton:SetScript("OnMouseUp", function(button)
		self:StopMovingOrSizing();
		self.isResizing = false;
		self:Refresh();
	end);

	resizeButton:SetScript("OnEnter", function(button)
		button:SetAlpha(1);
	end);
end

-- уголок виден, пока курсор над окном
function DamageMeterSessionWindowMixin:OnUpdate(elapsed)
	-- иконки классов: раз в секунду добираем те, что ещё не определились
	if self.needsIconRefresh then
		self.iconTimer = (self.iconTimer or 0) + (elapsed or 0);
		if self.iconTimer > 1 then
			self.iconTimer = 0;
			self.needsIconRefresh = false;
			self:Refresh();
		end
	end

	local resizeButton = self.ResizeButton;
	if not resizeButton then
		return;
	end

	local shouldShow = self:IsMouseOver() or self.isResizing;
	local alpha = resizeButton:GetAlpha();

	if shouldShow and alpha < 1 then
		resizeButton:SetAlpha(math.min(1, alpha + 0.1));
	elseif not shouldShow and alpha > 0 then
		resizeButton:SetAlpha(math.max(0, alpha - 0.1));
	end
end

---------------------------------------------------------------------------
-- данные
---------------------------------------------------------------------------
function DamageMeterSessionWindowMixin:Refresh()
	local session = C_DamageMeter.GetCombatSessionFromType(self.sessionType, self.damageMeterType);

	self.entries = session and session.combatSources or {};
	self.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(#self.entries));

	local duration = session and session.durationSeconds or 0;
	local total = session and session.totalAmount or 0;
	self.Footer:SetFormattedText("%s  |  %s", SecondsToTime(math.floor(duration)), DamageMeter_FormatAmount(total));

	if DamageMeterSourceWindow and DamageMeterSourceWindow:IsShown() then
		DamageMeterSourceWindow:Refresh();
	end
end

function DamageMeterSessionWindowMixin:GetDamageMeterType()
	return self.damageMeterType;
end

function DamageMeterSessionWindowMixin:GetSessionType()
	return self.sessionType;
end

SLASH_DAMAGEMETER1 = "/dm";
SLASH_DAMAGEMETER2 = "/damagemeter";
SlashCmdList["DAMAGEMETER"] = function()
	DamageMeterSessionWindow.userShown = not DamageMeterSessionWindow:IsShown();
	DamageMeterSessionWindow:SetShown(DamageMeterSessionWindow.userShown);
end
