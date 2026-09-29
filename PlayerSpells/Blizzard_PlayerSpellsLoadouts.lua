-- Наборы талантов (ретейл: ClassTalentLoadoutDropdown, C_ClassTalents.GetConfigIDsBySpecID / LoadConfig).
-- Выпадающий список на нижней панели вкладки «Таланты»: выбрать набор (применить), сохранить текущие
-- таланты новым набором или поверх выбранного, переименовать, удалить. Наборы - свои у каждой
-- специализации (двойная специализация 3.3.5), применяются только к активной.
-- Сервер (server/talent_loadouts.cpp):
--   "TLOAD_GET" -> "TLOAD" : id : name (xN), "TLOAD_END" : activeId : max
--   "TLOAD_SAVE" : id (0 - новый) : name, "TLOAD_RENAME" : id : name, "TLOAD_DEL" : id
--   "TLOAD_APPLY" : id -> "TLOAD_RESULT" : ok : код

TALENT_LOADOUT_LABEL = TALENT_LOADOUT_LABEL or "Наборы талантов";
TALENT_LOADOUT_NONE = TALENT_LOADOUT_NONE or "Без набора";
TALENT_LOADOUT_NEW = TALENT_LOADOUT_NEW or "Сохранить как новый набор";
TALENT_LOADOUT_OVERWRITE = TALENT_LOADOUT_OVERWRITE or "Сохранить в «%s»";
TALENT_LOADOUT_RENAME = TALENT_LOADOUT_RENAME or "Переименовать «%s»";
TALENT_LOADOUT_DELETE = TALENT_LOADOUT_DELETE or "Удалить «%s»";
TALENT_LOADOUT_NAME_PROMPT = TALENT_LOADOUT_NAME_PROMPT or "Название набора талантов:";
TALENT_LOADOUT_APPLY_CONFIRM = TALENT_LOADOUT_APPLY_CONFIRM or "Применить набор «%s»?\nТаланты активной специализации будут сброшены и изучены заново (бесплатно).";
TALENT_LOADOUT_DELETE_CONFIRM = TALENT_LOADOUT_DELETE_CONFIRM or "Удалить набор «%s»?";
TALENT_LOADOUT_OTHER_SPEC = TALENT_LOADOUT_OTHER_SPEC or "Наборы доступны для активной специализации.";
-- ответы сервера (коды)
TALENT_LOADOUT_SAVED = TALENT_LOADOUT_SAVED or "Набор талантов сохранён.";
TALENT_LOADOUT_APPLIED = TALENT_LOADOUT_APPLIED or "Набор талантов применён.";
TALENT_LOADOUT_ERR_COMBAT = TALENT_LOADOUT_ERR_COMBAT or "Нельзя менять таланты в бою.";
TALENT_LOADOUT_ERR_MAX = TALENT_LOADOUT_ERR_MAX or "Достигнуто максимальное число наборов.";
TALENT_LOADOUT_ERR_NOT_FOUND = TALENT_LOADOUT_ERR_NOT_FOUND or "Набор не найден.";

PlayerSpellsLoadouts = { list = {}, activeId = 0, max = 10 };
local incoming;

local function Send(...)
	if Comm_Send then
		Comm_Send(...);
	end
end

function PlayerSpellsLoadouts.Request()
	Send("TLOAD_GET");
end

local function FindLoadout(id)
	for _, loadout in ipairs(PlayerSpellsLoadouts.list) do
		if loadout.id == id then
			return loadout;
		end
	end
end

StaticPopupDialogs["TALENT_LOADOUT_NAME"] = {
	text = TALENT_LOADOUT_NAME_PROMPT,
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 24,
	OnShow = function(self)
		local data = self.data;
		self.editBox:SetText(data and data.name or "");
		self.editBox:HighlightText();
		self.editBox:SetFocus();
	end,
	OnAccept = function(self, data)
		local name = self.editBox:GetText();
		if not name or name == "" then
			return;
		end
		if data and data.rename then
			Send("TLOAD_RENAME", data.id, name);
		else
			Send("TLOAD_SAVE", 0, name);
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent();
		StaticPopupDialogs["TALENT_LOADOUT_NAME"].OnAccept(parent, parent.data);
		parent:Hide();
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

StaticPopupDialogs["TALENT_LOADOUT_APPLY"] = {
	text = TALENT_LOADOUT_APPLY_CONFIRM,
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self, data)
		Send("TLOAD_APPLY", data.id);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

StaticPopupDialogs["TALENT_LOADOUT_DELETE"] = {
	text = TALENT_LOADOUT_DELETE_CONFIRM,
	button1 = DELETE or YES,
	button2 = CANCEL,
	OnAccept = function(self, data)
		Send("TLOAD_DEL", data.id);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	showAlert = 1,
};

-- наборы только у активной специализации игрока (не у питомца и не у просматриваемой второй)
local function CanUse(talents)
	return not talents.showPet and talents.talentGroup == GetActiveTalentGroup(false, false);
end

function PlayerSpellsLoadouts.SetupDropdown(talents, dropdown)
	-- список внизу окна - меню вверх (если menuPoint из XML не подхватился)
	if dropdown.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
		dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2));
	end
	dropdown:SetupMenu(function(owner, rootDescription)
		if not CanUse(talents) then
			rootDescription:CreateTitle(TALENT_LOADOUT_OTHER_SPEC);
			return;
		end
		rootDescription:CreateTitle(TALENT_LOADOUT_LABEL);
		for _, loadout in ipairs(PlayerSpellsLoadouts.list) do
			rootDescription:CreateRadio(loadout.name, function()
				return loadout.id == PlayerSpellsLoadouts.activeId;
			end, function()
				if loadout.id ~= PlayerSpellsLoadouts.activeId then
					StaticPopup_Show("TALENT_LOADOUT_APPLY", loadout.name, nil, loadout);
				end
			end);
		end

		rootDescription:CreateDivider();
		local newButton = rootDescription:CreateButton(TALENT_LOADOUT_NEW, function()
			StaticPopup_Show("TALENT_LOADOUT_NAME", nil, nil, nil);
		end);
		if newButton.SetEnabled then
			newButton:SetEnabled(#PlayerSpellsLoadouts.list < PlayerSpellsLoadouts.max);
		end

		local active = FindLoadout(PlayerSpellsLoadouts.activeId);
		if active then
			rootDescription:CreateButton(TALENT_LOADOUT_OVERWRITE:format(active.name), function()
				Send("TLOAD_SAVE", active.id, active.name);
			end);
			rootDescription:CreateButton(TALENT_LOADOUT_RENAME:format(active.name), function()
				StaticPopup_Show("TALENT_LOADOUT_NAME", nil, nil, { id = active.id, name = active.name, rename = true });
			end);
			rootDescription:CreateButton(TALENT_LOADOUT_DELETE:format(active.name), function()
				StaticPopup_Show("TALENT_LOADOUT_DELETE", active.name, nil, active);
			end);
		end
	end);
end

function PlayerSpellsLoadouts.UpdateDropdown(talents)
	local dropdown = talents.Bar and talents.Bar.LoadoutDropdown;
	if not dropdown then
		return;
	end
	local canUse = CanUse(talents);
	dropdown:SetEnabled(canUse);
	if dropdown.GenerateMenu then
		dropdown:GenerateMenu();
	end
	local active = canUse and FindLoadout(PlayerSpellsLoadouts.activeId);
	if dropdown.OverrideText then
		dropdown:OverrideText(active and active.name or (canUse and TALENT_LOADOUT_NONE or TALENT_LOADOUT_LABEL));
	elseif dropdown.SetText then
		dropdown:SetText(active and active.name or TALENT_LOADOUT_NONE);
	end
end

---------------------------------------------------------------------------
-- сервер
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register("TLOAD", function(id, name)
		incoming = incoming or {};
		table.insert(incoming, { id = tonumber(id) or 0, name = name or "" });
	end);

	Comm_Register("TLOAD_END", function(activeId, max)
		PlayerSpellsLoadouts.list = incoming or {};
		incoming = nil;
		PlayerSpellsLoadouts.activeId = tonumber(activeId) or 0;
		PlayerSpellsLoadouts.max = tonumber(max) or 10;
		if PlayerSpellsTalentsFrame then
			PlayerSpellsLoadouts.UpdateDropdown(PlayerSpellsTalentsFrame);
		end
	end);

	Comm_Register("TLOAD_RESULT", function(ok, code)
		local text = code and _G[code] or code;
		if text and text ~= "" then
			if ok == "1" then
				UIErrorsFrame:AddMessage(text, 1.0, 0.82, 0.0, 1.0);
			else
				UIErrorsFrame:AddMessage(text, 1.0, 0.1, 0.1, 1.0);
			end
		end
	end);
end

-- другая специализация - свои наборы
local watcher = CreateFrame("Frame");
watcher:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
watcher:RegisterEvent("PLAYER_LOGIN");
watcher:SetScript("OnEvent", function()
	PlayerSpellsLoadouts.Request();
end);
