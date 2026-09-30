-- retail ChallengeModeCompleteBannerMixin for 3.3.5: shown on MPLUS_COMPLETE (Blizzard_ChallengeModeCompat.lua).
-- 3.3.5 has no TopBannerManager / AnimationGroup alpha from-to: the retail AnimIn timings are played in OnUpdate.

local TIME_TO_HOLD = 8;
local UNIT_TOKENS = { "player", "party1", "party2", "party3", "party4" };

-- retail AnimIn: { region, startDelay, duration, fromAlpha, toAlpha }
local ANIM_IN = {
	{ "SkullCircle", 0, 0.1, 0, 1 },
	{ "Level", 0, 0.1, 0, 1 },
	{ "BannerTop", 0.35, 0.25, 0, 1 },
	{ "BannerBottom", 0.35, 0.25, 0, 1 },
	{ "BannerMiddle", 0.35, 0.25, 0, 1 },
	{ "BottomFillagree", 0.15, 0.15, 0, 1 },
	{ "RightFillagree", 0.15, 0.1, 0, 1 },
	{ "LeftFillagree", 0.15, 0.1, 0, 1 },
	{ "Title", 0.35, 0.25, 0, 1 },
	{ "DescriptionLineOne", 0.35, 0.25, 0, 1 },
	{ "DescriptionLineTwo", 0.35, 0.25, 0, 1 },
	{ "DescriptionLineThree", 0.35, 0.25, 0, 1 },
	{ "Glow", 0.15, 0.1, 0, 1 },
};
local SKULL_SCALE_TIME = 0.15;	-- SkullCircle 5 -> 1
local FADE_OUT = 0.5;

function ChallengeModeCompleteBanner_OnLoad(self)
	self.PartyMembers = {};
	-- retail GameFontNormalWTF2Outline / QuestFont_Enormous
	local font = self.Level:GetFont();
	self.Level:SetFont(font, 36, "THICKOUTLINE");
	self.Title:SetFont(self.Title:GetFont(), 30);

	MythicPlus_RegisterCallback(function(event, info)
		if event == "COMPLETE" and type(info) == "table" and info.level > 0 then
			ChallengeModeCompleteBanner_PlayBanner(self, info);
		end
	end);
end

local function SetUpPartyMember(frame, unit)
	SetPortraitTexture(frame.Portrait, unit);
	local name = UnitName(unit);
	local _, class = UnitClass(unit);
	local color = class and RAID_CLASS_COLORS[class];
	if color then
		frame.Name:SetText(("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name or ""));
	else
		frame.Name:SetText(name or "");
	end
	frame:SetAlpha(0);
	frame:Show();
end

-- retail CreateAndPositionPartyMembers: a row centered under the title
local function PositionPartyMembers(self, units)
	local frameWidth, spacing, distance = 61, 22, -131;
	local num = #units;
	for i = 1, num do
		local frame = self.PartyMembers[i];
		if not frame then
			frame = CreateFrame("Frame", self:GetName() .. "PartyMember" .. i, self, "ChallengeModeBannerPartyMemberTemplate");
			self.PartyMembers[i] = frame;
		end
		frame:ClearAllPoints();
		local fullWidth = frameWidth * num + spacing * (num - 1);
		frame:SetPoint("TOPLEFT", self.Title, "TOP", -fullWidth / 2 + (i - 1) * (frameWidth + spacing), distance);
		SetUpPartyMember(frame, units[i]);
	end
	for i = num + 1, #self.PartyMembers do
		self.PartyMembers[i]:Hide();
	end
end

function ChallengeModeCompleteBanner_PlayBanner(self, info)
	local name = info.name;
	if name == "" then
		name = C_ChallengeMode.GetMapUIInfo(info.mapChallengeModeID) or "";
	end
	self.Title:SetText(name);
	self.Level:SetText(info.level);

	if info.onTime then
		self.DescriptionLineOne:SetText(CHALLENGE_MODE_COMPLETE_BEAT_TIMER);
		self.DescriptionLineTwo:SetFormattedText(CHALLENGE_MODE_COMPLETE_KEYSTONE_UPGRADED, info.keystoneUpgradeLevels);
		PlaySound("LevelUp");
	else
		self.DescriptionLineOne:SetText(CHALLENGE_MODE_COMPLETE_TIME_EXPIRED);
		self.DescriptionLineTwo:SetText(CHALLENGE_MODE_COMPLETE_TRY_AGAIN);
		PlaySound("igQuestFailed");
	end

	local gained = info.newOverallDungeonScore - info.oldOverallDungeonScore;
	self.DescriptionLineThree:SetText(CHALLENGE_COMPLETE_DUNGEON_SCORE:format(
		CHALLENGE_COMPLETE_DUNGEON_SCORE_FORMAT_TEXT:format(info.newOverallDungeonScore, gained)));

	local units = {};
	for _, unit in ipairs(UNIT_TOKENS) do
		if UnitExists(unit) then
			table.insert(units, unit);
		end
	end

	self:SetAlpha(1);
	self:Show();
	PositionPartyMembers(self, units);
	self.elapsed = 0;
end

function ChallengeModeCompleteBanner_OnUpdate(self, elapsed)
	if not self.elapsed then
		return;
	end
	self.elapsed = self.elapsed + elapsed;
	local t = self.elapsed;

	for _, step in ipairs(ANIM_IN) do
		local region = self[step[1]];
		local startAt, duration, from, to = step[2], step[3], step[4], step[5];
		if t >= startAt then
			region:SetAlpha(from + (to - from) * math.min(1, (t - startAt) / duration));
		end
	end

	-- the skull shrinks in (retail Scale 5 -> 1)
	local p = math.min(1, t / SKULL_SCALE_TIME);
	local size = 100 * (5 - 4 * p);
	self.SkullCircle:SetWidth(size);
	self.SkullCircle:SetHeight(size);

	-- party members (retail ChallengeModeBannerPartyMember AnimIn: 0.2 delay, 0.25)
	local memberAlpha = math.max(0, math.min(1, (t - 0.55) / 0.25));
	for _, frame in ipairs(self.PartyMembers) do
		if frame:IsShown() then
			frame:SetAlpha(memberAlpha);
		end
	end

	-- AnimOut after the hold
	if t > TIME_TO_HOLD then
		local out = (t - TIME_TO_HOLD) / FADE_OUT;
		if out >= 1 then
			ChallengeModeCompleteBanner_Stop(self);
		else
			self:SetAlpha(1 - out);
		end
	end
end

function ChallengeModeCompleteBanner_Stop(self)
	self.elapsed = nil;
	self:Hide();
	self:SetAlpha(1);
	for _, step in ipairs(ANIM_IN) do
		self[step[1]]:SetAlpha(0);
	end
end

function ChallengeModeCompleteBanner_OnMouseDown(self, button)
	if button == "RightButton" then
		ChallengeModeCompleteBanner_Stop(self);
	end
end
