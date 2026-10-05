-- PlayerFrame.lua: PlayerFrame_ToVehicleArt / PlayerFrame_ToPlayerArt for the retail player frame (PlayerFrame.xml),
-- as retail 12.1.5 Blizzard_UnitFrame\Mainline\PlayerFrame.lua does them:
-- in a vehicle the vehicle frame art (UI-HUD-UnitFrame-Player-PortraitOn-Vehicle) with its combat flash and status
-- glow, the bars 118 wide at the vehicle art's places; back to the player art, everything at its PlayerFrame.xml place.
-- Replace the two functions in PlayerFrame.lua with these.

function PlayerFrame_ToVehicleArt(self, vehicleType)
	PlayerFrame.state = "vehicle";

	-- swap pet and player frames
	UnitFrame_SetUnit(self, "vehicle", PlayerFrameHealthBar, PlayerFrameManaBar);
	UnitFrame_SetUnit(PetFrame, "player", PetFrameHealthBar, PetFrameManaBar);

	-- swap frame textures (retail has one vehicle art for every vehicle type)
	PlayerFrameTexture:Hide();
	PlayerFrameAlternatePowerTexture:Hide();
	PlayerFrameVehicleTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Vehicle", true);
	PlayerFrameVehicleTexture:Show();

	-- flash and status textures
	PlayerFrameFlash:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Vehicle-InCombat", true);
	PlayerFrameFlash:ClearAllPoints();
	PlayerFrameFlash:SetPoint("CENTER", PlayerFrameFlash:GetParent(), "CENTER", -3.5, 1);
	PlayerStatusTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Vehicle-Status", true);
	PlayerStatusTexture:ClearAllPoints();
	PlayerStatusTexture:SetPoint("TOPLEFT", PlayerFrameFlash:GetParent(), "TOPLEFT", 11, -8);

	-- health bar
	PlayerFrameHealthBar:SetWidth(118);
	PlayerFrameHealthBar:SetHeight(20);
	PlayerFrameHealthBar:ClearAllPoints();
	PlayerFrameHealthBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 91, -40);
	PlayerFrameBackground:SetWidth(118);
	PlayerFrameBackground:ClearAllPoints();
	PlayerFrameBackground:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 91, -40);

	-- mana bar
	PlayerFrameManaBar:SetWidth(118);
	PlayerFrameManaBar:SetHeight(10);
	PlayerFrameManaBar:ClearAllPoints();
	PlayerFrameManaBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 91, -61);

	-- class resources belong to the player, not the vehicle
	local _, class = UnitClass("player");
	if class == "SHAMAN" and TotemFrame then
		TotemFrame:Hide();
	elseif class == "DEATHKNIGHT" and RuneFrame then
		RuneFrame:Hide();
	end

	-- other stuff
	PetFrame_Update(PetFrame);
	PlayerFrame_Update();
	BuffFrame_Update();
	ComboFrame_Update();

	PlayerName:ClearAllPoints();
	PlayerName:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 96, -27);
	PlayerLeaderIcon:ClearAllPoints();
	PlayerLeaderIcon:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 92, -10);
	PlayerMasterIcon:ClearAllPoints();
	PlayerMasterIcon:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 114, -10);
	PlayerFrameGroupIndicator:ClearAllPoints();
	PlayerFrameGroupIndicator:SetPoint("BOTTOMRIGHT", PlayerFrame, "TOPLEFT", 210, -28);
	if PlayerFrameCornerIcon then
		PlayerFrameCornerIcon:Hide();
	end
	PlayerLevelText:Hide();
end

function PlayerFrame_ToPlayerArt(self)
	PlayerFrame.state = "player";

	-- unswap pet and player frames
	UnitFrame_SetUnit(self, "player", PlayerFrameHealthBar, PlayerFrameManaBar);
	UnitFrame_SetUnit(PetFrame, "pet", PetFrameHealthBar, PetFrameManaBar);

	-- swap frame textures
	PlayerFrameVehicleTexture:Hide();
	PlayerFrameTexture:Show();

	-- flash and status textures (PlayerFrame.xml)
	PlayerFrameFlash:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-InCombat", true);
	PlayerFrameFlash:ClearAllPoints();
	PlayerFrameFlash:SetPoint("CENTER", PlayerFrameFlash:GetParent(), "CENTER", -1, 1);
	PlayerStatusTexture:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Status", true);
	PlayerStatusTexture:ClearAllPoints();
	PlayerStatusTexture:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 17, -14);

	-- health bar
	PlayerFrameHealthBar:SetWidth(124);
	PlayerFrameHealthBar:SetHeight(20);
	PlayerFrameHealthBar:ClearAllPoints();
	PlayerFrameHealthBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -40);
	PlayerFrameBackground:SetWidth(124);
	PlayerFrameBackground:ClearAllPoints();
	PlayerFrameBackground:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -40);

	-- mana bar
	PlayerFrameManaBar:SetWidth(124);
	PlayerFrameManaBar:SetHeight(9);
	PlayerFrameManaBar:ClearAllPoints();
	PlayerFrameManaBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 85, -62);

	-- class resources back
	local _, class = UnitClass("player");
	if class == "SHAMAN" and TotemFrame and TotemFrame_Update then
		TotemFrame_Update();
	elseif class == "DEATHKNIGHT" and RuneFrame then
		RuneFrame:Show();
	end

	-- other stuff
	PetFrame_Update(PetFrame);
	PlayerFrame_Update();
	BuffFrame_Update();
	ComboFrame_Update();

	PlayerName:ClearAllPoints();
	PlayerName:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 88, -27);
	PlayerLeaderIcon:ClearAllPoints();
	PlayerLeaderIcon:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 86, -10);
	PlayerMasterIcon:ClearAllPoints();
	PlayerMasterIcon:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 108, -10);
	PlayerFrameGroupIndicator:ClearAllPoints();
	PlayerFrameGroupIndicator:SetPoint("BOTTOMRIGHT", PlayerFrame, "TOPLEFT", 210, -29);
	PlayerPortrait:ClearAllPoints();
	PlayerPortrait:SetWidth(60);
	PlayerPortrait:SetHeight(60);
	PlayerPortrait:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 24, -19);
	if PlayerFrameCornerIcon then
		PlayerFrameCornerIcon:Show();
	end
	PlayerLevelText:Show();
	if PlayerFrame_UpdatePortrait then
		PlayerFrame_UpdatePortrait();
	end
end
