-- ============================================================
--  The guild rewards (retail GuildRewards) on server/guild_rewards.cpp, and the guild reputation's bar.
--  API (Cataclysm's / retail's, + the guild level that stands for the achievement):
--    GetNumGuildRewards(), GetGuildRewardInfo(i) -> achievementID (0), itemID, itemName, iconTexture,
--    repLevel, moneyCost, guildLevel;  BuyGuildReward(itemID)
-- ============================================================

local REWARD_ROW_HEIGHT = 44;

local rewards = {};			-- { item =, standing =, price =, level = }

local function Decode(text)
	return (tostring(text or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)); end));
end

function GetNumGuildRewards()
	return #rewards;
end

function GetGuildRewardInfo(index)
	local reward = rewards[index];
	if ( not reward ) then
		return;
	end
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(reward.item);
	return 0, reward.item, name or ("item:"..reward.item), icon or "Interface\\Icons\\INV_Misc_QuestionMark", reward.standing, reward.price, reward.level;
end

function BuyGuildReward(itemID)
	if ( Comm_Send ) then
		Comm_Send("GUILD_REWARD_BUY", itemID);
	end
end

-- the reward can be bought now: the standing and the guild's level
local function IsAvailable(reward)
	local _, _, standing = GetGuildFactionInfo();
	local level = GetGuildLevel and GetGuildLevel() or 0;
	return standing >= reward.standing and level >= reward.level, standing >= reward.standing, level >= reward.level;
end

-- ------------------------------------------------------------ the list

local function Rewards()
	return CommunitiesFrame.Perks.Rewards;
end

function GuildRewards_Init()
	local frame = Rewards();
	if ( frame.List.rows ) then
		return;
	end
	GuildUI_MakeList(frame.List, "GuildUIRewardRowTemplate", REWARD_ROW_HEIGHT, 6, GuildRewards_Update, function(row)
		row:SetScript("OnClick", GuildRewardRow_OnClick);
	end);
end

function GuildRewards_Update()
	local frame = Rewards();
	local list = frame.List;
	if ( not list.rows ) then
		return;
	end
	local offset = FauxScrollFrame_GetOffset(list);
	for i, row in ipairs(list.rows) do
		local reward = rewards[offset + i];
		row.reward = reward;
		if ( reward ) then
			local _, itemID, name, icon, standing, price, level = GetGuildRewardInfo(offset + i);
			local _, _, quality = GetItemInfo(itemID);
			row.Icon:SetTexture(icon);
			row.Name:SetText(name);
			local r, g, b = GetItemQualityColor(quality or 1);
			row.Name:SetTextColor(r, g, b);
			local available, standingOk, levelOk = IsAvailable(reward);
			local needs = {};
			tinsert(needs, (standingOk and "|cffffffff" or "|cffff2020").._G["FACTION_STANDING_LABEL"..standing].."|r");
			if ( level > 0 ) then
				tinsert(needs, (levelOk and "|cffffffff" or "|cffff2020").."уровень гильдии "..level.."|r");
			end
			row.Needs:SetText("Требуется: "..table.concat(needs, ", "));
			row.Money:SetText(price > 0 and GetCoinTextureString(price) or "");
			row.Icon:SetDesaturated(not available);
			row.Lock:SetShown(not available);
			row:Show();
		else
			row:Hide();
		end
	end
	FauxScrollFrame_Update(list, #rewards, #list.rows, list.rowHeight);
	frame.Empty:SetShown(#rewards == 0);
	GuildRewards_UpdateReputation();
end

-- the guild reputation's bar under the rewards (retail GuildRewards' "Guild Reputation:")
function GuildRewards_UpdateReputation()
	local bar = CommunitiesFrame.Perks.RepBar;
	local _, _, standing, barMin, barMax, value = GetGuildFactionInfo();
	bar:SetMinMaxValues(0, math.max(1, barMax - barMin));
	bar:SetValue(math.min(value, barMax) - barMin);
	bar.Text:SetFormattedText("%s  %d / %d", _G["FACTION_STANDING_LABEL"..standing] or "", value - barMin, barMax - barMin);
	local color = FACTION_BAR_COLORS[standing];
	if ( color ) then
		bar:SetStatusBarColor(color.r, color.g, color.b);
	end
	local weekly, cap = GetGuildRepWeekly();
	if ( cap > 0 ) then
		CommunitiesFrame.Perks.RepWeekly:SetFormattedText("За неделю: %d / %d", weekly, cap);
	else
		CommunitiesFrame.Perks.RepWeekly:SetText("");
	end
end

function GuildRewardsRepBar_OnEnter(self)
	local _, _, standing, barMin, barMax, value = GetGuildFactionInfo();
	local weekly, cap = GetGuildRepWeekly();
	GameTooltip:SetOwner(self, "ANCHOR_TOP");
	GameTooltip:SetText("Репутация с гильдией");
	GameTooltip:AddLine(format("%s: %d / %d", _G["FACTION_STANDING_LABEL"..standing] or "", value - barMin, barMax - barMin), 1, 1, 1);
	GameTooltip:AddLine(format("За неделю: %d / %d", weekly, cap), 1, 1, 1);
	GameTooltip:AddLine("Репутацию приносят задания и победы в гильдейских группах. Она открывает награды гильдии.", nil, nil, nil, true);
	GameTooltip:Show();
end

function GuildRewardRow_OnEnter(self)
	if ( not self.reward ) then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink("item:"..self.reward.item);
	local _, standingOk, levelOk = IsAvailable(self.reward);
	if ( not standingOk ) then
		GameTooltip:AddLine("Требуется репутация с гильдией: ".._G["FACTION_STANDING_LABEL"..self.reward.standing], 1, 0.1, 0.1);
	end
	if ( not levelOk ) then
		GameTooltip:AddLine(format("Требуется уровень гильдии: %d", self.reward.level), 1, 0.1, 0.1);
	end
	if ( self.reward.price > 0 ) then
		SetTooltipMoney(GameTooltip, self.reward.price);
	end
	GameTooltip:Show();
end

-- a click: buy (confirmed); shift-click: the item's link
function GuildRewardRow_OnClick(self)
	local reward = self.reward;
	if ( not reward ) then
		return;
	end
	local name, link = GetItemInfo(reward.item);
	if ( IsModifiedClick("CHATLINK") and link ) then
		ChatEdit_InsertLink(link);
		return;
	end
	if ( not IsAvailable(reward) ) then
		UIErrorsFrame:AddMessage("Эта награда пока недоступна.", 1, 0.1, 0.1);
		return;
	end
	StaticPopup_Show("GUILDUI_BUY_REWARD", link or name or reward.item, GetCoinTextureString(reward.price), reward.item);
end

StaticPopupDialogs["GUILDUI_BUY_REWARD"] = {
	text = "Купить %s за %s?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		BuyGuildReward(data);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

-- ------------------------------------------------------------ server messages

local function OnRewards(list)
	wipe(rewards);
	if ( list and list ~= "-" ) then
		for entry in list:gmatch("[^,]+") do
			local item, standing, price, level = strsplit(";", entry);
			tinsert(rewards, { item = tonumber(item), standing = tonumber(standing) or 4, price = tonumber(price) or 0, level = tonumber(level) or 0 });
		end
	end
	if ( CommunitiesFrame and CommunitiesFrame.Perks:IsShown() ) then
		GuildRewards_Update();
	end
end

local function OnResult(ok, text)
	if ( ok == "1" ) then
		PlaySound("LOOTWINDOWCOINSOUND");
	else
		UIErrorsFrame:AddMessage(Decode(text), 1, 0.1, 0.1);
	end
end

local registered = false;
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:SetScript("OnEvent", function(self, event)
	if ( registered or not Comm_Register ) then
		return;
	end
	Comm_Register("GUILD_REWARDS", OnRewards);
	Comm_Register("GUILD_REWARD_RESULT", OnResult);
	registered = true;
	Comm_Send("GUILD_REWARDS_GET");
	if ( GuildProgression_RegisterCallback ) then
		GuildProgression_RegisterCallback(function(e)
			if ( CommunitiesFrame and CommunitiesFrame.Perks:IsShown() ) then
				GuildRewards_Update();
			end
		end);
	end
end);
