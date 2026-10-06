-- The retail queue status button (QueueStatus.xml): one eye left of the micro menu for every queue.
--   dungeon finder: the stock MiniMapLFGFrame lies invisible over the eye - its clicks, its dropdown and its
--                   LFDSearchStatus as before, only placed here;
--   raid finder:    RaidFinder_GetQueueInfo() (RaidFinder.lua), RaidFinderSearchStatus on mouse over.
-- The eye plays the retail flipbooks frame by frame: searching while queued, found for a proposal.

local FLIPBOOKS = {
	searching = { atlas = "groupfinder-eye-flipbook-searching", rows = 8, columns = 11, frames = 80, duration = 2 },
	found = { atlas = "groupfinder-eye-flipbook-found-loop", rows = 4, columns = 11, frames = 41, duration = 1.5 },
};

local lfdShown = false;		-- the stock dungeon finder's eye is "shown" (it is invisible here)
local flipbook, flipbookTime = nil, 0;

-- the file and the rect of an atlas: set it on the eye and read them back (SetAtlas, AtlasHelper.lua)
local function AtlasRect(atlas)
	local eye = QueueStatusButton.Eye;
	eye:SetAtlas(atlas);
	local file = eye:GetTexture();
	local ulx, uly, llx, lly, urx, ury = eye:GetTexCoord();
	if not file or not ulx then
		return;
	end
	return file, ulx, urx, uly, lly;
end

-- a flipbook (nil: the still eye)
local function SetFlipbook(name)
	local eye = QueueStatusButton.Eye;
	if flipbook and name and flipbook.name == name then
		return;
	end
	if not name then
		flipbook = nil;
		eye:SetAtlas("groupfinder-eye-single");
		return;
	end
	local book = FLIPBOOKS[name];
	local file, left, right, top, bottom = AtlasRect(book.atlas);
	if not file then
		flipbook = nil;
		eye:SetAtlas("groupfinder-eye-single");
		return;
	end
	flipbook = { name = name, book = book, left = left, top = top,
		width = (right - left) / book.columns, height = (bottom - top) / book.rows };
	flipbookTime = 0;
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
	QueueStatusButton.Highlight:Show();
	UpdateRaidStatus();
	if RaidFinder_GetQueueInfo and RaidFinder_GetQueueInfo() then
		RaidFinderSearchStatus:Show();
	end
	PlaceStatus();
end

local function HideStatus()
	QueueStatusButton.Highlight:Hide();
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
	if not flipbook then
		return;
	end
	local book = flipbook.book;
	flipbookTime = (flipbookTime + elapsed) % book.duration;
	local frame = math.floor(flipbookTime / book.duration * book.frames);
	local column = frame % book.columns;
	local row = math.floor(frame / book.columns);
	local left = flipbook.left + column * flipbook.width;
	local top = flipbook.top + row * flipbook.height;
	self.Eye:SetTexCoord(left, left + flipbook.width, top, top + flipbook.height);
end

---------------------------------------------------------------------------
-- the button
---------------------------------------------------------------------------
function QueueStatus_Update()
	local button = QueueStatusButton;
	local raid = RaidFinder_GetQueueInfo and RaidFinder_GetQueueInfo();
	if not lfdShown and not raid then
		button:Hide();
		HideStatus();
		return;
	end
	button:Show();

	local mode = lfdShown and GetLFGMode and GetLFGMode();
	if (raid and raid.state == "proposal") or mode == "proposal" then
		SetFlipbook("found");
	elseif (raid and (raid.state == "queued" or raid.state == "rolecheck"))
		or mode == "queued" or mode == "listed" or mode == "rolecheck" then
		SetFlipbook("searching");
	else
		SetFlipbook(nil);
	end

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
