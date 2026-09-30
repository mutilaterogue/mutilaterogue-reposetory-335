-- ScenarioObjectiveTracker (retail) for 3.3.5, dungeon display only.
-- The retail module without challenge mode, proving grounds, widgets, Maw buffs, tiered entrance,
-- scenario spells and the stage slide. Data: C_Scenario / C_ScenarioInfo of Blizzard_ScenarioCompat335.lua.

local settings = {
	hasDisplayPriority = true,
	headerText = TRACKER_HEADER_DUNGEON,
	events = { "PLAYER_ENTERING_WORLD" },
	fromHeaderOffsetY = 0,
	blockOffsetX = 20,
	lineSpacing = 12,
	fromBlockOffsetY = -2,
	lineTemplate = "ObjectiveTrackerAnimLineTemplate",
	progressBarTemplate = "ScenarioProgressBarTemplate",
	progressBarLineSpacing = 2,
	showCriteria = true,
	leftMargin = -20,
};

ScenarioObjectiveTrackerMixin = CreateFromMixins(ObjectiveTrackerModuleMixin, settings);

function ScenarioObjectiveTrackerMixin:InitModule()
	-- 3.3.5: no parentArray - the fixed blocks are listed here
	self.FixedBlocks = { self.ChallengeModeBlock, self.StageBlock, self.ObjectivesBlock };
	Mixin(self.StageBlock, ScenarioObjectiveTrackerStageMixin);
	for _, block in ipairs(self.FixedBlocks) do
		block.parentModule = self;
		block:SetParent(self.ContentsFrame);
	end
	self.ChallengeModeBlock.height = 87;
	self.ChallengeModeBlock.fixedHeight = true;
	self.ChallengeModeBlock.fixedWidth = true;
	Mixin(self.ChallengeModeBlock, ScenarioObjectiveTrackerChallengeModeMixin);
	self.ChallengeModeBlock:OnLoad();
	self.StageBlock.height = 83;
	self.StageBlock.fixedHeight = true;
	self.StageBlock.fixedWidth = true;
	self.ObjectivesBlock.offsetX = 14;
	self.ObjectivesBlock:Init();
	self.ObjectivesBlock:Reset();

	self.StageBlock.NormalBG:SetAtlas("evergreen-scenario-trackerheader", true);
	self.StageBlock.FinalBG:SetAtlas("evergreen-scenario-trackerheader-final-filigree", true);
	self.StageBlock.GlowTexture:SetAtlas("evergreen-scenario-trackerheader", true);

	self.shouldShowCriteria = C_Scenario.ShouldShowCriteria();

	-- the StageBlock art is wider than the module: room for it, like retail
	self.Header:SetPoint("TOPLEFT", self, "TOPLEFT", self.blockOffsetX, 0);
	self:SetWidth(self:GetWidth() + self.blockOffsetX);

	-- scenario events come from the compat layer
	ScenarioCompat_RegisterCallback(function(event, ...)
		self:OnEvent(event, ...);
	end);
end

function ScenarioObjectiveTrackerMixin:OnEvent(event, ...)
	if event == "SCENARIO_UPDATE" then
		local newStage = ...;
		self:SetHasNewStage(newStage);
		self:MarkDirty();
	elseif event == "SCENARIO_CRITERIA_UPDATE" then
		self:MarkDirty();
	elseif event == "SCENARIO_COMPLETED" then
		self:MarkDirty();
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:MarkDirty();
	end
end

function ScenarioObjectiveTrackerMixin:ShouldShowCriteria()
	return self.shouldShowCriteria;
end

function ScenarioObjectiveTrackerMixin:SetHasNewStage(hasNewStage)
	self.hasNewStage = hasNewStage;
end

-- override: the fixed blocks are managed here, not pooled
function ScenarioObjectiveTrackerMixin:MarkBlocksUnused()
	for _, block in ipairs(self.FixedBlocks or {}) do
		block.used = false;
	end
end

function ScenarioObjectiveTrackerMixin:FreeUnusedBlocks()
	for _, block in ipairs(self.FixedBlocks or {}) do
		if not block.used then
			block:Hide();
		end
	end
end

function ScenarioObjectiveTrackerMixin:LayoutContents()
	local hasNewStage = self.hasNewStage;
	self:SetHasNewStage(false);

	local scenarioName, currentStage, numStages, flags, _, _, _, xp, money, scenarioType, _, textureKit, scenarioID = C_Scenario.GetInfo();
	if not numStages or numStages == 0 then
		self.currentStage = nil;
		self.scenarioID = nil;
		return;
	end

	local stageName, stageDescription, numCriteria = C_Scenario.GetStepInfo();
	local scenarioCompleted = currentStage > numStages;
	local stageBlock = self.StageBlock;

	-- keystone run: the timer block instead of the stage block (retail ScenarioChallengeModeBlock)
	if scenarioType == LE_SCENARIO_TYPE_CHALLENGE_MODE then
		self.ChallengeModeBlock:CheckActivate();
		if self.ChallengeModeBlock:IsActive() then
			self:LayoutBlock(self.ChallengeModeBlock);
		end
		self.currentStage = nil;
	else
		self:LayoutBlock(stageBlock);
	end
	if scenarioType ~= LE_SCENARIO_TYPE_CHALLENGE_MODE and (self.currentStage ~= currentStage or self.scenarioID ~= scenarioID) then
		self.currentStage = currentStage;
		self.scenarioID = scenarioID;
		stageBlock:UpdateStageBlock(flags, currentStage, stageName, numStages, scenarioCompleted);
		if hasNewStage then
			stageBlock:PlayGlow();
		end
	end

	-- header
	if C_Scenario.IsRaid and C_Scenario.IsRaid() then
		self.Header.Text:SetText(TRACKER_HEADER_RAID);
	elseif scenarioType == LE_SCENARIO_TYPE_USE_DUNGEON_DISPLAY then
		self.Header.Text:SetText(TRACKER_HEADER_DUNGEON);
	else
		self.Header.Text:SetText(scenarioName);
	end

	-- boss lines stay after the dungeon is done, all checked
	local objectivesBlock = self.ObjectivesBlock;
	objectivesBlock:Reset();
	self:UpdateCriteria(numCriteria);
	if objectivesBlock.height > 0 then
		self:LayoutBlock(objectivesBlock);
	end
end

function ScenarioObjectiveTrackerMixin:UpdateCriteria(numCriteria)
	if not self:ShouldShowCriteria() then
		return;
	end

	local objectivesBlock = self.ObjectivesBlock;
	for criteriaIndex = 1, numCriteria do
		local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(criteriaIndex);
		if criteriaInfo then
			local criteriaString = criteriaInfo.description;
			if not criteriaInfo.isWeightedProgress and not criteriaInfo.isFormatted then
				criteriaString = string.format("%d/%d %s", criteriaInfo.quantity, criteriaInfo.totalQuantity, criteriaInfo.description);
			end
			local line;
			if criteriaInfo.completed then
				local existingLine = objectivesBlock:GetExistingLine(criteriaIndex);
				line = objectivesBlock:AddObjective(criteriaIndex, criteriaString, nil, nil, OBJECTIVE_DASH_STYLE_HIDE, OBJECTIVE_TRACKER_COLOR["Complete"]);
				line.Icon:Show();
				line.Icon:SetAtlas("ui-questtracker-tracker-check", false);
				if existingLine and line.SetState and (not line.state or line.state == ObjectiveTrackerAnimLineState.Present) then
					line:SetState(ObjectiveTrackerAnimLineState.Completing);
				end
			else
				line = objectivesBlock:AddObjective(criteriaIndex, criteriaString, nil, nil, OBJECTIVE_DASH_STYLE_HIDE);
				line.Icon:Show();
				line.Icon:SetAtlas("ui-questtracker-objective-nub", false);
			end

			-- progress bar (enemy forces)
			if criteriaInfo.isWeightedProgress and not criteriaInfo.completed then
				objectivesBlock:AddProgressBar(criteriaIndex, self.progressBarLineSpacing);
			end
		end
	end
end

-- *****************************************************************************************************
-- ***** CHALLENGE MODE BLOCK (retail ScenarioObjectiveTrackerChallengeModeMixin)
-- 3.3.5: no world elapsed timers - the run time comes from MythicPlus (server), the block ticks itself
-- *****************************************************************************************************

ScenarioObjectiveTrackerChallengeModeMixin = { };

function ScenarioObjectiveTrackerChallengeModeMixin:OnLoad()
	self.StartedDepleted:SetScript("OnEnter", function()
		GameTooltip:SetOwner(self.StartedDepleted, "ANCHOR_RIGHT");
		GameTooltip:SetText(CHALLENGE_MODE_DEPLETED_KEYSTONE, 1, 1, 1);
		GameTooltip:AddLine(CHALLENGE_MODE_KEYSTONE_DEPLETED_AT_START, nil, nil, nil, true);
		GameTooltip:Show();
	end);

	self.TimesUpLootStatus:SetScript("OnEnter", function()
		GameTooltip:SetOwner(self.TimesUpLootStatus, "ANCHOR_RIGHT");
		GameTooltip:SetText(CHALLENGE_MODE_TIMES_UP, 1, 1, 1);
		local line;
		if self.wasDepleted then
			if IsPartyLeader() then
				line = CHALLENGE_MODE_TIMES_UP_NO_LOOT_LEADER;
			else
				line = CHALLENGE_MODE_TIMES_UP_NO_LOOT;
			end
		else
			line = CHALLENGE_MODE_TIMES_UP_LOOT;
		end
		GameTooltip:AddLine(line, nil, nil, nil, true);
		GameTooltip:Show();
	end);

	self.DeathCount:SetScript("OnEnter", function()
		GameTooltip:SetOwner(self.DeathCount, "ANCHOR_LEFT");
		GameTooltip:SetText(CHALLENGE_MODE_DEATH_COUNT_TITLE:format(self.deathCount), 1, 1, 1);
		GameTooltip:AddLine(CHALLENGE_MODE_DEATH_COUNT_DESCRIPTION:format(SecondsToClock(self.timeLost)));
		GameTooltip:Show();
	end);

	self.affixFrames = {};
	-- art above the bar, texts and icons above the art (the texts live in Border)
	self.Level = self.Border.Level;
	self.TimeLeft = self.Border.TimeLeft;
	self.StartedDepleted:SetPoint("LEFT", self.Level, "RIGHT", 4, 0);
	self.TimesUpLootStatus:SetPoint("LEFT", self.TimeLeft, "RIGHT", 4, 0);
	self.Border:SetFrameLevel(self.StatusBar:GetFrameLevel() + 1);
	self.DeathCount:SetFrameLevel(self.Border:GetFrameLevel() + 1);
	self.StartedDepleted:SetFrameLevel(self.Border:GetFrameLevel() + 1);
	self.TimesUpLootStatus:SetFrameLevel(self.Border:GetFrameLevel() + 1);
	self:SetScript("OnUpdate", self.OnUpdate);
end

-- retail ScenarioTimerMixin:CheckTimers: activates the block when a keystone run is on
function ScenarioObjectiveTrackerChallengeModeMixin:CheckActivate()
	local run = MythicPlus.run;
	local mapID = C_ChallengeMode.GetActiveChallengeMapID();
	if not mapID or not run then
		self.active = nil;
		return;
	end
	local key = run.mapID .. ":" .. run.level;
	if self.active ~= key then
		-- set first: activation must not run again during this layout
		self.active = key;
		self:Activate(run.timeLimit);
	end
	self:UpdateDeathCount();
	self:UpdateTime(math.floor(MythicPlus_GetElapsedMs() / 1000));
end

function ScenarioObjectiveTrackerChallengeModeMixin:IsActive()
	return self.active ~= nil;
end

function ScenarioObjectiveTrackerChallengeModeMixin:OnUpdate(elapsed)
	if not self.active then
		return;
	end
	self.sinceUpdate = (self.sinceUpdate or 0) + elapsed;
	if self.sinceUpdate < 0.2 then
		return;
	end
	self.sinceUpdate = 0;
	self:UpdateDeathCount();
	self:UpdateTime(math.floor(MythicPlus_GetElapsedMs() / 1000));
end

function ScenarioObjectiveTrackerChallengeModeMixin:UpdateTime(elapsedTime)
	-- deaths add their penalty to the run time (retail: the server adds it to the world timer)
	local _, timeLost = C_ChallengeMode.GetDeathCount();
	elapsedTime = elapsedTime + (timeLost or 0);
	local timeLeft = math.max(0, self.timeLimit - elapsedTime);
	local statusBar = self.StatusBar;
	statusBar:SetValue(timeLeft);
	if timeLeft == 0 then
		self.TimeLeft:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b);
		self.StartedDepleted:Hide();
		self.TimesUpLootStatus:Show();
		self.TimesUpLootStatus.NoLoot:SetShown(self.wasDepleted);
	else
		self.TimeLeft:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
	end
	self.TimeLeft:SetText(SecondsToClock(timeLeft));
end

function ScenarioObjectiveTrackerChallengeModeMixin:Activate(timeLimit)
	self.timeLimit = timeLimit;
	local level, affixes, wasEnergized = C_ChallengeMode.GetActiveKeystoneInfo();
	self.Level:SetText(CHALLENGE_MODE_POWER_LEVEL:format(level));
	if not wasEnergized then
		self.wasDepleted = true;
		self.StartedDepleted:Show();
	else
		self.wasDepleted = false;
		self.StartedDepleted:Hide();
	end
	self.TimesUpLootStatus:Hide();
	self:SetUpAffixes(affixes);
	self:UpdateDeathCount();

	self.StatusBar:SetMinMaxValues(0, self.timeLimit);
end

function ScenarioObjectiveTrackerChallengeModeMixin:UpdateDeathCount()
	local deathCount = self.DeathCount;
	local count, timeLost = C_ChallengeMode.GetDeathCount();
	self.deathCount = count;
	self.timeLost = timeLost;
	if timeLost and timeLost > 0 and count and count > 0 then
		deathCount:Show();
		deathCount.Count:SetText(count);
	else
		deathCount:Hide();
	end
end

function ScenarioObjectiveTrackerChallengeModeMixin:SetUpAffixes(affixes)
	for _, frame in ipairs(self.affixFrames) do
		frame:Hide();
	end

	local frameWidth, spacing, distance = 22, 4, -18;
	local prevAffixFrame;
	for i, affixID in ipairs(affixes) do
		local affixFrame = self.affixFrames[i];
		if not affixFrame then
			affixFrame = CreateFrame("Frame", self:GetName() .. "Affix" .. i, self, "ScenarioChallengeModeAffixTemplate");
			self.affixFrames[i] = affixFrame;
		end
		affixFrame:ClearAllPoints();
		if prevAffixFrame then
			affixFrame:SetPoint("LEFT", prevAffixFrame, "RIGHT", spacing, 0);
		else
			local num = #affixes;
			local leftPoint = 28 + (spacing * (num - 1)) + (frameWidth * num);
			affixFrame:SetPoint("TOPLEFT", self, "TOPRIGHT", -leftPoint, distance);
		end
		local _, _, filedataid = C_ChallengeMode.GetAffixInfo(affixID);
		affixFrame.Portrait:SetTexture(filedataid);
		affixFrame.affixID = affixID;
		affixFrame:Show();
		prevAffixFrame = affixFrame;
	end
end

function ScenarioChallengeModeAffix_OnEnter(self)
	if self.affixID then
		local name, description = C_ChallengeMode.GetAffixInfo(self.affixID);
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(name, 1, 1, 1, 1, true);
		GameTooltip:AddLine(description, nil, nil, nil, true);
		GameTooltip:Show();
	end
end

-- *****************************************************************************************************
-- ***** PROGRESS BARS (retail ScenarioTrackerProgressBarMixin:OnGet / SetValue, no flares)
-- *****************************************************************************************************

function ScenarioTrackerProgressBar_OnGet(self, isNew, criteriaIndex)
	local criteriaInfo = criteriaIndex and C_ScenarioInfo.GetCriteriaInfo(criteriaIndex);
	local percentage = criteriaInfo and criteriaInfo.quantity or 0;
	self.Bar:SetValue(percentage);
	self.Bar.Label:SetFormattedText(PERCENTAGE_STRING, percentage);
	self.percentage = percentage;
end

-- *****************************************************************************************************
-- ***** STAGE BLOCK
-- *****************************************************************************************************

ScenarioObjectiveTrackerStageMixin = {};
local StageBlockMixin = ScenarioObjectiveTrackerStageMixin;

function StageBlockMixin:UpdateStageBlock(flags, currentStage, stageName, numStages, scenarioCompleted)
	if scenarioCompleted then
		self.Stage:Hide();
		self.Name:Hide();
		self.CompleteLabel:SetText(DUNGEON_COMPLETED);
		self.CompleteLabel:Show();
		self.FinalBG:Show();
		return;
	end

	self.CompleteLabel:Hide();
	self.Stage:Show();
	self.Name:Show();
	if bit.band(flags, SCENARIO_FLAG_SUPRESS_STAGE_TEXT) == SCENARIO_FLAG_SUPRESS_STAGE_TEXT then
		-- dungeon display: the dungeon name in the stage line
		self.Stage:SetText(stageName);
		self.Stage:SetHeight(36);
		self.Stage:SetPoint("TOPLEFT", 15, -18);
		self.FinalBG:Hide();
		self.Name:SetText(C_Scenario.IsMythic() and DUNGEON_DIFFICULTY3 or "");
	else
		if currentStage == numStages then
			self.Stage:SetText(SCENARIO_STAGE_FINAL or "Последний этап");
			self.FinalBG:Show();
		else
			self.Stage:SetFormattedText(SCENARIO_STAGE or "Этап %d", currentStage);
			self.FinalBG:Hide();
		end
		self.Stage:SetHeight(18);
		self.Name:SetText(stageName);
		self.Stage:SetPoint("TOPLEFT", 15, -10);
	end
	self.NormalBG:Show();
end

function StageBlockMixin:PlayGlow()
	local glow = self.GlowTexture;
	if not glow.anim then
		glow.anim = glow:CreateAnimationGroup();
		local fadeIn = glow.anim:CreateAnimation("Alpha");
		fadeIn:SetChange(1);
		fadeIn:SetDuration(0.266);
		fadeIn:SetOrder(1);
		local fadeOut = glow.anim:CreateAnimation("Alpha");
		fadeOut:SetChange(-1);
		fadeOut:SetDuration(0.333);
		fadeOut:SetStartDelay(0.2);
		fadeOut:SetOrder(2);
		glow.anim:SetScript("OnFinished", function() glow:Hide(); end);
	end
	glow:SetAlpha(0);
	glow:Show();
	glow.anim:Play();
end

function ScenarioObjectiveTrackerStage_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_NONE");
	GameTooltip:ClearAllPoints();
	GameTooltip:SetPoint("RIGHT", self, "LEFT", 0, 0);
	local name, description = C_Scenario.GetStepInfo();
	if name then
		GameTooltip:SetText(name, 1, 0.82, 0);
		if description and description ~= "" then
			GameTooltip:AddLine(description, 1, 1, 1, true);
		end
		GameTooltip:Show();
	end
end
