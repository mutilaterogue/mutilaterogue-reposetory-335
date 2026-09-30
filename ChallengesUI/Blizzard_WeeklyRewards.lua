-- Great Vault (retail WeeklyRewardsFrame, the Mythic+ row) for 3.3.5.
-- MythicPlus.vault (Blizzard_ChallengeModeCompat.lua): runs of this week and last week's options.

UIPanelWindows["WeeklyRewardsFrame"] = { area = "center", pushable = 0, whileDead = 1 };

local THRESHOLDS = { 1, 4, 8 };

local function Activity(index)
	return _G["WeeklyRewardsFrameActivity" .. index];
end

function WeeklyRewardsFrame_OnLoad(self)
	self:RegisterForDrag("LeftButton");
	if self.TitleContainer and self.TitleContainer.TitleText then
		self.TitleContainer.TitleText:SetText(GREAT_VAULT_REWARDS);
	end
	if self.PortraitContainer and self.PortraitContainer.portrait then
		self.PortraitContainer.portrait:SetAtlas("gficon-chest-evergreen-greatvault-complete", false);
	end
	MythicPlus_RegisterCallback(function(event)
		if event == "VAULT_OPEN" then
			ShowUIPanel(self);
		elseif event == "VAULT" and self:IsShown() then
			WeeklyRewardsFrame_Update(self);
		end
	end);
end

function WeeklyRewardsFrame_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	MythicPlus_Send("MPLUS_VAULT_GET");
	WeeklyRewardsFrame_Update(self);
end

function WeeklyRewardsFrame_Toggle()
	if WeeklyRewardsFrame:IsShown() then
		HideUIPanel(WeeklyRewardsFrame);
	else
		ShowUIPanel(WeeklyRewardsFrame);
	end
end

function WeeklyRewardsFrame_Update(self)
	local vault = MythicPlus.vault or { runs = 0, levels = {}, options = {}, claimed = false };
	local hasOptions = next(vault.options) ~= nil;

	for index, threshold in ipairs(THRESHOLDS) do
		local activity = Activity(index);
		local option = vault.options[index];
		activity.Threshold:SetText(WEEKLY_REWARDS_THRESHOLD_MYTHIC:format(threshold));
		activity.option = option;
		activity.slot = index;

		local item = activity.ItemFrame;
		if option and option.itemID > 0 then
			-- last week's reward: pick one
			item.Icon:SetTexture(GetItemIcon(option.itemID));
			item.Icon:SetDesaturated(vault.claimed and not option.claimed);
			item.Glow:SetShown(not vault.claimed);
			item.itemID = option.itemID;
			activity.Level:SetText(ITEM_MYTHIC .. " +" .. option.level);
			activity.Progress:SetText(option.claimed and "|cff1eff00" .. COLLECTED .. "|r" or "");
			activity.SelectButton:SetShown(not vault.claimed);
		else
			-- this week's progress toward the option
			local done = math.min(vault.runs, threshold);
			item.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");
			item.Icon:SetDesaturated(done < threshold);
			item.Glow:Hide();
			item.itemID = nil;
			activity.Progress:SetText(("%d/%d"):format(done, threshold));
			local level = vault.levels[threshold];
			activity.Level:SetText(level and (ITEM_MYTHIC .. " +" .. level) or "");
			activity.SelectButton:Hide();
		end
	end

	if hasOptions and not vault.claimed then
		self.Hint:SetText(GREAT_VAULT_REWARDS_WAITING);
	else
		self.Hint:SetText("");
	end
end

function WeeklyRewardsActivityItem_OnEnter(self)
	if self.itemID then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("item:" .. self.itemID);
		GameTooltip:Show();
	end
end

function WeeklyRewardsActivitySelect_OnClick(self)
	local activity = self:GetParent();
	if activity.option then
		MythicPlus_Send("MPLUS_VAULT_CHOOSE", activity.slot);
		PlaySound("igMainMenuOptionCheckBoxOn");
	end
end
