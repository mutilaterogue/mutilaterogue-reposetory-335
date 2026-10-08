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
	guildEntry.Icon:SetSize(34, 34);
	guildEntry.Icon:ClearAllPoints();
	guildEntry.Icon:SetPoint("CENTER", guildEntry.Banner, "CENTER", 0, 2);
	SetPortraitToTexture(guildEntry.Icon, "Interface\\Icons\\INV_Shirt_GuildTabard_01");
	local finderEntry = self.List.Finder;
	SetPortraitToTexture(finderEntry.Icon, "Interface\\Icons\\INV_Misc_Spyglass_03");
	finderEntry.Name:SetText("Поиск гильдии");
	finderEntry.Sub:SetText("Найдите гильдию по себе");

	-- the roster: column titles, rows
	local roster = self.Roster;
	roster.ColumnName.Label:SetText(NAME);
	roster.ColumnLevel.Label:SetText(LEVEL_ABBR);
	roster.ColumnZone.Label:SetText(ZONE);
	roster.ColumnRank.Label:SetText(RANK);
	roster.ColumnNote.Label:SetText(LABEL_NOTE);
	GuildUI_MakeList(roster.List, "GuildUIRosterRowTemplate", ROSTER_ROW_HEIGHT, 13, GuildUIRoster_Update, function(row, i)
		row.Name:SetPoint("LEFT", row.Class, "RIGHT", 4, 0);
		row.Name:SetWidth(134);
		row.Level:SetPoint("LEFT", row, "LEFT", 162, 0);
		row.Level:SetWidth(40);
		row.Zone:SetPoint("LEFT", row, "LEFT", 210, 0);
		row.Zone:SetWidth(124);
		row.Rank:SetPoint("LEFT", row, "LEFT", 342, 0);
		row.Rank:SetWidth(104);
		row.Note:SetPoint("LEFT", row, "LEFT", 454, 0);
		row.Note:SetPoint("RIGHT", row, "RIGHT", -4, 0);
		row.Stripe:SetShown(i % 2 == 0);
	end);

	-- the perks
	GuildUI_MakeList(self.Perks.List, "GuildUIPerkRowTemplate", PERK_ROW_HEIGHT, 6, GuildUIPerks_Update);

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
		if ( self.Info:IsShown() ) then
			GuildUIInfo_UpdateLog();
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
		GuildUIInfo_UpdateLog();
	elseif ( view == VIEW_PERKS ) then
		GuildUIPerks_Update();
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
function GuildUIListEntry_OnClick(self)
	PlaySound("igMainMenuOptionCheckBoxOn");
	local frame = CommunitiesFrame;
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
	zone = function(a, b) if ( a.zone ~= b.zone ) then return a.zone < b.zone; end return a.name < b.name; end,
	rank = function(a, b) if ( a.rankIndex ~= b.rankIndex ) then return a.rankIndex < b.rankIndex; end return a.name < b.name; end,
	note = function(a, b) if ( a.note ~= b.note ) then return a.note > b.note; end return a.name < b.name; end,
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
			if ( info.online ) then
				row.Name:SetTextColor(ClassColor(info.classFile));
				row.Level:SetTextColor(1, 1, 1);
				row.Zone:SetTextColor(1, 1, 1);
				row.Rank:SetTextColor(1, 1, 1);
				row.Note:SetTextColor(1, 1, 1);
				row.Class:SetDesaturated(false);
			else
				row.Name:SetTextColor(0.5, 0.5, 0.5);
				row.Level:SetTextColor(0.5, 0.5, 0.5);
				row.Zone:SetTextColor(0.5, 0.5, 0.5);
				row.Rank:SetTextColor(0.5, 0.5, 0.5);
				row.Note:SetTextColor(0.5, 0.5, 0.5);
				row.Class:SetDesaturated(true);
			end
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

function GuildUIInfo_Update()
	local info = CommunitiesFrame.Info;
	if ( not info.MOTD:HasFocus() ) then
		info.MOTD:SetText(GetGuildRosterMOTD() or "");
	end
	if ( not info.DetailsScroll.Details:HasFocus() ) then
		info.DetailsScroll.Details:SetText(GetGuildInfoText() or "");
	end
	local canMOTD, canInfo = CanEditMOTD(), CanEditGuildInfo();
	info.MOTD:EnableMouse(canMOTD);
	info.MOTD:EnableKeyboard(canMOTD);
	info.DetailsScroll.Details:EnableMouse(canInfo);
	info.DetailsScroll.Details:EnableKeyboard(canInfo);
	info.Save:SetShown(canMOTD or canInfo);
	info.Disband:SetShown(IsGuildLeader());
end

function GuildUIInfo_SaveMOTD()
	if ( CanEditMOTD() ) then
		GuildSetMOTD(CommunitiesFrame.Info.MOTD:GetText());
	end
end

function GuildUIInfo_Save()
	local info = CommunitiesFrame.Info;
	info.MOTD:ClearFocus();
	info.DetailsScroll.Details:ClearFocus();
	if ( CanEditMOTD() and info.MOTD:GetText() ~= (GetGuildRosterMOTD() or "") ) then
		GuildSetMOTD(info.MOTD:GetText());
	end
	if ( CanEditGuildInfo() ) then
		SetGuildInfoText(info.DetailsScroll.Details:GetText());
	end
	GuildRoster();
end

local EVENT_FORMATS = {
	invite = function(p1, p2) return format(GUILDEVENT_TYPE_INVITE, p1, p2); end,
	join = function(p1) return format(GUILDEVENT_TYPE_JOIN, p1); end,
	promote = function(p1, p2, rank) return format(GUILDEVENT_TYPE_PROMOTE, p1, p2, rank); end,
	demote = function(p1, p2, rank) return format(GUILDEVENT_TYPE_DEMOTE, p1, p2, rank); end,
	remove = function(p1, p2) return format(GUILDEVENT_TYPE_REMOVE, p1, p2); end,
	quit = function(p1) return format(GUILDEVENT_TYPE_QUIT, p1); end,
};

function GuildUIInfo_UpdateLog()
	local log = CommunitiesFrame.Info.Log;
	log:Clear();
	-- insertMode TOP: the oldest first, the newest ends up on top
	for i = 1, GetNumGuildEvents() do
		local eventType, player1, player2, rank, year, month, day, hour = GetGuildEventInfo(i);
		local make = EVENT_FORMATS[eventType];
		if ( make ) then
			local msg = make(player1 or UNKNOWN, player2 or UNKNOWN, rank);
			log:AddMessage(msg.."|cff009999  "..format(GUILD_BANK_LOG_TIME, RecentTimeDate(year, month, day, hour)).."|r");
		end
	end
end

-- ------------------------------------------------------------ 3: perks

function GuildUIPerks_Update()
	local perks = CommunitiesFrame.Perks;
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
