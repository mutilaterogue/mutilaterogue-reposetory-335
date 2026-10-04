-- Счётчик урона: окно со списком участников и окно разбивки по заклинаниям.
-- Данные берутся из C_DamageMeter (DamageMeterAPI.lua).

-- подписи типов: берутся из глобальных строк, если они объявлены
DamageMeterTypes = {
	{ type = Enum.DamageMeterType.DamageDone, label = DAMAGE_METER_DAMAGE_DONE or "Нанесённый урон" },
	{ type = Enum.DamageMeterType.Dps, label = DAMAGE_METER_DPS or "Урон в секунду" },
	{ type = Enum.DamageMeterType.HealingDone, label = DAMAGE_METER_HEALING_DONE or "Исцеление" },
	{ type = Enum.DamageMeterType.Hps, label = DAMAGE_METER_HPS or "Исцеление в секунду" },
	{ type = Enum.DamageMeterType.DamageTaken, label = DAMAGE_METER_DAMAGE_TAKEN or "Полученный урон" },
	{ type = Enum.DamageMeterType.Interrupts, label = DAMAGE_METER_INTERRUPTS or "Прерывания" },
	{ type = Enum.DamageMeterType.Dispels, label = DAMAGE_METER_DISPELS or "Рассеивания" },
	{ type = Enum.DamageMeterType.Deaths, label = DAMAGE_METER_DEATHS or "Смерти" },
};

DamageMeterFrameMixin = {};

---------------------------------------------------------------------------
-- окно со списком
---------------------------------------------------------------------------
function DamageMeterFrameMixin:OnLoad()
	self.damageMeterType = Enum.DamageMeterType.DamageDone;
	self.sessionType = Enum.DamageMeterSessionType.Current;
	self.entries = {};

	self:RegisterForDrag("LeftButton");

	self.ScrollBar:SetPoint("TOPLEFT", self.ScrollBox, "TOPRIGHT", 4, 0);
	self.ScrollBar:SetPoint("BOTTOMLEFT", self.ScrollBox, "BOTTOMRIGHT", 4, 0);

	local view = CreateScrollBoxListLinearView();
	view:SetElementExtent(20);
	view:SetPadding(0, 0, 0, 0, 2);
	view:SetElementInitializer("DamageMeterEntryTemplate", function(frame, index)
		frame:Init(self.entries[index]);
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);

	self:InitTypeDropDown();
	self:InitSessionDropDown();

	C_DamageMeter.RegisterFrame(self, "DAMAGE_METER_CURRENT_SESSION_UPDATED");
	C_DamageMeter.RegisterFrame(self, "DAMAGE_METER_RESET");

	self:Refresh();
end

function DamageMeterFrameMixin:OnEvent()
	self:Refresh();
end

function DamageMeterFrameMixin:InitTypeDropDown()
	UIDropDownMenu_SetWidth(self.TypeDropDown, 130);
	UIDropDownMenu_Initialize(self.TypeDropDown, function()
		for _, entry in ipairs(DamageMeterTypes) do
			local info = UIDropDownMenu_CreateInfo();
			info.text = entry.label;
			info.value = entry.type;
			info.checked = self.damageMeterType == entry.type;
			info.func = function(button)
				self.damageMeterType = button.value;
				UIDropDownMenu_SetText(self.TypeDropDown, button:GetText());
				self:Refresh();
			end;
			UIDropDownMenu_AddButton(info);
		end
	end);
	UIDropDownMenu_SetText(self.TypeDropDown, DamageMeterTypes[1].label);
end

function DamageMeterFrameMixin:InitSessionDropDown()
	UIDropDownMenu_SetWidth(self.SessionDropDown, 110);
	UIDropDownMenu_Initialize(self.SessionDropDown, function()
		for _, session in ipairs(C_DamageMeter.GetAvailableCombatSessions()) do
			local info = UIDropDownMenu_CreateInfo();
			info.text = session.name;
			info.value = session.sessionType;
			info.checked = self.sessionType == session.sessionType;
			info.func = function(button)
				self.sessionType = button.value;
				UIDropDownMenu_SetText(self.SessionDropDown, button:GetText());
				self:Refresh();
			end;
			UIDropDownMenu_AddButton(info);
		end
	end);
	UIDropDownMenu_SetText(self.SessionDropDown, DAMAGE_METER_SESSION_CURRENT or "Текущий бой");
end

function DamageMeterFrameMixin:Refresh()
	local session = C_DamageMeter.GetCombatSessionFromType(self.sessionType, self.damageMeterType);

	self.entries = session and session.combatSources or {};
	self.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(#self.entries));

	local duration = session and session.durationSeconds or 0;
	local total = session and session.totalAmount or 0;
	self.Footer:SetFormattedText("%s  |  %s: %s", SecondsToTime(math.floor(duration)),
		TOTAL or "Всего", DamageMeter_FormatAmount(total));

	-- окно разбивки грузится позже главного
	if DamageMeterSourceWindow and DamageMeterSourceWindow:IsShown() then
		DamageMeterSourceWindow:Refresh();
	end
end

function DamageMeterFrameMixin:Reset()
	C_DamageMeter.ResetAllCombatSessions();
	self:Refresh();
end

---------------------------------------------------------------------------
-- окно разбивки по заклинаниям
---------------------------------------------------------------------------
DamageMeterSourceWindowMixin = {};

function DamageMeterSourceWindowMixin:OnLoad()
	self.entries = {};

	self.ScrollBar:SetPoint("TOPLEFT", self.ScrollBox, "TOPRIGHT", 4, 0);
	self.ScrollBar:SetPoint("BOTTOMLEFT", self.ScrollBox, "BOTTOMRIGHT", 4, 0);

	local view = CreateScrollBoxListLinearView();
	view:SetElementExtent(20);
	view:SetPadding(0, 0, 0, 0, 2);
	view:SetElementInitializer("DamageMeterEntryTemplate", function(frame, index)
		frame:Init(self.entries[index]);
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

function DamageMeterSourceWindow_Show(source)
	if not DamageMeterSourceWindow then
		return;
	end

	DamageMeterSourceWindow.source = source;
	DamageMeterSourceWindow:Show();
	DamageMeterSourceWindow:Refresh();
end

function DamageMeterSourceWindowMixin:Refresh()
	local source = self.source;
	if not source then
		return;
	end

	local info = C_DamageMeter.GetCombatSessionSourceFromType(DamageMeterFrame.sessionType,
		DamageMeterFrame.damageMeterType, source.sourceGUID, source.sourceCreatureID);

	self.entries = info and info.combatSpells or {};

	-- индекс и максимум нужны полоске
	for index, spell in ipairs(self.entries) do
		spell.index = index;
		spell.maxAmount = info.maxAmount;
		spell.classFilename = source.classFilename;
		spell.showsValuePerSecondAsPrimary = info.showsValuePerSecondAsPrimary;
	end

	self.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(#self.entries));
	self.Title:SetText(source.name or UNKNOWN);
end
