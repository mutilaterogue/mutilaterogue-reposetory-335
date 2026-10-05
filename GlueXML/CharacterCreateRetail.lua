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

local function AddRings(button, size, ring, shrink)
	-- the metal ring over the icon, the gold ring when chosen
	button.CRRing = button:CreateTexture(nil, "OVERLAY");
	button.CRRing:SetPoint("CENTER");
	button.CRRing:SetWidth(size * 1.6 - (shrink or 0));
	button.CRRing:SetHeight(size * 1.6 - (shrink or 0));
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

	AddRings(button, size, ring, small and 3 or 0);
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
-- the appearance (stage 2, retail): category icons and the option rows on the left,
-- each row "< option >" in the retail dropdown box; the name box at the bottom
---------------------------------------------------------------------------
-- the categories: icon, camera; clicking one only moves the camera (3.3.5 has no option groups)
local CATEGORIES = {
	{ "body", "body" },
	{ "head", "head" },
	{ "hair", "head" },
};

local function ArrowButton(parent, atlas)
	local button = CreateFrame("Button", nil, parent);
	button:SetWidth(38);
	button:SetHeight(38);
	local normal = button:CreateTexture(nil, "ARTWORK");
	normal:SetAllPoints(button);
	SetAtlasIf(normal, atlas);
	button:SetNormalTexture(normal);
	local pushed = button:CreateTexture(nil, "ARTWORK");
	pushed:SetAllPoints(button);
	SetAtlasIf(pushed, atlas .. "-down");
	button:SetPushedTexture(pushed);
	local highlight = button:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAllPoints(button);
	SetAtlasIf(highlight, atlas);
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(0.3);
	button:SetHighlightTexture(highlight);
	return button;
end

function CR.SelectCategory(index)
	CR.category = index;
	for i, tab in ipairs(CR.Tabs or {}) do
		SetAtlasIf(tab.Icon, "charactercreate-icon-customize-" .. CATEGORIES[i][1] .. (i == index and "-selected" or ""));
	end
	CR.SetCamera(CATEGORIES[index][2]);
end

function CR.StyleCustomization(frame)
	-- the category icons over the rows
	CR.Tabs = {};
	for i, category in ipairs(CATEGORIES) do
		local tab = CreateFrame("Button", nil, frame);
		tab:SetWidth(64);
		tab:SetHeight(64);
		tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 70 + (i - 1) * 74, -150);
		tab.Icon = tab:CreateTexture(nil, "ARTWORK");
		tab.Icon:SetAllPoints(tab);
		tab:SetScript("OnClick", function()
			CR.SelectCategory(i);
			PlaySound("gsCharacterCreationLook");
		end);
		CR.Tabs[i] = tab;
		SetAtlasIf(tab.Icon, "charactercreate-icon-customize-" .. category[1] .. (i == 1 and "-selected" or ""));
	end

	-- the option rows: "< name >" in the dropdown box, the 3.3.5 arrow buttons replaced
	local previous;
	for i = 1, NUM_CHAR_CUSTOMIZATIONS do
		local row = _G["CharacterCustomizationButtonFrame" .. i];
		if row then
			local name = row:GetName();
			Hide(name .. "Left");
			Hide(name .. "Right");
			Hide(name .. "Middle");
			Hide(name .. "LeftButton");
			Hide(name .. "RightButton");
			row:SetWidth(300);
			row:SetHeight(40);
			row:ClearAllPoints();
			if previous then
				row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10);
			else
				row:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -240);
			end
			previous = row;

			local back = ArrowButton(row, "charactercreate-customize-backbutton");
			back:SetPoint("LEFT", row, "LEFT", 0, 0);
			back:SetScript("OnClick", function()
				CharacterCustomization_Left(row:GetID());
				PlaySound("gsCharacterCreationLook");
			end);
			local nextButton = ArrowButton(row, "charactercreate-customize-nextbutton");
			nextButton:SetPoint("RIGHT", row, "RIGHT", 0, 0);
			nextButton:SetScript("OnClick", function()
				CharacterCustomization_Right(row:GetID());
				PlaySound("gsCharacterCreationLook");
			end);

			local box = row:CreateTexture(nil, "BACKGROUND");
			box:SetPoint("LEFT", back, "RIGHT", 4, 0);
			box:SetPoint("RIGHT", nextButton, "LEFT", -4, 0);
			box:SetHeight(38);
			SetAtlasIf(box, "charactercreate-customize-dropdownbox");

			local text = _G[name .. "Text"];
			if text then
				text:ClearAllPoints();
				text:SetPoint("CENTER", box, "CENTER", 0, 0);
				text:SetFontObject(GlueFontHighlight);
			end
		end
	end

	-- randomize: the retail dice under the rows
	local random = CharCreateRandomizeButton;
	if random and previous then
		for _, key in ipairs({ "Left", "Right", "Center", "Glow" }) do
			if random[key] then
				random[key]:SetAlpha(0);
			end
		end
		random.Left = nil;	-- GlueRetailButton_Update leaves it alone
		random:SetWidth(300);
		random:SetHeight(40);
		random:ClearAllPoints();
		random:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -16);
		local box = random:CreateTexture(nil, "BACKGROUND");
		box:SetAllPoints(random);
		SetAtlasIf(box, "charactercreate-customize-dropdownbox");
		local dice = random:CreateTexture(nil, "ARTWORK");
		dice:SetWidth(24);
		dice:SetHeight(24);
		dice:SetPoint("RIGHT", random:GetFontString() or random, "LEFT", -8, 0);
		SetAtlasIf(dice, "charactercreate-icon-dice");
	end

	-- the name: the dropdown box art at the bottom center, the random name dice next to it
	local edit = CharacterCreateNameEdit;
	if edit then
		if edit.SetBackdrop then
			edit:SetBackdrop(nil);
		end
		edit:SetWidth(260);
		edit:SetHeight(40);
		edit:ClearAllPoints();
		edit:SetPoint("BOTTOM", frame, "BOTTOM", 0, 40);
		edit:SetTextInsets(12, 12, 0, 0);
		edit:SetJustifyH("CENTER");
		local box = edit:CreateTexture(nil, "BACKGROUND");
		box:SetAllPoints(edit);
		SetAtlasIf(box, "charactercreate-customize-dropdownbox");
	end
	local randomName = CharacterCreateRandomName;
	if randomName and edit then
		for _, key in ipairs({ "Left", "Right", "Center", "Glow" }) do
			if randomName[key] then
				randomName[key]:SetAlpha(0);
			end
		end
		randomName.Left = nil;
		randomName:SetText("");
		randomName:SetWidth(38);
		randomName:SetHeight(38);
		randomName:ClearAllPoints();
		randomName:SetPoint("LEFT", edit, "RIGHT", 6, 0);
		local dice = randomName:CreateTexture(nil, "ARTWORK");
		dice:SetWidth(28);
		dice:SetHeight(28);
		dice:SetPoint("CENTER");
		SetAtlasIf(dice, "charactercreate-icon-dice");
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

	CR.StyleCustomization(frame);

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
-- the camera per stage / category: "head" shows the zoomed background
local ROW_CAMERA = { "body", "head", "head", "head", "head" };

-- the face close up like that client (SetFaceCustomizeCamera): no camera moves, the background is swapped
-- for its zoomed copy Interface\Glues\Models\UI_<RACE>_ZOOM\UI_<RACE>_ZOOM.m2 (those models must be in the MPQ)
function CR.SetCamera(name)
	local zoomed = name == "head";
	if zoomed == (CR.zoomed or false) then
		return;
	end
	-- the background the client picked (Troll -> Orc, Gnome -> Dwarf, Death Knight -> DeathKnight)
	local background = GetCreateBackgroundModel and GetCreateBackgroundModel();
	if not background then
		return;
	end
	-- not SetBackgroundModel: it would look up the ambience / lights by the "_ZOOM" name (none);
	-- the same music goes on, the lights are the race's own
	local name = background .. (zoomed and "_ZOOM" or "");
	SetCharCustomizeBackground("Interface\\Glues\\Models\\UI_" .. name .. "\\UI_" .. name .. ".m2");
	if SetLighting then
		SetLighting(CharacterCreate, strupper(background));
	end
	CR.zoomed = zoomed;
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
	for _, tab in ipairs(CR.Tabs or {}) do
		table.insert(second, tab);
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
	if stage == 2 and CR.Tabs then
		CR.SelectCategory(1);
	else
		CR.SetCamera("select");
	end
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
	CR.zoomed = false;	-- the client loads the normal background
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

