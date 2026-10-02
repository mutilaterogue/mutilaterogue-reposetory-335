-- Interface options: "Pings" category (retail Settings -> Pings) for 3.3.5 - the tutorial, the options and the
-- key bindings of the ping system right in the panel. Options are CVars (config.wtf):
--   pingEnabled (receive pings), pingSound, pingChat (the chat line).

local function S(key)
	return _G[key] or key;
end

local function RegisterOption(name, default)
	if GetCVar(name) == nil and RegisterCVar then
		pcall(RegisterCVar, name, default);
	end
end

RegisterOption("pingEnabled", "1");
RegisterOption("pingSound", "1");
RegisterOption("pingChat", "1");
RegisterOption("pingTutorialSeen", "0");

function Ping_IsOptionOn(name)
	return GetCVar(name) ~= "0";
end

local TUTORIAL_TEXT = "Метки помогают общаться с группой без чата.\n\n"
	.. "|cffffd100Колесо меток:|r зажмите клавишу колеса, наведите курсор на нужный сектор и отпустите. "
	.. "Метка появится там, куда указывал курсор: на земле, на здании или на вашей цели.\n\n"
	.. "|cffffd100Быстрая метка:|r коротко нажмите клавишу колеса - по врагу ставится «В атаку», иначе «Внимание».\n\n"
	.. "|cffffd100Отдельные клавиши:|r каждую метку можно поставить своей клавишей, без колеса.\n\n"
	.. "Метки видит только ваша группа. Если точка за пределами экрана, стрелка у центра экрана показывает направление.";

---------------------------------------------------------------------------
-- tutorial window
---------------------------------------------------------------------------
local tutorial;

function Ping_ShowTutorial()
	if not tutorial then
		tutorial = CreateFrame("Frame", "PingTutorialFrame", UIParent);
		tutorial:SetWidth(420);
		tutorial:SetHeight(330);
		tutorial:SetPoint("CENTER", 0, 60);
		tutorial:SetFrameStrata("DIALOG");
		tutorial:EnableMouse(true);
		tutorial:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		});
		local title = tutorial:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
		title:SetPoint("TOP", 0, -22);
		title:SetText(S("BINDING_HEADER_PING_SYSTEM"));
		local wheel = tutorial:CreateTexture(nil, "ARTWORK");
		wheel:SetPoint("TOP", 0, -48);
		wheel:SetAtlas("Radial_Wheel_BG", false);
		wheel:SetWidth(90);
		wheel:SetHeight(90);
		local frame = tutorial:CreateTexture(nil, "OVERLAY");
		frame:SetAllPoints(wheel);
		frame:SetAtlas("Radial_Wheel_Frame_Count_4", false);
		local text = tutorial:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		text:SetPoint("TOPLEFT", 24, -146);
		text:SetPoint("RIGHT", -24, 0);
		text:SetJustifyH("LEFT");
		text:SetText(TUTORIAL_TEXT);
		local close = CreateFrame("Button", nil, tutorial, "UIPanelButtonTemplate");
		close:SetWidth(120);
		close:SetHeight(22);
		close:SetPoint("BOTTOM", 0, 18);
		close:SetText(OKAY);
		close:SetScript("OnClick", function() tutorial:Hide(); end);
	end
	SetCVar("pingTutorialSeen", "1");
	tutorial:Show();
end

---------------------------------------------------------------------------
-- options panel
---------------------------------------------------------------------------
local BINDINGS = { "TOGGLEPINGLISTENER", "PINGATTACK", "PINGWARNING", "PINGONMYWAY", "PINGASSIST" };
local panel = CreateFrame("Frame", "InterfaceOptionsPingPanel", UIParent);
panel.name = S("BINDING_HEADER_PING_SYSTEM");
panel:Hide();

local waitingButton;	-- the binding button waiting for a key

local function BindingKeyText(action)
	local key1, key2 = GetBindingKey(action);
	if not key1 then
		return NOT_BOUND;
	end
	local text = GetBindingText(key1, "KEY_");
	if key2 then
		text = text .. ", " .. GetBindingText(key2, "KEY_");
	end
	return text;
end

local function UpdateBindingButtons()
	for _, button in ipairs(panel.bindButtons) do
		if button == waitingButton then
			button:SetText("|cff00ff00" .. S("BIND_KEY_TO_COMMAND"):gsub("%%s", "") .. "|r");
		else
			button:SetText(BindingKeyText(button.action));
		end
	end
end

local function StopWaiting()
	waitingButton = nil;
	panel:EnableKeyboard(false);
	UpdateBindingButtons();
end

local function OnBindingKey(self, key)
	if not waitingButton then
		return;
	end
	if key == "ESCAPE" then
		StopWaiting();
		return;
	end
	-- modifiers alone are not keys
	if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
		return;
	end
	if IsAltKeyDown() then key = "ALT-" .. key; end
	if IsControlKeyDown() then key = "CTRL-" .. key; end
	if IsShiftKeyDown() then key = "SHIFT-" .. key; end
	local action = waitingButton.action;
	-- one key per action: the old ones go
	local old1, old2 = GetBindingKey(action);
	if old1 then SetBinding(old1); end
	if old2 then SetBinding(old2); end
	SetBinding(key, action);
	SaveBindings(GetCurrentBindingSet());
	StopWaiting();
end

local function MouseKey(button)
	if button == "LeftButton" or button == "RightButton" then
		return nil;
	end
	if button == "MiddleButton" then
		return "BUTTON3";
	end
	local n = button:match("Button(%d+)");
	return n and ("BUTTON" .. n) or nil;
end

local function CreateCheck(label, cvar, anchor, offsetY)
	local check = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate");
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY);
	local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	text:SetPoint("LEFT", check, "RIGHT", 2, 1);
	text:SetText(label);
	check:SetScript("OnShow", function(self) self:SetChecked(Ping_IsOptionOn(cvar)); end);
	check:SetScript("OnClick", function(self) SetCVar(cvar, self:GetChecked() and "1" or "0"); end);
	return check;
end

local function BuildPanel()
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOPLEFT", 16, -16);
	title:SetText(panel.name);

	local tutorialButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
	tutorialButton:SetWidth(160);
	tutorialButton:SetHeight(22);
	tutorialButton:SetPoint("TOPRIGHT", -16, -14);
	tutorialButton:SetText(S("TUTORIAL_TITLE"));
	tutorialButton:SetScript("OnClick", Ping_ShowTutorial);

	local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10);
	description:SetPoint("RIGHT", panel, "RIGHT", -16, 0);
	description:SetJustifyH("LEFT");
	description:SetText(TUTORIAL_TEXT);

	local enable = CreateCheck("Показывать метки группы", "pingEnabled", description, -12);
	local sound = CreateCheck("Звук меток", "pingSound", enable, -4);
	local chat = CreateCheck("Сообщение в чате", "pingChat", sound, -4);

	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	header:SetPoint("TOPLEFT", chat, "BOTTOMLEFT", 0, -16);
	header:SetText(S("KEY_BINDINGS"));

	panel.bindButtons = {};
	local previous = header;
	for i, action in ipairs(BINDINGS) do
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
		label:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -12 or -10);
		label:SetWidth(200);
		label:SetJustifyH("LEFT");
		label:SetText(S("BINDING_NAME_" .. action));

		local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
		button:SetWidth(180);
		button:SetHeight(22);
		button:SetPoint("LEFT", label, "RIGHT", 10, 0);
		button.action = action;
		button:RegisterForClicks("AnyUp");
		button:SetScript("OnClick", function(self, mouse)
			if waitingButton == self then
				-- a mouse button while waiting: bind it
				local key = MouseKey(mouse);
				if key then
					OnBindingKey(panel, key);
				elseif mouse == "RightButton" then
					StopWaiting();
				end
				return;
			end
			if mouse == "RightButton" then
				-- right click: unbind
				local old1, old2 = GetBindingKey(self.action);
				if old1 then SetBinding(old1); end
				if old2 then SetBinding(old2); end
				SaveBindings(GetCurrentBindingSet());
				UpdateBindingButtons();
				return;
			end
			waitingButton = self;
			panel:EnableKeyboard(true);
			UpdateBindingButtons();
		end);
		table.insert(panel.bindButtons, button);
		previous = label;
	end

	local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
	hint:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -14);
	hint:SetText("ЛКМ - назначить клавишу, ПКМ - снять. Esc - отмена.");
end

panel:SetScript("OnKeyDown", OnBindingKey);
panel:SetScript("OnShow", function(self)
	if not self.built then
		self.built = true;
		BuildPanel();
	end
	UpdateBindingButtons();
end);
panel:SetScript("OnHide", StopWaiting);
panel.okay = StopWaiting;
panel.cancel = StopWaiting;
panel.default = function()
	SetCVar("pingEnabled", "1");
	SetCVar("pingSound", "1");
	SetCVar("pingChat", "1");
end;

InterfaceOptions_AddCategory(panel);

-- the tutorial once, on the first login with the ping system
local tutorialLoader = CreateFrame("Frame");
tutorialLoader:RegisterEvent("PLAYER_ENTERING_WORLD");
tutorialLoader:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD");
	if GetCVar("pingTutorialSeen") ~= "1" then
		Ping_ShowTutorial();
	end
end);
