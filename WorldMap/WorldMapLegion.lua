-- WorldMapLegion.lua: Legion's windowed WorldMapFrame ("Map & Quest Log": BorderFrame, NavBar,
-- the quest panel button) around the 3.3.5 windowed map. Frames in QuestAndMap.xml.
-- The full screen map stays the 3.3.5 one (with the quest panel in its quest list mode).

MAP_AND_QUEST_LOG = MAP_AND_QUEST_LOG or "Карта и задания";
AZEROTH = AZEROTH or "Азерот";

-- Legion's windowed map: 702 x 468 (1002 x 668 at 0.7)
WORLDMAP_WINDOWED_SIZE = 0.7;
if WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size == 0.573 then
	WORLDMAP_SETTINGS.size = WORLDMAP_WINDOWED_SIZE;
end

local MAP_WIDTH, MAP_HEIGHT = 702, 468;
local TOP, BOTTOM, PANEL_WIDTH = 63, 26, 330;	-- the panel: the 3.3.5 quest text is wider than Legion's

local function SetAtlasIf(texture, atlas)
	if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas);
		return true;
	end
	return false;
end

local function IsWindowed()
	return WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE;
end

---------------------------------------------------------------------------
-- the border
---------------------------------------------------------------------------
-- RetailPortraitFrameNoPortraitTemplate: the portrait off, the border without its portrait corner
function RetailPortraitFrameNoPortrait_OnLoad(self)
	if self.SetBorder then
		self:SetBorder("ButtonFrameTemplateNoPortraitMinimizable");
	end
	if self.PortraitContainer then
		self.PortraitContainer:Hide();
	end
	if self.SetTitleOffsets then
		self:SetTitleOffsets(0, 0);
	end
end

function WorldMapLegionBorder_OnLoad(self)
	RetailPortraitFrameNoPortrait_OnLoad(self);
	local title = self.TitleContainer and self.TitleContainer.TitleText or self.TitleText;
	if title then
		title:SetText(MAP_AND_QUEST_LOG);
	end
	self:EnableMouse(true);
	if self.CloseButton then
		self.CloseButton:SetScript("OnClick", function() HideUIPanel(WorldMapFrame); end);
	end

	-- maximize: the full screen map
	local maximizeMinimize = self.MaximizeMinimizeFrame;
	-- next to the close button (the XML anchor resolves before the template's button)
	if maximizeMinimize and self.CloseButton then
		maximizeMinimize:ClearAllPoints();
		maximizeMinimize:SetPoint("RIGHT", self.CloseButton, "LEFT", 2, 0);
		maximizeMinimize:SetFrameLevel(self.CloseButton:GetFrameLevel());
	end
	if maximizeMinimize and maximizeMinimize.SetOnMaximizedCallback then
		maximizeMinimize:SetOnMaximizedCallback(function()
			if IsWindowed() then
				WorldMapFrame_ToggleWindowSize();
			end
		end);
		maximizeMinimize:Minimize(true, true);
	end
end

---------------------------------------------------------------------------
-- the navigation bar (Legion WorldMapNavBar_*; 3.3.5 has continents and zones only)
---------------------------------------------------------------------------
local function ContinentName(continent)
	if continent == 0 then
		return AZEROTH;
	end
	return (select(continent, GetMapContinents()));
end

local function ZoneName(continent, zone)
	return (select(zone, GetMapZones(continent)));
end

-- a button's sibling list: continents, or the zones of its continent
local function NavSibling(self, index)
	local data = self.data;
	if data.isContinent and data.id and data.id > 0 then
		local name = select(index, GetMapContinents());
		if name then
			return name, function() SetMapZoom(index); end;
		end
	elseif data.isZone then
		local name = select(index, GetMapZones(data.continent));
		if name then
			return name, function() SetMapZoom(data.continent, index); end;
		end
	end
	return nil;
end

local function NavClick(self)
	local data = self.data;
	if data.isZone then
		SetMapZoom(data.continent, data.id);
	else
		SetMapZoom(data.id);
	end
end

function WorldMapLegionNavBar_OnLoad(self)
	local homeData = {
		name = WORLD_MAP or WORLD,
		OnClick = NavClick,
		listFunc = NavSibling,
		id = WORLDMAP_COSMIC_ID,
		isContinent = true,
	};
	NavBar_Initialize(self, "NavButtonTemplate", homeData, self.home, self.overflow);
end

function WorldMapLegionNavBar_Update()
	local navBar = WorldMapLegionNavBar;
	if not (navBar and navBar.navList) then
		return;
	end
	NavBar_Reset(navBar);
	local continent = GetCurrentMapContinent();
	local zone = GetCurrentMapZone();
	if continent and continent >= 0 then
		-- Azeroth over its continents (Outland is on its own)
		if continent ~= WORLDMAP_OUTLAND_ID then
			NavBar_AddButton(navBar, { name = AZEROTH, id = 0, isContinent = true, OnClick = NavClick, listFunc = NavSibling });
		end
		if continent > 0 then
			NavBar_AddButton(navBar, { name = ContinentName(continent), id = continent, isContinent = true, OnClick = NavClick, listFunc = NavSibling });
		end
		if zone and zone > 0 then
			NavBar_AddButton(navBar, { name = ZoneName(continent, zone), id = zone, continent = continent, isZone = true, OnClick = NavClick, listFunc = NavSibling });
		end
	end
end

---------------------------------------------------------------------------
-- layout
---------------------------------------------------------------------------
-- the stock windowed map parts the Legion window replaces
local STOCK_WINDOWED = { "WorldMapFrameMiniBorderLeft", "WorldMapFrameMiniBorderRight", "WorldMapTitleButton",
	"WorldMapFrameTitle", "WorldMapFrameSizeUpButton", "WorldMapFrameCloseButton",
	"WorldMapLevelUpButton", "WorldMapLevelDownButton", "WorldMapZoomOutButton" };

function WorldMapLegion_Layout()
	local border, panelButton = WorldMapLegionBorder, WorldMapLegionQuestPanelButton;
	if not (border and QuestMapFrame) then
		return;
	end
	QuestMapFrame_HideStockParts();

	if IsWindowed() then
		local open = QuestMapFrame.open;
		local width = MAP_WIDTH + (open and PANEL_WIDTH or 0);
		local height = TOP + MAP_HEIGHT + BOTTOM;
		WorldMapFrame:SetWidth(width);
		WorldMapFrame:SetHeight(height);
		border:SetWidth(width);
		border:SetHeight(height);
		border:SetFrameLevel(WorldMapFrame:GetFrameLevel());
		border:Show();
		for _, name in ipairs(STOCK_WINDOWED) do
			if _G[name] then
				_G[name]:Hide();
			end
		end

		-- the map in the window (anchor offsets are in the map's scale)
		local scale = WorldMapDetailFrame:GetScale();
		WorldMapDetailFrame:ClearAllPoints();
		WorldMapDetailFrame:SetPoint("TOPLEFT", border, "TOPLEFT", 1 / scale, -TOP / scale);

		WorldMapLegionNavBar:SetWidth(MAP_WIDTH - 180);
		WorldMapLevelDropDown:ClearAllPoints();
		WorldMapLevelDropDown:SetPoint("TOPRIGHT", border, "TOPLEFT", MAP_WIDTH - 50, -28);
		WorldMapQuestShowObjectives:ClearAllPoints();
		WorldMapQuestShowObjectives:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 6, 1);

		QuestMapFrame:ClearAllPoints();
		QuestMapFrame:SetPoint("TOPLEFT", border, "TOPLEFT", MAP_WIDTH + 1, -TOP);
		QuestMapFrame:SetHeight(MAP_HEIGHT);

		panelButton:ClearAllPoints();
		panelButton:SetPoint("BOTTOMRIGHT", border, "TOPLEFT", MAP_WIDTH - 2, -(TOP + MAP_HEIGHT) + 2);
		panelButton:SetFrameLevel(WorldMapDetailFrame:GetFrameLevel() + 40);
		SetAtlasIf(panelButton.Icon, open and "QuestCollapse-Hide-Up" or "QuestCollapse-Show-Up");
		panelButton:Show();

		if open then
			QuestMapFrame_Show();
		else
			QuestMapFrame_Hide();
		end
		WorldMapLegionNavBar_Update();
	else
		border:Hide();
		panelButton:Hide();
		WorldMapFrameCloseButton:Show();
		WorldMapFrameTitle:Show();
		-- our windowed anchors off: the stock ones back (else the check box stretches between both)
		WorldMapQuestShowObjectives:ClearAllPoints();
		WorldMapQuestShowObjectives_AdjustPosition();
		if WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size == WORLDMAP_QUESTLIST_SIZE then
			QuestMapFrame:ClearAllPoints();
			QuestMapFrame:SetPoint("TOPLEFT", WorldMapDetailFrame, "TOPRIGHT", 1, 0);
			QuestMapFrame:SetHeight(WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale());
			QuestMapFrame_Show();
		else
			QuestMapFrame_Hide();
		end
	end
	QuestMapFrame:SetFrameLevel(WorldMapDetailFrame:GetFrameLevel() + 30);
end

hooksecurefunc("WorldMap_ToggleSizeUp", WorldMapLegion_Layout);
hooksecurefunc("WorldMap_ToggleSizeDown", WorldMapLegion_Layout);
hooksecurefunc("WorldMapFrame_SetMiniMode", WorldMapLegion_Layout);
hooksecurefunc("WorldMapFrame_SetQuestMapView", WorldMapLegion_Layout);
hooksecurefunc("WorldMapFrame_SetFullMapView", WorldMapLegion_Layout);
hooksecurefunc("WorldMapFrame_UpdateMap", function()
	if IsWindowed() then
		WorldMapLegionNavBar_Update();
	end
end);
WorldMapFrame:HookScript("OnShow", WorldMapLegion_Layout);

---------------------------------------------------------------------------
-- one frame for the map and the quest log (Legion): L / the micro button open the map with the quests
---------------------------------------------------------------------------
function ShowQuestLog()
	if not IsWindowed() then
		SetCVar("miniWorldMap", 1);
		WorldMap_ToggleSizeDown();
	end
	QuestMapFrame.open = true;
	if not WorldMapFrame:IsShown() then
		ShowUIPanel(WorldMapFrame);
	end
	WorldMapLegion_Layout();
end

function ToggleQuestLog()
	if WorldMapFrame:IsShown() and QuestMapFrame:IsShown() then
		HideUIPanel(WorldMapFrame);
	else
		ShowQuestLog();
	end
end

-- the old quest log frame opens this one instead (the key binding and the micro button show it directly)
if QuestLogFrame then
	QuestLogFrame:HookScript("OnShow", function(self)
		HideUIPanel(self);
		ToggleQuestLog();
	end);
end

-- the objective tracker / watch frame "open the quest" goes to its details here
if QuestLog_OpenToQuest then
	QuestLog_OpenToQuest = function(questIndex)
		local questID = select(9, GetQuestLogTitle(questIndex));
		ShowQuestLog();
		if questID and questID ~= 0 then
			QuestMapFrame_ShowQuestDetails(questID);
		end
	end;
end
