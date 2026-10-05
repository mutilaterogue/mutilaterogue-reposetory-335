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

local RACE_SIZE, RACE_SPACING = 64, 82;
local CLASS_SIZE, CLASS_SPACING = 52, 80;

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
-- round icons (retail masks them): the DLL mask textures (XMLExt.lua)
local function AddRoundMask(button, textures, size)
	if not (button.CreateMaskTexture and TextureAddMask and TextureSetIsMask) then
		return;
	end
	local mask = button:CreateMaskTexture();
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask");
	mask:SetVertexColor(1, 1, 1, 0);
	mask:SetPoint("CENTER");
	mask:SetWidth(size);
	mask:SetHeight(size);
	for _, texture in ipairs(textures) do
		if texture then
			texture:AddMaskTexture(mask);
		end
	end
end

local function AddRings(button, size, ring)
	-- the metal ring over the icon, the gold ring when chosen
	button.CRRing = button:CreateTexture(nil, "OVERLAY");
	button.CRRing:SetPoint("CENTER");
	button.CRRing:SetWidth(size * 1.6);
	button.CRRing:SetHeight(size * 1.6);
	SetAtlasIf(button.CRRing, ring or "charactercreate-ring-metaldark");
	-- the gold ring: the full size art (the small one is blurry), on a child frame over the metal ring
	local checked = button:GetCheckedTexture();
	if checked then
		checked:SetAlpha(0);
	end
	local over = CreateFrame("Frame", nil, button);
	over:SetAllPoints(button);
	over:SetFrameLevel(button:GetFrameLevel() + 2);
	button.CRSelect = over:CreateTexture(nil, "OVERLAY");
	button.CRSelect:SetPoint("CENTER");
	button.CRSelect:SetWidth(size + 16);
	button.CRSelect:SetHeight(size + 16);
	SetAtlasIf(button.CRSelect, "charactercreate-ring-select");
	button.CRSelect:Hide();
	over:SetScript("OnUpdate", function()
		if button:GetChecked() then
			button.CRSelect:Show();
		else
			button.CRSelect:Hide();
		end
	end);
end

local function StyleIconButton(button, size, small, ring)
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
			texture:SetWidth(size - 8);
			texture:SetHeight(size - 8);
		end
	end
	AddRoundMask(button, { normal or false, pushed or false }, size - 12);

	AddRings(button, size, ring);
	local highlight = button:GetHighlightTexture();
	if highlight then
		highlight:SetAlpha(0);
	end
end

local function RoundIcon(texture, atlas, fallback, mirror)
	if not texture then
		return;
	end
	if not SetAtlasIf(texture, atlas) then
		if fallback then
			texture:SetTexture(fallback);
		end
		return;
	end
	-- the right column looks to the middle (retail): the atlas mirrored
	if mirror then
		local info = C_Texture.GetAtlasInfo(atlas);
		local left, right = info.leftTexCoord or info.left, info.rightTexCoord or info.right;
		local top, bottom = info.topTexCoord or info.top, info.bottomTexCoord or info.bottom;
		if left and right and top and bottom then
			texture:SetTexCoord(right, left, top, bottom);
		end
	end
end

---------------------------------------------------------------------------
-- races / classes after the 3.3.5 enumeration
---------------------------------------------------------------------------
-- race tooltip (retail): the name, the description, the racial traits
local function RaceTooltipText(button)
	local file = button.crFile;
	local text = "|cffffd100" .. (button.name or "") .. "|r";
	if not button.enable then
		return text .. "|n|n" .. (button.tooltip or "");
	end
	local flavor = GetFlavorText and GetFlavorText("RACE_INFO_" .. file, GetSelectedSex()) or _G["RACE_INFO_" .. file];
	if flavor and flavor ~= "" then
		text = text .. "|n|n" .. flavor;
	end
	local index = 1;
	local ability = _G["ABILITY_INFO_" .. file .. index];
	while ability do
		text = text .. "|n|n" .. ability;
		index = index + 1;
		ability = _G["ABILITY_INFO_" .. file .. index];
	end
	return text;
end

function CR.HookRaceTooltip(button)
	if button.crTooltip then
		return;
	end
	button.crTooltip = true;
	button:SetScript("OnEnter", function(self)
		if self.crHorde then
			GlueTooltip_SetOwner(self, CharacterCreateTooltip, -10, 0, "TOPRIGHT", "TOPLEFT");
		else
			GlueTooltip_SetOwner(self, CharacterCreateTooltip, 10, 0, "TOPLEFT", "TOPRIGHT");
		end
		-- after SetOwner (it resets the width): the long race text wraps
		local line = CharacterCreateTooltipTextLeft1;
		if line then
			line:SetWidth(340);
			line:SetJustifyH("LEFT");
		end
		GlueTooltip_SetText(RaceTooltipText(self), CharacterCreateTooltip);
	end);
	button:SetScript("OnLeave", function()
		CharacterCreateTooltip:Hide();
	end);
end

function CR.LayoutRaces(...)
	local sex = GetSelectedSex();
	local alliance, horde = 0, 0;
	local index = 1;
	for i = 1, select("#", ...), 3 do
		local file = select(i + 1, ...);
		local button = _G["CharacterCreateRaceButton" .. index];
		if button then
			local _, faction = GetFactionForRace(index);
			local isHorde = faction == "Horde";
			local ring = isHorde and "charactercreate-ring-horde" or "charactercreate-ring-alliance";
			StyleIconButton(button, RACE_SIZE, false, ring);
			SetAtlasIf(button.CRRing, button.enable and ring or ring .. "-disabled");
			local atlas = RaceAtlas(file, sex);
			button.crFile, button.crHorde = strupper(file), isHorde;
			CR.HookRaceTooltip(button);
			RoundIcon(_G[button:GetName() .. "NormalTexture"], atlas, nil, isHorde);
			RoundIcon(_G[button:GetName() .. "PushedTexture"], atlas, nil, isHorde);
			button:ClearAllPoints();
			if isHorde then
				button:SetPoint("TOPRIGHT", CharacterCreateFrame, "TOPRIGHT", -44, -150 - horde * RACE_SPACING);
				horde = horde + 1;
			else
				button:SetPoint("TOPLEFT", CharacterCreateFrame, "TOPLEFT", 44, -150 - alliance * RACE_SPACING);
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
			-- retail: an unavailable class is only grey (no red cross)
			local disabled = _G[button:GetName() .. "DisableTexture"];
			if disabled then
				disabled:SetAlpha(0);
			end
			SetAtlasIf(button.CRRing, button.enable and "charactercreate-ring-metaldark" or "charactercreate-ring-metaldark-disabled");
			if not button.CRLabel then
				button.CRLabel = button:CreateFontString(nil, "OVERLAY", "GlueFontNormalSmall");
				button.CRLabel:SetPoint("TOP", button, "BOTTOM", 0, -6);
			end
			button.CRLabel:SetText(select(i, ...));
			if button.enable then
				button.CRLabel:SetTextColor(1, 0.82, 0);
			else
				button.CRLabel:SetTextColor(0.5, 0.5, 0.5);
			end
			button:ClearAllPoints();
			button:SetPoint("BOTTOM", CharacterCreateFrame, "BOTTOM", (index - (count + 1) / 2) * CLASS_SPACING, 64);
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
	--[[ the side vignette covers the whole screen: darker everywhere, off
	local sides = Vignette(HasAtlas("charactercreate-vignette-sides-widescreen") and "charactercreate-vignette-sides-widescreen" or "charactercreate-vignette-sides",
		"TOPLEFT", "TOPLEFT", 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0); ]]

	-- faction crests over the race columns
	local function Crest(atlas, point, x, text)
		local crest = frame:CreateTexture(nil, "ARTWORK");
		CR[point == "LEFT" and "AllianceCrest" or "HordeCrest"] = crest;
		crest:SetWidth(48);
		crest:SetHeight(48);
		crest:SetPoint("TOP" .. point, frame, "TOP" .. point, x, -30);
		if not SetAtlasIf(crest, atlas) then
			crest:Hide();
		end
		-- the faction name next to it (retail: ALLIANCE / HORDE)
		local label = frame:CreateFontString(nil, "ARTWORK", "GlueFontNormal");
		CR[point == "LEFT" and "AllianceLabel" or "HordeLabel"] = label;
		label:SetText(text or "");
		if point == "LEFT" then
			label:SetPoint("LEFT", crest, "RIGHT", 4, 0);
		else
			label:SetPoint("RIGHT", crest, "LEFT", -4, 0);
		end
	end
	Crest("charactercreate-icon-alliance", "LEFT", 40, "АЛЬЯНС");
	Crest("charactercreate-icon-horde", "RIGHT", -40, "ОРДА");

	-- gender: top center
	-- gender: the retail male / female symbols, the gold one when chosen
	for i, button in ipairs({ CharacterCreateGenderButtonMale, CharacterCreateGenderButtonFemale }) do
		if button then
			local gender = i == 1 and "male" or "female";
			local name = button:GetName();
			Hide(name .. "Shadow");
			Hide(name .. "BevelEdge");
			Hide(name .. "Text");
			button:SetWidth(52);
			button:SetHeight(52);
			for _, key in ipairs({ "NormalTexture", "PushedTexture" }) do
				local texture = _G[name .. key];
				if texture and SetAtlasIf(texture, "charactercreate-gendericon-" .. gender) then
					texture:ClearAllPoints();
					texture:SetPoint("TOPLEFT", 1, -1);
					texture:SetPoint("BOTTOMRIGHT", -1, 1);
				end
			end
			local checked = button:GetCheckedTexture();
			if checked and SetAtlasIf(checked, "charactercreate-gendericon-" .. gender .. "-selected") then
				checked:ClearAllPoints();
				checked:SetPoint("TOPLEFT", 1, -1);
				checked:SetPoint("BOTTOMRIGHT", -1, 1);
				checked:SetBlendMode("BLEND");
			end
			AddRoundMask(button, { _G[name .. "NormalTexture"] or false, _G[name .. "PushedTexture"] or false, checked or false }, 44);
			-- the rings of the other icon buttons; the gold symbol stays the chosen one's art
			AddRings(button, 52);
			if checked then
				checked:SetAlpha(1);
			end
			local highlight = button:GetHighlightTexture();
			if highlight then
				highlight:SetAlpha(0);
			end
			button:ClearAllPoints();
			button:SetPoint("TOP", frame, "TOP", (i - 1.5) * 60, -24);
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
				row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -120, -220);
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
	CharCreateBackButton:SetWidth(230);
	CharCreateBackButton:SetHeight(50);
	CharCreateOkayButton:ClearAllPoints();
	CharCreateOkayButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -46, 28);
	CharCreateOkayButton:SetWidth(230);
	CharCreateOkayButton:SetHeight(50);
	-- no rotate buttons (retail: drag the model)
	Hide("CharacterCreateRotateLeft");
	Hide("CharacterCreateRotateRight");
	if GlueRetailButton_Update then
		GlueRetailButton_Update(CharCreateBackButton);
		GlueRetailButton_Update(CharCreateOkayButton);
	end
end

---------------------------------------------------------------------------
-- camera (retail zooms on the customization): the scene moved toward the camera, smoothly
--   x - toward the camera, z - up; tune the targets here
---------------------------------------------------------------------------
local CAMERA = {
	select = { 0, 0, 0 },
	body = { 1.5, 0, -0.1 },
	head = { 3.6, 0, -0.85 },
};
-- the customization rows (3.3.5 order: skin, face, hair, hair color, facial hair)
local ROW_CAMERA = { "body", "head", "head", "head", "head" };

function CR.SetCamera(name)
	local target = CAMERA[name] or CAMERA.select;
	CR.cameraTarget = target;
	if not CR.cameraFrame then
		CR.cameraFrame = CreateFrame("Frame", nil, CharacterCreate);
		CR.cameraPosition = { 0, 0, 0 };
		CR.cameraFrame:SetScript("OnUpdate", function(self, elapsed)
			local position, goal = CR.cameraPosition, CR.cameraTarget;
			local done = true;
			for i = 1, 3 do
				local delta = goal[i] - position[i];
				if math.abs(delta) > 0.001 then
					position[i] = position[i] + delta * math.min(1, (elapsed or 0.016) * 8);
					done = false;
				else
					position[i] = goal[i];
				end
			end
			if CharacterCreate and CharacterCreate.SetPosition then
				CharacterCreate:SetPosition(position[1], position[2], position[3]);
			end
			if done then
				self:Hide();
			end
		end);
	end
	CR.cameraFrame:Show();
end

---------------------------------------------------------------------------
-- two stages (retail): 1 - race / class / gender, 2 - the appearance and the name only
---------------------------------------------------------------------------
local function SetShownList(list, shown)
	for _, region in ipairs(list) do
		if region then
			if shown then
				region:Show();
			else
				region:Hide();
			end
		end
	end
end

function CR.StageFrames()
	local first, second = {}, {};
	for i = 1, MAX_RACES do
		local button = _G["CharacterCreateRaceButton" .. i];
		if button and (CharacterCreate.numRaces or 0) >= i then
			table.insert(first, button);
		end
	end
	for i = 1, MAX_CLASSES_PER_RACE do
		local button = _G["CharacterCreateClassButton" .. i];
		if button and (CharacterCreate.numClasses or 0) >= i then
			table.insert(first, button);
		end
	end
	for _, region in ipairs({ CharacterCreateGenderButtonMale, CharacterCreateGenderButtonFemale, CR.AllianceCrest, CR.HordeCrest, CR.AllianceLabel or false, CR.HordeLabel or false }) do
		table.insert(first, region);
	end
	for i = 1, NUM_CHAR_CUSTOMIZATIONS do
		table.insert(second, _G["CharacterCustomizationButtonFrame" .. i]);
	end
	for _, region in ipairs({ CharCreateRandomizeButton, CharacterCreateNameEdit }) do
		table.insert(second, region);
	end
	return first, second;
end

function CR.SetStage(stage)
	CR.stage = stage;
	local first, second = CR.StageFrames();
	SetShownList(first, stage == 1);
	SetShownList(second, stage == 2);
	if CharacterCreateRandomName then
		if stage == 2 and CharacterCreateRandomName.crShown then
			CharacterCreateRandomName:Show();
		else
			CharacterCreateRandomName:Hide();
		end
	end
	CR.SetCamera(stage == 1 and "select" or "body");
	CharCreateOkayButton:SetText(stage == 1 and (CUSTOMIZE or "Настроить") or (CHARACTER_CREATE_ACCEPT or ACCEPT));
	if stage == 2 and CharacterCreateNameEdit then
		CharacterCreateNameEdit:SetFocus();
	end
end

---------------------------------------------------------------------------
-- hooks into the 3.3.5 flow (wrapped by hand: the XML calls these by name)
---------------------------------------------------------------------------
-- the glue tooltip keeps old anchors and the race text width: cleared on every owner
local setOwner = GlueTooltip_SetOwner;
GlueTooltip_SetOwner = function(self, tooltip, ...)
	tooltip = tooltip or GlueTooltip;
	if tooltip then
		tooltip:ClearAllPoints();
		local line = tooltip.GetName and _G[tooltip:GetName() .. "TextLeft1"];
		if line then
			line:SetWidth(0);
			line:SetJustifyH("CENTER");
		end
	end
	return setOwner(self, tooltip, ...);
end;

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

-- a customization arrow: the camera to what it changes
After("CharacterCustomization_Left", function(id) if CR.stage == 2 then CR.SetCamera(ROW_CAMERA[id] or "body"); end end);
After("CharacterCustomization_Right", function(id) if CR.stage == 2 then CR.SetCamera(ROW_CAMERA[id] or "body"); end end);

After("CharacterCreate_OnShow", function()
	CR.Setup();
	if CharacterCreateRandomName then
		CharacterCreateRandomName.crShown = CharacterCreateRandomName:IsShown();
	end
	CR.SetStage(1);
end);

-- Okay / Back by the stage: Okay on the first one goes to the appearance, Back on the second one comes back
local okay, back = CharacterCreate_Okay, CharacterCreate_Back;
CharacterCreate_Okay = function(...)
	if CR.stage == 1 then
		CR.SetStage(2);
		return;
	end
	return okay(...);
end;
CharacterCreate_Back = function(...)
	if CR.stage == 2 then
		CR.SetStage(1);
		return;
	end
	return back(...);
end;
After("CharacterCreateEnumerateRaces", function(...) CR.Setup(); CR.LayoutRaces(...); end);
After("CharacterCreateEnumerateClasses", function(...) CR.Setup(); CR.LayoutClasses(...); end);

-- retail has no blue Death Knight buttons: the 3.3.5 swap would put its old panel art over the red buttons
CharacterCreate_DeathKnightSwap = function() end;
