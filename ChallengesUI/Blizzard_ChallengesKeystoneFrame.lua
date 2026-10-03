-- Font of Power: retail ChallengesKeystoneFrameMixin (Blizzard_ChallengesUI.lua) for 3.3.5.
-- C_ChallengeMode.SlotKeystone / StartChallengeMode are AddonComm messages here (MPLUS_INSERT / MPLUS_START),
-- the server answers MPLUS_SLOTTED (-> OnKeystoneSlotted). Data: Blizzard_ChallengeModeCompat.lua.

UIPanelWindows["ChallengesKeystoneFrame"] = { area = "center", pushable = 0, whileDead = 0 };

local LEVEL_SCALE = 1.08;	-- server/mythic_plus.cpp LEVEL_SCALE: health and damage per level above 1

---------------------------------------------------------------------------
-- animations: the retail XML AnimationGroups (alpha from/to, startDelay, duration) played in OnUpdate
---------------------------------------------------------------------------
local INSERTED_ANIM = {
	{ "KeystoneSlotGlow", 0, 0.15, 0, 1 },
	{ "PentagonLines", 0.15, 0.25, 0, 1 },
	{ "PentagonLines", 0.55, 1, 1, 0.55 },
	{ "LargeCircleGlow", 0.05, 0.25, 0, 1 },
	{ "LargeCircleGlow", 0.35, 1, 1, 0.55 },
	{ "SmallCircleGlow", 0, 0.25, 0, 1 },
	{ "SmallCircleGlow", 0.25, 1, 1, 0.55 },
	{ "RuneCircleT", 0.35, 0.35, 0, 1 },
	{ "RuneT", 0.45, 0.45, 0, 1 },
	{ "RuneCircleR", 0.35, 0.35, 0, 1 },
	{ "RuneR", 0.45, 0.45, 0, 1 },
	{ "RuneCircleBR", 0.35, 0.35, 0, 1 },
	{ "RuneBR", 0.45, 0.45, 0, 1 },
	{ "RuneCircleBL", 0.35, 0.35, 0, 1 },
	{ "RuneBL", 0.45, 0.45, 0, 1 },
	{ "RuneCircleL", 0.35, 0.35, 0, 1 },
	{ "RuneL", 0.45, 0.45, 0, 1 },
	-- RunesLargeAnim / RunesSmallAnim
	{ "RunesLarge", 0, 0.25, 0.15, 1 },
	{ "LargeRuneGlow", 0.1, 0.25, 0, 1 },
	{ "LargeRuneGlow", 0.6, 1, 1, 0 },
	{ "GlowBurstLarge", 0.25, 0.25, 0, 1 },
	{ "GlowBurstLarge", 0.5, 0.5, 1, 0 },
	{ "RunesSmall", 0, 0.25, 0.15, 1 },
	{ "SmallRuneGlow", 0, 0.25, 0, 1 },
	{ "SmallRuneGlow", 0.5, 1, 1, 0 },
	{ "GlowBurstSmall", 0, 0.25, 0, 1 },
	{ "GlowBurstSmall", 0.25, 0.5, 1, 0 },
};
local INSERTED_DURATION = 1.55;
local PULSE_PERIOD = 3;		-- PulseAnim: BgBurst2 0 -> 0.75 -> 0, looping

local function PlayTimeline(self, t)
	-- later entries of a region override earlier ones once they start
	for _, step in ipairs(INSERTED_ANIM) do
		local region = self[step[1]];
		local startAt, duration, from, to = step[2], step[3], step[4], step[5];
		if t >= startAt then
			local p = math.min(1, (t - startAt) / duration);
			region:SetAlpha(from + (to - from) * p);
		end
	end
end

-- looping rotations (RunesLargeRotateAnim -360 / 60 s, RunesSmallRotateAnim 360 / 60 s)
local function CreateRotation(region, degrees, duration)
	local group = region:CreateAnimationGroup();
	local rotation = group:CreateAnimation("Rotation");
	rotation:SetDegrees(degrees);
	rotation:SetDuration(duration);
	group:SetLooping("REPEAT");
	return group;
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
function ChallengesKeystoneFrame_OnLoad(self)
	self.Affixes = {};
	self.baseStates = {};
	for _, r in ipairs({ self:GetRegions() }) do
		self.baseStates[r] = { shown = r:IsShown(), alpha = r:GetAlpha() };
	end

	self.rotations = {
		CreateRotation(self.RunesLarge, -360, 60),
		CreateRotation(self.LargeRuneGlow, -360, 60),
		CreateRotation(self.GlowBurstLarge, -360, 60),
		CreateRotation(self.RunesSmall, 360, 60),
		CreateRotation(self.SmallRuneGlow, 360, 60),
		CreateRotation(self.GlowBurstSmall, 360, 60),
	};

	MythicPlus_RegisterCallback(function(event, ...)
		if event == "FONT_OPEN" then
			ShowUIPanel(self);
		elseif event == "FONT_CLOSE" then
			self.closedByServer = true;
			HideUIPanel(self);
		elseif event == "SLOTTED" then
			local slotted = ...;
			if slotted then
				ChallengesKeystoneFrame_OnKeystoneSlotted(self);
			elseif self.slotted then
				ChallengesKeystoneFrame_OnKeystoneRemoved(self);
			end
		end
	end);
end

function ChallengesKeystoneFrame_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	ChallengesKeystoneFrame_Reset(self);
	self.closedByServer = nil;
end

function ChallengesKeystoneFrame_OnHide(self)
	if not self.startedChallengeMode then
		PlaySound("igCharacterInfoClose");
	end
	if self.slotted then
		MythicPlus_Send("MPLUS_REMOVE");
	end
	if not self.closedByServer then
		MythicPlus_Send("MPLUS_CLOSE");
	end
	ChallengesKeystoneFrame_Reset(self);
end

function ChallengesKeystoneFrame_Reset(self)
	self.KeystoneSlot.Texture:SetTexture(nil);
	self.slotted = nil;
	self.animTime = nil;
	for _, group in ipairs(self.rotations) do
		group:Stop();
	end
	self.StartButton:Disable();
	self.TimeLimit:Hide();
	self.DungeonName:Hide();
	self.PowerLevel:Hide();

	for i = 1, #self.Affixes do
		self.Affixes[i]:Hide();
	end

	for region, state in pairs(self.baseStates) do
		if state.shown then region:Show(); else region:Hide(); end
		region:SetAlpha(state.alpha);
	end

	self.startedChallengeMode = nil;
end

function ChallengesKeystoneFrame_OnUpdate(self, elapsed)
	if not self.animTime then
		return;
	end
	self.animTime = self.animTime + elapsed;
	local t = self.animTime;
	if t <= INSERTED_DURATION + elapsed then
		PlayTimeline(self, math.min(t, INSERTED_DURATION));
	end
	if t >= INSERTED_DURATION then
		-- InsertedAnim OnFinished: PulseAnim + StartButton
		local p = ((t - INSERTED_DURATION) % PULSE_PERIOD) / (PULSE_PERIOD / 2);
		self.BgBurst2:SetAlpha(p < 1 and 0.75 * p or 0.75 * (2 - p));
	end
end

function ChallengesKeystoneFrame_OnMouseUp(self)
	if CursorHasItem() then
		ChallengesKeystoneSlot_OnReceiveDrag(self.KeystoneSlot);
	end
end

local function CreateAndPositionAffixes(self, num)
	local frameWidth, spacing, distance = 52, 4, -34;
	while #self.Affixes < num do
		local index = #self.Affixes + 1;
		local frame = CreateFrame("Frame", self:GetName() .. "Affix" .. index, self, "ChallengesKeystoneFrameAffixTemplate");
		local prev = self.Affixes[index - 1];
		if prev then
			frame:SetPoint("LEFT", prev, "RIGHT", spacing, 0);
		end
		self.Affixes[index] = frame;
	end
	for i = num + 1, #self.Affixes do
		self.Affixes[i]:Hide();
	end
	if num == 0 then
		return;		-- +1: no affixes
	end

	-- the leftmost affix
	local frame = self.Affixes[1];
	frame:ClearAllPoints();
	if num % 2 == 1 then
		local x = (num - 1) / 2;
		frame:SetPoint("TOPLEFT", self.Divider, "TOP", -((frameWidth / 2) + (frameWidth * x) + (spacing * x)), distance);
	else
		local x = num / 2;
		frame:SetPoint("TOPLEFT", self.Divider, "TOP", -((frameWidth * x) + (spacing * (x - 1)) + (spacing / 2)), distance);
	end

	for i = num + 1, #self.Affixes do
		self.Affixes[i]:Hide();
	end
end

function ChallengesKeystoneFrame_OnKeystoneSlotted(self)
	local key = MythicPlus.key;
	if not key then
		return;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	self.slotted = true;
	self.animTime = 0;
	for _, group in ipairs(self.rotations) do
		group:Play();
	end
	self.InstructionBackground:Hide();
	self.Instructions:Hide();
	self.KeystoneSlot.Texture:SetTexture(GetItemIcon(KEYSTONE_ITEM_ID));
	self.StartButton:Enable();

	local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(key.mapID);
	self.DungeonName:SetText(name);
	self.DungeonName:Show();
	self.TimeLimit:SetText(SecondsToTime(timeLimit or 0, false, true));
	self.TimeLimit:Show();

	local powerLevel = key.level;
	self.PowerLevel:SetText(CHALLENGE_MODE_POWER_LEVEL:format(powerLevel));
	self.PowerLevel:Show();

	local affixes = MythicPlus_GetAffixesForLevel(powerLevel);
	local extra = 0;
	if powerLevel >= 3 then
		-- retail GetPowerLevelDamageHealthMod: the server scales health and damage the same
		local pct = math.floor((LEVEL_SCALE ^ (powerLevel - 1) - 1) * 100 + 0.5);
		extra = 2;
		CreateAndPositionAffixes(self, extra + #affixes);
		ChallengesKeystoneFrameAffix_SetUp(self.Affixes[1], { key = "dmg", pct = pct });
		ChallengesKeystoneFrameAffix_SetUp(self.Affixes[2], { key = "health", pct = pct });
	else
		CreateAndPositionAffixes(self, #affixes);
	end
	for i = 1, #affixes do
		ChallengesKeystoneFrameAffix_SetUp(self.Affixes[i + extra], affixes[i]);
	end
end

function ChallengesKeystoneFrame_OnKeystoneRemoved(self)
	PlaySound("igMainMenuOptionCheckBoxOff");
	ChallengesKeystoneFrame_Reset(self);
	self.StartButton:Disable();
end

function ChallengesKeystoneFrame_StartChallengeMode(self)
	PlaySound("igMainMenuOptionCheckBoxOn");
	MythicPlus_Send("MPLUS_START");
	self.startedChallengeMode = true;
end

---------------------------------------------------------------------------
-- keystone slot (retail ChallengesKeystoneSlotMixin)
---------------------------------------------------------------------------
local function FindKeystone()
	for bag = KEYRING_CONTAINER or -2, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot);
			if link and tonumber(string.match(link, "item:(%d+)")) == KEYSTONE_ITEM_ID then
				return bag, slot;
			end
		end
	end
	return nil;
end

function ChallengesKeystoneSlot_OnLoad(self)
	self:RegisterForDrag("LeftButton");
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
end

function ChallengesKeystoneSlot_OnEnter(self)
	local bag, slot = FindKeystone();
	if self:GetParent().slotted and bag then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetBagItem(bag, slot);
		GameTooltip:Show();
	end
end

-- retail C_ChallengeMode.SlotKeystone: the item on the cursor goes into the slot
function ChallengesKeystoneSlot_OnReceiveDrag(self)
	local kind, itemID = GetCursorInfo();
	if kind == "item" and itemID == KEYSTONE_ITEM_ID then
		ClearCursor();
		MythicPlus_Send("MPLUS_INSERT");
	end
end

function ChallengesKeystoneSlot_OnDragStart(self)
	if self:GetParent().slotted then
		MythicPlus_Send("MPLUS_REMOVE");
	end
end

function ChallengesKeystoneSlot_OnClick(self)
	if CursorHasItem() then
		ChallengesKeystoneSlot_OnReceiveDrag(self);
	end
end

---------------------------------------------------------------------------
-- affixes (retail ChallengesKeystoneFrameAffixMixin)
---------------------------------------------------------------------------
CHALLENGE_MODE_EXTRA_AFFIX_INFO = {
	["dmg"] = {
		name = CHALLENGE_MODE_ENEMY_EXTRA_DAMAGE,
		desc = CHALLENGE_MODE_ENEMY_EXTRA_DAMAGE_DESCRIPTION,
		texture = "Interface\\Icons\\Ability_DualWield",
	},
	["health"] = {
		name = CHALLENGE_MODE_ENEMY_EXTRA_HEALTH,
		desc = CHALLENGE_MODE_ENEMY_EXTRA_HEALTH_DESCRIPTION,
		texture = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
	},
};

function ChallengesKeystoneFrameAffix_OnEnter(self)
	if self.affixID or self.info then
		local name, description;
		if self.info then
			local tbl = CHALLENGE_MODE_EXTRA_AFFIX_INFO[self.info.key];
			name = tbl.name;
			description = string.format(tbl.desc, self.info.pct);
		else
			name, description = C_ChallengeMode.GetAffixInfo(self.affixID);
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(name, 1, 1, 1, 1, true);
		GameTooltip:AddLine(description, nil, nil, nil, true);
		GameTooltip:Show();
	end
end

function ChallengesKeystoneFrameAffix_SetUp(self, affixInfo)
	if type(affixInfo) == "table" then
		local info = affixInfo;
		self.Portrait:SetTexture(CHALLENGE_MODE_EXTRA_AFFIX_INFO[info.key].texture);
		self.Percent:SetText(("+%d%%"):format(info.pct));
		self.Percent:Show();
		self.info = info;
		self.affixID = nil;
	else
		local _, _, filedataid = C_ChallengeMode.GetAffixInfo(affixInfo);
		self.Portrait:SetTexture(filedataid);
		self.Percent:Hide();
		self.affixID = affixInfo;
		self.info = nil;
	end
	self:Show();
end
