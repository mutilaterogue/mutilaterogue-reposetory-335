-- Interface options: the ping system (retail Settings -> "Система сигналов") for 3.3.5, with the retail
-- "О системе отметок" window (4 cards). Options are CVars (config.wtf):
--   pingEnabled (receive pings), pingMode (0 hold the wheel key, 1 toggle), pingSound, pingChat, pingTutorialSeen.

local function S(key)
	return _G[key] or key;
end

local function RegisterOption(name, default)
	if GetCVar(name) == nil and RegisterCVar then
		pcall(RegisterCVar, name, default);
	end
end

RegisterOption("pingEnabled", "1");
RegisterOption("pingMode", "0");
RegisterOption("pingSound", "1");
RegisterOption("pingChat", "1");
RegisterOption("pingTutorialSeen", "0");

function Ping_IsOptionOn(name)
	return GetCVar(name) ~= "0";
end

local HIGHLIGHT = "|cff3fc7eb";	-- the blue of the retail tutorial

---------------------------------------------------------------------------
-- "О системе отметок" (retail PingSystemTutorial: 4 cards)
---------------------------------------------------------------------------
local tutorial;

-- retail layout: the art (Ping_Tutorial, 945x760, Interface/RadialWheel/UIPingSystemTutorial) holds the four
-- pictures and the macro box; the texts are over it (positions as in retail)
local TUTORIAL_TOP = 22;	-- the title bar of the frame above the art

local function TutorialText(parent, text, x, y, width, font, justify)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightLarge");
	label:SetPoint(justify == "CENTER" and "TOP" or "TOPLEFT", parent, "TOPLEFT", x, -(TUTORIAL_TOP + y));
	if width then
		label:SetWidth(width);
	end
	label:SetJustifyH(justify or "LEFT");
	label:SetText(text);
	return label;
end

function Ping_ShowTutorial()
	if not tutorial then
		tutorial = CreateFrame("Frame", "PingSystemTutorial", UIParent, "RetailPortraitFrameTemplate");
		tutorial:SetWidth(945);
		tutorial:SetHeight(760 + TUTORIAL_TOP);
		tutorial:SetPoint("CENTER", 0, 0);
		tutorial:SetFrameStrata("DIALOG");
		tutorial:EnableMouse(true);
		tutorial:SetMovable(true);
		tutorial:SetClampedToScreen(true);
		tutorial:RegisterForDrag("LeftButton");
		tutorial:SetScript("OnDragStart", tutorial.StartMoving);
		tutorial:SetScript("OnDragStop", tutorial.StopMovingOrSizing);
		if tutorial.TitleContainer and tutorial.TitleContainer.TitleText then
			tutorial.TitleContainer.TitleText:SetText("Система отметок");
		end
		if tutorial.PortraitContainer then
			tutorial.PortraitContainer:Hide();
		end

		local art = tutorial:CreateTexture(nil, "ARTWORK");
		art:SetPoint("TOPLEFT", tutorial, "TOPLEFT", 0, -TUTORIAL_TOP);
		art:SetAtlas("Ping_Tutorial", true);

		TutorialText(tutorial, HIGHLIGHT .. "Нажмите|r клавишу отметки, чтобы быстро поставить отметку.", 70, 50, 360);
		TutorialText(tutorial, HIGHLIGHT .. "Нажмите и удерживайте|r клавишу отметки, чтобы выбрать определенную отметку.", 513, 32, 360);
		TutorialText(tutorial, HIGHLIGHT .. "Размещайте отметку|r прямо на существах, персонажах и на вашей цели.", 70, 397, 360);
		TutorialText(tutorial, HIGHLIGHT .. "Создавайте макросы|r с отметками.", 513, 432, 360);

		-- the macro box of the art
		TutorialText(tutorial, "Наберите " .. HIGHLIGHT .. "/macro|r в чате", 695, 528, nil, "GameFontHighlightLarge", "CENTER");
		TutorialText(tutorial, "Макрос:", 695, 597, nil, "GameFontHighlightLarge", "CENTER");
		TutorialText(tutorial, "|cffffd100/отметка [@target] атака|r", 695, 628, nil, "GameFontHighlightLarge", "CENTER");
	end
	SetCVar("pingTutorialSeen", "1");
	tutorial:Show();
end

---------------------------------------------------------------------------
-- options panel (retail rows: the name on the left, the control on the right)
---------------------------------------------------------------------------
local BINDINGS = { "TOGGLEPINGLISTENER", "PINGATTACK", "PINGWARNING", "PINGONMYWAY", "PINGASSIST" };
local MODES = { "Удерживать для колеса", "Нажатие открывает колесо" };

local panel = CreateFrame("Frame", "InterfaceOptionsPingPanel", UIParent);
panel.name = "Система сигналов";
panel:Hide();

local controls = {};
local waitingButton;

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
	for _, button in ipairs(panel.bindButtons or {}) do
		if button == waitingButton then
			button:SetText("|cff00ff00...|r");
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

local function Bind(action, key)
	local old1, old2 = GetBindingKey(action);
	if old1 then SetBinding(old1); end
	if old2 then SetBinding(old2); end
	if key then
		SetBinding(key, action);
	end
	SaveBindings(GetCurrentBindingSet());
end

local function OnBindingKey(self, key)
	if not waitingButton then
		return;
	end
	if key == "ESCAPE" then
		StopWaiting();
		return;
	end
	if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
		return;
	end
	if IsAltKeyDown() then key = "ALT-" .. key; end
	if IsControlKeyDown() then key = "CTRL-" .. key; end
	if IsShiftKeyDown() then key = "SHIFT-" .. key; end
	Bind(waitingButton.action, key);
	StopWaiting();
end

local function MouseKey(button)
	if button == "MiddleButton" then
		return "BUTTON3";
	end
	local n = button:match("Button(%d+)");
	return n and ("BUTTON" .. n) or nil;
end

-- a row at y: the label at the left (indented - a sub option), the control at CONTROL_X
local CONTROL_X = 290;
local function Row(label, y, indent)
	local text = panel:CreateFontString(nil, "ARTWORK", indent and "GameFontNormalSmall" or "GameFontNormal");
	text:SetPoint("TOPLEFT", panel, "TOPLEFT", indent and 44 or 28, y);
	text:SetWidth(240);
	text:SetHeight(24);
	text:SetJustifyH("LEFT");
	text:SetText(label);
	return text;
end

local function PlaceControl(control, row, offsetX)
	control:SetPoint("TOP", row, "TOP", 0, 0);
	control:SetPoint("LEFT", panel, "LEFT", CONTROL_X + (offsetX or 0), 0);
end

local function Check(row, cvar)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate");
	check:SetWidth(26);
	check:SetHeight(26);
	PlaceControl(check, row);
	check.cvar = cvar;
	check:SetScript("OnClick", function(self)
		SetCVar(cvar, self:GetChecked() and "1" or "0");
		panel:Refresh();
	end);
	table.insert(controls, check);
	return check;
end

-- the retail stepper: [<] text [>]
local function Stepper(row, cvar, values)
	local frame = CreateFrame("Frame", nil, panel);
	frame:SetWidth(270);
	frame:SetHeight(24);
	PlaceControl(frame, row);
	local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	text:SetPoint("CENTER");
	local function Step(delta)
		local index = (tonumber(GetCVar(cvar)) or 0) + delta;
		index = math.max(0, math.min(#values - 1, index));
		SetCVar(cvar, tostring(index));
		panel:Refresh();
	end
	local left = CreateFrame("Button", nil, frame);
	left:SetWidth(24);
	left:SetHeight(24);
	left:SetPoint("LEFT");
	left:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up");
	left:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down");
	left:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled");
	left:SetScript("OnClick", function() Step(-1); end);
	local right = CreateFrame("Button", nil, frame);
	right:SetWidth(24);
	right:SetHeight(24);
	right:SetPoint("RIGHT");
	right:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up");
	right:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down");
	right:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled");
	right:SetScript("OnClick", function() Step(1); end);
	frame.Update = function()
		local index = tonumber(GetCVar(cvar)) or 0;
		text:SetText(values[index + 1] or "");
		if index > 0 then left:Enable(); else left:Disable(); end
		if index < #values - 1 then right:Enable(); else right:Disable(); end
	end;
	frame.left, frame.right = left, right;
	table.insert(controls, frame);
	return frame;
end

local function Button(text, width)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
	button:SetWidth(width);
	button:SetHeight(22);
	button:SetText(text);
	return button;
end

function panel:Refresh()
	local enabled = Ping_IsOptionOn("pingEnabled");
	for _, control in ipairs(controls) do
		if control.cvar then
			control:SetChecked(Ping_IsOptionOn(control.cvar));
			if control.cvar ~= "pingEnabled" then
				if enabled then control:Enable(); else control:Disable(); end
			end
		elseif control.Update then
			control.Update();
		end
	end
	UpdateBindingButtons();
end

local function BuildPanel()
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge");
	title:SetPoint("TOPLEFT", 16, -16);
	title:SetText(panel.name);

	local defaults = Button(DEFAULTS or "По умолчанию", 120);
	defaults:SetPoint("TOPRIGHT", -46, -16);
	defaults:SetScript("OnClick", function()
		panel.default();
		panel:Refresh();
	end);

	local info = CreateFrame("Button", nil, panel);
	info:SetWidth(26);
	info:SetHeight(26);
	info:SetPoint("LEFT", defaults, "RIGHT", 6, 0);
	info:SetNormalTexture("Interface\\Common\\help-i");
	info:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD");
	info:SetScript("OnClick", Ping_ShowTutorial);
	info:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText("О системе отметок");
		GameTooltip:Show();
	end);
	info:SetScript("OnLeave", GameTooltip_Hide);

	local line = panel:CreateTexture(nil, "ARTWORK");
	line:SetTexture(1, 1, 1, 0.15);
	line:SetHeight(1);
	line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8);
	line:SetPoint("RIGHT", panel, "RIGHT", -16, 0);

	local rowEnable = Row("Разрешить сигналы", -70);
	Check(rowEnable, "pingEnabled");

	local rowMode = Row("Режим сигналов", -102, true);
	Stepper(rowMode, "pingMode", MODES);

	local rowSound = Row("Звуки сигналов", -134, true);
	Check(rowSound, "pingSound");

	local rowChat = Row("Отображать сигналы в чате", -166);
	Check(rowChat, "pingChat");
	local chatSettings = Button("Настройки чата", 190);
	PlaceControl(chatSettings, rowChat, 40);
	chatSettings:SetScript("OnClick", function()
		if ChatConfigFrame then
			ShowUIPanel(ChatConfigFrame);
		end
	end);

	local keysButton = Button("Горячие клавиши сигналов", 200);
	keysButton:SetPoint("TOPLEFT", rowChat, "BOTTOMLEFT", 0, -14);

	-- the bindings (retail opens the key bindings at the ping section: here they are right below)
	panel.bindButtons = {};
	local previous = keysButton;
	for i, action in ipairs(BINDINGS) do
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
		label:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and 0 or 0, i == 1 and -12 or -8);
		label:SetWidth(230);
		label:SetHeight(22);
		label:SetJustifyH("LEFT");
		label:SetText(S("BINDING_NAME_" .. action));
		local button = Button("", 200);
		PlaceControl(button, label);
		button.action = action;
		button:RegisterForClicks("AnyUp");
		button:SetScript("OnClick", function(self, mouse)
			if waitingButton == self then
				local key = MouseKey(mouse);
				if key and mouse ~= "LeftButton" and mouse ~= "RightButton" then
					Bind(self.action, key);
				end
				StopWaiting();
				return;
			end
			if mouse == "RightButton" then
				Bind(self.action, nil);
				UpdateBindingButtons();
				return;
			end
			waitingButton = self;
			panel:EnableKeyboard(true);
			UpdateBindingButtons();
		end);
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(S("BINDING_NAME_" .. self.action));
			GameTooltip:AddLine("ЛКМ - назначить клавишу, ПКМ - снять, Esc - отмена.", 1, 1, 1, true);
			GameTooltip:Show();
		end);
		button:SetScript("OnLeave", GameTooltip_Hide);
		table.insert(panel.bindButtons, button);
		previous = label;
	end
	keysButton:SetScript("OnClick", function()
		-- the first binding without a key, else the wheel
		for _, button in ipairs(panel.bindButtons) do
			if not GetBindingKey(button.action) then
				button:Click("LeftButton");
				return;
			end
		end
		panel.bindButtons[1]:Click("LeftButton");
	end);
end

panel:SetScript("OnKeyDown", OnBindingKey);
panel:SetScript("OnShow", function(self)
	if not self.built then
		self.built = true;
		BuildPanel();
	end
	self:Refresh();
end);
panel:SetScript("OnHide", StopWaiting);
panel.okay = StopWaiting;
panel.cancel = StopWaiting;
panel.default = function()
	SetCVar("pingEnabled", "1");
	SetCVar("pingMode", "0");
	SetCVar("pingSound", "1");
	SetCVar("pingChat", "1");
end;

InterfaceOptions_AddCategory(panel);
