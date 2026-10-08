-- ============================================================
--  The guild news (retail GuildNews, Cataclysm's GuildNewsLog) on server/guild_news.cpp.
--  API: GetNumGuildNews(), GetGuildNewsInfo(i) -> { newsType, secondsAgo, whoText, value, text } (the filters
--  applied), SetGuildNewsFilter(type, on), GetGuildNewsFilters().
--  Types: 0 guild achievement, 1 member achievement, 2 boss, 3 epic looted, 4 epic crafted, 5 epic purchased,
--  6 guild level up; legendaries looted - a filter of their own (as retail).
-- ============================================================

NEWS_GUILD_ACHIEVEMENT, NEWS_PLAYER_ACHIEVEMENT, NEWS_DUNGEON_ENCOUNTER, NEWS_ITEM_LOOTED, NEWS_ITEM_CRAFTED,
	NEWS_ITEM_PURCHASED, NEWS_GUILD_LEVEL = 0, 1, 2, 3, 4, 5, 6;
local NEWS_LEGENDARY = 7;		-- a filter only

-- retail's Guild News Filters (the order there)
GUILD_NEWS_FILTERS = {
	{ type = NEWS_GUILD_ACHIEVEMENT, text = "Достижения гильдии" },
	{ type = NEWS_PLAYER_ACHIEVEMENT, text = "Достижения участников" },
	{ type = NEWS_DUNGEON_ENCOUNTER, text = "Рейдовые боссы" },
	{ type = NEWS_ITEM_LOOTED, text = "Эпические трофеи" },
	{ type = NEWS_ITEM_CRAFTED, text = "Эпические изделия" },
	{ type = NEWS_ITEM_PURCHASED, text = "Купленные эпики" },
	{ type = NEWS_LEGENDARY, text = "Легендарные трофеи" },
};

local news = {};			-- all, the newest first
local filtered = {};
local hidden = {};			-- [type] = true: filtered out

local function Decode(text)
	return (tostring(text or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)); end));
end

local function FilterType(entry)
	if ( entry.newsType == NEWS_ITEM_LOOTED ) then
		local _, _, quality = GetItemInfo(entry.value);
		if ( quality and quality >= 5 ) then
			return NEWS_LEGENDARY;
		end
	end
	return entry.newsType;
end

local function Refilter()
	wipe(filtered);
	for _, entry in ipairs(news) do
		if ( entry.newsType == NEWS_GUILD_LEVEL or not hidden[FilterType(entry)] ) then
			tinsert(filtered, entry);
		end
	end
end

function GetNumGuildNews()
	return #filtered;
end

function GetGuildNewsInfo(index)
	return filtered[index];
end

function SetGuildNewsFilter(newsType, on)
	hidden[newsType] = not on or nil;
	Refilter();
	if ( CommunitiesFrame and CommunitiesFrame.Info:IsShown() ) then
		GuildUIInfo_UpdateLog();
	end
end

function GetGuildNewsFilters()
	return hidden;
end

-- a news line's text (retail GuildNewsButton_SetText)
function GuildNews_GetText(entry)
	local who = entry.whoText ~= "" and ("|cffffffff"..entry.whoText.."|r") or "";
	local itemLink;
	if ( entry.newsType >= NEWS_ITEM_LOOTED and entry.newsType <= NEWS_ITEM_PURCHASED ) then
		local _, link = GetItemInfo(entry.value);
		itemLink = link or ("|cffa335ee["..entry.text.."]|r");
	end
	if ( entry.newsType == NEWS_DUNGEON_ENCOUNTER ) then
		return format("Гильдия победила: |cffffd200%s|r", entry.text);
	elseif ( entry.newsType == NEWS_ITEM_LOOTED ) then
		return format("%s получает %s", who, itemLink);
	elseif ( entry.newsType == NEWS_ITEM_CRAFTED ) then
		return format("%s создаёт %s", who, itemLink);
	elseif ( entry.newsType == NEWS_ITEM_PURCHASED ) then
		return format("%s покупает %s", who, itemLink);
	elseif ( entry.newsType == NEWS_GUILD_LEVEL ) then
		return format("|cff40c040Гильдия достигла %d-го уровня!|r", entry.value);
	elseif ( entry.newsType == NEWS_PLAYER_ACHIEVEMENT ) then
		return format("%s получает достижение %s", who, entry.text);
	elseif ( entry.newsType == NEWS_GUILD_ACHIEVEMENT ) then
		return format("Гильдия получает достижение %s", entry.text);
	end
	return entry.text;
end

-- ------------------------------------------------------------ the filters window

function GuildNewsFilters_OnLoad(self)
	GuildUIPopup_OnLoad(self);
	for i, filter in ipairs(GUILD_NEWS_FILTERS) do
		local check = CreateFrame("CheckButton", "GuildUINewsFilter"..i, self, "UICheckButtonTemplate");
		check:SetSize(24, 24);
		check:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 24);
		_G[check:GetName().."Text"]:SetText(filter.text);
		_G[check:GetName().."Text"]:SetFontObject("GameFontHighlight");
		check.newsType = filter.type;
		check:SetScript("OnClick", function(button)
			SetGuildNewsFilter(button.newsType, button:GetChecked() and true or false);
		end);
	end
end

function GuildNewsFilters_OnShow(self)
	for i, filter in ipairs(GUILD_NEWS_FILTERS) do
		_G["GuildUINewsFilter"..i]:SetChecked(not hidden[filter.type]);
	end
end

function GuildNewsFilters_Toggle()
	if ( GuildUINewsFiltersFrame:IsShown() ) then
		GuildUINewsFiltersFrame:Hide();
	else
		GuildUILogFrame:Hide();
		GuildUITextEditFrame:Hide();
		GuildUINewsFiltersFrame:Show();
	end
end

-- ------------------------------------------------------------ server messages

function GuildNews_Request()
	if ( Comm_Send and IsInGuild() ) then
		Comm_Send("GUILD_NEWS_GET");
	end
end

local function OnNews(list)
	wipe(news);
	if ( list and list ~= "-" ) then
		for entry in list:gmatch("[^,]+") do
			local newsType, ago, who, value, text = strsplit(";", entry);
			tinsert(news, { newsType = tonumber(newsType) or 0, secondsAgo = tonumber(ago) or 0, whoText = Decode(who),
				value = tonumber(value) or 0, text = Decode(text), received = time() });
		end
	end
	Refilter();
	if ( CommunitiesFrame and CommunitiesFrame.Info:IsShown() ) then
		GuildUIInfo_UpdateLog();
	end
end

local registered = false;
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:SetScript("OnEvent", function(self)
	if ( registered or not Comm_Register ) then
		return;
	end
	Comm_Register("GUILD_NEWS", OnNews);
	Comm_Register("GUILD_NEWS_NEW", function()
		if ( CommunitiesFrame and CommunitiesFrame:IsShown() ) then
			GuildNews_Request();
		end
	end);
	registered = true;
	self:UnregisterAllEvents();
end);
