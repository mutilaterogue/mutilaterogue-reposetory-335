-- Mythic+ rating of other players (tooltip, inspect), rating colors, season leaderboard.
-- Server: server/mythic_plus.cpp ("MPLUS_SCORE_GET" / "MPLUS_SCORE", "MPLUS_LEADERS").

-- global string or its key, so a missing string never breaks a tooltip
local function S(key)
	return _G[key] or key;
end

---------------------------------------------------------------------------
-- rating colors (retail C_ChallengeMode.GetDungeonScoreRarityColor, raider.io like steps)
---------------------------------------------------------------------------
local SCORE_COLORS = {
	{ score = 2000, r = 1.00, g = 0.50, b = 0.00 },
	{ score = 1400, r = 0.64, g = 0.21, b = 0.93 },
	{ score = 900,  r = 0.00, g = 0.44, b = 0.87 },
	{ score = 500,  r = 0.12, g = 1.00, b = 0.00 },
	{ score = 200,  r = 1.00, g = 1.00, b = 1.00 },
	{ score = 0,    r = 0.62, g = 0.62, b = 0.62 },
};

function MythicPlus_GetScoreColor(score)
	score = score or 0;
	for _, color in ipairs(SCORE_COLORS) do
		if score >= color.score then
			return color.r, color.g, color.b;
		end
	end
	return 0.62, 0.62, 0.62;
end

function MythicPlus_ColorScore(score)
	local r, g, b = MythicPlus_GetScoreColor(score);
	return string.format("|cff%02x%02x%02x%d|r", r * 255, g * 255, b * 255, score or 0);
end

---------------------------------------------------------------------------
-- scores of other players: cached by name, asked once in 60 s
---------------------------------------------------------------------------
local scores = {};		-- [name] = { rating, best, time }
local asked = {};		-- [name] = GetTime()

function MythicPlus_GetPlayerScore(name)
	if not name then
		return nil;
	end
	local entry = scores[name];
	if (not entry or GetTime() - entry.time > 60) and (not asked[name] or GetTime() - asked[name] > 60) then
		asked[name] = GetTime();
		MythicPlus_Send("MPLUS_SCORE_GET", name);
	end
	return entry;
end

local function AddScoreLine(tooltip, entry)
	if not entry or entry.rating <= 0 then
		return;
	end
	local text = S("DUNGEON_SCORE_LEADER"):find("%%s") and S("DUNGEON_SCORE_LEADER"):format(MythicPlus_ColorScore(entry.rating))
		or (S("DUNGEON_SCORE") .. ": " .. MythicPlus_ColorScore(entry.rating));
	if entry.best > 0 then
		text = text .. " |cffffffff(+" .. entry.best .. ")|r";
	end
	tooltip:AddLine(text);
	tooltip:Show();
end

GameTooltip:HookScript("OnTooltipSetUnit", function(self)
	local _, unit = self:GetUnit();
	if not unit or not UnitIsPlayer(unit) then
		return;
	end
	local name = UnitName(unit);
	self.mythicPlusName = name;
	AddScoreLine(self, MythicPlus_GetPlayerScore(name));
end);

---------------------------------------------------------------------------
-- inspect: the rating under the model (Blizzard_InspectUI loads on demand)
---------------------------------------------------------------------------
local inspectText;

local function UpdateInspect()
	if not InspectFrame or not InspectFrame:IsShown() or not inspectText then
		return;
	end
	local name = InspectFrame.unit and UnitName(InspectFrame.unit);
	local entry = MythicPlus_GetPlayerScore(name);
	if entry and entry.rating > 0 then
		inspectText:SetText(S("DUNGEON_SCORE") .. ": " .. MythicPlus_ColorScore(entry.rating));
		inspectText:Show();
	else
		inspectText:Hide();
	end
end

local function SetUpInspect()
	if inspectText or not InspectPaperDollFrame then
		return;
	end
	inspectText = InspectPaperDollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	inspectText:SetPoint("TOP", InspectPaperDollFrame, "TOP", 0, -58);
	InspectFrame:HookScript("OnShow", UpdateInspect);
end

local loader = CreateFrame("Frame");
loader:RegisterEvent("ADDON_LOADED");
loader:RegisterEvent("INSPECT_TALENT_READY");
loader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == "Blizzard_InspectUI" then
		SetUpInspect();
	elseif event == "INSPECT_TALENT_READY" then
		SetUpInspect();
		UpdateInspect();
	end
end);

if Comm_Register then
	Comm_Register("MPLUS_SCORE", function(name, rating, best)
		if not name then
			return;
		end
		scores[name] = { rating = tonumber(rating) or 0, best = tonumber(best) or 0, time = GetTime() };
		-- the tooltip of this player is open: show it again with the line
		if GameTooltip:IsShown() and GameTooltip.mythicPlusName == name then
			local _, unit = GameTooltip:GetUnit();
			if unit then
				GameTooltip:SetUnit(unit);
			end
		end
		UpdateInspect();
	end);
end

---------------------------------------------------------------------------
-- season leaderboard (click on a dungeon icon of ChallengesFrame)
---------------------------------------------------------------------------
local NUM_ROWS = 10;
local leaders = {};		-- [mapID] = { entries }

function ChallengesLeaderboard_Open(mapID)
	local frame = ChallengesLeaderboardFrame;
	frame.mapID = mapID;
	if frame.TitleContainer and frame.TitleContainer.TitleText then
		local title = C_ChallengeMode.GetMapUIInfo(mapID) or "";
		local season = MythicPlus.season;
		if season and season.name ~= "" then
			title = title .. " - " .. season.name;
		end
		frame.TitleContainer.TitleText:SetText(title);
	end
	ChallengesLeaderboard_Update(frame);
	ShowUIPanel(frame);
	MythicPlus_Send("MPLUS_LEADERS", mapID);
end

function ChallengesLeaderboard_OnLoad(self)
	UIPanelWindows[self:GetName()] = { area = "left", pushable = 2, whileDead = 1 };
	self:RegisterForDrag("LeftButton");
	if self.PortraitContainer and self.PortraitContainer.portrait then
		SetPortraitToTexture(self.PortraitContainer.portrait, "Interface\\Icons\\Achievement_ChallengeMode_Gold");
	end
	self.rows = {};
	for i = 1, NUM_ROWS do
		local row = CreateFrame("Frame", self:GetName() .. "Row" .. i, self, "ChallengesLeaderboardRowTemplate");
		row:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -64 - (i - 1) * 24);
		row:SetPoint("RIGHT", self, "RIGHT", -12, 0);
		row.Rank:SetText(i);
		row.Background:SetShown(i % 2 == 1);
		self.rows[i] = row;
	end
end

function ChallengesLeaderboard_Update(self)
	local entries = self.mapID and leaders[self.mapID] or {};
	for i, row in ipairs(self.rows) do
		local entry = entries[i];
		if entry then
			local color = RAID_CLASS_COLORS[entry.class] or NORMAL_FONT_COLOR;
			row.Name:SetText(entry.name);
			row.Name:SetTextColor(color.r, color.g, color.b);
			row.Level:SetText("+" .. entry.level);
			if entry.timed then
				row.Level:SetTextColor(1, 1, 1);
			else
				row.Level:SetTextColor(0.5, 0.5, 0.5);
			end
			row.Time:SetText(MythicPlus_FormatTime(entry.timeMs / 1000));
			row.Score:SetText(MythicPlus_ColorScore(entry.score));
			row:Show();
		else
			row:Hide();
		end
	end
	self.Empty:SetShown(#entries == 0);
end

-- class ids of the characters table -> RAID_CLASS_COLORS keys
local CLASS_FILES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", nil, "DRUID" };

if Comm_Register then
	Comm_Register("MPLUS_LEADERS", function(mapID, list)
		mapID = tonumber(mapID);
		if not mapID then
			return;
		end
		local entries = {};
		for entry in string.gmatch(list or "", "[^,]+") do
			local name, level, timeMs, timed, score, class = strsplit(";", entry);
			table.insert(entries, {
				name = name or "", level = tonumber(level) or 0, timeMs = tonumber(timeMs) or 0, timed = timed == "1",
				score = tonumber(score) or 0, class = CLASS_FILES[tonumber(class) or 0],
			});
		end
		leaders[mapID] = entries;
		if ChallengesLeaderboardFrame and ChallengesLeaderboardFrame:IsShown() and ChallengesLeaderboardFrame.mapID == mapID then
			ChallengesLeaderboard_Update(ChallengesLeaderboardFrame);
		end
	end);
end
