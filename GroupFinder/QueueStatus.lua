-- The retail queue status button (QueueStatus.xml): one eye left of the micro menu for every queue.
--   dungeon finder: the stock MiniMapLFGFrame lies invisible over the eye - its clicks, its dropdown and its
--                   LFDSearchStatus as before, only placed here;
--   raid finder:    RaidFinder_GetQueueInfo() (RaidFinder.lua), RaidFinderSearchStatus on mouse over.
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
-- the raid finder's status (RaidFinderSearchStatus)
---------------------------------------------------------------------------
local function SetRoleCount(role, have, need)
	role.count:SetFormattedText("%d / %d", have, need);
	if have >= need then
		role.count:SetTextColor(0, 1, 0);
		role.cover:Hide();
		role.texture:SetDesaturated(false);
	else
		role.count:SetTextColor(1, 1, 1);
		role.cover:Show();
		role.texture:SetDesaturated(true);
	end
end

local function UpdateRaidStatus()
	local status = RaidFinderSearchStatus;
	local info = RaidFinder_GetQueueInfo and RaidFinder_GetQueueInfo();
	if not info then
		status:Hide();
		return;
	end
	if info.state == "rolecheck" then
		status.title:SetText("Проверка ролей: " .. info.name);
	elseif info.state == "proposal" then
		status.title:SetText("Рейд собран: " .. info.name);
	else
		status.title:SetText("Формирование рейда: " .. info.name);
	end
	SetRoleCount(status.Tank, info.tanks, info.tanksNeeded);
	SetRoleCount(status.Healer, info.healers, info.healersNeeded);
	SetRoleCount(status.Damage, info.damage, info.damageNeeded);

	local elapsed = info.seconds;
	status.elapsedWait:SetFormattedText(TIME_IN_QUEUE, (elapsed >= 60) and SecondsToTime(elapsed) or LESS_THAN_ONE_MINUTE);

	-- "you are queued as": the role icons
	local index = 1;
	for _, entry in ipairs({ { 1, "TANK" }, { 2, "HEALER" }, { 4, "DAMAGER" } }) do
		if bit.band(info.roles, entry[1]) ~= 0 then
			local icon = _G["RaidFinderSearchStatusRoleIcon" .. index];
			icon:SetTexCoord(GetTexCoordsForRole(entry[2]));
			icon:Show();
			index = index + 1;
		end
	end
	for i = index, 3 do
		_G["RaidFinderSearchStatusRoleIcon" .. i]:Hide();
	end
	status.lookingFor:ClearAllPoints();
	status.lookingFor:SetPoint("BOTTOM", status, "BOTTOM", -27 * (index - 1) / 2, 14);
end

-- left of the eye, above the dungeon finder's status when that one is shown too
local function PlaceStatus()
	local anchor = QueueStatusButton;
	if LFDSearchStatus and LFDSearchStatus:IsShown() then
		LFDSearchStatus:ClearAllPoints();
		LFDSearchStatus:SetPoint("BOTTOMRIGHT", anchor, "TOPLEFT", 0, 0);
		anchor = LFDSearchStatus;
		RaidFinderSearchStatus:ClearAllPoints();
		RaidFinderSearchStatus:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2);
	else
		RaidFinderSearchStatus:ClearAllPoints();
		RaidFinderSearchStatus:SetPoint("BOTTOMRIGHT", anchor, "TOPLEFT", 0, 0);
	end
end

local function ShowStatus()
	local eye = players[QueueStatusButton.Eye];
	if not (eye and eye.book.once) then
		Play(QueueStatusButton.Eye, "mouseover");
	end
	UpdateRaidStatus();
	if RaidFinder_GetQueueInfo and RaidFinder_GetQueueInfo() then
		RaidFinderSearchStatus:Show();
	end
	PlaceStatus();
end

local function HideStatus()
	RaidFinderSearchStatus:Hide();
end

local statusTimer = 0;

function QueueStatusButton_OnUpdate(self, elapsed)
	-- the raid finder's status shown: its time in the queue counts on
	statusTimer = statusTimer + elapsed;
	if statusTimer >= 1 then
		statusTimer = 0;
		if RaidFinderSearchStatus:IsShown() then
			UpdateRaidStatus();
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

	if RaidFinderSearchStatus:IsShown() then
		UpdateRaidStatus();
		if not raid then
			RaidFinderSearchStatus:Hide();
		end
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
	if LFDSearchStatus then
		LFDSearchStatus:HookScript("OnShow", PlaceStatus);
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
