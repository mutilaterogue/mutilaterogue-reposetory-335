-- The retail queue status button (QueueStatus.xml): one eye left of the micro menu for every queue.
--   dungeon finder: the stock MiniMapLFGFrame lies invisible over the eye - its clicks and its dropdown as before;
--   raid finder:    RaidFinder_GetQueueInfo() (RaidFinder.lua).
-- On mouse over the retail status frame (QueueStatusFrame): an entry for each queue, retail role icons.
-- The eye plays the retail flipbooks frame by frame: the opening one and searching while queued, the found one with
-- its shards and glows for a proposal, the mouse over one on mouse over.

-- the retail flipbooks (Blizzard_QueueStatusFrame\QueueStatusFrame.xml, EyeTemplate)
local FLIPBOOKS = {
	initial = { atlas = "groupfinder-eye-flipbook-initial", rows = 5, columns = 11, frames = 52, duration = 1.5, once = true },
	searching = { atlas = "groupfinder-eye-flipbook-searching", rows = 8, columns = 11, frames = 80, duration = 2 },
	foundInitial = { atlas = "groupfinder-eye-flipbook-found-initial", rows = 7, columns = 11, frames = 70, duration = 2, once = true },
	found = { atlas = "groupfinder-eye-flipbook-found-loop", rows = 4, columns = 11, frames = 41, duration = 1.5 },
	-- the mouse over: the eye looks at the cursor once, then back to what it played
	mouseover = { atlas = "groupfinder-eye-flipbook-mouseover", rows = 1, columns = 12, frames = 12, duration = 0.4, once = true },
	-- the shards flying off when the group is found
	shards = { atlas = "groupfinder-eye-flipbook-foundfx", rows = 5, columns = 15, frames = 75, duration = 2, once = true },
};
-- after a one-shot: the loop it leads into
local NEXT = { initial = "searching", foundInitial = "found" };

local lfdShown = false;		-- the stock dungeon finder's eye is "shown" (it is invisible here)
local state;				-- "searching" / "found" / nil: what the queues want the eye to play
local players = {};			-- texture -> { name, book, rect, time }
local fades = {};			-- texture -> { from, to, duration, time }
local rects = {};			-- atlas -> { file, left, top, width, height } of one flipbook frame

-- an atlas' file and the size of one frame, read once from a scratch texture (SetAtlas, AtlasHelper.lua) -
-- the eye itself never shows the whole sheet
local function FrameRect(book)
	local rect = rects[book.atlas];
	if rect == nil then
		local scratch = QueueStatusButton.Scratch;
		scratch:SetAtlas(book.atlas);
		local file = scratch:GetTexture();
		local ulx, uly, llx, lly, urx = scratch:GetTexCoord();
		rect = file and ulx and { file = file, left = ulx, top = uly,
			width = (urx - ulx) / book.columns, height = (lly - uly) / book.rows } or false;
		rects[book.atlas] = rect;
	end
	return rect or nil;
end

local function ShowFrame(texture, player, frame)
	local column = frame % player.book.columns;
	local row = math.floor(frame / player.book.columns);
	local rect = player.rect;
	local left = rect.left + column * rect.width;
	local top = rect.top + row * rect.height;
	texture:SetTexCoord(left, left + rect.width, top, top + rect.height);
end

-- play a flipbook on a texture (nil: stop; the eye shows the still eye then)
local function Play(texture, name)
	local book = name and FLIPBOOKS[name];
	local rect = book and FrameRect(book);
	if not rect then
		players[texture] = nil;
		if texture == QueueStatusButton.Eye then
			texture:SetAtlas("groupfinder-eye-single");
		else
			texture:Hide();
		end
		return;
	end
	local player = { name = name, book = book, rect = rect, time = 0 };
	players[texture] = player;
	texture:SetTexture(rect.file);
	ShowFrame(texture, player, 0);		-- the first frame at once: never the whole sheet
	texture:Show();
end

local function Fade(texture, from, to, duration)
	texture:SetAlpha(from);
	texture:Show();
	fades[texture] = { from = from, to = to, duration = duration, time = 0 };
end

-- the eye to what the state plays: the retail opening one-shots when it changes
local function PlayState(newState)
	local button = QueueStatusButton;
	if newState == state then
		return;
	end
	local old = state;
	state = newState;
	if newState == "searching" then
		Play(button.Eye, old == nil and "initial" or "searching");
		if old == nil then
			Fade(button.GlowBack, 1, 0, 1);
			Fade(button.GlowFront, 1, 0, 1);
			Fade(button.CircShine, 1, 0, 2);
		end
	elseif newState == "found" then
		Play(button.Eye, "foundInitial");
		Play(button.Shards, "shards");
		Fade(button.GlowBack, 1, 0.2, 2);
		Fade(button.GlowFront, 1, 0, 1.5);
	else
		Play(button.Eye, nil);
	end
end

local function UpdateAnimations(elapsed)
	for texture, player in pairs(players) do
		local book = player.book;
		player.time = player.time + elapsed;
		if book.once and player.time >= book.duration then
			-- a one-shot ended: its loop, or (the mouse over) back to the state's own
			local nextName = NEXT[player.name];
			if texture == QueueStatusButton.Eye then
				Play(texture, nextName or state);
			else
				Play(texture, nil);
			end
		else
			local frame = math.floor((player.time % book.duration) / book.duration * book.frames);
			ShowFrame(texture, player, math.min(frame, book.frames - 1));
		end
	end
	for texture, fade in pairs(fades) do
		fade.time = fade.time + elapsed;
		local progress = math.min(fade.time / fade.duration, 1);
		texture:SetAlpha(fade.from + (fade.to - fade.from) * progress);
		if progress >= 1 then
			fades[texture] = nil;
			if fade.to <= 0 then
				texture:Hide();
			end
		end
	end
end

---------------------------------------------------------------------------
-- the status frame (retail QueueStatusFrame): an entry for every queue
---------------------------------------------------------------------------
local ROLE_ATLAS = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" };

-- retail GetIconForRole: the disabled one while the role still needs players
local function RoleAtlas(role, disabled)
	return ROLE_ATLAS[role] .. (disabled and "-Disabled" or "");
end

local function InitEntry(entry)
	if entry.initialized then
		return;
	end
	entry.initialized = true;
	entry.RoleIcon2:SetPoint("RIGHT", entry.RoleIcon1, "LEFT", 0, 0);
	entry.RoleIcon3:SetPoint("RIGHT", entry.RoleIcon2, "LEFT", 0, 0);
	entry.TanksFound:SetPoint("RIGHT", entry.HealersFound, "LEFT", -10, 0);
	entry.DamagersFound:SetPoint("LEFT", entry.HealersFound, "RIGHT", 10, 0);
end

local function TimeText(seconds)
	return string.format(TIME_IN_QUEUE, (seconds >= 60) and SecondsToTime(seconds) or LESS_THAN_ONE_MINUTE);
end

-- title, your roles, the found / needed of every role, the time (retail QueueStatusEntry_SetFullDisplay);
-- counts nil: a status line instead (QueueStatusEntry_SetMinimalDisplay)
local function SetEntry(entry, title, subTitle, roles, counts, seconds, averageWait, status)
	InitEntry(entry);
	local height = 14;
	entry.Title:SetText(title);

	-- your roles at the top right, the title left of them
	local nextIcon, leftmost = 1, nil;
	if roles then
		for _, role in ipairs({ "DAMAGER", "HEALER", "TANK" }) do
			if roles[role] then
				local icon = entry["RoleIcon" .. nextIcon];
				icon:SetAtlas(RoleAtlas(role, false));
				icon:Show();
				leftmost = icon;
				nextIcon = nextIcon + 1;
			end
		end
	end
	for i = nextIcon, 3 do
		entry["RoleIcon" .. i]:Hide();
	end
	entry.Title:ClearAllPoints();
	entry.Title:SetPoint("TOPLEFT", entry, "TOPLEFT", 10, -10);
	if leftmost then
		entry.Title:SetPoint("RIGHT", leftmost, "LEFT", -5, 0);
	else
		entry.Title:SetPoint("RIGHT", entry, "RIGHT", -10, 0);
	end
	height = height + entry.Title:GetHeight();

	local below = entry.Title;
	if subTitle then
		entry.SubTitle:ClearAllPoints();
		entry.SubTitle:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -5);
		entry.SubTitle:SetText(subTitle);
		entry.SubTitle:Show();
		height = height + entry.SubTitle:GetHeight() + 5;
		below = entry.SubTitle;
	else
		entry.SubTitle:Hide();
	end

	if status then
		entry.Status:ClearAllPoints();
		entry.Status:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -5);
		entry.Status:SetText(status);
		entry.Status:Show();
		height = height + entry.Status:GetHeight() + 5;
	else
		entry.Status:Hide();
	end

	if counts then
		entry.HealersFound:ClearAllPoints();
		entry.HealersFound:SetPoint("TOP", entry, "TOP", 0, -(height + 5));
		for _, row in ipairs({ { entry.TanksFound, "TANK", counts.tanks, counts.tanksNeeded },
				{ entry.HealersFound, "HEALER", counts.healers, counts.healersNeeded },
				{ entry.DamagersFound, "DAMAGER", counts.damage, counts.damageNeeded } }) do
			local frame, role, found, total = row[1], row[2], row[3], row[4];
			frame.Count:SetFormattedText(PLAYERS_FOUND_OUT_OF_MAX or "%d/%d", math.min(found, total), total);
			frame.RoleIcon:SetAtlas(RoleAtlas(role, found < total));
			frame:Show();
		end
		height = height + 68;
	else
		entry.TanksFound:Hide();
		entry.HealersFound:Hide();
		entry.DamagersFound:Hide();
	end

	if averageWait and averageWait > 0 then
		entry.AverageWait:ClearAllPoints();
		entry.AverageWait:SetPoint("TOPLEFT", entry, "TOPLEFT", 10, -(height + 5));
		entry.AverageWait:SetFormattedText(LFG_STATISTIC_AVERAGE_WAIT, SecondsToTime(averageWait, false, false, 1));
		entry.AverageWait:Show();
		height = height + entry.AverageWait:GetHeight();
	else
		entry.AverageWait:Hide();
	end

	if seconds then
		entry.TimeInQueue:ClearAllPoints();
		entry.TimeInQueue:SetPoint("TOPLEFT", entry, "TOPLEFT", 10, -(height + 5));
		entry.TimeInQueue:SetText(TimeText(seconds));
		entry.TimeInQueue:Show();
		height = height + entry.TimeInQueue:GetHeight();
	else
		entry.TimeInQueue:Hide();
	end

	entry:SetHeight(height + 14);
	entry:Show();
end

-- the dungeon finder (GetLFGMode / GetLFGQueueStats / GetLFGRoles)
local function SetDungeonEntry(entry)
	local mode, submode = GetLFGMode();
	if not lfdShown or not mode then
		entry:Hide();
		return false;
	end
	local _, tank, healer, damage = GetLFGRoles();
	local roles = { TANK = tank, HEALER = healer, DAMAGER = damage };
	local title = LOOKING_FOR_DUNGEON or "Поиск подземелий";
	if mode == "queued" then
		local hasData, _, tankNeeds, healerNeeds, dpsNeeds, _, instanceName, _, _, _, _, myWait, queuedTime = GetLFGQueueStats();
		if hasData then
			SetEntry(entry, title, instanceName, roles,
				{ tanks = 1 - tankNeeds, tanksNeeded = 1, healers = 1 - healerNeeds, healersNeeded = 1, damage = 3 - dpsNeeds, damageNeeded = 3 },
				GetTime() - queuedTime, myWait);
		else
			SetEntry(entry, title, nil, roles, nil, 0, nil, "Поиск…");
		end
	elseif mode == "proposal" then
		SetEntry(entry, title, nil, roles, nil, nil, nil, "Группа найдена!");
	elseif mode == "rolecheck" then
		SetEntry(entry, title, nil, roles, nil, nil, nil, "Проверка ролей…");
	elseif mode == "lfgparty" or mode == "abandonedInDungeon" then
		SetEntry(entry, title, nil, nil, nil, nil, nil, "Вы в подземелье.");
	else
		SetEntry(entry, title, nil, roles, nil, nil, nil, "В очереди.");
	end
	return true;
end

-- the raid finder (RaidFinder_GetQueueInfo, RaidFinder.lua)
local function SetRaidEntry(entry)
	local info = RaidFinder_GetQueueInfo and RaidFinder_GetQueueInfo();
	if not info then
		entry:Hide();
		return false;
	end
	local roles = { TANK = bit.band(info.roles, 1) ~= 0, HEALER = bit.band(info.roles, 2) ~= 0, DAMAGER = bit.band(info.roles, 4) ~= 0 };
	local title = "Поиск рейда";
	if info.state == "rolecheck" then
		SetEntry(entry, title, info.name, roles, nil, nil, nil, "Проверка ролей…");
	elseif info.state == "proposal" then
		SetEntry(entry, title, info.name, roles, nil, nil, nil, "Рейд собран!");
	else
		SetEntry(entry, title, info.name, roles, info, info.seconds);
	end
	return true;
end

local function UpdateStatusFrame()
	local frame = QueueStatusFrame;
	local height = 4;
	local previous;
	for _, pair in ipairs({ { frame.Dungeon, SetDungeonEntry }, { frame.Raid, SetRaidEntry } }) do
		local entry, set = pair[1], pair[2];
		if set(entry) then
			entry:ClearAllPoints();
			if previous then
				entry:SetPoint("TOP", previous, "BOTTOM", 0, 0);
				entry.EntrySeparator:Show();
			else
				entry:SetPoint("TOP", frame, "TOP", 0, -2);
				entry.EntrySeparator:Hide();
			end
			height = height + entry:GetHeight();
			previous = entry;
		end
	end
	frame:SetHeight(height);
	return previous ~= nil;
end

local function ShowStatus()
	local eye = players[QueueStatusButton.Eye];
	if not (eye and eye.book.once) then
		Play(QueueStatusButton.Eye, "mouseover");
	end
	-- (the stock dungeon finder's eye puts its own line in the game tooltip: the status frame says it all)
	if GameTooltip:IsOwned(MiniMapLFGFrame) then
		GameTooltip:Hide();
	end
	if UpdateStatusFrame() then
		QueueStatusFrame:Show();
	end
end

local function HideStatus()
	QueueStatusFrame:Hide();
end

local statusTimer = 0;

function QueueStatusButton_OnUpdate(self, elapsed)
	-- the raid finder's status shown: its time in the queue counts on
	statusTimer = statusTimer + elapsed;
	if statusTimer >= 1 then
		statusTimer = 0;
		if QueueStatusFrame:IsShown() then
			UpdateStatusFrame();
		end
	end
	UpdateAnimations(elapsed);
end

---------------------------------------------------------------------------
-- the button
---------------------------------------------------------------------------
function QueueStatus_Update()
	local button = QueueStatusButton;
	local raid = RaidFinder_GetQueueInfo and RaidFinder_GetQueueInfo();
	if not lfdShown and not raid then
		PlayState(nil);
		button:Hide();
		HideStatus();
		return;
	end
	button:Show();

	local mode = lfdShown and GetLFGMode and GetLFGMode();
	local newState;
	if (raid and raid.state == "proposal") or mode == "proposal" then
		newState = "found";
	elseif (raid and (raid.state == "queued" or raid.state == "rolecheck"))
		or mode == "queued" or mode == "listed" or mode == "rolecheck" then
		newState = "searching";
	end
	PlayState(newState);
	-- the glow: only when the group is found (retail pulses it then)
	button.Highlight:SetShown(newState == "found");

	if QueueStatusFrame:IsShown() and not UpdateStatusFrame() then
		HideStatus();
	end
end

-- left of the micro menu (retail: QueueStatusButton at the micro menu's bottom left, x -45)
local function PlaceButton()
	local button = QueueStatusButton;
	button:ClearAllPoints();
	if MicroMenuFrame then
		button:SetPoint("BOTTOMLEFT", MicroMenuFrame, "BOTTOMLEFT", -45, 4);
	else
		button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300, 4);
	end
end

-- the stock dungeon finder's eye: on our button, invisible, still doing its job
local function AdoptStockEye()
	local stock = MiniMapLFGFrame;
	if not stock or stock.queueStatusAdopted then
		return;
	end
	stock.queueStatusAdopted = true;
	stock:SetParent(QueueStatusButton);
	stock:ClearAllPoints();
	stock:SetAllPoints(QueueStatusButton);
	stock:SetFrameLevel(QueueStatusButton:GetFrameLevel() + 2);
	for _, region in ipairs({ stock:GetRegions() }) do
		region:SetAlpha(0);
	end
	for _, child in ipairs({ stock:GetChildren() }) do
		if child ~= LFDSearchStatus and child ~= MiniMapLFGFrameDropDown then
			child:SetAlpha(0);
		end
	end
	if stock:GetHighlightTexture() then
		stock:GetHighlightTexture():SetAlpha(0);
	end

	lfdShown = stock:IsShown();
	hooksecurefunc(stock, "Show", function()
		lfdShown = true;
		QueueStatus_Update();
	end);
	hooksecurefunc(stock, "Hide", function()
		lfdShown = false;
		QueueStatus_Update();
	end);
	-- its mouse over: the eye's glow and the raid finder's status next to its own
	stock:HookScript("OnEnter", ShowStatus);
	stock:HookScript("OnLeave", HideStatus);
	-- its old status window: the retail status frame shows the dungeon finder instead
	if LFDSearchStatus then
		LFDSearchStatus:Hide();
		LFDSearchStatus.Show = LFDSearchStatus.Hide;
	end
	-- its dropdown: the raid finder's queue too
	if MiniMapLFGFrameDropDown_Update then
		hooksecurefunc("MiniMapLFGFrameDropDown_Update", function()
			if RaidFinder_GetQueueInfo and RaidFinder_GetQueueInfo() then
				local info = UIDropDownMenu_CreateInfo();
				info.text = "Покинуть очередь в рейд";
				info.func = RaidFinder_LeaveQueue;
				info.notCheckable = 1;
				UIDropDownMenu_AddButton(info);
			end
		end);
	end
end

function QueueStatusButton_OnLoad(self)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	self:RegisterEvent("PLAYER_LOGIN");
	self:SetScript("OnEvent", function(frame, event)
		PlaceButton();
		AdoptStockEye();
		QueueStatus_Update();
	end);
end

function QueueStatusButton_OnEnter(self)
	ShowStatus();
end

function QueueStatusButton_OnLeave(self)
	HideStatus();
end

-- (the dungeon finder's eye lies over this one while it is queued: these are the raid finder's clicks)
local raidMenu = CreateFrame("Frame", "QueueStatusButtonDropDown", UIParent, "UIDropDownMenuTemplate");

function QueueStatusButton_OnClick(self, button)
	if button == "RightButton" then
		EasyMenu({
			{ text = "Поиск рейда", isTitle = 1, notCheckable = 1 },
			{ text = LEAVE_QUEUE, func = RaidFinder_LeaveQueue, notCheckable = 1 },
		}, raidMenu, self, 0, 0, "MENU");
	elseif PVEFrame_Open then
		PVEFrame_Open(1, 2);
	end
end
