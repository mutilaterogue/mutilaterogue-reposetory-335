-- Premade Groups: C_LFGList (retail API) over AddonComm for the server's group finder (server/premade_groups.cpp).
--   C->S "LG_DATA", "LG_STATUS", "LG_CREATE"/"LG_UPDATE" : activity : itemLevel : autoAccept : private : name : comment,
--        "LG_DELIST", "LG_SEARCH" : category : filter, "LG_APPLY" : listing : roles : comment, "LG_CANCEL" : listing,
--        "LG_INVITE" / "LG_DECLINE" : applicant, "LG_SEEN", "LG_ANSWER" : listing : 1/0
--   S->C "LG_CATS", "LG_GROUPS", "LG_ACTS", "LG_ENTRY", "LG_APPS", "LG_APP", "LG_APPLICANTS", "LG_RESULTS", "LG_RESULT"
-- Free text is percent-encoded both ways. Roles: 1 tank, 2 healer, 4 damage.
-- The retail events (LFG_LIST_*) go through EventRegistry when it is there, and to LFGList_RegisterCallback listeners.

local ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE = 1, 2, 4;

local STATUS_NAMES = {
	[0] = "none", "applied", "invited", "failed", "cancelled", "declined", "declined_full", "declined_delisted",
	"timedout", "invitedeclined", "inviteaccepted",
};

local categories, categoryOrder = {}, {};
local groups, groupOrder = {}, {};
local activities, activityOrder = {}, {};
local entry;					-- our group's listing
local applications = {};		-- by listing id: { status, expires, roles }
local applicants, applicantOrder = {}, {};
local results, resultOrder = {}, {};
local resultCache = {};			-- every listing seen: the invite popup / chat messages need its name
local searching = false;

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function Encode(text)
	return (tostring(text or ""):gsub("[%%:,;%./|%c]", function(c) return string.format("%%%02X", c:byte()); end));
end

local function Decode(text)
	if not text or text == "-" then
		return "";
	end
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)); end));
end

local function Send(...)
	if Comm_Send then
		Comm_Send(...);
	end
end

local function Split(list)
	local out = {};
	if list and list ~= "-" and list ~= "" then
		for item in string.gmatch(list, "[^,]+") do
			table.insert(out, item);
		end
	end
	return out;
end

local listeners = {};

-- the UI's callback: func(event, ...)
function LFGList_RegisterCallback(func)
	table.insert(listeners, func);
end

local function Fire(event, ...)
	for _, func in ipairs(listeners) do
		func(event, ...);
	end
	if EventRegistry and EventRegistry.TriggerEvent then
		EventRegistry:TriggerEvent(event, ...);
	end
end

function LFGList_EncodeText(text)
	return Encode(text);
end

---------------------------------------------------------------------------
-- C_LFGList
---------------------------------------------------------------------------
C_LFGList = C_LFGList or {};

function C_LFGList.GetAvailableCategories()
	local out = {};
	for _, id in ipairs(categoryOrder) do
		table.insert(out, id);
	end
	return out;
end

function C_LFGList.GetLfgCategoryInfo(categoryID)
	local category = categories[categoryID];
	return category and { name = category.name, categoryID = categoryID, separateRecommended = false } or nil;
end

function C_LFGList.GetAvailableActivityGroups(categoryID)
	local out = {};
	for _, id in ipairs(groupOrder) do
		if groups[id].categoryID == categoryID then
			table.insert(out, id);
		end
	end
	return out;
end

function C_LFGList.GetActivityGroupInfo(groupID)
	local group = groups[groupID];
	return group and group.name;
end

-- groupID nil: every activity of the category; 0: the ones with no group
function C_LFGList.GetAvailableActivities(categoryID, groupID)
	local out = {};
	for _, id in ipairs(activityOrder) do
		local activity = activities[id];
		if (not categoryID or activity.categoryID == categoryID) and (groupID == nil or activity.groupFinderActivityGroupID == groupID) then
			table.insert(out, id);
		end
	end
	return out;
end

function C_LFGList.GetActivityInfoTable(activityID)
	return activities[activityID];
end

function C_LFGList.Search(categoryID, filter)
	searching = true;
	Send("LG_SEARCH", categoryID or 0, Encode(filter or ""));
end

function C_LFGList.IsSearching()
	return searching;
end

function C_LFGList.GetSearchResults()
	return #resultOrder, resultOrder;
end

function C_LFGList.GetSearchResultInfo(resultID)
	return results[resultID] or resultCache[resultID];
end

function C_LFGList.GetSearchResultMemberCounts(resultID)
	local result = results[resultID];
	if not result then
		return nil;
	end
	return { TANK = result.tanks, HEALER = result.healers, DAMAGER = result.damage, NOROLE = 0 };
end

-- status (retail strings), pendingStatus, seconds left, role
function C_LFGList.GetApplicationInfo(resultID)
	local app = applications[resultID];
	if not app then
		return resultID, "none", nil, 0, nil;
	end
	return resultID, STATUS_NAMES[app.status] or "none", nil, math.max(0, app.expires - GetTime()), app.roles;
end

function C_LFGList.GetApplications()
	local out = {};
	for id in pairs(applications) do
		table.insert(out, id);
	end
	return out;
end

function C_LFGList.GetNumApplications()
	local applied, invited = 0, 0;
	for _, app in pairs(applications) do
		if app.status == 2 then
			invited = invited + 1;
		else
			applied = applied + 1;
		end
	end
	return applied, invited;
end

function C_LFGList.ApplyToGroup(resultID, comment, tank, healer, damage)
	local roles = (tank and ROLE_TANK or 0) + (healer and ROLE_HEALER or 0) + (damage and ROLE_DAMAGE or 0);
	Send("LG_APPLY", resultID, roles, Encode(comment or ""));
end

function C_LFGList.CancelApplication(resultID)
	Send("LG_CANCEL", resultID);
end

function C_LFGList.AcceptInvite(resultID)
	Send("LG_ANSWER", resultID, 1);
end

function C_LFGList.DeclineInvite(resultID)
	Send("LG_ANSWER", resultID, 0);
end

local function ListingArgs(info)
	return info.activityID or 0, tonumber(info.itemLevel) or 0, info.autoAccept and 1 or 0, info.privateGroup and 1 or 0,
		Encode(info.name or ""), Encode(info.comment or ""), Encode(info.voiceChat or ""), tonumber(info.minRating) or 0;
end

-- info: { activityID, name, comment, itemLevel, autoAccept, privateGroup, voiceChat, minRating }
-- (a mythic+ activity: the name may be empty - the server names it "+level dungeon" after the leader's keystone)
function C_LFGList.CreateListing(info)
	Send("LG_CREATE", ListingArgs(info));
end

function C_LFGList.UpdateListing(info)
	Send("LG_UPDATE", ListingArgs(info));
end

function C_LFGList.RemoveListing()
	Send("LG_DELIST");
end

function C_LFGList.HasActiveEntryInfo()
	return entry ~= nil;
end

function C_LFGList.GetActiveEntryInfo()
	return entry;
end

function C_LFGList.GetApplicants()
	local out = {};
	for _, id in ipairs(applicantOrder) do
		table.insert(out, id);
	end
	return out;
end

function C_LFGList.GetApplicantInfo(applicantID)
	return applicants[applicantID];
end

function C_LFGList.InviteApplicant(applicantID)
	Send("LG_INVITE", applicantID);
end

function C_LFGList.DeclineApplicant(applicantID)
	Send("LG_DECLINE", applicantID);
end

-- the leader saw the new applicants
function C_LFGList.RefreshApplicants()
	Send("LG_SEEN");
end

function C_LFGList.RequestAvailableActivities()
	Send("LG_DATA");
	Send("LG_STATUS");
end

---------------------------------------------------------------------------
-- the invite and the status messages
---------------------------------------------------------------------------
local STATUS_MESSAGES = {
	[3] = "Не удалось вступить в группу «%s».",
	[5] = "Ваша заявка в группу «%s» отклонена.",
	[6] = "Группа «%s» уже заполнена.",
	[7] = "Группа «%s» снята из списка.",
	[8] = "Время ожидания заявки в группу «%s» истекло.",
};

local function GroupName(resultID)
	local result = resultCache[resultID];
	return result and result.name or "?";
end

StaticPopupDialogs["LFG_LIST_INVITE"] = {
	text = "Вас приглашают в группу «%s».\nРоль: %s",
	button1 = ACCEPT,
	button2 = DECLINE,
	OnAccept = function(self, data)
		C_LFGList.AcceptInvite(data);
	end,
	OnCancel = function(self, data, reason)
		if reason == "clicked" then
			C_LFGList.DeclineInvite(data);
		end
	end,
	timeout = 60,
	whileDead = 1,
	hideOnEscape = 1,
	showAlert = 1,
};

local function RoleText(roles)
	local names = {};
	if bit.band(roles, ROLE_TANK) ~= 0 then table.insert(names, TANK or "Танк"); end
	if bit.band(roles, ROLE_HEALER) ~= 0 then table.insert(names, HEALER or "Лекарь"); end
	if bit.band(roles, ROLE_DAMAGE) ~= 0 then table.insert(names, DAMAGER or "Боец"); end
	return table.concat(names, ", ");
end

local function SetApplication(listingID, status, seconds, roles)
	local old = applications[listingID];
	local oldStatus = old and old.status or 0;
	if status == 1 or status == 2 then
		applications[listingID] = { status = status, expires = GetTime() + seconds, roles = roles };
	else
		applications[listingID] = nil;
	end
	if results[listingID] then
		results[listingID].applicationStatus = status;
	end
	if status == oldStatus then
		return;
	end
	if status == 2 then
		local dialog = StaticPopup_Show("LFG_LIST_INVITE", GroupName(listingID), RoleText(roles));
		if dialog then
			dialog.data = listingID;
		end
		PlaySound("ReadyCheck");
	elseif oldStatus == 2 then
		StaticPopup_Hide("LFG_LIST_INVITE");
	end
	if STATUS_MESSAGES[status] then
		DEFAULT_CHAT_FRAME:AddMessage(string.format(STATUS_MESSAGES[status], GroupName(listingID)), 1, 0.82, 0);
	end
	Fire("LFG_LIST_APPLICATION_STATUS_UPDATED", listingID, STATUS_NAMES[status], STATUS_NAMES[oldStatus], GroupName(listingID));
end

-- for the queue status eye (QueueStatus.lua)
function LFGList_GetQueueInfo()
	local applied, invited = C_LFGList.GetNumApplications();
	return { listed = entry, applied = applied, invited = invited, numApplicants = #applicantOrder };
end

---------------------------------------------------------------------------
-- comm
---------------------------------------------------------------------------
local function RegisterComm()
	Comm_Register("LG_CATS", function(list)
		if not list then return; end
		wipe(categories); wipe(categoryOrder);
		for _, item in ipairs(Split(list)) do
			local id, name = strsplit(";", item);
			id = tonumber(id);
			categories[id] = { name = Decode(name) };
			table.insert(categoryOrder, id);
		end
		Fire("LFG_LIST_AVAILABILITY_UPDATE");
	end);

	Comm_Register("LG_GROUPS", function(list)
		if not list then return; end
		wipe(groups); wipe(groupOrder);
		for _, item in ipairs(Split(list)) do
			local id, categoryID, name = strsplit(";", item);
			id = tonumber(id);
			groups[id] = { categoryID = tonumber(categoryID), name = Decode(name) };
			table.insert(groupOrder, id);
		end
		Fire("LFG_LIST_AVAILABILITY_UPDATE");
	end);

	Comm_Register("LG_ACTS", function(list)
		if not list then return; end
		wipe(activities); wipe(activityOrder);
		for _, item in ipairs(Split(list)) do
			local id, categoryID, groupID, name, shortName, minLevel, maxPlayers, itemLevel, mapID, difficulty = strsplit(";", item);
			id = tonumber(id);
			activities[id] = {
				activityID = id, categoryID = tonumber(categoryID), groupFinderActivityGroupID = tonumber(groupID) or 0,
				fullName = Decode(name), shortName = Decode(shortName), minLevel = tonumber(minLevel) or 1,
				maxNumPlayers = tonumber(maxPlayers) or 5, ilvlSuggestion = tonumber(itemLevel) or 0,
				mapID = tonumber(mapID) or 0, difficultyID = tonumber(difficulty) or 0,
			};
			table.insert(activityOrder, id);
		end
		Fire("LFG_LIST_AVAILABILITY_UPDATE");
	end);

	Comm_Register("LG_ENTRY", function(id, activityID, itemLevel, autoAccept, private, name, comment, seconds, voiceChat, minRating, keyLevel)
		if not id then return; end
		id = tonumber(id) or 0;
		if id == 0 then
			entry = nil;
		else
			entry = {
				listingID = id, activityID = tonumber(activityID), requiredItemLevel = tonumber(itemLevel) or 0,
				autoAccept = autoAccept == "1", privateGroup = private == "1", name = Decode(name), comment = Decode(comment),
				duration = tonumber(seconds) or 0, expires = GetTime() + (tonumber(seconds) or 0),
				voiceChat = Decode(voiceChat), requiredDungeonScore = tonumber(minRating) or 0, keyLevel = tonumber(keyLevel) or 0,
			};
		end
		Fire("LFG_LIST_ACTIVE_ENTRY_UPDATE", entry ~= nil);
		if QueueStatus_Update then QueueStatus_Update(); end
	end);

	Comm_Register("LG_APPS", function(list)
		if not list then return; end
		local seen = {};
		for _, item in ipairs(Split(list)) do
			local listingID, status, seconds, roles = strsplit(";", item);
			listingID = tonumber(listingID);
			seen[listingID] = true;
			SetApplication(listingID, tonumber(status) or 0, tonumber(seconds) or 0, tonumber(roles) or 0);
		end
		for listingID in pairs(applications) do
			if not seen[listingID] then
				applications[listingID] = nil;
			end
		end
		Fire("LFG_LIST_APPLICATION_STATUS_UPDATED");
		if QueueStatus_Update then QueueStatus_Update(); end
	end);

	Comm_Register("LG_APP", function(listingID, status, seconds, roles)
		if not listingID then return; end
		SetApplication(tonumber(listingID), tonumber(status) or 0, tonumber(seconds) or 0, tonumber(roles) or 0);
		if QueueStatus_Update then QueueStatus_Update(); end
	end);

	Comm_Register("LG_APPLICANTS", function(list)
		if not list then return; end
		local hadNew = false;
		for _, applicant in pairs(applicants) do
			hadNew = hadNew or applicant.isNew;
		end
		wipe(applicants); wipe(applicantOrder);
		local hasNew = false;
		for _, item in ipairs(Split(list)) do
			local id, name, class, level, itemLevel, roles, status, comment, isNew, rating = strsplit(";", item);
			id = tonumber(id);
			applicants[id] = {
				applicantID = id, name = Decode(name), classID = tonumber(class) or 0, level = tonumber(level) or 0,
				itemLevel = tonumber(itemLevel) or 0, roles = tonumber(roles) or 0, status = tonumber(status) or 1,
				applicationStatus = STATUS_NAMES[tonumber(status) or 1], comment = Decode(comment), isNew = isNew == "1",
				dungeonScore = tonumber(rating) or 0,
			};
			hasNew = hasNew or applicants[id].isNew;
			table.insert(applicantOrder, id);
		end
		if hasNew and not hadNew then
			PlaySound("ReadyCheck");
		end
		Fire("LFG_LIST_APPLICANT_LIST_UPDATED", hasNew);
		if QueueStatus_Update then QueueStatus_Update(); end
	end);

	Comm_Register("LG_RESULTS", function(list)
		if not list then return; end
		searching = false;
		wipe(results); wipe(resultOrder);
		for _, item in ipairs(Split(list)) do
			local id, activityID, leaderName, leaderClass, name, comment, itemLevel, age, autoAccept, numMembers,
				tanks, healers, damage, myStatus, members, keyLevel, leaderRating, minRating, voiceChat = strsplit(";", item);
			id = tonumber(id);
			local result = {
				searchResultID = id, activityID = tonumber(activityID), leaderName = Decode(leaderName),
				leaderClassID = tonumber(leaderClass) or 0, name = Decode(name), comment = Decode(comment),
				requiredItemLevel = tonumber(itemLevel) or 0, age = tonumber(age) or 0, ageTime = GetTime(),
				autoAccept = autoAccept == "1", numMembers = tonumber(numMembers) or 0,
				tanks = tonumber(tanks) or 0, healers = tonumber(healers) or 0, damage = tonumber(damage) or 0,
				applicationStatus = tonumber(myStatus) or 0, members = {},
				keyLevel = tonumber(keyLevel) or 0, leaderOverallDungeonScore = tonumber(leaderRating) or 0,
				requiredDungeonScore = tonumber(minRating) or 0, voiceChat = voiceChat == "1",
			};
			if members and members ~= "-" then
				for member in string.gmatch(members, "[^/]+") do
					local class, role, isLeader = strsplit(".", member);
					table.insert(result.members, { classID = tonumber(class) or 0, role = tonumber(role) or ROLE_DAMAGE, isLeader = isLeader == "1" });
				end
			end
			results[id] = result;
			resultCache[id] = result;
			table.insert(resultOrder, id);
		end
		Fire("LFG_LIST_SEARCH_RESULTS_RECEIVED");
	end);

	Comm_Register("LG_RESULT", function(text)
		if text and text ~= "" then
			UIErrorsFrame:AddMessage(Decode(text), 1, 0.1, 0.1);
			Fire("LFG_LIST_ERROR", Decode(text));
		end
	end);
end

local commFrame = CreateFrame("Frame");
commFrame:RegisterEvent("PLAYER_LOGIN");
commFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN");
	if Comm_Register then
		RegisterComm();
	end
	C_LFGList.RequestAvailableActivities();
end);
