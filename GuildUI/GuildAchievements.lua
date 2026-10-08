-- ============================================================
--  Guild challenges and guild achievements (server/guild_achievements.cpp).
--  API: GetGuildChallengeInfo(i) -> type, done, count, xp, gold (Cataclysm's: index, current, max, xp, gold);
--       GetNumGuildAchievements(), GetGuildAchievementInfo(i) -> id, name, description, points, done, secondsAgo,
--       progress, needed, icon;  GetGuildAchievementPoints();  GetGuildAchievementByID(id) -> the same.
--  Callback: GuildAchievements_RegisterCallback(func): func("GUILD_CHALLENGES_UPDATE") / ("GUILD_ACHIEVEMENTS_UPDATE").
-- ============================================================

local ACH_ROW_HEIGHT = 46;

local challenges = {};		-- [type] = { done, count, xp, gold }
local achievements = {};	-- the list, the server's order
local byId = {};
local points = 0;
local received;
local callbacks = {};

local function Decode(text)
	return (tostring(text or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)); end));
end

local function Fire(event)
	for _, func in ipairs(callbacks) do
		func(event);
	end
end

function GuildAchievements_RegisterCallback(func)
	tinsert(callbacks, func);
end

function GetGuildChallengeInfo(challengeType)
	local c = challenges[challengeType];
	if ( not c ) then
		return challengeType, 0, 0, 0, 0;
	end
	return challengeType, c.done, c.count, c.xp, c.gold;
end

function GetNumGuildAchievements()
	return #achievements;
end

local function Info(a)
	if ( not a ) then
		return;
	end
	return a.id, a.name, a.description, a.points, a.done, a.secondsAgo + (received and (time() - received) or 0), a.progress, a.needed, a.icon;
end

function GetGuildAchievementInfo(index)
	return Info(achievements[index]);
end

function GetGuildAchievementByID(id)
	return Info(byId[id]);
end

function GetGuildAchievementPoints()
	return points;
end

function GuildAchievements_Request()
	if ( Comm_Send and IsInGuild() ) then
		Comm_Send("GUILD_CHALLENGES_GET");
		Comm_Send("GUILD_ACH_GET");
	end
end

-- ------------------------------------------------------------ the achievements window

local function TimeAgo(seconds)
	local days = floor(seconds / 86400);
	if ( days > 0 ) then
		return format("%d дн. назад", days);
	end
	local hours = floor(seconds / 3600);
	if ( hours > 0 ) then
		return format("%d ч. назад", hours);
	end
	return "только что";
end

function GuildAchievementsFrame_OnLoad(self)
	GuildUIPopup_OnLoad(self);
	GuildUI_MakeList(GuildUIAchievementsFrameList, "GuildUIAchievementRowTemplate", ACH_ROW_HEIGHT, 8, GuildAchievementsFrame_Update);
end

function GuildAchievementsFrame_Toggle()
	if ( GuildUIAchievementsFrame:IsShown() ) then
		GuildUIAchievementsFrame:Hide();
	else
		GuildUILogFrame:Hide();
		GuildUITextEditFrame:Hide();
		GuildUINewsFiltersFrame:Hide();
		GuildUIAchievementsFrame:Show();
		GuildAchievements_Request();
	end
end

function GuildAchievementsFrame_Update()
	local list = GuildUIAchievementsFrameList;
	if ( not list.rows or not GuildUIAchievementsFrame:IsShown() ) then
		return;
	end
	local done = 0;
	for _, a in ipairs(achievements) do
		if ( a.done ) then
			done = done + 1;
		end
	end
	GuildUIAchievementsFrameSummary:SetFormattedText("Получено: %d из %d   |cffffffffОчки: %d|r", done, #achievements, points);
	local offset = FauxScrollFrame_GetOffset(list);
	for i, row in ipairs(list.rows) do
		local id, name, description, value, isDone, ago, progress, needed, icon = GetGuildAchievementInfo(offset + i);
		if ( id ) then
			row.Icon:SetTexture(icon ~= "" and icon or "Interface\\Icons\\INV_Misc_QuestionMark");
			row.Icon:SetDesaturated(not isDone);
			row.Name:SetText(name);
			row.Name:SetTextColor(isDone and 1 or 0.6, isDone and 0.82 or 0.6, isDone and 0 or 0.6);
			row.Desc:SetText(description);
			row.Points:SetText(value);
			if ( isDone ) then
				row.Status:SetText("|cff40c040"..TimeAgo(ago).."|r");
			else
				row.Status:SetFormattedText("%d / %d", progress, needed);
			end
			row:Show();
		else
			row:Hide();
		end
	end
	FauxScrollFrame_Update(list, #achievements, #list.rows, list.rowHeight);
end

-- ------------------------------------------------------------ server messages

local function OnChallenges(list)
	wipe(challenges);
	for entry in (list or ""):gmatch("[^,]+") do
		local t, done, count, xp, gold = strsplit(";", entry);
		challenges[tonumber(t) or 0] = { done = tonumber(done) or 0, count = tonumber(count) or 0, xp = tonumber(xp) or 0, gold = tonumber(gold) or 0 };
	end
	Fire("GUILD_CHALLENGES_UPDATE");
end

local function OnAchievements(total, list)
	points = tonumber(total) or 0;
	wipe(achievements);
	wipe(byId);
	received = time();
	if ( list and list ~= "-" ) then
		for entry in list:gmatch("[^,]+") do
			local id, value, done, ago, progress, needed, name, description, icon = strsplit(";", entry);
			local a = { id = tonumber(id) or 0, points = tonumber(value) or 0, done = done == "1", secondsAgo = tonumber(ago) or 0,
				progress = tonumber(progress) or 0, needed = tonumber(needed) or 1, name = Decode(name), description = Decode(description),
				icon = Decode(icon) };
			tinsert(achievements, a);
			byId[a.id] = a;
		end
	end
	GuildAchievementsFrame_Update();
	Fire("GUILD_ACHIEVEMENTS_UPDATE");
end

local registered = false;
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:RegisterEvent("PLAYER_GUILD_UPDATE");
loader:SetScript("OnEvent", function(self)
	if ( not Comm_Register ) then
		return;
	end
	if ( not registered ) then
		Comm_Register("GUILD_CHALLENGES", OnChallenges);
		Comm_Register("GUILD_ACH", OnAchievements);
		Comm_Register("GUILD_ACH_NEW", GuildAchievements_Request);
		registered = true;
	end
	GuildAchievements_Request();
end);
