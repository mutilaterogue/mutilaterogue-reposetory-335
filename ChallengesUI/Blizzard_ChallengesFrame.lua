-- retail ChallengesFrameMixin / ChallengesDungeonIconMixin / ChallengeModeWeeklyChestMixin for 3.3.5.
-- Data: Blizzard_ChallengeModeCompat.lua (maps, best runs, rating, weekly affixes, Great Vault).

UIPanelWindows["ChallengesFrame"] = { area = "left", pushable = 1, whileDead = 1, xOffset = "15", yOffset = "-10" };

local CHEST_STATE_WALL_OF_TEXT = 1;
local CHEST_STATE_INCOMPLETE = 2;
local CHEST_STATE_COMPLETE = 3;
local CHEST_STATE_COLLECT = 4;
local DEFAULT_ICON = "Interface\\Icons\\achievement_bg_wineos_underxminutes";

-- the encounter journal instance of a map (icon and background)
local function JournalInstance(mapID)
	if not EJ_DATA then
		return nil;
	end
	for _, inst in pairs(EJ_DATA.instances) do
		if inst.mapID == mapID then
			return inst;
		end
	end
	return nil;
end

function ChallengesFrame_OnLoad(self)
	self:RegisterForDrag("LeftButton");
	self.DungeonIcons = {};
	self.AffixFrames = {};
	if self.TitleContainer and self.TitleContainer.TitleText then
		self.TitleContainer.TitleText:SetText(CHALLENGES);
	end
	if self.PortraitContainer and self.PortraitContainer.portrait then
		SetPortraitToTexture(self.PortraitContainer.portrait, DEFAULT_ICON);
	end

	MythicPlus_RegisterCallback(function(event)
		if self:IsShown() and (event == "MAPS" or event == "RATING" or event == "AFFIXES" or event == "KEY" or event == "VAULT") then
			ChallengesFrame_Update(self);
		end
	end);
end

function ChallengesFrame_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	MythicPlus_Send("MPLUS_GET");
	MythicPlus_Send("MPLUS_VAULT_GET");
	ChallengesFrame_Update(self);
end

function ChallengesFrame_OnHide(self)
	PlaySound("igCharacterInfoClose");
end

-- retail LineUpFrames: the dungeon icons fill the bottom of the frame
local function LineUpFrames(frames, anchor, width)
	local num = #frames;
	if num == 0 then
		return;
	end
	local distanceBetween = 2;
	local size = (width - distanceBetween * num) / num;
	size = math.min(size, 70);
	local fullWidth = size * num + distanceBetween * (num - 1);
	for i, frame in ipairs(frames) do
		frame:SetWidth(size);
		frame:SetHeight(size);
		frame.Icon:SetWidth(size);
		frame.Icon:SetHeight(size);
		frame:ClearAllPoints();
		if i == 1 then
			frame:SetPoint("BOTTOMLEFT", anchor, "BOTTOM", -fullWidth / 2, 5);
		else
			frame:SetPoint("LEFT", frames[i - 1], "RIGHT", distanceBetween, 0);
		end
	end
end

local function WeeklyChestState()
	local vault = MythicPlus.vault;
	if vault then
		for _, option in pairs(vault.options) do
			if not vault.claimed then
				return CHEST_STATE_COLLECT;
			end
		end
		if vault.runs > 0 then
			return CHEST_STATE_COMPLETE;
		end
	end
	if C_MythicPlus.GetOwnedKeystoneLevel() or (MythicPlus.rating or 0) > 0 then
		return CHEST_STATE_INCOMPLETE;
	end
	return CHEST_STATE_WALL_OF_TEXT;
end

function ChallengesFrame_Update(self)
	local weekly = self.WeeklyInfo;

	-- this week's affixes (retail WeeklyInfo:SetUp, AffixesContainer: 10 apart, centered)
	local affixes = C_MythicPlus.GetCurrentAffixes();
	local count = #affixes;
	for i, affix in ipairs(affixes) do
		local frame = self.AffixFrames[i];
		if not frame then
			frame = CreateFrame("Frame", self:GetName() .. "Affix" .. i, weekly, "ChallengesKeystoneFrameAffixTemplate");
			self.AffixFrames[i] = frame;
		end
		frame:ClearAllPoints();
		frame:SetPoint("TOP", weekly.ThisWeekLabel, "BOTTOM", (i - (count + 1) / 2) * 62, -10);
		ChallengesKeystoneFrameAffix_SetUp(frame, affix.id);
	end
	for i = count + 1, #self.AffixFrames do
		self.AffixFrames[i]:Hide();
	end

	-- dungeons sorted by the best score, then by name (retail Update)
	local sorted = {};
	for _, mapID in ipairs(C_ChallengeMode.GetMapTable()) do
		local best = MythicPlus.best[mapID];
		table.insert(sorted, {
			id = mapID, level = best and best.level or 0, dungeonScore = best and best.score or 0,
			name = C_ChallengeMode.GetMapUIInfo(mapID) or "",
		});
	end
	table.sort(sorted, function(a, b)
		if a.dungeonScore ~= b.dungeonScore then
			return a.dungeonScore > b.dungeonScore;
		end
		return a.name < b.name;
	end);

	for i, mapInfo in ipairs(sorted) do
		local frame = self.DungeonIcons[i];
		if not frame then
			frame = CreateFrame("Frame", self:GetName() .. "DungeonIcon" .. i, weekly, "ChallengesDungeonIconFrameTemplate");
			self.DungeonIcons[i] = frame;
		end
		ChallengesDungeonIcon_SetUp(frame, mapInfo);
		frame:Show();
	end
	for i = #sorted + 1, #self.DungeonIcons do
		self.DungeonIcons[i]:Hide();
	end
	local shown = {};
	for i = 1, #sorted do
		shown[i] = self.DungeonIcons[i];
	end
	LineUpFrames(shown, weekly, weekly:GetWidth() - 20);
	if shown[1] then
		weekly.SeasonBest:ClearAllPoints();
		weekly.SeasonBest:SetPoint("TOPLEFT", shown[1], "TOPLEFT", 5, 15);
	end

	-- background of the best dungeon
	local inst = sorted[1] and JournalInstance(sorted[1].id);
	if inst and inst.bg then
		self.Inset.Background:SetTexture(inst.bg);
		self.Inset.Background:Show();
	else
		self.Inset.Background:Hide();
	end

	-- weekly chest (retail ChallengeModeWeeklyChestMixin:Update)
	local chest = weekly.WeeklyChest;
	local state = WeeklyChestState();
	local iconState = state == CHEST_STATE_COLLECT and "collect" or state == CHEST_STATE_COMPLETE and "complete" or "incomplete";
	chest.Icon:SetAtlas("gficon-chest-evergreen-greatvault-" .. iconState, false);
	chest.Highlight:SetAtlas("gficon-chest-evergreen-greatvault-" .. iconState, false);
	chest.RunStatus:SetText(state == CHEST_STATE_COLLECT and MYTHIC_PLUS_COLLECT_GREAT_VAULT or MYTHIC_PLUS_COMPLETE_MYTHIC_DUNGEONS);
	chest.state = state;
	chest:SetShown(state ~= CHEST_STATE_WALL_OF_TEXT);

	local score = MythicPlus.rating or 0;
	weekly.DungeonScoreInfo.Score:SetText(score);
	weekly.DungeonScoreInfo:SetShown(chest:IsShown());

	weekly.ThisWeekLabel:SetShown(state ~= CHEST_STATE_WALL_OF_TEXT);
	weekly.Description:SetShown(state == CHEST_STATE_WALL_OF_TEXT);
end

---------------------------------------------------------------------------
-- dungeon icons (retail ChallengesDungeonIconMixin)
---------------------------------------------------------------------------
function ChallengesDungeonIcon_SetUp(self, mapInfo)
	self.mapID = mapInfo.id;
	local inst = JournalInstance(mapInfo.id);
	self.Icon:SetTexture(inst and inst.button or DEFAULT_ICON);
	if inst and inst.button then
		self.Icon:SetTexCoord(0, 0.68359375, 0, 0.7421875);	-- the dungeon button art, a square of it
	else
		self.Icon:SetTexCoord(0, 1, 0, 1);
	end
	self.Icon:SetDesaturated(mapInfo.level == 0);
	if mapInfo.level > 0 then
		self.HighestLevel:SetText(mapInfo.level);
		self.HighestLevel:Show();
	else
		self.HighestLevel:Hide();
	end
end

function ChallengesDungeonIcon_OnEnter(self)
	local name = C_ChallengeMode.GetMapUIInfo(self.mapID);
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(name or "", 1, 1, 1);
	local best = MythicPlus.best[self.mapID];
	if best then
		GameTooltip:AddLine(DUNGEON_SCORE_TOTAL_SCORE:format(best.score), 0.1, 1, 0.1);
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine(LFG_LIST_BEST_RUN);
		GameTooltip:AddLine(MYTHIC_PLUS_POWER_LEVEL:format(best.level), 1, 1, 1);
		local seconds = math.floor(best.timeMs / 1000);
		local durationText = SecondsToClock(seconds, seconds >= 3600);
		if best.timed then
			GameTooltip:AddLine(durationText, 1, 1, 1);
		else
			GameTooltip:AddLine(DUNGEON_SCORE_OVERTIME_TIME:format(durationText), 0.6, 0.6, 0.6);
		end
	end
	GameTooltip:Show();
end

function ChallengesDungeonScore_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(DUNGEON_SCORE, 1, 1, 1);
	GameTooltip:AddLine(DUNGEON_SCORE_DESC, nil, nil, nil, true);
	GameTooltip:Show();
end

---------------------------------------------------------------------------
-- weekly chest (retail ChallengeModeWeeklyChestMixin:OnEnter)
---------------------------------------------------------------------------
function ChallengesWeeklyChest_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(GREAT_VAULT_REWARDS, 1, 1, 1);
	if self.state == CHEST_STATE_COLLECT then
		GameTooltip:AddLine(GREAT_VAULT_REWARDS_WAITING, 0.1, 1, 0.1, true);
		GameTooltip:AddLine(" ");
	end
	local runs = MythicPlus.vault and MythicPlus.vault.runs or 0;
	if runs == 0 then
		GameTooltip:AddLine(GREAT_VAULT_REWARDS_MYTHIC_INCOMPLETE, nil, nil, nil, true);
	elseif runs < 4 then
		GameTooltip:AddLine(GREAT_VAULT_REWARDS_MYTHIC_COMPLETED_FIRST:format(4 - runs), nil, nil, nil, true);
	elseif runs < 8 then
		GameTooltip:AddLine(GREAT_VAULT_REWARDS_MYTHIC_COMPLETED_SECOND:format(8 - runs), nil, nil, nil, true);
	else
		GameTooltip:AddLine(GREAT_VAULT_REWARDS_MYTHIC_COMPLETED_THIRD, nil, nil, nil, true);
	end
	GameTooltip:AddLine(WEEKLY_REWARDS_CLICK_TO_PREVIEW_INSTRUCTIONS, 0.1, 1, 0.1, true);
	GameTooltip:Show();
end

function ChallengesWeeklyChest_OnClick(self)
	WeeklyRewardsFrame_Toggle();
end

---------------------------------------------------------------------------
-- slash
---------------------------------------------------------------------------
SLASH_MYTHICPLUS1 = "/mplus";
SLASH_MYTHICPLUS2 = "/keystone";
SlashCmdList["MYTHICPLUS"] = function()
	if ChallengesFrame:IsShown() then
		HideUIPanel(ChallengesFrame);
	else
		ShowUIPanel(ChallengesFrame);
	end
end
