-- The retail (12.1.5) experience / reputation bars on 3.3.5 (StatusTrackingBarRetail.xml).
-- Experience: the fill (rested color while rested), the rested prediction ahead of it, the rested pip; gone at max level.
-- Reputation: the watched faction, colored by standing (ReputationBar.lua); a click opens the reputation tab.
-- The text shows on mouse over, as in retail.

local BAR_WIDTH = 563;
local BAR_HEIGHT = 17;

local REP_ATLASES = {
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Red",
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Red",
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Orange",
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Yellow",
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
	"UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
};

-- a fill texture: the atlas cut at the value (left part of the atlas, as wide as the value)
local function SetFill(texture, atlas, fraction)
	fraction = math.max(0, math.min(1, fraction or 0));
	local info = C_Texture.GetAtlasInfo(atlas);
	if not info or fraction <= 0 then
		texture:Hide();
		return;
	end
	local file = info.filename or info.file;
	local l, r = info.leftTexCoord or info.left, info.rightTexCoord or info.right;
	local t, b = info.topTexCoord or info.top, info.bottomTexCoord or info.bottom;
	texture:SetTexture(file);
	texture:SetTexCoord(l, l + (r - l) * fraction, t, b);
	texture:SetWidth(BAR_WIDTH * fraction);
	texture:Show();
end

local function UpdateExp(bar)
	local maxLevel = MAX_PLAYER_LEVEL_TABLE and MAX_PLAYER_LEVEL_TABLE[GetAccountExpansionLevel()] or MAX_PLAYER_LEVEL;
	if UnitLevel("player") >= maxLevel then
		bar:Hide();
		return false;
	end
	local current, max = UnitXP("player"), UnitXPMax("player");
	if max <= 0 then
		max = 1;
	end
	local rested = GetXPExhaustion();
	local isRested = rested and rested > 0;
	SetFill(bar.Fill, isRested and "UI-HUD-ExperienceBar-Fill-Rested" or "UI-HUD-ExperienceBar-Fill-Experience", current / max);

	local tick = bar.ExhaustionTick;
	if isRested then
		local predicted = math.min(current + rested, max) / max;
		SetFill(bar.Prediction, "UI-HUD-ExperienceBar-Fill-Prediction", predicted);
		tick:ClearAllPoints();
		tick:SetPoint("CENTER", bar.Background, "LEFT", BAR_WIDTH * predicted, 2);
		-- retail hides the pip at the bar's end
		if predicted < 1 then
			tick:Show();
		else
			tick:Hide();
		end
	else
		bar.Prediction:Hide();
		tick:Hide();
	end

	local text = XP .. " " .. current .. " / " .. max;
	if isRested then
		text = text .. " (+" .. rested .. ")";
	end
	bar.OverlayFrame.Text:SetText(text);
	bar:Show();
	return true;
end

local function UpdateRep(bar)
	local name, standing, min, max, value = GetWatchedFactionInfo();
	if not name then
		bar:Hide();
		return false;
	end
	local range = max - min;
	if range <= 0 then
		range = 1;
	end
	SetFill(bar.Fill, REP_ATLASES[standing] or REP_ATLASES[4], (value - min) / range);
	bar.OverlayFrame.Text:SetText(name .. " " .. (_G["FACTION_STANDING_LABEL" .. standing] or "") .. " " .. (value - min) .. " / " .. range);
	bar:Show();
	return true;
end

-- the main bar at the bottom, the second over it; MainMenuBar holds them (the main action bar stands on its top)
local layoutPending;

function StatusTrackingBarRetail_Update(self)
	self = self or StatusTrackingBarRetailManager;
	local exp, rep = self.ExpBar, self.RepBar;
	local shown = {};
	if UpdateExp(exp) then
		shown[#shown + 1] = exp;
	end
	if UpdateRep(rep) then
		shown[#shown + 1] = rep;
	end
	for i, bar in ipairs(shown) do
		bar:ClearAllPoints();
		bar:SetPoint("BOTTOM", self, "BOTTOM", 0, (i - 1) * BAR_HEIGHT);
	end
	local height = math.max(1, #shown * BAR_HEIGHT);
	self:SetHeight(height);
	-- the action buttons hang on MainMenuBar's top: not in combat
	if InCombatLockdown() then
		layoutPending = true;
	else
		layoutPending = nil;
		MainMenuBar:SetHeight(height);
	end
end

function StatusTrackingBarRetail_OnLoad(self)
	-- the stock bars: into a hidden frame (the stock code shows them again; a hidden parent keeps them hidden)
	local hidden = CreateFrame("Frame");
	hidden:Hide();
	for _, name in ipairs({ "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "ExhaustionTick" }) do
		if _G[name] then
			_G[name]:SetParent(hidden);
		end
	end

	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
		"UPDATE_FACTION", "PLAYER_REGEN_ENABLED", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN" }) do
		self:RegisterEvent(event);
	end
	StatusTrackingBarRetail_Update(self);
end

function StatusTrackingBarRetail_OnEnter(self)
	self.OverlayFrame.Text:Show();
	if self == StatusTrackingBarRetailRep then
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		GameTooltip:SetText(REPUTATION);
		GameTooltip:AddLine(CLICK_FOR_DETAILS or "", 1, 1, 1);
		GameTooltip:Show();
	end
end

function StatusTrackingBarRetail_OnLeave(self)
	self.OverlayFrame.Text:Hide();
	GameTooltip:Hide();
end

function StatusTrackingBarRetail_ExhaustionTick_OnEnter(self)
	local _, stateName, multiplier = GetRestState();
	GameTooltip:SetOwner(self, "ANCHOR_TOP");
	GameTooltip:SetText(stateName or "");
	local rested = GetXPExhaustion();
	if rested then
		GameTooltip:AddLine(XP .. ": +" .. rested .. " (" .. (multiplier or 1) * 100 .. "%)", 1, 1, 1);
	end
	GameTooltip:Show();
end
