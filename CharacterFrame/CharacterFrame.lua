-- CharacterFrame: Cataclysm 4.3.4 -> 3.3.5a
-- Рамка RetailPortraitFrameTemplate, вкладки - TabSystem (TabSystem\TabSystemTemplates.xml).
-- Вкладки: Персонаж, Питомец, Репутация, Навыки, Валюта (Blizzard_TokenUI, грузится по требованию).

CHARACTERFRAME_SUBFRAMES = { "PaperDollFrame", "PetPaperDollFrame", "ReputationFrame", "SkillFrame", "TokenFrame" };
CHARACTERFRAME_EXPANDED_WIDTH = 540;

-- старые (384x512) панели 3.3.5 со своей графикой: ставим поверх новой рамки со сдвигом
CHARACTERFRAME_LEGACY_SUBFRAMES = { ReputationFrame = true, SkillFrame = true, TokenFrame = true, HonorFrame = true };
CHARACTERFRAME_LEGACY_X = -14;
CHARACTERFRAME_LEGACY_Y = 12;

UIPanelWindows["CharacterFrame"] = { area = "left", pushable = 3, whileDead = 1, xOffset = "15", yOffset = "0" };

local TAB_INFO = {
	{ frame = "PaperDollFrame",    text = CHARACTER },
	{ frame = "PetPaperDollFrame", text = PET },
	{ frame = "ReputationFrame",   text = REPUTATION_ABBR },
	{ frame = "SkillFrame",        text = SKILLS },
	{ frame = "TokenFrame",        text = CURRENCY },
};

local function GetSubFrame(frameName)
	if ( frameName == "TokenFrame" and not TokenFrame and TokenFrame_LoadUI ) then
		TokenFrame_LoadUI();
	end
	return _G[frameName];
end

function ToggleCharacter (tab)
	local subFrame = GetSubFrame(tab);
	if ( subFrame ) then
		if (not subFrame.hidden) then
			if ( CharacterFrame:IsShown() ) then
				if ( subFrame:IsShown() ) then
					HideUIPanel(CharacterFrame);
				else
					PlaySound("igCharacterInfoTab");
					CharacterFrame_ShowSubFrame(tab);
				end
			else
				ShowUIPanel(CharacterFrame);
				CharacterFrame_ShowSubFrame(tab);
			end
		end
	end
end

-- выбирает вкладку по имени подокна (через TabSystem)
function CharacterFrame_ShowSubFrame (frameName)
	local tabID = CharacterFrame.tabIDs and CharacterFrame.tabIDs[frameName];
	if ( tabID and CharacterFrame:GetTab() ~= tabID ) then
		CharacterFrame:SetTab(tabID);
	else
		CharacterFrame_UpdateSubFrames(frameName);
	end
end

local function SetLegacyMode(self, legacy)
	if ( self.NineSlice ) then
		self.NineSlice:SetShown(not legacy);
	end
	if ( self.Bg ) then
		self.Bg:SetShown(not legacy);
	end
	CharacterFrameInset:SetShown(not legacy);
end

function CharacterFrame_UpdateSubFrames (frameName)
	for index, value in ipairs(CHARACTERFRAME_SUBFRAMES) do
		local frame = _G[value];
		if ( frame and value ~= frameName ) then
			frame:Hide();
		end
	end
	local subFrame = GetSubFrame(frameName);
	if ( not subFrame ) then
		return;
	end
	local legacy = CHARACTERFRAME_LEGACY_SUBFRAMES[frameName];
	if ( legacy and not subFrame.characterFrameLegacyAnchored ) then
		subFrame.characterFrameLegacyAnchored = true;
		subFrame:ClearAllPoints();
		subFrame:SetSize(384, 512);
		subFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", CHARACTERFRAME_LEGACY_X, CHARACTERFRAME_LEGACY_Y);
	end
	SetLegacyMode(CharacterFrame, legacy);
	if ( legacy ) then
		CharacterFrameTitleText:SetText(UnitPVPName("player"));
	end
	subFrame:Show();
end

local function RelayoutTabs()
	CharacterFrame.TabSystem:MarkDirty();
end

function CharacterFrame_OnLoad (self)
	TabSystemOwnerMixin.OnLoad(self);
	self:SetTabSystem(self.TabSystem);

	self.Inset = CharacterFrameInset;
	CharacterFramePortrait = self.PortraitContainer.portrait;
	CharacterFrameTitleText = self.TitleContainer.TitleText;
	CharacterFrameTitleText:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);

	self.tabIDs = {};
	for index, info in ipairs(TAB_INFO) do
		local tabID = self:AddNamedTab(info.text);
		self.tabIDs[info.frame] = tabID;
		local frameName = info.frame;
		self:SetTabCallback(tabID, function()
			CharacterFrame_UpdateSubFrames(frameName);
		end);
		-- старые имена вкладок (MainMenuBar: CharacterFrameTab5, PetPaperDoll: CharacterFrameTab2)
		local button = self.TabSystem:GetTabButton(tabID);
		_G["CharacterFrameTab"..index] = button;
		button:SetID(index);
		button:HookScript("OnShow", RelayoutTabs);
		button:HookScript("OnHide", RelayoutTabs);
	end

	-- как в PlayerSpellsFrame/CollectionsJournal: подокна под рамкой, вкладки поверх
	if ( self.SetFrameLevelsFromBaseLevel ) then
		self:SetFrameLevelsFromBaseLevel(self:GetFrameLevel());
	end
	self.TabSystem:SetFrameLevel(self:GetFrameLevel() + 25);
	self:RegisterForDrag("LeftButton");

	self:RegisterEvent("UNIT_NAME_UPDATE");
	self:RegisterEvent("UNIT_PORTRAIT_UPDATE");
	self:RegisterEvent("PLAYER_PVP_RANK_CHANGED");
	self:RegisterEvent("PLAYER_TALENT_UPDATE");
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");

	SetTextStatusBarTextPrefix(PlayerFrameHealthBar, HEALTH);
	SetTextStatusBarTextPrefix(PlayerFrameManaBar, MANA);
	SetTextStatusBarTextPrefix(MainMenuExpBar, XP);
	TextStatusBar_UpdateTextString(MainMenuExpBar);

	self.TabSystem:SetTabVisuallySelected(self.tabIDs["PaperDollFrame"]);
	self.internalTabTracker.tabID = self.tabIDs["PaperDollFrame"];
end

function CharacterFrame_UpdatePortrait()
	if ( SetSpecializationTexturePortrait ) then
		SetSpecializationTexturePortrait();
	else
		SetPortraitTexture(CharacterFramePortrait, "player");
	end
end

function CharacterFrame_OnEvent (self, event, ...)
	if ( not self:IsShown() ) then
		return;
	end

	local arg1 = ...;
	if ( event == "UNIT_PORTRAIT_UPDATE" ) then
		if ( arg1 == "player" ) then
			CharacterFrame_UpdatePortrait();
		end
	elseif ( event == "UNIT_NAME_UPDATE" ) then
		if ( arg1 == "player" ) then
			CharacterNameText:SetText(UnitPVPName("player"));
			if ( not PetPaperDollFrame:IsShown() ) then
				CharacterFrameTitleText:SetText(UnitPVPName("player"));
			end
		end
	elseif ( event == "PLAYER_PVP_RANK_CHANGED" ) then
		CharacterNameText:SetText(UnitPVPName("player"));
		if ( not PetPaperDollFrame:IsShown() ) then
			CharacterFrameTitleText:SetText(UnitPVPName("player"));
		end
	elseif ( event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" ) then
		CharacterFrame_UpdatePortrait();
	end
end

function CharacterFrame_OnShow (self)
	PlaySound("igCharacterInfoOpen");
	CharacterFrame_UpdatePortrait();
	CharacterNameText:SetText(UnitPVPName("player"));
	CharacterFrameTitleText:SetText(UnitPVPName("player"));
	if ( PetPaperDollFrame_UpdateIsAvailable ) then
		PetPaperDollFrame_UpdateIsAvailable();
	end
	UpdateMicroButtons();
	PlayerFrameHealthBar.showNumeric = true;
	PlayerFrameManaBar.showNumeric = true;
	PlayerFrameAlternateManaBar.showNumeric = true;
	MainMenuExpBar.showNumeric = true;
	PetFrameHealthBar.showNumeric = true;
	PetFrameManaBar.showNumeric = true;
	ShowTextStatusBarText(PlayerFrameHealthBar);
	ShowTextStatusBarText(PlayerFrameManaBar);
	ShowTextStatusBarText(PlayerFrameAlternateManaBar);
	ShowTextStatusBarText(MainMenuExpBar);
	ShowTextStatusBarText(PetFrameHealthBar);
	ShowTextStatusBarText(PetFrameManaBar);
	ShowWatchedReputationBarText();

	SetButtonPulse(CharacterMicroButton, 0, 1);	--Stop the button pulse
end

function CharacterFrame_OnHide (self)
	PlaySound("igCharacterInfoClose");
	UpdateMicroButtons();
	PlayerFrameHealthBar.showNumeric = nil;
	PlayerFrameManaBar.showNumeric = nil;
	PlayerFrameAlternateManaBar.showNumeric = nil;
	MainMenuExpBar.showNumeric =nil;
	PetFrameHealthBar.showNumeric = nil;
	PetFrameManaBar.showNumeric = nil;
	HideTextStatusBarText(PlayerFrameHealthBar);
	HideTextStatusBarText(PlayerFrameManaBar);
	HideTextStatusBarText(PlayerFrameAlternateManaBar);
	HideTextStatusBarText(MainMenuExpBar);
	HideTextStatusBarText(PetFrameHealthBar);
	HideTextStatusBarText(PetFrameManaBar);
	HideWatchedReputationBarText();
	PaperDollFrame.currentSideBar = nil;
end

function CharacterFrame_Collapse()
	CharacterFrame:SetWidth(PANEL_DEFAULT_WIDTH);
	CharacterFrame.Expanded = false;
	CharacterFrameExpandButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up");
	CharacterFrameExpandButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down");
	CharacterFrameExpandButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled");
	for i = 1, #PAPERDOLL_SIDEBARS do
		_G[PAPERDOLL_SIDEBARS[i].frame]:Hide();
	end
	CharacterFrameInsetRight:Hide();
	UpdateUIPanelPositions(CharacterFrame);
	PaperDollFrame_SetLevel();
end

function CharacterFrame_Expand()
	CharacterFrame:SetWidth(CHARACTERFRAME_EXPANDED_WIDTH);
	CharacterFrame.Expanded = true;
	CharacterFrameExpandButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up");
	CharacterFrameExpandButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down");
	CharacterFrameExpandButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled");
	if (PaperDollFrame:IsShown() and PaperDollFrame.currentSideBar) then
		PaperDollFrame.currentSideBar:Show();
	else
		CharacterStatsPane:Show();
	end
	PaperDollFrame_UpdateSidebarTabs();
	CharacterFrameInsetRight:Show();
	UpdateUIPanelPositions(CharacterFrame);
	PaperDollFrame_SetLevel();
end
