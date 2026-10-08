REQUIRED_REST_HOURS = 5;

function PlayerFrame_OnLoad(self)
	UnitFrame_Initialize(self, "player", PlayerName, PlayerPortrait,
						 PlayerFrameHealthBar, PlayerFrameHealthBarText, 
						 PlayerFrameManaBar, PlayerFrameManaBarText,
						 PlayerFrameFlash, nil, nil,
						 PlayerFrameMyHealPredictionBar, PlayerFrameOtherHealPredictionBar);
						 
	self.statusCounter = 0;
	self.statusSign = -1;
	CombatFeedback_Initialize(self, PlayerHitIndicator, 30);
	PlayerFrame_Update();
	self:RegisterEvent("UNIT_LEVEL");
	self:RegisterEvent("UNIT_COMBAT");
	self:RegisterEvent("UNIT_FACTION");
	self:RegisterEvent("UNIT_MAXMANA");
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("PLAYER_ENTER_COMBAT");
	self:RegisterEvent("PLAYER_LEAVE_COMBAT");
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:RegisterEvent("PLAYER_UPDATE_RESTING");
	self:RegisterEvent("PARTY_MEMBERS_CHANGED");
	self:RegisterEvent("PARTY_LEADER_CHANGED");
	self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED");
	self:RegisterEvent("VOICE_START");
	self:RegisterEvent("VOICE_STOP");
	self:RegisterEvent("RAID_ROSTER_UPDATE");
	self:RegisterEvent("READY_CHECK");
	self:RegisterEvent("READY_CHECK_CONFIRM");
	self:RegisterEvent("READY_CHECK_FINISHED");
	self:RegisterEvent("UNIT_ENTERED_VEHICLE");
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:RegisterEvent("UNIT_ENTERING_VEHICLE");
	self:RegisterEvent("UNIT_EXITING_VEHICLE");
	self:RegisterEvent("UNIT_EXITED_VEHICLE");
	self:RegisterEvent("PLAYER_FLAGS_CHANGED");
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED");
	self:RegisterEvent("VARIABLES_LOADED");
	
	-- Chinese playtime stuff
	self:RegisterEvent("PLAYTIME_CHANGED");


	local showmenu = function()
		if PlayerFrameMenu_Open(self) then
			return;
		end
		ToggleDropDownMenu(1, nil, PlayerFrameDropDown, "PlayerFrame", 106, 27);
	end
	SecureUnitButton_OnLoad(self, "player", showmenu);
end

function PlayerFrame_Update ()
	PlayerFrame_LockBarColors();
	PlayerFrame_UpdatePowerBarAtlas();
	PlayerFrame_UpdatePortrait();
	PlayerFrame_UpdateInCombatFlash();

	if ( UnitExists("player") ) then
		PlayerLevelText:SetText(UnitLevel(PlayerFrame.unit));
		PlayerFrame_UpdatePartyLeader();
		PlayerFrame_UpdatePvPStatus();
		PlayerFrame_UpdateStatus();
		PlayerFrame_UpdatePlaytime();
		PlayerFrame_UpdateLayout();
	end
end

function PlayerFrame_UpdatePartyLeader()
	if ( IsPartyLeader() ) then
		if ( HasLFGRestrictions() ) then
			PlayerGuideIcon:Show();
			PlayerLeaderIcon:Hide();
		else
			PlayerLeaderIcon:Show()
			PlayerGuideIcon:Hide();
		end
	else
		PlayerLeaderIcon:Hide();
		PlayerGuideIcon:Hide();
	end

	local lootMethod;
	local lootMaster;
	lootMethod, lootMaster = GetLootMethod();
	if ( lootMaster == 0 and ((GetNumPartyMembers() > 0) or (GetNumRaidMembers() > 0)) ) then
		PlayerMasterIcon:Show();
	else
		PlayerMasterIcon:Hide();
	end
end

function PlayerFrame_UpdatePvPStatus()
	local factionGroup, factionName = UnitFactionGroup("player");
	if ( UnitIsPVPFreeForAll("player") ) then
		if ( not PlayerPVPIcon:IsShown() ) then
			PlaySound("igPVPUpdate");
		end
		PlayerPVPIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA");
		PlayerPVPIcon:Show();

		-- Setup newbie tooltip
		PlayerPVPIconHitArea.tooltipTitle = PVPFFA;
		PlayerPVPIconHitArea.tooltipText = NEWBIE_TOOLTIP_PVPFFA;
		PlayerPVPIconHitArea:Show();
		
		PlayerPVPTimerText:Hide();
		PlayerPVPTimerText.timeLeft = nil;
	elseif ( factionGroup and UnitIsPVP("player") ) then
		if ( not PlayerPVPIcon:IsShown() ) then
			PlaySound("igPVPUpdate");
		end
		PlayerPVPIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-"..factionGroup);
		PlayerPVPIcon:Show();

		-- Setup newbie tooltip
		PlayerPVPIconHitArea.tooltipTitle = factionName;
		PlayerPVPIconHitArea.tooltipText = _G["NEWBIE_TOOLTIP_"..strupper(factionGroup)];
		PlayerPVPIconHitArea:Show();
	else
		PlayerPVPIcon:Hide();
		PlayerPVPIconHitArea:Hide();
		PlayerPVPTimerText:Hide();
		PlayerPVPTimerText.timeLeft = nil;
	end
end

function PlayerFrame_OnEvent(self, event, ...)
	UnitFrame_OnEvent(self, event, ...);
	
	local arg1, arg2, arg3, arg4, arg5 = ...;
	if ( event == "UNIT_LEVEL" ) then
		if ( arg1 == "player" ) then
			PlayerLevelText:SetText(UnitLevel(self.unit));
		end
	elseif ( event == "UNIT_COMBAT" ) then
		if ( arg1 == self.unit ) then
			CombatFeedback_OnCombatEvent(self, arg2, arg3, arg4, arg5);
		end
	elseif ( event == "UNIT_FACTION" ) then
		if ( arg1 == "player" ) then
			PlayerFrame_UpdatePvPStatus();
		end
	elseif ( event == "PLAYER_ENTERING_WORLD" ) then
		PlayerFrame_ToPlayerArt(self);
--		if ( UnitHasVehicleUI("player") ) then
--			UnitFrame_SetUnit(self, "vehicle", PlayerFrameHealthBar, PlayerFrameManaBar);
--		else
--			UnitFrame_SetUnit(self, "player", PlayerFrameHealthBar, PlayerFrameManaBar);
--		end
		self.inCombat = nil;
		self.onHateList = nil;
		PlayerFrame_Update();
		PlayerFrame_UpdateStatus();
		PlayerFrame_UpdateRolesAssigned();
		PlayerSpeakerFrame:Show();
		PlayerFrame_UpdateVoiceStatus(UnitIsTalking(UnitName("player")));
		
		if ( IsPVPTimerRunning() ) then
			PlayerPVPTimerText:Show();
			PlayerPVPTimerText.timeLeft = GetPVPTimer();
		else
			PlayerPVPTimerText:Hide();
			PlayerPVPTimerText.timeLeft = nil;
		end
	elseif ( event == "PLAYER_ENTER_COMBAT" ) then
		self.inCombat = 1;
		PlayerFrame_UpdateStatus();
	elseif ( event == "PLAYER_LEAVE_COMBAT" ) then
		self.inCombat = nil;
		PlayerFrame_UpdateStatus();
	elseif ( event == "PLAYER_REGEN_DISABLED" ) then
		self.onHateList = 1;
		PlayerFrame_UpdateStatus();

		if ( GetCVarBool("screenEdgeFlash") ) then
			CombatFeedback_StartFullscreenStatus();
		end
	elseif ( event == "PLAYER_REGEN_ENABLED" ) then
		self.onHateList = nil;
		PlayerFrame_UpdateStatus();

		CombatFeedback_StopFullscreenStatus();
	elseif ( event == "PLAYER_UPDATE_RESTING" ) then
		PlayerFrame_UpdateStatus();
	elseif ( event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_LEADER_CHANGED" or event == "RAID_ROSTER_UPDATE" ) then
		PlayerFrame_UpdateGroupIndicator();
		PlayerFrame_UpdatePartyLeader();
		PlayerFrame_UpdateReadyCheck();
	elseif ( event == "PARTY_LOOT_METHOD_CHANGED" ) then
		local lootMethod;
		local lootMaster;
		lootMethod, lootMaster = GetLootMethod();
		if ( lootMaster == 0 and ((GetNumPartyMembers() > 0) or (GetNumRaidMembers() > 0)) ) then
			PlayerMasterIcon:Show();
		else
			PlayerMasterIcon:Hide();
		end
	elseif ( event == "VOICE_START") then
		if ( arg1 == "player" ) then
			PlayerFrame_UpdateVoiceStatus(true);
		end
	elseif ( event == "VOICE_STOP" ) then
		if ( arg1 == "player" ) then
			PlayerFrame_UpdateVoiceStatus(false);
		end
	elseif ( event == "PLAYTIME_CHANGED" ) then
		PlayerFrame_UpdatePlaytime();
	elseif ( event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" ) then
		PlayerFrame_UpdateReadyCheck();
	elseif ( event == "READY_CHECK_FINISHED" ) then
		ReadyCheck_Finish(PlayerFrameReadyCheck);
	elseif ( event == "UNIT_RUNIC_POWER" and arg1 == "player" ) then
		PlayerFrame_SetRunicPower(UnitPower("player"));
	elseif ( event == "UNIT_ENTERING_VEHICLE" ) then
		if ( arg1 == "player" ) then
			if ( arg2 ) then
				PlayerFrame_AnimateOut(self);
			else
				if ( PlayerFrame.state == "vehicle" ) then
					PlayerFrame_AnimateOut(self);
				end
			end
		end
	elseif ( event == "UNIT_ENTERED_VEHICLE" ) then
		if ( arg1 == "player" ) then
			self.inSeat = true;
			PlayerFrame_UpdateArt(self);
		end
	elseif ( event == "UNIT_EXITING_VEHICLE" ) then
		if ( arg1 == "player" ) then
			if ( self.state == "vehicle" ) then
				PlayerFrame_AnimateOut(self);
			end
		end
	elseif ( event == "UNIT_EXITED_VEHICLE" ) then
		if ( arg1 == "player" ) then
			self.inSeat = true;
			PlayerFrame_UpdateArt(self);
		end
	elseif ( event == "PLAYER_FLAGS_CHANGED" ) then
		if ( IsPVPTimerRunning() ) then
			PlayerPVPTimerText:Show();
			PlayerPVPTimerText.timeLeft = GetPVPTimer();
		else
			PlayerPVPTimerText:Hide();
			PlayerPVPTimerText.timeLeft = nil;
		end
	elseif ( event == "PLAYER_ROLES_ASSIGNED" ) then
		PlayerFrame_UpdateRolesAssigned();
	end
end

function PlayerFrame_UpdateRolesAssigned()
	PlayerFrame_UpdateRoleIcon();

	local frame = PlayerFrame;
	local icon = _G[frame:GetName().."RoleIcon"];
	local isTank, isHealer, isDamage = UnitGroupRolesAssigned("player");
	
	if ( isTank ) then
		icon:SetTexCoord(0, 19/64, 22/64, 41/64);
		icon:Show();
	elseif ( isHealer ) then
		icon:SetTexCoord(20/64, 39/64, 1/64, 20/64);
		icon:Show();
	elseif ( isDamage ) then
		icon:SetTexCoord(20/64, 39/64, 22/64, 41/64);
		icon:Show();
	else
		icon:Hide();
	end
end

local function PlayerFrame_AnimPos(self, fraction)
	return "TOPLEFT", UIParent, "TOPLEFT", -19, fraction*140-4;
end

local PlayerFrameAnimTable = {
	totalTime = 0.3,
	updateFunc = "SetPoint",
	getPosFunc = PlayerFrame_AnimPos,
	}
function PlayerFrame_AnimateOut(self)
	self.inSeat = false;
	self.animFinished = false;
	self.inSequence = true;
	SetUpAnimation(PlayerFrame, PlayerFrameAnimTable, PlayerFrame_AnimFinished, false)
end

function PlayerFrame_AnimFinished(self)
	self.animFinished = true;
	PlayerFrame_UpdateArt(self);
end

function PlayerFrame_UpdateArt(self)
	if ( self.animFinished and self.inSeat and self.inSequence) then
		SetUpAnimation(PlayerFrame, PlayerFrameAnimTable, PlayerFrame_SequenceFinished, true)
		if ( UnitHasVehicleUI("player") ) then
			PlayerFrame_ToVehicleArt(self, UnitVehicleSkin("player"));
		else
			PlayerFrame_ToPlayerArt(self);
		end
	end
end

function PlayerFrame_SequenceFinished(self)
	self.inSequence = false;
	PetFrame_Update(PetFrame);
end

function PlayerFrame_ToVehicleArt(self, vehicleType)
	--Swap frame

	PlayerFrame.state = "vehicle";
	
	UnitFrame_SetUnit(self, "vehicle", PlayerFrameHealthBar, PlayerFrameManaBar);
	UnitFrame_SetUnit(PetFrame, "player", PetFrameHealthBar, PetFrameManaBar);
	PetFrame_Update(PetFrame);
	PlayerFrame_Update();
	BuffFrame_Update();
	ComboFrame_Update();
			
	PlayerFrameTexture:Hide();
	if ( vehicleType == "Natural" ) then
		PlayerFrameVehicleTexture:SetTexture("Interface\\Vehicles\\UI-Vehicle-Frame-Organic");
		PlayerFrameHealthBar:SetWidth(103);
		PlayerFrameHealthBar:SetPoint("TOPLEFT",116,-41);
		PlayerFrameManaBar:SetWidth(103);
		PlayerFrameManaBar:SetPoint("TOPLEFT",116,-52);
	else
		PlayerFrameVehicleTexture:SetTexture("Interface\\Vehicles\\UI-Vehicle-Frame");
		PlayerFrameHealthBar:SetWidth(100);
		PlayerFrameHealthBar:SetPoint("TOPLEFT",119,-41);
		PlayerFrameManaBar:SetWidth(100);
		PlayerFrameManaBar:SetPoint("TOPLEFT",119,-52);
	end
	PlayerFrameVehicleTexture:Show();
	
	PlayerName:SetPoint("CENTER",50,23);
	PlayerLeaderIcon:SetPoint("TOPLEFT",40,-12);
	PlayerMasterIcon:SetPoint("TOPLEFT",86,0);
	PlayerFrameGroupIndicator:SetPoint("BOTTOMLEFT", PlayerFrame, "TOPLEFT", 97, -13);
	
	PlayerFrameBackground:SetWidth(114);
	PlayerLevelText:Hide();
end

function PlayerFrame_ToPlayerArt(self)
	--Unswap frame
	
	PlayerFrame.state = "player";
	
	UnitFrame_SetUnit(self, "player", PlayerFrameHealthBar, PlayerFrameManaBar);
	UnitFrame_SetUnit(PetFrame, "pet", PetFrameHealthBar, PetFrameManaBar);
	PetFrame_Update(PetFrame);
	PlayerFrame_Update();
	BuffFrame_Update();
	ComboFrame_Update();
			
	PlayerFrameTexture:Show();
	PlayerFrameVehicleTexture:Hide();
	-- ретейловая раскладка (см. PlayerFrame.xml)
	PlayerName:ClearAllPoints();
	PlayerName:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 88, -27);
	PlayerLeaderIcon:ClearAllPoints();
	PlayerLeaderIcon:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 86, -10);
	PlayerMasterIcon:ClearAllPoints();
	PlayerMasterIcon:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 108, -10);
	PlayerFrameGroupIndicator:ClearAllPoints();
	PlayerFrameGroupIndicator:SetPoint("BOTTOMRIGHT", PlayerFrame, "TOPLEFT", 210, -29);
	PlayerFrameHealthBar:SetWidth(124);
	PlayerFrameHealthBar:ClearAllPoints();
	PlayerFrameHealthBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -40);
	PlayerFrameManaBar:SetWidth(124);
	PlayerFrameManaBar:ClearAllPoints();
	PlayerFrameManaBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -62);
	PlayerFrameBackground:SetWidth(124);
	PlayerPortrait:ClearAllPoints();
	PlayerPortrait:SetSize(60, 60);
	PlayerPortrait:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 24, -19);
	PlayerFrameCornerIcon:Show();
	PlayerLevelText:Show();
	PlayerFrame_UpdatePortrait();
end

local POWER_BAR_ATLAS = {
	MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
	RAGE = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
	ENERGY = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
	FOCUS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus",
	RUNIC_POWER = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower",
};

-- полоска ресурса: свой атлас под каждый тип силы, иначе цвет не тот
function PlayerFrame_UpdatePowerBarAtlas()
	local _, powerToken = UnitPowerType(PlayerFrame.unit or "player");
	local atlas = POWER_BAR_ATLAS[powerToken];
	local texture = PlayerFrameManaBar:GetStatusBarTexture();

	if atlas and texture and texture.SetAtlas then
		texture:SetAtlas(atlas);
		PlayerFrameManaBar:SetStatusBarColor(1, 1, 1);
		PlayerFrameManaBar.lockColor = true;
	end
end

-- атласы полосок: их нельзя перекрашивать, иначе атлас зальёт цветом
function PlayerFrame_LockBarColors()
	for _, bar in ipairs({ PlayerFrameHealthBar, PlayerFrameManaBar }) do
		local texture = bar:GetStatusBarTexture();
		if texture and texture.GetAtlas and texture:GetAtlas() then
			bar:SetStatusBarColor(1, 1, 1);
			bar.lockColor = true;
		end
	end
end

-- портрет или иконка класса (CVar unitFramePortraitClassIcon)
function UnitFramePortrait_SetClassIcon(texture, unit)
	local _, class = UnitClass(unit);
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class];

	if not coords then
		return false;
	end

	texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles");
	texture:SetTexCoord(unpack(coords));

	return true;
end

function PlayerFrame_UpdatePortrait()
	if GetCVar("unitFramePortraitClassIcon") == "1" and UnitIsPlayer("player") then
		if UnitFramePortrait_SetClassIcon(PlayerPortrait, "player") then
			return;
		end
	end

	PlayerPortrait:SetTexCoord(0, 1, 0, 1);
	SetPortraitTexture(PlayerPortrait, PlayerFrame.unit);
end

-- подсветка рамки в бою
function PlayerFrame_UpdateInCombatFlash()
	PlayerFrameFlash:SetShown(UnitAffectingCombat("player") and PlayerFrame.state == "player");
end

local ROLE_ATLAS = {
	TANK = "roleicon-tiny-tank",
	HEALER = "roleicon-tiny-healer",
	DAMAGER = "roleicon-tiny-dps",
};

function PlayerFrame_UpdateRoleIcon()
	if GetCVar("unitFrameShowRoleIcon") == "0" then
		PlayerFrameRoleIcon:Hide();
		return;
	end

	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player");
	local atlas = role and ROLE_ATLAS[role];

	if atlas and (GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0) then
		PlayerFrameRoleIcon:SetAtlas(atlas, false);
		PlayerFrameRoleIcon:Show();
	else
		PlayerFrameRoleIcon:Hide();
	end
end

-- значок отдыха: ретейловый флипбук 7x6, 42 кадра за 1.5 секунды
local REST_ROWS, REST_COLUMNS, REST_FRAMES, REST_DURATION = 7, 6, 42, 1.5;
local restElapsed, restFrameIndex, restShown = 0, 1, false;

function PlayerFrame_SetRestFlipbookFrame(index)
	local info = C_Texture.GetAtlasInfo("UI-HUD-UnitFrame-Player-Rest-Flipbook");
	if not info then
		return;
	end

	local width = (info.right - info.left) / REST_COLUMNS;
	local height = (info.bottom - info.top) / REST_ROWS;
	local column = (index - 1) % REST_COLUMNS;
	local row = math.floor((index - 1) / REST_COLUMNS);

	PlayerRestIcon:SetTexCoord(info.left + column * width, info.left + (column + 1) * width,
		info.top + row * height, info.top + (row + 1) * height);
end

function PlayerFrame_UpdateRestAnimation(elapsed)
	if not PlayerRestLoop:IsShown() then
		restShown = false;
		return;
	end

	if not restShown then
		restShown = true;
		restFrameIndex = 1;
		PlayerFrame_SetRestFlipbookFrame(1);
	end

	restElapsed = restElapsed + elapsed;
	if restElapsed < REST_DURATION / REST_FRAMES then
		return;
	end
	restElapsed = 0;

	restFrameIndex = restFrameIndex % REST_FRAMES + 1;
	PlayerFrame_SetRestFlipbookFrame(restFrameIndex);
end

function PlayerFrame_UpdateVoiceStatus (status)
	if ( status ) then
		UIFrameFadeIn(PlayerSpeakerFrame, 0.2, PlayerSpeakerFrame:GetAlpha(), 1);
		VoiceChat_Animate(PlayerSpeakerFrame, 1);
	else
		UIFrameFadeOut(PlayerSpeakerFrame, 0.2, PlayerSpeakerFrame:GetAlpha(), 0);
		VoiceChat_Animate(PlayerSpeakerFrame, nil);
	end
end

function PlayerFrame_UpdateReadyCheck ()
	local readyCheckStatus = GetReadyCheckStatus("player");
	if ( readyCheckStatus ) then
		if ( readyCheckStatus == "ready" ) then
			ReadyCheck_Confirm(PlayerFrameReadyCheck, 1);
		elseif ( readyCheckStatus == "notready" ) then
			ReadyCheck_Confirm(PlayerFrameReadyCheck, 0);
		else -- "waiting"
			ReadyCheck_Start(PlayerFrameReadyCheck);
		end
	else
		PlayerFrameReadyCheck:Hide();
	end
end

function PlayerFrame_OnUpdate (self, elapsed)
	if ( PlayerStatusTexture:IsShown() ) then
		local alpha = 255;
		local counter = self.statusCounter + elapsed;
		local sign    = self.statusSign;

		if ( counter > 0.5 ) then
			sign = -sign;
			self.statusSign = sign;
		end
		counter = mod(counter, 0.5);
		self.statusCounter = counter;

		if ( sign == 1 ) then
			alpha = (55  + (counter * 400)) / 255;
		else
			alpha = (255 - (counter * 400)) / 255;
		end
		PlayerStatusTexture:SetAlpha(alpha);
		PlayerFrameFlash:SetAlpha(alpha);
	end
	
	if ( PlayerPVPTimerText.timeLeft ) then
		PlayerPVPTimerText.timeLeft = PlayerPVPTimerText.timeLeft - elapsed*1000;
		local timeLeft = PlayerPVPTimerText.timeLeft;
		if ( timeLeft < 0 ) then
			PlayerPVPTimerText:Hide()
		end
		PlayerPVPTimerText:SetFormattedText(SecondsToTimeAbbrev(floor(timeLeft/1000)));
	else
		PlayerPVPTimerText:Hide();
	end
	CombatFeedback_OnUpdate(self, elapsed);
	PlayerFrame_UpdateRestAnimation(elapsed);
end

function PlayerFrame_OnReceiveDrag ()
	if ( CursorHasItem() ) then
		AutoEquipCursorItem();
	end
end

function PlayerFrame_UpdateStatus()
	if ( UnitHasVehicleUI("player") ) then
		PlayerStatusTexture:Hide()
		PlayerRestLoop:Hide()
		PlayerAttackIcon:Hide()
		PlayerFrameFlash:Hide()
	elseif ( IsResting() ) then
		PlayerStatusTexture:SetVertexColor(1.0, 0.88, 0.25, 1.0);
		PlayerStatusTexture:Show();
		PlayerRestLoop:Show();
		PlayerAttackIcon:Hide();
		PlayerFrameFlash:Show();
	elseif ( PlayerFrame.inCombat ) then
		PlayerStatusTexture:SetVertexColor(1.0, 0.0, 0.0, 1.0);
		PlayerStatusTexture:Show();
		PlayerAttackIcon:Show();
		PlayerRestLoop:Hide();
		PlayerFrameFlash:Show();
	elseif ( PlayerFrame.onHateList ) then
		PlayerAttackIcon:Show();
		PlayerRestLoop:Hide();
		PlayerFrameFlash:Hide();
	else
		PlayerStatusTexture:Hide();
		PlayerRestLoop:Hide();
		PlayerAttackIcon:Hide();
		PlayerFrameFlash:Hide();
	end
end

function PlayerFrame_UpdateGroupIndicator()
	PlayerFrameGroupIndicator:Hide();
	local name, rank, subgroup;
	if ( GetNumRaidMembers() == 0 ) then
		PlayerFrameGroupIndicator:Hide();
		return;
	end
	local numRaidMembers = GetNumRaidMembers();
	for i=1, MAX_RAID_MEMBERS do
		if ( i <= numRaidMembers ) then
			name, rank, subgroup = GetRaidRosterInfo(i);
			-- Set the player's group number indicator
			if ( name == UnitName("player") ) then
				PlayerFrameGroupIndicatorText:SetText(GROUP.." "..subgroup);
				PlayerFrameGroupIndicator:SetWidth(PlayerFrameGroupIndicatorText:GetWidth()+40);
				PlayerFrameGroupIndicator:Show();
			end
		end
	end
end

function PlayerFrameDropDown_OnLoad (self)
	UIDropDownMenu_Initialize(self, PlayerFrameDropDown_Initialize, "MENU");
end

function PlayerFrameDropDown_Initialize ()
	if ( PlayerFrame.unit == "vehicle" ) then
		UnitPopup_ShowMenu(PlayerFrameDropDown, "VEHICLE", "vehicle");
	else
		UnitPopup_ShowMenu(PlayerFrameDropDown, "SELF", "player");
	end
end

function PlayerFrame_UpdatePlaytime()
	if ( PartialPlayTime() ) then
		PlayerPlayTimeIcon:SetTexture("Interface\\CharacterFrame\\UI-Player-PlayTimeTired");
		PlayerPlayTime.tooltip = format(PLAYTIME_TIRED, REQUIRED_REST_HOURS - floor(GetBillingTimeRested()/60));
		PlayerPlayTime:Show();
	elseif ( NoPlayTime() ) then
		PlayerPlayTimeIcon:SetTexture("Interface\\CharacterFrame\\UI-Player-PlayTimeUnhealthy");
		PlayerPlayTime.tooltip = format(PLAYTIME_UNHEALTHY, REQUIRED_REST_HOURS - floor(GetBillingTimeRested()/60));
		PlayerPlayTime:Show();
	else
		PlayerPlayTime:Hide();
	end
end

function PlayerFrame_SetupDeathKnniggetLayout ()
	PlayerFrame:SetHitRectInsets(0,0,0,35);
end

CustomClassLayouts = {
	["DEATHKNIGHT"] = PlayerFrame_SetupDeathKnniggetLayout,
}

local layoutUpdated = false;

function PlayerFrame_UpdateLayout ()
	if ( layoutUpdated ) then
		return;
	end
	layoutUpdated = true;
	
	local _, class = UnitClass("player");	
	
	if ( CustomClassLayouts[class] ) then
		CustomClassLayouts[class]();
	end
end

local RUNICPOWERBARHEIGHT = 63;
local RUNICPOWERBARWIDTH = 64;

local RUNICGLOW_FADEALPHA = .050
local RUNICGLOW_MINALPHA = .40
local RUNICGLOW_MAXALPHA = .80
local RUNICGLOW_THROBINTERVAL = .8;

RUNICGLOW_FINISHTHROBANDHIDE = false;
local RUNICGLOW_THROBSTART = 0;

function PlayerFrame_SetRunicPower (runicPower)
	PlayerFrameRunicPowerBar:SetHeight(RUNICPOWERBARHEIGHT * (runicPower / 100));
	PlayerFrameRunicPowerBar:SetTexCoord(0, 1, (1 - (runicPower / 100)), 1);
	
	if ( runicPower >= 90 ) then
		-- Oh,  God help us for these function and variable names.
		RUNICGLOW_FINISHTHROBANDHIDE = false;
		if ( not PlayerFrameRunicPowerGlow:IsShown() ) then
			PlayerFrameRunicPowerGlow:Show();
		end
		PlayerFrameRunicPowerGlow:GetParent():SetScript("OnUpdate", DeathKnniggetThrobFunction);
	elseif ( PlayerFrameRunicPowerGlow:GetParent():GetScript("OnUpdate") ) then
		RUNICGLOW_FINISHTHROBANDHIDE = true;
	else
		PlayerFrameRunicPowerGlow:Hide();
	end
end

local firstFadeIn = true;
function DeathKnniggetThrobFunction (self, elapsed)
	if ( RUNICGLOW_THROBSTART == 0 ) then
		RUNICGLOW_THROBSTART = GetTime();
	elseif ( not RUNICGLOW_FINISHTHROBANDHIDE ) then
		local interval = RUNICGLOW_THROBINTERVAL - math.abs( .9 - (UnitPower("player") / 100)); 
		local animTime = GetTime() - RUNICGLOW_THROBSTART;
		if ( animTime >= interval ) then
			-- Fading out
			PlayerFrameRunicPowerGlow:SetAlpha(math.max(RUNICGLOW_MINALPHA, math.min(RUNICGLOW_MAXALPHA, RUNICGLOW_MAXALPHA * interval/animTime)));			
			if ( animTime >= interval * 2 ) then
				self.timeSinceThrob = 0;
				RUNICGLOW_THROBSTART = GetTime();
			end
			firstFadeIn = false;
		else
			-- Fading in
			if ( firstFadeIn ) then
				PlayerFrameRunicPowerGlow:SetAlpha(math.max(RUNICGLOW_FADEALPHA, math.min(RUNICGLOW_MAXALPHA, RUNICGLOW_MAXALPHA * animTime/interval)));			
			else
				PlayerFrameRunicPowerGlow:SetAlpha(math.max(RUNICGLOW_MINALPHA, math.min(RUNICGLOW_MAXALPHA, RUNICGLOW_MAXALPHA * animTime/interval)));			
			end
		end
	elseif ( RUNICGLOW_FINISHTHROBANDHIDE ) then
		local currentAlpha = PlayerFrameRunicPowerGlow:GetAlpha();
		local animTime = GetTime() - RUNICGLOW_THROBSTART;
		local interval = RUNICGLOW_THROBINTERVAL;
		firstFadeIn = true;
		
		if ( animTime >= interval ) then
			-- Already fading out, just keep fading out.
			local alpha = math.min(PlayerFrameRunicPowerGlow:GetAlpha(), RUNICGLOW_MAXALPHA * (interval/(animTime*(animTime/2))));
			
			PlayerFrameRunicPowerGlow:SetAlpha(alpha);
			if ( alpha <= RUNICGLOW_FADEALPHA ) then
				self.timeSinceThrob = 0;
				RUNICGLOW_THROBSTART = 0;
				PlayerFrameRunicPowerGlow:Hide();
				self:SetScript("OnUpdate", nil);
				RUNICGLOW_FINISHTHROBANDHIDE = false;
				return;
			end
		else
			-- Was fading in, start fading out
			animTime = interval;
		end
	end
end

function PlayerFrame_ShowVehicleTexture()
	PlayerFrameVehicleTexture:Show();
	
	local _, class = UnitClass("player");	
	if ( class == "WARLOCK" ) then
		ShardBarFrame:Hide();
	elseif ( class == "SHAMAN" ) then
		TotemFrame:Hide();
	elseif ( class == "DRUID" ) then
		EclipseBarFrame:Hide();
	elseif ( class == "PALADIN" ) then
		PaladinPowerBar:Hide();
	elseif ( class == "DEATHKNIGHT" ) then
		RuneFrame:Hide();
	end
end

function PlayerFrame_HideVehicleTexture()
	PlayerFrameVehicleTexture:Hide();
	
	local _, class = UnitClass("player");	
	if ( class == "WARLOCK" ) then
		ShardBarFrame:Show();
	elseif ( class == "SHAMAN" ) then
		TotemFrame_Update();
	elseif ( class == "DRUID" ) then
		EclipseBar_UpdateShown(EclipseBarFrame);
	elseif ( class == "PALADIN" ) then
		PaladinPowerBar:Show();
	elseif ( class == "DEATHKNIGHT" ) then
		RuneFrame:Show();
	end
end

function PlayerFrame_OnDragStart(self)
	self:StartMoving();
	self:SetUserPlaced(true);
	self:SetClampedToScreen(true);
end

function PlayerFrame_OnDragStop(self)
	self:StopMovingOrSizing();
end

function PlayerFrame_SetLocked(locked)
	PLAYER_FRAME_UNLOCKED = not locked;
	if ( locked ) then
		PlayerFrame:RegisterForDrag();	--Unregister all buttons.
	else
		PlayerFrame:RegisterForDrag("LeftButton");
	end
end

function PlayerFrame_ResetUserPlacedPosition()
	PlayerFrame:ClearAllPoints();
	PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -19, -4);
	PlayerFrame:SetUserPlaced(false);
	PlayerFrame:SetClampedToScreen(false);
	PlayerFrame_SetLocked(true);
end

--
-- Functions for having the cast bar underneath the player frame
--

function PlayerFrame_AttachCastBar()
	local castBar = CastingBarFrame;
	local petCastBar = PetCastingBarFrame;
	-- player
	castBar.ignoreFramePositionManager = true;
	CastingBarFrame_SetLook(castBar, "UNITFRAME");
	castBar:ClearAllPoints();
	castBar:SetPoint("LEFT", PlayerFrame, 78, 0);
	-- pet
	CastingBarFrame_SetLook(petCastBar, "UNITFRAME");
	petCastBar:SetWidth(150);
	petCastBar:SetHeight(10);
	petCastBar:ClearAllPoints();
	petCastBar:SetPoint("TOP", castBar, "TOP", 0, 0);
	
	PlayerFrame_AdjustAttachments();
end

function PlayerFrame_DetachCastBar()
	local castBar = CastingBarFrame;
	local petCastBar = PetCastingBarFrame;
	-- player
	castBar.ignoreFramePositionManager = nil;
	CastingBarFrame_SetLook(castBar, "CLASSIC");
	castBar:ClearAllPoints();
	-- pet
	CastingBarFrame_SetLook(petCastBar, "CLASSIC");
	petCastBar:SetWidth(195);
	petCastBar:SetHeight(13);
	petCastBar:ClearAllPoints();
	petCastBar:SetPoint("BOTTOM", castBar, "TOP", 0, 12);
	
	UIParent_ManageFramePositions();
end

function PlayerFrame_AdjustAttachments()
	if ( not PLAYER_FRAME_CASTBARS_SHOWN ) then
		return;
	end
	if ( PetFrame and PetFrame:IsShown() ) then
		CastingBarFrame:SetPoint("TOP", PetFrame, "BOTTOM", 0, -4);
	elseif ( TotemFrame and TotemFrame:IsShown() ) then
		CastingBarFrame:SetPoint("TOP", TotemFrame, "BOTTOM", 0, 2);
	else
		local _, class = UnitClass("player");
		if ( class == "PALADIN" ) then
			CastingBarFrame:SetPoint("TOP", PlayerFrame, "BOTTOM", 0, -6);
		elseif ( class == "DRUID" ) then
			if ( EclipseBarFrame and EclipseBarFrame:IsShown() ) then
				CastingBarFrame:SetPoint("TOP", PlayerFrame, "BOTTOM", 0, -2);
			else
				CastingBarFrame:SetPoint("TOP", PlayerFrame, "BOTTOM", 0, 10);
			end
		elseif ( class == "DEATHKNIGHT" or class == "WARLOCK" ) then
			CastingBarFrame:SetPoint("TOP", PlayerFrame, "BOTTOM", 0, 4);
		else
			CastingBarFrame:SetPoint("TOP", PlayerFrame, "BOTTOM", 0, 10);
		end
	end
end