-- Premade Groups window (LFGListFrame.xml), retail LFGListFrame on 3.3.5 over C_LFGList (LFGList.lua):
--   CategorySelection - the categories, "Start Group" / "Find Group";
--   SearchPanel       - the listed groups of the category (search, filter, refresh), the sign up dialog;
--   EntryCreation     - list our group (or change its listing);
--   ApplicationViewer - our listed group and its applicants (invite / decline).

local NUM_RESULT_ROWS, RESULT_HEIGHT = 7, 36;
local NUM_APPLICANT_ROWS, APPLICANT_HEIGHT = 6, 34;
local ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE = 1, 2, 4;
local PARTY_SIZE = 5;
local DIFFICULTY_MYTHIC_PLUS = 3;	-- premade_activity.difficulty of a keystone activity

-- the retail art of a category (groupfinder-button-* / groupfinder-background-*)
local CATEGORY_ART = { [1] = "questing", [2] = "dungeons", [3] = "raids-legion", [4] = "arenas", [6] = "custom-pve" };

local CLASS_FILES = {
	[1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [6] = "DEATHKNIGHT",
	[7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
};

-- the roles a class can take on 3.3.5 (retail grays the others out)
local CLASS_ROLES = {
	WARRIOR = ROLE_TANK + ROLE_DAMAGE, PALADIN = ROLE_TANK + ROLE_HEALER + ROLE_DAMAGE, HUNTER = ROLE_DAMAGE,
	ROGUE = ROLE_DAMAGE, PRIEST = ROLE_HEALER + ROLE_DAMAGE, DEATHKNIGHT = ROLE_TANK + ROLE_DAMAGE,
	SHAMAN = ROLE_HEALER + ROLE_DAMAGE, MAGE = ROLE_DAMAGE, WARLOCK = ROLE_DAMAGE,
	DRUID = ROLE_TANK + ROLE_HEALER + ROLE_DAMAGE,
};

local ROLE_ORDER = { ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE };
local ROLE_KEYS = { [ROLE_TANK] = "Tank", [ROLE_HEALER] = "Healer", [ROLE_DAMAGE] = "Damager" };
local ROLE_NAMES = { [ROLE_TANK] = TANK or "Танк", [ROLE_HEALER] = HEALER or "Лекарь", [ROLE_DAMAGE] = DAMAGER or "Боец" };
-- the member icons of a result / an applicant
local ROLE_ATLAS = {
	[ROLE_TANK] = "groupfinder-icon-role-large-tank",
	[ROLE_HEALER] = "groupfinder-icon-role-large-heal",
	[ROLE_DAMAGE] = "groupfinder-icon-role-large-dps",
};
local ROLE_MICRO_ATLAS = {
	[ROLE_TANK] = "groupfinder-icon-role-micro-tank",
	[ROLE_HEALER] = "groupfinder-icon-role-micro-heal",
	[ROLE_DAMAGE] = "groupfinder-icon-role-micro-dps",
};
-- the sign up dialog's big role icons
local ROLE_DIALOG_ATLAS = { [ROLE_TANK] = "UI-LFG-RoleIcon-Tank", [ROLE_HEALER] = "UI-LFG-RoleIcon-Healer", [ROLE_DAMAGE] = "UI-LFG-RoleIcon-DPS" };

local frame;
local selectedCategory;
local selectedResult;
local editing = false;			-- EntryCreation changes our listing
local creationGroup, creationActivity;
local dialogRoles = {};
local filters = {};				-- needTank, needHealer, needDamage, voiceChat
local categoryButtons = {};
local resultRows, applicantRows = {}, {};

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function ClassColor(classID)
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[CLASS_FILES[classID] or ""];
	return color or NORMAL_FONT_COLOR;
end

local function ClassColored(text, classID)
	local color = ClassColor(classID);
	return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text);
end

local function FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds));
	if seconds >= 3600 then
		return string.format("%d ч %d мин", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60));
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60);
end

local function GetActivity(activityID)
	return activityID and C_LFGList.GetActivityInfoTable(activityID);
end

local function ActivityName(activityID)
	local activity = GetActivity(activityID);
	return activity and activity.fullName or "";
end

local function IsMythicPlus(activityID)
	local activity = GetActivity(activityID);
	return activity and activity.difficultyID == DIFFICULTY_MYTHIC_PLUS;
end

local function InGroup()
	return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0;
end

-- the leader or a raid assistant (a group of one: its only member)
local function CanManageGroup()
	if GetNumRaidMembers() > 0 then
		return IsRaidLeader() or IsRaidOfficer();
	end
	if GetNumPartyMembers() > 0 then
		return IsPartyLeader();
	end
	return true;
end

local function PlayerRoles()
	local _, classFile = UnitClass("player");
	return CLASS_ROLES[classFile] or ROLE_DAMAGE;
end

local function ShowPanel(panel)
	for _, key in ipairs({ "CategorySelection", "SearchPanel", "EntryCreation", "ApplicationViewer" }) do
		if frame[key] == panel then
			frame[key]:Show();
		else
			frame[key]:Hide();
		end
	end
end

-- the dark inset (as the dungeon / raid finder's): under the content, its level set on every show
local function LayerInset(self)
	if not self.Inset then
		self.Inset = CreateFrame("Frame", "LFGListFrameInset", self, "InsetFrameTemplate");
		self.Inset:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -60);
		self.Inset:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -6, 26);
	end
	self.Inset:SetFrameLevel(self:GetFrameLevel());
	for _, child in ipairs({ self:GetChildren() }) do
		if child ~= self.Inset then
			child:SetFrameLevel(self:GetFrameLevel() + 3);
		end
	end
end

-- the retail mouse over art (an atlas: set here, not in the XML)
function LFGList_AddHighlight(self, atlas, width, height, alpha)
	local highlight = self:CreateTexture(nil, "HIGHLIGHT");
	if width then
		highlight:SetSize(width, height);
		highlight:SetPoint("CENTER");
	else
		highlight:SetAllPoints();
	end
	highlight:SetAtlas(atlas);
	highlight:SetBlendMode("ADD");
	highlight:SetAlpha(alpha or 1);
end

function LFGListEditBox_OnTextChanged(self)
	local empty = self:GetText() == "";
	if self.Instructions then
		self.Instructions:SetShown(empty);
	end
	if self.ClearButton then
		self.ClearButton:SetShown(not empty);
	end
	local owner = self.onTextChanged and self or self:GetParent();
	if owner.onTextChanged then
		owner.onTextChanged(owner);
	end
end

function LFGListSearchBoxClear_OnClick(self)
	local box = self:GetParent();
	box:SetText("");
	box:ClearFocus();
	LFGListSearchPanel_DoSearch();
end

---------------------------------------------------------------------------
-- the categories
---------------------------------------------------------------------------
local function UpdateCategorySelection()
	local panel = frame.CategorySelection;
	local categories = C_LFGList.GetAvailableCategories();
	for index, categoryID in ipairs(categories) do
		local button = categoryButtons[index];
		if not button then
			button = CreateFrame("Button", "LFGListCategoryButton" .. index, panel, "LFGListCategoryTemplate");
			button:SetPoint("TOP", panel, "TOP", -2, -66 - (index - 1) * 49);
			categoryButtons[index] = button;
		end
		local info = C_LFGList.GetLfgCategoryInfo(categoryID);
		button.categoryID = categoryID;
		button.Label:SetText(info and info.name or "");
		button.Icon:SetAtlas("groupfinder-button-" .. (CATEGORY_ART[categoryID] or "custom-pve"));
		button.SelectedTexture:SetShown(categoryID == selectedCategory);
		button:SetFrameLevel(panel:GetFrameLevel() + 1);
		button:Show();
	end
	for index = #categories + 1, #categoryButtons do
		categoryButtons[index]:Hide();
	end
	if not selectedCategory and categories[1] then
		selectedCategory = categories[1];
		UpdateCategorySelection();
		return;
	end
	panel.FindGroupButton:SetEnabled(selectedCategory ~= nil);
	-- a group member who does not lead it cannot list it
	panel.StartGroupButton:SetEnabled(selectedCategory ~= nil and CanManageGroup());
end

function LFGListCategoryButton_OnClick(self)
	selectedCategory = self.categoryID;
	PlaySound("igMainMenuOptionCheckBoxOn");
	UpdateCategorySelection();
end

function LFGListFrame_ShowCategorySelection()
	ShowPanel(frame.CategorySelection);
	UpdateCategorySelection();
end

function LFGListCategorySelectionFindGroup_OnClick()
	selectedResult = nil;
	local info = C_LFGList.GetLfgCategoryInfo(selectedCategory);
	frame.SearchPanel.CategoryName:SetText(info and info.name or "");
	frame.SearchPanel.SearchBox:SetText("");
	ShowPanel(frame.SearchPanel);
	LFGListSearchPanel_DoSearch();
end

---------------------------------------------------------------------------
-- the search
---------------------------------------------------------------------------
function LFGListSearchPanel_DoSearch()
	C_LFGList.Search(selectedCategory, frame.SearchPanel.SearchBox:GetText());
	LFGListSearchPanel_UpdateResults();
end

function LFGListSearchPanelSearchBox_OnEnterPressed(self)
	self:ClearFocus();
	LFGListSearchPanel_DoSearch();
end

-- the filter (retail: "needs a tank / healer / damage", voice chat): on the received results
local function PassesFilters(info)
	local activity = GetActivity(info.activityID);
	local party = not activity or activity.maxNumPlayers <= PARTY_SIZE;
	if party then
		if filters.needTank and info.tanks >= 1 then return false; end
		if filters.needHealer and info.healers >= 1 then return false; end
		if filters.needDamage and info.damage >= 3 then return false; end
	end
	if filters.voiceChat and not info.voiceChat then
		return false;
	end
	return true;
end

local function FilteredResults()
	local _, ids = C_LFGList.GetSearchResults();
	local out = {};
	for _, id in ipairs(ids) do
		local info = C_LFGList.GetSearchResultInfo(id);
		if info and PassesFilters(info) then
			table.insert(out, id);
		end
	end
	return out;
end

local function FiltersDefault()
	return not (filters.needTank or filters.needHealer or filters.needDamage or filters.voiceChat);
end

local function SetupFilterButton(button)
	local function Checkbox(root, text, key)
		root:CreateCheckbox(text, function() return filters[key]; end, function()
			filters[key] = not filters[key] or nil;
			LFGListSearchPanel_UpdateResults();
		end);
	end
	button:SetupMenu(function(dropdown, root)
		Checkbox(root, "Нужен танк", "needTank");
		Checkbox(root, "Нужен лекарь", "needHealer");
		Checkbox(root, "Нужен боец", "needDamage");
		Checkbox(root, "С голосовым чатом", "voiceChat");
	end);
	button:SetIsDefaultCallback(FiltersDefault);
	button:SetDefaultCallback(function() wipe(filters); end);
	button:SetUpdateCallback(LFGListSearchPanel_UpdateResults);
end

-- the members: five slots of a party (tanks, healers, damage, then the empty ones), the role counts of a raid
local function UpdateDataDisplay(display, info)
	local activity = GetActivity(info.activityID);
	local party = not activity or activity.maxNumPlayers <= PARTY_SIZE;
	for i = 1, PARTY_SIZE do
		display["Slot" .. i]:SetShown(party);
	end
	display.Tank:SetShown(not party);
	display.Healer:SetShown(not party);
	display.Damager:SetShown(not party);
	if not party then
		for role, key in pairs(ROLE_KEYS) do
			local count = role == ROLE_TANK and info.tanks or role == ROLE_HEALER and info.healers or info.damage;
			display[key].Icon:SetAtlas(ROLE_MICRO_ATLAS[role]);
			display[key].Count:SetText(count);
		end
		return;
	end
	local members = {};
	for _, member in ipairs(info.members) do
		table.insert(members, member);
	end
	table.sort(members, function(a, b)
		if a.role ~= b.role then
			return a.role < b.role;
		end
		return a.isLeader and not b.isLeader;
	end);
	for i = 1, PARTY_SIZE do
		local slot = display["Slot" .. i];
		local member = members[i];
		if member then
			slot.Icon:SetAtlas(ROLE_ATLAS[member.role] or ROLE_ATLAS[ROLE_DAMAGE]);
			slot.Leader:SetShown(member.isLeader);
		else
			slot.Icon:SetAtlas("groupfinder-icon-emptyslot");
			slot.Leader:Hide();
		end
	end
end

function LFGListSearchPanel_UpdateResults()
	local panel = frame.SearchPanel;
	local total = C_LFGList.GetSearchResults();
	local ids = FilteredResults();
	local count = #ids;
	local searching = C_LFGList.IsSearching();
	panel.Searching:SetShown(searching and count == 0);
	panel.NoResults:SetShown(not searching and count == 0);
	if searching then
		panel.ResultCount:SetText("");
	elseif count < total then
		panel.ResultCount:SetText(string.format("Найдено групп: %d (показано %d)", total, count));
	else
		panel.ResultCount:SetText(string.format("Найдено групп: %d", total));
	end
	panel.FilterButton:ValidateResetState();

	FauxScrollFrame_Update(panel.ScrollFrame, count, NUM_RESULT_ROWS, RESULT_HEIGHT);
	local offset = FauxScrollFrame_GetOffset(panel.ScrollFrame);
	for i = 1, NUM_RESULT_ROWS do
		local row = resultRows[i];
		local id = ids[i + offset];
		local info = id and C_LFGList.GetSearchResultInfo(id);
		if info then
			row.resultID = id;
			local _, status, _, secondsLeft = C_LFGList.GetApplicationInfo(id);
			local applied, invited = status == "applied", status == "invited";
			local pending = applied or invited;
			row.Name:SetText(info.name);
			if pending then
				row.Name:SetTextColor(0.1, 1, 0.1);
			else
				row.Name:SetTextColor(1, 0.82, 0);
			end
			row.ActivityName:SetText(ActivityName(info.activityID));
			row.PendingLabel:SetShown(pending);
			row.PendingLabel:SetText(invited and "Приглашение" or "В ожидании");
			row.ExpirationTime:SetShown(pending);
			row.ExpirationTime:SetText(FormatTime(secondsLeft));
			row.CancelButton:SetShown(applied);
			row.ResultBG:SetShown(pending);
			row.ResultBG:SetAtlas(invited and "groupfinder-highlightbar-yellow" or "groupfinder-highlightbar-green");
			-- the members give way to the status
			row.DataDisplay:SetShown(not pending);
			row.VoiceChat:SetShown(info.voiceChat and not pending);
			UpdateDataDisplay(row.DataDisplay, info);
			row.Selected:SetShown(id == selectedResult);
			row:Show();
		else
			row:Hide();
		end
	end

	-- "Sign Up": a group chosen, not applied to yet, and no group of our own
	local _, status = C_LFGList.GetApplicationInfo(selectedResult or 0);
	panel.SignUpButton:SetEnabled(selectedResult ~= nil and status == "none" and not InGroup());
	panel.StartGroupButton:SetEnabled(CanManageGroup());
end

function LFGListSearchEntry_OnClick(self, button)
	if button == "RightButton" then
		return;
	end
	selectedResult = self.resultID;
	PlaySound("igMainMenuOptionCheckBoxOn");
	LFGListSearchPanel_UpdateResults();
end

function LFGListSearchEntry_OnDoubleClick(self)
	selectedResult = self.resultID;
	LFGListSearchPanelSignUp_OnClick();
end

function LFGListSearchEntryCancel_OnClick(self)
	C_LFGList.CancelApplication(self:GetParent().resultID);
end

function LFGListSearchEntry_OnEnter(self)
	local info = C_LFGList.GetSearchResultInfo(self.resultID);
	if not info then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 25, 0);
	GameTooltip:SetText(info.name, 1, 1, 1, 1, true);
	GameTooltip:AddLine(ActivityName(info.activityID), 1, 0.82, 0);
	if info.comment ~= "" then
		GameTooltip:AddLine(info.comment, 0.75, 0.75, 0.75, true);
	end
	GameTooltip:AddLine(" ");
	if info.keyLevel > 0 then
		GameTooltip:AddLine(string.format("Ключ: +%d", info.keyLevel), 1, 1, 1);
	end
	if info.requiredItemLevel > 0 then
		GameTooltip:AddLine(string.format("Мин. уровень предметов: %d", info.requiredItemLevel), 1, 1, 1);
	end
	if info.requiredDungeonScore > 0 then
		GameTooltip:AddLine(string.format("Мин. рейтинг М+: %d", info.requiredDungeonScore), 1, 1, 1);
	end
	if info.voiceChat then
		GameTooltip:AddLine("Голосовой чат", 1, 1, 1);
	end
	if info.leaderName ~= "" then
		GameTooltip:AddLine("Лидер: " .. ClassColored(info.leaderName, info.leaderClassID), 1, 1, 1);
		if IsMythicPlus(info.activityID) or info.leaderOverallDungeonScore > 0 then
			GameTooltip:AddLine(string.format("Рейтинг лидера: %d", info.leaderOverallDungeonScore), 1, 1, 1);
		end
	end
	local age = info.age + (GetTime() - info.ageTime);
	GameTooltip:AddLine("Создана: " .. FormatTime(age) .. " назад", 0.5, 0.5, 0.5);
	if info.autoAccept then
		GameTooltip:AddLine("Новые участники принимаются автоматически.", 0.1, 1, 0.1, true);
	end
	GameTooltip:AddLine(" ");
	GameTooltip:AddLine(string.format("Участники: %d (%d/%d/%d)", info.numMembers, info.tanks, info.healers, info.damage), 1, 1, 1);
	local classes = {};
	for _, member in ipairs(info.members) do
		classes[member.classID] = (classes[member.classID] or 0) + 1;
	end
	for classID, n in pairs(classes) do
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[CLASS_FILES[classID] or ""] or CLASS_FILES[classID] or "?";
		GameTooltip:AddLine(ClassColored(name, classID) .. (n > 1 and (" x" .. n) or ""));
	end
	GameTooltip:Show();
end

---------------------------------------------------------------------------
-- the sign up dialog
---------------------------------------------------------------------------
local function UpdateApplicationDialog()
	local dialog = LFGListApplicationDialog;
	local available = PlayerRoles();
	local any = false;
	for role, key in pairs(ROLE_KEYS) do
		local button = dialog[key];
		local can = bit.band(available, role) ~= 0;
		if not can then
			dialogRoles[role] = nil;
		end
		button.CheckButton:SetChecked(dialogRoles[role]);
		if can then
			button.CheckButton:Enable();
		else
			button.CheckButton:Disable();
		end
		button.Icon:SetAtlas(ROLE_DIALOG_ATLAS[role] .. (can and "" or "-Disabled"));
		button.available = can;
		any = any or dialogRoles[role];
	end
	dialog.SignUpButton:SetEnabled(any and true or false);
end

function LFGListApplicationDialogRole_OnClick(self)
	dialogRoles[self:GetParent().role] = self:GetChecked() and true or nil;
	UpdateApplicationDialog();
end

function LFGListRoleButton_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(self.roleName);
	if not self.available then
		GameTooltip:AddLine("Ваш класс не может выполнять эту роль.", 1, 0.1, 0.1, true);
	end
	GameTooltip:Show();
end

function LFGListSearchPanelSignUp_OnClick()
	local info = selectedResult and C_LFGList.GetSearchResultInfo(selectedResult);
	if not info then
		return;
	end
	local dialog = LFGListApplicationDialog;
	dialog.resultID = selectedResult;
	dialog.GroupName:SetText(info.name);
	local requirements = {};
	if info.requiredItemLevel > 0 then
		table.insert(requirements, string.format("уровень предметов %d", info.requiredItemLevel));
	end
	if info.requiredDungeonScore > 0 then
		table.insert(requirements, string.format("рейтинг М+ %d", info.requiredDungeonScore));
	end
	dialog.Requirement:SetText(#requirements > 0 and ("Требуется: " .. table.concat(requirements, ", ")) or "");
	dialog.Description.EditBox:SetText("");
	-- the roles of the last sign up (or the first one the class can take)
	if not next(dialogRoles) then
		local available = PlayerRoles();
		for _, role in ipairs({ ROLE_DAMAGE, ROLE_HEALER, ROLE_TANK }) do
			if bit.band(available, role) ~= 0 then
				dialogRoles[role] = true;
				break;
			end
		end
	end
	UpdateApplicationDialog();
	dialog:Show();
end

function LFGListApplicationDialogSignUp_OnClick(self)
	local dialog = self:GetParent();
	C_LFGList.ApplyToGroup(dialog.resultID, dialog.Description.EditBox:GetText(),
		dialogRoles[ROLE_TANK], dialogRoles[ROLE_HEALER], dialogRoles[ROLE_DAMAGE]);
	dialog:Hide();
end

-- the sign up dialog is made after LFGListFrame (LFGListFrame.xml): its own OnLoad
function LFGListApplicationDialog_OnLoad(self)
	tinsert(UISpecialFrames, self:GetName());
	-- the retail dialog border (NineSlice "Dialog"; DialogBorderTemplate)
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
		NineSliceUtil.ApplyLayoutByName(self, "Dialog");
	end
	for role, key in pairs(ROLE_KEYS) do
		self[key].role = role;
		self[key].CheckButton.role = role;
		self[key].roleName = ROLE_NAMES[role];
	end
	self.Description.EditBox.Instructions:SetText("Комментарий (необязательно)");
end

---------------------------------------------------------------------------
-- the group creation
---------------------------------------------------------------------------
local function FirstActivity(categoryID, groupID)
	local level = UnitLevel("player");
	local activities = C_LFGList.GetAvailableActivities(categoryID, groupID);
	for _, activityID in ipairs(activities) do
		local activity = GetActivity(activityID);
		if activity and level >= activity.minLevel then
			return activityID;
		end
	end
	return activities[1];
end

local function HasGroups()
	return #C_LFGList.GetAvailableActivityGroups(selectedCategory) > 0;
end

function LFGListEntryCreation_UpdateValidState()
	local panel = frame.EntryCreation;
	local mythicPlus = IsMythicPlus(creationActivity);
	panel.ItemLevelBox:SetShown(panel.ItemLevel:GetChecked() and true or false);
	-- the rating: keystone activities only
	panel.Rating:SetShown(mythicPlus and true or false);
	panel.RatingBox:SetShown(mythicPlus and panel.Rating:GetChecked() and true or false);
	panel.VoiceChatBox:SetShown(panel.VoiceChat:GetChecked() and true or false);
	-- a keystone group may have no name: "+level dungeon" from the leader's key
	panel.Name.Instructions:SetText(mythicPlus and "По ключу (необязательно)" or "Название группы (обязательно)");
	local nameOk = mythicPlus or panel.Name:GetText() ~= "";
	panel.ListGroupButton:SetEnabled(creationActivity ~= nil and nameOk and CanManageGroup());
end

local function UpdateCreationDropdowns()
	local panel = frame.EntryCreation;
	local hasGroups = HasGroups();
	panel.GroupDropdown:SetShown(hasGroups);
	panel.ActivityDropdown:ClearAllPoints();
	if hasGroups then
		panel.ActivityDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -110);
		panel.GroupDropdown:GenerateMenu();
	else
		panel.ActivityDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -82);
	end
	panel.ActivityDropdown:GenerateMenu();
	local activity = GetActivity(creationActivity);
	if activity and activity.ilvlSuggestion > 0 then
		panel.ItemLevel.Label:SetText(string.format("Мин. уровень предметов (реком. %d)", activity.ilvlSuggestion));
	else
		panel.ItemLevel.Label:SetText("Минимальный уровень предметов");
	end
	LFGListEntryCreation_UpdateValidState();
end

local function SetupCreationDropdowns(panel)
	panel.GroupDropdown:SetupMenu(function(dropdown, root)
		for _, groupID in ipairs(C_LFGList.GetAvailableActivityGroups(selectedCategory)) do
			root:CreateRadio(C_LFGList.GetActivityGroupInfo(groupID), function() return groupID == creationGroup; end, function()
				creationGroup = groupID;
				creationActivity = FirstActivity(selectedCategory, groupID);
				UpdateCreationDropdowns();
			end);
		end
	end);
	panel.ActivityDropdown:SetupMenu(function(dropdown, root)
		local hasGroups = HasGroups();
		local level = UnitLevel("player");
		for _, activityID in ipairs(C_LFGList.GetAvailableActivities(selectedCategory, hasGroups and creationGroup or 0)) do
			local activity = GetActivity(activityID);
			local text = hasGroups and activity.shortName or activity.fullName;
			if level < activity.minLevel then
				text = string.format("|cff808080%s (%d+)|r", text, activity.minLevel);
			end
			root:CreateRadio(text, function() return activityID == creationActivity; end, function()
				if level >= activity.minLevel then
					creationActivity = activityID;
				end
				UpdateCreationDropdowns();
			end);
		end
	end);
end

-- an empty form for the category, or our listing to change
local function ShowEntryCreation(entry)
	local panel = frame.EntryCreation;
	editing = entry ~= nil;
	if entry then
		local activity = GetActivity(entry.activityID);
		selectedCategory = activity and activity.categoryID or selectedCategory;
		creationActivity = entry.activityID;
		creationGroup = activity and activity.groupFinderActivityGroupID ~= 0 and activity.groupFinderActivityGroupID or nil;
		panel.Name:SetText(entry.name);
		panel.Description.EditBox:SetText(entry.comment);
		panel.ItemLevel:SetChecked(entry.requiredItemLevel > 0);
		panel.ItemLevelBox:SetText(entry.requiredItemLevel > 0 and entry.requiredItemLevel or "");
		panel.Rating:SetChecked(entry.requiredDungeonScore > 0);
		panel.RatingBox:SetText(entry.requiredDungeonScore > 0 and entry.requiredDungeonScore or "");
		panel.VoiceChat:SetChecked(entry.voiceChat ~= "");
		panel.VoiceChatBox:SetText(entry.voiceChat);
		panel.AutoAccept:SetChecked(entry.autoAccept);
		panel.PrivateGroup:SetChecked(entry.privateGroup);
		panel.ListGroupButton:SetText("Применить");
	else
		creationGroup = C_LFGList.GetAvailableActivityGroups(selectedCategory)[1];
		creationActivity = FirstActivity(selectedCategory, creationGroup or 0);
		panel.Name:SetText("");
		panel.Description.EditBox:SetText("");
		panel.ItemLevel:SetChecked(false);
		panel.ItemLevelBox:SetText("");
		panel.Rating:SetChecked(false);
		panel.RatingBox:SetText("");
		panel.VoiceChat:SetChecked(false);
		panel.VoiceChatBox:SetText("");
		panel.AutoAccept:SetChecked(false);
		panel.PrivateGroup:SetChecked(false);
		panel.ListGroupButton:SetText("Внести в список");
	end
	local info = C_LFGList.GetLfgCategoryInfo(selectedCategory);
	panel.Label:SetText(info and info.name or "");
	ShowPanel(panel);
	UpdateCreationDropdowns();
end

function LFGListStartGroup_OnClick()
	ShowEntryCreation(nil);
end

function LFGListEntryCreationCancel_OnClick()
	if editing and C_LFGList.HasActiveEntryInfo() then
		editing = false;
		LFGListApplicationViewer_Show();
	else
		LFGListFrame_ShowCategorySelection();
	end
end

function LFGListEntryCreationListGroup_OnClick()
	local panel = frame.EntryCreation;
	local mythicPlus = IsMythicPlus(creationActivity);
	local info = {
		activityID = creationActivity,
		name = panel.Name:GetText(),
		comment = panel.Description.EditBox:GetText(),
		itemLevel = panel.ItemLevel:GetChecked() and (tonumber(panel.ItemLevelBox:GetText()) or 0) or 0,
		minRating = mythicPlus and panel.Rating:GetChecked() and (tonumber(panel.RatingBox:GetText()) or 0) or 0,
		voiceChat = panel.VoiceChat:GetChecked() and panel.VoiceChatBox:GetText() or "",
		autoAccept = panel.AutoAccept:GetChecked() and true or false,
		privateGroup = panel.PrivateGroup:GetChecked() and true or false,
	};
	panel.Name:ClearFocus();
	panel.Description.EditBox:ClearFocus();
	if editing and C_LFGList.HasActiveEntryInfo() then
		C_LFGList.UpdateListing(info);
	else
		C_LFGList.CreateListing(info);
	end
	-- the server's "LG_ENTRY" opens the applicants
	editing = false;
end

---------------------------------------------------------------------------
-- our listed group
---------------------------------------------------------------------------
function LFGListApplicationViewer_UpdateApplicants()
	local panel = frame.ApplicationViewer;
	local manage = CanManageGroup();
	local ids = manage and C_LFGList.GetApplicants() or {};
	local entry = C_LFGList.GetActiveEntryInfo();
	local mythicPlus = entry and IsMythicPlus(entry.activityID);
	panel.NotLeader:SetShown(not manage);
	panel.NoApplicants:SetShown(manage and #ids == 0);

	FauxScrollFrame_Update(panel.ScrollFrame, #ids, NUM_APPLICANT_ROWS, APPLICANT_HEIGHT);
	local offset = FauxScrollFrame_GetOffset(panel.ScrollFrame);
	for i = 1, NUM_APPLICANT_ROWS do
		local row = applicantRows[i];
		local info = ids[i + offset] and C_LFGList.GetApplicantInfo(ids[i + offset]);
		if info then
			row.applicantID = info.applicantID;
			local classFile = CLASS_FILES[info.classID];
			row.ClassIcon:SetAtlas("groupfinder-icon-class-" .. string.lower(classFile or "warrior"));
			row.Name:SetText(ClassColored(info.name, info.classID));
			if mythicPlus then
				row.Info:SetText(string.format("%d предм., рейтинг %d", info.itemLevel, info.dungeonScore));
			else
				row.Info:SetText(string.format("%d ур., %d предм.", info.level, info.itemLevel));
			end
			local index = 1;
			for _, role in ipairs(ROLE_ORDER) do
				if bit.band(info.roles, role) ~= 0 then
					row["Role" .. index]:SetAtlas(ROLE_ATLAS[role]);
					row["Role" .. index]:Show();
					index = index + 1;
				end
			end
			for j = index, 3 do
				row["Role" .. j]:Hide();
			end
			local invited = info.applicationStatus == "invited";
			row.InviteButton:SetShown(not invited);
			row.Status:SetShown(invited);
			row.Status:SetText("Приглашен");
			row.NewBG:SetShown(info.isNew);
			row:Show();
		else
			row:Hide();
		end
	end
end

local function UpdateExpiration()
	local entry = C_LFGList.GetActiveEntryInfo();
	if entry then
		frame.ApplicationViewer.Expiration:SetText("Исключение из списка через " .. FormatTime(entry.expires - GetTime()));
	end
end

function LFGListApplicationViewer_Show()
	local panel = frame.ApplicationViewer;
	local entry = C_LFGList.GetActiveEntryInfo();
	if not entry then
		LFGListFrame_ShowCategorySelection();
		return;
	end
	local activity = GetActivity(entry.activityID);
	panel.InfoBackground:SetAtlas("groupfinder-background-" .. (CATEGORY_ART[activity and activity.categoryID or 6] or "custom-pve"));
	panel.EntryName:SetText(entry.name);
	panel.ActivityName:SetText(activity and activity.fullName or "");
	panel.Description:SetText(entry.comment);
	local requirements = {};
	if entry.keyLevel > 0 then
		table.insert(requirements, string.format("ключ +%d", entry.keyLevel));
	end
	if entry.requiredItemLevel > 0 then
		table.insert(requirements, string.format("уровень предметов %d", entry.requiredItemLevel));
	end
	if entry.requiredDungeonScore > 0 then
		table.insert(requirements, string.format("рейтинг %d", entry.requiredDungeonScore));
	end
	panel.Requirements:SetText(table.concat(requirements, ", "));
	panel.AutoAcceptText:SetShown(entry.autoAccept);
	panel.VoiceChatIcon:SetShown(entry.voiceChat ~= "");
	UpdateExpiration();
	local manage = CanManageGroup();
	panel.RemoveEntryButton:SetEnabled(manage);
	panel.EditButton:SetEnabled(manage);
	ShowPanel(panel);
	LFGListApplicationViewer_UpdateApplicants();
	if manage then
		for _, id in ipairs(C_LFGList.GetApplicants()) do
			local info = C_LFGList.GetApplicantInfo(id);
			if info and info.isNew then
				C_LFGList.RefreshApplicants();
				break;
			end
		end
	end
end

function LFGListApplicationViewerRemove_OnClick()
	C_LFGList.RemoveListing();
end

function LFGListApplicationViewerEdit_OnClick()
	ShowEntryCreation(C_LFGList.GetActiveEntryInfo());
end

function LFGListApplicantInvite_OnClick(self)
	C_LFGList.InviteApplicant(self:GetParent().applicantID);
end

function LFGListApplicantDecline_OnClick(self)
	C_LFGList.DeclineApplicant(self:GetParent().applicantID);
end

function LFGListApplicant_OnEnter(self)
	local info = C_LFGList.GetApplicantInfo(self.applicantID);
	if not info then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 25, 0);
	GameTooltip:SetText(ClassColored(info.name, info.classID));
	GameTooltip:AddLine(string.format("Уровень %d, уровень предметов %d", info.level, info.itemLevel), 1, 1, 1);
	GameTooltip:AddLine(string.format("Рейтинг М+: %d", info.dungeonScore), 1, 1, 1);
	local roles = {};
	for _, role in ipairs(ROLE_ORDER) do
		if bit.band(info.roles, role) ~= 0 then
			table.insert(roles, ROLE_NAMES[role]);
		end
	end
	GameTooltip:AddLine("Роли: " .. table.concat(roles, ", "), 1, 1, 1);
	if info.comment ~= "" then
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine("\"" .. info.comment .. "\"", 0.75, 0.75, 0.75, true);
	end
	GameTooltip:Show();
end

---------------------------------------------------------------------------
-- the frame
---------------------------------------------------------------------------
local function OnLFGListEvent(event, ...)
	if not frame or not frame:IsShown() then
		return;
	end
	if event == "LFG_LIST_AVAILABILITY_UPDATE" then
		if frame.CategorySelection:IsShown() then
			UpdateCategorySelection();
		elseif frame.EntryCreation:IsShown() then
			UpdateCreationDropdowns();
		end
	elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
		if C_LFGList.HasActiveEntryInfo() then
			if not frame.EntryCreation:IsShown() or not editing then
				LFGListApplicationViewer_Show();
			end
		elseif frame.ApplicationViewer:IsShown() or (frame.EntryCreation:IsShown() and editing) then
			LFGListFrame_ShowCategorySelection();
		end
	elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
		if frame.SearchPanel:IsShown() then
			LFGListSearchPanel_UpdateResults();
		end
	elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
		if frame.ApplicationViewer:IsShown() then
			LFGListApplicationViewer_Show();
		end
	end
end

function LFGListFrame_OnLoad(self)
	frame = self;
	-- PVEFrame shows it as one of its sections, as is (no stock art to hide)
	self.isPlaceholder = true;

	for i = 1, NUM_RESULT_ROWS do
		local row = CreateFrame("Button", "LFGListSearchEntry" .. i, self.SearchPanel, "LFGListSearchEntryTemplate");
		row:SetPoint("TOPLEFT", self.SearchPanel.ScrollFrame, "TOPLEFT", 0, -(i - 1) * RESULT_HEIGHT);
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp");
		resultRows[i] = row;
	end
	for i = 1, NUM_APPLICANT_ROWS do
		local row = CreateFrame("Button", "LFGListApplicant" .. i, self.ApplicationViewer, "LFGListApplicantTemplate");
		row:SetPoint("TOPLEFT", self.ApplicationViewer.ScrollFrame, "TOPLEFT", 0, -(i - 1) * APPLICANT_HEIGHT);
		applicantRows[i] = row;
	end

	self.SearchPanel.SearchBox.Instructions:SetText(SEARCH or "Поиск");
	SetupFilterButton(self.SearchPanel.FilterButton);

	local creation = self.EntryCreation;
	SetupCreationDropdowns(creation);
	creation.Description.EditBox.Instructions:SetText("Подробности (необязательно)");
	creation.Name.onTextChanged = LFGListEntryCreation_UpdateValidState;
	creation.ItemLevel.Label:SetText("Минимальный уровень предметов");
	creation.Rating.Label:SetText("Минимальный рейтинг М+");
	creation.VoiceChat.Label:SetText("Голосовой чат");
	creation.VoiceChatBox.Instructions:SetText("Канал / сервер");
	creation.AutoAccept.Label:SetText("Автоматически принимать заявки");
	creation.PrivateGroup.Label:SetText("Частная группа (не видна в поиске)");
	creation.Name:SetScript("OnTabPressed", function() creation.Description.EditBox:SetFocus(); end);
	creation.Description.EditBox:SetScript("OnTabPressed", function() creation.Name:SetFocus(); end);

	LFGList_RegisterCallback(OnLFGListEvent);
	self:RegisterEvent("PARTY_MEMBERS_CHANGED");
	self:RegisterEvent("RAID_ROSTER_UPDATE");
	self:SetScript("OnEvent", function()
		if not self:IsShown() then
			return;
		end
		if self.CategorySelection:IsShown() then
			UpdateCategorySelection();
		elseif self.SearchPanel:IsShown() then
			LFGListSearchPanel_UpdateResults();
		elseif self.ApplicationViewer:IsShown() then
			LFGListApplicationViewer_Show();
		elseif self.EntryCreation:IsShown() then
			LFGListEntryCreation_UpdateValidState();
		end
	end);
end

function LFGListFrame_OnShow(self)
	LayerInset(self);
	C_LFGList.RequestAvailableActivities();
	if C_LFGList.HasActiveEntryInfo() then
		LFGListApplicationViewer_Show();
	elseif not (self.SearchPanel:IsShown() or self.EntryCreation:IsShown()) then
		LFGListFrame_ShowCategorySelection();
	end
end

function LFGListFrame_OnHide(self)
	LFGListApplicationDialog:Hide();
end

-- the timers: our applications, our listing
function LFGListFrame_OnUpdate(self, elapsed)
	self.timer = (self.timer or 0) + elapsed;
	if self.timer < 1 then
		return;
	end
	self.timer = 0;
	if self.SearchPanel:IsShown() then
		LFGListSearchPanel_UpdateResults();
	elseif self.ApplicationViewer:IsShown() then
		UpdateExpiration();
	end
end
