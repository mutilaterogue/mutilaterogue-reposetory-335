-- Specialization tab (retail ClassSpecializationsFrame): the primary 3.3.5 talent tree,
-- GetPrimaryTalentTree / SetPrimaryTalentTree (Cataclysm API of this client).
-- Until a tree is chosen the talents tab opens here.

PlayerSpellsSpecializations = {};
local PS = PlayerSpellsSpecializations;

-- retail SPEC_FORMAT_STRINGS by the 3.3.5 tab order: spec-thumbnail-<class>-<spec>
PS.SPEC_KEYS = {
	WARRIOR = { "arms", "fury", "protection" },
	PALADIN = { "holy", "protection", "retribution" },
	HUNTER = { "beastmastery", "marksmanship", "survival" },
	ROGUE = { "assassination", "outlaw", "subtlety" },
	PRIEST = { "discipline", "holy", "shadow" },
	DEATHKNIGHT = { "blood", "frost", "unholy" },
	SHAMAN = { "elemental", "enhancement", "restoration" },
	MAGE = { "arcane", "fire", "frost" },
	WARLOCK = { "affliction", "demonology", "destruction" },
	DRUID = { "balance", "feral", "restoration" },
};

function PS.SpecKey(tab)
	local _, classFile = UnitClass("player");
	local spec = PS.SPEC_KEYS[classFile] and PS.SPEC_KEYS[classFile][tab];
	return spec and (classFile:lower() .. "-" .. spec);
end

local function HasAtlas(atlas)
	return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil;
end

local function SetAtlasOr(texture, atlas, r, g, b, a)
	if HasAtlas(atlas) then
		texture:SetAtlas(atlas);
	elseif r then
		texture:SetTexture(r, g, b, a);
	end
end

local function Font(name, fallback)
	return _G[name] and name or fallback;
end

-- primary tree of the active talent group (0 / nil = not chosen)
function PS.GetPrimary()
	if not GetPrimaryTalentTree then
		return nil;
	end
	local tree = GetPrimaryTalentTree(false, false, GetActiveTalentGroup(false, false));
	if tree and tree > 0 then
		return tree;
	end
	return nil;
end

local function CreateSpecColumn(parent, index)
	local column = CreateFrame("Frame", nil, parent);
	column.HoverBackground = column:CreateTexture(nil, "BACKGROUND", nil, 1);
	column.HoverBackground:SetAllPoints();
	SetAtlasOr(column.HoverBackground, "spec-hover-background", 1, 1, 1, 0.04);
	column.HoverBackground:SetBlendMode("ADD");
	column.HoverBackground:Hide();

	column.Selected = column:CreateTexture(nil, "BACKGROUND", nil, 2);
	column.Selected:SetAllPoints();
	SetAtlasOr(column.Selected, "spec-selected-background1", 1, 0.82, 0, 0.06);
	column.Selected:SetBlendMode("ADD");
	column.Selected:SetAlpha(0.3);

	column.SpecImage = column:CreateTexture(nil, "ARTWORK");
	column.SpecImage:SetPoint("TOP", 0, -38);
	column.SpecImage:SetWidth(306);
	column.SpecImage:SetHeight(186);
	column.Border = column:CreateTexture(nil, "OVERLAY");
	column.Border:SetPoint("CENTER", column.SpecImage);
	column.Border:SetWidth(306);
	column.Border:SetHeight(186);

	column.SpecName = column:CreateFontString(nil, "ARTWORK", Font("Game30Font", "GameFontNormalHuge"));
	column.SpecName:SetPoint("TOP", column.SpecImage, "BOTTOM", 0, -54);
	column.Description = column:CreateFontString(nil, "ARTWORK", Font("GameFontNormalMed2", "GameFontNormal"));
	column.Description:SetPoint("TOP", column.SpecName, "BOTTOM", 0, -24);
	column.Description:SetWidth(280);
	column.Description:SetJustifyH("CENTER");

	-- the tree icon in the retail sample ability ring
	column.Ability = CreateFrame("Frame", nil, column);
	column.Ability:SetWidth(70);
	column.Ability:SetHeight(70);
	column.Ability:SetPoint("BOTTOM", 0, 265);
	column.Ability.Icon = column.Ability:CreateTexture(nil, "ARTWORK");
	column.Ability.Icon:SetPoint("CENTER");
	column.Ability.Icon:SetWidth(58);
	column.Ability.Icon:SetHeight(58);
	column.Ability.Ring = column.Ability:CreateTexture(nil, "OVERLAY");
	column.Ability.Ring:SetPoint("CENTER");
	column.Ability.Ring:SetWidth(70);
	column.Ability.Ring:SetHeight(70);
	SetAtlasOr(column.Ability.Ring, "spec-sampleabilityring");

	column.ActivatedText = column:CreateFontString(nil, "ARTWORK", Font("GameFontNormalLarge2", "GameFontNormalLarge"));
	column.ActivatedText:SetPoint("BOTTOM", 0, 97);
	column.ActivatedText:SetText(SPEC_ACTIVE);

	column.ActivateButton = CreateFrame("Button", nil, column, "UIPanelButtonTemplate");
	column.ActivateButton:SetWidth(160);
	column.ActivateButton:SetHeight(22);
	column.ActivateButton:SetPoint("BOTTOM", 0, 95);
	column.ActivateButton:SetText(TALENT_SPEC_ACTIVATE);
	column.ActivateButton:SetScript("OnClick", function()
		SetPrimaryTalentTree(index);
		PS.justChose = true;
	end);

	if index > 1 then
		column.Divider = column:CreateTexture(nil, "ARTWORK");
		column.Divider:SetPoint("CENTER", column, "LEFT", 0, 0);
		SetAtlasOr(column.Divider, "spec-columndivider", 1, 1, 1, 0.15);
		if not HasAtlas("spec-columndivider") then
			column.Divider:SetWidth(2);
			column.Divider:SetHeight(700);
		else
			local info = C_Texture.GetAtlasInfo("spec-columndivider");
			column.Divider:SetWidth(info.width or 8);
			column.Divider:SetHeight(info.height or 700);
		end
	end

	column:EnableMouse(true);
	column:SetScript("OnEnter", function(self) self.HoverBackground:Show(); end);
	column:SetScript("OnLeave", function(self) self.HoverBackground:Hide(); end);
	return column;
end

function PS.Create(container)
	local frame = CreateFrame("Frame", "PlayerSpellsSpecializationsFrame", container);
	frame:SetAllPoints(container);
	frame.BlackBG = frame:CreateTexture(nil, "BACKGROUND", nil, -2);
	frame.BlackBG:SetAllPoints();
	frame.BlackBG:SetTexture(0, 0, 0, 1);
	frame.Background = frame:CreateTexture(nil, "BACKGROUND", nil, -1);
	frame.Background:SetAllPoints();
	SetAtlasOr(frame.Background, "spec-background");
	frame.columns = {};
	frame:SetScript("OnShow", PS.Refresh);
	frame:RegisterEvent("PLAYER_TALENT_UPDATE");
	frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	frame:RegisterEvent("CHARACTER_POINTS_CHANGED");
	frame:SetScript("OnEvent", function(self)
		if self:IsShown() then
			PS.Refresh(self);
		end
		-- the tree is chosen: on to the talents
		if PS.justChose and PS.GetPrimary() then
			PS.justChose = nil;
			if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
				PlayerSpellsFrame:SetTab(PlayerSpellsFrame.talentTabID);
			end
		end
	end);
	PS.frame = frame;
	return frame;
end

function PS.Refresh(frame)
	frame = frame or PS.frame;
	local group = GetActiveTalentGroup(false, false);
	local numTabs = GetNumTalentTabs(false, false) or 0;
	local width = frame:GetWidth() / math.max(numTabs, 1);
	local primary = PS.GetPrimary();
	for i = 1, numTabs do
		local column = frame.columns[i] or CreateSpecColumn(frame, i);
		frame.columns[i] = column;
		column:ClearAllPoints();
		column:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * width, 0);
		column:SetWidth(width);
		column:SetHeight(frame:GetHeight());

		local name, icon, pointsSpent = GetTalentTabInfo(i, false, false, group);
		local key = PS.SpecKey(i);
		if HasAtlas(key and ("spec-thumbnail-" .. key)) then
			column.SpecImage:SetAtlas("spec-thumbnail-" .. key);
		else
			column.SpecImage:SetTexture(icon);
			column.SpecImage:SetTexCoord(0.08, 0.92, 0.25, 0.75);
		end
		column.SpecName:SetText(name);
		column.Description:SetText((TALENT_POINTS or "") .. ": " .. (pointsSpent or 0));
		column.Ability.Icon:SetTexture(icon);
		SetPortraitToTexture(column.Ability.Icon, icon);

		local active = primary == i;
		SetAtlasOr(column.Border, active and "spec-thumbnailborder-on" or "spec-thumbnailborder-off");
		column.Selected:SetShown(active);
		column.ActivatedText:SetShown(active);
		column.ActivateButton:SetShown(not active);
		column:Show();
	end
	for i = numTabs + 1, #frame.columns do
		frame.columns[i]:Hide();
	end
end
