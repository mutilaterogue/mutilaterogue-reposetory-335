-- Font of Power (retail ChallengesKeystoneFrameMixin) for 3.3.5.
-- The server opens it (MPLUS_FONT_OPEN), the key goes into the slot (drag from the bags or click the slot),
-- "Activate" starts the run (MPLUS_START). Data: Blizzard_ChallengeModeCompat.lua.

UIPanelWindows["ChallengesKeystoneFrame"] = { area = "center", pushable = 0, whileDead = 0 };

local function FindKeystone()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot);
			if link and tonumber(string.match(link, "item:(%d+)")) == KEYSTONE_ITEM_ID then
				return bag, slot;
			end
		end
	end
	return nil;
end

local function AffixFrame(index)
	return _G["ChallengesKeystoneFrameAffix" .. index];
end

function ChallengesKeystoneFrame_Reset(self)
	self.slotted = false;
	self.KeystoneSlot.Icon:SetTexture(nil);
	self.InsertedGlow:SetAlpha(0);
	self.DungeonName:Hide();
	self.PowerLevel:Hide();
	self.TimeLimit:Hide();
	self.Instructions:Show();
	self.StartButton:Disable();
	for i = 1, 3 do
		AffixFrame(i):Hide();
	end
end

function ChallengesKeystoneFrame_ShowKeystone(self)
	local key = MythicPlus.key;
	if not key then
		ChallengesKeystoneFrame_Reset(self);
		return;
	end

	self.slotted = true;
	self.KeystoneSlot.Icon:SetTexture(GetItemIcon(KEYSTONE_ITEM_ID));
	self.Instructions:Hide();
	self.DungeonName:SetText(key.name);
	self.DungeonName:Show();
	self.PowerLevel:SetText(CHALLENGE_MODE_POWER_LEVEL:format(key.level));
	self.PowerLevel:Show();

	if key.timeLimit and key.timeLimit > 0 then
		self.TimeLimit:SetText(MythicPlus_FormatTime(key.timeLimit));
		self.TimeLimit:Show();
	else
		self.TimeLimit:Hide();
	end

	-- affixes centered under the divider (retail: 52 px apart + 4)
	local affixes = MythicPlus_GetAffixesForLevel(key.level);
	local count = #affixes;
	for i = 1, 3 do
		local frame = AffixFrame(i);
		local affixID = affixes[i];
		if affixID then
			local _, _, icon = C_ChallengeMode.GetAffixInfo(affixID);
			frame.affixID = affixID;
			frame.Portrait:SetTexture(icon);
			frame:ClearAllPoints();
			frame:SetPoint("TOP", self.Divider, "BOTTOM", (i - (count + 1) / 2) * 56, -40);
			frame:Show();
		else
			frame:Hide();
		end
	end

	self.StartButton:Enable();
	self.glowTime = 0;
end

function ChallengesKeystoneFrame_OnLoad(self)
	self:RegisterForDrag("LeftButton");
	self:SetMovable(false);

	MythicPlus_RegisterCallback(function(event, ...)
		if event == "FONT_OPEN" then
			ShowUIPanel(self);
		elseif event == "FONT_CLOSE" then
			HideUIPanel(self);
		elseif event == "SLOTTED" then
			local slotted = ...;
			if slotted then
				ChallengesKeystoneFrame_ShowKeystone(self);
				PlaySound("igMainMenuOptionCheckBoxOn");
			else
				ChallengesKeystoneFrame_Reset(self);
			end
		elseif event == "KEY" and self:IsShown() and self.slotted then
			ChallengesKeystoneFrame_ShowKeystone(self);
		end
	end);
end

function ChallengesKeystoneFrame_OnShow(self)
	ChallengesKeystoneFrame_Reset(self);
	PlaySound("igCharacterInfoOpen");
end

function ChallengesKeystoneFrame_OnHide(self)
	if self.slotted then
		MythicPlus_Send("MPLUS_REMOVE");
	end
	MythicPlus_Send("MPLUS_CLOSE");
	ChallengesKeystoneFrame_Reset(self);
	PlaySound("igCharacterInfoClose");
end

-- slotted glow pulse (retail InsertedAnim)
function ChallengesKeystoneFrame_OnUpdate(self, elapsed)
	if not self.slotted or not self.glowTime then
		return;
	end
	self.glowTime = self.glowTime + elapsed;
	local t = self.glowTime;
	if t < 0.5 then
		self.InsertedGlow:SetAlpha(t / 0.5);
	elseif t < 1.5 then
		self.InsertedGlow:SetAlpha(1 - (t - 0.5) * 0.6);
	else
		self.InsertedGlow:SetAlpha(0.4 + 0.2 * math.sin((t - 1.5) * 3));
	end
end

local function InsertKeystone()
	if not MythicPlus.key or not FindKeystone() then
		UIErrorsFrame:AddMessage(CHALLENGE_MODE_INSERT_KEYSTONE, 1, 0.1, 0.1);
		return;
	end
	MythicPlus_Send("MPLUS_INSERT");
end

function ChallengesKeystoneSlot_OnLoad(self)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	self:RegisterForDrag("LeftButton");
end

function ChallengesKeystoneSlot_OnReceiveDrag(self)
	local kind, itemID = GetCursorInfo();
	if kind == "item" and itemID == KEYSTONE_ITEM_ID then
		ClearCursor();
		InsertKeystone();
	end
end

function ChallengesKeystoneSlot_OnClick(self, button)
	local kind, itemID = GetCursorInfo();
	if kind == "item" then
		ChallengesKeystoneSlot_OnReceiveDrag(self);
		return;
	end
	local frame = self:GetParent();
	if button == "RightButton" or frame.slotted then
		if frame.slotted then
			MythicPlus_Send("MPLUS_REMOVE");
		end
		return;
	end
	InsertKeystone();
end

function ChallengesKeystoneSlot_OnDragStart(self)
	local frame = self:GetParent();
	if frame.slotted then
		MythicPlus_Send("MPLUS_REMOVE");
		local bag, slot = FindKeystone();
		if bag then
			PickupContainerItem(bag, slot);
		end
	end
end

function ChallengesKeystoneSlot_OnEnter(self)
	local bag, slot = FindKeystone();
	if self:GetParent().slotted and bag then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetBagItem(bag, slot);
		GameTooltip:Show();
	end
end

function ChallengesKeystoneFrameAffix_OnEnter(self)
	local name, description = C_ChallengeMode.GetAffixInfo(self.affixID);
	if name then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(name, 1, 1, 1, 1, true);
		GameTooltip:AddLine(description, nil, nil, nil, true);
		GameTooltip:Show();
	end
end

function ChallengesKeystoneStartButton_OnClick(self)
	MythicPlus_Send("MPLUS_START");
	PlaySound("igMainMenuOptionCheckBoxOn");
end
