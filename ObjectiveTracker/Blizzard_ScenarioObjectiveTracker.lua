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
	ScenarioChallengeModeBlock_Init(self.ChallengeModeBlock);
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
		ScenarioChallengeModeBlock_Update(self.ChallengeModeBlock);
		self:LayoutBlock(self.ChallengeModeBlock);
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
		end
	end
end

-- *****************************************************************************************************
-- ***** CHALLENGE MODE BLOCK (keystone level, affixes, time left, timer bar, deaths)
-- *****************************************************************************************************

function ScenarioChallengeModeBlock_Init(block)
	block.Affixes = {};
	for i = 1, 3 do
		local affix = CreateFrame("Frame", nil, block);
		affix:SetWidth(22);
		affix:SetHeight(22);
		affix:EnableMouse(true);
		affix.Portrait = affix:CreateTexture(nil, "ARTWORK");
		affix.Portrait:SetWidth(20);
		affix.Portrait:SetHeight(20);
		affix.Portrait:SetPoint("CENTER");
		affix.Border = affix:CreateTexture(nil, "OVERLAY");
		affix.Border:SetAtlas("ChallengeMode-AffixRing-Sm", true);
		affix.Border:SetPoint("CENTER");
		affix:SetScript("OnEnter", function(self)
			local name, description = C_ChallengeMode.GetAffixInfo(self.affixID);
			if name then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
				GameTooltip:SetText(name, 1, 1, 1, 1, true);
				GameTooltip:AddLine(description, nil, nil, nil, true);
				GameTooltip:Show();
			end
		end);
		affix:SetScript("OnLeave", GameTooltip_Hide);
		affix:Hide();
		block.Affixes[i] = affix;
	end
	block.StatusBar:SetMinMaxValues(0, 1);
end

function ScenarioChallengeModeBlock_Update(block)
	local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo();
	block.Level:SetText(CHALLENGE_MODE_POWER_LEVEL:format(level));

	-- affixes right-aligned in the top row (retail)
	local count = #affixes;
	for i, affix in ipairs(block.Affixes) do
		local affixID = affixes[i];
		if affixID then
			local _, _, icon = C_ChallengeMode.GetAffixInfo(affixID);
			affix.affixID = affixID;
			affix.Portrait:SetTexture(icon);
			affix:ClearAllPoints();
			affix:SetPoint("TOPRIGHT", block, "TOPRIGHT", -28 - (count - i) * 24, -14);
			affix:Show();
		else
			affix:Hide();
		end
	end

	local run = MythicPlus.run;
	local limit = run and run.timeLimit or 0;
	block.ChestTimes:SetText(limit > 0 and string.format("+2 %s   +3 %s", MythicPlus_FormatTime(limit * 0.8), MythicPlus_FormatTime(limit * 0.6)) or "");
	ScenarioChallengeModeBlock_UpdateTime(block);
end

function ScenarioChallengeModeBlock_UpdateTime(block)
	local run = MythicPlus.run;
	if not run then
		return;
	end
	local deaths, timeLost = C_ChallengeMode.GetDeathCount();
	local elapsed = MythicPlus_GetElapsedMs() / 1000 + timeLost;
	local limit = run.timeLimit;

	if run.state == MYTHIC_RUN_COUNTDOWN then
		block.TimeLeft:SetText(MythicPlus_FormatTime(limit));
		block.TimeLeft:SetTextColor(1, 1, 1);
		block.StatusBar:SetValue(1);
	elseif elapsed <= limit then
		block.TimeLeft:SetText(MythicPlus_FormatTime(limit - elapsed));
		if run.state == MYTHIC_RUN_DONE_TIMED then
			block.TimeLeft:SetTextColor(0.1, 1, 0.1);
		else
			block.TimeLeft:SetTextColor(1, 1, 1);
		end
		block.StatusBar:SetValue(limit > 0 and (limit - elapsed) / limit or 0);
	else
		-- over time: how much over, red, empty bar
		block.TimeLeft:SetText("+" .. MythicPlus_FormatTime(elapsed - limit));
		block.TimeLeft:SetTextColor(1, 0.1, 0.1);
		block.StatusBar:SetValue(0);
	end

	if deaths > 0 then
		block.DeathCount.Count:SetText(deaths);
		block.DeathCount:Show();
	else
		block.DeathCount:Hide();
	end
end

function ScenarioChallengeModeBlock_OnUpdate(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed;
	if self.elapsed < 0.1 then
		return;
	end
	self.elapsed = 0;
	ScenarioChallengeModeBlock_UpdateTime(self);
end

function ScenarioChallengeDeathCount_OnEnter(self)
	local deaths, timeLost = C_ChallengeMode.GetDeathCount();
	GameTooltip:SetOwner(self, "ANCHOR_LEFT");
	GameTooltip:SetText(CHALLENGE_MODE_DEATH_COUNT_TITLE:format(deaths), 1, 1, 1);
	GameTooltip:AddLine(CHALLENGE_MODE_DEATH_COUNT_DESCRIPTION:format(MythicPlus_FormatTime(timeLost)));
	GameTooltip:Show();
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
