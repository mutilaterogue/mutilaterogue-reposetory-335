-- Raid Finder (RaidFinder.xml) - the client of the server's raid queue (server/raid_finder.cpp, AddonComm):
--   C->S "RF_LIST", "RF_JOIN" : raidId : roles, "RF_LEAVE", "RF_ANSWER" : 1/0, "RF_STATUS"
--   S->C "RF_LIST", "RF_STATUS", "RF_PROPOSAL", "RF_RESULT"
-- Roles as the server's bit mask: 1 tank, 2 healer, 4 damage.

local ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE = 1, 2, 4;
-- the stock role button ids: 1 damage, 2 tank, 3 healer
local ROLE_BY_ID = { [1] = ROLE_DAMAGE, [2] = ROLE_TANK, [3] = ROLE_HEALER };
local ROLE_NAME_BY_ID = { [1] = "DAMAGER", [2] = "TANK", [3] = "HEALER" };

local DIFFICULTY_NAMES = {
	[0] = "10 игроков",
	[1] = "25 игроков",
	[2] = "10 игроков (героич.)",
	[3] = "25 игроков (героич.)",
};

local STATE_NONE, STATE_QUEUED, STATE_PROPOSAL, STATE_IN_RAID = 0, 1, 2, 3;

local raids = {};			-- { id, name, mapId, difficulty, size, minLevel, minItemLevel, saved }
local selectedRaid;
local status = { state = STATE_NONE };
local statusTime;			-- GetTime() of the last status: the queue timer counts on from it
local proposal;
local checkedRoles = { [1] = true };	-- by button id, damage by default

local function Send(...)
	if Comm_Send then
		Comm_Send(...);
	end
end

local function FindRaid(id)
	for _, raid in ipairs(raids) do
		if raid.id == id then
			return raid;
		end
	end
end

local function GetRoles()
	local roles = 0;
	for id, role in pairs(ROLE_BY_ID) do
		if checkedRoles[id] then
			roles = roles + role;
		end
	end
	return roles;
end

local function FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds));
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60);
end

-- for the player frame menu (PlayerFrameMenu.lua): in the raid finder's raid / leave it
function RaidFinder_IsInRaid()
	return status.state == STATE_IN_RAID;
end

function RaidFinder_LeaveRaid()
	Send("RF_LEAVE_RAID");
end

---------------------------------------------------------------------------
-- the frame
---------------------------------------------------------------------------
local function UpdateInfo()
	local frame = RaidFinderFrame;
	local info = frame.Info;
	local raid = selectedRaid and FindRaid(selectedRaid);
	if not raid then
		info.Title:SetText("Поиск рейда");
		info.Description:SetText(#raids == 0 and "Нет доступных рейдов." or "Выберите рейд.");
	else
		info.Title:SetText(raid.name);
		local lines = { DIFFICULTY_NAMES[raid.difficulty] or "" };
		table.insert(lines, "Требуемый уровень: " .. raid.minLevel);
		if raid.minItemLevel > 0 then
			table.insert(lines, "Требуемый уровень предметов: " .. raid.minItemLevel);
		end
		if raid.saved then
			table.insert(lines, "|cffff2020Вы уже сохранены в этом рейде.|r");
		end
		info.Description:SetText(table.concat(lines, "\n"));
	end

	if status.state == STATE_NONE then
		info.QueueTitle:SetText("");
		info.Queue:SetText("");
	elseif status.state == STATE_IN_RAID then
		local inRaid = FindRaid(status.raidId);
		info.QueueTitle:SetText("Вы в рейде");
		info.Queue:SetText(inRaid and inRaid.name or "");
	else
		local queuedRaid = FindRaid(status.raidId);
		info.QueueTitle:SetText(status.state == STATE_PROPOSAL and "Рейд собран" or "В очереди");
		local elapsed = status.seconds + (statusTime and (GetTime() - statusTime) or 0);
		info.Queue:SetText(string.format("%s\nВремя в очереди: %s\nТанки: %d / %d\nЛекари: %d / %d\nБойцы: %d / %d",
			queuedRaid and queuedRaid.name or "", FormatTime(elapsed),
			status.tanks, status.tanksNeeded, status.healers, status.healersNeeded, status.damage, status.damageNeeded));
	end
end

local function UpdateButtons()
	local frame = RaidFinderFrame;
	local queued = status.state ~= STATE_NONE;
	frame.FindGroupButton:SetText(status.state == STATE_IN_RAID and "Покинуть рейд" or (queued and LEAVE_QUEUE or FIND_A_GROUP));
	local raid = selectedRaid and FindRaid(selectedRaid);
	if queued or (raid and not raid.saved and GetRoles() > 0) then
		frame.FindGroupButton:Enable();
	else
		frame.FindGroupButton:Disable();
	end
	UIDropDownMenu_SetText(frame.RaidDropDown, raid and raid.name or "");
	-- the queue is fixed while in it
	if queued then
		UIDropDownMenu_DisableDropDown(frame.RaidDropDown);
	else
		UIDropDownMenu_EnableDropDown(frame.RaidDropDown);
	end
end

local function UpdateRoleButtons()
	local canTank, canHeal, canDamage = true, true, true;
	if GetAvailableRoles then
		canTank, canHeal, canDamage = GetAvailableRoles();
	end
	local can = { [1] = canDamage, [2] = canTank, [3] = canHeal };
	local queued = status.state ~= STATE_NONE;
	for _, button in ipairs({ RaidFinderFrame.RoleTank, RaidFinderFrame.RoleHealer, RaidFinderFrame.RoleDamage }) do
		local id = button:GetID();
		if not can[id] then
			checkedRoles[id] = nil;
			LFG_PermanentlyDisableRoleButton(button);
		elseif queued then
			LFG_DisableRoleButton(button);
		else
			LFG_EnableRoleButton(button);
		end
		button.checkButton:SetChecked(checkedRoles[id] and true or false);
	end
end

local function Update()
	if not RaidFinderFrame:IsShown() then
		return;
	end
	UpdateRoleButtons();
	UpdateButtons();
	UpdateInfo();
end

function RaidFinderRoleButton_OnLoad(self)
	local role = ROLE_NAME_BY_ID[self:GetID()];
	self:GetNormalTexture():SetTexCoord(GetTexCoordsForRole(role));
	if self.background and GetBackgroundTexCoordsForRole then
		self.background:SetTexCoord(GetBackgroundTexCoordsForRole(role));
	end
	self.checkButton.onClick = function(check)
		checkedRoles[self:GetID()] = check:GetChecked() and true or nil;
		UpdateButtons();
	end;
end

local function RaidDropDown_Initialize()
	local info = UIDropDownMenu_CreateInfo();
	for _, raid in ipairs(raids) do
		info.text = raid.name .. " (" .. (DIFFICULTY_NAMES[raid.difficulty] or "") .. ")";
		info.value = raid.id;
		info.checked = raid.id == selectedRaid;
		info.disabled = raid.saved;
		info.func = function(button)
			selectedRaid = button.value;
			Update();
		end;
		UIDropDownMenu_AddButton(info);
	end
end

function RaidFinderFrame_OnLoad(self)
	-- PVEFrame shows it as one of its sections, as is (no stock art to hide)
	self.isPlaceholder = true;
	UIDropDownMenu_SetWidth(self.RaidDropDown, 180);
	UIDropDownMenu_Initialize(self.RaidDropDown, RaidDropDown_Initialize);
	self.Info.Description:SetWidth(290);
	self.Info.Queue:SetWidth(290);
	-- the dark inset: light text, gold headers (retail)
	self.Info.Title:SetTextColor(1, 0.82, 0);
	self.Info.QueueTitle:SetTextColor(1, 0.82, 0);
	self.Info.Description:SetTextColor(1, 1, 1);
	self.Info.Queue:SetTextColor(1, 1, 1);
end

-- the dark inset (as the dungeon finder's, made the same way): under the content, its level set on every show,
-- PVEFrame changes this frame's level when it takes it in
local function LayerInset(self)
	if not self.Inset then
		self.Inset = CreateFrame("Frame", "RaidFinderFrameInset", self, "InsetFrameTemplate");
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

function RaidFinderFrame_OnShow(self)
	LayerInset(self);
	Send("RF_LIST");
	Send("RF_STATUS");
	Update();
	-- the queue timer
	self.elapsed = 0;
	self:SetScript("OnUpdate", function(frame, elapsed)
		frame.elapsed = frame.elapsed + elapsed;
		if frame.elapsed >= 1 then
			frame.elapsed = 0;
			if status.state == STATE_QUEUED or status.state == STATE_PROPOSAL then
				UpdateInfo();
			end
		end
	end);
end

function RaidFinderFrame_OnHide(self)
	self:SetScript("OnUpdate", nil);
end

function RaidFinderFindGroupButton_OnClick(self)
	if status.state == STATE_IN_RAID then
		Send("RF_LEAVE_RAID");
	elseif status.state ~= STATE_NONE then
		Send("RF_LEAVE");
	elseif selectedRaid then
		Send("RF_JOIN", selectedRaid, GetRoles());
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
end

---------------------------------------------------------------------------
-- the proposal: "the raid is ready", accept / decline with a timer
---------------------------------------------------------------------------
StaticPopupDialogs["RAID_FINDER_PROPOSAL"] = {
	text = "%s",
	button1 = ACCEPT,
	button2 = DECLINE,
	OnAccept = function()
		Send("RF_ANSWER", 1);
	end,
	OnCancel = function(self, data, reason)
		-- timed out on the client: the server decides at its own timeout
		if reason ~= "timeout" then
			Send("RF_ANSWER", 0);
		end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
	showAlert = 1,
};

local function ProposalText()
	local raid = proposal and FindRaid(proposal.raidId);
	return string.format("Рейд готов: %s\nПодтвердили: %d / %d",
		raid and raid.name or "", proposal and proposal.accepted or 0, proposal and proposal.total or 0);
end

local function ShowProposal()
	if proposal.answered then
		-- already accepted: just the count, no buttons to press again
		StaticPopup_Hide("RAID_FINDER_PROPOSAL");
		if UIErrorsFrame then
			UIErrorsFrame:AddMessage(ProposalText(), 1, 0.82, 0);
		end
		return;
	end
	local dialog = StaticPopup_Visible("RAID_FINDER_PROPOSAL");
	if dialog then
		_G[dialog .. "Text"]:SetText(ProposalText());
		StaticPopup_Resize(_G[dialog], "RAID_FINDER_PROPOSAL");
	else
		StaticPopup_Show("RAID_FINDER_PROPOSAL", ProposalText());
	end
	PlaySound("ReadyCheck");
end

---------------------------------------------------------------------------
-- comm
---------------------------------------------------------------------------
-- registered at login: this file may load before Server.lua (Comm_Register) in FrameXML.toc
local function RegisterComm()
	Comm_Register("RF_LIST", function(list)
		-- our own request comes back as an addon whisper with no body: not the server's list
		if not list then
			return;
		end
		wipe(raids);
		if list and list ~= "-" then
			for entry in string.gmatch(list, "[^,]+") do
				local id, name, mapId, difficulty, size, minLevel, minItemLevel, saved = strsplit(";", entry);
				table.insert(raids, {
					id = tonumber(id), name = name or "", mapId = tonumber(mapId) or 0, difficulty = tonumber(difficulty) or 0,
					size = tonumber(size) or 0, minLevel = tonumber(minLevel) or 0, minItemLevel = tonumber(minItemLevel) or 0,
					saved = saved == "1",
				});
			end
		end
		-- the first raid the player is not saved to
		if not (selectedRaid and FindRaid(selectedRaid)) then
			selectedRaid = nil;
			for _, raid in ipairs(raids) do
				if not raid.saved then
					selectedRaid = raid.id;
					break;
				end
			end
		end
		Update();
	end);

	Comm_Register("RF_STATUS", function(state, raidId, roles, seconds, tanks, healers, damage, tanksNeeded, healersNeeded, damageNeeded)
		if not state then
			return;
		end
		status = {
			state = tonumber(state) or STATE_NONE, raidId = tonumber(raidId) or 0, roles = tonumber(roles) or 0,
			seconds = tonumber(seconds) or 0,
			tanks = tonumber(tanks) or 0, healers = tonumber(healers) or 0, damage = tonumber(damage) or 0,
			tanksNeeded = tonumber(tanksNeeded) or 0, healersNeeded = tonumber(healersNeeded) or 0, damageNeeded = tonumber(damageNeeded) or 0,
		};
		statusTime = GetTime();
		if status.state == STATE_QUEUED or status.state == STATE_PROPOSAL then
			-- the queue's raid and roles on the frame
			selectedRaid = status.raidId;
			for id, role in pairs(ROLE_BY_ID) do
				checkedRoles[id] = bit.band(status.roles, role) ~= 0 or nil;
			end
		end
		if status.state ~= STATE_PROPOSAL then
			proposal = nil;
			StaticPopup_Hide("RAID_FINDER_PROPOSAL");
		end
		Update();
	end);

	Comm_Register("RF_PROPOSAL", function(raidId, secondsLeft, accepted, total, answered)
		proposal = {
			raidId = tonumber(raidId) or 0, secondsLeft = tonumber(secondsLeft) or 0,
			accepted = tonumber(accepted) or 0, total = tonumber(total) or 0, answered = answered == "1",
		};
		ShowProposal();
	end);

	Comm_Register("RF_RESULT", function(text)
		if text and text ~= "" then
			DEFAULT_CHAT_FRAME:AddMessage(text, 1, 0.82, 0);
		end
	end);
end

local commFrame = CreateFrame("Frame");
commFrame:RegisterEvent("PLAYER_LOGIN");
commFrame:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents();
	if Comm_Register then
		RegisterComm();
	end
	Send("RF_LIST");
	Send("RF_STATUS");
end);
