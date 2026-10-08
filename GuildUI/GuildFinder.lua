-- ============================================================
--  The guild finder (retail ClubFinder, Cataclysm's LookingForGuild) on server/guild_finder.cpp.
--  No guild: the filters, the found guilds (apply), my applications (cancel).
--  In a guild: the guild's recruitment settings (officers edit) and its applicants (invite / decline).
--  Flags: availability 1 weekdays 2 weekends; roles 1 tank 2 healer 4 damage;
--  interests 1 questing 2 dungeons 4 raids 8 pvp 16 role playing; level 1 any 2 max.
-- ============================================================

local FINDER_ROW_HEIGHT = 44;

local MODE_SEARCH, MODE_APPS, MODE_REQUESTS = 1, 2, 3;
local mode = MODE_SEARCH;

local results, apps, requests = {}, {}, {};
local settings = { canEdit = false, listed = false, availability = 0, roles = 0, interests = 0, level = 1, comment = "" };
local searched = false;

local CHECKS = { "Weekdays", "Weekends", "Tank", "Healer", "Damage", "Questing", "Dungeons", "Raids", "PvP", "RP", "AnyLevel", "MaxLevel" };

local CLASS_FILES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", nil, "DRUID" };

local INTEREST_NAMES = { [1] = "задания", [2] = "подземелья", [4] = "рейды", [8] = "PvP", [16] = "отыгрыш" };
local ROLE_NAMES = { [1] = "танк", [2] = "лекарь", [4] = "боец" };

-- ------------------------------------------------------------ text

local function Encode(text)
	return (tostring(text or ""):gsub("[%%:,;%./|%c]", function(c) return string.format("%%%02X", c:byte()); end));
end

local function Decode(text)
	if ( not text ) then
		return "";
	end
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)); end));
end

-- "a;b;c,d;e;f" -> { {a,b,c}, {d,e,f} } ("-": empty)
local function Split(list)
	local out = {};
	if ( not list or list == "" or list == "-" ) then
		return out;
	end
	for entry in list:gmatch("[^,]+") do
		local fields = {};
		for field in (entry..";"):gmatch("([^;]*);") do
			tinsert(fields, field);
		end
		tinsert(out, fields);
	end
	return out;
end

local function FlagNames(flags, names)
	local out = {};
	for _, bit in ipairs({ 1, 2, 4, 8, 16 }) do
		if ( names[bit] and flags % (bit * 2) >= bit ) then
			tinsert(out, names[bit]);
		end
	end
	return table.concat(out, ", ");
end

local function TimeLeft(seconds)
	seconds = tonumber(seconds) or 0;
	if ( seconds >= 86400 ) then
		return format("%d дн.", math.floor(seconds / 86400));
	end
	return format("%d ч.", math.floor(seconds / 3600));
end

local function Send(...)
	if ( Comm_Send ) then
		Comm_Send(...);
	end
end

-- ------------------------------------------------------------ the filter boxes

local function Finder()
	return CommunitiesFrame.Finder;
end

-- the ticked flags of a field ("availability", "roles", "interests", "level")
local function GetFlags(field)
	local flags = 0;
	for _, key in ipairs(CHECKS) do
		local check = Finder()[key];
		if ( check.field == field and check:GetChecked() ) then
			flags = flags + check:GetID();
		end
	end
	return flags;
end

local function SetFlags(field, flags)
	for _, key in ipairs(CHECKS) do
		local check = Finder()[key];
		if ( check.field == field ) then
			check:SetChecked(flags % (check:GetID() * 2) >= check:GetID());
		end
	end
end

local function EnableChecks(enable)
	local finder = Finder();
	for _, key in ipairs(CHECKS) do
		if ( enable ) then
			finder[key]:Enable();
		else
			finder[key]:Disable();
		end
	end
	if ( enable ) then
		finder.Listed:Enable();
		finder.Comment:EnableMouse(true);
	else
		finder.Listed:Disable();
		finder.Comment:EnableMouse(false);
		finder.Comment:ClearFocus();
	end
end

-- ------------------------------------------------------------ the list

local function SetupRow(row)
	row.Button1:SetScript("OnClick", function(self) GuildFinderRow_OnButton(self:GetParent(), 1); end);
	row.Button2:SetScript("OnClick", function(self) GuildFinderRow_OnButton(self:GetParent(), 2); end);
end

local function Init()
	local finder = Finder();
	if ( finder.List.rows ) then
		return;
	end
	GuildUI_MakeList(finder.List, "GuildUIFinderRowTemplate", FINDER_ROW_HEIGHT, 8, GuildFinder_UpdateList, SetupRow);
	for _, key in ipairs(CHECKS) do
		local check = finder[key];
		_G[check:GetName().."Text"]:SetText(check.label);
	end
	_G[finder.Listed:GetName().."Text"]:SetText("Гильдия ищет игроков");
	-- a new player: what he plays (all ticked)
	for _, field in ipairs({ "availability", "roles", "interests" }) do
		SetFlags(field, 31);
	end
	SetFlags("level", 3);
end

function GuildFinder_UpdateList()
	local finder = Finder();
	local list = finder.List;
	if ( not list.rows ) then
		return;
	end
	local data = mode == MODE_SEARCH and results or mode == MODE_APPS and apps or requests;
	local offset = FauxScrollFrame_GetOffset(list);
	for i, row in ipairs(list.rows) do
		local entry = data[offset + i];
		row.entry = entry;
		if ( entry ) then
			if ( mode == MODE_SEARCH ) then
				row.Icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01");
				row.Icon:SetTexCoord(0, 1, 0, 1);
				row.Name:SetText(entry.name);
				row.Info:SetText(entry.comment ~= "" and entry.comment or ("Интересы: "..FlagNames(entry.interests, INTEREST_NAMES)));
				row.Right:SetFormattedText("Ур. %d  |cffffffff%d чел.|r", entry.level, entry.members);
				row.Button1:Hide();
				row.Button2:SetText(entry.applied and "Отозвать" or "Подать заявку");
				row.Button2:Show();
			elseif ( mode == MODE_APPS ) then
				row.Icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01");
				row.Icon:SetTexCoord(0, 1, 0, 1);
				row.Name:SetText(entry.name);
				row.Info:SetText(entry.comment ~= "" and entry.comment or "Без комментария");
				row.Right:SetText("Осталось: "..TimeLeft(entry.secondsLeft));
				row.Button1:Hide();
				row.Button2:SetText("Отозвать");
				row.Button2:Show();
			else
				row.Icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes");
				local coords = entry.classFile and CLASS_ICON_TCOORDS[entry.classFile];
				if ( coords ) then
					row.Icon:SetTexCoord(unpack(coords));
				end
				local color = entry.classFile and RAID_CLASS_COLORS[entry.classFile];
				row.Name:SetText(entry.name);
				if ( color ) then
					row.Name:SetTextColor(color.r, color.g, color.b);
				end
				row.Info:SetText(entry.comment ~= "" and entry.comment or ("Роли: "..FlagNames(entry.roles, ROLE_NAMES)));
				row.Right:SetFormattedText("Ур. %d  |cffffffff%s|r", entry.level, TimeLeft(entry.secondsLeft));
				row.Button1:SetText("Пригласить");
				row.Button1:Show();
				row.Button2:SetText("Отклонить");
				row.Button2:Show();
			end
			if ( mode ~= MODE_REQUESTS ) then
				row.Name:SetTextColor(1, 0.82, 0);
			end
			row:Show();
		else
			row:Hide();
		end
	end
	FauxScrollFrame_Update(list, #data, #list.rows, list.rowHeight);

	if ( #data == 0 ) then
		if ( mode == MODE_SEARCH ) then
			finder.Empty:SetText(searched and "Подходящих гильдий не найдено." or "Отметьте свои интересы и нажмите «Найти».");
		elseif ( mode == MODE_APPS ) then
			finder.Empty:SetText("У вас нет заявок.");
		elseif ( GuildFinder_CanInvite() ) then
			finder.Empty:SetText("Заявок в гильдию нет.");
		else
			finder.Empty:SetText("Заявки видят те, кто может приглашать в гильдию.");
		end
		finder.Empty:Show();
	else
		finder.Empty:Hide();
	end
end

function GuildFinder_CanInvite()
	return IsInGuild() and CanGuildInvite();
end

function GuildFinderRow_OnButton(row, button)
	local entry = row.entry;
	if ( not entry ) then
		return;
	end
	if ( mode == MODE_SEARCH ) then
		if ( entry.applied ) then
			Send("GF_CANCEL", entry.guildId);
			entry.applied = false;
			GuildFinder_UpdateList();
		else
			StaticPopup_Show("GUILDFINDER_APPLY", entry.name, nil, entry);
		end
	elseif ( mode == MODE_APPS ) then
		Send("GF_CANCEL", entry.guildId);
	elseif ( button == 1 ) then
		GuildInvite(entry.name);
	else
		Send("GF_DECLINE", entry.guid);
	end
end

function GuildFinderRow_OnEnter(self)
	local entry = self.entry;
	if ( not entry ) then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(entry.name, 1, 0.82, 0);
	if ( entry.members ) then
		GameTooltip:AddLine(format("Уровень гильдии %d, участников: %d", entry.level, entry.members), 1, 1, 1);
	elseif ( entry.class ) then
		GameTooltip:AddLine(format("%s %d %s", LEVEL, entry.level, entry.class), 1, 1, 1);
	end
	if ( entry.availability ) then
		local times = {};
		if ( entry.availability % 2 == 1 ) then tinsert(times, "будни"); end
		if ( entry.availability >= 2 ) then tinsert(times, "выходные"); end
		GameTooltip:AddLine("Время игры: "..table.concat(times, ", "), 1, 1, 1);
		GameTooltip:AddLine("Роли: "..FlagNames(entry.roles, ROLE_NAMES), 1, 1, 1);
		GameTooltip:AddLine("Интересы: "..FlagNames(entry.interests, INTEREST_NAMES), 1, 1, 1);
	end
	if ( entry.comment and entry.comment ~= "" ) then
		GameTooltip:AddLine(entry.comment, 1, 0.82, 0, true);
	end
	GameTooltip:Show();
end

StaticPopupDialogs["GUILDFINDER_APPLY"] = {
	text = "Заявка в гильдию «%s».\nКомментарий:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 200,
	OnShow = function(self)
		self.editBox:SetText("");
		self.editBox:SetFocus();
	end,
	OnAccept = function(self, data)
		GuildFinder_Apply(data, self.editBox:GetText());
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent();
		GuildFinder_Apply(parent.data, self:GetText());
		parent:Hide();
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

function GuildFinder_Apply(entry, comment)
	Send("GF_APPLY", entry.guildId, GetFlags("availability"), GetFlags("roles"), GetFlags("interests"), Encode(comment));
	entry.applied = true;
	GuildFinder_UpdateList();
end

-- ------------------------------------------------------------ the tab

function GuildFinder_Show()
	Init();
	local finder = Finder();
	if ( IsInGuild() ) then
		mode = MODE_REQUESTS;
		finder.FilterTitle:SetText("Набор в гильдию");
		finder.ListTitle:SetText("Заявки в гильдию");
		finder.Listed:Show();
		finder.Comment:Show();
		finder.Action:SetText("Сохранить");
		finder.Mode:Hide();
		GuildFinder_ApplySettings();
		Send("GF_SETTINGS_GET");
		Send("GF_REQUESTS");
	else
		if ( mode == MODE_REQUESTS ) then
			mode = MODE_SEARCH;
		end
		finder.FilterTitle:SetText("Что вы ищете");
		finder.Listed:Hide();
		finder.Comment:Hide();
		finder.Action:SetText("Найти");
		finder.Action:Enable();
		finder.Mode:Show();
		EnableChecks(true);
		GuildFinder_UpdateMode();
		Send("GF_MYAPPS");
		if ( mode == MODE_SEARCH ) then
			GuildFinder_Search();
		end
	end
	GuildFinder_UpdateList();
end

function GuildFinder_UpdateMode()
	local finder = Finder();
	if ( mode == MODE_SEARCH ) then
		finder.ListTitle:SetText("Найденные гильдии");
		finder.Mode:SetFormattedText("Мои заявки (%d)", #apps);
	else
		finder.ListTitle:SetText("Мои заявки");
		finder.Mode:SetText("Найденные гильдии");
	end
end

function GuildFinder_ToggleMode()
	mode = mode == MODE_SEARCH and MODE_APPS or MODE_SEARCH;
	FauxScrollFrame_SetOffset(Finder().List, 0);
	GuildFinder_UpdateMode();
	GuildFinder_UpdateList();
end

function GuildFinder_Search()
	searched = true;
	Send("GF_SEARCH", GetFlags("availability"), GetFlags("roles"), GetFlags("interests"), GetFlags("level"));
end

-- the button under the filters: search / save the settings
function GuildFinder_Action()
	local finder = Finder();
	if ( IsInGuild() ) then
		Send("GF_SETTINGS_SET", finder.Listed:GetChecked() and 1 or 0, GetFlags("availability"), GetFlags("roles"),
			GetFlags("interests"), GetFlags("level"), Encode(finder.Comment:GetText()));
	else
		if ( mode ~= MODE_SEARCH ) then
			GuildFinder_ToggleMode();
		end
		GuildFinder_Search();
	end
end

function GuildFinder_ApplySettings()
	local finder = Finder();
	SetFlags("availability", settings.availability);
	SetFlags("roles", settings.roles);
	SetFlags("interests", settings.interests);
	SetFlags("level", settings.level);
	finder.Listed:SetChecked(settings.listed);
	finder.Comment:SetText(settings.comment);
	EnableChecks(settings.canEdit);
	if ( settings.canEdit ) then
		finder.Action:Enable();
	else
		finder.Action:Disable();
	end
end

local function Visible()
	return CommunitiesFrame and CommunitiesFrame.Finder:IsShown();
end

-- ------------------------------------------------------------ server messages

local function OnResults(list)
	wipe(results);
	for _, f in ipairs(Split(list)) do
		tinsert(results, { guildId = tonumber(f[1]), name = Decode(f[2]), level = tonumber(f[3]) or 0, members = tonumber(f[4]) or 0,
			comment = Decode(f[5]), availability = tonumber(f[6]) or 0, roles = tonumber(f[7]) or 0, interests = tonumber(f[8]) or 0,
			levelFlags = tonumber(f[9]) or 0, applied = f[10] == "1" });
	end
	if ( Visible() ) then
		GuildFinder_UpdateList();
	end
end

local function OnApps(list)
	wipe(apps);
	for _, f in ipairs(Split(list)) do
		tinsert(apps, { guildId = tonumber(f[1]), name = Decode(f[2]), comment = Decode(f[3]), secondsLeft = tonumber(f[4]) or 0 });
	end
	-- the found guilds' "applied" follow
	for _, result in ipairs(results) do
		result.applied = false;
		for _, app in ipairs(apps) do
			if ( app.guildId == result.guildId ) then
				result.applied = true;
			end
		end
	end
	if ( Visible() and not IsInGuild() ) then
		GuildFinder_UpdateMode();
		GuildFinder_UpdateList();
	end
end

local function OnSettings(canEdit, listed, availability, roles, interests, level, comment)
	settings.canEdit = canEdit == "1";
	settings.listed = listed == "1";
	settings.availability = tonumber(availability) or 0;
	settings.roles = tonumber(roles) or 0;
	settings.interests = tonumber(interests) or 0;
	settings.level = tonumber(level) or 1;
	settings.comment = Decode(comment);
	if ( Visible() and IsInGuild() ) then
		GuildFinder_ApplySettings();
	end
end

local function OnRequests(list)
	wipe(requests);
	for _, f in ipairs(Split(list)) do
		local classFile = CLASS_FILES[tonumber(f[3]) or 0];
		tinsert(requests, { guid = tonumber(f[1]), name = Decode(f[2]), classFile = classFile,
			class = classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or "",
			level = tonumber(f[4]) or 0, availability = tonumber(f[5]) or 0, roles = tonumber(f[6]) or 0,
			interests = tonumber(f[7]) or 0, comment = Decode(f[8]), secondsLeft = tonumber(f[9]) or 0 });
	end
	if ( Visible() and IsInGuild() ) then
		GuildFinder_UpdateList();
	end
end

local function OnResult(text)
	DEFAULT_CHAT_FRAME:AddMessage(Decode(text), 1, 1, 0);
end

local function OnNewRequest()
	if ( Visible() and IsInGuild() ) then
		Send("GF_REQUESTS");
	end
end

-- Server.lua may load after this file: registered at login
local registered = false;
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:SetScript("OnEvent", function(self)
	if ( registered or not Comm_Register ) then
		return;
	end
	Comm_Register("GF_RESULTS", OnResults);
	Comm_Register("GF_APPS", OnApps);
	Comm_Register("GF_SETTINGS", OnSettings);
	Comm_Register("GF_REQUESTS", OnRequests);
	Comm_Register("GF_RESULT", OnResult);
	Comm_Register("GF_NEW_REQUEST", OnNewRequest);
	registered = true;
	self:UnregisterAllEvents();
end);
