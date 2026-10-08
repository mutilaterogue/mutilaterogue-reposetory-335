--------------------------------------------------------------------------------
-- Микрокнопки на атласе Interface/HUD/UIMicroMenu2x (через AtlasHelper)
--------------------------------------------------------------------------------

local MICRO_PREFIX = "UI-HUD-MicroMenu-";

-- старое имя из LoadMicroButtonTextures -> ключ в атласе
local MICRO_ATLAS = {
	Spellbook   = "SpellbookAbilities",
	Talents     = "SpecTalents",
	Achievement = "Achievements",
	Quest       = "Questlog",
	Socials     = "GuildCommunities",
	Guild       = "GuildCommunities",
	LFG         = "Groupfinder",
	EJ          = "AdventureGuide",
	Collections = "Collections",
	MainMenu    = "GameMenu",
	Help        = "Shop", -- отдельной иконки Help в атласе нет
};

local function Atlas(tex, name)
	if ( tex ) then
		SetAtlas(tex, MICRO_PREFIX..name);
	end
end

---------------------------------------------------------------- фон кнопки ---
local function MicroButton_UpdateBackground(self)
	if ( self.Background ) then
		if ( self.microPushed ) then
			Atlas(self.Background, "ButtonBG-Down");
		else
			Atlas(self.Background, "ButtonBG-Up");
		end
	end

	local hl = self:GetHighlightTexture();
	if ( hl ) then
		hl:SetAlpha(self.microPushed and 0 or 1);
	end
	if ( self.HoverGlow ) then
		Atlas(self.HoverGlow, "Highlightalert");
	end
end

local function MicroButton_OnSetButtonState(self, state, locked)
	self.microLocked = (state == "PUSHED" and locked) and true or nil;
	self.microPushed = (state == "PUSHED") and true or nil;
	MicroButton_UpdateBackground(self);
end

function MicroButton_SetupBackground(self)
	if ( self.Background ) then
		return;
	end
	local bg = self:CreateTexture(nil, "BACKGROUND");
	bg:SetAllPoints(self);
	self.Background = bg;
	local glow = self:CreateTexture(nil, "HIGHLIGHT");
	glow:SetAllPoints(self);
	glow:SetBlendMode("ADD");
	Atlas(glow, "Highlightalert");
	self.HoverGlow = glow;
	Atlas(bg, "ButtonBG-Up");

	hooksecurefunc(self, "SetButtonState", MicroButton_OnSetButtonState);
	self:HookScript("OnMouseDown", function(btn)
		if ( btn:IsEnabled() == 1 ) then
			btn.microPushed = true;
			MicroButton_UpdateBackground(btn);
		end
	end);
	self:HookScript("OnMouseUp", function(btn)
		if ( not btn.microLocked ) then
			btn.microPushed = nil;
			MicroButton_UpdateBackground(btn);
		end
	end);
end

function MicroButton_SetHighlightAtlas(self, name, blend)
	self:SetHighlightTexture("Interface\\Buttons\\WHITE8X8");
	local hl = self:GetHighlightTexture();
	Atlas(hl, name);
	hl:SetBlendMode(blend or "BLEND");
end

------------------------------------------------------------ обычные кнопки ---
function LoadMicroButtonTextures(self, name)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	self:RegisterEvent("UPDATE_BINDINGS");

	local key = MICRO_ATLAS[name];
	if ( not key ) then
		-- неизвестная кнопка: старые текстуры
		local prefix = "Interface\\Buttons\\UI-MicroButton-";
		self:SetNormalTexture(prefix..name.."-Up");
		self:SetPushedTexture(prefix..name.."-Down");
		self:SetDisabledTexture(prefix..name.."-Disabled");
		self:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight");
		return;
	end

	local placeholder = "Interface\\Buttons\\WHITE8X8";
	self:SetNormalTexture(placeholder);
	self:SetPushedTexture(placeholder);
	self:SetDisabledTexture(placeholder);

	Atlas(self:GetNormalTexture(),   key.."-Up");
	Atlas(self:GetPushedTexture(),   key.."-Down");
	Atlas(self:GetDisabledTexture(), key.."-Disabled");
	MicroButton_SetHighlightAtlas(self, key.."-Mouseover");

	MicroButton_SetupBackground(self);
end

function MicroButtonTooltipText(text, action)
	if ( GetBindingKey(action) ) then
		return text.." "..NORMAL_FONT_COLOR_CODE.."("..GetBindingText(GetBindingKey(action), "KEY_")..")"..FONT_COLOR_CODE_CLOSE;
	else
		return text;
	end
end

function UpdateMicroButtons()
	local playerLevel = UnitLevel("player");
	if ( CharacterFrame:IsShown() ) then
		CharacterMicroButton:SetButtonState("PUSHED", 1);
		CharacterMicroButton_SetPushed();
	else
		CharacterMicroButton:SetButtonState("NORMAL");
		CharacterMicroButton_SetNormal();
	end

	if ( SpellBookFrame:IsShown() ) then
		SpellbookMicroButton:SetButtonState("PUSHED", 1);
	else
		SpellbookMicroButton:SetButtonState("NORMAL");
	end

	if ( PlayerTalentFrame and PlayerTalentFrame:IsShown() ) then
		TalentMicroButton:SetButtonState("PUSHED", 1);
	else
		if ( playerLevel < TalentMicroButton.minLevel ) then
			TalentMicroButton:Disable();
		else
			TalentMicroButton:Enable();
			TalentMicroButton:SetButtonState("NORMAL");
		end
	end

	if ( QuestLogFrame:IsShown() ) then
		QuestLogMicroButton:SetButtonState("PUSHED", 1);
	else
		QuestLogMicroButton:SetButtonState("NORMAL");
	end

	if ( ( GameMenuFrame:IsShown() )
		or ( InterfaceOptionsFrame:IsShown())
		or ( KeyBindingFrame and KeyBindingFrame:IsShown())
		or ( MacroFrame and MacroFrame:IsShown()) ) then
		MainMenuMicroButton_SetPushed();
	else
		MainMenuMicroButton_SetNormal();
	end

	if ( PVPParentFrame:IsShown() and (not PVPFrame_IsJustBG())) then
		PVPMicroButton:SetButtonState("PUSHED", 1);
		PVPMicroButton_SetPushed();
	else
		if ( playerLevel < PVPMicroButton.minLevel ) then
			PVPMicroButton:Disable();
		else
			PVPMicroButton:Enable();
			PVPMicroButton:SetButtonState("NORMAL");
			PVPMicroButton_SetNormal();
		end
	end

	if ( FriendsFrame:IsShown() ) then
		SocialsMicroButton:SetButtonState("PUSHED", 1);
	else
		SocialsMicroButton:SetButtonState("NORMAL");
	end

	if ( GuildMicroButton ) then
		if ( CommunitiesFrame and CommunitiesFrame:IsShown() ) then
			GuildMicroButton:SetButtonState("PUSHED", 1);
		else
			GuildMicroButton:SetButtonState("NORMAL");
		end
	end

	if ( LFDParentFrame:IsShown() ) then
		LFDMicroButton:SetButtonState("PUSHED", 1);
	else
		if ( playerLevel < LFDMicroButton.minLevel ) then
			LFDMicroButton:Disable();
		else
			LFDMicroButton:Enable();
			LFDMicroButton:SetButtonState("NORMAL");
		end
	end

	if ( HelpFrame:IsShown() ) then
		--HelpMicroButton:SetButtonState("PUSHED", 1);
	else
		--HelpMicroButton:SetButtonState("NORMAL");
	end

	if ( AchievementFrame and AchievementFrame:IsShown() ) then
		AchievementMicroButton:SetButtonState("PUSHED", 1);
	else
		if ( HasCompletedAnyAchievement() and CanShowAchievementUI() ) then
			AchievementMicroButton:Enable();
			AchievementMicroButton:SetButtonState("NORMAL");
		else
			AchievementMicroButton:Disable();
		end
	end

	if ( CollectionsMicroButton ) then
		if ( CollectionsJournal and CollectionsJournal:IsShown() ) then
			CollectionsMicroButton:SetButtonState("PUSHED", 1);
		else
			CollectionsMicroButton:SetButtonState("NORMAL");
		end
	end

	if ( EncounterJournal and EncounterJournal:IsShown() ) then
		EJMicroButton:SetButtonState("PUSHED", 1);
	else
		EJMicroButton:SetButtonState("NORMAL");
	end

	-- Keyring microbutton
	if ( IsBagOpen(KEYRING_CONTAINER) ) then
		KeyRingButton:SetButtonState("PUSHED", 1);
	else
		KeyRingButton:SetButtonState("NORMAL");
	end
end

function AchievementMicroButton_OnEvent(self, event, ...)
	if ( event == "UPDATE_BINDINGS" ) then
		AchievementMicroButton.tooltipText = MicroButtonTooltipText(ACHIEVEMENT_BUTTON, "TOGGLEACHIEVEMENT");
	else
		UpdateMicroButtons();
	end
end

--------------------------------------------------------------- персонаж ---
function CharacterMicroButton_OnLoad(self)
	MicroButton_SetupBackground(self);

	-- портрет под тенью
	MicroButtonPortrait:SetDrawLayer("ARTWORK");
	MicroButtonPortrait:ClearAllPoints();
	MicroButtonPortrait:SetPoint("CENTER", self, "CENTER", 0, 0);
	MicroButtonPortrait:SetWidth(self:GetWidth() - 8);
	MicroButtonPortrait:SetHeight(self:GetHeight() - 10);

	local shadow = self:CreateTexture(nil, "OVERLAY");
	shadow:SetAllPoints(self);
	Atlas(shadow, "Portrait-Shadow");
	self.PortraitShadow = shadow;

	self:RegisterEvent("UNIT_PORTRAIT_UPDATE");
	self:RegisterEvent("UPDATE_BINDINGS");
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self.tooltipText = MicroButtonTooltipText(CHARACTER_BUTTON, "TOGGLECHARACTER0");
	self.newbieText = NEWBIE_TOOLTIP_CHARACTER;
end

function CharacterMicroButton_OnEvent(self, event, ...)
	if ( event == "UNIT_PORTRAIT_UPDATE" ) then
		local unit = ...;
		if ( unit == "player" ) then
			SetPortraitTexture(MicroButtonPortrait, unit);
		end
		return;
	elseif ( event == "PLAYER_ENTERING_WORLD" ) then
		SetPortraitTexture(MicroButtonPortrait, "player");
	elseif ( event == "UPDATE_BINDINGS" ) then
		self.tooltipText = MicroButtonTooltipText(CHARACTER_BUTTON, "TOGGLECHARACTER0");
	end
end

function CharacterMicroButton_SetPushed()
	MicroButtonPortrait:SetTexCoord(0.2666, 0.8666, 0, 0.8333);
	MicroButtonPortrait:SetAlpha(0.5);
	Atlas(CharacterMicroButton.PortraitShadow, "Portrait-Down");
	CharacterMicroButton.microPushed = true;
	MicroButton_UpdateBackground(CharacterMicroButton);
end

function CharacterMicroButton_SetNormal()
	MicroButtonPortrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9);
	MicroButtonPortrait:SetAlpha(1.0);
	Atlas(CharacterMicroButton.PortraitShadow, "Portrait-Shadow");
	CharacterMicroButton.microPushed = nil;
	MicroButton_UpdateBackground(CharacterMicroButton);
end

------------------------------------------------------------ главное меню ---
function MainMenuMicroButton_SetPushed()
	MainMenuMicroButton:SetButtonState("PUSHED", 1);
	MainMenuBarPerformanceBar:ClearAllPoints();
	MainMenuBarPerformanceBar:SetPoint("BOTTOM", MainMenuMicroButton, "BOTTOM", 3, 0);
end

function MainMenuMicroButton_SetNormal()
	MainMenuMicroButton:SetButtonState("NORMAL");
	MainMenuBarPerformanceBar:ClearAllPoints();
	MainMenuBarPerformanceBar:SetPoint("BOTTOM", MainMenuMicroButton, "BOTTOM", 3, 0);
end

--------------------------------------------------------------------- PvP ---
-- PVPMicroButton_SetPushed/SetNormal объявлены в PVPFrame.lua,
-- поэтому подправляем их после загрузки
local PVP_ICON_SIZE = 30;

local function PVPMicro_PlaceIcon(pushed)
	local t = PVPMicroButton and PVPMicroButton.texture;
	if ( not t ) then
		return;
	end
	t:ClearAllPoints();
	t:SetWidth(PVP_ICON_SIZE);
	t:SetHeight(PVP_ICON_SIZE);
	if ( pushed ) then
		t:SetPoint("CENTER", PVPMicroButton, "CENTER", 7, -7);
	else
		t:SetPoint("CENTER", PVPMicroButton, "CENTER", 6, -6);
	end
	PVPMicroButton.microPushed = pushed or nil;
	MicroButton_UpdateBackground(PVPMicroButton);
end

function PVPMicroButton_SetupAtlas(self)
	self:SetNormalTexture("");
	self:SetPushedTexture("");
	MicroButton_SetupBackground(self);
	MicroButton_SetHighlightAtlas(self, "Highlightalert", "ADD");
	PVPMicro_PlaceIcon(false);
end

local pvpFix = CreateFrame("Frame");
pvpFix:RegisterEvent("PLAYER_LOGIN");
pvpFix:SetScript("OnEvent", function(self)
	if ( PVPMicroButton_SetPushed ) then
		hooksecurefunc("PVPMicroButton_SetPushed", function() PVPMicro_PlaceIcon(true); end);
	end
	if ( PVPMicroButton_SetNormal ) then
		hooksecurefunc("PVPMicroButton_SetNormal", function() PVPMicro_PlaceIcon(false); end);
	end
	PVPMicro_PlaceIcon(PVPMicroButton:GetButtonState() == "PUSHED");
	self:UnregisterAllEvents();
end);

----------------------------------------------------------------- таланты ---
function TalentMicroButton_OnEvent(self, event, ...)
	if ( event == "PLAYER_LEVEL_UP" ) then
		local level = ...;
		UpdateMicroButtons();
		if ( not CharacterFrame:IsShown() and level >= SHOW_TALENT_LEVEL) then
			SetButtonPulse(self, 60, 1);
		end
	elseif ( event == "UNIT_LEVEL" or event == "PLAYER_ENTERING_WORLD" ) then
		UpdateMicroButtons();
	elseif ( event == "UPDATE_BINDINGS" ) then
		self.tooltipText =  MicroButtonTooltipText(TALENTS_BUTTON, "TOGGLETALENTS");
	end
end

------------------------------------------------ позиция: правый нижний угол ---
MICRO_MENU_OFFSET_X = 0;   -- отступ от правого края
MICRO_MENU_OFFSET_Y = 2;   -- отступ от низа
local MICRO_SPACING = -3;  -- тот же x, что в якорях кнопок

local MICRO_ORDER = {
	"CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
	"AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton", "GuildMicroButton",
	"PVPMicroButton", "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton",
	"MainMenuMicroButton",
};

-- ширина по размерам кнопок, не зависит от текущей раскладки
local function MicroMenu_GetWidth()
	local width, count = 0, 0;
	for _, name in ipairs(MICRO_ORDER) do
		local b = _G[name];
		if ( b and b:IsShown() ) then
			width = width + b:GetWidth();
			count = count + 1;
		end
	end
	if ( count > 1 ) then
		width = width + MICRO_SPACING * (count - 1);
	end
	return width;
end

local function PlayerHasVehicleUI()
	return UnitInVehicle("player") and UnitHasVehicleUI("player");
end

function MicroMenu_PlaceBottomRight()
	-- with or without a vehicle: the same place, every button shown (Collections too)
	local level = MainMenuBarArtFrame:GetFrameLevel() + 2;
	for _, name in ipairs(MICRO_ORDER) do
		local b = _G[name];
		if ( b ) then
			b:SetParent(UIParent);
			b:SetFrameStrata("MEDIUM");
			b:SetFrameLevel(level);
			b:Show();
		end
	end

	-- the menu frame grows to the left (BOTTOMRIGHT anchor) for the real number of buttons
	MicroMenuFrame:SetWidth(MicroMenu_GetWidth());

	-- one row: Socials after QuestLog (the 3.3.5 vehicle layout put it under Character)
	CharacterMicroButton:ClearAllPoints();
	CharacterMicroButton:SetPoint("LEFT", MicroMenuFrame, "LEFT");
	SocialsMicroButton:ClearAllPoints();
	SocialsMicroButton:SetPoint("BOTTOMLEFT", QuestLogMicroButton, "BOTTOMRIGHT", MICRO_SPACING, 0);
end

local microPos = CreateFrame("Frame");
microPos:RegisterEvent("PLAYER_ENTERING_WORLD");
microPos:RegisterEvent("UNIT_EXITED_VEHICLE");
microPos:SetScript("OnEvent", function(self, event, unit)
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		if ( not self.hooked ) then
			-- выход из техники: панель прячется, забираем кнопки
			if ( VehicleMenuBar ) then
				VehicleMenuBar:HookScript("OnHide", function()
					MicroMenu_PlaceBottomRight();
					UpdateMicroButtons();
				end);
			end
			-- если Blizzard сама вернёт кнопки на старую панель
			if ( VehicleMenuBar_MoveMicroButtons ) then
				hooksecurefunc("VehicleMenuBar_MoveMicroButtons", function()
					MicroMenu_PlaceBottomRight();
				end);
			end
			self.hooked = true;
		end
		MicroMenu_PlaceBottomRight();
	elseif ( unit == "player" ) then
		MicroMenu_PlaceBottomRight();
	end
end);