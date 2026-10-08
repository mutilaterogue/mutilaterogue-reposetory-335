-- ============================================================
--  The guild window (retail 12.1.5 Blizzard_Communities) for 3.3.5a: CommunitiesFrame.
--  The left list: the guild, the guild finder. The side tabs (the guild): roster, benefits (perks), info
--  (MOTD, details, event log). The bottom bar: invite, recruitment (GuildFinder.lua), guild control.
--  The level, experience and perks come from GuildProgression.lua.
--  Without a guild the window shows the guild finder only.
-- ============================================================

local VIEW_ROSTER, VIEW_PERKS, VIEW_INFO, VIEW_FINDER = 1, 2, 3, 4;

-- the side tabs (retail order: roster, benefits, info) and the views they show
local TABS = {
	{ name = "Состав", icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", fallback = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ name = "Преимущества гильдии", icon = "Interface\\Icons\\Achievement_GuildPerk_HonorableMention", fallback = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
	{ name = "Информация о гильдии", icon = "Interface\\Icons\\INV_Misc_ScrollUnrolled01", fallback = "Interface\\Icons\\INV_Misc_Note_01" },
};
local VIEW_FRAMES = { "Roster", "Perks", "Info", "Finder" };

local ROSTER_ROW_HEIGHT, PERK_ROW_HEIGHT = 20, 50;

local selectedView = VIEW_ROSTER;
local lastGuildView = VIEW_ROSTER;		-- the guild entry opens the last tab
local members = {};			-- the filtered, sorted roster
local selectedName;
local sortType, sortReverse = "rank", false;
local oldShowOffline;

-- ------------------------------------------------------------ helpers

local function ClassColor(classFile)
	local color = classFile and RAID_CLASS_COLORS[classFile];
	if ( color ) then
		return color.r, color.g, color.b;
	end
	return 1, 1, 1;
end

local function SetClassIcon(texture, classFile)
	local coords = classFile and CLASS_ICON_TCOORDS[classFile];
	if ( coords ) then
		texture:SetTexCoord(unpack(coords));
		texture:Show();
	else
		texture:Hide();
	end
end

-- a list of rows from a template over a FauxScrollFrame (rows named <list>Row<index>)
function GuildUI_MakeList(list, template, rowHeight, count, update, setup)
	list.rowHeight = rowHeight;
	list.update = update;
	list.rows = {};
	local parent = list:GetParent();
	for i = 1, count do
		local row = CreateFrame("Button", list:GetName().."Row"..i, parent, template);
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowHeight);
		row:SetPoint("RIGHT", list, "RIGHT", 0, 0);
		row:SetHeight(rowHeight - 2);
		if ( setup ) then
			setup(row, i);
		end
		list.rows[i] = row;
	end
	return list.rows;
end

-- ------------------------------------------------------------ the window

function GuildUI_OnLoad(self)
	self:RegisterEvent("PLAYER_GUILD_UPDATE");
	self:RegisterEvent("GUILD_ROSTER_UPDATE");
	self:RegisterEvent("GUILD_MOTD");
	self:RegisterEvent("GUILD_EVENT_LOG_UPDATE");
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	UIPanelWindows["CommunitiesFrame"] = { area = "left", pushable = 1, whileDead = 1, xOffset = "15", yOffset = "-10" };

	SetPortraitToTexture(self.PortraitContainer.portrait, "Interface\\Icons\\INV_Shirt_GuildTabard_01");

	for i, info in ipairs(TABS) do
		local tab = _G["CommunitiesFrameTab"..i];
		tab.tooltip = info.name;
		tab.Icon:SetTexture(info.icon);
		if ( not tab.Icon:GetTexture() ) then
			tab.Icon:SetTexture(info.fallback);
		end
	end

	-- the left list: the guild (its banner), the guild finder
	local guildEntry = self.List.Guild;
	guildEntry.Banner:Show();
	guildEntry.BannerBorder:Show();
	guildEntry.Icon:SetSize(26, 26);
	guildEntry.Icon:ClearAllPoints();
	guildEntry.Icon:SetPoint("CENTER", guildEntry.Banner, "CENTER", 0, 3);
	SetPortraitToTexture(guildEntry.Icon, "Interface\\Icons\\INV_Shirt_GuildTabard_01");
	local finderEntry = self.List.Finder;
	SetPortraitToTexture(finderEntry.Icon, "Interface\\Icons\\INV_Misc_Spyglass_03");
	finderEntry.Name:SetText("Поиск гильдии");
	finderEntry.Sub:SetText("Найти гильдию");

	-- the roster: column titles (retail order), rows, the last column's dropdown
	local roster = self.Roster;
	roster.ColumnLevel.Label:SetText("Ур.");
	roster.ColumnClass.Label:SetText("Класс");
	roster.ColumnName.Label:SetText("Имя");
	roster.ColumnZone.Label:SetText("Зона");
	roster.ColumnRank.Label:SetText("Звание");
	roster.ColumnNote.Label:SetText("Заметка");
	GuildUI_MakeList(roster.List, "GuildUIRosterRowTemplate", ROSTER_ROW_HEIGHT, 13, GuildUIRoster_Update, function(row, i)
		row.Level:SetPoint("LEFT", row, "LEFT", 8, 0);
		row.Level:SetWidth(30);
		row.Level:SetJustifyH("LEFT");
		row.Class:ClearAllPoints();
		row.Class:SetPoint("LEFT", row, "LEFT", 52, 0);
		row.Name:SetPoint("LEFT", row, "LEFT", 86, 0);
		row.Name:SetWidth(104);
		row.Zone:SetPoint("LEFT", row, "LEFT", 198, 0);
		row.Zone:SetWidth(102);
		row.Rank:SetPoint("LEFT", row, "LEFT", 308, 0);
		row.Rank:SetWidth(88);
		row.Note:SetPoint("LEFT", row, "LEFT", 402, 0);
		row.Note:SetWidth(88);
		row.Extra = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
		row.Extra:SetJustifyH("LEFT");
		row.Extra:SetPoint("LEFT", row, "LEFT", 496, 0);
		row.Extra:SetPoint("RIGHT", row, "RIGHT", -4, 0);
		row.Stripe:SetShown(i % 2 == 0);
	end);
	UIDropDownMenu_SetWidth(roster.ColumnDropDown, 130);
	UIDropDownMenu_Initialize(roster.ColumnDropDown, GuildUIRosterColumnDropDown_Initialize);
	GuildUIRoster_SetExtraColumn(CanViewOfficerNote() and "officer" or "online");

	-- the info: section titles, challenges, news rows
	local info = self.Info;
	info.Header1.Label:SetText("Испытания гильдии");
	info.Header2.Label:SetText("Сообщение дня");
	info.Header3.Label:SetText("Информация о гильдии");
	info.NewsHeader.Label:SetText("Новости гильдии");
	for i, challenge in ipairs(GUILD_CHALLENGES) do
		info["Challenge"..i].Label:SetText(challenge.name);
	end
	GuildUI_MakeList(info.News, "GuildUINewsRowTemplate", 18, 17, GuildUIInfo_UpdateLog);

	-- the guild entry's right click: leave / disband (retail: the guild's menu in the list)
	self.List.Guild:RegisterForClicks("LeftButtonUp", "RightButtonUp");

	-- the perks
	GuildUI_MakeList(self.Perks.List, "GuildUIPerkRowTemplate", PERK_ROW_HEIGHT, 6, GuildUIPerks_Update);

	-- the guild's emblem, challenges, achievements (GuildEmblem.lua, GuildAchievements.lua)
	GuildEmblem_RegisterCallback(GuildUI_UpdateHeader);
	GuildAchievements_RegisterCallback(function(event)
		if ( self.Info:IsShown() ) then
			GuildUIInfo_Update();
		end
		if ( self.Perks:IsShown() ) then
			GuildUIPerks_Update();
			GuildRewards_Update();
		end
	end);

	if ( GuildProgression_RegisterCallback ) then
		GuildProgression_RegisterCallback(function(event)
			GuildUI_UpdateHeader();
			if ( event == "GUILD_PERK_UPDATE" and self.Perks:IsShown() ) then
				GuildUIPerks_Update();
			end
		end);
	end

	-- the stock guild tab opens this window instead
	local ToggleFriendsFrameOld = ToggleFriendsFrame;
	function ToggleFriendsFrame(tab)
		if ( tab == 3 ) then
			ToggleGuildFrame();
		else
			ToggleFriendsFrameOld(tab);
		end
	end
	-- the Friends frame without its guild tab: the micro button "Guild" opens this window
	if ( FriendsFrameTab3 ) then
		FriendsFrameTab3:Hide();
		FriendsFrameTab3:SetScript("OnShow", FriendsFrameTab3.Hide);
		if ( FriendsFrameTab4 ) then
			FriendsFrameTab4:ClearAllPoints();
			FriendsFrameTab4:SetPoint("LEFT", FriendsFrameTab2, "RIGHT", -15, 0);
		end
	end

	SLASH_GUILDUI1 = "/guildui";
	SLASH_GUILDUI2 = "/gui";
	SlashCmdList["GUILDUI"] = ToggleGuildFrame;
end

function ToggleGuildFrame()
	if ( CommunitiesFrame:IsShown() ) then
		HideUIPanel(CommunitiesFrame);
	else
		ShowUIPanel(CommunitiesFrame);
	end
end
ToggleCommunitiesFrame = ToggleGuildFrame;

function GuildUI_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	-- the whole roster, the offline too: filtered here
	oldShowOffline = GetGuildRosterShowOffline();
	SetGuildRosterShowOffline(true);
	if ( IsInGuild() ) then
		GuildRoster();
		QueryGuildEventLog();
		GuildAchievements_Request();
	end
	GuildUI_Refresh();
	if ( UpdateMicroButtons ) then
		UpdateMicroButtons();
	end
end

function GuildUI_OnHide(self)
	PlaySound("igCharacterInfoClose");
	if ( oldShowOffline ~= nil ) then
		SetGuildRosterShowOffline(oldShowOffline);
	end
	if ( GuildControlPopupFrame and GuildControlPopupFrame.guildUI ) then
		GuildControlPopupFrame:Hide();
	end
	CloseDropDownMenus();
	if ( UpdateMicroButtons ) then
		UpdateMicroButtons();
	end
end

function GuildUI_OnEvent(self, event, ...)
	if ( event == "PLAYER_GUILD_UPDATE" or event == "PLAYER_ENTERING_WORLD" ) then
		if ( self:IsShown() ) then
			if ( IsInGuild() ) then
				GuildRoster();
			end
			GuildUI_Refresh();
		end
	elseif ( not self:IsShown() ) then
		return;
	elseif ( event == "GUILD_ROSTER_UPDATE" ) then
		local canRequestRosterUpdate = ...;
		if ( canRequestRosterUpdate ) then
			GuildRoster();
		end
		GuildUI_UpdateHeader();
		GuildUI_UpdateButtons();
		if ( self.Roster:IsShown() ) then
			GuildUIRoster_Update();
		end
		if ( self.Info:IsShown() ) then
			GuildUIInfo_Update();
		end
	elseif ( event == "GUILD_MOTD" ) then
		if ( self.Info:IsShown() ) then
			GuildUIInfo_Update();
		end
	elseif ( event == "GUILD_EVENT_LOG_UPDATE" ) then
		if ( GuildUILogFrame:IsShown() ) then
			GuildUILog_Update();
		end
	end
end

-- the list, the tabs for a guild member / the finder alone
function GuildUI_Refresh()
	local frame = CommunitiesFrame;
	local inGuild = IsInGuild();
	for i = 1, #TABS do
		_G["CommunitiesFrameTab"..i]:SetShown(inGuild);
	end
	frame.List.Guild:SetShown(inGuild);
	frame.List.Finder:ClearAllPoints();
	if ( inGuild ) then
		frame.List.Finder:SetPoint("TOPLEFT", frame.List.Guild, "BOTTOMLEFT", 0, -2);
	else
		frame.List.Finder:SetPoint("TOPLEFT", frame.List, "TOPLEFT", 2, -4);
		selectedView = VIEW_FINDER;
	end
	if ( inGuild and selectedView == VIEW_FINDER and not frame.recruiting and not frame.browsing ) then
		selectedView = lastGuildView;
	end
	GuildUI_SetView(selectedView);
	GuildUI_UpdateHeader();
	GuildUI_UpdateButtons();
end

function GuildUI_SetView(view)
	local frame = CommunitiesFrame;
	selectedView = view;
	if ( view ~= VIEW_FINDER ) then
		lastGuildView = view;
		frame.recruiting = nil;
		frame.browsing = nil;
	end
	for i = 1, #TABS do
		_G["CommunitiesFrameTab"..i]:SetChecked(i == view);
	end
	for i, key in ipairs(VIEW_FRAMES) do
		frame[key]:SetShown(i == view);
	end
	-- the content's border: the roster's only (the other views have their own insets)
	frame.Inset:SetShown(view == VIEW_ROSTER);
	frame.List.Guild.Selection:SetShown(view ~= VIEW_FINDER);
	frame.List.Finder.Selection:SetShown(view == VIEW_FINDER and not frame.recruiting);
	if ( view == VIEW_ROSTER ) then
		GuildUIRoster_Update();
	elseif ( view == VIEW_INFO ) then
		GuildUIInfo_Update();
		GuildNews_Request();
	elseif ( view == VIEW_PERKS ) then
		GuildUIPerks_Update();
		GuildRewards_Init();
		GuildRewards_Update();
		if ( Comm_Send ) then
			Comm_Send("GUILD_REWARDS_GET");
			Comm_Send("GUILD_REP_GET");
		end
	elseif ( view == VIEW_FINDER ) then
		GuildFinder_Show(frame.recruiting);
	end
end

function GuildUITab_OnClick(self)
	PlaySound("igMainMenuOptionCheckBoxOn");
	GuildUI_SetView(self:GetID());
end

function GuildUITab_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(self.tooltip);
	GameTooltip:Show();
end

-- the left list: 1 the guild (its last tab), 2 the guild finder
local guildMenuFrame = CreateFrame("Frame", "GuildUIGuildMenu", UIParent, "UIDropDownMenuTemplate");

function GuildUIListEntry_OnClick(self, button)
	PlaySound("igMainMenuOptionCheckBoxOn");
	local frame = CommunitiesFrame;
	if ( self:GetID() == 1 and button == "RightButton" ) then
		local menu = {
			{ text = (GetGuildInfo("player")), isTitle = true, notCheckable = true },
			{ text = "Покинуть гильдию", notCheckable = true, func = function()
				StaticPopup_Show("CONFIRM_GUILD_LEAVE", (GetGuildInfo("player")));
			end },
		};
		if ( IsGuildLeader() ) then
			tinsert(menu, { text = "Распустить гильдию", notCheckable = true, func = function()
				StaticPopup_Show("CONFIRM_GUILD_DISBAND");
			end });
		end
		tinsert(menu, { text = CANCEL, notCheckable = true, func = function() CloseDropDownMenus(); end });
		EasyMenu(menu, guildMenuFrame, "cursor", 0, 0, "MENU");
		return;
	end
	if ( self:GetID() == 1 ) then
		GuildUI_SetView(lastGuildView);
	else
		frame.recruiting = nil;
		frame.browsing = IsInGuild() or nil;
		GuildUI_SetView(VIEW_FINDER);
	end
end

-- the guild's recruitment settings and applicants (the bottom bar's button)
function GuildUI_ShowRecruitment()
	local frame = CommunitiesFrame;
	if ( frame.recruiting and frame.Finder:IsShown() ) then
		GuildUI_SetView(lastGuildView);
		return;
	end
	frame.recruiting = true;
	frame.browsing = nil;
	GuildUI_SetView(VIEW_FINDER);
end

-- the guild's name, level, experience
function GuildUI_UpdateHeader()
	local frame = CommunitiesFrame;
	if ( not IsInGuild() ) then
		frame:SetTitle("Поиск гильдии");
		frame.GuildLevel:SetText("");
		frame.XPBar:Hide();
		return;
	end
	local guildName = GetGuildInfo("player");
	frame:SetTitle(guildName or GUILD);

	local level, maxLevel = 0, 25;
	if ( GetGuildLevel ) then
		level, maxLevel = GetGuildLevel();
	end
	frame.GuildLevel:SetFormattedText("Уровень %d", level);
	frame.List.Guild.Name:SetText(guildName or GUILD);
	-- the guild's emblem on its banner (no design yet: the tabard icon)
	local emblem = GetGuildEmblemInfo();
	local entry = frame.List.Guild;
	GuildEmblem_Set(entry.Emblem, entry.Banner, entry.BannerBorder, emblem);
	entry.Emblem:SetShown(emblem ~= nil);
	entry.Icon:SetShown(emblem == nil);
	frame.List.Guild.Sub:SetFormattedText("Уровень %d", level);
	local bar = frame.XPBar;
	bar:Show();
	local experience, toNext, today, cap = 0, 0, 0, 0;
	if ( UnitGetGuildXP ) then
		experience, toNext, today, cap = UnitGetGuildXP("player");
	end
	if ( level >= maxLevel or toNext <= 0 ) then
		bar:SetMinMaxValues(0, 1);
		bar:SetValue(1);
		bar.Text:SetText(level >= maxLevel and "Максимальный уровень" or "");
	else
		local total = experience + toNext;
		bar:SetMinMaxValues(0, total);
		bar:SetValue(experience);
		bar.Text:SetFormattedText("%s / %s", BreakUpLargeNumbers and BreakUpLargeNumbers(experience) or experience,
			BreakUpLargeNumbers and BreakUpLargeNumbers(total) or total);
	end
	if ( cap and cap > 0 ) then
		bar.Today:SetFormattedText("Сегодня: %d%%", math.floor(today * 100 / cap));
	else
		bar.Today:SetText("");
	end
end

function GuildUIXPBar_OnEnter(self)
	local experience, toNext, today, cap = 0, 0, 0, 0;
	if ( UnitGetGuildXP ) then
		experience, toNext, today, cap = UnitGetGuildXP("player");
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM");
	GameTooltip:SetText("Опыт гильдии");
	GameTooltip:AddLine(format("Текущий: %d", experience), 1, 1, 1);
	GameTooltip:AddLine(format("До следующего уровня: %d", toNext), 1, 1, 1);
	if ( cap and cap > 0 ) then
		GameTooltip:AddLine(format("Сегодня: %d / %d", today, cap), 1, 1, 1);
	end
	GameTooltip:AddLine("Опыт приносят задания членов гильдии и победы в гильдейских группах.", nil, nil, nil, true);
	GameTooltip:Show();
end

function GuildUI_UpdateButtons()
	local frame = CommunitiesFrame;
	local inGuild = IsInGuild();
	frame.InviteButton:SetShown(inGuild);
	frame.ControlButton:SetShown(inGuild);
	frame.RecruitmentButton:SetShown(inGuild);
	if ( CanGuildInvite() ) then
		frame.InviteButton:Enable();
	else
		frame.InviteButton:Disable();
	end
	if ( IsGuildLeader() ) then
		frame.ControlButton:Enable();
	else
		frame.ControlButton:Disable();
	end
end


-- the stock rank control window, next to this one
function GuildUI_ToggleControl()
	local popup = GuildControlPopupFrame;
	if ( not popup ) then
		return;
	end
	if ( popup:IsShown() ) then
		popup:Hide();
		return;
	end
	popup.guildUI = true;
	-- the stock guild tab initializes it on GUILD_ROSTER_UPDATE: it never shows here
	GuildControlPopupFrame_Initialize();
	popup:ClearAllPoints();
	popup:SetPoint("TOPLEFT", CommunitiesFrame, "TOPRIGHT", 36, 0);
	popup:Show();
end

-- ------------------------------------------------------------ 1: roster

-- the last column (retail GuildMemberListDropdown): officer note / last online
local extraColumn = "online";
local EXTRA_COLUMNS = {
	{ key = "officer", text = "Офицерская заметка", allowed = function() return CanViewOfficerNote(); end },
	{ key = "online", text = "Последний вход" },
};

-- "3 дн.", "5 ч." since the last login (retail's zone column of the offline)
local function LastOnline(index)
	local years, months, days, hours = GetGuildRosterLastOnline(index);
	if ( not years ) then
		return "";
	end
	if ( years > 0 ) then
		return format("%d г.", years);
	elseif ( months > 0 ) then
		return format("%d мес.", months);
	elseif ( days > 0 ) then
		return format("%d дн.", days);
	elseif ( hours > 0 ) then
		return format("%d ч.", hours);
	end
	return "< 1 ч.";
end

local function ExtraText(info)
	if ( extraColumn == "officer" ) then
		return info.officerNote;
	end
	return info.online and "В сети" or info.lastOnline;
end

function GuildUIRoster_SetExtraColumn(key)
	extraColumn = key;
	for _, column in ipairs(EXTRA_COLUMNS) do
		if ( column.key == key ) then
			CommunitiesFrame.Roster.ColumnExtra.Label:SetText(column.text);
			UIDropDownMenu_SetText(CommunitiesFrame.Roster.ColumnDropDown, column.text);
		end
	end
	if ( CommunitiesFrame.Roster:IsShown() ) then
		GuildUIRoster_Update();
	end
end

function GuildUIRosterColumnDropDown_Initialize()
	for _, column in ipairs(EXTRA_COLUMNS) do
		if ( not column.allowed or column.allowed() ) then
			local item = UIDropDownMenu_CreateInfo();
			item.text = column.text;
			item.checked = column.key == extraColumn;
			item.func = function() GuildUIRoster_SetExtraColumn(column.key); end;
			UIDropDownMenu_AddButton(item);
		end
	end
end

local function MemberMatches(info, filter)
	if ( filter == "" ) then
		return true;
	end
	for _, text in ipairs({ info.name, info.zone, info.rank, info.note, info.class }) do
		if ( text and text:lower():find(filter, 1, true) ) then
			return true;
		end
	end
	return false;
end

local SORTERS = {
	name = function(a, b) return a.name < b.name; end,
	level = function(a, b) if ( a.level ~= b.level ) then return a.level > b.level; end return a.name < b.name; end,
	class = function(a, b) if ( (a.class or "") ~= (b.class or "") ) then return (a.class or "") < (b.class or ""); end return a.name < b.name; end,
	zone = function(a, b) if ( a.zone ~= b.zone ) then return a.zone < b.zone; end return a.name < b.name; end,
	rank = function(a, b) if ( a.rankIndex ~= b.rankIndex ) then return a.rankIndex < b.rankIndex; end return a.name < b.name; end,
	note = function(a, b) if ( a.note ~= b.note ) then return a.note > b.note; end return a.name < b.name; end,
	extra = function(a, b) local x, y = ExtraText(a), ExtraText(b); if ( x ~= y ) then return x > y; end return a.name < b.name; end,
};

local function BuildMembers()
	wipe(members);
	local roster = CommunitiesFrame.Roster;
	local showOffline = roster.ShowOffline:GetChecked();
	local filter = (roster.SearchBox:GetText() or ""):lower();
	if ( filter == SEARCH:lower() ) then
		filter = "";
	end
	local total = GetNumGuildMembers(true);
	local online = 0;
	for i = 1, total do
		local name, rank, rankIndex, level, class, zone, note, officerNote, isOnline, status, classFile = GetGuildRosterInfo(i);
		if ( name ) then
			if ( isOnline ) then
				online = online + 1;
			end
			local info = { index = i, name = name, rank = rank or "", rankIndex = rankIndex or 0, level = level or 0, class = class,
				zone = zone or "", note = note or "", officerNote = officerNote or "", online = isOnline, status = status, classFile = classFile };
			if ( not isOnline ) then
				-- retail: the offline's zone column tells how long ago
				info.lastOnline = LastOnline(i);
				info.zone = info.lastOnline;
			end
			if ( (isOnline or showOffline) and MemberMatches(info, filter) ) then
				tinsert(members, info);
			end
		end
	end
	local sorter = SORTERS[sortType] or SORTERS.rank;
	sort(members, function(a, b)
		-- online first, as retail
		if ( a.online ~= b.online ) then
			return a.online and true or false;
		end
		if ( sortReverse ) then
			return sorter(b, a);
		end
		return sorter(a, b);
	end);
	roster.Online:SetFormattedText("В сети: %d / %d", online, total);
end

function GuildUIRoster_Update()
	local roster = CommunitiesFrame.Roster;
	if ( not roster.List.rows ) then
		return;
	end
	BuildMembers();
	local list = roster.List;
	local rows = list.rows;
	local offset = FauxScrollFrame_GetOffset(list);
	for i, row in ipairs(rows) do
		local info = members[offset + i];
		row.info = info;
		if ( info ) then
			SetClassIcon(row.Class, info.classFile);
			row.Name:SetText(info.name..(info.status and info.status ~= "" and (" "..info.status) or ""));
			row.Level:SetText(info.level);
			row.Zone:SetText(info.zone);
			row.Rank:SetText(info.rank);
			row.Note:SetText(info.note);
			row.Extra:SetText(ExtraText(info));
			local c = info.online and 1 or 0.5;
			if ( info.online ) then
				row.Name:SetTextColor(ClassColor(info.classFile));
			else
				row.Name:SetTextColor(0.5, 0.5, 0.5);
			end
			row.Level:SetTextColor(c, c, c);
			row.Zone:SetTextColor(c, c, c);
			row.Rank:SetTextColor(c, c, c);
			row.Note:SetTextColor(c, c, c);
			row.Extra:SetTextColor(c, c, c);
			row.Class:SetDesaturated(not info.online);
			row.Selected:SetShown(info.name == selectedName);
			row:Show();
		else
			row:Hide();
		end
	end
	FauxScrollFrame_Update(list, #members, #rows, list.rowHeight);
end

function GuildUIColumn_OnClick(self)
	if ( sortType == self.sortType ) then
		sortReverse = not sortReverse;
	else
		sortType = self.sortType;
		sortReverse = false;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	GuildUIRoster_Update();
end

local menuFrame = CreateFrame("Frame", "GuildUIMemberMenu", UIParent, "UIDropDownMenuTemplate");

StaticPopupDialogs["GUILDUI_REMOVE_MEMBER"] = {
	text = "Исключить %s из гильдии?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		GuildUninvite(data);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	showAlert = 1,
};

StaticPopupDialogs["GUILDUI_SET_NOTE"] = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 31,
	OnShow = function(self, data)
		self.editBox:SetText(data.text or "");
		self.editBox:SetFocus();
	end,
	OnAccept = function(self, data)
		GuildUI_SetNote(data, self.editBox:GetText());
	end,
	EditBoxOnEnterPressed = function(self, data)
		local parent = self:GetParent();
		GuildUI_SetNote(parent.data, self:GetText());
		parent:Hide();
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

-- the roster index changes with every update: found again by the name
function GuildUI_SetNote(data, text)
	for i = 1, GetNumGuildMembers(true) do
		if ( GetGuildRosterInfo(i) == data.name ) then
			if ( data.officer ) then
				GuildRosterSetOfficerNote(i, text);
			else
				GuildRosterSetPublicNote(i, text);
			end
			break;
		end
	end
	GuildRoster();
end

local function ShowMemberMenu(row)
	local info = row.info;
	local isMe = info.name == UnitName("player");
	local menu = {
		{ text = info.name, isTitle = true, notCheckable = true },
	};
	if ( not isMe and info.online ) then
		tinsert(menu, { text = WHISPER, notCheckable = true, func = function() ChatFrame_SendTell(info.name); end });
		tinsert(menu, { text = PARTY_INVITE, notCheckable = true, func = function() InviteUnit(info.name); end });
	end
	if ( not isMe and CanGuildPromote() ) then
		tinsert(menu, { text = "Повысить", notCheckable = true, func = function() GuildPromote(info.name); end });
	end
	if ( not isMe and CanGuildDemote() ) then
		tinsert(menu, { text = "Понизить", notCheckable = true, func = function() GuildDemote(info.name); end });
	end
	if ( CanEditPublicNote() or isMe ) then
		tinsert(menu, { text = "Заметка", notCheckable = true, func = function()
			StaticPopup_Show("GUILDUI_SET_NOTE", "Заметка для "..info.name, nil, { name = info.name, text = info.note });
		end });
	end
	if ( CanEditOfficerNote() ) then
		tinsert(menu, { text = "Офицерская заметка", notCheckable = true, func = function()
			StaticPopup_Show("GUILDUI_SET_NOTE", "Офицерская заметка для "..info.name, nil, { name = info.name, text = info.officerNote, officer = true });
		end });
	end
	if ( not isMe and CanGuildRemove() ) then
		tinsert(menu, { text = "Исключить из гильдии", notCheckable = true, func = function()
			StaticPopup_Show("GUILDUI_REMOVE_MEMBER", info.name, nil, info.name);
		end });
	end
	tinsert(menu, { text = CANCEL, notCheckable = true, func = function() CloseDropDownMenus(); end });
	EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU");
end

function GuildUIRosterRow_OnClick(self, button)
	if ( not self.info ) then
		return;
	end
	selectedName = self.info.name;
	SetGuildRosterSelection(self.info.index);
	GuildUIRoster_Update();
	if ( button == "RightButton" ) then
		ShowMemberMenu(self);
	end
end

function GuildUIRosterRow_OnEnter(self)
	local info = self.info;
	if ( not info ) then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(info.name, ClassColor(info.classFile));
	GameTooltip:AddLine(format("%s %d %s", LEVEL, info.level, info.class or ""), 1, 1, 1);
	GameTooltip:AddLine(info.rank, 1, 1, 1);
	if ( info.online ) then
		GameTooltip:AddLine(info.zone, 1, 1, 1);
	else
		local years, months, days, hours = GetGuildRosterLastOnline(info.index);
		if ( years ) then
			GameTooltip:AddLine("Не в сети: "..(RecentTimeDate and RecentTimeDate(years, months, days, hours) or ""), 0.5, 0.5, 0.5);
		end
	end
	if ( info.note ~= "" ) then
		GameTooltip:AddLine(LABEL_NOTE..": "..info.note, 1, 0.82, 0, true);
	end
	if ( CanViewOfficerNote() and info.officerNote ~= "" ) then
		GameTooltip:AddLine("Офицерская: "..info.officerNote, 0.25, 1, 0.25, true);
	end
	GameTooltip:Show();
end

-- ------------------------------------------------------------ 2: info

-- the guild challenges (retail GuildChallenges; server/guild_achievements.cpp: type, the week's count)
GUILD_CHALLENGES = {
	{ type = 1, name = "Подземелье", max = 7, text = "Подземелье, пройденное гильдейской группой." },
	{ type = 2, name = "Эпохальный+", max = 3, text = "Эпохальное+ подземелье, пройденное гильдейской группой в срок." },
	{ type = 3, name = "Рейд", max = 1, text = "Рейдовый босс, побеждённый гильдейской группой." },
	{ type = 4, name = "Поле боя", max = 3, text = "Поле боя, выигранное командой, в которой много участников гильдии." },
};

function GuildUIChallenge_OnEnter(self)
	local challenge;
	for _, c in ipairs(GUILD_CHALLENGES) do
		if ( c.type == self.challengeType ) then
			challenge = c;
		end
	end
	if ( not challenge ) then
		return;
	end
	local _, done, count, xp, gold = GetGuildChallengeInfo(challenge.type);
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText("Испытание гильдии: "..challenge.name);
	GameTooltip:AddLine(challenge.text, 1, 1, 1, true);
	GameTooltip:AddLine(format("На этой неделе: %d / %d", done, count), 1, 0.82, 0);
	if ( xp > 0 ) then
		GameTooltip:AddLine(format("Награда за каждое: %d опыта гильдии", xp), 0.25, 1, 0.25);
	end
	if ( gold > 0 ) then
		GameTooltip:AddLine("и в банк гильдии: "..GetCoinTextureString(gold), 0.25, 1, 0.25);
	end
	GameTooltip:Show();
end

function GuildUIInfo_Update()
	local info = CommunitiesFrame.Info;
	for i, challenge in ipairs(GUILD_CHALLENGES) do
		local _, done, count = GetGuildChallengeInfo(challenge.type);
		if ( count == 0 ) then
			count = challenge.max;
		end
		local row = info["Challenge"..i];
		row.challengeType = challenge.type;
		row.Count:SetFormattedText("%d / %d", done, count);
		if ( done >= count and count > 0 ) then
			row.Count:SetTextColor(0.25, 1, 0.25);
		else
			row.Count:SetTextColor(1, 0.82, 0);
		end
	end
	local motd = GetGuildRosterMOTD() or "";
	info.MOTDText:SetText(motd);
	local details = GetGuildInfoText() or "";
	GuildUIInfoDetailsText:SetText(details);
	GuildUIInfoDetailsScrollChild:SetHeight(math.max(10, GuildUIInfoDetailsText:GetHeight()));
	info.DetailsScroll:UpdateScrollChildRect();
	info.EditMOTD:SetShown(CanEditMOTD());
	info.EditDetails:SetShown(CanEditGuildInfo());
	GuildUIInfo_UpdateLog();
end

-- ---- the MOTD / info editor

function GuildUIPopup_OnLoad(self)
	self:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	});
	self:SetBackdropColor(0.05, 0.05, 0.05, 0.95);
	self:SetBackdropBorderColor(0.6, 0.6, 0.6);
end

function GuildUITextEdit_Show(kind)
	local frame = GuildUITextEditFrame;
	frame.kind = kind;
	if ( kind == "motd" ) then
		GuildUITextEditFrameTitle:SetText("Сообщение дня");
		GuildUITextEditBox:SetMaxLetters(128);
		GuildUITextEditBox:SetText(GetGuildRosterMOTD() or "");
	else
		GuildUITextEditFrameTitle:SetText("Информация о гильдии");
		GuildUITextEditBox:SetMaxLetters(500);
		GuildUITextEditBox:SetText(GetGuildInfoText() or "");
	end
	frame:Show();
	GuildUITextEditBox:SetFocus();
end

function GuildUITextEdit_Accept()
	local frame = GuildUITextEditFrame;
	local text = GuildUITextEditBox:GetText();
	if ( frame.kind == "motd" ) then
		if ( CanEditMOTD() ) then
			GuildSetMOTD(text);
		end
	elseif ( CanEditGuildInfo() ) then
		SetGuildInfoText(text);
	end
	frame:Hide();
	GuildRoster();
end

-- ---- the event log: the news list (until the guild news stage) and the log window

local EVENT_FORMATS = {
	invite = function(p1, p2) return format(GUILDEVENT_TYPE_INVITE, p1, p2); end,
	join = function(p1) return format(GUILDEVENT_TYPE_JOIN, p1); end,
	promote = function(p1, p2, rank) return format(GUILDEVENT_TYPE_PROMOTE, p1, p2, rank); end,
	demote = function(p1, p2, rank) return format(GUILDEVENT_TYPE_DEMOTE, p1, p2, rank); end,
	remove = function(p1, p2) return format(GUILDEVENT_TYPE_REMOVE, p1, p2); end,
	quit = function(p1) return format(GUILDEVENT_TYPE_QUIT, p1); end,
};

-- the newest first: { text, ago, days }
local function GetEvents()
	local events = {};
	for i = GetNumGuildEvents(), 1, -1 do
		local eventType, player1, player2, rank, year, month, day, hour = GetGuildEventInfo(i);
		local make = EVENT_FORMATS[eventType];
		if ( make ) then
			tinsert(events, { text = make(player1 or UNKNOWN, player2 or UNKNOWN, rank),
				ago = RecentTimeDate(year, month, day, hour), days = (year or 0) * 365 + (month or 0) * 30 + (day or 0) });
		end
	end
	return events;
end

local function DayTitle(days)
	if ( days == 0 ) then
		return "Сегодня";
	elseif ( days == 1 ) then
		return "Вчера";
	end
	return format("%d дн. назад", days);
end

local function DaysAgo(seconds)
	return math.floor(seconds / 86400);
end

function GuildUIInfo_UpdateLog()
	local list = CommunitiesFrame.Info.News;
	if ( not list.rows ) then
		return;
	end
	-- retail news: the MOTD on top, then the days' headers and their news (GuildNews.lua)
	local lines = {};
	local motd = GetGuildRosterMOTD();
	if ( motd and motd ~= "" ) then
		tinsert(lines, { text = "|cffffd200Сообщение дня:|r "..motd });
	end
	local lastDays;
	for i = 1, GetNumGuildNews() do
		local entry = GetGuildNewsInfo(i);
		local days = DaysAgo(entry.secondsAgo + (time() - entry.received));
		if ( days ~= lastDays ) then
			tinsert(lines, { text = DayTitle(days), header = true });
			lastDays = days;
		end
		tinsert(lines, { text = GuildNews_GetText(entry), entry = entry });
	end
	if ( GetNumGuildNews() == 0 ) then
		tinsert(lines, { text = "|cff808080Новостей пока нет.|r" });
	end
	local offset = FauxScrollFrame_GetOffset(list);
	for i, row in ipairs(list.rows) do
		local line = lines[offset + i];
		row.entry = line and line.entry;
		if ( line ) then
			row.Text:SetText(line.text);
			row.Header:SetShown(line.header);
			if ( line.header ) then
				row.Text:SetFontObject("GameFontNormalSmall");
			else
				row.Text:SetFontObject("GameFontHighlightSmall");
			end
			row:Show();
		else
			row:Hide();
		end
	end
	FauxScrollFrame_Update(list, #lines, #list.rows, list.rowHeight);
end

-- a news line's item: its tooltip
function GuildUINewsRow_OnEnter(self)
	local entry = self.entry;
	if ( entry and entry.newsType >= NEWS_ITEM_LOOTED and entry.newsType <= NEWS_ITEM_PURCHASED ) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("item:"..entry.value);
		GameTooltip:Show();
	end
end

function GuildUILog_Toggle()
	if ( GuildUILogFrame:IsShown() ) then
		GuildUILogFrame:Hide();
	else
		GuildUITextEditFrame:Hide();
		GuildUILogFrame:Show();
	end
end

function GuildUILog_Update()
	local text = GuildUILogFrame.Text;
	text:Clear();
	local events = GetEvents();
	-- insertMode TOP: the oldest added first, the newest ends up on top
	for i = #events, 1, -1 do
		text:AddMessage(events[i].text.."|cff009999  "..format(GUILD_BANK_LOG_TIME, events[i].ago).."|r");
	end
end

-- ------------------------------------------------------------ 3: perks

function GuildUIPerks_Update()
	local perks = CommunitiesFrame.Perks;
	perks.AchievementPoints.Text:SetText(GetGuildAchievementPoints());
	local list = perks.List;
	if ( not list.rows ) then
		return;
	end
	local num = GetNumGuildPerks and GetNumGuildPerks() or 0;
	local level = GetGuildLevel and GetGuildLevel() or 0;
	local offset = FauxScrollFrame_GetOffset(list);
	local nextPerk;
	for i = 1, num do
		if ( not IsGuildPerkActive(i) ) then
			nextPerk = i;
			break;
		end
	end
	if ( nextPerk ) then
		local name, _, _, _, perkLevel = GetGuildPerkInfo(nextPerk);
		perks.Next:SetFormattedText("Следующее: |cffffd200%s|r на %d уровне гильдии", name, perkLevel);
	else
		perks.Next:SetText(num > 0 and "Все преимущества получены" or "");
	end
	for i, row in ipairs(list.rows) do
		local index = offset + i;
		if ( index <= num ) then
			local name, spellID, icon, description, perkLevel = GetGuildPerkInfo(index);
			row.index = index;
			row.spellID = spellID;
			row.Icon:SetTexture(icon);
			row.Name:SetText(name);
			row.Desc:SetText(description or "");
			row.Level:SetFormattedText("Уровень %d", perkLevel);
			local active = IsGuildPerkActive(index);
			row.Icon:SetDesaturated(not active);
			if ( active ) then
				row.Name:SetTextColor(1, 0.82, 0);
				row.Desc:SetTextColor(1, 1, 1);
				row.Level:SetTextColor(0.25, 1, 0.25);
				row.Bg:SetTexture(0.12, 0.10, 0.06, 0.8);
			else
				row.Name:SetTextColor(0.5, 0.5, 0.5);
				row.Desc:SetTextColor(0.5, 0.5, 0.5);
				row.Level:SetTextColor(0.5, 0.5, 0.5);
				row.Bg:SetTexture(0.06, 0.06, 0.06, 0.8);
			end
			row:Show();
		else
			row:Hide();
		end
	end
	FauxScrollFrame_Update(list, num, #list.rows, list.rowHeight);
end

function GuildUIPerkRow_OnEnter(self)
	if ( not self.spellID ) then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink("spell:"..self.spellID);
	if ( not IsGuildPerkActive(self.index) ) then
		local _, _, _, _, perkLevel = GetGuildPerkInfo(self.index);
		GameTooltip:AddLine(format("Требуется уровень гильдии: %d", perkLevel), 1, 0.1, 0.1);
	end
	GameTooltip:Show();
end
