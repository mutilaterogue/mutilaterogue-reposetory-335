-- Premade Groups window (LFGListFrame.xml), retail LFGListFrame on 3.3.5 over C_LFGList (LFGList.lua):
--   CategorySelection - the categories, "Find Group" / "Start Group";
--   SearchPanel       - the listed groups of the category, the sign up dialog (LFGListApplicationDialog);
--   EntryCreation     - list our group (or change its listing);
--   ApplicationViewer - our listed group and its applicants (invite / decline).

local NUM_RESULT_ROWS, RESULT_HEIGHT = 8, 36;
local NUM_APPLICANT_ROWS, APPLICANT_HEIGHT = 6, 34;
local ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE = 1, 2, 4;

-- the retail art of a category (groupfinder-button-* / groupfinder-background-*)
local CATEGORY_ART = { [1] = "questing", [2] = "dungeons", [3] = "raids-legion", [4] = "arenas", [6] = "custom-pve" };

local CLASS_FILES = {
	[1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [6] = "DEATHKNIGHT",
	[7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
};

local ROLE_ATLAS = {
	[ROLE_TANK] = "groupfinder-icon-role-large-tank",
	[ROLE_HEALER] = "groupfinder-icon-role-large-heal",
	[ROLE_DAMAGE] = "groupfinder-icon-role-large-dps",
};

local frame;
local selectedCategory;
local selectedResult;
local editing = false;			-- EntryCreation changes our listing
local creationGroup, creationActivity;
local dialogRoles = { [ROLE_DAMAGE] = true };
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

local function ActivityName(activityID)
	local activity = activityID and C_LFGList.GetActivityInfoTable(activityID);
	return activity and activity.fullName or "";
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
function LFGList_AddHighlight(self, atlas, width, height)
	local highlight = self:CreateTexture(nil, "HIGHLIGHT");
	if width then
		highlight:SetSize(width, height);
		highlight:SetPoint("CENTER");
	else
		highlight:SetAllPoints();
	end
	highlight:SetAtlas(atlas);
	highlight:SetBlendMode("ADD");
end

function LFGListEditBox_OnTextChanged(self)
	if self.Instructions then
		self.Instructions:SetShown(self:GetText() == "");
	end
	if self.onTextChanged then
		self.onTextChanged(self);
	end
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
	local panel = frame.SearchPanel;
	C_LFGList.Search(selectedCategory, panel.SearchBox:GetText());
	LFGListSearchPanel_UpdateResults();
end

function LFGListSearchPanelSearchBox_OnEnterPressed(self)
	self:ClearFocus();
	LFGListSearchPanel_DoSearch();
end

local function UpdateRoleCount(roleFrame, atlas, count)
	roleFrame.Icon:SetAtlas(atlas);
	roleFrame.Count:SetText(count);
	roleFrame.Icon:SetDesaturated(count == 0);
end

function LFGListSearchPanel_UpdateResults()
	local panel = frame.SearchPanel;
	local count, ids = C_LFGList.GetSearchResults();
	local searching = C_LFGList.IsSearching();
	panel.Searching:SetShown(searching and count == 0);
	panel.NoResults:SetShown(not searching and count == 0);

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
			row.Name:SetText(info.name);
			if applied or invited then
				row.Name:SetTextColor(0.1, 1, 0.1);
			else
				row.Name:SetTextColor(1, 0.82, 0);
			end
			row.ActivityName:SetText(ActivityName(info.activityID));
			row.PendingLabel:SetShown(applied or invited);
			row.PendingLabel:SetText(invited and "Приглашение" or "В ожидании");
			row.ExpirationTime:SetShown(applied or invited);
			row.ExpirationTime:SetText(FormatTime(secondsLeft));
			row.CancelButton:SetShown(applied);
			row.ResultBG:SetShown(applied or invited);
			row.ResultBG:SetAtlas(invited and "groupfinder-highlightbar-yellow" or "groupfinder-highlightbar-green");
			row.ResultBG:SetAlpha(0.4);
			-- the role counts give way to the status
			row.Tank:SetShown(not (applied or invited));
			row.Healer:SetShown(not (applied or invited));
			row.Damager:SetShown(not (applied or invited));
			UpdateRoleCount(row.Tank, "groupfinder-icon-role-micro-tank", info.tanks);
			UpdateRoleCount(row.Healer, "groupfinder-icon-role-micro-heal", info.healers);
			UpdateRoleCount(row.Damager, "groupfinder-icon-role-micro-dps", info.damage);
			row.Selected:SetShown(id == selectedResult);
			row:Show();
		else
			row:Hide();
		end
	end

	-- "Sign Up": a group chosen, not applied to yet, and no group of our own
	local _, status = C_LFGList.GetApplicationInfo(selectedResult or 0);
	panel.SignUpButton:SetEnabled(selectedResult ~= nil and status == "none" and not InGroup());
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
	if info.requiredItemLevel > 0 then
		GameTooltip:AddLine(string.format("Мин. уровень предметов: %d", info.requiredItemLevel), 1, 1, 1);
	end
	if info.leaderName ~= "" then
		GameTooltip:AddLine("Лидер: " .. ClassColored(info.leaderName, info.leaderClassID), 1, 1, 1);
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
	for role, key in pairs({ [ROLE_TANK] = "Tank", [ROLE_HEALER] = "Healer", [ROLE_DAMAGE] = "Damager" }) do
		dialog[key].CheckButton:SetChecked(dialogRoles[role]);
	end
	dialog.SignUpButton:SetEnabled((dialogRoles[ROLE_TANK] or dialogRoles[ROLE_HEALER] or dialogRoles[ROLE_DAMAGE]) and true or false);
end

function LFGListApplicationDialogRole_OnClick(self)
	dialogRoles[self:GetParent().role] = self:GetChecked() and true or nil;
	UpdateApplicationDialog();
end

function LFGListSearchPanelSignUp_OnClick()
	local info = selectedResult and C_LFGList.GetSearchResultInfo(selectedResult);
	if not info then
		return;
	end
	local dialog = LFGListApplicationDialog;
	dialog.resultID = selectedResult;
	dialog.GroupName:SetText(info.name);
	dialog.Description:SetText("");
	UpdateApplicationDialog();
	dialog:Show();
end

function LFGListApplicationDialogSignUp_OnClick(self)
	local dialog = self:GetParent();
	C_LFGList.ApplyToGroup(dialog.resultID, dialog.Description:GetText(),
		dialogRoles[ROLE_TANK], dialogRoles[ROLE_HEALER], dialogRoles[ROLE_DAMAGE]);
	dialog:Hide();
end

---------------------------------------------------------------------------
-- the group creation
---------------------------------------------------------------------------
local function FirstActivity(categoryID, groupID)
	return C_LFGList.GetAvailableActivities(categoryID, groupID)[1];
end

function LFGListEntryCreation_UpdateValidState()
	local panel = frame.EntryCreation;
	local name = panel.Name:GetText();
	panel.ItemLevelBox:SetShown(panel.ItemLevel:GetChecked() and true or false);
	panel.ListGroupButton:SetEnabled(creationActivity ~= nil and name ~= "" and CanManageGroup());
end

local function UpdateCreationDropDowns()
	local panel = frame.EntryCreation;
	local groups = C_LFGList.GetAvailableActivityGroups(selectedCategory);
	panel.GroupDropDown:SetShown(#groups > 0);
	if #groups > 0 then
		UIDropDownMenu_SetText(panel.GroupDropDown, creationGroup and C_LFGList.GetActivityGroupInfo(creationGroup) or "");
	end
	local activity = creationActivity and C_LFGList.GetActivityInfoTable(creationActivity);
	UIDropDownMenu_SetText(panel.ActivityDropDown, activity and (#groups > 0 and activity.shortName or activity.fullName) or "");
	if activity and activity.ilvlSuggestion > 0 then
		panel.ItemLevel.Label:SetText(string.format("Мин. уровень предметов (реком. %d)", activity.ilvlSuggestion));
	else
		panel.ItemLevel.Label:SetText("Минимальный уровень предметов");
	end
	LFGListEntryCreation_UpdateValidState();
end

local function GroupDropDown_Initialize()
	for _, groupID in ipairs(C_LFGList.GetAvailableActivityGroups(selectedCategory)) do
		local info = UIDropDownMenu_CreateInfo();
		info.text = C_LFGList.GetActivityGroupInfo(groupID);
		info.checked = groupID == creationGroup;
		info.func = function()
			creationGroup = groupID;
			creationActivity = FirstActivity(selectedCategory, groupID);
			UpdateCreationDropDowns();
		end;
		UIDropDownMenu_AddButton(info);
	end
end

local function ActivityDropDown_Initialize()
	local hasGroups = #C_LFGList.GetAvailableActivityGroups(selectedCategory) > 0;
	for _, activityID in ipairs(C_LFGList.GetAvailableActivities(selectedCategory, hasGroups and creationGroup or 0)) do
		local activity = C_LFGList.GetActivityInfoTable(activityID);
		local info = UIDropDownMenu_CreateInfo();
		info.text = hasGroups and activity.shortName or activity.fullName;
		info.checked = activityID == creationActivity;
		if UnitLevel("player") < activity.minLevel then
			info.disabled = true;
			info.text = info.text .. string.format(" (%d+)", activity.minLevel);
		end
		info.func = function()
			creationActivity = activityID;
			UpdateCreationDropDowns();
		end;
		UIDropDownMenu_AddButton(info);
	end
end

-- an empty form for the category, or our listing to change
local function ShowEntryCreation(entry)
	local panel = frame.EntryCreation;
	editing = entry ~= nil;
	if entry then
		local activity = C_LFGList.GetActivityInfoTable(entry.activityID);
		selectedCategory = activity and activity.categoryID or selectedCategory;
		creationActivity = entry.activityID;
		creationGroup = activity and activity.groupFinderActivityGroupID ~= 0 and activity.groupFinderActivityGroupID or nil;
		panel.Name:SetText(entry.name);
		panel.Description:SetText(entry.comment);
		panel.ItemLevel:SetChecked(entry.requiredItemLevel > 0);
		panel.ItemLevelBox:SetText(entry.requiredItemLevel > 0 and entry.requiredItemLevel or "");
		panel.AutoAccept:SetChecked(entry.autoAccept);
		panel.PrivateGroup:SetChecked(entry.privateGroup);
		panel.ListGroupButton:SetText("Применить");
	else
		creationGroup = C_LFGList.GetAvailableActivityGroups(selectedCategory)[1];
		creationActivity = FirstActivity(selectedCategory, creationGroup or 0);
		panel.Name:SetText("");
		panel.Description:SetText("");
		panel.ItemLevel:SetChecked(false);
		panel.ItemLevelBox:SetText("");
		panel.AutoAccept:SetChecked(false);
		panel.PrivateGroup:SetChecked(false);
		panel.ListGroupButton:SetText("Внести в список");
	end
	local info = C_LFGList.GetLfgCategoryInfo(selectedCategory);
	panel.Label:SetText(info and info.name or "");
	ShowPanel(panel);
	UpdateCreationDropDowns();
end

function LFGListCategorySelectionStartGroup_OnClick()
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
	local info = {
		activityID = creationActivity,
		name = panel.Name:GetText(),
		comment = panel.Description:GetText(),
		itemLevel = panel.ItemLevel:GetChecked() and (tonumber(panel.ItemLevelBox:GetText()) or 0) or 0,
		autoAccept = panel.AutoAccept:GetChecked() and true or false,
		privateGroup = panel.PrivateGroup:GetChecked() and true or false,
	};
	panel.Name:ClearFocus();
	panel.Description:ClearFocus();
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
			row.Info:SetText(string.format("%d ур., %d предм.", info.level, info.itemLevel));
			local index = 1;
			for _, role in ipairs({ ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE }) do
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

function LFGListApplicationViewer_Show()
	local panel = frame.ApplicationViewer;
	local entry = C_LFGList.GetActiveEntryInfo();
	if not entry then
		LFGListFrame_ShowCategorySelection();
		return;
	end
	local activity = C_LFGList.GetActivityInfoTable(entry.activityID);
	panel.InfoBackground:SetAtlas("groupfinder-background-" .. (CATEGORY_ART[activity and activity.categoryID or 6] or "custom-pve"));
	panel.EntryName:SetText(entry.name);
	panel.ActivityName:SetText(activity and activity.fullName or "");
	panel.Description:SetText(entry.comment);
	panel.ItemLevel:SetText(entry.requiredItemLevel > 0 and string.format("Уровень предметов: %d", entry.requiredItemLevel) or "");
	panel.AutoAcceptText:SetShown(entry.autoAccept);
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
			UpdateCreationDropDowns();
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

	local search = self.SearchPanel.SearchBox;
	search.Instructions:SetText(SEARCH or "Поиск");

	local creation = self.EntryCreation;
	UIDropDownMenu_SetWidth(creation.GroupDropDown, 260);
	UIDropDownMenu_Initialize(creation.GroupDropDown, GroupDropDown_Initialize);
	UIDropDownMenu_SetWidth(creation.ActivityDropDown, 260);
	UIDropDownMenu_Initialize(creation.ActivityDropDown, ActivityDropDown_Initialize);
	creation.Name.Instructions:SetText("Название группы (обязательно)");
	creation.Description.Instructions:SetText("Подробности (необязательно)");
	creation.Name.onTextChanged = LFGListEntryCreation_UpdateValidState;
	creation.ItemLevel.Label:SetText("Минимальный уровень предметов");
	creation.AutoAccept.Label:SetText("Автоматически принимать заявки");
	creation.PrivateGroup.Label:SetText("Частная группа (не видна в поиске)");
	creation.Name:SetScript("OnTabPressed", function() creation.Description:SetFocus(); end);
	creation.Description:SetScript("OnTabPressed", function() creation.Name:SetFocus(); end);


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

-- the sign up dialog is made after LFGListFrame (LFGListFrame.xml): its own OnLoad
function LFGListApplicationDialog_OnLoad(self)
	tinsert(UISpecialFrames, self:GetName());
	local dialog = self;
	for role, key in pairs({ [ROLE_TANK] = "Tank", [ROLE_HEALER] = "Healer", [ROLE_DAMAGE] = "Damager" }) do
		dialog[key].role = role;
		dialog[key].roleName = role == ROLE_TANK and (TANK or "Танк") or role == ROLE_HEALER and (HEALER or "Лекарь") or (DAMAGER or "Боец");
		dialog[key].Icon:SetAtlas(ROLE_ATLAS[role]);
	end
	dialog.Description.Instructions:SetText("Комментарий (необязательно)");
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

-- the application timers
function LFGListFrame_OnUpdate(self, elapsed)
	self.timer = (self.timer or 0) + elapsed;
	if self.timer < 1 then
		return;
	end
	self.timer = 0;
	if self.SearchPanel:IsShown() then
		LFGListSearchPanel_UpdateResults();
	end
end
