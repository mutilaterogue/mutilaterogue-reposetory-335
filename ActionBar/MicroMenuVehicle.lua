-- The micro menu stays at its place (bottom right, MicroMenuFrame) in a vehicle, as in retail: the 3.3.5
-- VehicleMenuBar no longer takes the micro buttons onto its art.
-- Replace in MainMenuBarMicroButtons.lua: MicroMenu_PlaceBottomRight; in VehicleMenuBar.lua: VehicleMenuBar_MoveMicroButtons.

-- MainMenuBarMicroButtons.lua (MICRO_ORDER, MICRO_SPACING and MicroMenu_GetWidth are the locals there)
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

-- VehicleMenuBar.lua
function VehicleMenuBar_MoveMicroButtons(skinName)
	-- retail: the micro menu does not move into the vehicle bar, whatever its skin
	for _, frame in pairs(MicroButtons) do
		frame:Show();
	end
	if ( MicroMenu_PlaceBottomRight ) then
		MicroMenu_PlaceBottomRight();
	end
	UpdateMicroButtons();
end
