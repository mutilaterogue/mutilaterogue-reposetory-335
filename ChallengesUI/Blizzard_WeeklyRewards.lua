-- Great Vault: port of retail Blizzard_WeeklyRewards.lua / WeeklyRewardsUtil.lua for 3.3.5.
-- Rows: raids, dungeons (Mythic+), world (delves, no progress source yet). Data: MythicPlus.vault (Blizzard_ChallengeModeCompat.lua):
--   runs     - number of keystone runs this week
--   levels   - their levels, best first
--   options  - [slot] = { itemID, level, claimed } rolled from last week's runs
--   claimed  - an option was already taken

local NUM_COLUMNS = 3;
-- retail Enum.WeeklyRewardChestThresholdType
local TYPE_ACTIVITIES, TYPE_RAID, TYPE_WORLD = 1, 3, 6;
-- per row: thresholds and the first option slot on the server
local ROWS = {
	[TYPE_RAID] = { thresholds = { 2, 4, 6 }, slot = 4, key = "raid" },
	[TYPE_ACTIVITIES] = { thresholds = { 1, 4, 8 }, slot = 1, key = "levels" },
	[TYPE_WORLD] = { thresholds = { 1, 4, 8 }, slot = 7, key = "world" },
};
local SELECTION_STATE_HIDDEN = 1;
local SELECTION_STATE_UNSELECTED = 2;
local SELECTION_STATE_SELECTED = 3;

-- global string or its key, so a missing string never breaks a tooltip
local function S(key)
	return _G[key] or key;
end

local function SetTextColor(fontString, color)
	fontString:SetTextColor(color.r, color.g, color.b);
end

UIPanelWindows["WeeklyRewardsFrame"] = { area = "center", pushable = 0, whileDead = 1 };

StaticPopupDialogs["CONFIRM_SELECT_WEEKLY_REWARD"] = {
	text = S("WEEKLY_REWARDS_CONFIRM_SELECT"),
	button1 = YES,
	button2 = CANCEL,
	OnAccept = function(self, data)
		MythicPlus_Send("MPLUS_VAULT_CHOOSE", data);
		PlaySound("igMainMenuOptionCheckBoxOn");
		HideUIPanel(WeeklyRewardsFrame);
	end,
	timeout = 0,
	hideOnEscape = 1,
	showAlert = 1,
	whileDead = 1,
};

---------------------------------------------------------------------------
-- C_WeeklyRewards over MythicPlus.vault
---------------------------------------------------------------------------
local function Vault()
	return MythicPlus.vault or { runs = 0, levels = {}, raid = {}, world = {}, options = {}, claimed = false };
end

C_WeeklyRewards = C_WeeklyRewards or {};

function C_WeeklyRewards.HasAvailableRewards()
	local vault = Vault();
	return next(vault.options) ~= nil and not vault.claimed;
end

function C_WeeklyRewards.CanClaimRewards()
	return C_WeeklyRewards.HasAvailableRewards();
end

function C_WeeklyRewards.GetActivities()
	local vault = Vault();
	local claiming = C_WeeklyRewards.CanClaimRewards();
	local activities = {};
	for activityType, row in pairs(ROWS) do
		local levels = vault[row.key] or {};
		for index, threshold in ipairs(row.thresholds) do
			local info = { type = activityType, index = index, threshold = threshold, progress = math.min(#levels, threshold),
				level = levels[threshold] or 0, rewards = {}, slot = row.slot + index - 1 };
			local option = vault.options[info.slot];
			if claiming and option and option.itemID > 0 then
				-- raid option level is the difficulty (0..3), shown as 1..4 like the progress
				local level = activityType == TYPE_RAID and option.level + 1 or option.level;
				info.rewards[1] = { id = option.itemID, level = level };
				info.progress = threshold;
				info.level = level;
			end
			table.insert(activities, info);
		end
	end
	return activities;
end

function C_WeeklyRewards.GetNumCompletedDungeonRuns()
	return 0, 0, #Vault().levels;
end

WeeklyRewardsUtil = { HeroicLevel = -1, MythicLevel = 0 };

function WeeklyRewardsUtil.GetNextMythicLevel(level)
	return level + 1;
end

-- returns level, count of that level among the top numRuns
function WeeklyRewardsUtil.GetLowestLevelInTopDungeonRuns(numRuns)
	local levels = Vault().levels;
	local lowestLevel, lowestCount = nil, 0;
	for i = math.min(numRuns, #levels), 1, -1 do
		lowestLevel = lowestLevel or levels[i];
		if levels[i] == lowestLevel then
			lowestCount = lowestCount + 1;
		else
			break;
		end
	end
	return lowestLevel or 0, lowestCount;
end

function WeeklyRewardsUtil.HasUnlockedRewards()
	for _, info in ipairs(C_WeeklyRewards.GetActivities()) do
		if info.progress >= info.threshold then
			return true;
		end
	end
	return false;
end

function WeeklyRewards_ShowUI()
	ShowUIPanel(WeeklyRewardsFrame);
end

function WeeklyRewardsFrame_Toggle()
	if WeeklyRewardsFrame:IsShown() then
		HideUIPanel(WeeklyRewardsFrame);
	else
		ShowUIPanel(WeeklyRewardsFrame);
	end
end

---------------------------------------------------------------------------
-- WeeklyRewardsMixin
---------------------------------------------------------------------------
WeeklyRewardsMixin = {};

function WeeklyRewardsFrame_OnLoad(self)
	Mixin(self, WeeklyRewardsMixin);
	self:OnLoad();
end

function WeeklyRewardsMixin:OnLoad()
	self.Activities = {};
	self:RegisterForDrag("LeftButton");
	self:SetUpActivity(self.RaidFrame, RAIDS, "evergreen-weeklyrewards-category-raids", TYPE_RAID);
	self:SetUpActivity(self.MythicFrame, DUNGEONS, "evergreen-weeklyrewards-category-dungeons", TYPE_ACTIVITIES);
	self:SetUpActivity(self.WorldFrame, S("DELVES_LABEL"), "evergreen-weeklyrewards-category-world", TYPE_WORLD);
	self.SelectRewardButton:SetText(S("WEEKLY_REWARDS_SELECT_REWARD"));
	self.PreviousRewardNotification:SetText(S("WEEKLY_REWARDS_UNCLAIMED_REWARDS_FROM_PREVIOUS_TIME"));

	MythicPlus_RegisterCallback(function(event)
		if event == "VAULT_OPEN" then
			self.hasInteraction = true;
			if self:IsShown() then
				self:FullRefresh();
			else
				ShowUIPanel(self);
			end
		elseif event == "VAULT" and self:IsShown() then
			local playSheenAnims = self.couldClaimRewardsInOnShow == false and C_WeeklyRewards.CanClaimRewards();
			if playSheenAnims then
				self.couldClaimRewardsInOnShow = nil;
			end
			self.hasAvailableRewards = C_WeeklyRewards.HasAvailableRewards();
			self:Refresh(playSheenAnims);
		end
	end);
end

function WeeklyRewardsMixin:OnShow()
	PlaySound("igCharacterInfoOpen");
	MythicPlus_Send("MPLUS_VAULT_GET");
	self:FullRefresh();
end

function WeeklyRewardsMixin:OnHide()
	PlaySound("igCharacterInfoClose");
	self.selectedActivity = nil;
	self.hasInteraction = nil;
	StaticPopup_Hide("CONFIRM_SELECT_WEEKLY_REWARD");
end

function WeeklyRewardsMixin:SetUpActivity(activityTypeFrame, name, atlas, activityType)
	activityTypeFrame.Name:SetText(name);
	activityTypeFrame.Background:SetAtlas(atlas, true);

	local prevFrame;
	for i = 1, NUM_COLUMNS do
		local frame = CreateFrame("Frame", nil, self, "WeeklyRewardActivityTemplate");
		Mixin(frame, WeeklyRewardsActivityMixin);
		Mixin(frame.ItemFrame, WeeklyRewardActivityItemMixin);
		table.insert(self.Activities, frame);
		if prevFrame then
			frame:SetPoint("LEFT", prevFrame, "RIGHT", 9, 0);
		else
			frame:SetPoint("LEFT", activityTypeFrame, "RIGHT", 44, 3);
		end
		frame.type = activityType;
		frame.index = i;
		prevFrame = frame;
	end
end

function WeeklyRewardsMixin:GetActivityFrame(activityType, index)
	for _, frame in ipairs(self.Activities) do
		if frame.type == activityType and frame.index == index then
			return frame;
		end
	end
end

function WeeklyRewardsMixin:IsReadOnly()
	return not self.hasInteraction;
end

function WeeklyRewardsMixin:FullRefresh()
	self.hasAvailableRewards = C_WeeklyRewards.HasAvailableRewards();
	self.couldClaimRewardsInOnShow = C_WeeklyRewards.CanClaimRewards();
	self:Refresh(self.couldClaimRewardsInOnShow);
end

function WeeklyRewardsMixin:Refresh(playSheenAnims)
	self:UpdateTitle();
	self.PreviousRewardNotification:SetShown(self:IsReadOnly() and C_WeeklyRewards.HasAvailableRewards());

	local canClaimRewards = C_WeeklyRewards.CanClaimRewards() and not self:IsReadOnly();
	self.SelectRewardButton:SetShown(canClaimRewards);

	for _, activityInfo in ipairs(C_WeeklyRewards.GetActivities()) do
		local frame = self:GetActivityFrame(activityInfo.type, activityInfo.index);
		if frame then
			if playSheenAnims then
				frame:MarkForPendingSheenAnim();
			end
			frame:Refresh(activityInfo);
		end
	end

	self:UpdateSelection();
end

function WeeklyRewardsMixin:UpdateTitle()
	if C_WeeklyRewards.CanClaimRewards() then
		if self:IsReadOnly() then
			self.HeaderFrame.Text:SetText(S("WEEKLY_REWARDS_RETURN_TO_CLAIM"));
		else
			self.HeaderFrame.Text:SetText(S("WEEKLY_REWARDS_CHOOSE_REWARD"));
		end
	else
		self.HeaderFrame.Text:SetText(S("WEEKLY_REWARDS_ADD_ITEMS"));
	end
end

function WeeklyRewardsMixin:SelectActivity(activityFrame)
	if self:IsReadOnly() or not self.hasAvailableRewards then
		return;
	end
	if activityFrame.hasRewards then
		PlaySound("igMainMenuOptionCheckBoxOn");
		if self.selectedActivity == activityFrame then
			self.selectedActivity = nil;
		else
			self.selectedActivity = activityFrame;
		end
		self:UpdateSelection();
		StaticPopup_Hide("CONFIRM_SELECT_WEEKLY_REWARD");
	end
end

function WeeklyRewardsMixin:UpdateSelection()
	local selectedActivity = self.selectedActivity;
	if selectedActivity then
		self.SelectRewardButton:Enable();
	else
		self.SelectRewardButton:Disable();
	end
	for _, frame in ipairs(self.Activities) do
		local selectionState = SELECTION_STATE_HIDDEN;
		if selectedActivity and frame.hasRewards then
			selectionState = frame == selectedActivity and SELECTION_STATE_SELECTED or SELECTION_STATE_UNSELECTED;
		end
		frame:SetSelectionState(selectionState);
	end
end

function WeeklyRewardsMixin:SelectReward()
	local activity = self.selectedActivity;
	if activity then
		PlaySound("igMainMenuOptionCheckBoxOn");
		StaticPopup_Show("CONFIRM_SELECT_WEEKLY_REWARD", nil, nil, activity.info.slot);
	end
end

-- Lua replacement for the retail looping/one-shot animation groups
function WeeklyRewardsMixin:OnUpdate(elapsed)
	self.animTime = (self.animTime or 0) + elapsed;
	local t = self.animTime;
	for _, frame in ipairs(self.Activities) do
		frame:UpdateAnims(t, elapsed);
	end
end

---------------------------------------------------------------------------
-- WeeklyRewardsActivityMixin
---------------------------------------------------------------------------
WeeklyRewardsActivityMixin = {};

function WeeklyRewardsActivityMixin:SetSelectionState(state)
	self.SelectedTexture:SetShown(state == SELECTION_STATE_SELECTED);
	self.SelectionGlow:SetShown(state == SELECTION_STATE_SELECTED);
	self.UnselectedFrame:SetShown(state == SELECTION_STATE_UNSELECTED);
end

function WeeklyRewardsActivityMixin:MarkForPendingSheenAnim()
	self.hasPendingSheenAnim = true;
end

function WeeklyRewardsActivityMixin:Refresh(activityInfo)
	local thresholdString = "WEEKLY_REWARDS_THRESHOLD_DUNGEONS";
	if activityInfo.type == TYPE_RAID then
		thresholdString = "WEEKLY_REWARDS_THRESHOLD_RAID";
	elseif activityInfo.type == TYPE_WORLD then
		thresholdString = "WEEKLY_REWARDS_THRESHOLD_WORLD";
	end
	self.Threshold:SetText(S(thresholdString):format(activityInfo.threshold));

	self.unlocked = activityInfo.progress >= activityInfo.threshold;
	self.hasRewards = #activityInfo.rewards > 0;
	self.info = activityInfo;

	self:SetProgressText();

	if self.unlocked or self.hasRewards then
		self.Background:SetAtlas("evergreen-weeklyrewards-reward-unlocked", true);
		SetTextColor(self.Threshold, NORMAL_FONT_COLOR);
		SetTextColor(self.Progress, GREEN_FONT_COLOR);
		self.CompletedIcon:Show();
		self.ItemFrame:Hide();
		if self.hasRewards then
			self.ItemFrame:SetRewards(activityInfo.rewards);
			self.ItemGlow:Show();
			self.UncollectedGlow:Hide();
		else
			if not self.UncollectedGlow:IsShown() then
				self.UncollectedGlow:SetAlpha(0);
				self.UncollectedGlow:Show();
				self.uncollectedFade = 0;
			end
			self.ItemGlow:Hide();
		end
		if self.hasPendingSheenAnim then
			self.hasPendingSheenAnim = nil;
			self.sheenTime = 0;
			self.RewardGenerated:Show();
		end
	else
		self.Background:SetAtlas("evergreen-weeklyrewards-reward-locked", true);
		SetTextColor(self.Threshold, GRAY_FONT_COLOR);
		SetTextColor(self.Progress, GRAY_FONT_COLOR);
		self.CompletedIcon:Hide();
		self.ItemFrame:Hide();
		self.ItemGlow:Hide();
		self.RewardGenerated:Hide();
		self.UncollectedGlow:Hide();
	end
end

function WeeklyRewardsActivityMixin:UpdateAnims(t, elapsed)
	-- UncollectedGlow.FadeAnim: 0 -> 1 in 0.5s
	if self.uncollectedFade then
		self.uncollectedFade = self.uncollectedFade + elapsed;
		local p = math.min(self.uncollectedFade / 0.5, 1);
		self.UncollectedGlow:SetAlpha(1 - (1 - p) * (1 - p));
		if p >= 1 then
			self.uncollectedFade = nil;
		end
	end
	-- SelectionGlow.SideGlows: 1 -> 0.75 -> 1 every 2s
	if self.SelectionGlow:IsShown() then
		local phase = t % 2;
		self.SelectionGlow.SideGlows:SetAlpha(phase < 1 and 1 - 0.25 * phase or 0.75 + 0.25 * (phase - 1));
	end
	-- RewardGenerated: swirl + sparkles, 1s
	if self.sheenTime then
		self.sheenTime = self.sheenTime + elapsed;
		local s = self.sheenTime;
		local fx = self.RewardGenerated;
		fx.Swirl:SetAlpha(s < 0.6 and 0.15 * s / 0.6 or math.max(0, 0.15 * (1 - (s - 0.6) / 0.4)));
		fx.Sparkle1:SetAlpha((s >= 0.5 and s < 1) and (s < 0.75 and (s - 0.5) / 0.25 or 1 - (s - 0.75) / 0.25) or 0);
		fx.Sparkle2:SetAlpha((s >= 0.7 and s < 1) and (s < 0.85 and (s - 0.7) / 0.15 or 1 - (s - 0.85) / 0.15) or 0);
		if s >= 1 then
			self.sheenTime = nil;
			self:OnSheenAnimFinished();
		end
	end
end

function WeeklyRewardsActivityMixin:OnSheenAnimFinished()
	self.RewardGenerated:Hide();
end

function WeeklyRewardsActivityMixin:SetProgressText(text)
	local activityInfo = self.info;
	if text then
		self.Progress:SetText(text);
	elseif self.hasRewards then
		self.Progress:SetText("");
	elseif self.unlocked then
		self.Progress:SetText(self:GetLevelText(activityInfo.level));
	elseif C_WeeklyRewards.CanClaimRewards() then
		self.Progress:SetText("");
	else
		self.Progress:SetText(S("GENERIC_FRACTION_STRING"):format(activityInfo.progress, activityInfo.threshold));
	end
end

-- raid: difficulty 1..4 (10N, 25N, 10H, 25H); dungeons: keystone level; world: tier
function WeeklyRewardsActivityMixin:GetLevelText(level)
	if self.info.type == TYPE_RAID then
		return S("RAID_DIFFICULTY" .. level);
	elseif self.info.type == TYPE_WORLD then
		return S("GREAT_VAULT_WORLD_TIER"):format(level);
	end
	return S("WEEKLY_REWARDS_MYTHIC"):format(level);
end

function WeeklyRewardsActivityMixin:OnMouseUp(button)
	if button == "LeftButton" and self:IsMouseOver() then
		self:GetParent():SelectActivity(self);
	end
end

function WeeklyRewardsActivityMixin:CanShowPreviewItemTooltip()
	return self.unlocked and not C_WeeklyRewards.CanClaimRewards();
end

function WeeklyRewardsActivityMixin:OnEnter()
	if not self.info then
		return;
	end
	if self:CanShowPreviewItemTooltip() then
		self:ShowPreviewItemTooltip();
		return;
	end

	local description, formatRemainingProgress;
	if self.info.type == TYPE_RAID then
		description = S(self.info.progress == 0 and "GREAT_VAULT_REWARDS_RAID_INCOMPLETE" or "GREAT_VAULT_REWARDS_RAID_INPROGRESS");
		formatRemainingProgress = true;
	elseif self.info.type == TYPE_WORLD then
		description = S(self.info.index == 1 and "GREAT_VAULT_REWARDS_WORLD_INCOMPLETE"
			or self.info.index == 2 and "GREAT_VAULT_REWARDS_WORLD_COMPLETED_FIRST" or "GREAT_VAULT_REWARDS_WORLD_COMPLETED_SECOND");
		formatRemainingProgress = true;
	else
		description = S("GREAT_VAULT_REWARDS_MYTHIC_INCOMPLETE");
		formatRemainingProgress = false;
		if self.info.index == 2 then
			description = S("GREAT_VAULT_REWARDS_MYTHIC_COMPLETED_FIRST");
			formatRemainingProgress = true;
		elseif self.info.index == 3 then
			description = S("GREAT_VAULT_REWARDS_MYTHIC_COMPLETED_SECOND");
			formatRemainingProgress = true;
		end
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -7, -11);
	GameTooltip:SetText(S("WEEKLY_REWARDS_UNLOCK_REWARD"), 1, 1, 1);
	if formatRemainingProgress then
		description = description:format(self.info.threshold - self.info.progress);
	end
	GameTooltip:AddLine(description, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true);

	if self.info.progress > 0 and self.info.type == TYPE_ACTIVITIES then
		GameTooltip:AddLine(" ");
		local lowestLevel = WeeklyRewardsUtil.GetLowestLevelInTopDungeonRuns(self.info.threshold);
		GameTooltip:AddLine(S("GREAT_VAULT_REWARDS_CURRENT_LEVEL_MYTHIC"):format(self.info.threshold, lowestLevel),
			NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true);
		self:AddTopRunsToTooltip();
	end
	GameTooltip:Show();
end

function WeeklyRewardsActivityMixin:ShowPreviewItemTooltip()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -7, -11);
	GameTooltip:SetText(S("WEEKLY_REWARDS_CURRENT_REWARD"), 1, 1, 1);
	GameTooltip:AddLine(self:GetLevelText(self.info.level), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true);
	if self.info.type ~= TYPE_ACTIVITIES then
		GameTooltip:Show();
		return;
	end
	GameTooltip:AddLine(" ");
	local nextLevel = WeeklyRewardsUtil.GetNextMythicLevel(self.info.level);
	if self.info.threshold == 1 then
		GameTooltip:AddLine(S("WEEKLY_REWARDS_COMPLETE_MYTHIC_SHORT"):format(nextLevel), 1, 1, 1, true);
	else
		GameTooltip:AddLine(S("WEEKLY_REWARDS_COMPLETE_MYTHIC"):format(nextLevel, self.info.threshold), 1, 1, 1, true);
		self:AddTopRunsToTooltip();
	end
	GameTooltip:Show();
end

function WeeklyRewardsActivityMixin:AddTopRunsToTooltip()
	GameTooltip:AddLine(" ");
	GameTooltip:AddLine(S("WEEKLY_REWARDS_MYTHIC_TOP_RUNS"):format(self.info.threshold), 1, 1, 1);
	local levels = Vault().levels;
	for i = 1, math.min(self.info.threshold, #levels) do
		GameTooltip:AddLine(S("WEEKLY_REWARDS_MYTHIC"):format(levels[i]), 1, 1, 1);
	end
end

function WeeklyRewardsActivityMixin:OnLeave()
	GameTooltip:Hide();
end

function WeeklyRewardsActivityMixin:OnHide()
	self.hasPendingSheenAnim = nil;
	self.sheenTime = nil;
end

---------------------------------------------------------------------------
-- WeeklyRewardActivityItemMixin
---------------------------------------------------------------------------
WeeklyRewardActivityItemMixin = {};

function WeeklyRewardActivityItemMixin:OnEnter()
	if self.itemID then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -3, -6);
		GameTooltip:SetHyperlink("item:" .. self.itemID);
		GameTooltip:Show();
	end
end

function WeeklyRewardActivityItemMixin:OnLeave()
	GameTooltip:Hide();
end

function WeeklyRewardActivityItemMixin:OnClick()
	local activityFrame = self:GetParent();
	if IsModifiedClick() and self.itemID then
		local _, link = GetItemInfo(self.itemID);
		HandleModifiedItemClick(link);
	else
		activityFrame:GetParent():SelectActivity(activityFrame);
	end
end

function WeeklyRewardActivityItemMixin:SetRewards(rewards)
	local reward = rewards[1];
	self.itemID = reward and reward.id;
	if not self.itemID then
		self:Hide();
		return;
	end
	local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(self.itemID);
	self.Icon:SetTexture(icon or GetItemIcon(self.itemID));
	self.Name:SetText(name or "");
	if quality then
		local r, g, b = GetItemQualityColor(quality);
		self.Name:SetTextColor(r, g, b);
	end
	local activity = self:GetParent();
	if activity.info.type == TYPE_ACTIVITIES then
		activity:SetProgressText(ITEM_MYTHIC .. " +" .. reward.level);
	else
		activity:SetProgressText(activity:GetLevelText(reward.level));
	end
	self:Show();
end
