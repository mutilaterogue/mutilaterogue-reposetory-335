-- The retail group finder window (PVEFrame.xml) on 3.3.5: the stock windows shown inside it.
--   tab 1 "Dungeons and raids": LFDParentFrame (dungeon finder), LFRParentFrame (raid browser)
--   tab 2 "PvP": PVPParentFrame - its battlegrounds tab (PVPBattlegroundFrame) and its honor / arena tab (PVPFrame)
--   tab 3 "Mythic+": ChallengesFrame (ChallengesUI), over the whole window
-- The stock windows keep their logic; their own frame art, title and close button are hidden. Whatever opens them
-- (key bindings, micro buttons, a battlemaster, /mplus) opens this window on their section.

local RIGHT_X, RIGHT_Y = 210, 46;		-- a stock window's place: its content right of the blue panel

local PORTRAITS = {
	"Interface\\LFGFrame\\UI-LFG-PORTRAIT",
	"Interface\\BattlefieldFrame\\UI-Battlefield-Icon",
	"Interface\\Icons\\INV_Relics_Hourglass",
};

local TITLES = {
	LOOKING_FOR_DUNGEON or "Подземелья и рейды",
	PLAYER_V_PLAYER or "Игрок против игрока",
	"Эпохальные+",
};

-- the sections of every tab: the window, the stock tab inside it (PVPParentFrame), the left button's text and icon
local SECTIONS = {
	{
		{ frame = "LFDParentFrame", text = LOOKING_FOR_DUNGEON or "Поиск подземелий", icon = "Interface\\Icons\\INV_Helmet_08" },
		{ frame = "LFRParentFrame", text = LOOKING_FOR_RAID or "Поиск рейда", icon = "Interface\\Icons\\INV_Helmet_06" },
	},
	{
		{ frame = "PVPParentFrame", tab = 2, text = BATTLEGROUNDS or "Поля боя", icon = "Interface\\Icons\\Achievement_BG_winWSG" },
		{ frame = "PVPParentFrame", tab = 1, text = (HONOR or "Честь") .. " / " .. (ARENA or "Арена"), icon = "Interface\\Icons\\Achievement_Arena_2v2_7" },
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
local function HideOldFrameArt(frame, depth)
	local name = frame:GetName();
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

local function Embed(name, full)
	local frame = _G[name];
	if not frame or embedded[name] then
		return frame;
	end
	embedded[name] = true;
	UIPanelWindows[name] = nil;		-- this window is the panel now
	frame:SetParent(PVEFrame);
	frame:ClearAllPoints();
	if full then
		frame:SetAllPoints(PVEFrame);
		frame:SetFrameLevel(PVEFrame:GetFrameLevel() + 5);
	else
		frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", RIGHT_X, RIGHT_Y);
		frame:SetFrameLevel(PVEFrame:GetFrameLevel() + 2);
	end
	if frame.SetMovable then
		frame:SetMovable(false);
	end
	HideOwnArt(frame);
	if name == "PVPParentFrame" then
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
	local frame = Embed(section.frame, section.full);
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
	PanelTemplates_SetTab(PVEFrame, tab);
	PVEFrame:SetTitle(TITLES[tab]);
	PVEFrame:SetPortraitToAsset(PORTRAITS[tab]);

	-- the left panel: the sections of tabs 1 and 2 (Mythic+ covers the whole window)
	local sections = SECTIONS[tab];
	if sections[1].full then
		GroupFinderFrame:Hide();
	else
		GroupFinderFrame:Show();
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
	PanelTemplates_SetNumTabs(self, 3);
	PanelTemplates_SetTab(self, 1);
	UIPanelWindows["PVEFrame"] = { area = "left", pushable = 0, whileDead = 1, xOffset = "15", yOffset = "-10" };
	-- every stock window inside this one from the start (a battlemaster may open one before this window ever showed)
	for _, sections in ipairs(SECTIONS) do
		for _, section in ipairs(sections) do
			Embed(section.frame, section.full);
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
