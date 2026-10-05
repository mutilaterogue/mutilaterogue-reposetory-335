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
-- zoom and pan (retail map canvas): mouse wheel zooms at the cursor, a drag moves the zoomed map
---------------------------------------------------------------------------
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 1, 3, 0.25;
local zoom, panX, panY = 1, 0, 0;
local onCanvas = false;
-- the stock frames drawn over the map area: they go into the canvas while the window shows
local CANVAS_FRAMES = { "WorldMapDetailFrame", "WorldMapButton", "WorldMapPOIFrame", "WorldMapBossButtonFrame",
	"WorldMapArchaeologyDigSites" };

local function ApplyZoom()
	local canvas = WorldMapLegionCanvas;
	local maxX, maxY = MAP_WIDTH * (zoom - 1), MAP_HEIGHT * (zoom - 1);
	panX = math.max(0, math.min(panX, maxX));
	panY = math.max(0, math.min(panY, maxY));
	canvas:SetScale(zoom);
	canvas:ClearAllPoints();
	canvas:SetPoint("TOPLEFT", WorldMapLegionScrollHolder, "TOPLEFT", -panX / zoom, panY / zoom);
	if WorldMapBlobFrame_CalculateHitTranslations then
		WorldMapBlobFrame_CalculateHitTranslations();
	end
	if WorldMapFrame_SetPOIMaxBounds then
		WorldMapFrame_SetPOIMaxBounds();
	end
end

function WorldMapLegion_ResetZoom()
	zoom, panX, panY = 1, 0, 0;
	if onCanvas then
		ApplyZoom();
	end
end

-- the cursor in the view (pixels from its top left, in the view's scale)
local function CursorInView()
	local view = WorldMapLegionScrollFrame;
	local scale = view:GetEffectiveScale();
	local x, y = GetCursorPosition();
	return x / scale - view:GetLeft(), view:GetTop() - y / scale;
end

local function OnMouseWheel(self, delta)
	if not onCanvas then
		return;
	end
	local newZoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoom + delta * ZOOM_STEP));
	if newZoom == zoom then
		return;
	end
	-- the map point under the cursor stays under it
	local cx, cy = CursorInView();
	local mx, my = (cx + panX) / zoom, (cy + panY) / zoom;
	zoom = newZoom;
	panX, panY = mx * zoom - cx, my * zoom - cy;
	ApplyZoom();
end

-- a drag pans (zoomed); a drag is not a click on the map
local dragger = CreateFrame("Frame");
dragger:Hide();
dragger:SetScript("OnUpdate", function(self)
	local x, y = CursorInView();
	local dx, dy = x - self.x, y - self.y;
	if not self.moved and math.abs(dx) + math.abs(dy) > 4 then
		self.moved = true;
	end
	if self.moved then
		panX, panY = self.panX - dx, self.panY - dy;
		ApplyZoom();
	end
end);

local function OnMouseDown(self, button)
	if onCanvas and button == "LeftButton" and zoom > 1 then
		dragger.x, dragger.y = CursorInView();
		dragger.panX, dragger.panY = panX, panY;
		dragger.moved = false;
		dragger:Show();
	end
end

local function OnMouseUp(self, button)
	if dragger:IsShown() and button == "LeftButton" then
		dragger:Hide();
		WorldMapLegion.dragged = dragger.moved;
	end
end

WorldMapLegion = WorldMapLegion or {};
WorldMapButton:EnableMouseWheel(true);
WorldMapButton:SetScript("OnMouseWheel", OnMouseWheel);
WorldMapButton:HookScript("OnMouseDown", OnMouseDown);
WorldMapButton:HookScript("OnMouseUp", OnMouseUp);
local stockButtonClick = WorldMapButton_OnClick;
WorldMapButton_OnClick = function(...)
	if WorldMapLegion.dragged then
		WorldMapLegion.dragged = false;
		return;
	end
	return stockButtonClick(...);
end;

-- the stock map frames into the canvas (windowed) or back to the map frame (full screen)
local function SetOnCanvas(on)
	if on == onCanvas then
		return;
	end
	onCanvas = on;
	local parent = on and WorldMapLegionCanvas or WorldMapFrame;
	for _, name in ipairs(CANVAS_FRAMES) do
		local frame = _G[name];
		if frame and (on and frame:GetParent() == WorldMapFrame or not on and frame:GetParent() == WorldMapLegionCanvas) then
			frame:SetParent(parent);
		end
	end
	if on then
		WorldMapLegionScrollFrame:Show();
	else
		WorldMapLegionScrollFrame:Hide();
		zoom, panX, panY = 1, 0, 0;
	end
	if WorldMapFrame_ResetFrameLevels then
		WorldMapFrame_ResetFrameLevels();
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

		-- the map in the window: the canvas view where the map was, the map at the canvas' top left
		local view = WorldMapLegionScrollFrame;
		view:ClearAllPoints();
		view:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -TOP);
		view:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 1);
		SetOnCanvas(true);
		local scale = WorldMapDetailFrame:GetScale();
		WorldMapDetailFrame:ClearAllPoints();
		WorldMapDetailFrame:SetPoint("TOPLEFT", WorldMapLegionCanvas, "TOPLEFT", 0, 0);
		ApplyZoom();

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
		SetOnCanvas(false);
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
	-- the retail border over the list and the details
	if QuestMapFrame.BorderFrame then
		QuestMapFrame.BorderFrame:SetFrameLevel(QuestMapFrame:GetFrameLevel() + 20);
	end
end

hooksecurefunc("WorldMap_ToggleSizeUp", WorldMapLegion_Layout);
hooksecurefunc("WorldMap_ToggleSizeDown", WorldMapLegion_Layout);
hooksecurefunc("WorldMapFrame_SetMiniMode", WorldMapLegion_Layout);
hooksecurefunc("WorldMapFrame_SetQuestMapView", WorldMapLegion_Layout);
hooksecurefunc("WorldMapFrame_SetFullMapView", WorldMapLegion_Layout);
local lastMapID;
hooksecurefunc("WorldMapFrame_UpdateMap", function()
	if IsWindowed() then
		WorldMapLegionNavBar_Update();
		-- another map: the zoom back to the whole map
		local mapID = tostring(GetCurrentMapContinent()) .. ":" .. tostring(GetCurrentMapZone()) .. ":" .. tostring(GetCurrentMapDungeonLevel());
		if mapID ~= lastMapID then
			lastMapID = mapID;
			WorldMapLegion_ResetZoom();
		end
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
