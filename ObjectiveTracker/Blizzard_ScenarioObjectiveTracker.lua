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
	self.FixedBlocks = { self.StageBlock, self.ObjectivesBlock };
	Mixin(self.StageBlock, ScenarioObjectiveTrackerStageMixin);
	for _, block in ipairs(self.FixedBlocks) do
		block.parentModule = self;
		block:SetParent(self.ContentsFrame);
	end
	self.StageBlock.height = 83;
	self.StageBlock.fixedHeight = true;
	self.StageBlock.fixedWidth = true;
	self.ObjectivesBlock.offsetX = 32;
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

	self:LayoutBlock(stageBlock);
	if self.currentStage ~= currentStage or self.scenarioID ~= scenarioID then
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
		self.Name:SetText("");
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
