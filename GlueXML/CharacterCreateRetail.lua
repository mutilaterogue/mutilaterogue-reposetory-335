-- Retail character create (12.x Blizzard_CharacterCreate) on top of the 3.3.5 one: the 3.3.5 logic stays
-- (CharacterCreateEnumerateRaces / Classes, SetCharacterRace / Class / Gender, customization, name, Okay / Back),
-- only the look changes:
--   Alliance races in a column on the left, Horde on the right (raceicon128-<race>-<sex>, metal rings, crests),
--   the classes in a row at the bottom (classicon-<class>), the gender buttons at the top,
--   the customization rows on the right, the name under the classes, Back bottom left, Create bottom right,
--   the retail vignettes around the screen.
-- GlueXML.toc: after CharacterCreate.xml.

CharacterCreateRetail = {};
local CR = CharacterCreateRetail;

local RACE_SIZE, RACE_SPACING = 60, 78;
local CLASS_SIZE, CLASS_SPACING = 54, 66;

local function HasAtlas(atlas)
	return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil;
end

local function SetAtlasIf(texture, atlas)
	if texture and HasAtlas(atlas) then
		texture:SetAtlas(atlas);
		return true;
	end
	return false;
end

local function Hide(name)
	local region = type(name) == "string" and _G[name] or name;
	-- some of these names are plain globals (strings) on the login screen, not frames
	if type(region) == "table" and type(region.Hide) == "function" then
		region:Hide();
		if region.SetAlpha then
			region:SetAlpha(0);
		end
	end
end

-- retail atlas names of the 3.3.5 race files (Scourge -> undead)
local RACE_ATLAS = { SCOURGE = "undead" };

local function RaceAtlas(file, sex)
	local race = RACE_ATLAS[strupper(file)] or strlower(file);
	local gender = sex == SEX_FEMALE and "female" or "male";
	local hi = "raceicon128-" .. race .. "-" .. gender;
	return HasAtlas(hi) and hi or ("raceicon-" .. race .. "-" .. gender);
end

---------------------------------------------------------------------------
-- icon buttons: retail art over the 3.3.5 check buttons
---------------------------------------------------------------------------
local function StyleIconButton(button, size, small)
	if button.crStyled then
		return;
	end
	button.crStyled = true;
	local name = button:GetName();
	button:SetWidth(size);
	button:SetHeight(size);
	Hide(name .. "Shadow");
	Hide(name .. "BevelEdge");
	Hide(name .. "Text");
	local normal, pushed = _G[name .. "NormalTexture"], _G[name .. "PushedTexture"];
	for _, texture in ipairs({ normal or false, pushed or false }) do
		if texture then
			texture:ClearAllPoints();
			texture:SetPoint("CENTER");
			texture:SetWidth(size - 6);
			texture:SetHeight(size - 6);
		end
	end
	-- the metal ring over the icon, the gold ring when chosen
	button.CRRing = button:CreateTexture(nil, "OVERLAY");
	button.CRRing:SetPoint("CENTER");
	button.CRRing:SetWidth(size + 14);
	button.CRRing:SetHeight(size + 14);
	SetAtlasIf(button.CRRing, small and "charactercreate-ring-metallight-small" or "charactercreate-ring-metallight");
	local checked = button:GetCheckedTexture();
	if checked and SetAtlasIf(checked, small and "charactercreate-ring-select-small" or "charactercreate-ring-select") then
		checked:ClearAllPoints();
		checked:SetPoint("CENTER");
		checked:SetWidth(size + 22);
		checked:SetHeight(size + 22);
		checked:SetBlendMode("BLEND");
	end
	local highlight = button:GetHighlightTexture();
	if highlight then
		highlight:SetAlpha(0);
	end
end

local function RoundIcon(texture, atlas, fallback)
	if not texture then
		return;
	end
	if not SetAtlasIf(texture, atlas) and fallback then
		texture:SetTexture(fallback);
	end
end

---------------------------------------------------------------------------
-- races / classes after the 3.3.5 enumeration
---------------------------------------------------------------------------
function CR.LayoutRaces(...)
	local sex = GetSelectedSex();
	local alliance, horde = 0, 0;
	local index = 1;
	for i = 1, select("#", ...), 3 do
		local file = select(i + 1, ...);
		local button = _G["CharacterCreateRaceButton" .. index];
		if button then
			StyleIconButton(button, RACE_SIZE);
			local atlas = RaceAtlas(file, sex);
			RoundIcon(_G[button:GetName() .. "NormalTexture"], atlas);
			RoundIcon(_G[button:GetName() .. "PushedTexture"], atlas);
			local _, faction = GetFactionForRace(index);
			button:ClearAllPoints();
			if faction == "Horde" then
				button:SetPoint("TOPRIGHT", CharacterCreateFrame, "TOPRIGHT", -68, -136 - horde * RACE_SPACING);
				horde = horde + 1;
			else
				button:SetPoint("TOPLEFT", CharacterCreateFrame, "TOPLEFT", 68, -136 - alliance * RACE_SPACING);
				alliance = alliance + 1;
			end
		end
		index = index + 1;
	end
end

function CR.LayoutClasses(...)
	local count = select("#", ...) / 3;
	local index = 1;
	for i = 1, select("#", ...), 3 do
		local file = select(i + 1, ...);
		local button = _G["CharacterCreateClassButton" .. index];
		if button then
			StyleIconButton(button, CLASS_SIZE, true);
			local atlas = "classicon-" .. strlower(file);
			RoundIcon(_G[button:GetName() .. "NormalTexture"], atlas);
			RoundIcon(_G[button:GetName() .. "PushedTexture"], atlas);
			local disabled = _G[button:GetName() .. "DisableTexture"];
			if disabled then
				SetAtlasIf(disabled, "common-icon-redx");
				disabled:ClearAllPoints();
				disabled:SetPoint("BOTTOMRIGHT", 2, -2);
				disabled:SetWidth(20);
				disabled:SetHeight(20);
			end
			button:ClearAllPoints();
			button:SetPoint("BOTTOM", CharacterCreateFrame, "BOTTOM", (index - (count + 1) / 2) * CLASS_SPACING, 130);
		end
		index = index + 1;
	end
end

---------------------------------------------------------------------------
-- the screen
---------------------------------------------------------------------------
function CR.Setup()
	if CR.done then
		return;
	end
	CR.done = true;
	local frame = CharacterCreateFrame;

	-- the 3.3.5 panels off: logo, race / class texts, the configuration box art
	for _, name in ipairs({ "CharacterCreateWoWLogo", "CharacterCreateCharacterRace", "CharacterCreateCharacterClass",
		"CharacterCreateOuterBorder1", "CharacterCreateOuterBorder2", "CharacterCreateOuterBorder3",
		"CharacterCreateConfigurationBackground", "CharacterCreateBanners", "CharacterCreateAllianceLabel",
		"CharacterCreateHordeLabel", "CharacterCreateAllianceRaceLabel", "CharacterCreateHordeRaceLabel",
		"CharacterCreateGender", "CharacterCreateClassName" }) do
		Hide(name);
	end
	-- the configuration frame keeps its buttons: over the whole screen, they are placed one by one
	local config = CharacterCreateConfigurationFrame;
	if config then
		if config.SetBackdrop then
			config:SetBackdrop(nil);
		end
		config:ClearAllPoints();
		config:SetAllPoints(frame);
	end

	-- vignettes (retail charactercreate-vignette-*)
	local function Vignette(atlas, ...)
		local texture = frame:CreateTexture(nil, "BACKGROUND");
		if SetAtlasIf(texture, atlas) then
			for i = 1, select("#", ...), 3 do
				texture:SetPoint(select(i, ...), frame, select(i + 1, ...), 0, select(i + 2, ...));
			end
		else
			texture:Hide();
		end
		return texture;
	end
	local top = Vignette("charactercreate-vignette-top", "TOPLEFT", "TOPLEFT", 0, "TOPRIGHT", "TOPRIGHT", 0);
	top:SetHeight(160);
	local bottom = Vignette("charactercreate-vignette-bottom", "BOTTOMLEFT", "BOTTOMLEFT", 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0);
	bottom:SetHeight(220);
	local sides = Vignette(HasAtlas("charactercreate-vignette-sides-widescreen") and "charactercreate-vignette-sides-widescreen" or "charactercreate-vignette-sides",
		"TOPLEFT", "TOPLEFT", 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0);

	-- faction crests over the race columns
	local function Crest(atlas, point, x)
		local crest = frame:CreateTexture(nil, "ARTWORK");
		crest:SetWidth(76);
		crest:SetHeight(76);
		crest:SetPoint("TOP" .. point, frame, "TOP" .. point, x, -40);
		if not SetAtlasIf(crest, atlas) then
			crest:Hide();
		end
	end
	Crest("charactercreate-icon-alliance", "LEFT", 60);
	Crest("charactercreate-icon-horde", "RIGHT", -60);

	-- gender: top center
	for i, button in ipairs({ CharacterCreateGenderButtonMale, CharacterCreateGenderButtonFemale }) do
		if button then
			StyleIconButton(button, 44, true);
			button:ClearAllPoints();
			button:SetPoint("TOP", frame, "TOP", (i - 1.5) * 56, -40);
		end
	end

	-- customization on the right, between the Horde column and the middle
	local previous;
	for i = 1, NUM_CHAR_CUSTOMIZATIONS do
		local row = _G["CharacterCustomizationButtonFrame" .. i];
		if row then
			row:ClearAllPoints();
			if previous then
				row:SetPoint("TOP", previous, "BOTTOM", 0, -6);
			else
				row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -170, -150);
			end
			previous = row;
		end
	end
	if CharCreateRandomizeButton and previous then
		CharCreateRandomizeButton:ClearAllPoints();
		CharCreateRandomizeButton:SetPoint("TOP", previous, "BOTTOM", 0, -12);
	end

	-- the name under the classes; Back bottom left, Create bottom right (retail navigation)
	if CharacterCreateNameEdit then
		CharacterCreateNameEdit:ClearAllPoints();
		CharacterCreateNameEdit:SetPoint("BOTTOM", frame, "BOTTOM", 0, 50);
	end
	if CharacterCreateRandomName then
		CharacterCreateRandomName:ClearAllPoints();
		CharacterCreateRandomName:SetPoint("LEFT", CharacterCreateNameEdit, "RIGHT", 8, 0);
	end
	CharCreateBackButton:ClearAllPoints();
	CharCreateBackButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 46, 28);
	CharCreateBackButton:SetWidth(250);
	CharCreateBackButton:SetHeight(58);
	CharCreateOkayButton:ClearAllPoints();
	CharCreateOkayButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -46, 28);
	CharCreateOkayButton:SetWidth(250);
	CharCreateOkayButton:SetHeight(58);
	if CharacterCreateRotateLeft and CharacterCreateRotateRight then
		CharacterCreateRotateLeft:ClearAllPoints();
		CharacterCreateRotateLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 200);
		CharacterCreateRotateRight:ClearAllPoints();
		CharacterCreateRotateRight:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 200);
	end
	if GlueRetailButton_Update then
		GlueRetailButton_Update(CharCreateBackButton);
		GlueRetailButton_Update(CharCreateOkayButton);
	end
end

---------------------------------------------------------------------------
-- hooks into the 3.3.5 flow (wrapped by hand: the XML calls these by name)
---------------------------------------------------------------------------
local function After(name, func)
	local original = _G[name];
	if not original then
		return;
	end
	_G[name] = function(...)
		local a, b, c = original(...);
		func(...);
		return a, b, c;
	end
end

After("CharacterCreate_OnShow", function() CR.Setup(); end);
After("CharacterCreateEnumerateRaces", function(...) CR.Setup(); CR.LayoutRaces(...); end);
After("CharacterCreateEnumerateClasses", function(...) CR.Setup(); CR.LayoutClasses(...); end);
