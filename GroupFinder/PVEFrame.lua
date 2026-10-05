-- The retail group finder window (PVEFrame.xml) on 3.3.5: the stock windows shown inside it.
--   tab 1 "Dungeons and raids": LFDParentFrame (dungeon finder); raid finder and premade groups: placeholders for now
--   tab 2 "PvP": PVPParentFrame - its battlegrounds tab (PVPBattlegroundFrame) and its honor / arena tab (PVPFrame)
--   tab 3 "Mythic+": ChallengesFrame (ChallengesUI), over the whole window
-- The stock windows keep their logic; their own frame art, title and close button are hidden. Whatever opens them
-- (key bindings, micro buttons, a battlemaster, /mplus) opens this window on their section.

local RIGHT_X, RIGHT_Y = 210, 46;		-- a stock window's place: its content right of the blue panel (default)

local PORTRAITS = {
	"Interface\\LFGFrame\\UI-LFG-PORTRAIT",
	"Interface\\BattlefieldFrame\\UI-Battlefield-Icon",
	"Interface\\Icons\\INV_Relics_Hourglass",
};

local TITLES = {
	"Поиск группы",
	PLAYER_V_PLAYER or "Игрок против игрока",
	"Эпохальные+",
};

local TAB_NAMES = {
	"Подземелья и рейды",
	PLAYER_V_PLAYER or "Игрок против игрока",
	"Эпохальные+",
};

-- the sections of every tab: the window, the stock tab inside it (PVPParentFrame), the left button's text and icon
local SECTIONS = {
	{
		{ frame = "LFDParentFrame", text = LOOKING_FOR_DUNGEON or "Поиск подземелий", icon = "Interface\\Icons\\INV_Helmet_08" },
		-- retail's raid finder and premade groups: not on 3.3.5 yet, a placeholder for now
		{ frame = "RaidFinderFrame", placeholder = true, text = "Поиск рейда", icon = "Interface\\LFGFrame\\UI-LFR-PORTRAIT" },
		{ frame = "LFGListPVEStub", placeholder = true, text = "Заранее собранные группы", icon = "Interface\\Icons\\Achievement_General_StayClassy" },
	},
	{
		-- the PvP window's content starts higher than the dungeon finder's: lower
		{ frame = "PVPParentFrame", tab = 2, y = 14, text = BATTLEGROUNDS or "Поля боя", icon = "Interface\\Icons\\Achievement_BG_winWSG" },
		{ frame = "PVPParentFrame", tab = 1, y = 14, text = (HONOR or "Честь") .. " / " .. (ARENA or "Арена"), icon = "Interface\\Icons\\Achievement_Arena_2v2_7" },
	},
	{
		{ frame = "ChallengesFrame", full = true },
	},
};

local selectedTab, selectedSection = 1, 1;
local embedded = {};

---------------------------------------------------------------------------
-- the stock windows inside this one
---------------------------------------------------------------------------
-- the 3.3.5 frame art: the corner pieces of the old windows, their portraits (by texture path)
local OLD_ART_PATTERNS = { "TopLeft", "TopRight", "BotLeft", "BotRight", "BottomLeft", "BottomRight", "Portrait", "PORTRAIT",
	"Battlefield%-Icon", "UI%-LFG%-FRAME", "UI%-LFR%-FRAME", "UI%-Character%-General", "UI%-Character%-PVP" };
local RETAIL_FRAME_KEYS = { "NineSlice", "PortraitContainer", "TitleContainer", "Bg", "TopTileStreaks", "CloseButton" };

local function Suppress(object)
	object:Hide();
	object.Show = object.Hide;
end

local function IsOldArt(region)
	if not region:IsObjectType("Texture") then
		return false;
	end
	local path = region:GetTexture();
	local name = region:GetName();
	for _, pattern in ipairs(OLD_ART_PATTERNS) do
		if (path and path:find(pattern)) or (name and name:find(pattern)) then
			return true;
		end
	end
	return false;
end

-- a window and its panels (two levels down): their own frame art, titles and close buttons; the content stays
-- popups of their own (the arena team's members): their frame and close button stay
local KEEP_FRAMES = { PVPTeamDetails = true };

local function HideOldFrameArt(frame, depth)
	local name = frame:GetName();
	if name and KEEP_FRAMES[name] then
		return;
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		local regionName = region:GetName();
		if IsOldArt(region) or (regionName and regionName:find("FrameLabel$")) then
			Suppress(region);
		end
	end
	for _, key in ipairs(RETAIL_FRAME_KEYS) do
		if frame[key] then
			Suppress(frame[key]);
		end
	end
	if name and _G[name .. "CloseButton"] then
		Suppress(_G[name .. "CloseButton"]);
	end
	if depth > 0 then
		for _, child in ipairs({ frame:GetChildren() }) do
			HideOldFrameArt(child, depth - 1);
		end
	end
end

local function HideOwnArt(frame)
	-- the window's own frame art and title (regions right on it)
	for _, region in ipairs({ frame:GetRegions() }) do
		Suppress(region);
	end
	HideOldFrameArt(frame, 2);
end

-- what the stock window still has over this window's top (its title, its close button: moved up with it)
local function HideAboveTop(frame, depth)
	local top = PVEFrame:GetTop();
	if not top then
		return;
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		local bottom = region:IsShown() and region:GetBottom();
		if bottom and bottom > top - 2 then
			Suppress(region);
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local bottom = child:IsShown() and child:GetBottom();
		if bottom and bottom > top - 2 then
			Suppress(child);
		elseif depth > 0 then
			HideAboveTop(child, depth - 1);
		end
	end
end

-- retail LFDFrame.xml / RaidFinderFrame.xml layout: 338x428 right of the blue panel, own inset and backgrounds
local RETAIL_LAYOUT = { LFDParentFrame = true, RaidFinderFrame = true, LFGListPVEStub = true };

local function RetailBackdrop(frame)
	local role = frame:CreateTexture(nil, "BACKGROUND");
	role:SetTexture("Interface\\LFGFrame\\UI-LFG-BlueBG");
	role:SetSize(512, 128);
	role:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 275);

	local inset = CreateFrame("Frame", frame:GetName() .. "RetailInset", frame, "InsetFrameTemplate");
	inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60);
	inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26);
	inset:SetFrameLevel(frame:GetFrameLevel());
	frame.retailInset = inset;
	-- the content (roles, list) over the inset, never under it
	for _, child in ipairs({ frame:GetChildren() }) do
		if child ~= inset then
			child:SetFrameLevel(frame:GetFrameLevel() + 3);
		end
	end
end

-- a section that is not done yet: the retail backdrop and a note
local function CreatePlaceholder(name, title)
	local frame = CreateFrame("Frame", name, PVEFrame);
	frame:SetSize(338, 428);
	RetailBackdrop(frame);
	local header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	header:SetPoint("TOP", frame, "TOP", 0, -100);
	header:SetText(title);
	local note = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	note:SetPoint("TOP", header, "BOTTOM", 0, -12);
	note:SetWidth(280);
	note:SetText("Будет добавлено в будущем.");
	frame:Hide();
	return frame;
end

-- the dungeon finder's own title and close button (inside its new top, HideAboveTop misses them)
local function HideLFDTitle(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("FontString") then
			Suppress(region);
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child:IsObjectType("Button") and not child:GetName() or (child:GetName() or ""):find("CloseButton$") then
			local normal = child:GetNormalTexture();
			local path = normal and normal:GetTexture();
			if path and path:find("MinimizeButton") then
				Suppress(child);
			end
		end
	end
end

local function ApplyRetailLFD()
	local frame = LFDParentFrame;
	HideLFDTitle(frame);
	-- the queue frame's own title and old frame art
	for _, name in ipairs({ "LFDQueueFrameTitleText", "LFDQueueFrameLayout" }) do
		if _G[name] then
			Suppress(_G[name]);
		end
	end
	RetailBackdrop(frame);
	-- the roles and the dropdown at their retail places
	if LFDQueueFrameRoleButtonTank then
		LFDQueueFrameRoleButtonTank:ClearAllPoints();
		LFDQueueFrameRoleButtonTank:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 37, 334);
		LFDQueueFrameRoleButtonHealer:ClearAllPoints();
		LFDQueueFrameRoleButtonHealer:SetPoint("LEFT", LFDQueueFrameRoleButtonTank, "RIGHT", 23, 0);
		LFDQueueFrameRoleButtonDPS:ClearAllPoints();
		LFDQueueFrameRoleButtonDPS:SetPoint("LEFT", LFDQueueFrameRoleButtonHealer, "RIGHT", 23, 0);
		LFDQueueFrameRoleButtonLeader:ClearAllPoints();
		LFDQueueFrameRoleButtonLeader:SetPoint("LEFT", LFDQueueFrameRoleButtonDPS, "RIGHT", 23, 0);
	end
	if LFDQueueFrameTypeDropDown then
		LFDQueueFrameTypeDropDown:ClearAllPoints();
		LFDQueueFrameTypeDropDown:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 117, 285);
	end
	-- retail has no quest paper under the list: the dark inset only
	if LFDQueueFrameBackground then
		Suppress(LFDQueueFrameBackground);
	end
	-- the old scroll bar backgrounds; the bar itself in the retail style
	for _, scrollName in ipairs({ "LFDQueueFrameRandomScrollFrame", "LFDQueueFrameSpecificListScrollFrame" }) do
		for _, suffix in ipairs({ "", "TopLeft", "BottomRight", "Top", "Bottom", "Middle" }) do
			local tex = _G[scrollName .. "ScrollBackground" .. suffix];
			if tex then
				Suppress(tex);
			end
		end
	end
	-- the retail scroll box size and place (303x239 at -29, 35); its bar restyled on the first show
	local scroll = LFDQueueFrameRandomScrollFrame;
	if scroll then
		scroll:SetSize(303, 239);
		scroll:ClearAllPoints();
		scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -29, 35);
		frame:HookScript("OnShow", function()
			if not scroll.retailBar and QuestMap_RetailScrollBar then
				scroll.retailBar = true;
				QuestMap_RetailScrollBar(scroll);
			end
		end);
	end
	-- the retail top streaks and the button bar along the bottom
	local streaks = frame:CreateTexture(nil, "BACKGROUND", nil, 1);
	streaks:SetAtlas("_UI-Frame-TopTileStreaks", true);
	streaks:SetHorizTile(true);
	streaks:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -21);
	streaks:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -21);
	local corner = frame:CreateTexture(nil, "BORDER");
	corner:SetAtlas("UI-Frame-BtnCornerRight", true);
	corner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1);
	local bottom = frame:CreateTexture(nil, "BORDER");
	bottom:SetAtlas("_UI-Frame-BtnBotTile", true);
	bottom:SetHorizTile(true);
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -23, 2);
	bottom:SetPoint("BOTTOMRIGHT", corner, "BOTTOMLEFT");
	if LFDQueueFrameFindGroupButton then
		LFDQueueFrameFindGroupButton:SetSize(135, 22);
		LFDQueueFrameFindGroupButton:ClearAllPoints();
		LFDQueueFrameFindGroupButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 3);
	end
	if LFDQueueFrameCancelButton then
		Suppress(LFDQueueFrameCancelButton);
	end
end

local function Embed(name, full, y)
	local frame = _G[name];
	if not frame or embedded[name] then
		return frame;
	end
	embedded[name] = true;
	if frame.isPlaceholder then
		frame:ClearAllPoints();
		frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", 224, 0);
		frame:SetFrameLevel(PVEFrame:GetFrameLevel() + 2);
		return frame;
	end
	UIPanelWindows[name] = nil;		-- this window is the panel now
	frame:SetParent(PVEFrame);
	frame:ClearAllPoints();
	if full then
		frame:SetAllPoints(PVEFrame);
		frame:SetFrameLevel(PVEFrame:GetFrameLevel() + 5);
	elseif RETAIL_LAYOUT[name] then
		frame:SetSize(338, 428);
		frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", 224, 0);
		frame:SetFrameLevel(PVEFrame:GetFrameLevel() + 2);
	else
		frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", RIGHT_X, y or RIGHT_Y);
		frame:SetFrameLevel(PVEFrame:GetFrameLevel() + 2);
	end
	if frame.SetMovable then
		frame:SetMovable(false);
	end
	HideOwnArt(frame);
	if name == "LFDParentFrame" then
		ApplyRetailLFD();
	end
	if name == "PVPParentFrame" then
		-- the 3.3.5 windows reach below this one: they no longer catch the clicks meant for the tabs there
		for _, f in ipairs({ frame, PVPFrame, PVPBattlegroundFrame }) do
			if f then
				f:EnableMouse(false);
			end
		end
		-- PVPFrame's unnamed "Player vs. Player" title: this window's title says it
		for _, region in ipairs({ PVPFrame:GetRegions() }) do
			if region:IsObjectType("FontString") and region:GetText() == PLAYER_V_PLAYER then
				Suppress(region);
			end
		end
		-- the left buttons choose its tab
		PVPParentFrameTab1:Hide();
		PVPParentFrameTab1.Show = PVPParentFrameTab1.Hide;
		PVPParentFrameTab2:Hide();
		PVPParentFrameTab2.Show = PVPParentFrameTab2.Hide;
	end
	frame:Hide();

	-- opened the stock way (ShowUIPanel, a battlemaster, ...) while this window is closed: open it on that section
	hooksecurefunc(frame, "Show", function()
		if not PVEFrame:IsShown() then
			for tab, sections in ipairs(SECTIONS) do
				for index, section in ipairs(sections) do
					if section.frame == name then
						PVEFrame_Open(tab, index, true);
						return;
					end
				end
			end
		end
	end);
	return frame;
end

---------------------------------------------------------------------------
-- tabs and sections
---------------------------------------------------------------------------
local function HideSections()
	for _, sections in ipairs(SECTIONS) do
		for _, section in ipairs(sections) do
			local frame = _G[section.frame];
			if frame and frame:IsShown() then
				frame:Hide();
			end
		end
	end
end

function PVEFrame_ShowSection(index, keepShown)
	local section = SECTIONS[selectedTab][index];
	if not section then
		return;
	end
	selectedSection = index;
	local frame = Embed(section.frame, section.full, section.y);
	if frame and not section.full and not RETAIL_LAYOUT[section.frame] then
		-- the same window in another section (PvP) may stand elsewhere
		frame:ClearAllPoints();
		frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", RIGHT_X, section.y or RIGHT_Y);
	end
	-- the retail-laid-out sections bring their own inset
	if not section.full then
		if RETAIL_LAYOUT[section.frame] then
			PVEFrameRightInset:Hide();
		else
			PVEFrameRightInset:Show();
		end
	end
	if not keepShown then
		HideSections();
	end
	if frame then
		frame:Show();
		if section.tab then
			local stockTab = _G["PVPParentFrameTab" .. section.tab];
			if stockTab then
				stockTab:Click();
			end
		end
		if not section.full then
			HideAboveTop(frame, 2);
		end
	end
	for i = 1, 3 do
		local button = _G["GroupFinderFrameGroupButton" .. i];
		if button.selected then
			if i == index then
				button.selected:Show();
			else
				button.selected:Hide();
			end
		end
	end
end

function PVEFrame_ShowTab(tab, section, keepShown)
	selectedTab = tab;
	PVEFrame.TabSystem:SetTabVisuallySelected(tab);
	PVEFrame:SetTitle(TITLES[tab]);
	PVEFrame:SetPortraitToAsset(PORTRAITS[tab]);

	-- the left panel: the sections of tabs 1 and 2 (Mythic+ covers the whole window)
	local sections = SECTIONS[tab];
	if sections[1].full then
		GroupFinderFrame:Hide();
		PVEFrameRightInset:Hide();
	else
		GroupFinderFrame:Show();
		PVEFrameRightInset:Show();
		for i = 1, 3 do
			local button = _G["GroupFinderFrameGroupButton" .. i];
			local info = sections[i];
			if info then
				button.name:SetText(info.text);
				SetPortraitToTexture(button.icon, info.icon);
				button:Show();
			else
				button:Hide();
			end
		end
	end
	PVEFrame_ShowSection(section or 1, keepShown);
end

-- open on a section; the same section again closes the window (the stock toggles)
function PVEFrame_Open(tab, section, keepShown)
	if not PVEFrame:IsShown() then
		ShowUIPanel(PVEFrame);
	end
	PVEFrame_ShowTab(tab, section, keepShown);
end

function PVEFrame_Toggle(tab, section)
	if PVEFrame:IsShown() and selectedTab == tab and selectedSection == (section or 1) then
		HideUIPanel(PVEFrame);
	else
		PVEFrame_Open(tab, section);
	end
end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------
function GroupFinderGroupButton_OnLoad(self)
	-- the round icon in the ring (retail CircleMask)
	if self.CreateMaskTexture then
		local mask = self:CreateMaskTexture(nil, "BORDER");
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask");
		mask:SetPoint("TOPLEFT", self.icon, "TOPLEFT", 2, -2);
		mask:SetPoint("BOTTOMRIGHT", self.icon, "BOTTOMRIGHT", -2, 2);
		self.icon:AddMaskTexture(mask);
	end
end

function GroupFinderGroupButton_OnClick(self)
	PVEFrame_ShowSection(self:GetID());
	PlaySound("igCharacterInfoTab");
end

function PVEFrame_OnLoad(self)
	-- retail tabs: TabSystem, each tab opens its first section
	Mixin(self, TabSystemOwnerMixin);
	TabSystemOwnerMixin.OnLoad(self);
	self:SetTabSystem(self.TabSystem);
	for tab = 1, #TITLES do
		local tabID = self:AddNamedTab(TAB_NAMES[tab]);
		local button = self.TabSystem:GetTabButton(tabID);
		_G["PVEFrameTab" .. tab] = button;
		-- the 3.3.5 font string reports its set width, not the text's: size the tab by the text itself
		local textWidth = button.Text:GetStringWidth();
		button.Text:SetWidth(textWidth + 10);
		button:SetTabWidth(math.max(70, textWidth + 30));
		self:SetTabCallback(tabID, function(isUserAction)
			if isUserAction then
				PVEFrame_ShowTab(tab);
			end
		end);
	end
	self.TabSystem:MarkDirty();
	self.TabSystem:SetFrameLevel(self:GetFrameLevel() + 25);
	UIPanelWindows["PVEFrame"] = { area = "left", pushable = 0, whileDead = 1, xOffset = "15", yOffset = "-10" };
	for _, section in ipairs(SECTIONS[1]) do
		if section.placeholder and not _G[section.frame] then
			CreatePlaceholder(section.frame, section.text).isPlaceholder = true;
		end
	end
	-- every stock window inside this one from the start (a battlemaster may open one before this window ever showed)
	for _, sections in ipairs(SECTIONS) do
		for _, section in ipairs(sections) do
			Embed(section.frame, section.full, section.y);
		end
	end
	-- each section's own toggles: this window instead
	function ToggleLFDParentFrame()
		if ( UnitLevel("player") >= SHOW_LFD_LEVEL ) then
			PVEFrame_Toggle(1, 1);
		end
	end
	function ToggleLFRParentFrame()
		PVEFrame_Toggle(1, 2);
	end
	function TogglePVPFrame()
		if ( PVPFrame_IsJustBG() ) then
			PVPFrame_SetJustBG(false);
		end
		if ( UnitLevel("player") >= SHOW_PVP_LEVEL ) then
			PVEFrame_Toggle(2, 1);
		end
	end
	SlashCmdList["MYTHICPLUS"] = function()
		PVEFrame_Toggle(3, 1);
	end
end

function PVEFrame_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	UpdateMicroButtons();
end

function PVEFrame_OnHide(self)
	HideSections();
	PlaySound("igCharacterInfoClose");
	UpdateMicroButtons();
end
